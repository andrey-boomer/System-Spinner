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
    private var sHelper = Helper()
    
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
        ActivityData.updateCpuOnly()
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
    
    @objc private func aboutWindow(sender: NSStatusItem) {
        let appCurrentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let anAbout = NSAlert()
        anAbout.messageText = "System Spinner " + appCurrentVersion!
        anAbout.informativeText = "System Spinner provides macOS system information in status bar. Minimal, small and light"
        anAbout.alertStyle = .informational
        anAbout.addButton(withTitle: "Go to App site")
        anAbout.addButton(withTitle: "Close")
        if anAbout.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: sHelper.appAboutUrl)!)
        }
    }
    
    @objc private func stopRunningNotify(_ notification: NSNotification) {
        closePopoverMenu(sender: self)
        stopRunning()
    }
    
    @objc private func startRunningNotify(_ notification: NSNotification) {
        startRunning()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            self.sHelper.hasNewVersion()
         }
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
    
    @objc private func analitycstApp(sender: NSMenuItem) {
        sHelper.openAnalitycstApp()
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
    
    @objc private func changeLaunchAtLogin(sender: NSMenuItem) {
        if sHelper.isAutoLaunch {
            sender.state = .off
            sHelper.isAutoLaunch = false
        } else {
            sender.state = .on
            sHelper.isAutoLaunch = true
        }
    }
    
    @objc private func changeRemapClick(sender: NSMenuItem) {
        if keyRemap {
            sender.state = .off
            keyRemap = false
        } else {
            sender.state = .on
            keyRemap = true
        }
        sHelper.remapKeysBacklight(toggle: keyRemap)
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

        // create pop up menu
        statusItemMenu = NSMenu()
        
        // open Analytics
        statusItemMenu.addItem(NSMenuItem(title: "Activity Monitor", action: #selector(analitycstApp(sender:)), keyEquivalent: ""))
        
        // Remap Menu
        let remapItem = NSMenuItem(title: "Keyboard backlight (F5/F6)", action: #selector(changeRemapClick(sender:)), keyEquivalent: "")
        if keyRemap {
            remapItem.state = .on
        }
        sHelper.remapKeysBacklight(toggle: keyRemap)
        statusItemMenu.addItem(remapItem)
        
        // Text status in Menu
        let statusItem = NSMenuItem(title: "Show CPU usage in menu", action: #selector(changeStatusMenuClick(sender:)), keyEquivalent: "")
        if enableStatusText {
            statusItem.state = .on
        }
        statusItemMenu.addItem(statusItem)
        
        // launch At Login
        let launchAtLoginItem = NSMenuItem(title: "Enable Autostart", action: #selector(changeLaunchAtLogin(sender:)), keyEquivalent: "")
        if sHelper.isAutoLaunch {
            launchAtLoginItem.state = .on
        }
        statusItemMenu.addItem(launchAtLoginItem)
        
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
        statusItemMenu.addItem(NSMenuItem(title: "About", action: #selector(aboutWindow(sender:)), keyEquivalent: ""))
        statusItemMenu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        
        // System Hooks
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(stopRunningNotify(_:)),
                         name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(startRunningNotify(_:)),
                         name: NSWorkspace.didWakeNotification, object: nil)
        
        NSEvent.addGlobalMonitorForEvents(matching: [NSEvent.EventTypeMask.leftMouseDown,NSEvent.EventTypeMask.rightMouseDown], handler: { [self](event: NSEvent) in
            closePopoverMenu(sender: self)
        })
                
        // end initialization
        changeSpinner(setName: spinnerActive)
        sHelper.hasNewVersion()
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
