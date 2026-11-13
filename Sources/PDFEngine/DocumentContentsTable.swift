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
import SwiftUI

/// A row of one of the Document tab's lists: a page heading, or an entry.
enum ContentsRow: Equatable {
    case header(String)
    case item(ContentsItem)
}

struct ContentsItem: Equatable {
    let id: String
    var symbol: String?
    var title: String
    /// Lines under the title, in the secondary colour.
    var details: [String] = []
    /// A line under those, in orange, for something to look out for.
    var warning: String?
    /// At the right of the title, such as a page.
    var trailing: String?
    var tooltip: String?
    /// The page it's on, for reading what's shown about it when it first shows.
    var page: Int?
}

/// One of the Document tab's lists, as an AppKit table: SwiftUI's List slows to a crawl with the
/// tens of thousands of links or destinations a long document can have, and changing it from
/// its selection handler upsets the table under it. Rows are made again only when `key` changes.
struct DocumentContentsTable: NSViewRepresentable {
    /// Changes whenever the rows would.
    let key: AnyHashable
    /// Changes when what `decorate` gives may have: only the rows on screen are drawn again.
    var refreshKey: AnyHashable = 0
    /// Fills in an entry as it's drawn, with what's been read since the rows were made.
    var decorate: ((ContentsItem) -> ContentsItem)?
    let makeRows: () -> [ContentsRow]
    /// A row clicked or chosen with the arrow keys.
    var onSelect: (ContentsItem) -> Void
    /// A row double-clicked.
    var onOpen: ((ContentsItem) -> Void)?
    /// A row first drawn.
    var onShow: ((ContentsItem) -> Void)?
    /// The right-click menu's commands for a row; a nil title is a separator.
    var menuItems: (ContentsItem) -> [(title: String?, action: () -> Void)] = { _ in [] }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let table = NSTableView()
        table.headerView = nil
        table.style = .sourceList
        table.allowsMultipleSelection = false
        table.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("row")))
        table.dataSource = context.coordinator
        table.delegate = context.coordinator
        table.target = context.coordinator
        table.doubleAction = #selector(Coordinator.doubleClicked(_:))
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
        let coordinator = context.coordinator
        coordinator.parent = self
        if coordinator.key != key {
            coordinator.key = key
            coordinator.refreshKey = refreshKey
            coordinator.setRows(makeRows())
        } else if coordinator.refreshKey != refreshKey {
            coordinator.refreshKey = refreshKey
            coordinator.redrawVisibleRows()
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        var parent: DocumentContentsTable?
        var key: AnyHashable?
        var refreshKey: AnyHashable?
        weak var table: NSTableView?
        private(set) var rows: [ContentsRow] = []
        /// Set while the rows are being replaced, so the table's own selection changes then
        /// aren't taken as the user's.
        private var isReloading = false

        func setRows(_ new: [ContentsRow]) {
            guard new != rows, let table else { return }
            let selectedID = selectedItem?.id
            isReloading = true
            rows = new
            table.reloadData()
            if let selectedID, let row = rows.firstIndex(where: { if case .item(let item) = $0 { return item.id == selectedID }; return false }) {
                table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            isReloading = false
        }

        func redrawVisibleRows() {
            guard let table else { return }
            let visible = table.rows(in: table.visibleRect)
            guard visible.length > 0 else { return }
            table.reloadData(forRowIndexes: IndexSet(integersIn: visible.location..<(visible.location + visible.length)), columnIndexes: IndexSet(integer: 0))
            table.noteHeightOfRows(withIndexesChanged: IndexSet(integersIn: visible.location..<(visible.location + visible.length)))
        }

        private var selectedItem: ContentsItem? {
            guard let row = table?.selectedRow, rows.indices.contains(row), case .item(let item) = rows[row] else { return nil }
            return item
        }

        private func item(at row: Int) -> ContentsItem? {
            guard rows.indices.contains(row), case .item(let item) = rows[row] else { return nil }
            return item
        }

        func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

        func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
            if case .header = rows[row] { return true }
            return false
        }

        func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool { item(at: row) != nil }

        func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
            guard let stored = item(at: row) else { return 24 }
            let item = parent?.decorate?(stored) ?? stored
            let lines = item.details.count + (item.warning == nil ? 0 : 1)
            return 22 + CGFloat(lines) * 15
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            switch rows[row] {
            case .header(let title):
                let id = NSUserInterfaceItemIdentifier("ContentsHeader")
                let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
                    let cell = NSTableCellView()
                    cell.identifier = id
                    let label = NSTextField(labelWithString: "")
                    label.translatesAutoresizingMaskIntoConstraints = false
                    cell.addSubview(label)
                    cell.textField = label
                    NSLayoutConstraint.activate([
                        label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                        label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                    ])
                    return cell
                }()
                cell.textField?.stringValue = title
                return cell
            case .item(let stored):
                let item = parent?.decorate?(stored) ?? stored
                let id = NSUserInterfaceItemIdentifier("ContentsItem")
                let cell = tableView.makeView(withIdentifier: id, owner: nil) as? ContentsItemCell ?? ContentsItemCell()
                cell.identifier = id
                cell.show(item)
                if let onShow = parent?.onShow {
                    // Afterwards: what it reads changes the view model, not to be done while the
                    // table is laying out its rows.
                    DispatchQueue.main.async { onShow(item) }
                }
                return cell
            }
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isReloading, let item = selectedItem, let onSelect = parent?.onSelect else { return }
            // After the table has finished: scrolling the page changes the view model.
            DispatchQueue.main.async { onSelect(item) }
        }

        @objc func doubleClicked(_ sender: NSTableView) {
            guard let item = item(at: sender.clickedRow), let onOpen = parent?.onOpen else { return }
            DispatchQueue.main.async { onOpen(item) }
        }

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()
            guard let table, let item = item(at: table.clickedRow), let parent else { return }
            for entry in parent.menuItems(item) {
                guard let title = entry.title else {
                    menu.addItem(.separator())
                    continue
                }
                let menuItem = NSMenuItem(title: title, action: #selector(ContentsMenuAction.run), keyEquivalent: "")
                let target = ContentsMenuAction(entry.action)
                menuItem.target = target
                menuItem.representedObject = target // the menu item keeps its target alive
                menu.addItem(menuItem)
            }
        }
    }
}

private final class ContentsMenuAction: NSObject {
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @objc func run() { action() }
}

/// An entry: a symbol, its title with something at the right, then lines of detail.
private final class ContentsItemCell: NSTableCellView {
    private let icon = NSImageView()
    private let title = NSTextField(labelWithString: "")
    private let trailing = NSTextField(labelWithString: "")
    private let details = NSTextField(labelWithString: "")
    private let warning = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        icon.contentTintColor = .secondaryLabelColor
        title.lineBreakMode = .byTruncatingMiddle
        trailing.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        trailing.textColor = .secondaryLabelColor
        trailing.setContentCompressionResistancePriority(.required, for: .horizontal)
        trailing.setContentHuggingPriority(.required, for: .horizontal)
        details.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        details.textColor = .secondaryLabelColor
        details.lineBreakMode = .byTruncatingTail
        details.maximumNumberOfLines = 0
        warning.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        warning.textColor = .systemOrange
        for label in [title, details, warning] {
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        let top = NSStackView(views: [title, trailing])
        top.spacing = 6
        let text = NSStackView(views: [top, details, warning])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        let row = NSStackView(views: [icon, text])
        row.alignment = .top
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        textField = title
        imageView = icon
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            top.widthAnchor.constraint(equalTo: text.widthAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            row.topAnchor.constraint(equalTo: topAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show(_ item: ContentsItem) {
        icon.image = item.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        icon.isHidden = item.symbol == nil
        title.stringValue = item.title
        trailing.stringValue = item.trailing ?? ""
        trailing.isHidden = item.trailing == nil
        details.stringValue = item.details.joined(separator: "\n")
        details.isHidden = item.details.isEmpty
        warning.stringValue = item.warning.map { "⚠︎ " + $0 } ?? ""
        warning.isHidden = item.warning == nil
        toolTip = item.tooltip
    }
}
