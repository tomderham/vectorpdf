import SwiftUI
import AppKit

/// High-performance, virtualized AppKit Table of Contents outline view.
/// Recycles table cells and supports in-ToC search filtering and active section highlighting.
public struct PDFOutlineNSView: NSViewRepresentable {
    let outline: [PDFOutlineNode]
    let documentIdentity: String
    let searchQuery: String
    let currentPage: Int
    let viewModel: PDFViewerViewModel?
    let onSelect: (Int) -> Void

    public init(
        outline: [PDFOutlineNode],
        documentIdentity: String,
        searchQuery: String = "",
        currentPage: Int = 0,
        viewModel: PDFViewerViewModel? = nil,
        onSelect: @escaping (Int) -> Void
    ) {
        self.outline = outline
        self.documentIdentity = documentIdentity
        self.searchQuery = searchQuery
        self.currentPage = currentPage
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
            currentPage: currentPage
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
            currentPage: currentPage
        )
    }

    @MainActor
    public final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var onSelect: (Int) -> Void
        var viewModel: PDFViewerViewModel?
        weak var outlineView: NSOutlineView?
        weak var emptyLabel: NSTextField?

        private var rawOutline: [PDFOutlineNode] = []
        private var displayedWrappers: [OutlineItemWrapper] = []
        private var lastDocumentIdentity: String?
        private var lastSearchQuery: String?
        private var currentPage: Int = 0
        private var currentVisibleActiveWrapper: OutlineItemWrapper?
        private var selectedNodeId: UUID?
        private var selectedNodePage: Int?
        private var searchWorkItem: DispatchWorkItem?

        init(viewModel: PDFViewerViewModel?, onSelect: @escaping (Int) -> Void) {
            self.viewModel = viewModel
            self.onSelect = onSelect
        }

        func updateState(outline: [PDFOutlineNode], documentIdentity: String, searchQuery: String, currentPage: Int) {
            let documentChanged = (documentIdentity != self.lastDocumentIdentity)
            let searchChanged = (searchQuery != self.lastSearchQuery)
            let pageChanged = (currentPage != self.currentPage)

            if pageChanged {
                if let selPage = selectedNodePage, currentPage != selPage {
                    self.selectedNodeId = nil
                    self.selectedNodePage = nil
                }
            }

            self.lastDocumentIdentity = documentIdentity
            self.lastSearchQuery = searchQuery
            self.currentPage = currentPage
            self.rawOutline = outline

            if documentChanged {
                searchWorkItem?.cancel()
                let isSearching = !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                rebuildDisplayedItems(expandAll: isSearching, scrollToActive: true)
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
            } else if pageChanged {
                refreshActiveIndicators(scrollToVisible: true)
            }
        }

        private func rebuildDisplayedItems(expandAll: Bool, scrollToActive: Bool) {
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
                } else {
                    for item in self.displayedWrappers where !item.children.isEmpty {
                        outlineView.expandItem(item)
                    }
                }

                self.refreshActiveIndicators(scrollToVisible: scrollToActive)
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
                self?.onSelect(page)
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
                    self?.onSelect(page)
                }
            }
        }

        func contextMenu(for node: PDFOutlineNode) -> NSMenu? {
            guard let viewModel = viewModel else { return nil }

            if let _ = node.targetPage {
                let menu = NSMenu(title: "Table of Contents")

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

                return menu
            }

            if let uri = node.uri, (uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("mailto:")), let url = URL(string: uri) {
                let menu = NSMenu(title: "Link")
                let openLinkItem = NSMenuItem(title: "Open Link", action: #selector(openLinkAction(_:)), keyEquivalent: "")
                openLinkItem.image = NSImage(systemSymbolName: "safari", accessibilityDescription: nil)
                openLinkItem.target = self
                openLinkItem.representedObject = url
                menu.addItem(openLinkItem)
                return menu
            }

            return nil
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
