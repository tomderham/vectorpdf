import Foundation
import AppKit
import CoreGraphics
import Testing
import PDFKit
@testable import PDFEngine

func createSamplePDF(at fileURL: URL) {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(fileURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create CGPDFContext")
    }
    
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    
    // Page 1: Two columns & Figure reference
    context.beginPDFPage(nil)
    let boldFont = NSFont.boldSystemFont(ofSize: 18)
    let normalFont = NSFont.systemFont(ofSize: 12)
    
    let title = "MuPDF Architecture Specification"
    (title as NSString).draw(at: NSPoint(x: 54, y: 720), withAttributes: [.font: boldFont])
    
    // Column 1 text
    let col1 = "First column text discussing Figure 1 and research workflows."
    (col1 as NSString).draw(at: NSPoint(x: 54, y: 670), withAttributes: [.font: normalFont])
    
    // Column 2 text
    let col2 = "Second column text achieving ultra-high speed rendering."
    (col2 as NSString).draw(at: NSPoint(x: 320, y: 670), withAttributes: [.font: normalFont])
    
    context.endPDFPage()
    
    // Page 2: Table & Citation reference
    context.beginPDFPage(nil)
    let p2Text = "According to Table I and reference [1], performance is optimal."
    (p2Text as NSString).draw(at: NSPoint(x: 54, y: 720), withAttributes: [.font: normalFont])
    context.endPDFPage()
    
    context.closePDF()
}

func createPasswordProtectedPDF(at fileURL: URL, userPassword: String) {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    let auxInfo: [CFString: Any] = [
        kCGPDFContextUserPassword: userPassword,
        kCGPDFContextOwnerPassword: "owner-\(userPassword)"
    ]
    guard let context = CGContext(fileURL as CFURL, mediaBox: &mediaBox, auxInfo as CFDictionary) else {
        fatalError("Failed to create encrypted CGPDFContext")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.beginPDFPage(nil)
    ("Secret content" as NSString).draw(at: NSPoint(x: 54, y: 720), withAttributes: [.font: NSFont.systemFont(ofSize: 12)])
    context.endPDFPage()
    context.closePDF()
}

@Suite(.serialized)
struct PDFEngineTests {

@Test func testPasswordProtectedDocumentRequiresAndAcceptsPassword() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_password_\(UUID().uuidString).pdf")
    createPasswordProtectedPDF(at: pdfURL, userPassword: "correct-horse")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    // No password supplied — must fail with .passwordRequired, not open successfully or throw
    // some other generic error.
    do {
        _ = try PDFDocumentCore(filePath: pdfURL.path)
        Issue.record("Expected PDFError.passwordRequired but open succeeded")
    } catch PDFError.passwordRequired {
        // expected
    } catch {
        Issue.record("Expected PDFError.passwordRequired, got \(error)")
    }

    // Wrong password — must fail with .incorrectPassword specifically.
    do {
        _ = try PDFDocumentCore(filePath: pdfURL.path, password: "wrong-password")
        Issue.record("Expected PDFError.incorrectPassword but open succeeded")
    } catch PDFError.incorrectPassword {
        // expected
    } catch {
        Issue.record("Expected PDFError.incorrectPassword, got \(error)")
    }

    // Correct password — must open successfully.
    let doc = try PDFDocumentCore(filePath: pdfURL.path, password: "correct-horse")
    #expect(doc.pageCount == 1)
}

@Test func testDocumentCoreAndRapidLayout() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_core_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(doc.pageCount == 2)
    #expect(doc.pageBounds.count == 2)
    #expect(doc.pageBounds[0].width > 500)
    #expect(doc.pageBounds[0].height > 700)
    #expect(doc.pageYOffsets.count == 2)
    #expect(doc.totalHeight > 1500)
    
    let pageAtTop = doc.pageIndex(atYOffset: 100)
    #expect(pageAtTop == 0)
    let pageAtBottom = doc.pageIndex(atYOffset: 900)
    #expect(pageAtBottom == 1)
}

@Test func testRenderActorAndDisplayList() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_render_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let renderActor = PDFRenderActor(cacheCapacity: 4)
    try await renderActor.openDocument(filePath: pdfURL.path)
    
    // First render creates display list
    let img1 = try await renderActor.renderPage(pageIndex: 0, scale: 2.0).image
    #expect(img1.width > 1000)
    #expect(img1.height > 1400)

    // Second render uses display list cache
    let img2 = try await renderActor.renderPage(pageIndex: 0, scale: 1.0).image
    #expect(img2.width > 500)
    #expect(img2.height > 700)
}

@Test func testStructuredTextAndSpatialSelection() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_text_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let ctx = PDFContextManager.shared.makeClonedContext()
    defer { PDFContextManager.shared.dropContext(ctx) }
    
    try doc.withPage(pageIndex: 0) { page in
        let structuredPage = try StructuredPage.load(from: page, pageIndex: 0, ctx: ctx)
        #expect(!structuredPage.blocks.isEmpty)
        #expect(structuredPage.plainText.contains("MuPDF Architecture"))
        
        let selector = SpatialTextSelector()
        // Select within Column 1
        let result = selector.selectText(
            on: structuredPage,
            from: CGPoint(x: 54, y: 105),
            to: CGPoint(x: 200, y: 120)
        )
        #expect(!result.text.isEmpty)
        #expect(!result.highlightQuads.isEmpty)
    }
}

@Test func testSmartRegexAndSearchActor() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_search_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    // Test regex builder
    let pattern = SmartRegexBuilder.buildPattern(from: "\"ultra-high\"")
    #expect(!pattern.contains("\""))
    
    let searchActor = PDFSearchActor()
    try await searchActor.openDocument(filePath: pdfURL.path)
    
    let results = try await searchActor.search(query: "ultra-high")
    #expect(!results.isEmpty)
    #expect(results[0].pageIndex == 0)
    #expect(results[0].matchedText.contains("ultra-high"))
    #expect(!results[0].highlightQuads.isEmpty)
}

@Test func testSearchOptionsMatchCaseWholeWordAndSmartToggle() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_search_options_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let searchActor = PDFSearchActor()
    try await searchActor.openDocument(filePath: pdfURL.path)

    // Default options (case-insensitive, substring, smart) preserve existing behavior:
    // "table" matches "Table I" regardless of case.
    let defaultResults = try await searchActor.search(query: "table")
    #expect(!defaultResults.isEmpty)

    // matchCase = true: lowercase "table" must NOT match the document's "Table I".
    let caseSensitiveMiss = try await searchActor.search(query: "table", options: SearchOptions(matchCase: true))
    #expect(caseSensitiveMiss.isEmpty)

    // matchCase = true with the correct case still matches.
    let caseSensitiveHit = try await searchActor.search(query: "Table", options: SearchOptions(matchCase: true))
    #expect(!caseSensitiveHit.isEmpty)

    // wholeWord = false: "ext" matches as a substring of "text".
    let substringHit = try await searchActor.search(query: "ext")
    #expect(!substringHit.isEmpty)

    // wholeWord = true: "ext" must NOT match inside "text" (no standalone "ext" in the doc).
    let wholeWordMiss = try await searchActor.search(query: "ext", options: SearchOptions(wholeWord: true))
    #expect(wholeWordMiss.isEmpty)

    // wholeWord = true still matches a query that IS a whole word in the doc.
    let wholeWordHit = try await searchActor.search(query: "Table", options: SearchOptions(wholeWord: true))
    #expect(!wholeWordHit.isEmpty)

    // smartSearch = false: literal match should not apply hyphen/space normalization,
    // so "ultra high" (space) must NOT match the document's "ultra-high" (hyphen).
    let literalMiss = try await searchActor.search(query: "ultra high", options: SearchOptions(smartSearch: false))
    #expect(literalMiss.isEmpty)

    // smartSearch = true (default) still bridges hyphen/space as before.
    let smartHit = try await searchActor.search(query: "ultra high")
    #expect(!smartHit.isEmpty)
}

@Test func testCrossReferenceDetection() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_xref_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let resolver = CrossReferenceResolver()
    
    let academicRefs = resolver.detectAcademicReferences(
        in: "As demonstrated in Figure 1 and Table I with citation [1]...",
        sourcePage: 0,
        document: doc
    )
    #expect(academicRefs.count >= 3)
    let labels = academicRefs.map { $0.label }
    #expect(labels.contains(where: { $0.contains("Figure 1") }))
    #expect(labels.contains(where: { $0.contains("Table I") }))
    #expect(labels.contains(where: { $0.contains("[1]") }))
}

@Test func testReadingStateManagerPersistence() async throws {
    let manager = await ReadingStateManager.shared
    let testPath = "/tmp/test_reading_state_\(UUID().uuidString).pdf"
    let snapshot = SnapshotTarget(label: "Figure 3", targetPage: 4, sourcePage: 4)

    await MainActor.run {
        #expect(manager.state(for: testPath) == nil)

        manager.updateState(for: testPath, lastPageIndex: 5, zoomScale: 1.5, snapshots: [snapshot])
        let loaded = manager.state(for: testPath)
        #expect(loaded?.lastPageIndex == 5)
        #expect(loaded?.zoomScale == 1.5)
        #expect(loaded?.snapshots.count == 1)
        #expect(loaded?.snapshots.first?.label == "Figure 3")
    }
}

@Test func testSnapshotTargetRoundTripsThroughJSON() throws {
    let target = SnapshotTarget(
        label: "Table I",
        snippet: "Some extracted text",
        targetPage: 2,
        targetPoint: CGPoint(x: 100, y: 200),
        targetRect: CGRect(x: 10, y: 20, width: 30, height: 40),
        sourceRect: CGRect(x: 1, y: 2, width: 3, height: 4),
        sourcePage: 1,
        uri: "https://example.com"
    )
    let data = try JSONEncoder().encode(target)
    let decoded = try JSONDecoder().decode(SnapshotTarget.self, from: data)
    #expect(decoded == target)
}

@Test func testConcurrentRenderAndSearchWithoutDeadlock() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_concurrency_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let renderActor = PDFRenderActor()
    let searchActor = PDFSearchActor()
    
    try await renderActor.openDocument(filePath: pdfURL.path)
    try await searchActor.openDocument(filePath: pdfURL.path)
    
    // Run rendering and searching in parallel
    async let renderTask: PDFRenderActor.RenderedPage = renderActor.renderPage(pageIndex: 0, scale: 2.0)
    async let searchTask: [SearchResult] = searchActor.search(query: "Architecture")

    let (renderedPage, searchResults) = try await (renderTask, searchTask)
    #expect(renderedPage.image.width > 0)
    #expect(!searchResults.isEmpty)
    #expect(searchResults[0].matchedText.contains("Architecture"))
}

@Test func testAnnotationAndSavePDF() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let originalURL = tempDir.appendingPathComponent("test_annot_orig_\(UUID().uuidString).pdf")
    let savedURL = tempDir.appendingPathComponent("test_annot_saved_\(UUID().uuidString).pdf")
    createSamplePDF(at: originalURL)
    defer {
        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: savedURL)
    }
    
    let doc = try PDFDocumentCore(filePath: originalURL.path)
    let quad = PDFQuad(
        ul: CGPoint(x: 54, y: 720),
        ur: CGPoint(x: 350, y: 720),
        ll: CGPoint(x: 54, y: 700),
        lr: CGPoint(x: 350, y: 700)
    )
    try doc.addHighlight(pageIndex: 0, quad: quad, red: 1.0, green: 0.9, blue: 0.0)
    try doc.save(to: savedURL.path)
    
    #expect(FileManager.default.fileExists(atPath: savedURL.path))
    let reloadedDoc = try PDFDocumentCore(filePath: savedURL.path)
    #expect(reloadedDoc.pageCount == 2)
}

@Test func testHyphenWhitespaceInterchangeability() {
    let patternFromSpace = SmartRegexBuilder.buildPattern(from: "MU MIMO")
    let regex1 = try! NSRegularExpression(pattern: patternFromSpace, options: [.caseInsensitive])
    
    let sample1 = "We evaluated MU-MIMO throughput."
    let match1 = regex1.firstMatch(in: sample1, range: NSRange(location: 0, length: (sample1 as NSString).length))
    #expect(match1 != nil)
    
    let sample2 = "We evaluated MU MIMO throughput."
    let match2 = regex1.firstMatch(in: sample2, range: NSRange(location: 0, length: (sample2 as NSString).length))
    #expect(match2 != nil)
    
    let sample3 = "We evaluated MU–MIMO throughput."
    let match3 = regex1.firstMatch(in: sample3, range: NSRange(location: 0, length: (sample3 as NSString).length))
    #expect(match3 != nil)
    
    // Reverse test: searching "MU-MIMO" also matches "MU MIMO"
    let patternFromHyphen = SmartRegexBuilder.buildPattern(from: "MU-MIMO")
    let regex2 = try! NSRegularExpression(pattern: patternFromHyphen, options: [.caseInsensitive])
    let match4 = regex2.firstMatch(in: sample2, range: NSRange(location: 0, length: (sample2 as NSString).length))
    #expect(match4 != nil)
}

@Test func testStreamingSearchIncrementalResults() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_stream_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let searchActor = PDFSearchActor()
    try await searchActor.openDocument(filePath: pdfURL.path)
    
    let stream = await searchActor.searchStream(query: "Architecture")
    var streamedCount = 0
    for await result in stream {
        #expect(result.matchedText.contains("Architecture"))
        streamedCount += 1
    }
    #expect(streamedCount > 0)
}

@Test func testOnPageHighlightAndSelectionIntegration() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_onpage_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let searchActor = PDFSearchActor()
    try await searchActor.openDocument(filePath: pdfURL.path)
    
    // 1. Search yields quads suitable for inline on-page highlights
    let searchResults = try await searchActor.search(query: "Architecture")
    #expect(!searchResults.isEmpty)
    let firstMatch = searchResults[0]
    #expect(!firstMatch.highlightQuads.isEmpty)
    let highlightRect = firstMatch.highlightQuads[0].boundingRect
    #expect(highlightRect.width > 0)
    #expect(highlightRect.height > 0)
    
    // 2. Spatial text selector yields quads and extracted text for on-page drag selection
    let ctx = PDFContextManager.shared.makeClonedContext()
    defer { PDFContextManager.shared.dropContext(ctx) }
    
    try doc.withPage(pageIndex: 0) { page in
        let stext = try StructuredPage.load(from: page, pageIndex: 0, ctx: ctx)
        let selector = SpatialTextSelector()
        let selection = selector.selectText(on: stext, from: CGPoint(x: 50, y: 50), to: CGPoint(x: 400, y: 150))
        #expect(!selection.text.isEmpty)
        #expect(!selection.highlightQuads.isEmpty)
    }
    
    // 3. SnapshotTarget supports both internal destination and web URI
    let target = SnapshotTarget(label: "Test Link", targetPage: 1, sourceRect: CGRect(x: 10, y: 10, width: 50, height: 20), sourcePage: 0, uri: "https://artifex.com")
    #expect(target.uri == "https://artifex.com")
    #expect(target.targetPage == 1)
}

func createMultiPagePDF(at fileURL: URL, pages: Int) {
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(fileURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create CGPDFContext")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 12)
    for i in 0..<pages {
        context.beginPDFPage(nil)
        let text = "Page \(i) description with keywords such as MU-MIMO throughput analysis and system benchmarks."
        (text as NSString).draw(at: NSPoint(x: 54, y: 700), withAttributes: [.font: font])
        context.endPDFPage()
    }
    context.closePDF()
}

@Test func testMemoryFootprintRemainsBoundedUnderSearchAndRender() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_memory_\(UUID().uuidString).pdf")
    createMultiPagePDF(at: pdfURL, pages: 100)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let searchActor = PDFSearchActor()
    let renderActor = PDFRenderActor(cacheCapacity: 8)
    try await searchActor.openDocument(filePath: pdfURL.path)
    try await renderActor.openDocument(filePath: pdfURL.path)
    
    // 1. Run streaming search across all 100 pages
    let stream = await searchActor.searchStream(query: "MU MIMO")
    var matchCount = 0
    for await _ in stream {
        matchCount += 1
    }
    #expect(matchCount == 100)
    
    // 2. Render 20 Retina pages
    for i in 0..<20 {
        _ = try await renderActor.renderPage(pageIndex: i, scale: 2.0)
    }
    
    // 3. Measure max RSS
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    let rssMB = Double(usage.ru_maxrss) / (1024.0 * 1024.0)
    print("Peak memory RSS during 100-page search & render: \(String(format: "%.2f", rssMB)) MB")
    #expect(rssMB < 150.0)
}

@Test func testDualModeSelectionAndActionableSnapshots() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_dualmode_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let ctx = PDFContextManager.shared.makeClonedContext()
    defer { PDFContextManager.shared.dropContext(ctx) }
    
    try doc.withPage(pageIndex: 0) { page in
        let stext = try StructuredPage.load(from: page, pageIndex: 0, ctx: ctx)
        let selector = SpatialTextSelector()
        
        // 1. Reading Order Selection: continuous flow across text
        let readingResult = selector.selectText(
            on: stext,
            from: CGPoint(x: 54, y: 70),
            to: CGPoint(x: 300, y: 130),
            mode: .readingOrder
        )
        #expect(readingResult.mode == .readingOrder)
        #expect(!readingResult.text.isEmpty)
        #expect(!readingResult.highlightQuads.isEmpty)
        // Each quad covers a line with minX to maxX without holes
        for q in readingResult.highlightQuads {
            #expect(q.boundingRect.width > 10)
            #expect(q.boundingRect.height > 5)
        }
        
        // 2. Rectangular Area Selection: marquee box
        let startPt = CGPoint(x: 50, y: 65)
        let endPt = CGPoint(x: 250, y: 135)
        let areaResult = selector.selectText(
            on: stext,
            from: startPt,
            to: endPt,
            mode: .rectangularArea
        )
        #expect(areaResult.mode == .rectangularArea)
        #expect(areaResult.highlightQuads.count == 1) // Single crisp marquee quad
        let marqueeQuad = areaResult.highlightQuads[0]
        #expect(abs(marqueeQuad.boundingRect.minX - 50) < 1.0)
        #expect(abs(marqueeQuad.boundingRect.maxX - 250) < 1.0)
        #expect(!areaResult.text.isEmpty)
    }
    
    // 3. Actionable SnapshotTarget with thumbnail & snippet
    let dummyImage = NSImage(size: NSSize(width: 40, height: 40))
    dummyImage.lockFocus()
    NSColor.blue.setFill()
    NSRect(x: 0, y: 0, width: 40, height: 40).fill()
    dummyImage.unlockFocus()
    let tiffData = dummyImage.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiffData)!
    let pngData = rep.representation(using: .png, properties: [:])!
    
    let snap = SnapshotTarget(
        label: "Figure 1 Architecture",
        snippet: "Detailed high-speed vector architecture diagram",
        targetPage: 1,
        targetPoint: CGPoint(x: 100, y: 200),
        targetRect: CGRect(x: 54, y: 600, width: 250, height: 180),
        sourceRect: CGRect(x: 54, y: 670, width: 60, height: 15),
        sourcePage: 0,
        thumbnailData: pngData
    )
    
    #expect(snap.label == "Figure 1 Architecture")
    #expect(snap.snippet == "Detailed high-speed vector architecture diagram")
    #expect(snap.targetPage == 1)
    #expect(snap.targetRect != nil)
    #expect(snap.thumbnailFileName != nil)
    #expect(snap.thumbnailImage != nil)
    #expect(snap.thumbnailImage!.size.width > 0)
}

@MainActor
@Test func testSnapshotSelectionLifecycle() async throws {
    let vm = PDFViewerViewModel()
    #expect(vm.selectedSnapshotId == nil)
    
    let snap = SnapshotTarget(
        label: "Figure 1",
        snippet: "Snippet text",
        targetPage: 0,
        targetPoint: CGPoint(x: 100, y: 100),
        sourcePage: 0
    )
    
    vm.addSnapshotTarget(snap)
    #expect(vm.selectedSnapshotId == snap.id)
    
    vm.jumpToSnapshot(snap)
    #expect(vm.selectedSnapshotId == snap.id)
    
    vm.removeSnapshotTarget(snap)
    #expect(vm.selectedSnapshotId == nil)
}

@Test @MainActor func testSnapshotFromSearchResultAndDuplicatePrevention() async throws {
    let vm = PDFViewerViewModel()
    #expect(vm.activeSnapshots.isEmpty)
    #expect(vm.selectedSnapshotId == nil)
    
    let quad = PDFQuad(
        ul: CGPoint(x: 50, y: 120),
        ur: CGPoint(x: 150, y: 120),
        ll: CGPoint(x: 50, y: 100),
        lr: CGPoint(x: 150, y: 100)
    )
    let match = SearchResult(
        pageIndex: 2,
        matchedText: "transceiver architecture",
        snippet: "...the transceiver architecture enables...",
        highlightQuads: [quad]
    )
    
    let target = vm.buildSnapshotTarget(from: match)
    #expect(target.label == "transceiver architecture")
    #expect(target.snippet == "...the transceiver architecture enables...")
    #expect(target.targetPage == 2)
    #expect(target.thumbnailFileName == nil)
    #expect(target.targetRect == CGRect(x: 50, y: 100, width: 100, height: 20))
    #expect(target.targetPoint == CGPoint(x: 100, y: 110))
    
    // Add snapshot from search result
    vm.addSnapshot(from: match)
    #expect(vm.activeSnapshots.count == 1)
    #expect(vm.activeSnapshots.first?.label == "transceiver architecture")
    // Should NOT arbitrarily mutate selectedSnapshotId to disrupt user flow
    #expect(vm.selectedSnapshotId == nil)
    
    // Attempt duplicate addition of the exact same search match
    vm.addSnapshot(from: match)
    #expect(vm.activeSnapshots.count == 1)
    #expect(vm.selectedSnapshotId == nil)
    
    // A different search match on a different page should be added
    let match2 = SearchResult(
        pageIndex: 5,
        matchedText: "demodulation",
        snippet: "...digital demodulation stage...",
        highlightQuads: [quad]
    )
    vm.addSnapshot(from: match2)
    #expect(vm.activeSnapshots.count == 2)
}

@Test @MainActor func testSnapshotAtPagePointAndAddAndOpen() async throws {
    let vm = PDFViewerViewModel()
    
    // Test point target fallback when no structured text
    let target = vm.buildSnapshotTarget(at: CGPoint(x: 200, y: 300), pageIndex: 3)
    #expect(target.targetPage == 3)
    #expect(target.label == "Page 4")
    #expect(target.targetPoint == CGPoint(x: 200, y: 300))
    #expect(target.thumbnailFileName == nil)
    
    // Test addSnapshotTarget duplicate prevention
    vm.addSnapshotTarget(target)
    #expect(vm.activeSnapshots.count == 1)
    
    // Exact duplicate target with same snippet/page should not duplicate
    let duplicateTarget = SnapshotTarget(
        label: "Page 4",
        snippet: "Page 4",
        targetPage: 3,
        targetPoint: CGPoint(x: 200, y: 300),
        sourcePage: 3
    )
    vm.addSnapshotTarget(duplicateTarget)
    #expect(vm.activeSnapshots.count == 1)
}

@Test @MainActor func testSnapshotFromOutlineNodeAndDuplicatePrevention() async throws {
    let vm = PDFViewerViewModel()
    #expect(vm.activeSnapshots.isEmpty)

    let node = PDFOutlineNode(title: "Chapter 3: Methodology", uri: nil, targetPage: 12)
    let target = vm.buildSnapshotTarget(from: node)
    #expect(target != nil)
    #expect(target?.label == "Chapter 3: Methodology")
    #expect(target?.snippet == "Chapter 3: Methodology")
    #expect(target?.targetPage == 12)
    #expect(target?.sourcePage == 12)

    // Outline node without targetPage returns nil target
    let emptyNode = PDFOutlineNode(title: "Part I", uri: nil, targetPage: nil)
    #expect(vm.buildSnapshotTarget(from: emptyNode) == nil)

    // Add snapshot from outline node
    vm.addSnapshot(from: node)
    #expect(vm.activeSnapshots.count == 1)
    #expect(vm.activeSnapshots.first?.label == "Chapter 3: Methodology")

    // Attempt duplicate addition
    vm.addSnapshot(from: node)
    #expect(vm.activeSnapshots.count == 1)

    // Add a second outline node on a different page
    let node2 = PDFOutlineNode(title: "Chapter 4: Results", uri: nil, targetPage: 25)
    vm.addSnapshot(from: node2)
    #expect(vm.activeSnapshots.count == 2)
}

@Test @MainActor func testOutlineContextMenuGeneration() async throws {
    let vm = PDFViewerViewModel()
    let coordinator = PDFOutlineNSView.Coordinator(viewModel: vm, onSelect: { _ in })

    // Node with target page should offer Create Snapshot, Create Snapshot and Open in New Window, and Open in New Window
    let pageNode = PDFOutlineNode(title: "Introduction", uri: nil, targetPage: 0)
    let menu = coordinator.contextMenu(for: pageNode)
    #expect(menu != nil)
    let items = menu?.items ?? []
    let titles = items.map(\.title)
    #expect(titles.contains("Create Snapshot"))
    #expect(titles.contains("Create Snapshot and Open in New Window"))
    #expect(titles.contains("Open in New Window"))

    // External link node without targetPage offers Open Link
    let urlNode = PDFOutlineNode(title: "Project Website", uri: "https://example.com", targetPage: nil)
    let urlMenu = coordinator.contextMenu(for: urlNode)
    #expect(urlMenu != nil)
    let urlTitles = urlMenu?.items.map(\.title) ?? []
    #expect(urlTitles.contains("Open Link"))

    // Empty node without page or link returns nil menu
    let bareNode = PDFOutlineNode(title: "Section", uri: nil, targetPage: nil)
    #expect(coordinator.contextMenu(for: bareNode) == nil)
}

@Test func testRapidToCNavigationAndBoundedCache() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_toc_nav_\(UUID().uuidString).pdf")
    createMultiPagePDF(at: pdfURL, pages: 100)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let viewModel = await PDFViewerViewModel()
    await viewModel.loadDocument(from: pdfURL.path)
    
    // Perform rapid navigation across distant pages mimicking quick ToC clicks
    let jumpTargets = [15, 85, 3, 92, 44, 70, 0]
    for target in jumpTargets {
        await viewModel.jumpToPage(target)
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
    }
    
    let currentPage = await viewModel.currentPageIndex
    let renderedCount = await viewModel.renderedPages.count
    #expect(currentPage == 0)
    #expect(renderedCount <= 4)
}

@Test func testLocalNeighborhoodPrioritySearch() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_local_search_\(UUID().uuidString).pdf")
    createMultiPagePDF(at: pdfURL, pages: 120)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let searchActor = PDFSearchActor()
    try await searchActor.openDocument(filePath: pdfURL.path)
    
    // Prioritize search around page 90:
    // Window: [90-50 ... min(119, 90+50)] = [40 ... 119]
    let stream = await searchActor.searchStream(query: "throughput", nearPage: 90)
    
    var firstEmittedPage: Int? = nil
    var totalMatches = 0
    for await result in stream {
        if firstEmittedPage == nil {
            firstEmittedPage = result.pageIndex
        }
        totalMatches += 1
    }
    
    #expect(totalMatches == 120)
    // The very first page emitted must be from the local neighborhood (page 40), not page 0
    #expect(firstEmittedPage != nil)
    #expect(firstEmittedPage! >= 40 && firstEmittedPage! <= 119)
    #expect(firstEmittedPage == 40)
}

@Test func testSearchBufferSuppressesEarlyJudderAndMaintainsActiveMatch() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_judder_\(UUID().uuidString).pdf")
    createMultiPagePDF(at: pdfURL, pages: 120)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let viewModel = await PDFViewerViewModel()
    await viewModel.loadDocument(from: pdfURL.path)
    
    await MainActor.run {
        viewModel.currentPageIndex = 90
        viewModel.searchQuery = "throughput"
        viewModel.performSearch()
    }
    
    // Await search completion
    for _ in 0..<100 {
        let isSearching = await viewModel.isSearching
        if !isSearching { break }
        try await Task.sleep(nanoseconds: 30_000_000)
    }
    
    let resultsCount = await viewModel.searchResults.count
    let activeIdx = await viewModel.activeSearchMatchIndex
    let activeId = await viewModel.activeSearchMatchId
    let targetPage = await viewModel.searchResults[activeIdx].pageIndex
    
    #expect(resultsCount == 120)
    // Even though 40 early results (pages 0...39) were added at completion,
    // the active match remained anchored to page 90 where the user initiated search!
    #expect(targetPage == 90)
    #expect(activeIdx == 90)
    let expectedId = await viewModel.searchResults[90].id
    #expect(activeId == expectedId)
    let scrollTargetBeforeSubmit = await viewModel.activeScrollTargetId
    #expect(scrollTargetBeforeSubmit == nil)
    
    await MainActor.run {
        viewModel.submitSearch()
    }
    let scrollTargetId = await viewModel.activeScrollTargetId
    #expect(scrollTargetId == expectedId.uuidString)
}

@Test func testSearchFindsNearestHitAndNavigatesOnSubmit() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_search_nav_\(UUID().uuidString).pdf")
    createMultiPagePDF(at: pdfURL, pages: 120)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let viewModel = await PDFViewerViewModel()
    await viewModel.loadDocument(from: pdfURL.path)
    
    // 1. Live search from page 10 for a term that appears forward on page 45
    await MainActor.run {
        viewModel.currentPageIndex = 10
        viewModel.searchQuery = "Page 45"
        viewModel.performSearch()
    }
    
    for _ in 0..<100 {
        let isSearching = await viewModel.isSearching
        if !isSearching { break }
        try await Task.sleep(nanoseconds: 30_000_000)
    }
    
    let resultsCount = await viewModel.searchResults.count
    #expect(resultsCount == 1)
    var curPage = await viewModel.currentPageIndex
    var targetId = await viewModel.activeScrollTargetId
    let matchId = await viewModel.searchResults.first?.id.uuidString
    
    // Quiet live search: canvas remains on page 10 without scrolling
    #expect(curPage == 10)
    #expect(targetId == nil)
    
    // Submitting search (e.g. pressing Return) navigates to the nearest match
    await MainActor.run {
        viewModel.submitSearch()
    }
    curPage = await viewModel.currentPageIndex
    targetId = await viewModel.activeScrollTargetId
    #expect(curPage == 45)
    #expect(targetId != nil)
    #expect(targetId == matchId)
    
    // 2. Live search from page 50 for a term that only appears backward on page 15
    await MainActor.run {
        viewModel.currentPageIndex = 50
        viewModel.searchQuery = "Page 15"
        viewModel.performSearch()
    }
    
    for _ in 0..<100 {
        let isSearching = await viewModel.isSearching
        if !isSearching { break }
        try await Task.sleep(nanoseconds: 30_000_000)
    }
    
    let backResultsCount = await viewModel.searchResults.count
    #expect(backResultsCount == 1)
    var backCurPage = await viewModel.currentPageIndex
    var backTargetId = await viewModel.activeScrollTargetId
    let backMatchId = await viewModel.searchResults.first?.id.uuidString
    
    // Canvas remains at page 50 while typing
    #expect(backCurPage == 50)
    #expect(backTargetId == nil)
    
    // Submitting search navigates canvas to page 15
    await MainActor.run {
        viewModel.submitSearch()
    }
    backCurPage = await viewModel.currentPageIndex
    backTargetId = await viewModel.activeScrollTargetId
    #expect(backCurPage == 15)
    #expect(backTargetId == backMatchId)
}

@Test func testNativeScreenshotExtractionAndClipboard() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_screenshot_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let viewModel = await PDFViewerViewModel()
    await viewModel.loadDocument(from: pdfURL.path)
    await viewModel.renderPage(0)
    
    // Simulate a rectangular marquee selection
    let cropBox = CGRect(x: 50, y: 650, width: 200, height: 100)
    let marqueeQuad = PDFQuad(
        ul: CGPoint(x: 50, y: 750),
        ur: CGPoint(x: 250, y: 750),
        ll: CGPoint(x: 50, y: 650),
        lr: CGPoint(x: 250, y: 650)
    )
    let selResult = SelectionResult(
        text: "Cropped figure text",
        highlightQuads: [marqueeQuad],
        boundingRect: cropBox,
        mode: .rectangularArea
    )
    
    await MainActor.run {
        viewModel.activeSelection = (pageIndex: 0, result: selResult)
    }
    
    // Test cropped image generation
    let croppedImage = await viewModel.renderCroppedSelection()
    #expect(croppedImage != nil)
    if let img = croppedImage {
        #expect(abs(img.size.width - 200) < 2.0)
        #expect(abs(img.size.height - 100) < 2.0)
    }
    
    // Test clipboard copy
    await viewModel.copyActiveScreenshot()
    let pb = NSPasteboard.general
    let availableTypes = pb.types ?? []
    #expect(availableTypes.contains(.png) || availableTypes.contains(.tiff))
}

@Test func testDocumentTitleAndEditableToolbarControls() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let uniqueName = "custom_spec_\(UUID().uuidString).pdf"
    let pdfURL = tempDir.appendingPathComponent(uniqueName)
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let viewModel = await PDFViewerViewModel()
    let initialTitle = await viewModel.documentTitle
    #expect(initialTitle == "VectorPDF")
    
    await viewModel.loadDocument(from: pdfURL.path)
    let loadedTitle = await viewModel.documentTitle
    #expect(loadedTitle == uniqueName)
    
    // Test custom zoom level input
    await viewModel.setZoom(1.75)
    let currentZoom = await viewModel.zoomScale
    #expect(abs(currentZoom - 1.75) < 0.001)
    
    // Test direct page navigation
    await viewModel.jumpToPage(1)
    let curPage = await viewModel.currentPageIndex
    #expect(curPage == 1)
    
    // Test previousPage / nextPage convenience methods for modernized pill navigation
    await viewModel.previousPage()
    #expect(await viewModel.currentPageIndex == 0)
    await viewModel.nextPage()
    #expect(await viewModel.currentPageIndex == 1)
}

@Test func testRapidGeometryIndexingLargeDoc() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_rapid_index_\(UUID().uuidString).pdf")
    createMultiPagePDF(at: pdfURL, pages: 120)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let startTime = CFAbsoluteTimeGetCurrent()
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let elapsedMs = (CFAbsoluteTimeGetCurrent() - startTime) * 1000.0
    
    print("Geometry indexing time for 120 pages: \(String(format: "%.2f", elapsedMs)) ms")
    #expect(elapsedMs < 50.0) // Must index in well under 50 ms (typically < 3 ms)
    #expect(doc.pageCount == 120)
    #expect(doc.pageBounds.count == 120)
    #expect(doc.pageYOffsets.count == 120)
    #expect(doc.pageYOffsets[0] == 0.0)
    #expect(doc.pageYOffsets[1] > 0.0)
    #expect(doc.pageYOffsets[119] > doc.pageYOffsets[118])
}

@Test func testAtomicSaveDocumentAndReload() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let originalURL = tempDir.appendingPathComponent("test_save_orig_\(UUID().uuidString).pdf")
    let copyURL = tempDir.appendingPathComponent("test_save_copy_\(UUID().uuidString).pdf")
    createSamplePDF(at: originalURL)
    defer {
        try? FileManager.default.removeItem(at: originalURL)
        try? FileManager.default.removeItem(at: copyURL)
    }
    
    let doc = try PDFDocumentCore(filePath: originalURL.path)
    #expect(doc.pageCount == 2)
    
    // 1. Add highlight annotation
    let quad = PDFQuad(
        ul: CGPoint(x: 54, y: 720),
        ur: CGPoint(x: 300, y: 720),
        ll: CGPoint(x: 54, y: 700),
        lr: CGPoint(x: 300, y: 700)
    )
    try doc.addHighlight(pageIndex: 0, quad: quad, red: 1.0, green: 0.8, blue: 0.0)
    
    // 2. Atomic save to SAME file
    try doc.save(to: originalURL.path)
    #expect(FileManager.default.fileExists(atPath: originalURL.path))
    
    // Verify file reloads cleanly
    let reloadedDoc = try PDFDocumentCore(filePath: originalURL.path)
    #expect(reloadedDoc.pageCount == 2)
    
    // 3. Save As to NEW file
    try doc.save(to: copyURL.path)
    #expect(FileManager.default.fileExists(atPath: copyURL.path))
    let copyDoc = try PDFDocumentCore(filePath: copyURL.path)
    #expect(copyDoc.pageCount == 2)
}

@Test func testFavoritesManagerPersistence() async throws {
    let manager = await FavoritesManager.shared
    let testPath = "/tmp/test_fav_\(UUID().uuidString).pdf"
    let testTitle = "Favorites Test Spec"
    
    await MainActor.run {
        #expect(!manager.isFavorite(path: testPath))
        manager.addFavorite(path: testPath, title: testTitle)
        #expect(manager.isFavorite(path: testPath))
        #expect(manager.favorites.contains { $0.path == testPath && $0.title == testTitle })
        
        manager.removeFavorite(path: testPath)
        #expect(!manager.isFavorite(path: testPath))
    }
}

@Test @MainActor func testPrintOperationCreation() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_print_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let printView = try MuPDFPrintView(filePath: pdfURL.path, password: nil, pageCount: 1)
    #expect(printView.pageCount == 1)
    
    let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
    printInfo.isHorizontallyCentered = true
    printInfo.isVerticallyCentered = true
    printInfo.dictionary()[NSPrintInfo.AttributeKey.firstPage] = 1
    printInfo.dictionary()[NSPrintInfo.AttributeKey.lastPage] = 1

    let printOp = NSPrintOperation(view: printView, printInfo: printInfo)
    printOp.showsPrintPanel = true
    printOp.showsProgressPanel = true
    printOp.canSpawnSeparateThread = true
    
    let expectedTitle = (pdfURL.path as NSString).lastPathComponent
    printOp.jobTitle = expectedTitle
    #expect(printOp.jobTitle == expectedTitle)
    
    printOp.printPanel.options.insert([
        .showsPaperSize,
        .showsOrientation
    ])
    printOp.printPanel.options.remove([
        .showsScaling,
        .showsPageSetupAccessory
    ])
    #expect(printOp.printPanel.options.contains(.showsPaperSize))
    #expect(printOp.printPanel.options.contains(.showsOrientation))
    #expect(!printOp.printPanel.options.contains(.showsScaling))
    #expect(!printOp.printPanel.options.contains(.showsPageSetupAccessory))
    
    let accessoryVC = PDFPrintAccessoryViewController(printOperation: printOp, printView: printView)
    printOp.printPanel.addAccessoryController(accessoryVC)
    #expect(printOp.printPanel.accessoryControllers.count == 1)
    #expect(printOp.printPanel.accessoryControllers.first?.title == "PDF Options")
    _ = accessoryVC.view
    #expect(accessoryVC.localizedSummaryItems().count == 2)
    #expect(accessoryVC.keyPathsForValuesAffectingPreview().contains("previewScale"))
    #expect(accessoryVC.keyPathsForValuesAffectingPreview().contains("previewAutoRotate"))
    
    var pageRange = NSRange()
    #expect(printView.knowsPageRange(&pageRange) == true)
    #expect(pageRange.location == 1)
    #expect(pageRange.length == 1)
    
    let pageRect = printView.rectForPage(1)
    #expect(pageRect.width > 0 && pageRect.height > 0)
    
    let pdfData = printView.dataWithPDF(inside: printView.bounds)
    #expect(pdfData.count > 1000)
}

@Test @MainActor func testFlushPendingFormEdits() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_flush_\(UUID().uuidString).pdf")
    createFormSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    
    let widgets = vm.pageFormWidgets[0]
    guard let textWidget = widgets?.first(where: { $0.type == .text }) else {
        Issue.record("Missing text widget in sample PDF")
        return
    }
    
    // Update debounced (not committed immediately)
    vm.updateWidgetValueDebounced(pageIndex: 0, widgetIndex: textWidget.widgetIndex, value: "Immediately Flushed")
    
    // Flush immediately before debounce timer triggers
    vm.flushPendingFormEdits()
    
    // Check that the widget was committed to pageFormWidgets and the document
    let updatedWidgets = vm.pageFormWidgets[0]
    let updatedTextWidget = updatedWidgets?.first(where: { $0.widgetIndex == textWidget.widgetIndex })
    #expect(updatedTextWidget?.value == "Immediately Flushed")
}

func createFormSamplePDF(at fileURL: URL) {
    let pdfDoc = PDFKit.PDFDocument()
    let page = PDFKit.PDFPage()
    pdfDoc.insert(page, at: 0)
    
    // Text widget
    let textAnnot = PDFKit.PDFAnnotation(bounds: CGRect(x: 100, y: 500, width: 200, height: 30), forType: .widget, withProperties: nil)
    textAnnot.widgetFieldType = .text
    textAnnot.widgetStringValue = "Initial Form Value"
    textAnnot.fieldName = "CustomerName"
    page.addAnnotation(textAnnot)
    
    // Checkbox widget
    let checkAnnot = PDFKit.PDFAnnotation(bounds: CGRect(x: 100, y: 450, width: 24, height: 24), forType: .widget, withProperties: nil)
    checkAnnot.widgetFieldType = .button
    checkAnnot.widgetControlType = .checkBoxControl
    checkAnnot.widgetStringValue = "Off"
    checkAnnot.fieldName = "SubscribeNewsletter"
    page.addAnnotation(checkAnnot)
    
    pdfDoc.write(to: fileURL)
}

@Test @MainActor func testAcroFormWidgetLoadingAndValueEditing() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_acroform_\(UUID().uuidString).pdf")
    createFormSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let widgets = doc.loadFormWidgets(for: 0)
    #expect(!widgets.isEmpty)
    
    let textWidget = widgets.first(where: { $0.type == .text })
    #expect(textWidget != nil)
    #expect(textWidget?.name == "CustomerName")
    #expect(textWidget?.value == "Initial Form Value")
    
    let checkWidget = widgets.first(where: { $0.type == .checkbox || $0.type == .button })
    #expect(checkWidget != nil)
    print("Found checkWidget: type=\(String(describing: checkWidget?.type)), name=\(String(describing: checkWidget?.name)), value=\(String(describing: checkWidget?.value))")
    
    // Update text widget value
    if let tw = textWidget {
        try doc.setFormWidgetValue(pageIndex: 0, widgetIndex: tw.widgetIndex, value: "Updated Via MuPDF")
    }
    if let cw = checkWidget {
        try doc.setFormWidgetValue(pageIndex: 0, widgetIndex: cw.widgetIndex, value: "Yes")
    }
    
    // Save to same file
    try doc.save(to: pdfURL.path)
    
    // Re-open and verify persistence
    let reloadedDoc = try PDFDocumentCore(filePath: pdfURL.path)
    let reloadedWidgets = reloadedDoc.loadFormWidgets(for: 0)
    let reloadedTextWidget = reloadedWidgets.first(where: { $0.name == "CustomerName" })
    #expect(reloadedTextWidget?.value == "Updated Via MuPDF")
    let reloadedCheckWidget = reloadedWidgets.first(where: { $0.name == "SubscribeNewsletter" })
    print("Reloaded checkWidget value: \(String(describing: reloadedCheckWidget?.value))")
    #expect(reloadedCheckWidget?.value != "Off")
    #expect(PDFFormButton.isValueChecked(reloadedCheckWidget?.value ?? "") == true)
    
    // Uncheck checkbox back to Off and verify persistence
    if let cw = reloadedCheckWidget {
        try reloadedDoc.setFormWidgetValue(pageIndex: 0, widgetIndex: cw.widgetIndex, value: "Off")
    }
    try reloadedDoc.save(to: pdfURL.path)
    let reloadedDoc2 = try PDFDocumentCore(filePath: pdfURL.path)
    let reloadedWidgets2 = reloadedDoc2.loadFormWidgets(for: 0)
    let reloadedCheckWidget2 = reloadedWidgets2.first(where: { $0.name == "SubscribeNewsletter" })
    #expect(reloadedCheckWidget2?.value == "Off")
    #expect(PDFFormButton.isValueChecked(reloadedCheckWidget2?.value ?? "") == false)
    
    // Test ViewModel integration
    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.isDocumentEdited == false)
    
    vm.updateWidgetValue(pageIndex: 0, widgetIndex: 0, value: "ViewModel Edited")
    #expect(vm.isDocumentEdited == true)
    #expect(vm.pageFormWidgets[0]?.first?.value == "ViewModel Edited")
    
    vm.saveDocument()
    #expect(vm.isDocumentEdited == false)
}

@Test @MainActor func testFormControlsScaleWithZoom() throws {
    let vm = PDFViewerViewModel()
    let textWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .text,
        rect: CGRect(x: 10, y: 10, width: 200, height: 20),
        name: "TestText",
        value: "Zoom Test"
    )
    let tf = PDFFormTextField(widget: textWidget, viewModel: vm, frame: NSRect(x: 10, y: 10, width: 200, height: 20))
    let initialFontSize = tf.font?.pointSize ?? 0
    #expect(initialFontSize > 0)
    
    // Zoom in 2x: frame height doubles
    let zoomedFrame = NSRect(x: 20, y: 20, width: 400, height: 40)
    tf.updateZoom(frame: zoomedFrame)
    let zoomedFontSize = tf.font?.pointSize ?? 0
    #expect(zoomedFontSize > initialFontSize)
    
    // Choice button zoom
    let choiceWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 1,
        type: .combobox,
        rect: CGRect(x: 10, y: 40, width: 100, height: 20),
        name: "TestChoice",
        value: "Opt1",
        options: ["Opt1", "Opt2"]
    )
    let popup = PDFFormChoiceButton(widget: choiceWidget, viewModel: vm, frame: NSRect(x: 10, y: 40, width: 100, height: 20))
    let initialPopupFontSize = popup.font?.pointSize ?? 0
    popup.updateZoom(frame: NSRect(x: 20, y: 80, width: 200, height: 40))
    let zoomedPopupFontSize = popup.font?.pointSize ?? 0
    #expect(zoomedPopupFontSize > initialPopupFontSize)
}

@Test @MainActor func testCheckboxAndRadioButtonTogglingAndState() throws {
    // 1. Verify isValueChecked logic for PDF compliance
    #expect(PDFFormButton.isValueChecked("Off") == false)
    #expect(PDFFormButton.isValueChecked("off") == false)
    #expect(PDFFormButton.isValueChecked("0") == false)
    #expect(PDFFormButton.isValueChecked("false") == false)
    #expect(PDFFormButton.isValueChecked("") == false)
    
    #expect(PDFFormButton.isValueChecked("Yes") == true)
    #expect(PDFFormButton.isValueChecked("yes") == true)
    #expect(PDFFormButton.isValueChecked("On") == true)
    #expect(PDFFormButton.isValueChecked("on") == true)
    #expect(PDFFormButton.isValueChecked("1") == true)
    #expect(PDFFormButton.isValueChecked("Choice1") == true)
    
    // 2. Checkbox toggle cycle (off -> on -> off)
    let vm = PDFViewerViewModel()
    let checkWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .checkbox,
        rect: CGRect(x: 10, y: 10, width: 12, height: 12),
        name: "Terms",
        value: "Off"
    )
    let btn = PDFFormButton(widget: checkWidget, viewModel: vm, frame: NSRect(x: 10, y: 10, width: 12, height: 12))
    #expect(btn.state == .off)
    
    // Toggle on
    btn.toggle()
    #expect(btn.state == .on)
    
    // Toggle off
    btn.toggle()
    #expect(btn.state == .off)
    
    // Radio button stays on once selected
    let radioWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 1,
        type: .radiobutton,
        rect: CGRect(x: 10, y: 30, width: 12, height: 12),
        name: "OptionA",
        value: "Off"
    )
    let radioBtn = PDFFormButton(widget: radioWidget, viewModel: vm, frame: NSRect(x: 10, y: 30, width: 12, height: 12))
    #expect(radioBtn.state == .off)
    radioBtn.toggle()
    #expect(radioBtn.state == .on)
    radioBtn.toggle()
    #expect(radioBtn.state == .on)
}

@Test @MainActor func testCheckboxGeometryNonIntrusiveAcrossZooms() throws {
    let vm = PDFViewerViewModel()
    let smallWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .checkbox,
        rect: CGRect(x: 50, y: 100, width: 12, height: 12),
        name: "CompactBox",
        value: "Off"
    )
    
    // Test across various zoom scales (0.5x, 1.0x, 2.0x, 3.0x)
    let zoomScales: [CGFloat] = [0.5, 0.75, 1.0, 1.5, 2.0, 3.0]
    for zoom in zoomScales {
        let expectedWidth = smallWidget.rect.width * zoom
        let expectedHeight = smallWidget.rect.height * zoom
        let frame = NSRect(x: 50 * zoom, y: 100 * zoom, width: expectedWidth, height: expectedHeight)
        
        let btn = PDFFormButton(widget: smallWidget, viewModel: vm, frame: frame)
        #expect(btn.frame.width == expectedWidth)
        #expect(btn.frame.height == expectedHeight)
        
        // Ensure bounds strictly contain the control without intrusion
        #expect(btn.bounds.width == expectedWidth)
        #expect(btn.bounds.height == expectedHeight)
    }
}

@Test @MainActor func testWidgetMaskAndControlGeometryMatchAcrossZooms() throws {
    let vm = PDFViewerViewModel()
    let canvas = PDFCanvasView(viewModel: vm)
    let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let checkboxWidget = PDFFormWidget(
        pageIndex: 0, widgetIndex: 0, type: .checkbox,
        rect: CGRect(x: 50, y: 100, width: 10, height: 10),
        name: "Box", value: "Off"
    )
    let textWidget = PDFFormWidget(
        pageIndex: 0, widgetIndex: 1, type: .text,
        rect: CGRect(x: 50, y: 100, width: 100, height: 6),
        name: "Field", value: ""
    )

    // Regression test: draw() masks widgets and syncFormControls() sizes their live
    // NSControl overlay by calling this exact same function, so a checkbox's on-screen
    // mask can never grow past its own control frame and blank out neighboring page
    // content — which is what happened before when the two had separately-maintained,
    // drifted-apart size floors. Covers a range including very low zoom, where the old
    // 16x14pt floor would have kicked in for a widget this small.
    for zoom in [CGFloat(0.25), 0.5, 1.0, 2.0] {
        vm.zoomScale = zoom
        let pageFrame = NSRect(x: 0, y: 0, width: pageBounds.width * zoom, height: pageBounds.height * zoom)

        // Checkboxes/radio buttons scale proportionally with no minimum floor.
        let checkboxFrame = canvas.widgetScreenFrame(for: checkboxWidget, pageFrame: pageFrame, pageBounds: pageBounds)
        #expect(checkboxFrame.width == checkboxWidget.rect.width * zoom)
        #expect(checkboxFrame.height == checkboxWidget.rect.height * zoom)

        // Text fields keep their legibility/click-target floor at low zoom.
        let textFrame = canvas.widgetScreenFrame(for: textWidget, pageFrame: pageFrame, pageBounds: pageBounds)
        #expect(textFrame.width >= 16)
        #expect(textFrame.height >= 14)
    }
}

@Test @MainActor func testZoomInAndOutSnapsTo25PercentIntervalsFromCustomZoom() throws {
    let vm = PDFViewerViewModel()
    
    // 1. Standard progression from 100%
    vm.zoomScale = 1.0
    vm.zoomIn()
    #expect(abs(vm.zoomScale - 1.25) < 0.001)
    vm.zoomIn()
    #expect(abs(vm.zoomScale - 1.50) < 0.001)
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 1.25) < 0.001)
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 1.00) < 0.001)
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 0.75) < 0.001)
    
    // 2. Custom zoom above 100% (e.g. 113%)
    vm.zoomScale = 1.13
    // zoomOut should snap down to 100% in one click
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 1.00) < 0.001)
    
    vm.zoomScale = 1.13
    // zoomIn should snap up to 125% in one click
    vm.zoomIn()
    #expect(abs(vm.zoomScale - 1.25) < 0.001)
    
    // 3. Custom zoom below 100% (e.g. 88%)
    vm.zoomScale = 0.88
    // zoomIn should snap up to 100% in one click
    vm.zoomIn()
    #expect(abs(vm.zoomScale - 1.00) < 0.001)
    
    vm.zoomScale = 0.88
    // zoomOut should snap down to 75% in one click
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 0.75) < 0.001)
    
    // 4. Boundary clamping
    vm.zoomScale = 3.90
    vm.zoomIn()
    #expect(abs(vm.zoomScale - 4.00) < 0.001)
    vm.zoomIn()
    #expect(abs(vm.zoomScale - 4.00) < 0.001)
    
    vm.zoomScale = 0.55
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 0.50) < 0.001)
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 0.50) < 0.001)
}

@Test @MainActor func testPDFViewerAppCoordinatorUpdatesOnDocumentLifecycle() async throws {
    let coordinator = PDFViewerAppCoordinator.shared
    
    // Create new view model without document
    let vm = PDFViewerViewModel()
    coordinator.registerActive(vm)
    #expect(coordinator.hasActiveDocument == false)
    #expect(coordinator.activeViewModel === vm)
    
    // Create temporary PDF
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_coordinator_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    // Load document into view model
    await vm.loadDocument(from: pdfURL.path)
    
    #expect(coordinator.hasActiveDocument == true)
    #expect(coordinator.documentTitle == pdfURL.lastPathComponent)
    #expect(coordinator.canZoomIn == true)
    #expect(coordinator.canZoomOut == true)
    
    // Registering nil resets active document status
    coordinator.registerActive(nil)
    #expect(coordinator.hasActiveDocument == false)
    #expect(coordinator.activeViewModel == nil)
}

@Test @MainActor func testCheckboxSaveAppearanceAndPDFKitCompatibility() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_checkbox_print_\(UUID().uuidString).pdf")
    createFormSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let widgets = doc.loadFormWidgets(for: 0)
    guard let checkWidget = widgets.first(where: { $0.type == .checkbox || $0.type == .button }) else {
        Issue.record("No checkbox widget found")
        return
    }
    
    // Set to checked ("Yes")
    try doc.setFormWidgetValue(pageIndex: 0, widgetIndex: checkWidget.widgetIndex, value: "Yes")
    try doc.save(to: pdfURL.path)
    
    // 1. Verify MuPDF reload
    let mupdfDoc = try PDFDocumentCore(filePath: pdfURL.path)
    let mupdfWidgets = mupdfDoc.loadFormWidgets(for: 0)
    let reloadedCheck = mupdfWidgets.first(where: { $0.name == checkWidget.name })
    #expect(reloadedCheck?.value != "Off")
    #expect(PDFFormButton.isValueChecked(reloadedCheck?.value ?? "") == true)
    
    // 2. Verify Apple PDFKit / Quartz (used for printing) reads the updated appearance/value
    guard let appleDoc = PDFKit.PDFDocument(url: pdfURL), let page = appleDoc.page(at: 0) else {
        Issue.record("Failed to load PDF via PDFKit")
        return
    }
    let appleCheck = page.annotations.first(where: { $0.fieldName == checkWidget.name })
    #expect(appleCheck != nil)
    #expect(appleCheck?.widgetStringValue != "Off")
    #expect(PDFFormButton.isValueChecked(appleCheck?.widgetStringValue ?? "") == true)
}

@Test func testWindowTabBarVisibilityOnCreation() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_tabbar_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    await MainActor.run {
        let window = DocumentWindowing.makeWindow(for: pdfURL)
        #expect(window.tabbingMode == .preferred)
        #expect(window.tabGroup?.isTabBarVisible == true)
        #expect(window.styleMask.contains(.fullSizeContentView))
        #expect(window.titlebarAppearsTransparent == true)
        #expect(window.toolbarStyle == .unified)
    }
}

@Test func testSemanticVersionComparison() throws {
    // Basic core version comparisons
    #expect(SemanticVersion.isNewerVersion(latestTag: "0.1.2", currentVersion: "0.1.1") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0", currentVersion: "0.9.9") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "0.1.1", currentVersion: "0.1.1") == false)
    #expect(SemanticVersion.isNewerVersion(latestTag: "0.1.0", currentVersion: "0.1.1") == false)

    // Leading 'v' or 'V' and whitespace stripping
    #expect(SemanticVersion.isNewerVersion(latestTag: "v0.1.2", currentVersion: "0.1.1") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "V1.0.0", currentVersion: "v0.9.9") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "  v0.1.1  ", currentVersion: "0.1.1") == false)

    // Build metadata (ignored in SemVer precedence)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0+build123", currentVersion: "1.0.0") == false)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.1+build123", currentVersion: "1.0.0") == true)

    // Normal release vs Pre-release precedence
    // Normal release has higher precedence than a pre-release of the same core version
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0", currentVersion: "1.0.0-rc.1") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-rc.1", currentVersion: "1.0.0") == false)

    // Pre-release vs Pre-release
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-beta.2", currentVersion: "1.0.0-beta.1") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-beta.1", currentVersion: "1.0.0-beta.2") == false)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-rc.1", currentVersion: "1.0.0-beta.2") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-alpha", currentVersion: "1.0.0-alpha.1") == false)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-alpha.1", currentVersion: "1.0.0-alpha") == true)

    // Numeric vs Alphanumeric identifier precedence in pre-release
    // Numeric identifiers always have lower precedence than alphanumeric identifiers
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-alpha.beta", currentVersion: "1.0.0-alpha.1") == true)
    #expect(SemanticVersion.isNewerVersion(latestTag: "1.0.0-alpha.1", currentVersion: "1.0.0-alpha.beta") == false)
}

@Test func testGitHubReleaseJSONDecoding() throws {
    let json = """
    {
        "tag_name": "v0.1.2",
        "name": "VectorPDF 0.1.2",
        "body": "Fixed update check and improved performance.",
        "html_url": "https://github.com/tomderham/vectorpdf/releases/tag/v0.1.2",
        "assets": [
            {
                "name": "VectorPDF-0.1.2.dmg",
                "browser_download_url": "https://github.com/tomderham/vectorpdf/releases/download/v0.1.2/VectorPDF.dmg",
                "size": 25165824
            },
            {
                "name": "checksums.txt",
                "browser_download_url": "https://github.com/tomderham/vectorpdf/releases/download/v0.1.2/checksums.txt",
                "size": 128
            }
        ]
    }
    """.data(using: .utf8)!

    let release = try JSONDecoder().decode(GitHubRelease.self, from: json)
    #expect(release.tagName == "v0.1.2")
    #expect(release.name == "VectorPDF 0.1.2")
    #expect(release.assets.count == 2)

    let dmgAsset = release.assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
    #expect(dmgAsset != nil)
    #expect(dmgAsset?.browserDownloadUrl == "https://github.com/tomderham/vectorpdf/releases/download/v0.1.2/VectorPDF.dmg")
    #expect(dmgAsset?.size == 25165824)
}

@Test @MainActor func testGitHubUpdaterSettingsPersistence() throws {
    let updater = GitHubUpdater.shared

    // Toggle automaticUpdateChecks
    let initialValue = updater.automaticUpdateChecks
    updater.automaticUpdateChecks = !initialValue
    #expect(UserDefaults.standard.bool(forKey: GitHubUpdater.automaticUpdateChecksKey) == !initialValue)

    // Restore initial value
    updater.automaticUpdateChecks = initialValue
    #expect(UserDefaults.standard.bool(forKey: GitHubUpdater.automaticUpdateChecksKey) == initialValue)

    // Timestamp persistence
    let testDate = Date(timeIntervalSince1970: 1700000000)
    updater.lastUpdateCheckDate = testDate
    let storedMs = UserDefaults.standard.double(forKey: GitHubUpdater.lastUpdateCheckKey)
    #expect(abs(storedMs - testDate.timeIntervalSince1970 * 1000.0) < 1.0)
}

@Test @MainActor func testFavoritesManagerUndo() throws {
    let manager = FavoritesManager.shared
    let testPath = "/tmp/test_fav_undo_\(UUID().uuidString).pdf"
    
    // Clean up if already exists
    manager.removeFavorite(path: testPath)
    
    manager.addFavorite(path: testPath, title: "Test Doc")
    #expect(manager.isFavorite(path: testPath) == true)
    
    // Remove and check return tuple
    let removed = manager.removeFavorite(path: testPath)
    #expect(removed != nil)
    #expect(removed?.document.path == testPath)
    #expect(manager.isFavorite(path: testPath) == false)
    
    // Undo / re-insert
    if let removed {
        manager.insertFavorite(removed.document, at: removed.index)
    }
    #expect(manager.isFavorite(path: testPath) == true)
    
    // Clean up
    manager.removeFavorite(path: testPath)
    #expect(manager.isFavorite(path: testPath) == false)
}

@Test @MainActor func testTabGroupManagerUndo() throws {
    let manager = TabGroupManager.shared
    let group = manager.addGroup(name: "Test Group", documentPaths: ["/tmp/a.pdf", "/tmp/b.pdf"])
    #expect(manager.group(withId: group.id) != nil)
    
    // Remove and check return tuple
    let removed = manager.removeGroup(group.id)
    #expect(removed != nil)
    #expect(removed?.group.id == group.id)
    #expect(manager.group(withId: group.id) == nil)
    
    // Undo / re-insert
    if let removed {
        manager.insertGroup(removed.group, at: removed.index)
    }
    #expect(manager.group(withId: group.id) != nil)
    
    // Clean up
    manager.removeGroup(group.id)
    #expect(manager.group(withId: group.id) == nil)
}
@Test @MainActor func testIsStandaloneEmptyStartWindowDetection() async throws {
    let window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    defer { window.close() }

    // Standalone window with no doc and no edits is eligible
    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(window) == true)

    // Window with a represented URL is not eligible
    window.representedURL = URL(fileURLWithPath: "/path/to/doc.pdf")
    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(window) == false)
    window.representedURL = nil

    // Edited window is not eligible
    window.isDocumentEdited = true
    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(window) == false)
    window.isDocumentEdited = false

    // Associated with view model that has no doc -> eligible
    let vm = PDFViewerViewModel()
    vm.currentWindow = window
    PDFViewerAppCoordinator.shared.registerActive(vm)
    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(window) == true)

    // Associated with view model that has a doc -> not eligible
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_tabgroup_detect_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    await vm.loadDocument(from: pdfURL.path)
    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(window) == false)

    PDFViewerAppCoordinator.shared.registerActive(nil)
}

@Test @MainActor func testOpenGroupReplacesStandaloneEmptyStartWindow() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL1 = tempDir.appendingPathComponent("test_tg_1_\(UUID().uuidString).pdf")
    let pdfURL2 = tempDir.appendingPathComponent("test_tg_2_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL1)
    createSamplePDF(at: pdfURL2)
    defer {
        try? FileManager.default.removeItem(at: pdfURL1)
        try? FileManager.default.removeItem(at: pdfURL2)
    }

    let initialFrame = NSRect(x: 150, y: 150, width: 900, height: 620)
    let startWindow = NSWindow(
        contentRect: initialFrame,
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    startWindow.isReleasedWhenClosed = false
    startWindow.setFrame(initialFrame, display: false)

    let group = TabGroup(name: "Test Group", documentPaths: [pdfURL1.path, pdfURL2.path])
    let openedWindow = DocumentWindowing.openGroup(group, replacing: startWindow)
    defer {
        // Clean up opened windows
        let tabs = openedWindow?.tabbedWindows ?? (openedWindow.map { [$0] } ?? [])
        for tab in tabs {
            tab.close()
        }
    }

    #expect(openedWindow != nil)
    if let opened = openedWindow {
        #expect(opened.frame == initialFrame)
        let tabCount = opened.tabbedWindows?.count ?? 1
        #expect(tabCount == 2)
    }
}

@Test @MainActor func testOpenGroupDoesNotReplaceWindowWithDocument() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL1 = tempDir.appendingPathComponent("test_tg_doc1_\(UUID().uuidString).pdf")
    let pdfURL2 = tempDir.appendingPathComponent("test_tg_doc2_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL1)
    createSamplePDF(at: pdfURL2)
    defer {
        try? FileManager.default.removeItem(at: pdfURL1)
        try? FileManager.default.removeItem(at: pdfURL2)
    }

    let docWindow = NSWindow(
        contentRect: NSRect(x: 200, y: 200, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    docWindow.isReleasedWhenClosed = false
    docWindow.representedURL = pdfURL1
    defer { docWindow.close() }

    let group = TabGroup(name: "Test Group", documentPaths: [pdfURL1.path, pdfURL2.path])
    let openedWindow = DocumentWindowing.openGroup(group, replacing: docWindow)
    defer {
        let tabs = openedWindow?.tabbedWindows ?? (openedWindow.map { [$0] } ?? [])
        for tab in tabs {
            tab.close()
        }
    }

    #expect(openedWindow != nil)
    #expect(openedWindow !== docWindow)
    // docWindow should still exist and not have been closed as replacement
    #expect(docWindow.representedURL == pdfURL1)
}

@Test @MainActor func testCloseStandaloneEmptyStartWindows() async throws {
    let emptyWin1 = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    emptyWin1.isReleasedWhenClosed = false

    let emptyWin2 = NSWindow(
        contentRect: NSRect(x: 120, y: 120, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    emptyWin2.isReleasedWhenClosed = false

    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(emptyWin1) == true)
    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(emptyWin2) == true)

    DocumentWindowing.closeStandaloneEmptyStartWindows(except: emptyWin1)

    #expect(DocumentWindowing.isStandaloneEmptyStartWindow(emptyWin1) == true)
    emptyWin1.close()
}

@Test @MainActor func testOpenDocumentHandlingEmptyStart() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_handling_empty_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let emptyWindow = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    emptyWindow.isReleasedWhenClosed = false

    let opened = DocumentWindowing.openDocumentHandlingEmptyStart(url: pdfURL, preferredWindow: emptyWindow)
    defer { opened.close() }

    #expect(opened.title == pdfURL.lastPathComponent)
    #expect(opened.contentViewController != nil)
}

@Test @MainActor func testSnapshotWindowManagerParentChildClose() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_snapshot_manager_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let parentWindow = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    parentWindow.isReleasedWhenClosed = false
    defer { parentWindow.close() }

    let target1 = SnapshotTarget(label: "Figure 1", targetPage: 0, sourcePage: 0)
    let target2 = SnapshotTarget(label: "Table 1", targetPage: 1, sourcePage: 0)

    SnapshotWindowManager.shared.open(url: pdfURL, target: target1, source: parentWindow)
    SnapshotWindowManager.shared.open(url: pdfURL, target: target2, source: parentWindow)

    #expect(SnapshotWindowManager.shared.isOpen(target1.id) == true)
    #expect(SnapshotWindowManager.shared.isOpen(target2.id) == true)

    // Closing all children from child window or parent window context
    SnapshotWindowManager.shared.closeChildrenOfCurrentParent(for: parentWindow)

    #expect(SnapshotWindowManager.shared.isOpen(target1.id) == false)
    #expect(SnapshotWindowManager.shared.isOpen(target2.id) == false)
}

@Test @MainActor func testSnapshotWindowAutoClosesWhenParentCloses() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_snapshot_autoclose_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let parentWindow = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    parentWindow.isReleasedWhenClosed = false

    let target = SnapshotTarget(label: "Section 1", targetPage: 0, sourcePage: 0)
    SnapshotWindowManager.shared.open(url: pdfURL, target: target, source: parentWindow)

    #expect(SnapshotWindowManager.shared.isOpen(target.id) == true)

    parentWindow.close()

    #expect(SnapshotWindowManager.shared.isOpen(target.id) == false)
}

@Test func testTruncatedAtWordBoundary() {
    let text = "achieving ultra-high speed architecture rendering"
    #expect(text.truncatedAtWordBoundary(maxLength: 20) == "achieving ultra-high")
    #expect(text.truncatedAtWordBoundary(maxLength: 25) == "achieving ultra-high")

    let textWithPunct = "first column text, discussing Figure 1"
    #expect(textWithPunct.truncatedAtWordBoundary(maxLength: 18) == "first column text")
}

@Test @MainActor func testBuildSnapshotTargetAtPagePointStartsWithClickedWord() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_point_target_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    // Title "MuPDF Architecture Specification" is at y=720 (MuPDF y=72).
    // Clicking at x=54 should start with "MuPDF"
    let target1 = vm.buildSnapshotTarget(at: CGPoint(x: 54, y: 72), pageIndex: 0)
    #expect(target1.label.hasPrefix("MuPDF"))
    #expect(target1.targetPage == 0)

    // Clicking at x=140 (on "Architecture") must start with "Architecture", NOT "MuPDF"
    let target2 = vm.buildSnapshotTarget(at: CGPoint(x: 140, y: 72), pageIndex: 0)
    #expect(target2.label.hasPrefix("Architecture"))
    #expect(!target2.label.hasSuffix(" "))
    #expect(target2.targetPage == 0)
}

@Test @MainActor func testForm1040CheckboxDoesNotCorruptSiblingTextFields() throws {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let f1040URL = repoRoot.appendingPathComponent("Resources/test-files/f1040.pdf")
    guard FileManager.default.fileExists(atPath: f1040URL.path) else { return }

    let doc = try PDFDocumentCore(filePath: f1040URL.path)
    let page1WidgetsBefore = doc.loadFormWidgets(for: 1)
    let textWidgetsBefore = page1WidgetsBefore.filter { $0.type == .text }
    let emptyTextFieldsBefore = textWidgetsBefore.filter { $0.value.isEmpty }
    #expect(!emptyTextFieldsBefore.isEmpty)

    let btnWidgets = page1WidgetsBefore.filter { $0.type == .checkbox || $0.type == .radiobutton }
    guard let targetBtn = btnWidgets.first(where: { $0.name.contains("c2_16[1]") || $0.name.contains("c2_17[1]") }) ?? btnWidgets.first else {
        Issue.record("No button widget found on page 1 of f1040.pdf")
        return
    }

    // Toggle button on (which in f1040 sets on-state "2" or "1")
    try doc.setFormWidgetValue(pageIndex: 1, widgetIndex: targetBtn.widgetIndex, value: "Yes")

    let page1WidgetsAfter = doc.loadFormWidgets(for: 1)
    let textWidgetsAfter = page1WidgetsAfter.filter { $0.type == .text }
    
    // Crucial check: None of the previously empty text fields should now have the button's value (e.g. "2" or "Yes")
    for tw in textWidgetsAfter {
        if emptyTextFieldsBefore.contains(where: { $0.name == tw.name }) {
            #expect(tw.value.isEmpty, "Text field \(tw.name) was unexpectedly populated with '\(tw.value)'")
        }
    }

    // Check that the button itself was set
    let reloadedBtn = page1WidgetsAfter.first(where: { $0.widgetIndex == targetBtn.widgetIndex })
    #expect(reloadedBtn != nil)
    #expect(PDFFormButton.isValueChecked(reloadedBtn?.value ?? "") == true)

    // Toggle back off
    try doc.setFormWidgetValue(pageIndex: 1, widgetIndex: targetBtn.widgetIndex, value: "Off")
    let page1WidgetsOff = doc.loadFormWidgets(for: 1)
    let reloadedBtnOff = page1WidgetsOff.first(where: { $0.widgetIndex == targetBtn.widgetIndex })
    #expect(PDFFormButton.isValueChecked(reloadedBtnOff?.value ?? "") == false)

    for tw in page1WidgetsOff.filter({ $0.type == .text }) {
        if emptyTextFieldsBefore.contains(where: { $0.name == tw.name }) {
            #expect(tw.value.isEmpty, "Text field \(tw.name) was unexpectedly populated after unchecking with '\(tw.value)'")
        }
    }
}

@Test @MainActor func testSecureTextFieldCreatedForPasswordWidget() throws {
    let vm = PDFViewerViewModel()
    let normalWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .text,
        rect: CGRect(x: 10, y: 10, width: 100, height: 20),
        name: "Username",
        value: "user",
        isPassword: false
    )
    let secureWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 1,
        type: .text,
        rect: CGRect(x: 10, y: 40, width: 100, height: 20),
        name: "Password",
        value: "secret",
        isPassword: true
    )

    let normalControl = PDFFormControlFactory.makeControl(for: normalWidget, viewModel: vm, frame: NSRect(x: 10, y: 10, width: 100, height: 20))
    let secureControl = PDFFormControlFactory.makeControl(for: secureWidget, viewModel: vm, frame: NSRect(x: 10, y: 40, width: 100, height: 20))

    #expect(normalControl is PDFFormTextField)
    #expect(!(normalControl is PDFFormSecureTextField))
    #expect(secureControl is PDFFormSecureTextField)
}

@Test func testDocumentWithoutOutlineHasEmptyOutline() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_no_outline_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(doc.outline.isEmpty == true)
}

@Test @MainActor func testSingleLineTextFieldDisallowsMultilineAndSanitizesNewlines() throws {
    let vm = PDFViewerViewModel()
    let singleLineWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .text,
        rect: CGRect(x: 10, y: 10, width: 200, height: 20),
        name: "SingleLineField",
        value: "Line1\nLine2\rLine3",
        isMultiline: false
    )
    let tf = PDFFormTextField(widget: singleLineWidget, viewModel: vm, frame: NSRect(x: 10, y: 10, width: 200, height: 20))
    #expect(tf.usesSingleLineMode == true)
    #expect(tf.maximumNumberOfLines == 1)
    #expect(tf.cell?.wraps == false)
    #expect(tf.cell?.isScrollable == true)
    #expect(tf.stringValue == "Line1 Line2 Line3")

    // Multiline field preserves wrapping
    let multiLineWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 1,
        type: .text,
        rect: CGRect(x: 10, y: 40, width: 200, height: 80),
        name: "MultiLineField",
        value: "Line1\nLine2",
        isMultiline: true
    )
    let multiTf = PDFFormTextField(widget: multiLineWidget, viewModel: vm, frame: NSRect(x: 10, y: 40, width: 200, height: 80))
    #expect(multiTf.usesSingleLineMode == false)
    #expect(multiTf.maximumNumberOfLines == 0)
    #expect(multiTf.cell?.wraps == true)
}

@Test @MainActor func testTextFieldAccurateFontSizeScaling() throws {
    let vm = PDFViewerViewModel()
    // Explicit font size (e.g. 8pt in tax forms)
    let exactWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .text,
        rect: CGRect(x: 10, y: 10, width: 100, height: 12),
        name: "ExactFontField",
        value: "Test",
        fontSize: 8.0
    )
    let tf = PDFFormTextField(widget: exactWidget, viewModel: vm, frame: NSRect(x: 10, y: 10, width: 100, height: 12))
    #expect(tf.font?.pointSize == 8.0)

    // Zoomed 1.5x -> height becomes 18
    tf.updateZoom(frame: NSRect(x: 15, y: 15, width: 150, height: 18))
    #expect(tf.font?.pointSize == 12.0)
}

@Test @MainActor func testCombFieldDetectionAndFactoryCreation() throws {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let f1040URL = repoRoot.appendingPathComponent("Resources/test-files/f1040.pdf")
    guard FileManager.default.fileExists(atPath: f1040URL.path) else { return }

    let doc = try PDFDocumentCore(filePath: f1040URL.path)
    let page1Widgets = doc.loadFormWidgets(for: 1)
    let combWidgets = page1Widgets.filter { $0.isComb }
    #expect(!combWidgets.isEmpty, "f1040.pdf should have comb fields such as PIN or Routing number")

    let vm = PDFViewerViewModel()
    for widget in combWidgets {
        #expect(widget.maxLen > 0)
        let control = PDFFormControlFactory.makeControl(for: widget, viewModel: vm, frame: NSRect(origin: .zero, size: widget.rect.size))
        #expect(control is PDFFormCombTextField)
    }
}

@Test @MainActor func testCombFieldInteractionAndTyping() throws {
    let vm = PDFViewerViewModel()
    let combWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .text,
        rect: CGRect(x: 0, y: 0, width: 100, height: 20),
        name: "PIN",
        value: "12",
        maxLen: 5,
        isComb: true
    )
    let combField = PDFFormCombTextField(widget: combWidget, viewModel: vm, frame: NSRect(x: 0, y: 0, width: 100, height: 20))
    #expect(combField.stringValue == "12")
    #expect(combField.maxLen == 5)
    #expect(combField.activeCellIndex == 2)

    // Setting stringValue respects maxLen
    combField.stringValue = "123456789"
    #expect(combField.stringValue == "12345")
    #expect(combField.activeCellIndex == 4)

    // Clear stringValue
    combField.stringValue = ""
    #expect(combField.stringValue == "")
    #expect(combField.activeCellIndex == 0)
}

@Test @MainActor func testTextFieldMaxLenEnforcement() throws {
    let vm = PDFViewerViewModel()
    let maxLenWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .text,
        rect: CGRect(x: 0, y: 0, width: 100, height: 20),
        name: "Code",
        value: "ABCD",
        maxLen: 4
    )
    let tf = PDFFormTextField(widget: maxLenWidget, viewModel: vm, frame: NSRect(x: 0, y: 0, width: 100, height: 20))
    
    // Attempting to type or paste past maxLen is rejected by shouldChangeTextIn
    let tv = NSTextView()
    tv.string = "ABCD"
    let canInsertMore = tf.control(tf, textView: tv, shouldChangeTextIn: NSRange(location: 4, length: 0), replacementString: "E")
    #expect(canInsertMore == false)

    let canReplace = tf.control(tf, textView: tv, shouldChangeTextIn: NSRange(location: 3, length: 1), replacementString: "X")
    #expect(canReplace == true)
}

@Test @MainActor func testTextAlignmentApplied() throws {
    let vm = PDFViewerViewModel()
    let centerWidget = PDFFormWidget(
        pageIndex: 0,
        widgetIndex: 0,
        type: .text,
        rect: CGRect(x: 0, y: 0, width: 100, height: 20),
        name: "Centered",
        value: "Center",
        textAlignment: .center
    )
    let tf = PDFFormTextField(widget: centerWidget, viewModel: vm, frame: NSRect(x: 0, y: 0, width: 100, height: 20))
    #expect(tf.alignment == .center)
}

@Test func testFormResetFunctionality() throws {
    let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let f1040URL = repoRoot.appendingPathComponent("Resources/test-files/f1040.pdf")
    guard FileManager.default.fileExists(atPath: f1040URL.path) else { return }

    let doc = try PDFDocumentCore(filePath: f1040URL.path)
    // Verify resetForm succeeds without throwing
    try doc.resetForm()
}

@Test @MainActor func testWindowDelegateClosesCleanlyWhenNotEdited() throws {
    let vm = PDFViewerViewModel()
    let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
        styleMask: [.titled, .closable],
        backing: .buffered,
        defer: false
    )
    let delegate = PDFViewerWindowDelegate(viewModel: vm)
    window.delegate = delegate
    vm.currentWindow = window
    
    // When not edited, windowShouldClose immediately returns true
    #expect(vm.isDocumentEdited == false)
    #expect(delegate.windowShouldClose(window) == true)
}

@Test @MainActor func testAgentModelContextConstantsAndInstructions() throws {
    #expect(DocumentAgentConversation.onDeviceContextSize == 4096)
    #expect(DocumentAgentConversation.pccContextSize == 32768)
    #expect(DocumentAgentConversation.onDeviceMaxResponseTokens == 800)
    #expect(DocumentAgentConversation.pccMaxResponseTokens == 4000)
    #expect(DocumentAgentConversation.fullDocumentTokenThreshold == 20_000)

    // Verify on-device instructions are ultra-compact (< 25 words) to preserve limited token context
    let onDeviceWords = DocumentAgentConversation.onDeviceInstructions.split(whereSeparator: { $0.isWhitespace })
    #expect(onDeviceWords.count < 25)

    // Verify PCC instructions encourage thoroughness and citation tags
    #expect(DocumentAgentConversation.pccInstructions.contains("[Page X]"))
    #expect(DocumentAgentConversation.instructions == DocumentAgentConversation.onDeviceInstructions)

    let engine = DocumentAgentConversation()
    let pools = engine.recommendedCandidatePoolSizes()
    let passageBudget = engine.recommendedPassageCount()
    #expect(pools.embedding >= 24)
    #expect(pools.lexical >= 10)
    #expect(passageBudget >= 6)
}

@Test func testAgentCitationFormattingAndExtraction() throws {
    let sampleText = "Gross revenue was $1.2M [Page 4]. Net profit increased [Pages 12-14], while debt fell [p. 8] and taxes rose [pp. 19-20]."
    let formatted = formatAgentAnswerCitations(sampleText)

    #expect(formatted.contains("[Page 4](pdfpage://4)"))
    #expect(formatted.contains("[Page 12](pdfpage://12)"))
    #expect(formatted.contains("[Page 8](pdfpage://8)"))
    #expect(formatted.contains("[Page 19](pdfpage://19)"))

    let cited = extractCitedPageIndices(from: sampleText)
    // 0-indexed page indices
    #expect(cited.contains(3))   // Page 4
    #expect(cited.contains(11))  // Page 12
    #expect(cited.contains(7))   // Page 8
    #expect(cited.contains(18))  // Page 19
    #expect(!cited.contains(0))
}

@Test @MainActor func testAgentMultiTurnQueryFoldingLogic() throws {
    let vm = PDFViewerViewModel()

    // Short follow-up queries should fold previous question
    #expect(vm.shouldFoldPreviousQuestion("why?") == true)
    #expect(vm.shouldFoldPreviousQuestion("tell me more") == true)
    #expect(vm.shouldFoldPreviousQuestion("how does it work?") == true)
    #expect(vm.shouldFoldPreviousQuestion("elaborate on that point") == true)

    // Distinct long questions should not fold
    #expect(vm.shouldFoldPreviousQuestion("What is the penalty for filing late under section 4?") == false)
    #expect(vm.shouldFoldPreviousQuestion("Where does the document list standard deductions for joint filers?") == false)
}
}


