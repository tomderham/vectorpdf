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
import ImageIO
import Testing
@testable import PDFEngine

/// Pages are exported as PNG, JPEG or TIFF images at a chosen resolution.
struct PageImageExportTests {
    private func properties(of url: URL) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        return try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    @Test func onePageIsOneFileAtTheResolutionChosen() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: pdf, labels: ["Alpha", "Bravo"])
        let doc = try PDFDocumentCore(filePath: pdf.path)
        let url = dir.appendingPathComponent("Plan page 2.png")
        let written = try doc.exportPageImages(pageIndices: [1], format: .png, dpi: 300, to: url)
        #expect(written == [url])
        let props = try properties(of: url)
        // US Letter at 300 dpi.
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 2550)
        #expect(props[kCGImagePropertyPixelHeight] as? Int == 3300)
        #expect((props[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 300) < 1 } == true)
    }

    @Test func severalPagesGoInAFolder() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("Plan.pdf")
        makeLabelledPDF(at: pdf, labels: Array(natoLabels.prefix(3)) + ["India", "Juliett", "Kilo", "Lima", "Mike", "November", "Oscar"])
        let doc = try PDFDocumentCore(filePath: pdf.path)
        for format in PageImageFormat.allCases {
            let url = dir.appendingPathComponent("Plan \(format.title).\(format.fileExtension)")
            let written = try doc.exportPageImages(pageIndices: [0, 9], format: format, dpi: 72, to: url)
            let folder = dir.appendingPathComponent("Plan \(format.title)")
            // Numbered to sort in page order.
            #expect(written.map(\.lastPathComponent) == ["Plan \(format.title) 01.\(format.fileExtension)", "Plan \(format.title) 10.\(format.fileExtension)"])
            #expect(written.allSatisfy { $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL })
            let source = try #require(CGImageSourceCreateWithURL(written[0] as CFURL, nil))
            #expect(CGImageSourceGetType(source) as String? == format.contentType.identifier)
            #expect(try properties(of: written[1])[kCGImagePropertyPixelWidth] as? Int == 612)
        }
    }

    @Test func aHugePageIsMadeSmaller() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pdf = dir.appendingPathComponent("Drawing.pdf")
        // A0 landscape.
        makeLabelledPDF(at: pdf, labels: ["Alpha"], pageSize: CGSize(width: 3370, height: 2384))
        let doc = try PDFDocumentCore(filePath: pdf.path)
        let image = try doc.renderPageImage(pageIndex: 0, dpi: 600)
        #expect(image.width == PDFDocumentCore.maxExportPixelEdge)
        #expect(abs(Double(image.height) - 16384 * 2384 / 3370) < 2)
    }
}
