//
//  AppDelegate.swift
//  System Spinner
//
//  Copyright 2024 Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    
    private lazy var statusItem: NSStatusItem = {
        return NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }()
    
    public let popover = NSPopover()
    public let ActivityData = AKservice()
    public var updateInterval: Double = 1.0
    private var keyRemap: Bool = false
    private var enableStatusText: Bool = false
    private var updateIntervalName = ["0.3", "0.5", "1.0", "1.5", "2.0"]
    private var spinners = ["Loader" : 8, "Grey Loader" : 18, "Cirrcles": 8, "Dots": 12, "Pie": 6, "Rainbow Pie": 15, "Recharges": 8, "Cat": 5]
    private var spinnerActive: String!
    private var statusItemMenu: NSMenu!
    private var frames: [NSImage] =  []
    private var curFrame: Int = 0
    private var cpuTimer: Timer? = nil
    private var spinnerTimer: Timer? = nil
    
    private func startRunning() {
        cpuTimer = Timer(timeInterval: updateInterval, repeats: true, block: { [weak self] _ in
            self?.updateUsage()
        })
        RunLoop.main.add(cpuTimer!, forMode: .common)
        cpuTimer?.fire()
    }
    
    private func stopRunning() {
        spinnerTimer?.invalidate()
        cpuTimer?.invalidate()
    }
    
    private func updateUsage() {
        ActivityData.update(Interval: updateInterval)
        curFrame =  curFrame + 1
        if curFrame > Int(spinners[spinnerActive]!) - 1 {
            curFrame = 0
        }
        statusItem.button?.image = frames[curFrame]
        
        if enableStatusText {
            statusItem.button?.title =  String(Int(ActivityData.cpuPercentage)) + "% "
        } else {
            statusItem.button?.title = ""
        }
        
        let interval = 0.25 / max(1.0, min(100.0, ActivityData.cpuPercentage / Double(spinners[spinnerActive]!)))
        spinnerTimer?.invalidate()
        spinnerTimer = Timer(timeInterval: interval, repeats: true, block: { [weak self] _ in
            self!.curFrame =  self!.curFrame + 1
            if self!.curFrame == Int(self!.spinners[self!.spinnerActive]!) {
                self!.curFrame = 0
            }
            self?.statusItem.button?.image = self?.frames[self!.curFrame]
            
        })
        RunLoop.main.add(spinnerTimer!, forMode: .common)
    }
    
    private func changeSpinner(setName: String) {
        stopRunning()
        spinnerActive = setName
        
        // load spinner
        frames = {
            return (0 ..< spinners[setName]!).map { n in
                let image = NSImage(named: setName + " \(n)")!
                image.size = NSSize(width: 19 / image.size.height * image.size.width, height: 19)
                return image
            }
        }()
        curFrame = 0
        startRunning()
    }
    
    @objc private func stopRunningNotify(_ notification: NSNotification) {
        closePopoverMenu(sender: self)
        stopRunning()
    }
    
    @objc private func startRunningNotify(_ notification: NSNotification) {
        startRunning()
    }
    
    @objc private func togglePopover(sender: NSStatusItem) {
        let event = NSApp.currentEvent!
        if event.type == NSEvent.EventType.leftMouseUp {
            if popover.isShown {
                closePopoverMenu(sender: sender)
            } else {
                statusItem.menu = nil
                showPopover(sender: sender)
            }
        } else {
            statusItem.menu = statusItemMenu
            statusItem.button?.performClick(nil)
        }
    }
    
    @objc private func changeSpinnerClick(sender: NSMenuItem) {
        changeSpinner(setName: sender.title)
    }
    
    @objc private func changeUpdateSpeedClick(sender: NSMenuItem) {
        stopRunning()
        
        for menuItem in statusItem.menu!.items { // set all submenu state off
            if menuItem.hasSubmenu && menuItem.title == sender.parent?.title {
                for subMenuItem in menuItem.submenu!.items {
                    subMenuItem.state = .off
                }
            }
        }
        
        updateInterval = Double(sender.title.replacingOccurrences(of: " s", with: ""))!
        sender.state = .on
        startRunning()
    }
    
    private func changeRemap() {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        
        if keyRemap {
            task.arguments = ["hidutil", "property", "--set", "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\": 0xC000000CF,\"HIDKeyboardModifierMappingDst\": 0xFF00000009},{\"HIDKeyboardModifierMappingSrc\": 0x10000009B,\"HIDKeyboardModifierMappingDst\": 0xFF00000008}]}"]
            
        } else {
            task.arguments = ["hidutil", "property", "--set", "{\"UserKeyMapping\":[{\"HIDKeyboardModifierMappingSrc\": 0xFF00000009,\"HIDKeyboardModifierMappingDst\": 0xC000000CF},{\"HIDKeyboardModifierMappingSrc\": 0xFF00000008,\"HIDKeyboardModifierMappingDst\": 0x10000009B}]}"]
            
        }
        task.launch()
        task.waitUntilExit()
    }
    
    @objc private func openAnalystApp(sender: NSMenuItem) {
        let url = NSURL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app", isDirectory: true) as URL
        
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = ["/bin"]
        NSWorkspace.shared.openApplication(at: url,
                                           configuration: configuration,
                                           completionHandler: nil)
    }

    @objc private func changeRemapClick(sender: NSMenuItem) {
        if keyRemap {
            sender.state = .off
            keyRemap = false
        } else {
            sender.state = .on
            keyRemap = true
        }
        changeRemap()
    }
    
   @objc private func changeStatusMenuClick(sender: NSMenuItem) {
        if enableStatusText {
            sender.state = .off
            enableStatusText = false
        } else {
            sender.state = .on
            enableStatusText = true
        }
    }
    
    private func showPopover(sender: Any?) {
      if let button = statusItem.button {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: NSRectEdge.minY)
      }
    }

    private func closePopoverMenu(sender: Any?) {
        statusItem.menu = nil
        if popover.isShown {
            popover.performClose(sender)
        }
    }
    
    private func setNotifications() {
           NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(stopRunningNotify(_:)),
                            name: NSWorkspace.willSleepNotification,
                            object: nil)
           NSWorkspace.shared.notificationCenter
            .addObserver(self, selector: #selector(startRunningNotify(_:)),
                            name: NSWorkspace.didWakeNotification,
                            object: nil)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        spinnerActive = UserDefaults.standard.string(forKey: "group.spinnerActive") ?? "Loader"
        updateInterval = Double(UserDefaults.standard.string(forKey: "group.spinnerUpdateInterval") ?? "1.0")!
        keyRemap = Bool(UserDefaults.standard.bool(forKey: "group.keyRemap"))
        enableStatusText = Bool(UserDefaults.standard.bool(forKey: "group.enableStatusText"))
        
        if let button = statusItem.button {
            button.action = #selector(togglePopover(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        }
    
        popover.contentViewController = UsageViewController.freshController()
        
        NSEvent.addGlobalMonitorForEvents(matching: NSEvent.EventTypeMask.leftMouseDown, handler: { [self](event: NSEvent) in
            closePopoverMenu(sender: self)
        })
        
        NSEvent.addGlobalMonitorForEvents(matching: NSEvent.EventTypeMask.rightMouseDown, handler: { [self](event: NSEvent) in
            closePopoverMenu(sender: self)
        })

        // create pop up menu
        statusItemMenu = NSMenu()
        
        // open Analytics
        statusItemMenu.addItem(NSMenuItem(title: "Activity Monitor", action: #selector(openAnalystApp(sender:)), keyEquivalent: ""))
        
        // Remap Menu
        let remapItem = NSMenuItem(title: "Keyboard backlight (F5/F6)", action: #selector(changeRemapClick(sender:)), keyEquivalent: "")
        if keyRemap {
            remapItem.state = .on
        }
        changeRemap()
        statusItemMenu.addItem(remapItem)
        
        // Text status in Menu
        let statusItem = NSMenuItem(title: "Show CPU usage in menu", action: #selector(changeStatusMenuClick(sender:)), keyEquivalent: "")
        if enableStatusText {
            statusItem.state = .on
        }
        statusItemMenu.addItem(statusItem)
        
        statusItemMenu.addItem(NSMenuItem.separator())
        
        // update interval
        let updateSubMenu = NSMenu()
        let updateMenu = NSMenuItem(title: "Update speed", action: nil, keyEquivalent: "")
        
        for updateItem in updateIntervalName {
            let newItem = NSMenuItem(title: updateItem + " s", action: #selector(changeUpdateSpeedClick(sender:)), keyEquivalent: "")
            if updateItem == String(updateInterval) {
                newItem.state = .on
            } else {
                newItem.state = .off
            }
            updateSubMenu.addItem(newItem)
        }
        statusItemMenu.addItem(updateMenu)
        statusItemMenu.setSubmenu(updateSubMenu, for: updateMenu)
        
        let spinnersSubMenu = NSMenu()
        let spinnersMenu = NSMenuItem(title: "Spinners", action: nil, keyEquivalent: "")
        
        for spinnersItem in spinners.keys {
            let newItem = NSMenuItem(title: spinnersItem, action: #selector(changeSpinnerClick(sender:)), keyEquivalent: "")
            let image = NSImage(named: spinnersItem + " 1")!
            image.size = NSSize(width: 19 / image.size.height * image.size.width, height: 19)
            newItem.image = image
            spinnersSubMenu.addItem(newItem)
        }
        statusItemMenu.addItem(spinnersMenu)
        statusItemMenu.setSubmenu(spinnersSubMenu, for: spinnersMenu)
        
        statusItemMenu.addItem(NSMenuItem.separator())
        statusItemMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        
        changeSpinner(setName: spinnerActive)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        closePopoverMenu(sender: self)
        stopRunning()
        UserDefaults.standard.set(spinnerActive, forKey: "group.spinnerActive")
        UserDefaults.standard.set(updateInterval, forKey: "group.spinnerUpdateInterval")
        UserDefaults.standard.set(keyRemap, forKey: "group.keyRemap")
        UserDefaults.standard.set(enableStatusText, forKey: "group.enableStatusText")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }


}
