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

import Foundation
import CoreGraphics

/// The tools that each keep a color (and, for lines, a width) of their own.
public enum MarkupStyleTool: String, CaseIterable, Codable, Sendable {
    case highlight, underline, strikethrough, pen, shape, textBox, callout, note, measurement

    /// Whether the tool draws lines, so has a width.
    public var hasWidth: Bool { self == .pen || self == .shape || self == .measurement }
}

public struct MarkupToolStyle: Codable, Equatable, Sendable {
    public var color: AnnotationColor
    public var width: CGFloat

    public init(color: AnnotationColor, width: CGFloat) {
        self.color = color
        self.width = width
    }
}

/// Each tool's color and width, as last chosen, kept between launches. Defaults follow review
/// conventions: yellow highlights and notes, red marks and shapes ("redlining"), black text, and
/// quiet gray measurements that sit on a drawing rather than stand out from it.
@MainActor
public final class MarkupToolStyles {
    public static let defaultStyles: [MarkupStyleTool: MarkupToolStyle] = [
        .highlight: MarkupToolStyle(color: .yellow, width: 2.5),
        .underline: MarkupToolStyle(color: .red, width: 2.5),
        .strikethrough: MarkupToolStyle(color: .red, width: 2.5),
        .pen: MarkupToolStyle(color: .red, width: 2.5),
        .shape: MarkupToolStyle(color: .red, width: 2.5),
        .textBox: MarkupToolStyle(color: .black, width: 2.5),
        .callout: MarkupToolStyle(color: .black, width: 2.5),
        .note: MarkupToolStyle(color: .yellow, width: 2.5),
        .measurement: MarkupToolStyle(color: .gray, width: 1.5),
    ]

    private static let key = "com.thomasderham.vectorpdf.markupToolStyles"
    private static let app = MarkupToolStyles(defaults: .standard)

    /// The styles every window shares. Under the test runner, a new set each time with nothing
    /// saved, so tests start from the defaults and leave nothing behind.
    public static var shared: MarkupToolStyles {
        PDFViewerViewModel.isRunningTests ? MarkupToolStyles(defaults: nil) : app
    }

    private let defaults: UserDefaults?
    private var styles: [MarkupStyleTool: MarkupToolStyle]

    /// Styles kept in `defaults`, or only in memory with nil.
    public init(defaults: UserDefaults?) {
        self.defaults = defaults
        var styles = Self.defaultStyles
        if let data = defaults?.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([String: MarkupToolStyle].self, from: data) {
            for (name, style) in saved {
                if let tool = MarkupStyleTool(rawValue: name), style.width > 0 { styles[tool] = style }
            }
        }
        self.styles = styles
    }

    public subscript(tool: MarkupStyleTool) -> MarkupToolStyle {
        get { styles[tool] ?? Self.defaultStyles[tool]! }
        set {
            guard styles[tool] != newValue else { return }
            styles[tool] = newValue
            save()
        }
    }

    private func save() {
        guard let defaults else { return }
        let named = Dictionary(uniqueKeysWithValues: styles.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(named) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

extension PDFViewerViewModel {
    /// The tool whose style the Markup toolbar shows: Text Selection mode's is the highlighter's,
    /// whose button is there with the color.
    public var styleTool: MarkupStyleTool? {
        switch canvasMode {
        case .select: return .highlight
        case .draw: return .pen
        case .shape: return .shape
        case .text: return .textBox
        case .callout: return .callout
        case .note: return .note
        default: return nil
        }
    }

    /// A tool's color, as last chosen.
    public func toolColor(_ tool: MarkupStyleTool) -> AnnotationColor { toolStyles[tool].color }

    /// Makes `color` the tool's from now on, as choosing a color for one markup in a menu does.
    public func rememberToolColor(_ color: AnnotationColor, for tool: MarkupStyleTool) {
        toolStyles[tool].color = color
        if tool == styleTool { applyToolStyle() }
    }

    /// Shows the current tool's style in the toolbars, unless an annotation is selected.
    func applyToolStyle() {
        guard inspectedAnnotation == nil else { return }
        isApplyingToolStyle = true
        defer { isApplyingToolStyle = false }
        if let tool = styleTool {
            let style = toolStyles[tool]
            if selectedAnnotationColor != style.color { selectedAnnotationColor = style.color }
            if tool.hasWidth, drawStrokeWidth != style.width { drawStrokeWidth = style.width }
        }
        let measurement = toolStyles[.measurement]
        if measurementColor != measurement.color { measurementColor = measurement.color }
        if measurementStrokeWidth != measurement.width { measurementStrokeWidth = measurement.width }
    }

    /// The Markup toolbar's color or width was chosen: it's the current tool's from now on. With an
    /// annotation selected in Text Selection mode, it's for that annotation only; with a tool in
    /// use, the selected annotation is the one it just made, and the tool takes the change too.
    func rememberToolStyle() {
        guard !isApplyingToolStyle, inspectedAnnotation == nil || canvasMode != .select,
              let tool = styleTool else { return }
        var style = toolStyles[tool]
        style.color = selectedAnnotationColor
        if tool.hasWidth { style.width = drawStrokeWidth }
        toolStyles[tool] = style
    }

    func rememberMeasurementStyle() {
        guard !isApplyingToolStyle, inspectedAnnotation == nil || canvasMode.isMeasuring else { return }
        toolStyles[.measurement] = MarkupToolStyle(color: measurementColor, width: measurementStrokeWidth)
    }
}

extension CanvasMode {
    /// One of the Measurement toolbar's tools.
    var isMeasuring: Bool {
        switch self {
        case .measureLength, .measurePerimeter, .measureArea, .measureAngle, .measureCount, .calibrateScale: return true
        default: return false
        }
    }
}
