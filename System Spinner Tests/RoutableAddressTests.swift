//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Testing
@testable import System_Spinner

@Suite("Routable addresses")
struct RoutableAddressTests {
    private func ipv4(_ a: UInt32, _ b: UInt32, _ c: UInt32, _ d: UInt32) -> UInt32 {
        a << 24 | b << 16 | c << 8 | d
    }

    private func ipv6(_ text: String) -> [UInt8] {
        var address = in6_addr()
        #expect(inet_pton(AF_INET6, text, &address) == 1, "\(text) is not an address")
        return withUnsafeBytes(of: address) { Array($0) }
    }

    @Test("An address on a real network counts")
    func realAddressesCount() {
        #expect(NetworkMonitor.isRoutable(ipv4: ipv4(192, 168, 1, 40)))
        #expect(NetworkMonitor.isRoutable(ipv4: ipv4(172, 30, 212, 2)))
        #expect(NetworkMonitor.isRoutable(ipv4: ipv4(8, 8, 8, 8)))
        // Unique-local: private, but the address the machine really has.
        #expect(NetworkMonitor.isRoutable(ipv6: ipv6("fd6e:68b1:7040:4ce7::1")))
        #expect(NetworkMonitor.isRoutable(ipv6: ipv6("2a00:1450:4001:800::200e")))
    }

    @Test("Loopback is not an address the machine can be reached at")
    func loopbackDoesNotCount() {
        #expect(!NetworkMonitor.isRoutable(ipv4: ipv4(127, 0, 0, 1)))
        #expect(!NetworkMonitor.isRoutable(ipv4: ipv4(127, 44, 3, 9)))
        #expect(!NetworkMonitor.isRoutable(ipv6: ipv6("::1")))
    }

    @Test("Link-local is what is left when the network is gone")
    func linkLocalDoesNotCount() {
        // macOS keeps awdl0, llw0 and the utun tunnels running with nothing but
        // these, so taking one would report an address where there is none.
        #expect(!NetworkMonitor.isRoutable(ipv6: ipv6("fe80::1875:5aff:fe96:cedc")))
        #expect(!NetworkMonitor.isRoutable(ipv6: ipv6("fe80::1")))
        #expect(!NetworkMonitor.isRoutable(ipv6: ipv6("febf::1")))
        #expect(!NetworkMonitor.isRoutable(ipv4: ipv4(169, 254, 13, 7)))
    }
}
