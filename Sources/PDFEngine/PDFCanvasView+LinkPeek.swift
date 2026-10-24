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
import Combine
import CoreGraphics
import MuPDFBridge

extension PDFCanvasView {
    // MARK: - Link Peek

    /// Watches Command and anything that cancels a peek. A monitor, since the canvas isn't
    /// always first responder and menu shortcuts never reach keyDown.
    func installLinkPeekEventMonitor() {
        guard linkPeekEventMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .scrollWheel, .leftMouseDown, .rightMouseDown, .otherMouseDown, .magnify]
        linkPeekEventMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            if event.type == .flagsChanged {
                self.isLinkPeekSuppressed = false
                self.updateLinkPeek(modifierFlags: event.modifierFlags)
            } else if self.linkPeek.targetId != nil {
                self.linkPeek.dismiss()
                self.isLinkPeekSuppressed = true
            }
            return event
        }
    }

    /// Peeks while Command alone is held over an internal link.
    func updateLinkPeek(modifierFlags: NSEvent.ModifierFlags) {
        let commandOnly = modifierFlags.intersection([.command, .option, .shift, .control]) == .command
        guard commandOnly, !isLinkPeekSuppressed, pendingLinkTarget == nil, let window, window.isKeyWindow,
              allowsLinkPeek else {
            linkPeek.dismiss()
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard visibleRect.contains(point) else {
            linkPeek.dismiss()
            return
        }
        if let link = internalLinkInfo(at: point) {
            linkPeek.request(link, parent: window) { [weak self] in await self?.linkPeekContent(for: $0) }
        } else if let link = webLinkInfo(at: point), link.id == linkPeek.targetId || crossDocLinkTarget(for: link) != nil {
            linkPeek.request(link, parent: window) { [weak self] in await self?.crossDocLinkPeekContent(for: $0) }
        } else {
            linkPeek.dismiss()
        }
    }

    /// Force Click peeks immediately; releasing the click ends it.
    public override func pressureChange(with event: NSEvent) {
        super.pressureChange(with: event)
        guard event.stage == 2, let pending = pendingLinkTarget, !pending.didPeek,
              allowsLinkPeek, let window else { return }
        if pending.target.targetPage >= 0 {
            pendingLinkTarget?.didPeek = true
            linkPeek.request(pending.target, immediate: true, parent: window) { [weak self] in await self?.linkPeekContent(for: $0) }
        } else if crossDocLinkTarget(for: pending.target) != nil {
            // A web link into a document open in another tab: preview it there instead of
            // following the link on release.
            pendingLinkTarget?.didPeek = true
            linkPeek.request(pending.target, immediate: true, parent: window) { [weak self] in await self?.crossDocLinkPeekContent(for: $0) }
        }
    }

    /// Wherever links are clickable: not while drawing or measuring.
    private var allowsLinkPeek: Bool {
        guard viewModel.isInteractiveViewingMode else { return false }
        switch viewModel.canvasMode {
        case .select, .text, .callout, .redact: return true
        default: return false
        }
    }

    private func linkPeekContent(for link: SnapshotTarget) async -> LinkPeekContent? {
        guard let sourceRect = link.sourceRect, screenRect(forPageRect: sourceRect, pageIndex: link.sourcePage) != nil else { return nil }
        let targetRect = viewModel.linkPeekRect(for: link)
        guard let rendered = await viewModel.renderRegionAtCurrentZoom(pageIndex: link.targetPage, rect: targetRect) else {
            return nil
        }
        // Recomputed after rendering, in case the canvas scrolled meanwhile.
        guard let screenRect = screenRect(forPageRect: sourceRect, pageIndex: link.sourcePage) else { return nil }
        return LinkPeekContent(image: appearanceAdjusted(rendered), linkScreenRect: screenRect)
    }

    /// The web link under `canvasPoint`, if any.
    private func webLinkInfo(at canvasPoint: CGPoint) -> SnapshotTarget? {
        guard let (pageIdx, _, pagePoint) = pageInfo(at: canvasPoint),
              let link = viewModel.pageLinks[pageIdx]?.first(where: { $0.sourceRect?.contains(pagePoint) == true }),
              link.targetPage < 0, link.uri != nil else { return nil }
        return link
    }

    /// The tab and target a web link leads to when its document is open in this window's tab group.
    private func crossDocLinkTarget(for link: SnapshotTarget) -> (viewModel: PDFViewerViewModel, target: SnapshotTarget)? {
        CrossDocLinkResolver.target(for: link, in: otherTabViewModels)
    }

    /// Peek of a web link's target from the other tab that has its document open, rendered at
    /// this canvas's zoom and captioned with that document's name.
    private func crossDocLinkPeekContent(for link: SnapshotTarget) async -> LinkPeekContent? {
        guard let sourceRect = link.sourceRect, screenRect(forPageRect: sourceRect, pageIndex: link.sourcePage) != nil,
              let (other, target) = crossDocLinkTarget(for: link) else { return nil }
        // The peek widens to the target's text column, which needs that page's text.
        other.loadPageMetadata(target.targetPage)
        let targetRect = other.linkPeekRect(for: target)
        guard let rendered = await other.renderRegion(pageIndex: target.targetPage, rect: targetRect, zoom: viewModel.effectiveZoom),
              let screenRect = screenRect(forPageRect: sourceRect, pageIndex: link.sourcePage) else { return nil }
        return LinkPeekContent(
            image: appearanceAdjusted(rendered),
            linkScreenRect: screenRect,
            caption: (other.documentTitle as NSString).deletingPathExtension,
            truncationHint: ""
        )
    }

    /// `image` recoloured for the active reading theme, as the canvas draws pages.
    private func appearanceAdjusted(_ image: NSImage) -> NSImage {
        let appearance = activeColorAppearance
        return appearance == .light ? image : (Self.transformedImage(from: image, appearance: appearance) ?? image)
    }

    /// Screen rect of a page-space rect on `pageIndex`, or nil when that page isn't laid out.
    private func screenRect(forPageRect rect: CGRect, pageIndex: Int) -> NSRect? {
        guard let window, let doc = viewModel.document, pageIndex >= 0, pageIndex < doc.pageCount,
              let pFrame = pageFrame(for: pageIndex) else { return nil }
        let pBounds = doc.pageBounds[pageIndex]
        let zoom = viewModel.effectiveZoom
        let canvasRect = NSRect(
            x: pFrame.minX + (rect.minX - pBounds.minX) * zoom,
            y: pFrame.minY + (rect.minY - pBounds.minY) * zoom,
            width: rect.width * zoom,
            height: rect.height * zoom
        )
        return window.convertToScreen(convert(canvasRect, to: nil))
    }

    /// Builds a target for a canvas point with no link or selection under
    /// it — extracting the surrounding words/sentence text if near text, or a page target if in margin.
    func pointTarget(at canvasPoint: CGPoint) -> SnapshotTarget? {
        guard let (pageIdx, _, pagePoint) = pageInfo(at: canvasPoint) else { return nil }
        return viewModel.buildSnapshotTarget(at: pagePoint, pageIndex: pageIdx)
    }

    // MARK: - Cross-Document References

    /// What a reference menu item acts on: the reference, its page, and (for "Go to") the outline
    /// candidates already found.
    private final class ReferenceMenuPayload: NSObject {
        let reference: ParsedReference
        let pageIndex: Int
        let candidates: [ReferenceCandidate]
        init(reference: ParsedReference, pageIndex: Int, candidates: [ReferenceCandidate]) {
            self.reference = reference
            self.pageIndex = pageIndex
            self.candidates = candidates
        }
    }

    /// Other loaded documents in this window's tab group.
    private var otherTabViewModels: [PDFViewerViewModel] {
        guard !viewModel.isTransientWindow else { return [] }
        return PDFViewerAppCoordinator.shared.tabGroupViewModels(of: viewModel)
            .filter { $0 !== viewModel && $0.document != nil }
    }

    /// An unlinked reference ("Section 4.2", "Appendix C") in the text under a canvas point.
    func crossDocReference(at canvasPoint: CGPoint) -> (ParsedReference, Int)? {
        guard let (pageIndex, _, pagePoint) = pageInfo(at: canvasPoint),
              let page = viewModel.pageStructuredData[pageIndex] ?? viewModel.document?.loadStructuredPage(for: pageIndex),
              let reference = ReferenceExtractor.reference(at: pagePoint, on: page),
              !isInternallyLinked(reference, pageIndex: pageIndex) else { return nil }
        return (reference, pageIndex)
    }

    /// True when the reference's text is (part of) a link within this document. A click just
    /// beside such a link misses it, but still finds its text as a reference, which points here
    /// rather than to another tab.
    private func isInternallyLinked(_ reference: ParsedReference, pageIndex: Int) -> Bool {
        guard let rect = reference.sourceRect?.insetBy(dx: 1, dy: 1), let links = viewModel.pageLinks[pageIndex] else { return false }
        return links.contains { $0.targetPage >= 0 && $0.sourceRect?.intersects(rect) == true }
    }

    /// Adds "Go to …" (when an outline heading in another tab is a confident match) and "Find …
    /// in Other Tabs" at the top of `menu`; or, for a reference to a heading of this document,
    /// just "Go to …" that heading. Nothing when this window has no other tabs.
    func insertCrossDocReferenceItems(into menu: NSMenu, reference: ParsedReference, pageIndex: Int) {
        let others = otherTabViewModels
        guard !others.isEmpty else { return }
        var items: [NSMenuItem] = []

        if let own = CrossDocReferenceFinder.sameDocumentTarget(for: reference, in: viewModel, others: others) {
            // Searching other tabs would only find nothing, slowly.
            if let best = own.first, !isReferenceSource(reference, at: best.target, pageIndex: pageIndex) {
                items += goToReferenceItems(ReferenceMenuPayload(reference: reference, pageIndex: pageIndex, candidates: own), inDocument: nil)
            }
            insert(items, into: menu)
            return
        }

        let outline = CrossDocReferenceFinder.outlineCandidates(for: reference, in: others)
        if CrossDocReferenceFinder.isConfident(outline), let best = outline.first {
            // The same heading in several tabs: the preview lists each.
            let tabs = Set(outline.filter { $0.score == best.score }.map { ObjectIdentifier($0.viewModel) }).count
            let place = tabs > 1 ? "\(tabs) Tabs" : (best.documentTitle as NSString).deletingPathExtension
            items += goToReferenceItems(ReferenceMenuPayload(reference: reference, pageIndex: pageIndex, candidates: outline), inDocument: place)
        }

        let quoted = reference.quotedTitle != nil ? reference.displayText : "“\(reference.displayText)”"
        let findItem = NSMenuItem(title: "Find \(quoted) in Other Tabs", action: #selector(findReferenceAction(_:)), keyEquivalent: "")
        findItem.image = NSImage(systemSymbolName: "doc.text.magnifyingglass", accessibilityDescription: nil)
        findItem.representedObject = ReferenceMenuPayload(reference: reference, pageIndex: pageIndex, candidates: [])
        items.append(findItem)
        insert(items, into: menu)
    }

    /// "Go to" the best candidate (previewing it first), with a ⌘ alternate that jumps straight
    /// there. `inDocument` names the tab, when it isn't this one.
    private func goToReferenceItems(_ payload: ReferenceMenuPayload, inDocument documentTitle: String?) -> [NSMenuItem] {
        guard let best = payload.candidates.first else { return [] }
        let heading = Self.menuTruncated(best.heading)
        let suffix = documentTitle.map { " in \($0)" } ?? ""
        let goItem = NSMenuItem(title: "Go to “\(heading)”\(suffix)", action: #selector(peekReferenceAction(_:)), keyEquivalent: "")
        goItem.image = NSImage(systemSymbolName: "arrow.turn.down.right", accessibilityDescription: nil)
        goItem.keyEquivalentModifierMask = []
        goItem.representedObject = payload

        // Hold ⌘ to skip the preview and go straight there.
        let openItem = NSMenuItem(title: documentTitle == nil ? "Jump to “\(heading)”" : "Open “\(heading)”\(suffix)",
                                  action: #selector(openReferenceAction(_:)), keyEquivalent: "")
        openItem.image = goItem.image
        openItem.keyEquivalentModifierMask = .command
        openItem.isAlternate = true
        openItem.representedObject = payload
        return [goItem, openItem]
    }

    /// True when `target` is the reference itself, e.g. right-clicking the heading it names.
    private func isReferenceSource(_ reference: ParsedReference, at target: SnapshotTarget, pageIndex: Int) -> Bool {
        guard target.targetPage == pageIndex, let rect = reference.sourceRect else { return false }
        guard let point = target.targetPoint else { return true }
        return abs(point.y - rect.minY) < 30
    }

    private func insert(_ items: [NSMenuItem], into menu: NSMenu) {
        guard !items.isEmpty else { return }
        for (i, item) in items.enumerated() {
            item.target = self
            menu.insertItem(item, at: i)
        }
        menu.insertItem(.separator(), at: items.count)
    }

    private static func menuTruncated(_ s: String, limit: Int = 40) -> String {
        s.count <= limit ? s : String(s.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Where the reference sits on screen, for positioning its peek; falls back to the click.
    private func referenceAnchorRect(_ payload: ReferenceMenuPayload) -> NSRect? {
        if let rect = payload.reference.sourceRect, let screen = screenRect(forPageRect: rect, pageIndex: payload.pageIndex) {
            return screen
        }
        guard let window else { return nil }
        let point = convert(lastContextMenuLocation, to: nil)
        return window.convertToScreen(NSRect(x: point.x - 1, y: point.y - 8, width: 2, height: 16))
    }

    private func showReferencePeek(_ candidates: [ReferenceCandidate], anchor: NSRect) {
        guard let window else { return }
        referencePeek.show(candidates, anchor: anchor, parent: window, render: { [weak self] candidate in
            let vm = candidate.viewModel
            let rect = vm.linkPeekRect(for: candidate.target)
            guard let image = await vm.renderRegionAtCurrentZoom(pageIndex: candidate.target.targetPage, rect: rect) else { return nil }
            return self?.appearanceAdjusted(image) ?? image
        }, onOpen: { candidate in
            PDFViewerAppCoordinator.shared.activate(candidate.viewModel, jumpingTo: candidate.target)
        })
    }

    @objc private func peekReferenceAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ReferenceMenuPayload,
              let anchor = referenceAnchorRect(payload) else { return }
        showReferencePeek(payload.candidates, anchor: anchor)
    }

    @objc private func openReferenceAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ReferenceMenuPayload, let best = payload.candidates.first else { return }
        PDFViewerAppCoordinator.shared.activate(best.viewModel, jumpingTo: best.target)
    }

    @objc private func findReferenceAction(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? ReferenceMenuPayload, let window,
              let anchor = referenceAnchorRect(payload) else { return }
        let reference = payload.reference
        let others = otherTabViewModels
        referenceSearchTask?.cancel()
        // Outline matches are instant; only a full-text search needs the spinner.
        let outline = CrossDocReferenceFinder.outlineCandidates(for: reference, in: others)
        if !outline.isEmpty {
            showReferencePeek(outline, anchor: anchor)
            return
        }
        referencePeek.showMessage("Searching other tabs for \(reference.displayText)…", spinning: true, anchor: anchor, parent: window)
        referenceSearchTask = Task { @MainActor [weak self] in
            let candidates = await CrossDocReferenceFinder.candidates(for: reference, in: others)
            guard !Task.isCancelled, let self, self.referencePeek.isShowing else { return }
            // The canvas may have scrolled while searching.
            let anchor = self.referenceAnchorRect(payload) ?? anchor
            if candidates.isEmpty {
                self.referencePeek.showMessage("No match for \(reference.displayText) in other tabs", spinning: false,
                                               anchor: anchor, parent: window, autoDismissAfter: .seconds(2.5))
            } else {
                self.showReferencePeek(candidates, anchor: anchor)
            }
        }
    }

    func makeOpenInNewWindowItem(target: SnapshotTarget) -> NSMenuItem {
        let item = NSMenuItem(title: "Open in New Window", action: #selector(openTargetInNewWindowAction(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
        item.target = self
        item.representedObject = target
        return item
    }
}
