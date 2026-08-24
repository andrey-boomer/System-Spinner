//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import IOKit.hid

// What is plugged in to point with. Only the vendor is of interest: Apple's own
// trackpads and mice scroll by the pixel and are smooth already, so the
// smoothing below is worth offering only when something else is attached.
enum PointingDevices {
    // Apple answers with two different ids depending on how it is attached:
    // its USB vendor id over the wire, and its Bluetooth SIG company id over
    // the air. A Magic Mouse reports the second one and would otherwise pass
    // for somebody else's.
    private static let appleVendorIDs = [0x05AC, 0x004C]

    // Asked for on the spot rather than watched: the answer is needed when the
    // menu opens and at no other time, and a device that comes and goes leaves
    // nothing to keep in sync.
    static var hasThirdPartyMouse: Bool {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        // A wheel mouse describes itself as either of these; which one depends
        // on the device, so both are asked for.
        let matching = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }

        return devices.contains { device in
            // The built-in trackpad reports no vendor id at all, so it is ruled
            // out by being built in; a Magic Mouse is ruled out by the vendor.
            // Anything else attached is taken to be a wheel, unknown id or not.
            if isBuiltIn(device) { return false }
            guard let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int else {
                return true
            }
            return !appleVendorIDs.contains(vendor)
        }
    }

    private static func isBuiltIn(_ device: IOHIDDevice) -> Bool {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) else { return false }
        return (value as? Bool) ?? false
    }
}
