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

/// The sample document offered to new users, made by `Scripts/make_tour_pdf.py`.
///
/// Readers open a copy in Application Support, because saving a markup into the app bundle would
/// fail in /Applications and invalidate the code signature anywhere else. An existing copy is kept,
/// so the tour reopens with the reader's own markups.
public enum TourDocument {
    static let fileName = "VectorPDF Tour.pdf"

    /// Debug builds outside an app bundle (`swift run`, tests) use the copy in the source tree.
    public static var bundledURL: URL? {
        if let url = Bundle.main.url(forResource: "VectorPDF Tour", withExtension: "pdf") {
            return url
        }
        #if DEBUG
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources").appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: source.path) ? source : nil
        #else
        return nil
        #endif
    }

    /// Copies `source` into `directory` unless it's there already, and returns the copy's URL.
    static func installedCopy(of source: URL, in directory: URL) throws -> URL {
        let fm = FileManager.default
        let destination = directory.appendingPathComponent(fileName)
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        if !fm.fileExists(atPath: destination.path) {
            try fm.copyItem(at: source, to: destination)
            // Bundle files can be read-only.
            try fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: destination.path)
        }
        return destination
    }

    /// Opens the tour, in `viewModel`'s Start screen if there is one, otherwise like a Finder open.
    @MainActor
    public static func open(in viewModel: PDFViewerViewModel? = nil) {
        guard let source = bundledURL else { return }
        do {
            let support = try FileManager.default.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let url = try installedCopy(of: source, in: support.appendingPathComponent("VectorPDF"))
            if let viewModel {
                Task { await viewModel.loadDocument(from: url.path) }
            } else {
                DocumentWindowing.openDocumentHandlingEmptyStart(url: url)
            }
        } catch {
            guard !PDFViewerViewModel.isRunningTests else { return }
            NSAlert(error: error).runModal()
        }
    }
}
