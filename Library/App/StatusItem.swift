//  Copyright © Takuto Nakamura, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa
import ServiceManagement

@MainActor
final class SpinnerAnimator {
    var onFrame: ((NSImage) -> Void)?

    private let preferences = Preferences.shared
    private var style = SpinnerCatalog.fallback
    private var frames: [NSImage] = []
    private var timer: Timer?
    private var currentFrame = 0
    private var currentInterval: Double = -1
    private static let minimumInterval = 1.0 / 120.0
    private static let speedTolerance = 0.15
    private var lastFrameDate = Date.distantPast

    func load(style: SpinnerStyle, effect: SpinnerEffect) {
        self.style = style
        frames = (0 ..< style.frameCount).compactMap { index in
            guard var image = NSImage(named: style.frameName(at: index)) else { return nil }

            let height = NSStatusBar.system.thickness - 2
            image.size = NSSize(width: height / image.size.height * image.size.width, height: height)

            if style.supportsEffect {
                switch effect {
                case .original:
                    image.isTemplate = false
                case .whiteShaded:
                    image.isTemplate = true
                    image = image.imageWithTint(color: NSColor(red: 1, green: 1, blue: 1, alpha: 0.8))
                case .blackShaded:
                    image.isTemplate = true
                    image = image.imageWithTint(color: NSColor(red: 0, green: 0, blue: 0, alpha: 0.8))
                case .automatic:
                    image.isTemplate = true
                }
            }
            return image
        }

        currentFrame = 0
        currentInterval = -1
        if let first = frames.first {
            onFrame?(first)
        }
    }

    func updateSpeed(usage: Double) {
        guard frames.count > 1 else {
            stop()
            return
        }

        let load = max(1.0, min(100.0, usage / Double(frames.count)))
        let interval = max(Self.minimumInterval, 0.25 / load * Double(style.speedCoefficient))

        guard currentInterval <= 0 || abs(interval - currentInterval) > currentInterval * Self.speedTolerance else {
            return
        }

        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.advance() }
        }

        timer.fireDate = max(lastFrameDate.addingTimeInterval(interval), Date())

        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        currentInterval = interval
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentInterval = -1
    }

    private func advance() {
        if frames.isEmpty || frames.count == 1 { return }

        lastFrameDate = Date()
        currentFrame += preferences.invertsRotation ? -1 : 1
        if currentFrame >= frames.count {
            currentFrame = 0
        } else if currentFrame < 0 {
            currentFrame = frames.count - 1
        }

        onFrame?(frames[currentFrame])
    }
}

extension NSImage {
    func imageWithTint(color: NSColor) -> NSImage {
        guard let tintedImage = self.copy() as? NSImage else { return self }
        tintedImage.lockFocus()

        color.set()
        NSRect(origin: .zero, size: tintedImage.size).fill(using: .sourceAtop)

        tintedImage.unlockFocus()
        return tintedImage
    }
}

@MainActor
protocol AppMenuControllerDelegate: AnyObject {
    func appMenuDidChangeSpinnerAppearance(_ controller: AppMenuController)
    func appMenuDidChangeUpdateInterval(_ controller: AppMenuController)
    func appMenuDidRequestDisplayRefresh(_ controller: AppMenuController)
    func appMenuDidRequestQuit(_ controller: AppMenuController)
}

enum LoginItemService {
    static var isEnabled: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            if newValue {
                if SMAppService.mainApp.status == .enabled {
                    try? SMAppService.mainApp.unregister()
                }
                try? SMAppService.mainApp.register()
            } else {
                try? SMAppService.mainApp.unregister()
            }
        }
    }
}

@MainActor
final class AppMenuController: NSObject {
    weak var delegate: AppMenuControllerDelegate?

    private(set) var menu = NSMenu()
    private let preferences = Preferences.shared

    private var displaysItem: NSMenuItem?
    private var effectsItem: NSMenuItem?
    private var rotationItem: NSMenuItem?
    private var backlightItem: NSMenuItem?
    private var smoothScrollItem: NSMenuItem?

    private let updateIntervals: [Double] = [0.5, 1.0, 1.5, 2.0]

    func rebuild() {
        let menu = NSMenu()

        menu.addItem(item(localizedString("Activity Monitor"),
                          symbol: "ellipsis.curlybraces",
                          action: #selector(openActivityMonitor)))

        menu.addItem(item(localizedString("Show load in menu"),
                          symbol: "cpu",
                          action: #selector(toggleStatusText),
                          state: preferences.showsCPUInMenuBar))

        menu.addItem(item(localizedString("Enable Autostart"),
                          symbol: "character",
                          action: #selector(toggleLaunchAtLogin),
                          state: LoginItemService.isEnabled))

        menu.addItem(.separator())

        let displays = item(localizedString("HDMI/DVI DDC enabled"),
                            symbol: "display.2",
                            action: #selector(refreshDisplays))
        displays.submenu = NSMenu()
        menu.addItem(displays)
        displaysItem = displays

        let steps = item(localizedString("Adjustment steps"), symbol: "display.and.screwdriver", action: nil)
        steps.submenu = submenu(Preferences.adjustmentStepChoices.map { (String($0), $0 == preferences.adjustmentSteps) },
                                action: #selector(changeAdjustmentSteps(sender:)))
        menu.addItem(steps)

        menu.addItem(item(localizedString("Always use custom OSD"),
                          symbol: "dot.scope.display",
                          action: #selector(toggleCustomOSD),
                          state: preferences.alwaysUsesCustomOSD))

        menu.addItem(item(localizedString("Use popup animation"),
                          symbol: "lasso.badge.sparkles",
                          action: #selector(togglePopUpAnimation),
                          state: preferences.usesPopUpAnimation))

        menu.addItem(.separator())

        let backlight = item(localizedString("Keyboard backlight on F5/F6"),
                             symbol: "keyboard",
                             action: #selector(toggleKeyboardBacklightKeys),
                             state: preferences.usesKeyboardBacklightKeys)
        menu.addItem(backlight)
        backlightItem = backlight

        menu.addItem(item(localizedString("Use system language"),
                          symbol: "translate",
                          action: #selector(toggleLocalization),
                          state: preferences.usesSystemLanguage))

        menu.addItem(item(localizedString("Show external ip address"),
                          symbol: "globe",
                          action: #selector(toggleExternalAddress),
                          state: preferences.showsExternalAddress))

        menu.addItem(item(localizedString("System chart color"),
                          symbol: "paintpalette",
                          action: #selector(toggleSystemChartColor),
                          state: preferences.usesSystemChartColor))

        let smoothScroll = item(localizedString("Smooth mouse scroll"),
                                symbol: "computermouse",
                                action: #selector(toggleSmoothScroll),
                                state: preferences.usesSmoothScroll)
        menu.addItem(smoothScroll)
        smoothScrollItem = smoothScroll

        menu.addItem(.separator())

        let spinners = item(localizedString("Spinners"), symbol: "checklist.unchecked", action: nil)
        spinners.submenu = spinnersSubmenu()
        menu.addItem(spinners)

        let intervals = item(localizedString("Data update every"), symbol: "progress.indicator", action: nil)
        intervals.submenu = submenu(updateIntervals.map {
            (String($0) + " " + localizedString("Second"), $0 == preferences.updateInterval)
        }, action: #selector(changeUpdateInterval(sender:)))
        menu.addItem(intervals)

        let effects = item(localizedString("Spinners Effects"), symbol: "wand.and.sparkles.inverse", action: nil)
        effects.submenu = submenu(SpinnerEffect.allCases.map {
            ($0.title, $0.rawValue == preferences.spinnerEffect)
        }, action: #selector(changeEffect(sender:)))
        menu.addItem(effects)
        effectsItem = effects

        let rotation = item(localizedString("Invert rotation"),
                            symbol: "circle.righthalf.filled.inverse",
                            action: #selector(toggleRotation),
                            state: preferences.invertsRotation)
        menu.addItem(rotation)
        rotationItem = rotation

        menu.addItem(.separator())

        menu.addItem(item(localizedString("About"), symbol: "info", action: #selector(showAbout)))
        menu.addItem(item(localizedString("Check new version"),
                          symbol: "arrow.trianglehead.clockwise.rotate.90",
                          action: #selector(checkNewVersion)))
        menu.addItem(item(localizedString("Quit"), symbol: "xmark", action: #selector(quit)))

        self.menu = menu
        refreshSpinnerState()
        refreshDeviceItems()
    }

    func updateDisplays(_ displays: [Display]) {
        let submenu = NSMenu()

        for display in displays {
            let entry = NSMenuItem(title: display.name,
                                   action: display.isBuiltIn() ? nil : #selector(refreshDisplays),
                                   keyEquivalent: "")
            entry.target = self
            entry.image = AccentPalette.symbol("display", describedBy: display.name)
            submenu.addItem(entry)
        }

        displaysItem?.submenu = submenu
    }

    func refreshSpinnerState() {
        let style = SpinnerCatalog.style(validating: preferences.spinnerName)
        effectsItem?.action = style.supportsEffect ? #selector(changeEffect(sender:)) : nil
        effectsItem?.isEnabled = style.supportsEffect

        let isAnimated = style.frameCount > 1
        rotationItem?.action = isAnimated ? #selector(toggleRotation(sender:)) : nil
        rotationItem?.isEnabled = isAnimated
    }

    private func item(_ title: String, symbol: String, action: Selector?, state: Bool = false) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = AccentPalette.symbol(symbol, describedBy: title)
        item.state = state ? .on : .off
        return item
    }

    private func submenu(_ entries: [(title: String, selected: Bool)], action: Selector) -> NSMenu {
        let submenu = NSMenu()
        for entry in entries {
            let item = NSMenuItem(title: entry.title, action: action, keyEquivalent: "")
            item.target = self
            item.state = entry.selected ? .on : .off
            submenu.addItem(item)
        }
        return submenu
    }

    private func spinnersSubmenu() -> NSMenu {
        let submenu = NSMenu()
        for style in SpinnerCatalog.all {
            let item = NSMenuItem(title: style.name, action: #selector(changeSpinner(sender:)), keyEquivalent: "")
            item.target = self
            item.state = style.name == preferences.spinnerName ? .on : .off
            let imageName = (style.frameCount == 1) ? (style.name) : (style.name + " 1")
            if let image = NSImage(named: imageName) {
                image.size = NSSize(width: 19 / image.size.height * image.size.width, height: 19)
                item.image = image
            }
            submenu.addItem(item)
        }
        return submenu
    }

    private func selectExclusively(_ sender: NSMenuItem) {
        sender.menu?.items.forEach { $0.state = .off }
        sender.state = .on
    }

    @objc private func openActivityMonitor() {
        let url = URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app", isDirectory: true)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    @objc private func toggleStatusText(sender: NSMenuItem) {
        preferences.showsCPUInMenuBar.toggle()
        sender.state = preferences.showsCPUInMenuBar ? .on : .off
    }

    @objc private func toggleLaunchAtLogin(sender: NSMenuItem) {
        LoginItemService.isEnabled.toggle()
        sender.state = LoginItemService.isEnabled ? .on : .off
    }

    @objc private func toggleCustomOSD(sender: NSMenuItem) {
        preferences.alwaysUsesCustomOSD.toggle()
        sender.state = preferences.alwaysUsesCustomOSD ? .on : .off
        delegate?.appMenuDidRequestDisplayRefresh(self)
    }

    @objc private func toggleKeyboardBacklightKeys(sender: NSMenuItem) {
        preferences.usesKeyboardBacklightKeys.toggle()
        sender.state = preferences.usesKeyboardBacklightKeys ? .on : .off
    }

    @objc private func toggleLocalization(sender: NSMenuItem) {
        preferences.usesSystemLanguage.toggle()
        rebuild()
        delegate?.appMenuDidRequestDisplayRefresh(self)
    }

    @objc private func togglePopUpAnimation(sender: NSMenuItem) {
        preferences.usesPopUpAnimation.toggle()
        sender.state = preferences.usesPopUpAnimation ? .on : .off
    }

    @objc private func toggleExternalAddress(sender: NSMenuItem) {
        preferences.showsExternalAddress.toggle()
        sender.state = preferences.showsExternalAddress ? .on : .off
    }

    @objc private func toggleSystemChartColor(sender: NSMenuItem) {
        preferences.usesSystemChartColor.toggle()
        sender.state = preferences.usesSystemChartColor ? .on : .off
        rebuild()
    }

    @objc private func toggleSmoothScroll(sender: NSMenuItem) {
        preferences.usesSmoothScroll.toggle()
        sender.state = preferences.usesSmoothScroll ? .on : .off
        MouseInput.shared.setEnabled(preferences.usesSmoothScroll)
    }

    func refreshDeviceItems() {
        backlightItem?.isHidden = !KeyboardBacklight.shared.isAvailable
        smoothScrollItem?.isHidden = !MouseInput.hasThirdPartyMouse
    }

    @objc private func toggleRotation(sender: NSMenuItem) {
        preferences.invertsRotation.toggle()
        sender.state = preferences.invertsRotation ? .on : .off
    }

    @objc private func changeAdjustmentSteps(sender: NSMenuItem) {
        selectExclusively(sender)
        preferences.adjustmentSteps = Int(sender.title) ?? preferences.adjustmentSteps
    }

    @objc private func changeUpdateInterval(sender: NSMenuItem) {
        selectExclusively(sender)

        let value = sender.title
            .replacingOccurrences(of: localizedString("Second"), with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        preferences.updateInterval = Double(value) ?? preferences.updateInterval

        delegate?.appMenuDidChangeUpdateInterval(self)
    }

    @objc private func changeSpinner(sender: NSMenuItem) {
        selectExclusively(sender)
        preferences.spinnerName = SpinnerCatalog.style(validating: sender.title).name
        refreshSpinnerState()
        delegate?.appMenuDidChangeSpinnerAppearance(self)
    }

    @objc private func changeEffect(sender: NSMenuItem) {
        selectExclusively(sender)
        if let effect = SpinnerEffect.allCases.first(where: { $0.title == sender.title }) {
            preferences.spinnerEffect = effect.rawValue
        }
        delegate?.appMenuDidChangeSpinnerAppearance(self)
    }

    @objc private func refreshDisplays() {
        delegate?.appMenuDidRequestDisplayRefresh(self)
    }

    @objc private func checkNewVersion() {
        UpdateChecker.shared.check(force: true)
    }

    @objc private func quit() {
        delegate?.appMenuDidRequestQuit(self)
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "System Spinner v\(UpdateChecker.shared.installedVersion)"
        alert.informativeText = localizedString("""
                                                System Spinner provides macOS system information in status bar.
                                                Minimal, small and light.

                                                Author: @Andrey.Lysikov
                                                """)
        alert.alertStyle = .informational
        alert.addButton(withTitle: localizedString("Goto site"))
        alert.addButton(withTitle: localizedString("Close"))

        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(UpdateChecker.repositoryURL)
        } else {
            alert.window.close()
        }
    }
}

@MainActor
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let animator = SpinnerAnimator()
    private let menuController = AppMenuController()
    private let metrics = MetricsService.shared
    private let preferences = Preferences.shared

    private let usageController = UsageViewController.freshController()

    private var metricsObserver: UUID?
    private var lastUsage: Double = 0
    private var clickMonitors: [Any] = []

    func start() {
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(handleClick)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
            button.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
        }

        popover.contentViewController = usageController

        animator.onFrame = { [weak self] image in
            self?.statusItem.button?.image = image
        }

        menuController.delegate = self
        menuController.rebuild()

        DisplayManager.shared.onDisplaysChanged = { [weak self] displays in
            self?.menuController.updateDisplays(displays)
        }
        DisplayManager.shared.start()

        observeWorkspace()

        reloadSpinner()
        resume()
    }

    func stop() {
        pause()
        stopClickMonitoring()
    }

    @objc private func resume() {
        let interval = preferences.updateInterval
        var newToken: UUID?
        if metricsObserver == nil {
            let token = UUID()
            metricsObserver = token
            newToken = token
        }

        Task { [weak self] in
            guard let self else { return }

            if let newToken {
                await metrics.addObserver(newToken) { [weak self] snapshot in
                    self?.apply(snapshot)
                }
            }
            await metrics.start(interval: interval)
        }

        DisplayManager.shared.setNeedsRefresh()
    }

    @objc private func pause() {
        closePopover()
        animator.stop()
        Task { await metrics.stop() }
    }

    private func apply(_ snapshot: MetricsSnapshot) {
        lastUsage = max(snapshot.cpuUsage, snapshot.gpuUsage)

        if preferences.showsCPUInMenuBar {
            statusItem.button?.title = String(format: "%2d%%", Int(lastUsage))
        } else if statusItem.button?.title != "" {
            statusItem.button?.title = ""
        }

        animator.updateSpeed(usage: lastUsage)
    }

    private func reloadSpinner() {
        let style = SpinnerCatalog.style(validating: preferences.spinnerName)
        let effect = SpinnerEffect(rawValue: preferences.spinnerEffect) ?? .original
        animator.load(style: style, effect: effect)
        animator.updateSpeed(usage: lastUsage)
    }

    @objc private func handleClick() {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .leftMouseUp {
            if popover.isShown {
                closePopover()
            } else {
                showPopover()
            }
        } else {
            let menu = menuController.menu
            menu.delegate = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        }
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.animates = preferences.usesPopUpAnimation
        button.window?.layoutIfNeeded()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        startClickMonitoring()
    }

    func closePopover() {
        usageController.closeDetail()
        if popover.isShown {
            popover.performClose(nil)
        }
        stopClickMonitoring()
    }

    private func startClickMonitoring() {
        guard clickMonitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]

        let global = NSEvent.addGlobalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            self?.dismiss(for: event)
        })
        let local = NSEvent.addLocalMonitorForEvents(matching: clicks, handler: { [weak self] event in
            self?.dismiss(for: event)
            return event
        })
        clickMonitors = [global, local].compactMap { $0 }
    }

    private func stopClickMonitoring() {
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors.removeAll()
    }

    private func dismiss(for event: NSEvent) {
        guard popover.isShown else { return }
        guard let window = event.window else {
            closePopover()
            return
        }

        if window === statusItem.button?.window { return }
        if window === usageController.detailWindow { return }

        if window === usageController.view.window {
            usageController.dismissDetail(clickedAt: event.locationInWindow)
            return
        }
        closePopover()
    }

    @objc private func reloadMenu() {
        menuController.rebuild()
    }

    private func observeWorkspace() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(reloadMenu),
                                               name: NSColor.systemColorsDidChangeNotification,
                                               object: nil)

        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(resume), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(resume), name: NSWorkspace.screensDidWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(pause), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(pause), name: NSWorkspace.screensDidSleepNotification, object: nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        menuController.refreshDeviceItems()
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}

extension StatusItemController: AppMenuControllerDelegate {
    func appMenuDidChangeSpinnerAppearance(_ controller: AppMenuController) {
        reloadSpinner()
    }

    func appMenuDidChangeUpdateInterval(_ controller: AppMenuController) {
        let interval = preferences.updateInterval
        Task { await metrics.start(interval: interval) }
    }

    func appMenuDidRequestDisplayRefresh(_ controller: AppMenuController) {
        DisplayManager.shared.setNeedsRefresh()
    }

    func appMenuDidRequestQuit(_ controller: AppMenuController) {
        NSApp.terminate(nil)
    }
}
