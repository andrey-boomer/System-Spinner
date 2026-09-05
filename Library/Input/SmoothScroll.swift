//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0
//  Smoothing approach from https://github.com/Caldis/Mos

import AppKit
import QuartzCore

@MainActor
final class SmoothScroll {
    static let shared = SmoothScroll()
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

    private enum Stage {
        case idle
        case began
        case tracking
        case coastBegan
        case coasting
    }

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


    private init() {}

    var isRunning: Bool { eventTap != nil }

    nonisolated static func step(remaining: Double, frameDuration: Double) -> Double {
        guard abs(remaining) > restThreshold else { return remaining }

        return remaining * share(decayPerFrame, frameDuration: frameDuration)
    }

    nonisolated static func advance(remaining: Double,
                                    emitted: Double,
                                    frameDuration: Double) -> (post: Double, remaining: Double) {
        guard abs(remaining) > restThreshold else { return (remaining, 0) }

        let want = step(remaining: remaining, frameDuration: frameDuration)
        let next = emitted + share(easeInPerFrame, frameDuration: frameDuration) * (want - emitted)
        let capped = abs(next) > abs(remaining) ? remaining : next
        return (capped, remaining - capped)
    }

    nonisolated static func share(_ perFrame: Double, frameDuration: Double) -> Double {
        1 - pow(1 - perFrame, max(frameDuration, 1.0 / 240) * 60)
    }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgAnnotatedSessionEventTap,
            place: .tailAppendEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.eventTapCallback,
            userInfo: refcon
        ) else {
            return false
        }

        let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        eventTapSource = runLoopSource
        return true
    }

    func stop() {
        stopGlide()

        let source = eventTapSource
        let tap = eventTap
        eventTap = nil
        eventTapSource = nil

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
            let scroll = Unmanaged<SmoothScroll>.fromOpaque(box.refcon).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                scroll.enableEventTap()
                return ResultBox(value: Unmanaged.passUnretained(box.event))
            }

            return ResultBox(value: scroll.handle(box.event))
        }

        return result.value
    }

    private func handle(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker {
            return Unmanaged.passUnretained(event)
        }

        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }

        if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
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
        guard pid != 0, let copy = event.copy(), startGlide() else {
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
            post(dx: 0, dy: 0, scroll: Self.phaseEnded, momentum: 0)
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
            post(dx: emitted.x, dy: emitted.y, scroll: Self.phaseBegan, momentum: 0)
            stage = .tracking
        case .tracking:
            post(dx: emitted.x, dy: emitted.y, scroll: Self.phaseChanged, momentum: 0)
        case .coastBegan:
            post(dx: emitted.x, dy: emitted.y, scroll: 0, momentum: Self.momentumBegan)
            stage = .coasting
        case .coasting, .idle:
            post(dx: emitted.x, dy: emitted.y, scroll: 0, momentum: Self.momentumOngoing)
        }

        if pending.x == 0, pending.y == 0 {
            if stage == .began || stage == .tracking {
                post(dx: 0, dy: 0, scroll: Self.phaseEnded, momentum: 0)
            } else {
                post(dx: 0, dy: 0, scroll: 0, momentum: Self.momentumEnded)
            }
            stopGlide()
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
}
