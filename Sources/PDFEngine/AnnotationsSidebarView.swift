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


import SwiftUI

/// The sidebar's Comments tab: every annotation in the document, by page, with its comment,
/// status and replies, as in Acrobat's Comments pane. Clicking one goes to it on the page;
/// double-clicking also opens its comments there, to reply or set a status.
struct AnnotationsSidebarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var threadsByPage: [Int: [PDFAnnotationThread]] = [:]
    @State private var isLoading = true
    @State private var filter = PDFAnnotationFilter()
    @State private var selection: PDFAnnotationThread.ID?
    /// Bumped to read every page again, when anything but a single page may have changed.
    @State private var fullReloads = 0

    private var allThreads: [PDFAnnotationThread] {
        threadsByPage.keys.sorted().flatMap { threadsByPage[$0] ?? [] }
    }

    private var visibleByPage: [(page: Int, threads: [PDFAnnotationThread])] {
        threadsByPage.keys.sorted().compactMap { page in
            let threads = (threadsByPage[page] ?? []).filter { filter.matches($0) }
            return threads.isEmpty ? nil : (page, threads)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if threadsByPage.isEmpty {
                ContentUnavailableView {
                    Label("No Comments", systemImage: "text.bubble")
                } description: {
                    Text("Annotations and their replies appear here. To reply to one, double-click it on the page.")
                }
            } else if visibleByPage.isEmpty {
                ContentUnavailableView {
                    Label("No Matching Comments", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Show All") { filter = PDFAnnotationFilter() }
                }
            } else {
                list
            }
        }
        .task(id: "\(viewModel.document?.filePath ?? "")|\(fullReloads)") {
            await loadAllPages()
        }
        .onChange(of: viewModel.annotationChange) { _, change in
            if let page = change.page {
                let threads = viewModel.annotationThreads(pageIndex: page)
                threadsByPage[page] = threads.isEmpty ? nil : threads
            } else {
                fullReloads += 1
            }
        }
    }

    private var header: some View {
        HStack {
            Text(countText)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("Type", selection: $filter.type) {
                    Text("All Types").tag(String?.none)
                    ForEach(Array(Set(allThreads.map(\.root.typeName))).sorted(), id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Author", selection: $filter.author) {
                    Text("All Authors").tag(String?.none)
                    ForEach(Array(Set(allThreads.map(\.root.author))).filter { !$0.isEmpty }.sorted(), id: \.self) { Text($0).tag(String?.some($0)) }
                }
                Picker("Status", selection: $filter.status) {
                    Text("All Statuses").tag(PDFReviewStatus?.none)
                    ForEach(PDFReviewStatus.allCases) { Text($0.displayName).tag(PDFReviewStatus?.some($0)) }
                }
                Picker("Date", selection: $filter.date) {
                    ForEach(PDFAnnotationDateFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                if filter != PDFAnnotationFilter() {
                    Divider()
                    Button("Show All") { filter = PDFAnnotationFilter() }
                }
            } label: {
                Image(systemName: filter == PDFAnnotationFilter() ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Filter Comments")
            .disabled(threadsByPage.isEmpty)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
    }

    private var countText: String {
        let total = threadsByPage.values.reduce(0) { $0 + $1.count }
        let shown = visibleByPage.reduce(0) { $0 + $1.threads.count }
        let noun = total == 1 ? "Annotation" : "Annotations"
        return shown == total ? "\(total) \(noun)" : "\(shown) of \(total) \(noun)"
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(visibleByPage, id: \.page) { group in
                Section("Page \(viewModel.document?.displayLabel(forPage: group.page) ?? "\(group.page + 1)")") {
                    ForEach(group.threads) { thread in
                        AnnotationSidebarRow(thread: thread)
                            .tag(thread.id)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .contextMenu(forSelectionType: PDFAnnotationThread.ID.self) { ids in
            if let thread = thread(ids.first) {
                Button("Show on Page") { viewModel.revealAnnotation(thread) }
                Button("Comments…") { viewModel.revealAnnotation(thread, opensComments: true) }
                Divider()
                Button("Delete", role: .destructive) { viewModel.deleteThread(thread) }
            }
        } primaryAction: { ids in
            if let thread = thread(ids.first) {
                viewModel.revealAnnotation(thread, opensComments: true)
            }
        }
        .onChange(of: selection) { _, id in
            if let thread = thread(id) {
                viewModel.revealAnnotation(thread)
            }
        }
    }

    private func thread(_ id: PDFAnnotationThread.ID?) -> PDFAnnotationThread? {
        guard let id else { return nil }
        return allThreads.first { $0.id == id }
    }

    /// Reads every page's annotations, letting the window keep up between pages: a long
    /// document takes a moment.
    private func loadAllPages() async {
        guard let pageCount = viewModel.document?.pageCount else {
            threadsByPage = [:]
            isLoading = false
            return
        }
        isLoading = true
        var found: [Int: [PDFAnnotationThread]] = [:]
        for page in 0..<pageCount {
            let threads = viewModel.annotationThreads(pageIndex: page)
            if !threads.isEmpty { found[page] = threads }
            if page % 100 == 99 {
                await Task.yield()
                if Task.isCancelled { return }
            }
        }
        threadsByPage = found
        isLoading = false
    }
}

/// One annotation in the Comments tab: its kind and color, who made it and when, its status,
/// its comment, and its replies beneath.
private struct AnnotationSidebarRow: View {
    let thread: PDFAnnotationThread

    private func byline(_ comment: PDFAnnotationComment) -> String {
        let author = comment.author.isEmpty ? "Unknown Author" : comment.author
        guard let date = comment.date else { return author }
        return "\(author) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AnnotationColorSwatch(color: thread.root.color, size: 10)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(thread.root.typeName)
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 4)
                    if thread.status != .none {
                        Text(thread.status.displayName)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.secondary.opacity(0.15)))
                    }
                }
                Text(byline(thread.root))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !thread.root.text.isEmpty {
                    Text(thread.root.text)
                        .font(.callout)
                        .lineLimit(4)
                }
                ForEach(thread.replies) { reply in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(byline(reply))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(reply.text)
                            .font(.caption)
                            .lineLimit(3)
                    }
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.35))
                            .frame(width: 2)
                    }
                    .padding(.top, 2)
                }
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }
}
