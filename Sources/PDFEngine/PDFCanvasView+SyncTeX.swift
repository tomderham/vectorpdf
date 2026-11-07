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

/// SyncTeX on the canvas: ⇧⌘-click and Show in Editor (backward search), and the highlight a
/// forward search leaves on the line it found.
extension PDFCanvasView {
    /// How long a SyncTeX highlight shows fully, then how long it takes to fade.
    static let syncTeXHighlightHold: TimeInterval = 1.2
    static let syncTeXHighlightFade: TimeInterval = 0.6

    /// The highlight's opacity `elapsed` seconds after it appeared: 1, then fading to 0.
    static func syncTeXHighlightOpacity(at elapsed: TimeInterval) -> CGFloat {
        guard elapsed > syncTeXHighlightHold else { return 1 }
        return CGFloat(max(0, 1 - (elapsed - syncTeXHighlightHold) / syncTeXHighlightFade))
    }

    /// Highlights the line a SyncTeX forward search found, then fades it out.
    func showSyncTeXReveal(_ reveal: SyncTeXReveal) {
        syncTeXHighlight = (reveal.pageIndex, reveal.rects, Date())
        syncTeXHighlightTimer?.invalidate()
        needsDisplay = true
        let timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.advanceSyncTeXHighlight()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTeXHighlightTimer = timer
    }

    private func advanceSyncTeXHighlight() {
        guard let highlight = syncTeXHighlight else {
            syncTeXHighlightTimer?.invalidate()
            syncTeXHighlightTimer = nil
            return
        }
        let elapsed = Date().timeIntervalSince(highlight.shownAt)
        if elapsed > Self.syncTeXHighlightHold + Self.syncTeXHighlightFade {
            syncTeXHighlight = nil
            syncTeXHighlightTimer?.invalidate()
            syncTeXHighlightTimer = nil
            needsDisplay = true
        } else if elapsed > Self.syncTeXHighlightHold {
            needsDisplay = true
        }
    }

    /// Whether `event` is a SyncTeX backward-search click: ⇧⌘ and nothing else but Caps Lock.
    static func isSyncTeXClick(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection([.command, .shift, .option, .control]) == [.command, .shift]
    }

    /// Acts on a ⇧⌘-click on a document with SyncTeX data, opening the source line under it in
    /// the editor. Returns whether it did (the click is then used up).
    func handleSyncTeXClick(_ event: NSEvent, at canvasPoint: CGPoint) -> Bool {
        guard Self.isSyncTeXClick(event), viewModel.refreshSyncTeXAvailability(),
              let (pageIndex, _, pagePoint) = pageInfo(at: canvasPoint) else { return false }
        viewModel.showInEditor(pageIndex: pageIndex, pagePoint: pagePoint)
        return true
    }

    /// "Show in Editor" for the context menu at `canvasPoint`, when the document has SyncTeX data.
    func makeShowInEditorItem(at canvasPoint: CGPoint) -> NSMenuItem? {
        guard !viewModel.isTransientWindow, viewModel.refreshSyncTeXAvailability(),
              let (pageIndex, _, pagePoint) = pageInfo(at: canvasPoint) else { return nil }
        let item = NSMenuItem(title: "Show in Editor", action: #selector(showInEditorAction(_:)), keyEquivalent: "")
        item.image = NSImage(systemSymbolName: "chevron.left.forwardslash.chevron.right", accessibilityDescription: nil)
        item.target = self
        item.representedObject = SyncTeXClickTarget(pageIndex: pageIndex, pagePoint: pagePoint)
        return item
    }

    @objc func showInEditorAction(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? SyncTeXClickTarget else { return }
        viewModel.showInEditor(pageIndex: target.pageIndex, pagePoint: target.pagePoint)
    }
}

/// Where Show in Editor was asked for.
final class SyncTeXClickTarget: NSObject {
    let pageIndex: Int
    let pagePoint: CGPoint

    init(pageIndex: Int, pagePoint: CGPoint) {
        self.pageIndex = pageIndex
        self.pagePoint = pagePoint
    }
}
