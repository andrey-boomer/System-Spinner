//  Copyright 2025 Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa
import Foundation
import SimplyCoreAudio

var spinnerActive: String!
var enableStatusText: Bool = false
var updateInterval: Double = 1.0
var isDeviceChanged: Bool = true // update display menu on application start
var useLocalization: Bool = true
var spinnersEffectSelected : Int = 1
var spinnersRotationInvert: Bool = false
let ActivityData = AKservice()
let simplyCA = SimplyCoreAudio()

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
    private var spinnersEffect = [
        localizedString("Original")  : 1,
        localizedString("White opage 80%") : 2,
        localizedString("Black opage 80%") : 3,
        localizedString("Automatic Dark/White mode") : 4
    ]
    private let spinners: [String: [Int]] =  [ // [name: [item count, can use effect?]]
        "Blue Ball" : [19, 1],
        "Cat" : [5, 1],
        "Circles Two" : [9, 1],
        "Cirrcles" : [8, 0],
        "Color Balls" : [17, 1],
        "Color Well" : [20, 0],
        "Dots" : [12, 0],
        "Delay" : [17, 1],
        "Grey Loader" : [18, 0],
        "Loader" : [8, 0],
        "Pie" : [6, 0],
        "Rainbow Pie" : [15, 0],
        "Recharges" : [ 8, 1],
        "Rotation Color Well" : [24, 0],
        "Waves" : [17, 1]
    ]
    
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
    
    private func changeSpinner(spinnerName: String) {
        stopRunning()
        spinnerActive = spinnerName
        let spinnerFrames: Int = spinners[spinnerName]![0]
        
        // load spinner
        frames = {
            return (0 ..< spinnerFrames).map { n in
                var image = NSImage(named: spinnerName + " \(n)")!
                image.size = NSSize(width: (NSStatusBar.system.thickness - 2) / image.size.height * image.size.width, height: (NSStatusBar.system.thickness - 2))
                // Apply image effect
                if spinners[spinnerName]![1] > 0 { switch spinnersEffectSelected {
                    case 2: // White opage 80%
                        image.isTemplate = true
                        image = image.image(with: NSColor(red: 1, green: 1, blue: 1, alpha: 0.8))
                        break
                    case 3: // Black opage 80%
                        image.isTemplate = true
                        image = image.image(with: NSColor(red: 0, green: 0, blue: 0, alpha: 0.8))
                        break
                    case 4: // Automatic
                        image.isTemplate = true
                        break
                    default:
                        image.isTemplate = false
                        break
                    }
                }
             return image
            }
        }()
        curFrame = 0
        maxFrame = spinnerFrames
        startRunning()
        
        // update effect menu
        for menuItem in statusItemMenu.items {
            if menuItem.title == localizedString("Spinners Effects") {
                if spinners[spinnerName]![1] > 0 {
                    menuItem.action = #selector(changeSpinnerEffectClick(sender:))
                } else {
                    menuItem.action = nil
                }
            }
        }
        
        // update spinners menu
        for menuItem in statusItemMenu.items {
            if menuItem.hasSubmenu && menuItem.title == localizedString("Spinners") {
                for subMenuItem in menuItem.submenu!.items {
                    if subMenuItem.title == spinnerName {
                        subMenuItem.state = .on
                    } else {
                        subMenuItem.state = .off
                    }
                }
            }
        }
        
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
        curFrame = curFrame + (spinnersRotationInvert ? -1 : 1)
        if curFrame > maxFrame - 1 {
            curFrame = 0
        } else if curFrame < 0 {
            curFrame = maxFrame - 1
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
            self!.curFrame = self!.curFrame + (spinnersRotationInvert ? -1 : 1)
            if self!.curFrame == self!.maxFrame {
                self!.curFrame = 0
            } else if self!.curFrame < 0 {
                self!.curFrame = self!.maxFrame - 1
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
        changeSpinner(spinnerName: sender.title)
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
        updateInterval = Double(sender.title.replacingOccurrences(of: localizedString("Second"), with: ""))!
        sender.state = .on
        startRunning()
    }
    
    @objc private func changeSpinnerEffectClick(sender: NSMenuItem) {
        stopRunning()
        
        for menuItem in statusItemMenu.items { // set all submenu state off
            if menuItem.hasSubmenu && menuItem.title == sender.parent?.title {
                for subMenuItem in menuItem.submenu!.items {
                    subMenuItem.state = .off
                }
            }
        }
        
        for (_, value) in spinnersEffect.enumerated() {
            if value.key == sender.title {
                spinnersEffectSelected = value.value
            }
        }
            
        sender.state = .on
        changeSpinner(spinnerName: spinnerActive)
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
    
    @objc private func changeSpinnersRotationInvert(sender: NSMenuItem) {
        if spinnersRotationInvert {
            sender.state = .off
            spinnersRotationInvert = false
        } else {
            sender.state = .on
            spinnersRotationInvert = true
        }
        saveParams()
    }
    
    @objc private func changelocalizeClick(sender: NSMenuItem) {
        if useLocalization {
            sender.state = .off
            useLocalization = false
        } else {
            sender.state = .on
            useLocalization = true
        }
        saveParams()
        updateStatusMenu()
        changeSpinner(spinnerName: spinnerActive)
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
        UserDefaults.standard.set(enableStatusText, forKey: "group.enableStatusText")
        UserDefaults.standard.set(useLocalization, forKey: "group.useLocalization")
        UserDefaults.standard.set(spinnersEffectSelected, forKey: "group.spinnersEffectSelected")
        UserDefaults.standard.set(spinnersRotationInvert, forKey: "group.spinnersRotationInvert")
        
        DisplayManager.shared.saveBrightnessVolumeValue()
    }
    
    private func updateStatusMenu() {
        // create pop up menu if in not menu
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
        
        // ---------------------------- Display controll Section ----------------------------
        let displayItem = NSMenuItem(title: localizedString("HDMI/DVI DDC enabled"), action:  #selector(WakeNotification), keyEquivalent: "")
        statusItemMenu.addItem(displayItem)
        statusItemMenu.setSubmenu(NSMenu(), for: displayItem)
        
        // Localize Item
        let localizeItem = NSMenuItem(title: localizedString("Use system language"), action: #selector(changelocalizeClick(sender:)), keyEquivalent: "")
        if useLocalization {
            localizeItem.state = .on
        }
        statusItemMenu.addItem(localizeItem)
        statusItemMenu.addItem(NSMenuItem.separator())
        
        // ---------------------------- Spinner Section ----------------------------
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
        
        let updateSubMenu = NSMenu()
        let updateMenu = NSMenuItem(title: localizedString("Data update every"), action: nil, keyEquivalent: "")
        
        for updateItem in updateIntervalName {
            let newItem = NSMenuItem(title: updateItem + localizedString("Second"), action: #selector(changeUpdateSpeedClick(sender:)), keyEquivalent: "")
            if updateItem == String(updateInterval) {
                newItem.state = .on
            } else {
                newItem.state = .off
            }
            updateSubMenu.addItem(newItem)
        }
        statusItemMenu.addItem(updateMenu)
        statusItemMenu.setSubmenu(updateSubMenu, for: updateMenu)
        
        let spinnersEffectSubMenu = NSMenu()
        let spinnersEffectMenu = NSMenuItem(title: localizedString("Spinners Effects"), action: nil, keyEquivalent: "")

        for (_, value) in spinnersEffect.enumerated() {
            let newItem = NSMenuItem(title: value.key, action: #selector(changeSpinnerEffectClick(sender:)), keyEquivalent: "")
            if value.value == spinnersEffectSelected {
                newItem.state = .on
            }
            spinnersEffectSubMenu.addItem(newItem)
        }
        statusItemMenu.addItem(spinnersEffectMenu)
        statusItemMenu.setSubmenu(spinnersEffectSubMenu, for: spinnersEffectMenu)
        
        let invertedItem = NSMenuItem(title: localizedString("Invert rotation"), action: #selector(changeSpinnersRotationInvert(sender:)), keyEquivalent: "")
        if spinnersRotationInvert {
            invertedItem.state = .on
        }
        statusItemMenu.addItem(invertedItem)
        
        statusItemMenu.addItem(NSMenuItem.separator())
        statusItemMenu.addItem(NSMenuItem(title: localizedString("About"), action: #selector(aboutWindow(sender:)), keyEquivalent: ""))
        statusItemMenu.addItem(NSMenuItem(title: localizedString("Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        
        isDeviceChanged = true
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        spinnerActive = UserDefaults.standard.string(forKey: "group.spinnerActive") ?? "Loader"
        updateInterval = Double(UserDefaults.standard.string(forKey: "group.spinnerUpdateInterval") ?? String(updateInterval))!
        enableStatusText = Bool(UserDefaults.standard.bool(forKey: "group.enableStatusText"))
        useLocalization = Bool(UserDefaults.standard.bool(forKey: "group.useLocalization"))
        spinnersEffectSelected = Int(UserDefaults.standard.string(forKey: "group.spinnersEffectSelected") ?? String(spinnersEffectSelected))!
        spinnersRotationInvert = Bool(UserDefaults.standard.bool(forKey: "group.spinnersRotationInvert"))
        print(updateInterval)
        if let button = statusItem.button {
            button.action = #selector(togglePopover(sender:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        }
        
        popover.contentViewController = UsageViewController.freshController()
        
        // create menu
        updateStatusMenu()
        
        // start spinning!
        changeSpinner(spinnerName: spinnerActive)
        
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
    }
    
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }
}
