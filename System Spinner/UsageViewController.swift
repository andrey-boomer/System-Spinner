//
//  UsageViewController.swift
//  System Spinner
//
//  Created by Андрей Лысиков on 23.01.2024.
//

import Cocoa

class UsageViewController: NSViewController {
    
    let appDelegate = NSApp.delegate as! AppDelegate
    
    private var dataTimer: Timer? = nil
    private let ioService = IOServiceData()
    
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
        super.viewDidAppear()
    }
    
    private func updateData() {
        ioService.update()
        
        // CPU data
        cpuLabel.stringValue = "CPU Usage " + String(appDelegate.ActivityData.cpuUsage.percentage) + "%"
        cpuLevel.doubleValue = appDelegate.ActivityData.cpuUsage.percentage / 5
        cpuTempLabel.stringValue = "CPU Temp " + String(ioService.cpuTemp)  + " °С"
        tempLevel.doubleValue = Double(ioService.cpuTemp / 5)
        
        // power data
        powerComp.stringValue = "System power " + String(ioService.systemPower) + " watt"
        
        // Fan data
        if ioService.isFanPresent {
            fanLabel.stringValue =  "fan " + String(ioService.fan1Speed) + " | " + String(ioService.fan2Speed) + " rpm"
        } else {
            fanLabel.stringValue =  "no fan found"
        }
        
        // memory data
        memPercentage.stringValue = "Memory Usage " + String(appDelegate.ActivityData.memoryPerformance.percentage) + "%"
        memLevel.doubleValue = appDelegate.ActivityData.memoryPerformance.percentage / 10
        
        memPressure.stringValue = "Pressure " + String(appDelegate.ActivityData.memoryPerformance.pressure) + "%"
        pressureLevel.doubleValue = appDelegate.ActivityData.memoryPerformance.pressure / 10
        
        memApp.stringValue = String(Int(appDelegate.ActivityData.memoryPerformance.app)) + "% (App)"
        memAppBar.doubleValue = appDelegate.ActivityData.memoryPerformance.app
        
        memWired.stringValue = String(Int(appDelegate.ActivityData.memoryPerformance.wired)) + "% (Wrd)"
        memWiredBar.doubleValue = appDelegate.ActivityData.memoryPerformance.wired
        
        memComp.stringValue = String(Int(appDelegate.ActivityData.memoryPerformance.compressed)) + "% (Zip)"
        memCompBar.doubleValue = appDelegate.ActivityData.memoryPerformance.compressed
        
        netLabel.stringValue = "↓ " + String(appDelegate.ActivityData.networkConnection.download.value) + appDelegate.ActivityData.networkConnection.download.unit + " | ↑ " + String(appDelegate.ActivityData.networkConnection.upload.value) + appDelegate.ActivityData.networkConnection.upload.unit
        
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
