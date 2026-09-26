import SwiftUI
import AppKit

/// Manages persistent storage of the user's saved digital signature.
@MainActor
public final class SignatureStore: ObservableObject {
    public static let shared = SignatureStore()
    private let userDefaultsKey = "VectorPDF_SavedSignatureData"

    @Published public var savedSignatureData: Data? {
        didSet {
            if let data = savedSignatureData {
                UserDefaults.standard.set(data, forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            }
        }
    }

    private init() {
        self.savedSignatureData = UserDefaults.standard.data(forKey: userDefaultsKey)
    }

    public func save(data: Data) {
        self.savedSignatureData = data
    }

    public func clear() {
        self.savedSignatureData = nil
    }
}

public struct SignatureFontPreset: Identifiable, Hashable, Sendable {
    public var id: String { fontName }
    public let displayName: String
    public let fontName: String

    public init(displayName: String, fontName: String) {
        self.displayName = displayName
        self.fontName = fontName
    }
}

public let signatureFontPresets: [SignatureFontPreset] = [
    SignatureFontPreset(displayName: "Elegant Script", fontName: "Snell Roundhand"),
    SignatureFontPreset(displayName: "Classic Chancery", fontName: "Apple Chancery"),
    SignatureFontPreset(displayName: "Casual Hand", fontName: "Bradley Hand"),
    SignatureFontPreset(displayName: "Artistic Script", fontName: "SignPainter-HouseScript"),
    SignatureFontPreset(displayName: "Calligraphy", fontName: "Zapfino")
]

public enum SignatureCreationMode: String, CaseIterable, Identifiable, Sendable {
    case draw = "Draw"
    case type = "Type"
    case image = "Image"

    public var id: String { rawValue }
}

/// Comprehensive signature capture view: draw freehand, type name/initials in signature fonts, or choose an image.
public struct SignatureCaptureView: View {
    public let isOpaqueDefault: Bool
    public let onComplete: (NSImage?) -> Void

    @State private var creationMode: SignatureCreationMode = .draw
    @State private var strokes: [[CGPoint]] = []
    @State private var currentStroke: [CGPoint] = []
    @State private var typedText: String = ""
    @State private var selectedFontName: String = "Snell Roundhand"
    @State private var importedImage: NSImage? = nil
    @State private var transparentBackground: Bool = true

    private static let canvasSize = CGSize(width: 360, height: 140)

    public init(isOpaqueDefault: Bool = false, onComplete: @escaping (NSImage?) -> Void) {
        self.isOpaqueDefault = isOpaqueDefault
        self._transparentBackground = State(initialValue: !isOpaqueDefault)
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Create Stamp")
                    .font(.headline)
                Spacer()
                Picker("", selection: $creationMode) {
                    ForEach(SignatureCreationMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 170)
            }

            // Mode-specific content area (fixed size 360x140)
            switch creationMode {
            case .draw:
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
                .clipShape(RoundedRectangle(cornerRadius: 4))
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

            case .type:
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Enter name or initials", text: $typedText)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.small)

                        Picker("Font", selection: $selectedFontName) {
                            ForEach(signatureFontPresets) { preset in
                                Text(preset.displayName).tag(preset.fontName)
                            }
                        }
                        .controlSize(.small)
                        .frame(width: 140)
                    }

                    // Live signature font preview box
                    ZStack {
                        Color.white
                        Rectangle().stroke(Color.secondary.opacity(0.4))

                        if typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Stamp preview will appear here")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(typedText)
                                .font(.custom(selectedFontName, size: 34))
                                .foregroundColor(.black)
                                .minimumScaleFactor(0.4)
                                .lineLimit(1)
                                .padding(.horizontal, 16)
                        }
                    }
                    .frame(width: Self.canvasSize.width, height: Self.canvasSize.height - 36)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)

            case .image:
                ZStack {
                    Color.white
                    Rectangle().stroke(Color.secondary.opacity(0.4))

                    if let img = importedImage {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFit()
                            .padding(8)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                            Button("Choose Image File…") {
                                promptChooseImage()
                            }
                            .controlSize(.small)
                            Text("Supports PNG with transparency or JPEG")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            HStack {
                Toggle("Transparent background", isOn: $transparentBackground)
                    .font(.caption)
                Spacer()
            }

            HStack {
                Button("Clear") {
                    switch creationMode {
                    case .draw:
                        strokes = []
                        currentStroke = []
                    case .type:
                        typedText = ""
                    case .image:
                        importedImage = nil
                    }
                }

                if creationMode == .image && importedImage != nil {
                    Button("Change Image…") {
                        promptChooseImage()
                    }
                }

                Spacer()

                Button("Cancel") { onComplete(nil) }

                Button("Use") {
                    guard let resultImage = generateImage() else { return }
                    if let data = resultImage.pdfStampPNGData {
                        SignatureStore.shared.save(data: data)
                    }
                    onComplete(resultImage)
                }
                .disabled(!canApply)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 410)
    }

    private var canApply: Bool {
        switch creationMode {
        case .draw:
            return !strokes.isEmpty
        case .type:
            return !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .image:
            return importedImage != nil
        }
    }

    private func promptChooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let image = NSImage(contentsOf: url) {
            importedImage = image
        }
    }

    private func generateImage() -> NSImage? {
        switch creationMode {
        case .draw:
            return renderStrokesToImage()
        case .type:
            return renderTextToImage(text: typedText, fontName: selectedFontName)
        case .image:
            return importedImage
        }
    }

    private func renderStrokesToImage() -> NSImage? {
        let size = Self.canvasSize
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        if !transparentBackground {
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
        }

        NSColor.black.setStroke()
        for stroke in strokes where stroke.count > 1 {
            let path = NSBezierPath()
            path.lineWidth = 2.5
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            path.move(to: NSPoint(x: stroke[0].x, y: size.height - stroke[0].y))
            for point in stroke.dropFirst() {
                path.line(to: NSPoint(x: point.x, y: size.height - point.y))
            }
            path.stroke()
        }
        return image
    }

    private func renderTextToImage(text: String, fontName: String) -> NSImage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let size = Self.canvasSize
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        if !transparentBackground {
            NSColor.white.setFill()
            NSRect(origin: .zero, size: size).fill()
        }

        var targetFontSize: CGFloat = 44.0
        var font = NSFont(name: fontName, size: targetFontSize) ?? NSFont.systemFont(ofSize: targetFontSize)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black
        ]
        var strSize = (trimmed as NSString).size(withAttributes: attrs)
        while (strSize.width > size.width - 36 || strSize.height > size.height - 24) && targetFontSize > 14.0 {
            targetFontSize -= 2.0
            font = NSFont(name: fontName, size: targetFontSize) ?? NSFont.systemFont(ofSize: targetFontSize)
            attrs[.font] = font
            strSize = (trimmed as NSString).size(withAttributes: attrs)
        }

        let drawPoint = NSPoint(
            x: max(16, (size.width - strSize.width) / 2),
            y: max(8, (size.height - strSize.height) / 2)
        )
        (trimmed as NSString).draw(at: drawPoint, withAttributes: attrs)
        return image
    }
}

public extension NSImage {
    var pdfStampPNGData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    /// Returns a new NSImage tinted with `color`, keeping original alpha transparency.
    func tinted(with color: NSColor) -> NSImage {
        let newImage = NSImage(size: size)
        newImage.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()
        self.draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceIn)
        newImage.unlockFocus()
        return newImage
    }
}
