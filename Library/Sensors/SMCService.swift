//  Copyright © Serhiy Mytrovtsiy, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0
//  Основано на https://github.com/exelban/stats

import Foundation
import IOKit

final class SMCService {
    enum Failure: Error {
        case serviceUnavailable
        case connectionFailed(kern_return_t)
        case invalidKey(String)
        case callFailed(kern_return_t)
        case unsupportedType(String)
    }

    private let connection: io_connect_t

    private static let kernelIndexSMC: UInt32 = 2
    private static let cmdReadBytes: UInt8 = 5
    private static let cmdReadKeyInfo: UInt8 = 9

    init() throws {
        guard let matching = IOServiceMatching("AppleSMC") else {
            throw Failure.serviceUnavailable
        }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else {
            throw Failure.serviceUnavailable
        }
        defer { IOObjectRelease(service) }

        var port: io_connect_t = 0
        let result = IOServiceOpen(service, mach_task_self_, 0, &port)
        guard result == kIOReturnSuccess, port != 0 else {
            throw Failure.connectionFailed(result)
        }
        connection = port
    }

    deinit {
        IOServiceClose(connection)
    }

    func value(forKey key: String) throws -> Double {
        var input = ParamStruct()
        input.key = try FourCharCode(key)

        input.data8 = Self.cmdReadKeyInfo
        let info = try call(&input)

        input.keyInfo.size = info.keyInfo.size
        input.keyInfo.type = info.keyInfo.type
        input.data8 = Self.cmdReadBytes
        let payload = try call(&input)

        return try Self.decode(payload.bytes, type: info.keyInfo.type.stringValue)
    }

    func optionalValue(forKey key: String) -> Double? {
        try? value(forKey: key)
    }

    func readableKeys(among keys: [String]) -> [String] {
        keys.filter { key in
            guard let value = optionalValue(forKey: key) else { return false }
            return value != 0
        }
    }

    private func call(_ input: inout ParamStruct) throws -> ParamStruct {
        var output = ParamStruct()
        var outputSize = MemoryLayout<ParamStruct>.size
        let result = IOConnectCallStructMethod(connection,
                                              Self.kernelIndexSMC,
                                              &input,
                                              MemoryLayout<ParamStruct>.size,
                                              &output,
                                              &outputSize)
        guard result == kIOReturnSuccess else { throw Failure.callFailed(result) }
        return output
    }

    private static func decode(_ bytes: Bytes, type: String) throws -> Double {
        let b = bytes.values
        switch type {
        case "flt ":
            var float: Float32 = 0
            withUnsafeMutableBytes(of: &float) { destination in
                for index in 0 ..< 4 { destination[index] = b[index] }
            }
            return Double(float)
        case "ui8 ", "si8 ":
            return Double(b[0])
        case "ui16":
            return Double(UInt16(b[0]) << 8 | UInt16(b[1]))
        case "ui32":
            return Double(UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3]))
        case "si16":
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1])))
        case "sp78":
            return Double(Int16(bitPattern: UInt16(b[0]) << 8 | UInt16(b[1]))) / 256.0
        default:
            throw Failure.unsupportedType(type)
        }
    }

    private struct FourCharCode {
        var chars: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)

        init() {}

        init(_ string: String) throws {
            let bytes = Array(string.utf8)
            guard bytes.count == 4 else { throw Failure.invalidKey(string) }
            chars = (bytes[3], bytes[2], bytes[1], bytes[0])
        }

        var stringValue: String {
            String(decoding: [chars.3, chars.2, chars.1, chars.0], as: UTF8.self)
        }
    }

    private struct Version {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct LimitData {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpu: UInt32 = 0
        var gpu: UInt32 = 0
        var mem: UInt32 = 0
    }

    private struct KeyInfo {
        var size: UInt32 = 0
        var type = FourCharCode()
        var attribute: UInt8 = 0
        var unused1: UInt8 = 0
        var unused2: UInt8 = 0
        var unused3: UInt8 = 0
    }

    private struct Bytes {
        var storage: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                      UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

        var values: [UInt8] {
            withUnsafeBytes(of: storage) { Array($0) }
        }
    }

    private struct ParamStruct {
        var key = FourCharCode()
        var version = Version()
        var limit = LimitData()
        var keyInfo = KeyInfo()
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes = Bytes()
    }
}
