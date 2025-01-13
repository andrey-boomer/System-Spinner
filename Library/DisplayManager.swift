//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others, Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation
import OSLog

enum Command: UInt8 {
    case none = 0
    case luminance = 0x10
    case audioSpeakerVolume = 0x62
    case audioMuteScreenBlank = 0x8D
    case contrast = 0x12
    public static let brightness = luminance
}

class Display: Equatable {
    public let identifier: CGDirectDisplayID
    public var name: String
    public var modelNumber: UInt32?
    public var pixelHeight: CGFloat?
    public var pixelWidth: CGFloat?
    public var displays: [Display] = []
    
    public static func == (lhs: Display, rhs: Display) -> Bool {
        lhs.identifier == rhs.identifier
    }
    
    init(_ identifier: CGDirectDisplayID, name: String, modelNumber: UInt32?, pixelHeight: CGFloat?, pixelWidth: CGFloat?) {
        self.identifier = identifier
        self.name = name
        self.modelNumber = modelNumber
        self.pixelHeight = pixelHeight
        self.pixelWidth = pixelWidth
    }
    
    public func isBuiltIn() -> Bool {
        if CGDisplayIsBuiltin(self.identifier) != 0 {
            return true
        } else {
            return false
        }
    }
    
    public func setDirectBrightness(valueBrightness: Float) {
        os_log("Set direct brightness: \(valueBrightness)")
    }
    
    public func setDirectVolume(valueVolume: Float) {
        os_log("Set direct volume: \(valueVolume)")
    }
}

class DisplayManager {
    public static let shared = DisplayManager()
    public var displays: [Display] = []
    public let globalDDCQueue = DispatchQueue(label: "Global DDC queue")
    private var audioControlTargetDisplays: [OtherDisplay] = []
    private let correctionValue: Double = 6.25
    
    static func getDisplayNameByID(displayID: CGDirectDisplayID) -> String {
        if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], var name = nameList[Locale.current.identifier] ?? nameList["en_US"] ?? nameList.first?.value {
            print(dictionary)
            if CGDisplayIsInHWMirrorSet(displayID) != 0 || CGDisplayIsInMirrorSet(displayID) != 0 {
                let mirroredDisplayID = CGDisplayMirrorsDisplay(displayID)
                if mirroredDisplayID != 0, let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(mirroredDisplayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], let mirroredName = nameList[Locale.current.identifier] ?? nameList["en_US"] ?? nameList.first?.value {
                    name.append(" | " + mirroredName)
                }
            }
            return name
        }
        return "Unknown"
    }
    
    private static func getDisplayRawNameByID(displayID: CGDirectDisplayID) -> String {
        if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], let name = nameList["en_US"] ?? nameList.first?.value {
            return name
        }
        return ""
    }
    
    private static func isDummy(displayID: CGDirectDisplayID) -> Bool {
        let vendorNumber = CGDisplayVendorNumber(displayID)
        let rawName = getDisplayRawNameByID(displayID: displayID)
        if rawName.lowercased().contains("dummy") || (self.isVirtual(displayID: displayID) && vendorNumber == UInt32(0xF0F0)) {
            return true
        }
        return false
    }
    
    private static func isVirtual(displayID: CGDirectDisplayID) -> Bool {
        var isVirtual = false
        if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?) {
            let isVirtualDevice = dictionary["kCGDisplayIsVirtualDevice"] as? Bool
            let displayIsAirplay = dictionary["kCGDisplayIsAirPlay"] as? Bool
            if isVirtualDevice ?? displayIsAirplay ?? false {
                isVirtual = true
            }
        }
        return isVirtual
    }
    
    private static func isAppleDisplay(displayID: CGDirectDisplayID) -> Bool {
        if #available(macOS 15.0, *) {
            if CGDisplayVendorNumber(displayID) != 1552, CGSIsHDRSupported(displayID), CGSIsHDREnabled(displayID) {
                return CGDisplayIsBuiltin(displayID) != 0
            }
        }
        var brightness: Float = -1
        let ret = DisplayServicesGetBrightness(displayID, &brightness)
        if ret == 0, brightness >= 0 { // If brightness read appears to be successful using DisplayServices then it should be an Apple display
            return true
        }
        return CGDisplayIsBuiltin(displayID) != 0 // If built-in display, it should be Apple
    }
    
    private func updateArm64AVServices() {
        if Arm64DDC.isArm64 {
            var displayIDs: [CGDirectDisplayID] = []
            for otherDisplay in self.getOtherDisplays() {
                displayIDs.append(otherDisplay.identifier)
            }
            for serviceMatch in Arm64DDC.getServiceMatches(displayIDs: displayIDs) {
                for otherDisplay in self.getOtherDisplays() where otherDisplay.identifier == serviceMatch.displayID && serviceMatch.service != nil {
                    otherDisplay.arm64avService = serviceMatch.service
                    if serviceMatch.discouraged {
                        otherDisplay.isDiscouraged = true
                    } else if serviceMatch.dummy {
                        otherDisplay.isDiscouraged = true
                    } else {
                        otherDisplay.arm64ddc = true
                    }
                }
            }
        }
    }
    
    public func configureDisplays() {
        self.displays = []
        CGDisplayRestoreColorSyncSettings()
        var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success else {
            return
        }
        
        for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 {
            let name = DisplayManager.getDisplayNameByID(displayID: onlineDisplayID)
            let id = onlineDisplayID
            let modelNumber = CGDisplayModelNumber(onlineDisplayID)
            let pixelHeight = CGDisplayScreenSize(onlineDisplayID).height
            let pixelWidth = CGDisplayScreenSize(onlineDisplayID).width
            
            if !DisplayManager.isDummy(displayID: onlineDisplayID) && !DisplayManager.isVirtual(displayID: onlineDisplayID) {
                if DisplayManager.isAppleDisplay(displayID: onlineDisplayID) {
                    let appleDisplay = AppleDisplay(id, name: "Apple " + name, modelNumber: modelNumber, pixelHeight: pixelHeight, pixelWidth: pixelWidth)
                    self.displays.append(appleDisplay)
                } else {
                    let otherDisplay = OtherDisplay(id, name: name, modelNumber: modelNumber, pixelHeight: pixelHeight, pixelWidth: pixelWidth)
                    self.displays.append(otherDisplay)
                }
            }
        }
        updateArm64AVServices()
    }
    
    public func getOtherDisplays() -> [OtherDisplay] {
        self.displays.compactMap { $0 as? OtherDisplay }
    }
    
    private func normalizedName(_ name: String) -> String {
        var normalizedName = name.replacingOccurrences(of: "(", with: "")
        normalizedName = normalizedName.replacingOccurrences(of: ")", with: "")
        normalizedName = normalizedName.replacingOccurrences(of: " ", with: "")
        for i in 0 ... 9 {
            normalizedName = normalizedName.replacingOccurrences(of: String(i), with: "")
        }
        return normalizedName
    }
    
    public func isAppleDisplayPresent() -> Bool {
        for display in DisplayManager.shared.displays where display.isBuiltIn() {
            return true
        }
        return false
    }
    
    public func hasBrightnessControll() -> Bool {
        var disengageBrightness = true
        
        for display in DisplayManager.shared.displays where !display.isBuiltIn() {
            disengageBrightness = false
        }
        if disengageBrightness {
            return false
        } else {
            return true
        }
    }
    
    public func toggleMute() {
        let savedVolume = Double(UserDefaults.standard.string(forKey: "group.volumeValue") ?? String(volumeValue))!
        if volumeValue == 0 {
            volumeValue = savedVolume
        } else {
            volumeValue = 0
        }
        
        for display in displays {
            display.setDirectVolume(valueVolume: Float(volumeValue))
        }
        
    }
    
    public func setVolume(isUp: Bool) {
        volumeValue = volumeValue + (isUp ? correctionValue : -correctionValue)
        if volumeValue < 0 {
            volumeValue = 0
        } else if volumeValue > 100 {
            volumeValue = 100
        } else if (volumeValue == 0 || (isUp && volumeValue == correctionValue)) {
            volumeValue = correctionValue / 2
        } else if (volumeValue > correctionValue && (isUp && volumeValue < correctionValue * 2)) {
            volumeValue = correctionValue
        }
        
        for display in displays {
            display.setDirectVolume(valueVolume: Float(volumeValue))
        }
        
        UserDefaults.standard.set(volumeValue, forKey: "group.volumeValue")
    }
    
    public func setBrightness(isUp: Bool) {
        brightnessValue = brightnessValue + (isUp ? correctionValue : -correctionValue)
        if brightnessValue < 0 {
            brightnessValue = 0
        } else if brightnessValue > 100 {
            brightnessValue = 100
        }
        
        for display in displays {
            display.setDirectBrightness(valueBrightness: Float(brightnessValue))
        }
        
        UserDefaults.standard.set(brightnessValue, forKey: "group.brightnessValue")
    }
    
    private func getDdcCapableDisplays() -> [OtherDisplay] {
        self.displays.compactMap { display -> OtherDisplay? in
            if let otherDisplay = display as? OtherDisplay {
                return otherDisplay
            } else { return nil }
        }
    }
    
    public static func engageMirror() -> Bool {
        var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success, displayCount > 1 else {
            return false
        }
        // Break display mirror if there is any
        var mirrorBreak = false
        var displayConfigRef: CGDisplayConfigRef?
        for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 {
            if CGDisplayIsInHWMirrorSet(onlineDisplayID) != 0 || CGDisplayIsInMirrorSet(onlineDisplayID) != 0 {
                if mirrorBreak == false {
                    CGBeginDisplayConfiguration(&displayConfigRef)
                }
                CGConfigureDisplayMirrorOfDisplay(displayConfigRef, onlineDisplayID, kCGNullDirectDisplay)
                mirrorBreak = true
            }
        }
        if mirrorBreak {
            CGCompleteDisplayConfiguration(displayConfigRef, CGConfigureOption.permanently)
            return true
        }
        // Build display mirror
        var mainDisplayId = kCGNullDirectDisplay
        for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 {
            if CGDisplayIsBuiltin(onlineDisplayID) == 0, mainDisplayId == kCGNullDirectDisplay {
                mainDisplayId = onlineDisplayID
            }
        }
        guard mainDisplayId != kCGNullDirectDisplay else {
            return false
        }
        CGBeginDisplayConfiguration(&displayConfigRef)
        for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 && onlineDisplayID != mainDisplayId {
            CGConfigureDisplayMirrorOfDisplay(displayConfigRef, onlineDisplayID, mainDisplayId)
        }
        CGCompleteDisplayConfiguration(displayConfigRef, CGConfigureOption.permanently)
        return true
    }
}
