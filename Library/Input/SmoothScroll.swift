//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0
//  Smoothing approach from https://github.com/Caldis/Mos

import AppKit
import QuartzCore

// Turns the notches of a wheel mouse into a glide. A wheel reports whole lines
// and the page jumps by all of them at once; a trackpad reports pixels and is
// smooth already. The line event is swallowed here and its distance paid back
// out one frame at a time.
@MainActor
final class SmoothScroll {
    static let shared = SmoothScroll()

    // A notch travels four lines rather than the three macOS itself jumps: the
    // glide reads as slower than a jump of the same size, so covering the same
    // page needs a little more of it.
    private static let pixelsPerLine: Double = 16
    private static let linesPerNotch: Double = 4

    // The share of what is left that one frame hands over, at 60 Hz. Rescaled
    // for faster displays so the glide takes the same time rather than half.
    nonisolated private static let decayPerFrame: Double = 0.12

    // How fast the frame being posted catches up with the frame being asked
    // for. An exponential glide hands over its largest slice on the very first
    // frame, and that jolt is what a wheel feels like without this: the motion
    // is eased into over several frames instead, the way a hand builds up
    // speed. Mos calls the same thing a peak filter.
    nonisolated private static let easeInPerFrame: Double = 0.23

    // Below this the glide is over. A fraction of a pixel would only post
    // events that move nothing.
    nonisolated private static let restThreshold: Double = 0.5

    // Marks what this class posts, so the tap lets its own work past instead of
    // smoothing it a second time.
    private static let marker: Int64 = 0x5350_4E52

    // A trackpad wraps its pixels in a gesture, and the apps that scroll
    // smoothly are listening for it: Safari ignores loose continuous events
    // that begin and end nowhere. The glide is dressed as one gesture —
    // "began" on the first frame, "changed" while it runs, "ended" once.
    private static let phaseBegan: Int64 = 1
    private static let phaseChanged: Int64 = 2
    private static let phaseEnded: Int64 = 4

    // Once the finger is off, a trackpad stops sending the scroll phase and
    // switches to the momentum one for the coast. Keeping the gesture "down"
    // for the whole glide instead leaves WebKit latched onto whatever it began
    // over — a table inside a mail, say — and the page behind never moves.
    private static let momentumBegan: Int64 = 1
    private static let momentumOngoing: Int64 = 2
    private static let momentumEnded: Int64 = 3

    // How long the wheel may be still before the finger counts as lifted.
    // Taken from Mos, where the same threshold separates one turn of the wheel
    // from the next.
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

    // The event that opened the glide, replayed every frame with a new delta.
    // A scroll event carries the process it was aimed at, the pointer position
    // and the modifiers held; a freshly built one would have none of that.
    private var template: CGEvent?
    private var targetPID: pid_t = 0

    // Pixels still owed, and the direction of the last turn of the wheel.
    private var pending = (x: 0.0, y: 0.0)
    private var emitted = (x: 0.0, y: 0.0)
    private var lastDelta = (x: 0.0, y: 0.0)
    private var stage: Stage = .idle
    private var lastInput: CFTimeInterval = 0


    private init() {}

    var isRunning: Bool { eventTap != nil }

    // Exponential ease-out: a fixed share of the remaining distance per frame.
    // Kept apart from the event plumbing so the curve can be checked on its own.
    nonisolated static func step(remaining: Double, frameDuration: Double) -> Double {
        guard abs(remaining) > restThreshold else { return remaining }

        return remaining * share(decayPerFrame, frameDuration: frameDuration)
    }

    // One frame of the glide: what to post, and what is left afterwards. The
    // step is eased into rather than taken whole, and what comes off the total
    // is what was actually posted — so easing delays the travel without
    // swallowing any of it.
    nonisolated static func advance(remaining: Double,
                                    emitted: Double,
                                    frameDuration: Double) -> (post: Double, remaining: Double) {
        guard abs(remaining) > restThreshold else { return (remaining, 0) }

        let want = step(remaining: remaining, frameDuration: frameDuration)
        let next = emitted + share(easeInPerFrame, frameDuration: frameDuration) * (want - emitted)

        // A frame lagging behind a falling curve overshoots it, and one that
        // hands over more than is left drives the total past zero: from there
        // the glide rings around it instead of settling, for an unpredictable
        // number of frames. Capped at what remains, the total only ever falls.
        let capped = abs(next) > abs(remaining) ? remaining : next
        return (capped, remaining - capped)
    }

    // A per-frame fraction restated for the frame actually drawn, so that every
    // curve here lasts the same time on a 60 Hz display and on a 170 Hz one.
    nonisolated static func share(_ perFrame: Double, frameDuration: Double) -> Double {
        1 - pow(1 - perFrame, max(frameDuration, 1.0 / 240) * 60)
    }

    @discardableResult
    func start() -> Bool {
        if eventTap != nil { return true }

        let mask = CGEventMask(1 << CGEventType.scrollWheel.rawValue)
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        // The annotated session tap, not the HID one: only here has the window
        // server already worked out which process the scroll is aimed at, and
        // that process is where the glide has to be delivered.
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
        // Delivering to the target process sends the glide back through this
        // tap, so its own work is recognised first — the continuous check below
        // would otherwise claim it and never let this one run.
        if event.getIntegerValueField(.eventSourceUserData) == Self.marker {
            return Unmanaged.passUnretained(event)
        }

        // A trackpad or a Magic Mouse sends pixels and momentum of its own;
        // smoothing that would fight it.
        if event.getIntegerValueField(.scrollWheelEventIsContinuous) != 0 {
            return Unmanaged.passUnretained(event)
        }

        // With a modifier held the wheel means zoom or a jump by page, which is
        // not a scroll to smooth. Shift is left in: it only turns the same
        // scroll sideways.
        if !event.flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
            return Unmanaged.passUnretained(event)
        }

        let travel = Self.pixelsPerLine * Self.linesPerNotch
        let deltaY = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)) * travel
        let deltaX = Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis2)) * travel
        guard deltaY != 0 || deltaX != 0 else {
            return Unmanaged.passUnretained(event)
        }

        // Turning the wheel back replaces what is left rather than being
        // subtracted from it, so the reversal answers at once instead of first
        // paying off the glide that is still running the other way.
        if deltaY != 0 {
            pending.y = deltaY * lastDelta.y > 0 ? pending.y + deltaY : deltaY
            lastDelta.y = deltaY
        }
        if deltaX != 0 {
            pending.x = deltaX * lastDelta.x > 0 ? pending.x + deltaX : deltaX
            lastDelta.x = deltaX
        }

        // Nothing is swallowed until there is something to replay it with and
        // somewhere to send it. Without all three the distance would go
        // nowhere and the mouse would stop scrolling at all.
        let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
        guard pid != 0, let copy = event.copy(), startGlide() else {
            pending = (0, 0)
            return Unmanaged.passUnretained(event)
        }

        template = copy
        targetPID = pid
        lastInput = CACurrentMediaTime()
        if stage != .began, stage != .tracking {
            // Coming out of a coast, or off nothing at all: either way this is
            // a new gesture and has to announce itself as one.
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
        // The wheel has stopped turning, so the finger comes off and the rest
        // of the distance is a coast. The frame carries no travel of its own —
        // it says only that the gesture is over.
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
            // A gesture short enough to finish before the finger came off is
            // closed as a gesture; anything else is closed as a coast.
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

        // Written in this order and no other. These fields are different views
        // of one scroll amount and CoreGraphics keeps them agreed: writing the
        // line delta rewrites the pixel delta, so touching it after the pixels
        // are in place wipes them, and the app is handed a gesture that moves
        // nothing at all. The line fields are left alone for that reason.
        event.setDoubleValueField(.scrollWheelEventScrollPhase, value: Double(scroll))
        event.setDoubleValueField(.scrollWheelEventMomentumPhase, value: Double(momentum))
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: dy)
        event.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: dx)

        // This is what makes the glide survive: it tells the app the event came
        // from a device that scrolls by the pixel. Without it the fractions are
        // rounded back to whole lines and nothing is gained.
        event.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1)

        // Delivered to the process the wheel was pointed at, not back into the
        // event stream: a glide outliving the pointer would otherwise land in
        // whatever window happens to be under it by then.
        event.postToPid(targetPID)
    }
}
