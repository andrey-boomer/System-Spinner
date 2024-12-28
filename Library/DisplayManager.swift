//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import CoreGraphics
import MediaKeyTap
import SimplyCoreAudio

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
    
    func updateAudioControlTargetDisplays(deviceName: String) -> Int {
      self.audioControlTargetDisplays.removeAll()
      var numOfAddedDisplays = 0
      for ddcCapableDisplay in self.getDdcCapableDisplays() {
          let  displayAudioDeviceName = DisplayManager.getDisplayRawNameByID(displayID: ddcCapableDisplay.identifier)
        if self.normalizedName(displayAudioDeviceName) == self.normalizedName(deviceName) {
          self.audioControlTargetDisplays.append(ddcCapableDisplay)
          numOfAddedDisplays += 1
        }
      }
      return numOfAddedDisplays
    }
    
    func getDdcCapableDisplays() -> [OtherDisplay] {
      self.displays.compactMap { display -> OtherDisplay? in
        if let otherDisplay = display as? OtherDisplay {
          return otherDisplay
        } else { return nil }
      }
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

class MediaKeyTapManager: MediaKeyTapDelegate {
    var mediaKeyTap: MediaKeyTap?
    var keyRepeatTimers: [MediaKey: Timer] = [:]
    let simplyCA = SimplyCoreAudio()

    static func readPrivileges() -> Bool {
      let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
      let status = AXIsProcessTrustedWithOptions(options)
        if status == false {
            let alert = NSAlert()
            alert.messageText = "Keyboard not available"
            alert.informativeText = "You need enable application in System Settings > Security and Privacy > Accessibility for the keyboard shortcuts to work"
            alert.runModal()
        }
      return status
    }
    
    public func Start() {
        updateMediaKeyTap()
        mediaKeyTap?.start()
    }
    
    public func Stop() {
        updateMediaKeyTap()
        mediaKeyTap?.stop()
    }

    func handle(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) {
      let isPressed = event?.keyPressed ?? true
      let isRepeat = event?.keyRepeat ?? false
      let isControl = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.control])) ?? false
      let isCommand = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.command])) ?? false
      let isOption = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.option])) ?? false
      if isPressed, isCommand, !isControl, mediaKey == .brightnessDown, DisplayManager.engageMirror() {
        return
      }
      if isPressed, isControl, !isOption, mediaKey == .brightnessUp || mediaKey == .brightnessDown {
        self.handleDirectedBrightness(isCommandModifier: isCommand, isUp: mediaKey == .brightnessUp)
        return
      }
      let oppositeKey: MediaKey? = self.oppositeMediaKey(mediaKey: mediaKey)
      // If the opposite key to the one being held has an active timer, cancel it - we'll be going in the opposite direction
      if let oppositeKey = oppositeKey, let oppositeKeyTimer = self.keyRepeatTimers[oppositeKey], oppositeKeyTimer.isValid {
        oppositeKeyTimer.invalidate()
      } else if let mediaKeyTimer = self.keyRepeatTimers[mediaKey], mediaKeyTimer.isValid {
        // If there's already an active timer for the key being held down, let it run rather than executing it again
        if isRepeat {
          return
        }
        mediaKeyTimer.invalidate()
      }
      self.sendDisplayCommand(mediaKey: mediaKey, isRepeat: isRepeat, isPressed: isPressed)
    }

    func handleDirectedBrightness(isCommandModifier: Bool, isUp: Bool) {
      if isCommandModifier {
          for otherDisplay in DisplayManager.shared.getOtherDisplays() {
              otherDisplay.stepBrightness(isUp: isUp)
        }
          for appleDisplay in DisplayManager.shared.getAppleDisplays() where !appleDisplay.isBuiltIn() {
              appleDisplay.stepBrightness(isUp: isUp)
        }
        return
      } else if let internalDisplay = DisplayManager.shared.getBuiltInDisplay() as? AppleDisplay {
              internalDisplay.stepBrightness(isUp: isUp)
        return
      }
    }

    private func sendDisplayCommand(mediaKey: MediaKey, isRepeat: Bool, isPressed: Bool) {
        guard [.brightnessUp, .brightnessDown, .volumeUp, .volumeDown, .mute].contains(mediaKey), isPressed, let affectedDisplays = DisplayManager.shared.getAffectedDisplays() else {
            return
        }
        
        for display in affectedDisplays {
            switch mediaKey {
                case .brightnessUp:
                    display.stepBrightness(isUp: mediaKey == .brightnessUp)
                case .brightnessDown:
                    display.stepBrightness(isUp: mediaKey == .brightnessUp)
                default: continue
            }
        }
        
        for display in affectedDisplays {
          switch mediaKey {
          case .mute:
            if !isRepeat, isPressed, let display = display as? OtherDisplay {
              display.toggleMute()
            }
          case .volumeUp, .volumeDown:
            // volume only matters for other displays
            if let display = display as? OtherDisplay {
              if isPressed {
                display.stepVolume(isUp: mediaKey == .volumeUp)
              }
            }
          default: continue
          }
        }
    }

    private func oppositeMediaKey(mediaKey: MediaKey) -> MediaKey? {
      if mediaKey == .brightnessUp {
        return .brightnessDown
      } else if mediaKey == .brightnessDown {
        return .brightnessUp
      } else if mediaKey == .volumeUp {
        return .volumeDown
      } else if mediaKey == .volumeDown {
        return .volumeUp
      }
      return nil
    }

    func updateMediaKeyTap() {
        var keys: [MediaKey] = [.brightnessUp, .brightnessDown,.mute, .volumeUp, .volumeDown]

        // Remove brightness keys if no external displays are connected, but only if brightness fine control is not active
        var disengageBrightness = true
        for display in DisplayManager.shared.displays where !display.isBuiltIn() {
            disengageBrightness = false
        }

        if disengageBrightness {
            let keysToDelete: [MediaKey] = [.brightnessUp, .brightnessDown]
            keys.removeAll { keysToDelete.contains($0) }
        }
        
        // Remove volume related keys if audio device is controllable
        if let defaultAudioDevice = simplyCA.defaultOutputDevice {
            let keysToDelete: [MediaKey] = [.volumeUp, .volumeDown, .mute]
            if DisplayManager.shared.updateAudioControlTargetDisplays(deviceName: defaultAudioDevice.name) == 0 {
                    keys.removeAll { keysToDelete.contains($0) }
            } else if defaultAudioDevice.canSetVirtualMainVolume(scope: .output) == true {
                    keys.removeAll { keysToDelete.contains($0) }
            }
        }
        
        self.mediaKeyTap?.stop()
        
        // returning an empty array listens for all mediakeys in MediaKeyTap
        if keys.count > 0 {
            self.mediaKeyTap = MediaKeyTap(delegate: self, on: KeyPressMode.keyDownAndUp, for: keys, observeBuiltIn: true)
            self.mediaKeyTap?.start()
        }
    }
}
