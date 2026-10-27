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

import AppKit
import Foundation
import Testing
@testable import PDFEngine

/// PDFs committed under `Resources/test-files` (see the README there for where each came from).
enum Fixture {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/test-files")

    /// IRS Form 1040: AcroForm text fields, checkboxes and radio buttons.
    static var form1040: URL { url("f1040.pdf") }
    /// Little CMS tutorial: 60 pages of real-world typesetting with embedded fonts and internal links.
    static var lcmsTutorial: URL { url("lcms2-tutorial.pdf") }

    /// The fixture's URL, recording a test failure (not a silent skip) if it is missing.
    static func url(_ name: String, sourceLocation: SourceLocation = #_sourceLocation) -> URL {
        let url = directory.appendingPathComponent(name)
        if !FileManager.default.fileExists(atPath: url.path) {
            Issue.record("Missing test fixture \(name) in Resources/test-files", sourceLocation: sourceLocation)
        }
        return url
    }
}

/// A fresh, empty directory for one test's files; remove it with `defer`.
func makeScratchDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// Writes a PDF with one page per label, each page showing only its label, so a test can tell
/// pages apart after they are moved, copied or imported (see `pageLabels`).
func makeLabelledPDF(at url: URL, labels: [String], pageSize: CGSize = CGSize(width: 612, height: 792)) {
    var mediaBox = CGRect(origin: .zero, size: pageSize)
    guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create CGPDFContext")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for label in labels {
        context.beginPDFPage(nil)
        (label as NSString).draw(at: NSPoint(x: 72, y: pageSize.height - 120),
                                 withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
        context.endPDFPage()
    }
    context.closePDF()
}

/// Which of `labels` each page of `doc` shows, in page order; "" for a page showing none of them
/// (such as a blank page).
func pageLabels(of doc: PDFDocumentCore, among labels: [String]) -> [String] {
    (0..<doc.pageCount).map { index in
        let text = doc.extractText(pageIndex: index) ?? ""
        return labels.first { text.contains($0) } ?? ""
    }
}

/// The same, for a saved file.
func pageLabels(ofFileAt url: URL, among labels: [String]) throws -> [String] {
    pageLabels(of: try PDFDocumentCore(filePath: url.path), among: labels)
}

let natoLabels = ["Alpha", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"]
