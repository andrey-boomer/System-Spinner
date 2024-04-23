//
//  Helper.swift
//  System Spinner
//
//  Created by Андрей Лысиков on 23.04.2024.
//

import Foundation
import ServiceManagement
import AppKit

class Helper {
    
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
    
    public func checkNewVersion() -> Bool {
        let url = URL(string: "https://api.github.com/repos/andrey-boomer/System-Spinner/releases/latest")!
        let appCurrentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let sem = DispatchSemaphore.init(value: 0)
        var hasUpdate = false
        
        struct versionEntry: Codable {
            let id: Int
            var tagName: String
            let name: String
        }
        
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
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
    
}
