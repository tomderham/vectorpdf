import SwiftUI
import AppKit
import UniformTypeIdentifiers

public enum SplitMode: String, CaseIterable, Identifiable {
    case everyNPages = "Every N Pages"
    case singlePages = "Single Pages"
    case customRanges = "Page Ranges"

    public var id: String { rawValue }
}

public enum NamingPattern: String, CaseIterable, Identifiable {
    case partNumber = "Part Number (e.g. _Part_1)"
    case pageRange = "Page Range (e.g. _Pages_1-5)"

    public var id: String { rawValue }
}

public struct PDFSplitPDFView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var splitMode: SplitMode = .everyNPages
    @State private var pagesPerFile: Int = 5
    @State private var customRangesText: String = ""
    @State private var namingPattern: NamingPattern = .partNumber
    @State private var filePrefix: String = ""
    @State private var outputDirectoryURL: URL?

    @State private var isProcessing: Bool = false
    @State private var progressFraction: Double = 0.0
    @State private var progressStatus: String = ""
    @State private var generatedFiles: [URL] = []
    @State private var errorMessage: String?
    @State private var isComplete: Bool = false

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var totalPages: Int {
        viewModel.document?.pageCount ?? 1
    }

    private var defaultBaseName: String {
        guard let doc = viewModel.document else { return "Document" }
        return ((doc.filePath as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    private var computedRanges: [[Int]] {
        switch splitMode {
        case .everyNPages:
            let step = max(1, pagesPerFile)
            var ranges: [[Int]] = []
            var start = 0
            while start < totalPages {
                let end = min(start + step, totalPages)
                ranges.append(Array(start..<end))
                start = end
            }
            return ranges

        case .singlePages:
            return (0..<totalPages).map { [$0] }

        case .customRanges:
            return parseCustomRanges(customRangesText, maxPage: totalPages)
        }
    }

    private func parseCustomRanges(_ text: String, maxPage: Int) -> [[Int]] {
        let segments = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var result: [[Int]] = []
        for segment in segments {
            if segment.contains("-") {
                let parts = segment.split(separator: "-").map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count == 2, let s = Int(parts[0]), let e = Int(parts[1]), s > 0, e >= s {
                    let clampedStart = max(1, min(s, maxPage))
                    let clampedEnd = max(1, min(e, maxPage))
                    if clampedStart <= clampedEnd {
                        result.append(Array((clampedStart - 1)...(clampedEnd - 1)))
                    }
                }
            } else if let p = Int(segment), p > 0, p <= maxPage {
                result.append([p - 1])
            }
        }
        return result
    }

    private func generateFileName(index: Int, range: [Int]) -> String {
        let prefix = filePrefix.trimmingCharacters(in: .whitespaces).isEmpty ? defaultBaseName : filePrefix.trimmingCharacters(in: .whitespaces)
        let ext = "pdf"
        switch namingPattern {
        case .partNumber:
            return "\(prefix)_Part_\(index + 1).\(ext)"
        case .pageRange:
            if range.count == 1 {
                return "\(prefix)_Page_\(range[0] + 1).\(ext)"
            } else {
                return "\(prefix)_Pages_\(range.first! + 1)-\(range.last! + 1).\(ext)"
            }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 24))
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Split PDF")
                        .font(.headline)
                    Text("\(defaultBaseName).pdf • \(totalPages) pages total")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            if isComplete {
                // Success View
                VStack(spacing: 18) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("PDF Split Successfully!")
                        .font(.title2.bold())

                    Text("Created \(generatedFiles.count) PDF files in:")
                        .font(.callout)
                        .foregroundColor(.secondary)

                    if let dir = outputDirectoryURL {
                        Text(dir.path)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        Button("Reveal in Finder") {
                            if !generatedFiles.isEmpty {
                                NSWorkspace.shared.activateFileViewerSelecting(generatedFiles)
                            } else if let dir = outputDirectoryURL {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: dir.path)
                            }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Done") {
                            dismiss()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else if isProcessing {
                // Processing View
                VStack(spacing: 16) {
                    ProgressView(value: progressFraction, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 320)

                    Text(progressStatus)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                // Configuration View
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        // Split Mode
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Split Method")
                                .font(.subheadline.bold())

                            Picker("Method", selection: $splitMode) {
                                ForEach(SplitMode.allCases) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)

                            if splitMode == .everyNPages {
                                HStack(spacing: 8) {
                                    Text("Pages per file:")
                                        .font(.callout)

                                    TextField("", text: Binding(
                                        get: { "\(pagesPerFile)" },
                                        set: { newStr in
                                            let digits = newStr.filter { $0.isNumber }
                                            if let val = Int(digits) {
                                                pagesPerFile = max(1, val)
                                            } else if digits.isEmpty {
                                                pagesPerFile = 1
                                            }
                                        }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                                    .multilineTextAlignment(.center)

                                    Stepper("", value: $pagesPerFile, in: 1...max(pagesPerFile, totalPages))
                                        .labelsHidden()

                                    Text("pages")
                                        .font(.callout)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            } else if splitMode == .customRanges {
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("e.g. 1-5, 6-12, 13-20", text: $customRangesText)
                                        .textFieldStyle(.roundedBorder)
                                    Text("Enter comma-separated page numbers or ranges (1 to \(totalPages)).")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }

                        Divider()

                        // Output Directory
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Save Location")
                                .font(.subheadline.bold())

                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.secondary)
                                Text(outputDirectoryURL?.path ?? "Choose Destination...")
                                    .font(.callout)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Choose…") {
                                    chooseOutputDirectory()
                                }
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(6)
                        }

                        Divider()

                        // File Naming
                        VStack(alignment: .leading, spacing: 8) {
                            Text("File Naming")
                                .font(.subheadline.bold())

                            HStack {
                                Text("Prefix:")
                                    .font(.callout)
                                TextField("File Prefix", text: $filePrefix)
                                    .textFieldStyle(.roundedBorder)
                            }

                            Picker("Naming Style", selection: $namingPattern) {
                                ForEach(NamingPattern.allCases) { pattern in
                                    Text(pattern.rawValue).tag(pattern)
                                }
                            }
                            .pickerStyle(.radioGroup)
                        }

                        Divider()

                        // Live Preview Summary
                        VStack(alignment: .leading, spacing: 8) {
                            let ranges = computedRanges
                            HStack {
                                Text("Output Preview")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text("\(ranges.count) files will be created")
                                    .font(.caption.bold())
                                    .foregroundColor(.accentColor)
                            }

                            if ranges.isEmpty {
                                Text("No valid pages specified.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                VStack(alignment: .leading, spacing: 4) {
                                    ForEach(Array(ranges.prefix(4).enumerated()), id: \.offset) { idx, r in
                                        HStack {
                                            Image(systemName: "doc")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                            Text(generateFileName(index: idx, range: r))
                                                .font(.system(size: 11, design: .monospaced))
                                            Spacer()
                                            Text("Pages \(r.first! + 1)–\(r.last! + 1) (\(r.count) p.)")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    if ranges.count > 4 {
                                        Text("... and \(ranges.count - 4) more files")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .padding(.top, 2)
                                    }
                                }
                                .padding(8)
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(6)
                            }
                        }

                        if let error = errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .padding(20)
                }

                Divider()

                // Footer
                HStack {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button("Split PDF") {
                        startSplitting()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(computedRanges.isEmpty || outputDirectoryURL == nil)
                    .keyboardShortcut(.defaultAction)
                }
                .padding()
            }
        }
        .frame(width: 520, height: 500)
        .onAppear {
            initializeDefaults()
        }
    }

    private func initializeDefaults() {
        filePrefix = defaultBaseName
        if let docPath = viewModel.document?.filePath {
            outputDirectoryURL = URL(fileURLWithPath: docPath).deletingLastPathComponent()
        } else {
            outputDirectoryURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        }
        pagesPerFile = max(1, min(10, totalPages))
        customRangesText = "1-\(min(5, totalPages))"
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        if let initial = outputDirectoryURL {
            panel.directoryURL = initial
        }
        if panel.runModal() == .OK, let url = panel.url {
            outputDirectoryURL = url
        }
    }

    private func startSplitting() {
        guard let doc = viewModel.document, let outDir = outputDirectoryURL else { return }
        let ranges = computedRanges
        guard !ranges.isEmpty else { return }

        let fileNames = ranges.enumerated().map { generateFileName(index: $0.offset, range: $0.element) }

        isProcessing = true
        progressFraction = 0.0
        progressStatus = "Preparing to split..."
        errorMessage = nil

        Task.detached(priority: .userInitiated) {
            do {
                let files = try doc.split(
                    pageRanges: ranges,
                    outputDirectory: outDir,
                    fileNames: fileNames
                ) { fraction, status in
                    Task { @MainActor in
                        self.progressFraction = fraction
                        self.progressStatus = status
                    }
                }
                await MainActor.run {
                    self.generatedFiles = files
                    self.isProcessing = false
                    self.isComplete = true
                }
            } catch {
                await MainActor.run {
                    self.isProcessing = false
                    self.errorMessage = "Failed to split PDF: \(error.localizedDescription)"
                }
            }
        }
    }
}
