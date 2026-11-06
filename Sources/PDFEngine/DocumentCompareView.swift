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
import Combine
import SwiftUI
import Synchronization
import UniformTypeIdentifiers

// Compare Documents: a tab showing two documents side by side, read-only, with the text that
// differs highlighted and the two scrolled together. The comparison itself is DocumentComparison.

/// What a Compare Documents pane highlights (see `PDFViewerViewModel.compareMarks`), in page
/// coordinates by page.
public struct CompareMarks: Equatable {
    /// The words that differ, a box per line.
    public var changed: [Int: [CGRect]] = [:]
    /// Thin markers where the other document has text this one doesn't.
    public var gaps: [Int: [CGRect]] = [:]
    /// Text that's the same in the other document but in another place, a box per line:
    /// underlined, as it isn't a change to the text.
    public var moved: [Int: [CGRect]] = [:]
    /// The change chosen with Next or Previous Change.
    public var active: Active?
    /// The revision's side, shown in green; the original's is red.
    public var isRevised = false

    public struct Active: Equatable {
        public let pageIndex: Int
        public let rects: [CGRect]
    }

    public var isEmpty: Bool { changed.isEmpty && gaps.isEmpty && moved.isEmpty && active == nil }
    var color: NSColor { isRevised ? .systemGreen : .systemRed }
    static let movedColor = NSColor.systemBlue
}

/// A set-once flag that tells a comparison running off the main thread to stop.
private final class CancelFlag: Sendable {
    private let flag = Atomic<Bool>(false)
    func cancel() { flag.store(true, ordering: .relaxed) }
    var isCancelled: Bool { flag.load(ordering: .relaxed) }
}

/// Notification observers removed when the session goes, and the comparison running then
/// stopped.
private final class SessionResources: @unchecked Sendable {
    var observers: [NSObjectProtocol] = []
    var cancelFlag: CancelFlag?
    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        cancelFlag?.cancel()
    }
}

/// One Compare Documents tab: the revision is the tab's own document, read-only, and the
/// original is beside it in a view model of its own; and the comparison of their text. The tab's
/// view model owns the session (`PDFViewerViewModel.compareSession`).
@MainActor
public final class DocumentCompareSession: ObservableObject {
    public enum Status: Equatable {
        /// Opening the documents.
        case opening
        /// Reading and comparing their text.
        case comparing
        case done
        case failed(String)
    }

    /// The original, in the pane beside the tab's document.
    public let original: PDFViewerViewModel
    /// The tab's own document. It holds this session too; the tab ends the session when it
    /// closes (`end`), which lets both go.
    public let revised: PDFViewerViewModel
    @Published public private(set) var status: Status = .opening
    @Published public private(set) var comparison: DocumentComparison?
    /// Index into the comparison's changes of the one chosen with Next or Previous Change.
    @Published public private(set) var currentChange: Int?
    @Published public var options = CompareOptions(ignoresRenumbering: true) {
        didSet { if options != oldValue { compareText() } }
    }

    /// The share of the pane's height, from the top, where the line that's kept level in both
    /// documents is: about where one reads.
    static let readingLine: CGFloat = 1.0 / 3.0

    private var texts: (original: ComparedText, revised: ComparedText)?
    private var isScrollingFollower = false
    private var isPassingOnZoom = false
    /// While a zoom settles: the document being read and the text on its reading line.
    private var zoomAnchor: (side: CompareSide, offset: CGFloat)?
    private var zoomSettling: DispatchWorkItem?
    private var hasFittedWidth = false
    /// The document the other follows: the revision, unless the user scrolls the original.
    private var lastScrolled: CompareSide = .revised
    private var liveScrolling: CompareSide?
    private var scrollMap: (key: [CGFloat], map: CompareScrollMap)?
    private var comparisonGeneration = 0
    private var cancellables = Set<AnyCancellable>()
    private let resources = SessionResources()
    public let originalURL: URL

    /// Compares `original` with the document `revised` opens (or has open), which becomes
    /// read-only.
    public init(original: URL, revised: PDFViewerViewModel) {
        self.originalURL = original
        self.original = PDFViewerViewModel()
        self.revised = revised
        self.original.isComparePane = true
        revised.isComparePane = true
        // After both are set: each pane's comparison, for menu commands.
        defer {
            self.original.compareContext = self
            revised.compareContext = self
        }
        // Links to other files open as the tab's own document's do.
        self.original.onOpenNewTab = { [weak revised] url in revised?.onOpenNewTab?(url) }
        self.original.onOpenNewWindow = { DocumentWindowing.openNewWindow(url: $0) }
        self.original.documentTitle = original.lastPathComponent
        observeScrolling()
        observe(self.original)
        observe(revised)
        Task { [weak self] in await self?.original.loadDocument(from: original.path) }
    }

    public func viewModel(_ side: CompareSide) -> PDFViewerViewModel {
        side == .original ? original : revised
    }

    /// Stops comparing and lets go of both documents: the tab's view model no longer holds the
    /// session. Called when the tab closes.
    public func end() {
        resources.cancelFlag?.cancel()
        cancellables.removeAll()
        resources.observers.forEach(NotificationCenter.default.removeObserver)
        resources.observers.removeAll()
        revised.compareSession = nil
    }

    /// The original's file name.
    public var originalName: String { originalURL.lastPathComponent }
    /// The revision's file name.
    public var revisedName: String {
        revised.document.map { URL(fileURLWithPath: $0.filePath).lastPathComponent } ?? revised.documentTitle
    }

    /// The tab's title.
    public var title: String { "\(originalName) ↔ \(revisedName)" }

    private func observe(_ pane: PDFViewerViewModel) {
        // Compared whenever either document opens, or reopens after changing on disk.
        pane.$document
            .removeDuplicates { $0 === $1 }
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.documentsChanged() }
            .store(in: &cancellables)
        // The panes zoom together, so the text stays level. At once, not on the next turn of the
        // run loop: a zoom passed on late (during a pinch, say) would be passed back over the
        // newer one, and the two panes would swap zooms back and forth.
        pane.$zoomScale
            .removeDuplicates()
            .sink { [weak self, weak pane] zoom in
                MainActor.assumeIsolated {
                    guard let self, let pane else { return }
                    self.zoomChanged(to: zoom, in: pane === self.original ? .original : .revised)
                }
            }
            .store(in: &cancellables)
    }

    /// Passes a zoom on to the other pane, keeping the text on the reading line where it was:
    /// zooming lays both documents out again, and each would otherwise centre itself on its
    /// current page. Scrolls while the zoom changes are the layout's, not the user's, and are
    /// left alone until it settles.
    private func zoomChanged(to zoom: CGFloat, in side: CompareSide) {
        guard !isPassingOnZoom else { return }
        if zoomAnchor == nil, let reading = readingOffset(lastScrolled) {
            // Heights at a zoom of 1, so still right at the new zoom.
            zoomAnchor = (lastScrolled, reading)
        }
        let other = viewModel(side.other)
        if abs(other.zoomScale - zoom) > 0.001 {
            isPassingOnZoom = true
            other.zoomScale = zoom
            isPassingOnZoom = false
        }
        zoomSettling?.cancel()
        let settle = DispatchWorkItem { [weak self] in
            guard let self, let anchor = self.zoomAnchor else { return }
            self.zoomAnchor = nil
            self.setReadingOffset(anchor.offset, on: anchor.side)
            self.follow(from: anchor.side)
        }
        zoomSettling = settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: settle)
    }

    // MARK: Comparing

    private func documentsChanged() {
        guard original.document != nil, revised.document != nil else { return }
        // Opening the original made it the active document; menu commands go to the tab's own.
        if PDFViewerViewModel.active === original {
            PDFViewerViewModel.active = revised
            PDFViewerAppCoordinator.shared.registerActive(revised)
        }
        // The tab shows both names; opening the revision gave it the revision's.
        revised.documentTitle = title
        if let window = revised.currentWindow {
            window.title = title
            TabBarAppearanceHelper.refreshTabs(for: window)
        }
        if !hasFittedWidth {
            // Each pane is half a window: fit the page to it (the other pane zooms to match).
            hasFittedWidth = true
            DispatchQueue.main.async { [weak self] in self?.original.zoomToFitWidth() }
        }
        texts = nil
        compareText()
    }

    /// Reads both documents' words (unless already read) and compares them, off the main thread.
    private func compareText() {
        guard let originalDoc = original.document, let revisedDoc = revised.document else { return }
        resources.cancelFlag?.cancel()
        let flag = CancelFlag()
        resources.cancelFlag = flag
        comparisonGeneration += 1
        let generation = comparisonGeneration
        status = .comparing
        let texts = self.texts
        let options = self.options
        // The comparison on show, of the same texts, which Ignore Renumbering can start from.
        let previous = texts != nil ? comparison : nil
        let sources = [(originalDoc.filePath, original.currentDocumentPassword, original.ocrResults),
                       (revisedDoc.filePath, revised.currentDocumentPassword, revised.ocrResults)]
        Task.detached(priority: .userInitiated) { [weak self] in
            let result: Result<(ComparedText, ComparedText, DocumentComparison)?, Error> = Result {
                let read = try texts ?? {
                    let both = try sources.map { try ComparedText.load(filePath: $0.0, password: $0.1, ocrPages: $0.2, isCancelled: { flag.isCancelled }) }
                    guard let a = both[0], let b = both[1] else { return nil }
                    return (a, b)
                }()
                guard let read, !flag.isCancelled else { return nil }
                return (read.0, read.1, DocumentComparison(original: read.0, revised: read.1, options: options, previous: previous))
            }
            await MainActor.run {
                guard let self, generation == self.comparisonGeneration else { return }
                switch result {
                case .success(let value?):
                    self.texts = (value.0, value.1)
                    self.show(value.2)
                case .success(nil):
                    break
                case .failure(let error):
                    self.status = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func show(_ comparison: DocumentComparison) {
        self.comparison = comparison
        scrollMap = nil
        currentChange = nil
        status = .done
        for side in [CompareSide.original, .revised] {
            viewModel(side).compareMarks = CompareMarks(
                changed: comparison.highlights(on: side),
                gaps: comparison.gapMarkers(on: side),
                moved: comparison.highlights(on: side, for: comparison.moves),
                isRevised: side == .revised
            )
        }
        follow(from: lastScrolled)
    }

    // MARK: Moving between changes

    public var changeCount: Int { comparison?.changes.count ?? 0 }

    public func nextChange() {
        guard changeCount > 0 else { return }
        go(to: currentChange.map { min($0 + 1, changeCount - 1) } ?? firstChange(after: true))
    }

    public func previousChange() {
        guard changeCount > 0 else { return }
        go(to: currentChange.map { max($0 - 1, 0) } ?? firstChange(after: false))
    }

    /// With no change chosen yet: the first change below the reading line in the document last
    /// scrolled, or the last one above it.
    private func firstChange(after: Bool) -> Int {
        guard let comparison, let reading = readingOffset(lastScrolled), let offset = layoutOffsets(lastScrolled) else { return 0 }
        let offsets = comparison.changes.map { change in
            comparison.location(of: change, on: lastScrolled).flatMap { offset(ComparePoint(pageIndex: $0.pageIndex, y: $0.rect.midY)) } ?? 0
        }
        if after {
            return offsets.firstIndex { $0 > reading + 1 } ?? changeCount - 1
        }
        return offsets.lastIndex { $0 < reading - 1 } ?? 0
    }

    /// Chooses change `index` and scrolls both documents to it.
    public func go(to index: Int) {
        guard let comparison, comparison.changes.indices.contains(index) else { return }
        currentChange = index
        let change = comparison.changes[index]
        for side in [CompareSide.original, .revised] {
            let pane = viewModel(side)
            guard let location = comparison.location(of: change, on: side) else { continue }
            let words = change.words(on: side)
            let rects: [CGRect] = words.isEmpty
                ? (pane.compareMarks.gaps[location.pageIndex] ?? []).filter { $0.intersects(location.rect.insetBy(dx: -4, dy: 0)) }.prefix(1).map { $0 }
                : comparison.highlights(on: side, for: [change])[location.pageIndex] ?? [location.rect]
            pane.compareMarks.active = CompareMarks.Active(pageIndex: location.pageIndex, rects: rects)
            scroll(side, toPage: location.pageIndex, y: location.rect.midY)
        }
    }

    // MARK: Scrolling together

    private func observeScrolling() {
        let center = NotificationCenter.default
        let bounds = center.addObserver(forName: NSView.boundsDidChangeNotification, object: nil, queue: nil) { [weak self] note in
            let clip = note.object as? NSClipView
            MainActor.assumeIsolated {
                guard let self, let clip, !self.isScrollingFollower, let side = self.side(of: clip) else { return }
                self.scrolled(side)
            }
        }
        // Dragging a scroller (and trackpad scrolling) is a live scroll.
        let liveStart = center.addObserver(forName: NSScrollView.willStartLiveScrollNotification, object: nil, queue: nil) { [weak self] note in
            let scrollView = note.object as? NSScrollView
            MainActor.assumeIsolated {
                guard let self, let scrollView else { return }
                self.liveScrolling = self.side(of: scrollView.contentView)
            }
        }
        let liveEnd = center.addObserver(forName: NSScrollView.didEndLiveScrollNotification, object: nil, queue: nil) { [weak self] _ in
            MainActor.assumeIsolated { self?.liveScrolling = nil }
        }
        resources.observers += [bounds, liveStart, liveEnd]
    }

    private func side(of clip: NSClipView) -> CompareSide? {
        if clip === original.hostScrollView?.contentView { return .original }
        if clip === revised.hostScrollView?.contentView { return .revised }
        return nil
    }

    /// `side` scrolled. The revision is the tab's document, moved by its sidebar (outline,
    /// search) and toolbar as well as by the user, so whatever moves it, the original follows.
    /// The original leads only while the user scrolls it; if it moves by itself while following
    /// (its pages laid out again, say), it's put back level with the revision.
    private func scrolled(_ side: CompareSide) {
        // Laid out again for a new zoom: put right once it settles (see zoomChanged).
        guard zoomAnchor == nil else { return }
        if side == .original && !isUserScrolling(.original) {
            follow(from: lastScrolled)
            return
        }
        lastScrolled = side
        follow(from: side)
    }

    /// Whether the user is scrolling `side`: with the mouse wheel or trackpad just now, by
    /// dragging its scroller, or with a key or click in it (a key, a menu command's shortcut, or
    /// a link followed).
    private func isUserScrolling(_ side: CompareSide) -> Bool {
        guard let scrollView = viewModel(side).hostScrollView else { return false }
        if liveScrolling == side { return true }
        if let pdfScrollView = scrollView as? PDFScrollView, Date().timeIntervalSince(pdfScrollView.lastUserScroll) < 0.5 { return true }
        let userEvents: Set<NSEvent.EventType> = [.keyDown, .leftMouseDown, .leftMouseUp]
        if let canvas = canvas(side), let window = canvas.window, window.firstResponder === canvas,
           let event = NSApp.currentEvent, userEvents.contains(event.type) { return true }
        return false
    }

    private func canvas(_ side: CompareSide) -> PDFCanvasView? {
        viewModel(side).hostScrollView?.documentView as? PDFCanvasView
    }

    /// A point's height in `side`'s layout, at a zoom of 1.
    private func layoutOffset(_ side: CompareSide, _ point: ComparePoint) -> CGFloat? {
        layoutOffsets(side)?(point)
    }

    /// A function giving points' heights in `side`'s layout, at a zoom of 1, for many points: a
    /// page's place on the canvas is worked out once, the first time a point on it is asked for,
    /// rather than for every point (a large document has tens of thousands of anchors).
    private func layoutOffsets(_ side: CompareSide) -> ((ComparePoint) -> CGFloat?)? {
        let pane = viewModel(side)
        guard let canvas = canvas(side) else { return nil }
        let zoom = pane.effectiveZoom
        // Each page's height on the layout as a + b·y, for y on the page.
        var lines: [Int: (a: CGFloat, b: CGFloat)?] = [:]
        return { point in
            let line: (a: CGFloat, b: CGFloat)?
            if let known = lines[point.pageIndex] {
                line = known
            } else {
                line = canvas.pageGeometry(for: point.pageIndex).map { geometry in
                    let bounds = geometry.pageBounds
                    let top = geometry.canvasRect(forPageRect: CGRect(x: bounds.midX, y: bounds.minY, width: 1, height: 1)).midY
                    let bottom = geometry.canvasRect(forPageRect: CGRect(x: bounds.midX, y: bounds.maxY, width: 1, height: 1)).midY
                    let a = bounds.height > 0 ? (bottom - top) / bounds.height : 0
                    return (a, top - a * bounds.minY)
                }
                lines[point.pageIndex] = line
            }
            guard let line else { return nil }
            return (line.a * point.y + line.b - 16) / zoom
        }
    }

    /// The reading line's height in `side`'s layout, at a zoom of 1.
    private func readingOffset(_ side: CompareSide) -> CGFloat? {
        guard let clip = viewModel(side).hostScrollView?.contentView else { return nil }
        let y = clip.bounds.minY + clip.bounds.height * Self.readingLine
        return (y - 16) / viewModel(side).effectiveZoom
    }

    /// The map between the two layouts, rebuilt when either is laid out differently.
    private func currentScrollMap() -> CompareScrollMap? {
        guard let comparison, original.document != nil, revised.document != nil,
              canvas(.original) != nil, canvas(.revised) != nil else { return nil }
        // Heights at a zoom of 1 don't change with the zoom, so zooming doesn't rebuild the map;
        // laying the pages out differently does.
        let key: [CGFloat] = [original, revised].flatMap { pane in
            [CGFloat(pane.viewRotationDegrees), pane.isTwoPageMode ? 1 : 0, pane.effectiveTotalHeight, CGFloat(pane.effectivePageYOffsets.count)]
        }
        if let scrollMap, scrollMap.key == key { return scrollMap.map }
        guard let originalOffsets = layoutOffsets(.original), let revisedOffsets = layoutOffsets(.revised) else { return nil }
        let map = CompareScrollMap(anchors: comparison.anchors) { side, point in
            (side == .original ? originalOffsets : revisedOffsets)(point) ?? 0
        }
        scrollMap = (key, map)
        return map
    }

    /// Scrolls the other document so the text matching the reading line of `side` is level with
    /// it.
    private func follow(from side: CompareSide) {
        guard let map = currentScrollMap(), let reading = readingOffset(side) else { return }
        setReadingOffset(map.offset(reading, from: side), on: side.other, across: horizontalPosition(side))
    }

    /// How far across `side` is scrolled, from 0 (its left edge) to 1 (its right), when zoomed in
    /// past its width; nil when it all fits. Zoomed in, the other shows the same part of the page.
    private func horizontalPosition(_ side: CompareSide) -> CGFloat? {
        guard let clip = viewModel(side).hostScrollView?.contentView, let canvas = canvas(side) else { return nil }
        let range = canvas.frame.width - clip.bounds.width
        return range > 1 ? clip.bounds.minX / range : nil
    }

    /// Scrolls `side` to put `offset` (in its layout, at a zoom of 1) on the reading line.
    /// Scrolls `side` to put `offset` (in its layout, at a zoom of 1) on the reading line, and,
    /// given `across` (see `horizontalPosition`), as far across.
    private func setReadingOffset(_ offset: CGFloat, on side: CompareSide, across: CGFloat? = nil) {
        let pane = viewModel(side)
        guard let scrollView = pane.hostScrollView, let canvas = canvas(side) else { return }
        let clip = scrollView.contentView
        var y = offset * pane.effectiveZoom + 16 - clip.bounds.height * Self.readingLine
        y = min(max(0, y), max(0, canvas.frame.height - clip.bounds.height))
        let range = max(0, canvas.frame.width - clip.bounds.width)
        let x = across.map { min(max(0, $0), 1) * range } ?? clip.bounds.minX
        guard abs(y - clip.bounds.minY) > 0.5 || abs(x - clip.bounds.minX) > 0.5 else { return }
        isScrollingFollower = true
        clip.scroll(to: NSPoint(x: x, y: y))
        scrollView.reflectScrolledClipView(clip)
        isScrollingFollower = false
    }

    /// Scrolls `side` to put a height on a page on the reading line, without the other following.
    private func scroll(_ side: CompareSide, toPage pageIndex: Int, y: CGFloat) {
        guard let offset = layoutOffset(side, ComparePoint(pageIndex: pageIndex, y: y)) else { return }
        let pane = viewModel(side)
        guard let scrollView = pane.hostScrollView, let canvas = canvas(side) else { return }
        let clip = scrollView.contentView
        var target = offset * pane.effectiveZoom + 16 - clip.bounds.height * Self.readingLine
        target = min(max(0, target), max(0, canvas.frame.height - clip.bounds.height))
        isScrollingFollower = true
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: target))
        scrollView.reflectScrolledClipView(clip)
        isScrollingFollower = false
    }
}

// MARK: - The tab's views

/// The line over each pane of a Compare Documents tab naming its document.
struct ComparePaneHeader: View {
    let side: CompareSide
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color(nsColor: side == .original ? .systemRed : .systemGreen))
                .frame(width: 8, height: 8)
            Text(side == .original ? "Original" : "Revised")
                .font(.caption.weight(.semibold))
            Text(name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .help(name)
    }
}

/// The original's side of a Compare Documents tab, beside the tab's own document.
struct CompareOriginalPane: View {
    @ObservedObject var session: DocumentCompareSession
    @ObservedObject var viewModel: PDFViewerViewModel

    init(session: DocumentCompareSession) {
        self.session = session
        self.viewModel = session.original
    }

    var body: some View {
        VStack(spacing: 0) {
            ComparePaneHeader(side: .original, name: session.originalName)
            Divider()
            PDFVirtualizedScrollView(viewModel: viewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay {
                    if viewModel.document == nil {
                        ProgressView().controlSize(.small)
                    }
                }
        }
    }
}

/// The Changes tab of a Compare Documents tab's sidebar: each change, with what was taken out
/// and what was put in, and the comparison's options.
struct CompareChangesSidebar: View {
    @ObservedObject var session: DocumentCompareSession

    /// Whether either document has links within it, which Ignore Renumbering follows. Until the
    /// comparison is read, it may.
    private var hasLinks: Bool {
        guard let comparison = session.comparison else { return true }
        return !comparison.original.links.isEmpty || !comparison.revised.links.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                status
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Ignore Case", isOn: $session.options.ignoresCase)
                    Toggle("Ignore Punctuation", isOn: $session.options.ignoresPunctuation)
                    Toggle("Ignore Renumbering", isOn: $session.options.ignoresRenumbering)
                        .help(hasLinks
                              ? "Leaves out new clause, figure, table and page numbers in contents entries and cross-references that link to the same place in both, and in the headings and captions they link to"
                              : "These documents have no links within them to follow, so renumbering can't be told apart from other changes")
                        .disabled(!hasLinks)
                }
                .toggleStyle(.checkbox)
                .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            if let comparison = session.comparison, !comparison.changes.isEmpty {
                counter(of: comparison)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
            Divider()
            if let comparison = session.comparison, !comparison.changes.isEmpty {
                // A stack, not a List: a List is a table view, which AppKit warns about when the
                // rows change while it's handling a click in one.
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(comparison.changes.indices, id: \.self) { index in
                                // A button, which takes the first click even before the window
                                // is in front.
                                Button { session.go(to: index) } label: {
                                    CompareChangeRow(comparison: comparison, index: index, isSelected: session.currentChange == index)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(index)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                    }
                    .onChange(of: session.currentChange) { _, index in
                        guard let index else { return }
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                    }
                }
            } else {
                Spacer()
            }
        }
    }

    /// "3 of 12", or the number of changes, with Previous and Next Change: as the Search tab
    /// shows its matches.
    private func counter(of comparison: DocumentComparison) -> some View {
        let count = comparison.changes.count
        return HStack {
            Text(session.currentChange.map { "\($0 + 1) of \(count)" } ?? (count == 1 ? "1 change" : "\(count) changes"))
                .font(.caption2.monospacedDigit().weight(.medium))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Self.capsule)
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 2) {
                Button(action: session.previousChange) {
                    Image(systemName: "chevron.up")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Previous Change (⌥⌘↑)")
                .disabled(session.currentChange == 0)
                Button(action: session.nextChange) {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Next Change (⌥⌘↓)")
                .disabled(session.currentChange == count - 1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Self.capsule)
        }
    }

    private static var capsule: some View {
        Capsule(style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }

    @ViewBuilder
    private var status: some View {
        switch session.status {
        case .opening, .comparing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(session.status == .opening ? "Opening…" : "Comparing…")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        case .failed(let message):
            Label("Couldn't compare: \(message)", systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.secondary)
        case .done:
            if let comparison = session.comparison {
                VStack(alignment: .leading, spacing: 2) {
                    if comparison.changes.isEmpty {
                        Text("No differences in the text")
                            .font(.callout.weight(.semibold))
                    }
                    if !comparison.moves.isEmpty {
                        Text(comparison.moves.count == 1 ? "1 passage in another place, underlined" : "\(comparison.moves.count) passages in another place, underlined")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .help("Text that's the same in both documents but in another place, such as a table that falls on the other side of a page break. It isn't counted as a change.")
                    }
                    if let warning = Self.warning(for: comparison) {
                        Text(warning)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Why the comparison may not be much use, if it may not be.
    static func warning(for comparison: DocumentComparison) -> String? {
        let withoutText = comparison.original.pagesWithoutText + comparison.revised.pagesWithoutText
        if comparison.original.words.isEmpty || comparison.revised.words.isEmpty {
            return "A document has no text to compare."
        }
        if comparison.similarity < 0.2 {
            return "These documents have little text in common."
        }
        if withoutText > 0 {
            return withoutText == 1 ? "1 page has no text to compare." : "\(withoutText) pages have no text to compare."
        }
        return nil
    }
}

/// One change in the Changes list: the words taken out, struck through, over the words put in,
/// and where it is.
private struct CompareChangeRow: View {
    let comparison: DocumentComparison
    let index: Int
    let isSelected: Bool

    /// Up to `limit` of the change's words on `side`.
    private func text(on side: CompareSide, limit: Int = 30) -> String {
        let range = comparison.changes[index].words(on: side)
        let words = comparison.text(on: side).words
        let shown = range.prefix(limit).map { words[$0].text }.joined(separator: " ")
        return range.count > limit ? shown + " …" : shown
    }

    var body: some View {
        let change = comparison.changes[index]
        let page = comparison.location(of: change, on: .revised)?.pageIndex
            ?? comparison.location(of: change, on: .original)?.pageIndex
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                if !change.original.isEmpty {
                    Text(text(on: .original))
                        .strikethrough()
                        .foregroundStyle(Color(nsColor: .systemRed))
                        .lineLimit(3)
                }
                if !change.revised.isEmpty {
                    Text(text(on: .revised))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .lineLimit(3)
                }
            }
            .font(.callout)
            Spacer(minLength: 4)
            if let page {
                Text("\(page + 1)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .help("Page \(page + 1) of the revision")
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        )
    }
}

// MARK: - Choosing the documents

/// The sheet File > Compare Documents opens: which document is the original and which the
/// revision, each one of the open documents or a file chosen.
struct CompareDocumentsSheet: View {
    let openDocuments: [URL]
    @State var original: URL?
    @State var revised: URL?
    let onCompare: (URL, URL) -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Compare Documents")
                .font(.headline)
            Text("The revision's changes are highlighted in both, and the two scroll together.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Original:").gridColumnAlignment(.trailing)
                    documentMenu(selection: $original)
                }
                GridRow {
                    Text("Revised:").gridColumnAlignment(.trailing)
                    documentMenu(selection: $revised)
                }
            }
            HStack {
                Button("Swap") { swap(&original, &revised) }
                    .disabled(original == nil && revised == nil)
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Compare") {
                    if let original, let revised { onCompare(original, revised) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(original == nil || revised == nil || original == revised)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func documentMenu(selection: Binding<URL?>) -> some View {
        Menu {
            ForEach(openDocuments, id: \.self) { url in
                Button(url.lastPathComponent) { selection.wrappedValue = url }
            }
            if !openDocuments.isEmpty { Divider() }
            Button("Choose File…") {
                if let url = Self.chooseFile() { selection.wrappedValue = url }
            }
        } label: {
            Text(selection.wrappedValue?.lastPathComponent ?? "Choose a Document")
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity)
        .help(selection.wrappedValue?.path ?? "")
    }

    private static func chooseFile() -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = OpenableDocumentTypes.contentTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

extension DocumentWindowing {
    /// The documents open in any window, in the order they were opened.
    @MainActor
    static var openDocumentURLs: [URL] {
        var seen = Set<String>()
        return PDFViewerAppCoordinator.shared.openViewModels.compactMap { vm -> URL? in
            guard let path = vm.document?.filePath, !vm.isComparePane, seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path)
        }
    }

    /// Asks which two documents to compare, as a sheet on `window` (or a window of its own), then
    /// opens them in a Compare Documents tab. `original` starts as the document in front, and
    /// `revised` as the only other open document if there's just one.
    @MainActor
    public static func promptCompareDocuments(from window: NSWindow?, original: URL? = nil, revised: URL? = nil) {
        let open = openDocumentURLs
        let front = window.flatMap { PDFViewerAppCoordinator.shared.viewModel(for: $0)?.document?.filePath }.map { URL(fileURLWithPath: $0) }
        let first = original ?? front
        let second = revised ?? {
            let others = open.filter { $0 != first }
            return others.count == 1 ? others[0] : nil
        }()
        let host = window?.attachedSheet == nil ? window : nil
        var sheetWindow: NSWindow?
        let close = {
            guard let sheetWindow else { return }
            if let parent = sheetWindow.sheetParent { parent.endSheet(sheetWindow) } else { sheetWindow.close() }
        }
        let view = CompareDocumentsSheet(
            openDocuments: open,
            original: first,
            revised: second,
            onCompare: { original, revised in
                close()
                openComparison(original: original, revised: revised, besides: host)
            },
            onCancel: { close() }
        )
        let panel = NSWindow(contentViewController: NSHostingController(rootView: view))
        panel.styleMask = host == nil ? [.titled, .closable] : [.titled]
        panel.title = "Compare Documents"
        panel.isReleasedWhenClosed = false
        sheetWindow = panel
        if let host {
            host.beginSheet(panel)
        } else {
            panel.center()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    /// Opens `original` and `revised` in a Compare Documents tab, in `sourceWindow`'s tab group if
    /// given (replacing it if it's an empty Start window), or a window of its own.
    @MainActor
    @discardableResult
    public static func openComparison(original: URL, revised: URL, besides sourceWindow: NSWindow?) -> NSWindow {
        let window = makeBareWindow(tabbingIdentifier: sourceWindow?.tabbingIdentifier)
        window.title = "\(original.lastPathComponent) ↔ \(revised.lastPathComponent)"
        window.representedURL = revised
        let view = PDFViewerMainView(
            initialURL: revised,
            comparingOriginal: original,
            onOpenNewTab: { [weak window] url in
                if let window { addTab(url: url, to: window) } else { openNewWindow(url: url) }
            },
            onOpenNewWindow: { openNewWindow(url: $0) }
        )
        window.contentViewController = NSHostingController(rootView: view)
        let replacesStart = isStandaloneEmptyStartWindow(sourceWindow)
        if let sourceWindow, !replacesStart, sourceWindow.isVisible {
            sourceWindow.tabbingMode = .preferred
            sourceWindow.addTabbedWindow(window, ordered: .above)
        } else if let sourceWindow, replacesStart {
            window.setFrame(sourceWindow.frame, display: false)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        if replacesStart { closeStandaloneEmptyStartWindows(except: window) }
        TabBarAppearanceHelper.refreshTabs(for: window)
        return window
    }
}
