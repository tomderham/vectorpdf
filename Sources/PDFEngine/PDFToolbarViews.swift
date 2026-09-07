import SwiftUI
import AppKit

/// A single Favorite or Tab Group entry on the empty-window "Start" screen — tap anywhere to
/// open, or the trailing x to remove. Styled to match SnapshotCardView's cards for a consistent
/// look across the app's list-of-things UI.
struct StartScreenRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let onOpen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(role: .destructive) {
                onRemove()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpen()
        }
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

/// Interactive zoom percentage field allowing click-to-edit with custom zoom levels in a continuous glass pill
public struct EditableZoomField: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var isEditing: Bool = false
    @State private var editValue: String = ""
    @FocusState private var isFocused: Bool
    
    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        HStack(spacing: 2) {
            Button {
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
                TextField("", text: $editValue)
                    .font(.caption.monospacedDigit().bold())
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .frame(width: 48, height: 18)
                    .focused($isFocused)
                    .onSubmit {
                        commit()
                    }
                    .onExitCommand {
                        isEditing = false
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing {
                            commit()
                        }
                    }
            } else {
                Button {
                    editValue = "\(Int(viewModel.zoomScale * 100))"
                    isEditing = true
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                } label: {
                    Text("\(Int(viewModel.zoomScale * 100))%")
                        .font(.caption.monospacedDigit().bold())
                        .frame(minWidth: 42)
                        .frame(height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to enter custom zoom percentage")
            }
            
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 0.5, height: 12)
            
            Button {
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
    
    private func commit() {
        let cleaned = editValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
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
    @FocusState private var isFocused: Bool
    
    public init(viewModel: PDFViewerViewModel, pageCount: Int) {
        self.viewModel = viewModel
        self.pageCount = pageCount
    }
    
    public var body: some View {
        let formattedPageCount = pageCount.formatted()
        let numberWidth = CGFloat(max(formattedPageCount.count, 2)) * 8 + 4

        HStack(spacing: 3) {
            Button {
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
                TextField("", text: $editValue)
                    .font(.caption.monospacedDigit().bold())
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .frame(width: numberWidth + 8, height: 18)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.accentColor, lineWidth: 1)
                    )
                    .focused($isFocused)
                    .onSubmit {
                        commit()
                    }
                    .onExitCommand {
                        isEditing = false
                    }
                    .onChange(of: isFocused) { _, focused in
                        if !focused && isEditing {
                            commit()
                        }
                    }
            } else {
                Button {
                    editValue = "\(viewModel.currentPageIndex + 1)"
                    isEditing = true
                    DispatchQueue.main.async {
                        isFocused = true
                    }
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
    
    private func commit() {
        if let target = Int(editValue.trimmingCharacters(in: .whitespacesAndNewlines)) {
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
    @State private var isCopied: Bool = false
    @State private var showPreviewPopover: Bool = false
    @State private var hoverPreviewTask: Task<Void, Never>?
    @State private var isHovered: Bool = false

    private var isSelected: Bool {
        viewModel.selectedSnapshotId == snap.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Page badge + close button
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
                    .font(.system(size: 11))
                    .lineLimit(3)
                    .foregroundStyle(.primary)
            }

            // Action Buttons: Open/Close Window, Copy.
            HStack(spacing: 6) {
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
                .help(isWindowOpen ? "Close the window showing this snapshot" : "Open this snapshot in a new window")

                // A dropdown only when there's an actual choice to make (a rectangular snapshot
                // with underlying text has both); otherwise a single plain button naming exactly
                // what it copies, rather than a superfluous one-item menu.
                if !snap.snippet.isEmpty && snap.thumbnailImage != nil {
                    Menu {
                        Button("Copy Text") { copyText() }
                        Button("Copy Screenshot") { copyImage() }
                    } label: {
                        Label(isCopied ? "Copied" : "Copy", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                            .foregroundStyle(isCopied ? Color.green : Color.accentColor)
                    }
                    .help("Copy")
                } else if !snap.snippet.isEmpty {
                    Button {
                        copyText()
                    } label: {
                        Label(isCopied ? "Copied" : "Copy Text", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy Text")
                } else if snap.thumbnailImage != nil {
                    Button {
                        copyImage()
                    } label: {
                        Label(isCopied ? "Copied" : "Copy Screenshot", systemImage: isCopied ? "checkmark" : "doc.on.doc")
                    }
                    .help("Copy Screenshot")
                }

                Spacer()
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.accentColor)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.14) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(
                            isSelected ? Color.accentColor.opacity(0.5) : (isHovered ? Color.primary.opacity(0.12) : Color.primary.opacity(0.06)),
                            lineWidth: isSelected ? 1.5 : 0.5
                        )
                )
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            viewModel.jumpToSnapshot(snap)
        }
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func flashCopied() {
        isCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            isCopied = false
        }
    }

    private func copyText() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(snap.snippet, forType: .string)
        flashCopied()
    }

    private func copyImage() {
        guard let image = snap.thumbnailImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([image])
        flashCopied()
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

    public init(viewModel: PDFViewerViewModel, pageCount: Int) {
        self.viewModel = viewModel
        self.pageCount = pageCount
    }

    public var body: some View {
        HStack(spacing: 6) {
            Button {
                viewModel.previousPage()
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
        .opacity(isHovered ? 1.0 : 0.65)
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
        .fixedSize()
    }
}


