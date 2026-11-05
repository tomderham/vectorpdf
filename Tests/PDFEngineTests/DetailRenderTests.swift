import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import PDFEngine

/// RGBA bytes of `image`, or of the part of it inside `crop` (pixels, top-left origin).
private func rgba(_ image: CGImage, crop: CGRect? = nil) -> [UInt8] {
    let source = crop.flatMap { image.cropping(to: $0) } ?? image
    let w = source.width, h = source.height
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    bytes.withUnsafeMutableBytes { buf in
        let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return bytes
}

@Suite struct DetailRenderTests {
    @Test func detailMatchesTheSameRegionOfAWholePageRender() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("detail_\(UUID().uuidString).pdf")
        createSamplePDF(at: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let actor = PDFRenderActor()
        try await actor.openDocument(filePath: url.path)
        let scale: CGFloat = 2
        let whole = try await actor.renderPage(pageIndex: 0, scale: scale)
        #expect(!PDFRenderActor.clampsRender(scale: scale, pageBounds: whole.nativeBounds))

        // Off the pixel grid on purpose: the detail snaps out to it and reports what it covers.
        let detail = try await actor.renderPageDetail(pageIndex: 0, rect: CGRect(x: 40.2, y: 60.7, width: 300.3, height: 120.1), scale: scale)
        #expect(detail.rect == CGRect(x: 40, y: 60.5, width: 300.5, height: 120.5))
        #expect(detail.image.width == 601)
        #expect(detail.image.height == 241)

        let crop = CGRect(x: detail.rect.minX * scale, y: detail.rect.minY * scale, width: CGFloat(detail.image.width), height: CGFloat(detail.image.height))
        let expected = rgba(whole.image, crop: crop)
        let actual = rgba(detail.image)
        #expect(actual.count == expected.count)
        let maxDiff = zip(actual, expected).map { abs(Int($0) - Int($1)) }.max() ?? 0
        #expect(maxDiff <= 2)
        // Not a blank region, or the comparison proves nothing.
        #expect(Set(actual).count > 2)
    }

    @Test func largeSheetsAreCappedAndOrdinaryPagesAreNot() {
        let archE = CGRect(x: 0, y: 0, width: 2592, height: 3456)
        let letter = CGRect(x: 0, y: 0, width: 612, height: 792)
        #expect(PDFRenderActor.clampsRender(scale: 2, pageBounds: archE))
        #expect(!PDFRenderActor.clampsRender(scale: 2, pageBounds: letter))
        #expect(PDFRenderActor.clampsRender(scale: 8, pageBounds: letter))
    }

    @Test func detailRectCoversTheVisibleAreaPlusAMarginWithinThePage() throws {
        // A 1000 x 1000 pt page at zoom 4, framed at (100, 50), with part of it on screen.
        let pageFrame = NSRect(x: 100, y: 50, width: 4000, height: 4000)
        let pageBounds = CGRect(x: 0, y: 0, width: 1000, height: 1000)
        let geometry = PageGeometry(frame: pageFrame, pageBounds: pageBounds, zoom: 4, rotation: 0)
        let visible = NSRect(x: 1100, y: 1050, width: 800, height: 400)
        let rect = try #require(PDFCanvasView.detailRect(visible: visible, geometry: geometry, backingScale: 2))
        // 25% margin each side: 1100 - 200 = 900 → page x 200; 1050 - 100 = 950 → page y 225.
        #expect(rect == CGRect(x: 200, y: 225, width: 300, height: 150))

        // Near the page's corner the margin is cut off at its edge.
        let corner = NSRect(x: 0, y: 0, width: 800, height: 400)
        let clipped = try #require(PDFCanvasView.detailRect(visible: corner, geometry: geometry, backingScale: 2))
        #expect(clipped.minX == 0 && clipped.minY == 0)

        // Off the page: nothing.
        #expect(PDFCanvasView.detailRect(visible: NSRect(x: 0, y: 0, width: 50, height: 40), geometry: geometry, backingScale: 2) == nil)
    }

    @Test func detailMarginShrinksOnAHugeViewButTheVisibleAreaIsKept() throws {
        let geometry = PageGeometry(frame: NSRect(x: 0, y: 0, width: 40000, height: 40000), pageBounds: CGRect(x: 0, y: 0, width: 10000, height: 10000), zoom: 4, rotation: 0)
        // 3000 x 2000 pt at 2x is 24 Mpx, already over the cap: no margin at all.
        let visible = NSRect(x: 10000, y: 10000, width: 3000, height: 2000)
        let rect = try #require(PDFCanvasView.detailRect(visible: visible, geometry: geometry, backingScale: 2))
        #expect(rect == CGRect(x: 2500, y: 2500, width: 750, height: 500))
    }

    @Test func detailRectInARotatedViewIsThePartOfThePageOnScreen() throws {
        // A 1000 x 500 pt page at zoom 2, turned 90° clockwise: 1000 x 2000 on screen at (100, 50).
        let geometry = PageGeometry(frame: NSRect(x: 100, y: 50, width: 1000, height: 2000), pageBounds: CGRect(x: 0, y: 0, width: 1000, height: 500), zoom: 2, rotation: 90)
        // The top-left 200 x 100 of the page as it's shown; the margin around it is cut off at the page's edges.
        let visible = NSRect(x: 100, y: 50, width: 200, height: 100)
        let rect = try #require(PDFCanvasView.detailRect(visible: visible, geometry: geometry, backingScale: 2))
        // Turned clockwise, the screen's top-left is the page's bottom-left: page x 0…50, y 400…500.
        let core = CGRect(x: 0, y: 400, width: 50, height: 100)
        #expect(rect.insetBy(dx: -0.001, dy: -0.001).contains(core))
        #expect(rect.maxY <= 500.001 && rect.minX >= -0.001)
    }
}
