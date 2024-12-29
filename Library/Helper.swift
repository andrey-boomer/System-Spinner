//
//  Helper.swift
//  System Spinner
//
//  Created by Андрей Лысиков on 23.04.2024.
//

import Foundation
import ServiceManagement
import AppKit
import UserNotifications

class Helper: NSObject, UNUserNotificationCenterDelegate {
    // Autoupdate links
    public let appApiUrl = "https://api.github.com/repos/andrey-boomer/System-Spinner/releases/latest"
    public let appLastestUrl = "https://github.com/andrey-boomer/System-Spinner/releases/latest"
    public let appAboutUrl = "https://github.com/andrey-boomer/System-Spinner"
    public let popover = NSPopover()
    private var versionTimer: Timer? = nil
    private var cpuTimer: Timer? = nil
    private var spinnerTimer: Timer? = nil
    private var frames: [NSImage] =  []
    private var curFrame: Int = 0
    private var maxFrame: Int = 0
    
    public var isAutoLaunch: Bool {
            get { SMAppService.mainApp.status == .enabled }
            set {
                do {
                    if newValue {
                        if SMAppService.mainApp.status == .enabled {
                            try? SMAppService.mainApp.unregister()
                        }

                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    print("Can't use SMAppService")
                }
            }
        }
    
    public func openAnalitycstApp() {
        let url = NSURL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app", isDirectory: true) as URL
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["/bin"]
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: configuration,
                                           completionHandler: nil)
    }
    
    public func remapKeysBacklight(toggle: Bool) {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        
        if toggle {
            task.arguments = ["hidutil", "property", "--set", "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\": 0xC000000CF,\"HIDKeyboardModifierMappingDst\": 0xFF00000009},{\"HIDKeyboardModifierMappingSrc\": 0x10000009B,\"HIDKeyboardModifierMappingDst\": 0xFF00000008}]}"]
            
        } else {
            task.arguments = ["hidutil", "property", "--set", "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\": 0xFF00000009,\"HIDKeyboardModifierMappingDst\": 0xC000000CF},{\"HIDKeyboardModifierMappingSrc\": 0xFF00000008,\"HIDKeyboardModifierMappingDst\": 0x10000009B}]}"]
            
        }
        task.standardOutput = nil
        task.launch()
        task.waitUntilExit()
    }
    
    public func sendSystemNotification(title: String, body: String = "", action: String) {
        let content = UNMutableNotificationContent()
        let notificationCenter = UNUserNotificationCenter.current()
        let downloadAction = UNNotificationAction(identifier: action, title: action, options: .init(rawValue: 0))
        let category = UNNotificationCategory(identifier: "ACTION", actions: [downloadAction], intentIdentifiers: [], hiddenPreviewsBodyPlaceholder: "", options: .customDismissAction)

        content.title = title
        content.body = body
        content.categoryIdentifier = "ACTION"
        notificationCenter.setNotificationCategories([category])
        notificationCenter.removeAllPendingNotificationRequests()
        notificationCenter.requestAuthorization(options: [.alert,.sound]) { (granted, error) in
            if !granted {
                print("Notifications is not allowed")
            }
        }
        notificationCenter.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
   
    public func showPopover(sender: Any?) {
      if let button = statusItem.button {
          popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
      }
    }

    public func closePopoverMenu(sender: Any?) {
        statusItem.menu = nil
        if popover.isShown {
            popover.performClose(sender)
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
         if  response.actionIdentifier == "Download" {
             guard let url = URL(string: appLastestUrl) else {
                   return
             }
             NSWorkspace.shared.open(url)
        }
        completionHandler()
    }
    
    public func hasNewVersion() {
        
        struct versionEntry: Codable {
            let id: Int
            var tagName: String
            let name: String
        }
        
        func trimCharacter(val: Any) -> Int {
            let forFilter = val as? String ?? ""
            let filteredString = forFilter.filter("0123456789".contains)
            return Int(filteredString) ?? 0
        }
        
        let appCurrentVersion = trimCharacter(val: Bundle.main.infoDictionary!["CFBundleShortVersionString"] as Any)
        
        guard let url = URL(string: appApiUrl) else {
              return
        }
        
		// start check new version after 5 minits from execute function
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            URLSession.shared.dataTask(with: url) { (data, res, err) in
                guard let data = data else {
                      return
                }
                
                do {
                    let decoder = JSONDecoder()
                    decoder.keyDecodingStrategy = .convertFromSnakeCase
                    let versionGit = try trimCharacter(val: decoder.decode(versionEntry.self, from: data).tagName)
                    if versionGit > 0 && appCurrentVersion > 0 && versionGit > appCurrentVersion {
                        self.sendSystemNotification(title: "New System Spinner has released!",
                                                    body: "An new version is available. Would you like to update?",
                                                    action: "Download")
                    }
                } catch {
                   return
                }
			}.resume()
         }
    }
    
    public func changeSpinner(spinnerName: String, spinnerFrames: Int) {
        stopRunning()
        spinnerActive = spinnerName
        
        // load spinner
        frames = {
            return (0 ..< spinnerFrames).map { n in
                let image = NSImage(named: spinnerName + " \(n)")!
                image.size = NSSize(width: 19 / image.size.height * image.size.width, height: 19)
                return image
            }
        }()
        curFrame = 0
        maxFrame = spinnerFrames
        startRunning()
    }
    
    public func startRunning() {
        cpuTimer = Timer(timeInterval: updateInterval, repeats: true, block: { [weak self] _ in
            self?.updateUsage()
        })
        RunLoop.main.add(cpuTimer!, forMode: .common)
        cpuTimer?.fire()
    }
    
    public func stopRunning() {
        spinnerTimer?.invalidate()
        cpuTimer?.invalidate()
    }
    
    private func updateUsage() {
        ActivityData.updateCpuOnly()
        curFrame =  curFrame + 1
        if curFrame > maxFrame - 1 {
            curFrame = 0
        }
        statusItem.button?.image = frames[curFrame]
        
        if enableStatusText {
            statusItem.button?.title =  String(Int(ActivityData.cpuPercentage)) + "% "
        } else {
            statusItem.button?.title = ""
        }
        
        let interval = 0.25 / max(1.0, min(100.0, ActivityData.cpuPercentage / Double(maxFrame)))
        spinnerTimer?.invalidate()
        spinnerTimer = Timer(timeInterval: interval, repeats: true, block: { [weak self] _ in
            self!.curFrame =  self!.curFrame + 1
            if self!.curFrame == self!.maxFrame {
                self!.curFrame = 0
            }
            statusItem.button?.image = self?.frames[self!.curFrame]
            
        })
        RunLoop.main.add(spinnerTimer!, forMode: .common)
    }
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
}

class OSDUtils: NSObject {
    enum OSDImage: Int64 {
        case brightness = 1
        case audioSpeaker = 3
        case audioSpeakerMuted = 4
        case contrast = 0
    }
    
    static func getOSDImageByCommand(command: Command, value: Float = 1) -> OSDImage {
        var osdImage: OSDImage
        switch command {
            case .audioSpeakerVolume: osdImage = value > 0 ? .audioSpeaker : .audioSpeakerMuted
            case .audioMuteScreenBlank: osdImage = .audioSpeakerMuted
            case .contrast: osdImage = .contrast
            default: osdImage = .brightness
        }
        return osdImage
    }

  static func showOsd(displayID: CGDirectDisplayID, command: Command, value: Float, maxValue: Float = 1, lock: Bool = false) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    let osdImage = self.getOSDImageByCommand(command: command, value: value)
    let filledChiclets: Int
    let totalChiclets: Int
    filledChiclets = Int(value * 100)
    totalChiclets = Int(maxValue * 100)
    manager.showImage(osdImage.rawValue, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000, filledChiclets: UInt32(filledChiclets), totalChiclets: UInt32(totalChiclets), locked: lock)
  }

  static func showOsdVolumeDisabled(displayID: CGDirectDisplayID) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    manager.showImage(22, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000)
  }

  static func showOsdMuteDisabled(displayID: CGDirectDisplayID) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    manager.showImage(21, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 1000)
  }

  static func popEmptyOsd(displayID: CGDirectDisplayID, command: Command) {
    guard let manager = OSDManager.sharedManager() as? OSDManager else {
      return
    }
    let osdImage = self.getOSDImageByCommand(command: command)
    manager.showImage(osdImage.rawValue, onDisplayID: displayID, priority: 0x1F4, msecUntilFade: 0)
  }

  static let chicletCount: Float = 16

  static func chiclet(fromValue value: Float, maxValue: Float, half: Bool = false) -> Float {
    (value * self.chicletCount * (half ? 2 : 1)) / maxValue
  }

  static func value(fromChiclet chiclet: Float, maxValue: Float, half: Bool = false) -> Float {
    (chiclet * maxValue) / (self.chicletCount * (half ? 2 : 1))
  }

  static func getDistance(fromNearestChiclet chiclet: Float) -> Float {
    abs(chiclet.rounded(.towardZero) - chiclet)
  }
}
