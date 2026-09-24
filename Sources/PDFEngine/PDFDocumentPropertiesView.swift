import SwiftUI
import AppKit

public struct PDFDocumentPropertiesView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: PropertiesTab = .general
    @State private var geometryPageIndex: Int = 0
    @State private var geometryUnit: BoxUnit = .points
    @State private var fontSearchQuery: String = ""

    public enum PropertiesTab: String, CaseIterable, Identifiable {
        case general = "General"
        case security = "Security"
        case geometry = "Page Geometry"
        case fonts = "Fonts"

        public var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "doc.text"
            case .security: return "lock.shield"
            case .geometry: return "aspectratio"
            case .fonts: return "textformat"
            }
        }
    }

    public enum BoxUnit: String, CaseIterable, Identifiable {
        case points = "Points"
        case inches = "Inches"
        case millimeters = "Millimeters"

        public var id: String { rawValue }

        func format(width: CGFloat, height: CGFloat) -> String {
            switch self {
            case .points:
                return String(format: "%.1f × %.1f pt", width, height)
            case .inches:
                return String(format: "%.2f × %.2f in", width / 72.0, height / 72.0)
            case .millimeters:
                return String(format: "%.1f × %.1f mm", width * 25.4 / 72.0, height * 25.4 / 72.0)
            }
        }

        func formatRect(_ r: CGRect) -> String {
            switch self {
            case .points:
                return String(format: "Origin: (%.1f, %.1f) • Size: %.1f × %.1f pt", r.origin.x, r.origin.y, r.size.width, r.size.height)
            case .inches:
                return String(format: "Origin: (%.2f, %.2f) • Size: %.2f × %.2f in", r.origin.x / 72.0, r.origin.y / 72.0, r.size.width / 72.0, r.size.height / 72.0)
            case .millimeters:
                return String(format: "Origin: (%.1f, %.1f) • Size: %.1f × %.1f mm", r.origin.x * 25.4 / 72.0, r.origin.y * 25.4 / 72.0, r.size.width * 25.4 / 72.0, r.size.height * 25.4 / 72.0)
            }
        }
    }

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
        _geometryPageIndex = State(initialValue: viewModel.currentPageIndex)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header / Tab picker
            HStack {
                Picker("", selection: $selectedTab) {
                    ForEach(PropertiesTab.allCases) { tab in
                        Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Content
            Group {
                if let report = viewModel.documentInspectionReport {
                    switch selectedTab {
                    case .general:
                        generalTabView(report.metadata)
                    case .security:
                        securityTabView(meta: report.metadata, perms: report.permissions)
                    case .geometry:
                        geometryTabView(boxes: report.pageBoxes)
                    case .fonts:
                        fontsTabView(fonts: report.fonts)
                    }
                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Reading document properties...")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 580, height: 460)
        .onAppear {
            if viewModel.documentInspectionReport == nil {
                viewModel.refreshInspectionReport()
            }
            geometryPageIndex = viewModel.currentPageIndex
        }
    }

    // MARK: - General Tab
    private func generalTabView(_ meta: DocumentMetadata) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Primary File Summary Card
                HStack(spacing: 14) {
                    Image(systemName: "doc.richtext.fill")
                        .font(.system(size: 38))
                        .foregroundColor(.accentColor)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(meta.title.isEmpty ? viewModel.documentTitle : meta.title)
                            .font(.headline)
                            .lineLimit(2)
                        HStack(spacing: 8) {
                            Text(meta.pdfVersion)
                                .font(.caption.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .cornerRadius(4)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("\(meta.pageCount) \(meta.pageCount == 1 ? "page" : "pages")")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(meta.fileSizeDescription)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)

                Divider()

                // Metadata Key-Value pairs
                VStack(spacing: 10) {
                    metadataRow(label: "Title", value: meta.title)
                    metadataRow(label: "Author", value: meta.author)
                    metadataRow(label: "Subject", value: meta.subject)
                    metadataRow(label: "Keywords", value: meta.keywords)
                }

                Divider()

                VStack(spacing: 10) {
                    metadataRow(label: "Created", value: meta.creationDate)
                    metadataRow(label: "Modified", value: meta.modificationDate)
                    metadataRow(label: "Application", value: meta.creator)
                    metadataRow(label: "PDF Producer", value: meta.producer)
                    metadataRow(label: "File Path", value: viewModel.document?.filePath ?? "")
                }
            }
            .padding(20)
        }
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .trailing)

            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("—")
                    .foregroundColor(.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(value)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Security Tab
    private func securityTabView(meta: DocumentMetadata, perms: DocumentSecurityPermissions) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Encryption Summary Banner
                HStack(spacing: 12) {
                    Image(systemName: meta.isEncrypted ? "lock.fill" : "lock.open.fill")
                        .font(.system(size: 26))
                        .foregroundColor(meta.isEncrypted ? .orange : .green)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(meta.isEncrypted ? "Document Encrypted" : "No Encryption")
                            .font(.headline)
                        Text(meta.isEncrypted ? "Security Method: \(meta.encryptionMethod)" : "Document opens without password protection")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(meta.isEncrypted ? Color.orange.opacity(0.1) : Color.green.opacity(0.1))
                .cornerRadius(8)

                Text("Document Permissions")
                    .font(.headline)

                VStack(spacing: 8) {
                    permissionRow(title: "Printing", allowed: perms.canPrint)
                    permissionRow(title: "High Quality Printing", allowed: perms.canPrintHighQuality)
                    permissionRow(title: "Content Copying / Text Extraction", allowed: perms.canCopy)
                    permissionRow(title: "Document Modification", allowed: perms.canModify)
                    permissionRow(title: "Adding Comments & Annotations", allowed: perms.canAnnotate)
                    permissionRow(title: "Filling Form Fields", allowed: perms.canFillForms)
                    permissionRow(title: "Content Extraction for Accessibility", allowed: perms.canAccessibility)
                    permissionRow(title: "Page Assembly & Manipulation", allowed: perms.canAssemble)
                }
            }
            .padding(20)
        }
    }

    private func permissionRow(title: String, allowed: Bool) -> some View {
        HStack {
            Image(systemName: allowed ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(allowed ? .green : .red)
                .font(.system(size: 15))

            Text(title)
                .font(.body)

            Spacer()

            Text(allowed ? "Allowed" : "Not Allowed")
                .font(.subheadline)
                .foregroundColor(allowed ? .primary : .secondary)
        }
        .padding(.vertical, 3)
    }

    // MARK: - Geometry Tab
    private func geometryTabView(boxes: [PageBoxGeometry]) -> some View {
        let totalPages = max(1, boxes.count)
        let safeIndex = max(0, min(geometryPageIndex, totalPages - 1))
        let box = boxes.indices.contains(safeIndex) ? boxes[safeIndex] : nil

        return VStack(spacing: 14) {
            // Controls bar: Page Stepper and Unit Picker
            HStack {
                HStack(spacing: 6) {
                    Text("Page:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Stepper("\(safeIndex + 1) of \(totalPages)", value: $geometryPageIndex, in: 0...(totalPages - 1))
                        .font(.subheadline.bold())
                }

                Spacer()

                Picker("Units:", selection: $geometryUnit) {
                    ForEach(BoxUnit.allCases) { u in
                        Text(u.rawValue).tag(u)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            Divider()

            if let b = box {
                ScrollView {
                    VStack(spacing: 12) {
                        geometryBoxCard(
                            name: "MediaBox",
                            desc: "Defines the physical boundaries of the medium on which the page is printed.",
                            rect: b.mediaBox,
                            isExplicit: true,
                            badgeColor: .blue
                        )

                        geometryBoxCard(
                            name: "CropBox",
                            desc: "Defines the region to which page contents are clipped upon display and print.",
                            rect: b.cropBox,
                            isExplicit: b.hasCropBox,
                            badgeColor: .indigo
                        )

                        geometryBoxCard(
                            name: "BleedBox",
                            desc: "Defines the clipping region for page production in professional printing.",
                            rect: b.bleedBox,
                            isExplicit: b.hasBleedBox,
                            badgeColor: .orange
                        )

                        geometryBoxCard(
                            name: "TrimBox",
                            desc: "Defines the intended finished dimensions of the page after trimming.",
                            rect: b.trimBox,
                            isExplicit: b.hasTrimBox,
                            badgeColor: .green
                        )

                        geometryBoxCard(
                            name: "ArtBox",
                            desc: "Defines the meaningful extent of the page content (e.g. artwork bounds).",
                            rect: b.artBox,
                            isExplicit: b.hasArtBox,
                            badgeColor: .purple
                        )
                    }
                    .padding(20)
                }
            } else {
                Text("No geometry data available for this page")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func geometryBoxCard(name: String, desc: String, rect: CGRect, isExplicit: Bool, badgeColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(name)
                    .font(.headline)
                    .foregroundColor(badgeColor)

                if isExplicit {
                    Text("Defined")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badgeColor.opacity(0.15))
                        .foregroundColor(badgeColor)
                        .cornerRadius(4)
                } else {
                    Text("Inherited")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundColor(.secondary)
                        .cornerRadius(4)
                }

                Spacer()

                Text(geometryUnit.format(width: rect.width, height: rect.height))
                    .font(.system(.body, design: .monospaced).bold())
            }

            Text(geometryUnit.formatRect(rect))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)

            Text(desc)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Fonts Tab
    private func fontsTabView(fonts: [PDFEmbeddedFont]) -> some View {
        let filteredFonts = fontSearchQuery.isEmpty ? fonts : fonts.filter {
            $0.rawName.localizedCaseInsensitiveContains(fontSearchQuery) ||
            $0.cleanName.localizedCaseInsensitiveContains(fontSearchQuery) ||
            $0.subtype.localizedCaseInsensitiveContains(fontSearchQuery) ||
            $0.encoding.localizedCaseInsensitiveContains(fontSearchQuery)
        }

        let embeddedCount = fonts.filter { $0.isEmbedded }.count
        let subsetCount = fonts.filter { $0.isSubset }.count

        return VStack(spacing: 0) {
            // Font filter and summary count
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Filter fonts...", text: $fontSearchQuery)
                        .textFieldStyle(.plain)
                    if !fontSearchQuery.isEmpty {
                        Button(action: { fontSearchQuery = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))

                Spacer()

                Text("\(fonts.count) \(fonts.count == 1 ? "font" : "fonts") (\(subsetCount) subsets, \(embeddedCount) embedded)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Divider()

            if filteredFonts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "textformat.alt")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text(fontSearchQuery.isEmpty ? "No fonts found in document" : "No fonts match “\(fontSearchQuery)”")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredFonts) { font in
                    HStack(alignment: .center, spacing: 10) {
                        Image(systemName: "f.cursive")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(font.cleanName)
                                    .font(.headline)
                                if font.isSubset {
                                    Text("Subset (\(font.rawName.prefix(6)))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(spacing: 8) {
                                Text("Type: \(font.subtype)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("•")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Encoding: \(font.encoding)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        HStack(spacing: 6) {
                            if font.isSubset {
                                Text("Embedded Subset")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15))
                                    .foregroundColor(.green)
                                    .cornerRadius(4)
                            } else if font.isEmbedded {
                                Text("Embedded")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.blue.opacity(0.15))
                                    .foregroundColor(.blue)
                                    .cornerRadius(4)
                            } else {
                                Text("System / Fallback")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.15))
                                    .foregroundColor(.orange)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }
}
