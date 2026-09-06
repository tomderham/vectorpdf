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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
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
        field.target = context.coordinator
        field.action = #selector(Coordinator.action(_:))
        field.delegate = context.coordinator
        field.focusRingType = .exterior
        field.bezelStyle = .roundedBezel
        return field
    }
    
    public func updateNSView(_ nsView: NSSearchField, context: Context) {
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
        
        init(_ parent: NativeSearchField) {
            self.parent = parent
        }
        
        @objc func action(_ sender: NSSearchField) {
            parent.text = sender.stringValue
            parent.onCommit()
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

/// Interactive zoom percentage field allowing click-to-edit with custom zoom levels
public struct EditableZoomField: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var isEditing: Bool = false
    @State private var editValue: String = ""
    @FocusState private var isFocused: Bool
    
    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editValue)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .frame(width: 50, height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
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
                    editValue = "\(Int(viewModel.zoomScale * 100))"
                    isEditing = true
                    DispatchQueue.main.async {
                        isFocused = true
                    }
                } label: {
                    Text("\(Int(viewModel.zoomScale * 100))%")
                        .font(.caption.monospacedDigit())
                        .frame(width: 46, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                )
                .help("Click to enter custom zoom percentage (e.g. 150%)")
            }
        }
    }
    
    private func commit() {
        let cleaned = editValue.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let val = Double(cleaned), val >= 10 && val <= 1000 {
            viewModel.setZoom(CGFloat(val) / 100.0)
        }
        isEditing = false
    }
}

/// Interactive Page X of Y pill allowing click-to-edit to jump directly to any page
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
        // SwiftUI's Text(_:) applies locale-aware grouping to interpolated integers (e.g. "7,355",
        // not "7355") — sized off that formatted string, not raw digit count, or a grouping comma
        // silently didn't fit. Never sized down for a short document, so the pill doesn't need to
        // resize itself later if a shorter document is replaced by a longer one.
        let formattedPageCount = pageCount.formatted()
        let numberWidth = CGFloat(max(formattedPageCount.count, 5)) * 8 + 4

        HStack(spacing: 4) {
            // A couple of points of leading breathing room — without it, "Page"'s leading glyph
            // renders flush against the toolbar item's exact edge and its left edge visibly clips.
            Text("Page")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.leading, 6)

            if isEditing {
                TextField("", text: $editValue)
                    .font(.caption.monospacedDigit().bold())
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                    .frame(width: numberWidth + 12, height: 19)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
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
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
                .help("Click to jump to page number")
            }

            Text("of \(pageCount)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(minWidth: numberWidth, alignment: .leading)
        }
        // Retain natural content width to prevent toolbar truncation.
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header: Page badge + close button
            HStack {
                Text("Page \(snap.targetPage + 1)")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.12))
                    .foregroundStyle(Color.accentColor)
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
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.1), lineWidth: 1)
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
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.jumpToSnapshot(snap)
        }
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

