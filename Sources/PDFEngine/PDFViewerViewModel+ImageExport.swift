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
import UniformTypeIdentifiers

/// What the save panel's options chose, for Export Pages as Images.
@MainActor
final class PageImageExportOptions: ObservableObject {
    enum Pages: Hashable { case all, current, selected }

    @Published var format: PageImageFormat
    @Published var dpi: Int
    @Published var pages: Pages

    static let resolutions = [72, 150, 300, 600]
    private static let formatKey = "com.thomasderham.vectorpdf.imageExportFormat"
    private static let dpiKey = "com.thomasderham.vectorpdf.imageExportDPI"

    init(pages: Pages) {
        format = UserDefaults.standard.string(forKey: Self.formatKey).flatMap(PageImageFormat.init) ?? .png
        let dpi = UserDefaults.standard.integer(forKey: Self.dpiKey)
        self.dpi = Self.resolutions.contains(dpi) ? dpi : 150
        self.pages = pages
    }

    func remember() {
        UserDefaults.standard.set(format.rawValue, forKey: Self.formatKey)
        UserDefaults.standard.set(dpi, forKey: Self.dpiKey)
    }
}

private struct PageImageExportOptionsView: View {
    @ObservedObject var options: PageImageExportOptions
    let currentPage: Int
    let selectedCount: Int

    var body: some View {
        Form {
            Picker("Format:", selection: $options.format) {
                ForEach(PageImageFormat.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            Picker("Resolution:", selection: $options.dpi) {
                ForEach(PageImageExportOptions.resolutions, id: \.self) { Text("\($0) dpi").tag($0) }
            }
            Picker("Pages:", selection: $options.pages) {
                Text("All").tag(PageImageExportOptions.Pages.all)
                Text("Current Page (\(currentPage + 1))").tag(PageImageExportOptions.Pages.current)
                if selectedCount > 1 {
                    Text("Selected Pages (\(selectedCount))").tag(PageImageExportOptions.Pages.selected)
                }
            }
        }
        .fixedSize()
        .padding(12)
    }
}

extension PDFViewerViewModel {
    /// Exports pages as PNG, JPEG or TIFF images, asking where and how in a save panel.
    /// `selectedPages`: from the thumbnails' menu, the pages chosen there.
    public func exportPagesAsImages(selectedPages: Bool = false) {
        guard let doc = document else { return }
        let selection = selectedThumbnailPageIndices.sorted().filter { $0 < doc.pageCount }
        let options = PageImageExportOptions(pages: selectedPages && selection.count > 1 ? .selected : (selectedPages ? .current : .all))
        let current = selectedPages && selection.count == 1 ? selection[0] : currentPageIndex
        let baseName = URL(fileURLWithPath: doc.filePath).deletingPathExtension().lastPathComponent

        let panel = NSSavePanel()
        panel.title = "Export Pages as Images"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let accessory = NSHostingView(rootView: PageImageExportOptionsView(options: options, currentPage: current, selectedCount: selection.count))
        accessory.frame.size = accessory.fittingSize
        panel.accessoryView = accessory
        // The extension follows the format, keeping any name typed.
        func update() {
            panel.allowedContentTypes = [options.format.contentType]
            let typed = (panel.nameFieldStringValue as NSString).deletingPathExtension
            panel.nameFieldStringValue = "\(typed).\(options.format.fileExtension)"
            let pageCount = options.pages == .all ? doc.pageCount : options.pages == .selected ? selection.count : 1
            panel.message = pageCount > 1 ? "The \(pageCount) pages go in a folder of this name, one image each." : ""
        }
        let single = options.pages == .current || (options.pages == .all && doc.pageCount == 1)
        panel.nameFieldStringValue = single && doc.pageCount > 1 ? "\(baseName) page \(current + 1)" : baseName
        update()
        let watcher = options.objectWillChange.sink { _ in DispatchQueue.main.async { update() } }
        defer { watcher.cancel() }

        guard panel.runModal() == .OK, let url = panel.url else { return }
        options.remember()
        let pages: [Int]
        switch options.pages {
        case .all: pages = Array(0..<doc.pageCount)
        case .current: pages = [current]
        case .selected: pages = selection
        }
        let format = options.format, dpi = Double(options.dpi)
        Task { [weak self] in
            let failure: String? = await Task.detached(priority: .userInitiated) {
                do {
                    try doc.exportPageImages(pageIndices: pages, format: format, dpi: dpi, to: url) { _ in !Task.isCancelled }
                    return nil
                } catch {
                    return error.localizedDescription
                }
            }.value
            if let failure { self?.showErrorAlert(title: "Couldn't Export the Pages", message: failure) }
        }
    }
}
