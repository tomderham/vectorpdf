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
    // MARK: - Review Summary Export

    public func generateReviewSummaryMarkdown() -> String {
        let title = documentInspectionReport?.metadata.title.isEmpty == false ? documentInspectionReport!.metadata.title : (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).lastPathComponent : "Document")
        
        var md = "# Review Summary: \(title)\n\n"
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        md += "**Generated:** \(df.string(from: Date()))  \n"
        let totalCount = pageAnnotations.values.reduce(0) { $0 + $1.count }
        md += "**Total Annotations:** \(totalCount)  \n\n"
        md += "---\n\n"

        let sortedPages = pageAnnotations.keys.sorted()
        if sortedPages.isEmpty {
            md += "*No annotations found in this document.*\n"
            return md
        }

        for pIdx in sortedPages {
            guard let annots = pageAnnotations[pIdx], !annots.isEmpty else { continue }
            md += "## Page \(pIdx + 1)\n\n"
            for annot in annots {
                let colorName = annot.color.displayName
                switch annot.type {
                case .highlight:
                    let quoted = annot.text.isEmpty ? "*(Highlighted area)*" : "\"\(annot.text)\""
                    md += "- **[Highlight]** *(\(colorName))*: \(quoted)\n"
                case .underline:
                    let quoted = annot.text.isEmpty ? "*(Underlined area)*" : "\"\(annot.text)\""
                    md += "- **[Underline]** *(\(colorName))*: \(quoted)\n"
                case .strikeout:
                    let quoted = annot.text.isEmpty ? "*(Strikethrough area)*" : "\"\(annot.text)\""
                    md += "- **[Strikethrough]** *(\(colorName))*: \(quoted)\n"
                case .freeText:
                    md += "- **[Note / Free Text]** *(\(colorName))*: \(annot.text)\n"
                case .callout:
                    var loc = ""
                    if let tp = annot.targetPoint {
                        loc = " pointing at (\(Int(tp.x)), \(Int(tp.y)))"
                    }
                    md += "- **[Callout]** *(\(colorName)\(loc))*: \(annot.text)\n"
                case .ink:
                    md += "- **[Ink Drawing]** *(\(colorName))*: \(annot.inkPoints.count) points\n"
                case .stamp:
                    md += "- **[Signature / Stamp]**: Area \(annot.rect.map { "(\(Int($0.minX)), \(Int($0.minY)), \(Int($0.width))x\(Int($0.height)))" } ?? "")\n"
                case .measureLength:
                    md += "- **[Dimension]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                case .measurePerimeter:
                    md += "- **[Perimeter]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                case .measureArea:
                    md += "- **[Area Takeoff]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                case .measureAngle:
                    md += "- **[Angle]** *(\(colorName))*: \(annot.measurementText.isEmpty ? annot.text : annot.measurementText)\n"
                }
            }
            md += "\n"
        }
        return md
    }

    public func generateReviewSummaryCSV() -> String {
        var csv = "Page,Type,Color,Content,Coordinates,Date\n"
        let df = ISO8601DateFormatter()
        let sortedPages = pageAnnotations.keys.sorted()
        for pIdx in sortedPages {
            guard let annots = pageAnnotations[pIdx] else { continue }
            for annot in annots {
                let pageStr = "\(pIdx + 1)"
                let typeStr = annot.type.rawValue.capitalized
                let colorStr = annot.color.displayName
                let contentRaw = annot.measurementText.isEmpty ? annot.text : annot.measurementText
                let contentEscaped = contentRaw.replacingOccurrences(of: "\"", with: "\"\"")
                var coordStr = ""
                if let r = annot.rect {
                    coordStr = "(\(Int(r.minX)) \(Int(r.minY)) \(Int(r.width))x\(Int(r.height)))"
                } else if let tp = annot.targetPoint {
                    coordStr = "(\(Int(tp.x)) \(Int(tp.y)))"
                } else if !annot.measurementPoints.isEmpty {
                    coordStr = annot.measurementPoints.map { "(\(Int($0.x)),\(Int($0.y)))" }.joined(separator: "-")
                }
                let dateStr = df.string(from: annot.dateCreated)
                csv += "\(pageStr),\(typeStr),\(colorStr),\"\(contentEscaped)\",\"\(coordStr)\",\(dateStr)\n"
            }
        }
        return csv
    }

    public func exportAnnotationsSummary() {
        let savePanel = NSSavePanel()
        savePanel.title = "Export Annotations Summary"
        savePanel.prompt = "Export"
        let baseName = (document?.filePath != nil ? URL(fileURLWithPath: document!.filePath).deletingPathExtension().lastPathComponent : "Document")
        savePanel.nameFieldStringValue = "\(baseName)_Annotations_Summary.md"
        savePanel.allowedContentTypes = [.plainText, .commaSeparatedText]

        if savePanel.runModal() == .OK, let url = savePanel.url {
            let isCSV = url.pathExtension.lowercased() == "csv"
            let content = isCSV ? generateReviewSummaryCSV() : generateReviewSummaryMarkdown()
            try? content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    public func exportReviewSummary() {
        exportAnnotationsSummary()
    }

    /// Prompts the user with a save panel and exports the open document in the specified format (.txt, .docx, or flattened .pdf).
    public func exportDocument(as format: ExportDocumentFormat) {
        guard let doc = document else { return }

        if format == .flattenedPDF {
            saveDocumentFlattenedAs()
            return
        }

        let isMultiPageSVG = (format == .svgDocument && doc.pageCount > 1)
        let baseName = URL(fileURLWithPath: doc.filePath).deletingPathExtension().lastPathComponent

        let savePanel = NSSavePanel()
        if isMultiPageSVG {
            savePanel.title = "Export SVG Pages to Folder"
            savePanel.prompt = "Export"
            savePanel.nameFieldStringValue = "\(baseName)"
            savePanel.canCreateDirectories = true
        } else {
            let formatTitle: String
            switch format {
            case .plainText: formatTitle = "Plain Text"
            case .wordDocument: formatTitle = "Word Document"
            case .svgDocument: formatTitle = "Scalable Vector Graphics"
            case .flattenedPDF: formatTitle = "Flattened PDF"
            }
            savePanel.title = "Export Document As \(formatTitle)"
            savePanel.prompt = "Export"
            savePanel.nameFieldStringValue = "\(baseName).\(format.fileExtension)"
            if let utType = UTType(filenameExtension: format.fileExtension) {
                savePanel.allowedContentTypes = [utType]
            }
        }

        guard savePanel.runModal() == .OK, let url = savePanel.url else { return }

        // Reconstructing every page's layout takes a while on a long document — off the main thread.
        Task { [weak self] in
            let failure: String? = await Task.detached(priority: .userInitiated) {
                let exporter = PDFDocumentExporter()
                do {
                    switch format {
                    case .plainText:
                        try exporter.exportPlainText(from: doc).write(to: url, atomically: true, encoding: .utf8)
                    case .wordDocument:
                        try exporter.exportWordDocument(from: doc, to: url)
                    case .svgDocument:
                        try exporter.exportSVG(from: doc, to: url)
                    case .flattenedPDF:
                        break // Handled above via saveDocumentFlattenedAs()
                    }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure {
                self?.showErrorAlert(title: "Couldn't Export Document", message: failure)
            }
        }
    }
}
