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

extension PDFCanvasView {
    // MARK: - Annotation Comments

    /// Opens the comments popover beside an annotation, on the page rather than in a side panel.
    func showComments(pageIndex: Int, objectNumber: Int, isNewNote: Bool = false) {
        guard window != nil,
              let thread = viewModel.annotationThread(pageIndex: pageIndex, objectNumber: objectNumber),
              let doc = viewModel.document,
              let pFrame = pageFrame(for: pageIndex) else { return }
        commentsPopover?.close()

        let popover = NSPopover()
        popover.behavior = .transient
        // A new note left empty is discarded, the way an empty text box is.
        let delegate = CommentsPopoverDelegate { [weak self, weak viewModel] in
            self?.commentsPopover = nil
            self?.commentsPopoverDelegate = nil
            guard isNewNote, let viewModel,
                  let thread = viewModel.annotationThread(pageIndex: pageIndex, objectNumber: objectNumber),
                  thread.root.text.isEmpty, thread.replies.isEmpty else { return }
            viewModel.deleteThread(thread)
        }
        popover.delegate = delegate
        commentsPopoverDelegate = delegate
        popover.contentViewController = NSHostingController(rootView: AnnotationCommentsView(
            viewModel: viewModel,
            pageIndex: pageIndex,
            objectNumber: objectNumber,
            focusNote: isNewNote,
            close: { [weak popover] in popover?.close() }
        ))
        let origin = canvasPoint(for: thread.root.rect.origin, pFrame: pFrame, pBounds: doc.pageBounds[pageIndex])
        let anchor = NSRect(
            origin: origin,
            size: CGSize(width: thread.root.rect.width * viewModel.effectiveZoom, height: thread.root.rect.height * viewModel.effectiveZoom)
        )
        commentsPopover = popover
        popover.show(relativeTo: anchor.intersection(visibleRect).isEmpty ? visibleRect : anchor, of: self, preferredEdge: .maxX)
    }

    /// The corner handles of a selected, resizable annotation.
    func drawResizeHandles(around rect: NSRect) {
        let size: CGFloat = 5.0
        for corner in [
            NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)
        ] {
            let handle = NSBezierPath(roundedRect: NSRect(x: corner.x - size / 2, y: corner.y - size / 2, width: size, height: size), xRadius: 1, yRadius: 1)
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.lineWidth = 1.0
            handle.stroke()
        }
    }

    /// A note icon matching the speech bubble of the PDF's /Name /Comment.
    func drawNoteIcon(in rect: NSRect, color: NSColor) {
        let bubble = NSBezierPath(roundedRect: NSRect(x: rect.minX + 1, y: rect.minY + 1, width: rect.width - 2, height: rect.height * 0.7), xRadius: 3, yRadius: 3)
        bubble.move(to: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.minY + rect.height * 0.7))
        bubble.line(to: NSPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY - 1))
        bubble.line(to: NSPoint(x: rect.minX + rect.width * 0.55, y: rect.minY + rect.height * 0.7))
        color.setFill()
        bubble.fill()
        NSColor.black.withAlphaComponent(0.6).setStroke()
        bubble.lineWidth = 1
        bubble.stroke()
    }

    /// A scalloped outline using the spacing and radius MuPDF measured from Acrobat, so a cloud
    /// looks the same before and after it's saved.
    func drawRevisionCloud(in rect: NSRect, intensity: CGFloat, color: NSColor) {
        guard rect.width > 0, rect.height > 0 else { return }
        let border: CGFloat = 1.5
        let zoom = viewModel.effectiveZoom
        let spacing = (intensity * 6.666667 + border * 0.8333333) * zoom
        let bulge = (intensity * 4.0 + border * 0.5) * zoom * 1.3
        let corners = [
            NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.maxY)
        ]
        let path = NSBezierPath()
        path.lineWidth = max(border * zoom, 1.0)
        path.move(to: corners[0])
        for i in 0..<4 {
            let a = corners[i]
            let b = corners[(i + 1) % 4]
            let length = hypot(b.x - a.x, b.y - a.y)
            let arcs = max(Int(length / spacing), 1)
            let ux = (b.x - a.x) / length
            let uy = (b.y - a.y) / length
            // Corners run counterclockwise in the canvas's coordinates, so outward is to the right.
            let nx = uy * (isFlipped ? -1 : 1) * bulge
            let ny = -ux * (isFlipped ? -1 : 1) * bulge
            let step = length / CGFloat(arcs)
            for n in 0..<arcs {
                let start = NSPoint(x: a.x + ux * step * CGFloat(n), y: a.y + uy * step * CGFloat(n))
                let end = NSPoint(x: start.x + ux * step, y: start.y + uy * step)
                path.curve(to: end, controlPoint1: NSPoint(x: start.x + nx, y: start.y + ny), controlPoint2: NSPoint(x: end.x + nx, y: end.y + ny))
            }
        }
        path.close()
        color.setStroke()
        path.stroke()
    }
}

final class CommentsPopoverDelegate: NSObject, NSPopoverDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func popoverDidClose(_ notification: Notification) {
        onClose()
    }
}

/// The details of one annotation, shown in a popover beside it: who made it and when, its comment,
/// its review status, and its replies.
struct AnnotationCommentsView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let pageIndex: Int
    let objectNumber: Int
    let focusNote: Bool
    let close: () -> Void

    @State private var thread: PDFAnnotationThread?
    @State private var noteText = ""
    @State private var replyText = ""
    @FocusState private var isNoteFocused: Bool

    private var isNote: Bool { thread?.root.subtype == "Text" }

    private func reload() {
        thread = viewModel.annotationThread(pageIndex: pageIndex, objectNumber: objectNumber)
    }

    private func byline(_ comment: PDFAnnotationComment) -> String {
        let author = comment.author.isEmpty ? "Unknown Author" : comment.author
        guard let date = comment.date else { return author }
        return "\(author) · \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let thread {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(thread.root.typeName)
                            .font(.headline)
                        Text(byline(thread.root))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        viewModel.deleteThread(thread)
                        self.thread = nil
                        close()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .help("Delete Annotation")
                }

                if isNote {
                    // Saved as it's typed, so a Save with the popover still open includes it.
                    TextField("Note", text: $noteText, axis: .vertical)
                        .lineLimit(2...8)
                        .focused($isNoteFocused)
                        .onChange(of: noteText) { _, text in
                            viewModel.setComment(text, of: thread)
                            reload()
                        }
                } else if !thread.root.text.isEmpty {
                    Text(thread.root.text)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Picker("Status", selection: Binding(
                    get: { thread.status },
                    set: { status in
                        viewModel.setStatus(status, of: thread)
                        reload()
                    }
                )) {
                    ForEach(PDFReviewStatus.allCases) { status in
                        Text(status.displayName).tag(status)
                    }
                }

                if !thread.replies.isEmpty {
                    Divider()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(thread.replies) { reply in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(byline(reply))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(reply.text)
                                        .textSelection(.enabled)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }

                TextField("Reply", text: $replyText)
                    .onSubmit {
                        viewModel.addReply(to: thread, text: replyText)
                        replyText = ""
                        reload()
                    }
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear {
            reload()
            noteText = thread?.root.text ?? ""
            isNoteFocused = focusNote
        }
    }
}

/// A filterable list of the document's annotations, from any app, opened from the Markup toolbar.
struct AnnotationsTableView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var threads: [PDFAnnotationThread] = []
    @State private var filter = PDFAnnotationFilter()
    @State private var selection: PDFAnnotationThread.ID?

    private var visible: [PDFAnnotationThread] { threads.filter { filter.matches($0) } }
    private var types: [String] { Array(Set(threads.map(\.root.typeName))).sorted() }
    private var authors: [String] { Array(Set(threads.map(\.root.author))).filter { !$0.isEmpty }.sorted() }

    private func show(_ id: PDFAnnotationThread.ID?) {
        guard let thread = threads.first(where: { $0.id == id }) else { return }
        viewModel.jumpToPage(thread.root.pageIndex)
        dismiss()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Annotations")
                    .font(.headline)
                Spacer()
                Picker("Type", selection: $filter.type) {
                    Text("All Types").tag(String?.none)
                    ForEach(types, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden()
                Picker("Author", selection: $filter.author) {
                    Text("All Authors").tag(String?.none)
                    ForEach(authors, id: \.self) { Text($0).tag(String?.some($0)) }
                }
                .labelsHidden()
                Picker("Date", selection: $filter.date) {
                    ForEach(PDFAnnotationDateFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .labelsHidden()
                Picker("Status", selection: $filter.status) {
                    Text("All Statuses").tag(PDFReviewStatus?.none)
                    ForEach(PDFReviewStatus.allCases) { Text($0.displayName).tag(PDFReviewStatus?.some($0)) }
                }
                .labelsHidden()
            }
            .controlSize(.small)
            .padding(14)

            Divider()

            if visible.isEmpty {
                Text(threads.isEmpty ? "No Annotations" : "No Matching Annotations")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(visible, selection: $selection) {
                    TableColumn("Page") { Text("\($0.root.pageIndex + 1)").font(.caption.monospacedDigit()) }
                        .width(min: 32, ideal: 40, max: 50)
                    TableColumn("Type") { thread in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(nsColor: thread.root.color.nsColor))
                                .frame(width: 8, height: 8)
                            Text(thread.root.typeName).font(.caption)
                        }
                    }
                    .width(min: 80, ideal: 110, max: 140)
                    TableColumn("Author") { Text($0.root.author).font(.caption) }
                        .width(min: 60, ideal: 110)
                    TableColumn("Date") { Text($0.root.date?.formatted(date: .abbreviated, time: .shortened) ?? "").font(.caption) }
                        .width(min: 80, ideal: 130)
                    TableColumn("Status") { Text($0.status == .none ? "" : $0.status.displayName).font(.caption) }
                        .width(min: 56, ideal: 70, max: 90)
                    TableColumn("Comment") { Text($0.root.text).font(.caption).lineLimit(2) }
                    TableColumn("Replies") { Text($0.replies.isEmpty ? "" : "\($0.replies.count)").font(.caption.monospacedDigit()) }
                        .width(min: 40, ideal: 48, max: 56)
                }
                .contextMenu(forSelectionType: PDFAnnotationThread.ID.self, menu: { _ in }, primaryAction: { ids in show(ids.first) })
            }

            Divider()

            HStack {
                Text("\(visible.count) of \(threads.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Show on Page") { show(selection) }
                    .disabled(selection == nil)
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(14)
        }
        .frame(minWidth: 720, minHeight: 420)
        .onAppear { threads = viewModel.annotationThreads() }
    }
}
