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
import Synchronization
import SwiftUI

extension PDFViewerViewModel {
    public enum OutlineMove { case up, down, indent, outdent }

    public var canEditOutline: Bool { document?.isPDF == true && !isReadOnlyDocument }

    /// Where a new entry goes to, and the title it's offered: the selected text, if any, where it
    /// starts; otherwise the top of the page being read.
    func newOutlineEntryTarget() -> (title: String, page: Int, y: CGFloat) {
        if let sel = activeSelection {
            let text = activeSelectionCombinedText
            let firstLine = text.components(separatedBy: .newlines).first ?? text
            let title = firstLine.split(whereSeparator: \.isWhitespace).joined(separator: " ").truncatedAtWordBoundary(maxLength: 80)
            let top = sel.result.highlightQuads.mergedLineQuads().first?.boundingRect.minY ?? sel.result.boundingRect.minY
            if !title.isEmpty { return (title, sel.pageIndex, max(0, top - 4)) }
        }
        let page = currentPageIndex
        return ("Page \(document?.displayLabel(forPage: page) ?? "\(page + 1)")", page, 0)
    }

    /// Adds an entry for the selection or the page being read: after `node`, or inside it at the
    /// end with `asChild`; with no node, among the top entries in page order. Asks for its title.
    public func promptToAddOutlineEntry(near node: PDFOutlineNode? = nil, asChild: Bool = false) {
        guard canEditOutline else { return }
        let target = newOutlineEntryTarget()
        let title: String
        if Self.isRunningTests {
            title = target.title
        } else {
            guard let typed = promptForOutlineTitle(
                message: asChild ? "Add Entry Inside “\(node?.title ?? "")”" : "Add Outline Entry",
                info: "The entry goes to \(target.y > 0 ? "the selected text on " : "")page \(document?.displayLabel(forPage: target.page) ?? "\(target.page + 1)").",
                initial: target.title, button: "Add"
            ) else { return }
            title = typed
        }
        addOutlineEntry(title: title, page: target.page, y: target.y, near: node, asChild: asChild)
    }

    func addOutlineEntry(title: String, page: Int, y: CGFloat, near node: PDFOutlineNode?, asChild: Bool) {
        guard let doc = document else { return }
        let path: OutlinePath
        if let node, let at = doc.outline.path(of: node.id) {
            // The entry as the outline has it: `node` may come from a filtered outline, without
            // all of its children.
            let children = doc.outline.node(at: at)?.children.count ?? node.children.count
            path = asChild ? at + [children] : Array(at.dropLast()) + [at.last! + 1]
        } else {
            path = [doc.outline.firstIndex { ($0.targetPage ?? -1) > page } ?? doc.outline.count]
        }
        editOutline("Add Outline Entry") { try doc.addOutlineEntry(title: title, page: page, y: y, at: path) }
    }

    public func promptToRenameOutlineEntry(_ node: PDFOutlineNode) {
        guard canEditOutline, !Self.isRunningTests,
              let title = promptForOutlineTitle(message: "Rename Outline Entry", info: nil, initial: node.title, button: "Rename") else { return }
        renameOutlineEntry(node, to: title)
    }

    func renameOutlineEntry(_ node: PDFOutlineNode, to title: String) {
        guard let doc = document, let path = doc.outline.path(of: node.id), title != node.title else { return }
        editOutline("Rename Outline Entry") { try doc.renameOutlineEntry(at: path, to: title) }
    }

    /// Points the entry at the selection, or the top of the page being read.
    public func setOutlineEntryToCurrentPlace(_ node: PDFOutlineNode) {
        guard canEditOutline, let doc = document, let path = doc.outline.path(of: node.id) else { return }
        let target = newOutlineEntryTarget()
        editOutline("Change Outline Entry") { try doc.setOutlineEntryDestination(at: path, page: target.page, y: target.y) }
    }

    public func deleteOutlineEntry(_ node: PDFOutlineNode) {
        guard canEditOutline, let doc = document, let path = doc.outline.path(of: node.id) else { return }
        editOutline("Delete Outline Entry") { try doc.deleteOutlineEntry(at: path) }
    }

    /// Where `move` would put the entry at `path` (a place in the outline as it is), if it can go.
    func outlineDestination(for move: OutlineMove, from path: OutlinePath) -> OutlinePath? {
        guard let doc = document, let index = path.last else { return nil }
        let parent = OutlinePath(path.dropLast())
        let siblings = doc.outline.siblingCount(at: path)
        switch move {
        case .up: return index > 0 ? parent + [index - 1] : nil
        case .down: return index < siblings - 1 ? parent + [index + 2] : nil
        case .indent:
            // Into the entry above it, after its last.
            guard index > 0, let above = doc.outline.node(at: parent + [index - 1]) else { return nil }
            return parent + [index - 1, above.children.count]
        case .outdent:
            // Out of its parent, just after it.
            guard let parentIndex = parent.last else { return nil }
            return OutlinePath(parent.dropLast()) + [parentIndex + 1]
        }
    }

    public func canMoveOutlineEntry(_ node: PDFOutlineNode, _ move: OutlineMove) -> Bool {
        guard canEditOutline, let path = document?.outline.path(of: node.id) else { return false }
        return outlineDestination(for: move, from: path) != nil
    }

    public func moveOutlineEntry(_ node: PDFOutlineNode, _ move: OutlineMove) {
        guard canEditOutline, let doc = document, let path = doc.outline.path(of: node.id),
              let destination = outlineDestination(for: move, from: path) else { return }
        let name: String
        switch move {
        case .up, .down: name = "Move Outline Entry"
        case .indent: name = "Indent Outline Entry"
        case .outdent: name = "Outdent Outline Entry"
        }
        editOutline(name) { try doc.moveOutlineEntry(from: path, to: destination) }
    }

    /// Moves an entry to a place in the outline as it is: for dragging.
    public func moveOutlineEntry(_ node: PDFOutlineNode, to destination: OutlinePath) {
        guard canEditOutline, let doc = document, let path = doc.outline.path(of: node.id) else { return }
        editOutline("Move Outline Entry") { try doc.moveOutlineEntry(from: path, to: destination) }
    }

    /// Makes an edit, and registers the edit that undoes it under `name`.
    private func editOutline(_ name: String, _ edit: () throws -> OutlineEdit?) {
        flushPendingFormEdits()
        let inverse: OutlineEdit?
        do {
            inverse = try edit()
        } catch {
            showErrorAlert(title: "Couldn't Change the Outline", message: error.localizedDescription)
            return
        }
        guard let inverse else { return }
        registerOutlineUndo(inverse, name: name)
        outlineEdited()
    }

    /// Undoes or redoes an outline edit, registering its reverse in turn.
    private func applyOutlineUndo(_ edit: OutlineEdit, name: String) {
        guard let doc = document else { return }
        do {
            registerOutlineUndo(try doc.applyOutlineEdit(edit), name: name)
        } catch {
            showErrorAlert(title: "Couldn't Change the Outline", message: error.localizedDescription)
            return
        }
        outlineEdited()
    }

    private func registerOutlineUndo(_ edit: OutlineEdit, name: String) {
        undoManager.registerUndo(withTarget: self) { $0.applyOutlineUndo(edit, name: name) }
        undoManager.setActionName(name)
    }

    private func outlineEdited() {
        outlineRevision &+= 1
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
    }

    /// Finds the document's headings (see `HeadingOutline`) and shows them in a sheet, where
    /// they can be checked before they replace the outline (`applyHeadingOutline`). Shows
    /// progress for a long document. Under tests, the headings found are used as they are.
    public func buildOutlineFromHeadings() async {
        guard canEditOutline, let doc = document else { return }
        flushPendingFormEdits()

        let progress = RecognitionProgress(total: doc.pageCount)
        let cancelled = CancelFlag()
        var sheet: NSWindow?
        if !Self.isRunningTests, doc.pageCount > 40, let window = currentWindow, window.attachedSheet == nil {
            let panel = NSPanel(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
            panel.contentView = NSHostingView(rootView: RecognitionProgressView(progress: progress, title: "Finding headings…"))
            panel.setContentSize(panel.contentView?.fittingSize ?? NSSize(width: 380, height: 100))
            window.beginSheet(panel, completionHandler: nil)
            sheet = panel
        }
        let found = await Task.detached(priority: .userInitiated) {
            doc.findHeadings(progress: { pages in
                DispatchQueue.main.async {
                    progress.done = pages
                    if progress.isCancelled { cancelled.cancel() }
                }
            }, isCancelled: { cancelled.isCancelled })
        }.value
        if let sheet { sheet.sheetParent?.endSheet(sheet) }
        guard let found, document === doc else { return }

        guard found.count >= 2 else {
            if !Self.isRunningTests {
                let alert = NSAlert()
                alert.messageText = "No Headings Found"
                alert.informativeText = "VectorPDF couldn't tell this document's headings from the rest of its text. You can add entries one at a time with Edit > Add Outline Entry."
                alert.runModal()
            }
            return
        }
        if Self.isRunningTests {
            applyHeadingOutline(found)
        } else {
            headingOutlineProposal = HeadingOutlineProposal(headings: found, replacesOutline: !doc.outline.isEmpty)
        }
    }

    /// Replaces the outline with one of `headings`, as one step for Undo.
    public func applyHeadingOutline(_ headings: [FoundHeading]) {
        headingOutlineProposal = nil
        guard canEditOutline, let doc = document, !headings.isEmpty else { return }
        let undo: [OutlineEdit]
        do {
            undo = try doc.replaceOutline(with: headings)
        } catch {
            showErrorAlert(title: "Couldn't Change the Outline", message: error.localizedDescription)
            return
        }
        let name = "Build Outline from Headings"
        undoManager.beginUndoGrouping()
        // Undo runs the last registered first; these are to be made in order.
        for edit in undo.reversed() {
            undoManager.registerUndo(withTarget: self) { $0.applyOutlineUndo(edit, name: name) }
        }
        undoManager.setActionName(name)
        undoManager.endUndoGrouping()
        outlineEdited()
    }

    private func promptForOutlineTitle(message: String, info: String?, initial: String, button: String) -> String? {
        let alert = NSAlert()
        alert.messageText = message
        if let info { alert.informativeText = info }
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = initial
        field.placeholderString = "Title"
        alert.accessoryView = field
        alert.addButton(withTitle: button)
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? nil : title
    }
}

/// Stops a background task when set from the main thread.
private final class CancelFlag: Sendable {
    private let flag = Atomic<Bool>(false)
    var isCancelled: Bool { flag.load(ordering: .relaxed) }
    func cancel() { flag.store(true, ordering: .relaxed) }
}

/// The headings found for an outline, shown to be checked before they're used.
public struct HeadingOutlineProposal: Identifiable {
    public let id = UUID()
    public let headings: [FoundHeading]
    /// Whether the document has an outline they'd replace.
    public let replacesOutline: Bool
}
