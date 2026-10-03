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

/// A collapsible secondary toolbar providing calibrated AEC measurement tools,
/// drawing scale indicators, snapping controls, color swatches, and takeoff export triggers.
public struct PDFMeasurementToolbarView: View {
    @ObservedObject var viewModel: PDFViewerViewModel

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var activePageScale: PDFScaleConfiguration {
        viewModel.scaleConfig(for: viewModel.currentPageIndex)
    }

    public var body: some View {
        HStack(spacing: 10) {
            // 1. Tool Mode Buttons
            HStack(spacing: 2) {
                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .measureLength,
                    helpText: "Linear Dimension Tool (Measure distance between two points)"
                ) {
                    viewModel.canvasMode = .measureLength
                } label: {
                    Image(systemName: "ruler")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .measurePerimeter,
                    helpText: "Perimeter Tool (Multi-segment polyline tracing)"
                ) {
                    viewModel.canvasMode = .measurePerimeter
                } label: {
                    Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .measureArea,
                    helpText: "Polygon Area Tool (Surface area & room takeoff)"
                ) {
                    viewModel.canvasMode = .measureArea
                } label: {
                    Image(systemName: "trapezoid.and.line.vertical")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.canvasMode == .measureAngle,
                    helpText: "Vertex Angle Inspector (Angle between intersecting lines)"
                ) {
                    viewModel.canvasMode = .measureAngle
                } label: {
                    Image(systemName: "angle")
                }
            }

            Divider()
                .frame(height: 16)

            // 2. Active Scale Pill & Calibration Trigger
            Button {
                viewModel.isShowingCalibrationSheet = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "scalemass")
                        .font(.system(size: 11))
                        .foregroundColor(.accentColor)
                    Text(activePageScale.ratioString)
                        .font(.caption.monospacedDigit().weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Click to Change Drawing Scale or Calibrate")

            Divider()
                .frame(height: 16)

            // 3. Snapping Controls
            HStack(spacing: 2) {
                PreviewToolbarButton(
                    isSelected: viewModel.isOrthoSnapEnabled,
                    helpText: "Ortho Lock (0°, 45°, 90° snapping; hold Shift while dragging)"
                ) {
                    viewModel.isOrthoSnapEnabled.toggle()
                } label: {
                    Image(systemName: "compass.drawing")
                }

                PreviewToolbarButton(
                    isSelected: viewModel.isVertexSnapEnabled,
                    helpText: "Vertex Magnetic Snapping (Snaps cursor to corners and endpoints)"
                ) {
                    viewModel.isVertexSnapEnabled.toggle()
                } label: {
                    Image(systemName: "dot.circle.and.hand.point.up.left.fill")
                }
            }

            Divider()
                .frame(height: 16)

            // 4. Line Width Selector
            Picker("Line Width", selection: $viewModel.drawStrokeWidth) {
                Text("Thin").tag(CGFloat(1.5))
                Text("Medium").tag(CGFloat(2.5))
                Text("Thick").tag(CGFloat(4.5))
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .controlSize(.small)
            .frame(width: 145)
            .help("Dimension Stroke Width")

            Divider()
                .frame(height: 16)

            // 5. Color Palette Swatches
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

            Divider()
                .frame(height: 16)

            // 6. Takeoff Table Sheet Button
            Button {
                viewModel.isShowingTakeoffTable = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "tablecells")
                        .font(.system(size: 11))
                    Text("Takeoff Table")
                        .font(.caption)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(5)
            }
            .buttonStyle(.plain)
            .help("Open Takeoff Review Summary & Export Table")

            Spacer()

            // 7. Close Toolbar Button
            PreviewToolbarButton(
                helpText: "Close Measurement Toolbar (⇧⌘M)"
            ) {
                withAnimation(.easeInOut(duration: 0.15)) {
                    viewModel.isMeasurementBarVisible = false
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
    }
}
