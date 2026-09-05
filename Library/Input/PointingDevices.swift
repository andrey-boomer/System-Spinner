//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import IOKit.hid

enum PointingDevices {
    private static let appleVendorIDs = [0x05AC, 0x004C]
    private static let logitechVendorID = 0x046D

    static var hasThirdPartyMouse: Bool {
        mice.contains { device in
            if isBuiltIn(device) { return false }
            guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int else {
                return true
            }
            return !appleVendorIDs.contains(vendor)
        }
    }

    static var hasLogitechMouse: Bool {
        mice.contains { device in
            guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int else {
                return false
            }
            return vendor == logitechVendorID
        }
    }

    private static var mice: Set<IOHIDDevice> {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        return IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    }

    private static func isBuiltIn(_ device: IOHIDDevice) -> Bool {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) else { return false }
        return (value as? Bool) ?? false
    }
}
