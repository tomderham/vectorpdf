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
    /// Builds a SnapshotTarget from the current selection, without saving it anywhere — shared by
    /// addSnapshotFromSelection() (saves to the sidebar list) and openSelectionInNewWindow()
    /// (opens it directly in a new window without saving a card). For a selection spanning more
    /// than one page, the target itself (page/rect/thumbnail) always anchors to the *first* page
    /// — "jump back to this snapshot" for a passage that crosses a page break most naturally means
    /// jumping to where it begins — but the label/snippet reflect the full combined text.
    public func buildSnapshotTargetFromSelection() -> SnapshotTarget? {
        guard let sel = activeSelection else { return nil }
        let pageIdx = sel.pageIndex
        let bounds = (document?.pageBounds.indices.contains(pageIdx) == true)
            ? document!.pageBounds[pageIdx]
            : CGRect(x: 0, y: 0, width: 612, height: 792)
        let combinedText = activeSelectionCombinedText

        let labelText: String
        if !combinedText.isEmpty {
            let firstLine = combinedText.components(separatedBy: .newlines).first ?? combinedText
            let normalized = firstLine.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            let truncated = normalized.truncatedAtWordBoundary(maxLength: 45)
            labelText = truncated.isEmpty ? "Anchor (Page \(pageIdx + 1))" : truncated
        } else if sel.result.mode == .rectangularArea {
            labelText = "Area Anchor (Page \(pageIdx + 1))"
        } else {
            // A reading-order selection with nothing extractable (visible highlight, empty
            // text) — rare, but possible; "Area Anchor" would be actively misleading here.
            labelText = "Anchor (Page \(pageIdx + 1))"
        }

        // Only generate a screenshot for rectangular/area selections, where boundingRect is
        // exactly the dragged rectangle — a clean, correct crop. For text (reading-order)
        // selections, boundingRect is the union of every selected line's quad, which for any
        // multi-line/wrapped selection spans the full width between the two, pulling in
        // whatever unselected content sits between them (e.g. the rest of a two-column layout)
        // — a crop that looks distorted/wrong relative to what was actually selected. Text
        // selections rely on the extracted text alone, which is exact by construction.
        var thumbData: Data? = nil
        if sel.result.mode == .rectangularArea, let image = renderedPages[pageIdx] {
            thumbData = makeThumbnail(from: image, pageBounds: bounds, targetRect: sel.result.boundingRect)
        }

        let targetRect: CGRect
        if sel.result.mode == .rectangularArea {
            targetRect = sel.result.boundingRect
        } else if let firstLineQuad = sel.result.highlightQuads.mergedLineQuads().first {
            // For reading-order selections, anchor targetRect to the first line's quads so
            // multi-line or multi-column selections don't create an inflated box covering unselected
            // columns and gutters.
            targetRect = firstLineQuad.boundingRect
        } else {
            targetRect = sel.result.boundingRect
        }
        let targetPoint = CGPoint(x: targetRect.midX, y: targetRect.midY)

        return SnapshotTarget(
            label: labelText,
            snippet: combinedText,
            targetPage: pageIdx,
            targetPoint: targetPoint,
            targetRect: targetRect,
            sourceRect: targetRect,
            sourcePage: pageIdx,
            thumbnailData: thumbData
        )
    }

    public func addSnapshotFromSelection() {
        guard let target = buildSnapshotTargetFromSelection() else { return }
        addSnapshotTarget(target)
    }

    /// Opens the current selection (text or area) in a new window at that exact location,
    /// without saving a snapshot card — for a one-off "let me see this next to what I'm reading"
    /// without cluttering the Snapshots list.
    public func openSelectionInNewWindow() {
        guard let target = buildSnapshotTargetFromSelection() else { return }
        openSnapshotInNewWindow(target)
    }

    /// Builds a SnapshotTarget from a search result row, representing a text shortcut containing
    /// the matched hit and its surrounding context words.
    public func buildSnapshotTarget(from match: SearchResult) -> SnapshotTarget {
        let unionRect = match.highlightQuads.reduce(into: CGRect.null) { rect, quad in
            rect = rect.isNull ? quad.boundingRect : rect.union(quad.boundingRect)
        }
        let targetRect = unionRect.isNull ? nil : unionRect
        let targetPoint = targetRect.map { CGPoint(x: $0.midX, y: $0.midY) }

        let label = match.matchedText.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = label.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let truncated = normalized.truncatedAtWordBoundary(maxLength: 45)
        let cleanLabel = truncated.isEmpty ? "Search Match (Page \(match.pageIndex + 1))" : truncated

        return SnapshotTarget(
            label: cleanLabel,
            snippet: match.snippet,
            targetPage: match.pageIndex,
            targetPoint: targetPoint,
            targetRect: targetRect,
            sourceRect: targetRect,
            sourcePage: match.pageIndex,
            thumbnailData: nil
        )
    }

    /// Saves a snapshot shortcut from a search result hit directly into the snapshots collection.
    /// Skips duplicate creation if an identical snapshot (same page and snippet/rect) is already present,
    /// without re-selecting any snapshot so the user's active search triage flow is not disrupted.
    public func addSnapshot(from match: SearchResult) {
        let isDuplicate = activeSnapshots.contains { snap in
            guard snap.targetPage == match.pageIndex else { return false }
            if snap.snippet == match.snippet { return true }
            if let snapRect = snap.targetRect, !match.highlightQuads.isEmpty {
                let matchRect = match.highlightQuads.reduce(into: CGRect.null) { $0 = $0.isNull ? $1.boundingRect : $0.union($1.boundingRect) }
                if !matchRect.isNull && snapRect.intersects(matchRect) {
                    return true
                }
            }
            return false
        }

        guard !isDuplicate else { return }

        let target = buildSnapshotTarget(from: match)
        activeSnapshots.append(target)
        saveReadingStateIfNeeded()
    }

    /// Opens the search result in a separate snapshot window centered on the match coordinates.
    public func openSnapshotInNewWindow(from match: SearchResult) {
        let target = buildSnapshotTarget(from: match)
        openSnapshotInNewWindow(target)
    }

    /// Saves a search result as a snapshot and opens it in a new window in one step.
    public func addSnapshotAndOpenInNewWindow(from match: SearchResult) {
        let target = buildSnapshotTarget(from: match)
        addSnapshot(from: match)
        let snapToOpen = activeSnapshots.first(where: { $0.id == target.id || ($0.targetPage == match.pageIndex && $0.snippet == match.snippet) }) ?? target
        openSnapshotInNewWindow(snapToOpen)
    }

    /// Builds a SnapshotTarget from a Table of Contents outline node.
    public func buildSnapshotTarget(from node: PDFOutlineNode) -> SnapshotTarget? {
        guard let page = node.targetPage else { return nil }
        let label = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = label.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
        let cleanLabel = normalized.isEmpty ? "Page \(page + 1)" : normalized
        return SnapshotTarget(
            label: cleanLabel,
            snippet: cleanLabel,
            targetPage: page,
            targetPoint: nil,
            targetRect: nil,
            sourceRect: nil,
            sourcePage: page,
            uri: node.uri,
            thumbnailData: nil
        )
    }

    /// Saves a snapshot shortcut from a Table of Contents outline node into the snapshots collection.
    public func addSnapshot(from node: PDFOutlineNode) {
        guard let target = buildSnapshotTarget(from: node) else { return }
        addSnapshotTarget(target)
    }

    /// Opens the outline node in a separate snapshot window centered on the target page.
    public func openSnapshotInNewWindow(from node: PDFOutlineNode) {
        guard let target = buildSnapshotTarget(from: node) else { return }
        openSnapshotInNewWindow(target)
    }

    /// Saves an outline node as a snapshot and opens it in a new window in one step.
    public func addSnapshotAndOpenInNewWindow(from node: PDFOutlineNode) {
        guard let target = buildSnapshotTarget(from: node) else { return }
        addSnapshot(from: node)
        let snapToOpen = activeSnapshots.first(where: { $0.id == target.id || ($0.targetPage == target.targetPage && $0.snippet == target.snippet) }) ?? target
        openSnapshotInNewWindow(snapToOpen)
    }

    /// Saves a snapshot target and opens it in a new window in one step.
    public func addSnapshotAndOpen(_ target: SnapshotTarget) {
        addSnapshotTarget(target)
        openSnapshotInNewWindow(target)
    }

    /// Saves the current selection as a snapshot and opens it in a new window in one step.
    public func addSnapshotAndOpenFromSelection() {
        guard let target = buildSnapshotTargetFromSelection() else { return }
        addSnapshotTarget(target)
        openSnapshotInNewWindow(target)
    }

    /// Builds a SnapshotTarget at an arbitrary point on a page (e.g. from right-clicking with no active selection),
    /// Builds an Anchor/Snapshot target at an arbitrary point on a page (e.g. from right-clicking with no active selection),
    /// deterministically filtering out margin line-number gutters and matching section/subsection headings directly from the outline.
    public func buildSnapshotTarget(at pagePoint: CGPoint, pageIndex: Int) -> SnapshotTarget {
        guard let stext = pageStructuredData[pageIndex] ?? document?.loadStructuredPage(for: pageIndex) else {
            return SnapshotTarget(
                label: "Page \(pageIndex + 1)",
                snippet: "Page \(pageIndex + 1)",
                targetPage: pageIndex,
                targetPoint: pagePoint,
                targetRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
                sourceRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
                sourcePage: pageIndex,
                thumbnailData: nil
            )
        }

        // 1. Collect all authoritative outline (TOC) nodes for this page to deterministically identify section/subsection headings
        var outlineNodesOnPage: [PDFOutlineNode] = []
        func collectOutline(nodes: [PDFOutlineNode]) {
            for n in nodes {
                if n.targetPage == pageIndex {
                    outlineNodesOnPage.append(n)
                }
                collectOutline(nodes: n.children)
            }
        }
        if let outline = document?.outline {
            collectOutline(nodes: outline)
        }

        // 2. Separate body content from margin line-number gutters
        let textBlocks = stext.blocks.filter { $0.type == .text && !$0.lines.isEmpty }
        let bodyBlocks = textBlocks.filter { $0.bbox.width >= SpatialTextSelector.minColumnWidth }
        let candidateBlocks = bodyBlocks.isEmpty ? textBlocks : bodyBlocks
        let bodyLeftMargin = candidateBlocks.map { $0.bbox.minX }.min() ?? (stext.bounds.minX + SpatialTextSelector.minColumnWidth)

        var contentLines: [(line: TextLine, block: TextBlock)] = []
        for block in textBlocks {
            for line in block.lines {
                // Strictly exclude margin line numbers: numeric-only with narrow width or in the left margin gutter
                if SpatialTextSelector.isLineNumberGutter(line: line, bodyLeftMargin: bodyLeftMargin) { continue }
                if line.characters.allSatisfy({ $0.char.isNumber || $0.char.isWhitespace }) && line.bbox.width < 45 { continue }
                contentLines.append((line, block))
            }
        }

        // 3. Find the best content line closest to the click point (prioritizing vertical alignment)
        var bestCandidate: (line: TextLine, block: TextBlock)? = nil
        var bestScore: CGFloat = .infinity

        for item in contentLines {
            let line = item.line
            let dy: CGFloat
            if pagePoint.y >= line.bbox.minY - 4 && pagePoint.y <= line.bbox.maxY + 4 {
                dy = 0
            } else if pagePoint.y < line.bbox.minY {
                dy = line.bbox.minY - pagePoint.y
            } else {
                dy = pagePoint.y - line.bbox.maxY
            }

            let dx: CGFloat
            if pagePoint.x >= line.bbox.minX && pagePoint.x <= line.bbox.maxX {
                dx = 0
            } else if pagePoint.x < line.bbox.minX {
                dx = line.bbox.minX - pagePoint.x
            } else {
                dx = pagePoint.x - line.bbox.maxX
            }

            let score = (dy * 3.5) + dx
            if score < bestScore {
                bestScore = score
                bestCandidate = item
            }
        }

        if let (bestLine, bestBlock) = bestCandidate, bestScore < 250 {
            func normalizeHeading(_ str: String) -> String {
                str.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ").lowercased()
            }

            let lineNorm = normalizeHeading(bestLine.text)
            let blockNorm = normalizeHeading(bestBlock.text)

            // 4. Deterministic Heading Detection: Check if the clicked line or its block matches a document outline node
            var matchedOutlineNode: PDFOutlineNode? = nil
            for node in outlineNodesOnPage {
                let nodeNorm = normalizeHeading(node.title)
                guard !nodeNorm.isEmpty else { continue }
                if lineNorm == nodeNorm || blockNorm == nodeNorm ||
                   lineNorm.hasPrefix(nodeNorm) || nodeNorm.hasPrefix(lineNorm) ||
                   blockNorm.hasPrefix(nodeNorm) {
                    matchedOutlineNode = node
                    break
                }
            }

            if let node = matchedOutlineNode {
                let cleanHeading = node.title.trimmingCharacters(in: .whitespacesAndNewlines)
                let targetRect = (bestBlock.lines.count <= 3 && bestBlock.bbox.width >= bestLine.bbox.width) ? bestBlock.bbox : bestLine.bbox
                let targetPoint = CGPoint(x: targetRect.minX, y: targetRect.midY)
                return SnapshotTarget(
                    label: cleanHeading,
                    snippet: cleanHeading,
                    targetPage: pageIndex,
                    targetPoint: targetPoint,
                    targetRect: targetRect,
                    sourceRect: targetRect,
                    sourcePage: pageIndex,
                    uri: node.uri,
                    thumbnailData: nil
                )
            }

            // 5. Regular Body Line (not an outline heading): Extract clean words without any line numbers
            let validChars = bestLine.characters.filter { $0.char != "\n" }
            let lineCleanText = bestLine.text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")

            var startCharIdx = 0
            if pagePoint.x > bestLine.bbox.minX + 25 {
                var closestCharIdx = 0
                var closestDx: CGFloat = .infinity
                for (cIdx, char) in validChars.enumerated() {
                    let dx = abs(char.boundingRect.midX - pagePoint.x)
                    if dx < closestDx {
                        closestDx = dx
                        closestCharIdx = cIdx
                    }
                }
                while closestCharIdx > 0 && validChars[closestCharIdx - 1].char != " " {
                    closestCharIdx -= 1
                }
                startCharIdx = closestCharIdx
            }

            let remainingText = String(validChars[startCharIdx...].map { $0.char }).trimmingCharacters(in: .whitespacesAndNewlines)
            let words = remainingText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
            let candidateLabel = words.prefix(6).joined(separator: " ")
            let truncated = candidateLabel.truncatedAtWordBoundary(maxLength: 45)
            let cleanLabel = truncated.isEmpty ? (lineCleanText.isEmpty ? "Page \(pageIndex + 1)" : lineCleanText) : truncated

            let targetRect = bestLine.bbox
            let targetPoint = CGPoint(x: targetRect.minX, y: targetRect.midY)

            return SnapshotTarget(
                label: cleanLabel,
                snippet: lineCleanText,
                targetPage: pageIndex,
                targetPoint: targetPoint,
                targetRect: targetRect,
                sourceRect: targetRect,
                sourcePage: pageIndex,
                thumbnailData: nil
            )
        }

        return SnapshotTarget(
            label: "Page \(pageIndex + 1)",
            snippet: "Page \(pageIndex + 1)",
            targetPage: pageIndex,
            targetPoint: pagePoint,
            targetRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
            sourceRect: CGRect(x: max(0, pagePoint.x - 100), y: max(0, pagePoint.y - 20), width: 200, height: 40),
            sourcePage: pageIndex,
            thumbnailData: nil
        )
    }
    
    private func makeThumbnail(from image: NSImage, pageBounds: CGRect, targetRect: CGRect) -> Data? {
        guard targetRect.width > 5 && targetRect.height > 5 else { return nil }
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        
        let scaleX = CGFloat(cgImage.width) / pageBounds.width
        let scaleY = CGFloat(cgImage.height) / pageBounds.height
        
        let cropX = max(0, (targetRect.minX - pageBounds.minX) * scaleX)
        let cropY = max(0, (targetRect.minY - pageBounds.minY) * scaleY)
        let cropW = min(CGFloat(cgImage.width) - cropX, max(targetRect.width * scaleX, 20))
        let cropH = min(CGFloat(cgImage.height) - cropY, max(targetRect.height * scaleY, 20))
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        guard let cropped = cgImage.cropping(to: cropRect) else { return nil }
        
        let rep = NSBitmapImageRep(cgImage: cropped)
        return rep.representation(using: .png, properties: [:])
    }
    
    /// Opens `target` in a new, separate window (not a tab) positioned at that exact location —
    /// for keeping related sections of the same document visible side by side. Used both by
    /// saved snapshot cards and by Option-click / "Open in New Window" on cross-reference links,
    /// selections, and plain page locations. `currentWindow` (this document's own window) is
    /// passed as the source so the new window cascades near it and closes automatically if this
    /// window closes first.
    public func openSnapshotInNewWindow(_ target: SnapshotTarget) {
        guard let doc = document else { return }
        let source = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow
        SnapshotWindowManager.shared.open(url: URL(fileURLWithPath: doc.filePath), target: target, source: source)
    }

    /// Closes the snapshot window for `target`, if one is currently open. Snapshot cards use
    /// this to turn their window button into a Close action once its window is already open.
    public func closeSnapshotWindow(_ target: SnapshotTarget) {
        SnapshotWindowManager.shared.close(target.id)
    }

    /// Resolves the bounding box for a reference or snapshot target in native page coordinates,
    /// unifying spatial text line detection, margin gutter filtering, and fallbacks so that both
    /// the focus ring renderer and viewport scrolling share identical geometry.
    public func resolvedTargetRect(for snap: SnapshotTarget) -> CGRect {
        let pageIdx = snap.targetPage
        let doc = document
        let pageBounds: CGRect
        if let doc, pageIdx >= 0, pageIdx < doc.pageCount {
            pageBounds = doc.pageBounds[pageIdx]
        } else {
            pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        }

        if let rect = snap.targetRect, rect.width > 0, rect.height > 0 {
            if snap.thumbnailFileName != nil {
                // Exact user-drawn marquee area crop
                return rect
            }
            // Text selections, search hits, and point snapshots receive breathable padding matching link targets
            let padded = rect.insetBy(dx: -6, dy: -3)
            let safeLeft = pageBounds.minX + 4
            let safeRight = pageBounds.maxX - 4
            let clampedX = max(safeLeft, min(padded.minX, safeRight - 24))
            let clampedY = max(pageBounds.minY + 4, min(padded.minY, pageBounds.maxY - 20))
            let clampedW = min(padded.width, safeRight - clampedX)
            let clampedH = min(padded.height, pageBounds.maxY - clampedY)
            return CGRect(x: clampedX, y: clampedY, width: max(clampedW, 24), height: max(clampedH, 20))
        }

        guard let doc, pageIdx >= 0, pageIdx < doc.pageCount else {
            return snap.targetRect ?? CGRect(x: 54, y: 36, width: 300, height: 40)
        }

        // Ensure structured data is available for line resolution
        if pageStructuredData[pageIdx] == nil {
            pageStructuredData[pageIdx] = doc.loadStructuredPage(for: pageIdx)
        }
        let stext = pageStructuredData[pageIdx]

        let rawPoint = snap.targetPoint
        let hasValidX = (rawPoint != nil && !rawPoint!.x.isNaN)
        let hasValidY = (rawPoint != nil && !rawPoint!.y.isNaN)

        // If MuPDF returned (0, 0) or near-origin coords (e.g. for /Fit links with unspecified coordinates),
        // anchor into the top body content rather than the top-left margin gutter.
        let isOriginPoint = (hasValidX && hasValidY && rawPoint!.x <= pageBounds.minX + 10 && rawPoint!.y <= pageBounds.minY + 10)
        let bodyLeftMargin = max(pageBounds.minX + 48, stext?.blocks
            .filter { $0.type == .text && $0.bbox.width >= SpatialTextSelector.minColumnWidth }
            .map { $0.bbox.minX }.min() ?? (pageBounds.minX + SpatialTextSelector.minColumnWidth))

        let safeX = (hasValidX && !isOriginPoint) ? rawPoint!.x : bodyLeftMargin
        let safeY = (hasValidY && !isOriginPoint) ? rawPoint!.y : (pageBounds.minY + 40)
        let safePoint = CGPoint(x: safeX, y: safeY)

        var resolvedLineRect: CGRect? = nil
        if let stext,
           let line = textSelector.targetLine(on: stext, at: safePoint, label: snap.label, uri: snap.uri) {
            resolvedLineRect = line.bbox.insetBy(dx: -6, dy: -3)
        }

        if let lineRect = resolvedLineRect {
            return lineRect
        }

        if rawPoint != nil && (hasValidX || hasValidY) && !isOriginPoint {
            // Fallback geometry when structured text is unavailable or non-textual.
            let isLeftAnchored = safePoint.x <= bodyLeftMargin + 10
            let desiredWidth: CGFloat = min(360, pageBounds.width - (bodyLeftMargin - pageBounds.minX) - 36)
            let desiredHeight: CGFloat = 36

            let rx: CGFloat = isLeftAnchored ? bodyLeftMargin : (safePoint.x - desiredWidth / 2)
            let ry: CGFloat = safePoint.y - desiredHeight / 2

            let minX = bodyLeftMargin
            let maxX = pageBounds.maxX - 16
            let minY = pageBounds.minY + 16
            let maxY = pageBounds.maxY - 16

            let clampedX = max(minX, min(rx, maxX - desiredWidth))
            let clampedY = max(minY, min(ry, maxY - desiredHeight))
            let clampedW = min(desiredWidth, maxX - clampedX)
            let clampedH = min(desiredHeight, maxY - clampedY)

            return CGRect(x: clampedX, y: clampedY, width: max(clampedW, 40), height: max(clampedH, 20))
        }

        let minX = max(bodyLeftMargin, pageBounds.minX + 54)
        let width = max(min(pageBounds.width - (minX - pageBounds.minX) - 36, 400), 100)
        let minY = pageBounds.minY + 36
        return CGRect(x: minX, y: minY, width: width, height: 40)
    }


    /// Destination keys of all outline entries; a link sharing one points at a heading.
    private var outlineDestinationKeys: Set<String> {
        guard let doc = document else { return [] }
        if let cached = cachedOutlineDestinationKeys, cached.document == ObjectIdentifier(doc) {
            return cached.keys
        }
        var keys = Set<String>()
        func collect(_ nodes: [PDFOutlineNode]) {
            for node in nodes {
                if let key = LinkTargetKind.destinationKey(for: node.uri) { keys.insert(key) }
                collect(node.children)
            }
        }
        collect(doc.outline)
        cachedOutlineDestinationKeys = (ObjectIdentifier(doc), keys)
        return keys
    }

    public func linkTargetKind(for link: SnapshotTarget) -> LinkTargetKind {
        LinkTargetKind(uri: link.uri, outlineDestinationKeys: outlineDestinationKeys)
    }

    /// Page region shown by a link peek: the target line for citations and footnotes, otherwise
    /// a fixed amount of context around the destination (see LinkTargetKind.peekContext).
    public func linkPeekRect(for link: SnapshotTarget) -> CGRect {
        let anchor = resolvedTargetRect(for: link)
        guard let context = linkTargetKind(for: link).peekContext,
              let doc = document, link.targetPage >= 0, link.targetPage < doc.pageCount else {
            return anchor
        }
        let pageBounds = doc.pageBounds[link.targetPage]
        var top = anchor.minY
        if let point = link.targetPoint, point.y.isFinite, point.y > pageBounds.minY + 10 {
            top = min(top, point.y)
        }
        let bottom = min(pageBounds.maxY, top + context.below)
        top = max(pageBounds.minY, top - max(context.above, 4))

        // Widen to the text column: MuPDF text blocks in this band overlapping the anchor.
        var minX = anchor.minX
        var maxX = anchor.maxX
        for block in pageStructuredData[link.targetPage]?.blocks ?? [] where block.type == .text {
            let b = block.bbox
            guard b.maxY > top, b.minY < bottom, b.width >= SpatialTextSelector.minColumnWidth,
                  b.maxX > anchor.minX, b.minX < anchor.maxX else { continue }
            minX = min(minX, b.minX)
            maxX = max(maxX, b.maxX)
        }
        minX = max(pageBounds.minX, minX - 6)
        maxX = min(pageBounds.maxX, maxX + 6)
        return CGRect(x: minX, y: top, width: maxX - minX, height: bottom - top)
    }

    /// Renders a page region at the current zoom, sized to match the canvas.
    public func renderRegionAtCurrentZoom(pageIndex: Int, rect: CGRect) async -> NSImage? {
        await renderRegion(pageIndex: pageIndex, rect: rect, zoom: effectiveZoom)
    }

    /// Renders a page region at `zoom`, e.g. another tab's zoom for a peek shown over it.
    public func renderRegion(pageIndex: Int, rect: CGRect, zoom: CGFloat) async -> NSImage? {
        guard isRenderActorReady, let doc = document, pageIndex >= 0, pageIndex < doc.pageCount,
              rect.width > 0, rect.height > 0 else { return nil }
        let backingScale = (currentWindow ?? NSApplication.shared.keyWindow)?.backingScaleFactor ?? 2.0
        guard let image = try? await renderActor.renderPageRect(pageIndex: pageIndex, rect: rect, scale: max(zoom * backingScale, 1.5)) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: rect.width * zoom, height: rect.height * zoom))
    }

    public func jumpToSnapshot(_ snap: SnapshotTarget) {
        loadPageMetadata(snap.targetPage)
        self.selectedSnapshotId = snap.id
        self.activeSnapshotTarget = snap
        self.snapshotJumpToken &+= 1
        self.currentPageIndex = snap.targetPage
        pruneCaches(around: snap.targetPage)
        
        Task {
            await renderPage(snap.targetPage)
            await MainActor.run {
                self.activeScrollTargetId = "snap_\(snap.id.uuidString)"
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if self.activeSnapshotTarget?.id == snap.id {
                withAnimation(.easeOut(duration: 0.5)) {
                    self.activeSnapshotTarget = nil
                }
            }
        }
    }

    /// Adds an anchor for the current page location (or active selection if text is selected),
    /// switching the sidebar tab to Anchors to provide immediate visual feedback.
    public func addAnchorForCurrentPage() {
        if let target = buildSnapshotTargetFromSelection() {
            addSnapshotTarget(target)
            NotificationCenter.default.post(name: .focusAnchorsCommand, object: nil)
            return
        }
        guard let doc = document, doc.pageCount > 0 else { return }
        let p = currentPageIndex
        let bounds = doc.pageBounds[p]
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let target = buildSnapshotTarget(at: center, pageIndex: p)
        addSnapshotTarget(target)
        NotificationCenter.default.post(name: .focusAnchorsCommand, object: nil)
    }

    public func addSnapshotTarget(_ target: SnapshotTarget) {
        let isDuplicate = activeSnapshots.contains { existing in
            if existing.id == target.id { return true }
            if existing.targetPage == target.targetPage && !target.snippet.isEmpty && existing.snippet == target.snippet {
                return true
            }
            return false
        }
        guard !isDuplicate else { return }
        activeSnapshots.append(target)
        selectedSnapshotId = target.id
        saveReadingStateIfNeeded()
        if PDFViewerAppCoordinator.shared.activeViewModel === self || PDFViewerViewModel.active === self {
            PDFViewerAppCoordinator.shared.activeAnchors = activeSnapshots
        }
    }

    public func removeSnapshotTarget(_ target: SnapshotTarget) {
        if selectedSnapshotId == target.id {
            selectedSnapshotId = nil
        }
        activeSnapshots.removeAll(where: { $0.id == target.id })
        target.deleteThumbnailFile()
        saveReadingStateIfNeeded()
        if PDFViewerAppCoordinator.shared.activeViewModel === self || PDFViewerViewModel.active === self {
            PDFViewerAppCoordinator.shared.activeAnchors = activeSnapshots
        }
    }

    public func clearAllSnapshots() {
        selectedSnapshotId = nil
        for target in activeSnapshots {
            target.deleteThumbnailFile()
        }
        activeSnapshots.removeAll()
        saveReadingStateIfNeeded()
        if PDFViewerAppCoordinator.shared.activeViewModel === self || PDFViewerViewModel.active === self {
            PDFViewerAppCoordinator.shared.activeAnchors = activeSnapshots
        }
    }
}
