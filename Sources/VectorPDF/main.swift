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
import Foundation
import UniformTypeIdentifiers
import PDFEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// The file path passed as a CLI argument (`open -a VectorPDF file.pdf`, or running the
    /// built binary directly), if any.
    private static func commandLineFilePath() -> String? {
        let args = CommandLine.arguments
        if args.count > 1 && !args[1].starts(with: "-") {
            return args[1]
        }
        return nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = TabBarAppearanceHelper.shared
        DocumentWindowing.installTabBarPlusButtonHandler()
        NSApp.setActivationPolicy(.regular)

        // The initial document window is created here via DocumentWindowing.
        // consumePendingOpenFilePath prioritizes Finder/CLI open events over launch arguments.
        let launchPath = PDFViewerAppCoordinator.shared.consumePendingOpenFilePath() ?? Self.commandLineFilePath()
        if let launchPath {
            DocumentWindowing.openNewWindow(url: URL(fileURLWithPath: launchPath))
        } else {
            DocumentWindowing.openNewEmptyWindow()
        }

        let additionalPaths = PDFViewerAppCoordinator.shared.pendingAdditionalOpenFilePaths
        PDFViewerAppCoordinator.shared.pendingAdditionalOpenFilePaths = []
        for path in additionalPaths {
            DocumentWindowing.openNewWindow(url: URL(fileURLWithPath: path))
        }

        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
            if window.tabbingMode != .disallowed {
                window.tabbingMode = .preferred
                if window.tabGroup?.isTabBarVisible != true {
                    window.toggleTabBar(nil)
                }
                TabBarAppearanceHelper.refreshTabs(for: window)
            }
        }
        DispatchQueue.main.async {
            if NSApp.windows.contains(where: { !DocumentWindowing.isStandaloneEmptyStartWindow($0) }) {
                DocumentWindowing.closeStandaloneEmptyStartWindows()
            }
        }
        GitHubUpdater.shared.start(
            gitHubUser: "tomderham",
            gitHubRepo: "vectorpdf",
            applicationName: "VectorPDF"
        )
    }
    
    @MainActor
    private func handleSystemOpenFile(url: URL) {
        if NSApp.windows.isEmpty {
            // Buffer path during cold start before applicationDidFinishLaunching runs.
            let coordinator = PDFViewerAppCoordinator.shared
            let isFirst = coordinator.pendingOpenFilePath == nil
            coordinator.enqueuePendingOpenFilePath(url.path)
            if isFirst {
                NotificationCenter.default.post(name: .openFilePathCommand, object: url.path)
            }
        } else {
            // Warm start: if current window has a single empty tab, open into that, else open in a new window
            DocumentWindowing.openDocumentHandlingEmptyStart(url: url)
        }
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        handleSystemOpenFile(url: url)
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            handleSystemOpenFile(url: url)
        }
    }

    func application(_ application: NSApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([NSUserActivityRestoring]) -> Void) -> Bool {
        guard userActivity.activityType == "com.thomasderham.vectorpdf.document-reading",
              let userInfo = userActivity.userInfo else {
            return false
        }

        var targetPath = userInfo["filePath"] as? String
        let canonicalKey = userInfo["canonicalKey"] as? String
        let pageIndex = userInfo["pageIndex"] as? Int ?? 0

        // If the path from the remote machine does not exist locally, resolve its canonical cloud key
        if let canonicalKey, targetPath == nil || !FileManager.default.fileExists(atPath: targetPath!) {
            targetPath = CloudStorageHelper.resolveLocalPath(for: canonicalKey)
        }

        guard let path = targetPath, FileManager.default.fileExists(atPath: path) else {
            return false
        }

        let url = URL(fileURLWithPath: path)
        DispatchQueue.main.async { [weak self] in
            self?.handleSystemOpenFile(url: url)
            if pageIndex > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if let active = PDFViewerAppCoordinator.shared.activeViewModel {
                        active.jumpToPage(pageIndex)
                    }
                }
            }
        }
        return true
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    @MainActor
    @objc func newWindowForTab(_ sender: Any?) {
        if let keyWindow = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApp.windows.first {
            DocumentWindowing.addEmptyTab(to: keyWindow)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let dirtyWindows = sender.windows.filter { $0.isDocumentEdited && !($0 is NSPanel) }
        for window in dirtyWindows {
            window.makeKeyAndOrderFront(nil)
            if let delegate = window.delegate {
                if delegate.windowShouldClose?(window) == false {
                    return .terminateCancel
                }
            }
        }
        return .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Persist reading state on application termination.
        PDFViewerAppCoordinator.shared.flushAllReadingStates()
        GitHubUpdater.shared.stop()
    }
}

@MainActor
func promptOpenFileGlobal(inNewTab: Bool) {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [UTType.pdf]
    panel.allowsMultipleSelection = false
    panel.canChooseDirectories = false
    panel.canChooseFiles = true
    panel.prompt = inNewTab ? "Open PDF in New Tab" : "Open PDF"

    let completion: (NSApplication.ModalResponse) -> Void = { response in
        guard response == .OK, let url = panel.url else { return }
        if inNewTab, let keyWindow = NSApp.keyWindow {
            DocumentWindowing.addTab(url: url, to: keyWindow)
        } else {
            DocumentWindowing.openNewWindow(url: url)
        }
    }
    panel.begin(completionHandler: completion)
}

// Snapshot windows are managed by SnapshotWindowManager.

@main
struct VectorPDF: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = PDFViewerAppCoordinator.shared

    // Uses coordinator.activeViewModel to avoid command-tree rebuilds while menus are open.
    private var resolvedViewModel: PDFViewerViewModel? {
        if let vm = coordinator.activeViewModel, vm.document != nil {
            return vm
        }
        if let vm = PDFViewerViewModel.active, vm.document != nil {
            return vm
        }
        return coordinator.activeViewModel ?? PDFViewerViewModel.active
    }
    
    private var hasDocument: Bool {
        coordinator.hasActiveDocument || (resolvedViewModel?.document != nil)
    }
    
    /// Rich-text credits displayed in the About panel.
    private static var aboutCredits: NSAttributedString {
        let text = """
        VectorPDF is a native macOS PDF reader, released under the GNU Affero \
        General Public License v3 (AGPL-3.0).

        PDF rendering is powered by MuPDF, © Artifex Software, Inc., also \
        licensed under the AGPL-3.0.
        """
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .paragraphStyle: paragraphStyle,
                .foregroundColor: NSColor.labelColor,
            ]
        )
        if let range = text.range(of: "MuPDF") {
            attributed.addAttribute(.link, value: "https://mupdf.com", range: NSRange(range, in: text))
        }
        return attributed
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About VectorPDF") {
                NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: VectorPDF.aboutCredits])
            }
            Button("Check for Updates...") {
                GitHubUpdater.shared.checkForUpdates(isManualCheck: true)
            }
        }
        CommandGroup(replacing: .newItem) {
            Button("New Window") {
                DocumentWindowing.openNewEmptyWindow()
            }
            .keyboardShortcut("n", modifiers: .command)

            Button("New Tab") {
                if let keyWindow = NSApp.keyWindow {
                    DocumentWindowing.addEmptyTab(to: keyWindow)
                } else {
                    DocumentWindowing.openNewEmptyWindow()
                }
            }
            .keyboardShortcut("t", modifiers: .command)

            Divider()

            Button("Open PDF...") {
                if let vm = resolvedViewModel {
                    vm.promptOpenFile(inNewTab: false)
                } else {
                    promptOpenFileGlobal(inNewTab: false)
                }
            }
            .keyboardShortcut("o", modifiers: .command)

            Button("Open PDF in New Tab...") {
                if let vm = resolvedViewModel {
                    vm.promptOpenFile(inNewTab: true)
                } else {
                    promptOpenFileGlobal(inNewTab: true)
                }
            }
            .keyboardShortcut("o", modifiers: [.command, .option])

            Button("Insert Pages from PDF...") {
                resolvedViewModel?.promptImportPDF(atSlot: nil)
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(!hasDocument)

            // Reads NSDocumentController recent documents list directly.
            Menu("Open Recent") {
                let _ = coordinator.recentDocumentsRevision
                let recents = NSDocumentController.shared.recentDocumentURLs
                if recents.isEmpty {
                    Text("No Recent Documents")
                } else {
                    ForEach(recents, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            if let vm = resolvedViewModel {
                                vm.openDocumentPreferringNewWindow(atPath: url.path)
                            } else {
                                DocumentWindowing.openNewWindow(url: url)
                            }
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                        coordinator.recentDocumentsRevision += 1
                    }
                }
            }
        }
        
        CommandGroup(replacing: .saveItem) {
            Button("Save") {
                resolvedViewModel?.saveDocument()
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!hasDocument)
            
            Button("Save As...") {
                resolvedViewModel?.saveDocumentAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(!hasDocument)

            Button("Save Encrypted with Password...") {
                resolvedViewModel?.saveDocumentEncryptedAs()
            }
            .keyboardShortcut("s", modifiers: [.command, .option])
            .disabled(!hasDocument)

            Divider()

            Button("Split PDF...") {
                if let vm = resolvedViewModel {
                    vm.showSplitPDF()
                } else {
                    NotificationCenter.default.post(name: .showSplitPDFCommand, object: nil)
                }
            }
            .disabled(!hasDocument)

            Menu("Export Document As") {
                Button("Plain Text (.txt)...") {
                    resolvedViewModel?.exportDocument(as: .plainText)
                }
                Button("Word Document (.docx)...") {
                    resolvedViewModel?.exportDocument(as: .wordDocument)
                }
                Button("Scalable Vector Graphics (.svg)...") {
                    resolvedViewModel?.exportDocument(as: .svgDocument)
                }
                Button("Flattened PDF (.pdf)...") {
                    resolvedViewModel?.exportDocument(as: .flattenedPDF)
                }
            }
            .disabled(!hasDocument)

            Button("Export Annotations Summary...") {
                resolvedViewModel?.exportAnnotationsSummary()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(!hasDocument)

            Divider()

            Button("Share...") {
                resolvedViewModel?.shareDocument()
            }
            .disabled(!hasDocument)

            Button("Show in Finder") {
                resolvedViewModel?.showInFinder()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!hasDocument)
        }
        
        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                resolvedViewModel?.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!hasDocument)

            Divider()

            Button("Document Properties...") {
                if let vm = resolvedViewModel {
                    vm.showDocumentProperties()
                } else {
                    NotificationCenter.default.post(name: .showDocumentPropertiesCommand, object: nil)
                }
            }
            .keyboardShortcut("i", modifiers: .command)
            .disabled(!hasDocument)
        }
        
        CommandMenu("Favorites") {
            // Mirrors the toolbar star menu.
            if let vm = resolvedViewModel, let groupOrigin = vm.groupOrigin, let group = TabGroupManager.shared.group(withId: groupOrigin) {
                Button("Update Group “\(group.name)” with Open Tabs") {
                    vm.updateGroupFromCurrentTabs()
                }
            }

            if let vm = resolvedViewModel, vm.currentWindowTabCount > 1 {
                Button("Save All Open Tabs as a Group...") {
                    vm.promptSaveCurrentWindowAsGroup()
                }
            }

            Button(hasDocument && FavoritesManager.shared.isFavorite(path: resolvedViewModel?.document?.filePath ?? "") ? "Remove This PDF from Favorites" : "Add This PDF to Favorites") {
                if let vm = resolvedViewModel, let doc = vm.document {
                    FavoritesManager.shared.toggleFavorite(path: doc.filePath, title: vm.documentTitle)
                }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(!hasDocument)

            Divider()

            if !TabGroupManager.shared.groups.isEmpty {
                Section("Tab Groups") {
                    ForEach(TabGroupManager.shared.groups) { group in
                        Menu("\(group.name) (\(group.documentPaths.count))") {
                            Button("Open") {
                                TabGroupManager.shared.open(group)
                            }
                            Button("Delete Tab Group", role: .destructive) {
                                TabGroupManager.shared.removeGroup(group.id)
                            }
                        }
                    }
                }
                Divider()
            }

            if FavoritesManager.shared.favorites.isEmpty {
                Text("No Favorites Added")
            } else {
                Section("Favorites") {
                    ForEach(FavoritesManager.shared.favorites) { fav in
                        Menu(fav.title) {
                            Button("Open") {
                                if let vm = resolvedViewModel {
                                    vm.openDocumentPreferringNewWindow(atPath: fav.path)
                                } else {
                                    DocumentWindowing.openNewWindow(url: URL(fileURLWithPath: fav.path))
                                }
                            }
                            Button("Remove from Favorites", role: .destructive) {
                                FavoritesManager.shared.removeFavorite(path: fav.path)
                            }
                        }
                    }
                }
            }
        }
        
        CommandMenu("Anchors") {
            Button("Add Anchor") {
                resolvedViewModel?.addAnchorForCurrentPage()
            }
            .keyboardShortcut("b", modifiers: .command)
            .disabled(!hasDocument)

            Divider()

            let anchors = !coordinator.activeAnchors.isEmpty ? coordinator.activeAnchors : (resolvedViewModel?.activeSnapshots ?? [])
            if !anchors.isEmpty {
                ForEach(anchors) { snap in
                    Button(snap.menuDisplayTitle) {
                        resolvedViewModel?.jumpToSnapshot(snap)
                    }
                }
                Divider()
                Button("Clear All Anchors", role: .destructive) {
                    resolvedViewModel?.clearAllSnapshots()
                }
            } else {
                Text("No Anchors Added")
            }
        }

        CommandGroup(after: .textEditing) {
            Menu("Find") {
                Button("Find...") {
                    NotificationCenter.default.post(name: .focusSearchCommand, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
                
                Button("Find Next") {
                    resolvedViewModel?.nextSearchMatch()
                }
                .keyboardShortcut("g", modifiers: .command)
                .disabled(!hasDocument)
                
                Button("Find Previous") {
                    resolvedViewModel?.previousSearchMatch()
                }
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(!hasDocument)
            }

            Divider()

            Menu("Highlight Selection") {
                Button("Highlight") {
                    resolvedViewModel?.highlightSelection(color: resolvedViewModel?.selectedAnnotationColor ?? .yellow)
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                ForEach(AnnotationColor.allCases, id: \.rawValue) { color in
                    Button {
                        resolvedViewModel?.selectedAnnotationColor = color
                        resolvedViewModel?.highlightSelection(color: color)
                    } label: {
                        Label {
                            Text(color.displayName)
                        } icon: {
                            Image(nsImage: color.menuIcon)
                        }
                    }
                }
            }
            .disabled(!coordinator.hasActiveSelection)

            Menu("Underline Selection") {
                Button("Underline") {
                    resolvedViewModel?.underlineSelection(color: resolvedViewModel?.selectedAnnotationColor ?? .yellow)
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])

                Divider()

                ForEach(AnnotationColor.allCases, id: \.rawValue) { color in
                    Button {
                        resolvedViewModel?.selectedAnnotationColor = color
                        resolvedViewModel?.underlineSelection(color: color)
                    } label: {
                        Label {
                            Text(color.displayName)
                        } icon: {
                            Image(nsImage: color.menuIcon)
                        }
                    }
                }
            }
            .disabled(!coordinator.hasActiveSelection)

            Menu("Strikethrough Selection") {
                Button("Strikethrough") {
                    resolvedViewModel?.strikethroughSelection(color: resolvedViewModel?.selectedAnnotationColor ?? .yellow)
                }
                .keyboardShortcut("x", modifiers: [.command, .shift])

                Divider()

                ForEach(AnnotationColor.allCases, id: \.rawValue) { color in
                    Button {
                        resolvedViewModel?.selectedAnnotationColor = color
                        resolvedViewModel?.strikethroughSelection(color: color)
                    } label: {
                        Label {
                            Text(color.displayName)
                        } icon: {
                            Image(nsImage: color.menuIcon)
                        }
                    }
                }
            }
            .disabled(!coordinator.hasActiveSelection)



            Divider()

            Menu("Speech") {
                // No shortcut: ⌥⌘S is Save Encrypted with Password.
                Button("Start Speaking") {
                    resolvedViewModel?.startSpeakingSelection()
                }
                .disabled(!coordinator.hasActiveSelection)

                Button("Stop Speaking") {
                    resolvedViewModel?.stopSpeaking()
                }
                .keyboardShortcut(".", modifiers: [.option, .command])
                .disabled(!coordinator.isSpeaking)
            }
        }
        
        CommandGroup(replacing: .toolbar) {
            Button((resolvedViewModel?.isMarkupBarVisible ?? false) ? "Hide Markup Toolbar" : "Show Markup Toolbar") {
                resolvedViewModel?.isMarkupBarVisible.toggle()
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(!hasDocument)

            Button((resolvedViewModel?.isMeasurementBarVisible ?? false) ? "Hide Measurement Toolbar" : "Show Measurement Toolbar") {
                resolvedViewModel?.toggleMeasurementBar()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(!hasDocument)

            Button((resolvedViewModel?.isRedactionBarVisible ?? false) ? "Hide Redact Toolbar" : "Show Redact Toolbar") {
                resolvedViewModel?.toggleRedactionBar()
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
            .disabled(!hasDocument)

            Divider()

            Button("Zoom In") {
                resolvedViewModel?.zoomIn()
            }
            .keyboardShortcut("+", modifiers: .command)
            .disabled(!hasDocument)
            
            Button("Zoom Out") {
                resolvedViewModel?.zoomOut()
            }
            .keyboardShortcut("-", modifiers: .command)
            .disabled(!hasDocument)
            
            Button("Actual Size (100%)") {
                resolvedViewModel?.resetZoom()
            }
            .keyboardShortcut("1", modifiers: .command)
            .disabled(!hasDocument)

            Button("Zoom to Fit Width") {
                resolvedViewModel?.zoomToFitWidth()
            }
            .keyboardShortcut("9", modifiers: .command)
            .disabled(!hasDocument)

            Button("Zoom to Fit Window") {
                resolvedViewModel?.zoomToFitPage()
            }
            .keyboardShortcut("0", modifiers: [.command, .option])
            .disabled(!hasDocument)

            Divider()

            Button((resolvedViewModel?.isTwoPageMode ?? false) ? "Single Page" : "Two Pages") {
                resolvedViewModel?.toggleTwoPageMode()
            }
            .keyboardShortcut("2", modifiers: [.command, .option])
            .disabled(!hasDocument)

            Divider()

            Picker("PDF Color", selection: $coordinator.pdfColorAppearance) {
                ForEach(PDFColorAppearance.allCases, id: \.self) { appearance in
                    Text(appearance.displayName).tag(appearance)
                }
            }

            Picker("Define 100% Scale As", selection: $coordinator.scaleMode) {
                ForEach(PDFScaleMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
        }
        
        CommandMenu("Go") {
            Button("Back") {
                resolvedViewModel?.goBack()
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!(resolvedViewModel?.canGoBack ?? false))

            Button("Forward") {
                resolvedViewModel?.goForward()
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!(resolvedViewModel?.canGoForward ?? false))

            Divider()

            Button("Previous Page") {
                resolvedViewModel?.previousPage()
            }
            .keyboardShortcut(.upArrow, modifiers: .option)
            .disabled(!hasDocument || !(resolvedViewModel?.canGoPreviousPage ?? false))

            Button("Next Page") {
                resolvedViewModel?.nextPage()
            }
            .keyboardShortcut(.downArrow, modifiers: .option)
            .disabled(!hasDocument || !(resolvedViewModel?.canGoNextPage ?? false))

            Divider()

            Button("First Page") {
                resolvedViewModel?.goToFirstPage()
            }
            .keyboardShortcut(.upArrow, modifiers: .command)
            .disabled(!hasDocument || !(resolvedViewModel?.canGoPreviousPage ?? false))

            Button("Last Page") {
                resolvedViewModel?.goToLastPage()
            }
            .keyboardShortcut(.downArrow, modifiers: .command)
            .disabled(!hasDocument || !(resolvedViewModel?.canGoNextPage ?? false))
        }
    }
    
    // Document windows are managed by DocumentWindowing. Settings serves as the required SwiftUI Scene.
    var body: some Scene {
        Settings {
            AppSettingsView()
        }
        .defaultLaunchBehavior(.suppressed)
        .commands {
            appCommands
        }
    }
}
