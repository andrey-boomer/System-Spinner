//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Testing
@testable import System_Spinner

@Suite("Metrics values")
struct MetricsSnapshotTests {
    @Test("Readings are rounded up to a tenth", arguments: [
        (0.0, 0.0),
        (0.01, 0.1),
        (1.0, 1.0),
        (1.24, 1.3),
        (99.91, 100.0),
    ])
    func rounding(input: Double, expected: Double) {
        #expect(roundedTenth(input) == expected)
    }

    @Test("An empty snapshot reads as idle")
    func emptySnapshot() {
        let snapshot = MetricsSnapshot.empty

        #expect(snapshot.cpuUsage == 0)
        #expect(snapshot.gpuUsage == 0)
        #expect(snapshot.cpuHistory.isEmpty)
        #expect(snapshot.memoryHistory.isEmpty)
        #expect(snapshot.network.address.isEmpty)
        #expect(snapshot.memory.used == 0)
    }

    @Test("Sensors are unavailable until they are read")
    func sensorsDefault() {
        let sensors = SensorsSnapshot.unavailable

        #expect(sensors.cpuTemperature == 0)
        #expect(sensors.fanSpeeds.isEmpty)
        #expect(sensors.power == 0)
    }

    @Test("Total memory is a sane number")
    func totalMemory() {
        // Read from the host through host_info; a zero would break every
        // percentage in the window.
        #expect(MemoryMonitor.totalMemory > 0)
        #expect(MemoryMonitor.totalMemory < 4096, "value is in gigabytes")
    }
}
