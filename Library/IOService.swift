//  Copyright 2025 Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation

class IOServiceData {
    private var con: io_connect_t = 0
    private var cpuTempKeys: [String] = []
    private var gpuTempKeys: [String] = []
    private var fanTempKeys: [String] = []
    private var fanSpeedKeys:  [String] = []
    private var systemPowerKeys: [String] = []
    private var systemAdapterKeys: [String] = []
    private var systemBatteryKeys: [String] = []
    private let dateFormatter = DateFormatter()
    private let KERNEL_INDEX_SMC: UInt32 = 2
    private let SMC_CMD_READ_BYTES: UInt8 = 5
    private let SMC_CMD_READ_KEYINFO: UInt8 = 9
    public var isAir: Bool = false
    public var presentSMC: Bool = true
    
    private let SensorsList: [String: [String:[String]]]  = [
        // imported from https://raw.githubusercontent.com/exelban/stats/refs/heads/master/Modules/Sensors/values.swift
        "DEFAULT": [
            "CPU": ["TC0D","TC0E","TC0F","TC0H","TC0P","TCAD"],
            "GPU": ["TCGC","TG0D","TGDD","TG0H","TG0P","PCPG","PCGC","PCGM"],
            "FAN": ["TaLP", "TaRF"],
            "FAN SPEED": ["F0Ac", "F1Ac"],
            "POWER": ["PSTR"],
            "BATTERY": ["PPBR"],
            "ADAPTER": ["PDTR"]
        ],
        "M1": [
            "CPU": ["Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b"],
            "GPU": ["Tg05", "Tg0D", "Tg0L" ,"Tg0T"],
        ],
        "M2": [
            "CPU": ["Tp1h", "Tp1t", "Tp1p", "Tp1l", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j"],
            "GPU": ["Tg0f", "Tg0j"],
        ],
        "M3": [
            "CPU": ["Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
            "GPU": ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"],
        ],
        "M4": [
            "CPU": ["Te05", "Te0S", "Te09", "Te0H", "Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e"],
            "GPU": ["Tg0G", "Tg0H", "Tg1U", "Tg1k", "Tg0K", "Tg0L", "Tg0d", "Tg0e", "Tg0j", "Tg0k"],
        ]
    ]
    
    // data for translate
    public var cpuTemp: Double = 0.0
    public var gpuTemp: Double = 0.0
    public var fanTemp: Double = 0.0
    public var fanSpeed: [Int] = []
    public var systemPower: Int = 0
    public var systemAdapter: Int = 0
    public var systemBattery: Int = 0
    
    private struct AppleSMCVers { // 6 bytes
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }
    
    private struct AppleSMCLimit { // 16 bytes
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var mem: UInt32 = 0
    }
    
    private struct AppleSMCInfo { // 9+3=12 bytes
        var size: UInt32 = 0
        var type = AppleSMC4Chars()
        var attribute: UInt8 = 0
        var unused1: UInt8 = 0
        var unused2: UInt8 = 0
        var unused3: UInt8 = 0
    }
    
    private struct AppleSMCBytes { // 32 bytes
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
    }
    enum MyError: Error {
        case iokit(kern_return_t)
        case string(String)
    }
    
    private struct AppleSMC4Chars {  // 4 bytes
        var chars: (UInt8, UInt8, UInt8, UInt8) = (0,0,0,0)
        init() {
        }
        init(chars: (UInt8, UInt8, UInt8, UInt8)) {
            self.chars = chars
        }
        init(_ string: String) throws {
            // This looks silly but I don't know a better solution
            guard string.lengthOfBytes(using: .utf8) == 4 else { throw MyError.string("Sensor name \(string) must be 4 characters long")}
            chars.0 = string.utf8.reversed()[0]
            chars.1 = string.utf8.reversed()[1]
            chars.2 = string.utf8.reversed()[2]
            chars.3 = string.utf8.reversed()[3]
        }
    }
    
    private struct AppleSMCKey {
        var key = AppleSMC4Chars()
        var vers = AppleSMCVers()
        var limit = AppleSMCLimit()
        var info = AppleSMCInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = AppleSMCBytes()
    }
    
    private func process(path: String, arguments: [String]) -> String? {
        let task = Process()
        task.launchPath = path
        task.arguments = arguments
        
        let outputPipe = Pipe()
        defer {
            outputPipe.fileHandleForReading.closeFile()
        }
        task.standardOutput = outputPipe
        
        task.launch()
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: outputData, as: UTF8.self)
        
        task.waitUntilExit()
        
        if output.isEmpty {
            return nil
        }
        
        return output
    }
    
    private func getMacModel() -> String? {
        guard let res = process(path: "/usr/sbin/system_profiler", arguments: ["SPHardwareDataType", "-json"]) else {
            return nil
        }
        
        do {
            if let json = try JSONSerialization.jsonObject(with: Data(res.utf8), options: []) as? [String: Any],
               let obj = json["SPHardwareDataType"] as? [[String: Any]], !obj.isEmpty, let val = obj.first,
               let name = val["machine_name"] as? String {
                return name
            }
        } catch {
            return nil
        }
        return nil
    }
    
    private func getCpuModel() -> String {
        var sizeOfName = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &sizeOfName, nil, 0)
        var nameChars = [CChar](repeating: 0, count: sizeOfName)
        sysctlbyname("machdep.cpu.brand_string", &nameChars, &sizeOfName, nil, 0)
        
        if getMacModel()!.uppercased().contains("AIR") {
            isAir = true
        }
        
        if String(cString: nameChars).uppercased().contains("M4") {
            return "M4"
        } else if String(cString: nameChars).uppercased().contains("M3") {
            return "M3"
        } else if String(cString: nameChars).uppercased().contains("M2") {
            return "M2"
        } else if String(cString: nameChars).uppercased().contains("M1") {
            // m1 air is not present SMC :(
            if isAir {
                presentSMC = false
            }
            return "M1"
        }  else {
            return "INTEL"
        }
        
    }
    
    init() {
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let mainport: mach_port_t = 0
        let serviceDir = IOServiceMatching("AppleSMC")
        let service = IOServiceGetMatchingService(mainport, serviceDir)
        IOServiceOpen(service, mach_task_self_ , 0, &con)
        IOObjectRelease(service)
        
        // let set default values
        cpuTempKeys = checkNulValues(sourceArray: (SensorsList["DEFAULT"]?["CPU"])!)
        gpuTempKeys = checkNulValues(sourceArray: (SensorsList["DEFAULT"]?["GPU"])!)
        fanTempKeys = checkNulValues(sourceArray: (SensorsList["DEFAULT"]?["FAN"])!)
        fanSpeedKeys = (SensorsList["DEFAULT"]?["FAN SPEED"])!
        systemPowerKeys = (SensorsList["DEFAULT"]?["POWER"])!
        systemAdapterKeys = (SensorsList["DEFAULT"]?["ADAPTER"])!
        systemBatteryKeys = (SensorsList["DEFAULT"]?["BATTERY"])!
        
        // let load apple sillicon models custom values
        for cpuModel in SensorsList {
            if cpuModel.key ==  getCpuModel() {
                for sensors in cpuModel.value {
                    if sensors.key == "CPU" {
                        cpuTempKeys = checkNulValues(sourceArray: sensors.value)
                    } else if sensors.key == "GPU" {
                        gpuTempKeys = checkNulValues(sourceArray: sensors.value)
                    } else if sensors.key == "FAN" {
                        fanTempKeys = checkNulValues(sourceArray: sensors.value)
                    } else if sensors.key == "FAN SPEED" {
                        fanSpeedKeys = sensors.value
                    } else if sensors.key == "POWER" {
                        systemPowerKeys = sensors.value
                    } else if sensors.key == "ADAPTER" {
                        systemAdapterKeys = sensors.value
                    } else if sensors.key == "BATTERY" {
                        systemBatteryKeys = sensors.value
                    }
                }
            }
        }
        self.update()
    }
    
    deinit {
        IOServiceClose(con)
    }
    
    private func checkNulValues(sourceArray: [String]) -> [String] {
        var resultArray = sourceArray
        
        // clear nullable values
        for value in sourceArray {
            if read(value) == 0.0 {
                resultArray.remove(at: resultArray.firstIndex(of: value)!)
            }
        }
        return resultArray
    }
    
    private func callStructMethod(_ input: inout AppleSMCKey, _ output: inout AppleSMCKey) throws {
        var outsize = MemoryLayout<AppleSMCKey>.size
        let result = IOConnectCallStructMethod(con, KERNEL_INDEX_SMC, &input, MemoryLayout<AppleSMCKey>.size, &output, &outsize)
        guard result == kIOReturnSuccess else { throw MyError.iokit(result) }
    }
    
    private func readKey(_ input: inout AppleSMCKey) throws {
        var output = AppleSMCKey()
        
        input.data8 = SMC_CMD_READ_KEYINFO
        try callStructMethod(&input, &output)
        
        input.info.size = output.info.size
        input.info.type = output.info.type
        input.data8 = SMC_CMD_READ_BYTES
        
        try callStructMethod(&input, &output)
        
        input.bytes = output.bytes
    }
    
    private func read(_ key: String) -> Double {
        var input = AppleSMCKey()
        input.key = try! AppleSMC4Chars(key)
        input.info.size = 4
        input.info.type = try! AppleSMC4Chars("flt ")
        try! readKey(&input)
        var ret: Float = 0.0
        memmove(&ret, &input.bytes, 4)
        return Double(String(format: "%0.1f",ret)) ?? 0.0
    }
    
    public func update () {
        // get SMC data
        cpuTemp = cpuTempKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})
        gpuTemp = gpuTempKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})
        
        if fanTempKeys.count > 0 {
            fanTemp = fanTempKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})
        }
        
        fanSpeed = []
        
        for key in fanSpeedKeys {
           fanSpeed.append(Int(self.read(key)))
        }
        
        systemPower = Int(systemPowerKeys.reduce(0, { sum, sensor in round(sum + self.read(sensor))}))
        systemAdapter = Int(systemAdapterKeys.reduce(0, { sum, sensor in round(sum + self.read(sensor))}))
        systemBattery = Int(systemBatteryKeys.reduce(0, { sum, sensor in round(sum + self.read(sensor))}))
    }
}
