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

    /// The annotation whose comments a double-click at `pagePoint` opens. One made in this
    /// session is hit exactly. One from the file is known only by its bounds, so a shape or
    /// cloud counts only near its edge, and lines and freehand drawings, whose bounds cover text
    /// they don't touch, aren't hit at all; they can still be right-clicked.
    func commentsTarget(at pagePoint: CGPoint, pageIndex: Int) -> Int? {
        if let annot = viewModel.pageAnnotations[pageIndex]?.reversed().first(where: { $0.contains(pagePoint: pagePoint) }) {
            return annot.documentObjectNumber
        }
        let outlined: Set<String> = ["Square", "Circle", "Polygon"]
        let unbounded: Set<String> = ["Line", "PolyLine", "Ink"]
        return viewModel.annotationThreads(pageIndex: pageIndex)
            .filter { thread in
                let root = thread.root
                guard !unbounded.contains(root.subtype), root.rect.insetBy(dx: -3, dy: -3).contains(pagePoint) else { return false }
                let isOutline = root.isCloud || outlined.contains(root.subtype)
                return !isOutline || !root.rect.insetBy(dx: 12, dy: 12).contains(pagePoint)
            }
            .min { $0.root.rect.width * $0.root.rect.height < $1.root.rect.width * $1.root.rect.height }?
            .root.objectNumber
    }

    /// Selects an annotation the Comments sidebar scrolled to, if it was made in this session,
    /// outlines it for a moment, and opens its comments if asked.
    func showRevealedAnnotation(_ reveal: AnnotationReveal) {
        if let annot = viewModel.pageAnnotations[reveal.pageIndex]?.first(where: { $0.documentObjectNumber == reveal.objectNumber }) {
            selectedAnnotation = (id: annot.id, pageIndex: reveal.pageIndex)
        } else {
            selectedAnnotation = nil
        }
        revealedAnnotationOutline = (reveal.pageIndex, reveal.rect)
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.revealedAnnotationOutline?.rect == reveal.rect else { return }
            self.revealedAnnotationOutline = nil
            self.needsDisplay = true
        }
        if reveal.opensComments {
            // After the scroll, so the popover points at the annotation where it now is.
            DispatchQueue.main.async { [weak self] in
                self?.showComments(pageIndex: reveal.pageIndex, objectNumber: reveal.objectNumber)
            }
        }
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
        drawRevisionCloud(around: [
            NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
            NSPoint(x: rect.maxX, y: rect.maxY), NSPoint(x: rect.minX, y: rect.maxY)
        ], intensity: intensity, color: color)
    }

    /// The same, round the polygon `points` in canvas coordinates: equal arcs, spaced evenly
    /// along the whole outline, each bulging away from the inside.
    func drawRevisionCloud(around points: [NSPoint], intensity: CGFloat, color: NSColor) {
        guard points.count >= 3 else { return }
        let border: CGFloat = 1.5
        let zoom = viewModel.effectiveZoom
        let spacing = (intensity * 6.666667 + border * 0.8333333) * zoom
        let bulge = (intensity * 4.0 + border * 0.5) * zoom * 1.3

        // Points every `spacing` or so round the outline.
        let closed = points + [points[0]]
        let lengths = zip(closed, closed.dropFirst()).map { hypot($1.x - $0.x, $1.y - $0.y) }
        let perimeter = lengths.reduce(0, +)
        guard perimeter > 0 else { return }
        let count = max(Int((perimeter / spacing).rounded()), 3)
        let step = perimeter / CGFloat(count)
        var stops: [NSPoint] = []
        var edge = 0
        var edgeStart: CGFloat = 0
        for n in 0..<count {
            let distance = CGFloat(n) * step
            while edge < lengths.count - 1, distance > edgeStart + lengths[edge] {
                edgeStart += lengths[edge]
                edge += 1
            }
            let t = lengths[edge] > 0 ? (distance - edgeStart) / lengths[edge] : 0
            let a = closed[edge], b = closed[edge + 1]
            stops.append(NSPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
        }

        // Right of the direction of travel is outside when the outline runs the way a
        // rectangle's corners do from (minX, minY) to (maxX, minY); left otherwise.
        let outward: CGFloat = CloudOutline.signedArea(points) > 0 ? 1 : -1

        let path = NSBezierPath()
        path.lineWidth = max(border * zoom, 1.0)
        path.lineJoinStyle = .round
        path.move(to: stops[0])
        for i in stops.indices {
            let a = stops[i]
            let b = stops[(i + 1) % stops.count]
            let length = hypot(b.x - a.x, b.y - a.y)
            guard length > 0 else { continue }
            let normal = NSPoint(x: outward * (b.y - a.y) / length, y: -outward * (b.x - a.x) / length)
            path.curve(to: b, controlPoint1: NSPoint(x: a.x + normal.x * bulge, y: a.y + normal.y * bulge),
                       controlPoint2: NSPoint(x: b.x + normal.x * bulge, y: b.y + normal.y * bulge))
        }
        path.close()
        color.setStroke()
        path.stroke()
    }

    /// A rectangle or oval filling `box`, or a line through `ends` with `ending` at the last,
    /// all in canvas points; `strokeWidth` is in page points.
    func drawShape(_ type: PDFAnnotationType, box: NSRect, ends: [NSPoint], strokeWidth: CGFloat, ending: PDFLineEnding?, color: NSColor) {
        let zoom = viewModel.effectiveZoom
        let path: NSBezierPath
        switch type {
        case .square:
            path = NSBezierPath(rect: box)
        case .circle:
            path = NSBezierPath(ovalIn: box)
        case .line where ends.count >= 2:
            path = NSBezierPath()
            path.move(to: ends[0])
            path.line(to: ends[1])
        default:
            return
        }
        path.lineWidth = max(strokeWidth * zoom, 1.0)
        color.setStroke()
        path.stroke()
        if type == .line, let ending, let head = ending.path(tip: ends[1], dx: ends[0].x - ends[1].x, dy: ends[0].y - ends[1].y, scale: max(1, strokeWidth) * zoom) {
            head.path.lineWidth = path.lineWidth
            if head.filled {
                color.setFill()
                head.path.fill()
            } else {
                head.path.stroke()
            }
        }
    }

    /// An annotation from the file being edited, drawn as the document draws it, where a drag
    /// in progress would put it, with its selection handles.
    func drawFileAnnotation(_ annot: PDFAnnotation, pFrame: NSRect, pBounds: CGRect) {
        guard let number = annot.documentObjectNumber, let initialRect = annot.rect else { return }
        let zoom = viewModel.effectiveZoom
        let scale = zoom * (window?.backingScaleFactor ?? 2)
        if let picture = fileAnnotationPictures[number], picture.revision == annot.appearanceRevision, picture.scale == scale {
            // Drawn already
        } else if let fresh = viewModel.document?.renderAnnotation(pageIndex: annot.pageIndex, objectNumber: number, scale: scale) {
            fileAnnotationPictures[number] = (annot.appearanceRevision, scale, fresh.image, fresh.bounds)
        }
        let drag = activeAnnotationDrag.flatMap { $0.id == annot.id ? $0 : nil }
        var rect = initialRect
        var ends = annot.inkPoints
        if let drag {
            if annot.type == .line {
                ends = updatedLineEnds(of: annot, part: drag.part, delta: drag.currentDelta)
                if drag.part == .entireAnnotation {
                    rect = initialRect.offsetBy(dx: drag.currentDelta.width, dy: drag.currentDelta.height)
                }
            } else {
                rect = updatedRect(from: initialRect, part: drag.part, delta: drag.currentDelta)
            }
        }
        if let picture = fileAnnotationPictures[number] {
            // Its picture, carried the way the drag carries its box.
            let sx = initialRect.width > 0 ? rect.width / initialRect.width : 1
            let sy = initialRect.height > 0 ? rect.height / initialRect.height : 1
            let pageBox = CGRect(
                x: rect.minX + (picture.bounds.minX - initialRect.minX) * sx,
                y: rect.minY + (picture.bounds.minY - initialRect.minY) * sy,
                width: picture.bounds.width * sx,
                height: picture.bounds.height * sy
            )
            let origin = canvasPoint(for: pageBox.origin, pFrame: pFrame, pBounds: pBounds)
            let box = NSRect(origin: origin, size: CGSize(width: pageBox.width * zoom, height: pageBox.height * zoom))
            let isDraggingAnEnd = drag.map { $0.part == .lineStart || $0.part == .lineEnd } ?? false
            NSImage(cgImage: picture.image, size: box.size).draw(in: box, from: .zero, operation: .sourceOver, fraction: isDraggingAnEnd ? 0.35 : 1, respectFlipped: true, hints: nil)
        }
        let canvasEnds = ends.map { canvasPoint(for: $0, pFrame: pFrame, pBounds: pBounds) }
        if let drag, drag.part == .lineStart || drag.part == .lineEnd, canvasEnds.count >= 2 {
            drawShape(.line, box: .zero, ends: canvasEnds, strokeWidth: annot.strokeWidth, ending: annot.lineEnding, color: annot.color.nsColor)
        }
        guard selectedAnnotation?.id == annot.id else { return }
        if annot.type == .line {
            drawEndHandles(canvasEnds)
            return
        }
        let origin = canvasPoint(for: rect.origin, pFrame: pFrame, pBounds: pBounds)
        let selRect = NSRect(origin: origin, size: CGSize(width: rect.width * zoom, height: rect.height * zoom)).insetBy(dx: -2.5, dy: -2.5)
        let selPath = NSBezierPath(roundedRect: selRect, xRadius: 3, yRadius: 3)
        selPath.lineWidth = 1.5
        NSColor.controlAccentColor.setStroke()
        selPath.stroke()
        if annot.isResizableFromFile {
            drawResizeHandles(around: selRect)
        }
    }

    /// The round handles on the ends of a selected line.
    func drawEndHandles(_ points: [NSPoint]) {
        for point in points {
            let handle = NSBezierPath(ovalIn: NSRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
            NSColor.white.setFill()
            handle.fill()
            NSColor.controlAccentColor.setStroke()
            handle.lineWidth = 1.5
            handle.stroke()
        }
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
