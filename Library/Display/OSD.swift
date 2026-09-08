//  Copyright © (yu) zmlabs, AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import SwiftUI

struct OSDValue: Equatable {
    enum Kind {
        case volume
        case displayBrightness
        case keyboardBacklight
    }

    var value: Float
    var kind: Kind
    var separatorSteps: Int

    init(value: Float = 0.0, kind: Kind = .volume, separatorSteps: Int = 16) {
        self.value = max(0.0, min(100.0, value))
        self.kind = kind
        self.separatorSteps = separatorSteps
    }

    var iconName: String {
        switch kind {
        case .displayBrightness:
            return value < 80 ? "sun.min" : "sun.max"
        case .keyboardBacklight:
            return value <= 0 ? "keyboard" : "keyboard.fill"
        case .volume:
            switch value {
            case ...0: return "speaker.slash.fill"
            case ..<33: return "speaker.wave.1.fill"
            case ..<66: return "speaker.wave.2.fill"
            default: return "speaker.wave.3.fill"
            }
        }
    }
}

@MainActor
final class OSDController {
    static let shared = OSDController()
    let valuePublisher = CurrentValueSubject<OSDValue, Never>(OSDValue())
    var currentValue: OSDValue { valuePublisher.value }

    private lazy var window = OSDWindow()
    private var hideTask: Task<Void, Never>?
    private static let visibleDuration: Duration = .seconds(2.5)

    private init() {}

    func show(value: Float, kind: OSDValue.Kind, separators: Int = 16) {
        valuePublisher.send(OSDValue(value: value, kind: kind, separatorSteps: separators))
        scheduleHide()
        window.showWithAnimation()
    }

    private func scheduleHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.visibleDuration)
            guard !Task.isCancelled else { return }
            self?.window.hideWithAnimation()
        }
    }
}

@MainActor
final class OSDWindow: NSPanel {
    private let hostingView: NSHostingView<OSDView>
    private static let pillSize = NSSize(width: 280, height: 64)
    private static let contentPadding: CGFloat = 48
    private static let glassMargin: CGFloat = 16
    private static let pillBottomInset: CGFloat = 156

    private static let windowSize = NSSize(width: pillSize.width + (contentPadding + glassMargin) * 2,
                                           height: pillSize.height + (contentPadding + glassMargin) * 2)
    private static let bottomInset = pillBottomInset - contentPadding - glassMargin

    @objc(_hasActiveAppearance) dynamic func _hasActiveAppearance() -> Bool { true }

    init() {
        hostingView = NSHostingView(rootView: OSDView())

        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        ignoresMouseEvents = true

        hostingView.sizingOptions = []
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor
        hostingView.frame = NSRect(origin: .zero, size: Self.windowSize)
        hostingView.autoresizingMask = [.width, .height]
        contentView = hostingView
    }

    func showWithAnimation() {
        updatePosition()

        let animates = Preferences.shared.usesPopUpAnimation

        if isVisible {
            if alphaValue < 1.0 {
                if animates {
                    animator().alphaValue = 1.0
                } else {
                    alphaValue = 1.0
                }
            }
            return
        }

        hostingView.layoutSubtreeIfNeeded()

        guard animates else {
            alphaValue = 1.0
            orderFrontRegardless()
            return
        }

        alphaValue = 0.0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            self.animator().alphaValue = 1.0
        }
    }

    func hideWithAnimation() {
        guard Preferences.shared.usesPopUpAnimation else {
            orderOut(nil)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.3
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            self.animator().alphaValue = 0.0
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self, alphaValue == 0.0 else { return }
                orderOut(nil)
            }
        }
    }

    private func updatePosition() {
        guard let screen = Self.activeScreen() else { return }
        let frame = screen.frame
        let size = Self.pointSize(of: screen)
        setFrame(NSRect(x: (frame.minX + (size.width - Self.windowSize.width) / 2).rounded(),
                        y: frame.minY + Self.bottomInset,
                        width: Self.windowSize.width,
                        height: Self.windowSize.height),
                 display: false)
    }

    private static func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
    }

    private static func pointSize(of screen: NSScreen) -> CGSize {
        let screenSize = screen.frame.size
        let scale = screen.backingScaleFactor

        guard scale > 0,
              let identifier = screen.displayID,
              let display = DisplayManager.shared.display(withID: identifier)
        else {
            return screenSize
        }

        let resolution = display.refreshResolution()
        let size = CGSize(width: resolution.width / scale, height: resolution.height / scale)

        guard abs(size.width - screenSize.width) <= 1, abs(size.height - screenSize.height) <= 1 else {
            return screenSize
        }

        return size
    }
}

struct OSDView: View {
    @State private var value: OSDValue

    @MainActor
    init() {
        _value = State(initialValue: OSDController.shared.currentValue)
    }

    var body: some View {
        OSDIndicatorView(value: value)
            .padding(48)
            .onReceive(OSDController.shared.valuePublisher) {
                value = $0
            }
    }
}

struct OSDIndicatorView: View {
    let value: OSDValue

    @Environment(\.colorScheme) private var colorScheme

    private var backgroundTint: NSColor {
        colorScheme == .dark
            ? NSColor.black.withAlphaComponent(0.5)
            : NSColor.white.withAlphaComponent(0.5)
    }

    private var foregroundTint: Color {
        colorScheme == .dark ? .white : .black
    }

    private var accentTint: Color {
        Preferences.shared.usesSystemChartColor ? Color(nsColor: AccentPalette.normal) : foregroundTint
    }

    var body: some View {
        let content = HStack(spacing: 16) {
            icon
            VStack(spacing: 4) {
                bar
                scale
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 280, height: 64)

        GlassEffectContainer(tintColor: backgroundTint) { content }
            .frame(width: 280, height: 64)
    }

    @ViewBuilder
    private var icon: some View {
        let image = Image(systemName: value.iconName)
            .font(.system(size: 24, weight: .medium))
            .frame(width: 28)
            .foregroundStyle(accentTint.opacity(0.8))

        if Preferences.shared.usesPopUpAnimation {
            image.contentTransition(.symbolEffect(.replace))
        } else {
            image
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(foregroundTint.opacity(0.25))
                if value.value > 0 {
                    Capsule()
                        .fill(accentTint)
                        .frame(width: geometry.size.width * CGFloat(value.value / 100))
                }
            }
        }
        .frame(height: 4)
    }

    private var scale: some View {
        GeometryReader { geometry in
            let steps = max(value.separatorSteps, 1)
            let spacing = max((geometry.size.width - CGFloat(steps + 1)) / CGFloat(steps), 0)

            HStack(spacing: spacing) {
                ForEach(0 ... steps, id: \.self) { index in
                    VStack {
                        Spacer()
                        Rectangle()
                            .fill(foregroundTint.opacity(0.8))
                            .frame(width: 1, height: index % 4 == 0 ? 6 : 3)
                    }
                }
            }
        }
        .frame(height: 2)
    }
}

struct GlassEffectContainer<Content: View>: NSViewRepresentable {
    let tintColor: NSColor?
    let content: Content

    private let cornerRadius: CGFloat = 28
    private let style: NSGlassEffectView.Style = .regular

    init(tintColor: NSColor? = nil, @ViewBuilder content: () -> Content) {
        self.tintColor = tintColor
        self.content = content()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(rootView: content)
    }

    func makeNSView(context: Context) -> NSGlassEffectView {
        let glassView = NSGlassEffectView(frame: .zero)
        glassView.cornerRadius = cornerRadius
        glassView.style = style
        glassView.tintColor = tintColor

        let hostingView = context.coordinator.hostingView
        hostingView.frame = glassView.bounds
        hostingView.autoresizingMask = [.width, .height]
        glassView.contentView = hostingView
        return glassView
    }

    func updateNSView(_ nsView: NSGlassEffectView, context: Context) {
        nsView.cornerRadius = cornerRadius
        nsView.style = style
        nsView.tintColor = tintColor
        context.coordinator.hostingView.rootView = content
        context.coordinator.hostingView.frame = nsView.bounds
    }

    @MainActor
    final class Coordinator {
        let hostingView: NSHostingView<Content>

        init(rootView: Content) {
            hostingView = NSHostingView(rootView: rootView)
        }
    }
}
