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
    /// The single decision point for every *explicit* "open this document" action (File > Open,
    /// the toolbar Open button, clicking a Favorite): load directly into this window/tab if it's
    /// still empty, otherwise always open a genuinely separate window — never a tab — so all of
    /// these actions behave identically regardless of which one you used. Drag-and-drop is the
    /// one exception, handled separately via onOpenNewTab (see its doc comment).
    public func openDocumentPreferringNewWindow(atPath path: String) {
        Task { @MainActor in
            if self.document == nil && !self.isLoadingDocument {
                await self.loadDocument(from: path)
            } else if let onOpenNewWindow = self.onOpenNewWindow {
                onOpenNewWindow(URL(fileURLWithPath: path))
            } else {
                await self.loadDocument(from: path)
            }
        }
    }

    /// Opens `path` directly into this window/tab if still empty, otherwise appends it as a new tab
    /// in the current window's tab group.
    public func openDocumentInNewTab(atPath path: String) {
        Task { @MainActor in
            if self.document == nil && !self.isLoadingDocument {
                await self.loadDocument(from: path)
            } else if let onOpenNewTab = self.onOpenNewTab {
                onOpenNewTab(URL(fileURLWithPath: path))
            } else {
                await self.loadDocument(from: path)
            }
        }
    }

    /// Total tabs in this window's tab group, including this one — 1 if it isn't tabbed with
    /// anything. Drives whether "Save All Open Tabs as a Group..." is offered at all (only makes
    /// sense once there's more than one tab to bundle up).
    public var currentWindowTabCount: Int {
        currentWindow?.tabbedWindows?.count ?? 1
    }

    private var currentWindowTabPaths: [String] {
        let windows = currentWindow.map { $0.tabbedWindows ?? [$0] } ?? []
        return windows.compactMap { $0.representedURL?.path }
    }

    /// Overwrites the saved Tab Group this window belongs to (`groupOrigin`) with whatever tabs
    /// are currently open here. No-op if this window isn't an instance of a saved group.
    public func updateGroupFromCurrentTabs() {
        guard let groupOrigin else { return }
        let paths = currentWindowTabPaths
        guard !paths.isEmpty else { return }
        TabGroupManager.shared.updateDocumentPaths(for: groupOrigin, to: paths)
    }

    /// Prompts for a name (a plain NSAlert, matching promptOpenFile's NSOpenPanel style — no
    /// SwiftUI view-local state needed, so this works identically whether triggered from the
    /// toolbar or the app's menu bar) and saves every tab currently open in this window as a new
    /// Tab Group.
    public func promptSaveCurrentWindowAsGroup() {
        let paths = currentWindowTabPaths
        guard !paths.isEmpty, !Self.isRunningTests else { return }

        let alert = NSAlert()
        alert.messageText = "Save Window as Tab Group"
        alert.informativeText = "Saves all \(paths.count) open tabs in this window as a group you can reopen together."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 22))
        field.placeholderString = "Group Name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        let completion: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            TabGroupManager.shared.addGroup(name: name, documentPaths: paths)
        }

        if let window = currentWindow ?? NSApplication.shared.keyWindow, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    public func promptOpenFile(inNewTab: Bool = false) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = OpenableDocumentTypes.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = inNewTab ? "Open in New Tab" : "Open"

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            if inNewTab {
                self?.openDocumentInNewTab(atPath: url.path)
            } else {
                self?.openDocumentPreferringNewWindow(atPath: url.path)
            }
        }
        
        if let window = currentWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow {
            if window.attachedSheet == nil {
                panel.beginSheetModal(for: window, completionHandler: completion)
                return
            }
        }
        panel.begin(completionHandler: completion)
    }
}

// MARK: - The sidebar when a document opens

/// The sidebar tab a document opens on.
public enum SidebarOpeningTab: Equatable, Sendable {
    case contents, layers, comments, attachments
}

extension PDFViewerViewModel {
    /// Documents this long or shorter open without the sidebar, unless something in them is
    /// found there: an outline, layers, annotations or attachments.
    static let shortDocumentPageCount = 2

    /// Whether the sidebar shows when a document opens, and on which tab. The user's own last
    /// choice for the document wins; otherwise it shows unless the document is short and has
    /// nothing for the sidebar. A short document opens on the tab that has what it holds.
    static func sidebarOpening(pageCount: Int, hasOutline: Bool, hasLayers: Bool = false, hasAnnotations: Bool, hasAttachments: Bool, savedChoice: Bool?) -> (isVisible: Bool, tab: SidebarOpeningTab) {
        let isShort = pageCount <= shortDocumentPageCount
        let tab: SidebarOpeningTab = !isShort ? .contents
            : hasAttachments ? .attachments : hasAnnotations ? .comments : hasLayers && !hasOutline ? .layers : .contents
        let isVisible = savedChoice ?? (!isShort || hasOutline || hasLayers || hasAnnotations || hasAttachments)
        return (isVisible, tab)
    }

    /// Remembers that the user showed or hid the sidebar, for the next time this document opens.
    func rememberSidebarChoice(_ isVisible: Bool) {
        guard !isTransientWindow, let doc = document else { return }
        ReadingStateManager.shared.setSidebarVisible(isVisible, for: doc.filePath)
    }
}
