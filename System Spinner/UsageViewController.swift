//
//  UsageViewController.swift
//  System Spinner
//
//  Copyright 2024 Andrey Lysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa

class UsageViewController: NSViewController {
    
    let appDelegate = NSApp.delegate as! AppDelegate
    
    private var dataTimer: Timer? = nil
    private let ioService = IOServiceData()
    
    @IBOutlet var cpuTempStack: NSStackView!
    @IBOutlet var cpuLabel: NSTextField!
    @IBOutlet var cpuTempLabel: NSTextField!
    @IBOutlet var fanLabel: NSTextField!
    
    @IBOutlet var memPercentage: NSTextField!
    @IBOutlet var memPressure: NSTextField!
    @IBOutlet var memApp: NSTextField!
    @IBOutlet var memWired: NSTextField!
    @IBOutlet var memComp: NSTextField!
    @IBOutlet var powerComp: NSTextField!
    
    @IBOutlet var cpuLevel: NSLevelIndicator!
    @IBOutlet var tempLevel: NSLevelIndicator!
    @IBOutlet var memLevel: NSLevelIndicator!
    @IBOutlet var pressureLevel: NSLevelIndicator!
    
    @IBOutlet var memAppBar: NSProgressIndicator!
    @IBOutlet var memWiredBar: NSProgressIndicator!
    @IBOutlet var memCompBar: NSProgressIndicator!
    
    @IBOutlet var netLabel: NSTextField!
    
    override func viewDidLoad() {
        // check, do is run on M1 chip? (CMS is not present for than model)
        if ioService.cpuCurrentModel == "M1" {
            // hide cpu power and fan data
            cpuTempStack.removeFromSuperview()
        }
        super.viewDidLoad()
    }
    
    override func viewWillDisappear() {
        dataTimer?.invalidate()
        super.viewWillDisappear()
    }
    
    override func viewDidAppear() {
        dataTimer = Timer(timeInterval: appDelegate.updateInterval, repeats: true, block: { [weak self] _ in
             self?.updateData()
        })
        RunLoop.main.add(dataTimer!, forMode: .common)
        dataTimer?.fire()
        
        // check, do is run on M1 chip? (CMS is not present for than model)
        if ioService.cpuCurrentModel == "M1" {
            self.preferredContentSize = NSMakeSize(self.view.frame.size.width, 256);
        }
        super.viewDidAppear()
    }
    
    private func updateData() {
        ioService.update()
        
        // CPU data
        cpuLabel.stringValue = "CPU Usage " + String(appDelegate.ActivityData.cpuPercentage) + "%"
        cpuLevel.doubleValue = appDelegate.ActivityData.cpuPercentage / 5
        
        // check, do is run on M1 chip? (CMS is not present for than model)
        if ioService.cpuCurrentModel != "M1" {
            // temp data
            cpuTempLabel.stringValue = "CPU Temp " + String(ioService.cpuTemp)  + " °С"
            tempLevel.doubleValue = ioService.cpuTemp / 5
            
            // power data
            powerComp.stringValue = "System power " + String(ioService.systemPower) + " watt"
            
            // Fan data
            fanLabel.stringValue =  "fan " + String(ioService.fan1Speed) + " | " + String(ioService.fan2Speed) + " rpm"
        }
        
        // memory data
        memPercentage.stringValue = "Memory Usage " + String(appDelegate.ActivityData.memPercentage) + "%"
        memLevel.doubleValue = appDelegate.ActivityData.memPercentage / 10
        
        memPressure.stringValue = "Pressure " + String(appDelegate.ActivityData.memPressure) + "%"
        pressureLevel.doubleValue = appDelegate.ActivityData.memPressure / 10
        
        memApp.stringValue = String(Int(appDelegate.ActivityData.memApp)) + "% (App)"
        memAppBar.doubleValue = appDelegate.ActivityData.memApp
        
        memWired.stringValue = String(Int(appDelegate.ActivityData.memWired)) + "% (Wrd)"
        memWiredBar.doubleValue = appDelegate.ActivityData.memWired
        
        memComp.stringValue = String(Int(appDelegate.ActivityData.memCompressed)) + "% (Zip)"
        memCompBar.doubleValue = appDelegate.ActivityData.memCompressed
        
        netLabel.stringValue = appDelegate.ActivityData.netIp + "\n↓ " + String(appDelegate.ActivityData.netIn.value) + appDelegate.ActivityData.netIn.unit + " | ↑ " + String(appDelegate.ActivityData.netOut.value) + appDelegate.ActivityData.netOut.unit
        
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
