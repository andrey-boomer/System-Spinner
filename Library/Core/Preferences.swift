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
