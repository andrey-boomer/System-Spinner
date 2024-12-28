//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Foundation
import IOKit

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
     
    override init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?) {
        super.init(identifier, name: name, vendorNumber: vendorNumber, modelNumber: modelNumber, serialNumber: serialNumber)
        if !Arm64DDC.isArm64 {
            self.ddc = IntelDDC(for: identifier)
        }
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
    var brightnessSyncSourceValue: Float = 1

    init(_ identifier: CGDirectDisplayID, name: String, vendorNumber: UInt32?, modelNumber: UInt32?, serialNumber: UInt32?) {
        self.identifier = identifier
        self.name = name
        self.vendorNumber = vendorNumber
        self.modelNumber = modelNumber
        self.serialNumber = serialNumber
        self.prefsId = "(\(name.filter { !$0.isWhitespace })\(vendorNumber ?? 0)\(modelNumber ?? 0)@\(identifier))"
        self.brightnessSyncSourceValue = self.getBrightness()
    }

    private func calcNewBrightness(isUp: Bool, isSmallIncrement: Bool) -> Float {
        var step: Float = (isUp ? 1 : -1) / 16.0
        let delta = step / 4
        if isSmallIncrement {
          step = delta
        }
        return min(max(0, ceil((self.getBrightness() + delta) / step) * step), 1)
    }

    private func getBrightness() -> Float {
    // need load яркость return self.readPrefAsFloat(for: .brightness)
      return 1
    }
}
