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

/// The headings found for an outline, to check before they replace it: each can be left out,
/// renamed, or put a level higher or lower. Clicking one shows it on the page.
struct HeadingOutlineSheet: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let proposal: HeadingOutlineProposal
    @Environment(\.dismiss) private var dismiss

    private struct Row: Identifiable {
        let id = UUID()
        var heading: FoundHeading
        var isIncluded = true
    }

    @State private var rows: [Row] = []

    private var included: [FoundHeading] { rows.filter(\.isIncluded).map(\.heading) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Build Outline from Headings")
                    .font(.headline)
                Text("\(proposal.headings.count) headings found. Uncheck any that aren't headings, and change titles or levels if you need to.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 10)

            List {
                ForEach($rows) { $row in
                    HStack(spacing: 6) {
                        Toggle("", isOn: $row.isIncluded)
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                        TextField("Title", text: $row.heading.title)
                            .textFieldStyle(.plain)
                            .padding(.leading, CGFloat(row.heading.level - 1) * 16)
                            .foregroundStyle(row.isIncluded ? .primary : .secondary)
                            .fontWeight(row.heading.level == 1 ? .semibold : .regular)
                        Spacer(minLength: 8)
                        Text(viewModel.document?.displayLabel(forPage: row.heading.page) ?? "\(row.heading.page + 1)")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button {
                            row.heading.level = max(1, row.heading.level - 1)
                        } label: { Image(systemName: "decrease.indent") }
                            .buttonStyle(.borderless)
                            .disabled(row.heading.level <= 1)
                            .help("Up a Level")
                        Button {
                            row.heading.level = min(6, row.heading.level + 1)
                        } label: { Image(systemName: "increase.indent") }
                            .buttonStyle(.borderless)
                            .disabled(row.heading.level >= 6)
                            .help("Down a Level")
                        Button {
                            viewModel.jumpToOutlineEntry(PDFOutlineNode(title: row.heading.title, targetPage: row.heading.page, targetY: row.heading.top))
                        } label: { Image(systemName: "arrow.right.circle") }
                            .buttonStyle(.borderless)
                            .help("Show on Page")
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 300)

            HStack {
                if proposal.replacesOutline {
                    Text("Replaces the document's outline. Edit > Undo brings it back.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(proposal.replacesOutline ? "Replace Outline" : "Create Outline") {
                    let headings = included
                    dismiss()
                    viewModel.applyHeadingOutline(headings)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(included.isEmpty)
            }
            .padding(20)
        }
        .frame(width: 560, height: 520)
        .onAppear {
            if rows.isEmpty { rows = proposal.headings.map { Row(heading: $0) } }
        }
    }
}
