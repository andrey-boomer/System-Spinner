//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others, Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Foundation
import Cocoa
import MediaKeyTap

class MediaKeyTapManager: MediaKeyTapDelegate {
    public static let shared = MediaKeyTapManager()
    var mediaKeyTap: MediaKeyTap?
    var keyRepeatTimers: [MediaKey: Timer] = [:]
    
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
        let device = simplyCA.defaultOutputDevice
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let keysAudio: [MediaKey] = [.volumeUp, .volumeDown, .mute]
        let keysBrightness: [MediaKey] = [.brightnessUp, .brightnessDown]
        var keys: [MediaKey] = keysAudio + keysBrightness
        
        mediaKeyTap?.stop()
        
        // ask for privileges
        if AXIsProcessTrustedWithOptions(options) {
            if !DisplayManager.shared.hasBrightnessControll() {
                keys.removeAll { keysBrightness.contains($0) }
            }
            
            var disengageVolume = true
            for display in DisplayManager.shared.displays {
                if display.name == device?.name {
                    disengageVolume = false
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
}
