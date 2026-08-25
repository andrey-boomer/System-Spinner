//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Testing
@testable import System_Spinner

@Suite("Sensor keys")
struct SensorKeysTests {
    @Test("The table holds nothing but SMC keys")
    func tableIsWellFormed() {
        for sensor in SMCKeys.all {
            #expect(sensor.key.count == 4, "\(sensor.key) is not a four-character SMC key")
            #expect(!sensor.name.isEmpty, "\(sensor.key) has no name")
        }
    }

    @Test("Every reading the app shows has a key behind it")
    func nothingIsMissing() {
        #expect(!SMCKeys.keys(.systemPower).isEmpty)
        #expect(!SMCKeys.keys(.adapterPower).isEmpty)
        #expect(!SMCKeys.keys(.fanCount).isEmpty)
        #expect(!SMCKeys.keys(.fan).isEmpty)
    }

    @Test("Fan keys follow the number of fans", arguments: [0, 1, 2, 4])
    func fanKeys(count: Int) {
        let keys = SMCKeys.fanSpeed(count: count)

        #expect(keys.count == count)
        #expect(keys.allSatisfy { $0.count == 4 }, "SMC keys are always four characters")
        #expect(Set(keys).count == count, "the same fan was asked for twice")
    }

    // The sensors are found by asking the chip, so what they are cannot be
    // asserted ahead of time — only that what came back is a temperature. A
    // machine with no SMC has nothing to say and is left alone.
    @Test("Discovered sensors read as temperatures")
    @MainActor
    func discoveryReturnsTemperatures() {
        let service = SensorService()
        guard service.isAvailable, service.hasTemperature else { return }

        let reading = service.read().cpuTemperature

        #expect(reading > 5, "\(reading) is too cold to be a running processor")
        #expect(reading < 120, "\(reading) is past anything a processor survives")
    }
}

@Suite("Temperature smoothing")
struct TemperatureSmoothingTests {
    private let now = Date()

    @Test("Readings older than the window are dropped")
    func theWindowMovesOn() {
        // Written against the window rather than against a number, so that
        // moving it does not turn into a failing test with nothing wrong.
        let window = SensorService.smoothingWindow
        let readings = [
            SensorService.Reading(time: now.addingTimeInterval(-window * 3), value: 90),
            SensorService.Reading(time: now.addingTimeInterval(-window - 1), value: 90),
            SensorService.Reading(time: now.addingTimeInterval(-window + 1), value: 50),
            SensorService.Reading(time: now, value: 50),
        ]

        let kept = SensorService.recent(readings, at: now)

        #expect(kept.count == 2, "the window let something stale through")
        #expect(SensorService.mean(of: kept.map(\.value)) == 50)
    }

    @Test("A jump is followed, not ignored")
    func theAverageMoves() {
        // Smoothing that never catches up would be worse than none: a machine
        // that heats up has to show it.
        var readings: [SensorService.Reading] = []
        for step in 0 ..< Int(SensorService.smoothingWindow) {
            readings.append(SensorService.Reading(time: now.addingTimeInterval(Double(step)), value: 80))
            readings = SensorService.recent(readings, at: now.addingTimeInterval(Double(step)))
        }

        #expect(SensorService.mean(of: readings.map(\.value)) == 80)
    }

    @Test("Nothing to average is not a temperature of zero")
    func emptyIsZero() {
        #expect(SensorService.mean(of: []) == 0)
    }
}
