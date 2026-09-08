//  Copyright © Takuto Nakamura, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import AppKit
import Darwin
import IOKit

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

struct MovingAverage {
    private let window: Int
    private var values: [Double] = []
    private var sum: Double = 0

    init(window: Int) {
        self.window = window
    }

    mutating func add(_ value: Double) -> Double {
        values.append(value)
        sum += value
        if values.count > window {
            sum -= values.removeFirst()
        }
        return roundedTenth(sum / Double(values.count))
    }
}

struct History {
    private let capacity: Int
    private(set) var values: [Double] = []

    init(capacity: Int = 900) {
        self.capacity = capacity
    }

    mutating func append(_ value: Double) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst()
        }
    }
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
        let delay = network.pendingLookupDelay
        network.externalLookupStarted()

        externalAddressTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
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

let machHost = mach_host_self()

final class CPUMonitor {
    private var previous = host_cpu_load_info()
    private var smoothed = MovingAverage(window: 15)
    private var detailed = History()

    private(set) var usage: Double = 0
    var history: [Double] { detailed.values }

    func update() {
        let load = currentLoad()
        let user = Double(load.cpu_ticks.0 - previous.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 - previous.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 - previous.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 - previous.cpu_ticks.3)
        previous = load

        let total = user + system + idle + nice
        guard total > 0 else { return }

        let current = roundedTenth(min(99.9, 100.0 * (system + user) / total))

        detailed.append(current)
        usage = smoothed.add(current)
    }

    private func currentLoad() -> host_cpu_load_info {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(machHost, HOST_CPU_LOAD_INFO, $0, &count)
            }
        }

        guard result == KERN_SUCCESS else { return previous }
        return info
    }
}

final class GPUMonitor {
    private var service: io_service_t = 0
    private var smoothed = MovingAverage(window: 5)

    private(set) var usage: Double = 0

    deinit {
        if service != 0 { IOObjectRelease(service) }
    }

    func update() {
        usage = smoothed.add(currentUtilization() ?? 0)
    }

    private func currentUtilization() -> Double? {
        if service == 0 { connect() }
        guard service != 0 else { return nil }

        guard let property = IORegistryEntryCreateCFProperty(service,
                                                             "PerformanceStatistics" as CFString,
                                                             kCFAllocatorDefault, 0),
              let performance = property.takeRetainedValue() as? [String: Any],
              let utilization = performance["Device Utilization %"] as? Int64 else {
            return nil
        }
        return Double(utilization)
    }

    private func connect() {
        guard let matching = IOServiceMatching("AGXAccelerator") else { return }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == kIOReturnSuccess else { return }
        defer { IOObjectRelease(iterator) }

        service = IOIteratorNext(iterator)

        var extra = IOIteratorNext(iterator)
        while extra != 0 {
            IOObjectRelease(extra)
            extra = IOIteratorNext(iterator)
        }
    }
}

final class MemoryMonitor {

    static let totalMemory: Double = {
        var size = mach_msg_type_number_t(MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
        var info = host_basic_info_data_t()

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_info(machHost, HOST_BASIC_INFO, $0, &size)
            }
        }

        guard result == KERN_SUCCESS, info.max_mem > 0 else { return 1 }
        return Double(info.max_mem) / 1_073_741_824
    }()

    private var detailed = History()

    private(set) var usage: MemoryUsage = .empty
    var history: [Double] { detailed.values }

    func update() {
        guard let statistics = vmStatistics() else { return }

        let unit = Double(sysconf(_SC_PAGESIZE)) / 1_073_741_824
        let total = Self.totalMemory

        let active = Double(statistics.active_count) * unit
        let speculative = Double(statistics.speculative_count) * unit
        let inactive = Double(statistics.inactive_count) * unit
        let wired = Double(statistics.wire_count) * unit
        let compressed = Double(statistics.compressor_page_count) * unit
        let purgeable = Double(statistics.purgeable_count) * unit
        let external = Double(statistics.external_page_count) * unit
        let used = active + inactive + speculative + wired + compressed - purgeable - external

        usage = MemoryUsage(
            used: roundedTenth(min(99.9, 100.0 * used / total)),
            pressure: roundedTenth(100.0 * (wired + compressed) / total),
            app: roundedTenth(100.0 * (used - wired - compressed) / total),
            compressed: roundedTenth(compressed),
            inactive: roundedTenth(100.0 * inactive / total),
            swap: swapUsage()
        )

        detailed.append(usage.used)
    }

    private func vmStatistics() -> vm_statistics64? {
        var size = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        var info = vm_statistics64_data_t()

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                host_statistics64(machHost, HOST_VM_INFO64, $0, &size)
            }
        }

        return result == KERN_SUCCESS ? info : nil
    }

    private func swapUsage() -> Int {
        var mib = [CTL_VM, VM_SWAPUSAGE]
        var size = MemoryLayout<xsw_usage>.size
        var usage = xsw_usage()

        guard sysctl(&mib, 2, &usage, &size, nil, 0) == 0, usage.xsu_total > 0 else { return 0 }

        let percent = Double(usage.xsu_used) / Double(usage.xsu_total) * 100
        return percent.isFinite ? Int(percent) : 0
    }
}

final class NetworkMonitor {
    private var previousInBytes: UInt64 = 0
    private var previousOutBytes: UInt64 = 0
    private var hasBaseline = false
    private var localAddress = ""
    private var externalAddress = ""
    private var isLookingUpExternalAddress = false
    private var wasResolvingExternalAddress = true
    private var externalRetryAttempt = 0
    private var externalRetryDate: Date?

    private(set) var usage: NetworkUsage = .empty
    private(set) var needsExternalLookup = false

    private(set) var pendingLookupDelay: TimeInterval = NetworkMonitor.externalLookupDelays[0]

    private static let externalAddressURL = URL(string: "https://checkip.dyndns.org")!
    static let externalLookupDelays: [TimeInterval] = [15, 15 * 60, 30 * 60, 60 * 60]

    func update(interval: TimeInterval) {
        let counters = interfaceCounters()
        let resolvesExternalAddress = Preferences.shared.showsExternalAddress

        if !resolvesExternalAddress {
            externalAddress = ""
            cancelExternalRetries()
        }

        if counters.address != localAddress {
            localAddress = counters.address
            externalAddress = ""
            cancelExternalRetries()
            requestExternalLookup(if: resolvesExternalAddress)
        } else if resolvesExternalAddress, !wasResolvingExternalAddress {
            cancelExternalRetries()
            requestExternalLookup(if: true)
        } else if resolvesExternalAddress, let retryDate = externalRetryDate, Date() >= retryDate {
            externalRetryDate = nil
            requestExternalLookup(if: true, delay: 0)
        }

        wasResolvingExternalAddress = resolvesExternalAddress

        let seconds = max(interval, 0.001)
        let inbound = hasBaseline && counters.inBytes >= previousInBytes
            ? Double(counters.inBytes - previousInBytes) / seconds : 0
        let outbound = hasBaseline && counters.outBytes >= previousOutBytes
            ? Double(counters.outBytes - previousOutBytes) / seconds : 0

        previousInBytes = counters.inBytes
        previousOutBytes = counters.outBytes
        hasBaseline = true

        usage = NetworkUsage(
            address: externalAddress.isEmpty ? localAddress : externalAddress,
            inbound: Throughput(bytesPerSecond: inbound),
            outbound: Throughput(bytesPerSecond: outbound)
        )
    }

    private func requestExternalLookup(if enabled: Bool, delay: TimeInterval = NetworkMonitor.externalLookupDelays[0]) {
        guard enabled, !isLookingUpExternalAddress else { return }
        isLookingUpExternalAddress = true
        needsExternalLookup = true
        pendingLookupDelay = delay
    }

    func externalLookupStarted() {
        needsExternalLookup = false
    }

    func externalLookupFinished(address: String?) {
        isLookingUpExternalAddress = false

        guard Preferences.shared.showsExternalAddress else {
            cancelExternalRetries()
            return
        }

        guard let address else {
            scheduleExternalRetry()
            return
        }

        cancelExternalRetries()
        externalAddress = address
    }

    private func scheduleExternalRetry() {
        externalRetryAttempt += 1
        guard externalRetryAttempt < Self.externalLookupDelays.count else { return }
        externalRetryDate = Date().addingTimeInterval(Self.externalLookupDelays[externalRetryAttempt])
    }

    private func cancelExternalRetries() {
        externalRetryAttempt = 0
        externalRetryDate = nil
    }

    static func fetchExternalAddress() async -> String? {
        guard let (data, _) = try? await URLSession.shared.data(from: externalAddressURL) else { return nil }
        return parseExternalAddress(from: data)
    }

    private func interfaceCounters() -> (inBytes: UInt64, outBytes: UInt64, address: String) {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0
        var active = ""
        var foundIPv4 = false

        guard getifaddrs(&addresses) == 0 else { return (0, 0, active) }
        defer { freeifaddrs(addresses) }

        var pointer = addresses
        while pointer != nil {
            defer { pointer = pointer?.pointee.ifa_next }
            guard let interface = pointer?.pointee, let address = interface.ifa_addr else { continue }

            let family = address.pointee.sa_family
            let flags = Int32(interface.ifa_flags)

            if family == UInt8(AF_LINK), let data = interface.ifa_data {
                let statistics = data.assumingMemoryBound(to: if_data.self).pointee
                totalIn += UInt64(statistics.ifi_ibytes)
                totalOut += UInt64(statistics.ifi_obytes)
            }

            guard (flags & (IFF_UP | IFF_RUNNING | IFF_LOOPBACK)) == (IFF_UP | IFF_RUNNING),
                  family == UInt8(AF_INET) || family == UInt8(AF_INET6),
                  Self.isRoutable(address) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len),
                              &hostname, socklen_t(hostname.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }

            if family == UInt8(AF_INET) {
                active = String(cBuffer: hostname)
                foundIPv4 = true
            } else if !foundIPv4 {
                active = String(cBuffer: hostname)
            }
        }

        return (totalIn, totalOut, active)
    }

    private static func isRoutable(_ address: UnsafeMutablePointer<sockaddr>) -> Bool {
        switch Int32(address.pointee.sa_family) {
        case AF_INET:
            let value = address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
            }
            return isRoutable(ipv4: value)
        case AF_INET6:
            let bytes = address.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                withUnsafeBytes(of: pointer.pointee.sin6_addr) { Array($0) }
            }
            return isRoutable(ipv6: bytes)
        default:
            return false
        }
    }

    static func isRoutable(ipv4 address: UInt32) -> Bool {
        address >> 24 != 127 && address >> 16 != 0xA9FE
    }

    static func isRoutable(ipv6 address: [UInt8]) -> Bool {
        guard address.count == 16 else { return false }
        guard !(address[0] == 0xFE && address[1] & 0xC0 == 0x80) else { return false }

        return address != Array(repeating: 0, count: 15) + [1]
    }

    static func parseExternalAddress(from data: Data) -> String? {
        guard let html = String(data: data, encoding: .utf8),
              let range = html.range(of: "Current IP Address: ") else { return nil }

        let address = html[range.upperBound...]
            .components(separatedBy: "<").first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return address.isEmpty ? nil : address
    }
}

struct ProcessUsage: Identifiable {
    let pid: Int
    let name: String
    let cpu: Double
    let memory: Double
    let memoryText: String

    var id: Int { pid }

    var icon: NSImage {
        if let application = NSRunningApplication(processIdentifier: pid_t(pid)), let icon = application.icon {
            return icon
        }
        return NSWorkspace.shared.icon(forFile: "/bin/bash")
    }
}

final class ProcessMonitor {
    private var previousCPUTimes: [pid_t: UInt64] = [:]
    private var cached: [ProcessUsage] = []

    private static let pathInfoMaxSize: Int32 = 4096
    private static let taskInfoFlavor: Int32 = 4
    private static let bsdInfoFlavor: Int32 = 3

    func snapshot(systemCPUUsage: Double) -> [ProcessUsage] {
        let pidCount = proc_listallpids(nil, 0)
        guard pidCount > 0 else { return cached }

        var pids = [pid_t](repeating: 0, count: Int(pidCount))
        let listed = proc_listallpids(&pids, Int32(pidCount) * Int32(MemoryLayout<pid_t>.size))
        guard listed > 0 else { return cached }

        let totalMemory = MemoryMonitor.totalMemory
        var currentCPUTimes: [pid_t: UInt64] = [:]
        var candidates: [(pid: pid_t, name: String, cpuTime: Double, memory: Double, memoryText: String)] = []

        for index in 0 ..< Int(listed) {
            let pid = pids[index]
            guard pid > 0 else { continue }

            var task = proc_taskinfo()
            let taskSize = MemoryLayout<proc_taskinfo>.size
            guard proc_pidinfo(pid, Self.taskInfoFlavor, 0, &task, Int32(taskSize)) == Int32(taskSize) else { continue }
            guard let name = processName(for: pid), name != "WindowServer" else { continue }

            let cpuTime = task.pti_total_user + task.pti_total_system
            currentCPUTimes[pid] = cpuTime

            var delta: Double = 0
            if let previous = previousCPUTimes[pid], cpuTime > previous {
                delta = Double(cpuTime - previous) / 1_000_000_000.0
            }

            let residentBytes = Double(task.pti_resident_size)
            let memoryPercent = residentBytes / (totalMemory * 1024 * 1024 * 1024) * 100.0

            guard delta > 0 || memoryPercent > 0.1 else { continue }

            candidates.append((pid, name, delta, memoryPercent,
                               String(format: "%.1f MB", residentBytes / (1024 * 1024))))
        }

        previousCPUTimes = currentCPUTimes

        let totalCPUTime = candidates.reduce(0.0) { $0 + $1.cpuTime }
        var processes: [ProcessUsage] = []

        for candidate in candidates {
            let cpu = totalCPUTime > 0 ? candidate.cpuTime / totalCPUTime * systemCPUUsage : 0
            guard cpu > 0.05 || candidate.memory > 0.1 else { continue }

            processes.append(ProcessUsage(pid: Int(candidate.pid),
                                          name: candidate.name,
                                          cpu: roundedTenth(cpu),
                                          memory: roundedTenth(candidate.memory),
                                          memoryText: candidate.memoryText))
        }

        cached = processes.sorted { $0.cpu > $1.cpu }
        return cached
    }

    private func processName(for pid: pid_t) -> String? {
        var pathBuffer = [CChar](repeating: 0, count: Int(Self.pathInfoMaxSize))
        if proc_pidpath(pid, &pathBuffer, UInt32(Self.pathInfoMaxSize)) > 0 {
            return (String(cBuffer: pathBuffer) as NSString).lastPathComponent
        }

        var bsd = proc_bsdinfo()
        let bsdSize = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, Self.bsdInfoFlavor, 0, &bsd, Int32(bsdSize)) == Int32(bsdSize) else { return nil }

        return withUnsafeBytes(of: &bsd.pbi_comm) { bytes in
            guard let base = bytes.bindMemory(to: CChar.self).baseAddress else { return nil }
            return String(cString: base)
        }
    }
}
