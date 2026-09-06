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
        
        self.stringValue = widget.value
        self.isEditable = !widget.isReadOnly
        self.isSelectable = true
        self.isBezeled = true
        self.bezelStyle = .squareBezel
        self.drawsBackground = true
        self.backgroundColor = NSColor.textBackgroundColor
        self.focusRingType = .exterior
        
        updateZoom(frame: frame)
        
        if widget.isMultiline {
            self.lineBreakMode = .byWordWrapping
            self.cell?.wraps = true
            self.cell?.isScrollable = false
        }
        
        self.delegate = self
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func updateZoom(frame: NSRect) {
        let fontSize = max(9, min(48, frame.height * 0.65))
        let newFont = NSFont.systemFont(ofSize: fontSize)
        self.font = newFont
        if let editor = self.currentEditor() as? NSTextView {
            editor.font = newFont
        }
    }
    
    public func controlTextDidChange(_ obj: Notification) {
        viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func controlTextDidEndEditing(_ obj: Notification) {
        viewModel.updateWidgetValue(pageIndex: widget.pageIndex, widgetIndex: widget.widgetIndex, value: self.stringValue)
    }
    
    public func controlTextDidBeginEditing(_ obj: Notification) {
        if #available(macOS 15.0, *), let editor = self.currentEditor() as? NSTextView {
            editor.writingToolsBehavior = .complete
            let fontSize = max(9, min(48, frame.height * 0.65))
            editor.font = NSFont.systemFont(ofSize: fontSize)
        }
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

/// Factory helper for creating native AppKit form controls matching PDFFormWidget
@MainActor
public enum PDFFormControlFactory {
    public static func makeControl(for widget: PDFFormWidget, viewModel: PDFViewerViewModel, frame: NSRect) -> NSView? {
        switch widget.type {
        case .text:
            return PDFFormTextField(widget: widget, viewModel: viewModel, frame: frame)
        case .checkbox, .radiobutton:
            return PDFFormButton(widget: widget, viewModel: viewModel, frame: frame)
        case .combobox, .listbox:
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
