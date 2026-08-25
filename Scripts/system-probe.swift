//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0
//
//  Reads the SMC while it runs and writes two tables into the working
//  directory. Run it, then move through the states — on battery, plug in while
//  low so it charges, wait until it is full — and the columns show which
//  reading follows which state.
//
//      swiftc -O -o system-probe system-probe.swift
//      ./system-probe
//
//  Everything lands in probe-log.tsv as time, key, type, value — one shape for
//  both halves of it, because the point is comparing them against each other.
//
//  Rows typed "app" are the power line as the app builds it: what it would put
//  in the menu, next to the readings behind that answer. Written every sample.
//

//  The rest is the chip itself. The first sweep writes every key the machine
//  admits to — a couple of thousand of them, and on a laptop nobody has mapped
//  yet that list is the point of this tool. After it only what changed is
//  written, so the keys that follow the battery stand out instead of drowning.
//
//  Rows typed "device" are the displays, mice and keyboards attached, with the
//  verdicts the app draws from them — whether the smooth scroll is offered and
//  whether the backlight can be reached. Written when they change, so plugging
//  something in or shutting the lid shows up as a row of its own.
//
//  Which machine it is, what the app's tables get out of it, and what is
//  attached:
//      awk -F'\t' '$3 != "flt " && $3 != "app"' probe-*.tsv
//
//  Stop it with Ctrl+C. Each run appends, so several runs share the file.

import CoreGraphics
import Foundation
import IOKit
import IOKit.hid
import IOKit.ps

private struct FourCharCode {
    var chars: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)

    init() {}

    init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 4 else { return nil }
        chars = (bytes[3], bytes[2], bytes[1], bytes[0])
    }

    var stringValue: String {
        String(decoding: [chars.3, chars.2, chars.1, chars.0], as: UTF8.self)
    }
}

private struct Bytes {
    var storage = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                   UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                   UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0),
                   UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))

    var values: [UInt8] { withUnsafeBytes(of: storage) { Array($0) } }
}

private struct KeyInfo {
    var size: UInt32 = 0
    var type = FourCharCode()
    var attribute: UInt8 = 0
    var unused = (UInt8(0), UInt8(0), UInt8(0))
}

private struct ParamStruct {
    var key = FourCharCode()
    var version = (UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt16(0))
    var limit = (UInt16(0), UInt16(0), UInt32(0), UInt32(0), UInt32(0))
    var keyInfo = KeyInfo()
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes = Bytes()
}

private final class SMC {
    private let connection: io_connect_t

    init?() {
        guard let matching = IOServiceMatching("AppleSMC") else { return nil }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
        guard service != IO_OBJECT_NULL else { return nil }
        defer { IOObjectRelease(service) }

        var port: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, 0, &port) == kIOReturnSuccess, port != 0 else {
            return nil
        }
        connection = port
    }

    deinit { IOServiceClose(connection) }

    func value(forKey key: String) -> Double? {
        guard let code = FourCharCode(key) else { return nil }

        var input = ParamStruct()
        input.key = code
        input.data8 = 9
        guard let info = call(&input) else { return nil }

        input.keyInfo.size = info.keyInfo.size
        input.keyInfo.type = info.keyInfo.type
        input.data8 = 5
        guard let payload = call(&input) else { return nil }

        return Self.decode(payload.bytes, type: info.keyInfo.type.stringValue)
    }

    func allKeys() -> [String] {
        guard let count = value(forKey: "#KEY").map({ Int($0) }), count > 0 else { return [] }

        var keys: [String] = []
        keys.reserveCapacity(count)

        for index in 0 ..< count {
            var input = ParamStruct()
            input.data8 = 8
            input.data32 = UInt32(index)
            guard let output = call(&input) else { continue }

            let key = output.key.stringValue
            if key.count == 4 { keys.append(key) }
        }
        return keys
    }

    func reading(forKey key: String) -> (type: String, value: String)? {
        guard let code = FourCharCode(key) else { return nil }

        var input = ParamStruct()
        input.key = code
        input.data8 = 9
        guard let info = call(&input) else { return nil }

        let type = info.keyInfo.type.stringValue
        let size = Int(info.keyInfo.size)

        input.keyInfo.size = info.keyInfo.size
        input.keyInfo.type = info.keyInfo.type
        input.data8 = 5
        guard let payload = call(&input) else { return (type, "-") }

        if let number = Self.decode(payload.bytes, type: type) {
            return (type, String(format: "%g", number))
        }

        let bytes = payload.bytes.values.prefix(max(0, min(size, 32)))
        if type == "ch8*" {
            let text = String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
            if !text.isEmpty, text.allSatisfy({ $0.isASCII && !$0.isNewline }) { return (type, text) }
        }
        return (type, bytes.map { String(format: "%02x", $0) }.joined())
    }

    private func call(_ input: inout ParamStruct) -> ParamStruct? {
        var output = ParamStruct()
        var size = MemoryLayout<ParamStruct>.size
        let result = IOConnectCallStructMethod(connection, 2, &input,
                                               MemoryLayout<ParamStruct>.size, &output, &size)
        return result == kIOReturnSuccess ? output : nil
    }

    private static func decode(_ bytes: Bytes, type: String) -> Double? {
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
        case "si32":
            return Double(Int32(bitPattern: b.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }))
        case "ui64":
            return Double(b.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) })
        case "ioft":
            // IOKit's fixed point: eight bytes with sixteen fraction bits.
            return Double(b.prefix(8).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }) / 65536
        case "flag":
            return b[0] == 0 ? 0 : 1
        default:
            guard type.count == 4, type.hasPrefix("fp") || type.hasPrefix("sp"),
                  let fraction = Int(String(type.suffix(1)), radix: 16)
            else {
                return nil
            }

            let raw = UInt16(b[0]) << 8 | UInt16(b[1])
            let scale = Double(1 << fraction)
            return type.hasPrefix("sp")
                ? Double(Int16(bitPattern: raw)) / scale
                : Double(raw) / scale
        }
    }
}

private func powerState() -> (onBattery: Bool, charging: Bool) {
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

private func batteryProperties() -> [String: Any] {
    guard let matching = IOServiceMatching("AppleSmartBattery") else { return [:] }
    let service = IOServiceGetMatchingService(kIOMainPortDefault, matching)
    guard service != IO_OBJECT_NULL else { return [:] }
    defer { IOObjectRelease(service) }

    var properties: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(service, &properties, kCFAllocatorDefault, 0) == KERN_SUCCESS,
          let dictionary = properties?.takeRetainedValue() as? [String: Any]
    else {
        return [:]
    }
    return dictionary
}

private typealias DisplayInfo = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?
private let coreDisplay = dlopen("/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay", RTLD_LAZY)
private let displayInfo = dlsym(coreDisplay, "CoreDisplay_DisplayCreateInfoDictionary")
    .map { unsafeBitCast($0, to: DisplayInfo.self) }

private func displayName(_ identifier: CGDirectDisplayID) -> String {
    guard let dictionary = displayInfo?(identifier)?.takeRetainedValue() as? [String: Any],
          let names = dictionary["DisplayProductName"] as? [String: String],
          let name = names[Locale.current.identifier] ?? names["en_US"] ?? names.first?.value
    else {
        return "Unknown"
    }
    return name
}

private func displayRows() -> [(String, String)] {
    var identifiers = [CGDirectDisplayID](repeating: 0, count: 16)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(16, &identifiers, &count) == .success else { return [] }

    var rows = [("displays", String(count))]
    for identifier in identifiers.prefix(Int(count)) {
        let flags = [
            CGDisplayIsBuiltin(identifier) != 0 ? "builtin" : "external",
            CGDisplayIsActive(identifier) != 0 ? "active" : "inactive",
            CGDisplayIsAsleep(identifier) != 0 ? "asleep" : "awake",
            CGDisplayIsMain(identifier) != 0 ? "main" : "secondary",
            CGDisplayIsInMirrorSet(identifier) != 0 ? "mirrored" : "own",
        ].joined(separator: " ")

        let size = "\(CGDisplayPixelsWide(identifier))x\(CGDisplayPixelsHigh(identifier))"
        let vendor = "vendor \(CGDisplayVendorNumber(identifier)) model \(CGDisplayModelNumber(identifier))"
        rows.append(("display.\(identifier)", "\(displayName(identifier)) | \(flags) | \(size) | \(vendor)"))
    }
    return rows
}

private let appleVendorIDs = [0x05AC, 0x004C]

private func hidRows() -> [(String, String)] {
    let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    let matching = [
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Mouse],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Pointer],
        [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop, kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard],
    ]
    IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)

    guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return [] }

    var rows: [(String, String)] = []
    var thirdPartyMouse = false

    for device in devices {
        let property = { (key: String) in IOHIDDeviceGetProperty(device, key as CFString) }
        let usage = property(kIOHIDPrimaryUsageKey) as? Int ?? 0
        let vendor = property(kIOHIDVendorIDKey) as? Int
        let builtIn = (property(kIOHIDBuiltInKey) as? Bool) ?? false
        let kind = usage == kHIDUsage_GD_Keyboard ? "keyboard" : "mouse"
        let counts = kind == "mouse" && !builtIn && !appleVendorIDs.contains(vendor ?? -1)
        if counts { thirdPartyMouse = true }

        let location = property(kIOHIDLocationIDKey) as? Int ?? 0
        rows.append(("hid.\(kind).\(location)", [
            property(kIOHIDProductKey) as? String ?? "—",
            property(kIOHIDManufacturerKey) as? String ?? "—",
            "vendor " + (vendor.map(String.init) ?? "none"),
            property(kIOHIDTransportKey) as? String ?? "—",
            builtIn ? "builtin" : "external",
            counts ? "counts as a wheel mouse" : "does not count",
        ].joined(separator: " | ")))
    }

    rows.append(("hasThirdPartyMouse", thirdPartyMouse ? "yes" : "no"))
    return rows.sorted { $0.0 < $1.0 }
}

private typealias CopyIDs = @convention(c) (AnyObject, Selector) -> Unmanaged<NSArray>?
private typealias BoolForKeyboard = @convention(c) (AnyObject, Selector, UInt64) -> Bool
private typealias BrightnessForKeyboard = @convention(c) (AnyObject, Selector, UInt64) -> Float

private let brightnessClient: NSObject? = {
    dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
    guard let type = NSClassFromString("KeyboardBrightnessClient") as? NSObject.Type else { return nil }
    return type.init()
}()

private func isLidClosed() -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != IO_OBJECT_NULL else { return false }
    defer { IOObjectRelease(root) }

    let state = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
    return (state?.takeRetainedValue() as? Bool) ?? false
}

private func backlightRows() -> [(String, String)] {
    let closed = isLidClosed()
    var rows = [("lidClosed", closed ? "yes" : "no")]

    guard let client = brightnessClient,
          let copy = client.method(for: Selector(("copyKeyboardBacklightIDs"))),
          let identifiers = unsafeBitCast(copy, to: CopyIDs.self)(client, Selector(("copyKeyboardBacklightIDs")))?
              .takeRetainedValue() as? [NSNumber]
    else {
        rows.append(("backlightAvailable", "no"))
        return rows
    }

    let builtInSelector = Selector(("isKeyboardBuiltIn:"))
    let brightnessSelector = Selector(("brightnessForKeyboard:"))
    let isBuiltIn = client.method(for: builtInSelector).map { unsafeBitCast($0, to: BoolForKeyboard.self) }
    let brightness = client.method(for: brightnessSelector).map { unsafeBitCast($0, to: BrightnessForKeyboard.self) }

    for identifier in identifiers {
        let id = identifier.uint64Value
        let builtIn = isBuiltIn?(client, builtInSelector, id) ?? false
        let level = brightness.map { $0(client, brightnessSelector, id) * 100 } ?? -1
        rows.append(("backlight.\(id)", "\(builtIn ? "builtin" : "external") | \(String(format: "%.0f", level))%"))
    }
    let reachable = closed ? identifiers.filter { !(isBuiltIn?(client, builtInSelector, $0.uint64Value) ?? false) }
                           : identifiers
    let chosen = reachable.first(where: { isBuiltIn?(client, builtInSelector, $0.uint64Value) ?? false })
        ?? reachable.first
    rows.append(("backlightAvailable", chosen == nil ? "no" : "yes"))
    rows.append(("keyboardID", chosen.map { "\($0)" } ?? "none"))
    return rows
}

private let interval: TimeInterval = 2
private let alwaysWritten = ["PSTR", "PPBR", "PDTR"]
private let processorPrefix = "Tp"
private let plausibleTemperature = 5.0 ... 120.0

private func processorSensors(among keys: [String], _ smc: SMC?) -> [(String, Double)] {
    keys.filter { $0.hasPrefix(processorPrefix) }.compactMap { key in
        guard let text = smc?.reading(forKey: key)?.value, let value = Double(text),
              plausibleTemperature.contains(value)
        else {
            return nil
        }
        return (key, value)
    }
}

private func batteryTemperature() -> Double? {
    (batteryProperties()["Temperature"] as? Int).map { Double($0) / 100 }
}

private func format(_ value: Double?) -> String {
    value.map { String(format: "%.2f", $0) } ?? "-"
}

private func appRows(_ smc: SMC?) -> [(String, String)] {
    let read = { (key: String) in smc?.value(forKey: key) }
    let state = powerState()
    let battery = batteryProperties()

    let amps = (battery["Amperage"] as? Int).map { Double($0) / 1000 }
    let volts = (battery["Voltage"] as? Int).map { Double($0) / 1000 }
    let adapter = ((battery["AdapterDetails"] as? [String: Any])?["Watts"] as? Int).map(Double.init)
    let level = battery["CurrentCapacity"] as? Int ?? 0
    let flow: Double? = amps.flatMap { current in volts.map { current * $0 } }
    let system = read("PSTR").map { Int($0.rounded()) } ?? 0
    let dcIn = read("PDTR").map { Int($0.rounded()) } ?? 0
    let shown = state.onBattery ? system : (dcIn > 0 ? dcIn : system)
    let label = state.onBattery ? "on battery" : (state.charging ? "charging" : "on adapter")

    return [
        ("source", state.onBattery ? "battery" : "ac"),
        ("charging", state.charging ? "yes" : "no"),
        ("label", label),
        ("shown", String(shown)),
        ("battA", format(amps)),
        ("battV", format(volts)),
        ("battW", format(flow)),
        ("adapterW", format(adapter)),
        ("level", "\(level)"),
        ("batteryTemp", format(batteryTemperature())),
    ]
}

private func temperatureRows(among keys: [String], _ smc: SMC?) -> [(String, String)] {
    let found = processorSensors(among: keys, smc)
    guard !found.isEmpty else { return [("cpuSensors", "0"), ("cpuTemp", "-")] }

    let values = found.map(\.1).sorted()
    let mean = values.reduce(0, +) / Double(values.count)
    return [
        ("cpuSensors", String(found.count)),
        ("cpuTemp", format(mean)),
        ("cpuTempMin", format(values.first)),
        ("cpuTempMax", format(values.last)),
    ]
}

guard isatty(STDIN_FILENO) == 1 else {
    FileHandle.standardError.write(Data("power-probe has to be run from a terminal.\n".utf8))
    exit(1)
}

private func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }

    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }

    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

private let model = sysctlString("hw.model")
private let directory = FileManager.default.currentDirectoryPath

private func openLog(_ name: String, header: [String]) -> FileHandle? {
    let path = directory + "/" + name
    if !FileManager.default.fileExists(atPath: path) {
        FileManager.default.createFile(atPath: path,
                                       contents: Data((header.joined(separator: "\t") + "\n").utf8))
    }

    guard let file = FileHandle(forWritingAtPath: path) else {
        FileHandle.standardError.write(Data("Cannot write to \(path)\n".utf8))
        return nil
    }
    file.seekToEndOfFile()
    return file
}

private func append(_ line: String, to file: FileHandle) {
    file.write(Data((line + "\n").utf8))
    try? file.synchronize()
}

private let name = "probe-" + (model.isEmpty ? "unknown" : model).replacingOccurrences(of: ",", with: "-") + ".tsv"

guard let log = openLog(name, header: ["time", "key", "type", "value"]) else {
    exit(1)
}

private let smc = SMC()
if smc == nil {
    FileHandle.standardError.write(Data("No SMC connection — nothing to read.\n".utf8))
}

private let keys = smc?.allKeys() ?? []

private var previous: [String: String] = [:]

private let clock = DateFormatter()
clock.dateFormat = "HH:mm:ss"

for (key, value) in [("model", model),
                     ("chip", sysctlString("machdep.cpu.brand_string")),
                     ("os", ProcessInfo.processInfo.operatingSystemVersionString),
                     ("board", smc?.reading(forKey: "RPlt")?.value ?? "-"),
                     ("keys", String(keys.count)),
                     ("cpuKeys", processorSensors(among: keys, smc).map(\.0).joined(separator: " "))] {
    append([clock.string(from: Date()), key, "host", value].joined(separator: "\t"), to: log)
}

print("""
Writing \(name) in \(directory), every \(Int(interval))s.
\(keys.count) SMC keys listed by the chip. Ctrl+C to stop.
""")

while true {
    let stamp = clock.string(from: Date())
    let rows = appRows(smc)
    for (key, value) in rows {
        append([stamp, key, "app", value].joined(separator: "\t"), to: log)
    }
    print(stamp + "  " + rows.map { "\($0.0)=\($0.1)" }.joined(separator: "  "))
    for (key, value) in displayRows() + hidRows() + backlightRows() {
        guard previous.updateValue(value, forKey: key) != value else { continue }
        append([stamp, key, "device", value].joined(separator: "\t"), to: log)
    }

    for (key, value) in temperatureRows(among: keys, smc) {
        append([stamp, key, "app", value].joined(separator: "\t"), to: log)
    }

    for key in keys {
        guard let reading = smc?.reading(forKey: key) else { continue }
        let moved = previous.updateValue(reading.value, forKey: key) != reading.value
        guard moved || alwaysWritten.contains(key) else { continue }

        append([stamp, key, reading.type, reading.value].joined(separator: "\t"), to: log)
    }

    Thread.sleep(forTimeInterval: interval)
}
