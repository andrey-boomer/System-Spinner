//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others
//  Adapted @Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import Cocoa
import AudioToolbox
import MediaKeyTap
import IOKit

class AudioDevice {
    struct AudioDevice: Codable {
        var deviceID: AudioDeviceID
        var name: String
        var hasOutput: Bool
        var selected: Bool
    }
    
    var devices: [AudioDevice] = []
    
    private let audioObjectPropertyElementMain: AudioObjectPropertyElement = 0
    
    init() {
        var address = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDevices),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: audioObjectPropertyElementMain)
        
        var propSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propSize)
        
        let numDevices = Int(propSize / UInt32(MemoryLayout<AudioDeviceID>.size))
        var devids = Array<AudioDeviceID>(repeating: AudioDeviceID(), count: numDevices)
        
        result = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &propSize,
            &devids)
        
        if (result == 0) {
            for i in 0..<numDevices {
                let newDevice = AudioDevice(deviceID: devids[i],
                                            name: getDeviceName(audioDeviceID: devids[i]),
                                            hasOutput: hasOutput(audioDeviceID: devids[i]),
                                            selected: selectedDevice(audioDeviceID: devids[i]))
                devices.append(newDevice)
            }
        }
    }
    
    
    private func getDeviceName(audioDeviceID: AudioDeviceID) -> String {
        var propertySize = UInt32(MemoryLayout<CFString>.size)
        
        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyDeviceNameCFString),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: AudioObjectPropertyElement(kAudioObjectPropertyElementMain))
        
        var result: CFString = "" as CFString
        
        AudioObjectGetPropertyData(audioDeviceID, &propertyAddress, 0, nil, &propertySize, &result)
        
        return result as String
    }
    
    private func hasOutput(audioDeviceID: AudioDeviceID) ->  Bool {
        var address: AudioObjectPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioDevicePropertyStreamConfiguration),
            mScope: AudioObjectPropertyScope(kAudioDevicePropertyScopeOutput),
            mElement: audioObjectPropertyElementMain)
        
        var propSize: UInt32 = 0
        var result = AudioObjectGetPropertyDataSize(
            audioDeviceID,
            &address,
            0,
            nil,
            &propSize)
        if (result != 0) {
            return false
        }
        let bufferList = UnsafeMutablePointer<AudioBufferList>.allocate(capacity: Int(propSize))
        defer {
            bufferList.deallocate()
        }
        result = AudioObjectGetPropertyData(audioDeviceID, &address, 0, nil, &propSize, bufferList)
        if (result != 0) {
            return false
        }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        return buffers.contains { $0.mNumberChannels > 0 }
    }
    
    private func selectedDevice(audioDeviceID: AudioDeviceID) -> Bool {
        var id = AudioObjectID(kAudioObjectSystemObject)
        var idSize = UInt32(MemoryLayout.size(ofValue: id))
        
        var idPropertyAddress = AudioObjectPropertyAddress(
            mSelector: AudioObjectPropertySelector(kAudioHardwarePropertyDefaultOutputDevice),
            mScope: AudioObjectPropertyScope(kAudioObjectPropertyScopeGlobal),
            mElement: audioObjectPropertyElementMain)
        
        let result = AudioObjectGetPropertyData(
            id,
            &idPropertyAddress,
            0,
            nil,
            &idSize,
            &id)
        
        if (result != 0) {
            return false
        } else {
            if audioDeviceID == id {
                return true
            }
        }
        return false
    }
}

class MediaKeyTapManager: MediaKeyTapDelegate {
    let audioDevice = AudioDevice()
    var mediaKeyTap: MediaKeyTap?
    var keyRepeatTimers: [MediaKey: Timer] = [:]
    
    public func readPrivileges() -> Bool {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let status = AXIsProcessTrustedWithOptions(options)
        if status == false {
            let alert = NSAlert()
            alert.messageText = "Keyboard not available"
            alert.informativeText = "You need enable application in System Settings > Security and Privacy > Accessibility for the keyboard shortcuts to work"
            alert.runModal()
        }
        return status
    }
    
    public func handle(mediaKey: MediaKey, event: KeyEvent?, modifiers: NSEvent.ModifierFlags?) {
        let isPressed = event?.keyPressed ?? true
        let isRepeat = event?.keyRepeat ?? false
        let isControl = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.control])) ?? false
        let isCommand = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.command])) ?? false
        let isOption = modifiers?.isSuperset(of: NSEvent.ModifierFlags([.option])) ?? false
        if isPressed, isCommand, !isControl, mediaKey == .brightnessDown, DisplayManager.engageMirror() {
            return
        }
        if isPressed, isControl, !isOption, mediaKey == .brightnessUp || mediaKey == .brightnessDown {
            self.handleDirectedBrightness(isCommandModifier: isCommand, isUp: mediaKey == .brightnessUp)
            return
        }
        let oppositeKey: MediaKey? = self.oppositeMediaKey(mediaKey: mediaKey)
        
        if let oppositeKey = oppositeKey, let oppositeKeyTimer = self.keyRepeatTimers[oppositeKey], oppositeKeyTimer.isValid {
            oppositeKeyTimer.invalidate()
        } else if let mediaKeyTimer = self.keyRepeatTimers[mediaKey], mediaKeyTimer.isValid {
            if isRepeat {
                return
            }
            mediaKeyTimer.invalidate()
        }
        self.sendDisplayCommand(mediaKey: mediaKey, isRepeat: isRepeat, isPressed: isPressed)
    }
    
    private func handleDirectedBrightness(isCommandModifier: Bool, isUp: Bool) {
        if isCommandModifier {
            for otherDisplay in DisplayManager.shared.getOtherDisplays() {
                otherDisplay.setBrightness(to: otherDisplay, isUp: true)
            }
            for appleDisplay in DisplayManager.shared.getAppleDisplays() where !appleDisplay.isBuiltIn() {
                appleDisplay.setBrightness(to: appleDisplay, isUp: true)
            }
            return
        } else if let internalDisplay = DisplayManager.shared.getBuiltInDisplay() as? AppleDisplay {
            internalDisplay.setBrightness(to: internalDisplay, isUp: true)
            return
        }
    }
    
    private func sendDisplayCommand(mediaKey: MediaKey, isRepeat: Bool, isPressed: Bool) {
        guard [.brightnessUp, .brightnessDown, .volumeUp, .volumeDown, .mute].contains(mediaKey), isPressed, let affectedDisplays = DisplayManager.shared.getAffectedDisplays() else {
            return
        }
        for display in affectedDisplays {
            switch mediaKey {
            case .brightnessUp:
                display.setBrightness(to: display, isUp: true)
            case .brightnessDown:
                display.setBrightness(to: display, isUp: false)
            default: continue
            }
        }
        
        for display in affectedDisplays {
            switch mediaKey {
            case .mute:
                if !isRepeat, isPressed, let display = display as? OtherDisplay {
                    display.toggleMute()
                }
            case .volumeUp, .volumeDown:
                if let display = display as? OtherDisplay {
                    if isPressed {
                        display.stepVolume(isUp: mediaKey == .volumeUp)
                    }
                }
            default: continue
            }
        }
    }
    
    private func oppositeMediaKey(mediaKey: MediaKey) -> MediaKey? {
        if mediaKey == .brightnessUp {
            return .brightnessDown
        } else if mediaKey == .brightnessDown {
            return .brightnessUp
        } else if mediaKey == .volumeUp {
            return .volumeDown
        } else if mediaKey == .volumeDown {
            return .volumeUp
        }
        return nil
    }
    
    public func updateMediaKeyTap() {
        let keysAudio: [MediaKey] = [.volumeUp, .volumeDown, .mute]
        let keysBrightness: [MediaKey] = [.brightnessUp, .brightnessDown]
        var keys: [MediaKey] = keysAudio + keysBrightness
        
        self.mediaKeyTap = MediaKeyTap(delegate: self, on: KeyPressMode.keyDownAndUp, for: [], observeBuiltIn: true)
        self.mediaKeyTap?.stop()

        var disengageBrightness = true
        
        for display in DisplayManager.shared.displays where !display.isBuiltIn() {
            disengageBrightness = false
        }
        if disengageBrightness {
            keys.removeAll { keysBrightness.contains($0) }
        }
        
        var disengageVolume = true
        for display in DisplayManager.shared.displays {
            for audio in audioDevice.devices {
                if display.name == audio.name && audio.selected == true {
                    disengageVolume = false
                }
            }
        }
        
        if disengageVolume {
            keys.removeAll { keysAudio.contains($0) }
        }
        if keys.count > 0 {
            self.mediaKeyTap = MediaKeyTap(delegate: self, on: KeyPressMode.keyDownAndUp, for: keys, observeBuiltIn: true)
            self.mediaKeyTap?.start()
        }
    }
}
