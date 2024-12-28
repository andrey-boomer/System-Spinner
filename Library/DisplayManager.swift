//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import CoreGraphics
import MediaKeyTap

class DisplayManager {
    var displays: [Display] = []
    
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
    
    public func configureDisplays() {
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
                if  DisplayManager.isAppleDisplay(displayID: onlineDisplayID) {
                    let appleDisplay = AppleDisplay(id, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber)
                    self.displays.append(appleDisplay)
                } else {
                    let otherDisplay = OtherDisplay(id, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber)
                    self.displays.append(otherDisplay)
                }
            }
        }
    }
}


class MediaKeyTapManager: MediaKeyTapDelegate {
    var mediaKeyTap: MediaKeyTap?
    var keyRepeatTimers: [MediaKey: Timer] = [:]
    
    func handle(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) {
        print(MediaKey.self)
    }
    
    static func acquirePrivileges(firstAsk: Bool = false) {
      if !self.readPrivileges(prompt: true), !firstAsk {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Shortcuts not available", comment: "Shown in the alert dialog")
        alert.informativeText = NSLocalizedString("You need to enable MonitorControl in System Settings > Security and Privacy > Accessibility for the keyboard shortcuts to work", comment: "Shown in the alert dialog")
        alert.runModal()
      }
    }

    static func readPrivileges(prompt: Bool) -> Bool {
      let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: prompt]
      let status = AXIsProcessTrustedWithOptions(options)
      return status
    }
    
    public func Start() {
        mediaKeyTap?.start()
    }
    
    public func Stop() {
        mediaKeyTap?.stop()
    }
}
