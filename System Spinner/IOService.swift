//
//  UsageViewController.swift
//  System Spinner

import Foundation

class IOServiceData {
    private var con: io_connect_t = 0
    private var debug = false
    private var cpuTempKeys: [String] = []
    private var gpuTempKeys: [String] = []
    private var fanTempKeys: [String] = []
    private var fanSpeedKeys:  [String] = []
    private var systemPowerKeys: [String] = []
    private let dateFormatter = DateFormatter()
    private let KERNEL_INDEX_SMC: UInt32 = 2
    private let SMC_CMD_READ_BYTES: UInt8 = 5
    private let SMC_CMD_READ_KEYINFO: UInt8 = 9
    private var now: String {
        dateFormatter.string(from: Date())
     }
    
    private let SensorsList: [String: [String:[String]]]  = [
        // imported from https://github.com/exelban/stats/blob/df1a0a8bacb9a9a6c23afa3c5faaabae2fc15890/Modules/Sensors/values.swift
        "DEFAULT": [
            "CPU": ["TC1c","TC2c","TC3c","TC4c"],
            "GPU": ["TCGC"],
            "FAN": ["TaLP", "TaRF"],
            "FAN SPEED": ["F0Ac", "F1Ac"],
            "POWER": ["PSTR", "PDTR", "PPBR"]
        ],
        "M1": [
            "CPU": ["TC0P", "Tp09", "Tp0T", "Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tg0H"],
            "GPU": ["Tg05", "Tg0D", "Tg0L" ,"Tg0T"],
            ],
        "M2": [
            "CPU": ["TC0P", "Tp0A", "Tp0D", "Tp0E", "Tp01", "Tp02", "Tp05", "Tp06", "Tp09"],
            "GPU": ["Tg0f", "Tg0j"],
        ],
        "M3": [
            "CPU": ["TC0P", "Te05", "Te0L", "Te0P", "Te0S", "Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E"],
            "GPU": ["Tf14", "Tf18", "Tf19", "Tf1A", "Tf24", "Tf28", "Tf29", "Tf2A"],
        ]
    ]
    
    // data for translate
    public var cpuTemp: Float = 0
    public var gpuTemp: Float = 0
    public var fanTemp: Float = 0
    public var fanSpeed: Float = 0
    public var fan1Speed: Float = 0
    public var fan2Speed: Float = 0
    public var systemPower: Float = 0
    
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
    
    private func getCpuModel() -> String {
        var sizeOfName = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &sizeOfName, nil, 0)
        var nameChars = [CChar](repeating: 0, count: sizeOfName)
        sysctlbyname("machdep.cpu.brand_string", &nameChars, &sizeOfName, nil, 0)
        
        if String(cString: nameChars).contains("M3") {
            return "M3"
        } else if String(cString: nameChars).contains("M2") {
            return "M2"
        }  else {
            return "M1"
        }
    }

    init(_ debug: Bool = false) {
        self.debug = debug
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
        fanSpeedKeys = checkNulValues(sourceArray: (SensorsList["DEFAULT"]?["FAN SPEED"])!)
        systemPowerKeys = checkNulValues(sourceArray: (SensorsList["DEFAULT"]?["POWER"])!)
        
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
                        fanSpeedKeys = checkNulValues(sourceArray: sensors.value)
                    } else if sensors.key == "POWER" {
                        systemPowerKeys = checkNulValues(sourceArray: sensors.value)
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
    
    private func read(_ key: String) -> Float {
        var input = AppleSMCKey()
        input.key = try! AppleSMC4Chars(key)
        input.info.size = 4
        input.info.type = try! AppleSMC4Chars("flt ")
        try! readKey(&input)
        var ret: Float = 0.0
        memmove(&ret, &input.bytes, 4)
        if debug { print( now, "read \(key): \(ret)") }
        return ceil(ret * 10) / 10.0
    }
    
    public func update () {
        // get SMC data
        cpuTemp = cpuTempKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})
        gpuTemp = gpuTempKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})

        if fanSpeedKeys.count > 0 {
            fanTemp = fanTempKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})
            fanSpeed = fanSpeedKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})
            fan1Speed = self.read(fanSpeedKeys[0])
            fan2Speed = self.read(fanSpeedKeys[1])
        }
        
        systemPower = systemPowerKeys.reduce(0,{ result, sensor in max(result, self.read(sensor))})
    }
}
