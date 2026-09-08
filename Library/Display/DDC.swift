//  Copyright © MonitorControl. JoniVR, theOneyouseek, waydabber, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import IOKit

class DDC: NSObject {
    static let MAX_MATCH_SCORE: Int = 20
    static let ARM64_DDC_7BIT_ADDRESS: UInt8 = 0x37
    static let ARM64_DDC_DATA_ADDRESS: UInt8 = 0x51

    struct IORegService: @unchecked Sendable {
        var edidUUID: String = ""
        var productName: String = ""
        var serialNumber: Int64 = 0
        var ioDisplayLocation: String = ""
        var service: IOAVService?
        var serviceLocation: Int = 0
    }

    struct ServiceMatch: @unchecked Sendable {
        var displayID: CGDirectDisplayID = 0
        var service: IOAVService?
        var serviceLocation: Int = 0
    }

    static func getServiceMatches(displayIDs: [CGDirectDisplayID]) -> [ServiceMatch] {
        let ioregServicesForMatching = self.getIoregServicesForMatching()
        var matchedDisplayServices: [ServiceMatch] = []
        var scoredCandidateDisplayServices: [Int: [ServiceMatch]] = [:]
        for displayID in displayIDs {
            for ioregServiceForMatching in ioregServicesForMatching {
                let score = self.ioregMatchScore(displayID: displayID, ioregEdidUUID: ioregServiceForMatching.edidUUID, ioDisplayLocation: ioregServiceForMatching.ioDisplayLocation, ioregProductName: ioregServiceForMatching.productName, ioregSerialNumber: ioregServiceForMatching.serialNumber, serviceLocation: ioregServiceForMatching.serviceLocation)
                let displayService = ServiceMatch(displayID: displayID, service: ioregServiceForMatching.service, serviceLocation: ioregServiceForMatching.serviceLocation)
                if scoredCandidateDisplayServices[score] == nil {
                    scoredCandidateDisplayServices[score] = []
                }
                scoredCandidateDisplayServices[score]?.append(displayService)
            }
        }
        var takenServiceLocations: [Int] = []
        var takenDisplayIDs: [CGDirectDisplayID] = []
        for score in stride(from: self.MAX_MATCH_SCORE, to: 0, by: -1) {
            if let scoredCandidateDisplayService = scoredCandidateDisplayServices[score] {
                for candidateDisplayService in scoredCandidateDisplayService where !(takenDisplayIDs.contains(candidateDisplayService.displayID) || takenServiceLocations.contains(candidateDisplayService.serviceLocation)) {
                    takenDisplayIDs.append(candidateDisplayService.displayID)
                    takenServiceLocations.append(candidateDisplayService.serviceLocation)
                    matchedDisplayServices.append(candidateDisplayService)
                }
            }
        }
        return matchedDisplayServices
    }

    private static let writeSleepTime: UInt32 = 10000
    private static let numOfWriteCycles = 2
    private static let numOfRetryAttempts = 4
    private static let retrySleepTime: UInt32 = 20000

    static func write(service: IOAVService?, command: UInt8, value: UInt16) -> Bool {
        var send: [UInt8] = [command, UInt8(value >> 8), UInt8(value & 255)]
        return Self.performDDCCommunication(service: service, send: &send)
    }

    static func performDDCCommunication(service: IOAVService?, send: inout [UInt8]) -> Bool {
        let dataAddress = ARM64_DDC_DATA_ADDRESS
        var success = false
        guard service != nil else {
            return success
        }
        var packet: [UInt8] = [UInt8(0x80 | (send.count + 1)), UInt8(send.count)] + send + [0]
        packet[packet.count - 1] = self.checksum(chk: send.count == 1 ? ARM64_DDC_7BIT_ADDRESS << 1 : ARM64_DDC_7BIT_ADDRESS << 1 ^ dataAddress, data: &packet, start: 0, end: packet.count - 2)
        for _ in 1 ... Self.numOfRetryAttempts + 1 {
            for _ in 1 ... Self.numOfWriteCycles {
                usleep(Self.writeSleepTime)
                success = IOAVServiceWriteI2C(service, UInt32(ARM64_DDC_7BIT_ADDRESS), UInt32(dataAddress), &packet, UInt32(packet.count)) == 0
            }
            if success {
                return success
            }
            usleep(Self.retrySleepTime)
        }
        return success
    }

    static func checksum(chk: UInt8, data: inout [UInt8], start: Int, end: Int) -> UInt8 {
        var chkd: UInt8 = chk
        for i in start ... end {
            chkd ^= data[i]
        }
        return chkd
    }

    static func ioregMatchScore(displayID: CGDirectDisplayID, ioregEdidUUID: String, ioDisplayLocation: String = "", ioregProductName: String = "", ioregSerialNumber: Int64 = 0, serviceLocation _: Int = 0) -> Int {
        var matchScore = 0
        if let dictionary = CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary? {
            if let kDisplayYearOfManufacture = dictionary[kDisplayYearOfManufacture] as? Int64, let kDisplayWeekOfManufacture = dictionary[kDisplayWeekOfManufacture] as? Int64, let kDisplayVendorID = dictionary[kDisplayVendorID] as? Int64, let kDisplayProductID = dictionary[kDisplayProductID] as? Int64, let kDisplayVerticalImageSize = dictionary[kDisplayVerticalImageSize] as? Int64, let kDisplayHorizontalImageSize = dictionary[kDisplayHorizontalImageSize] as? Int64 {
                struct KeyLoc {
                    var key: String
                    var loc: Int
                }
                let edidUUIDSearchKeys: [KeyLoc] = [

                    KeyLoc(key: String(format: "%04x", UInt16(max(0, min(kDisplayVendorID, 256 * 256 - 1)))).uppercased(), loc: 0),

                    KeyLoc(key: String(format: "%02x", UInt8((UInt16(max(0, min(kDisplayProductID, 256 * 256 - 1))) >> (0 * 8)) & 0xFF)).uppercased()
                           + String(format: "%02x", UInt8((UInt16(max(0, min(kDisplayProductID, 256 * 256 - 1))) >> (1 * 8)) & 0xFF)).uppercased(), loc: 4),

                    KeyLoc(key: String(format: "%02x", UInt8(max(0, min(kDisplayWeekOfManufacture, 256 - 1)))).uppercased()
                           + String(format: "%02x", UInt8(max(0, min(kDisplayYearOfManufacture - 1990, 256 - 1)))).uppercased(), loc: 19),

                    KeyLoc(key: String(format: "%02x", UInt8(max(0, min(kDisplayHorizontalImageSize / 10, 256 - 1)))).uppercased()
                           + String(format: "%02x", UInt8(max(0, min(kDisplayVerticalImageSize / 10, 256 - 1)))).uppercased(), loc: 30),
                ]
                for searchKey in edidUUIDSearchKeys where searchKey.key != "0000" && searchKey.key == ioregEdidUUID.prefix(searchKey.loc + 4).suffix(4) {
                    matchScore += 1
                }
            }
            if ioDisplayLocation != "", let kIODisplayLocation = dictionary[kIODisplayLocationKey] as? String, ioDisplayLocation == kIODisplayLocation {
                matchScore += 10
            }
            if ioregProductName != "", let nameList = dictionary["DisplayProductName"] as? [String: String], let name = nameList["en_US"] ?? nameList.first?.value, name.lowercased() == ioregProductName.lowercased() {
                matchScore += 1
            }
            if ioregSerialNumber != 0, let serial = dictionary[kDisplaySerialNumber] as? Int64, serial == ioregSerialNumber {
                matchScore += 1
            }
        }
        return matchScore
    }

    static func ioregIterateToNextObjectOfInterest(interests: [String], iterator: inout io_iterator_t) -> (name: String, entry: io_service_t)? {
        let name = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_name_t>.size)
        defer {
            name.deallocate()
        }
        while true {
            let entry = IOIteratorNext(iterator)
            guard entry != IO_OBJECT_NULL else {
                return nil
            }
            guard IORegistryEntryGetName(entry, name) == KERN_SUCCESS else {
                IOObjectRelease(entry)
                return nil
            }
            let nameString = String(cString: name)
            if interests.contains(where: { nameString.contains($0) }) {
                return (nameString, entry)
            }
            IOObjectRelease(entry)
        }
    }

    static func getIORegServiceAppleCDC2Properties(entry: io_service_t) -> IORegService {
        var ioregService = IORegService()
        if let unmanagedEdidUUID = IORegistryEntryCreateCFProperty(entry, "EDID UUID" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)), let edidUUID = unmanagedEdidUUID.takeRetainedValue() as? String {
            ioregService.edidUUID = edidUUID
        }
        let cpath = UnsafeMutablePointer<CChar>.allocate(capacity: MemoryLayout<io_string_t>.size)
        defer {
            cpath.deallocate()
        }
        IORegistryEntryGetPath(entry, kIOServicePlane, cpath)
        ioregService.ioDisplayLocation = String(cString: cpath)
        if let unmanagedDisplayAttrs = IORegistryEntryCreateCFProperty(entry, "DisplayAttributes" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)), let displayAttrs = unmanagedDisplayAttrs.takeRetainedValue() as? NSDictionary {
            if let productAttrs = displayAttrs.value(forKey: "ProductAttributes") as? NSDictionary {
                if let productName = productAttrs.value(forKey: "ProductName") as? String {
                    ioregService.productName = productName
                }
                if let serialNumber = productAttrs.value(forKey: "SerialNumber") as? Int64 {
                    ioregService.serialNumber = serialNumber
                }
            }
        }
        return ioregService
    }

    static func setIORegServiceDCPAVServiceProxy(entry: io_service_t, ioregService: inout IORegService) {
        if let unmanagedLocation = IORegistryEntryCreateCFProperty(entry, "Location" as CFString, kCFAllocatorDefault, IOOptionBits(kIORegistryIterateRecursively)), let location = unmanagedLocation.takeRetainedValue() as? String {
            if location == "External" {
                ioregService.service = IOAVServiceCreateWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() as IOAVService
            }
        }
    }

    static func getIoregServicesForMatching() -> [IORegService] {
        var serviceLocation = 0
        var ioregServicesForMatching: [IORegService] = []
        let ioregRoot: io_registry_entry_t = IORegistryGetRootEntry(kIOMainPortDefault)
        defer {
            IOObjectRelease(ioregRoot)
        }
        var iterator = io_iterator_t()
        defer {
            IOObjectRelease(iterator)
        }
        var ioregService = IORegService()
        guard IORegistryEntryCreateIterator(ioregRoot, "IOService", IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS else {
            return ioregServicesForMatching
        }
        let keyDCPAVServiceProxy = "DCPAVServiceProxy"
        let keysFramebuffer = ["AppleCLCD2", "IOMobileFramebufferShim"]
        while true {
            guard let objectOfInterest = ioregIterateToNextObjectOfInterest(interests: [keyDCPAVServiceProxy] + keysFramebuffer, iterator: &iterator) else {
                break
            }
            defer {
                IOObjectRelease(objectOfInterest.entry)
            }
            if keysFramebuffer.contains(objectOfInterest.name) {
                ioregService = self.getIORegServiceAppleCDC2Properties(entry: objectOfInterest.entry)
                serviceLocation += 1
                ioregService.serviceLocation = serviceLocation
            } else if objectOfInterest.name == keyDCPAVServiceProxy {
                self.setIORegServiceDCPAVServiceProxy(entry: objectOfInterest.entry, ioregService: &ioregService)
                ioregServicesForMatching.append(ioregService)
            }
        }
        return ioregServicesForMatching
    }

}
