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
    // MARK: - On-Device Apple Vision OCR

    public func isScannedPage(_ pageIndex: Int) -> Bool {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return false }
        if ocrResults[pageIndex] != nil { return false }
        return doc.isScannedPage(pageIndex: pageIndex)
    }

    /// Forgets the text recognized on pages whose content or geometry changed, so nothing can
    /// select or find text that a redaction removed, and returns those pages. Discards any
    /// recognition under way, which may have rendered the old pages; follow with
    /// `recognizeAgain(_:)` once the document is reopened.
    func discardOCR(onPages pages: Set<Int>) -> Set<Int> {
        ocrGeneration += 1
        let recognized = pages.filter { ocrResults[$0] != nil }
        for page in recognized { ocrResults.removeValue(forKey: page) }
        return recognized
    }

    func recognizeAgain(_ pages: Set<Int>) async {
        guard let doc = document else { return }
        let generation = ocrGeneration
        for page in pages.sorted() {
            guard document === doc, ocrGeneration == generation else { return }
            await runOCR(onPageIndex: page)
        }
        guard document === doc, ocrGeneration == generation else { return }
        startScannedPageDetection()
    }

    public func runOCR(onPageIndex pageIndex: Int) async {
        guard let doc = document, pageIndex >= 0, pageIndex < doc.pageCount else { return }
        guard ocrResults[pageIndex] == nil else { return }
        let generation = ocrGeneration

        await MainActor.run { self.activeOCRCount += 1 }
        defer {
            Task { @MainActor in
                self.activeOCRCount = max(0, self.activeOCRCount - 1)
            }
        }

        do {
            let pageBounds = doc.pageBounds[pageIndex]
            let maxDim = max(pageBounds.width, pageBounds.height)
            let result: PDFOCRPageResult

            if maxDim > 1200 {
                // Tiled high-resolution OCR for large schematics, posters, and technical drawings
                var tileResults: [PDFOCRPageResult] = []
                let targetTileSize: CGFloat = 1100.0
                let overlap: CGFloat = 60.0
                let step = targetTileSize - overlap

                var y = pageBounds.minY
                while y < pageBounds.maxY {
                    let tileH = min(targetTileSize, pageBounds.maxY - y)
                    var x = pageBounds.minX
                    while x < pageBounds.maxX {
                        let tileW = min(targetTileSize, pageBounds.maxX - x)
                        let tileRect = CGRect(x: x, y: y, width: tileW, height: tileH)

                        let tileImage = try await renderActor.renderPageRect(
                            pageIndex: pageIndex,
                            rect: tileRect,
                            scale: 300.0 / 72.0
                        )
                        let res = try await PDFOCREngine.shared.recognizeText(
                            in: tileImage,
                            pageIndex: pageIndex,
                            pageBounds: tileRect
                        )
                        tileResults.append(res)

                        if x + tileW >= pageBounds.maxX { break }
                        x += step
                    }
                    if y + tileH >= pageBounds.maxY { break }
                    y += step
                }
                result = await PDFOCREngine.shared.mergeOCRResults(pageIndex: pageIndex, results: tileResults)
            } else {
                let rendered = try await renderActor.renderPage(pageIndex: pageIndex, scale: 300.0 / 72.0)
                result = try await PDFOCREngine.shared.recognizeText(
                    in: rendered.image,
                    pageIndex: pageIndex,
                    pageBounds: pageBounds
                )
            }
            await MainActor.run {
                guard self.document === doc, self.ocrGeneration == generation else { return }
                self.ocrResults[pageIndex] = result
                self.detectedScannedPages.remove(pageIndex)
                let query = self.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if !query.isEmpty {
                    self.performSearch(autoNavigate: false)
                }
            }
        } catch {
            print("OCR failed on page \(pageIndex): \(error)")
        }
    }

    public func runOCROnAllScannedPages() async {
        guard let doc = document else { return }
        let generation = ocrGeneration

        // Checking every page for extractable text is slow on a large document, so it happens off
        // the main thread; only the OCR bookkeeping itself comes back here.
        let scanned = await Task.detached(priority: .utility) {
            (0..<doc.pageCount).filter { doc.isScannedPage(pageIndex: $0) }
        }.value
        for pIdx in scanned {
            guard document === doc, ocrGeneration == generation else { return }
            if ocrResults[pIdx] == nil {
                await runOCR(onPageIndex: pIdx)
            }
        }
    }
}
