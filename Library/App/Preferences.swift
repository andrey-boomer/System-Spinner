//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import Synchronization

@propertyWrapper
final class Stored<Value: Sendable>: Sendable {
    private let key: String
    private let cached: Mutex<Value>

    init(_ key: String, _ defaultValue: Value) {
        self.key = key
        cached = Mutex(UserDefaults.standard.object(forKey: key) as? Value ?? defaultValue)
    }

    var wrappedValue: Value {
        get { cached.withLock { $0 } }
        set {
            cached.withLock { $0 = newValue }
            UserDefaults.standard.set(newValue, forKey: key)
        }
    }
}

extension String {
    init(cBuffer: [CChar]) {
        let bytes = cBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }
}

struct SpinnerStyle {
    let name: String
    let frameCount: Int
    let supportsEffect: Bool
    let speedCoefficient: Int

    func frameName(at index: Int) -> String {
        frameCount == 1 ? name : "\(name) \(index)"
    }
}

enum SpinnerEffect: Int, CaseIterable {
    case original = 1
    case whiteShaded = 2
    case blackShaded = 3
    case automatic = 4

    var title: String {
        switch self {
        case .original: return localizedString("Original")
        case .whiteShaded: return localizedString("White shaded")
        case .blackShaded: return localizedString("Black shaded")
        case .automatic: return localizedString("Automatic Dark/White mode")
        }
    }
}

enum SpinnerCatalog {
    static let all: [SpinnerStyle] = [
        SpinnerStyle(name: "Blue Ball", frameCount: 19, supportsEffect: true, speedCoefficient: 1),
        SpinnerStyle(name: "Cat", frameCount: 5, supportsEffect: true, speedCoefficient: 2),
        SpinnerStyle(name: "Circles Two", frameCount: 9, supportsEffect: true, speedCoefficient: 1),
        SpinnerStyle(name: "Cirrcles", frameCount: 8, supportsEffect: false, speedCoefficient: 1),
        SpinnerStyle(name: "Color Balls", frameCount: 17, supportsEffect: true, speedCoefficient: 1),
        SpinnerStyle(name: "Color Well", frameCount: 20, supportsEffect: false, speedCoefficient: 1),
        SpinnerStyle(name: "Delay", frameCount: 17, supportsEffect: true, speedCoefficient: 1),
        SpinnerStyle(name: "Dots", frameCount: 12, supportsEffect: false, speedCoefficient: 1),
        SpinnerStyle(name: "Grey Loader", frameCount: 18, supportsEffect: false, speedCoefficient: 1),
        SpinnerStyle(name: "Loader", frameCount: 8, supportsEffect: false, speedCoefficient: 1),
        SpinnerStyle(name: "Pie", frameCount: 6, supportsEffect: false, speedCoefficient: 1),
        SpinnerStyle(name: "Pikachu", frameCount: 4, supportsEffect: true, speedCoefficient: 2),
        SpinnerStyle(name: "Rainbow Pie", frameCount: 15, supportsEffect: false, speedCoefficient: 1),
        SpinnerStyle(name: "Recharges", frameCount: 8, supportsEffect: true, speedCoefficient: 1),
        SpinnerStyle(name: "Rotation Color Well", frameCount: 24, supportsEffect: false, speedCoefficient: 2),
        SpinnerStyle(name: "Sun", frameCount: 24, supportsEffect: true, speedCoefficient: 1),
        SpinnerStyle(name: "Waves", frameCount: 17, supportsEffect: true, speedCoefficient: 1),
        SpinnerStyle(name: "App Icon", frameCount: 1, supportsEffect: true, speedCoefficient: 1),
    ]

    static let fallback = all.first { $0.name == "Loader" } ?? all[0]

    static func style(named name: String) -> SpinnerStyle? {
        all.first { $0.name == name }
    }

    static func style(validating name: String) -> SpinnerStyle {
        style(named: name) ?? fallback
    }
}

final class Preferences: @unchecked Sendable {
    static let shared = Preferences()

    private static let obsoleteKeys = ["group.lastCheckVersion"]

    private init() {
        for key in Self.obsoleteKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    @Stored("spinnerActive", "Loader")
    var spinnerName: String

    @Stored("spinnerUpdateInterval", 1.0)
    var updateInterval: Double

    @Stored("enableStatusText", false)
    var showsCPUInMenuBar: Bool

    @Stored("useLocalization", true)
    var usesSystemLanguage: Bool

    @Stored("spinnersEffectSelected", 1)
    var spinnerEffect: Int

    @Stored("spinnersRotationInvert", false)
    var invertsRotation: Bool

    @Stored("alwaysUseCustomOSD", false)
    var alwaysUsesCustomOSD: Bool

    @Stored("adjSteps", 16)
    var adjustmentSteps: Int

    static let adjustmentStepChoices = [8, 16, 24, 32]
    static let fineAdjustmentSteps = adjustmentStepChoices.max() ?? 32

    static func adjustmentSteps(base: Int, fine: Bool) -> Int {
        fine ? max(base, fineAdjustmentSteps) : base
    }

    func adjustmentSteps(fine: Bool) -> Int {
        Self.adjustmentSteps(base: adjustmentSteps, fine: fine)
    }

    @Stored("usePopUpAnimation", true)
    var usesPopUpAnimation: Bool

    @Stored("showExternalAddress", true)
    var showsExternalAddress: Bool

    @Stored("keyboardBacklightKeys", false)
    var usesKeyboardBacklightKeys: Bool

    @Stored("smoothMouseScroll", false)
    var usesSmoothScroll: Bool

    @Stored("lastVersionCheckTime", 0.0)
    private var lastVersionCheckTime: TimeInterval

    var lastVersionCheck: Date? {
        get { lastVersionCheckTime > 0 ? Date(timeIntervalSince1970: lastVersionCheckTime) : nil }
        set { lastVersionCheckTime = newValue?.timeIntervalSince1970 ?? 0 }
    }

    func brightness(forDisplay name: String) -> Float? {
        UserDefaults.standard.object(forKey: "brightness." + name) as? Float
    }

    func setBrightness(_ value: Float, forDisplay name: String) {
        UserDefaults.standard.set(value, forKey: "brightness." + name)
    }

    func keyboardBacklight(forKeyboard identifier: UInt64) -> Float? {
        UserDefaults.standard.object(forKey: "keyboardBacklight.\(identifier)") as? Float
            ?? UserDefaults.standard.object(forKey: "keyboardBacklight") as? Float
    }

    func setKeyboardBacklight(_ value: Float, forKeyboard identifier: UInt64) {
        UserDefaults.standard.set(value, forKey: "keyboardBacklight.\(identifier)")
    }

    func volume(forDisplay name: String) -> Float? {
        UserDefaults.standard.object(forKey: "volume." + name) as? Float
    }

    func setVolume(_ value: Float, forDisplay name: String) {
        UserDefaults.standard.set(value, forKey: "volume." + name)
    }
}

private let englishLocalizationPath = Bundle.main.path(forResource: "en", ofType: "lproj")

func localizedString(_ key: String.LocalizationValue) -> String {
    if Preferences.shared.usesSystemLanguage {
        return String(localized: key)
    }

    let bundle = englishLocalizationPath.flatMap(Bundle.init(path:)) ?? .main
    return String(localized: key, bundle: bundle, locale: Locale(identifier: "en"))
}
