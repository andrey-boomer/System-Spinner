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
    private var versionTimer: Timer? = nil
    
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
   
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
         if  response.actionIdentifier == "Download" {
                NSWorkspace.shared.open(URL(string: appLastestUrl)!)
        }
        completionHandler()
    }
    
    public func checkNewVersion() -> Bool {
        let appCurrentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let sem = DispatchSemaphore.init(value: 0)
        var hasUpdate = false
        
        struct versionEntry: Codable {
            let id: Int
            var tagName: String
            let name: String
        }
        
        let task = URLSession.shared.dataTask(with:  URL(string: appApiUrl)!) { data, response, error in
              guard
                  error == nil,
                  let data = data
              else {
                  return
              }
              
              let decoder = JSONDecoder()
              decoder.keyDecodingStrategy = .convertFromSnakeCase
              do {
                  let versionList = try decoder.decode(versionEntry.self, from: data)
                  if !versionList.tagName.contains(appCurrentVersion!) {
                      hasUpdate = true
                  }
                  do { sem.signal() }
              } catch {
                  return
             }
          }
          task.resume()
        sem.wait()
        return hasUpdate
    }
    
    public func hasNewVersion() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.checkNewVersion() {
                self.sendSystemNotification(title: "New System Spinner has released!", body: "An new version is available. Would you like to update?", action: "Download")
            }
         }
    }
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
}
