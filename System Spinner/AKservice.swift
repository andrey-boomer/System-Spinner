//
//  AKservice.swift
//  System Spinner
//
//  Copyright 2024 Andrey Lysikov
//  Copyright 2020 Takuto Nakamura
//  SPDX-License-Identifier: Apache-2.0
//  Based on https://github.com/Kyome22/ActivityKit

import Foundation
import Darwin
import SystemConfiguration

class AKservice {

    private let loadInfoCount = UInt32(exactly: MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size)!
    private let hostVmInfo64Count = UInt32(exactly: MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)!
    private let hostBasicInfoCount = UInt32(exactly: MemoryLayout<host_basic_info_data_t>.size / MemoryLayout<integer_t>.size)!
    private var loadPrevious = host_cpu_load_info()
    private var previousUpload: Int64 = 0
    private var previousDownload: Int64 = 0

    public struct netPacketData {
        public var value: Double
        public var unit: String
    }
    
    public var cpuPercentage: Double = 0.0
    public var memPercentage: Double = 0.0
    public var memPressure: Double = 0.0
    public var memApp: Double = 0.0
    public var memWired: Double = 0.0
    public var memCompressed: Double = 0.0
    public var netIp: String = "no ip found"
    public var netIn = netPacketData(value: 0.0, unit: "KB/s")
    public var netOut = netPacketData(value: 0.0, unit: "KB/s")
    
    init() {
        
    }
    
    private func round(In: Double) -> Double {
        return Double(ceil(In * 10) / 10.0)
    }
    
    private func hostCPULoadInfo() -> host_cpu_load_info {
        var size: mach_msg_type_number_t = loadInfoCount
        let hostInfo = host_cpu_load_info_t.allocate(capacity: 1)
        let _ = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { (pointer) -> kern_return_t in
            return host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, pointer, &size)
        }
        let data = hostInfo.move()
        hostInfo.deallocate()
        return data
    }
    
    private var vmStatistics64: vm_statistics64 {
        var size: mach_msg_type_number_t = hostVmInfo64Count
        let hostInfo = vm_statistics64_t.allocate(capacity: 1)
        let _ = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { (pointer) -> kern_return_t in
            return host_statistics64(mach_host_self(), HOST_VM_INFO64, pointer, &size)
        }
        let data = hostInfo.move()
        hostInfo.deallocate()
        return data
    }
    
    private var maxMemory: Double {
        var size: mach_msg_type_number_t = hostBasicInfoCount
        let hostInfo = host_basic_info_t.allocate(capacity: 1)
        let _ = hostInfo.withMemoryRebound(to: integer_t.self, capacity: Int()) { (pointer) -> kern_return_t in
            return host_info(mach_host_self(), HOST_BASIC_INFO, pointer, &size)
        }
        let data = hostInfo.move()
        hostInfo.deallocate()
        return Double(data.max_mem) / 1073741824
    }
    
    private func getDefaultNetworkDevice() -> String {
        let processName = ProcessInfo.processInfo.processName as CFString
        let dynamicStore = SCDynamicStoreCreate(kCFAllocatorDefault, processName, nil, nil)
        let ipv4Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(kCFAllocatorDefault,
                                                                 kSCDynamicStoreDomainState,
                                                                 kSCEntNetIPv4)
        guard let list = SCDynamicStoreCopyValue(dynamicStore, ipv4Key) as? [CFString: Any],
              let interface = list[kSCDynamicStorePropNetPrimaryInterface] as? String
        else {
            return ""
        }
        return interface
    }
    
    private func getBytesInfo(_ id: String, _ pointer: UnsafeMutablePointer<ifaddrs>) -> (up: Int64, down: Int64)? {
        let name = String(cString: pointer.pointee.ifa_name)
        if name == id {
            let addr = pointer.pointee.ifa_addr.pointee
            guard addr.sa_family == UInt8(AF_LINK) else { return nil }
            var data: UnsafeMutablePointer<if_data>? = nil
            data = unsafeBitCast(pointer.pointee.ifa_data,
                                 to: UnsafeMutablePointer<if_data>.self)
            return (up: Int64(data?.pointee.ifi_obytes ?? 0),
                    down: Int64(data?.pointee.ifi_ibytes ?? 0))
        }
        return nil
    }
    
    private func getIPAddress(_ id: String,_ pointer: UnsafeMutablePointer<ifaddrs>) -> String? {
        let name = String(cString: pointer.pointee.ifa_name)
        if name == id {
            var addr = pointer.pointee.ifa_addr.pointee
            guard addr.sa_family == UInt8(AF_INET) else { return nil }
            var ip = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(&addr, socklen_t(addr.sa_len), &ip,
                        socklen_t(ip.count), nil, socklen_t(0), NI_NUMERICHOST)
            return String(cString: ip)
        }
        return nil
    }
    
    private func convert(byte: Double) -> netPacketData {
        let KB: Double = 1024
        let MB: Double = pow(KB, 2)
        let GB: Double = pow(KB, 3)
        let TB: Double = pow(KB, 4)
        if TB <= byte {
            return netPacketData(value: round(In: byte / TB), unit: "TB/s")
        } else if GB <= byte {
            return netPacketData(value: round(In: byte / GB), unit: "GB/s")
        } else if MB <= byte {
            return netPacketData(value: round(In: byte / MB), unit: "MB/s")
        } else {
            return netPacketData(value: round(In: byte / KB), unit: "KB/s")
        }
    }
    
    public func update(Interval: Double) {
 
        // Update CPU Data
        let load = hostCPULoadInfo()
        let userDiff    = Double(load.cpu_ticks.0 - loadPrevious.cpu_ticks.0)
        let systemDiff  = Double(load.cpu_ticks.1 - loadPrevious.cpu_ticks.1)
        let idleDiff    = Double(load.cpu_ticks.2 - loadPrevious.cpu_ticks.2)
        let niceDiff    = Double(load.cpu_ticks.3 - loadPrevious.cpu_ticks.3)
        let totalTicks  = systemDiff + userDiff + idleDiff + niceDiff
        loadPrevious    = load
        cpuPercentage = round(In: min(99.9, ((100.0 * systemDiff / totalTicks) + (100.0 * userDiff / totalTicks))))
        
        // Update MEM Data
        let maxMem = maxMemory
        let memLoad = vmStatistics64

        let unit        = Double(vm_kernel_page_size) / 1073741824
        let active      = Double(memLoad.active_count) * unit
        let speculative = Double(memLoad.speculative_count) * unit
        let inactive    = Double(memLoad.inactive_count) * unit
        let wired       = Double(memLoad.wire_count) * unit
        let compressed  = Double(memLoad.compressor_page_count) * unit
        let purgeable   = Double(memLoad.purgeable_count) * unit
        let external    = Double(memLoad.external_page_count) * unit
        let using       = active + inactive + speculative + wired + compressed - purgeable - external
        
        memPercentage = round(In: min(99.9, (100.0 * using / maxMem)))
        memPressure   = round(In: 100.0 * (wired + compressed) / maxMem)
        memApp        = round(In: using - wired - compressed)
        memWired      = round(In: wired)
        memCompressed = round(In: compressed)
                              
        // Update NET Data
        let netId = getDefaultNetworkDevice()
        if netId.isEmpty {
            netIp = "no ip found"
            netIn = netPacketData(value: 0.0, unit: "KB/s")
            netOut = netPacketData(value: 0.0, unit: "KB/s")
        } else {
            var ifaddr: UnsafeMutablePointer<ifaddrs>? = nil
            getifaddrs(&ifaddr)
            
            var pointer = ifaddr
            var upload: Int64 = 0
            var download: Int64 = 0
            while pointer != nil {
                defer { pointer = pointer?.pointee.ifa_next }
                if let info = getBytesInfo(netId, pointer!) {
                    upload += info.up
                    download += info.down
                }
                if let ip = getIPAddress(netId, pointer!) {
                    if netIp != ip {
                        previousUpload = 0
                        previousDownload = 0
                    }
                    netIp = ip
                }
            }
            freeifaddrs(ifaddr)
            if previousUpload != 0 && previousDownload != 0 {
                netIn = convert(byte: Double(upload - previousUpload) / Interval)
                netOut = convert(byte: Double(download - previousDownload) / Interval)
            }
            previousUpload = upload
            previousDownload = download
        }
    }
    
}
