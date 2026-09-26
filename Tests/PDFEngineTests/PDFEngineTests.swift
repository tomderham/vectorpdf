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

@Test func testSaveEncryptedDocumentWithPassword() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let srcURL = tempDir.appendingPathComponent("test_plain_\(UUID().uuidString).pdf")
    let encURL = tempDir.appendingPathComponent("test_encrypted_\(UUID().uuidString).pdf")
    createSamplePDF(at: srcURL)
    defer {
        try? FileManager.default.removeItem(at: srcURL)
        try? FileManager.default.removeItem(at: encURL)
    }

    let doc = try PDFDocumentCore(filePath: srcURL.path)
    #expect(doc.pageCount == 2)

    // Save with AES-256 encryption password
    let password = "vector-super-secret"
    try doc.saveEncrypted(to: encURL.path, password: password)
    #expect(FileManager.default.fileExists(atPath: encURL.path))

    // Must fail without password
    do {
        _ = try PDFDocumentCore(filePath: encURL.path)
        Issue.record("Expected PDFError.passwordRequired when opening encrypted document without password")
    } catch PDFError.passwordRequired {
        // expected
    } catch {
        Issue.record("Expected PDFError.passwordRequired, got \(error)")
    }

    // Must fail with incorrect password
    do {
        _ = try PDFDocumentCore(filePath: encURL.path, password: "incorrect-pass")
        Issue.record("Expected PDFError.incorrectPassword")
    } catch PDFError.incorrectPassword {
        // expected
    } catch {
        Issue.record("Expected PDFError.incorrectPassword, got \(error)")
    }

    // Must succeed with correct password
    let encDoc = try PDFDocumentCore(filePath: encURL.path, password: password)
    #expect(encDoc.pageCount == 2)
}

@Test @MainActor func testCoordinatorTracksActiveSelection() throws {
    let coordinator = PDFViewerAppCoordinator.shared
    let vm = PDFViewerViewModel()
    coordinator.registerActive(vm)

    #expect(coordinator.hasActiveSelection == false)

    let quad = PDFQuad(rect: CGRect(x: 0, y: 0, width: 10, height: 10))
    let result = SelectionResult(text: "Selected text", highlightQuads: [quad], mode: .readingOrder)
    vm.activeSelection = (pageIndex: 0, result: result)

    #expect(coordinator.hasActiveSelection == true)

    vm.clearSelection()
    #expect(coordinator.hasActiveSelection == false)
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

    // Node with target page should offer Create Anchor, Create Anchor and Open in New Window, and Open in New Window
    let pageNode = PDFOutlineNode(title: "Introduction", uri: nil, targetPage: 0)
    let menu = coordinator.contextMenu(for: pageNode)
    #expect(menu != nil)
    let items = menu?.items ?? []
    let titles = items.map(\.title)
    #expect(titles.contains("Create Anchor"))
    #expect(titles.contains("Create Anchor and Open in New Window"))
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
    #expect(availableTypes.contains(.png))
    #expect(pb.data(forType: .png) != nil)
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
    #expect(abs(vm.zoomScale - 0.25) < 0.001)
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 0.25) < 0.001)

    // 5. Behaviors when below 25% (e.g. via pinch-to-zoom down to 10%)
    vm.zoomScale = 0.10
    vm.zoomOut()
    #expect(abs(vm.zoomScale - 0.10) < 0.001)
    vm.zoomIn()
    #expect(abs(vm.zoomScale - 0.25) < 0.001)
}

@Test @MainActor func testMenuZoomCentersOnCurrentPage() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_zoom_center_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    
    let scrollView = PDFScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let canvasView = PDFCanvasView(viewModel: vm)
    scrollView.documentView = canvasView
    let coordinator = PDFVirtualizedScrollView.Coordinator(viewModel: vm)
    coordinator.scrollView = scrollView
    coordinator.canvasView = canvasView
    
    // Initial layout at 100% zoom
    coordinator.update(viewModel: vm, scrollView: scrollView)
    
    // Now zoom in to 150% (simulating menu / toolbar zoom)
    vm.zoomScale = 1.5
    coordinator.update(viewModel: vm, scrollView: scrollView)
    
    let clipView = scrollView.contentView
    guard let pFrame = canvasView.pageFrame(for: vm.currentPageIndex) else {
        Issue.record("pageFrame missing")
        return
    }
    
    let maxScrollX = max(0, canvasView.frame.width - clipView.bounds.width)
    let maxScrollY = max(0, canvasView.frame.height - clipView.bounds.height)
    let expectedScrollX = min(max(0, pFrame.midX - clipView.bounds.width / 2), maxScrollX)
    let expectedScrollY = min(max(0, pFrame.midY - clipView.bounds.height / 2), maxScrollY)
    
    #expect(abs(clipView.bounds.origin.x - expectedScrollX) < 1.0)
    #expect(abs(clipView.bounds.origin.y - expectedScrollY) < 1.0)
}

@Test @MainActor func testPinchToZoomStateAndBounds() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_pinch_bounds_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }
    
    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    
    let scrollView = PDFScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
    let canvasView = PDFCanvasView(viewModel: vm)
    scrollView.documentView = canvasView
    let coordinator = PDFVirtualizedScrollView.Coordinator(viewModel: vm)
    coordinator.scrollView = scrollView
    coordinator.canvasView = canvasView
    
    coordinator.update(viewModel: vm, scrollView: scrollView)
    #expect(coordinator.isPinching == false)
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

    // At 50% zoom, zoom out is still possible (can go down to 25%)
    vm.zoomScale = 0.50
    coordinator.updateDocumentStatus()
    #expect(coordinator.canZoomOut == true)

    // At 25% zoom, zoom out is disabled
    vm.zoomScale = 0.25
    coordinator.updateDocumentStatus()
    #expect(coordinator.canZoomOut == false)

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

@Test @MainActor func testResolvedTargetRectForReferenceAtBottomOfPage() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_bottom_ref_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        Issue.record("Failed to create CGContext")
        return
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    context.beginPDFPage(nil)
    let normalFont = NSFont.systemFont(ofSize: 12)
    ("Header section at the top" as NSString).draw(at: NSPoint(x: 54, y: 720), withAttributes: [.font: normalFont])
    ("Reference [42] High performance rendering specification." as NSString).draw(at: NSPoint(x: 54, y: 80), withAttributes: [.font: normalFont])
    context.endPDFPage()
    context.closePDF()

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    // Destination anchor at top of page (y=0 or y=40, common for /FitH anchors)
    let topAnchorSnap = SnapshotTarget(label: "[42]", targetPage: 0, targetPoint: CGPoint(x: 0, y: 0), sourcePage: 0)
    let resolvedRect = vm.resolvedTargetRect(for: topAnchorSnap)

    // The text at CoreGraphics y=80 sits at MuPDF Fitz y ≈ 792 - 80 - 12 ≈ 700.
    // resolvedTargetRect MUST resolve to the bottom line (y > 600), not the top of the page (y ≈ 0).
    #expect(resolvedRect.minY > 600)
    #expect(resolvedRect.maxY < 790)

    // With NaN coordinates, it should still resolve to the line matching the label
    let nanSnap = SnapshotTarget(label: "[42]", targetPage: 0, targetPoint: CGPoint(x: CGFloat.nan, y: CGFloat.nan), sourcePage: 0)
    let resolvedNaNRect = vm.resolvedTargetRect(for: nanSnap)
    #expect(resolvedNaNRect.minY > 600)
    #expect(resolvedNaNRect.maxY < 790)

    // When a window is not tall enough (e.g. height 400 < 792), simulate viewport scrolling calculation
    let viewportHeight: CGFloat = 400.0
    let pageCanvasY: CGFloat = 16.0 // page 0 frame minY
    let targetCanvasY = pageCanvasY + resolvedRect.minY
    let targetCanvasH = resolvedRect.height

    let scrollY = targetCanvasY + (targetCanvasH / 2) - (viewportHeight / 2)
    // The target rect MUST be completely inside the visible viewport [scrollY, scrollY + viewportHeight]
    #expect(targetCanvasY >= scrollY)
    #expect(targetCanvasY + targetCanvasH <= scrollY + viewportHeight)
}

@Test func testAnnotationModelAndColorRGB() throws {
    let quad = PDFQuad(
        ul: CGPoint(x: 10, y: 10),
        ur: CGPoint(x: 50, y: 10),
        ll: CGPoint(x: 10, y: 30),
        lr: CGPoint(x: 50, y: 30)
    )
    let annot = PDFAnnotation(
        pageIndex: 0,
        type: PDFAnnotationType.highlight,
        quads: [quad],
        color: .yellow,
        text: "Sample highlighted text"
    )

    #expect(annot.pageIndex == 0)
    #expect(annot.type == PDFAnnotationType.highlight)
    #expect(annot.text == "Sample highlighted text")
    #expect(annot.contains(pagePoint: CGPoint(x: 25, y: 20)) == true)
    #expect(annot.contains(pagePoint: CGPoint(x: 100, y: 100)) == false)

    // Check color channels
    let (yr, yg, yb) = AnnotationColor.yellow.rgb
    #expect(yr > 0.9 && yg > 0.8 && yb < 0.5)

    let (gr, gg, gb) = AnnotationColor.green.rgb
    #expect(gr < 0.5 && gg > 0.8 && gb < 0.6)

    #expect(AnnotationColor.allCases.count == 10)
}

@Test func testMuPDFMultiQuadHighlightAndDeletion() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_highlight_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(doc.pageCount == 2)

    let quad1 = PDFQuad(
        ul: CGPoint(x: 54, y: 720),
        ur: CGPoint(x: 200, y: 720),
        ll: CGPoint(x: 54, y: 740),
        lr: CGPoint(x: 200, y: 740)
    )
    let quad2 = PDFQuad(
        ul: CGPoint(x: 54, y: 670),
        ur: CGPoint(x: 250, y: 670),
        ll: CGPoint(x: 54, y: 690),
        lr: CGPoint(x: 250, y: 690)
    )

    // Add multi-quad highlight
    try doc.addHighlight(pageIndex: 0, quads: [quad1, quad2], red: 1.0, green: 0.9, blue: 0.2)

    // Delete the highlight near the first quad point
    let hitPoint = CGPoint(x: 100, y: 730)
    try doc.deleteHighlight(pageIndex: 0, at: hitPoint)
}

@Test @MainActor func testNavigationHistoryAndPageJump() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_nav_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.document?.pageCount == 2)

    // Initially at page 0
    #expect(vm.currentPageIndex == 0)
    #expect(vm.canGoBack == false)
    #expect(vm.canGoForward == false)

    // Jump to page 1
    vm.jumpToPage(1)
    #expect(vm.currentPageIndex == 1)
    #expect(vm.canGoBack == true)
    #expect(vm.canGoForward == false)

    // Go back
    vm.goBack()
    #expect(vm.currentPageIndex == 0)
    #expect(vm.canGoForward == true)

    // Go forward
    vm.goForward()
    #expect(vm.currentPageIndex == 1)

    // First / Last page helpers
    vm.goToFirstPage()
    #expect(vm.currentPageIndex == 0)

    vm.goToLastPage()
    #expect(vm.currentPageIndex == 1)
}

@Test @MainActor func testZoomPresets() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_zoom_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    vm.setZoom(1.5)
    #expect(abs(vm.zoomScale - 1.5) < 0.01)

    vm.resetZoom()
    #expect(abs(vm.zoomScale - 1.0) < 0.01)

    vm.zoomToFitWidth()
    #expect(vm.zoomScale > 0.1)

    vm.zoomToFitPage()
    #expect(vm.zoomScale > 0.1)
}

@Test func testTextMarkupAndInkAnnotationModel() throws {
    // 1. Test text markup types and initialization
    let quad = PDFQuad(
        ul: CGPoint(x: 20, y: 50),
        ur: CGPoint(x: 100, y: 50),
        ll: CGPoint(x: 20, y: 70),
        lr: CGPoint(x: 100, y: 70)
    )
    let underlineAnnot = PDFAnnotation(
        pageIndex: 0,
        type: .underline,
        quads: [quad],
        color: .cyan,
        text: "Underlined"
    )
    #expect(underlineAnnot.type == .underline)
    #expect(underlineAnnot.contains(pagePoint: CGPoint(x: 50, y: 60)))

    let strikeoutAnnot = PDFAnnotation(
        pageIndex: 0,
        type: .strikeout,
        quads: [quad],
        color: .pink,
        text: "Strikethrough"
    )
    #expect(strikeoutAnnot.type == .strikeout)
    #expect(strikeoutAnnot.contains(pagePoint: CGPoint(x: 50, y: 60)))

    // 2. Test ink annotation model and hit testing
    let inkPoints = [
        CGPoint(x: 100, y: 100),
        CGPoint(x: 150, y: 100),
        CGPoint(x: 200, y: 150)
    ]
    let inkAnnot = PDFAnnotation(
        pageIndex: 0,
        type: .ink,
        inkPoints: inkPoints,
        strokeWidth: 3.0,
        color: .green
    )
    #expect(inkAnnot.type == .ink)
    #expect(!inkAnnot.boundingRect.isEmpty)
    // Hit directly on first segment (125, 100)
    #expect(inkAnnot.contains(pagePoint: CGPoint(x: 125, y: 100), tolerance: 3.0))
    // Hit within tolerance of segment
    #expect(inkAnnot.contains(pagePoint: CGPoint(x: 125, y: 102), tolerance: 3.0))
    // Far miss
    #expect(!inkAnnot.contains(pagePoint: CGPoint(x: 125, y: 150), tolerance: 3.0))

    // 3. Test CanvasMode enum
    #expect(CanvasMode.allCases.count == 7)
    #expect(CanvasMode.select.rawValue == "select")
    #expect(CanvasMode.draw.rawValue == "draw")
    #expect(CanvasMode.text.rawValue == "text")
    #expect(CanvasMode.callout.rawValue == "callout")
    #expect(CanvasMode.redact.rawValue == "redact")
    #expect(CanvasMode.eraser.rawValue == "eraser")
    #expect(CanvasMode.stamp.rawValue == "stamp")
}

@Test func testMuPDFTextMarkupAndInkPersistence() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_markup_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(doc.pageCount == 2)

    let quad = PDFQuad(
        ul: CGPoint(x: 54, y: 700),
        ur: CGPoint(x: 180, y: 700),
        ll: CGPoint(x: 54, y: 720),
        lr: CGPoint(x: 180, y: 720)
    )

    // Add Underline
    try doc.addTextMarkup(pageIndex: 0, type: .underline, quads: [quad], red: 0.2, green: 0.8, blue: 0.95)

    // Add Strikethrough
    try doc.addTextMarkup(pageIndex: 0, type: .strikeout, quads: [quad], red: 1.0, green: 0.4, blue: 0.6)

    // Add Ink stroke
    let inkPoints = [CGPoint(x: 100, y: 500), CGPoint(x: 150, y: 520), CGPoint(x: 200, y: 500)]
    try doc.addInkStroke(pageIndex: 0, points: inkPoints, strokeWidth: 2.5, red: 0.3, green: 0.85, blue: 0.4)

    // Delete annotation near ink point
    try doc.deleteAnnotation(pageIndex: 0, at: CGPoint(x: 150, y: 520))

    // Save document to ensure Fitz doesn't throw during serialization
    let savedURL = tempDir.appendingPathComponent("test_saved_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: savedURL) }
    try doc.save(to: savedURL.path)
    #expect(FileManager.default.fileExists(atPath: savedURL.path))
}

@Test func testAllMarkupPDFStandardsCompatibility() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_all_markup_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let doc = try PDFDocumentCore(filePath: pdfURL.path)

    // Highlight (Yellow: 1.0, 0.92, 0.23) at view y = 100..120
    let hlQuad = PDFQuad(
        ul: CGPoint(x: 54, y: 100),
        ur: CGPoint(x: 350, y: 100),
        ll: CGPoint(x: 54, y: 120),
        lr: CGPoint(x: 350, y: 120)
    )
    try doc.addHighlight(pageIndex: 0, quad: hlQuad, red: 1.0, green: 0.92, blue: 0.23)

    // Underline (Cyan: 0.20, 0.78, 0.95) at view y = 130..150
    let ulQuad = PDFQuad(
        ul: CGPoint(x: 54, y: 130),
        ur: CGPoint(x: 350, y: 130),
        ll: CGPoint(x: 54, y: 150),
        lr: CGPoint(x: 350, y: 150)
    )
    try doc.addTextMarkup(pageIndex: 0, type: .underline, quads: [ulQuad], red: 0.20, green: 0.78, blue: 0.95)

    // Strikeout (Red: 1.00, 0.23, 0.19) at view y = 160..180
    let soQuad = PDFQuad(
        ul: CGPoint(x: 54, y: 160),
        ur: CGPoint(x: 350, y: 160),
        ll: CGPoint(x: 54, y: 180),
        lr: CGPoint(x: 350, y: 180)
    )
    try doc.addTextMarkup(pageIndex: 0, type: .strikeout, quads: [soQuad], red: 1.00, green: 0.23, blue: 0.19)

    // FreeText (Blue: 0.00, 0.48, 1.00) at view y = 200..230
    try doc.addFreeText(pageIndex: 0, rect: CGRect(x: 54, y: 200, width: 250, height: 30), text: "Compatibility Note FreeText", fontSize: 14.0, red: 0.0, green: 0.48, blue: 1.0)

    // Ink (Purple: 0.69, 0.32, 0.87) at view y = 250..320
    let purplePoints = [CGPoint(x: 100, y: 250), CGPoint(x: 150, y: 320), CGPoint(x: 200, y: 250)]
    try doc.addInkStroke(pageIndex: 0, points: purplePoints, strokeWidth: 4.0, red: 0.69, green: 0.32, blue: 0.87)

    let savedURL = tempDir.appendingPathComponent("mupdf_saved_test_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: savedURL) }
    try doc.save(to: savedURL.path)

    let pdfData = try Data(contentsOf: savedURL)
    let pdfStr = String(decoding: pdfData, as: UTF8.self)
    #expect(pdfStr.contains("/Highlight"))
    #expect(pdfStr.contains("/Underline"))
    #expect(pdfStr.contains("/StrikeOut"))
    #expect(pdfStr.contains("/FreeText"))
    #expect(pdfStr.contains("/Ink"))
    #expect(!pdfStr.contains("/CL[")) // FreeText should not have spurious callout line

    #if canImport(PDFKit)
    if let pdfKitDoc = PDFKit.PDFDocument(url: savedURL), let page = pdfKitDoc.page(at: 0) {
        let annots = page.annotations
        #expect(annots.count == 5)
        
        let inkAnnot = annots.first(where: { $0.type == "Ink" })
        #expect(inkAnnot != nil)

        // Verify PDFKit rendering of Ink annotation produces purple pixels (no grayscale fallback)
        let rect = page.bounds(for: .mediaBox)
        let width = Int(rect.width)
        let height = Int(rect.height)
        if let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: width * 4,
            bitsPerPixel: 32
        ) {
            NSGraphicsContext.saveGraphicsState()
            if let ctx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = ctx
                ctx.cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                ctx.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
                inkAnnot?.draw(with: .mediaBox, in: ctx.cgContext)
                NSGraphicsContext.restoreGraphicsState()

                var purpleCount = 0
                var greyCount = 0
                for y in 0..<height {
                    for x in 0..<width {
                        if let col = rep.colorAt(x: x, y: y), col.redComponent < 0.98 {
                            let r = col.redComponent
                            let g = col.greenComponent
                            let b = col.blueComponent
                            if r < 0.8 && abs(r - g) < 0.05 && abs(g - b) < 0.05 {
                                greyCount += 1
                            } else if r > 0.5 && b > 0.7 && g < 0.4 {
                                purpleCount += 1
                            }
                        }
                    }
                }
                #expect(purpleCount > 0)
                #expect(greyCount == 0)
            }

            // Also verify page-level Quartz rendering (matching Apple Preview) renders all markups in full color
            NSGraphicsContext.saveGraphicsState()
            if let pageCtx = NSGraphicsContext(bitmapImageRep: rep) {
                NSGraphicsContext.current = pageCtx
                pageCtx.cgContext.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
                pageCtx.cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
                page.draw(with: .mediaBox, to: pageCtx.cgContext)
                NSGraphicsContext.restoreGraphicsState()

                var pagePurple = 0
                var pageBlue = 0
                var pageYellow = 0
                for y in 0..<height {
                    for x in 0..<width {
                        if let col = rep.colorAt(x: x, y: y) {
                            let r = col.redComponent
                            let g = col.greenComponent
                            let b = col.blueComponent
                            if r > 0.5 && b > 0.7 && g < 0.4 {
                                pagePurple += 1
                            } else if b > 0.8 && r < 0.3 {
                                pageBlue += 1
                            } else if r > 0.8 && g > 0.8 && b < 0.4 {
                                pageYellow += 1
                            }
                        }
                    }
                }
                #expect(pagePurple > 0)
                #expect(pageBlue > 0)
                #expect(pageYellow > 0)
            }
        }
    }
    #endif
}

@Test @MainActor func testViewModelMarkupAndCanvasModes() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_vm_markup_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.document != nil)

    // Canvas mode state
    #expect(vm.canvasMode == .select)
    #expect(vm.isMarkupBarVisible == false)
    #expect(vm.selectedAnnotationColor == .yellow)
    #expect(vm.drawStrokeWidth == 2.5)

    vm.isMarkupBarVisible = true
    #expect(vm.isMarkupBarVisible == true)

    vm.canvasMode = .draw
    #expect(vm.canvasMode == .draw)

    // Add ink annotation via ViewModel
    let inkPoints = [CGPoint(x: 50, y: 100), CGPoint(x: 80, y: 120)]
    let created = vm.addInkAnnotation(pageIndex: 0, points: inkPoints, strokeWidth: 3.0, color: .orange)
    #expect(created != nil)
    #expect(vm.pageAnnotations[0]?.count == 1)
    #expect(vm.pageAnnotations[0]?.first?.type == .ink)
    #expect(vm.isDocumentEdited == true)

    // Remove ink annotation
    if let annot = created {
        vm.removeAnnotation(annot)
        #expect(vm.pageAnnotations[0]?.isEmpty == true)
    }
}

@Test @MainActor func testSignatureStampAnywhere() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_sig_stamp_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    // Test SignatureStore
    let store = SignatureStore.shared
    store.clear()
    #expect(store.savedSignatureData == nil)

    let dummyImage = NSImage(size: NSSize(width: 100, height: 40))
    dummyImage.lockFocus()
    NSColor.black.setStroke()
    NSBezierPath.strokeLine(from: NSPoint(x: 10, y: 10), to: NSPoint(x: 90, y: 30))
    dummyImage.unlockFocus()
    guard let dummyData = dummyImage.pdfStampPNGData else {
        Issue.record("Failed to generate test signature PNG data")
        return
    }

    store.save(data: dummyData)
    #expect(store.savedSignatureData != nil)

    // Test PDFAnnotation model for .stamp
    let stampRect = CGRect(x: 100, y: 200, width: 140, height: 50)
    let stampAnnot = PDFAnnotation(
        pageIndex: 0,
        type: .stamp,
        rect: stampRect,
        stampImageData: dummyData
    )
    #expect(stampAnnot.type == .stamp)
    #expect(stampAnnot.boundingRect == stampRect)
    #expect(stampAnnot.contains(pagePoint: CGPoint(x: 150, y: 225)))
    #expect(!stampAnnot.contains(pagePoint: CGPoint(x: 50, y: 50)))

    // Test adding stamp annotation through PDFViewerViewModel with color
    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.document != nil)

    let addedStamp = vm.addStampAnnotation(pageIndex: 0, rect: stampRect, imageData: dummyData, color: .blue)
    #expect(addedStamp != nil)
    #expect(addedStamp?.color == .blue)
    #expect(vm.pageAnnotations[0]?.count == 1)
    #expect(vm.pageAnnotations[0]?.first?.type == .stamp)
    #expect(vm.isDocumentEdited == true)

    // Test stamp image tinting
    let tintedImage = dummyImage.tinted(with: NSColor.systemRed)
    #expect(tintedImage.size == dummyImage.size)
    guard let tintedData = tintedImage.pdfStampPNGData else {
        Issue.record("Failed to generate tinted stamp PNG data")
        return
    }
    #expect(!tintedData.isEmpty)

    let tintedStamp = vm.addStampAnnotation(pageIndex: 0, rect: stampRect, imageData: tintedData, color: .red)
    #expect(tintedStamp != nil)
    #expect(tintedStamp?.color == .red)
    #expect(vm.pageAnnotations[0]?.count == 2)

    // Save and verify document persistence
    vm.saveDocument()
    #expect(vm.isDocumentEdited == false)

    // Remove stamp annotations
    if let annot = addedStamp {
        vm.removeAnnotation(annot)
    }
    if let annot = tintedStamp {
        vm.removeAnnotation(annot)
    }
    #expect(vm.pageAnnotations[0]?.isEmpty == true)

    // Test presets & CanvasMode.stamp
    #expect(signatureFontPresets.count >= 5)
    #expect(SignatureCreationMode.allCases.count == 3)
    #expect(CanvasMode.stamp.rawValue == "stamp")

    store.clear()
}

@Test @MainActor func testTenAnnotationColorsAndIcons() async throws {
    let allColors = AnnotationColor.allCases
    #expect(allColors.count == 10)
    
    let expectedNames = ["Yellow", "Green", "Cyan", "Blue", "Purple", "Pink", "Red", "Orange", "Gray", "Black"]
    let actualNames = allColors.map(\.displayName)
    #expect(actualNames == expectedNames)

    for color in allColors {
        let (r, g, b) = color.rgb
        #expect(r >= 0.0 && r <= 1.0)
        #expect(g >= 0.0 && g <= 1.0)
        #expect(b >= 0.0 && b <= 1.0)

        let icon = color.menuIcon
        #expect(icon.size.width == 13)
        #expect(icon.size.height == 13)
        #expect(icon.isTemplate == false)
    }
}

@Test @MainActor func testFreeTextAnnotationCoreAndSerialization() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_freetext_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let doc = try PDFDocumentCore(filePath: pdfURL.path)

    let boxRect = CGRect(x: 100, y: 300, width: 200, height: 40)
    try doc.addFreeText(pageIndex: 0, rect: boxRect, text: "Sample FreeText Annotation", fontSize: 14.0, red: 0.0, green: 0.48, blue: 1.0)

    // Save document to ensure Fitz doesn't throw during FreeText serialization
    let savedURL = tempDir.appendingPathComponent("test_saved_freetext_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: savedURL) }
    try doc.save(to: savedURL.path)
    #expect(FileManager.default.fileExists(atPath: savedURL.path))

    // Verify PDF structure: FreeText exists, /DA is set, but no /C fill color array that creates solid blocks
    let pdfData = try Data(contentsOf: savedURL)
    let pdfString = String(decoding: pdfData, as: UTF8.self)
    #expect(pdfString.contains("/FreeText"))
    #expect(pdfString.contains("/Helv"))
    #expect(!pdfString.contains("/C ["))

    // Verify standard PDF reader interoperability via Apple's PDFKit (engine behind macOS Preview)
    #if canImport(PDFKit)
    if let pdfDoc = PDFKit.PDFDocument(url: savedURL), let page = pdfDoc.page(at: 0) {
        let annots = page.annotations
        let freeTextAnnot = annots.first(where: { $0.type == "FreeText" })
        #expect(freeTextAnnot != nil)
        #expect(freeTextAnnot?.contents == "Sample FreeText Annotation")
    }
    #endif

    // Reopen and ensure rendering succeeds cleanly
    let reloadedDoc = try PDFDocumentCore(filePath: savedURL.path)
    #expect(reloadedDoc.pageCount > 0)
    let renderActor = PDFRenderActor()
    try await renderActor.openDocument(filePath: savedURL.path)
    let image = try await renderActor.renderPage(pageIndex: 0, scale: 1.0).image
    #expect(image.width > 0)

    // Reopen and delete annotation near center of box
    try reloadedDoc.deleteAnnotation(pageIndex: 0, at: CGPoint(x: 150, y: 320))
    
    let savedDeletedURL = tempDir.appendingPathComponent("test_saved_deleted_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: savedDeletedURL) }
    try reloadedDoc.save(to: savedDeletedURL.path)
    #expect(FileManager.default.fileExists(atPath: savedDeletedURL.path))
}

@Test @MainActor func testViewModelFreeTextAnnotation() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_vm_freetext_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.document != nil)

    vm.canvasMode = .text
    #expect(vm.canvasMode == .text)
    #expect(vm.selectedFontSize == 13.0)

    let boxRect = CGRect(x: 120, y: 250, width: 180, height: 35)
    let created = vm.addFreeTextAnnotation(pageIndex: 0, rect: boxRect, text: "Hello VectorPDF", fontSize: 16.0, color: .purple)
    #expect(created != nil)
    #expect(vm.pageAnnotations[0]?.count == 1)
    #expect(vm.pageAnnotations[0]?.first?.type == .freeText)
    #expect(vm.pageAnnotations[0]?.first?.text == "Hello VectorPDF")
    #expect(vm.pageAnnotations[0]?.first?.fontSize == 16.0)
    #expect(vm.pageAnnotations[0]?.first?.color == .purple)
    #expect(vm.isDocumentEdited == true)

    // Test hit testing on FreeText
    if let annot = created {
        #expect(annot.contains(pagePoint: CGPoint(x: 150, y: 260)))
        #expect(!annot.contains(pagePoint: CGPoint(x: 10, y: 10)))

        vm.removeAnnotation(annot)
        #expect(vm.pageAnnotations[0]?.isEmpty == true)
    }
}

@Test @MainActor func testWindowTopBarDraggingAndControls() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_win_drag_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let window = DocumentWindowing.makeWindow(for: pdfURL)
    window.makeKeyAndOrderFront(nil)
    window.displayIfNeeded()

    #expect(window.isMovableByWindowBackground == true)
    #expect(window.titlebarAppearsTransparent == true)
    #expect(window.toolbarStyle == .unified)
    #expect(window.styleMask.contains(.fullSizeContentView))

    let titlebarHeight = window.frame.height - window.contentLayoutRect.height
    #expect(titlebarHeight > 0)

    // Add second tab to verify multi-tab state
    let doc2URL = tempDir.appendingPathComponent("test_tab2_\(UUID().uuidString).pdf")
    createSamplePDF(at: doc2URL)
    defer { try? FileManager.default.removeItem(at: doc2URL) }

    DocumentWindowing.addTab(url: doc2URL, to: window)
    window.displayIfNeeded()

    #expect(window.tabGroup?.windows.count == 2)

    // Verify clicks on titlebar / toolbar execute safely
    let topBarLocation = NSPoint(x: window.frame.width * 0.5, y: window.frame.height - 15)
    let event = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: topBarLocation,
        modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )
    if let event {
        window.sendEvent(event)
    }
}

@Test @MainActor func testTableAndFigureTargetResolution() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_table_fig_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create context")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 12)

    // Page 0: Contains references
    context.beginPDFPage(nil)
    ("See Table 1 for details." as NSString).draw(at: NSPoint(x: 100, y: 700), withAttributes: [.font: font])
    ("See Figure 2 for overview." as NSString).draw(at: NSPoint(x: 100, y: 650), withAttributes: [.font: font])
    context.endPDFPage()

    // Page 1:
    // Running header at top (y=740 in CG coordinates -> y=52 in MuPDF Fitz top-down)
    // Table 1 at y=500 in CG (y=292 in Fitz), followed by header cell "Parameter" at y=460 (y=332 in Fitz)
    // Figure 2 illustration at y=300 (y=492 in Fitz), with caption "Figure 2: Architecture diagram" at y=150 (y=642 in Fitz)
    context.beginPDFPage(nil)
    ("IEEE JOURNAL OF SELECTED TOPICS, VOL. 10" as NSString).draw(at: NSPoint(x: 100, y: 740), withAttributes: [.font: font])
    ("Table 1 - System Performance Parameters" as NSString).draw(at: NSPoint(x: 150, y: 500), withAttributes: [.font: font])
    ("Setting   Value   Description" as NSString).draw(at: NSPoint(x: 100, y: 460), withAttributes: [.font: font])
    ("[Illustration diagram box]" as NSString).draw(at: NSPoint(x: 100, y: 300), withAttributes: [.font: font])
    ("Figure 2: Architecture diagram" as NSString).draw(at: NSPoint(x: 150, y: 150), withAttributes: [.font: font])
    context.endPDFPage()
    context.closePDF()

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    guard let stext = doc.loadStructuredPage(for: 1) else {
        #expect(Bool(false), "StructuredPage must load")
        return
    }

    let selector = SpatialTextSelector()

    // 1. Table 1 target resolution: anchor is near table top (y=290 in Fitz)
    let tableTarget = selector.targetLine(on: stext, at: CGPoint(x: 90, y: 290), label: "Table 1")
    #expect(tableTarget != nil)
    #expect(tableTarget?.text.contains("Table 1") == true)
    #expect(tableTarget?.text.contains("Setting") == false)

    // 2. Figure 2 target resolution: anchor is at top of figure float (y=480 in Fitz),
    // while caption is at y=642 (162pt below anchor)
    let figTarget = selector.targetLine(on: stext, at: CGPoint(x: 90, y: 480), label: "Figure 2")
    #expect(figTarget != nil)
    #expect(figTarget?.text.contains("Figure 2") == true)
    #expect(figTarget?.text.contains("Illustration") == false)
}

@Test @MainActor func testEquationTargetResolution() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_equation_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create context")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 12)

    context.beginPDFPage(nil)
    // Left-margin line number at x=60
    ("33" as NSString).draw(at: NSPoint(x: 60, y: 500), withAttributes: [.font: font])
    // Centered equation math formula
    ("y = a * x + b" as NSString).draw(at: NSPoint(x: 200, y: 500), withAttributes: [.font: font])
    // Right-aligned equation number (27-19)
    ("(27-19)" as NSString).draw(at: NSPoint(x: 500, y: 500), withAttributes: [.font: font])
    // Explanatory prose directly below
    ("where y is the output vector and a is the gain." as NSString).draw(at: NSPoint(x: 100, y: 460), withAttributes: [.font: font])
    context.endPDFPage()
    context.closePDF()

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    guard let stext = doc.loadStructuredPage(for: 0) else {
        #expect(Bool(false), "StructuredPage must load")
        return
    }

    let selector = SpatialTextSelector()

    // Anchor placed near equation baseline / top of "where" prose
    let targetPoint = CGPoint(x: 90, y: 292) // y=500 in CG -> y=292 in Fitz
    let eqTarget = selector.targetLine(on: stext, at: targetPoint, label: "Equation (27-19)")

    #expect(eqTarget != nil)
    // Must select the equation and/or its (27-19) number, NOT the "where" prose below
    #expect(eqTarget?.text.contains("where") == false)
    #expect(eqTarget?.text.contains("33") == false) // Must not pick line number 33
    #expect(eqTarget?.text.contains("27-19") == true || eqTarget?.text.contains("y = a") == true)
}

@Test @MainActor func testSpatialSelectionBleedAndAdjacentLineSeparation() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_selection_bleed_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create context")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 12)

    context.beginPDFPage(nil)
    // Line 48: margin line number at x=40, math symbols line at x=80, y=650
    ("48" as NSString).draw(at: NSPoint(x: 40, y: 650), withAttributes: [.font: font])
    ("Nr, Nc, Nr, Nc parameters" as NSString).draw(at: NSPoint(x: 80, y: 650), withAttributes: [.font: font])

    // Line 49: margin line number at x=40, body text at x=80, y=630
    ("49" as NSString).draw(at: NSPoint(x: 40, y: 630), withAttributes: [.font: font])
    ("number of rows and columns, respectively" as NSString).draw(at: NSPoint(x: 80, y: 630), withAttributes: [.font: font])
    context.endPDFPage()
    context.closePDF()

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    guard let stext = doc.loadStructuredPage(for: 0) else {
        #expect(Bool(false), "StructuredPage must load")
        return
    }

    let selector = SpatialTextSelector()

    // 1. Text selection on line 49 must not bleed math symbols from line 48
    let result = selector.selectText(on: stext, from: CGPoint(x: 80, y: 162), to: CGPoint(x: 250, y: 162))
    #expect(result.text.contains("number of rows and columns"))
    #expect(!result.text.contains("Nr"))
    #expect(!result.text.contains("Nc"))

    // 2. Double-click word selection on "number"
    if let wordSel = selector.selectWord(at: CGPoint(x: 95, y: 162), on: stext) {
        #expect(wordSel.text == "number")
        #expect(!wordSel.highlightQuads.isEmpty)
    }

    // 3. Triple-click line selection on line 49
    if let lineSel = selector.selectLine(at: CGPoint(x: 95, y: 162), on: stext) {
        #expect(lineSel.text.contains("number of rows and columns"))
        #expect(!lineSel.text.contains("Nr"))
    }
}

@Test @MainActor func testDeterministicAnchorHeadingAndGutterResolution() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_anchor_heading_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create context")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 12)
    let boldFont = NSFont.boldSystemFont(ofSize: 14)

    context.beginPDFPage(nil)
    // Section Heading at y=700, margin line number 48 at x=40
    ("48" as NSString).draw(at: NSPoint(x: 40, y: 700), withAttributes: [.font: font])
    ("19.3.12.3.6 Compressed beamforming feedback matrix" as NSString).draw(at: NSPoint(x: 80, y: 700), withAttributes: [.font: boldFont])

    // Body Line at y=660, margin line number 49 at x=40
    ("49" as NSString).draw(at: NSPoint(x: 40, y: 660), withAttributes: [.font: font])
    ("number of rows and columns, respectively" as NSString).draw(at: NSPoint(x: 80, y: 660), withAttributes: [.font: font])
    context.endPDFPage()
    context.closePDF()

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    vm.document?.outline = [
        PDFOutlineNode(title: "19.3.12.3.6 Compressed beamforming feedback matrix", uri: nil, targetPage: 0)
    ]

    // Heading Anchor: deterministic outline matching, excludes line number 48
    let headingAnchor = vm.buildSnapshotTarget(at: CGPoint(x: 100, y: 92), pageIndex: 0)
    #expect(headingAnchor.label == "19.3.12.3.6 Compressed beamforming feedback matrix")
    #expect(headingAnchor.snippet == "19.3.12.3.6 Compressed beamforming feedback matrix")
    #expect(!headingAnchor.label.contains("48"))

    // Body Anchor: extracts body words, strictly excludes line number 49
    let bodyAnchor = vm.buildSnapshotTarget(at: CGPoint(x: 100, y: 132), pageIndex: 0)
    #expect(bodyAnchor.label.contains("number of rows and columns"))
    #expect(!bodyAnchor.label.contains("49"))

    // Margin click: skips gutter line number and anchors to the body text
    let marginAnchor = vm.buildSnapshotTarget(at: CGPoint(x: 42, y: 132), pageIndex: 0)
    #expect(marginAnchor.label.contains("number of rows and columns"))
    #expect(!marginAnchor.label.contains("49"))
}

@Test @MainActor func testPageManipulationMarksDocumentDirtyAndSavesOnDemand() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_dirty_tracking_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    // Create 3-page test PDF
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create context")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 14)
    for i in 1...3 {
        context.beginPDFPage(nil)
        ("Page \(i) content" as NSString).draw(at: NSPoint(x: 72, y: 700), withAttributes: [.font: font])
        context.endPDFPage()
    }
    context.closePDF()

    let originalData = try Data(contentsOf: pdfURL)

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.isDocumentEdited == false)

    // 1. Rotate Page 0: marks document dirty, but original file on disk is NOT touched yet
    vm.rotatePage(0, by: 90)
    #expect(vm.isDocumentEdited == true)

    let fileDataDuringEdit = try Data(contentsOf: pdfURL)
    #expect(fileDataDuringEdit == originalData) // Disk file was NOT overwritten!

    // 2. Explicit Save: writes changes to disk and clears isDocumentEdited
    vm.saveDocument()
    #expect(vm.isDocumentEdited == false)

    let fileDataAfterSave = try Data(contentsOf: pdfURL)
    #expect(fileDataAfterSave != originalData) // Disk file has now been updated!

    // 3. Delete Page 1: marks document dirty, disk file unchanged until save
    let dataBeforeDelete = try Data(contentsOf: pdfURL)
    vm.deletePage(1)
    #expect(vm.isDocumentEdited == true)

    let fileDataDuringDelete = try Data(contentsOf: pdfURL)
    #expect(fileDataDuringDelete == dataBeforeDelete)

    // 4. Save updates disk and verifies page count
    vm.saveDocument()
    #expect(vm.isDocumentEdited == false)
    let reloadedDoc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(reloadedDoc.pageCount == 2)
}

@Test @MainActor func testViewModelWordSelectionAndTranslation() async throws {
    let vm = PDFViewerViewModel()
    let selResult = SelectionResult(
        text: "Bonjour le monde",
        highlightQuads: [PDFQuad(ul: .zero, ur: CGPoint(x: 100, y: 0), ll: CGPoint(x: 0, y: 20), lr: CGPoint(x: 100, y: 20))],
        boundingRect: CGRect(x: 0, y: 0, width: 100, height: 20),
        mode: .readingOrder
    )
    vm.activeSelection = (pageIndex: 0, result: selResult)
    #expect(vm.activeSelectionCombinedText == "Bonjour le monde")

    vm.translateSelection()
    #expect(vm.translationTargetText == "Bonjour le monde")
    #expect(vm.isPresentingTranslation == true)
}

@Test @MainActor func testPageManipulationOperations() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let pdfURL = tempDir.appendingPathComponent("manipulation_test.pdf")

    // Create 3-page PDF
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create test PDF")
    }
    for i in 1...3 {
        context.beginPDFPage(nil)
        let text = "Page \(i) Content"
        (text as NSString).draw(at: NSPoint(x: 100, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        context.endPDFPage()
    }
    context.closePDF()

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(doc.pageCount == 3)
    let origWidth = doc.pageBounds[0].width
    let origHeight = doc.pageBounds[0].height
    #expect(origWidth == 612)
    #expect(origHeight == 792)

    // 1. Rotate Page 0 by 90 degrees
    try doc.rotatePage(0, by: 90)
    #expect(doc.pageBounds[0].width == 792)
    #expect(doc.pageBounds[0].height == 612)

    // 2. Extract Pages 0 and 2
    let extractURL = tempDir.appendingPathComponent("extracted.pdf")
    try doc.extractPages([0, 2], to: extractURL)
    let extractDoc = try PDFDocumentCore(filePath: extractURL.path)
    #expect(extractDoc.pageCount == 2)

    // 3. Delete Page 1
    try doc.deletePage(1)
    #expect(doc.pageCount == 2)

    // 4. Reorder Page 0 to 1
    try doc.reorderPage(from: 0, to: 1)
    #expect(doc.pageCount == 2)

    // 5. Save and reload
    try doc.save(to: pdfURL.path)
    let reloadedDoc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(reloadedDoc.pageCount == 2)
}

@Test @MainActor func testPhysicalScaleAndEffectiveZoom() throws {
    let coordinator = PDFViewerAppCoordinator.shared
    
    // Save previous scale mode to restore at defer
    let originalMode = coordinator.scaleMode
    defer { coordinator.scaleMode = originalMode }

    // 1. physicalScale calculation
    let scale = PDFViewerAppCoordinator.physicalScale(for: NSScreen.main)
    #expect(scale > 0.5 && scale < 5.0)

    let vm = PDFViewerViewModel()
    vm.displayScale = 1.770833 // Typical 14"/16" MacBook Retina physical scale factor
    vm.zoomScale = 1.0

    // In physical scale mode (Apple Preview default), effectiveZoom matches displayScale * zoomScale
    coordinator.scaleMode = .physical
    #expect(abs(vm.effectiveZoom - 1.770833) < 0.0001)

    // At 200% zoom
    vm.zoomScale = 2.0
    #expect(abs(vm.effectiveZoom - (1.770833 * 2.0)) < 0.0001)

    // In point-to-point mode (72 DPI, 1 pt = 1 pt)
    coordinator.scaleMode = .pointToPoint
    vm.zoomScale = 1.0
    #expect(abs(vm.effectiveZoom - 1.0) < 0.0001)

    vm.zoomScale = 0.5
    #expect(abs(vm.effectiveZoom - 0.5) < 0.0001)
}

@Test @MainActor func testSupersampledRenderScaleAtSmallZooms() async throws {
    let coordinator = PDFViewerAppCoordinator.shared
    let originalMode = coordinator.scaleMode
    defer { coordinator.scaleMode = originalMode }

    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_zoom_render_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    vm.displayScale = 1.0
    coordinator.scaleMode = .pointToPoint

    // When zoom is very small (e.g. 0.25 on a 1x display, targetScale = 0.25),
    // targetScale is below the 1.5 floor. The render engine enforces max(targetScale, 1.5)
    // to preserve font stem sharpness and prevent stroke collapse.
    vm.zoomScale = 0.25
    let smallTargetScale = vm.effectiveZoom * 1.0
    let enforcedRenderScale = max(smallTargetScale, 1.5)
    #expect(enforcedRenderScale == 1.5)

    // At 100% zoom with Retina 2.0 backing scale, targetScale = 2.0 >= 1.5
    let retinaTargetScale = 1.0 * 2.0
    let normalRenderScale = max(retinaTargetScale, 1.5)
    #expect(normalRenderScale == 2.0)
}

@Test @MainActor func testLineNumberGutterDetection() {
    let dummyQuad = PDFQuad(ul: .zero, ur: .zero, ll: .zero, lr: .zero)
    func makeLine(text: String, bbox: CGRect) -> TextLine {
        let chars = text.map { TextCharacter(char: $0, quad: dummyQuad, origin: .zero, size: 10) }
        return TextLine(bbox: bbox, characters: chars)
    }

    let bodyLeftMargin: CGFloat = 72.0

    // 1. Genuine line numbers in left gutter: numeric only, width < 45, x in gutter
    let lineNum1 = makeLine(text: "1", bbox: CGRect(x: 36, y: 100, width: 10, height: 12))
    let lineNum2 = makeLine(text: "42", bbox: CGRect(x: 40, y: 200, width: 16, height: 12))
    let lineNumWithDot = makeLine(text: "15.", bbox: CGRect(x: 38, y: 300, width: 18, height: 12))

    #expect(SpatialTextSelector.isLineNumberGutter(line: lineNum1, bodyLeftMargin: bodyLeftMargin) == true)
    #expect(SpatialTextSelector.isLineNumberGutter(line: lineNum2, bodyLeftMargin: bodyLeftMargin) == true)
    #expect(SpatialTextSelector.isLineNumberGutter(line: lineNumWithDot, bodyLeftMargin: bodyLeftMargin) == true)

    // 2. Real body content (equations, section headers, short text words) must NEVER be flagged as line numbers
    let bodyText = makeLine(text: "Introduction", bbox: CGRect(x: 72, y: 100, width: 120, height: 14))
    let equation = makeLine(text: "y = 2x + 1", bbox: CGRect(x: 72, y: 150, width: 180, height: 14))
    let sectionNum = makeLine(text: "1.2", bbox: CGRect(x: 72, y: 180, width: 24, height: 14))
    let equationNum = makeLine(text: "(1)", bbox: CGRect(x: 500, y: 150, width: 20, height: 14))

    #expect(SpatialTextSelector.isLineNumberGutter(line: bodyText, bodyLeftMargin: bodyLeftMargin) == false)
    #expect(SpatialTextSelector.isLineNumberGutter(line: equation, bodyLeftMargin: bodyLeftMargin) == false)
    #expect(SpatialTextSelector.isLineNumberGutter(line: sectionNum, bodyLeftMargin: bodyLeftMargin) == false)
    #expect(SpatialTextSelector.isLineNumberGutter(line: equationNum, bodyLeftMargin: bodyLeftMargin) == false)
}

@Test @MainActor func testRomanNumeralTableTargetResolution() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_roman_table_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create context")
    }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    let font = NSFont.systemFont(ofSize: 12)

    context.beginPDFPage(nil)
    // Left-margin line number 1 at x=40
    ("1" as NSString).draw(at: NSPoint(x: 40, y: 650), withAttributes: [.font: font])
    // Prose containing "table" and "i"
    ("In this table it is critical to observe the system results." as NSString).draw(at: NSPoint(x: 80, y: 650), withAttributes: [.font: font])
    // Left-margin line number 2 at x=40
    ("2" as NSString).draw(at: NSPoint(x: 40, y: 600), withAttributes: [.font: font])
    // Actual table title: TABLE I
    ("TABLE I: Execution Performance Benchmarks" as NSString).draw(at: NSPoint(x: 80, y: 600), withAttributes: [.font: font])
    context.endPDFPage()
    context.closePDF()

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    guard let stext = doc.loadStructuredPage(for: 0) else {
        #expect(Bool(false), "StructuredPage must load")
        return
    }

    let selector = SpatialTextSelector()
    // Target "Table I"
    let target = selector.targetLine(on: stext, at: CGPoint(x: 80, y: 192), label: "Table I")
    #expect(target != nil)
    #expect(target?.text.contains("TABLE I") == true)
    #expect(target?.text.contains("critical") == false) // Must not match the prose line with "table it is"
    #expect((target?.bbox.minX ?? 0) >= 70) // Must not be on margin line numbers
}

@Test @MainActor func testMultiLineTextSelectionSnapshotTargetRect() {
    let q1 = PDFQuad(
        ul: CGPoint(x: 72, y: 100), ur: CGPoint(x: 300, y: 100),
        ll: CGPoint(x: 72, y: 114), lr: CGPoint(x: 300, y: 114)
    )
    let q2 = PDFQuad(
        ul: CGPoint(x: 72, y: 120), ur: CGPoint(x: 280, y: 120),
        ll: CGPoint(x: 72, y: 134), lr: CGPoint(x: 280, y: 134)
    )
    let q3 = PDFQuad(
        ul: CGPoint(x: 350, y: 100), ur: CGPoint(x: 550, y: 100),
        ll: CGPoint(x: 350, y: 114), lr: CGPoint(x: 550, y: 114)
    )

    let selResult = SelectionResult(
        text: "Line 1 in col 1\nLine 2 in col 1\nLine 1 in col 2",
        highlightQuads: [q1, q2, q3],
        boundingRect: CGRect(x: 72, y: 100, width: 478, height: 34),
        mode: .readingOrder
    )

    let vm = PDFViewerViewModel()
    vm.activeSelection = (pageIndex: 0, result: selResult)

    // Snapshot from selection must focus on the first line rather than the full multi-column union
    let target = vm.buildSnapshotTargetFromSelection()
    #expect(target != nil)
    #expect(target?.label == "Line 1 in col 1")
    #expect(target?.targetRect != nil)
    // First line width should be ~228pt (300 - 72), not 478pt across both columns!
    #expect((target?.targetRect?.width ?? 0) <= 250)
    #expect(target?.targetRect?.minX == 72)

    // Area selection label fallback
    let areaResult = SelectionResult(
        text: "",
        highlightQuads: [],
        boundingRect: CGRect(x: 100, y: 100, width: 200, height: 150),
        mode: .rectangularArea
    )
    vm.activeSelection = (pageIndex: 2, result: areaResult)
    let areaTarget = vm.buildSnapshotTargetFromSelection()
    #expect(areaTarget?.label == "Area Anchor (Page 3)")

    // Empty reading order selection label fallback
    let emptyReadingResult = SelectionResult(
        text: "",
        highlightQuads: [],
        boundingRect: CGRect(x: 100, y: 100, width: 50, height: 12),
        mode: .readingOrder
    )
    vm.activeSelection = (pageIndex: 4, result: emptyReadingResult)
    let emptyReadingTarget = vm.buildSnapshotTargetFromSelection()
    #expect(emptyReadingTarget?.label == "Anchor (Page 5)")
}

@Test @MainActor func testResolvedTargetRectAvoidsGutterAndAddsPadding() {
    let vm = PDFViewerViewModel()
    // Create a snapshot target with point near (0, 0)
    let snapNearOrigin = SnapshotTarget(
        label: "Top Bookmark",
        targetPage: 0,
        targetPoint: CGPoint(x: 0, y: 0),
        sourcePage: 0
    )
    let resolved = vm.resolvedTargetRect(for: snapNearOrigin)
    // Fallback or resolved rect must never be in margin gutter (< 48pt)
    #expect(resolved.minX >= 48)

    // Snapshot target with explicit text targetRect gets breathable padding
    let rawRect = CGRect(x: 100, y: 200, width: 150, height: 20)
    let snapText = SnapshotTarget(
        label: "Search Hit",
        targetPage: 0,
        targetPoint: CGPoint(x: 175, y: 210),
        targetRect: rawRect,
        sourcePage: 0
    )
    let padded = vm.resolvedTargetRect(for: snapText)
    #expect(padded.minX < rawRect.minX) // Has horizontal expansion padding
    #expect(padded.minY < rawRect.minY) // Has vertical expansion padding
    #expect(padded.width > rawRect.width)
}

@Test @MainActor func testSnapshotJumpTokenIncrementsOnEveryJump() {
    let vm = PDFViewerViewModel()
    let initialToken = vm.snapshotJumpToken
    let snap = SnapshotTarget(
        label: "Test",
        targetPage: 0,
        sourcePage: 0
    )
    vm.jumpToSnapshot(snap)
    #expect(vm.snapshotJumpToken == initialToken + 1)
    vm.jumpToSnapshot(snap)
    #expect(vm.snapshotJumpToken == initialToken + 2)
}

@Test @MainActor func testLinkClickOnMouseUpAndDragSelection() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_link_mouseup_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 1000), styleMask: [.borderless], backing: .buffered, defer: false)
    let canvas = PDFCanvasView(viewModel: vm)
    canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)
    window.contentView = canvas

    guard let pFrame = canvas.pageFrame(for: 0), let doc = vm.document else {
        Issue.record("Missing pageFrame or document")
        return
    }
    let pBounds = doc.pageBounds[0]

    // Create an internal link target on page 0 pointing to page 1
    let linkSourceRect = CGRect(x: pBounds.minX + 50, y: pBounds.minY + 50, width: 100, height: 20)
    let linkTarget = SnapshotTarget(
        label: "Section 2",
        targetPage: 1,
        targetPoint: CGPoint(x: 100, y: 100),
        sourceRect: linkSourceRect,
        sourcePage: 0
    )
    vm.pageLinks[0] = [linkTarget]

    // Canvas coordinates corresponding to the link sourceRect center
    let canvasClickPoint = CGPoint(
        x: pFrame.minX + (linkSourceRect.midX - pBounds.minX) * vm.effectiveZoom,
        y: pFrame.minY + (linkSourceRect.midY - pBounds.minY) * vm.effectiveZoom
    )
    let windowClickLocation = canvas.convert(canvasClickPoint, to: nil)

    let mouseDownEvent = NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: windowClickLocation,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 1.0
    )!

    // 1. Mouse down over the link: should NOT trigger jump immediately
    canvas.mouseDown(with: mouseDownEvent)
    #expect(vm.activeSnapshotTarget == nil)

    // 2. Mouse up at the same point: SHOULD trigger jump
    let mouseUpEvent = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowClickLocation,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 2,
        clickCount: 1,
        pressure: 0.0
    )!
    canvas.mouseUp(with: mouseUpEvent)
    #expect(vm.activeSnapshotTarget?.id == linkTarget.id)

    // Reset active snapshot target
    vm.activeSnapshotTarget = nil

    // 3. Mouse down over the link, then DRAG past threshold: should cancel link jump and start drag selection
    canvas.mouseDown(with: mouseDownEvent)
    #expect(vm.activeSnapshotTarget == nil)

    let dragPoint = CGPoint(x: canvasClickPoint.x + 50, y: canvasClickPoint.y)
    let windowDragLocation = canvas.convert(dragPoint, to: nil)
    let mouseDraggedEvent = NSEvent.mouseEvent(
        with: .leftMouseDragged,
        location: windowDragLocation,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 3,
        clickCount: 1,
        pressure: 1.0
    )!
    canvas.mouseDragged(with: mouseDraggedEvent)

    // Mouse up after dragging: link jump must NOT be triggered
    let mouseUpAfterDragEvent = NSEvent.mouseEvent(
        with: .leftMouseUp,
        location: windowDragLocation,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 4,
        clickCount: 1,
        pressure: 0.0
    )!
    canvas.mouseUp(with: mouseUpAfterDragEvent)
    #expect(vm.activeSnapshotTarget == nil)
}

@Test @MainActor func testSegmentedControlTooltipsApplied() {
    let seg = NSSegmentedControl(labels: ["One", "Two", "Three"], trackingMode: .selectOne, target: nil, action: nil)
    #expect(seg.segmentCount == 3)
    let tooltips = ["Outline & Thumbnails", "Search Document (Cmd+F)", "Anchors"]
    SegmentedControlTooltipAccessor.applyTooltips(tooltips, to: seg)

    #expect(seg.toolTip(forSegment: 0) == "Outline & Thumbnails")
    #expect(seg.toolTip(forSegment: 1) == "Search Document (Cmd+F)")
    #expect(seg.toolTip(forSegment: 2) == "Anchors")
}

@Test func testThumbnailDropLogicCalculation() {
    // 4-page document: pages 0, 1, 2, 3 (display as 1, 2, 3, 4)
    // Dragging Page 1 (index 0) forward:
    #expect(ThumbnailDropLogic.isValidSlot(slot: 0, fromIndex: 0) == false) // before page 1 -> no-op
    #expect(ThumbnailDropLogic.isValidSlot(slot: 1, fromIndex: 0) == false) // between 1 and 2 -> no-op
    #expect(ThumbnailDropLogic.isValidSlot(slot: 2, fromIndex: 0) == true)  // between 2 and 3
    #expect(ThumbnailDropLogic.isValidSlot(slot: 3, fromIndex: 0) == true)  // between 3 and 4
    #expect(ThumbnailDropLogic.isValidSlot(slot: 4, fromIndex: 0) == true)  // after 4 (at end)

    #expect(ThumbnailDropLogic.destinationIndex(from: 0, slot: 0) == nil)
    #expect(ThumbnailDropLogic.destinationIndex(from: 0, slot: 1) == nil)
    #expect(ThumbnailDropLogic.destinationIndex(from: 0, slot: 2) == 1) // becomes Page 2
    #expect(ThumbnailDropLogic.destinationIndex(from: 0, slot: 3) == 2) // becomes Page 3
    #expect(ThumbnailDropLogic.destinationIndex(from: 0, slot: 4) == 3) // becomes Page 4

    // Badge labels when dragging Page 1 forward:
    #expect(ThumbnailDropLogic.slotLabel(slot: 2, fromIndex: 0, pageCount: 4) == "Move to Page 2")
    #expect(ThumbnailDropLogic.slotLabel(slot: 3, fromIndex: 0, pageCount: 4) == "Move to Page 3")
    #expect(ThumbnailDropLogic.slotLabel(slot: 4, fromIndex: 0, pageCount: 4) == "Move to Page 4")

    // Dragging Page 4 (index 3) backward:
    #expect(ThumbnailDropLogic.isValidSlot(slot: 0, fromIndex: 3) == true)  // before page 1
    #expect(ThumbnailDropLogic.isValidSlot(slot: 1, fromIndex: 3) == true)  // between 1 and 2
    #expect(ThumbnailDropLogic.isValidSlot(slot: 2, fromIndex: 3) == true)  // between 2 and 3
    #expect(ThumbnailDropLogic.isValidSlot(slot: 3, fromIndex: 3) == false) // between 3 and 4 -> no-op
    #expect(ThumbnailDropLogic.isValidSlot(slot: 4, fromIndex: 3) == false) // after 4 -> no-op

    #expect(ThumbnailDropLogic.destinationIndex(from: 3, slot: 0) == 0) // becomes Page 1
    #expect(ThumbnailDropLogic.destinationIndex(from: 3, slot: 1) == 1) // becomes Page 2
    #expect(ThumbnailDropLogic.destinationIndex(from: 3, slot: 2) == 2) // becomes Page 3
    #expect(ThumbnailDropLogic.destinationIndex(from: 3, slot: 3) == nil)
    #expect(ThumbnailDropLogic.destinationIndex(from: 3, slot: 4) == nil)

    // Badge labels when dragging Page 4 backward:
    #expect(ThumbnailDropLogic.slotLabel(slot: 0, fromIndex: 3, pageCount: 4) == "Move to Page 1")
    #expect(ThumbnailDropLogic.slotLabel(slot: 1, fromIndex: 3, pageCount: 4) == "Move to Page 2")
    #expect(ThumbnailDropLogic.slotLabel(slot: 2, fromIndex: 3, pageCount: 4) == "Move to Page 3")

    // When no drag is active (fromIndex == nil), no slot is valid:
    #expect(ThumbnailDropLogic.isValidSlot(slot: 0, fromIndex: nil) == false)
    #expect(ThumbnailDropLogic.isValidSlot(slot: 1, fromIndex: nil) == false)
    #expect(ThumbnailDropLogic.isValidSlot(slot: 2, fromIndex: nil) == false)
}

@Test @MainActor func testThumbnailDragLifecycle() {
    let vm = PDFViewerViewModel()
    #expect(vm.draggedThumbnailPageIndex == nil)
    #expect(vm.activeThumbnailDropSlot == nil)

    vm.startThumbnailDrag(pageIndex: 2)
    #expect(vm.draggedThumbnailPageIndex == 2)

    vm.activeThumbnailDropSlot = 4
    #expect(vm.activeThumbnailDropSlot == 4)

    vm.endThumbnailDrag()
    #expect(vm.draggedThumbnailPageIndex == nil)
    #expect(vm.activeThumbnailDropSlot == nil)

    // Idempotent cleanups
    vm.endThumbnailDrag()
    #expect(vm.draggedThumbnailPageIndex == nil)
    #expect(vm.activeThumbnailDropSlot == nil)
}

@Test func testThumbnailDropLogicMultiPage() {
    let pageCount = 6

    // Contiguous selection S = {2, 3} (Pages 3 and 4)
    let sContig: Set<Int> = [2, 3]
    // In-place / inside slots are no-ops:
    #expect(ThumbnailDropLogic.isValidSlot(slot: 2, fromIndices: sContig, pageCount: pageCount) == false)
    #expect(ThumbnailDropLogic.isValidSlot(slot: 3, fromIndices: sContig, pageCount: pageCount) == false)
    #expect(ThumbnailDropLogic.isValidSlot(slot: 4, fromIndices: sContig, pageCount: pageCount) == false)

    // Moving to beginning (slot 0):
    #expect(ThumbnailDropLogic.isValidSlot(slot: 0, fromIndices: sContig, pageCount: pageCount) == true)
    #expect(ThumbnailDropLogic.destinationIndex(fromIndices: sContig, slot: 0, pageCount: pageCount) == 0)
    #expect(ThumbnailDropLogic.slotLabel(slot: 0, fromIndices: sContig, pageCount: pageCount) == "Move 2 Pages to Page 1")

    // Moving between page 1 and 2 (slot 1):
    #expect(ThumbnailDropLogic.isValidSlot(slot: 1, fromIndices: sContig, pageCount: pageCount) == true)
    #expect(ThumbnailDropLogic.destinationIndex(fromIndices: sContig, slot: 1, pageCount: pageCount) == 1)
    #expect(ThumbnailDropLogic.slotLabel(slot: 1, fromIndices: sContig, pageCount: pageCount) == "Move 2 Pages to Page 2")

    // Moving to end of document (slot 6):
    #expect(ThumbnailDropLogic.isValidSlot(slot: 6, fromIndices: sContig, pageCount: pageCount) == true)
    #expect(ThumbnailDropLogic.destinationIndex(fromIndices: sContig, slot: 6, pageCount: pageCount) == 4)
    #expect(ThumbnailDropLogic.slotLabel(slot: 6, fromIndices: sContig, pageCount: pageCount) == "Move 2 Pages to Page 5")

    // Non-contiguous selection S = {0, 3}: moving them together at slot 0 moves page 3 to index 1
    let sNonContig: Set<Int> = [0, 3]
    #expect(ThumbnailDropLogic.isValidSlot(slot: 0, fromIndices: sNonContig, pageCount: pageCount) == true)
    #expect(ThumbnailDropLogic.isValidSlot(slot: 2, fromIndices: sNonContig, pageCount: pageCount) == true)
    #expect(ThumbnailDropLogic.destinationIndex(fromIndices: sNonContig, slot: 2, pageCount: pageCount) == 1)

    // Empty selection
    #expect(ThumbnailDropLogic.isValidSlot(slot: 0, fromIndices: [], pageCount: pageCount) == false)
    #expect(ThumbnailDropLogic.destinationIndex(fromIndices: [], slot: 0, pageCount: pageCount) == nil)
}

@Test @MainActor func testMultiPageSelectionAndDragLifecycle() {
    let vm = PDFViewerViewModel()

    // Initial state
    #expect(vm.selectedThumbnailPageIndices == [0])
    #expect(vm.draggedThumbnailPageIndices.isEmpty)

    // Select single thumbnail
    vm.selectThumbnail(pageIndex: 2, isShift: false, isCommand: false)
    #expect(vm.selectedThumbnailPageIndices == [2])
    #expect(vm.currentPageIndex == 2)

    // Shift-click range from 2 to 5
    vm.selectThumbnail(pageIndex: 5, isShift: true, isCommand: false)
    #expect(vm.selectedThumbnailPageIndices == Set([2, 3, 4, 5]))
    #expect(vm.currentPageIndex == 5)

    // Shift-click range from anchor 2 to 3 narrows selection
    vm.selectThumbnail(pageIndex: 3, isShift: true, isCommand: false)
    #expect(vm.selectedThumbnailPageIndices == Set([2, 3]))

    // Command-click adds page 7
    vm.selectThumbnail(pageIndex: 7, isShift: false, isCommand: true)
    #expect(vm.selectedThumbnailPageIndices == Set([2, 3, 7]))

    // Command-click removes page 3
    vm.selectThumbnail(pageIndex: 3, isShift: false, isCommand: true)
    #expect(vm.selectedThumbnailPageIndices == Set([2, 7]))

    // Dragging an already-selected thumbnail (e.g. 7) drags the whole selection
    vm.startThumbnailDrag(pageIndex: 7)
    #expect(vm.draggedThumbnailPageIndices == Set([2, 7]))
    #expect(vm.draggedThumbnailPageIndex == 7)

    // End drag cleans up both
    vm.endThumbnailDrag()
    #expect(vm.draggedThumbnailPageIndices.isEmpty)
    #expect(vm.draggedThumbnailPageIndex == nil)

    // Dragging an unselected thumbnail (e.g. 1) collapses selection and drags just that thumbnail
    vm.startThumbnailDrag(pageIndex: 1)
    #expect(vm.selectedThumbnailPageIndices == Set([1]))
    #expect(vm.draggedThumbnailPageIndices == Set([1]))
    #expect(vm.draggedThumbnailPageIndex == 1)

    vm.endThumbnailDrag()
    #expect(vm.draggedThumbnailPageIndices.isEmpty)
    #expect(vm.draggedThumbnailPageIndex == nil)
}

@Test @MainActor func testMultiPageManipulationCore() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let pdfURL = tempDir.appendingPathComponent("bulk_test.pdf")

    // Create 5-page PDF
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create test PDF")
    }
    for i in 1...5 {
        context.beginPDFPage(nil)
        let text = "Page \(i) Content"
        (text as NSString).draw(at: NSPoint(x: 100, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        context.endPDFPage()
    }
    context.closePDF()

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(doc.pageCount == 5)

    // Test multi-page reorder: move pages 1 and 2 to slot 0 (beginning)
    try doc.reorderPages(from: [1, 2], toSlot: 0)
    #expect(doc.pageCount == 5)

    // Test multi-page rotate: rotate pages 0 and 1 by 90 degrees
    try doc.rotatePages([0, 1], by: 90)
    #expect(doc.pageCount == 5)

    // Test multi-page delete: delete pages 3 and 4
    try doc.deletePages([3, 4])
    #expect(doc.pageCount == 3)

    // Guard against deleting all pages
    #expect(throws: Error.self) {
        try doc.deletePages([0, 1, 2])
    }
}

@Test @MainActor func testDuplicatePagesCore() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let pdfURL = tempDir.appendingPathComponent("dup_test.pdf")

    // Create 3-page PDF
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create test PDF")
    }
    for i in 1...3 {
        context.beginPDFPage(nil)
        let text = "Page \(i) Content"
        (text as NSString).draw(at: NSPoint(x: 100, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        context.endPDFPage()
    }
    context.closePDF()

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    #expect(doc.pageCount == 3)

    // Duplicate single page (page 0) -> should be inserted at slot 1, making 4 pages total
    let (slot1, count1) = try doc.duplicatePages([0])
    #expect(slot1 == 1)
    #expect(count1 == 1)
    #expect(doc.pageCount == 4)

    // Duplicate multiple pages (pages 1 and 2) -> max index is 2, inserted at slot 3
    let (slot2, count2) = try doc.duplicatePages([1, 2])
    #expect(slot2 == 3)
    #expect(count2 == 2)
    #expect(doc.pageCount == 6)
}

@Test @MainActor func testImportPagesFromExternalPDF() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let primaryURL = tempDir.appendingPathComponent("primary.pdf")
    let externalURL = tempDir.appendingPathComponent("external.pdf")

    // Create 2-page primary PDF
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let ctxA = CGContext(primaryURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create primary PDF")
    }
    for i in 1...2 {
        ctxA.beginPDFPage(nil)
        let text = "Primary Page \(i)"
        (text as NSString).draw(at: NSPoint(x: 100, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        ctxA.endPDFPage()
    }
    ctxA.closePDF()

    // Create 3-page external PDF
    guard let ctxB = CGContext(externalURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create external PDF")
    }
    for i in 1...3 {
        ctxB.beginPDFPage(nil)
        let text = "External Page \(i)"
        (text as NSString).draw(at: NSPoint(x: 100, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 14)])
        ctxB.endPDFPage()
    }
    ctxB.closePDF()

    let docA = try PDFDocumentCore(filePath: primaryURL.path)
    #expect(docA.pageCount == 2)

    // Import external PDF at slot 1 (between page 0 and 1)
    let (slot, importedCount) = try docA.importPages(from: externalURL, atSlot: 1)
    #expect(slot == 1)
    #expect(importedCount == 3)
    #expect(docA.pageCount == 5)
}

@Test @MainActor func testQuickAnchorShortcut() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let pdfURL = tempDir.appendingPathComponent("anchor_test.pdf")
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create test PDF")
    }
    context.beginPDFPage(nil)
    let text = "Sample Chapter 1 Heading"
    (text as NSString).draw(at: NSPoint(x: 100, y: 700), withAttributes: [.font: NSFont.systemFont(ofSize: 18)])
    context.endPDFPage()
    context.closePDF()

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.activeSnapshots.isEmpty)

    // Call quick anchor shortcut
    vm.addAnchorForCurrentPage()
    #expect(!vm.activeSnapshots.isEmpty)
    #expect(vm.activeSnapshots.first?.targetPage == 0)
}

@Test @MainActor func testAnchorsMenuCoordinatorReactivity() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let pdfURL = tempDir.appendingPathComponent("reactivity_test.pdf")
    var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, nil) else {
        fatalError("Failed to create test PDF")
    }
    context.beginPDFPage(nil)
    context.endPDFPage()
    context.closePDF()

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    PDFViewerAppCoordinator.shared.registerActive(vm)

    #expect(PDFViewerAppCoordinator.shared.activeAnchors.isEmpty)

    // Add anchor
    vm.addAnchorForCurrentPage()
    #expect(!vm.activeSnapshots.isEmpty)
    #expect(PDFViewerAppCoordinator.shared.activeAnchors.count == 1)

    // Clear anchors
    vm.clearAllSnapshots()
    #expect(vm.activeSnapshots.isEmpty)
    #expect(PDFViewerAppCoordinator.shared.activeAnchors.isEmpty)
}

@Test @MainActor func testDocumentMetadataAndProperties() async throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let pdfURL = tempDir.appendingPathComponent("metadata_test.pdf")
    var mediaBox = CGRect(x: 0, y: 0, width: 500, height: 700)
    let info: [CFString: Any] = [
        kCGPDFContextTitle: "VectorPDF Engineering Spec" as CFString,
        kCGPDFContextAuthor: "Engineering Team" as CFString,
        kCGPDFContextSubject: "Technical Architecture" as CFString,
        kCGPDFContextKeywords: "PDF, Vector, Architecture" as CFString,
        kCGPDFContextCreator: "VectorPDF Test Generator" as CFString
    ]
    guard let context = CGContext(pdfURL as CFURL, mediaBox: &mediaBox, info as CFDictionary) else {
        fatalError("Failed to create test PDF")
    }
    context.beginPDFPage(nil)
    let font = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
    let attrStr = NSAttributedString(string: "Test Content For Inspection", attributes: [
        kCTFontAttributeName as NSAttributedString.Key: font
    ])
    let line = CTLineCreateWithAttributedString(attrStr)
    context.textPosition = CGPoint(x: 50, y: 500)
    CTLineDraw(line, context)
    context.endPDFPage()
    context.closePDF()

    let core = try PDFDocumentCore(filePath: pdfURL.path)
    let meta = core.getMetadata()
    #expect(meta.title == "VectorPDF Engineering Spec")
    #expect(meta.author == "Engineering Team")
    #expect(meta.subject == "Technical Architecture")
    #expect(meta.keywords.contains("Vector"))
    #expect(!meta.fileSizeDescription.isEmpty)
    #expect(meta.pageCount == 1)

    // Check Security
    let perms = core.getPermissions()
    #expect(perms.canPrint == true)
    #expect(perms.canCopy == true)

    // Check Geometry Boxes
    let boxes = core.getPageBoxes(for: 0)
    #expect(boxes.mediaBox.width == 500)
    #expect(boxes.mediaBox.height == 700)
    #expect(boxes.cropBox.width == 500)
    #expect(boxes.cropBox.height == 700)

    // Check Combined Report
    let report = core.generateInspectionReport(pageIndex: 0)
    #expect(report.metadata.title == "VectorPDF Engineering Spec")
    #expect(report.pageBoxes.count == 1)
    #expect(!report.fonts.isEmpty)

    // Test ViewModel integration
    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.isShowingDocumentProperties == false)
    vm.showDocumentProperties()
    #expect(vm.isShowingDocumentProperties == true)
    #expect(vm.documentInspectionReport != nil)
    #expect(vm.documentInspectionReport?.metadata.title == "VectorPDF Engineering Spec")
}

@Test func testAnchorMenuDisplayTitleFormatting() {
    // 1. Text snippet selection on page 345 (0-indexed 344)
    let snap1 = SnapshotTarget(label: "This event is made for engineers", snippet: "This event is made for engineers", targetPage: 344)
    #expect(snap1.menuDisplayTitle == "Page 345 “This event is made for engineers”")

    // 2. Default page anchor with empty label
    let snap2 = SnapshotTarget(label: "", snippet: "", targetPage: 12)
    #expect(snap2.menuDisplayTitle == "Page 13")

    // 3. Label identical to "Page 13"
    let snap3 = SnapshotTarget(label: "Page 13", snippet: "Page 13", targetPage: 12)
    #expect(snap3.menuDisplayTitle == "Page 13")

    // 4. Label already starting with "Page 13: Section 4"
    let snap4 = SnapshotTarget(label: "Page 13: Section 4 Architecture", snippet: "Section 4", targetPage: 12)
    #expect(snap4.menuDisplayTitle == "Page 13 “Section 4 Architecture”")

    // 5. Section outline heading
    let snap5 = SnapshotTarget(label: "Section 2.1 Overview", snippet: "Section 2.1 Overview", targetPage: 5)
    #expect(snap5.menuDisplayTitle == "Page 6 “Section 2.1 Overview”")
}

@Test @MainActor func testTruePDFRedactionContentScrubbing() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_redact_scrub_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    // 1. Initial verification: page 0 contains "Architecture Specification"
    let initialCore = try PDFDocumentCore(filePath: pdfURL.path)
    let initialText = initialCore.extractText(pageIndex: 0) ?? ""
    #expect(initialText.contains("MuPDF Architecture Specification"))
    #expect(initialText.contains("First column text"))
    #expect(initialCore.isScannedPage(pageIndex: 0) == false)

    // 2. Load into PDFViewerViewModel and add redaction covering the title (54, 50.6)
    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)
    #expect(vm.pendingRedactionsCount == 0)

    // In VectorPDF / MuPDF page coordinates (top-down): (50, 40, 350, 40) covers (54, 50.6)
    let redactAnnot = vm.addRedaction(pageIndex: 0, rect: CGRect(x: 50, y: 40, width: 350, height: 40))
    #expect(redactAnnot != nil)
    #expect(vm.pendingRedactionsCount == 1)

    // 3. Apply redactions permanently
    vm.applyAllPendingRedactions()
    #expect(vm.pendingRedactionsCount == 0)

    // 4. Save document
    let redactedURL = tempDir.appendingPathComponent("test_redacted_out_\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: redactedURL) }
    try vm.document?.save(to: redactedURL.path)

    // 5. Open new document from the saved file and verify underlying stream is scrubbed
    let scrubbedCore = try PDFDocumentCore(filePath: redactedURL.path)
    let scrubbedText = scrubbedCore.extractText(pageIndex: 0) ?? ""
    #expect(!scrubbedText.contains("Architecture Specification"))
    #expect(!scrubbedText.contains("MuPDF Architecture"))
    #expect(scrubbedText.contains("First column text"))
}

@Test @MainActor func testTechnicalCalloutAnnotationCreation() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_callout_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    let target = CGPoint(x: 100, y: 670)
    let knee = CGPoint(x: 150, y: 620)
    let box = CGRect(x: 150, y: 600, width: 140, height: 40)
    let note = "Critical engineering leader line note"

    let callout = vm.addCalloutAnnotation(
        pageIndex: 0,
        targetPoint: target,
        kneePoint: knee,
        textBoxRect: box,
        text: note,
        fontSize: 11.0,
        color: .red
    )
    #expect(callout != nil)
    #expect(callout?.type == .callout)
    #expect(callout?.targetPoint == target)
    #expect(callout?.kneePoint == knee)
    #expect(callout?.text == note)

    let pageAnnots = vm.pageAnnotations[0] ?? []
    #expect(pageAnnots.contains(where: { $0.type == .callout && $0.text == note }))

    // Test that the callout is hit-testable at its text box and leader line
    #expect(callout?.contains(pagePoint: CGPoint(x: 160, y: 610)) == true)
    #expect(callout?.contains(pagePoint: CGPoint(x: 125, y: 645)) == true)

    // Test editing / updating callout note
    vm.removeAnnotation(callout!)
    let updatedCallout = vm.addCalloutAnnotation(
        pageIndex: 0,
        targetPoint: target,
        kneePoint: knee,
        textBoxRect: CGRect(x: 150, y: 600, width: 220, height: 40),
        text: "Updated engineering leader line note",
        fontSize: 11.0,
        color: .blue
    )
    #expect(updatedCallout != nil)
    #expect(updatedCallout?.text == "Updated engineering leader line note")
    #expect(vm.pageAnnotations[0]?.contains(where: { $0.text == "Updated engineering leader line note" }) == true)
    #expect(vm.pageAnnotations[0]?.contains(where: { $0.text == note }) == false)
}

@Test @MainActor func testReviewSummaryExportMarkdownAndCSV() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_review_export_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    // Add a callout
    _ = vm.addCalloutAnnotation(
        pageIndex: 0,
        targetPoint: CGPoint(x: 100, y: 670),
        kneePoint: CGPoint(x: 140, y: 630),
        textBoxRect: CGRect(x: 140, y: 600, width: 120, height: 40),
        text: "Important callout feedback",
        fontSize: 12.0,
        color: .blue
    )

    // 1. Test Markdown generation
    let md = vm.generateReviewSummaryMarkdown()
    #expect(md.contains("# Review Summary"))
    #expect(md.contains("Page 1"))
    #expect(md.contains("Callout"))
    #expect(md.contains("Important callout feedback"))

    // 2. Test CSV generation
    let csv = vm.generateReviewSummaryCSV()
    #expect(csv.hasPrefix("Page,Type,Color,Content,Coordinates,Date\n"))
    #expect(csv.contains("1,Callout,Blue,\"Important callout feedback\""))
}

@Test func testOnDeviceVisionOCRTextRecognition() async throws {
    // 1. Create a synthetic bitmap image containing known text
    let width = 600
    let height = 200
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
    guard let cgContext = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        Issue.record("Failed to create CGContext for OCR test")
        return
    }

    // Fill background white
    cgContext.setFillColor(NSColor.white.cgColor)
    cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))

    // Draw text in high-contrast black
    let text = "VECTOR_PDF_OCR_RECOGNITION"
    let font = NSFont.boldSystemFont(ofSize: 28)
    let attrStr = NSAttributedString(string: text, attributes: [
        .font: font,
        .foregroundColor: NSColor.black
    ])
    let line = CTLineCreateWithAttributedString(attrStr)
    cgContext.textPosition = CGPoint(x: 40, y: 80)
    CTLineDraw(line, cgContext)

    guard let cgImage = cgContext.makeImage() else {
        Issue.record("Failed to make CGImage")
        return
    }

    // 2. Run Apple Vision OCR engine
    let ocrEngine = PDFOCREngine.shared
    let ocrResult = try await ocrEngine.recognizeText(
        in: cgImage,
        pageIndex: 0,
        pageBounds: CGRect(x: 0, y: 0, width: width, height: height)
    )

    #expect(!ocrResult.fullText.isEmpty)
    #expect(ocrResult.fullText.contains("VECTOR_PDF_OCR"))
    #expect(!ocrResult.lines.isEmpty)
    if let firstLine = ocrResult.lines.first {
        #expect(firstLine.boundingBox.width > 0)
        #expect(firstLine.boundingBox.height > 0)
    }
}

@Test @MainActor func testRealTimeFontSizeAndColorChangesOnAnnotations() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_realtime_font_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    let canvasView = PDFCanvasView(viewModel: vm)
    canvasView.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)

    // 1. Add Callout annotation and verify live font size update
    let initialCallout = vm.addCalloutAnnotation(
        pageIndex: 0,
        targetPoint: CGPoint(x: 100, y: 670),
        kneePoint: CGPoint(x: 150, y: 620),
        textBoxRect: CGRect(x: 150, y: 600, width: 140, height: 26),
        text: "Real-time Note",
        fontSize: 12.0,
        color: .blue
    )
    #expect(initialCallout != nil)

    // 2. Add FreeText annotation and test immediate size and color updates
    let initialFreeText = vm.addFreeTextAnnotation(
        pageIndex: 0,
        rect: CGRect(x: 200, y: 500, width: 160, height: 26),
        text: "FreeText Slider Test",
        fontSize: 13.0,
        color: .black
    )
    #expect(initialFreeText != nil)
    #expect(vm.pageAnnotations[0]?.contains(where: { $0.text == "FreeText Slider Test" && $0.fontSize == 13.0 }) == true)

    // Change font size and color on ViewModel
    vm.selectedFontSize = 24.0
    vm.selectedAnnotationColor = .red
    await Task.yield()

    #expect(vm.selectedFontSize == 24.0)
    #expect(vm.selectedAnnotationColor == .red)
}

@Test func testSpatialTextSelectorEmptyBlocksNoCrash() {
    let selector = SpatialTextSelector()
    let pt = CGPoint(x: 100, y: 100)

    // Ensure word and line selection on empty structured page (which invokes resolvePosition)
    // return nil gracefully without SIGTRAP or out-of-bounds assertion failure
    let emptyPage = StructuredPage(pageIndex: 0, bounds: CGRect(x: 0, y: 0, width: 612, height: 792), blocks: [])
    let wordSel = selector.selectWord(at: pt, on: emptyPage)
    #expect(wordSel == nil)

    let lineSel = selector.selectLine(at: pt, on: emptyPage)
    #expect(lineSel == nil)
}

@Test @MainActor func testMarkupToolbarDismissalResetsSelectMode() {
    let vm = PDFViewerViewModel()
    vm.isMarkupBarVisible = true
    vm.canvasMode = .callout
    #expect(vm.canvasMode == .callout)

    // Closing markup toolbar must automatically reset canvasMode to .select
    vm.isMarkupBarVisible = false
    #expect(vm.canvasMode == .select)

    // Toggling markup toolbar off also resets to .select
    vm.isMarkupBarVisible = true
    vm.canvasMode = .draw
    vm.toggleMarkupToolbar()
    #expect(vm.isMarkupBarVisible == false)
    #expect(vm.canvasMode == .select)
}

@Test func testAnnotationHitTestingAndDragBounds() {
    let callout = PDFAnnotation(
        pageIndex: 0,
        type: .callout,
        rect: CGRect(x: 150, y: 300, width: 120, height: 26),
        targetPoint: CGPoint(x: 100, y: 350),
        kneePoint: CGPoint(x: 150, y: 313),
        text: "Important section"
    )

    // Hits inside text box
    #expect(callout.contains(pagePoint: CGPoint(x: 160, y: 310)))
    // Hits target arrow tip
    #expect(callout.contains(pagePoint: CGPoint(x: 100, y: 350)))
    // Hits near knee elbow
    #expect(callout.contains(pagePoint: CGPoint(x: 150, y: 313)))
    // Misses far away point
    #expect(!callout.contains(pagePoint: CGPoint(x: 50, y: 50)))
}

@Test func testFreeTextAddAndDeleteInDocumentCore() throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_freetext_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let doc = try PDFDocumentCore(filePath: pdfURL.path)
    let rect = CGRect(x: 100, y: 200, width: 150, height: 40)
    // Add multi-line free text
    try doc.addFreeText(pageIndex: 0, rect: rect, text: "Line 1\nLine 2", fontSize: 13, red: 0, green: 0, blue: 0)

    let midPoint = CGPoint(x: rect.midX, y: rect.midY)
    let deleted = try doc.deleteAnnotation(pageIndex: 0, at: midPoint)
    #expect(deleted == true)

    // Deleting again at the same point must return false (already removed)
    let deletedAgain = try doc.deleteAnnotation(pageIndex: 0, at: midPoint)
    #expect(deletedAgain == false)

    // Test Callout addition and deletion
    let target = CGPoint(x: 80, y: 350)
    let knee = CGPoint(x: 120, y: 320)
    let noteBox = CGRect(x: 120, y: 300, width: 100, height: 36)
    try doc.addCallout(
        pageIndex: 0,
        targetPoint: target,
        kneePoint: knee,
        textBoxRect: noteBox,
        text: "Callout\nMulti-line",
        fontSize: 11,
        red: 0.8,
        green: 0.1,
        blue: 0.1
    )

    // Deleting near target arrow tip or note box returns true
    let calloutDeleted = try doc.deleteAnnotation(pageIndex: 0, at: target)
    #expect(calloutDeleted == true)
}

@Test @MainActor func testSnugTextBoxSizingAndMultiLine() async throws {
    let vm = PDFViewerViewModel()
    let canvas = PDFCanvasView(viewModel: vm)

    // Short technical annotation: "R12" or "47k"
    let shortSize = canvas.computeTextBoxSize(text: "R12", fontSize: 11.0, maxWidth: 200)
    #expect(shortSize.width < 45.0, "Short technical annotation should have snug width, got \(shortSize.width)")
    #expect(shortSize.height < 25.0)

    // Multi-line annotation: height must expand proportionally
    let multiLineSize = canvas.computeTextBoxSize(text: "Line 1\nLine 2\nLine 3", fontSize: 11.0, maxWidth: 200)
    #expect(multiLineSize.height > shortSize.height * 2.0, "Multi-line annotation should have taller height")
}

@Test @MainActor func testCornerResizeHandleHitTestingAndResizing() async throws {
    let tempDir = FileManager.default.temporaryDirectory
    let pdfURL = tempDir.appendingPathComponent("test_resize_handles_\(UUID().uuidString).pdf")
    createSamplePDF(at: pdfURL)
    defer { try? FileManager.default.removeItem(at: pdfURL) }

    let vm = PDFViewerViewModel()
    await vm.loadDocument(from: pdfURL.path)

    let canvas = PDFCanvasView(viewModel: vm)
    canvas.frame = NSRect(x: 0, y: 0, width: 800, height: 1000)

    let box = CGRect(x: 100, y: 200, width: 120, height: 40)
    // With 1.0 zoom and page at (0, 0), canvas coordinates match page coordinates
    let delta = CGSize(width: 20, height: 10)

    // Test resizeBottomRight expands width and shifts bottom
    let resizedBR = canvas.updatedRect(from: box, part: .resizeBottomRight, delta: delta)
    #expect(resizedBR.width == 140)
    #expect(resizedBR.minY == 210)

    // Test resizeTopLeft shifts origin x and expands top y
    let resizedTL = canvas.updatedRect(from: box, part: .resizeTopLeft, delta: delta)
    #expect(resizedTL.minX == 120)
    #expect(resizedTL.maxY == 250)

    // Ensure resizing respects minimum bounds floor
    let shrinkDelta = CGSize(width: -200, height: -200)
    let minRect = canvas.updatedRect(from: box, part: .resizeBottomLeft, delta: shrinkDelta)
    #expect(minRect.width >= 24)
    #expect(minRect.height >= 16)
}

@Test func testTiledSchematicOCR() async throws {
    let schematicPath = "/Users/td958143/Downloads/fender-studio-85-schematic.pdf"
    guard FileManager.default.fileExists(atPath: schematicPath) else { return }

    let vm = await PDFViewerViewModel()
    await vm.loadDocument(from: schematicPath)

    try await Task.sleep(nanoseconds: 500_000_000)
    await vm.runOCR(onPageIndex: 0)

    let ocr = await MainActor.run { vm.ocrResults[0] }
    #expect(ocr != nil)
    let lineCount = ocr?.lines.count ?? 0
    print("Total recognized lines in schematic: \(lineCount)")
    #expect(lineCount > 50)
}

@Test func testSearchJumpTokenIncrementsOnNavigation() async throws {
    let vm = await PDFViewerViewModel()
    let initialToken = await MainActor.run { vm.searchJumpToken }

    // Mock search results
    let match1 = SearchResult(
        pageIndex: 0,
        matchedText: "test1",
        snippet: "test1",
        highlightQuads: [PDFQuad(ul: .zero, ur: .zero, ll: .zero, lr: .zero)]
    )
    let match2 = SearchResult(
        pageIndex: 1,
        matchedText: "test2",
        snippet: "test2",
        highlightQuads: [PDFQuad(ul: .zero, ur: .zero, ll: .zero, lr: .zero)]
    )

    await MainActor.run {
        vm.searchResults = [match1, match2]
        vm.navigateToMatch(at: 0)
    }

    let tokenAfterFirstNav = await MainActor.run { vm.searchJumpToken }
    #expect(tokenAfterFirstNav == initialToken + 1)

    await MainActor.run {
        vm.nextSearchMatch()
    }
    let tokenAfterNext = await MainActor.run { vm.searchJumpToken }
    #expect(tokenAfterNext == tokenAfterFirstNav + 1)

    await MainActor.run {
        vm.previousSearchMatch()
    }
    let tokenAfterPrev = await MainActor.run { vm.searchJumpToken }
    #expect(tokenAfterPrev == tokenAfterNext + 1)
}

@Test func testRemoveAnnotationDeduplication() async throws {
    let vm = await PDFViewerViewModel()
    let rect = CGRect(x: 100, y: 100, width: 120, height: 30)
    let annot1 = PDFAnnotation(
        id: UUID(),
        pageIndex: 0,
        type: .freeText,
        rect: rect,
        fontSize: 13.0,
        color: .red,
        text: "Duplicate Test"
    )
    let annot2 = PDFAnnotation(
        id: UUID(),
        pageIndex: 0,
        type: .freeText,
        rect: rect,
        fontSize: 13.0,
        color: .red,
        text: "Duplicate Test"
    )

    await MainActor.run {
        vm.pageAnnotations[0] = [annot1, annot2]
        #expect(vm.pageAnnotations[0]?.count == 2)
        vm.removeAnnotation(annot1)
        #expect(vm.pageAnnotations[0]?.count == 0)
    }
}

@Test func testOCRSearchYieldsDistinctBoundingBoxesForEachMatch() async throws {
    let schematicPath = "/Users/td958143/Downloads/fender-studio-85-schematic.pdf"
    guard FileManager.default.fileExists(atPath: schematicPath) else { return }

    let searchActor = PDFSearchActor()
    try await searchActor.openDocument(filePath: schematicPath)

    // Construct mock OCR lines at different positions on page 0
    let line1 = PDFOCRLine(text: "R10 47k", confidence: 0.9, boundingBox: CGRect(x: 100, y: 200, width: 80, height: 20))
    let line2 = PDFOCRLine(text: "R10 100k", confidence: 0.9, boundingBox: CGRect(x: 800, y: 1200, width: 85, height: 20))
    let line3 = PDFOCRLine(text: "R10 1M", confidence: 0.9, boundingBox: CGRect(x: 1500, y: 2100, width: 75, height: 20))
    let ocrResult = PDFOCRPageResult(pageIndex: 0, lines: [line1, line2, line3], fullText: "R10 47k\nR10 100k\nR10 1M")

    let stream = await searchActor.searchStream(query: "R10", nearPage: 0, options: SearchOptions(), ocrPages: [0: ocrResult])
    var results: [SearchResult] = []
    for await r in stream {
        results.append(r)
    }

    #expect(results.count == 3)
    // Verify each result has exactly its own quad
    for r in results {
        #expect(r.highlightQuads.count == 1)
    }
    // Verify each result has a distinct bounding box matching its line position
    let r0Box = try #require(results[0].highlightQuads.first?.boundingRect)
    let r1Box = try #require(results[1].highlightQuads.first?.boundingRect)
    let r2Box = try #require(results[2].highlightQuads.first?.boundingRect)

    #expect(abs(r0Box.minX - 100) < 5)
    #expect(abs(r0Box.minY - 200) < 5)

    #expect(abs(r1Box.minX - 800) < 5)
    #expect(abs(r1Box.minY - 1200) < 5)

    #expect(abs(r2Box.minX - 1500) < 5)
    #expect(abs(r2Box.minY - 2100) < 5)

    // They must all have completely different positions (not all pointing to line 1)
    #expect(r0Box.minX != r1Box.minX)
    #expect(r1Box.minX != r2Box.minX)
    #expect(r0Box.minY != r1Box.minY)
    #expect(r1Box.minY != r2Box.minY)
}
}







