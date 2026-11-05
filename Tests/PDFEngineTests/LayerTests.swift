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

import Foundation
import CoreGraphics
import Testing
@testable import PDFEngine

/// The object number of the `index`th layer in a PDF `makeLayeredPDF` writes, for `config`.
private func layerRef(_ index: Int) -> String { "\(6 + index) 0 R" }

/// Writes a one-page PDF with a layer for each name in `layers`. Each layer holds its name in
/// capitals as text, and a black 50pt square at x = 100 + 100 × its index, y = 100. `config`
/// is the rest of the default configuration (`/D`): its /Order, /OFF, /RBGroups or /Locked.
/// With no layers it's a plain page.
private func makeLayeredPDF(at url: URL, layers: [String], config: String = "") throws {
    let refs = layers.indices.map(layerRef).joined(separator: " ")
    let ocProperties = layers.isEmpty ? "" : " /OCProperties << /OCGs [\(refs)] /D << \(config) >> >>"
    var content = "BT /F1 12 Tf 72 740 Td (Always shown) Tj ET\n"
    for (index, name) in layers.enumerated() {
        content += "/OC /L\(index) BDC BT /F1 24 Tf 72 \(700 - 40 * index) Td (\(name.uppercased())) Tj ET "
        content += "0 0 0 rg \(100 + 100 * index) 100 50 50 re f EMC\n"
    }
    let properties = layers.indices.map { "/L\($0) \(layerRef($0))" }.joined(separator: " ")
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R\(ocProperties) >>",
        "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> /Properties << \(properties) >> >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]
    objects += layers.map { "<< /Type /OCG /Name (\($0)) >>" }
    var file = "%PDF-1.7\n"
    var offsets: [Int] = []
    for (index, object) in objects.enumerated() {
        offsets.append(file.utf8.count)
        file += "\(index + 1) 0 obj\n\(object)\nendobj\n"
    }
    let xref = file.utf8.count
    file += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets { file += String(format: "%010d 00000 n \n", offset) }
    file += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
    try Data(file.utf8).write(to: url)
}

/// Whether the `index`th layer's square is drawn in `image`, rendered at scale 1.
private func showsSquare(_ index: Int, in image: CGImage) -> Bool {
    let x = 125 + 100 * index
    let y = 792 - 125
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
    let pixel = bytes + y * image.bytesPerRow + x * (image.bitsPerPixel / 8)
    return pixel[0] < 128
}

private func text(of doc: PDFDocumentCore) -> String {
    doc.loadStructuredPage(for: 0)?.plainText ?? ""
}

private let threeLayers = ["Walls", "Pipes", "Wiring"]

@Suite(.serialized)
struct LayerTests {
    private func open(layers: [String], config: String = "", in dir: URL) throws -> (PDFDocumentCore, URL) {
        let url = dir.appendingPathComponent("\(UUID().uuidString).pdf")
        try makeLayeredPDF(at: url, layers: layers, config: config)
        return (try PDFDocumentCore(filePath: url.path), url)
    }

    // MARK: - Listing

    @Test func aDocumentWithoutLayersHasNone() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(layers: [], in: dir)
        #expect(doc.layers().isEmpty)
        #expect(doc.layerStates().isEmpty)
    }

    @Test func listsLayersAsTheDocumentOrdersThem() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let order = "/Order [ [ (Architectural) \(layerRef(0)) ] \(layerRef(2)) \(layerRef(1)) ] /OFF [\(layerRef(1))]"
        let (doc, _) = try open(layers: threeLayers, config: order, in: dir)
        let layers = doc.layers()
        #expect(layers.map(\.name) == ["Architectural", "Walls", "Wiring", "Pipes"])
        #expect(layers.map(\.kind) == [.heading, .checkbox, .checkbox, .checkbox])
        #expect(layers[1].depth > layers[0].depth)
        #expect(layers.map(\.isVisible) == [false, true, true, false])
        #expect(!layers[0].canToggle)
    }

    @Test func withoutAnOrderEveryLayerIsListed() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(layers: threeLayers, config: "/OFF [\(layerRef(2))]", in: dir)
        let layers = doc.layers()
        #expect(layers.map(\.name) == threeLayers)
        #expect(layers.map(\.isVisible) == [true, true, false])

        try doc.toggleLayer(id: 2)
        try doc.toggleLayer(id: 0)
        #expect(doc.layers().map(\.isVisible) == [false, true, true])
        #expect(!text(of: doc).contains("WALLS"))
        #expect(text(of: doc).contains("WIRING"))
    }

    // MARK: - Showing and hiding

    @Test func aHiddenLayersTextCantBeSelected() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(layers: threeLayers, config: "/Order [\(layerRef(0)) \(layerRef(1)) \(layerRef(2))]", in: dir)
        #expect(text(of: doc).contains("WALLS"))

        try doc.toggleLayer(id: 0)
        #expect(!doc.layers()[0].isVisible)
        let hidden = text(of: doc)
        #expect(!hidden.contains("WALLS"))
        #expect(hidden.contains("PIPES"))
        #expect(hidden.contains("Always shown"))

        try doc.toggleLayer(id: 0)
        #expect(text(of: doc).contains("WALLS"))
    }

    @Test func choosingOneOfAGroupHidesTheOthers() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = "/Order [\(layerRef(0)) \(layerRef(1)) \(layerRef(2))] /OFF [\(layerRef(2))] /RBGroups [[\(layerRef(1)) \(layerRef(2))]]"
        let (doc, _) = try open(layers: threeLayers, config: config, in: dir)
        #expect(doc.layers().map(\.kind) == [.checkbox, .radio, .radio])

        try doc.toggleLayer(id: 2)
        #expect(doc.layers().map(\.isVisible) == [true, false, true])
    }

    @Test func aLockedLayerStaysAsItIs() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let config = "/Order [\(layerRef(0)) \(layerRef(1))] /Locked [\(layerRef(0))]"
        let (doc, _) = try open(layers: ["Title Block", "Notes"], config: config, in: dir)
        let layers = doc.layers()
        #expect(layers[0].isLocked)
        #expect(!layers[0].canToggle)

        try doc.toggleLayer(id: 0)
        #expect(doc.layers()[0].isVisible)
    }

    @Test func otherCopiesDrawAndSearchTheLayersShown() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, url) = try open(layers: threeLayers, in: dir)
        let renderer = PDFRenderActor()
        try await renderer.openDocument(filePath: url.path)
        let search = PDFSearchActor(workerCount: 2)
        try await search.openDocument(filePath: url.path)

        // Fills the display list cache with every layer shown.
        let before = try await renderer.renderPage(pageIndex: 0, scale: 1).image
        #expect((0..<3).allSatisfy { showsSquare($0, in: before) })

        try doc.toggleLayer(id: 1)
        await renderer.setLayerStates(doc.layerStates())
        await search.setLayerStates(doc.layerStates())

        let after = try await renderer.renderPage(pageIndex: 0, scale: 1).image
        #expect(showsSquare(0, in: after))
        #expect(!showsSquare(1, in: after))
        #expect(showsSquare(2, in: after))

        var found: [String] = []
        for await result in await search.searchStream(query: "PIPES") { found.append(result.matchedText) }
        #expect(found.isEmpty)
        for await result in await search.searchStream(query: "WIRING") { found.append(result.matchedText) }
        #expect(!found.isEmpty)
    }

    @Test func savingKeepsTheFilesOwnLayers() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(layers: threeLayers, in: dir)
        try doc.toggleLayer(id: 0)
        let saved = dir.appendingPathComponent("saved.pdf")
        try doc.save(to: saved.path)
        #expect(try PDFDocumentCore(filePath: saved.path).layers().map(\.isVisible) == [true, true, true])
    }

    // MARK: - Window

    @MainActor
    @Test func theViewerListsLayersOnlyForADocumentWithThem() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let layered = dir.appendingPathComponent("layered.pdf")
        let plain = dir.appendingPathComponent("plain.pdf")
        try makeLayeredPDF(at: layered, layers: threeLayers)
        try makeLayeredPDF(at: plain, layers: [])

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: plain.path)
        #expect(vm.layers.isEmpty)

        await vm.loadDocument(from: layered.path)
        #expect(vm.layers.map(\.name) == threeLayers)

        await vm.loadDocument(from: plain.path)
        #expect(vm.layers.isEmpty)
    }

    @MainActor
    @Test func layersStayHiddenWhenTheRendererReopens() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("layered.pdf")
        try makeLayeredPDF(at: url, layers: threeLayers)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        vm.toggleLayer(vm.layers[0])
        #expect(!vm.layers[0].isVisible)
        #expect(vm.document.map(text(of:))?.contains("WALLS") == false)

        // As after a page edit, which reopens the renderer on a saved copy.
        #expect(await vm.reopenActors(at: url.path))
        let image = try await vm.renderActor.renderPage(pageIndex: 0, scale: 1).image
        #expect(!showsSquare(0, in: image))
        #expect(showsSquare(1, in: image))
    }
}
