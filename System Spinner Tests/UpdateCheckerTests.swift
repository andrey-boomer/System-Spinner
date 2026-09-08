//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Testing
@testable import System_Spinner

@Suite("Version numbers")
struct UpdateCheckerTests {
    @Test("Components are weighted by their position", arguments: [
        ("4.7.0", 4_007_000),
        ("5.0.0", 5_000_000),
        ("5.6", 5_006_000),
        ("v4.7.0", 4_007_000),
        ("Version 4.7.0", 4_007_000),
    ])
    func parsing(tag: String, expected: Int) {
        #expect(UpdateChecker.versionNumber(tag) == expected)
    }

    @Test("A tag without digits reads as zero", arguments: ["", "latest", "vX.Y.Z"])
    func noDigits(tag: String) {
        #expect(UpdateChecker.versionNumber(tag) == 0)
    }

    @Test("A newer release compares greater than the installed one")
    func ordering() {
        #expect(UpdateChecker.versionNumber("5.0.0") > UpdateChecker.versionNumber("4.7.0"))
        #expect(UpdateChecker.versionNumber("4.7.1") > UpdateChecker.versionNumber("4.7.0"))
        #expect(UpdateChecker.versionNumber("4.7.0") == UpdateChecker.versionNumber("4.7.0"))
    }

    @Test("A two-component version outranks the three-component one it follows")
    func twoComponentNumbering() {
        #expect(UpdateChecker.versionNumber("5.6") > UpdateChecker.versionNumber("5.5.3"))
        #expect(UpdateChecker.versionNumber("5.6.1") > UpdateChecker.versionNumber("5.6"))
        #expect(UpdateChecker.versionNumber("6.0") > UpdateChecker.versionNumber("5.6"))
    }

    @Test("A component past nine keeps its place")
    func doubleDigitComponents() {
        #expect(UpdateChecker.versionNumber("4.10.0") > UpdateChecker.versionNumber("4.7.0"))
        #expect(UpdateChecker.versionNumber("41.0.0") > UpdateChecker.versionNumber("4.10.0"))
    }

    @Test("Anything past the third component is ignored")
    func extraComponents() {
        #expect(UpdateChecker.versionNumber("5.6.1.4") == UpdateChecker.versionNumber("5.6.1"))
    }
}
