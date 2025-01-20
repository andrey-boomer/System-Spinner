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
        if isPressed, isCommand, !isControl, mediaKey == .brightnessDown, DisplayManager.engageMirror() {
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
    
    private func sendDisplayCommand(mediaKey: MediaKey, isRepeat: Bool, isPressed: Bool) {
        guard [.brightnessUp, .brightnessDown, .volumeUp, .volumeDown, .mute].contains(mediaKey), isPressed else {
            return
        }

        switch mediaKey {
        case .brightnessUp:
            DisplayManager.shared.setBrightness(isUp: true)
        case .brightnessDown:
            DisplayManager.shared.setBrightness(isUp: false)
        default :
            break
        }
        
        switch mediaKey {
        case .mute:
            if !isRepeat, isPressed {
                DisplayManager.shared.toggleMute()
            }
        case .volumeUp, .volumeDown:
            if isPressed {
                DisplayManager.shared.setVolume(isUp: mediaKey == .volumeUp)
            }
        default :
            break
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
        let keysAudio: [MediaKey] = [.volumeUp, .volumeDown, .mute]
        let keysBrightness: [MediaKey] = [.brightnessUp, .brightnessDown]
        var keys: [MediaKey] = keysAudio + keysBrightness
        
        mediaKeyTap?.stop()
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
