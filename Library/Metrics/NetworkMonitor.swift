//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Darwin
import Foundation

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
