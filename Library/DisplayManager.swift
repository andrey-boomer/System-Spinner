//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others
//  Adapted @Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import CoreGraphics
import Foundation

enum Command: UInt8 {
    case none = 0
    case luminance = 0x10
    case audioSpeakerVolume = 0x62
    case audioMuteScreenBlank = 0x8D
    case contrast = 0x12
    public static let brightness = luminance
}

class Display: Equatable {
    let brValue: Double = 6.25
    let identifier: CGDirectDisplayID
    let prefsId: String
    var name: String
    var vendorNumber: UInt32?
    var modelNumber: UInt32?
    var serialNumber: UInt32?
    var displays: [Display] = []
    
    static func == (lhs: Display, rhs: Display) -> Bool {
        lhs.identifier == rhs.identifier
    }
    
    init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?) {
        self.identifier = identifier
        self.name = name
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.prefsId = "(\(name.filter { !$0.isWhitespace })\(vendorNumber ?? 0)\(modelNumber ?? 0)@\(identifier))"
    }
    
    func isBuiltIn() -> Bool {
        if CGDisplayIsBuiltin(self.identifier) != 0 {
            return true
        } else {
            return false
        }
    }
    
    func setDirectBrightness(valueBrightness: Float) {
        // for override
    }
    
    func setDirectVolume(valueVolume: Float) {
        // for override
    }
    
    
    func toggleMute() {
        let savedVolume = Double(UserDefaults.standard.string(forKey: "group.volumeValue") ?? String(volumeValue))!
        if volumeValue == 0 {
            volumeValue = savedVolume
        } else {
            volumeValue = 0
        }
        setDirectVolume(valueVolume: Float(volumeValue))
    }
    
    func stepVolume(isUp: Bool) {
        volumeValue = volumeValue + (isUp ? brValue : -brValue)
        if volumeValue < 0 {
            volumeValue = 0
        } else if volumeValue > 100 {
            volumeValue = 100
        } else if (volumeValue == 0 || (isUp && volumeValue == brValue)) {
            volumeValue = brValue / 2
        } else if (volumeValue > brValue && (isUp && volumeValue < brValue * 2)) {
            volumeValue = brValue
        }
        setDirectVolume(valueVolume: Float(volumeValue))
        UserDefaults.standard.set(volumeValue, forKey: "group.volumeValue")
    }
    
    func setBrightness(to: Display, isUp: Bool) {
        let brvValue: Double = brValue / Double(DisplayManager.shared.displays.count)
        brightnessValue = brightnessValue + (isUp ? brvValue : -brvValue)
        if brightnessValue < 0 {
            brightnessValue = 0
        } else if brightnessValue > 100 {
            brightnessValue = 100
        }
        setDirectBrightness(valueBrightness: Float(brightnessValue))
        UserDefaults.standard.set(brightnessValue, forKey: "group.brightnessValue")
    }
}
    
class DisplayManager {
        public static let shared = DisplayManager()
        var displays: [Display] = []
        var audioControlTargetDisplays: [OtherDisplay] = []
        let globalDDCQueue = DispatchQueue(label: "Global DDC queue")
        
        static func getDisplayNameByID(displayID: CGDirectDisplayID) -> String {
            if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], var name = nameList[Locale.current.identifier] ?? nameList["en_US"] ?? nameList.first?.value {
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
        
        static func getDisplayRawNameByID(displayID: CGDirectDisplayID) -> String {
            if let dictionary = (CoreDisplay_DisplayCreateInfoDictionary(displayID)?.takeRetainedValue() as NSDictionary?), let nameList = dictionary["DisplayProductName"] as? [String: String], let name = nameList["en_US"] ?? nameList.first?.value {
                return name
            }
            return ""
        }
        
        static func isDummy(displayID: CGDirectDisplayID) -> Bool {
            let vendorNumber = CGDisplayVendorNumber(displayID)
            let rawName = getDisplayRawNameByID(displayID: displayID)
            if rawName.lowercased().contains("dummy") || (self.isVirtual(displayID: displayID) && vendorNumber == UInt32(0xF0F0)) {
                return true
            }
            return false
        }
        
        static func isVirtual(displayID: CGDirectDisplayID) -> Bool {
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
        
        static func isAppleDisplay(displayID: CGDirectDisplayID) -> Bool {
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
        
        func updateArm64AVServices() {
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
        
        func configureDisplays() {
            self.displays = []
            var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
            var displayCount: UInt32 = 0
            guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success else {
                return
            }
            
            for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 {
                let name = DisplayManager.getDisplayNameByID(displayID: onlineDisplayID)
                let id = onlineDisplayID
                let vendorNumber = CGDisplayVendorNumber(onlineDisplayID)
                let modelNumber = CGDisplayModelNumber(onlineDisplayID)
                let serialNumber = CGDisplaySerialNumber(onlineDisplayID)
                
                if !DisplayManager.isDummy(displayID: onlineDisplayID) && !DisplayManager.isVirtual(displayID: onlineDisplayID) {
                    if DisplayManager.isAppleDisplay(displayID: onlineDisplayID) {
                        let appleDisplay = AppleDisplay(id, name: "Apple " + name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber)
                        self.displays.append(appleDisplay)
                    } else {
                        let otherDisplay = OtherDisplay(id, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber)
                        self.displays.append(otherDisplay)
                    }
                }
            }
        }
        
        func getOtherDisplays() -> [OtherDisplay] {
            self.displays.compactMap { $0 as? OtherDisplay }
        }
        
        func getAppleDisplays() -> [AppleDisplay] {
            self.displays.compactMap { $0 as? AppleDisplay }
        }
        
        func getBuiltInDisplay() -> Display? {
            self.displays.first { CGDisplayIsBuiltin($0.identifier) != 0 }
        }
        
        func getAffectedDisplays() -> [Display]? {
            return self.displays
        }
    func normalizedName(_ name: String) -> String {
      var normalizedName = name.replacingOccurrences(of: "(", with: "")
      normalizedName = normalizedName.replacingOccurrences(of: ")", with: "")
      normalizedName = normalizedName.replacingOccurrences(of: " ", with: "")
      for i in 0 ... 9 {
        normalizedName = normalizedName.replacingOccurrences(of: String(i), with: "")
      }
      return normalizedName
    }
    
    func getDdcCapableDisplays() -> [OtherDisplay] {
      self.displays.compactMap { display -> OtherDisplay? in
        if let otherDisplay = display as? OtherDisplay {
          return otherDisplay
        } else { return nil }
      }
    }
    
    func updateAudioControlTargetDisplays(deviceName: String) -> Int {
      self.audioControlTargetDisplays.removeAll()
      var numOfAddedDisplays = 0
      var displayAudioDeviceName = ""
      for ddcCapableDisplay in self.getDdcCapableDisplays() {
          displayAudioDeviceName = DisplayManager.getDisplayRawNameByID(displayID: ddcCapableDisplay.identifier)
          if self.normalizedName(displayAudioDeviceName) == self.normalizedName(deviceName) {
              self.audioControlTargetDisplays.append(ddcCapableDisplay)
              numOfAddedDisplays += 1
          }
      }
      return numOfAddedDisplays
    }
    
    static func engageMirror() -> Bool {
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
