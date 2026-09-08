//  Copyright © (yu) zmlabs, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import AppKit
import ApplicationServices

enum MediaKeyHandlingResult: Equatable {
    case passThrough
    case consumed
}

@MainActor
final class MediaKeyMonitor {
    enum MediaKey: Int {
        case soundUp = 0
        case soundDown = 1
        case brightnessUp = 2
        case brightnessDown = 3
        case mute = 7
        case illuminationUp = 21
        case illuminationDown = 22
    }

    static let shared = MediaKeyMonitor()

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var eventTapRunLoop: CFRunLoop?
    private static let brightnessUpKeyCode: Int64 = 144
    private static let brightnessDownKeyCode: Int64 = 145
    private static let f5KeyCode: Int64 = 176
    private static let f6KeyCode: Int64 = 178

    private static let reservingFlags: CGEventFlags = [.maskCommand, .maskControl, .maskShift]
    private static let fineAdjustmentFlag: CGEventFlags = .maskAlternate

    @discardableResult
    func start() -> Bool {
        if eventTap != nil {
            return true
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue) |
                (1 << UInt64(NSEvent.EventType.systemDefined.rawValue))
        )
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        let runLoop = CFRunLoopGetMain()
        CFRunLoopAddSource(runLoop, source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapSource = source
        eventTapRunLoop = runLoop

        return true
    }

    func stop() {
        let source = eventTapSource
        let runLoop = eventTapRunLoop
        let tap = eventTap
        eventTap = nil
        eventTapSource = nil
        eventTapRunLoop = nil

        if let source, let runLoop {
            CFRunLoopRemoveSource(runLoop, source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        if let tap {
            CFMachPortInvalidate(tap)
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
            let monitor = Unmanaged<MediaKeyMonitor>.fromOpaque(box.refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                monitor.enableEventTap()
                return ResultBox(value: Unmanaged.passUnretained(box.event))
            }

            return ResultBox(value: monitor.handle(box.event))
        }

        return result.value
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.type == .keyDown {
            return handleKeyDown(event)
        }
        return handleSystemDefinedMediaKey(event)
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let isPlainKey = event.flags.isDisjoint(with: Self.reservingFlags)

        let mediaKey: MediaKey
        switch keyCode {
        case Self.brightnessUpKeyCode:
            mediaKey = .brightnessUp
        case Self.brightnessDownKeyCode:
            mediaKey = .brightnessDown
        case Self.f6KeyCode where isPlainKey:
            mediaKey = .illuminationUp
        case Self.f5KeyCode where isPlainKey:
            mediaKey = .illuminationDown
        default:
            return Unmanaged.passUnretained(event)
        }

        return applyResult(handleMediaKey(mediaKey, fine: Self.isFineAdjustment(event)), event: event)
    }

    private func handleSystemDefinedMediaKey(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        guard let nsEvent = NSEvent(cgEvent: event) else {
            return Unmanaged.passUnretained(event)
        }

        guard nsEvent.type == .systemDefined, nsEvent.subtype.rawValue == 8 else {
            return Unmanaged.passUnretained(event)
        }

        let data1 = nsEvent.data1
        let keyCode = Int((data1 & 0xFFFF_0000) >> 16)
        let flags = Int(data1 & 0x0000_FFFF)

        let keyState = (flags & 0xFF00) >> 8
        guard keyState == 0x0A else { return Unmanaged.passUnretained(event) }

        guard let mk = MediaKey(rawValue: keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        return applyResult(handleMediaKey(mk, fine: Self.isFineAdjustment(event)), event: event)
    }

    private func applyResult(_ result: MediaKeyHandlingResult, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch result {
        case .passThrough:
            Unmanaged.passUnretained(event)
        case .consumed:
            nil
        }
    }

    private static func isFineAdjustment(_ event: CGEvent) -> Bool {
        !event.flags.isDisjoint(with: fineAdjustmentFlag)
    }

    private func handleMediaKey(_ key: MediaKey, fine: Bool) -> MediaKeyHandlingResult {
        switch key {
            case .soundUp:
                return DisplayManager.shared.setVolume(isUp: true, fine: fine)
            case .soundDown:
                return DisplayManager.shared.setVolume(isUp: false, fine: fine)
            case .mute:
                return DisplayManager.shared.toggleMute()
            case .brightnessUp:
                return DisplayManager.shared.setBrightness(isUp: true, fine: fine)
            case .brightnessDown:
                return DisplayManager.shared.setBrightness(isUp: false, fine: fine)
            case .illuminationUp, .illuminationDown:
                guard Preferences.shared.usesKeyboardBacklightKeys else { return .passThrough }
                return KeyboardBacklight.shared.adjust(isUp: key == .illuminationUp, fine: fine)
        }
    }
}
