//  Copyright © Serhiy Mytrovtsiy, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0
//  Таблицы датчиков из https://github.com/exelban/stats

import Foundation
import IOKit.ps

enum ChipFamily: String, CaseIterable {
    case m1 = "M1"
    case m2 = "M2"
    case m3 = "M3"
    case m4 = "M4"
    case m5 = "M5"

    static let every = Set(ChipFamily.allCases)
}

enum SensorType {
    case temperature
    case fanCount
    case fan
    case systemPower
    case adapterPower
}

struct Sensor {
    let key: String
    let name: String
    let type: SensorType
    var platforms: Set<ChipFamily> = ChipFamily.every
}

enum SMCKeys {
    static let all: [Sensor] = [
        // M1
        Sensor(key: "Tp09", name: "CPU efficiency core 1", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp0T", name: "CPU efficiency core 2", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp01", name: "CPU performance core 1", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp05", name: "CPU performance core 2", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp0D", name: "CPU performance core 3", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp0H", name: "CPU performance core 4", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp0L", name: "CPU performance core 5", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp0P", name: "CPU performance core 6", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp0X", name: "CPU performance core 7", type: .temperature, platforms: [.m1]),
        Sensor(key: "Tp0b", name: "CPU performance core 8", type: .temperature, platforms: [.m1]),

        // M2
        Sensor(key: "Tp1h", name: "CPU efficiency core 1", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp1t", name: "CPU efficiency core 2", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp1p", name: "CPU efficiency core 3", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp1l", name: "CPU efficiency core 4", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp01", name: "CPU performance core 1", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp05", name: "CPU performance core 2", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp09", name: "CPU performance core 3", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp0D", name: "CPU performance core 4", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp0X", name: "CPU performance core 5", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp0b", name: "CPU performance core 6", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp0f", name: "CPU performance core 7", type: .temperature, platforms: [.m2]),
        Sensor(key: "Tp0j", name: "CPU performance core 8", type: .temperature, platforms: [.m2]),

        // M3
        Sensor(key: "Te05", name: "CPU efficiency core 1", type: .temperature, platforms: [.m3]),
        Sensor(key: "Te0L", name: "CPU efficiency core 2", type: .temperature, platforms: [.m3]),
        Sensor(key: "Te0P", name: "CPU efficiency core 3", type: .temperature, platforms: [.m3]),
        Sensor(key: "Te0S", name: "CPU efficiency core 4", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf04", name: "CPU performance core 1", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf09", name: "CPU performance core 2", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf0A", name: "CPU performance core 3", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf0B", name: "CPU performance core 4", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf0D", name: "CPU performance core 5", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf0E", name: "CPU performance core 6", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf44", name: "CPU performance core 7", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf49", name: "CPU performance core 8", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf4A", name: "CPU performance core 9", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf4B", name: "CPU performance core 10", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf4D", name: "CPU performance core 11", type: .temperature, platforms: [.m3]),
        Sensor(key: "Tf4E", name: "CPU performance core 12", type: .temperature, platforms: [.m3]),

        // M4
        Sensor(key: "Te05", name: "CPU efficiency core 1", type: .temperature, platforms: [.m4]),
        Sensor(key: "Te0S", name: "CPU efficiency core 2", type: .temperature, platforms: [.m4]),
        Sensor(key: "Te09", name: "CPU efficiency core 3", type: .temperature, platforms: [.m4]),
        Sensor(key: "Te0H", name: "CPU efficiency core 4", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp01", name: "CPU performance core 1", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp05", name: "CPU performance core 2", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp09", name: "CPU performance core 3", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp0D", name: "CPU performance core 4", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp0V", name: "CPU performance core 5", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp0Y", name: "CPU performance core 6", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp0b", name: "CPU performance core 7", type: .temperature, platforms: [.m4]),
        Sensor(key: "Tp0e", name: "CPU performance core 8", type: .temperature, platforms: [.m4]),

        // M5
        Sensor(key: "Tp00", name: "CPU super core 1", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp04", name: "CPU super core 2", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp08", name: "CPU super core 3", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0C", name: "CPU super core 4", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0G", name: "CPU super core 5", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0K", name: "CPU super core 6", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0O", name: "CPU performance core 1", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0R", name: "CPU performance core 2", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0U", name: "CPU performance core 3", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0X", name: "CPU performance core 4", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0a", name: "CPU performance core 5", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0d", name: "CPU performance core 6", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0g", name: "CPU performance core 7", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0j", name: "CPU performance core 8", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0m", name: "CPU performance core 9", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0p", name: "CPU performance core 10", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0u", name: "CPU performance core 11", type: .temperature, platforms: [.m5]),
        Sensor(key: "Tp0y", name: "CPU performance core 12", type: .temperature, platforms: [.m5]),

        // Power
        Sensor(key: "PSTR", name: "System total", type: .systemPower),
        Sensor(key: "PDTR", name: "DC in", type: .adapterPower),

        // Cooling
        Sensor(key: "FNum", name: "Fan count", type: .fanCount),
        Sensor(key: "F%Ac", name: "Fan %", type: .fan),
    ]

    static func keys(_ type: SensorType, for chip: ChipFamily) -> [String] {
        all.filter { $0.type == type && $0.platforms.contains(chip) }.map(\.key)
    }

    static func fanSpeed(count: Int, for chip: ChipFamily) -> [String] {
        let templates = keys(.fan, for: chip)
        return (0 ..< count).flatMap { index in
            templates.map { $0.replacingOccurrences(of: "%", with: String(index)) }
        }
    }
}

struct HardwareModel {
    let chip: ChipFamily

    static let current = HardwareModel()

    private init() {
        chip = Self.chipFamily(from: Self.sysctlString("machdep.cpu.brand_string"))
    }

    static func chipFamily(from brand: String) -> ChipFamily {
        let uppercased = brand.uppercased()
        
        for family in ChipFamily.allCases.reversed()
        where uppercased.range(of: "\\b\(family.rawValue)\\b", options: .regularExpression) != nil {
            return family
        }
        return .m1
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }

        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }

        return String(cBuffer: buffer)
    }
}

struct SensorsSnapshot {
    var cpuTemperature: Double = 0
    var fanSpeeds: [Int] = []
    var power: Int = 0
    var isOnBattery: Bool = false
    var isCharging: Bool = false

    static let unavailable = SensorsSnapshot()
}

final class SensorService {
    private let smc: SMCService?
    private let temperatureKeys: [String]
    private let fanKeys: [String]
    private let systemPowerKeys: [String]
    private let adapterPowerKeys: [String]

    let isAvailable: Bool
    let hasFans: Bool

    init() {
        let connection = try? SMCService()
        smc = connection

        guard let connection else {
            temperatureKeys = []
            fanKeys = []
            systemPowerKeys = []
            adapterPowerKeys = []
            isAvailable = false
            hasFans = false
            return
        }

        let chip = HardwareModel.current.chip
        temperatureKeys = connection.readableKeys(among: SMCKeys.keys(.temperature, for: chip))
        systemPowerKeys = SMCKeys.keys(.systemPower, for: chip)
        adapterPowerKeys = SMCKeys.keys(.adapterPower, for: chip)
        let fanCount = SMCKeys.keys(.fanCount, for: chip)
            .compactMap { connection.optionalValue(forKey: $0) }
            .first
            .map { max(0, Int($0)) } ?? 0
        fanKeys = SMCKeys.fanSpeed(count: fanCount, for: chip)
        isAvailable = !temperatureKeys.isEmpty
        hasFans = fanCount > 0
    }

    func read() -> SensorsSnapshot {
        guard let smc else { return .unavailable }

        var snapshot = SensorsSnapshot()
        snapshot.cpuTemperature = temperatureKeys.reduce(0) { max($0, smc.optionalValue(forKey: $1) ?? 0) }
        snapshot.fanSpeeds = fanKeys.map { Int(smc.optionalValue(forKey: $0) ?? 0) }
        let source = Self.powerState
        snapshot.isOnBattery = source.isOnBattery
        snapshot.isCharging = source.isCharging

        let system = watts(among: systemPowerKeys, smc)
        if snapshot.isOnBattery {
            snapshot.power = system ?? 0
        } else {
            snapshot.power = watts(among: adapterPowerKeys, smc) ?? system ?? 0
        }
        return snapshot
    }

    private func watts(among keys: [String], _ smc: SMCService) -> Int? {
        for key in keys {
            guard let value = smc.optionalValue(forKey: key) else { continue }
            let rounded = Int(value.rounded())
            if rounded > 0 { return rounded }
        }
        return nil
    }

    private static var powerState: (isOnBattery: Bool, isCharging: Bool) {
        guard let info = IOPSCopyPowerSourcesInfo() else { return (false, false) }
        let blob = info.takeRetainedValue()
        guard let list = IOPSCopyPowerSourcesList(blob) else { return (false, false) }

        for source in list.takeRetainedValue() as [CFTypeRef] {
            guard let entry = IOPSGetPowerSourceDescription(blob, source),
                  let description = entry.takeUnretainedValue() as? [String: Any] else { continue }

            return (description[kIOPSPowerSourceStateKey] as? String == kIOPSBatteryPowerValue,
                    description[kIOPSIsChargingKey] as? Bool ?? false)
        }
        return (false, false)
    }
}
