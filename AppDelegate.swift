//  Copyright 2025 Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa
import Foundation
import SimplyCoreAudio

var spinnerActive: String!
var enableStatusText: Bool = false
var updateInterval: Double = 1.0
var keyRemap: Bool = false
var isDeviceChanged: Bool = true // update display menu on application start
var useLocalization: Bool = true
let ActivityData = AKservice()
let simplyCA = SimplyCoreAudio()

func localizedString(_ key: String.LocalizationValue) -> String {
    if useLocalization {
        return String(localized: key)
    } else {
        return String(localized: key, table: "English")
    }
}

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemMenu: NSMenu!
    private var sHelper = Helper()
    var statusItem: NSStatusItem = {
        return NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    }()
    
    private var cpuTimer: Timer? = nil
    private var spinnerTimer: Timer? = nil
    private var frames: [NSImage] =  []
    private var curFrame: Int = 0
    private var maxFrame: Int = 0
    private let popover = NSPopover()
    private var updateIntervalName = ["0.5", "1.0", "1.5", "2.0"]
    private var spinners = ["Loader" : 8, "Grey Loader" : 18, "Cirrcles": 8, "Dots": 12, "Pie": 6, "Rainbow Pie": 15, "Recharges": 8, "Cat": 5]
    
    @objc private func aboutWindow(sender: NSStatusItem) {
        let appCurrentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let anAbout = NSAlert()
        anAbout.messageText = "System Spinner " + appCurrentVersion!
        anAbout.informativeText = localizedString("System Spinner provides macOS system information in status bar. Minimal, small and light")
        anAbout.alertStyle = .informational
        anAbout.addButton(withTitle: localizedString("Goto site"))
        anAbout.addButton(withTitle: localizedString("Close"))
        if anAbout.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(URL(string: sHelper.appAboutUrl)!)
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
    
    private func changeSpinner(spinnerName: String, spinnerFrames: Int) {
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
        saveParams()
    }
    
    @objc private func WakeNotification() {
        isDeviceChanged = true // maybe devices changed?
        startRunning()
    }
    
    @objc private func startRunning() {
        cpuTimer?.invalidate()
        cpuTimer = Timer(timeInterval: updateInterval, repeats: true, block: { [weak self] _ in
            self?.updateUsage()
        })
        RunLoop.main.add(cpuTimer!, forMode: .common)
        cpuTimer?.fire()
    }
    
    @objc private func stopRunning() {
        closePopoverMenu(sender: self)
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
            self?.statusItem.button?.image = self?.frames[self!.curFrame]
            
        })
        RunLoop.main.add(spinnerTimer!, forMode: .common)
        
        // check if we need update display and menu
        if isDeviceChanged {
            isDeviceChanged = false
            displayDeviceChanged()
        }
    }
    
    @objc static func doChangeDevice() {
        isDeviceChanged = true
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
        changeSpinner(spinnerName: sender.title, spinnerFrames: Int(spinners[sender.title]!))
    }
    
    @objc private func analitycstApp(sender: NSMenuItem) {
        sHelper.openAnalitycstApp()
    }
    
    @objc private func changeUpdateSpeedClick(sender: NSMenuItem) {
        stopRunning()
        
        for menuItem in statusItemMenu.items { // set all submenu state off
            if menuItem.hasSubmenu && menuItem.title == sender.parent?.title {
                for subMenuItem in menuItem.submenu!.items {
                    subMenuItem.state = .off
                }
            }
        }
        updateInterval = Double(sender.title)!
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
        saveParams()
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
        saveParams()
    }
    
    @objc private func changelocalizeClick(sender: NSMenuItem) {
        sHelper.needRestart()
        if useLocalization {
            sender.state = .off
            useLocalization = false
        } else {
            sender.state = .on
            useLocalization = true
        }
        saveParams()
    }
    
    @objc private func displayDeviceChanged() {
        var displayMenuItem: NSMenuItem = NSMenuItem()
        let displaySubMenu = NSMenu()
        
        DisplayManager.shared.saveBrightnessVolumeValue()
        DisplayManager.shared.configureDisplays()
        
        // let find menu intem
        for menuItem in statusItemMenu.items {
            if menuItem.title == localizedString("HDMI/DVI DDC enabled") {
                displayMenuItem = menuItem
            }
        }
        
        for displayItem in DisplayManager.shared.displays {
            let newItem = NSMenuItem(title: displayItem.name, action: #selector(WakeNotification), keyEquivalent: "")
            
            if displayItem.isBuiltIn() {
                newItem.action = nil
            }
            
            displaySubMenu.addItem(newItem)
        }
        
        displayMenuItem.submenu = displaySubMenu
        
        if sHelper.checkPrivileges() {
            MediaKeyTapManager.shared.updateMediaKeyTap()
        }
        
        // check for keyboadr blacklight controll
        for menuItem in statusItemMenu.items {
            if menuItem.title == localizedString("Keyboard backlight (F5/F6)") {
                if keyRemap {
                    menuItem.state = .on
                } else {
                    menuItem.state = .off
                }
                if DisplayManager.shared.isAppleDisplayPresent() {
                    menuItem.action = #selector(changeRemapClick(sender:))
                    sHelper.remapKeysBacklight(toggle: keyRemap)
                } else {
                    menuItem.action = nil
                    sHelper.remapKeysBacklight(toggle: false)
                }
            }
        }
        
        // Load saved values
        DisplayManager.shared.loadBrightnessVolumeValue()
        
        // Check new version?
        sHelper.hasNewVersion()
    }
    
    @objc private func changeStatusMenuClick(sender: NSMenuItem) {
        if enableStatusText {
            sender.state = .off
            enableStatusText = false
        } else {
            sender.state = .on
            enableStatusText = true
        }
        saveParams()
    }
    
    private func saveParams() {
        UserDefaults.standard.set(spinnerActive, forKey: "group.spinnerActive")
        UserDefaults.standard.set(updateInterval, forKey: "group.spinnerUpdateInterval")
        UserDefaults.standard.set(keyRemap, forKey: "group.keyRemap")
        UserDefaults.standard.set(enableStatusText, forKey: "group.enableStatusText")
        UserDefaults.standard.set(useLocalization, forKey: "group.useLocalization")
        DisplayManager.shared.saveBrightnessVolumeValue()
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        spinnerActive = UserDefaults.standard.string(forKey: "group.spinnerActive") ?? "Loader"
        updateInterval = Double(UserDefaults.standard.string(forKey: "group.spinnerUpdateInterval") ?? String(updateInterval))!
        keyRemap = Bool(UserDefaults.standard.bool(forKey: "group.keyRemap"))
        enableStatusText = Bool(UserDefaults.standard.bool(forKey: "group.enableStatusText"))
        useLocalization = Bool(UserDefaults.standard.bool(forKey: "group.useLocalization"))
        
        if let button = statusItem.button {
            button.action = #selector(togglePopover(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        }
        
        popover.contentViewController = UsageViewController.freshController()
        
        // create pop up menu
        statusItemMenu = NSMenu()
        
        // open Analytics
        statusItemMenu.addItem(NSMenuItem(title: localizedString("Activity Monitor"), action: #selector(analitycstApp(sender:)), keyEquivalent: ""))
        
        // Text status in Menu
        let statusItem = NSMenuItem(title: localizedString("Show CPU usage in menu"), action: #selector(changeStatusMenuClick(sender:)), keyEquivalent: "")
        if enableStatusText {
            statusItem.state = .on
        }
        statusItemMenu.addItem(statusItem)
        
        // launch At Login
        let launchAtLoginItem = NSMenuItem(title: localizedString("Enable Autostart"), action: #selector(changeLaunchAtLogin(sender:)), keyEquivalent: "")
        if sHelper.isAutoLaunch {
            launchAtLoginItem.state = .on
        }
        statusItemMenu.addItem(launchAtLoginItem)
        statusItemMenu.addItem(NSMenuItem.separator())
        
        // Display controll support Menu
        let displayItem = NSMenuItem(title: localizedString("HDMI/DVI DDC enabled"), action:  #selector(WakeNotification), keyEquivalent: "")
        statusItemMenu.addItem(displayItem)
        statusItemMenu.setSubmenu(NSMenu(), for: displayItem)
        
        // Remap Menu
        let remapItem = NSMenuItem(title: localizedString("Keyboard backlight (F5/F6)"), action: #selector(changeRemapClick(sender:)), keyEquivalent: "")
        if keyRemap && DisplayManager.shared.isAppleDisplayPresent() {
            remapItem.state = .on
            sHelper.remapKeysBacklight(toggle: keyRemap)
        } else {
            remapItem.action = nil
            sHelper.remapKeysBacklight(toggle: false)
        }
        statusItemMenu.addItem(remapItem)
        
        // Localize Item
        let localizeItem = NSMenuItem(title: localizedString("Use system language"), action: #selector(changelocalizeClick(sender:)), keyEquivalent: "")
        if useLocalization {
            localizeItem.state = .on
        }
        statusItemMenu.addItem(localizeItem)
        statusItemMenu.addItem(NSMenuItem.separator())
        
        // update interval
        let updateSubMenu = NSMenu()
        let updateMenu = NSMenuItem(title: localizedString("Update speed (s)"), action: nil, keyEquivalent: "")
        
        for updateItem in updateIntervalName {
            let newItem = NSMenuItem(title: updateItem, action: #selector(changeUpdateSpeedClick(sender:)), keyEquivalent: "")
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
        let spinnersMenu = NSMenuItem(title: localizedString("Spinners"), action: nil, keyEquivalent: "")
        
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
        statusItemMenu.addItem(NSMenuItem(title: localizedString("About"), action: #selector(aboutWindow(sender:)), keyEquivalent: ""))
        statusItemMenu.addItem(NSMenuItem(title: localizedString("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        
        // start spinning!
        changeSpinner(spinnerName: spinnerActive, spinnerFrames: Int(spinners[spinnerActive]!))
        
        // if we wakup
        NotificationCenter.default.addObserver(self, selector: #selector(WakeNotification), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(WakeNotification), name: NSWorkspace.screensDidWakeNotification, object: nil)
        
        // if we go to sleep
        NotificationCenter.default.addObserver(self, selector: #selector(stopRunning), name: NSWorkspace.willSleepNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stopRunning), name: NSWorkspace.screensDidSleepNotification, object: nil)
        
        // mouse click event
        NSEvent.addGlobalMonitorForEvents(matching: [NSEvent.EventTypeMask.leftMouseDown,NSEvent.EventTypeMask.rightMouseDown], handler: { [self](event: NSEvent) in
            closePopoverMenu(sender: self)
        })
        
        // change audio device?
        NotificationCenter.default.addObserver(self, selector: #selector(WakeNotification), name: Notification.Name.defaultOutputDeviceChanged, object: nil)
        
        // change monitor device?
        CGDisplayRegisterReconfigurationCallback({ displayID, flags, userInfo in AppDelegate.doChangeDevice()}, nil)
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        stopRunning()
        saveParams()
        sHelper.remapKeysBacklight(toggle: false)
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
