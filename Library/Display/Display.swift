//  Copyright © MonitorControl. JoniVR, theOneyouseek, waydabber, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa
import IOKit

@MainActor
class Display: Equatable {
    public let identifier: CGDirectDisplayID
    public var name: String
    public var resolution: CGSize
    public var savedVolume: Float = 0

    nonisolated public static func == (lhs: Display, rhs: Display) -> Bool {
        lhs.identifier == rhs.identifier
    }

    init(_ identifier: CGDirectDisplayID, name: String) {
        self.identifier = identifier
        self.name = name
        self.resolution = Display.pixelResolution(of: identifier)
    }

    public static func pixelResolution(of identifier: CGDirectDisplayID) -> CGSize {
        var size: CGSize

        if let mode = CGDisplayCopyDisplayMode(identifier) {
            size = CGSize(width: mode.pixelWidth, height: mode.pixelHeight)
        } else {
            size = CGSize(width: CGDisplayPixelsWide(identifier), height: CGDisplayPixelsHigh(identifier))
        }

        if abs(CGDisplayRotation(identifier).truncatingRemainder(dividingBy: 180)) > 45 {
            size = CGSize(width: size.height, height: size.width)
        }

        return size
    }

    @discardableResult
    public func refreshResolution() -> CGSize {
        resolution = Display.pixelResolution(of: identifier)
        return resolution
    }

    public func isBuiltIn() -> Bool {
        CGDisplayIsBuiltin(identifier) != 0
    }

    public func isHDR() -> Bool {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == identifier }) else { return false }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0
    }

    public func hasVolumeControl() -> Bool {
        name == AudioOutput.name(of: AudioOutput.defaultDeviceID)
    }

    public func saveCurrentBrightness(valueBrightness: Float) {
        Preferences.shared.setBrightness(valueBrightness, forDisplay: name)
    }

    public func saveCurrentVolume(valueVolume: Float) {
        Preferences.shared.setVolume(valueVolume, forDisplay: name)
    }

    public func getCurrentBrightness() -> Float {
        Preferences.shared.brightness(forDisplay: name) ?? 100
    }

    public func getCurrentVolume() -> Float {
        let deviceID = AudioOutput.defaultDeviceID

        if name != AudioOutput.name(of: deviceID) {
            return AudioOutput.volume(of: deviceID) * 100
        }
        return Preferences.shared.volume(forDisplay: name) ?? 0
    }

    public func setBrightness(valueBrightness: Float) {
        saveCurrentBrightness(valueBrightness: valueBrightness)
    }

    public func setVolume(valueVolume: Float) {
        AudioOutput.setVolume(valueVolume / 100, for: AudioOutput.defaultDeviceID)
        saveCurrentVolume(valueVolume: valueVolume)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }
}

@MainActor
final class AppleDisplay: Display {
    private let displayQueue: DispatchQueue

    override init(_ identifier: CGDirectDisplayID, name: String) {
        displayQueue = DispatchQueue(label: "displayQueue-\(identifier)")
        super.init(identifier, name: name)
    }

    override func getCurrentBrightness() -> Float {
        var brightness: Float = 0
        DisplayServicesGetBrightness(identifier, &brightness)
        return brightness * 100
    }

    override func setBrightness(valueBrightness: Float) {
        displayQueue.sync {
            _ = DisplayServicesSetBrightness(identifier, valueBrightness / 100)
        }
        saveCurrentBrightness(valueBrightness: valueBrightness)
    }
}

@MainActor
final class OtherDisplay: Display {
    enum Command: UInt8 {
        case luminance = 0x10
        case audioSpeakerVolume = 0x62

        static let brightness = luminance
    }

    var ddcService: IOAVService?

    private var lastSentValue: [Command: UInt16] = [:]

    override func setBrightness(valueBrightness: Float) {
        writeDDCValues(command: .brightness, value: UInt16(valueBrightness))
        saveCurrentBrightness(valueBrightness: valueBrightness)
    }

    override func setVolume(valueVolume: Float) {
        let deviceID = AudioOutput.defaultDeviceID

        if name == AudioOutput.name(of: deviceID) {
            writeDDCValues(command: .audioSpeakerVolume, value: UInt16(valueVolume))
        } else {
            AudioOutput.setVolume(valueVolume / 100, for: deviceID)
        }
        saveCurrentVolume(valueVolume: valueVolume)
    }

    private struct ServiceBox: @unchecked Sendable {
        let service: IOAVService?
    }

    private func writeDDCValues(command: Command, value: UInt16) {
        guard lastSentValue[command] != value else { return }
        lastSentValue[command] = value

        let box = ServiceBox(service: ddcService)
        DisplayManager.shared.globalDDCQueue.async(flags: .barrier) {
            _ = DDC.write(service: box.service, command: command.rawValue, value: value)
        }
    }
}

@MainActor
final class DisplayManager {
    public static let shared = DisplayManager()
    public let globalDDCQueue = DispatchQueue(label: "Global DDC queue")
    public var displays: [Display] = []
    var onDisplaysChanged: (([Display]) -> Void)?

    private let osd = OSDController.shared
    private let preferences = Preferences.shared
    private var pendingRefresh: DispatchWorkItem?
    private static let debounceDelay: TimeInterval = 1.0

    private init() {}

    func start() {
        CGDisplayRegisterReconfigurationCallback({ _, _, _ in
            DispatchQueue.main.async {
                DisplayManager.shared.setNeedsRefresh()
            }
        }, nil)
        setNeedsRefresh()
    }

    func setNeedsRefresh() {
        DispatchQueue.main.async { [self] in
            pendingRefresh?.cancel()

            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            pendingRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.debounceDelay, execute: work)
        }
    }

    private func refresh() {
        configureDisplays { [weak self] displays in
            self?.onDisplaysChanged?(displays)

            if AccessibilityPermission.check() {
                MediaKeyMonitor.shared.start()
                KeyboardBacklight.shared.syncBrightness()
                MouseInput.shared.setEnabled(Preferences.shared.usesSmoothScroll)
            }

            UpdateChecker.shared.check()
        }
    }

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
        if CGDisplayVendorNumber(displayID) != 1552 {
            return CGDisplayIsBuiltin(displayID) != 0
        } else {
            var brightness: Float = -1
            let ret = DisplayServicesGetBrightness(displayID, &brightness)
            if ret == 0, brightness >= 0 {
                return true
            }
        }
        return CGDisplayIsBuiltin(displayID) != 0
    }

    private func applyAVServices(_ serviceMatches: [DDC.ServiceMatch]) {
        for serviceMatch in serviceMatches {
            for otherDisplay in self.getOtherDisplays()
            where otherDisplay.identifier == serviceMatch.displayID && serviceMatch.service != nil {
                otherDisplay.ddcService = serviceMatch.service
            }
        }
    }

    private func configureDisplays(completion: (([Display]) -> Void)? = nil) {
        self.displays = []
        CGDisplayRestoreColorSyncSettings()
        var onlineDisplayIDs = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &onlineDisplayIDs, &displayCount) == .success else {
            completion?([])
            return
        }

        for onlineDisplayID in onlineDisplayIDs where onlineDisplayID != 0 {
            let name = DisplayManager.getDisplayNameByID(displayID: onlineDisplayID)
            let id = onlineDisplayID

            if !DisplayManager.isDummy(displayID: onlineDisplayID) && !DisplayManager.isVirtual(displayID: onlineDisplayID) {
                if DisplayManager.isAppleDisplay(displayID: onlineDisplayID) {
                    self.displays.append(AppleDisplay(id, name: "Apple " + name))
                } else {
                    self.displays.append(OtherDisplay(id, name: name))
                }
            }
        }

        completion?(self.displays)

        let displayIDs = self.getOtherDisplays().map { $0.identifier }
        globalDDCQueue.async {
            let matches = DDC.getServiceMatches(displayIDs: displayIDs)
            Task { @MainActor in
                DisplayManager.shared.applyAVServices(matches)
            }
        }
    }

    public func getOtherDisplays() -> [OtherDisplay] {
        self.displays.compactMap { $0 as? OtherDisplay }
    }

    public func display(withID identifier: CGDirectDisplayID) -> Display? {
        self.displays.first { $0.identifier == identifier }
    }

    public func hasBrightnessControl() -> Bool {
        displays.contains { !$0.isBuiltIn() && !$0.isHDR() }
    }

    private var handlesVolumeKeys: Bool {
        preferences.alwaysUsesCustomOSD || displays.contains { $0.hasVolumeControl() }
    }

    public func toggleMute() -> MediaKeyHandlingResult {
        guard handlesVolumeKeys else { return .passThrough }

        let deviceID = AudioOutput.defaultDeviceID
        let shouldMute = !AudioOutput.isMuted(deviceID)

        if AudioOutput.setMuted(shouldMute, for: deviceID) {
            let volumeValue = shouldMute ? 0 : (displays.first?.getCurrentVolume() ?? 0)
            osd.show(value: volumeValue, kind: .volume, separators: preferences.adjustmentSteps)
            return .consumed
        }

        for display in displays {
            var volumeValue = display.getCurrentVolume()
            if volumeValue == 0 {
                volumeValue = display.savedVolume
            } else {
                display.savedVolume = volumeValue
                volumeValue = 0
            }

            osd.show(value: Float(volumeValue), kind: .volume, separators: preferences.adjustmentSteps)
            display.setVolume(valueVolume: Float(volumeValue))
        }

        return .consumed
    }

    public func setVolume(isUp: Bool, fine: Bool = false) -> MediaKeyHandlingResult {
        guard handlesVolumeKeys else { return .passThrough }

        let steps = preferences.adjustmentSteps(fine: fine)
        let step:Float = 100 / Float(steps)

        for display in displays {
            var volumeValue = (display.getCurrentVolume()/step).rounded() * step + (isUp ? step : -step)

            if volumeValue < 0 {
                volumeValue = 0
            } else if volumeValue > 100 {
                volumeValue = 100
            }

            osd.show(value: Float(volumeValue), kind: .volume, separators: steps)
            display.setVolume(valueVolume: Float(volumeValue))
        }

        return .consumed
    }

    public func setBrightness(isUp: Bool, fine: Bool = false) -> MediaKeyHandlingResult {
        let steps = preferences.adjustmentSteps(fine: fine)
        let step:Float = 100 / Float(steps)

        if !hasBrightnessControl() && !preferences.alwaysUsesCustomOSD {
            return .passThrough
        }

        for display in displays {
               var brightnessValue = (display.getCurrentBrightness()/step).rounded() * step + (isUp ? step : -step)
            if brightnessValue < 0 {
                brightnessValue = 0
            } else if brightnessValue > 100 {
                brightnessValue = 100
            }

            osd.show(value: Float(brightnessValue), kind: .displayBrightness, separators: steps)
            display.setBrightness(valueBrightness: Float(brightnessValue))
        }
        return .consumed
    }
}

@MainActor
final class KeyboardBacklight {
    static let shared = KeyboardBacklight()

    private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
    private typealias BoolForKeyboard = @convention(c) (AnyObject, Selector, UInt64) -> Bool
    private typealias BrightnessForKeyboard = @convention(c) (AnyObject, Selector, UInt64) -> Float
    private typealias SetBrightness = @convention(c) (AnyObject, Selector, Float, UInt64) -> Bool

    private static let frameworkPath = "/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness"
    private static let copyIDsSelector = Selector(("copyKeyboardBacklightIDs"))
    private static let isBuiltInSelector = Selector(("isKeyboardBuiltIn:"))
    private static let brightnessSelector = Selector(("brightnessForKeyboard:"))
    private static let setBrightnessSelector = Selector(("setBrightness:forKeyboard:"))

    private let client: NSObject?
    private let osd = OSDController.shared
    private let preferences = Preferences.shared
    private var lastKeyboardID: UInt64?

    private init() {
        dlopen(Self.frameworkPath, RTLD_LAZY)

        guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else {
            client = nil
            return
        }

        let instance = type.init()
        let selectors = [Self.copyIDsSelector, Self.brightnessSelector, Self.setBrightnessSelector]
        client = selectors.allSatisfy { instance.responds(to: $0) } ? instance : nil
    }

    public var isAvailable: Bool {
        keyboardID != nil
    }

    public var brightness: Float {
        guard let client, let keyboardID,
              let method = client.method(for: Self.brightnessSelector)
        else {
            return 0
        }

        let read = unsafeBitCast(method, to: BrightnessForKeyboard.self)
        return read(client, Self.brightnessSelector, keyboardID) * 100
    }

    @discardableResult
    public func setBrightness(_ value: Float) -> Bool {
        guard let keyboardID, applyBrightness(value) else { return false }
        preferences.setKeyboardBacklight(value, forKeyboard: keyboardID)
        return true
    }

    public func syncBrightness() {
        let current = keyboardID
        defer { lastKeyboardID = current }

        guard let current else { return }

        guard current != lastKeyboardID else {
            let level = brightness
            if level > 0 {
                preferences.setKeyboardBacklight(level, forKeyboard: current)
            }
            return
        }

        guard preferences.usesKeyboardBacklightKeys,
              let saved = preferences.keyboardBacklight(forKeyboard: current)
        else {
            return
        }

        applyBrightness(saved)
    }

    @discardableResult
    private func applyBrightness(_ value: Float) -> Bool {
        guard let client, let keyboardID,
              let method = client.method(for: Self.setBrightnessSelector)
        else {
            return false
        }

        let write = unsafeBitCast(method, to: SetBrightness.self)
        return write(client, Self.setBrightnessSelector, value / 100, keyboardID)
    }

    public func adjust(isUp: Bool, fine: Bool = false) -> MediaKeyHandlingResult {
        guard isAvailable else { return .passThrough }

        let steps = preferences.adjustmentSteps(fine: fine)
        let step = 100 / Float(steps)
        var value = (brightness / step).rounded() * step + (isUp ? step : -step)

        if value < 0 {
            value = 0
        } else if value > 100 {
            value = 100
        }

        guard setBrightness(value) else { return .passThrough }

        osd.show(value: value, kind: .keyboardBacklight, separators: steps)
        return .consumed
    }

    private var keyboardID: UInt64? {
        guard let client, let method = client.method(for: Self.copyIDsSelector) else { return nil }

        let copyIDs = unsafeBitCast(method, to: CopyIDs.self)
        guard let identifiers = copyIDs(client, Self.copyIDsSelector)?.takeRetainedValue() as? [NSNumber],
              !identifiers.isEmpty
        else {
            return nil
        }

        let reachable = Self.isLidClosed
            ? identifiers.filter { !isBuiltIn($0.uint64Value) }
            : identifiers

        if let builtIn = reachable.first(where: { isBuiltIn($0.uint64Value) }) {
            return builtIn.uint64Value
        }

        return reachable.first?.uint64Value
    }

    private func isBuiltIn(_ identifier: UInt64) -> Bool {
        guard let client, let method = client.method(for: Self.isBuiltInSelector) else { return false }

        let check = unsafeBitCast(method, to: BoolForKeyboard.self)
        return check(client, Self.isBuiltInSelector, identifier)
    }

    private static var isLidClosed: Bool {
        let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard root != IO_OBJECT_NULL else { return false }
        defer { IOObjectRelease(root) }

        let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
        return (state?.takeRetainedValue() as? Bool) ?? false
    }
}
