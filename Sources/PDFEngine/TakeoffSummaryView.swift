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

/// A structured takeoff review table and export inspector for architectural/engineering measurements.
public struct TakeoffSummaryView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var copyFeedback: Bool = false

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    /// Measurements loaded when the sheet appears.
    @State private var items: [PDFViewerViewModel.TakeoffEntry] = []

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "tablecells")
                    .font(.system(size: 18))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Measurement Takeoff Summary")
                        .font(.headline)
                    Text("Itemized schedule of lengths, perimeters, surface areas, and angles.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 16))
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            // Table Content
            if items.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "ruler")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text("No Measurements Found")
                        .font(.headline)
                    Text("Use the Linear Dimension, Perimeter, Area, or Angle tools from the Measurement Toolbar to perform drawing takeoffs.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 320)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(40)
            } else {
                Table(items) {
                    TableColumn("#") { item in
                        Text("\((items.firstIndex { $0.id == item.id } ?? 0) + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    .width(min: 28, ideal: 36, max: 48)

                    TableColumn("Page") { item in
                        Text("Page \(item.pageIndex + 1)")
                            .font(.caption)
                    }
                    .width(min: 50, ideal: 60, max: 70)

                    TableColumn("Type") { item in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color(nsColor: item.annotation.color.nsColor))
                                .frame(width: 8, height: 8)
                            Text(typeName(for: item.annotation.type))
                                .font(.caption)
                        }
                    }
                    .width(min: 90, ideal: 120, max: 140)

                    TableColumn("Measurement") { item in
                        Text(item.formattedValue)
                            .font(.caption.monospacedDigit().weight(.semibold))
                    }
                    .width(min: 100, ideal: 130, max: 180)

                    TableColumn("Scale") { item in
                        Text(item.scale.ratioString)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Divider()

            // Bottom Summary Bar & Action Buttons
            HStack(spacing: 16) {
                if !items.isEmpty {
                    HStack(spacing: 12) {
                        Text("\(items.count) Items")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        let totals = viewModel.takeoffTotals(items)
                        if let formattedLinear = totals.linear {
                            Text("Total Linear: \(formattedLinear)")
                                .font(.caption.monospacedDigit().weight(.medium))
                        }

                        if let formattedArea = totals.area {
                            Text("Total Area: \(formattedArea)")
                                .font(.caption.monospacedDigit().weight(.medium))
                        }
                    }
                }

                Spacer()

                if copyFeedback {
                    Text("Copied to Clipboard!")
                        .font(.caption)
                        .foregroundColor(.green)
                }

                Button {
                    let tsv = viewModel.generateTakeoffSummaryCSV()
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(tsv, forType: .string)
                    copyFeedback = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        copyFeedback = false
                    }
                } label: {
                    Label("Copy Table", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
                .disabled(items.isEmpty)

                Button {
                    viewModel.exportTakeoffSummary()
                } label: {
                    Label("Export CSV...", systemImage: "arrow.down.doc")
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .disabled(items.isEmpty)
            }
            .padding(12)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 580, minHeight: 380)
        .onAppear {
            items = viewModel.takeoffEntries()
        }
    }

    private func typeName(for type: PDFAnnotationType) -> String {
        switch type {
        case .measureLength: return "Linear Dimension"
        case .measurePerimeter: return "Perimeter"
        case .measureArea: return "Area Takeoff"
        case .measureAngle: return "Angle"
        default: return "Measurement"
        }
    }
}
