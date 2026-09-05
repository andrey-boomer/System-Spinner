//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices
import QuartzCore

@MainActor
final class MouseButtons {
    static let shared = MouseButtons()
    nonisolated static let rearButton: Int64 = 3
    nonisolated static let frontButton: Int64 = 4
    nonisolated static let leftArrowKeyCode: CGKeyCode = 123
    nonisolated static let rightArrowKeyCode: CGKeyCode = 124
    private static let controlKeyCode: CGKeyCode = 59
    private static let arrowFlags: CGEventFlags = [.maskControl, .maskSecondaryFn, .maskNumericPad]
    private static let chordHold: Duration = .milliseconds(80)
    private static let deviceCheckLifetime: CFTimeInterval = 2
    private static let systemDefinedEventType: UInt32 = 14
    private static let auxMouseButtonsSubtype: Int16 = 7
    private static let thumbButtonsMask: Int = (1 << Int(rearButton)) | (1 << Int(frontButton))
    private static let reservedFlags: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var lastDeviceCheck: (time: CFTimeInterval, present: Bool)?

    private init() {}

    var isRunning: Bool { eventTap != nil }

    nonisolated static func keyCode(forButton button: Int64) -> CGKeyCode? {
        switch button {
        case rearButton: rightArrowKeyCode
        case frontButton: leftArrowKeyCode
        default: nil
        }
    }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        let mask = CGEventMask(
            (1 << CGEventType.otherMouseDown.rawValue) |
                (1 << CGEventType.otherMouseUp.rawValue) |
                (1 << Self.systemDefinedEventType)
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
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
        let source = eventTapSource
        let tap = eventTap
        eventTap = nil
        eventTapSource = nil
        lastDeviceCheck = nil

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap {
            CFMachPortInvalidate(tap)
        }
    }

    func setEnabled(_ enabled: Bool) {
        if enabled {
            start()
        } else {
            stop()
        }
    }

    private func enableEventTap() {
        guard let tap = eventTap else { return }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private struct EventBox: @unchecked Sendable {
        let event: CGEvent
        let refcon: UnsafeMutableRawPointer
    }

    private struct ResultBox: @unchecked Sendable {
        let value: Unmanaged<CGEvent>?
    }

    private static let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
        guard let refcon else {
            return Unmanaged.passUnretained(event)
        }

        let box = EventBox(event: event, refcon: refcon)

        let result = MainActor.assumeIsolated { () -> ResultBox in
            let buttons = Unmanaged<MouseButtons>.fromOpaque(box.refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                buttons.enableEventTap()
                return ResultBox(value: Unmanaged.passUnretained(box.event))
            }

            return ResultBox(value: buttons.handle(box.event, type: type))
        }

        return result.value
    }

    private func handle(_ event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        let taken: Bool = switch type {
        case .otherMouseDown, .otherMouseUp: handleButton(event, type: type)
        default: isThumbMirror(event, type: type)
        }
        return taken ? nil : Unmanaged.passUnretained(event)
    }

    private func handleButton(_ event: CGEvent, type: CGEventType) -> Bool {
        let button = event.getIntegerValueField(.mouseEventButtonNumber)
        guard let keyCode = Self.keyCode(forButton: button),
              event.flags.isDisjoint(with: Self.reservedFlags),
              hasLogitechMouse() else {
            return false
        }

        if type == .otherMouseDown {
            Task { @MainActor [weak self] in
                await self?.pressKey(keyCode)
            }
        }
        return true
    }

    private func isThumbMirror(_ event: CGEvent, type: CGEventType) -> Bool {
        guard type.rawValue == Self.systemDefinedEventType,
              event.flags.isDisjoint(with: Self.reservedFlags),
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Self.auxMouseButtonsSubtype,
              nsEvent.data1 & Self.thumbButtonsMask != 0 else {
            return false
        }
        return hasLogitechMouse()
    }

    private func hasLogitechMouse() -> Bool {
        let now = CACurrentMediaTime()
        if let last = lastDeviceCheck, now - last.time < Self.deviceCheckLifetime {
            return last.present
        }

        let present = PointingDevices.hasLogitechMouse
        lastDeviceCheck = (now, present)
        return present
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
