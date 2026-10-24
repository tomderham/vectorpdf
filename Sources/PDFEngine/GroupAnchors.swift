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
import AppKit
import Combine

/// The anchors of every tab in a window's tab group, kept live as anchors are added or removed
/// in any of them and as tabs come and go.
@MainActor
public final class GroupAnchorsModel: ObservableObject {
    public struct Section: Identifiable {
        public var id: ObjectIdentifier { ObjectIdentifier(viewModel) }
        public let viewModel: PDFViewerViewModel
        public let title: String
        public let anchors: [SnapshotTarget]
        public let isCurrent: Bool
    }

    /// One per tab, in tab order.
    @Published public private(set) var sections: [Section] = []
    /// Tabs in the window, including any not (yet) showing a document.
    @Published public private(set) var tabCount = 1

    private weak var owner: PDFViewerViewModel?
    private var memberIds: [ObjectIdentifier] = []
    private var memberCancellables: [AnyCancellable] = []
    // Touched only on the main actor, and in deinit once nothing else can.
    nonisolated(unsafe) private var windowObservers: [NSObjectProtocol] = []

    public init() {}

    public func attach(to viewModel: PDFViewerViewModel) {
        owner = viewModel
        if windowObservers.isEmpty {
            // Tabs are added, merged, reordered or closed without any notification of their own;
            // each of those makes some window key, or closes one.
            let center = NotificationCenter.default
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
                windowObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    // After the close (or tab move) has completed.
                    DispatchQueue.main.async { self?.refresh() }
                })
            }
        }
        refresh()
    }

    deinit {
        windowObservers.forEach(NotificationCenter.default.removeObserver)
    }

    public func refresh() {
        guard let owner else { return }
        let members = PDFViewerAppCoordinator.shared.tabGroupViewModels(of: owner)
        let ids = members.map(ObjectIdentifier.init)
        if ids != memberIds {
            memberIds = ids
            // @Published fires before the value changes, so rebuild on the next turn of the run loop.
            memberCancellables = members.flatMap { vm in [
                vm.$activeSnapshots.map { _ in () }.eraseToAnyPublisher(),
                vm.$documentTitle.map { _ in () }.eraseToAnyPublisher()
            ] }.map { $0.dropFirst().receive(on: RunLoop.main).sink { [weak self] in self?.rebuild() } }
        }
        let count = owner.currentWindowTabCount
        if tabCount != count { tabCount = count }
        rebuild(members)
    }

    private func rebuild(_ members: [PDFViewerViewModel]? = nil) {
        guard let owner else { return }
        let members = members ?? PDFViewerAppCoordinator.shared.tabGroupViewModels(of: owner)
        sections = members.map { vm in
            Section(viewModel: vm, title: vm.documentTitle, anchors: vm.activeSnapshots, isCurrent: vm === owner)
        }
    }
}

/// Anchors sidebar content for "All Tabs": one section per tab that has anchors, each anchor
/// opening its tab.
struct GroupAnchorsListView: View {
    @ObservedObject var model: GroupAnchorsModel

    var body: some View {
        if model.sections.allSatisfy({ $0.anchors.isEmpty }) {
            ContentUnavailableView {
                Label {
                    Text("No Anchors in These Tabs")
                } icon: {
                    Image.anchorIcon
                }
            } description: {
                Text("Anchors you create in any tab of this window appear here.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    // Tabs without anchors would only clutter the list.
                    ForEach(model.sections.filter { !$0.anchors.isEmpty }) { section in
                        header(for: section)
                        ForEach(section.anchors) { snap in
                            SnapshotCardView(snap: snap, viewModel: section.viewModel, activatesTab: !section.isCurrent)
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func header(for section: GroupAnchorsModel.Section) -> some View {
        HStack(spacing: 6) {
            Image(systemName: section.isCurrent ? "doc.text.fill" : "doc.text")
                .font(.caption)
                .foregroundStyle(section.isCurrent ? Color.accentColor : Color.secondary)
            Text(section.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text("\(section.anchors.count)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 4)
        .padding(.top, 6)
        .help(section.isCurrent ? "\(section.title) (this tab)" : section.title)
    }
}
