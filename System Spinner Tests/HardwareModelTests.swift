//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Testing
@testable import System_Spinner

@Suite("Chip family detection")
struct HardwareModelTests {
    @Test("Family is taken from the processor brand string", arguments: [
        ("Apple M1", ChipFamily.m1),
        ("Apple M1 Pro", .m1),
        ("Apple M1 Max", .m1),
        ("Apple M2", .m2),
        ("Apple M2 Ultra", .m2),
        ("Apple M3 Pro", .m3),
        ("Apple M4 Max", .m4),
        ("Apple M5", .m5),
    ])
    func knownChips(brand: String, expected: ChipFamily) {
        #expect(HardwareModel.chipFamily(from: brand) == expected)
    }

    @Test("Detection ignores letter case")
    func caseInsensitive() {
        #expect(HardwareModel.chipFamily(from: "apple m3 pro") == .m3)
    }

    @Test("Unknown processors fall back to the first family", arguments: [
        "Intel Core i7",
        "",
        "Apple Silicon",
    ])
    func unknownChips(brand: String) {
        #expect(HardwareModel.chipFamily(from: brand) == .m1)
    }

    @Test("Longer numbers are not mistaken for a family")
    func wordBoundaries() {
        // Matching is anchored on word boundaries, so "M12" must not read as M1.
        #expect(HardwareModel.chipFamily(from: "Apple M12") == .m1)
        #expect(HardwareModel.chipFamily(from: "Apple M25") == .m1)
    }

    @Test("Newer families win over older ones in the same string")
    func newestFamilyWins() {
        // The brand string of a future chip may still mention an older name.
        #expect(HardwareModel.chipFamily(from: "Apple M1 M5") == .m5)
    }

    @Test("Every family has sensor keys")
    func sensorKeys() {
        for family in ChipFamily.allCases {
            #expect(!SMCKeys.keys(.temperature, for: family).isEmpty, "\(family.rawValue) has no CPU keys")
            #expect(!SMCKeys.keys(.systemPower, for: family).isEmpty, "\(family.rawValue) has no power keys")
            #expect(!SMCKeys.keys(.adapterPower, for: family).isEmpty, "\(family.rawValue) has no adapter keys")
        }
    }

    @Test("The sensor table holds nothing but SMC keys")
    func sensorTableIsWellFormed() {
        for sensor in SMCKeys.all {
            #expect(sensor.key.count == 4, "\(sensor.key) is not a four-character SMC key")
            #expect(!sensor.platforms.isEmpty, "\(sensor.key) answers for no chip at all")
        }
    }

    @Test("Fan keys follow the number of fans", arguments: [0, 1, 2, 4])
    func fanKeys(count: Int) {
        let keys = SMCKeys.fanSpeed(count: count, for: .m3)

        #expect(keys.count == count)
        #expect(keys.allSatisfy { $0.count == 4 }, "SMC keys are always four characters")
    }
}
