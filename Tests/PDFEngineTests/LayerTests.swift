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

/// Where `makeLayeredPDF` draws each layer's text and square.
enum LayerDrawing: Sendable {
    /// In the page's content, as marked content on the layer.
    case onThePage
    /// In a form of its own, drawn from the page inside marked content on the layer.
    case formInsideMarkedContent
    /// In a form of its own, as marked content on the layer inside it, drawn from the page.
    case markedContentInsideForm
}

/// Writes a one-page PDF with a layer for each name in `layers`. Each layer holds its name in
/// capitals as text, and a black 50pt square at x = 100 + 100 × its index, y = 100. `config`
/// is the rest of the default configuration (`/D`): its /Order, /OFF, /RBGroups or /Locked;
/// `properties` the rest of /OCProperties, such as /Configs. With no layers it's a plain page.
private func makeLayeredPDF(at url: URL, layers: [String], config: String = "", properties extra: String = "",
                            drawing: LayerDrawing = .onThePage) throws {
    let refs = layers.indices.map(layerRef).joined(separator: " ")
    let ocProperties = layers.isEmpty ? "" : " /OCProperties << /OCGs [\(refs)] /D << \(config) >> \(extra) >>"
    let formNumber = { (index: Int) in 6 + layers.count + index }
    var content = "BT /F1 12 Tf 72 740 Td (Always shown) Tj ET\n"
    var forms: [String] = []
    for (index, name) in layers.enumerated() {
        let drawn = "BT /F1 24 Tf 72 \(700 - 40 * index) Td (\(name.uppercased())) Tj ET 0 0 0 rg \(100 + 100 * index) 100 50 50 re f"
        let marked = "/OC /L\(index) BDC \(drawn) EMC"
        switch drawing {
        case .onThePage:
            content += marked + "\n"
        case .formInsideMarkedContent:
            content += "/OC /L\(index) BDC /Fm\(index) Do EMC\n"
            forms.append(form(drawn, properties: ""))
        case .markedContentInsideForm:
            content += "/Fm\(index) Do\n"
            forms.append(form(marked, properties: "/Properties << /L\(index) \(layerRef(index)) >>"))
        }
    }
    func form(_ stream: String, properties: String) -> String {
        "<< /Type /XObject /Subtype /Form /BBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> \(properties) >> /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream"
    }
    let properties = layers.indices.map { "/L\($0) \(layerRef($0))" }.joined(separator: " ")
    let xobjects = forms.indices.map { "/Fm\($0) \(formNumber($0)) 0 R" }.joined(separator: " ")
    var objects = [
        "<< /Type /Catalog /Pages 2 0 R\(ocProperties) >>",
        "<< /Type /Pages /Count 1 /Kids [3 0 R] >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 5 0 R >> /Properties << \(properties) >> /XObject << \(xobjects) >> >> /Contents 4 0 R >>",
        "<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream",
        "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"
    ]
    objects += layers.map { "<< /Type /OCG /Name (\($0)) >>" }
    objects += forms
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

/// Whether `image`, rendered at scale 1, has anything other than white within 3 points of `point`
/// (page coordinates, top-down).
private func hasInk(near point: CGPoint, in image: CGImage) -> Bool {
    guard let data = image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return false }
    let step = image.bitsPerPixel / 8
    for y in max(0, Int(point.y) - 3)...min(image.height - 1, Int(point.y) + 3) {
        for x in max(0, Int(point.x) - 3)...min(image.width - 1, Int(point.x) + 3) {
            let pixel = bytes + y * image.bytesPerRow + x * step
            if pixel[0] < 200 || pixel[1] < 200 || pixel[2] < 200 { return true }
        }
    }
    return false
}

@MainActor
@Suite(.serialized)
struct AnnotationLayerTests {
    private func open(layers: [String] = threeLayers, config: String = "", in dir: URL) async throws -> (PDFViewerViewModel, URL) {
        let url = dir.appendingPathComponent("\(UUID().uuidString).pdf")
        try makeLayeredPDF(at: url, layers: layers, config: config)
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        vm.undoManager.groupsByEvent = false
        return (vm, url)
    }

    private func step(_ vm: PDFViewerViewModel, _ body: () -> Void) {
        vm.undoManager.beginUndoGrouping()
        body()
        vm.undoManager.endUndoGrouping()
    }

    private func layer(_ vm: PDFViewerViewModel, _ name: String) throws -> PDFLayer {
        try #require(vm.layers.first { $0.name == name })
    }

    /// A rectangle, as one step for Undo (tests group their own, see `open`).
    private func rectangle(_ vm: PDFViewerViewModel) -> PDFEngine.PDFAnnotation? {
        var made: PDFEngine.PDFAnnotation?
        step(vm) { made = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 400, y: 400)) }
        return made
    }

    /// The saved file drawn by a renderer of its own, with layers shown as in `vm`.
    private func renderSaved(_ vm: PDFViewerViewModel, _ url: URL) async throws -> CGImage {
        vm.saveDocument()
        let renderer = PDFRenderActor()
        try await renderer.openDocument(filePath: url.path)
        await renderer.setLayerStates(try #require(vm.document).layerStates())
        return try await renderer.renderPage(pageIndex: 0, scale: 1).image
    }

    @Test func everyLayerCanHoldAnnotations() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let order = "/Order [ [ (Architectural) \(layerRef(0)) ] \(layerRef(1)) \(layerRef(2)) ]"
        let (vm, _) = try await open(config: order, in: dir)
        #expect(vm.annotationLayers.map(\.name) == threeLayers)
        #expect(vm.layers.first?.objectNumber == nil)
        #expect(Set(vm.annotationLayers.compactMap(\.objectNumber)) == [6, 7, 8])
    }

    @Test func newAnnotationsGoOnTheChosenLayer() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await open(in: dir)
        let pipes = try layer(vm, "Pipes")
        let doc = try #require(vm.document)

        let onNone = try #require(rectangle(vm))
        #expect(onNone.layerObjectNumber == nil)

        vm.setAnnotationLayer(pipes.objectNumber)
        let onPipes = try #require(rectangle(vm))
        #expect(onPipes.layerObjectNumber == pipes.objectNumber)
        #expect(doc.annotationLayer(pageIndex: 0, objectNumber: try #require(onPipes.documentObjectNumber)) == pipes.objectNumber)
        #expect(vm.annotationThreads().contains { $0.root.layerObjectNumber == pipes.objectNumber })

        // Saved, it's on the layer for other readers too.
        vm.saveDocument()
        let reopened = try PDFDocumentCore(filePath: url.path)
        #expect(reopened.annotationThreads(pageIndex: 0).compactMap(\.root.layerObjectNumber) == [try #require(pipes.objectNumber)])
    }

    @Test func choosingAHiddenLayerShowsIt() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await open(in: dir)
        vm.toggleLayer(try layer(vm, "Wiring"))
        #expect(try !layer(vm, "Wiring").isVisible)
        vm.setAnnotationLayer(try layer(vm, "Wiring").objectNumber)
        #expect(try layer(vm, "Wiring").isVisible)
    }

    @Test func hidingALayerHidesItsAnnotations() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await open(in: dir)
        vm.setAnnotationLayer(try layer(vm, "Walls").objectNumber)
        let annot = try #require(rectangle(vm))
        let edge = CGPoint(x: 300, y: 350)
        #expect(vm.shownAnnotations(onPage: 0).contains { $0.id == annot.id })
        #expect(vm.annotationThread(pageIndex: 0, at: edge) != nil)
        #expect(hasInk(near: edge, in: try await renderSaved(vm, url)))

        vm.toggleLayer(try layer(vm, "Walls"))
        #expect(vm.shownAnnotations(onPage: 0).isEmpty)
        #expect(vm.annotationThread(pageIndex: 0, at: edge) == nil)
        #expect(vm.document?.annotationObjectNumber(pageIndex: 0, at: edge) == nil)
        let thread = try #require(vm.annotationThreads().first)
        #expect(vm.isOnHiddenLayer(thread.root))
        #expect(!hasInk(near: edge, in: try await renderSaved(vm, url)))
    }

    @Test func undoPutsAnAnnotationBackOnItsLayer() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await open(in: dir)
        let pipes = try #require(try layer(vm, "Pipes").objectNumber)
        vm.setAnnotationLayer(pipes)
        var added: PDFEngine.PDFAnnotation?
        step(vm) { added = rectangle(vm) }
        let made = try #require(added)
        // Where new ones go has changed since; Undo puts it back where it was.
        vm.setAnnotationLayer(nil)
        step(vm) { vm.removeAnnotation(made) }
        vm.undoManager.undo()
        let back = try #require(vm.pageAnnotations[0]?.first)
        #expect(back.layerObjectNumber == pipes)
        #expect(vm.document?.annotationLayer(pageIndex: 0, objectNumber: try #require(back.documentObjectNumber)) == pipes)

        // From the file, erased: the copy kept for Undo keeps the layer, not a copy of it.
        vm.saveDocument()
        let fresh = PDFViewerViewModel()
        await fresh.loadDocument(from: url.path)
        fresh.undoManager.groupsByEvent = false
        let number = try #require(fresh.annotationThreads().first?.root.objectNumber)
        step(fresh) { fresh.deleteFileAnnotation(pageIndex: 0, objectNumber: number) }
        #expect(fresh.annotationThreads().isEmpty)
        fresh.undoManager.undo()
        let restored = try #require(fresh.annotationThreads().first)
        #expect(restored.root.layerObjectNumber == pipes)
        #expect(fresh.document?.layers().count == 3)
        fresh.toggleLayer(try layer(fresh, "Pipes"))
        #expect(fresh.isOnHiddenLayer(try #require(fresh.annotationThreads().first).root))
    }

    @Test func anEditKeepsTheAnnotationOnItsLayer() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await open(in: dir)
        let walls = try #require(try layer(vm, "Walls").objectNumber)
        vm.setAnnotationLayer(walls)
        let made = try #require(rectangle(vm))
        vm.setAnnotationLayer(try layer(vm, "Wiring").objectNumber)
        var restyled: PDFEngine.PDFAnnotation?
        step(vm) {
            vm.beginReplacingAnnotation(made)
            restyled = vm.addRestyledShape(made, strokeWidth: 6)
            vm.finishReplacingAnnotation()
        }
        #expect(try #require(restyled).layerObjectNumber == walls)
    }

    @Test func annotationsMoveBetweenLayersWithUndo() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await open(in: dir)
        let made = try #require(rectangle(vm))
        let number = try #require(made.documentObjectNumber)
        let wiring = try #require(try layer(vm, "Wiring").objectNumber)

        step(vm) { vm.moveAnnotation(made, toLayer: wiring) }
        #expect(vm.document?.annotationLayer(pageIndex: 0, objectNumber: number) == wiring)
        #expect(vm.pageAnnotations[0]?.first?.layerObjectNumber == wiring)
        vm.undoManager.undo()
        #expect(vm.document?.annotationLayer(pageIndex: 0, objectNumber: number) == nil)
        #expect(vm.pageAnnotations[0]?.first?.layerObjectNumber == nil)
        vm.undoManager.redo()
        #expect(vm.document?.annotationLayer(pageIndex: 0, objectNumber: number) == wiring)
    }

    @Test func aNewLayerKeepsTheOthersAsTheyAreShown() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let order = "/Order [\(layerRef(0)) \(layerRef(1)) \(layerRef(2))] /OFF [\(layerRef(2))]"
        let (vm, url) = try await open(config: order, in: dir)
        vm.toggleLayer(try layer(vm, "Walls"))
        #expect(vm.layers.map(\.isVisible) == [false, true, false])

        var added: Int?
        step(vm) { added = vm.addLayer(named: "My Markups") }
        let number = try #require(added)
        #expect(vm.layers.map(\.name) == threeLayers + ["My Markups"])
        #expect(vm.layers.map(\.isVisible) == [false, true, false, true])
        #expect(vm.annotationLayer == number)
        #expect(vm.isDocumentEdited)
        #expect(!(vm.document.map(text(of:)) ?? "").contains("WALLS"))

        // Annotations go on it, and it's saved with them.
        let made = try #require(rectangle(vm))
        #expect(made.layerObjectNumber == number)
        vm.saveDocument()
        let reopened = try PDFDocumentCore(filePath: url.path)
        #expect(reopened.layers().map(\.name) == threeLayers + ["My Markups"])
        #expect(reopened.layers().map(\.isVisible) == [true, true, false, true])
    }

    @Test func aNewLayerInADocumentWithoutAnOrderIsListed() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await open(in: dir)
        step(vm) { vm.addLayer(named: "Markups") }
        #expect(vm.layers.map(\.name) == threeLayers + ["Markups"])
        // The renderer opens the changed file again and follows its layers.
        #expect(await vm.reopenActors(at: try #require(vm.workingCopyPath)))
        vm.toggleLayer(try layer(vm, "Walls"))
        // The renderer is told in a task of its own.
        var image = try await vm.renderActor.renderPage(pageIndex: 0, scale: 1).image
        for _ in 0..<200 where showsSquare(0, in: image) {
            try await Task.sleep(nanoseconds: 10_000_000)
            image = try await vm.renderActor.renderPage(pageIndex: 0, scale: 1).image
        }
        #expect(!showsSquare(0, in: image))
        #expect(showsSquare(1, in: image))
        #expect(showsSquare(2, in: image))
    }

    @Test func theTakeoffLeavesOutHiddenMeasurements() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await open(in: dir)
        vm.setAnnotationLayer(try layer(vm, "Pipes").objectNumber)
        step(vm) { _ = vm.addMeasurementAnnotation(pageIndex: 0, type: .measureLength, points: [CGPoint(x: 100, y: 500), CGPoint(x: 300, y: 500)], value: 200, formattedText: "200 pt") }
        vm.setAnnotationLayer(nil)
        step(vm) { _ = vm.addMeasurementAnnotation(pageIndex: 0, type: .measureLength, points: [CGPoint(x: 100, y: 550), CGPoint(x: 200, y: 550)], value: 100, formattedText: "100 pt") }
        #expect(vm.takeoffEntries().count == 2)
        #expect(vm.generateTakeoffSummaryCSV().hasPrefix("Page,Index,Type,Color,Measurement,Value,Unit,Scale,Layer\n"))
        #expect(vm.generateTakeoffSummaryCSV().contains("\"Pipes\""))

        vm.toggleLayer(try layer(vm, "Pipes"))
        let entries = vm.takeoffEntries()
        #expect(entries.count == 1)
        #expect(entries.first?.annotation.layerObjectNumber == nil)
    }
}

/// Edit > New Layer, Rename Layer and Delete Layer.
@MainActor
@Suite(.serialized)
struct LayerEditingTests {
    private func open(layers: [String], in dir: URL) async throws -> (PDFViewerViewModel, URL) {
        let url = dir.appendingPathComponent("\(UUID().uuidString).pdf")
        try makeLayeredPDF(at: url, layers: layers)
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        vm.undoManager.groupsByEvent = false
        return (vm, url)
    }

    private func step(_ vm: PDFViewerViewModel, _ body: () -> Void) {
        vm.undoManager.beginUndoGrouping()
        body()
        vm.undoManager.endUndoGrouping()
    }

    private func rectangle(_ vm: PDFViewerViewModel, at y: CGFloat = 300) -> PDFEngine.PDFAnnotation? {
        var made: PDFEngine.PDFAnnotation?
        step(vm) { made = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 300, y: y), to: CGPoint(x: 400, y: y + 50)) }
        return made
    }

    @Test func aPlainPDFGetsItsFirstLayer() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await open(layers: [], in: dir)
        #expect(vm.layers.isEmpty)

        var added: Int?
        step(vm) { added = vm.addLayer(named: "Markups") }
        let number = try #require(added)
        #expect(vm.layers.map(\.name) == ["Markups"])
        #expect(vm.layers.first?.isVisible == true)
        #expect(vm.annotationLayer == number)
        let made = try #require(rectangle(vm))
        #expect(made.layerObjectNumber == number)

        vm.saveDocument()
        let reopened = try PDFDocumentCore(filePath: url.path)
        #expect(reopened.layers().map(\.name) == ["Markups"])
        #expect(reopened.annotationThreads(pageIndex: 0).first?.root.layerObjectNumber == number)
    }

    @Test func undoTakesANewLayerOutAgain() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await open(layers: [], in: dir)
        var added: Int?
        step(vm) { added = vm.addLayer(named: "Markups") }
        vm.undoManager.undo()
        #expect(vm.layers.isEmpty)
        #expect(vm.annotationLayer == nil)
        #expect(vm.document?.layers().isEmpty == true)
        vm.undoManager.redo()
        #expect(vm.layers.map(\.name) == ["Markups"])
        #expect(vm.layers.first?.objectNumber == added)
    }

    @Test func layersCanBeRenamedWithUndo() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await open(layers: threeLayers, in: dir)
        let pipes = try #require(vm.layers.first { $0.name == "Pipes" })
        vm.toggleLayer(pipes)
        let number = try #require(pipes.objectNumber)

        step(vm) { vm.renameLayer(objectNumber: number, to: "Plumbing") }
        #expect(vm.layers.map(\.name) == ["Walls", "Plumbing", "Wiring"])
        // Renaming doesn't show it again.
        #expect(vm.layers.map(\.isVisible) == [true, false, true])
        #expect(vm.isDocumentEdited)
        vm.undoManager.undo()
        #expect(vm.layers.map(\.name) == threeLayers)
        vm.undoManager.redo()
        vm.saveDocument()
        #expect(try PDFDocumentCore(filePath: url.path).layers().map(\.name) == ["Walls", "Plumbing", "Wiring"])
    }

    @Test func onlyLayersHoldingJustAnnotationsCanBeDeleted() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await open(layers: threeLayers, in: dir)
        #expect(vm.deletableLayers().isEmpty)
        let walls = try #require(vm.layers.first?.objectNumber)
        var deleted = true
        step(vm) { deleted = vm.deleteLayer(objectNumber: walls) }
        #expect(!deleted)
        #expect(vm.layers.count == 3)

        var added: Int?
        step(vm) { added = vm.addLayer(named: "Markups") }
        let mine = try #require(added)
        // An annotation on a drawing's layer doesn't make it deletable.
        vm.setAnnotationLayer(walls)
        _ = rectangle(vm)
        vm.setAnnotationLayer(mine)
        _ = rectangle(vm, at: 400)
        #expect(vm.deletableLayers().compactMap(\.objectNumber) == [mine])
    }

    @Test func deletingALayerKeepsItsAnnotationsOnNone() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await open(layers: threeLayers, in: dir)
        var added: Int?
        step(vm) { added = vm.addLayer(named: "Markups") }
        let mine = try #require(added)
        let made = try #require(rectangle(vm))
        let objectNumber = try #require(made.documentObjectNumber)
        // Hidden, so its annotations show again once it's gone.
        vm.toggleLayer(try #require(vm.layers.first { $0.objectNumber == mine }))
        #expect(vm.shownAnnotations(onPage: 0).isEmpty)

        var deleted = false
        step(vm) { deleted = vm.deleteLayer(objectNumber: mine) }
        #expect(deleted)
        #expect(vm.layers.map(\.name) == threeLayers)
        #expect(vm.annotationLayer == nil)
        #expect(vm.document?.annotationLayer(pageIndex: 0, objectNumber: objectNumber) == nil)
        #expect(vm.shownAnnotations(onPage: 0).count == 1)

        // Saving drops nothing Undo needs.
        vm.saveDocument()
        #expect(try PDFDocumentCore(filePath: url.path).layers().map(\.name) == threeLayers)
        vm.undoManager.undo()
        #expect(vm.layers.map(\.name) == threeLayers + ["Markups"])
        #expect(vm.document?.annotationLayer(pageIndex: 0, objectNumber: objectNumber) == mine)
        #expect(vm.pageAnnotations[0]?.first?.layerObjectNumber == mine)
        vm.undoManager.redo()
        #expect(vm.layers.map(\.name) == threeLayers)
        #expect(vm.document?.annotationLayer(pageIndex: 0, objectNumber: objectNumber) == nil)
    }

    @Test func deletingTheLastLayerLeavesADocumentWithout() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await open(layers: [], in: dir)
        var added: Int?
        step(vm) { added = vm.addLayer(named: "Markups") }
        let mine = try #require(added)
        var deleted = false
        step(vm) { deleted = vm.deleteLayer(objectNumber: mine) }
        #expect(deleted)
        #expect(vm.layers.isEmpty)
        vm.saveDocument()
        #expect(try PDFDocumentCore(filePath: url.path).layers().isEmpty)
        #expect(try PDFDocumentCore(filePath: url.path).layerStates().isEmpty)
    }
}

/// /Configs for `makeLayeredPDF` with `threeLayers`: "Plot" shows only Walls and lists Walls and
/// Wiring; "Electrical" hides Walls and lists them as the default does.
private let plotAndElectrical = """
    /Configs [ << /Name (Plot) /BaseState /OFF /ON [\(layerRef(0))] /Order [\(layerRef(0)) \(layerRef(2))] >> \
    << /Name (Electrical) /OFF [\(layerRef(0))] >> ]
    """

@Suite(.serialized)
struct LayerConfigurationTests {
    private func open(config: String = "", properties: String = plotAndElectrical, drawing: LayerDrawing = .onThePage,
                      in dir: URL) throws -> (PDFDocumentCore, URL) {
        let url = dir.appendingPathComponent("\(UUID().uuidString).pdf")
        try makeLayeredPDF(at: url, layers: threeLayers, config: config, properties: properties, drawing: drawing)
        return (try PDFDocumentCore(filePath: url.path), url)
    }

    private func render(_ url: URL, _ states: PDFLayerStates? = nil) async throws -> CGImage {
        let renderer = PDFRenderActor()
        try await renderer.openDocument(filePath: url.path)
        if let states { await renderer.setLayerStates(states) }
        return try await renderer.renderPage(pageIndex: 0, scale: 1).image
    }

    @Test func aDocumentWithoutAlternativesOffersNone() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(properties: "", in: dir)
        #expect(doc.layerConfigurations().isEmpty)
    }

    @Test func listsTheConfigurationsAndShowsLayersAsEachSays() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(in: dir)
        #expect(doc.layerConfigurations().map(\.displayName) == ["Default", "Plot", "Electrical"])
        #expect(doc.layerConfigurations().map(\.id) == [-1, 0, 1])

        try doc.chooseLayerConfiguration(0)
        #expect(doc.layerConfiguration == 0)
        // Listed as it orders them.
        #expect(doc.layers().map(\.name) == ["Walls", "Wiring"])
        #expect(doc.layers().map(\.isVisible) == [true, false])
        #expect(text(of: doc).contains("WALLS"))
        #expect(!text(of: doc).contains("PIPES"))
        #expect(!text(of: doc).contains("WIRING"))

        // Without an order of its own, as the default lists them.
        try doc.chooseLayerConfiguration(1)
        #expect(doc.layers().map(\.name) == threeLayers)
        #expect(doc.layers().map(\.isVisible) == [false, true, true])

        try doc.chooseLayerConfiguration(-1)
        #expect(doc.layers().map(\.isVisible) == [true, true, true])
        #expect(throws: (any Error).self) { try doc.chooseLayerConfiguration(2) }
    }

    @Test func otherCopiesFollowTheConfigurationChosen() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, url) = try open(in: dir)
        try doc.chooseLayerConfiguration(0)
        let image = try await render(url, doc.layerStates())
        #expect(showsSquare(0, in: image))
        #expect(!showsSquare(1, in: image))
        #expect(!showsSquare(2, in: image))

        let search = PDFSearchActor(workerCount: 2)
        try await search.openDocument(filePath: url.path)
        await search.setLayerStates(doc.layerStates())
        var found: [String] = []
        for await result in await search.searchStream(query: "WIRING") { found.append(result.matchedText) }
        #expect(found.isEmpty)
    }

    @Test func aNewLayerKeepsTheConfigurationChosen() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(in: dir)
        try doc.chooseLayerConfiguration(0)
        _ = try doc.addLayer(named: "Markups")
        #expect(doc.layerConfiguration == 0)
        #expect(doc.layers().map(\.name) == ["Walls", "Wiring", "Markups"])
        #expect(doc.layers().map(\.isVisible) == [true, false, true])
    }

    @Test func tellsWhetherLayersAreShownAsTheFileSays() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(config: "/OFF [\(layerRef(1))]", in: dir)
        #expect(doc.layersAreShownAsTheFileSays())
        try doc.toggleLayer(id: 1)
        #expect(!doc.layersAreShownAsTheFileSays())
        try doc.toggleLayer(id: 1)
        #expect(doc.layersAreShownAsTheFileSays())
        try doc.chooseLayerConfiguration(1)
        #expect(!doc.layersAreShownAsTheFileSays())
    }

    // MARK: - Flattened PDF

    @Test(arguments: [LayerDrawing.onThePage, .formInsideMarkedContent, .markedContentInsideForm])
    func flatteningLeavesOutHiddenLayers(drawing: LayerDrawing) async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(drawing: drawing, in: dir)
        try doc.toggleLayer(id: try #require(doc.layers().first { $0.name == "Pipes" }).id)
        let flat = dir.appendingPathComponent("flat.pdf")
        try doc.saveFlattened(to: flat.path)

        let flattened = try PDFDocumentCore(filePath: flat.path)
        #expect(flattened.layers().map(\.name) == ["Walls", "Wiring"])
        #expect(flattened.layers().allSatisfy { $0.isVisible })
        #expect(flattened.layerConfigurations().isEmpty)
        let flatText = text(of: flattened)
        #expect(!flatText.contains("PIPES"))
        #expect(flatText.contains("WALLS"))
        #expect(flatText.contains("WIRING"))
        #expect(flatText.contains("Always shown"))
        let image = try await render(flat)
        #expect(showsSquare(0, in: image))
        #expect(!showsSquare(1, in: image))
        #expect(showsSquare(2, in: image))
        // The layers left still show and hide what's on them.
        try flattened.toggleLayer(id: try #require(flattened.layers().first { $0.name == "Walls" }).id)
        #expect(!text(of: flattened).contains("WALLS"))
    }

    @Test func flatteningWithEveryLayerShownKeepsThemAll() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(in: dir)
        let flat = dir.appendingPathComponent("flat.pdf")
        try doc.saveFlattened(to: flat.path)
        let flattened = try PDFDocumentCore(filePath: flat.path)
        #expect(flattened.layers().map(\.name) == threeLayers)
        #expect(flattened.layerConfigurations().count == 3)
    }

    @Test func flatteningFollowsTheConfigurationChosen() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, _) = try open(in: dir)
        try doc.chooseLayerConfiguration(0)
        let flat = dir.appendingPathComponent("flat.pdf")
        try doc.saveFlattened(to: flat.path)
        let flattened = try PDFDocumentCore(filePath: flat.path)
        #expect(flattened.layers().map(\.name) == ["Walls"])
        #expect(text(of: flattened).contains("WALLS"))
        #expect(!text(of: flattened).contains("WIRING"))
    }

    // MARK: - Agent

    @Test func theAgentsIndexLeavesOutHiddenLayers() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (doc, url) = try open(in: dir)
        try doc.chooseLayerConfiguration(0)
        let builder = SemanticIndexBuilder()
        try await builder.openDocument(filePath: url.path, layerStates: doc.layerStates())
        var pages: [String] = []
        for await (_, text) in await builder.extractPageTexts() { pages.append(text) }
        let indexed = pages.joined(separator: "\n")
        #expect(indexed.contains("WALLS"))
        #expect(!indexed.contains("PIPES"))
        #expect(!indexed.contains("WIRING"))
    }
}

@MainActor
@Suite(.serialized)
struct LayerConfigurationViewerTests {
    @Test func theLayersTabTellsWhenLayersHaveChangedSinceAConfigurationWasChosen() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("layered.pdf")
        try makeLayeredPDF(at: url, layers: threeLayers, properties: plotAndElectrical)
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        #expect(vm.layerConfigurations.map(\.displayName) == ["Default", "Plot", "Electrical"])
        #expect(vm.chosenLayerConfiguration?.isDefault == true)

        let plot = vm.layerConfigurations[1]
        vm.chooseLayerConfiguration(plot)
        #expect(vm.layerConfiguration == 0)
        #expect(vm.layers.map(\.name) == ["Walls", "Wiring"])
        #expect(!vm.isLayerConfigurationChanged)
        #expect(!vm.isDocumentEdited)

        vm.toggleLayer(vm.layers[1])
        #expect(vm.isLayerConfigurationChanged)
        vm.toggleLayer(vm.layers[1])
        #expect(!vm.isLayerConfigurationChanged)

        vm.toggleLayer(vm.layers[0])
        #expect(vm.isLayerConfigurationChanged)
        // Choosing it again puts the layers back.
        vm.chooseLayerConfiguration(plot)
        #expect(!vm.isLayerConfigurationChanged)
        #expect(vm.layers.map(\.isVisible) == [true, false])

        // The renderer follows, in a task of its own.
        var image = try await vm.renderActor.renderPage(pageIndex: 0, scale: 1).image
        for _ in 0..<200 where showsSquare(1, in: image) {
            try await Task.sleep(nanoseconds: 10_000_000)
            image = try await vm.renderActor.renderPage(pageIndex: 0, scale: 1).image
        }
        #expect(showsSquare(0, in: image))
        #expect(!showsSquare(1, in: image))
    }

    @Test func flatteningLeavesOutAnnotationsOnHiddenLayersAndKeepsTheRestOnTheirs() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("layered.pdf")
        try makeLayeredPDF(at: url, layers: threeLayers)
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        let walls = try #require(vm.layers.first { $0.name == "Walls" })
        let pipes = try #require(vm.layers.first { $0.name == "Pipes" })
        vm.setAnnotationLayer(walls.objectNumber)
        _ = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 300, y: 300), to: CGPoint(x: 400, y: 400))
        vm.setAnnotationLayer(pipes.objectNumber)
        _ = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 300, y: 450), to: CGPoint(x: 400, y: 550))
        vm.toggleLayer(try #require(vm.layers.first { $0.name == "Pipes" }))

        let flat = dir.appendingPathComponent("flat.pdf")
        try #require(vm.document).saveFlattened(to: flat.path)
        let flattened = try PDFDocumentCore(filePath: flat.path)
        #expect(flattened.annotationThreads(pageIndex: 0).isEmpty)

        let wallsEdge = CGPoint(x: 300, y: 350), pipesEdge = CGPoint(x: 300, y: 500)
        let renderer = PDFRenderActor()
        try await renderer.openDocument(filePath: flat.path)
        let image = try await renderer.renderPage(pageIndex: 0, scale: 1).image
        #expect(hasInk(near: wallsEdge, in: image))
        #expect(!hasInk(near: pipesEdge, in: image))

        // Baked into the page, the rectangle is still on Walls.
        try flattened.toggleLayer(id: try #require(flattened.layers().first { $0.name == "Walls" }).id)
        await renderer.setLayerStates(flattened.layerStates())
        #expect(!hasInk(near: wallsEdge, in: try await renderer.renderPage(pageIndex: 0, scale: 1).image))
    }
}
