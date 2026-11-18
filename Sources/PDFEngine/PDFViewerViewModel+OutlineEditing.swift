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
            path = asChild ? at + [node.children.count] : Array(at.dropLast()) + [at.last! + 1]
        } else {
            path = [doc.outline.firstIndex { ($0.targetPage ?? -1) > page } ?? doc.outline.count]
        }
        editOutline { try doc.addOutlineEntry(title: title, page: page, y: y, at: path) }
    }

    public func promptToRenameOutlineEntry(_ node: PDFOutlineNode) {
        guard canEditOutline, !Self.isRunningTests,
              let title = promptForOutlineTitle(message: "Rename Outline Entry", info: nil, initial: node.title, button: "Rename") else { return }
        renameOutlineEntry(node, to: title)
    }

    func renameOutlineEntry(_ node: PDFOutlineNode, to title: String) {
        guard let doc = document, let path = doc.outline.path(of: node.id), title != node.title else { return }
        editOutline { try doc.renameOutlineEntry(at: path, to: title) }
    }

    /// Points the entry at the selection, or the top of the page being read.
    public func setOutlineEntryToCurrentPlace(_ node: PDFOutlineNode) {
        guard canEditOutline, let doc = document, let path = doc.outline.path(of: node.id) else { return }
        let target = newOutlineEntryTarget()
        editOutline { try doc.setOutlineEntryDestination(at: path, page: target.page, y: target.y) }
    }

    public func deleteOutlineEntry(_ node: PDFOutlineNode) {
        guard canEditOutline, let doc = document, let path = doc.outline.path(of: node.id) else { return }
        editOutline { try doc.deleteOutlineEntry(at: path) }
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
        editOutline { try doc.moveOutlineEntry(from: path, to: destination) }
    }

    /// Moves an entry to a place in the outline as it is: for dragging.
    public func moveOutlineEntry(_ node: PDFOutlineNode, to destination: OutlinePath) {
        guard canEditOutline, let doc = document, let path = doc.outline.path(of: node.id) else { return }
        editOutline { try doc.moveOutlineEntry(from: path, to: destination) }
    }

    private func editOutline(_ edit: () throws -> Void) {
        flushPendingFormEdits()
        do {
            try edit()
        } catch {
            showErrorAlert(title: "Couldn't Change the Outline", message: error.localizedDescription)
            return
        }
        outlineRevision &+= 1
        isDocumentEdited = true
        currentWindow?.isDocumentEdited = true
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
