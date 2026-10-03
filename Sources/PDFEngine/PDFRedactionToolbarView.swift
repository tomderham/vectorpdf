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

/// Redact toolbar for region redaction and pattern search redaction.
public struct PDFRedactionToolbarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var selectedMatchesCount: Int {
        viewModel.redactionMatches.filter { $0.isSelected }.count
    }

    private var uniquePagesCount: Int {
        Set(viewModel.redactionMatches.map { $0.result.pageIndex }).count
    }

    private var isFindAndRedact: Bool {
        viewModel.editRedactTab == .findAndRedact
    }

    private var actionButtonTitle: String {
        switch viewModel.replaceAction {
        case .redact:
            return selectedMatchesCount > 0 ? "Redact Selected (\(selectedMatchesCount))" : "Redact Selected"
        case .remove:
            return selectedMatchesCount > 0 ? "Remove Selected (\(selectedMatchesCount))" : "Remove Selected"
        }
    }

    private var actionButtonIcon: String {
        switch viewModel.replaceAction {
        case .redact:
            return "lock.slash.fill"
        case .remove:
            return "trash"
        }
    }

    private var actionButtonTint: Color {
        switch viewModel.replaceAction {
        case .redact:
            return viewModel.redactionColor == .white ? .orange : .red
        case .remove:
            return .orange
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // MARK: - Primary Control Bar
            VStack(spacing: 8) {
                // Row 1: Mode Switcher, Harmonized Redact Color Control, Match Case/Word options, and Dismiss
                HStack(spacing: 12) {
                    // 1. Mode Selector: [ Redact Region | Find & Redact ]
                    Picker("", selection: Binding(
                        get: { viewModel.editRedactTab },
                        set: { viewModel.editRedactTab = $0 }
                    )) {
                        Label("Redact Region", systemImage: "rectangle.dashed.badge.record")
                            .tag(EditRedactTab.redactRegion)
                        Label("Find & Redact", systemImage: "magnifyingglass")
                            .tag(EditRedactTab.findAndRedact)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 260)

                    Divider()
                        .frame(height: 16)

                    // 2. Harmonized Redact Color Control (Label: "Redact Color:")
                    HStack(spacing: 6) {
                        Text("Redact Color:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Picker("", selection: $viewModel.redactionColor) {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.primary)
                                    .frame(width: 9, height: 9)
                                Text("Black")
                            }
                            .tag(RedactionColor.black)

                            HStack(spacing: 4) {
                                Circle()
                                    .stroke(Color.primary, lineWidth: 1)
                                    .frame(width: 8, height: 8)
                                Text("White")
                            }
                            .tag(RedactionColor.white)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 140)
                        .help("Harmonized color for redacted areas (Black or White)")
                    }

                    // 3. Match Options (Match Case, Whole Word) on top row when in Find & Redact
                    if isFindAndRedact && (viewModel.redactionPreset == .customText || viewModel.redactionPreset == .customRegex) {
                        Divider()
                            .frame(height: 16)

                        HStack(spacing: 6) {
                            Text("Match:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Toggle("Match Case", isOn: $viewModel.redactionMatchCase)
                                .toggleStyle(.button)
                                .controlSize(.small)

                            if viewModel.redactionPreset == .customText {
                                Toggle("Whole Word", isOn: $viewModel.redactionWholeWord)
                                    .toggleStyle(.button)
                                    .controlSize(.small)
                            }
                        }
                    }

                    if !isFindAndRedact {
                        // Helpful hint for direct region drawing
                        HStack(spacing: 4) {
                            Image(systemName: "hand.draw")
                                .foregroundColor(.secondary)
                            Text("Click and drag across any area of the page to redact")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.leading, 6)
                    }

                    Spacer()

                    // Close Toolbar Button
                    Button {
                        viewModel.toggleRedactionBar()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Redact Toolbar (⌥⌘R)")
                }

                // Row 2: Find & Redact Controls (only shown when Find & Redact is active)
                if isFindAndRedact {
                    HStack(spacing: 8) {
                        // Pattern / Preset Menu (Fixed width: 175)
                        Menu {
                            ForEach(RedactionPreset.allCases) { preset in
                                Button {
                                    viewModel.redactionPreset = preset
                                } label: {
                                    Label(preset.rawValue, systemImage: preset.iconName)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: viewModel.redactionPreset.iconName)
                                Text(viewModel.redactionPreset.rawValue)
                            }
                            .font(.caption)
                        }
                        .menuStyle(.borderedButton)
                        .controlSize(.small)
                        .frame(width: 175)

                        // Search Query Field (Fixed width: 220)
                        if viewModel.redactionPreset == .customText || viewModel.redactionPreset == .customRegex {
                            TextField(viewModel.redactionPreset.placeholder, text: $viewModel.redactionSearchQuery)
                                .textFieldStyle(.roundedBorder)
                                .controlSize(.small)
                                .frame(width: 220)
                                .onSubmit {
                                    viewModel.performRedactionSearch()
                                }
                        } else {
                            HStack {
                                Text(viewModel.redactionPreset.placeholder)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .frame(width: 220)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                        }

                        // Find Action Button (Fixed width: 65)
                        Button {
                            if viewModel.isRedactionSearching {
                                viewModel.cancelRedactionSearch()
                            } else {
                                viewModel.performRedactionSearch()
                            }
                        } label: {
                            HStack(spacing: 4) {
                                if viewModel.isRedactionSearching {
                                    ProgressView()
                                        .controlSize(.mini)
                                    Text("Stop")
                                } else {
                                    Image(systemName: "magnifyingglass")
                                    Text("Find")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .frame(width: 65)

                        // Constant-position separator between Find and Redact / Remove
                        Divider()
                            .frame(height: 16)

                        // Action Selector: [ Redact | Remove ] (Fixed width: 160)
                        Picker("", selection: $viewModel.replaceAction) {
                            Label("Redact", systemImage: "lock.slash.fill").tag(RedactAction.redact)
                            Label("Remove", systemImage: "trash").tag(RedactAction.remove)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(width: 160)

                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .topWindowBarColor))

            // MARK: - Found Matches Drawer
            if isFindAndRedact && (!viewModel.redactionMatches.isEmpty || viewModel.isRedactionSearching) {
                Divider()

                VStack(spacing: 8) {
                    if !viewModel.redactionMatches.isEmpty {
                        // Matches Header
                        HStack {
                            Text("Found \(viewModel.redactionMatches.count) match\(viewModel.redactionMatches.count == 1 ? "" : "es") across \(uniquePagesCount) page\(uniquePagesCount == 1 ? "" : "s")")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Spacer()

                            Button("Select All") {
                                viewModel.selectAllRedactionMatches(true)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .controlSize(.mini)

                            Text("•")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("Deselect All") {
                                viewModel.selectAllRedactionMatches(false)
                            }
                            .buttonStyle(.borderless)
                            .font(.caption)
                            .controlSize(.mini)
                        }

                        // Scrollable Match List
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(viewModel.redactionMatches) { item in
                                    let isItemActive = (viewModel.activeRedactionMatchId == item.id)
                                    HStack(spacing: 8) {
                                        Toggle("", isOn: Binding(
                                             get: { item.isSelected },
                                             set: { _ in viewModel.toggleRedactionMatchSelection(id: item.id) }
                                        ))
                                        .toggleStyle(.checkbox)
                                        .labelsHidden()
                                        .controlSize(.mini)

                                        Text("Page \(item.result.pageIndex + 1)")
                                            .font(.caption.monospacedDigit().bold())
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(isItemActive ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.15))
                                            .cornerRadius(4)

                                        Text(item.result.snippet)
                                            .font(.caption)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .foregroundColor(.primary)

                                        Spacer()

                                        if viewModel.replaceAction == .remove {
                                            HStack(spacing: 4) {
                                                Text(item.result.matchedText)
                                                    .strikethrough()
                                                    .font(.caption.monospaced())
                                                    .foregroundColor(.secondary)
                                                Text("(remove)")
                                                    .font(.caption2.italic())
                                                    .foregroundColor(.orange)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(Color.orange.opacity(0.12))
                                            .cornerRadius(3)
                                        } else {
                                            Text(item.result.matchedText)
                                                .font(.caption.monospaced())
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 1)
                                                .background(viewModel.redactionColor == .white ? Color.orange.opacity(0.12) : Color.red.opacity(0.12))
                                                .foregroundColor(viewModel.redactionColor == .white ? .orange : .red)
                                                .cornerRadius(3)
                                        }
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isItemActive ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor).opacity(item.isSelected ? 0.6 : 0.2))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(isItemActive ? Color.accentColor : Color.clear, lineWidth: 1)
                                    )
                                    .cornerRadius(4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        viewModel.selectRedactionMatch(item)
                                    }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                        .frame(maxHeight: 140)

                        // Action Bar: Apply Directly Right Away
                        HStack {
                            Text("\(selectedMatchesCount) of \(viewModel.redactionMatches.count) selected")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                viewModel.applySelectedMatches()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: actionButtonIcon)
                                    Text(actionButtonTitle)
                                }
                                .font(.caption.bold())
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(actionButtonTint)
                            .controlSize(.small)
                            .disabled(selectedMatchesCount == 0)
                        }
                    } else if viewModel.isRedactionSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching document for matches...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            }
        }
    }
}
