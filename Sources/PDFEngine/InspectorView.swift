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

/// The Inspector beside the page (View > Show Inspector): the selected annotation, with its
/// place and size to type in, and what the page draws where it was last clicked: the text's
/// font, size and colour, an image's pixels and resolution, a drawing's line width and colours.
struct InspectorView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let annotation = viewModel.inspectorAnnotation {
                    AnnotationInspectorSection(viewModel: viewModel, annotation: annotation, unit: coordinator.readoutUnit)
                }
                if let content = viewModel.inspectedContent {
                    ContentInspectorSections(viewModel: viewModel, content: content, unit: coordinator.readoutUnit)
                } else if viewModel.inspectorAnnotation == nil {
                    Text("Click the page to see the text, image or drawing there, or select an annotation.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A heading and rows of label and value.
struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
                content
            }
        }
    }
}

struct InspectorRow: View {
    let label: String
    let value: String

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(3)
                .truncationMode(.middle)
        }
        .font(.callout)
    }
}

struct InspectorColorRow: View {
    let label: String
    let color: PageContentInspection.RGB

    var body: some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(nsColor: color.nsColor))
                    .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5), lineWidth: 0.5))
                    .frame(width: 14, height: 14)
                Text(color.hex)
                    .monospaced()
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
    }
}

// MARK: - Annotation

struct AnnotationInspectorSection: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let annotation: PDFAnnotation
    let unit: ReadoutUnit

    var body: some View {
        let details = viewModel.inspectorDetails(for: annotation)
        InspectorSection(title: "Annotation") {
            InspectorRow("Type", details.typeName)
            if let author = details.author, !author.isEmpty { InspectorRow("Author", author) }
            if let created = details.created { InspectorRow("Created", created.formatted(date: .abbreviated, time: .shortened)) }
            if let modified = details.modified, modified != details.created {
                InspectorRow("Modified", modified.formatted(date: .abbreviated, time: .shortened))
            }
            InspectorRow("Layer", details.layerName ?? "None")
            if let opacity = details.opacity { InspectorRow("Opacity", "\(Int((opacity * 100).rounded()))%") }
            InspectorRow("Color", annotation.color.displayName)
            if annotation.isShape || annotation.type == .ink {
                InspectorRow("Line width", "\(ReadoutUnit.points.format(Double(annotation.strokeWidth))) pt")
            }
            if annotation.isMeasurement, !annotation.measurementText.isEmpty {
                InspectorRow("Measures", annotation.measurementText)
            }
        }
        if let bounds = pageBounds {
            InspectorSection(title: "Position and Size") {
                editableRow("X", bounds.minX, enabled: annotation.canMoveInInspector) { set(\.origin.x, $0, in: bounds) }
                editableRow("Y", bounds.minY, enabled: annotation.canMoveInInspector) { set(\.origin.y, $0, in: bounds) }
                editableRow("Width", bounds.width, enabled: annotation.canResizeInInspector) { set(\.size.width, $0, in: bounds) }
                editableRow("Height", bounds.height, enabled: annotation.canResizeInInspector) { set(\.size.height, $0, in: bounds) }
            }
            .disabled(viewModel.isReadOnlyDocument)
            Text("From the top-left corner of the page, in \(unit.displayName.lowercased()).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Its box, from the page's top-left corner.
    private var pageBounds: CGRect? {
        guard let box = annotation.inspectorBounds, let doc = viewModel.document, annotation.pageIndex < doc.pageBounds.count else { return nil }
        let origin = doc.pageBounds[annotation.pageIndex].origin
        return box.offsetBy(dx: -origin.x, dy: -origin.y)
    }

    private func set(_ keyPath: WritableKeyPath<CGRect, CGFloat>, _ value: CGFloat, in bounds: CGRect) {
        guard let doc = viewModel.document else { return }
        var box = bounds
        box[keyPath: keyPath] = value
        guard box.width > 0, box.height > 0 else { return }
        let origin = doc.pageBounds[annotation.pageIndex].origin
        viewModel.setInspectorAnnotationBounds(box.offsetBy(dx: origin.x, dy: origin.y))
    }

    private func editableRow(_ label: String, _ points: CGFloat, enabled: Bool, commit: @escaping (CGFloat) -> Void) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            HStack(spacing: 4) {
                InspectorNumberField(value: unit.value(fromPoints: Double(points))) { value in
                    commit(CGFloat(unit.points(fromValue: value)))
                }
                .disabled(!enabled)
                Text(unit.rawValue).foregroundStyle(.secondary)
            }
        }
        .font(.callout)
    }
}

/// A number typed in and applied on Return or on leaving the field.
struct InspectorNumberField: View {
    let value: Double
    let onCommit: (Double) -> Void
    @State private var text = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .frame(width: 80)
            .focused($isFocused)
            .onSubmit(commit)
            .onChange(of: isFocused) { _, focused in if !focused { commit() } }
            .onAppear { text = Self.format(value) }
            .onChange(of: value) { _, new in if !isFocused { text = Self.format(new) } }
    }

    private func commit() {
        let normalized = text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        guard let typed = Double(normalized), typed.isFinite else {
            text = Self.format(value)
            return
        }
        if abs(typed - value) > 0.0005 { onCommit(typed) }
    }

    static func format(_ value: Double) -> String {
        ((value * 100).rounded() / 100).formatted(.number.precision(.fractionLength(0...2)).grouping(.never).locale(Locale(identifier: "en_US_POSIX")))
    }
}

// MARK: - Page content

struct ContentInspectorSections: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let content: PageContentInspection
    let unit: ReadoutUnit

    var body: some View {
        if content.isEmpty {
            Text("Nothing is drawn where you clicked on \(pageName).")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        if let text = content.text {
            InspectorSection(title: "Text") {
                InspectorRow("Font", text.fontName)
                InspectorRow("Size", "\(ReadoutUnit.points.format(Double(text.fontSize))) pt")
                if let character = text.character { InspectorRow("Character", character) }
                InspectorColorRow(label: text.isOutlined ? "Outline" : "Color", color: text.color)
                if !text.colorSpace.isEmpty { InspectorRow("Color space", text.colorSpace) }
                if text.opacity < 0.999 { InspectorRow("Opacity", "\(Int((text.opacity * 100).rounded()))%") }
                if text.isSubstitute {
                    InspectorRow("Embedded", "No: shown in a substitute font")
                } else if text.isSubset {
                    InspectorRow("Embedded", "Yes, the characters used")
                }
            }
        }
        if let image = content.image {
            InspectorSection(title: image.isMask ? "Image Mask" : "Image") {
                InspectorRow("Pixels", "\(image.pixelWidth) × \(image.pixelHeight)")
                InspectorRow("Resolution", resolution(image.dpi))
                InspectorRow("Size on page", unit.formatSize(image.rect.size))
                if !image.colorSpace.isEmpty { InspectorRow("Color space", image.colorSpace) }
                InspectorRow("Bits per component", "\(image.bitsPerComponent)")
            }
        }
        if let path = content.path {
            InspectorSection(title: "Drawing") {
                if let width = path.strokeWidth {
                    InspectorRow("Line width", width == 0 ? "Thinnest" : "\(ReadoutUnit.points.format(Double(width), decimals: 2)) pt")
                }
                if let stroke = path.strokeColor { InspectorColorRow(label: "Line", color: stroke) }
                if let fill = path.fillColor { InspectorColorRow(label: "Fill", color: fill) }
                if !path.colorSpace.isEmpty { InspectorRow("Color space", path.colorSpace) }
                if path.opacity < 0.999 { InspectorRow("Opacity", "\(Int((path.opacity * 100).rounded()))%") }
            }
        }
        Text("At \(pageName), x \(unit.format(Double(local.x))) y \(unit.format(Double(local.y))) \(unit.rawValue)")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private var pageName: String {
        "page \(viewModel.document?.displayLabel(forPage: content.pageIndex) ?? "\(content.pageIndex + 1)")"
    }

    private var local: CGPoint {
        guard let doc = viewModel.document, content.pageIndex < doc.pageBounds.count else { return content.point }
        let origin = doc.pageBounds[content.pageIndex].origin
        return CGPoint(x: content.point.x - origin.x, y: content.point.y - origin.y)
    }

    private func resolution(_ dpi: CGSize) -> String {
        let x = Int(dpi.width.rounded()), y = Int(dpi.height.rounded())
        return abs(x - y) <= 1 ? "\(x) ppi" : "\(x) × \(y) ppi"
    }
}

/// What the Inspector shows of an annotation besides what `PDFAnnotation` holds.
struct AnnotationInspectorDetails {
    var typeName: String
    var author: String?
    var created: Date?
    var modified: Date?
    var layerName: String?
    var opacity: CGFloat?
}

extension PDFViewerViewModel {
    func inspectorDetails(for annotation: PDFAnnotation) -> AnnotationInspectorDetails {
        var details = AnnotationInspectorDetails(typeName: annotation.type.inspectorName, created: annotation.dateCreated)
        if let layer = annotation.layerObjectNumber {
            details.layerName = layers.first { $0.objectNumber == layer }?.name
        }
        guard let doc = document, let number = annotation.documentObjectNumber else { return details }
        if let comment = doc.annotationThreads(pageIndex: annotation.pageIndex).first(where: { $0.root.objectNumber == number })?.root {
            details.typeName = comment.typeName
            details.author = comment.author
            details.created = comment.created ?? details.created
            details.modified = comment.modified
        }
        details.opacity = doc.annotationOpacity(pageIndex: annotation.pageIndex, objectNumber: number)
        return details
    }
}

extension PDFAnnotationType {
    /// A name for the Inspector, for an annotation without one from the file.
    var inspectorName: String {
        String(describing: self)
            .replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
            .capitalized
    }
}
