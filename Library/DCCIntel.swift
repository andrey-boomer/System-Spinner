//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others, Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import IOKit.i2c

public class IntelDDC {
    let displayId: CGDirectDisplayID
    let framebuffer: io_service_t
    let replyTransactionType: IOOptionBits
    var enabled: Bool = false
    
    deinit {
        assert(IOObjectRelease(self.framebuffer) == KERN_SUCCESS)
    }
    
    public init?(for displayId: CGDirectDisplayID, withReplyTransactionType replyTransactionType: IOOptionBits? = nil) {
        self.displayId = displayId
        guard let framebuffer = IntelDDC.ioFramebufferPortFromDisplayId(displayId: displayId) else {
            return nil
        }
        self.framebuffer = framebuffer
        if let replyTransactionType = replyTransactionType {
            self.replyTransactionType = replyTransactionType
        } else if let replyTransactionType = IntelDDC.supportedTransactionType() {
            self.replyTransactionType = replyTransactionType
        } else {
            return nil
        }
    }
    
    public func write(command: UInt8, value: UInt16, errorRecoveryWaitTime: UInt32? = nil, writeSleepTime: UInt32 = 10000, numofWriteCycles: UInt8 = 2) -> Bool {
        var success = false
        var data: [UInt8] = Array(repeating: 0, count: 7)
        
        data[0] = 0x51
        data[1] = 0x84
        data[2] = 0x03
        data[3] = command
        data[4] = UInt8(value >> 8)
        data[5] = UInt8(value & 255)
        data[6] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4] ^ data[5]
        
        for _ in 1 ... numofWriteCycles {
            usleep(writeSleepTime)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBuffer = withUnsafePointer(to: &data[0]) { vm_address_t(bitPattern: $0) }
            request.sendBytes = UInt32(data.count)
            request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)
            request.replyBytes = 0
            if IntelDDC.send(request: &request, to: self.framebuffer, errorRecoveryWaitTime: errorRecoveryWaitTime) {
                success = true
            }
        }
        return success
    }
    
    public func read(command: UInt8, tries: UInt = 1, replyTransactionType _: IOOptionBits? = nil, minReplyDelay: UInt64? = nil, errorRecoveryWaitTime: UInt32? = nil, writeSleepTime: UInt32 = 10000) -> (UInt16, UInt16)? {
        var data: [UInt8] = Array(repeating: 0, count: 5)
        var replyData: [UInt8] = Array(repeating: 0, count: 11)
        
        data[0] = 0x51
        data[1] = 0x82
        data[2] = 0x01
        data[3] = command
        data[4] = 0x6E ^ data[0] ^ data[1] ^ data[2] ^ data[3]
        
        for _ in 1 ... tries {
            usleep(writeSleepTime)
            usleep(errorRecoveryWaitTime ?? 0)
            var request = IOI2CRequest()
            request.commFlags = 0
            request.sendAddress = 0x6E
            request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
            request.sendBuffer = withUnsafePointer(to: &data[0]) { vm_address_t(bitPattern: $0) }
            request.sendBytes = UInt32(data.count)
            request.minReplyDelay = minReplyDelay ?? 10
            request.replyAddress = 0x6F
            request.replySubAddress = 0x51
            request.replyTransactionType = self.replyTransactionType
            request.replyBytes = UInt32(replyData.count)
            request.replyBuffer = withUnsafePointer(to: &replyData[0]) { vm_address_t(bitPattern: $0) }
            
            if IntelDDC.send(request: &request, to: self.framebuffer, errorRecoveryWaitTime: errorRecoveryWaitTime) {
                if replyData.count > 0 {
                    let checksum = replyData.last!
                    var calculated = UInt8(0x50)
                    for i in 0 ..< (replyData.count - 1) {
                        calculated ^= replyData[i]
                    }
                    guard checksum == calculated else {
                        continue
                    }
                }
                guard replyData[2] == 0x02 else {
                    continue
                }
                guard replyData[3] == 0x00 else {
                    return nil
                }
                let (mh, ml, sh, sl) = (replyData[6], replyData[7], replyData[8], replyData[9])
                let maxValue = UInt16(mh << 8) + UInt16(ml)
                let currentValue = UInt16(sh << 8) + UInt16(sl)
                return (currentValue, maxValue)
            }
        }
        return nil
    }
    
    private static func supportedTransactionType() -> IOOptionBits? {
        var ioIterator = io_iterator_t()
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceNameMatching("IOFramebufferI2CInterface"), &ioIterator) == KERN_SUCCESS else {
            return nil
        }
        defer {
            assert(IOObjectRelease(ioIterator) == KERN_SUCCESS)
        }
        while case let ioService = IOIteratorNext(ioIterator), ioService != 0 {
            var serviceProperties: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(ioService, &serviceProperties, kCFAllocatorDefault, IOOptionBits()) == KERN_SUCCESS, serviceProperties != nil else {
                continue
            }
            let dict = serviceProperties!.takeRetainedValue() as NSDictionary
            if let types = dict[kIOI2CTransactionTypesKey] as? UInt64 {
                if (1 << kIOI2CDDCciReplyTransactionType) & types != 0 {
                    return IOOptionBits(kIOI2CDDCciReplyTransactionType)
                }
                if (1 << kIOI2CSimpleTransactionType) & types != 0 {
                    return IOOptionBits(kIOI2CSimpleTransactionType)
                }
            }
        }
        return nil
    }
    
    static func send(request: inout IOI2CRequest, to framebuffer: io_service_t, errorRecoveryWaitTime: UInt32? = nil) -> Bool {
        if let errorRecoveryWaitTime = errorRecoveryWaitTime {
            usleep(errorRecoveryWaitTime)
        }
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(framebuffer, &busCount) == KERN_SUCCESS else {
            return false
        }
        for bus: IOOptionBits in 0 ..< busCount {
            var interface = io_service_t()
            guard IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) == KERN_SUCCESS else {
                continue
            }
            var connect: IOI2CConnectRef?
            guard IOI2CInterfaceOpen(interface, IOOptionBits(), &connect) == KERN_SUCCESS else {
                continue
            }
            defer { IOI2CInterfaceClose(connect, IOOptionBits()) }
            guard IOI2CSendRequest(connect, IOOptionBits(), &request) == KERN_SUCCESS else {
                continue
            }
            guard request.result == KERN_SUCCESS else {
                continue
            }
            return true
        }
        return false
    }
    
    static func servicePortUsingDisplayPropertiesMatching(from displayId: CGDirectDisplayID) -> io_object_t? {
        var portIterator = io_iterator_t()
        let status: kern_return_t = IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(IOFRAMEBUFFER_CONFORMSTO), &portIterator)
        guard status == KERN_SUCCESS else {
            return nil
        }
        defer {
            assert(IOObjectRelease(portIterator) == KERN_SUCCESS)
        }
        while case let port = IOIteratorNext(portIterator), port != 0 {
            let dict = IODisplayCreateInfoDictionary(port, IOOptionBits(kIODisplayOnlyPreferredName)).takeRetainedValue() as NSDictionary
            let valueForKey = { (k: String) in
                (dict[k] as? CFIndex).flatMap { Int32(exactly: $0) }.flatMap { UInt32(bitPattern: $0) } ?? 0
            }
            let portVendorId = valueForKey(kDisplayVendorID)
            let displayVendorId = CGDisplayVendorNumber(displayId)
            guard portVendorId == displayVendorId else {
                continue
            }
            let portProductId = valueForKey(kDisplayProductID)
            let displayProductId = CGDisplayModelNumber(displayId)
            guard portProductId == displayProductId else {
                continue
            }
            let portSerialNumber = valueForKey(kDisplaySerialNumber)
            let displaySerialNumber = CGDisplaySerialNumber(displayId)
            guard portSerialNumber == displaySerialNumber else {
                continue
            }
            if let displayLocation = dict[kIODisplayLocationKey] as? NSString {
                // the unit number is the number right after the last "@" sign in the display location
                // swiftlint:disable:next force_try
                let regex = try! NSRegularExpression(pattern: "@([0-9]+)[^@]+$", options: [])
                if let match = regex.firstMatch(in: displayLocation as String, options: [], range: NSRange(location: 0, length: displayLocation.length)) {
                    let unitNumber = UInt32(displayLocation.substring(with: match.range(at: 1)))
                    guard unitNumber == CGDisplayUnitNumber(displayId) else {
                        continue
                    }
                }
            }
            return port
        }
        return nil
    }
    
    static func ioFramebufferPortFromDisplayId(displayId: CGDirectDisplayID) -> io_service_t? {
        if CGDisplayIsBuiltin(displayId) == boolean_t(truncating: true) {
            return nil
        }
        var servicePortUsingCGSServiceForDisplayNumber: io_service_t = 0
        CGSServiceForDisplayNumber(displayId, &servicePortUsingCGSServiceForDisplayNumber)
        if servicePortUsingCGSServiceForDisplayNumber != 0 {
            return servicePortUsingCGSServiceForDisplayNumber
        }
        guard let servicePort = self.servicePortUsingDisplayPropertiesMatching(from: displayId) else {
            return nil
        }
        var busCount: IOItemCount = 0
        guard IOFBGetI2CInterfaceCount(servicePort, &busCount) == KERN_SUCCESS, busCount >= 1 else {
            return nil
        }
        return servicePort
    }
}

class OtherDisplay: Display {
    var ddc: IntelDDC?
    var arm64ddc: Bool = false
    var arm64avService: IOAVService?
    var isDiscouraged: Bool = false
    let writeDDCQueue = DispatchQueue(label: "Local write DDC queue")
    var writeDDCNextValue: [Command: UInt16] = [:]
    var writeDDCLastSavedValue: [Command: UInt16] = [:]
    
    override init(_ identifier: CGDirectDisplayID, name: String, modelNumber: UInt32?, pixelHeight: CGFloat?, pixelWidth: CGFloat?)  {
        super.init(identifier, name: name, modelNumber: modelNumber, pixelHeight: pixelHeight, pixelWidth: pixelWidth)
        if !Arm64DDC.isArm64 {
            self.ddc = IntelDDC(for: identifier)
        }
    }
    
    func calcNewValue(currentValue: Float, isUp: Bool, half: Bool = false) -> Float {
        let nextValue: Float
        let osdChicletFromValue = OSDUtils.chiclet(fromValue: currentValue, maxValue: 1, half: half)
        let distance = OSDUtils.getDistance(fromNearestChiclet: osdChicletFromValue)
        var nextFilledChiclet = isUp ? ceil(osdChicletFromValue) : floor(osdChicletFromValue)
        let distanceThreshold: Float = 0.25 // 25% of the distance between the edges of an osd box
        if distance == 0 {
            nextFilledChiclet += (isUp ? 1 : -1)
        } else if !isUp, distance < distanceThreshold {
            nextFilledChiclet -= 1
        } else if isUp, distance > (1 - distanceThreshold) {
            nextFilledChiclet += 1
        }
        nextValue = OSDUtils.value(fromChiclet: nextFilledChiclet, maxValue: 1, half: half)
        return max(0, min(1, nextValue))
    }
    
    public func writeDDCValues(command: Command, value: UInt16) {
        self.writeDDCQueue.async(flags: .barrier) {
            self.writeDDCNextValue[command] = value
        }
        DisplayManager.shared.globalDDCQueue.async(flags: .barrier) {
            self.asyncPerformWriteDDCValues(command: command)
        }
    }
    
    override func setDirectBrightness(valueBrightness: Float) {
        self.writeDDCValues(command: .brightness, value: UInt16(valueBrightness))
        OSDUtils.showOsd(displayID: self.identifier, command: .brightness, value: valueBrightness, maxValue: Float(100))
    }
    
    override func setDirectVolume(valueVolume: Float) {
        self.writeDDCValues(command: .audioSpeakerVolume, value: UInt16(valueVolume))
        OSDUtils.showOsd(displayID: self.identifier, command: .audioSpeakerVolume, value: Float(valueVolume), maxValue: Float(100))
    }
    
    func asyncPerformWriteDDCValues(command: Command) {
        var value = UInt16.max
        var lastValue = UInt16.max
        self.writeDDCQueue.sync {
            value = self.writeDDCNextValue[command] ?? UInt16.max
            lastValue = self.writeDDCLastSavedValue[command] ?? UInt16.max
        }
        guard value != UInt16.max, value != lastValue else {
            return
        }
        self.writeDDCQueue.async(flags: .barrier) {
            self.writeDDCLastSavedValue[command] = value
        }
        if Arm64DDC.isArm64 {
            if self.arm64ddc {
                _ = Arm64DDC.write(service: self.arm64avService, command: command.rawValue, value: value)
            }
        } else {
            _ = self.ddc?.write(command: command.rawValue, value: value, errorRecoveryWaitTime: 2000) ?? false
        }
    }
}
