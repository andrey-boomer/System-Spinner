//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa
import SwiftUI

class UsageViewController: NSViewController {
    private let metrics = MetricsService.shared
    private var metricsObserver: UUID?

    private let popupChart = NSPopover()
    private let dataModel = ChartDataModel()
    private var lastClickButton: NSButton? = nil
    private var powerHistory: String = ""
    private var fanHistory: String = ""
    private var lastPopupUpdate: Date = .distantPast
    private var forcesFullRefresh = false
    private var lastSnapshot: MetricsSnapshot = .empty

    private static let popupUpdateInterval: TimeInterval = 2
    private static let chartPointLimit = 500

    @IBOutlet var fanStack: NSStackView!
    @IBOutlet var cpuTempStack: NSStackView!
    @IBOutlet var cpuLabel: NSTextField!
    @IBOutlet var gpuLabel: NSTextField!
    @IBOutlet var cpuTempLabel: NSTextField!
    @IBOutlet var fanLabel: NSTextField!
    @IBOutlet var memSwapLabel: NSTextField!

    @IBOutlet var memPercentage: NSTextField!
    @IBOutlet var memPressure: NSTextField!
    @IBOutlet var memApp: NSTextField!
    @IBOutlet var memInactive: NSTextField!
    @IBOutlet var memComp: NSTextField!
    @IBOutlet var powerComp: NSTextField!

    @IBOutlet var cpuLevel: SegmentedLevelView!
    @IBOutlet var gpuLevel: SegmentedLevelView!
    @IBOutlet var tempLevel: SegmentedLevelView!
    @IBOutlet var memLevel: SegmentedLevelView!
    @IBOutlet var pressureLevel: SegmentedLevelView!
    @IBOutlet var memSwapLevel: SegmentedLevelView!

    @IBOutlet var memAppBar: SegmentedLevelView!
    @IBOutlet var memInactiveBar: SegmentedLevelView!
    @IBOutlet var memCompBar: SegmentedLevelView!

    @IBOutlet var netLabel: NSTextField!

    @IBOutlet var cpuChartPopupButton: NSButton!
    @IBOutlet var memChartPopupButton: NSButton!

    @IBAction func cpuPopupButtonAction(_ sender: NSButton) {
        showChart(from: sender)
    }

    @IBAction func memPopupButtonAction(_ sender: NSButton) {
        showChart(from: sender)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        self.preferredContentSize = NSMakeSize(self.view.frame.width, 100)

        if !metrics.hasFans {
            fanStack.removeFromSuperview()
        }

        if !metrics.sensorsAvailable {
            cpuTempStack.removeFromSuperview()
        }

        for bar in [memAppBar, memInactiveBar, memCompBar] {
            bar?.barHeight = 3
        }

        let hostingController = NSHostingController(rootView: ChartContentView(chartItems: dataModel))
        hostingController.preferredContentSize = NSSize(width: 420, height: 400)
        popupChart.contentViewController = hostingController
        popupChart.behavior = .applicationDefined
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        let token = UUID()
        metricsObserver = token

        Task { [weak self] in
            guard let self else { return }

            await metrics.setDetailedMetricsEnabled(true)
            await metrics.addObserver(token) { [weak self] snapshot in
                self?.apply(snapshot)
            }

            guard metricsObserver == token else {
                await metrics.removeObserver(token)
                await metrics.setDetailedMetricsEnabled(false)
                return
            }

            forcesFullRefresh = true
            apply(await metrics.snapshot)
            _ = await metrics.topProcesses()
        }
        for level in [cpuLevel, gpuLevel, tempLevel, memLevel, pressureLevel, memSwapLevel,
                      memAppBar, memInactiveBar, memCompBar] {
            level?.needsDisplay = true
        }

        popupChart.animates = Preferences.shared.usesPopUpAnimation
        view.window?.makeKey()
    }

    override func viewWillDisappear() {
        closeDetail()

        let token = metricsObserver
        metricsObserver = nil

        Task { [metrics] in
            if let token {
                await metrics.removeObserver(token)
            }
            await metrics.setDetailedMetricsEnabled(false)
        }
        super.viewWillDisappear()
    }

    private func apply(_ snapshot: MetricsSnapshot) {
        lastSnapshot = snapshot

        if forcesFullRefresh || round(cpuLevel.value) != round(snapshot.cpuUsage) {
            cpuLabel.stringValue = localizedString("CPU Usage") + " " + Int(snapshot.cpuUsage).formatted(.percent)
            cpuLevel.value = snapshot.cpuUsage
        }

        if forcesFullRefresh || round(gpuLevel.value) != round(snapshot.gpuUsage) {
            gpuLabel.stringValue = localizedString("GPU Usage") + " " + Int(snapshot.gpuUsage).formatted(.percent)
            gpuLevel.value = snapshot.gpuUsage
        }

        applySensors(snapshot.sensors)
        applyMemory(snapshot.memory)

        let address = snapshot.network.address.isEmpty
            ? localizedString("no ip found")
            : snapshot.network.address

        let network = "ip: " + address + "\n ▼ "
            + String(Int(snapshot.network.inbound.value)) + snapshot.network.inbound.unit.title
            + " | ▲ " + String(Int(snapshot.network.outbound.value)) + snapshot.network.outbound.unit.title

        if forcesFullRefresh || netLabel.stringValue != network {
            netLabel.stringValue = network
        }

        if popupChart.isShown, Date().timeIntervalSince(lastPopupUpdate) >= Self.popupUpdateInterval {
            updatePopupData()
        }

        forcesFullRefresh = false
    }

    private func applySensors(_ sensors: SensorsSnapshot) {
        let power: String
        if sensors.isOnBattery {
            power = localizedString("Power on battery: \(sensors.power) w")
        } else if sensors.isCharging {
            power = localizedString("Charging on adapter: \(sensors.power) w")
        } else {
            power = localizedString("Power on adapter: \(sensors.power) w")
        }

        if forcesFullRefresh || powerHistory != power {
            powerComp.stringValue = power
            powerHistory = power
        }

        if metrics.hasFans, !sensors.fanSpeeds.isEmpty {
            let fans = sensors.fanSpeeds.first == 0
                ? localizedString("fan is stopped")
                : "fan " + sensors.fanSpeeds.map(String.init).joined(separator: " | ") + " rpm"

            if forcesFullRefresh || fanHistory != fans {
                fanLabel.stringValue = fans
                fanHistory = fans
            }
        }

        if metrics.sensorsAvailable, forcesFullRefresh || round(tempLevel.value) != round(sensors.cpuTemperature) {
            cpuTempLabel.stringValue = localizedString("CPU Temp") + " " + String(Int(sensors.cpuTemperature)) + "°С"
            tempLevel.value = sensors.cpuTemperature
        }
    }

    private func applyMemory(_ memory: MemoryUsage) {
        if forcesFullRefresh || round(memLevel.value) != round(memory.used) {
            memPercentage.stringValue = localizedString("MEM Usage") + " " + Int(memory.used).formatted(.percent)
            memLevel.value = memory.used
        }

        if forcesFullRefresh || round(pressureLevel.value) != round(memory.pressure) {
            memPressure.stringValue = localizedString("Pressure") + " " + Int(memory.pressure).formatted(.percent)
            pressureLevel.value = memory.pressure

            memApp.stringValue = String(Int(memory.app.rounded())) + "% (App)"
            memAppBar.value = memory.app

            memInactive.stringValue = String(Int(memory.inactive.rounded())) + "% (NAct)"
            memInactiveBar.value = memory.inactive

            memComp.stringValue = String(Int(memory.compressed.rounded())) + "% (Comp)"
            memCompBar.value = memory.compressed
        }

        if forcesFullRefresh || round(memSwapLevel.value) != Double(memory.swap) {
            memSwapLabel.stringValue = localizedString("Swap") + " " + memory.swap.formatted(.percent)
            memSwapLevel.value = Double(memory.swap)
        }
    }

    var detailWindow: NSWindow? {
        popupChart.isShown ? popupChart.contentViewController?.view.window : nil
    }

    func closeDetail() {
        if popupChart.isShown {
            popupChart.performClose(nil)
        }
    }

    func dismissDetail(clickedAt point: NSPoint) {
        guard popupChart.isShown else { return }

        if let hit = view.window?.contentView?.hitTest(point),
           hit.isDescendant(of: cpuChartPopupButton) || hit.isDescendant(of: memChartPopupButton) {
            return
        }
        closeDetail()
    }

    private func showChart(from sender: NSButton) {
        if popupChart.isShown {
            popupChart.performClose(sender)
            if lastClickButton === sender { return }
        }
        lastClickButton = sender
        updatePopupData()
        popupChart.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
    }

    private func updatePopupData() {
        let snapshot = lastSnapshot
        let showsCPU = lastClickButton == cpuChartPopupButton

        guard showsCPU || lastClickButton == memChartPopupButton else { return }

        lastPopupUpdate = Date()

        let history = showsCPU ? snapshot.cpuHistory : snapshot.memoryHistory
        dataModel.title = localizedString(showsCPU ? "CPU usage details:" : "Memory usage details:")
        dataModel.chartPoints = ChartPoint.series(from: history, limit: Self.chartPointLimit)

        Task { [weak self] in
            guard let self else { return }
            let processes = await metrics.topProcesses()

            let rows = showsCPU
                ? processes.filter { $0.cpu > 0 }
                    .sorted { $0.cpu > $1.cpu }
                    .map { ProcessRow(pid: $0.pid, icon: $0.icon, name: $0.name, usage: String($0.cpu) + "%") }
                : processes.filter { $0.memory > 0.1 }
                    .sorted { $0.memory > $1.memory }
                    .map { ProcessRow(pid: $0.pid, icon: $0.icon, name: $0.name, usage: $0.memoryText) }

            self.dataModel.tablePoints = rows
        }
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
