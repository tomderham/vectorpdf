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

/// The Search tab: the search field, OCR notices, the result count with previous and next, and
/// the results by outline section and page. It shows in the sidebar, or in the column on the
/// window's right when the document keeps Search there (see PDFViewerViewModel.isSearchOnRight).
struct SearchSidebarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    /// Moves Search to the other side of the window.
    let moveToOtherSide: () -> Void
    /// The search results list, which takes keyboard focus when a result is clicked so the arrow
    /// keys step through results instead of moving the cursor in the search field.
    @FocusState private var isSearchResultsFocused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                NativeSearchField(
                    text: $viewModel.searchQuery,
                    placeholder: "Search document...",
                    onCommit: {
                        viewModel.performSearch()
                    },
                    onNext: {
                        viewModel.submitSearch()
                    },
                    onPrevious: {
                        viewModel.previousSearchMatch()
                    },
                    recents: viewModel.recentSearches,
                    onSelectRecent: { query in
                        viewModel.selectRecentSearch(query)
                    },
                    onClearRecents: {
                        viewModel.clearRecentSearches()
                    }
                )

                if viewModel.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }

                SearchOptionsMenu(viewModel: viewModel, moveToOtherSide: moveToOtherSide)

                if viewModel.isSearchOnRight {
                    // The right column has no button of its own to close it, as the sidebar has.
                    Button {
                        viewModel.closeRightSearch()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Hide Search (⌘F shows it again)")
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)

            if viewModel.isRunningOCR {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Recognizing text in scanned pages...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .padding(.horizontal, 8)
            } else if !viewModel.detectedScannedPages.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.detectedScannedPages.count) scanned page(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Run OCR") {
                        Task {
                            await viewModel.runOCROnAllScannedPages()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .padding(.horizontal, 8)
            } else if viewModel.canSaveRecognizedText {
                HStack(spacing: 6) {
                    Image(systemName: "text.viewfinder")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(viewModel.ocrResults.count == 1 ? "Text recognized on 1 page" : "Text recognized on \(viewModel.ocrResults.count) pages")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Save in PDF") {
                        Task {
                            await viewModel.saveWithRecognizedText()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
                    .help("Save the document with the recognized text in it, so other apps can search and select it (File > Save with Recognized Text)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                .cornerRadius(6)
                .padding(.horizontal, 8)
            }
            let hasQuery = !viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let shouldShowCount = !viewModel.searchResults.isEmpty || (hasQuery && !viewModel.isSearching && !viewModel.isRunningOCR)
            if shouldShowCount {
                HStack {
                    Text(viewModel.searchResults.isEmpty ? "0 results" : "\(viewModel.activeSearchMatchIndex + 1) of \(viewModel.searchResults.count)")
                        .font(.caption2.monospacedDigit().weight(.medium))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                )
                        )
                        .foregroundStyle(.secondary)

                    Spacer()

                    if !viewModel.searchResults.isEmpty {
                        HStack(spacing: 2) {
                            Button {
                                viewModel.previousSearchMatch()
                            } label: {
                                Image(systemName: "chevron.up")
                                    .font(.caption2.weight(.semibold))
                                    .frame(width: 20, height: 20)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .help("Previous Match (Shift+Cmd+G)")

                            Button {
                                viewModel.nextSearchMatch()
                            } label: {
                                Image(systemName: "chevron.down")
                                    .font(.caption2.weight(.semibold))
                                    .frame(width: 20, height: 20)
                            }
                            .buttonStyle(.plain)
                            .help("Next Match (Cmd+G)")
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                                )
                        )
                    }
                }
                .padding(.horizontal, 8)
            }

            Divider()

            // Use ScrollView/LazyVStack to avoid table view reentrancy while search results stream in.
            ScrollViewReader { proxy in
                ScrollView {
                    // Each outline section's header stays at the top while its results scroll past.
                    LazyVStack(spacing: 3, pinnedViews: [.sectionHeaders]) {
                        if !hasQuery && !viewModel.recentSearches.isEmpty {
                            RecentSearchesListView(viewModel: viewModel)
                                .padding(.horizontal, 6)
                        }
                        ForEach(viewModel.searchSectionGroups) { sectionGroup in
                            Section {
                                ForEach(sectionGroup.pages) { group in
                                    SearchPageSeparatorView(
                                        pageLabel: viewModel.document?.displayLabel(forPage: group.pageIndex) ?? String(group.pageIndex + 1),
                                        count: group.matches.count
                                    )
                                    .padding(.horizontal, 6)

                                    ForEach(group.matches) { match in
                                        SearchResultRowView(
                                            match: match,
                                            isActive: viewModel.isActiveMatch(match)
                                        )
                                        .padding(.horizontal, 6)
                                        .onTapGesture {
                                            isSearchResultsFocused = true
                                            DispatchQueue.main.async {
                                                viewModel.navigateToMatch(match, shouldScrollList: false)
                                            }
                                        }
                                        .contextMenu {
                                            Button {
                                                viewModel.addSnapshot(from: match)
                                            } label: {
                                                Label {
                                                    Text("Create Anchor")
                                                } icon: {
                                                    Image.anchorIcon
                                                }
                                            }

                                            Button {
                                                viewModel.addSnapshotAndOpenInNewWindow(from: match)
                                            } label: {
                                                Label {
                                                    Text("Create Anchor and Open in New Window")
                                                } icon: {
                                                    Image.anchorIcon
                                                }
                                            }

                                            Divider()

                                            Button {
                                                viewModel.openSnapshotInNewWindow(from: match)
                                            } label: {
                                                Label("Open in New Window", systemImage: "macwindow.badge.plus")
                                            }
                                        }
                                        .id(match.id)
                                    }
                                }
                            } header: {
                                if let section = sectionGroup.section {
                                    SearchSectionHeaderView(path: section.path)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .focusable()
                .focused($isSearchResultsFocused)
                // The active result is already highlighted.
                .focusEffectDisabled()
                .onKeyPress(keys: [.upArrow, .leftArrow, .downArrow, .rightArrow]) { press in
                    if press.key == .upArrow || press.key == .leftArrow {
                        viewModel.previousSearchMatch()
                    } else {
                        viewModel.nextSearchMatch()
                    }
                    return .handled
                }
                .onChange(of: viewModel.searchScrollRevision) { _, _ in
                    if let targetId = viewModel.activeSearchMatchId {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            proxy.scrollTo(targetId, anchor: .center)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The document's recent searches, shown in the Search sidebar while the field is empty.
private struct RecentSearchesListView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Recent Searches")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    viewModel.clearRecentSearches()
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .help("Clear Recent Searches")
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 2)

            ForEach(viewModel.recentSearches, id: \.self) { query in
                Button {
                    viewModel.selectRecentSearch(query)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(query)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(query)
            }
        }
        .padding(.top, 4)
    }
}

/// The outline section of the results below it: a full-width bar, so it reads as the level above
/// the page labels. Only the section's own title is shown, cut at the end when it's long (numbered
/// headings start with their number); the path from the top of the outline is in its help tag.
private struct SearchSectionHeaderView: View {
    let path: [String]

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "list.bullet")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.accentColor)
            Text(path.last ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color.primary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .help(path.joined(separator: " › "))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(path.joined(separator: ", "))
        .accessibilityAddTraits(.isHeader)
    }
}

/// A page's results start here: a plain label, below the section bars and above the result cards.
private struct SearchPageSeparatorView: View {
    let pageLabel: String
    let count: Int
    
    var body: some View {
        HStack(spacing: 6) {
            Text("Page \(pageLabel)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            
            Spacer()
            
            Text("\(count) \(count == 1 ? "item" : "items")")
                .font(.caption2.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 1)
    }
}

private struct SearchResultRowView: View {
    let match: SearchResult
    let isActive: Bool
    
    var body: some View {
        Text(match.snippet)
            .font(.caption)
            .lineLimit(3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.85))
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor).opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(isActive ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.06), lineWidth: 0.75)
                    )
            )
            .contentShape(Rectangle())
    }
}
