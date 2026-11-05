import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import PDFEngine

private func scratchDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("optimize-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func fileSize(_ url: URL) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int)
}

/// A page with a 1200 px colour image in a 2-inch box (600 dpi) and a line of text.
private func makeImagePDF(at url: URL) {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil)!
    let side = 1200
    var generator = SystemRandomNumberGenerator()
    var pixels = [UInt8](repeating: 255, count: side * side * 4)
    for i in stride(from: 0, to: pixels.count, by: 4) {
        // Noise, which compresses poorly losslessly, so the image dominates the file.
        pixels[i] = UInt8.random(in: 0...255, using: &generator)
        pixels[i + 1] = UInt8.random(in: 0...255, using: &generator)
        pixels[i + 2] = UInt8.random(in: 0...255, using: &generator)
    }
    let image = pixels.withUnsafeMutableBytes { buf -> CGImage in
        let bitmap = CGContext(data: buf.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        return bitmap.makeImage()!
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.beginPDFPage(nil)
    context.draw(image, in: CGRect(x: 72, y: 500, width: 144, height: 144))
    ("Optimized drawing notes" as NSString).draw(at: NSPoint(x: 72, y: 400), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
    context.endPDFPage()
    context.closePDF()
}

@Suite @MainActor struct OptimizeAndRevertTests {
    @Test func downsamplingImagesShrinksTheFileAndKeepsItsText() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("drawing.pdf")
        let output = dir.appendingPathComponent("drawing (Optimized).pdf")
        makeImagePDF(at: source)

        let doc = try PDFDocumentCore(filePath: source.path)
        try doc.saveOptimized(to: output.path, options: .init(imageDPI: 150))
        // 600 dpi down to 150 dpi is a sixteenth of the pixels.
        #expect(try fileSize(output) < fileSize(source) / 4)

        let optimized = try PDFDocumentCore(filePath: output.path)
        #expect(optimized.pageCount == 1)
        #expect(optimized.extractText(pageIndex: 0)?.contains("Optimized drawing notes") == true)
    }

    @Test func keepingImagesLeavesThemAtFullResolution() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("drawing.pdf")
        let output = dir.appendingPathComponent("out.pdf")
        makeImagePDF(at: source)

        try PDFDocumentCore(filePath: source.path).saveOptimized(to: output.path, options: .init())
        // Noise doesn't compress, so the full-resolution image keeps the file near its size.
        #expect(try fileSize(output) > fileSize(source) / 2)
    }

    @Test func outlinedTextLooksTheSameButIsNoLongerText() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appendingPathComponent("sample.pdf")
        let output = dir.appendingPathComponent("outlined.pdf")
        createSamplePDF(at: source)

        let doc = try PDFDocumentCore(filePath: source.path)
        #expect(doc.extractText(pageIndex: 0)?.contains("MuPDF Architecture") == true)
        try doc.saveOptimized(to: output.path, options: .init(outlineText: true))

        let outlined = try PDFDocumentCore(filePath: output.path)
        #expect(outlined.pageCount == 2)
        #expect(outlined.extractText(pageIndex: 0)?.contains("MuPDF") != true)

        // Still drawn: the title's area isn't blank.
        let actor = PDFRenderActor()
        try await actor.openDocument(filePath: output.path)
        let detail = try await actor.renderPageDetail(pageIndex: 0, rect: CGRect(x: 54, y: 50, width: 200, height: 24), scale: 1)
        let ctx = CGContext(data: nil, width: detail.image.width, height: detail.image.height, bitsPerComponent: 8, bytesPerRow: detail.image.width * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(detail.image, in: CGRect(x: 0, y: 0, width: detail.image.width, height: detail.image.height))
        let bytes = UnsafeBufferPointer(start: ctx.data!.assumingMemoryBound(to: UInt8.self), count: detail.image.width * detail.image.height * 4)
        #expect(bytes.contains { $0 < 128 })
    }

    @Test func optimizedCopyIncludesUnsavedEditsAndLeavesTheDocumentAlone() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("review.pdf")
        let output = dir.appendingPathComponent("review (Optimized).pdf")
        makeLabelledPDF(at: url, labels: ["Page0", "Page1"])
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let doc = try #require(vm.document)
        let shape = try #require(vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)))
        let number = try #require(shape.documentObjectNumber)
        #expect(vm.isDocumentEdited)

        try doc.saveOptimized(to: output.path, options: .init())

        let copy = try PDFDocumentCore(filePath: output.path)
        // Saving renumbers objects, so look for any annotation: the source file had none.
        #expect(copy.lastAnnotationObjectNumber(pageIndex: 0) != nil)
        // The open document is untouched and still has its unsaved edit.
        #expect(vm.isDocumentEdited)
        #expect(vm.document === doc)
        #expect(doc.describeAnnotation(pageIndex: 0, objectNumber: number) != nil)
    }

    @Test func revertToSavedDiscardsUnsavedChanges() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("review.pdf")
        makeLabelledPDF(at: url, labels: ["Page0", "Page1"])
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let shape = try #require(vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)))
        let number = try #require(shape.documentObjectNumber)
        #expect(vm.isDocumentEdited)
        #expect(vm.undoManager.canUndo)

        await vm.revertToSaved()

        #expect(!vm.isDocumentEdited)
        #expect(vm.pageAnnotations[0]?.isEmpty ?? true)
        #expect(vm.document?.describeAnnotation(pageIndex: 0, objectNumber: number) == nil)
        #expect(!vm.undoManager.canUndo)
        #expect(vm.document?.filePath == url.path)
    }

    @Test func revertDoesNothingWithoutChanges() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plain.pdf")
        makeLabelledPDF(at: url, labels: ["Page0"])
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        let doc = vm.document
        await vm.revertToSaved()
        #expect(vm.document === doc)
    }
}
