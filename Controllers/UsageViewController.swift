//  Copyright 2025 Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa

class UsageViewController: NSViewController {
    private var dataTimer: Timer? = nil
    private var cpuProcessMenu: NSMenu!
    private var memProcessMenu: NSMenu!
    private let ioService = IOServiceData()
    
    @IBOutlet var fanStack: NSStackView!
    @IBOutlet var cpuTempStack: NSStackView!
    @IBOutlet var cpuLabel: NSTextField!
    @IBOutlet var cpuTempLabel: NSTextField!
    @IBOutlet var fanLabel: NSTextField!
    
    @IBOutlet var memPercentage: NSTextField!
    @IBOutlet var memPressure: NSTextField!
    @IBOutlet var memApp: NSTextField!
    @IBOutlet var memInactive: NSTextField!
    @IBOutlet var memComp: NSTextField!
    @IBOutlet var powerComp: NSTextField!
    
    @IBOutlet var cpuLevel: NSLevelIndicator!
    @IBOutlet var tempLevel: NSLevelIndicator!
    @IBOutlet var memLevel: NSLevelIndicator!
    @IBOutlet var pressureLevel: NSLevelIndicator!
    
    @IBOutlet var memAppBar: NSProgressIndicator!
    @IBOutlet var memInactiveBar: NSProgressIndicator!
    @IBOutlet var memCompBar: NSProgressIndicator!
    
    @IBOutlet var netLabel: NSTextField!
    
    @IBOutlet var cpuPopupButton: NSButton!
    @IBOutlet var memPopupButton: NSButton!
    
    @objc private func itemMenuClick(sender: NSMenuItem) {
        // no action yet
    }
    
    @objc private func cpuPopupAction(sender: NSButton) {
        cpuProcessMenu.removeAllItems()
        for item in ActivityData.getTopProcess().sorted(by: \.cpu) {
            if item.cpu > 0 {
                let menuItem = NSMenuItem(title: item.name + " (" + String(item.pid) + ") - " + String(item.cpu) + "%", action: #selector(itemMenuClick(sender:)), keyEquivalent: "")
                let image = item.icon
                image.size = NSSize(width: 19 / image.size.height * image.size.width, height: 19)
                menuItem.image = image
                menuItem.isEnabled = true
                cpuProcessMenu.addItem(menuItem)
            }
        }
        cpuProcessMenu.popUp(positioning: nil, at: NSPoint(x: -cpuProcessMenu.size.width/1.1, y: sender.frame.height + 5), in: sender)
    }
    
    @objc private func memPopupAction(sender: NSButton) {
        memProcessMenu.removeAllItems()
        for item in ActivityData.getTopProcess().sorted(by: \.mem) {
            if item.mem > 0.5 {
                let menuItem = NSMenuItem(title: item.name + " (" + String(item.pid) + ") " + String(item.realmem), action: #selector(itemMenuClick(sender:)), keyEquivalent: "")
                let image = item.icon
                image.size = NSSize(width: 19 / image.size.height * image.size.width, height: 19)
                menuItem.image = image
                memProcessMenu.addItem(menuItem)
            }
        }
        memProcessMenu.popUp(positioning: nil, at: NSPoint(x:  -memProcessMenu.size.width/1.1, y: sender.frame.height + 5), in: sender)
    }
    
    override func viewDidLoad() {
        
        //for autoresize
        self.preferredContentSize = NSMakeSize(self.view.frame.width, 100);
        
        // Air is not present fan
        if ioService.isAir {
            fanStack.removeFromSuperview()
        }
        
        // if no SMC, remove CPU temp data
        if !ioService.presentSMC {
            cpuTempStack.removeFromSuperview()
        }
        
        // create top cpu process menu
        cpuProcessMenu = NSMenu()
        cpuProcessMenu.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        cpuPopupButton.action =  #selector(cpuPopupAction(sender:))
        
        // create top mem process menu
        memProcessMenu  = NSMenu()
        memLevel.menu = memProcessMenu
        memProcessMenu.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        memPopupButton.action =  #selector(memPopupAction(sender:))
        
        super.viewDidLoad()
    }
    
    override func viewWillDisappear() {
        dataTimer?.invalidate()
        super.viewWillDisappear()
    }
    
    override func viewDidAppear() {
        dataTimer?.invalidate()
        dataTimer = Timer(timeInterval: updateInterval * 2, repeats: true, block: { [weak self] _ in
            self?.updateData()
        })
        RunLoop.main.add(dataTimer!, forMode: .common)
        dataTimer?.fire()
        
        super.viewDidAppear()
        view.window?.makeKey()
    }
    
    private func updateData() {
        ioService.update()
        ActivityData.updateAll()
        
        // CPU data
        cpuLabel.stringValue = localizedString("CPU Usage \(Int(ActivityData.cpuPercentage))%")
        cpuLevel.doubleValue = ActivityData.cpuPercentage / 5
        
        // power data
        if ioService.systemAdapter > 0 {
            powerComp.stringValue = "PWR: " + String(ioService.systemPower) + "w, DC: " + String(ioService.systemAdapter) + "w"
        } else if (ioService.systemBattery > 0 && ioService.systemAdapter > 0)  {
            powerComp.stringValue = "PWR: " + String(ioService.systemPower) + "w, BAT: " + String(ioService.systemBattery) + "w, DC: " + String(ioService.systemAdapter) + "w"
        } else {
            powerComp.stringValue = "PWR: " + String(ioService.systemPower) + "w, BAT: " + String(ioService.systemBattery) + "w"
        }
        
        // Air is not present fan
        if !ioService.isAir {
            var fanSpeed: Int = 0
            for (key, _) in ioService.fanSpeed.enumerated() {
                if key == 0 {
                    fanLabel.stringValue =  "fan " + String(ioService.fanSpeed[key])
                } else {
                    fanLabel.stringValue +=  " | " + String(ioService.fanSpeed[key])
                }
                fanSpeed += ioService.fanSpeed[key]
            }
            fanLabel.stringValue += " rpm"
            if fanSpeed == 0 {
                fanLabel.stringValue =  localizedString("fan is stoped")
            }
        }
        
        // if presentSMC
        if ioService.presentSMC {
            // temp data
            cpuTempLabel.stringValue = localizedString("CPU Temp \(String(Int(round(ioService.cpuTemp))))°С")
            tempLevel.doubleValue = ioService.cpuTemp / 5
        }
        
        // memory data
        memPercentage.stringValue =  localizedString("Memory Usage \(Int(round(ActivityData.memPercentage)))%")
        memLevel.doubleValue = ActivityData.memPercentage / 5
        
        memPressure.stringValue = localizedString("Pressure \(Int(round(ActivityData.memPressure)))%")
        pressureLevel.doubleValue = ActivityData.memPressure / 5
        
        memApp.stringValue = String(Int(round(ActivityData.memApp))) + "% (App)"
        memAppBar.doubleValue = ActivityData.memApp
        
        memInactive.stringValue = String(Int(round(ActivityData.memInactive))) + "% (NAct)"
        memInactiveBar.doubleValue = ActivityData.memInactive
        
        memComp.stringValue = String(Int(round(ActivityData.memCompressed))) + "% (Comp)"
        memCompBar.doubleValue = ActivityData.memCompressed
        
        netLabel.stringValue = ActivityData.netIp + "\n↓ " + String(Int(ActivityData.netIn.value)) + ActivityData.netIn.unit + " | ↑ " + String(Int(ActivityData.netOut.value)) + ActivityData.netOut.unit
    }
}

extension UsageViewController {
    static func freshController() -> UsageViewController {
        let storyboard = NSStoryboard(name: NSStoryboard.Name("Main"), bundle: nil)
        let identifier = NSStoryboard.SceneIdentifier("UsageViewController")
        guard let viewcontroller = storyboard.instantiateController(withIdentifier: identifier) as? UsageViewController else {
            fatalError("Why cant i find UsageViewController? - Check Main.storyboard")
        }
        return viewcontroller
    }
}
