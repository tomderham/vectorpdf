import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Native AppKit text field overlay for AcroForm text fields
@MainActor
public final class PDFFormTextField: NSTextField, NSTextFieldDelegate {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    
    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        super.init(frame: frame)
        
        if !widget.isMultiline && (widget.value.contains("\n") || widget.value.contains("\r")) {
            self.stringValue = widget.value
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
        } else {
            self.stringValue = widget.value
        }
        self.isEditable = !widget.isReadOnly
        self.isSelectable = true
        self.wantsLayer = true
        self.isBezeled = false
        self.isBordered = false
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = NSColor.separatorColor.cgColor
        self.layer?.cornerRadius = 1.0
        self.drawsBackground = true
        self.backgroundColor = NSColor.textBackgroundColor
        self.focusRingType = .exterior
        self.alignment = widget.textAlignment
        
        if widget.isMultiline {
            self.lineBreakMode = .byWordWrapping
            self.cell?.wraps = true
            self.cell?.isScrollable = false
            self.maximumNumberOfLines = 0
            self.usesSingleLineMode = false
        } else {
            self.lineBreakMode = .byClipping
            self.cell?.wraps = false
            self.cell?.isScrollable = true
            self.maximumNumberOfLines = 1
            self.usesSingleLineMode = true
        }
        
        updateZoom(frame: frame)
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateZoom(frame: NSRect) {
        let fontSize: CGFloat
        if widget.fontSize > 0 {
            let zoom = widget.rect.height > 0 ? (frame.height / widget.rect.height) : viewModel.zoomScale
            fontSize = max(5, min(72, widget.fontSize * zoom))
        } else {
            fontSize = max(6, min(48, frame.height * 0.56))
        }
        let newFont = NSFont.systemFont(ofSize: fontSize)
        self.font = newFont
        self.alignment = widget.textAlignment
        if let editor = self.currentEditor() as? NSTextView {
            editor.font = newFont
            editor.alignment = widget.textAlignment
        }
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        if !widget.isMultiline && (self.stringValue.contains("\n") || self.stringValue.contains("\r")) {
            let sanitized = self.stringValue
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            self.stringValue = sanitized
        }
        if widget.maxLen > 0 && self.stringValue.count > widget.maxLen {
            self.stringValue = String(self.stringValue.prefix(widget.maxLen))
        }
        viewModel.updateWidgetValueDebounced(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func controlTextDidEndEditing(_ obj: Notification) {
        if widget.maxLen > 0 && self.stringValue.count > widget.maxLen {
            self.stringValue = String(self.stringValue.prefix(widget.maxLen))
        }
        viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func control(_ control: NSControl, textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard widget.maxLen > 0, let replacement = replacementString else { return true }
        let currentText = (textView.string as NSString)
        let newText = currentText.replacingCharacters(in: affectedCharRange, with: replacement)
        return newText.count <= widget.maxLen
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if !widget.isMultiline {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
               commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
               commandSelector == #selector(NSResponder.insertParagraphSeparator(_:)) {
                self.window?.makeFirstResponder(nil)
                return true
            }
        }
        return false
    }
    
    public func controlTextDidBeginEditing(_ obj: Notification) {
        if #available(macOS 15.0, *), let editor = self.currentEditor() as? NSTextView {
            editor.writingToolsBehavior = .complete
            if let f = self.font {
                editor.font = f
            }
        }
    }
}

/// Native AppKit secure text field overlay for AcroForm password fields
@MainActor
public final class PDFFormSecureTextField: NSSecureTextField, NSTextFieldDelegate {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    
    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        super.init(frame: frame)
        
        self.stringValue = widget.value
        self.isEditable = !widget.isReadOnly
        self.isSelectable = true
        self.wantsLayer = true
        self.isBezeled = false
        self.isBordered = false
        self.layer?.borderWidth = 0.5
        self.layer?.borderColor = NSColor.separatorColor.cgColor
        self.layer?.cornerRadius = 1.0
        self.drawsBackground = true
        self.backgroundColor = NSColor.textBackgroundColor
        self.focusRingType = .exterior
        self.alignment = widget.textAlignment
        
        self.lineBreakMode = .byClipping
        self.cell?.wraps = false
        self.cell?.isScrollable = true
        self.maximumNumberOfLines = 1
        self.usesSingleLineMode = true
        
        updateZoom(frame: frame)
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateZoom(frame: NSRect) {
        let fontSize: CGFloat
        if widget.fontSize > 0 {
            let zoom = widget.rect.height > 0 ? (frame.height / widget.rect.height) : viewModel.zoomScale
            fontSize = max(5, min(72, widget.fontSize * zoom))
        } else {
            fontSize = max(6, min(48, frame.height * 0.56))
        }
        let newFont = NSFont.systemFont(ofSize: fontSize)
        self.font = newFont
        self.alignment = widget.textAlignment
        if let editor = self.currentEditor() as? NSTextView {
            editor.font = newFont
            editor.alignment = widget.textAlignment
        }
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        if self.stringValue.contains("\n") || self.stringValue.contains("\r") {
            let sanitized = self.stringValue
                .replacingOccurrences(of: "\r\n", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
                .replacingOccurrences(of: "\r", with: " ")
            self.stringValue = sanitized
        }
        if widget.maxLen > 0 && self.stringValue.count > widget.maxLen {
            self.stringValue = String(self.stringValue.prefix(widget.maxLen))
        }
        viewModel.updateWidgetValueDebounced(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func controlTextDidEndEditing(_ obj: Notification) {
        if widget.maxLen > 0 && self.stringValue.count > widget.maxLen {
            self.stringValue = String(self.stringValue.prefix(widget.maxLen))
        }
        viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func control(_ control: NSControl, textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        guard widget.maxLen > 0, let replacement = replacementString else { return true }
        let currentText = (textView.string as NSString)
        let newText = currentText.replacingCharacters(in: affectedCharRange, with: replacement)
        return newText.count <= widget.maxLen
    }
    
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) ||
           commandSelector == #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)) ||
           commandSelector == #selector(NSResponder.insertParagraphSeparator(_:)) {
            self.window?.makeFirstResponder(nil)
            return true
        }
        return false
    }
}

/// Native vector AppKit checkbox / radio overlay that dynamically scales with document zoom
@MainActor
public final class PDFFormButton: NSControl {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    public var state: NSControl.StateValue = .off {
        didSet {
            needsDisplay = true
        }
    }
    
    public override var isFlipped: Bool { return true }
    
    public override var acceptsFirstResponder: Bool {
        return isEnabled
    }
    
    public static func isValueChecked(_ val: String) -> Bool {
        let trimmed = val.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.caseInsensitiveCompare("Off") == .orderedSame ||
           trimmed == "0" ||
           trimmed.caseInsensitiveCompare("false") == .orderedSame {
            return false
        }
        return true
    }
    
    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        super.init(frame: frame)
        
        self.state = Self.isValueChecked(widget.value) ? .on : .off
        self.isEnabled = !widget.isReadOnly
        self.focusRingType = .exterior
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateZoom(frame: NSRect) {
        self.needsDisplay = true
    }
    
    public override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        PDFViewerViewModel.active = viewModel
        window?.makeFirstResponder(self)
        
        // Track mouse up inside bounds for crisp, reliable macOS click response
        let trackingMask: NSEvent.EventTypeMask = [.leftMouseDragged, .leftMouseUp]
        while let nextEvent = window?.nextEvent(matching: trackingMask) {
            if nextEvent.type == .leftMouseUp {
                let loc = convert(nextEvent.locationInWindow, from: nil)
                if bounds.contains(loc) {
                    toggle()
                }
                break
            }
        }
    }
    
    public func toggle() {
        guard isEnabled else { return }
        let nextChecked: Bool
        if widget.type == .radiobutton {
            nextChecked = true
        } else {
            nextChecked = (self.state != .on)
        }
        self.state = nextChecked ? .on : .off
        let newVal = nextChecked ? "Yes" : "Off"
        viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: newVal)
    }
    
    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 { // Spacebar toggles
            toggle()
            return
        }
        super.keyDown(with: event)
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        let b = bounds
        guard b.width > 0 && b.height > 0 else { return }
        
        // Ensure box strictly stays within bounds without intruding on neighboring form elements
        let boxSize = max(2.0, min(b.width, b.height) - 1.0)
        let boxRect = NSRect(
            x: (b.width - boxSize) / 2,
            y: (b.height - boxSize) / 2,
            width: boxSize,
            height: boxSize
        )
        
        if widget.type == .radiobutton {
            let circle = NSBezierPath(ovalIn: boxRect)
            NSColor.textBackgroundColor.setFill()
            circle.fill()
            
            if state == .on {
                NSColor.controlAccentColor.setStroke()
                circle.lineWidth = max(1.2, boxSize * 0.12)
                circle.stroke()
                
                if boxSize >= 5 {
                    let dotSize = max(2.0, boxSize * 0.48)
                    let dotRect = NSRect(
                        x: boxRect.midX - dotSize / 2,
                        y: boxRect.midY - dotSize / 2,
                        width: dotSize,
                        height: dotSize
                    )
                    let dot = NSBezierPath(ovalIn: dotRect)
                    NSColor.controlAccentColor.setFill()
                    dot.fill()
                }
            } else {
                NSColor.separatorColor.setStroke()
                circle.lineWidth = 1.0
                circle.stroke()
            }
        } else {
            // Checkbox
            let radius = max(1.5, boxSize * 0.18)
            let path = NSBezierPath(roundedRect: boxRect, xRadius: radius, yRadius: radius)
            
            if state == .on {
                NSColor.controlAccentColor.setFill()
                path.fill()
                NSColor.controlAccentColor.setStroke()
                path.lineWidth = 1.0
                path.stroke()
                
                if boxSize >= 5 {
                    // Crisp white checkmark in flipped coordinates
                    let check = NSBezierPath()
                    check.move(to: NSPoint(x: boxRect.minX + boxSize * 0.22, y: boxRect.minY + boxSize * 0.50))
                    check.line(to: NSPoint(x: boxRect.minX + boxSize * 0.42, y: boxRect.minY + boxSize * 0.72))
                    check.line(to: NSPoint(x: boxRect.minX + boxSize * 0.78, y: boxRect.minY + boxSize * 0.26))
                    check.lineWidth = max(1.2, boxSize * 0.13)
                    check.lineCapStyle = .round
                    check.lineJoinStyle = .round
                    NSColor.white.setStroke()
                    check.stroke()
                }
            } else {
                NSColor.textBackgroundColor.setFill()
                path.fill()
                NSColor.separatorColor.setStroke()
                path.lineWidth = 1.0
                path.stroke()
            }
        }
    }
}

/// Native AppKit popup button overlay for AcroForm combobox and listbox fields
@MainActor
public final class PDFFormChoiceButton: NSPopUpButton {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    
    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        super.init(frame: frame, pullsDown: false)
        
        self.wantsLayer = true
        self.layer?.cornerRadius = 3
        self.layer?.masksToBounds = true
        
        self.removeAllItems()
        if widget.options.isEmpty && !widget.value.isEmpty {
            self.addItem(withTitle: widget.value)
        } else {
            self.addItems(withTitles: widget.options)
        }
        if !widget.value.isEmpty {
            self.selectItem(withTitle: widget.value)
        }
        
        updateZoom(frame: frame)
        
        self.isEnabled = !widget.isReadOnly
        self.target = self
        self.action = #selector(selectionChanged)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateZoom(frame: NSRect) {
        let fontSize = max(9, min(36, frame.height * 0.60))
        self.font = NSFont.systemFont(ofSize: fontSize)
        if frame.height < 18 {
            self.controlSize = .mini
        } else if frame.height < 24 {
            self.controlSize = .small
        } else {
            self.controlSize = .regular
        }
        self.needsDisplay = true
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        // Draw solid opaque background so underlying PDF text never bleeds through
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        
        let borderPath = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        NSColor.separatorColor.setStroke()
        borderPath.lineWidth = 1.0
        borderPath.stroke()
        
        super.draw(dirtyRect)
    }
    
    @objc private func selectionChanged() {
        let newVal = self.titleOfSelectedItem ?? ""
        viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: newVal)
    }
}

/// Native AppKit overlay for AcroForm signature fields. This is a *visual* stamp only (draw a
/// signature or pick an image) — not a cryptographic PDF signature, which would need OpenSSL.
@MainActor
public final class PDFSignatureStampButton: NSButton {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    private var popover: NSPopover?

    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        super.init(frame: frame)

        // No bezel: an already-signed field has its stamp baked into the page bitmap, and this
        // button must not cover it. hasSignatureStamp tells the two cases apart on a fresh load.
        self.isBordered = false
        if viewModel.document?.hasSignatureStamp(pageIndex: widget.pageIndex, widgetRect: widget.rect) == true {
            self.title = ""
        } else {
            self.title = "Sign"
            self.contentTintColor = .secondaryLabelColor
        }
        self.target = self
        self.action = #selector(showSignaturePad)
        self.isEnabled = !widget.isReadOnly
        updateZoom(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func updateZoom(frame: NSRect) {
        self.font = NSFont.systemFont(ofSize: max(9, min(14, frame.height * 0.45)))
    }

    @objc private func showSignaturePad() {
        guard isEnabled else { return }
        let capture = SignatureCaptureView { [weak self] image in
            self?.popover?.close()
            guard let self, let image else { return }
            self.applySignature(image)
        }
        let controller = NSHostingController(rootView: capture)
        let popover = NSPopover()
        popover.contentViewController = controller
        popover.behavior = .transient
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        self.popover = popover
    }

    /// Shows the drawn/picked image directly on the button itself, like a checkbox showing its own
    /// checkmark — no save/re-render round trip needed for the live preview.
    private func applySignature(_ image: NSImage) {
        self.image = image
        self.imagePosition = .imageOnly
        self.imageScaling = .scaleProportionallyUpOrDown
        guard let data = image.pdfStampPNGData else { return }
        viewModel.insertSignatureStamp(pageIndex: widget.pageIndex, rect: widget.rect, imageData: data)
    }
}

/// Freehand signature capture shown in a popover from PDFSignatureStampButton: draw with the
/// mouse/trackpad, or pick an existing image file. Calls back with the chosen/drawn image, or nil
/// if cancelled.
private struct SignatureCaptureView: View {
    let onComplete: (NSImage?) -> Void

    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []

    private static let canvasSize = CGSize(width: 360, height: 140)

    var body: some View {
        VStack(spacing: 12) {
            Text("Draw a signature, or choose an image")
                .font(.headline)

            Canvas { context, _ in
                for stroke in strokes + [currentStroke] {
                    guard stroke.count > 1 else { continue }
                    var path = Path()
                    path.addLines(stroke)
                    context.stroke(path, with: .color(.black), lineWidth: 2.5)
                }
            }
            .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
            .background(Color.white)
            .overlay(Rectangle().stroke(Color.secondary.opacity(0.4)))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in currentStroke.append(value.location) }
                    .onEnded { _ in
                        if !currentStroke.isEmpty {
                            strokes.append(currentStroke)
                            currentStroke = []
                        }
                    }
            )

            HStack {
                Button("Clear") {
                    strokes = []
                    currentStroke = []
                }
                Button("Choose Image…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.image]
                    panel.canChooseDirectories = false
                    if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
                        onComplete(image)
                    }
                }
                Spacer()
                Button("Cancel") { onComplete(nil) }
                Button("Use This") { onComplete(renderStrokesToImage()) }
                    .disabled(strokes.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 400)
    }

    private func renderStrokesToImage() -> NSImage? {
        let size = Self.canvasSize
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        // Opaque, not transparent: fully covers the field's existing placeholder artwork underneath,
        // like ink on paper, instead of letting it show through around the strokes.
        NSColor.white.setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor.black.setStroke()
        for stroke in strokes where stroke.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = 2.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // SwiftUI's Canvas/DragGesture report points in a top-left-origin coordinate space;
            // NSImage's lockFocus drawing here is bottom-left-origin, so without flipping the y
            // axis the signature would render upside down.
            path.move(to: NSPoint(x: stroke[0].x, y: size.height - stroke[0].y))
            for point in stroke.dropFirst() {
                path.line(to: NSPoint(x: point.x, y: size.height - point.y))
            }
            path.stroke()
        }
        return image
    }
}

private extension NSImage {
    var pdfStampPNGData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}

/// Specialized AppKit control for AcroForm comb text fields (divided into MaxLen character boxes)
@MainActor
public final class PDFFormCombTextField: NSControl {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    public let maxLen: Int
    
    private var characters: [Character] = []
    public private(set) var activeCellIndex: Int = 0
    private var blinkTimer: Timer?
    private var cursorVisible: Bool = true
    
    public override var stringValue: String {
        get { String(characters) }
        set {
            let sanitized = newValue
                .replacingOccurrences(of: "\r\n", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
            characters = Array(sanitized.prefix(maxLen))
            activeCellIndex = min(characters.count, maxLen - 1)
            needsDisplay = true
        }
    }
    
    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        self.maxLen = max(1, widget.maxLen)
        super.init(frame: frame)
        
        let sanitized = widget.value
            .replacingOccurrences(of: "\r\n", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        self.characters = Array(sanitized.prefix(self.maxLen))
        self.activeCellIndex = min(self.characters.count, self.maxLen - 1)
        self.wantsLayer = true
        self.focusRingType = .exterior
        
        updateZoom(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            stopBlinkTimer()
        }
    }
    
    public func updateZoom(frame: NSRect) {
        let cellHeight = frame.height
        let fontSize: CGFloat
        if widget.fontSize > 0 {
            let zoom = widget.rect.height > 0 ? (frame.height / widget.rect.height) : viewModel.zoomScale
            fontSize = max(6, min(48, widget.fontSize * zoom))
        } else {
            fontSize = max(6, min(48, cellHeight * 0.65))
        }
        self.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        self.needsDisplay = true
    }
    
    private func cellRect(for index: Int) -> NSRect {
        let cellWidth = bounds.width / CGFloat(maxLen)
        return NSRect(
            x: bounds.minX + CGFloat(index) * cellWidth,
            y: bounds.minY,
            width: cellWidth,
            height: bounds.height
        )
    }
    
    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // 1. Background
        NSColor.textBackgroundColor.setFill()
        bounds.fill()
        
        // 2. Outer Border
        let borderPath = NSBezierPath(rect: bounds.insetBy(dx: 0.25, dy: 0.25))
        borderPath.lineWidth = 0.5
        NSColor.separatorColor.setStroke()
        borderPath.stroke()
        
        let cellWidth = bounds.width / CGFloat(maxLen)
        
        // 3. Cell Dividers
        let dividerColor = NSColor.separatorColor.withAlphaComponent(0.6)
        dividerColor.setStroke()
        for i in 1..<maxLen {
            let x = floor(bounds.minX + CGFloat(i) * cellWidth) + 0.5
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: bounds.minY))
            line.line(to: NSPoint(x: x, y: bounds.maxY))
            line.lineWidth = 0.5
            line.stroke()
        }
        
        // 4. Characters
        let font = self.font ?? NSFont.monospacedSystemFont(ofSize: max(8, bounds.height * 0.65), weight: .regular)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.textColor,
            .paragraphStyle: paragraphStyle
        ]
        
        for (i, char) in characters.enumerated() where i < maxLen {
            let cr = cellRect(for: i)
            let str = String(char)
            let strSize = str.size(withAttributes: attrs)
            let drawRect = NSRect(
                x: cr.midX - strSize.width / 2,
                y: cr.midY - strSize.height / 2,
                width: strSize.width,
                height: strSize.height
            )
            str.draw(in: drawRect, withAttributes: attrs)
        }
        
        // 5. Active Cursor
        let isFocused = (window?.firstResponder == self)
        if isFocused && cursorVisible && !widget.isReadOnly {
            let cr = cellRect(for: activeCellIndex)
            let cursorH = min(bounds.height * 0.75, font.pointSize * 1.3)
            let cursorW: CGFloat = 1.5
            let cursorRect: NSRect
            if activeCellIndex < characters.count {
                // Position after character or underline
                cursorRect = NSRect(x: cr.midX - cursorW / 2, y: cr.midY - cursorH / 2, width: cursorW, height: cursorH)
            } else {
                cursorRect = NSRect(x: cr.midX - cursorW / 2, y: cr.midY - cursorH / 2, width: cursorW, height: cursorH)
            }
            NSColor.keyboardFocusIndicatorColor.setFill()
            cursorRect.fill()
        }
    }
    
    // MARK: - Responder & Focus
    public override var acceptsFirstResponder: Bool { !widget.isReadOnly }
    public override var canBecomeKeyView: Bool { !widget.isReadOnly }
    
    public override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok {
            cursorVisible = true
            startBlinkTimer()
            needsDisplay = true
        }
        return ok
    }
    
    public override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok {
            stopBlinkTimer()
            viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
            needsDisplay = true
        }
        return ok
    }
    
    private func startBlinkTimer() {
        stopBlinkTimer()
        blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.cursorVisible.toggle()
                self.needsDisplay = true
            }
        }
    }
    
    private func stopBlinkTimer() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        cursorVisible = false
    }
    
    // MARK: - Mouse & Keyboard
    public override func mouseDown(with event: NSEvent) {
        guard !widget.isReadOnly else { return }
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let cellWidth = bounds.width / CGFloat(maxLen)
        let clickedCell = max(0, min(maxLen - 1, Int(point.x / cellWidth)))
        activeCellIndex = min(clickedCell, characters.count)
        cursorVisible = true
        needsDisplay = true
    }
    
    public override func keyDown(with event: NSEvent) {
        guard !widget.isReadOnly else {
            super.keyDown(with: event)
            return
        }
        
        let chars = event.charactersIgnoringModifiers ?? ""
        
        if let special = chars.unicodeScalars.first {
            switch Int(special.value) {
            case NSDeleteCharacter, 0x7F: // Backspace
                if activeCellIndex > 0 {
                    if activeCellIndex <= characters.count {
                        characters.remove(at: activeCellIndex - 1)
                        activeCellIndex -= 1
                    }
                    cursorVisible = true
                    viewModel.updateWidgetValueDebounced(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
                    needsDisplay = true
                }
                return
            case NSDeleteFunctionKey: // Forward delete
                if activeCellIndex < characters.count {
                    characters.remove(at: activeCellIndex)
                    cursorVisible = true
                    viewModel.updateWidgetValueDebounced(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
                    needsDisplay = true
                }
                return
            case NSLeftArrowFunctionKey:
                activeCellIndex = max(0, activeCellIndex - 1)
                cursorVisible = true
                needsDisplay = true
                return
            case NSRightArrowFunctionKey:
                activeCellIndex = min(characters.count, activeCellIndex + 1)
                cursorVisible = true
                needsDisplay = true
                return
            case NSEnterCharacter, 0x0D, 0x0A: // Return
                window?.makeFirstResponder(nil)
                return
            case NSTabCharacter:
                if event.modifierFlags.contains(.shift) {
                    window?.selectPreviousKeyView(self)
                } else {
                    window?.selectNextKeyView(self)
                }
                return
            default:
                break
            }
        }
        
        // Paste command (Cmd+V)
        if event.modifierFlags.contains(.command) && chars.lowercased() == "v" {
            if let clipboardString = NSPasteboard.general.string(forType: .string) {
                let sanitized = clipboardString
                    .replacingOccurrences(of: "\r\n", with: "")
                    .replacingOccurrences(of: "\n", with: "")
                    .replacingOccurrences(of: "\r", with: "")
                let available = maxLen - activeCellIndex
                let toInsert = Array(sanitized.prefix(available))
                for (idx, ch) in toInsert.enumerated() {
                    let targetIdx = activeCellIndex + idx
                    if targetIdx < characters.count {
                        characters[targetIdx] = ch
                    } else {
                        characters.append(ch)
                    }
                }
                activeCellIndex = min(maxLen - 1, activeCellIndex + toInsert.count)
                cursorVisible = true
                viewModel.updateWidgetValueDebounced(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
                needsDisplay = true
            }
            return
        }
        
        // Regular characters
        for ch in chars {
            guard !ch.isNewline && !ch.isWhitespace || ch == " " else { continue }
            guard characters.count < maxLen || activeCellIndex < characters.count else { break }
            
            if activeCellIndex < characters.count {
                characters[activeCellIndex] = ch
            } else {
                characters.append(ch)
            }
            activeCellIndex = min(maxLen - 1, activeCellIndex + 1)
            cursorVisible = true
            viewModel.updateWidgetValueDebounced(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
            needsDisplay = true
        }
    }
}

/// Native AppKit editable dropdown combobox for AcroForm combo fields with edit flag
@MainActor
public final class PDFFormEditableChoiceField: NSComboBox, NSComboBoxDelegate {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    
    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        super.init(frame: frame)
        
        self.isEditable = !widget.isReadOnly
        self.isSelectable = true
        self.completes = true
        self.hasVerticalScroller = true
        self.addItems(withObjectValues: widget.options)
        self.stringValue = widget.value
        self.focusRingType = .exterior
        
        updateZoom(frame: frame)
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateZoom(frame: NSRect) {
        let fontSize = max(8, min(24, frame.height * 0.55))
        self.font = NSFont.systemFont(ofSize: fontSize)
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        viewModel.updateWidgetValueDebounced(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func controlTextDidEndEditing(_ obj: Notification) {
        viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func comboBoxSelectionDidChange(_ notification: Notification) {
        if self.indexOfSelectedItem >= 0 && self.indexOfSelectedItem < widget.options.count {
            let val = widget.options[self.indexOfSelectedItem]
            viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: val)
        }
    }
}

/// Native AppKit pushbutton for AcroForm button fields
@MainActor
public final class PDFFormPushButton: NSButton {
    public let widget: PDFFormWidget
    public unowned let viewModel: PDFViewerViewModel
    
    public init(widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) {
        self.widget = widget
        self.viewModel = viewModel
        super.init(frame: frame)
        
        self.bezelStyle = .rounded
        self.title = widget.name.isEmpty ? "Button" : widget.name
        self.isEnabled = !widget.isReadOnly
        self.target = self
        self.action = #selector(buttonClicked)
        updateZoom(frame: frame)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateZoom(frame: NSRect) {
        self.font = NSFont.systemFont(ofSize: max(8, min(18, frame.height * 0.50)))
    }
    
    @objc private func buttonClicked() {
        guard isEnabled else { return }
        let lower = widget.name.lowercased()
        if lower.contains("reset") || lower.contains("clear") {
            viewModel.resetForm()
        }
    }
}

/// Factory helper for creating native AppKit form controls matching PDFFormWidget
@MainActor
public enum PDFFormControlFactory {
    public static func makeControl(for widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) -> NSView? {
        switch widget.type {
        case .text:
            if widget.isComb {
                return PDFFormCombTextField(widget: widget, viewModel: viewModel, frame: frame)
            }
            if widget.isPassword {
                return PDFFormSecureTextField(widget: widget, viewModel: viewModel, frame: frame)
            }
            return PDFFormTextField(widget: widget, viewModel: viewModel, frame: frame)
        case .checkbox, .radiobutton:
            return PDFFormButton(widget: widget, viewModel: viewModel, frame: frame)
        case .button:
            if widget.isPushButton {
                return PDFFormPushButton(widget: widget, viewModel: viewModel, frame: frame)
            }
            return nil
        case .combobox:
            if widget.isEditableChoice {
                return PDFFormEditableChoiceField(widget: widget, viewModel: viewModel, frame: frame)
            }
            if widget.options.isEmpty {
                return PDFFormTextField(widget: widget, viewModel: viewModel, frame: frame)
            } else {
                return PDFFormChoiceButton(widget: widget, viewModel: viewModel, frame: frame)
            }
        case .listbox:
            if widget.options.isEmpty {
                return PDFFormTextField(widget: widget, viewModel: viewModel, frame: frame)
            } else {
                return PDFFormChoiceButton(widget: widget, viewModel: viewModel, frame: frame)
            }
        case .signature:
            return PDFSignatureStampButton(widget: widget, viewModel: viewModel, frame: frame)
        default:
            return nil
        }
    }
}
