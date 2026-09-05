//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Testing
@testable import System_Spinner

@Suite("Smooth scroll glide")
struct SmoothScrollTests {
    private let frame60 = 1.0 / 60
    private let frame170 = 1.0 / 170

    // Runs a whole glide the way the display link does, and reports what the
    // scrolled window would have seen.
    private func glide(_ distance: Double, frameDuration: Double) -> (frames: Int, travelled: Double, first: Double, peak: Double) {
        var remaining = distance
        var emitted = 0.0
        var frames = 0
        var travelled = 0.0
        var first = 0.0
        var peak = 0.0

        while remaining != 0, frames < 5000 {
            let next = MouseInput.advance(remaining: remaining, emitted: emitted, frameDuration: frameDuration)
            emitted = next.post
            remaining = next.remaining
            travelled += next.post
            if frames == 0 { first = next.post }
            peak = max(peak, abs(next.post))
            frames += 1
        }

        return (frames, travelled, first, peak)
    }

    @Test("The glide covers exactly the distance asked for")
    func distanceIsConserved() {
        // Easing delays the travel; it must not swallow any of it.
        for distance in [-960.0, -64.0, 64.0, 960.0] {
            let run = glide(distance, frameDuration: frame170)

            #expect(abs(run.travelled - distance) < 0.001, "\(distance) delivered \(run.travelled)")
        }
    }

    @Test("A frame never hands over more than is left")
    func noOvershoot() {
        // Without the cap the remainder goes past zero and the glide rings
        // around it for an unpredictable number of frames.
        var remaining = 64.0
        var emitted = 0.0
        var frames = 0

        while remaining != 0, frames < 5000 {
            let next = MouseInput.advance(remaining: remaining, emitted: emitted, frameDuration: frame170)

            #expect(abs(next.remaining) <= abs(remaining), "the remainder grew back")
            #expect(next.remaining == 0 || next.remaining.sign == remaining.sign, "the remainder changed sign")

            emitted = next.post
            remaining = next.remaining
            frames += 1
        }

        #expect(frames < 5000, "the glide never settled")
    }

    @Test("The first frame is a nudge, not a jolt")
    func theStartIsEased() {
        let run = glide(64, frameDuration: frame170)

        // A bare exponential would hand over its largest slice immediately,
        // which is the jerk this is here to remove.
        #expect(run.first < run.peak / 3, "started at \(run.first) against a peak of \(run.peak)")
    }

    @Test("A faster display glides for the same time, not a shorter one")
    func refreshRateDoesNotChangeTheDuration() {
        let slow = glide(64, frameDuration: frame60)
        let fast = glide(64, frameDuration: frame170)

        let slowSeconds = Double(slow.frames) * frame60
        let fastSeconds = Double(fast.frames) * frame170

        #expect(abs(slowSeconds - fastSeconds) < 0.05, "\(slowSeconds)s at 60 Hz against \(fastSeconds)s at 170 Hz")
        #expect(fastSeconds < 0.5, "\(fastSeconds)s is a drift, not a glide")
    }
}
