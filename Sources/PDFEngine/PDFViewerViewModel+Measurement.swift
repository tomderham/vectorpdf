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
import Combine
import UniformTypeIdentifiers
import ObjectiveC

extension PDFViewerViewModel {
    // MARK: - Engineering Measurement & Takeoff Annotations

    public func toggleMeasurementBar() {
        withAnimation(.easeInOut(duration: 0.15)) {
            isMeasurementBarVisible.toggle()
        }
    }

    public func scaleConfig(for pageIndex: Int) -> PDFScaleConfiguration {
        pageScaleConfigs[pageIndex] ?? currentScaleConfig
    }

    public func setScaleConfig(_ config: PDFScaleConfiguration, for pageIndex: Int? = nil, applyToAll: Bool = false) {
        if applyToAll || pageIndex == nil {
            currentScaleConfig = config
            if let count = document?.pageCount {
                for i in 0..<count {
                    pageScaleConfigs[i] = config
                }
            }
        } else if let pIdx = pageIndex {
            pageScaleConfigs[pIdx] = config
        }

        // Persist scale via ISO 32000 Viewport (/VP) on target pages
        if let doc = document {
            let targetPages = applyToAll ? Array(0..<doc.pageCount) : (pageIndex != nil ? [pageIndex!] : [currentPageIndex])
            for p in targetPages {
                try? doc.setPageScale(
                    pageIndex: p,
                    ratioString: config.ratioString,
                    unitString: config.linearUnit.shortSymbol,
                    pointsPerUnit: config.pointsPerUnit
                )
            }
            isDocumentEdited = true
            currentWindow?.isDocumentEdited = true
        }
        objectWillChange.send()
    }

    @discardableResult
    public func addMeasurementAnnotation(
        pageIndex: Int,
        type: PDFAnnotationType,
        points: [CGPoint],
        value: Double,
        formattedText: String,
        leaderOffset: CGFloat = 0.0,
        color: AnnotationColor? = nil,
        strokeWidth: CGFloat = 2.0,
        label: String? = nil,
        shape: MeasuredShape? = nil
    ) -> PDFAnnotation? {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount, !points.isEmpty else { return nil }
        let annotColor = color ?? measurementColor
        var annot = PDFAnnotation(
            pageIndex: pageIndex,
            type: type,
            strokeWidth: strokeWidth,
            color: annotColor,
            text: label ?? formattedText,
            measurementPoints: points,
            measurementValue: value,
            measurementText: formattedText,
            leaderOffset: leaderOffset
        )
        annot.measuredShape = shape

        // Write directly to PDF backend
        do {
            switch type {
            case .measureLength:
                if points.count >= 2 {
                    try doc.addLineDimension(
                        pageIndex: pageIndex,
                        startPoint: points[0],
                        endPoint: points[1],
                        leaderOffset: leaderOffset,
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue,
                        strokeWidth: strokeWidth
                    )
                }
            case .measurePerimeter:
                if points.count >= 2 {
                    try doc.addPolylineDimension(
                        pageIndex: pageIndex,
                        vertices: points,
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue,
                        strokeWidth: strokeWidth
                    )
                }
            case .measureArea:
                if points.count >= 3 {
                    try doc.addPolygonDimension(
                        pageIndex: pageIndex,
                        vertices: points,
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue,
                        strokeWidth: strokeWidth
                    )
                }
            case .measureAngle:
                if points.count >= 3 {
                    try doc.addAngleMeasurement(
                        pageIndex: pageIndex,
                        points: Array(points.prefix(3)),
                        text: formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue,
                        strokeWidth: strokeWidth
                    )
                }
            case .measureCount:
                if let center = points.first {
                    try doc.addCountMarker(
                        pageIndex: pageIndex,
                        center: center,
                        group: label ?? formattedText,
                        red: annotColor.rgb.red,
                        green: annotColor.rgb.green,
                        blue: annotColor.rgb.blue
                    )
                }
            default:
                break
            }
        } catch {
            print("Failed to save measurement annotation to PDF core: \(error)")
            return nil
        }

        let stored = recordAddedAnnotation(annot)
        if let shape, let number = stored.documentObjectNumber {
            try? doc.setMeasurementShape(pageIndex: pageIndex, objectNumber: number, shape: shape)
        }
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
        objectWillChange.send()
        return stored
    }

    // MARK: - Editing Measurements

    /// The value and label of a measurement of `type` through `points` on page `pageIndex`, as
    /// the Measurement tools work them out.
    func measured(_ type: PDFAnnotationType, points: [CGPoint], pageIndex: Int, shape: MeasuredShape? = nil) -> (value: Double, text: String) {
        let scale = scaleConfig(for: pageIndex)
        if let shape { return (shape.value, shape.label(scale: scale)) }
        switch type {
        case .measureArea:
            let area = PDFMeasurementGeometry.shoelaceArea(points: points)
            return (area, scale.formatArea(pointsSquared: area))
        case .measureCount:
            return (1, "")
        case .measureAngle:
            guard points.count >= 3 else { return (0, "") }
            let degrees = PDFMeasurementGeometry.angleDegrees(r1: points[0], apex: points[1], r2: points[2])
            return (degrees, String(format: "%.1f°", degrees))
        default:
            let length = zip(points, points.dropFirst()).reduce(0.0) { $0 + Double(hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y)) }
            return (length, scale.formatLength(points: length))
        }
    }

    /// `annot` with new points, dimension-line offset or color, its value and label worked out
    /// again. A label of its own, rather than its value, is kept.
    /// A measurement drawn as a shape changes through `shape`, whose outline its points become;
    /// given points instead, it's no longer that shape.
    func editedMeasurement(_ annot: PDFAnnotation, points: [CGPoint]? = nil, shape: MeasuredShape? = nil, leaderOffset: CGFloat? = nil, color: AnnotationColor? = nil, strokeWidth: CGFloat? = nil) -> PDFAnnotation {
        let shape = shape ?? (points == nil ? annot.measuredShape : nil)
        let points = shape?.outline ?? points ?? annot.measurementPoints
        let (value, text) = measured(annot.type, points: points, pageIndex: annot.pageIndex, shape: shape)
        // A count marker's text is its group, whatever its point.
        let hasOwnLabel = annot.type == .measureCount || (!annot.text.isEmpty && annot.text != annot.measurementText)
        var edited = PDFAnnotation(
            id: annot.id,
            pageIndex: annot.pageIndex,
            type: annot.type,
            strokeWidth: strokeWidth ?? annot.strokeWidth,
            color: color ?? annot.color,
            text: hasOwnLabel ? annot.text : text,
            measurementPoints: points,
            measurementValue: value,
            measurementText: text,
            leaderOffset: leaderOffset ?? annot.leaderOffset,
            dateCreated: annot.dateCreated
        )
        edited.documentObjectNumber = annot.documentObjectNumber
        edited.layerObjectNumber = annot.layerObjectNumber
        edited.cameWithFile = annot.cameWithFile
        edited.measuredShape = shape
        return edited
    }

    /// Changes a measurement on the page to `edited` (from `editedMeasurement`): it's written
    /// again, keeping its comments and layer, as one step to undo.
    @discardableResult
    func replaceMeasurement(_ annot: PDFAnnotation, with edited: PDFAnnotation) -> PDFAnnotation? {
        guard annot.isMeasurement else { return nil }
        beginReplacingAnnotation(annot)
        defer { finishReplacingAnnotation() }
        return addMeasurementAnnotation(
            pageIndex: annot.pageIndex, type: annot.type, points: edited.measurementPoints,
            value: edited.measurementValue, formattedText: edited.measurementText,
            leaderOffset: edited.leaderOffset, color: edited.color, strokeWidth: edited.strokeWidth,
            label: edited.text, shape: edited.measuredShape
        )
    }

    /// A measurement in the file, as PDF object `objectNumber` on `pageIndex`, that isn't on the
    /// canvas yet: one that was in the file when it was opened.
    func fileMeasurement(pageIndex: Int, objectNumber: Int) -> PDFAnnotation? {
        guard pageAnnotations[pageIndex]?.contains(where: { $0.documentObjectNumber == objectNumber }) != true,
              var annot = document?.measurementAnnotations(pageIndex: pageIndex).first(where: { $0.documentObjectNumber == objectNumber }) else { return nil }
        annot.cameWithFile = true
        return annot
    }

    /// Picks up a measurement from `fileMeasurement` so it can be selected and changed. From now
    /// on the canvas draws it, and the renderer leaves it out.
    func pickUpMeasurement(_ annot: PDFAnnotation) -> PDFAnnotation {
        if let existing = pageAnnotations[annot.pageIndex]?.first(where: { $0.documentObjectNumber == annot.documentObjectNumber }) {
            return existing
        }
        pageAnnotations[annot.pageIndex, default: []].append(annot)
        return annot
    }

    // MARK: - Takeoff Summary Generation & Export

    /// One measurement in the takeoff, valued with the scale of the page it's on.
    public struct TakeoffEntry: Identifiable, Sendable {
        public let id = UUID()
        public let pageIndex: Int
        public let annotation: PDFAnnotation
        public let scale: PDFScaleConfiguration
        /// Length in `scale.linearUnit`, area in `scale.areaUnit`, or angle in degrees.
        public let realValue: Double
        public let unitSymbol: String
        public let formattedValue: String
    }

    /// The scale for a page, reading one stored in the document if this page hasn't been shown
    /// yet (scaleConfig(for:) only knows pages whose metadata has been loaded).
    private func resolvedScaleConfig(for pageIndex: Int) -> PDFScaleConfiguration {
        pageScaleConfigs[pageIndex] ?? document?.loadPageScale(pageIndex: pageIndex) ?? currentScaleConfig
    }

    /// Returns every measurement in the document, except ones on hidden layers.
    public func takeoffEntries() -> [TakeoffEntry] {
        guard let doc = document else { return [] }
        var entries: [TakeoffEntry] = []
        for pageIndex in 0..<doc.pageCount {
            let all = doc.measurementAnnotations(pageIndex: pageIndex, shownOnly: true)
            guard !all.isEmpty else { continue }
            let scale = resolvedScaleConfig(for: pageIndex)
            // Count markers are one row per group on each page, with how many there are.
            let markers = all.filter { $0.type == .measureCount }
            for (group, inGroup) in Dictionary(grouping: markers, by: \.text).sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending }) {
                guard let first = inGroup.first else { continue }
                entries.append(TakeoffEntry(pageIndex: pageIndex, annotation: first, scale: scale, realValue: Double(inGroup.count), unitSymbol: "ea", formattedValue: "\(group) × \(inGroup.count)"))
            }
            for annot in all where annot.type != .measureCount {
                let realValue: Double
                let unit: String
                let formatted: String
                switch annot.type {
                case .measureArea:
                    realValue = scale.convertAreaPointsToReal(pointsArea: annot.measurementValue)
                    unit = scale.areaUnit.shortSymbol
                    formatted = scale.formatArea(pointsSquared: annot.measurementValue)
                case .measureAngle:
                    realValue = annot.measurementValue
                    unit = "°"
                    formatted = scale.formatAngle(degrees: annot.measurementValue)
                default:
                    realValue = scale.convertPointsToReal(pointsDistance: annot.measurementValue)
                    // A feet-and-inches scale still yields a plain number of feet.
                    unit = scale.linearUnit == .footInch ? "ft" : scale.linearUnit.shortSymbol
                    formatted = scale.formatLength(points: annot.measurementValue)
                }
                entries.append(TakeoffEntry(pageIndex: pageIndex, annotation: annot, scale: scale, realValue: realValue, unitSymbol: unit, formattedValue: formatted))
            }
        }
        return entries
    }

    /// Total length (dimensions + perimeters) and area across `entries`, each converted with its
    /// own page's scale and expressed in the units of the first entry's scale.
    public func takeoffTotals(_ entries: [TakeoffEntry]) -> (linear: String?, area: String?) {
        guard let reference = entries.first?.scale else { return (nil, nil) }
        var meters = 0.0
        var squareMeters = 0.0
        for entry in entries {
            switch entry.annotation.type {
            case .measureLength, .measurePerimeter:
                meters += entry.scale.convertPointsToReal(pointsDistance: entry.annotation.measurementValue) * entry.scale.metersPerLinearUnit
            case .measureArea:
                squareMeters += entry.scale.squareMeters(pointsSquared: entry.annotation.measurementValue)
            default:
                break
            }
        }
        let ppu = reference.pointsPerUnit
        let mpu = reference.metersPerLinearUnit
        let linear = meters > 0 ? reference.formatLength(points: meters / mpu * ppu) : nil
        let area = squareMeters > 0 ? reference.formatArea(pointsSquared: squareMeters / (mpu * mpu) * ppu * ppu) : nil
        return (linear, area)
    }

    /// What a takeoff row is: its kind of measurement, or the shape it was drawn as.
    static func takeoffTypeName(_ annot: PDFAnnotation) -> String {
        switch annot.measuredShape?.kind {
        case .rectangle: return "Rectangle Area"
        case .circle: return "Circle Area"
        case .arc: return "Arc Length"
        case nil: return takeoffTypeName(annot.type)
        }
    }

    private static func takeoffTypeName(_ type: PDFAnnotationType) -> String {
        switch type {
        case .measureLength: return "Linear Dimension"
        case .measurePerimeter: return "Perimeter"
        case .measureArea: return "Area Takeoff"
        case .measureAngle: return "Angle"
        case .measureCount: return "Count"
        default: return "Measurement"
        }
    }

    /// How many of each Count group there are in `entries`, by group name.
    public func takeoffCounts(_ entries: [TakeoffEntry]) -> [(group: String, count: Int)] {
        var counts: [String: Int] = [:]
        for entry in entries where entry.annotation.type == .measureCount {
            counts[entry.annotation.text, default: 0] += Int(entry.realValue)
        }
        return counts.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }.map { ($0.key, $0.value) }
    }

    public func generateTakeoffSummaryMarkdown() -> String {
        let title = documentInspectionReport?.metadata.title.isEmpty == false ? documentInspectionReport!.metadata.title : (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).lastPathComponent : "Document")
        var md = "# Measurement Takeoff Summary: \(title)\n\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        md += "**Generated:** \(df.string(from: Date()))  \n\n"
        md += "---\n\n"

        let entries = takeoffEntries()
        guard !entries.isEmpty else {
            md += "*No calibrated measurements or takeoffs found in this document.*\n"
            return md
        }

        for (pageIndex, pageEntries) in Dictionary(grouping: entries, by: \.pageIndex).sorted(by: { $0.key < $1.key }) {
            md += "## Page \(pageIndex + 1) (Scale: \(pageEntries[0].scale.ratioString))\n\n"
            let byLayer = !layers.isEmpty
            md += "| Item | Type | Color | Measurement |" + (byLayer ? " Layer |" : "") + "\n"
            md += "| :--- | :--- | :--- | :--- |" + (byLayer ? " :--- |" : "") + "\n"
            for (idx, entry) in pageEntries.enumerated() {
                md += "| #\(idx + 1) | \(Self.takeoffTypeName(entry.annotation)) | \(entry.annotation.color.displayName) | **\(entry.formattedValue)** |"
                md += byLayer ? " \(layerName(entry.annotation.layerObjectNumber) ?? "") |\n" : "\n"
            }
            md += "\n"
        }

        let totals = takeoffTotals(entries)
        md += "---\n\n"
        md += "### Cumulative Totals\n\n"
        md += "- **Total Measurements:** \(entries.count)\n"
        if let linear = totals.linear {
            md += "- **Total Linear Footage / Perimeter:** \(linear)\n"
        }
        if let area = totals.area {
            md += "- **Total Calculated Surface Area:** \(area)\n"
        }
        for (group, count) in takeoffCounts(entries) {
            md += "- **Count, \(group):** \(count)\n"
        }
        return md
    }

    public func generateTakeoffSummaryCSV() -> String {
        func quoted(_ s: String) -> String { "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        // A Layer column only for a document with layers.
        let byLayer = !layers.isEmpty
        var csv = "Page,Index,Type,Color,Measurement,Value,Unit,Scale" + (byLayer ? ",Layer" : "") + "\n"
        for (pageIndex, pageEntries) in Dictionary(grouping: takeoffEntries(), by: \.pageIndex).sorted(by: { $0.key < $1.key }) {
            for (idx, entry) in pageEntries.enumerated() {
                csv += "\(pageIndex + 1),\(idx + 1),\(Self.takeoffTypeName(entry.annotation)),\(entry.annotation.color.displayName),\(quoted(entry.formattedValue)),\(String(format: "%.3f", entry.realValue)),\(quoted(entry.unitSymbol)),\(quoted(entry.scale.ratioString))"
                csv += byLayer ? ",\(quoted(layerName(entry.annotation.layerObjectNumber) ?? ""))\n" : "\n"
            }
        }
        return csv
    }

    public func exportTakeoffSummary() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Measurement Takeoff Summary"
        savePanel.prompt = "Export"
        let baseName = (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).deletingPathExtension().lastPathComponent : "Document")
        savePanel.nameFieldStringValue = "\(baseName)_Takeoff_Summary.csv"
        savePanel.allowedContentTypes = [.commaSeparatedText, .plainText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let isMD = url.pathExtension.lowercased() == "md"
            let content = isMD ? generateTakeoffSummaryMarkdown() : generateTakeoffSummaryCSV()
            do {
                try content.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                showErrorAlert(title: "Couldn't Export Takeoff Summary", message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Count tool

extension PDFViewerViewModel {
    /// The group a Count marker is placed in: `countGroup`, or "Count" when that's blank.
    public var effectiveCountGroup: String {
        let group = countGroup.trimmingCharacters(in: .whitespacesAndNewlines)
        return group.isEmpty ? "Count" : group
    }

    /// How many markers of `group` page `page` has.
    public func countMarkers(onPage page: Int, group: String) -> Int {
        guard let doc = document, page >= 0, page < doc.pageCount else { return 0 }
        let revision = annotationChange.revision
        if let cache = countCache, cache.revision == revision, cache.page == page {
            return cache.counts[group] ?? 0
        }
        var counts: [String: Int] = [:]
        for annot in doc.measurementAnnotations(pageIndex: page, shownOnly: true) where annot.type == .measureCount {
            counts[annot.text, default: 0] += 1
        }
        countCache = (revision, page, counts)
        return counts[group] ?? 0
    }

    /// The Count groups used in the document, by name.
    public func countGroupsInDocument() -> [String] {
        guard let doc = document else { return [] }
        var groups = Set<String>()
        for page in 0..<doc.pageCount {
            for annot in doc.measurementAnnotations(pageIndex: page) where annot.type == .measureCount {
                groups.insert(annot.text)
            }
        }
        return groups.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// Places a Count marker in the current group at `point` on `page`.
    @discardableResult
    public func addCountMarker(pageIndex: Int, at point: CGPoint) -> PDFAnnotation? {
        let group = effectiveCountGroup
        return addMeasurementAnnotation(pageIndex: pageIndex, type: .measureCount, points: [point], value: 1,
                                        formattedText: group, color: measurementColor, strokeWidth: measurementStrokeWidth, label: group)
    }
}

