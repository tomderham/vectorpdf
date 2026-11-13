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

/// The strip under the page (View > Show Status Bar): where the pointer is on the page, the
/// size of that page, the figures of a measurement being drawn and the size of the text
/// selection.
struct StatusBarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @ObservedObject var readout: CanvasReadout
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared

    init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
        self.readout = viewModel.canvasReadout
    }

    var body: some View {
        let unit = coordinator.readoutUnit
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 14) {
                if let pointer = readout.pointer {
                    item(systemImage: "cursorarrow", pointerText(pointer, unit: unit))
                        .help("Where the pointer is, from the top-left corner of the page")
                }
                if let page = shownPage {
                    item(systemImage: "doc", pageSizeText(page, unit: unit))
                        .help(readout.pointer == nil ? "The size of the current page" : "The size of the page under the pointer")
                }
                if !readout.measurement.isEmpty {
                    HStack(spacing: 10) {
                        ForEach(readout.measurement, id: \.label) { figure in
                            HStack(spacing: 3) {
                                Text(figure.label).foregroundStyle(.secondary)
                                Text(figure.value)
                            }
                        }
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let counts = readout.selectionCounts {
                    Text("\(counts.words) word\(counts.words == 1 ? "" : "s"), \(counts.characters) character\(counts.characters == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                        .help("The size of the text selection")
                }
                Menu {
                    Picker("Units", selection: $coordinator.readoutUnit) {
                        ForEach(ReadoutUnit.allCases, id: \.self) { unit in
                            Text(unit.displayName).tag(unit)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                } label: {
                    Text(unit.rawValue)
                }
                .menuStyle(.borderlessButton)
                .controlSize(.small)
                .fixedSize()
                .help("Units for positions and sizes on the page")
            }
            .font(.system(size: 11).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(height: 22)
        }
        .background(.bar)
        .onAppear { viewModel.updateSelectionReadout() }
    }

    /// The page under the pointer, or else the current one.
    private var shownPage: Int? {
        guard let doc = viewModel.document, doc.pageCount > 0 else { return nil }
        return min(readout.pointer?.pageIndex ?? viewModel.currentPageIndex, doc.pageCount - 1)
    }

    private func item(systemImage: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).foregroundStyle(.secondary)
            Text(text)
        }
    }

    private func pointerText(_ pointer: PointerLocation, unit: ReadoutUnit) -> String {
        var text = "x \(unit.format(pointer.point.x))  y \(unit.format(pointer.point.y)) \(unit.rawValue)"
        // On a drawing with a scale, also where that is on what it's a drawing of.
        if let scale = viewModel.pageScaleConfigs[pointer.pageIndex] {
            text += "  (\(scale.formatLength(points: pointer.point.x)), \(scale.formatLength(points: pointer.point.y)))"
        }
        return text
    }

    private func pageSizeText(_ page: Int, unit: ReadoutUnit) -> String {
        guard let doc = viewModel.document else { return "" }
        let size = doc.pageBounds[page].size
        let label = "Page \(doc.displayLabel(forPage: page))"
        if let paper = PaperSize.name(for: size) {
            return "\(label): \(paper), \(unit.formatSize(size))"
        }
        return "\(label): \(unit.formatSize(size))"
    }
}
