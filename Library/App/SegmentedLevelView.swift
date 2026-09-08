//  Copyright © AndreyLysikov
//  SPDX-License-Identifier: Apache-2.0

import Cocoa

@MainActor
final class SegmentedLevelView: NSView {
    var value: Double = 0 {
        didSet {
            let filled = filledSegments
            if filled != filledSegmentsCache || zone != zoneCache {
                filledSegmentsCache = filled
                zoneCache = zone
                needsDisplay = true
            }
        }
    }

    var segmentCount: Int = 20 { didSet { needsDisplay = true } }
    var cornerRadius: CGFloat = 2 { didSet { needsDisplay = true } }
    var criticalLevel: Double = 90 { didSet { needsDisplay = true } }
    var barHeight: CGFloat = 16 {
        didSet {
            invalidateIntrinsicContentSize()
            needsDisplay = true
        }
    }

    private var filledSegmentsCache = -1
    private var zoneCache: Zone = .normal

    private enum Zone {
        case normal, critical
        var color: NSColor {
            switch self {
            case .normal: return .labelColor
            case .critical: return .systemRed
            }
        }
    }

    private var zone: Zone {
        if value >= criticalLevel { return .critical }
        return .normal
    }

    private var filledSegments: Int {
        let clamped = max(0, min(100, value))
        return Int((clamped / 100 * Double(segmentCount)).rounded())
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: barHeight)
    }

    override nonisolated func awakeFromNib() {
        super.awakeFromNib()
        MainActor.assumeIsolated {
            setContentHuggingPriority(.init(1), for: .horizontal)
            setContentCompressionResistancePriority(.init(1), for: .horizontal)
            setContentHuggingPriority(.defaultHigh, for: .vertical)
        }
    }

    override var isFlipped: Bool { true }
    override var allowsVibrancy: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    override func viewDidUnhide() {
        super.viewDidUnhide()
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        guard segmentCount > 0, bounds.width > 0 else { return }

        let spacing: CGFloat = 1
        let height = min(barHeight, bounds.height)
        let top = (bounds.height - height) / 2
        let segmentWidth = (bounds.width - CGFloat(segmentCount - 1) * spacing) / CGFloat(segmentCount)
        guard segmentWidth > 0 else { return }

        let radius = min(cornerRadius, segmentWidth / 2, height / 2)
        let filled = filledSegments
        let activeColor = zone.color
        let emptyColor = NSColor.quaternaryLabelColor

        for index in 0 ..< segmentCount {
            let rect = NSRect(x: CGFloat(index) * (segmentWidth + spacing),
                              y: top,
                              width: segmentWidth,
                              height: height)

            (index < filled ? activeColor : emptyColor).setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
        }
    }
}
