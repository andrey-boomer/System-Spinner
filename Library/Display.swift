//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Foundation
import IOKit

enum Command: UInt8 {
    case none = 0
    case luminance = 0x10
    case audioSpeakerVolume = 0x62
    case audioMuteScreenBlank = 0x8D
    case contrast = 0x12
    public static let brightness = luminance
}

class AppleDisplay: Display {
  private var displayQueue: DispatchQueue

  override init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?) {
    self.displayQueue = DispatchQueue(label: String("displayQueue-\(identifier)"))
    super.init(identifier, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber)
  }

  public func getAppleBrightness() -> Float {
    var brightness: Float = 0
    DisplayServicesGetBrightness(self.identifier, &brightness)
    return brightness
  }

  public func setAppleBrightness(value: Float) {
    _ = self.displayQueue.sync {
      DisplayServicesSetBrightness(self.identifier, value)
    }
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
    
    override init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?) {
        super.init(identifier, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber)
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
    
    func stepVolume(isUp: Bool) {
        let currentValue = volumeValue
        let volumeOSDValue = self.calcNewValue(currentValue: currentValue, isUp: isUp)
        let isAlreadySet = volumeOSDValue == volumeValue
        
        if !isAlreadySet {
            self.writeDDCValues(command: .audioSpeakerVolume, value: UInt16(volumeOSDValue))
        }
        
        OSDUtils.showOsd(displayID: self.identifier, command: .audioSpeakerVolume, value: volumeOSDValue)

        volumeValue = volumeOSDValue
    }
    
    public func writeDDCValues(command: Command, value: UInt16) {
      self.writeDDCQueue.async(flags: .barrier) {
        self.writeDDCNextValue[command] = value
      }
      DisplayManager.shared.globalDDCQueue.async(flags: .barrier) {
        self.asyncPerformWriteDDCValues(command: command)
      }
    }
    
    func toggleMute() {
        let muteValue: Int = 2
        var volumeOSDValue: Float = volumeValue
        if volumeOSDValue == 0 {
            volumeOSDValue = 1 / OSDUtils.chicletCount
            volumeValue = volumeOSDValue
            self.writeDDCValues(command: .audioMuteScreenBlank, value: UInt16(muteValue))
        } else if volumeOSDValue > 0 {
            self.writeDDCValues(command: .audioSpeakerVolume, value: UInt16(volumeOSDValue))
        }
        OSDUtils.showOsd(displayID: self.identifier, command: volumeOSDValue > 0 ? .audioSpeakerVolume : .audioMuteScreenBlank, value: volumeOSDValue)
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
      /*var controlCodes = self.getRemapControlCodes(command: command)
      if controlCodes.count == 0 {
        controlCodes.append(command.rawValue)
      }
      for controlCode in controlCodes {
        if Arm64DDC.isArm64 {
          if self.arm64ddc {
            _ = Arm64DDC.write(service: self.arm64avService, command: controlCode, value: value)
          }
        } else {
          _ = self.ddc?.write(command: controlCode, value: value, errorRecoveryWaitTime: 2000) ?? false
        }
      }*/
    }
    
}

class OSDUtils: NSObject {
    enum OSDImage: Int64 {
        case brightness = 1
        case audioSpeaker = 3
        case audioSpeakerMuted = 4
        case contrast = 0
    }
    
    static func getOSDImageByCommand(command: Command, value: Float = 1) -> OSDImage {
        var osdImage: OSDImage
        switch command {
            case .audioSpeakerVolume: osdImage = value > 0 ? .audioSpeaker : .audioSpeakerMuted
            case .audioMuteScreenBlank: osdImage = .audioSpeakerMuted
            case .contrast: osdImage = .contrast
            default: osdImage = .brightness
        }
        return osdImage
    }

  static func showOsd(displayID: CGDirectDisplayID, command: Command, value: Float, maxValue: Float = 1, lock: Bool = false) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    let osdImage = self.getOSDImageByCommand(command: command, value: value)
    let filledChiclets: Int
    let totalChiclets: Int
    filledChiclets = Int(value * 100)
    totalChiclets = Int(maxValue * 100)
    manager.showImage(osdImage.rawValue, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000, filledChiclets: UInt32(filledChiclets), totalChiclets: UInt32(totalChiclets), locked: lock)
  }

  static func showOsdVolumeDisabled(displayID: CGDirectDisplayID) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    manager.showImage(22, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000)
  }

  static func showOsdMuteDisabled(displayID: CGDirectDisplayID) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    manager.showImage(21, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000)
  }

  static func popEmptyOsd(displayID: CGDirectDisplayID, command: Command) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    let osdImage = self.getOSDImageByCommand(command: command)
    manager.showImage(osdImage.rawValue, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 0)
  }

  static let chicletCount: Float = 16

  static func chiclet(fromValue value: Float, maxValue: Float, half: Bool = false) -> Float {
    (value * self.chicletCount * (half ? 2 : 1)) / maxValue
  }

  static func value(fromChiclet chiclet: Float, maxValue: Float, half: Bool = false) -> Float {
    (chiclet * maxValue) / (self.chicletCount * (half ? 2 : 1))
  }

  static func getDistance(fromNearestChiclet chiclet: Float) -> Float {
    abs(chiclet.rounded(.towardZero) - chiclet)
  }
}


class Display: Equatable {
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

    private func calcNewBrightness(isUp: Bool) -> Float {
        let step: Float = (isUp ? 1 : -1) / 16.0
        return min(max(0, ceil((brightnessValue) / step) * step), 1)
    }
    
    func isBuiltIn() -> Bool {
      if CGDisplayIsBuiltin(self.identifier) != 0 {
        return true
      } else {
        return false
      }
    }
    
    func stepBrightness(isUp: Bool) {
      let value = self.calcNewBrightness(isUp: isUp)
      if self.setDirectBrightness(value) {
        OSDUtils.showOsd(displayID: self.identifier, command: .brightness, value: value * 64, maxValue: 64)
      }
    }
    
    func setDirectBrightness(_ to: Float, transient: Bool = false) -> Bool {
      let value = max(min(to, 1), 0)
        if !transient {
            brightnessValue = value
        }
      return false
    }
}
