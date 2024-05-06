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
import Cocoa
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
    
    public struct topProcess: Codable {
        public var pid: Int
        public var name: String
        public var cpu: Double
        public var mem: Double
        
        public var icon: NSImage {
            get {
                if let app = NSRunningApplication(processIdentifier: pid_t(self.pid)), let icon = app.icon {
                    return icon
                }
                return NSWorkspace.shared.icon(forFile: "/bin/bash")
            }
        }
    }
    
    public var cpuPercentage: Double = 0.0
    public var cpuUser: Double = 0.0
    public var cpuSystem: Double = 0.0
    public var cpuIdle: Double = 0.0
    public var cpuNiceD: Double = 0.0
    public var cpuProcess: [topProcess] = []
    
    public var memPercentage: Double = 0.0
    public var memPressure: Double = 0.0
    public var memApp: Double = 0.0
    public var memWired: Double = 0.0
    public var memCompressed: Double = 0.0
    public var netIp: String = "no ip found"
    public var netIn = netPacketData(value: 0.0, unit: "KB/s")
    public var netOut = netPacketData(value: 0.0, unit: "KB/s")
        
    private func round(In: Double) -> Double {
        return Double(ceil(In * 10) / 10.0)
    }
    
    private func hostCPULoadInfo() -> host_cpu_load_info {
        var info = host_cpu_load_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info, {
          host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0.withMemoryRebound(to: integer_t.self, capacity: 1, { $0 }), &count)
        })
        
        guard kerr == KERN_SUCCESS else {
          return host_cpu_load_info()
        }
        
        return info
    }
    
    public func getTopProcess() -> [topProcess] {
        let task = Process()
        task.launchPath = "/bin/ps"
        task.arguments = ["-Aceo pid,pcpu,pmem,comm", "-r"]
        
        let outputPipe = Pipe()
        task.standardOutput = outputPipe
        
        task.launch()
      
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        task.waitUntilExit()
        
        var processes: [topProcess] = []
        output.enumerateLines { (line, stop) -> Void in
                let str = line.trimmingCharacters(in: .whitespaces)
                let pidFind = str.findAndCrop(pattern: "^\\d+")
                let usageFindCpu = pidFind.remain.findAndCrop(pattern: "^[0-9,.]+ ")
                let usageFindMem = usageFindCpu.remain.findAndCrop(pattern: "^[0-9,.]+ ")
                let command = usageFindMem.remain.trimmingCharacters(in: .whitespaces)
                let usagePCPU = Double(usageFindCpu.cropped.replacingOccurrences(of: ",", with: ".")) ?? 0
                let usagePMEM = Double(usageFindMem.cropped.replacingOccurrences(of: ",", with: ".")) ?? 0
                
                if let pid = Int(pidFind.cropped) {
                    processes.append(topProcess(pid: pid, name: command, cpu: usagePCPU, mem: usagePMEM))
                }
        }
        
        return processes
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
    
    public func updateCpuOnly() {
        let load = hostCPULoadInfo()
        cpuUser = Double(load.cpu_ticks.0 - loadPrevious.cpu_ticks.0)
        cpuSystem = Double(load.cpu_ticks.1 - loadPrevious.cpu_ticks.1)
        cpuIdle = Double(load.cpu_ticks.2 - loadPrevious.cpu_ticks.2)
        cpuNiceD =  Double(load.cpu_ticks.3 - loadPrevious.cpu_ticks.3)
        
        let totalTicks  = cpuUser + cpuSystem + cpuIdle + cpuNiceD
        
        loadPrevious    = load
        cpuPercentage = round(In: min(99.9, ((100.0 * cpuSystem / totalTicks) + (100.0 * cpuUser / totalTicks))))
    }
    
    public func updateAll() {
        
        // Update CPU Data
        updateCpuOnly()
              
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
                netIn = convert(byte: Double(upload - previousUpload))
                netOut = convert(byte: Double(download - previousDownload))
            }
            previousUpload = upload
            previousDownload = download
        }
    }
    
}

extension String: LocalizedError {
    public func findAndCrop(pattern: String) -> (cropped: String, remain: String) {
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(self.startIndex..., in: self)
            
            if let match = regex.firstMatch(in: self, options: [], range: range) {
                if let range = Range(match.range, in: self) {
                    let cropped = String(self[range]).trimmingCharacters(in: .whitespaces)
                    let remaining = self.replacingOccurrences(of: cropped, with: "", options: .regularExpression).trimmingCharacters(in: .whitespaces)
                    return (cropped, remaining)
                }
            }
        } catch {
            print("Error creating regex: \(error.localizedDescription)")
        }
        
        return ("", self)
    }
}

extension Sequence {
    func sorted<T: Comparable>(by keyPath: KeyPath<Element, T>) -> [Element] {
        sorted { a, b in
            a[keyPath: keyPath] > b[keyPath: keyPath]
        }
    }
}
