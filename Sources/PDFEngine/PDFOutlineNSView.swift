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

/// High-performance, virtualized AppKit Table of Contents outline view.
/// Recycles table cells and supports in-ToC search filtering and active section highlighting.
public struct PDFOutlineNSView: NSViewRepresentable {
    let outline: [PDFOutlineNode]
    let documentIdentity: String
    let searchQuery: String
    let currentPage: Int
    /// The section under the reading line, which is followed in preference to the page alone.
    let readingSection: PDFViewerViewModel.ReadingSection?
    let viewModel: PDFViewerViewModel?
    let onSelect: (PDFOutlineNode) -> Void

    public init(
        outline: [PDFOutlineNode],
        documentIdentity: String,
        searchQuery: String = "",
        currentPage: Int = 0,
        readingSection: PDFViewerViewModel.ReadingSection? = nil,
        viewModel: PDFViewerViewModel? = nil,
        onSelect: @escaping (PDFOutlineNode) -> Void
    ) {
        self.outline = outline
        self.documentIdentity = documentIdentity
        self.searchQuery = searchQuery
        self.currentPage = currentPage
        self.readingSection = readingSection
        self.viewModel = viewModel
        self.onSelect = onSelect
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel, onSelect: onSelect)
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        let outlineView = CustomOutlineView(frame: .zero)
        outlineView.coordinator = context.coordinator
        // Entries are dragged to reorder and nest them.
        outlineView.registerForDraggedTypes([.outlineEntry])
        outlineView.setDraggingSourceOperationMask(.move, forLocal: true)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("OutlineColumn"))
        column.title = "Contents"
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .small
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        
        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator
        outlineView.target = context.coordinator
        outlineView.action = #selector(Coordinator.onOutlineClick(_:))
        
        scrollView.documentView = outlineView
        context.coordinator.outlineView = outlineView

        let emptyLabel = NSTextField(labelWithString: "No matching outline sections")
        emptyLabel.font = NSFont.systemFont(ofSize: 12)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(emptyLabel)
        context.coordinator.emptyLabel = emptyLabel
        
        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor, constant: -20),
            emptyLabel.leadingAnchor.constraint(greaterThanOrEqualTo: scrollView.leadingAnchor, constant: 16),
            emptyLabel.trailingAnchor.constraint(lessThanOrEqualTo: scrollView.trailingAnchor, constant: -16)
        ])
        
        context.coordinator.updateState(
            outline: outline,
            documentIdentity: documentIdentity,
            searchQuery: searchQuery,
            currentPage: currentPage,
            readingSection: readingSection
        )

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.viewModel = viewModel
        context.coordinator.updateState(
            outline: outline,
            documentIdentity: documentIdentity,
            searchQuery: searchQuery,
            currentPage: currentPage,
            readingSection: readingSection
        )
    }

    @MainActor
    public final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var onSelect: (PDFOutlineNode) -> Void
        var viewModel: PDFViewerViewModel?
        weak var outlineView: NSOutlineView?
        weak var emptyLabel: NSTextField?

        private var rawOutline: [PDFOutlineNode] = []
        private var displayedWrappers: [OutlineItemWrapper] = []
        private var lastDocumentIdentity: String?
        private var lastSearchQuery: String?
        private var currentPage: Int = 0
        private var readingSection: PDFViewerViewModel.ReadingSection?
        private var currentVisibleActiveWrapper: OutlineItemWrapper?
        private var selectedNodeId: UUID?
        private var selectedNodePage: Int?
        private var searchWorkItem: DispatchWorkItem?

        init(viewModel: PDFViewerViewModel?, onSelect: @escaping (PDFOutlineNode) -> Void) {
            self.viewModel = viewModel
            self.onSelect = onSelect
        }

        func updateState(outline: [PDFOutlineNode], documentIdentity: String, searchQuery: String, currentPage: Int, readingSection: PDFViewerViewModel.ReadingSection? = nil) {
            let documentChanged = (documentIdentity != self.lastDocumentIdentity)
            let previousIdentity = self.lastDocumentIdentity
            let searchChanged = (searchQuery != self.lastSearchQuery)
            let pageChanged = (currentPage != self.currentPage)
            let sectionChanged = (readingSection != self.readingSection)

            if pageChanged {
                if let selPage = selectedNodePage, currentPage != selPage {
                    self.selectedNodeId = nil
                    self.selectedNodePage = nil
                    // Drop the clicked row's highlight too, or it outshines the active indicator
                    // and reads as the ToC not following the page.
                    outlineView?.deselectAll(nil)
                }
            }

            self.lastDocumentIdentity = documentIdentity
            self.lastSearchQuery = searchQuery
            self.currentPage = currentPage
            self.readingSection = readingSection
            self.rawOutline = outline

            if documentChanged {
                searchWorkItem?.cancel()
                let isSearching = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                // The same document's outline, edited: what was open stays open.
                let sameFile = previousIdentity.map { Self.file(of: $0) == Self.file(of: documentIdentity) } ?? false
                rebuildDisplayedItems(expandAll: isSearching, scrollToActive: !sameFile, keepingOpen: sameFile && !isSearching ? openTitlePaths() : nil)
            } else if searchChanged {
                searchWorkItem?.cancel()
                let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    // Instant response when clearing search
                    rebuildDisplayedItems(expandAll: false, scrollToActive: true)
                } else {
                    // 100ms debounce while user is typing
                    let workItem = DispatchWorkItem { [weak self] in
                        self?.rebuildDisplayedItems(expandAll: true, scrollToActive: false)
                    }
                    self.searchWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.10, execute: workItem)
                }
            } else if pageChanged || sectionChanged {
                refreshActiveIndicators(scrollToVisible: true)
            }
        }

        private static func file(of identity: String) -> Substring {
            identity.split(separator: "#").first ?? ""
        }

        /// The entries that had entries inside them before an edit, by title path.
        private var hadChildren = Set<[String]>()

        /// The entries open in the outline, each by its title and those of the entries it's in;
        /// notes those with entries inside them in `hadChildren`.
        private func openTitlePaths() -> Set<[String]> {
            guard let outlineView else { return [] }
            var open = Set<[String]>()
            hadChildren = []
            func visit(_ wrappers: [OutlineItemWrapper], _ titles: [String]) {
                for wrapper in wrappers where !wrapper.children.isEmpty {
                    let path = titles + [wrapper.node.title]
                    hadChildren.insert(path)
                    if outlineView.isItemExpanded(wrapper) { open.insert(path) }
                    visit(wrapper.children, path)
                }
            }
            visit(displayedWrappers, [])
            return open
        }

        private func rebuildDisplayedItems(expandAll: Bool, scrollToActive: Bool, keepingOpen: Set<[String]>? = nil) {
            let query = lastSearchQuery ?? ""
            let filteredNodes = PDFOutlineNode.filter(nodes: rawOutline, query: query)
            displayedWrappers = filteredNodes.map { OutlineItemWrapper(node: $0) }

            let isEmptyResult = displayedWrappers.isEmpty && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            emptyLabel?.isHidden = !isEmptyResult

            DispatchQueue.main.async { [weak self] in
                guard let self = self, let outlineView = self.outlineView else { return }
                outlineView.reloadData()

                if expandAll {
                    self.expandAllMatchingItems(in: self.displayedWrappers, in: outlineView)
                } else if let keepingOpen {
                    self.reopen(self.displayedWrappers, titles: [], keepingOpen: keepingOpen, in: outlineView)
                } else {
                    for item in self.displayedWrappers where !item.children.isEmpty {
                        outlineView.expandItem(item)
                    }
                }

                self.refreshActiveIndicators(scrollToVisible: scrollToActive)
            }
        }

        /// Opens the entries in `keepingOpen`, and those just given entries inside them.
        private func reopen(_ wrappers: [OutlineItemWrapper], titles: [String], keepingOpen: Set<[String]>, in outlineView: NSOutlineView) {
            for wrapper in wrappers where !wrapper.children.isEmpty {
                let path = titles + [wrapper.node.title]
                if keepingOpen.contains(path) || !hadChildren.contains(path) {
                    outlineView.expandItem(wrapper)
                    reopen(wrapper.children, titles: path, keepingOpen: keepingOpen, in: outlineView)
                }
            }
        }

        private func expandAllMatchingItems(in wrappers: [OutlineItemWrapper], in outlineView: NSOutlineView) {
            for item in wrappers {
                if !item.children.isEmpty {
                    outlineView.expandItem(item)
                    expandAllMatchingItems(in: item.children, in: outlineView)
                }
            }
        }

        func refreshActiveIndicators(scrollToVisible: Bool = false) {
            guard let outlineView = outlineView else { return }
            let activeId: UUID?
            if let selId = selectedNodeId, selectedNodePage == currentPage {
                activeId = selId
            } else if let reading = readingSection, reading.page == currentPage {
                // Where on the page matters: a section starting partway down one page and ending
                // before the next section heading on the following page is never the first entry
                // on either page.
                activeId = reading.nodeId
            } else {
                activeId = PDFOutlineNode.findActiveNodeId(in: rawOutline, for: currentPage)
            }

            var targetWrapper: OutlineItemWrapper? = nil
            if let activeId = activeId {
                targetWrapper = findWrapper(by: activeId, in: displayedWrappers)
            }

            // Reveal active item by expanding any collapsed ancestors
            if scrollToVisible, let target = targetWrapper {
                revealItem(target, in: outlineView)
            }

            var visibleActiveWrapper: OutlineItemWrapper? = nil
            if let target = targetWrapper {
                visibleActiveWrapper = findVisibleItem(for: target, in: outlineView)
            }

            self.currentVisibleActiveWrapper = visibleActiveWrapper

            let numRows = outlineView.numberOfRows
            guard numRows > 0 else { return }
            for row in 0..<numRows {
                guard let cellView = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false) as? OutlineCellView,
                      let itemWrapper = outlineView.item(atRow: row) as? OutlineItemWrapper else {
                    continue
                }
                let isActive = (visibleActiveWrapper === itemWrapper)
                let isSelected = (outlineView.selectedRow == row)
                cellView.setActive(isActive, isRowSelected: isSelected)
            }

            // Scroll so the current active section is comfortably visible on screen
            if scrollToVisible, let visibleWrapper = visibleActiveWrapper {
                let row = outlineView.row(forItem: visibleWrapper)
                if row >= 0 {
                    let rowRect = outlineView.rect(ofRow: row)
                    let visibleRect = outlineView.visibleRect
                    if !visibleRect.contains(rowRect) {
                        let paddedRect = rowRect.insetBy(dx: 0, dy: -24)
                        outlineView.scrollToVisible(paddedRect)
                    }
                }
            }
        }

        private func revealItem(_ wrapper: OutlineItemWrapper, in outlineView: NSOutlineView) {
            var ancestors: [OutlineItemWrapper] = []
            var cur = wrapper.parent
            while let p = cur {
                ancestors.append(p)
                cur = p.parent
            }
            for ancestor in ancestors.reversed() {
                if !outlineView.isItemExpanded(ancestor) {
                    outlineView.expandItem(ancestor)
                }
            }
        }

        private func findWrapper(by id: UUID, in wrappers: [OutlineItemWrapper]) -> OutlineItemWrapper? {
            for wrapper in wrappers {
                if wrapper.node.id == id {
                    return wrapper
                }
                if let found = findWrapper(by: id, in: wrapper.children) {
                    return found
                }
            }
            return nil
        }

        private func findVisibleItem(for wrapper: OutlineItemWrapper, in outlineView: NSOutlineView) -> OutlineItemWrapper? {
            var current: OutlineItemWrapper? = wrapper
            while let c = current {
                if outlineView.row(forItem: c) >= 0 {
                    return c
                }
                current = c.parent
            }
            return nil
        }
        
        // MARK: - NSOutlineViewDataSource
        
        public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return displayedWrappers.count
            }
            if let wrapper = item as? OutlineItemWrapper {
                return wrapper.children.count
            }
            return 0
        }
        
        public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return displayedWrappers[index]
            }
            if let wrapper = item as? OutlineItemWrapper {
                return wrapper.children[index]
            }
            fatalError("Invalid item hierarchy")
        }
        
        public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            if let wrapper = item as? OutlineItemWrapper {
                return !wrapper.children.isEmpty
            }
            return false
        }
        
        // MARK: - NSOutlineViewDelegate
        
        public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let wrapper = item as? OutlineItemWrapper else { return nil }
            
            let cellIdentifier = NSUserInterfaceItemIdentifier("OutlineCell")
            var cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: nil) as? OutlineCellView
            
            if cell == nil {
                cell = OutlineCellView()
                cell?.identifier = cellIdentifier
            }
            
            let row = outlineView.row(forItem: item)
            let isSelected = (row >= 0 && outlineView.selectedRow == row)
            let isActive = (wrapper === currentVisibleActiveWrapper)

            cell?.configure(
                title: wrapper.node.title,
                targetPage: wrapper.node.targetPage,
                isActive: isActive,
                isRowSelected: isSelected
            )
            
            return cell
        }
        
        public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            return true
        }
        
        public func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let row = outlineView.selectedRow
            guard row >= 0, let wrapper = outlineView.item(atRow: row) as? OutlineItemWrapper, let page = wrapper.node.targetPage else {
                refreshActiveIndicators()
                return
            }
            self.selectedNodeId = wrapper.node.id
            self.selectedNodePage = page
            refreshActiveIndicators(scrollToVisible: false)
            DispatchQueue.main.async { [weak self] in
                self?.onSelect(wrapper.node)
            }
        }

        public func outlineViewItemDidExpand(_ notification: Notification) {
            refreshActiveIndicators()
        }

        public func outlineViewItemDidCollapse(_ notification: Notification) {
            refreshActiveIndicators()
        }
        
        @objc func onOutlineClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0 else { return }
            if let wrapper = sender.item(atRow: row) as? OutlineItemWrapper, let page = wrapper.node.targetPage {
                self.selectedNodeId = wrapper.node.id
                self.selectedNodePage = page
                refreshActiveIndicators(scrollToVisible: false)
                DispatchQueue.main.async { [weak self] in
                    self?.onSelect(wrapper.node)
                }
            }
        }

        func contextMenu(for node: PDFOutlineNode) -> NSMenu? {
            guard let viewModel = viewModel else { return nil }
            let menu = NSMenu(title: "Table of Contents")

            if node.targetPage != nil {
                if !viewModel.isTransientWindow {
                    let snapItem = NSMenuItem(title: "Create Anchor", action: #selector(snapshotNodeAction(_:)), keyEquivalent: "")
                    snapItem.image = NSImage.anchorIcon
                    snapItem.target = self
                    snapItem.representedObject = node
                    menu.addItem(snapItem)

                    let snapAndOpenItem = NSMenuItem(title: "Create Anchor and Open in New Window", action: #selector(snapshotAndOpenNodeAction(_:)), keyEquivalent: "")
                    snapAndOpenItem.image = NSImage.anchorIcon
                    snapAndOpenItem.target = self
                    snapAndOpenItem.representedObject = node
                    menu.addItem(snapAndOpenItem)

                    menu.addItem(NSMenuItem.separator())
                }

                let openItem = NSMenuItem(title: "Open in New Window", action: #selector(openNodeInNewWindowAction(_:)), keyEquivalent: "")
                openItem.image = NSImage(systemSymbolName: "macwindow.badge.plus", accessibilityDescription: nil)
                openItem.target = self
                openItem.representedObject = node
                menu.addItem(openItem)
            } else if let uri = node.uri, (uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("mailto:")), let url = URL(string: uri) {
                let openLinkItem = NSMenuItem(title: "Open Link", action: #selector(openLinkAction(_:)), keyEquivalent: "")
                openLinkItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
                openLinkItem.target = self
                openLinkItem.representedObject = url
                menu.addItem(openLinkItem)
            }

            // Editing, only on the whole outline: a filtered one hides where entries would go.
            if viewModel.canEditOutline, (lastSearchQuery ?? "").isEmpty, !viewModel.isTransientWindow {
                if !menu.items.isEmpty { menu.addItem(.separator()) }
                func add(_ title: String, _ action: Selector, enabled: Bool = true) {
                    let item = NSMenuItem(title: title, action: enabled ? action : nil, keyEquivalent: "")
                    item.target = self
                    item.representedObject = node
                    menu.addItem(item)
                }
                add("Add Entry After", #selector(addAfterAction(_:)))
                add("Add Entry Inside", #selector(addInsideAction(_:)))
                add("Rename…", #selector(renameAction(_:)))
                add("Go Here Instead", #selector(repointAction(_:)))
                menu.addItem(.separator())
                add("Move Up", #selector(moveUpAction(_:)), enabled: viewModel.canMoveOutlineEntry(node, .up))
                add("Move Down", #selector(moveDownAction(_:)), enabled: viewModel.canMoveOutlineEntry(node, .down))
                add("Indent", #selector(indentAction(_:)), enabled: viewModel.canMoveOutlineEntry(node, .indent))
                add("Outdent", #selector(outdentAction(_:)), enabled: viewModel.canMoveOutlineEntry(node, .outdent))
                menu.addItem(.separator())
                add("Delete Entry", #selector(deleteAction(_:)))
                menu.addItem(.separator())
                add("Build Outline from Headings…", #selector(buildFromHeadingsAction(_:)))
            }
            return menu.items.isEmpty ? nil : menu
        }

        private func node(_ sender: NSMenuItem) -> PDFOutlineNode? { sender.representedObject as? PDFOutlineNode }
        @objc private func addAfterAction(_ sender: NSMenuItem) { viewModel?.promptToAddOutlineEntry(near: node(sender)) }
        @objc private func addInsideAction(_ sender: NSMenuItem) { viewModel?.promptToAddOutlineEntry(near: node(sender), asChild: true) }
        @objc private func renameAction(_ sender: NSMenuItem) { node(sender).map { viewModel?.promptToRenameOutlineEntry($0) } }
        @objc private func repointAction(_ sender: NSMenuItem) { node(sender).map { viewModel?.setOutlineEntryToCurrentPlace($0) } }
        @objc private func moveUpAction(_ sender: NSMenuItem) { node(sender).map { viewModel?.moveOutlineEntry($0, .up) } }
        @objc private func moveDownAction(_ sender: NSMenuItem) { node(sender).map { viewModel?.moveOutlineEntry($0, .down) } }
        @objc private func indentAction(_ sender: NSMenuItem) { node(sender).map { viewModel?.moveOutlineEntry($0, .indent) } }
        @objc private func outdentAction(_ sender: NSMenuItem) { node(sender).map { viewModel?.moveOutlineEntry($0, .outdent) } }
        @objc private func buildFromHeadingsAction(_ sender: NSMenuItem) {
            guard let viewModel else { return }
            Task { await viewModel.buildOutlineFromHeadings() }
        }
        @objc private func deleteAction(_ sender: NSMenuItem) { node(sender).map { viewModel?.deleteOutlineEntry($0) } }

        // MARK: Dragging entries

        private var canDragEntries: Bool {
            viewModel?.canEditOutline == true && (lastSearchQuery ?? "").isEmpty && viewModel?.isTransientWindow == false
        }

        public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
            guard canDragEntries, let wrapper = item as? OutlineItemWrapper else { return nil }
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(wrapper.node.id.uuidString, forType: .outlineEntry)
            return pasteboardItem
        }

        private func draggedNode(_ info: NSDraggingInfo) -> PDFOutlineNode? {
            guard let string = info.draggingPasteboard.string(forType: .outlineEntry), let id = UUID(uuidString: string),
                  let path = rawOutline.path(of: id) else { return nil }
            return rawOutline.node(at: path)
        }

        /// The place a drop at `index` in `item` stands for, in the outline as it is.
        private func dropPath(item: Any?, index: Int) -> OutlinePath? {
            if let wrapper = item as? OutlineItemWrapper {
                guard let parent = rawOutline.path(of: wrapper.node.id) else { return nil }
                return parent + [index == NSOutlineViewDropOnItemIndex ? wrapper.node.children.count : index]
            }
            return [index == NSOutlineViewDropOnItemIndex ? rawOutline.count : index]
        }

        public func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
            guard canDragEntries, info.draggingSource as? NSOutlineView === outlineView,
                  let node = draggedNode(info), let source = rawOutline.path(of: node.id),
                  let destination = dropPath(item: item, index: index),
                  !destination.starts(with: source) else { return [] }
            return .move
        }

        public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
            guard canDragEntries, let node = draggedNode(info), let destination = dropPath(item: item, index: index) else { return false }
            DispatchQueue.main.async { [weak self] in self?.viewModel?.moveOutlineEntry(node, to: destination) }
            return true
        }

        @objc private func snapshotNodeAction(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? PDFOutlineNode else { return }
            viewModel?.addSnapshot(from: node)
        }

        @objc private func snapshotAndOpenNodeAction(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? PDFOutlineNode else { return }
            viewModel?.addSnapshotAndOpenInNewWindow(from: node)
        }

        @objc private func openNodeInNewWindowAction(_ sender: NSMenuItem) {
            guard let node = sender.representedObject as? PDFOutlineNode else { return }
            viewModel?.openSnapshotInNewWindow(from: node)
        }

        @objc private func openLinkAction(_ sender: NSMenuItem) {
            guard let url = sender.representedObject as? URL else { return }
            PDFViewerAppCoordinator.shared.openExternalURL(url)
        }
    }
}

/// Custom NSTableCellView with subtle current-page active section indicator and background styling.
final class OutlineCellView: NSTableCellView {
    let indicatorBar = NSView()
    let backgroundPill = NSView()

    private(set) var isActive: Bool = false
    private(set) var isRowSelected: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    private func setupViews() {
        wantsLayer = true

        backgroundPill.wantsLayer = true
        backgroundPill.layer?.cornerRadius = 4
        backgroundPill.layer?.masksToBounds = true
        backgroundPill.translatesAutoresizingMaskIntoConstraints = false
        addSubview(backgroundPill)

        indicatorBar.wantsLayer = true
        indicatorBar.layer?.cornerRadius = 1.5
        indicatorBar.layer?.masksToBounds = true
        indicatorBar.translatesAutoresizingMaskIntoConstraints = false
        addSubview(indicatorBar)

        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        tf.font = NSFont.systemFont(ofSize: 12)
        tf.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tf)
        self.textField = tf

        NSLayoutConstraint.activate([
            backgroundPill.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 1),
            backgroundPill.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -1),
            backgroundPill.topAnchor.constraint(equalTo: topAnchor, constant: 1),
            backgroundPill.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1),

            indicatorBar.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            indicatorBar.centerYAnchor.constraint(equalTo: centerYAnchor),
            indicatorBar.widthAnchor.constraint(equalToConstant: 3),
            indicatorBar.heightAnchor.constraint(equalToConstant: 14),

            tf.leadingAnchor.constraint(equalTo: indicatorBar.trailingAnchor, constant: 5),
            tf.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])

        updateAppearance()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    func configure(title: String, targetPage: Int?, isActive: Bool, isRowSelected: Bool) {
        if let page = targetPage {
            textField?.stringValue = "\(title)  (\(page + 1))"
        } else {
            textField?.stringValue = title
        }
        setActive(isActive, isRowSelected: isRowSelected)
    }

    func setActive(_ isActive: Bool, isRowSelected: Bool) {
        self.isActive = isActive
        self.isRowSelected = isRowSelected
        updateAppearance()
    }

    private func updateAppearance() {
        if isActive {
            indicatorBar.isHidden = false
            if isRowSelected {
                indicatorBar.layer?.backgroundColor = NSColor.white.cgColor
                backgroundPill.layer?.backgroundColor = NSColor.clear.cgColor
                textField?.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
            } else {
                indicatorBar.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
                backgroundPill.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
                textField?.font = NSFont.systemFont(ofSize: 12, weight: .medium)
            }
        } else {
            indicatorBar.isHidden = true
            backgroundPill.layer?.backgroundColor = NSColor.clear.cgColor
            textField?.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        }
    }
}

/// Custom NSOutlineView that provides contextual menus for outline nodes without changing page selection.
final class CustomOutlineView: NSOutlineView {
    weak var coordinator: PDFOutlineNSView.Coordinator?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = self.row(at: point)
        guard row >= 0, let wrapper = item(atRow: row) as? OutlineItemWrapper else {
            return nil
        }
        return coordinator?.contextMenu(for: wrapper.node)
    }
}

extension NSPasteboard.PasteboardType {
    /// An outline entry being dragged within the outline.
    static let outlineEntry = NSPasteboard.PasteboardType("com.thomasderham.vectorpdf.outline-entry")
}

/// Class wrapper around PDFOutlineNode for standard AppKit outline data source identity and parent tracking.
final class OutlineItemWrapper: NSObject {
    let node: PDFOutlineNode
    let children: [OutlineItemWrapper]
    weak var parent: OutlineItemWrapper?

    init(node: PDFOutlineNode, parent: OutlineItemWrapper? = nil) {
        self.node = node
        self.parent = parent
        let builtChildren = node.children.map { OutlineItemWrapper(node: $0) }
        self.children = builtChildren
        super.init()
        for child in builtChildren {
            child.parent = self
        }
    }
}
