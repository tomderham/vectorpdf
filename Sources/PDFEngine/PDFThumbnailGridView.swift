//
//  PDFThumbnailGridView.swift
//  VectorPDF
//
//  Created for VectorPDF.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Pure logic for calculating drop insertion slots and target reorder indices.
public enum ThumbnailDropLogic {
    /// Determines whether dropping `fromIndices` into `slot` moves pages to a new position.
    /// If no items are being dragged (`fromIndices.isEmpty`), no slot is valid.
    public static func isValidSlot(slot: Int, fromIndices: Set<Int>, pageCount: Int) -> Bool {
        guard !fromIndices.isEmpty, pageCount > 0, slot >= 0, slot <= pageCount else { return false }

        let original = Array(0..<pageCount)
        let sortedSelection = fromIndices.sorted()

        var remaining: [Int] = []
        remaining.reserveCapacity(pageCount - sortedSelection.count)
        for i in original {
            if !fromIndices.contains(i) {
                remaining.append(i)
            }
        }

        let beforeCount = sortedSelection.filter { $0 < slot }.count
        let insertIndex = slot - beforeCount
        guard insertIndex >= 0 && insertIndex <= remaining.count else { return false }

        var reordered = remaining
        reordered.insert(contentsOf: sortedSelection, at: insertIndex)

        return reordered != original
    }

    /// Calculates the 0-based destination starting index where the first moved page will land.
    public static func destinationIndex(fromIndices: Set<Int>, slot: Int, pageCount: Int) -> Int? {
        guard isValidSlot(slot: slot, fromIndices: fromIndices, pageCount: pageCount) else { return nil }
        let beforeCount = fromIndices.filter { $0 < slot }.count
        return slot - beforeCount
    }

    /// Human-readable label displayed in the drop indicator badge.
    public static func slotLabel(slot: Int, fromIndices: Set<Int>, pageCount: Int) -> String {
        if let dest = destinationIndex(fromIndices: fromIndices, slot: slot, pageCount: pageCount) {
            if fromIndices.count == 1 {
                return "Move to Page \(dest + 1)"
            } else {
                return "Move \(fromIndices.count) Pages to Page \(dest + 1)"
            }
        }
        if slot == 0 {
            return fromIndices.count > 1 ? "Move \(fromIndices.count) Pages to Page 1" : "Move to Page 1"
        } else if slot >= pageCount {
            return fromIndices.count > 1 ? "Move \(fromIndices.count) Pages to End" : "Move to Page \(pageCount)"
        } else {
            return fromIndices.count > 1 ? "Move \(fromIndices.count) Pages to Page \(slot + 1)" : "Move to Page \(slot + 1)"
        }
    }

    // Backwards-compatible single-index overloads:
    public static func isValidSlot(slot: Int, fromIndex: Int?) -> Bool {
        guard let from = fromIndex else { return false }
        return slot != from && slot != from + 1
    }

    public static func destinationIndex(from fromIndex: Int, slot: Int) -> Int? {
        if slot == fromIndex || slot == fromIndex + 1 {
            return nil
        }
        if slot < fromIndex {
            return slot
        } else {
            return slot - 1
        }
    }

    public static func slotLabel(slot: Int, fromIndex: Int?, pageCount: Int) -> String {
        if let from = fromIndex, let dest = destinationIndex(from: from, slot: slot) {
            return "Move to Page \(dest + 1)"
        }
        if slot == 0 {
            return "Move to Page 1"
        } else if slot >= pageCount {
            return "Move to Page \(pageCount)"
        } else {
            return "Move to Page \(slot + 1)"
        }
    }
}

/// Visual indicator showing the exact drop insertion line and target page badge.
public struct DropInsertionIndicator: View {
    let label: String

    public init(label: String) {
        self.label = label
    }

    public var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 7, height: 7)

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2.5)

            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule()
                        .fill(Color.accentColor)
                        .shadow(color: Color.accentColor.opacity(0.35), radius: 2, x: 0, y: 1)
                )
                .fixedSize()

            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2.5)
        }
        .frame(width: 140, height: 18)
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }
}

/// DropDelegate that calculates the active insertion slot based on pointer position within the thumbnail item row.
public struct ThumbnailPageDropDelegate: DropDelegate {
    let pageIndex: Int
    let cardHeight: CGFloat
    let pageCount: Int
    let viewModel: PDFViewerViewModel

    public func validateDrop(info: DropInfo) -> Bool {
        let isInternalDrag = !viewModel.draggedThumbnailPageIndices.isEmpty || viewModel.draggedThumbnailPageIndex != nil
        let hasExternalPDF = info.hasItemsConforming(to: [UTType.pdf, UTType.fileURL])
        return isInternalDrag || hasExternalPDF
    }

    public func dropEntered(info: DropInfo) {
        updateSlot(at: info.location)
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        let isInternalDrag = !viewModel.draggedThumbnailPageIndices.isEmpty || viewModel.draggedThumbnailPageIndex != nil
        let hasExternalPDF = info.hasItemsConforming(to: [UTType.pdf, UTType.fileURL])
        guard isInternalDrag || hasExternalPDF else {
            if viewModel.activeThumbnailDropSlot != nil {
                viewModel.activeThumbnailDropSlot = nil
            }
            return nil
        }
        updateSlot(at: info.location)
        return DropProposal(operation: isInternalDrag ? .move : .copy)
    }

    public func dropExited(info: DropInfo) {
        // Continuous transitions between elements are maintained in dropUpdated
    }

    public func performDrop(info: DropInfo) -> Bool {
        let isUpper = info.location.y < cardHeight * 0.5
        let currentItemSlot = isUpper ? pageIndex : (pageIndex + 1)
        let slot = viewModel.activeThumbnailDropSlot ?? currentItemSlot

        let draggedIndices = !viewModel.draggedThumbnailPageIndices.isEmpty ?
            viewModel.draggedThumbnailPageIndices :
            (viewModel.draggedThumbnailPageIndex.map { Set([$0]) } ?? [])

        if !draggedIndices.isEmpty {
            viewModel.endThumbnailDrag()
            guard ThumbnailDropLogic.isValidSlot(slot: slot, fromIndices: draggedIndices, pageCount: pageCount) else {
                return true
            }
            viewModel.reorderPages(from: Array(draggedIndices).sorted(), toSlot: slot)
            return true
        }

        if info.hasItemsConforming(to: [UTType.pdf, UTType.fileURL]) {
            viewModel.activeThumbnailDropSlot = nil
            let providers = info.itemProviders(for: [UTType.pdf, UTType.fileURL])
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url, url.pathExtension.lowercased() == "pdf" {
                            DispatchQueue.main.async {
                                self.viewModel.importPages(from: url, toSlot: slot)
                            }
                        }
                    }
                } else {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        var targetURL: URL?
                        if let url = item as? URL {
                            targetURL = url
                        } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            targetURL = url
                        }
                        if let targetURL = targetURL, targetURL.pathExtension.lowercased() == "pdf" {
                            DispatchQueue.main.async {
                                self.viewModel.importPages(from: targetURL, toSlot: slot)
                            }
                        }
                    }
                }
            }
            return true
        }

        viewModel.endThumbnailDrag()
        return false
    }

    private func updateSlot(at location: CGPoint) {
        let isUpper = location.y < cardHeight * 0.5
        let slot = isUpper ? pageIndex : (pageIndex + 1)
        if viewModel.activeThumbnailDropSlot != slot {
            viewModel.activeThumbnailDropSlot = slot
        }
    }
}

public struct BottomZoneDropDelegate: DropDelegate {
    let pageCount: Int
    let viewModel: PDFViewerViewModel

    public func dropEntered(info: DropInfo) {
        viewModel.activeThumbnailDropSlot = pageCount
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        let isInternalDrag = !viewModel.draggedThumbnailPageIndices.isEmpty || viewModel.draggedThumbnailPageIndex != nil
        let hasExternalPDF = info.hasItemsConforming(to: [UTType.pdf, UTType.fileURL])
        guard isInternalDrag || hasExternalPDF else {
            return nil
        }
        viewModel.activeThumbnailDropSlot = pageCount
        return DropProposal(operation: isInternalDrag ? .move : .copy)
    }

    public func dropExited(info: DropInfo) {
        if viewModel.activeThumbnailDropSlot == pageCount {
            viewModel.activeThumbnailDropSlot = nil
        }
    }

    public func performDrop(info: DropInfo) -> Bool {
        viewModel.activeThumbnailDropSlot = nil
        let draggedIndices = !viewModel.draggedThumbnailPageIndices.isEmpty ?
            viewModel.draggedThumbnailPageIndices :
            (viewModel.draggedThumbnailPageIndex.map { Set([$0]) } ?? [])

        if !draggedIndices.isEmpty {
            viewModel.reorderPages(from: Array(draggedIndices).sorted(), toSlot: pageCount)
            viewModel.endThumbnailDrag()
            return true
        }

        if info.hasItemsConforming(to: [UTType.pdf, UTType.fileURL]) {
            let providers = info.itemProviders(for: [UTType.pdf, UTType.fileURL])
            for provider in providers {
                if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url, url.pathExtension.lowercased() == "pdf" {
                            DispatchQueue.main.async {
                                self.viewModel.importPages(from: url, toSlot: pageCount)
                            }
                        }
                    }
                } else {
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        var targetURL: URL?
                        if let url = item as? URL {
                            targetURL = url
                        } else if let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                            targetURL = url
                        }
                        if let targetURL = targetURL, targetURL.pathExtension.lowercased() == "pdf" {
                            DispatchQueue.main.async {
                                self.viewModel.importPages(from: targetURL, toSlot: pageCount)
                            }
                        }
                    }
                }
            }
            return true
        }

        viewModel.endThumbnailDrag()
        return false
    }
}

public struct PDFThumbnailGridView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @State private var hoveredPageIndex: Int? = nil

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        guard let doc = viewModel.document, doc.pageCount > 0 else {
            return AnyView(
                ContentUnavailableView(
                    "No Pages",
                    systemImage: "doc",
                    description: Text("Document has no pages")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            )
        }

        let pageCount = doc.pageCount

        return AnyView(
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(0..<pageCount, id: \.self) { pageIndex in
                            let isSelected = viewModel.selectedThumbnailPageIndices.contains(pageIndex)
                            let isCurrent = viewModel.currentPageIndex == pageIndex
                            let isHovered = hoveredPageIndex == pageIndex
                            let activeDragged = !viewModel.draggedThumbnailPageIndices.isEmpty ?
                                viewModel.draggedThumbnailPageIndices :
                                (viewModel.draggedThumbnailPageIndex.map { Set([$0]) } ?? [])
                            let isDragged = activeDragged.contains(pageIndex)
                            let h = cardHeight(for: pageIndex, doc: doc)

                            VStack(spacing: 0) {
                                // Insertion indicator above this page
                                if !activeDragged.isEmpty {
                                    if viewModel.activeThumbnailDropSlot == pageIndex,
                                       ThumbnailDropLogic.isValidSlot(slot: pageIndex, fromIndices: activeDragged, pageCount: pageCount) {
                                        DropInsertionIndicator(label: ThumbnailDropLogic.slotLabel(slot: pageIndex, fromIndices: activeDragged, pageCount: pageCount))
                                            .padding(.vertical, 4)
                                    }
                                } else if viewModel.activeThumbnailDropSlot == pageIndex {
                                    DropInsertionIndicator(label: "Insert Pages from PDF")
                                        .padding(.vertical, 4)
                                }

                                VStack(spacing: 6) {
                                    thumbnailCard(for: pageIndex, doc: doc, isCurrent: isCurrent)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 3)
                                                .stroke(
                                                    isSelected ? Color.accentColor : (isHovered ? Color.secondary.opacity(0.6) : Color.gray.opacity(0.3)),
                                                    lineWidth: isSelected ? 2.5 : 1
                                                )
                                        )
                                        .shadow(color: isSelected ? Color.accentColor.opacity(0.3) : Color.black.opacity(0.12), radius: isSelected ? 4 : 2, x: 0, y: 1)
                                        .opacity(isDragged ? 0.35 : 1.0)
                                        .scaleEffect(isDragged ? 0.96 : 1.0)
                                        .animation(.easeInOut(duration: 0.15), value: isDragged)

                                    Text("\(pageIndex + 1)")
                                        .font(isSelected ? .caption.bold() : .caption)
                                        .foregroundColor(isSelected ? .accentColor : .secondary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)

                                // Insertion indicator after the last page
                                if pageIndex == pageCount - 1 {
                                    if !activeDragged.isEmpty,
                                       viewModel.activeThumbnailDropSlot == pageCount,
                                       ThumbnailDropLogic.isValidSlot(slot: pageCount, fromIndices: activeDragged, pageCount: pageCount) {
                                        DropInsertionIndicator(label: ThumbnailDropLogic.slotLabel(slot: pageCount, fromIndices: activeDragged, pageCount: pageCount))
                                            .padding(.vertical, 4)
                                    } else if activeDragged.isEmpty && viewModel.activeThumbnailDropSlot == pageCount {
                                        DropInsertionIndicator(label: "Insert Pages from PDF")
                                            .padding(.vertical, 4)
                                    }
                                }
                            }
                            .id(pageIndex)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                hoveredPageIndex = hovering ? pageIndex : nil
                                if (NSEvent.pressedMouseButtons & 1) == 0 && (viewModel.draggedThumbnailPageIndex != nil || !viewModel.draggedThumbnailPageIndices.isEmpty) {
                                    viewModel.endThumbnailDrag()
                                }
                            }
                            .onTapGesture {
                                if viewModel.draggedThumbnailPageIndex != nil || !viewModel.draggedThumbnailPageIndices.isEmpty {
                                    viewModel.endThumbnailDrag()
                                }
                                let flags = NSEvent.modifierFlags
                                let isShift = flags.contains(.shift)
                                let isCmd = flags.contains(.command)
                                viewModel.selectThumbnail(pageIndex: pageIndex, isShift: isShift, isCommand: isCmd)
                            }
                            .contextMenu {
                                let isMulti = viewModel.selectedThumbnailPageIndices.contains(pageIndex) && viewModel.selectedThumbnailPageIndices.count > 1
                                let count = viewModel.selectedThumbnailPageIndices.count

                                if isMulti {
                                    Button {
                                        viewModel.rotateSelectedThumbnails(by: 90)
                                    } label: {
                                        Label("Rotate \(count) Pages Clockwise", systemImage: "rotate.right")
                                    }

                                    Button {
                                        viewModel.rotateSelectedThumbnails(by: -90)
                                    } label: {
                                        Label("Rotate \(count) Pages Counterclockwise", systemImage: "rotate.left")
                                    }

                                    Button {
                                        viewModel.rotateSelectedThumbnails(by: 180)
                                    } label: {
                                        Label("Rotate \(count) Pages 180°", systemImage: "arrow.triangle.2.circlepath")
                                    }

                                    Divider()

                                    Button {
                                        viewModel.duplicateSelectedThumbnails()
                                    } label: {
                                        Label("Duplicate \(count) Pages", systemImage: "plus.rectangle.on.rectangle")
                                    }

                                    Button {
                                        viewModel.insertBlankPageAtSelection()
                                    } label: {
                                        Label("Insert Blank Page", systemImage: "plus.rectangle")
                                    }

                                    Button {
                                        let insertSlot = (viewModel.selectedThumbnailPageIndices.max() ?? pageIndex) + 1
                                        viewModel.promptImportPDF(atSlot: insertSlot)
                                    } label: {
                                        Label("Insert Pages from PDF…", systemImage: "arrow.down.doc")
                                    }

                                    Divider()

                                    Button {
                                        viewModel.extractSelectedThumbnails()
                                    } label: {
                                        Label("Save \(count) selected pages as a PDF…", systemImage: "arrow.up.forward.square")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        viewModel.deleteSelectedThumbnails()
                                    } label: {
                                        Label("Delete \(count) Pages", systemImage: "trash")
                                    }
                                    .disabled(count >= pageCount)
                                } else {
                                    Button {
                                        viewModel.rotatePage(pageIndex, by: 90)
                                    } label: {
                                        Label("Rotate Clockwise", systemImage: "rotate.right")
                                    }

                                    Button {
                                        viewModel.rotatePage(pageIndex, by: -90)
                                    } label: {
                                        Label("Rotate Counterclockwise", systemImage: "rotate.left")
                                    }

                                    Button {
                                        viewModel.rotatePage(pageIndex, by: 180)
                                    } label: {
                                        Label("Rotate 180°", systemImage: "arrow.triangle.2.circlepath")
                                    }

                                    Divider()

                                    Button {
                                        viewModel.duplicatePage(pageIndex)
                                    } label: {
                                        Label("Duplicate Page", systemImage: "plus.rectangle.on.rectangle")
                                    }

                                    Button {
                                        viewModel.insertBlankPage(after: pageIndex)
                                    } label: {
                                        Label("Insert Blank Page", systemImage: "plus.rectangle")
                                    }

                                    Button {
                                        viewModel.promptImportPDF(atSlot: pageIndex + 1)
                                    } label: {
                                        Label("Insert Pages from PDF…", systemImage: "arrow.down.doc")
                                    }

                                    Divider()

                                    Button {
                                        viewModel.extractPage(pageIndex)
                                    } label: {
                                        Label("Save selected page as a PDF…", systemImage: "arrow.up.forward.square")
                                    }

                                    Divider()

                                    if pageIndex > 0 {
                                        Button {
                                            viewModel.reorderPage(from: pageIndex, to: pageIndex - 1)
                                        } label: {
                                            Label("Move Page Up", systemImage: "arrow.up")
                                        }
                                    }

                                    if pageIndex < pageCount - 1 {
                                        Button {
                                            viewModel.reorderPage(from: pageIndex, to: pageIndex + 1)
                                        } label: {
                                            Label("Move Page Down", systemImage: "arrow.down")
                                        }
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        viewModel.deletePage(pageIndex)
                                    } label: {
                                        Label("Delete Page", systemImage: "trash")
                                    }
                                    .disabled(pageCount <= 1)
                                }
                            }
                            .onDrag {
                                viewModel.startThumbnailDrag(pageIndex: pageIndex)
                                return NSItemProvider(object: String(pageIndex) as NSString)
                            }
                            .onDrop(
                                of: [UTType.plainText, UTType.pdf, UTType.fileURL],
                                delegate: ThumbnailPageDropDelegate(
                                    pageIndex: pageIndex,
                                    cardHeight: h + 32,
                                    pageCount: pageCount,
                                    viewModel: viewModel
                                )
                            )
                        }

                        // Bottom drop zone for dragging to the end of the document
                        Color.clear
                            .frame(maxWidth: .infinity)
                            .frame(height: 60)
                            .contentShape(Rectangle())
                            .onDrop(
                                of: [UTType.plainText, UTType.pdf, UTType.fileURL],
                                delegate: BottomZoneDropDelegate(pageCount: pageCount, viewModel: viewModel)
                            )
                    }
                    .animation(.easeInOut(duration: 0.15), value: viewModel.activeThumbnailDropSlot)
                    .padding(.vertical, 12)
                }
                .onKeyPress(.init("d"), phases: .down) { press in
                    if press.modifiers.contains(.command) && !press.modifiers.contains(.shift) && !press.modifiers.contains(.option) {
                        viewModel.duplicateSelectedThumbnails()
                        return .handled
                    }
                    return .ignored
                }
                .onChange(of: viewModel.currentPageIndex) { _, newIndex in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo(newIndex, anchor: .center)
                    }
                }
                .onAppear {
                    proxy.scrollTo(viewModel.currentPageIndex, anchor: .center)
                }
            }
        )
    }

    private func cardHeight(for pageIndex: Int, doc: PDFDocumentCore) -> CGFloat {
        let bounds = doc.pageBounds[pageIndex]
        let aspect = (bounds.width > 0 && bounds.height > 0) ? (bounds.width / bounds.height) : (612.0 / 792.0)
        let cardWidth: CGFloat = 130
        return cardWidth / aspect
    }

    @ViewBuilder
    private func thumbnailCard(for pageIndex: Int, doc: PDFDocumentCore, isCurrent: Bool) -> some View {
        let cardWidth: CGFloat = 130
        let h = cardHeight(for: pageIndex, doc: doc)

        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(Color(nsColor: .windowBackgroundColor))

            if let img = viewModel.thumbnailImages[pageIndex] {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            } else {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task {
                    viewModel.requestThumbnail(for: pageIndex)
                }
            }
        }
        .frame(width: cardWidth, height: h)
        .id("\(viewModel.thumbnailVersion)-\(pageIndex)")
    }
}
