import AppKit
import SwiftUI

/// Bridges SwiftUI segmented `Picker` to AppKit `NSSegmentedControl` to assign per-segment tooltips,
/// which SwiftUI `.help(...)` modifiers on individual segment tags do not natively propagate on macOS.
public struct SegmentedControlTooltipModifier: ViewModifier {
    let tooltips: [String]

    public init(tooltips: [String]) {
        self.tooltips = tooltips
    }

    public func body(content: Content) -> some View {
        content
            .background(SegmentedControlTooltipAccessor(tooltips: tooltips))
    }
}

public extension View {
    /// Applies individual hover tooltips to each segment of an AppKit-backed segmented picker.
    func segmentedControlTooltips(_ tooltips: [String]) -> some View {
        modifier(SegmentedControlTooltipModifier(tooltips: tooltips))
    }
}

public struct SegmentedControlTooltipAccessor: NSViewRepresentable {
    let tooltips: [String]

    public init(tooltips: [String]) {
        self.tooltips = tooltips
    }

    public func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            guard let view else { return }
            Self.applyTooltips(tooltips, from: view)
        }
        return view
    }

    public func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            guard let nsView else { return }
            Self.applyTooltips(tooltips, from: nsView)
        }
    }

    public static func applyTooltips(_ tooltips: [String], to seg: NSSegmentedControl) {
        seg.toolTip = nil // Remove blanket control tooltip so segment tooltips take precedence
        for (index, tip) in tooltips.enumerated() {
            if index < seg.segmentCount {
                seg.setToolTip(tip, forSegment: index)
                if let cell = seg.cell as? NSSegmentedCell {
                    cell.setToolTip(tip, forSegment: index)
                }
            }
        }
    }

    private static func applyTooltips(_ tooltips: [String], from view: NSView) {
        guard let seg = findSegmentedControl(from: view) else { return }
        applyTooltips(tooltips, to: seg)
    }

    private static func findSegmentedControl(from view: NSView) -> NSSegmentedControl? {
        var current: NSView? = view
        for _ in 0..<4 {
            guard let parent = current?.superview else { break }
            if let direct = parent.subviews.compactMap({ $0 as? NSSegmentedControl }).first {
                return direct
            }
            for sub in parent.subviews {
                if let seg = sub as? NSSegmentedControl ?? sub.subviews.compactMap({ $0 as? NSSegmentedControl }).first {
                    return seg
                }
            }
            current = parent
        }
        return nil
    }
}

