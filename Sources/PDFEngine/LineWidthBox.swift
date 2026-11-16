//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

import SwiftUI
import AppKit

/// A line width in points, typed or picked from common sizes, as Acrobat and PDF-XChange set it.
public struct LineWidthBox: NSViewRepresentable {
    @Binding var width: CGFloat
    let help: String

    public init(width: Binding<CGFloat>, help: String) {
        _width = width
        self.help = help
    }

    public static let presets: [CGFloat] = [0.25, 0.5, 0.75, 1, 1.5, 2, 2.5, 3, 4, 6, 8, 12]
    public static let range: ClosedRange<CGFloat> = 0.1...72

    /// "0.25 pt", "1.5 pt", "2 pt".
    public static func format(_ width: CGFloat) -> String {
        let rounded = (width * 100).rounded() / 100
        let number = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%g", Double(rounded))
        return "\(number) pt"
    }

    /// A typed width: a number, with or without "pt", a comma for the decimal point, kept within
    /// `range`. Nil for something else.
    public static func parse(_ text: String) -> CGFloat? {
        var number = text.trimmingCharacters(in: .whitespaces).lowercased()
        if number.hasSuffix("pt") { number = String(number.dropLast(2)).trimmingCharacters(in: .whitespaces) }
        number = number.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(number), value.isFinite, value > 0 else { return nil }
        return min(max(CGFloat(value), range.lowerBound), range.upperBound)
    }

    public func makeNSView(context: Context) -> NSComboBox {
        let box = NSComboBox()
        box.controlSize = .small
        box.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        box.isEditable = true
        box.completes = false
        box.numberOfVisibleItems = Self.presets.count
        box.addItems(withObjectValues: Self.presets.map(Self.format))
        box.stringValue = Self.format(width)
        box.toolTip = help
        box.setAccessibilityLabel("Line Width")
        box.delegate = context.coordinator
        box.target = context.coordinator
        box.action = #selector(Coordinator.commit(_:))
        return box
    }

    public func updateNSView(_ box: NSComboBox, context: Context) {
        context.coordinator.parent = self
        box.toolTip = help
        // Not while it's being typed in.
        if box.currentEditor() == nil, box.stringValue != Self.format(width) {
            box.stringValue = Self.format(width)
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSComboBox, context: Context) -> CGSize? {
        CGSize(width: 76, height: nsView.intrinsicContentSize.height)
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor
    public final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: LineWidthBox

        init(parent: LineWidthBox) { self.parent = parent }

        public func comboBoxSelectionDidChange(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            let index = box.indexOfSelectedItem
            guard LineWidthBox.presets.indices.contains(index) else { return }
            parent.width = LineWidthBox.presets[index]
        }

        @objc func commit(_ sender: NSComboBox) {
            apply(sender)
        }

        public func controlTextDidEndEditing(_ notification: Notification) {
            guard let box = notification.object as? NSComboBox else { return }
            apply(box)
        }

        private func apply(_ box: NSComboBox) {
            if let width = LineWidthBox.parse(box.stringValue) {
                if abs(width - parent.width) > 0.0001 { parent.width = width }
                box.stringValue = LineWidthBox.format(width)
            } else {
                // Not a width: back to the one in use.
                box.stringValue = LineWidthBox.format(parent.width)
            }
        }
    }
}
