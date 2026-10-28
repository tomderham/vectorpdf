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
import Testing
@testable import PDFEngine

/// Many documents opened, read, searched and rendered at once, each on its own MuPDF context, as
/// the app does with several tabs and as the test suite does in parallel. A crash here is a
/// thread-safety bug. Slow, so it only runs with `VECTORPDF_STRESS_TESTS=1 swift test`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["VECTORPDF_STRESS_TESTS"] == "1",
                "Stress test; run with VECTORPDF_STRESS_TESTS=1"))
struct ConcurrencyStressTests {
    private let files = [
        "federal-register-2024-00301.pdf", "nist-tn-2255.pdf", "rfc9457.pdf",
        "ieee-802.11-draft-layout.pdf", "hr1968-ih.pdf", "lcms2-tutorial.pdf", "f1040.pdf",
    ]

    @Test func documentsUsedInParallelDoNotCrash() async throws {
        let rounds = Int(ProcessInfo.processInfo.environment["VECTORPDF_STRESS_ROUNDS"] ?? "") ?? 6
        for _ in 0..<rounds {
            await withTaskGroup(of: Void.self) { group in
                for (i, file) in (files + files).enumerated() {
                    let path = Fixture.url(file).path
                    group.addTask {
                        // Open, then read text, render and export from the first few pages.
                        guard let doc = try? PDFDocumentCore(filePath: path) else { return }
                        for page in 0..<min(doc.pageCount, 4) {
                            _ = doc.loadStructuredPage(for: page)
                            _ = doc.renderPageRect(pageIndex: page, rect: doc.pageBounds[page], scale: 1)
                            if i % 3 == 0 {
                                let svg = FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_stress_\(UUID().uuidString).svg")
                                try? doc.exportPageToSVGFile(pageIndex: page, destinationURL: svg)
                                try? FileManager.default.removeItem(at: svg)
                            }
                        }
                    }
                    group.addTask {
                        let actor = PDFSearchActor()
                        try? await actor.openDocument(filePath: path)
                        _ = try? await actor.search(query: "the")
                    }
                    group.addTask {
                        let renderer = PDFRenderActor()
                        try? await renderer.openDocument(filePath: path)
                        for page in 0..<3 { _ = try? await renderer.renderPage(pageIndex: page, scale: 1) }
                    }
                }
            }
        }
    }
}
