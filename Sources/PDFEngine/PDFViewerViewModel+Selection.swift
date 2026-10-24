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
    // MARK: - Text Selection
    public func handleDragSelect(pageIndex: Int, startPagePoint: CGPoint, currentPagePoint: CGPoint, forceMode: SelectionMode? = nil) {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else { return }
        let mode = forceMode ?? selectionMode
        let res = textSelector.selectText(on: stext, from: startPagePoint, to: currentPagePoint, mode: mode)
        if !res.text.isEmpty || (!res.highlightQuads.isEmpty && mode == .rectangularArea) {
            self.activeSelection = (pageIndex: pageIndex, result: res)
            self.additionalSelectionPages = []
        }
    }

    public func selectWord(at pagePoint: CGPoint, pageIndex: Int) {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else { return }
        if let res = textSelector.selectWord(at: pagePoint, on: stext) {
            self.activeSelection = (pageIndex: pageIndex, result: res)
            self.additionalSelectionPages = []
        }
    }

    public func selectLine(at pagePoint: CGPoint, pageIndex: Int) {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else { return }
        if let res = textSelector.selectLine(at: pagePoint, on: stext) {
            self.activeSelection = (pageIndex: pageIndex, result: res)
            self.additionalSelectionPages = []
        }
    }

    // MARK: - Translation Support

    public func translateSelection() {
        let text = activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Apple's Translation framework (macOS 15+) presents the translation in place.
        self.translationTargetText = text
        self.isPresentingTranslation = true
    }

    // MARK: - Speech Support
    public var isSpeaking: Bool {
        PDFSpeechCoordinator.shared.isSpeaking
    }

    public func startSpeakingSelection() {
        let text = activeSelectionCombinedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        PDFSpeechCoordinator.shared.startSpeaking(text)
    }

    public func stopSpeaking() {
        PDFSpeechCoordinator.shared.stopSpeaking()
    }

    public func toggleSpeakingSelection() {
        if isSpeaking {
            stopSpeaking()
        } else {
            startSpeakingSelection()
        }
    }

    /// Handles reading-order text selection spanning across page boundaries.
    public func handleCrossPageDragSelect(pageA: Int, pointA: CGPoint, pageB: Int, pointB: CGPoint) {
        guard pageA != pageB else {
            handleDragSelect(pageIndex: pageA, startPagePoint: pointA, currentPagePoint: pointB)
            return
        }
        let (firstPage, firstPoint, lastPage, lastPoint) = pageA < pageB ? (pageA, pointA, pageB, pointB) : (pageB, pointB, pageA, pointA)

        var results: [PageSelectionResult] = []
        for pageIdx in firstPage...lastPage {
            guard let stext = pageStructuredData[pageIdx] ?? document?.loadStructuredPage(for: pageIdx) else { continue }
            let topLeft = CGPoint(x: stext.bounds.minX, y: stext.bounds.minY)
            let bottomRight = CGPoint(x: stext.bounds.maxX, y: stext.bounds.maxY)

            let from: CGPoint
            let to: CGPoint
            if pageIdx == firstPage {
                from = firstPoint
                to = bottomRight
            } else if pageIdx == lastPage {
                from = topLeft
                to = lastPoint
            } else {
                // Fully intervening page — select it in its entirety.
                from = topLeft
                to = bottomRight
            }

            let res = textSelector.selectText(on: stext, from: from, to: to, mode: .readingOrder)
            if !res.text.isEmpty || !res.highlightQuads.isEmpty {
                results.append(PageSelectionResult(pageIndex: pageIdx, result: res))
            }
        }

        guard let first = results.first else {
            self.activeSelection = nil
            self.additionalSelectionPages = []
            return
        }
        self.activeSelection = (pageIndex: first.pageIndex, result: first.result)
        self.additionalSelectionPages = Array(results.dropFirst())
    }

    /// Selects all text on the current page — the PDF-content equivalent of the Edit menu's
    /// "Select All" (see PDFCanvasView.selectAll), which otherwise does nothing when the canvas
    /// itself has focus rather than some other text control. Deliberately page-scoped rather than
    /// whole-document, to keep this simple: reuses the same "select a page in full" corner-to-
    /// corner trick already used for pages fully spanned by a cross-page drag, just above.
    public func selectAllOnCurrentPage() {
        guard let stext = pageStructuredData[currentPageIndex] ?? document?.loadStructuredPage(for: currentPageIndex) else { return }
        let topLeft = CGPoint(x: stext.bounds.minX, y: stext.bounds.minY)
        let bottomRight = CGPoint(x: stext.bounds.maxX, y: stext.bounds.maxY)
        handleDragSelect(pageIndex: currentPageIndex, startPagePoint: topLeft, currentPagePoint: bottomRight, forceMode: .readingOrder)
    }

    /// The full selected text, combining `activeSelection` with any further pages in
    /// `additionalSelectionPages` in page order — for an ordinary single-page selection this is
    /// just that one page's text, unchanged.
    public var activeSelectionCombinedText: String {
        guard let sel = activeSelection else { return "" }
        return ([sel.result.text] + additionalSelectionPages.map { $0.result.text })
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    public func copyActiveSelection() {
        let combined = activeSelectionCombinedText
        guard !combined.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(combined, forType: .string)
    }
    
    /// Extracts a cropped high-resolution NSImage from the active rectangular marquee selection.
    public func renderCroppedSelection(scale: CGFloat = 2.0) -> NSImage? {
        guard let sel = activeSelection, let doc = document else { return nil }
        let pageIdx = sel.pageIndex
        guard doc.pageBounds.indices.contains(pageIdx) else { return nil }
        let pageBounds = doc.pageBounds[pageIdx]
        let targetRect = sel.result.boundingRect
        guard targetRect.width > 2 && targetRect.height > 2 else { return nil }
        
        guard let pageImage = renderedPages[pageIdx],
              let cgImage = pageImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        
        let scaleX = CGFloat(cgImage.width) / pageBounds.width
        let scaleY = CGFloat(cgImage.height) / pageBounds.height
        
        let cropX = max(0, (targetRect.minX - pageBounds.minX) * scaleX)
        let cropY = max(0, (targetRect.minY - pageBounds.minY) * scaleY)
        let cropW = min(CGFloat(cgImage.width) - cropX, targetRect.width * scaleX)
        let cropH = min(CGFloat(cgImage.height) - cropY, targetRect.height * scaleY)
        
        guard cropW > 0 && cropH > 0 else { return nil }
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        
        return NSImage(cgImage: cropped, size: NSSize(width: targetRect.width, height: targetRect.height))
    }
    
    /// Copies the active rectangular selection as high-DPI image (PNG primary, TIFF fallback, and extracted text) to NSPasteboard.general
    public func copyActiveScreenshot() {
        guard let image = renderCroppedSelection() else { return }
        let pb = NSPasteboard.general
        pb.clearContents()

        let item = NSPasteboardItem()
        if let tiffData = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiffData) {
            if let pngData = rep.representation(using: .png, properties: [:]) {
                item.setData(pngData, forType: .png)
            }
            item.setData(tiffData, forType: .tiff)
        }
        if let sel = activeSelection, !sel.result.text.isEmpty {
            item.setString(sel.result.text, forType: .string)
        }
        pb.writeObjects([item])
    }
    
    /// Prompts an AppKit NSSavePanel to save the active screenshot as a PNG file.
    public func saveActiveScreenshot() {
        guard let image = renderCroppedSelection() else { return }
        guard let tiffData = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiffData),
              let pngData = rep.representation(using: .png, properties: [:]) else { return }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.png]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "Screenshot_Page_\(currentPageIndex + 1).png"
        panel.title = "Save Screenshot As"
        panel.prompt = "Save Screenshot"
        
        let completion: (NSApplication.ModalResponse) -> Void = { response in
            if response == .OK, let url = panel.url {
                try? pngData.write(to: url)
            }
        }
        
        if let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            panel.begin(completionHandler: completion)
        }
    }
    
    /// Dispatches appropriate copy action depending on selection mode.
    public func copyCommandAction() {
        if let sel = activeSelection, sel.result.mode == .rectangularArea {
            copyActiveScreenshot()
        } else {
            copyActiveSelection()
        }
    }
    
    public func clearSelection() {
        self.activeSelection = nil
        self.additionalSelectionPages = []
    }
}
