import SwiftUI
import AppKit
import Foundation
import UniformTypeIdentifiers
import PDFEngine

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows {
            window.makeKeyAndOrderFront(nil)
            if window.tabbingMode != .disallowed {
                window.tabbingMode = .preferred
                if window.tabGroup?.isTabBarVisible != true {
                    window.toggleTabBar(nil)
                }
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
            // Cold start before any windows are constructed: buffer path for initial WindowGroup task
            PDFViewerAppCoordinator.shared.pendingOpenFilePath = url.path
            NotificationCenter.default.post(name: .openFilePathCommand, object: url.path)
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
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Covers "still reading a document when you quit" — the one exit path that neither
        // loadDocument's save-on-switch nor PDFViewerMainView's save-on-window-close reaches,
        // and the single most common way people actually quit a PDF reader.
        PDFViewerAppCoordinator.shared.flushAllReadingStates()
        GitHubUpdater.shared.stop()
    }
}

// General window/tab creation (isReleasedWhenClosed, tabbingMode, closure-wiring) lives in
// DocumentWindowing (PDFEngine), shared with TabGroupManager's group-opening logic. This just
// picks which of its two behaviors — new tab vs. new window — applies for drag-and-drop, which
// reads as "add this here" by direct-manipulation convention and so always joins the current
// window's tab group rather than opening separately.
@MainActor
func openDocumentInTabOrWindow(url: URL) {
    if let keyWindow = NSApp.keyWindow {
        DocumentWindowing.addTab(url: url, to: keyWindow)
    } else {
        DocumentWindowing.openNewWindow(url: url)
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

// Snapshot windows ("Open in New Window" on a link, selection, page location, or snapshot
// card) are created by SnapshotWindowManager (in PDFEngine) rather than here — see that type
// for window creation, cascading, and parent/child close behavior.

struct DocumentWindowView: View {
    let initialFilePath: String?
    let initialURL: URL?

    var body: some View {
        PDFViewerMainView(
            initialFilePath: initialFilePath,
            initialURL: initialURL,
            onOpenNewTab: { url in
                openDocumentInTabOrWindow(url: url)
            },
            onOpenNewWindow: { url in
                DocumentWindowing.openNewWindow(url: url)
            }
        )
    }
}

@main
struct VectorPDFApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared

    // Uses coordinator.activeViewModel instead of @FocusedValue to prevent redundant
    // command-tree rebuilds while menus are open.
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
    
    private var initialPath: String? {
        let args = CommandLine.arguments
        if args.count > 1 && !args[1].starts(with: "-") {
            return args[1]
        }
        return nil
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
                NSApplication.shared.orderFrontStandardAboutPanel(options: [.credits: VectorPDFApp.aboutCredits])
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

            // Reads NSDocumentController's shared recent-documents list directly rather than
            // maintaining our own — its size already follows AppKit/system configuration, so
            // "how many are shown, or none at all" is handled for free rather than something we'd
            // need to reimplement. `coordinator.recentDocumentsRevision` isn't read for its value,
            // only to make this re-evaluate when a new document is opened (recentDocumentURLs
            // itself isn't observable).
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
        }
        
        CommandGroup(replacing: .printItem) {
            Button("Print...") {
                resolvedViewModel?.printDocument()
            }
            .keyboardShortcut("p", modifiers: .command)
            .disabled(!hasDocument)
        }
        
        CommandMenu("Favorites") {
            // Mirrors the toolbar's star-icon menu exactly (see PDFUI.swift) — the two "save
            // something for later" actions paired together with explicit scope in the label,
            // then the read-only Favorites/Tab Groups lists below,
            // with Tab Groups placed above Favorites to match the Start screen hierarchy.
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

            if !TabGroupManager.shared.groups.isEmpty {
                Divider()
                Section("Tab Groups") {
                    ForEach(TabGroupManager.shared.groups) { group in
                        Menu("\(group.name) (\(group.documentPaths.count))") {
                            Button("Open") {
                                TabGroupManager.shared.open(group)
                                TabGroupManager.shared.open(group, replacing: resolvedViewModel?.currentWindow)
                            }
                            Button("Delete Group", role: .destructive) {
                                TabGroupManager.shared.removeGroup(group.id)
                            }
                        }
                    }
                }
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
        }
        
        CommandGroup(replacing: .toolbar) {
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
            .keyboardShortcut("0", modifiers: .command)
            .disabled(!hasDocument)
        }
    }
    
    var body: some Scene {
        WindowGroup {
            DocumentWindowView(initialFilePath: initialPath, initialURL: nil)
                .frame(minWidth: 960, minHeight: 650)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            appCommands
        }

        Settings {
            AppSettingsView()
        }
    }
}
