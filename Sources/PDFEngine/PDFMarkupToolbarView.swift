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

/// A collapsible macOS-style secondary markup toolbar providing drawing tools,
/// text markup actions (highlight, underline, strikethrough), color swatches, and stroke widths.
public struct PDFMarkupToolbarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @StateObject private var signatureStore = SignatureStore.shared
    @State private var showSignatureCaptureSheet: Bool = false

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var hasSelection: Bool {
        guard let sel = viewModel.activeSelection else { return false }
        return !sel.result.highlightQuads.isEmpty || !viewModel.additionalSelectionPages.isEmpty
    }

    public var body: some View {
        HStack(spacing: 12) {
            // 1. Tool Mode Buttons [Text Select | Draw | Text | Callout | Eraser | Stamp]
            HStack(spacing: 2) {
                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .select,
                    helpText: "Text Selection Mode"
                ) {
                    viewModel.canvasMode = .select
                } label: {
                    Image(systemName: "text.cursor")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .draw,
                    helpText: "Draw Freehand Pen (Ink)"
                ) {
                    viewModel.canvasMode = .draw
                } label: {
                    Image(systemName: "pencil.tip")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .text,
                    helpText: "Add Text Box"
                ) {
                    viewModel.canvasMode = .text
                } label: {
                    Image(systemName: "character.textbox")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .callout,
                    helpText: "Callout Annotation (Leader arrow pointer to text note)"
                ) {
                    viewModel.canvasMode = .callout
                } label: {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .eraser,
                    helpText: "Eraser (Click or Drag to remove annotations)"
                ) {
                    viewModel.canvasMode = .eraser
                } label: {
                    Image(systemName: "eraser")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .stamp,
                    helpText: "Stamp"
                ) {
                    viewModel.canvasMode = .stamp
                } label: {
                    Image(systemName: "signature")
                }
            }

            // 2. Context-Sensitive Tool Controls
            switch viewModel.canvasMode {
            case .select:
                Divider()
                    .frame(height: 16)

                // Text Markup Quick Actions (always accessible in Select mode)
                HStack(spacing: 2) {
                    PreviewToolbarButton(
                        helpText: "Highlight Selected Text"
                    ) {
                        viewModel.highlightSelection(color: viewModel.selectedAnnotationColor)
                    } label: {
                        Image(systemName: "highlighter")
                    }

                    PreviewToolbarButton(
                        helpText: "Underline Selected Text"
                    ) {
                        viewModel.underlineSelection(color: viewModel.selectedAnnotationColor)
                    } label: {
                        Image(systemName: "underline")
                    }

                    PreviewToolbarButton(
                        helpText: "Strikethrough Selected Text"
                    ) {
                        viewModel.strikethroughSelection(color: viewModel.selectedAnnotationColor)
                    } label: {
                        Image(systemName: "strikethrough")
                    }
                }

                Divider()
                    .frame(height: 16)

                HStack(spacing: 6) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.selectedFontSize, in: 6...32, step: 1)
                        .frame(width: 80)
                        .controlSize(.small)
                    Text("\(Int(viewModel.selectedFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .leading)
                }
                .help("Annotation Font Size (6–32 pt)")

            case .draw:
                Divider()
                    .frame(height: 16)

                // Stroke Width Selector (only in Draw mode)
                Picker("Line Width", selection: $viewModel.drawStrokeWidth) {
                    Text("Thin").tag(CGFloat(1.5))
                    Text("Medium").tag(CGFloat(2.5))
                    Text("Thick").tag(CGFloat(4.5))
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 155)
                .help("Pen Stroke Width")

            case .text:
                Divider()
                    .frame(height: 16)

                // Font Size Slider (6 pt - 32 pt)
                HStack(spacing: 6) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.selectedFontSize, in: 6...32, step: 1)
                        .frame(width: 90)
                        .controlSize(.small)
                    Text("\(Int(viewModel.selectedFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .leading)
                }
                .help("Text Box Font Size (6–32 pt)")

            case .callout:
                Divider()
                    .frame(height: 16)

                HStack(spacing: 6) {
                    Text("Size")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: $viewModel.selectedFontSize, in: 6...32, step: 1)
                        .frame(width: 80)
                        .controlSize(.small)
                    Text("\(Int(viewModel.selectedFontSize)) pt")
                        .font(.caption.monospacedDigit())
                        .frame(width: 32, alignment: .leading)
                    Text("• Drag target to note; click note to edit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .help("Callout Note Font Size (6–32 pt)")

            case .redact:
                EmptyView()

            case .eraser:
                Divider()
                    .frame(height: 16)

                Text("Click or drag annotations to erase")
                    .font(.caption)
                    .foregroundStyle(.secondary)

            case .stamp:
                Divider()
                    .frame(height: 16)

                HStack(spacing: 6) {
                    Image(systemName: "signature")
                        .foregroundColor(.accentColor)
                    Text("Click anywhere on the document to place stamp")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

            case .measureLength, .measurePerimeter, .measureArea, .measureAngle, .calibrateScale:
                EmptyView()
            }

            // 3. Color Palette Swatches (shown for Select, Draw, Text, and Callout modes)
            if viewModel.canvasMode != .eraser && viewModel.canvasMode != .redact && viewModel.canvasMode != .stamp {
                Divider()
                    .frame(height: 16)

                HStack(spacing: 5) {
                    ForEach(AnnotationColor.allCases, id: \.self) { color in
                        Button {
                            viewModel.selectedAnnotationColor = color
                        } label: {
                            ZStack {
                                Circle()
                                    .fill(Color(nsColor: color.nsColor))
                                    .frame(width: 14, height: 14)

                                if viewModel.selectedAnnotationColor == color {
                                    Circle()
                                        .strokeBorder(Color.primary.opacity(0.8), lineWidth: 1.5)
                                        .frame(width: 19, height: 19)
                                }
                            }
                            .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(color.displayName)
                    }
                }
            }

            Spacer()

            // 5. Close Toolbar Button
            PreviewToolbarButton(
                helpText: "Close Markup Toolbar (⇧⌘A)"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.isMarkupBarVisible = false
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .medium))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .frame(height: 32)
        .background(Color(nsColor: .topWindowBarColor))
        .onAppear {
            if viewModel.canvasMode == .stamp {
                if let data = signatureStore.savedSignatureData {
                    viewModel.pendingSignatureData = data
                } else {
                    showSignatureCaptureSheet = true
                }
            }
        }
        .onChange(of: viewModel.canvasMode) { _, newMode in
            if newMode == .stamp {
                if let data = signatureStore.savedSignatureData {
                    viewModel.pendingSignatureData = data
                } else {
                    showSignatureCaptureSheet = true
                }
            } else {
                viewModel.pendingSignatureData = nil
            }
        }
        .sheet(isPresented: $showSignatureCaptureSheet) {
            SignatureCaptureView { image in
                showSignatureCaptureSheet = false
                if let image = image, let data = image.pdfStampPNGData {
                    viewModel.pendingSignatureData = data
                    viewModel.canvasMode = .stamp
                } else {
                    viewModel.canvasMode = .select
                    viewModel.pendingSignatureData = nil
                }
            }
        }
    }
}

