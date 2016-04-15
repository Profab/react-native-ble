#import "RNBLE.h"
#import "RCTEventDispatcher.h"
#import "RCTLog.h"
#import "RCTConvert.h"
#import "RCTCONVERT+CBUUID.h"
#import "RCTUtils.h"

@interface RNBLE () <CBCentralManagerDelegate, CBPeripheralDelegate, CBPeripheralManagerDelegate> {
    CBCentralManager *centralManager;
    CBPeripheralManager *peripheralManager;
    dispatch_queue_t centralEventQueue;
    dispatch_queue_t peripheralEventQueue;
    NSMutableDictionary *peripherals;
}
@end

@implementation RNBLE

RCT_EXPORT_MODULE()

@synthesize bridge = _bridge;

#pragma mark Initialization

- (instancetype)init
{
    if (self = [super init]) {
        
    }
    return self;
}

RCT_EXPORT_METHOD(setup)
{
    centralEventQueue = dispatch_queue_create("com.openble.mycentral", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(centralEventQueue, dispatch_get_main_queue());
    centralManager = [[CBCentralManager alloc] initWithDelegate:self queue:centralEventQueue];
    
    peripheralEventQueue = dispatch_queue_create("com.openble.myperipheral", DISPATCH_QUEUE_SERIAL);
    dispatch_set_target_queue(peripheralEventQueue, dispatch_get_main_queue());
    peripheralManager = [[CBPeripheralManager alloc] initWithDelegate:self queue:peripheralEventQueue];
    
    peripherals = [NSMutableDictionary new];
}

RCT_EXPORT_METHOD(startAdvertising:(NSDictionary *)advertisementData)
{
    NSMutableDictionary *data = [NSMutableDictionary new];
    
    if (advertisementData[@"localName"] != nil) {
        [data setObject:advertisementData[@"localName"] forKey:CBAdvertisementDataLocalNameKey];
    }
    if (advertisementData[@"serviceUuids"] != nil && [advertisementData[@"serviceUuids"] isKindOfClass:[NSArray class]]) {
        NSMutableArray *serviceUuids = [NSMutableArray new];
        for (NSString *uuid in advertisementData[@"serviceUuids"]) {
            [serviceUuids addObject:[CBUUID UUIDWithString:uuid]];
        }
        [data setObject:serviceUuids forKey:CBAdvertisementDataServiceUUIDsKey];
    }
    
    [peripheralManager startAdvertising:data];
}

RCT_EXPORT_METHOD(stopAdvertising)
{
    [peripheralManager stopAdvertising];
}

- (void)peripheralManagerDidUpdateState:(CBPeripheralManager *)peripheral
{
    // @TODO?
}

RCT_EXPORT_METHOD(startScanning:(CBUUIDArray *)uuids allowDuplicates:(BOOL)allowDuplicates)
{
    NSMutableDictionary *scanOptions = [NSMutableDictionary dictionaryWithObject:@NO
                                                          forKey:CBCentralManagerScanOptionAllowDuplicatesKey];

    if(allowDuplicates){
        [scanOptions setObject:@YES forKey:CBCentralManagerScanOptionAllowDuplicatesKey];
    }

    [centralManager scanForPeripheralsWithServices:uuids options:scanOptions];
}

RCT_EXPORT_METHOD(stopScanning)
{
    [centralManager stopScan];
}

RCT_EXPORT_METHOD(getState)
{
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.stateChange" body:[self NSStringForCBCentralManagerState:[centralManager state]]];
}

- (void)centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral
            advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    [peripherals setObject:peripheral forKey:peripheral.identifier.UUIDString];
    NSDictionary *advertisementDictionary = [self dictionaryForAdvertisementData:advertisementData fromPeripheral:peripheral];
    
    NSDictionary *event = @{
                            @"kCBMsgArgDeviceUUID": peripheral.identifier.UUIDString,
                            @"kCBMsgArgAdvertisementData": advertisementDictionary,
                            @"kCBMsgArgName": peripheral.name ? peripheral.name : @"",
                            @"kCBMsgArgRssi": RSSI
                            };

    [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.discover" body:event];
}


RCT_EXPORT_METHOD(connect:(NSString *)peripheralUuid)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    
    if (peripheral) {
        [centralManager connectPeripheral:peripheral options:nil];
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

RCT_EXPORT_METHOD(disconnect:(NSString *)peripheralUuid)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    
    if (peripheral) {
        [centralManager cancelPeripheralConnection:peripheral];
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

- (void)centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    peripheral.delegate = self;
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.connect" body:@{
                                                                               @"peripheralUuid": peripheral.identifier.UUIDString}];
}

- (void)centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSMutableDictionary *eventData = [NSMutableDictionary new];
    [eventData setObject:peripheral.identifier.UUIDString forKey:@"peripheralUuid"];
    if (error != nil) {
        [eventData setObject:RCTJSErrorFromNSError(error) forKey:@"error"];
    }
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.disconnect" body:eventData];
}

- (void)centralManager:(CBCentralManager *)central didFailToConnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.connect" body:@{
                                                                               @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                               @"error": RCTJSErrorFromNSError(error)
                                                                               }];
}

RCT_EXPORT_METHOD(updateRssi:(NSString *)peripheralUuid)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    
    if (peripheral) {
        [peripheral readRSSI];
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 80000

- (void)peripheralDidUpdateRSSI:(CBPeripheral *)peripheral error:(NSError *)error
{
    if (error == nil) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.rssiUpdate" body:@{
                                                                                      @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                                      @"rssi": peripheral.RSSI
                                                                                      }];
    }
}

#else

- (void)peripheral:(CBPeripheral *)peripheral didReadRSSI:(NSNumber *)RSSI error:(NSError *)error
{
    if (error == nil) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.rssiUpdate" body:@{
                                                                                      @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                                      @"rssi": RSSI
                                                                                      }];
    }
}

#endif

RCT_EXPORT_METHOD(discoverServices:(NSString *)peripheralUuid serviceUuids:(CBUUIDArray *)serviceUuids)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    
    if (peripheral) {
        [peripheral discoverServices:serviceUuids];
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

RCT_EXPORT_METHOD(discoverIncludedServices:(NSString *)peripheralUuid serviceUuid:(NSString *)serviceUuid serviceUuids:(CBUUIDArray *)serviceUuids)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    
    if (peripheral) {
        CBService *targetService = [self getTargetService:peripheral serviceUuid:serviceUuid];
        if (targetService) {
            [peripheral discoverIncludedServices:serviceUuids forService:targetService];
        } else {
            NSLog(@"Could not find service %@ for peripheral %@", serviceUuid, peripheralUuid);
        }
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error == nil) {
        NSMutableArray *serviceUuids = [NSMutableArray new];
        for (CBService *service in peripheral.services) {
            [serviceUuids addObject:service.UUID.UUIDString];
        }
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.servicesDiscover" body:@{
                                                                                        @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                                        @"serviceUuids": serviceUuids
                                                                                        }];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverIncludedServicesForService:(CBService *)service error:(NSError *)error
{
    if (error == nil) {
        NSMutableArray *includedServiceUuids = [NSMutableArray new];
        for (CBService *includedService in service.includedServices) {
            [includedServiceUuids addObject:includedService.UUID.UUIDString];
        }
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.includedServicesDiscover" body:@{
                                                                                            @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                                            @"serviceUuid": service.UUID.UUIDString,
                                                                                            @"includedServiceUuids": includedServiceUuids
                                                                                            }];
    }
}

RCT_EXPORT_METHOD(discoverCharacteristics:(NSString *)peripheralUuid serviceUuid:(NSString *)serviceUuid)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    if (peripheral) {
        CBService *targetService = [self getTargetService:peripheral serviceUuid:serviceUuid];
        if (targetService) {
            [peripheral discoverCharacteristics:nil forService:targetService];
        } else {
            NSLog(@"Could not find service %@ for peripheral %@", serviceUuid, peripheralUuid);
        }
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

RCT_EXPORT_METHOD(discoverDescriptors:(NSString *)peripheralUuid serviceUuid:(NSString *)serviceUuid characteristicUuid:(NSString *)characteristicUuid)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    if (peripheral) {
        CBCharacteristic *targetCharacteristic = [self getTargetCharacteristic:peripheral serviceUuid:serviceUuid characteristicUuid:characteristicUuid];
        if (targetCharacteristic) {
            [peripheral discoverDescriptorsForCharacteristic:targetCharacteristic];
        } else {
            NSLog(@"Could not find characteristic for UUID: %@", characteristicUuid);
        }
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if (error == nil) {
        NSMutableArray *characteristics = [NSMutableArray new];
        for (CBCharacteristic *characteristic in service.characteristics) {
            NSDictionary *characteristicObject = [NSMutableDictionary new];
            [characteristicObject setValue:characteristic.UUID.UUIDString forKey:@"uuid"];
            
            NSMutableArray *properties = [NSMutableArray new];
            
            if (characteristic.properties & CBCharacteristicPropertyBroadcast) {
                [properties addObject:@"broadcast"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyRead) {
                [properties addObject:@"read"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) {
                [properties addObject:@"writeWithoutResponse"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyWrite) {
                [properties addObject:@"write"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyNotify) {
                [properties addObject:@"notify"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyIndicate) {
                [properties addObject:@"indicate"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyAuthenticatedSignedWrites) {
                [properties addObject:@"authenticatedSignedWrites"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyExtendedProperties) {
                [properties addObject:@"extendedProperties"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyNotifyEncryptionRequired) {
                [properties addObject:@"notifyEncryptionRequired"];
            }
            
            if (characteristic.properties & CBCharacteristicPropertyIndicateEncryptionRequired) {
                [properties addObject:@"indicateEncryptionRequired"];
            }
            
            [characteristicObject setValue:properties forKey:@"properties"];
            [characteristics addObject:characteristicObject];
        }
        
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.characteristicsDiscover" body:@{
                                                                                        @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                                        @"serviceUuid": service.UUID.UUIDString,
                                                                                        @"characteristics": characteristics
                                                                                        }];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didDiscoverDescriptorsForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error == nil) {
        NSMutableArray *descriptors = [NSMutableArray new];
        for (CBDescriptor *descriptor in characteristic.descriptors) {
            [descriptors addObject:descriptor.UUID.UUIDString];
        }
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.descriptorsDiscover" body:@{
                                                                                                   @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                                                   @"serviceUuid": characteristic.service.UUID.UUIDString,
                                                                                                   @"characteristicUuid": characteristic.UUID.UUIDString,
                                                                                                   @"descriptors": descriptors
                                                                                                   }];
    }
}

RCT_EXPORT_METHOD(read:(NSString *)peripheralUuid serviceUuid:(NSString *)serviceUuid characteristicUuid:(NSString *)characteristicUuid)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    if (peripheral) {
        CBCharacteristic *targetCharacteristic = [self getTargetCharacteristic:peripheral serviceUuid:serviceUuid characteristicUuid:characteristicUuid];
        if (targetCharacteristic) {
            [peripheral readValueForCharacteristic:targetCharacteristic];
        } else {
            NSLog(@"Could not find characteristic for UUID: %@", characteristicUuid);
        }
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

RCT_EXPORT_METHOD(write:(NSString *)peripheralUuid serviceUuid:(NSString *)serviceUuid characteristicUuid:(NSString *)characteristicUuid data:(NSDictionary *)data withoutResponse:(BOOL)withoutResponse)
{
    NSData *writeValue;
    NSString *dataType = [data objectForKey:@"type"];
    
    // @TODO: add more data types
    if ([dataType isEqualToString:@"uint8"]) {
        uint8_t num = [[data objectForKey:@"value"] intValue];
        writeValue = [NSData dataWithBytes:(void *)&num length:sizeof(num)];
    } else {
        // Throw an error?
    }
    
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    if (peripheral) {
        CBCharacteristic *targetCharacteristic = [self getTargetCharacteristic:peripheral serviceUuid:serviceUuid characteristicUuid:characteristicUuid];
        if (targetCharacteristic) {
            [peripheral writeValue:writeValue forCharacteristic:targetCharacteristic type:withoutResponse ? CBCharacteristicWriteWithoutResponse : CBCharacteristicWriteWithResponse];
        } else {
            NSLog(@"Could not find characteristic for UUID: %@", characteristicUuid);
        }
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

RCT_EXPORT_METHOD(notify:(NSString *)peripheralUuid serviceUuid:(NSString *)serviceUuid characteristicUuid:(NSString *)characteristicUuid notify:(BOOL)notify)
{
    CBPeripheral *peripheral = peripherals[peripheralUuid];
    if (peripheral) {
        CBCharacteristic *targetCharacteristic = [self getTargetCharacteristic:peripheral serviceUuid:serviceUuid characteristicUuid:characteristicUuid];
        if (targetCharacteristic) {
            [peripheral setNotifyValue:notify forCharacteristic:targetCharacteristic];
        } else {
            NSLog(@"Could not find characteristic for UUID: %@", characteristicUuid);
        }
    } else {
        NSLog(@"Could not find peripheral for UUID: %@", peripheralUuid);
    }
}

- (CBCharacteristic *)getTargetCharacteristic:(CBPeripheral *)peripheral serviceUuid:(NSString *)serviceUuid characteristicUuid:(NSString *)characteristicUuid
{
    CBCharacteristic *targetCharacteristic;
    CBService *targetService = [self getTargetService:peripheral serviceUuid:serviceUuid];
    if (targetService) {
        for (CBCharacteristic *characteristic in targetService.characteristics) {
            if ([characteristic.UUID.UUIDString isEqualToString:characteristicUuid]) {
                targetCharacteristic = characteristic;
                break;
            }
        }
    }
    return targetCharacteristic;
}

- (CBService *)getTargetService:(CBPeripheral *)peripheral serviceUuid:(NSString *)serviceUuid
{
    CBService *targetService;
    for (CBService *service in peripheral.services) {
        if ([service.UUID.UUIDString isEqualToString:serviceUuid]) {
            targetService = service;
            break;
        }
    }
    return targetService;
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateNotificationStateForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error == nil) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.notify" body:@{
                                                                              @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                              @"serviceUuid": characteristic.service.UUID.UUIDString,
                                                                              @"characteristicUuid": characteristic.UUID.UUIDString,
                                                                              @"state": @(characteristic.isNotifying)
                                                                              }];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error == nil) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.data" body:@{
                                                                            @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                            @"serviceUuid": characteristic.service.UUID.UUIDString,
                                                                            @"characteristicUuid": characteristic.UUID.UUIDString,
                                                                            @"data": [characteristic.value base64EncodedStringWithOptions:0],
                                                                            @"isNotification": @(characteristic.isNotifying)
                                                                            }];
    }
}

- (void)peripheral:(CBPeripheral *)peripheral didWriteValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error == nil) {
        [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.write" body:@{
                                                                             @"peripheralUuid": peripheral.identifier.UUIDString,
                                                                             @"serviceUuid": characteristic.service.UUID.UUIDString,
                                                                             @"characteristicUuid": characteristic.UUID.UUIDString
                                                                             }];
    }
}

- (NSDictionary *)dictionaryForPeripheral:(CBPeripheral *)peripheral
{
    return @{
        @"identifier": peripheral.identifier.UUIDString,
        @"name" : peripheral.name ? peripheral.name : @"",
        @"state" : [self nameForCBPeripheralState:peripheral.state]
    };
}

- (NSDictionary *)dictionaryForAdvertisementData:(NSDictionary *)advertisementData fromPeripheral:(CBPeripheral *)peripheral
{
    NSString *localNameString = [advertisementData objectForKey:@"kCBAdvDataLocalName"];
    localNameString = localNameString ? localNameString : @"";

    NSData *manufacturerData = [advertisementData objectForKey:@"kCBAdvDataManufacturerData"];
    NSString *manufacturerDataString = [manufacturerData base64EncodedStringWithOptions:0];
    manufacturerDataString = manufacturerDataString ? manufacturerDataString : @"";

    NSDictionary *serviceDataDictionary = [advertisementData objectForKey:@"kCBAdvDataServiceData"];
    NSMutableDictionary *stringServiceDataDictionary = [NSMutableDictionary new];
    
    for (CBUUID *cbuuid in serviceDataDictionary)
    {
        NSString *uuidString = cbuuid.UUIDString;
        NSData *serviceData =  [serviceDataDictionary objectForKey:cbuuid];
        NSString *serviceDataString = [serviceData base64EncodedStringWithOptions:0];
        [stringServiceDataDictionary setObject:serviceDataString forKey:uuidString];
    }

    NSMutableArray *serviceUUIDsStringArray = [NSMutableArray new];
    for (CBUUID *cbuuid in [advertisementData objectForKey:@"kCBAdvDataServiceUUIDs"])
    {
        [serviceUUIDsStringArray addObject:cbuuid.UUIDString];
    }
    
    NSDictionary *advertisementDataDictionary = @{ @"identifier" : @"",
                            @"kCBAdvDataIsConnectable" : [advertisementData objectForKey:@"kCBAdvDataIsConnectable"],
                            @"kCBAdvDataLocalName" : localNameString,
                            @"kCBAdvDataManufacturerData" : manufacturerDataString,
                            @"kCBAdvDataServiceData" : stringServiceDataDictionary,
                            @"kCBAdvDataServiceUUIDs" : serviceUUIDsStringArray,
                            @"kCBAdvDataTxPowerLevel" : [advertisementData objectForKey:@"kCBAdvDataTxPowerLevel"] ? [advertisementData objectForKey:@"kCBAdvDataTxPowerLevel"] : @""
                            };
    
    return advertisementDataDictionary;
}


- (void)centralManagerDidUpdateState:(CBCentralManager *)central
{
    [self.bridge.eventDispatcher sendDeviceEventWithName:@"ble.stateChange" body:[self NSStringForCBCentralManagerState:[central state]]];
}

- (NSString *)NSStringForCBCentralManagerState:(CBCentralManagerState)state{
    NSString *stateString = [NSString new];
    
    switch (state) {
        case CBCentralManagerStateResetting:
            stateString = @"resetting";
            break;
        case CBCentralManagerStateUnsupported:
            stateString = @"unsupported";
            break;
        case CBCentralManagerStateUnauthorized:
            stateString = @"unauthorized";
            break;
        case CBCentralManagerStatePoweredOff:
            stateString = @"poweredOff";
            break;
        case CBCentralManagerStatePoweredOn:
            stateString = @"poweredOn";
            break;
        case CBCentralManagerStateUnknown:
        default:
            stateString = @"unknown";
    }
    return stateString;
}

- (NSString *)nameForCBPeripheralState:(CBPeripheralState)state{
    switch (state) {
        case CBPeripheralStateDisconnected:
            return @"CBPeripheralStateDisconnected";

        case CBPeripheralStateConnecting:
            return @"CBPeripheralStateConnecting";

        case CBPeripheralStateConnected:
            return @"CBPeripheralStateConnected";
            
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
        case CBPeripheralStateDisconnecting:
            return @"CBPeripheralStateDisconnecting";
#endif
    }
}

- (NSString *)nameForCBCentralManagerState:(CBCentralManagerState)state{
    switch (state) {
        case CBCentralManagerStateUnknown:
            return @"CBCentralManagerStateUnknown";

        case CBCentralManagerStateResetting:
            return @"CBCentralManagerStateResetting";

        case CBCentralManagerStateUnsupported:
            return @"CBCentralManagerStateUnsupported";

        case CBCentralManagerStateUnauthorized:
            return @"CBCentralManagerStateUnauthorized";

        case CBCentralManagerStatePoweredOff:
            return @"CBCentralManagerStatePoweredOff";

        case CBCentralManagerStatePoweredOn:
            return @"CBCentralManagerStatePoweredOn";
    }
}

@end
