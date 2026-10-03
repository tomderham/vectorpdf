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

/// Modal sheet for selecting predefined drawing scale presets or interactively calibrating scale from a known dimension line.
public struct ScaleCalibrationSheet: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedCategory: ScaleCategory = .metric
    @State private var selectedPresetId: String = "met_1_100"

    // Custom / Interactive calibration inputs
    @State private var inputFeet: String = "10"
    @State private var inputInches: String = "0"
    @State private var inputMetricValue: String = "5.0"
    @State private var selectedLinearUnit: MeasurementUnit = .meters
    @State private var selectedAreaUnit: AreaUnit = .squareMeters

    public init(viewModel: PDFViewerViewModel) {
        self.viewModel = viewModel
    }

    private var activeConfig: PDFScaleConfiguration {
        viewModel.scaleConfig(for: viewModel.currentPageIndex)
    }

    /// A non-negative number typed with either a decimal point or a decimal comma.
    private static func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let normalized = trimmed.contains(".") ? trimmed : trimmed.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value >= 0, value.isFinite else { return nil }
        return value
    }

    /// The known real-world length entered for the measured line, or nil if invalid.
    private var enteredRealLength: Double? {
        if selectedLinearUnit == .footInch {
            let feet = inputFeet.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Self.parseNumber(inputFeet)
            let inches = inputInches.trimmingCharacters(in: .whitespaces).isEmpty ? 0 : Self.parseNumber(inputInches)
            guard let feet, let inches else { return nil }
            let total = feet + inches / 12.0
            return total > 0 ? total : nil
        }
        guard let value = Self.parseNumber(inputMetricValue), value > 0 else { return nil }
        return value
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "scalemass")
                    .font(.system(size: 20))
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Drawing Scale Calibration")
                        .font(.headline)
                    Text("Set drawing scale from standard presets or calibrate from a known line.")
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
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // If triggered by interactive 2-point measurement
                    if viewModel.calibrationMeasuredPoints > 0 {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Line Measured: \(String(format: "%.1f", viewModel.calibrationMeasuredPoints)) pt (\(String(format: "%.2f", viewModel.calibrationMeasuredPoints / 72.0)) in on paper)")
                                    .font(.subheadline.bold())
                            }

                            Text("Enter the known real-world dimension for this line:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            HStack(spacing: 12) {
                                if selectedLinearUnit == .footInch {
                                    HStack(spacing: 4) {
                                        TextField("Feet", text: $inputFeet)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        Text("ft")
                                            .font(.caption)
                                        TextField("Inches", text: $inputInches)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 60)
                                        Text("in")
                                            .font(.caption)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        TextField("Dimension", text: $inputMetricValue)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 80)
                                        Text(selectedLinearUnit.shortSymbol)
                                            .font(.caption)
                                    }
                                }

                                Picker("Linear Format", selection: $selectedLinearUnit) {
                                    ForEach(MeasurementUnit.allCases, id: \.self) { u in
                                        Text(u.displayName).tag(u)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 170)
                            }

                            if enteredRealLength == nil {
                                Text("Enter a length greater than zero.")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(12)
                        .background(Color.accentColor.opacity(0.08))
                        .cornerRadius(8)
                    }

                    // Predefined Presets
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Standard Drawing Scales")
                            .font(.subheadline.bold())

                        Picker("Drawing Type", selection: $selectedCategory) {
                            Text("Metric (ISO)").tag(ScaleCategory.metric)
                            Text("Architectural (US)").tag(ScaleCategory.architectural)
                            Text("Civil Engineering (US)").tag(ScaleCategory.engineering)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .onChange(of: selectedCategory) { _, newCategory in
                            switch newCategory {
                            case .metric:
                                selectedPresetId = "met_1_100"
                                selectedLinearUnit = .meters
                                selectedAreaUnit = .squareMeters
                            case .architectural:
                                selectedPresetId = "arch_1_4"
                                selectedLinearUnit = .footInch
                                selectedAreaUnit = .squareMeters
                            case .engineering:
                                selectedPresetId = "eng_10"
                                selectedLinearUnit = .decimalFeet
                                selectedAreaUnit = .squareMeters
                            case .custom:
                                break
                            }
                        }

                        let filteredPresets = ScalePreset.standardPresets.filter { $0.category == selectedCategory }
                        Picker("Scale", selection: $selectedPresetId) {
                            ForEach(filteredPresets) { preset in
                                Text(preset.name).tag(preset.id)
                            }
                        }
                        .pickerStyle(.menu)

                        HStack {
                            Button("Calibrate by Measuring Known Line...") {
                                viewModel.calibrationMeasuredPoints = 0.0
                                viewModel.canvasMode = .calibrateScale
                                dismiss()
                            }
                            .buttonStyle(.link)
                            .font(.caption)

                            Spacer()
                        }
                    }

                    Divider()

                    // Area format
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Area Takeoff")
                            .font(.subheadline.bold())

                        Picker("Format", selection: $selectedAreaUnit) {
                            ForEach(AreaUnit.allCases, id: \.self) { au in
                                Text(au.displayName).tag(au)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 220)
                    }
                }
                .padding(16)
            }

            Divider()

            // Action Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text("Applies to all pages")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Button("Apply Scale") {
                    applyScale()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.calibrationMeasuredPoints > 0 && enteredRealLength == nil)
            }
            .padding(14)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 440, height: 380)
        .onDisappear {
            // Reset measured line when dismissing without saving.
            viewModel.calibrationMeasuredPoints = 0.0
        }
        .onAppear {
            if viewModel.calibrationMeasuredPoints > 0 {
                selectedLinearUnit = .meters
                selectedAreaUnit = .squareMeters
            } else {
                // Find matching preset for activeConfig
                if let match = ScalePreset.standardPresets.first(where: { abs($0.pointsPerUnit - activeConfig.pointsPerUnit) < 0.001 }) {
                    selectedCategory = match.category
                    selectedPresetId = match.id
                    selectedAreaUnit = activeConfig.areaUnit
                    selectedLinearUnit = match.linearUnit
                } else {
                    selectedCategory = .metric
                    selectedPresetId = "met_1_100"
                    selectedAreaUnit = .squareMeters
                    selectedLinearUnit = .meters
                }
            }
        }
    }

    private func applyScale() {
        if viewModel.calibrationMeasuredPoints > 0 {
            // Interactive 2-point calibration
            guard let realLen = enteredRealLength else { return }
            let config = PDFScaleConfiguration.calibrated(
                measuredPoints: viewModel.calibrationMeasuredPoints,
                knownRealWorldLength: realLen,
                unit: selectedLinearUnit,
                areaUnit: selectedAreaUnit
            )
            viewModel.setScaleConfig(config, for: viewModel.currentPageIndex, applyToAll: true)
            viewModel.calibrationMeasuredPoints = 0.0
        } else if let preset = ScalePreset.standardPresets.first(where: { $0.id == selectedPresetId }) {
            let config = PDFScaleConfiguration(
                name: preset.name,
                pointsPerUnit: preset.pointsPerUnit,
                linearUnit: preset.linearUnit,
                areaUnit: selectedAreaUnit,
                precisionFractionDenominator: 16,
                ratioString: preset.name
            )
            viewModel.setScaleConfig(config, for: viewModel.currentPageIndex, applyToAll: true)
        }
    }
}
