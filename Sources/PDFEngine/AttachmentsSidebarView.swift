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
@preconcurrency import Quartz
import SwiftUI
import UniformTypeIdentifiers

/// The sidebar's Attachments tab: the files embedded in the PDF, which can be previewed with
/// Quick Look, opened, saved or dragged out. Shown only for a document with attachments.
struct AttachmentsSidebarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    private var count: Int { viewModel.attachments.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(count) Attachment\(count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Save All…") {
                    viewModel.saveAllAttachments()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .help("Save every attachment in a folder")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            // An AppKit table: a SwiftUI List with draggable rows waits on every click to see if
            // a drag starts, which made selecting slow and swallowed double-clicks.
            AttachmentsTableView(viewModel: viewModel, attachments: viewModel.attachments)
        }
    }
}

/// The list of attachments, as an NSTableView: double-click or Space for Quick Look (with the
/// arrow keys moving through them while it's open, as in the Finder), a right-click menu, and
/// rows dragged out as file promises, written only when dropped.
struct AttachmentsTableView: NSViewRepresentable {
    let viewModel: PDFViewerViewModel
    let attachments: [PDFAttachment]

    func makeCoordinator() -> Coordinator { Coordinator(viewModel: viewModel) }

    func makeNSView(context: Context) -> NSScrollView {
        let table = AttachmentsNSTableView()
        table.coordinator = context.coordinator
        table.headerView = nil
        table.style = .sourceList
        table.usesAutomaticRowHeights = true
        table.allowsMultipleSelection = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("attachment")))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        let menu = NSMenu()
        menu.delegate = context.coordinator
        table.menu = menu
        context.coordinator.table = table

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.viewModel = viewModel
        context.coordinator.update(attachments)
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate,
                             NSFilePromiseProviderDelegate, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
        var viewModel: PDFViewerViewModel
        weak var table: NSTableView?
        private(set) var attachments: [PDFAttachment] = []
        /// Files already taken out for Quick Look, so moving back to one doesn't write it again.
        private var extracted: [PDFAttachment.ID: URL] = [:]
        private let promiseQueue: OperationQueue = {
            let queue = OperationQueue()
            queue.qualityOfService = .userInitiated
            return queue
        }()

        /// Shows the Quick Look panel. Window tests replace it: a real panel under the test runner
        /// ends the test process.
        var presentQuickLook: () -> Void = { QLPreviewPanel.shared().makeKeyAndOrderFront(nil) }

        init(viewModel: PDFViewerViewModel) {
            self.viewModel = viewModel
        }

        func update(_ new: [PDFAttachment]) {
            guard new != attachments else { return }
            // Positions may now mean other files (another document, or the list read again).
            attachments = new
            extracted = [:]
            table?.reloadData()
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().reloadData()
            }
        }

        var selected: PDFAttachment? {
            guard let row = table?.selectedRow, attachments.indices.contains(row) else { return nil }
            return attachments[row]
        }

        // MARK: Table

        func numberOfRows(in tableView: NSTableView) -> Int { attachments.count }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let id = NSUserInterfaceItemIdentifier("AttachmentCell")
            let cell = tableView.makeView(withIdentifier: id, owner: nil) as? AttachmentCellView ?? AttachmentCellView()
            cell.identifier = id
            cell.show(attachments[row])
            return cell
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().reloadData()
            }
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            guard sender.clickedRow >= 0 else { return }
            showQuickLook()
        }

        func showQuickLook() {
            guard selected != nil, let table else { return }
            // The panel finds its controller through the responder chain, from the table.
            table.window?.makeFirstResponder(table)
            presentQuickLook()
        }

        // MARK: Right-click menu

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, attachments.indices.contains(table.clickedRow) else { return }
            if table.selectedRow != table.clickedRow {
                table.selectRowIndexes(IndexSet(integer: table.clickedRow), byExtendingSelection: false)
            }
            let attachment = attachments[table.clickedRow]
            func item(_ title: String, _ action: @escaping () -> Void) {
                let menuItem = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
                let target = MenuAction(action)
                menuItem.target = target
                menuItem.representedObject = target // the menu item keeps its target alive
                menu.addItem(menuItem)
            }
            item("Quick Look") { [weak self] in self?.showQuickLook() }
            item("Open") { [weak self] in self?.viewModel.openAttachment(attachment) }
            item("Save As…") { [weak self] in self?.viewModel.saveAttachmentAs(attachment) }
            if let page = attachment.pageIndex {
                menu.addItem(.separator())
                item("Show on Page") { [weak self] in self?.viewModel.jumpToPage(page) }
            }
        }

        // MARK: Dragging out

        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> (any NSPasteboardWriting)? {
            guard attachments.indices.contains(row) else { return nil }
            let attachment = attachments[row]
            let type = attachment.contentType ?? .data
            let provider = NSFilePromiseProvider(fileType: type.identifier, delegate: self)
            provider.userInfo = attachment
            return provider
        }

        nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
            (provider.userInfo as? PDFAttachment)?.fileName ?? "Attachment"
        }

        nonisolated func operationQueue(for provider: NSFilePromiseProvider) -> OperationQueue {
            MainActor.assumeIsolated { promiseQueue }
        }

        nonisolated func filePromiseProvider(_ provider: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping ((any Error)?) -> Void) {
            guard let attachment = provider.userInfo as? PDFAttachment else {
                completionHandler(PDFError.saveFailed("Nothing to save"))
                return
            }
            let document = DispatchQueue.main.sync { MainActor.assumeIsolated { viewModel.document } }
            do {
                guard let document else { throw PDFError.saveFailed("No document is open") }
                try document.saveAttachment(attachment, to: url.path)
                PDFViewerViewModel.quarantine(url)
                completionHandler(nil)
            } catch {
                completionHandler(error)
            }
        }

        // MARK: Quick Look

        nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
            MainActor.assumeIsolated { selected == nil ? 0 : 1 }
        }

        nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
            MainActor.assumeIsolated {
                guard let attachment = selected else { return nil }
                if let url = extracted[attachment.id] { return url as NSURL }
                guard let url = try? viewModel.extractAttachment(attachment) else { return nil }
                extracted[attachment.id] = url
                return url as NSURL
            }
        }

        /// The arrow keys move through the attachments while the panel is open, as in the Finder.
        nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
            // The panel calls this on the main thread with an event made there.
            nonisolated(unsafe) let event = event
            return MainActor.assumeIsolated {
                guard let event, event.type == .keyDown, let table, [125, 126].contains(event.keyCode) else { return false }
                table.keyDown(with: event)
                return true
            }
        }
    }
}

/// Runs a closure from a menu item.
private final class MenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

/// The table, taking control of the Quick Look panel and opening it with Space.
final class AttachmentsNSTableView: NSTableView {
    weak var coordinator: AttachmentsTableView.Coordinator?

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
                QLPreviewPanel.shared().orderOut(nil)
            } else {
                coordinator?.showQuickLook()
            }
            return
        }
        super.keyDown(with: event)
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { coordinator != nil }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = coordinator
        panel.delegate = coordinator
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }
}

/// A row: the file's icon, its name, then its description and size or page.
final class AttachmentCellView: NSTableCellView {
    private let icon = NSImageView()
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private let info = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        icon.imageScaling = .scaleProportionallyUpOrDown
        name.font = .systemFont(ofSize: NSFont.systemFontSize)
        name.lineBreakMode = .byTruncatingMiddle
        detail.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        detail.textColor = .secondaryLabelColor
        detail.maximumNumberOfLines = 2
        detail.lineBreakMode = .byTruncatingTail
        detail.cell?.truncatesLastVisibleLine = true
        info.font = .systemFont(ofSize: NSFont.smallSystemFontSize - 1)
        info.textColor = .tertiaryLabelColor
        for label in [name, detail, info] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let text = NSStackView(views: [name, detail, info])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        imageView = icon
        textField = name
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 28),
            icon.heightAnchor.constraint(equalToConstant: 28),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -2),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 4),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -4),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ attachment: PDFAttachment) {
        icon.image = NSWorkspace.shared.icon(for: attachment.contentType ?? .data)
        name.stringValue = attachment.name
        detail.stringValue = attachment.description ?? ""
        detail.isHidden = attachment.description == nil
        var parts: [String] = []
        if let size = attachment.size {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
        }
        if let page = attachment.pageIndex { parts.append("Page \(page + 1)") }
        if parts.isEmpty, let kind = attachment.contentType?.localizedDescription { parts.append(kind) }
        info.stringValue = parts.joined(separator: " · ")
        info.isHidden = parts.isEmpty

        var tip = [attachment.name]
        if let description = attachment.description { tip.append(description) }
        if let kind = attachment.contentType?.localizedDescription { tip.append(kind) }
        if let date = attachment.modified ?? attachment.created {
            tip.append("Modified \(date.formatted(date: .abbreviated, time: .shortened))")
        }
        toolTip = tip.joined(separator: "\n")
    }
}
