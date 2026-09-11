import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Modern macOS hero drop zone replacing the solitary "Open PDF..." button.
/// Users can drag PDF files directly into this area or click anywhere to choose a file.
/// Typography and visual scale align with the sidebar pane for Agent and Snapshots.
struct HeroDropZoneView: View {
    let onChooseFile: () -> Void
    let onDropURLs: ([URL]) -> Void

    @State private var isTargeted = false
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(Color.accentColor.opacity(isTargeted ? 0.25 : 0.12))
                    .frame(width: 56, height: 56)

                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.badge.plus")
                    .font(.system(size: 28))
                    .foregroundStyle(Color.accentColor)
                    .symbolEffect(.bounce, value: isTargeted)
            }

            VStack(spacing: 4) {
                Text(isTargeted ? "Drop PDF to Open" : "Drop PDF here to open")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("or click anywhere to choose a file")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 5) {
                Text("Shortcut:")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Text("⌘O")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 24)
        .frame(maxWidth: 480)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isTargeted ? AnyShapeStyle(Color.accentColor.opacity(0.08)) : (isHovered ? AnyShapeStyle(Color.primary.opacity(0.03)) : AnyShapeStyle(.ultraThinMaterial)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.primary.opacity(isHovered ? 0.20 : 0.10),
                            style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: isTargeted ? [] : [6, 4])
                        )
                )
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            onChooseFile()
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let u = item as? URL {
                        url = u
                    } else if let d = item as? Data {
                        url = URL(dataRepresentation: d, relativeTo: nil)
                    } else {
                        url = nil
                    }
                    guard let fileURL = url, fileURL.pathExtension.lowercased() == "pdf" else { return }
                    Task { @MainActor in
                        onDropURLs([fileURL])
                    }
                }
            }
            return true
        }
    }
}

/// A single Favorite, Tab Group, or Recent entry on the empty-window "Start" screen.
/// Tap anywhere to open, right-click for native context actions, or hover to reveal the safe action menu on the right.
struct StartScreenRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    var filePath: String? = nil
    let onOpen: () -> Void
    var onOpenInNewTab: (() -> Void)? = nil
    var onOpenInNewWindow: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil
    var removeLabel: String = "Remove"

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .font(.system(size: 14))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            // Trailing action menu: aligned on the far right of the tab, revealed on hover
            if onRemove != nil || onOpenInNewTab != nil || onOpenInNewWindow != nil || filePath != nil {
                Menu {
                    Button("Open") { onOpen() }
                    if let onOpenInNewTab {
                        Button("Open in New Tab") { onOpenInNewTab() }
                    }
                    if let onOpenInNewWindow {
                        Button("Open in New Window") { onOpenInNewWindow() }
                    }
                    if let path = filePath {
                        Button("Show in Finder") {
                            NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                        }
                    }
                    if let onRemove {
                        Divider()
                        Button(role: .destructive, action: onRemove) {
                            Label(removeLabel, systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(width: 24, height: 24)
                .opacity(isHovered ? 1.0 : 0.0)
                .allowsHitTesting(isHovered)
                .help("Options")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isHovered ? AnyShapeStyle(Color.primary.opacity(0.04)) : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(isHovered ? 0.12 : 0.06), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
        .contextMenu {
            Button("Open") { onOpen() }
            if let onOpenInNewTab {
                Button("Open in New Tab") { onOpenInNewTab() }
            }
            if let onOpenInNewWindow {
                Button("Open in New Window") { onOpenInNewWindow() }
            }
            if let path = filePath {
                Button("Show in Finder") {
                    NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                }
            }
            if let onRemove {
                Divider()
                Button(role: .destructive, action: onRemove) {
                    Label(removeLabel, systemImage: "trash")
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}

/// Floating Undo Toast notification banner shown when an item is removed.
struct UndoToastView: View {
    let message: String
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.primary)

            Button("Undo") {
                onUndo()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.accentColor)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(.regularMaterial)
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
        )
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Native AppKit NSSearchField wrapper that guarantees focus and first responder handling
public struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onCommit: () -> Void
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    
    public init(
        text: Binding<String>,
        placeholder: String = "Search document...",
        onCommit: @escaping () -> Void,
        onNext: (() -> Void)? = nil,
        onPrevious: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.onCommit = onCommit
        self.onNext = onNext
        self.onPrevious = onPrevious
    }
    
    public func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField(frame: .zero)
        field.placeholderString = placeholder
        field.stringValue = text
        field.target = context.coordinator
        field.action = #selector(Coordinator.action(_:))
        field.delegate = context.coordinator
        field.focusRingType = .exterior
        field.bezelStyle = .roundedBezel
        field.sendsWholeSearchString = true
        (field.cell as? NSSearchFieldCell)?.sendsWholeSearchString = true
        field.sendsSearchStringImmediately = false
        (field.cell as? NSSearchFieldCell)?.sendsSearchStringImmediately = false
        context.coordinator.searchField = field
        context.coordinator.focusAndSelectText()
        return field
    }
    
    public func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.searchField = nsView
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    @MainActor
    public class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField
        weak var searchField: NSSearchField?
        
        init(_ parent: NativeSearchField) {
            self.parent = parent
            super.init()
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleFocusSearch(_:)),
                name: .focusSearchCommand,
                object: nil
            )
        }
        
        deinit {
            NotificationCenter.default.removeObserver(self)
        }
        
        @objc func handleFocusSearch(_ notification: Notification) {
            focusAndSelectText()
        }
        
        func focusAndSelectText() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let field = self.searchField else { return }
                
                @MainActor func performFocus(on targetField: NSSearchField) {
                    guard let window = targetField.window else { return }
                    guard window.isKeyWindow || NSApplication.shared.keyWindow == window else { return }
                    window.makeFirstResponder(targetField)
                    targetField.selectText(nil)
                    (targetField.currentEditor() as? NSTextView)?.selectAll(nil)
                }
                
                if let window = field.window, (window.isKeyWindow || NSApplication.shared.keyWindow == window) {
                    performFocus(on: field)
                } else {
                    DispatchQueue.main.async {
                        guard let field = self.searchField else { return }
                        performFocus(on: field)
                    }
                }
            }
        }
        
        @objc func action(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onCommit()
            
            // In NSSearchField, pressing Return is intercepted by control(_:textView:doCommandBy:).
            // This action selector is only invoked when clicking the search icon / search button
            // or if an explicit Return/Enter key was pressed outside the standard editor.
            // Ensure we NEVER navigate on an automatic typing pause timer.
            guard let event = NSApplication.shared.currentEvent else { return }
            let isMouseClick = (event.type == .leftMouseUp || event.type == .leftMouseDown)
            let isReturnKey = (event.type == .keyDown && (event.keyCode == 36 || event.keyCode == 76))
            if isMouseClick || isReturnKey {
                parent.onNext?()
            }
        }
        
        public func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSSearchField {
                parent.text = field.stringValue
                parent.onCommit()
            }
        }
        
        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                if let event = NSApplication.shared.currentEvent, event.modifierFlags.contains(.shift) {
                    if let onPrev = parent.onPrevious {
                        onPrev()
                        return true
                    }
                } else {
                    if let onNext = parent.onNext {
                        onNext()
                        return true
                    }
                }
            }
            return false
        }
    }
}

/// Native AppKit text field for inline toolbar pills (Page and Zoom), guaranteeing
/// immediate first-responder focus, select-all on click, Return to commit, Escape to cancel,
/// and click-outside commit.
public struct NativePillTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: (String) -> Void
    var onCancel: () -> Void
    
    public init(text: Binding<String>, onCommit: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self._text = text
        self.onCommit = onCommit
        self.onCancel = onCancel
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.isEditable = true
        field.isSelectable = true
        field.isBordered = false
        field.drawsBackground = false
        field.alignment = .center
        field.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize(for: .small), weight: .bold)
        field.textColor = NSColor.labelColor
        field.focusRingType = .none
        field.usesSingleLineMode = true
        field.maximumNumberOfLines = 1
        field.delegate = context.coordinator
        context.coordinator.textField = field
        
        context.coordinator.focusAndSelectAll()
        context.coordinator.startClickOutsideMonitor()
        
        return field
    }
    
    public func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.parent = self
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }
    
    public static func dismantleNSView(_ nsView: NSTextField, coordinator: Coordinator) {
        coordinator.stopClickOutsideMonitor()
    }
    
    @MainActor
    public class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativePillTextField
        weak var textField: NSTextField?
        private var monitor: Any?
        private var hasCommittedOrCancelled = false
        private var isReadyToCommit = false
        
        init(_ parent: NativePillTextField) {
            self.parent = parent
            super.init()
        }
        
        func focusAndSelectAll() {
            DispatchQueue.main.async { [weak self] in
                guard let self = self, let field = self.textField else { return }
                if let window = field.window {
                    window.makeFirstResponder(field)
                    field.selectText(nil)
                    (field.currentEditor() as? NSTextView)?.selectAll(nil)
                    DispatchQueue.main.async { [weak self] in
                        self?.isReadyToCommit = true
                    }
                } else {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self, let field = self.textField, let window = field.window else { return }
                        window.makeFirstResponder(field)
                        field.selectText(nil)
                        (field.currentEditor() as? NSTextView)?.selectAll(nil)
                        DispatchQueue.main.async { [weak self] in
                            self?.isReadyToCommit = true
                        }
                    }
                }
            }
        }
        
        func startClickOutsideMonitor() {
            guard monitor == nil else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.monitor == nil, !self.hasCommittedOrCancelled else { return }
                self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                    guard let self = self, let field = self.textField, self.isReadyToCommit, !self.hasCommittedOrCancelled else {
                        return event
                    }
                    guard field.bounds.width > 0, field.bounds.height > 0, let window = field.window else {
                        return event
                    }
                    
                    let isOutside: Bool
                    if event.window === window {
                        let locationInView = field.convert(event.locationInWindow, from: nil)
                        let hitBounds = field.bounds.insetBy(dx: -4, dy: -4)
                        isOutside = !hitBounds.contains(locationInView)
                    } else {
                        isOutside = true
                    }
                    
                    if isOutside {
                        self.commitAction()
                    }
                    return event
                }
            }
        }
        
        func stopClickOutsideMonitor() {
            if let m = monitor {
                NSEvent.removeMonitor(m)
                monitor = nil
            }
        }
        
        func commitAction() {
            guard isReadyToCommit, !hasCommittedOrCancelled else { return }
            hasCommittedOrCancelled = true
            stopClickOutsideMonitor()
            let val = textField?.stringValue ?? parent.text
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.parent.text = val
                self.parent.onCommit(val)
            }
        }
        
        func cancelAction() {
            guard !hasCommittedOrCancelled else { return }
            hasCommittedOrCancelled = true
            stopClickOutsideMonitor()
            DispatchQueue.main.async { [weak self] in
                self?.parent.onCancel()
            }
        }
        
        public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                commitAction()
                return true
            } else if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelAction()
                return true
            }
            return false
        }
        
        public func controlTextDidChange(_ obj: Notification) {
            if let field = textField {
                parent.text = field.stringValue
            }
        }
        
        public func controlTextDidEndEditing(_ obj: Notification) {
            commitAction()
        }
        
        isolated deinit {
            if let m = monitor {
                NSEvent.removeMonitor(m)
            }
        }
    }
}

/// Interactive zoom percentage field allowing click-to-edit with custom zoom levels in a continuous glass pill
public struct EditableZoomField: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var isEditing: Bool = false
    @State private var editValue: String = ""
    
    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack(spacing: 2) {
            Button {
                if isEditing { commit(with: editValue) }
                viewModel.zoomOut()
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Zoom Out (Cmd -)")
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5, height: 12)
            
            if isEditing {
                NativePillTextField(
                    text: $editValue,
                    onCommit: { val in commit(with: val) },
                    onCancel: { isEditing = false }
                )
                .frame(width: 48, height: 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
            } else {
                Button {
                    editValue = "\(Int(viewModel.zoomScale * 100))"
                    isEditing = true
                } label: {
                    Text("\(Int(viewModel.zoomScale * 100))%")
                        .font(.caption.monospacedDigit().bold())
                        .frame(minWidth: 42)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Click to enter custom zoom percentage")
            }
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5, height: 12)
            
            Button {
                if isEditing { commit(with: editValue) }
                viewModel.zoomIn()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Zoom In (Cmd +)")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .fixedSize()
    }
    
    private func commit(with value: String) {
        let cleaned = value.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let val = Double(cleaned), val >= 10 && val <= 1000 {
            viewModel.setZoom(CGFloat(val) / 100.0)
        }
        isEditing = false
    }
}

/// Interactive Page X of Y pill allowing click-to-edit to jump directly to any page, with stepping chevrons
public struct EditablePagePill: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let pageCount: Int
    @State private var isEditing: Bool = false
    @State private var editValue: String = ""
    
    public init(viewModel: PDFViewerViewModel, pageCount: Int) {
        self.viewModel = viewModel
        self.pageCount = pageCount
    }
    
    public var body: some View {
        let formattedPageCount = pageCount.formatted()
        let numberWidth = CGFloat(max(formattedPageCount.count, 2)) * 8 + 4

        HStack(spacing: 3) {
            Button {
                if isEditing { commit(with: editValue) }
                viewModel.previousPage()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(viewModel.currentPageIndex > 0 ? Color.secondary : Color.secondary.opacity(0.3))
                    .frame(width: 18, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPageIndex <= 0)
            .help("Previous Page")

            Text("Page")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 2)

            if isEditing {
                NativePillTextField(
                    text: $editValue,
                    onCommit: { val in commit(with: val) },
                    onCancel: { isEditing = false }
                )
                .frame(width: numberWidth + 8, height: 18)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(Color.accentColor, lineWidth: 1)
                )
            } else {
                Button {
                    editValue = "\(viewModel.currentPageIndex + 1)"
                    isEditing = true
                } label: {
                    Text("\(viewModel.currentPageIndex + 1)")
                        .font(.caption.monospacedDigit().bold())
                        .frame(minWidth: numberWidth)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Click to jump to page number")
            }

            Text("of \(pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.trailing, 2)

            Button {
                if isEditing { commit(with: editValue) }
                viewModel.nextPage()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(viewModel.currentPageIndex + 1 < pageCount ? Color.secondary : Color.secondary.opacity(0.3))
                    .frame(width: 18, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPageIndex + 1 >= pageCount)
            .help("Next Page")
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .fixedSize()
    }
    
    private func commit(with value: String) {
        if let target = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
            let clamped = min(max(target, 1), pageCount)
            viewModel.jumpToPage(clamped - 1)
        }
        isEditing = false
    }
}

/// Rich, actionable sidebar card for cross-reference and user snapshot targets
struct SnapshotCardView: View {
    let snap: SnapshotTarget
    @ObservedObject var viewModel: PDFViewerViewModel
    @ObservedObject private var windowManager = SnapshotWindowManager.shared
    @State private var showPreviewPopover: Bool = false
    @State private var hoverPreviewTask: Task<Void, Never>?
    @State private var isHovered: Bool = false

    private var isSelected: Bool {
        viewModel.selectedSnapshotId == snap.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Page badge + close button
            // Header: Page label + close button (matching SearchResultRowView styling)
            HStack {
                Text("Page \(snap.targetPage + 1)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.accentColor : Color.accentColor.opacity(0.12))
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                    .clipShape(Capsule())
                
                Spacer()
                
                Button(role: .destructive) {
                    withAnimation {
                        viewModel.removeSnapshotTarget(snap)
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Delete Snapshot")
            }
            
            // Visual Thumbnail Preview (clicking navigates; hover displays enlarged preview).
            if let thumb = snap.thumbnailImage {
                Image(nsImage: thumb)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    )
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoverPreviewTask?.cancel()
                        if hovering {
                            hoverPreviewTask = Task {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                                if !Task.isCancelled {
                                    showPreviewPopover = true
                                }
                            }
                        } else {
                            showPreviewPopover = false
                        }
                    }
                    .popover(isPresented: $showPreviewPopover, arrowEdge: .trailing) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(snap.label)
                                    .font(.headline)
                                Spacer()
                                Text("Page \(snap.targetPage + 1)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            // Enlarged thumbnail preview
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 400, maxHeight: 300)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(16)
                        .frame(minWidth: 320)
                    }
            }
            
            // Snippet / Label Text — displayed when no thumbnail is present
            if snap.thumbnailImage == nil, !snap.snippet.isEmpty {
                Text(snap.snippet)
                    .font(.caption)
                    .lineLimit(3)
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }

        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : (isHovered ? Color.primary.opacity(0.06) : Color.primary.opacity(0.03)))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(isSelected ? Color.accentColor.opacity(0.3) : (isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.04)), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            viewModel.jumpToSnapshot(snap)
        }
        .contextMenu {
            let isWindowOpen = windowManager.isOpen(snap.id)
            Button {
                if isWindowOpen {
                    viewModel.closeSnapshotWindow(snap)
                } else {
                    viewModel.openSnapshotInNewWindow(snap)
                }
            } label: {
                Label(
                    isWindowOpen ? "Close Window" : "Open in New Window",
                    systemImage: isWindowOpen ? "xmark.circle" : "macwindow.badge.plus"
                )
            }

            if !snap.snippet.isEmpty {
                Button {
                    copyText()
                } label: {
                    Label("Copy Text", systemImage: "doc.on.doc")
                }
            }

            if snap.thumbnailImage != nil {
                Button {
                    copyImage()
                } label: {
                    Label("Copy Screenshot", systemImage: "camera")
                }
            }

            Divider()

            Button(role: .destructive) {
                withAnimation {
                    viewModel.removeSnapshotTarget(snap)
                }
            } label: {
                Label("Delete Snapshot", systemImage: "trash")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func copyText() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snap.snippet, forType: .string)
    }

    private func copyImage() {
        guard let image = snap.thumbnailImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
    }
}

/// Popover menu of search matching toggles (case sensitivity, whole word, smart/fuzzy
/// matching). Any change re-runs the active search immediately, same as editing the query.
public struct SearchOptionsMenu: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var isNonDefault: Bool {
        viewModel.searchOptions != SearchOptions()
    }

    private func binding(for keyPath: WritableKeyPath<SearchOptions, Bool>) -> Binding<Bool> {
        Binding(
            get: { viewModel.searchOptions[keyPath: keyPath] },
            set: { newValue in
                viewModel.searchOptions[keyPath: keyPath] = newValue
                viewModel.performSearch()
            }
        )
    }

    public var body: some View {
        Menu {
            Toggle("Match Case", isOn: binding(for: \.matchCase))
            Toggle("Whole Word", isOn: binding(for: \.wholeWord))
            Divider()
            // "Ignore hyphens & dashes" overstated what SmartRegexBuilder actually does: it treats
            // spaces, hyphens, dashes, and line breaks as interchangeable (so "MU MIMO" matches
            // "MU-MIMO" and a word hyphenated across a line wrap still matches), plus normalizes
            // curly vs. straight quotes — it doesn't let those characters be absent entirely.
            Toggle("Smart Search (spaces/hyphens/dashes interchangeable)", isOn: binding(for: \.smartSearch))
        } label: {
            Image(systemName: "slider.horizontal.3")
                .symbolVariant(isNonDefault ? .fill : .none)
                .foregroundStyle(isNonDefault ? Color.accentColor : Color.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Search Options")
    }
}

/// Floating glass HUD overlay providing quick page navigation over the document canvas
public struct FloatingReaderHUD: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let pageCount: Int
    @State private var isHovered: Bool = false
    @State private var isTemporarilyVisible: Bool = false
    @State private var hideTask: Task<Void, Never>? = nil

    private var isVisible: Bool {
        isHovered || isTemporarilyVisible
    }

    public init(viewModel: PDFViewerViewModel, pageCount: Int) {
        self.viewModel = viewModel
        self.pageCount = pageCount
    }

    public var body: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.previousPage()
                showTemporarily()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.currentPageIndex > 0 ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPageIndex <= 0)
            .help("Previous Page")

            Text("Page \(viewModel.currentPageIndex + 1) of \(pageCount)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)

            Button {
                viewModel.nextPage()
                showTemporarily()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(viewModel.currentPageIndex + 1 < pageCount ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.currentPageIndex + 1 >= pageCount)
            .help("Next Page")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
        )
        .opacity(isVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        .allowsHitTesting(isVisible)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                hideTask?.cancel()
            } else {
                scheduleAutoHide(delay: 1.5)
            }
        }
        .onChange(of: viewModel.currentPageIndex) { _, _ in
            showTemporarily()
        }
        .onAppear {
            showTemporarily()
        }
        .fixedSize()
    }

    private func showTemporarily() {
        guard !isHovered else { return }
        isTemporarilyVisible = true
        scheduleAutoHide(delay: 2.0)
    }

    private func scheduleAutoHide(delay: Double) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            if !Task.isCancelled && !isHovered {
                isTemporarilyVisible = false
            }
        }
    }
}
