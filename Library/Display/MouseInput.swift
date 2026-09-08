//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0
//  Smoothing approach from https://github.com/Caldis/Mos

import AppKit
import ApplicationServices
import IOKit.hid
import QuartzCore

@MainActor
final class MouseInput {
    private static let appleVendorIDs = [0x05AC, 0x004C]
    private static let logitechVendorID = 0x046D

    private nonisolated static func getAllMice() -> Set<IOHIDDevice> {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        let matching = [
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
            [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

        return IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []
    }

    private nonisolated static func isBuiltIn(_ device: IOHIDDevice) -> Bool {
        guard let value = IOHIDDeviceGetProperty(device, kIOHIDBuiltInKey as CFString) else { return false }
        return (value as? Bool) ?? false
    }

    private nonisolated static func getVendorID(_ device: IOHIDDevice) -> Int? {
        return IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int
    }

    private nonisolated static func hasMouseWithVendor(_ vendorID: Int) -> Bool {
        getAllMice().contains { device in
            guard let vendor = getVendorID(device) else { return false }
            return vendor == vendorID
        }
    }

    static var hasThirdPartyMouse: Bool {
        getAllMice().contains { device in
            if isBuiltIn(device) { return false }
            guard let vendor = getVendorID(device) else { return true }
            return !appleVendorIDs.contains(vendor)
        }
    }

    static var hasLogitechMouse: Bool {
        hasMouseWithVendor(logitechVendorID)
    }

    static let shared = MouseInput()
    private static let pixelsPerLine: Double = 16
    private static let linesPerNotch: Double = 4
    nonisolated private static let decayPerFrame: Double = 0.12
    nonisolated private static let easeInPerFrame: Double = 0.23
    nonisolated private static let restThreshold: Double = 0.5
    private static let marker: Int64 = 0x5350_4E52
    private static let phaseBegan: Int64 = 1
    private static let phaseChanged: Int64 = 2
    private static let phaseEnded: Int64 = 4
    private static let momentumBegan: Int64 = 1
    private static let momentumOngoing: Int64 = 2
    private static let momentumEnded: Int64 = 3
    private static let inputHoldOff: CFTimeInterval = 0.18

    nonisolated static func step(remaining: Double, frameDuration: Double) -> Double {
        guard abs(remaining) > restThreshold else { return remaining }
        return remaining * Self.share(decayPerFrame, frameDuration: frameDuration)
    }

    nonisolated static func advance(remaining: Double,
                                    emitted: Double,
                                    frameDuration: Double) -> (post: Double, remaining: Double) {
        guard abs(remaining) > restThreshold else { return (remaining, 0) }
        let want = Self.step(remaining: remaining, frameDuration: frameDuration)
        let next = emitted + Self.share(easeInPerFrame, frameDuration: frameDuration) * (want - emitted)
        let capped = abs(next) > abs(remaining) ? remaining : next
        return (capped, remaining - capped)
    }

    nonisolated static func share(_ perFrame: Double, frameDuration: Double) -> Double {
        1 - pow(1 - perFrame, max(frameDuration, 1.0 / 240) * 60)
    }

    nonisolated static let rearButton: Int64 = 3
    nonisolated static let frontButton: Int64 = 4
    nonisolated static let leftArrowKeyCode: CGKeyCode = 123
    nonisolated static let rightArrowKeyCode: CGKeyCode = 124
    private static let controlKeyCode: CGKeyCode = 59
    private static let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
    private static let chordHold: Duration = .milliseconds(80)
    private static let reservedFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    private static let scrollReservedFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate]
    private static let deviceCheckLifetime: CFTimeInterval = 2

    private struct ResultBox: @unchecked Sendable {
        let value: Unmanaged<CGEvent>?
    }

    private struct EventBox: @unchecked Sendable {
        let event: CGEvent
        let refcon: UnsafeMutableRawPointer
    }

    private enum Stage { case idle, began, tracking, coastBegan, coasting }

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var displayLink: CADisplayLink?
    private var template: CGEvent?
    private var targetPID: pid_t = 0
    private var pending = (x: 0.0, y: 0.0)
    private var emitted = (x: 0.0, y: 0.0)
    private var lastDelta = (x: 0.0, y: 0.0)
    private var stage: Stage = .idle
    private var lastInput: CFTimeInterval = 0
    private var hasLogitechCache: (time: CFTimeInterval, value: Bool)?

    private init() {}

    var isRunning: Bool { eventTap != nil }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        let mask = CGEventMask(
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)
        )

        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapSource = source
        return true
    }

    func stop() {
        self.stopGlide()

        let source = eventTapSource
        let tap = eventTap
        eventTap = nil
        eventTapSource = nil
        hasLogitechCache = nil

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled && Self.hasThirdPartyMouse {
            self.start()
        } else {
            self.stop()
        }
    }

    private func hasLogitechMouse() -> Bool {
        let now = CACurrentMediaTime()
        if let cache = hasLogitechCache, now - cache.time < Self.deviceCheckLifetime {
            return cache.value
        }
        let value = Self.hasLogitechMouse
        hasLogitechCache = (time: now, value: value)
        return value
    }

    private func enableEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let box = EventBox(event: event, refcon: refcon)

        let result = MainActor.assumeIsolated { () -> ResultBox in
            let input = Unmanaged<MouseInput>.fromOpaque(box.refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                input.enableEventTap()
                return ResultBox(value: Unmanaged.passUnretained(box.event))
            }

            return ResultBox(value: input.handle(box.event, type: type))
        }

        return result.value
    }

    private func handle(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        switch type {
        case .otherMouseDown, .otherMouseUp:

            guard hasLogitechMouse() else {
                return Unmanaged.passUnretained(event)
            }
            guard !self.handleButtons(event, type: type) else { return nil }
            return Unmanaged.passUnretained(event)

        case .scrollWheel:
            return self.handleScroll(event)

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleScroll(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }

        if !event.flags.intersection(Self.scrollReservedFlags).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let travel = Self.pixelsPerLine * Self.linesPerNotch
        let deltaY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * travel
        let deltaX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * travel
        guard deltaY != 0 || deltaX != 0 else {
            return Unmanaged.passUnretained(event)
        }

        if deltaY != 0 {
            pending.y = deltaY * lastDelta.y > 0 ? pending.y + deltaY : deltaY
            lastDelta.y = deltaY
        }
        if deltaX != 0 {
            pending.x = deltaX * lastDelta.x > 0 ? pending.x + deltaX : deltaX
            lastDelta.x = deltaX
        }

        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard pid != 0, let copy = event.copy(), self.startGlide() else {
            pending = (0, 0)
            return Unmanaged.passUnretained(event)
        }

        template = copy
        targetPID = pid
        lastInput = CACurrentMediaTime()
        if stage != .began, stage != .tracking {
            stage = .began
        }

        return nil
    }

    private func startGlide() -> Bool {
        if displayLink != nil { return true }
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return false
        }

        let link = screen.displayLink(target: self, selector: #selector(glide(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
        return true
    }

    private func stopGlide() {
        displayLink?.invalidate()
        displayLink = nil
        template = nil
        targetPID = 0
        pending = (0, 0)
        emitted = (0, 0)
        lastDelta = (0, 0)
        stage = .idle
        lastInput = 0
    }

    @objc private func glide(_ link: CADisplayLink) {
        if stage == .tracking, CACurrentMediaTime() - lastInput > Self.inputHoldOff {
            self.post(dx: 0, dy: 0, scroll: Self.phaseEnded, momentum: 0)
            stage = .coastBegan
            return
        }

        let frame = link.targetTimestamp - link.timestamp
        let y = Self.advance(remaining: pending.y, emitted: emitted.y, frameDuration: frame)
        let x = Self.advance(remaining: pending.x, emitted: emitted.x, frameDuration: frame)
        emitted = (x: x.post, y: y.post)
        pending = (x: x.remaining, y: y.remaining)

        switch stage {
        case .began:
            self.post(dx: emitted.x, dy: emitted.y, scroll: Self.phaseBegan, momentum: 0)
            stage = .tracking
        case .tracking:
            self.post(dx: emitted.x, dy: emitted.y, scroll: Self.phaseChanged, momentum: 0)
        case .coastBegan:
            self.post(dx: emitted.x, dy: emitted.y, scroll: 0, momentum: Self.momentumBegan)
            stage = .coasting
        case .coasting, .idle:
            self.post(dx: emitted.x, dy: emitted.y, scroll: 0, momentum: Self.momentumOngoing)
        }

        if pending.x == 0, pending.y == 0 {
            if stage == .began || stage == .tracking {
                self.post(dx: 0, dy: 0, scroll: Self.phaseEnded, momentum: 0)
            } else {
                self.post(dx: 0, dy: 0, scroll: 0, momentum: Self.momentumEnded)
            }
            self.stopGlide()
        }
    }

    private func post(dx: Double, dy: Double, scroll: Int64, momentum: Int64) {
        guard let event = template?.copy() else { return }
        event.setIntegerValueField(.eventSourceUserData, value: Self.marker)
        event.setDoubleValueField(.scrollWheelEventScrollPhase, value: Double(scroll))
        event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: Double(momentum))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)
        event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1)
        event.postToPid(targetPID)
    }

    nonisolated static func keyCode(forButton button: Int64) -> CGKeyCode? {
        switch button {
        case Self.rearButton: Self.rightArrowKeyCode
        case Self.frontButton: Self.leftArrowKeyCode
        default: nil
        }
    }

    private func handleButtons(_ event: CGEvent, type: CGEventType) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard let keyCode = Self.keyCode(forButton: button),
              event.flags.isDisjoint(with: Self.reservedFlags) else {
            return false
        }

        if type == .otherMouseDown {
            Task { @MainActor [weak self] in
                await self?.pressKey(keyCode)
            }
        }
        return true
    }

    private func pressKey(_ keyCode: CGKeyCode) async {
        let source = CGEventSource(stateID: .hidSystemState)

        Self.post(Self.controlKeyCode, down: true, flags: .maskControl, source: source, asModifier: true)
        Self.post(keyCode, down: true, flags: Self.arrowFlags, source: source)
        try? await Task.sleep(for: Self.chordHold)
        Self.post(keyCode, down: false, flags: Self.arrowFlags, source: source)
        Self.post(Self.controlKeyCode, down: false, flags: [], source: source, asModifier: true)
    }

    private static func post(_ keyCode: CGKeyCode, down: Bool, flags: CGEventFlags,
                             source: CGEventSource?, asModifier: Bool = false) {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { return }
        if asModifier {
            event.type = .flagsChanged
        }
        event.flags = flags
        event.post(tap: .cghidEventTap)
    }
}
