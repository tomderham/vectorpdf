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

import AppKit
import SwiftUI

/// Edit > Headers, Footers and Watermark: what to put on the pages, and which pages.
struct PageMarksSheet: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var settings = PageMarkSettings()
    @State private var part = Part.headerFooter
    @State private var hadMarks = false
    @FocusState private var focus: Field?

    private enum Part: String, CaseIterable {
        case headerFooter = "Header & Footer", watermark = "Watermark", pages = "Pages & Numbers"
    }

    /// The text fields a token can be put in.
    private enum Field: Hashable {
        case slot(Int), watermark, batesPrefix, batesSuffix
    }

    /// The field tokens go in: the one being edited, else the bottom center.
    @State private var lastTextField = Field.slot(4)

    private var pageCount: Int { viewModel.document?.pageCount ?? 1 }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Part", selection: $part) {
                ForEach(Part.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 8)

            Form {
                switch part {
                case .headerFooter: headerFooter
                case .watermark: watermark
                case .pages: pagesAndNumbers
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 340)

            Divider()
            HStack {
                if hadMarks {
                    Button("Remove All") {
                        viewModel.applyPageMarks(PageMarkSettings())
                        dismiss()
                    }
                    .help("Take the headers, footers and watermark off every page")
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(hadMarks ? "Update" : "Add") {
                    viewModel.applyPageMarks(settings)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(settings.isEmpty && !hadMarks)
            }
            .padding(16)
        }
        .frame(width: 600)
        .onAppear {
            settings = viewModel.initialPageMarkSettings()
            hadMarks = viewModel.hasPageMarks
        }
        .onChange(of: focus) { _, field in
            if let field, field != .batesPrefix, field != .batesSuffix { lastTextField = field }
        }
    }

    // MARK: - Header and footer

    @ViewBuilder
    private var headerFooter: some View {
        Section {
            Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    Text("")
                    Text("Left").font(.caption).foregroundStyle(.secondary)
                    Text("Center").font(.caption).foregroundStyle(.secondary)
                    Text("Right").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(0..<2) { row in
                    GridRow {
                        Text(row == 0 ? "Header" : "Footer")
                        ForEach(0..<3) { col in
                            TextField("", text: $settings.header.texts[row * 3 + col])
                                .textFieldStyle(.roundedBorder)
                                .focused($focus, equals: .slot(row * 3 + col))
                                .accessibilityLabel("\(row == 0 ? "Header" : "Footer") \(["left", "center", "right"][col])")
                        }
                    }
                }
            }
            HStack {
                insertMenu
                Spacer()
                Text("For example, Page <<page>> of <<pages>>")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        Section("Text") {
            fontPicker($settings.header.font)
            sizeField("Size", value: $settings.header.size, range: 4...72)
            ColorPicker("Color", selection: colorBinding($settings.header.color), supportsOpacity: false)
        }
        Section("Margins (points)") {
            HStack(spacing: 16) {
                marginField("Top", $settings.header.marginTop)
                marginField("Bottom", $settings.header.marginBottom)
                marginField("Left", $settings.header.marginLeft)
                marginField("Right", $settings.header.marginRight)
            }
        }
    }

    // MARK: - Watermark

    @ViewBuilder
    private var watermark: some View {
        Section {
            TextField("Text", text: $settings.watermark.text, prompt: Text("CONFIDENTIAL"), axis: .vertical)
                .lineLimit(1...4)
                .focused($focus, equals: .watermark)
            insertMenu
        }
        Section("Text") {
            fontPicker($settings.watermark.font)
            Toggle("As large as fits the page", isOn: Binding(
                get: { settings.watermark.size <= 0 },
                set: { settings.watermark.size = $0 ? 0 : 72 }
            ))
            if settings.watermark.size > 0 {
                sizeField("Size", value: $settings.watermark.size, range: 6...400)
            }
            ColorPicker("Color", selection: colorBinding($settings.watermark.color), supportsOpacity: false)
            LabeledContent("Opacity") {
                HStack {
                    Slider(value: $settings.watermark.opacity, in: 0.05...1)
                    Text("\(Int((settings.watermark.opacity * 100).rounded()))%")
                        .monospacedDigit()
                        .frame(width: 40, alignment: .trailing)
                }
            }
            Picker("Angle", selection: $settings.watermark.rotation) {
                Text("Horizontal").tag(0.0)
                Text("Diagonal up").tag(45.0)
                Text("Diagonal down").tag(-45.0)
                Text("Vertical").tag(90.0)
            }
            Toggle("Behind the page's content", isOn: $settings.watermark.behindContent)
                .help("Drawn under the page's text and pictures. A page with a background, such as a scan, hides it.")
        }
    }

    // MARK: - Pages and numbers

    @ViewBuilder
    private var pagesAndNumbers: some View {
        Section("Pages") {
            Picker("Pages", selection: $settings.pages.which) {
                Text("All").tag(PageMarkSettings.PageChoice.Which.all)
                Text("Odd").tag(PageMarkSettings.PageChoice.Which.odd)
                Text("Even").tag(PageMarkSettings.PageChoice.Which.even)
            }
            .pickerStyle(.segmented)
            HStack {
                pageNumberField("From", $settings.pages.from, placeholder: "1")
                pageNumberField("To", $settings.pages.to, placeholder: "\(pageCount)")
            }
            let count = settings.pages.indices(pageCount: pageCount).count
            Text("\(count) of \(pageCount) page\(pageCount == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section("Page numbers") {
            LabeledContent("First page marked is page") {
                TextField("", value: $settings.firstPageNumber, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
            }
        }
        Section("Bates numbers") {
            TextField("Prefix", text: $settings.bates.prefix, prompt: Text("ACME-"))
                .focused($focus, equals: .batesPrefix)
            TextField("Suffix", text: $settings.bates.suffix)
                .focused($focus, equals: .batesSuffix)
            Stepper("Digits: \(settings.bates.digits)", value: $settings.bates.digits, in: 1...12)
            LabeledContent("Start at") {
                TextField("", value: $settings.bates.start, format: .number.grouping(.never))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 100)
            }
            Text("The first page marked will be \(settings.bates.number(0)). Put <<bates>> in a header or footer to show them.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Parts

    private var insertMenu: some View {
        Menu("Insert") {
            ForEach(PageMarkSettings.Token.allCases, id: \.self) { token in
                Button(token.title) { insert(token) }
            }
        }
        .fixedSize()
        .help("Put a page number, Bates number, the date or the file name in the field being edited")
    }

    private func insert(_ token: PageMarkSettings.Token) {
        switch lastTextField {
        case .slot(let index):
            settings.header.texts[index] += token.rawValue
        case .watermark:
            settings.watermark.text += token.rawValue
        case .batesPrefix, .batesSuffix:
            break
        }
        // The token's field, for typing on after it.
        focus = part == .watermark ? .watermark : lastTextField
    }

    private func fontPicker(_ font: Binding<PageMarkSettings.MarkFont>) -> some View {
        Picker("Font", selection: font) {
            ForEach(PageMarkSettings.MarkFont.allCases, id: \.self) { Text($0.displayName).tag($0) }
        }
    }

    private func sizeField(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 4) {
                TextField("", value: value, format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 60)
                Stepper("", value: value, in: range)
                    .labelsHidden()
                Text("pt").foregroundStyle(.secondary)
            }
        }
    }

    private func marginField(_ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number.precision(.fractionLength(0...1)))
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .frame(width: 70)
        }
    }

    private func pageNumberField(_ title: String, _ value: Binding<Int?>, placeholder: String) -> some View {
        LabeledContent(title) {
            TextField("", value: value, format: .number, prompt: Text(placeholder))
                .textFieldStyle(.roundedBorder)
                .frame(width: 70)
        }
    }

    private func colorBinding(_ color: Binding<PageMarkSettings.MarkColor>) -> Binding<Color> {
        Binding(
            get: { Color(nsColor: color.wrappedValue.nsColor) },
            set: { color.wrappedValue = PageMarkSettings.MarkColor(NSColor($0)) }
        )
    }
}
