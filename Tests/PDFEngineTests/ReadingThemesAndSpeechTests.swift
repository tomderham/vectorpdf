import Testing
import Foundation
@testable import PDFEngine
import MuPDFBridge

@Suite("Reading Themes & Speech Tests")
struct ReadingThemesAndSpeechTests {
    @Test("PDFColorAppearance cases and display names")
    func testPDFColorAppearanceCases() {
        let cases = PDFColorAppearance.allCases
        #expect(cases.contains(.system))
        #expect(cases.contains(.light))
        #expect(cases.contains(.dark))
        #expect(cases.contains(.sepia))
        
        #expect(PDFColorAppearance.sepia.displayName == "Sepia")
        #expect(PDFColorAppearance.system.displayName == "Follow System")
        #expect(PDFColorAppearance.light.displayName == "Light")
        #expect(PDFColorAppearance.dark.displayName == "Dark")
    }

    @Test("PDFSpeechCoordinator toggle and stop")
    @MainActor
    func testSpeechCoordinator() {
        let coordinator = PDFSpeechCoordinator.shared
        #expect(!coordinator.isSpeaking)

        // Stopping when not speaking is safe no-op
        coordinator.stopSpeaking()
        #expect(!coordinator.isSpeaking)

        // Blank text speaking does not trigger speaking state
        coordinator.startSpeaking("   \n  ")
        #expect(!coordinator.isSpeaking)
    }

    @Test("InstalledBrowser discovery and preferences")
    @MainActor
    func testInstalledBrowsers() {
        let appCoordinator = PDFViewerAppCoordinator.shared
        let browsers = appCoordinator.installedBrowsers
        #expect(!browsers.isEmpty)
        #expect(browsers.first?.id == "system")
        #expect(browsers.first?.name == "System Default")

        // Preferred browser setting persistence
        appCoordinator.preferredBrowserBundleID = "com.apple.Safari"
        #expect(appCoordinator.preferredBrowserBundleID == "com.apple.Safari")

        // Reset to system default
        appCoordinator.preferredBrowserBundleID = "system"
        #expect(appCoordinator.preferredBrowserBundleID == "system")
    }

    @Test("Native Pixmap Dark Mode & Sepia Appearance transformation")
    func testNativePixmapAppearanceTransformation() {
        let ctx = PDFContextManager.shared.makeClonedContext()
        defer { PDFContextManager.shared.dropContext(ctx) }

        // Test 1: Dark Mode luminance inversion on a 2x2 white RGBA buffer
        var darkPixels: [UInt8] = [
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255
        ]
        let darkRet = mupdf_apply_color_appearance(ctx, &darkPixels, 2, 2, 8, 4, 1)
        #expect(darkRet == 0)
        // Inverted luminance turns pure white (255) dark (<= 10) while preserving alpha (255)
        #expect(darkPixels[0] <= 10)
        #expect(darkPixels[1] <= 10)
        #expect(darkPixels[2] <= 10)
        #expect(darkPixels[3] == 255)

        // Test 2: Sepia tinting on a 2x2 white RGBA buffer
        var sepiaPixels: [UInt8] = [
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255,
            255, 255, 255, 255
        ]
        let sepiaRet = mupdf_apply_color_appearance(ctx, &sepiaPixels, 2, 2, 8, 4, 2)
        #expect(sepiaRet == 0)
        // Sepia maps white to warm ivory parchment (#F6EED9: R~246, G~238, B~217)
        #expect(sepiaPixels[0] >= 240)
        #expect(sepiaPixels[1] >= 230)
        #expect(sepiaPixels[2] >= 210)
        #expect(sepiaPixels[3] == 255)
    }

    @Test("SVG page export to string and file")
    func testSVGPageExport() throws {
        let tempPDF = FileManager.default.temporaryDirectory.appendingPathComponent("svg_test_\(UUID().uuidString).pdf")
        createSamplePDF(at: tempPDF)
        defer { try? FileManager.default.removeItem(at: tempPDF) }

        let doc = try PDFDocumentCore(filePath: tempPDF.path)
        #expect(doc.pageCount == 2)

        // 1. Export page 0 to SVG string with vector paths (default textAsPath = true, preserves math/glyphs)
        let svgString = try doc.exportPageToSVG(pageIndex: 0)
        #expect(!svgString.isEmpty)
        #expect(svgString.contains("<svg"))
        #expect(svgString.contains("</svg>"))
        #expect(svgString.contains("<path"))

        // Also verify raw <text> mode when textAsPath = false
        let rawTextSVG = try doc.exportPageToSVG(pageIndex: 0, textAsPath: false)
        #expect(rawTextSVG.contains("<text"))

        // 2. Export page 1 to SVG file
        let tempSVG = FileManager.default.temporaryDirectory.appendingPathComponent("svg_single_\(UUID().uuidString).svg")
        defer { try? FileManager.default.removeItem(at: tempSVG) }
        try doc.exportPageToSVGFile(pageIndex: 1, destinationURL: tempSVG)
        #expect(FileManager.default.fileExists(atPath: tempSVG.path))
        let fileContent = try String(contentsOf: tempSVG, encoding: .utf8)
        #expect(fileContent.contains("<svg"))
        #expect(fileContent.contains("<path"))

        // 3. Multi-page export via PDFDocumentExporter (packages all pages into a dedicated folder)
        let exporter = PDFDocumentExporter()
        let multiFolder = FileManager.default.temporaryDirectory.appendingPathComponent("svg_multi_\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: multiFolder) }

        let exportedFolder = try exporter.exportSVG(from: doc, to: multiFolder)
        #expect(FileManager.default.fileExists(atPath: exportedFolder.path))
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: exportedFolder.path, isDirectory: &isDir) && isDir.boolValue)
        let page1URL = exportedFolder.appendingPathComponent("\(multiFolder.lastPathComponent)_page_1.svg")
        let page2URL = exportedFolder.appendingPathComponent("\(multiFolder.lastPathComponent)_page_2.svg")
        #expect(FileManager.default.fileExists(atPath: page1URL.path))
        #expect(FileManager.default.fileExists(atPath: page2URL.path))

        // Also verify that passing a destination with .svg extension creates the folder by stripping the extension
        let multiSVGTarget = FileManager.default.temporaryDirectory.appendingPathComponent("svg_pkg_\(UUID().uuidString).svg")
        let expectedFolder = multiSVGTarget.deletingPathExtension()
        defer { try? FileManager.default.removeItem(at: expectedFolder) }

        let resultFolder = try exporter.exportSVG(from: doc, to: multiSVGTarget)
        #expect(resultFolder.path == expectedFolder.path)
        #expect(FileManager.default.fileExists(atPath: expectedFolder.appendingPathComponent("\(expectedFolder.lastPathComponent)_page_1.svg").path))
        #expect(FileManager.default.fileExists(atPath: expectedFolder.appendingPathComponent("\(expectedFolder.lastPathComponent)_page_2.svg").path))
    }
}
