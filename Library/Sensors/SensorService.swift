//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import IOKit
import IOKit.ps

enum SensorType {
    case fanCount
    case fan
    case systemPower
    case adapterPower
}

struct Sensor {
    let key: String
    let name: String
    let type: SensorType
}

enum SMCKeys {
    static let all: [Sensor] = [
        Sensor(key: "PSTR", name: "System total", type: .systemPower),
        Sensor(key: "PDTR", name: "DC in", type: .adapterPower),
        Sensor(key: "FNum", name: "Fan count", type: .fanCount),
        Sensor(key: "F%Ac", name: "Fan %", type: .fan),
    ]

    static func keys(_ type: SensorType) -> [String] {
        all.filter { $0.type == type }.map(\.key)
    }

    static func fanSpeed(count: Int) -> [String] {
        let templates = keys(.fan)
        return (0 ..< count).flatMap { index in
            templates.map { $0.replacingOccurrences(of: "%", with: String(index)) }
        }
    }
}

struct SensorsSnapshot {
    var cpuTemperature: Double = 0
    var fanSpeeds: [Int] = []
    var power: Int = 0
    var isOnBattery: Bool = false
    var isCharging: Bool = false
    var batteryTemperature: Double = 0

    static let unavailable = SensorsSnapshot()
}

final class SensorService {
    private let smc: SMCService?
    private let temperatureKeys: [String]
    private let fanKeys: [String]
    private var history: [Reading] = []
    private let systemPowerKeys: [String]
    private let adapterPowerKeys: [String]
    let isAvailable: Bool
    let hasTemperature: Bool
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
            hasTemperature = false
            hasFans = false
            return
        }

        temperatureKeys = Self.processorSensors(of: connection)
        systemPowerKeys = SMCKeys.keys(.systemPower)
        adapterPowerKeys = SMCKeys.keys(.adapterPower)

        let fanCount = SMCKeys.keys(.fanCount)
            .compactMap { connection.optionalValue(forKey: $0) }
            .first
            .map { max(0, Int($0)) } ?? 0
        fanKeys = SMCKeys.fanSpeed(count: fanCount)
        isAvailable = true
        hasTemperature = !temperatureKeys.isEmpty
        hasFans = fanCount > 0
    }

    func read() -> SensorsSnapshot {
        guard let smc else { return .unavailable }

        var snapshot = SensorsSnapshot()
        let readings = temperatureKeys.compactMap { smc.optionalValue(forKey: $0) }
        let now = Date()
        history.append(Reading(time: now, value: Self.mean(of: readings)))
        history = Self.recent(history, at: now)
        snapshot.cpuTemperature = Self.mean(of: history.map(\.value))
        snapshot.fanSpeeds = fanKeys.map { Int(smc.optionalValue(forKey: $0) ?? 0) }
        let source = Self.powerState
        snapshot.isOnBattery = source.isOnBattery

        let system = watts(among: systemPowerKeys, smc)
        guard !snapshot.isOnBattery else {
            snapshot.power = system ?? 0
            snapshot.isCharging = false
            return snapshot
        }

        let adapter = watts(among: adapterPowerKeys, smc)
        snapshot.power = adapter ?? system ?? 0

        let intoBattery = (adapter ?? 0) - (system ?? 0)
        snapshot.isCharging = source.isCharging || intoBattery >= Self.chargingThreshold
        if snapshot.isCharging {
            snapshot.batteryTemperature = Self.batteryTemperature()
        }

        return snapshot
    }

    private static let processorPrefix = "Tp"
    private static let plausibleTemperature: ClosedRange<Double> = 5 ... 120

    private static func processorSensors(of smc: SMCService) -> [String] {
        smc.allKeys()
            .filter { $0.hasPrefix(processorPrefix) }
            .filter { key in
                guard let value = smc.optionalValue(forKey: key) else { return false }
                return plausibleTemperature.contains(value)
            }
    }

    static let smoothingWindow: TimeInterval = 5

    struct Reading {
        let time: Date
        let value: Double
    }

    nonisolated static func recent(_ readings: [Reading], at now: Date) -> [Reading] {
        readings.filter { now.timeIntervalSince($0.time) <= smoothingWindow }
    }

    nonisolated static func mean(of values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    private static func batteryTemperature() -> Double {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != IO_OBJECT_NULL else { return 0 }
        defer { IOObjectRelease(service) }

        let property = IORegistryEntryCreateCFProperty(service, "Temperature" as CFString, kCFAllocatorDefault, 0)
        guard let hundredths = property?.takeRetainedValue() as? Int else { return 0 }

        return Double(hundredths) / 100
    }

    private static let chargingThreshold = 5

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
