import SwiftUI
import AppKit

/// High-performance, virtualized AppKit Table of Contents outline view.
/// Recycles table cells and completely eliminates SwiftUI FocusStoreList memory overhead.
public struct PDFOutlineNSView: NSViewRepresentable {
    let outline: [PDFOutlineNode]
    // Identifies which document `outline` belongs to (its file path) — see setOutline's use of
    // this for why a plain node-count comparison isn't enough to detect a document switch.
    let documentIdentity: String
    let onSelect: (Int) -> Void

    public init(outline: [PDFOutlineNode], documentIdentity: String, onSelect: @escaping (Int) -> Void) {
        self.outline = outline
        self.documentIdentity = documentIdentity
        self.onSelect = onSelect
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }
    
    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView(frame: .zero)
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        let outlineView = NSOutlineView(frame: .zero)
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
        context.coordinator.setOutline(outline, documentIdentity: documentIdentity)

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.onSelect = onSelect
        context.coordinator.setOutline(outline, documentIdentity: documentIdentity)
    }

    @MainActor
    public final class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var onSelect: (Int) -> Void
        weak var outlineView: NSOutlineView?
        private var rootItems: [OutlineItemWrapper] = []
        private var lastDocumentIdentity: String?

        init(onSelect: @escaping (Int) -> Void) {
            self.onSelect = onSelect
        }

        // Skips the reloadData()/expandItem() pass below when nothing has actually changed —
        // updateNSView(_:context:) runs on every SwiftUI re-render of the containing view (e.g.
        // every page/zoom change), not only when the outline itself changes, so this guard matters
        // for avoiding needless work on every scroll. Compares document identity (the file path)
        // rather than nodes.count, since two different documents can easily share the same
        // top-level section count.
        func setOutline(_ nodes: [PDFOutlineNode], documentIdentity: String) {
            if documentIdentity == lastDocumentIdentity && !rootItems.isEmpty {
                return
            }
            lastDocumentIdentity = documentIdentity
            rootItems = nodes.map { OutlineItemWrapper(node: $0) }

            // Deferred to the next run loop turn, never called synchronously from
            // updateNSView(_:context:): reloadData()/expandItem() can trigger a
            // synchronous layout pass that loops back into another SwiftUI update
            // before this call returns, which AppKit surfaces as "reentrant
            // operation in its NSTableView delegate" — a warning today, but it
            // silently corrupts the outline view's internal row/view-recycling
            // state, which crashes unpredictably later (a generic, unsymbolicated
            // autorelease-pool-drain SIGSEGV, disconnected from this call site).
            DispatchQueue.main.async { [weak self] in
                guard let self, let outlineView = self.outlineView else { return }
                outlineView.reloadData()

                // Expand first level items for immediate usability
                for item in self.rootItems where !item.children.isEmpty {
                    outlineView.expandItem(item)
                }
            }
        }
        
        // MARK: - NSOutlineViewDataSource
        
        public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return rootItems.count
            }
            if let wrapper = item as? OutlineItemWrapper {
                return wrapper.children.count
            }
            return 0
        }
        
        public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return rootItems[index]
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
            var cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: nil) as? NSTableCellView
            
            if cell == nil {
                cell = NSTableCellView()
                cell?.identifier = cellIdentifier
                
                let tf = NSTextField(labelWithString: "")
                tf.lineBreakMode = .byTruncatingTail
                tf.font = NSFont.systemFont(ofSize: 12)
                tf.translatesAutoresizingMaskIntoConstraints = false
                cell?.addSubview(tf)
                cell?.textField = tf
                
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: cell!.leadingAnchor, constant: 4),
                    tf.trailingAnchor.constraint(equalTo: cell!.trailingAnchor, constant: -4),
                    tf.centerYAnchor.constraint(equalTo: cell!.centerYAnchor)
                ])
            }
            
            if let page = wrapper.node.targetPage {
                cell?.textField?.stringValue = "\(wrapper.node.title)  (\(page + 1))"
            } else {
                cell?.textField?.stringValue = wrapper.node.title
            }
            
            return cell
        }
        
        public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            return true
        }
        
        public func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let row = outlineView.selectedRow
            guard row >= 0, let wrapper = outlineView.item(atRow: row) as? OutlineItemWrapper, let page = wrapper.node.targetPage else { return }
            DispatchQueue.main.async { [weak self] in
                self?.onSelect(page)
            }
        }
        
        @objc func onOutlineClick(_ sender: NSOutlineView) {
            let row = sender.clickedRow
            guard row >= 0 else { return }
            if let wrapper = sender.item(atRow: row) as? OutlineItemWrapper, let page = wrapper.node.targetPage {
                DispatchQueue.main.async { [weak self] in
                    self?.onSelect(page)
                }
            }
        }
    }
}

/// Class wrapper around PDFOutlineNode for standard AppKit outline data source identity
final class OutlineItemWrapper: NSObject {
    let node: PDFOutlineNode
    let children: [OutlineItemWrapper]
    
    init(node: PDFOutlineNode) {
        self.node = node
        self.children = node.children.map { OutlineItemWrapper(node: $0) }
        super.init()
    }
}
