import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import PDFEngine

/// Text selection, reading OCR results rather than a page's own text.
struct OCRSelectionTests {
    private let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)

    /// A line starting at (`x`, `y`) with each word `wordWidth` wide and a 10pt space between
    /// them, tilted by `angle` about the point (0, 0).
    private func line(_ text: String, x: CGFloat, y: CGFloat, wordWidth: CGFloat = 50, angle: CGFloat = 0) -> PDFOCRLine {
        let tilt = CGAffineTransform(rotationAngle: angle)
        let words = text.split(separator: " ")
        let wordQuads = words.indices.map { i in
            PDFQuad(rect: CGRect(x: x + CGFloat(i) * (wordWidth + 10), y: y, width: wordWidth, height: 12)).applying(tilt)
        }
        let width = CGFloat(words.count) * (wordWidth + 10) - 10
        return PDFOCRLine(text: text, confidence: 1,
                          quad: PDFQuad(rect: CGRect(x: x, y: y, width: width, height: 12)).applying(tilt),
                          wordQuads: wordQuads)
    }

    private func page(_ lines: [PDFOCRLine]) -> StructuredPage {
        PDFOCRPageResult(pageIndex: 0, lines: lines, fullText: lines.map(\.text).joined(separator: "\n"))
            .structuredPage(bounds: bounds)
    }

    @Test func selectionEndsOnVisionsWordEdges() throws {
        // Equal letters would put a proportional estimate of "bb"'s edges far from Vision's.
        let line = PDFOCRLine(
            text: "aaaaaaaaaaaa bb cc", confidence: 1,
            quad: PDFQuad(rect: CGRect(x: 100, y: 100, width: 300, height: 12)),
            wordQuads: [
                PDFQuad(rect: CGRect(x: 100, y: 100, width: 60, height: 12)),
                PDFQuad(rect: CGRect(x: 170, y: 100, width: 120, height: 12)),
                PDFQuad(rect: CGRect(x: 300, y: 100, width: 100, height: 12))
            ])
        let result = try #require(SpatialTextSelector().selectWord(at: CGPoint(x: 230, y: 106), on: page([line])))
        #expect(result.text == "bb")
        #expect(result.boundingRect == CGRect(x: 170, y: 100, width: 120, height: 12))
    }

    @Test func linesWithoutWordOutlinesAreSpreadEvenly() throws {
        let line = PDFOCRLine(text: "ab cd", confidence: 1, boundingBox: CGRect(x: 100, y: 100, width: 100, height: 12))
        let result = try #require(SpatialTextSelector().selectWord(at: CGPoint(x: 185, y: 106), on: page([line])))
        #expect(result.text == "cd")
        #expect(abs(result.boundingRect.minX - 160) < 0.001 && abs(result.boundingRect.maxX - 200) < 0.001)
    }

    @Test func dragsCopyWholeLinesOfRecognizedText() {
        let scan = page([line("first line here", x: 72, y: 100), line("second line here", x: 72, y: 116)])
        let result = SpatialTextSelector().selectText(on: scan, from: CGPoint(x: 72, y: 106), to: CGPoint(x: 300, y: 122))
        #expect(result.text == "first line here second line here")
        #expect(result.highlightQuads.count == 2)
    }

    @Test func selectionsKeepToAColumnOfRecognizedText() {
        var lines = [line("A heading across both columns of text", x: 72, y: 60)]
        for row in 0..<4 {
            let y = CGFloat(100 + row * 16)
            lines.append(line("left \(row) body text", x: 72, y: y))
            lines.append(line("right \(row) body text", x: 340, y: y))
        }
        let result = SpatialTextSelector().selectText(on: page(lines), from: CGPoint(x: 72, y: 106), to: CGPoint(x: 300, y: 138))
        #expect(result.text.contains("left 0") && result.text.contains("left 2"))
        #expect(!result.text.contains("right"))
    }

    /// At 3°, a line 400pt long rises 21pt, so its upright box covers the lines around it.
    @Test func skewedScansSelectTheLineUnderTheMouse() throws {
        let angle: CGFloat = 3 * .pi / 180
        let lines = (0..<8).map { line("row\($0) alpha beta gamma delta epsilon zeta", x: 72, y: 200 + CGFloat($0) * 16, angle: angle) }
        let scan = page(lines)
        let selector = SpatialTextSelector()

        // Far along row 3, where an upright reading of the boxes would find another line.
        let top = lines[3].wordQuads[5].slice(from: 0.5, to: 0.5)
        let point = CGPoint(x: (top.ul.x + top.ll.x) / 2, y: (top.ul.y + top.ll.y) / 2)
        let word = try #require(selector.selectWord(at: point, on: scan))
        #expect(word.text == "epsilon")
        let wholeLine = try #require(selector.selectLine(at: point, on: scan))
        #expect(wholeLine.text.hasPrefix("row3"))

        // The highlight lies along the text, in page coordinates.
        let quad = wholeLine.highlightQuads[0]
        #expect(!quad.isAxisAligned())
        #expect(abs(atan2(quad.ur.y - quad.ul.y, quad.ur.x - quad.ul.x) - angle) < 0.001)
        #expect(hypot(quad.ul.x - lines[3].quad.ul.x, quad.ul.y - lines[3].quad.ul.y) < 0.5)

        let drag = selector.selectText(on: scan, from: lines[2].quad.ul, to: lines[4].quad.lr)
        #expect(drag.text.hasPrefix("row2") && drag.text.contains("row3") && drag.text.contains("row4"))
        #expect(!drag.text.contains("row1") && !drag.text.contains("row5"))

        let all = scan.fullSelectionPoints
        let everything = selector.selectText(on: scan, from: all.start, to: all.end)
        #expect(everything.text.hasPrefix("row0") && everything.text.contains("row7"))
    }

    /// A marquee is drawn upright on the page, however the text beneath it runs.
    @Test func areaSelectionOnASkewedScanStaysAPageRectangle() {
        let angle: CGFloat = 3 * .pi / 180
        let lines = (0..<4).map { line("row\($0) alpha beta gamma", x: 72, y: 200 + CGFloat($0) * 30, angle: angle) }
        let target = lines[1].quad.boundingRect.insetBy(dx: -2, dy: -2)
        let result = SpatialTextSelector().selectText(
            on: page(lines), from: CGPoint(x: target.minX, y: target.minY), to: CGPoint(x: target.maxX, y: target.maxY), mode: .rectangularArea
        )
        #expect(result.boundingRect == target)
        #expect(result.highlightQuads == [PDFQuad(rect: target)])
        #expect(result.text.hasPrefix("row1") && !result.text.contains("row0") && !result.text.contains("row2"))
    }

    @Test func aSidewaysLabelDoesNotTiltThePage() {
        let label = PDFOCRLine(text: "SIDEWAYS", confidence: 1, quad: PDFQuad(
            ul: CGPoint(x: 500, y: 300), ur: CGPoint(x: 500, y: 200), ll: CGPoint(x: 512, y: 300), lr: CGPoint(x: 512, y: 200)))
        let scan = page([line("level text one", x: 72, y: 100), line("level text two", x: 72, y: 120), label])
        #expect(scan.pageTransform.isIdentity)
    }

    // MARK: - Word outlines from Vision

    @Test func visionPlacesEachWord() async throws {
        let size = CGSize(width: 1200, height: 200)
        let context = try #require(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let text = NSAttributedString(string: "hello there wonderful world", attributes: [
            .font: NSFont.systemFont(ofSize: 60), .foregroundColor: NSColor.black])
        context.textPosition = CGPoint(x: 40, y: 80)
        CTLineDraw(CTLineCreateWithAttributedString(text), context)

        let result = try await PDFOCREngine().recognizeText(
            in: try #require(context.makeImage()), pageIndex: 0, pageBounds: CGRect(origin: .zero, size: size))
        let line = try #require(result.lines.first)
        #expect(line.text.split(separator: " ").count == 4)
        #expect(line.wordQuads.count == 4)
        for (a, b) in zip(line.wordQuads, line.wordQuads.dropFirst()) {
            #expect(a.boundingRect.maxX <= b.boundingRect.minX)
        }
    }

    /// A real recognition of a skewed page, from image to selection.
    @Test func recognizedSkewedTextSelectsAlongTheSlant() async throws {
        let size = CGSize(width: 1800, height: 1200)
        let context = try #require(CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        context.rotate(by: 3 * .pi / 180)
        let rows = ["alpha bravo charlie delta echo foxtrot golf hotel", "india juliet kilo lima mike november oscar papa",
                    "quebec romeo sierra tango uniform victor whiskey", "xray yankee zulu ablaze bonfire cobbler dolphin"]
        for (i, row) in rows.enumerated() {
            let text = NSAttributedString(string: row, attributes: [.font: NSFont.systemFont(ofSize: 60), .foregroundColor: NSColor.black])
            context.textPosition = CGPoint(x: 80, y: 850 - CGFloat(i) * 110)
            CTLineDraw(CTLineCreateWithAttributedString(text), context)
        }

        let pageRect = CGRect(origin: .zero, size: size)
        let result = try await PDFOCREngine().recognizeText(in: try #require(context.makeImage()), pageIndex: 0, pageBounds: pageRect)
        let lines = result.lines.sorted { $0.boundingBox.midY < $1.boundingBox.midY }
        try #require(lines.count == 4)
        let third = lines[2]
        let words = third.text.split(separator: " ").map(String.init)
        try #require(third.wordQuads.count == words.count)

        let scan = result.structuredPage(bounds: pageRect)
        #expect(!scan.pageTransform.isIdentity)
        let selector = SpatialTextSelector()
        let quad = third.wordQuads[words.count - 1]
        let middle = CGPoint(x: (quad.ul.x + quad.lr.x) / 2, y: (quad.ul.y + quad.lr.y) / 2)
        let word = try #require(selector.selectWord(at: middle, on: scan))
        #expect(word.text == words[words.count - 1])
        #expect(!word.highlightQuads[0].isAxisAligned())
        // The highlight stays on the word Vision placed.
        #expect(hypot(word.highlightQuads[0].ul.x - quad.ul.x, word.highlightQuads[0].ul.y - quad.ul.y) < 6)
        #expect(hypot(word.highlightQuads[0].lr.x - quad.lr.x, word.highlightQuads[0].lr.y - quad.lr.y) < 6)
    }

    // MARK: - In the viewer

    private func writeImageOnlyPDF(at url: URL) {
        let body = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >>\nendobj\n"
        FileManager.default.createFile(atPath: url.path, contents: ("%PDF-1.4\n" + body + "trailer\n<< /Root 1 0 R >>\n%%EOF\n").data(using: .utf8))
    }

    @MainActor
    @Test func redactingAPageForgetsItsRecognizedText() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-selection-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        writeImageOnlyPDF(at: url)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        vm.ocrResults[0] = PDFOCRPageResult(pageIndex: 0, lines: [line("private words here", x: 72, y: 100)], fullText: "private words here")

        vm.selectLine(at: CGPoint(x: 80, y: 106), pageIndex: 0)
        #expect(vm.activeSelection?.result.text == "private words here")

        vm.finalizeRedactionChanges(affectedPages: [0])
        #expect(vm.ocrResults[0] == nil)
        #expect(vm.activeSelection == nil)
        vm.selectLine(at: CGPoint(x: 80, y: 106), pageIndex: 0)
        #expect(vm.activeSelection == nil)
    }

    @MainActor
    @Test func pagesWithTheirOwnTextIgnoreOCR() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ocr-selection-\(UUID().uuidString).pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        writeOneLineTextPDF(at: url)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        vm.ocrResults[0] = PDFOCRPageResult(pageIndex: 0, lines: [line("recognized instead", x: 72, y: 60)], fullText: "recognized instead")
        vm.selectAllOnCurrentPage()
        #expect(vm.activeSelection?.result.text == "real text")
    }

    private func writeOneLineTextPDF(at url: URL) {
        let content = "BT /F1 24 Tf 72 700 Td (real text) Tj ET\n"
        let body = "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n4 0 obj\n<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream\nendobj\n5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n"
        FileManager.default.createFile(atPath: url.path, contents: ("%PDF-1.4\n" + body + "trailer\n<< /Root 1 0 R >>\n%%EOF\n").data(using: .utf8))
    }
}
