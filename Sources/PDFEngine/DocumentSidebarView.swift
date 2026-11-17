//
// VectorPDF
// Copyright (c) 2026 Thomas Derham
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or (at your
// option) any later version.
//
// This application links to and incorporates the MuPDF framework, which is
// Copyright (c) 2006-2026 Artifex Software, Inc.
//
// VECTORPDF IS PROVIDED "AS IS" WITHOUT ANY WARRANTY, AND ALL
// WARRANTIES, WHETHER EXPRESSED OR IMPLIED, INCLUDING WARRANTY OF
// MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, ARE DISCLAIMED.
//

import AppKit
import SwiftUI

/// The sidebar's Document tab: what the document holds besides its pages, one part at a time,
/// chosen from a menu at the top: layers, attachments, signatures, form fields, links and
/// named destinations. Each part is offered only when the document has some, and the tab shows
/// only when it has at least one.
struct DocumentSidebarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    var body: some View {
        let sections = viewModel.documentSidebarSections
        let shown = viewModel.shownDocumentSidebarSection
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                if sections.count > 1, let shown {
                    Picker("Show", selection: Binding(
                        get: { shown },
                        set: { viewModel.documentSidebarSection = $0 }
                    )) {
                        ForEach(sections, id: \.self) { section in
                            Label(section.title, systemImage: section.systemImage).tag(section)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .help("Choose what the Document tab shows")
                } else if let shown {
                    Label(shown.title, systemImage: shown.systemImage)
                        .font(.callout)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .frame(height: 30)

            Divider()

            switch shown {
            case .layers:
                LayersSidebarView(viewModel: viewModel)
            case .attachments:
                AttachmentsSidebarView(viewModel: viewModel)
            case .signatures:
                SignaturesSidebarList(viewModel: viewModel)
            case .fields:
                FormFieldsSidebarList(viewModel: viewModel)
            case .links:
                LinksSidebarList(viewModel: viewModel)
            case .destinations:
                DestinationsSidebarList(viewModel: viewModel)
            case nil:
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: shown, initial: true) { _, section in
            // Not while the view is being updated: loading changes the view model.
            if let section { DispatchQueue.main.async { viewModel.loadDocumentSection(section) } }
        }
    }
}

/// A caption and an optional filter field, at the top of each list.
private struct SectionHeader: View {
    let caption: String
    @Binding var filter: String
    var showsFilter = true

    var body: some View {
        HStack(spacing: 8) {
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 4)
            if showsFilter {
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(maxWidth: 130)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

/// Shown while a list is being read.
private struct LoadingRow: View {
    var progress: Double?
    var message = "Reading the document…"

    var body: some View {
        VStack(spacing: 6) {
            if let progress {
                ProgressView(value: progress)
                    .frame(maxWidth: 160)
            } else {
                ProgressView().controlSize(.small)
            }
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor private func pageTitle(_ viewModel: PDFViewerViewModel, _ page: Int) -> String {
    "Page \(viewModel.document?.displayLabel(forPage: page) ?? "\(page + 1)")"
}

private func matches(_ filter: String, _ texts: String?...) -> Bool {
    let filter = filter.trimmingCharacters(in: .whitespaces)
    guard !filter.isEmpty else { return true }
    return texts.contains { $0?.localizedCaseInsensitiveContains(filter) == true }
}

private func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

// MARK: - Signatures

/// Each signature, as checked: few enough for a plain list, with room to say what was found.
struct SignaturesSidebarList: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    var body: some View {
        VStack(spacing: 0) {
            if let results = viewModel.signatureValidations {
                SectionHeader(caption: "\(results.count) Signature\(results.count == 1 ? "" : "s")", filter: .constant(""), showsFilter: false)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(results, id: \.objectNumber) { result in
                            SignatureRow(viewModel: viewModel, result: result)
                            Divider()
                        }
                    }
                }
            } else {
                LoadingRow(message: "Checking the signatures…")
            }
        }
    }
}

private struct SignatureRow: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let result: PDFSignatureValidation

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: result.statusSymbol)
                .foregroundStyle(result.statusColor)
                .font(.title3)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(result.displayName)
                        .font(.callout.weight(.semibold))
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if let page = result.pageIndex {
                        Text(pageTitle(viewModel, page))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(result.statusLine)
                    .font(.caption)
                    .foregroundStyle(result.hasProblems ? Color.red : Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(result.detailLines, id: \.self) { line in
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !result.certificates.isEmpty {
                    Button("Show Certificate…") { viewModel.showCertificate(of: result) }
                        .controlSize(.small)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture { reveal() }
        .contextMenu {
            Button("Show on Page") { reveal() }
                .disabled(result.pageIndex == nil)
            Button("Show Certificate…") { viewModel.showCertificate(of: result) }
                .disabled(result.certificates.isEmpty)
        }
    }

    private func reveal() {
        guard let page = result.pageIndex else { return }
        viewModel.revealPageRect(result.rect, onPage: page)
    }
}

extension PDFSignatureValidation {
    var statusSymbol: String {
        if hasProblems { return "xmark.seal.fill" }
        if case .unsupported = integrity { return "questionmark.circle.fill" }
        return isFullyValid ? "checkmark.seal.fill" : "exclamationmark.triangle.fill"
    }

    var statusColor: Color {
        if hasProblems { return .red }
        if case .unsupported = integrity { return .secondary }
        return isFullyValid ? .green : .orange
    }

    /// What else the Signatures list says about it, a line each.
    var detailLines: [String] {
        var lines: [String] = []
        if let identityDetail, integrity == .intact { lines.append(identityDetail) }
        if let timestamp {
            lines.append("Signed \(timestamp.formatted(date: .abbreviated, time: .shortened)), by a timestamp authority's clock")
        } else if let claimedSigningTime {
            lines.append("Signed \(claimedSigningTime.formatted(date: .abbreviated, time: .shortened)), by the signer's clock")
        }
        if let signerEmail { lines.append(signerEmail) }
        if let issuerName, issuerName != signerName { lines.append("Certificate issued by \(issuerName)") }
        if let nameInDocument, nameInDocument != signerName { lines.append("Name in the document: \(nameInDocument)") }
        if let reason { lines.append("Reason: \(reason)") }
        if let location { lines.append("Location: \(location)") }
        return lines
    }
}

// MARK: - Form fields

struct FormFieldsSidebarList: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            if let entries = viewModel.formFieldEntries {
                let signatures = entries.filter { $0.type == .signature }.count
                SectionHeader(caption: caption(entries.count, signatures: signatures), filter: $filter)
                Divider()
                DocumentContentsTable(
                    key: [viewModel.documentListsRevision, filter.hashValue, viewModel.signatureValidations?.count ?? -1],
                    makeRows: { rows(entries) },
                    onSelect: { item in reveal(item, in: entries) },
                    menuItems: { item in
                        guard let field = entries.first(where: { $0.id == item.id }) else { return [] }
                        var items: [(title: String?, action: () -> Void)] = [
                            ("Show on Page", { viewModel.revealPageRect(field.rect, onPage: field.pageIndex) }),
                            (nil, {}),
                            ("Copy Name", { copyToPasteboard(field.name) }),
                        ]
                        if !field.displayValue.isEmpty { items.append(("Copy Value", { copyToPasteboard(field.value) })) }
                        return items
                    }
                )
            } else {
                LoadingRow()
            }
        }
    }

    private func caption(_ count: Int, signatures: Int) -> String {
        var text = "\(count) Field\(count == 1 ? "" : "s")"
        if signatures > 0 { text += ", \(signatures) Signature\(signatures == 1 ? "" : "s")" }
        return text
    }

    private func reveal(_ item: ContentsItem, in entries: [PDFFormFieldEntry]) {
        guard let field = entries.first(where: { $0.id == item.id }) else { return }
        viewModel.revealPageRect(field.rect, onPage: field.pageIndex)
    }

    private func rows(_ entries: [PDFFormFieldEntry]) -> [ContentsRow] {
        let shown = filter.isEmpty ? entries : entries.filter { matches(filter, $0.displayName, $0.name, $0.value, $0.signature?.signer) }
        var rows: [ContentsRow] = []
        var page = -1
        for field in shown {
            if field.pageIndex != page {
                page = field.pageIndex
                rows.append(.header(pageTitle(viewModel, page)))
            }
            var item = ContentsItem(id: field.id, symbol: field.type.systemImage, title: field.displayName, page: field.pageIndex)
            if field.isRequired { item.trailing = "Required" }
            if let validation = viewModel.signatureValidations?.first(where: { $0.objectNumber == field.objectNumber }) {
                item.symbol = validation.statusSymbol
                item.details = [validation.displayName, validation.statusLine]
                if validation.hasProblems { item.warning = "See Signatures for details" }
            } else if let signature = field.signature {
                item.details = signature.summaryLines
                if signature.changedSinceSigning == true { item.warning = "Changed since it was signed" }
            } else if !field.displayValue.isEmpty {
                item.details = [field.displayValue]
            }
            var tip = [field.name.isEmpty ? field.displayName : field.name, field.type.displayName]
            if field.isReadOnly { tip.append("Read-only") }
            if let reason = field.signature?.reason { tip.append("Reason: \(reason)") }
            if let location = field.signature?.location { tip.append("Location: \(location)") }
            item.tooltip = tip.joined(separator: "\n")
            rows.append(.item(item))
        }
        return rows
    }
}

extension PDFSignatureInfo {
    /// What the Document tab says about it, a line each.
    var summaryLines: [String] {
        guard isSigned else { return ["Not signed"] }
        var first = [signer.map { "Signed by \($0)" } ?? "Signed"]
        if let date { first.append(date.formatted(date: .abbreviated, time: .shortened)) }
        var lines = [first.joined(separator: ", ")]
        if changedSinceSigning == false { lines.append("Not changed since it was signed") }
        if let certification { lines.append(certification.description) }
        return lines
    }
}

// MARK: - Links

struct LinksSidebarList: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var filter = ""
    @State private var kind: LinkKind = .all

    var body: some View {
        VStack(spacing: 0) {
            if let links = viewModel.documentLinks {
                SectionHeader(caption: "\(links.count) Link\(links.count == 1 ? "" : "s")", filter: $filter)
                Picker("Kind", selection: $kind) {
                    ForEach(LinkKind.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
                if let progress = viewModel.documentLinksProgress {
                    ProgressView(value: progress)
                        .controlSize(.small)
                        .padding(.horizontal, 10)
                        .padding(.bottom, 4)
                }
                Divider()
                DocumentContentsTable(
                    key: [viewModel.documentListsRevision, filter.hashValue, kind.hashValue],
                    refreshKey: viewModel.documentLinkTexts.count,
                    decorate: { item in
                        // The text under the link, once read: it becomes the title.
                        guard item.details.isEmpty, let text = viewModel.documentLinkTexts[item.id] else { return item }
                        var item = item
                        item.details = [item.title]
                        item.title = text
                        return item
                    },
                    makeRows: { rows(links) },
                    onSelect: { item in
                        if let link = link(item, in: links) { viewModel.revealPageRect(link.rect, onPage: link.pageIndex) }
                    },
                    onOpen: { item in
                        if let link = link(item, in: links) { viewModel.followDocumentLink(link) }
                    },
                    onShow: { item in
                        // The text under links is read for a page when its rows first show.
                        if let page = item.page { viewModel.loadLinkTexts(onPage: page) }
                    },
                    menuItems: { item in
                        guard let link = link(item, in: links) else { return [] }
                        var items: [(title: String?, action: () -> Void)] = [
                            ("Show on Page", { viewModel.revealPageRect(link.rect, onPage: link.pageIndex) }),
                            (link.isExternal ? "Open Link" : "Go to Destination", { viewModel.followDocumentLink(link) }),
                        ]
                        if link.isExternal, let uri = link.uri {
                            items.append((nil, {}))
                            items.append(("Copy Address", { copyToPasteboard(uri) }))
                        }
                        return items
                    }
                )
            } else {
                LoadingRow(progress: viewModel.documentLinksProgress)
            }
        }
    }

    private func link(_ item: ContentsItem, in links: [PDFDocumentLink]) -> PDFDocumentLink? {
        // Links are listed in order; their ids carry their page, so look near it.
        links.first { $0.id == item.id }
    }

    private func rows(_ links: [PDFDocumentLink]) -> [ContentsRow] {
        let texts = viewModel.documentLinkTexts
        var rows: [ContentsRow] = []
        rows.reserveCapacity(links.count + links.count / 8)
        var page = -1
        for link in links {
            guard kind == .all || (kind == .web) == link.isExternal else { continue }
            let destination = link.targetPage.map { pageTitle(viewModel, $0) } ?? link.destinationDescription
            let text = texts[link.id] ?? ""
            guard filter.isEmpty || matches(filter, text, destination) else { continue }
            if link.pageIndex != page {
                page = link.pageIndex
                rows.append(.header(pageTitle(viewModel, page)))
            }
            rows.append(.item(ContentsItem(
                id: link.id,
                symbol: link.isExternal ? "globe" : "arrow.turn.down.right",
                title: text.isEmpty ? destination : text,
                details: text.isEmpty ? [] : [destination],
                tooltip: link.uri ?? destination,
                page: link.pageIndex
            )))
        }
        return rows
    }
}

enum LinkKind: String, CaseIterable {
    case all = "All", web = "Web", inDocument = "In Document"
}

// MARK: - Named destinations

struct DestinationsSidebarList: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var filter = ""

    var body: some View {
        VStack(spacing: 0) {
            if let destinations = viewModel.namedDestinations {
                let count = destinations.count
                SectionHeader(caption: "\(count) Destination\(count == 1 ? "" : "s")", filter: $filter)
                Divider()
                DocumentContentsTable(
                    key: [viewModel.documentListsRevision, filter.hashValue],
                    makeRows: {
                        let shown = filter.isEmpty ? destinations : destinations.filter { matches(filter, $0.name) }
                        return shown.map { destination in
                            .item(ContentsItem(
                                id: destination.name,
                                title: destination.name,
                                trailing: destination.pageIndex.map { pageTitle(viewModel, $0) } ?? "Missing",
                                tooltip: destination.name
                            ))
                        }
                    },
                    onSelect: { item in
                        if let destination = destinations.first(where: { $0.name == item.id }) {
                            viewModel.goToNamedDestination(destination)
                        }
                    },
                    menuItems: { item in [("Copy Name", { copyToPasteboard(item.id) })] }
                )
            } else {
                LoadingRow()
            }
        }
    }
}
