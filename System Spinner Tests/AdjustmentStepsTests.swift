//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Testing
@testable import System_Spinner

@Suite("Adjustment steps")
struct AdjustmentStepsTests {
    @Test("Fine adjustment is the coarsest step count offered in the menu")
    func fineStepsMatchMenu() {
        #expect(Preferences.fineAdjustmentSteps == 32)
        #expect(Preferences.adjustmentStepChoices.max() == Preferences.fineAdjustmentSteps)
    }

    @Test("Without the modifier the preference is used as is", arguments: [8, 16, 24, 32])
    func plainStepsFollowPreference(base: Int) {
        #expect(Preferences.adjustmentSteps(base: base, fine: false) == base)
    }

    @Test("The modifier widens the scale to 32 steps", arguments: [8, 16, 24, 32])
    func fineStepsWidenScale(base: Int) {
        #expect(Preferences.adjustmentSteps(base: base, fine: true) == 32)
    }

    @Test("A preference finer than 32 steps is never coarsened")
    func fineStepsNeverShrink() {
        #expect(Preferences.adjustmentSteps(base: 64, fine: true) == 64)
    }

    @Test("The OSD carries the widened scale")
    func osdCarriesFineScale() {
        let steps = Preferences.adjustmentSteps(base: 16, fine: true)
        #expect(OSDValue(value: 50, kind: .displayBrightness, separatorSteps: steps).separatorSteps == 32)
    }
}
