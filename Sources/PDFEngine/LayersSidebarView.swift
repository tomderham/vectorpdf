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

/// The sidebar's Layers tab: the document's layers (optional content groups), as CAD and
/// drawing programs export them, each with a checkbox to show or hide it. Shown only for a
/// document with layers.
struct LayersSidebarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    private var layerCount: Int {
        viewModel.layers.filter { $0.kind != .heading }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(layerCount) Layer\(layerCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(viewModel.layers) { layer in
                        LayerRowView(layer: layer) {
                            viewModel.toggleLayer(layer)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }

            Divider()

            HStack(alignment: .top, spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .padding(.top, 1)
                Text("Hidden layers aren't printed, selected or found by search. Which layers are shown isn't saved.")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LayerRowView: View {
    let layer: PDFLayer
    let toggle: () -> Void

    private var name: String {
        layer.name.isEmpty ? "Untitled Layer" : layer.name
    }

    var body: some View {
        HStack(spacing: 6) {
            switch layer.kind {
            case .heading:
                Text(name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            case .checkbox:
                Toggle(isOn: Binding(get: { layer.isVisible }, set: { _ in toggle() })) {
                    Text(name)
                }
                .toggleStyle(.checkbox)
                .disabled(layer.isLocked)
            case .radio:
                // One of a group: choosing it hides the others, as in Acrobat.
                Button(action: toggle) {
                    HStack(spacing: 6) {
                        Image(systemName: layer.isVisible ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(layer.isVisible ? Color.accentColor : Color.secondary)
                        Text(name)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(layer.isLocked)
            }
            if layer.isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help("This document doesn't let this layer be shown or hidden")
            }
            Spacer(minLength: 0)
        }
        .font(.callout)
        .lineLimit(1)
        .truncationMode(.middle)
        .help(name)
        .padding(.leading, CGFloat(layer.depth) * 14)
        .padding(.vertical, 2)
    }
}
