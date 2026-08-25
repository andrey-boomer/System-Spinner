//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation

struct Throughput {
    enum Unit {
        case kilobytes, megabytes, gigabytes, terabytes

        var title: String {
            switch self {
            case .kilobytes: return localizedString("KB/s")
            case .megabytes: return localizedString("MB/s")
            case .gigabytes: return localizedString("GB/s")
            case .terabytes: return localizedString("TB/s")
            }
        }
    }

    let bytesPerSecond: Double

    static let zero = Throughput(bytesPerSecond: 0)

    var value: Double { scaled.value }
    var unit: Unit { scaled.unit }

    private var scaled: (value: Double, unit: Unit) {
        let kilobyte = 1024.0
        let megabyte = pow(kilobyte, 2)
        let gigabyte = pow(kilobyte, 3)
        let terabyte = pow(kilobyte, 4)

        switch bytesPerSecond {
        case terabyte...:
            return (bytesPerSecond / terabyte, .terabytes)
        case gigabyte ..< terabyte:
            return (bytesPerSecond / gigabyte, .gigabytes)
        case megabyte ..< gigabyte:
            return (bytesPerSecond / megabyte, .megabytes)
        default:
            return (bytesPerSecond / kilobyte, .kilobytes)
        }
    }
}

struct MemoryUsage {
    var used: Double = 0
    var pressure: Double = 0
    var app: Double = 0
    var compressed: Double = 0
    var inactive: Double = 0
    var swap: Int = 0

    static let empty = MemoryUsage()
}

struct NetworkUsage {
    var address: String = ""
    var inbound: Throughput = .zero
    var outbound: Throughput = .zero

    static let empty = NetworkUsage()
}

struct MetricsSnapshot {
    var cpuUsage: Double = 0
    var gpuUsage: Double = 0
    var memory: MemoryUsage = .empty
    var network: NetworkUsage = .empty
    var cpuHistory: [Double] = []
    var memoryHistory: [Double] = []
    var sensors: SensorsSnapshot = .unavailable

    static let empty = MetricsSnapshot()
}

func roundedTenth(_ value: Double) -> Double {
    (value * 10).rounded(.up) / 10
}

actor MetricsService {
    typealias Observer = @MainActor @Sendable (MetricsSnapshot) -> Void

    static let shared = MetricsService()
    nonisolated let sensorsAvailable: Bool
    nonisolated let hasFans: Bool

    private let cpu = CPUMonitor()
    private let gpu = GPUMonitor()
    private let memory = MemoryMonitor()
    private let processes = ProcessMonitor()
    private let network = NetworkMonitor()
    private let sensors: SensorService

    private var pollingTask: Task<Void, Never>?
    private var externalAddressTask: Task<Void, Never>?
    private var interval: TimeInterval = 1
    private var readsDetailedMetrics = false
    private var observers: [UUID: Observer] = [:]

    private(set) var snapshot: MetricsSnapshot = .empty

    private init() {
        let service = SensorService()
        sensors = service
        sensorsAvailable = service.hasTemperature
        hasFans = service.hasFans
    }

    func start(interval: TimeInterval) {
        self.interval = interval
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        externalAddressTask?.cancel()
        externalAddressTask = nil
    }

    func addObserver(_ token: UUID, _ observer: @escaping Observer) {
        observers[token] = observer
    }

    func removeObserver(_ token: UUID) {
        observers.removeValue(forKey: token)
    }

    func setDetailedMetricsEnabled(_ enabled: Bool) {
        readsDetailedMetrics = enabled

        guard enabled, sensors.isAvailable else { return }
        var updated = snapshot
        updated.sensors = sensors.read()
        publish(updated)
    }

    func topProcesses() -> [ProcessUsage] {
        processes.snapshot(systemCPUUsage: cpu.usage)
    }

    private func tick() {
        cpu.update()
        memory.update()
        network.update(interval: interval)
        resolveExternalAddressIfNeeded()

        gpu.update()

        var updated = MetricsSnapshot(
            cpuUsage: cpu.usage,
            gpuUsage: gpu.usage,
            memory: memory.usage,
            network: network.usage,
            cpuHistory: cpu.history,
            memoryHistory: memory.history
        )
        updated.sensors = readsDetailedMetrics && sensors.isAvailable ? sensors.read() : .unavailable

        publish(updated)
    }

    private func resolveExternalAddressIfNeeded() {
        guard network.needsExternalLookup, externalAddressTask == nil else { return }
        network.externalLookupStarted()

        externalAddressTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(NetworkMonitor.externalLookupDelay))
            let address = await NetworkMonitor.fetchExternalAddress()
            await self?.finishExternalLookup(address: address)
        }
    }

    private func finishExternalLookup(address: String?) {
        externalAddressTask = nil
        network.externalLookupFinished(address: address)
    }

    private func publish(_ snapshot: MetricsSnapshot) {
        self.snapshot = snapshot

        let handlers = Array(observers.values)
        guard !handlers.isEmpty else { return }

        Task { @MainActor in
            handlers.forEach { $0(snapshot) }
        }
    }
}
