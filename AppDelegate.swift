//
//  AppDelegate.swift
//  System Spinner
//
//  Copyright 2024 Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa
import Foundation

var app: AppDelegate!
var spinnerActive: String!
var enableStatusText: Bool = false
var updateInterval: Double = 1.0
var keyRemap: Bool = false
var displayControll: Bool = true
var brightnessValue: Float = 1
var volumeValue: Float = 1
let ActivityData = AKservice()
var statusItem: NSStatusItem = {
    return NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
}()

@main
class AppDelegate: NSObject, NSApplicationDelegate{
    private var statusItemMenu: NSMenu!
    private var sHelper = Helper()
    private var mediaKeyTap = MediaKeyTapManager()
    private var displayList = DisplayManager()
    private var updateIntervalName = ["0.5", "1.0", "1.5", "2.0"]
    private var spinners = ["Loader" : 8, "Grey Loader" : 18, "Cirrcles": 8, "Dots": 12, "Pie": 6, "Rainbow Pie": 15, "Recharges": 8, "Cat": 5]
    
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
        sHelper.closePopoverMenu(sender: self)
        sHelper.stopRunning()
    }
    
    @objc private func startRunningNotify(_ notification: NSNotification) {
        sHelper.startRunning()
        sHelper.hasNewVersion()
    }
    
    @objc private func togglePopover(sender: NSStatusItem) {
        let event = NSApp.currentEvent!
        if event.type == NSEvent.EventType.leftMouseUp {
            if sHelper.popover.isShown {
                sHelper.closePopoverMenu(sender: sender)
            } else {
                statusItem.menu = nil
                sHelper.showPopover(sender: sender)
            }
        } else {
            statusItem.menu = statusItemMenu
            statusItem.button?.performClick(nil)
        }
    }
    
    @objc private func changeSpinnerClick(sender: NSMenuItem) {
        sHelper.changeSpinner(spinnerName: sender.title, spinnerFrames: Int(spinners[sender.title]!))
    }
    
    @objc private func analitycstApp(sender: NSMenuItem) {
        sHelper.openAnalitycstApp()
    }
        
    @objc private func changeUpdateSpeedClick(sender: NSMenuItem) {
        sHelper.stopRunning()
        
        for menuItem in statusItem.menu!.items { // set all submenu state off
            if menuItem.hasSubmenu && menuItem.title == sender.parent?.title {
                for subMenuItem in menuItem.submenu!.items {
                    subMenuItem.state = .off
                }
            }
        }
        
        updateInterval = Double(sender.title.replacingOccurrences(of: " s", with: ""))!
        sender.state = .on
        sHelper.startRunning()
    }
    
    @objc private func displayItemMenuClick(sender: NSMenuItem) {
        displayDeviceChanged()
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
    
    @objc private func changeDisplayControll(sender: NSMenuItem) {
        if displayControll {
            sender.state = .off
            displayControll = false
            mediaKeyTap.Stop()
        } else if MediaKeyTapManager.readPrivileges() && displayControll && !displayList.displays.isEmpty {
            sender.state = .on
            displayControll = true
            mediaKeyTap.Start()
        }
    }
    
    @objc private func displayDeviceChangedNotify(_ notification: NSNotification) {
        displayDeviceChanged()
    }
    
    private func displayDeviceChanged() {
        displayList.configureDisplays()
        
        for menuItem in statusItem.menu!.items {
            if menuItem.hasSubmenu && menuItem.title == "Enable DDC controll" {
                let displaySubMenu = NSMenu()
                for displayItem in displayList.displays {
                    let newItem = NSMenuItem(title: displayItem.name, action: #selector(displayItemMenuClick(sender:)), keyEquivalent: "")
                    displaySubMenu.addItem(newItem)
                }
                menuItem.submenu = displaySubMenu
            }
        }
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
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        spinnerActive = UserDefaults.standard.string(forKey: "group.spinnerActive") ?? "Loader"
        updateInterval = Double(UserDefaults.standard.string(forKey: "group.spinnerUpdateInterval") ?? "1.0")!
        keyRemap = Bool(UserDefaults.standard.bool(forKey: "group.keyRemap"))
        enableStatusText = Bool(UserDefaults.standard.bool(forKey: "group.enableStatusText"))
        displayControll = Bool(UserDefaults.standard.bool(forKey: "group.enableDisplayControll"))
        
        if let button = statusItem.button {
            button.action = #selector(togglePopover(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        }

        sHelper.popover.contentViewController = UsageViewController.freshController()

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
        
        // Display controll support Menu
        displayList.configureDisplays()
        let displayItem = NSMenuItem(title: "Enable DDC controll", action: #selector(changeDisplayControll(sender:)), keyEquivalent: "")
       
        let displaySubMenu = NSMenu()
        for displayItem in displayList.displays {
            let newItem = NSMenuItem(title: displayItem.name, action: #selector(displayItemMenuClick(sender:)), keyEquivalent: "")
            displaySubMenu.addItem(newItem)
        }
        
        if MediaKeyTapManager.readPrivileges() && displayControll && !displayList.displays.isEmpty {
            displayItem.state = .on
            statusItemMenu.setSubmenu(displaySubMenu, for: displayItem)
            mediaKeyTap.Start()
        } else {
            displayItem.isEnabled = false
        }
        statusItemMenu.addItem(displayItem)
    
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
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(stopRunningNotify(_:)),
                         name: NSWorkspace.screensDidSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(startRunningNotify(_:)),
                         name: NSWorkspace.screensDidWakeNotification, object: nil)
        DistributedNotificationCenter.default.addObserver(self, selector: #selector(displayDeviceChangedNotify(_:)),
                        name: NSNotification.Name(rawValue: kColorSyncDisplayDeviceProfilesNotification.takeRetainedValue() as String), object: nil)
        
        NSEvent.addGlobalMonitorForEvents(matching: [NSEvent.EventTypeMask.leftMouseDown,NSEvent.EventTypeMask.rightMouseDown], handler: { [self](event: NSEvent) in
            sHelper.closePopoverMenu(sender: self)
        })
        
        // Hook for Change Display
        CGDisplayRegisterReconfigurationCallback({ _, _, _ in app.displayDeviceChanged()}, nil)
        
        // end initialization
        sHelper.changeSpinner(spinnerName: spinnerActive, spinnerFrames: Int(spinners[spinnerActive]!))
        sHelper.hasNewVersion()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        sHelper.closePopoverMenu(sender: self)
        sHelper.stopRunning()
        UserDefaults.standard.set(spinnerActive, forKey: "group.spinnerActive")
        UserDefaults.standard.set(updateInterval, forKey: "group.spinnerUpdateInterval")
        UserDefaults.standard.set(keyRemap, forKey: "group.keyRemap")
        UserDefaults.standard.set(enableStatusText, forKey: "group.enableStatusText")
        UserDefaults.standard.set(displayControll, forKey: "group.enableDisplayControll")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
