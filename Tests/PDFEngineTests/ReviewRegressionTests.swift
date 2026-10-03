import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import PDFEngine

/// A one-page, 612x792 PDF written by hand with an *uncompressed* content stream, so a test can
/// search the saved file's raw bytes for a specific string.
private func writePlainTextPDF(at url: URL, lines: [String]) {
    var content = ""
    var y = 700
    for line in lines {
        content += "BT /F1 24 Tf 72 \(y) Td (\(line)) Tj ET\n"
        y -= 100
    }
    let objects = [
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
        "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n",
        "4 0 obj\n<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream\nendobj\n",
        "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n"
    ]
    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for object in objects {
        offsets.append(pdf.utf8.count)
        pdf += object
    }
    let xrefOffset = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        pdf += String(format: "%010d 00000 n \n", offset)
    }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
    try! Data(pdf.utf8).write(to: url)
}

private func scratchURL(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_regression_\(UUID().uuidString)_\(name)")
}

private func rawText(of url: URL) throws -> String {
    String(data: try Data(contentsOf: url), encoding: .isoLatin1) ?? ""
}

/// Like writePlainTextPDF, but with each line placed at its own (x, y) in PDF space, 8 pt.
private func writePositionedTextPDF(at url: URL, lines: [(x: Int, y: Int, text: String)]) {
    var content = ""
    for line in lines {
        content += "BT /F1 8 Tf \(line.x) \(line.y) Td (\(line.text)) Tj ET\n"
    }
    let objects = [
        "1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n",
        "2 0 obj\n<< /Type /Pages /Kids [3 0 R] /Count 1 >>\nendobj\n",
        "3 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>\nendobj\n",
        "4 0 obj\n<< /Length \(content.utf8.count) >>\nstream\n\(content)endstream\nendobj\n",
        "5 0 obj\n<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>\nendobj\n"
    ]
    var pdf = "%PDF-1.4\n"
    var offsets: [Int] = []
    for object in objects {
        offsets.append(pdf.utf8.count)
        pdf += object
    }
    let xrefOffset = pdf.utf8.count
    pdf += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
    for offset in offsets {
        pdf += String(format: "%010d 00000 n \n", offset)
    }
    pdf += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xrefOffset)\n%%EOF\n"
    try! Data(pdf.utf8).write(to: url)
}

/// A two-page sample PDF whose first page carries a file-resident highlight over (60,60)–(320,110).
private func writePDFWithHighlight(at url: URL) throws {
    let seed = scratchURL("seed.pdf")
    defer { try? FileManager.default.removeItem(at: seed) }
    createSamplePDF(at: seed)
    let core = try PDFDocumentCore(filePath: seed.path)
    try core.addHighlight(
        pageIndex: 0,
        quad: PDFQuad(ul: CGPoint(x: 60, y: 60), ur: CGPoint(x: 320, y: 60), ll: CGPoint(x: 60, y: 110), lr: CGPoint(x: 320, y: 110)),
        red: 1, green: 1, blue: 0
    )
    try core.save(to: url.path)
}

@MainActor
private func keyEvent(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: keyCode
    )!
}

@Suite(.serialized)
struct ReviewRegressionTests {

    // MARK: - Redaction

    @Test func redactedTextIsNotRecoverableFromSavedFile() throws {
        let src = scratchURL("redact_src.pdf")
        let out = scratchURL("redact_out.pdf")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: out)
        }
        writePlainTextPDF(at: src, lines: ["SECRETTOKEN alpha", "PUBLIC beta"])

        let doc = try PDFDocumentCore(filePath: src.path)
        let line = try #require(doc.loadStructuredPage(for: 0)?.allLines.first { $0.text.contains("SECRETTOKEN") })
        try doc.applyRedactions(pageIndex: 0, rects: [line.bbox.insetBy(dx: -1, dy: -1)], mode: 1)
        try doc.save(to: out.path)

        // Not just "no longer extractable": the original content stream must be gone from the bytes.
        let raw = try rawText(of: out)
        #expect(!raw.contains("SECRETTOKEN"))
        #expect(raw.contains("PUBLIC beta"))

        let reopened = try PDFDocumentCore(filePath: out.path)
        #expect(reopened.extractText(pageIndex: 0)?.contains("PUBLIC") == true)
    }

    // MARK: - Encrypted working copies

    @Test func actorsReopenEncryptedWorkingCopyWithPassword() async throws {
        let plain = scratchURL("enc_plain.pdf")
        let encrypted = scratchURL("enc.pdf")
        let working = scratchURL("enc_working.pdf")
        defer {
            for url in [plain, encrypted, working] { try? FileManager.default.removeItem(at: url) }
        }
        createSamplePDF(at: plain)
        try PDFDocumentCore(filePath: plain.path).saveEncrypted(to: encrypted.path, password: "pw123")

        let doc = try PDFDocumentCore(filePath: encrypted.path, password: "pw123")
        try doc.rotatePage(0, by: 90)
        try doc.save(to: working.path)

        let renderActor = PDFRenderActor()
        try await renderActor.openDocument(filePath: encrypted.path, password: "pw123")

        // A reopen that fails must leave the actor on the document it already had.
        await #expect(throws: PDFError.passwordRequired) {
            try await renderActor.openDocument(filePath: working.path)
        }
        _ = try await renderActor.renderPage(pageIndex: 0, scale: 1.0)

        // With the password, the (still encrypted) working copy opens and renders.
        try await renderActor.openDocument(filePath: working.path, password: "pw123")
        _ = try await renderActor.renderPage(pageIndex: 0, scale: 1.0)
    }

    // MARK: - Annotation appearance streams

    @Test func calloutAppearanceIsInPDFSpaceAndKeepsItsCalloutLine() throws {
        let src = scratchURL("callout_src.pdf")
        let out = scratchURL("callout_out.pdf")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: out)
        }
        writePlainTextPDF(at: src, lines: ["body"])
        let doc = try PDFDocumentCore(filePath: src.path)
        // Page space is top-down: target near the top, text box further down the page.
        try doc.addCallout(
            pageIndex: 0,
            targetPoint: CGPoint(x: 100, y: 100),
            kneePoint: CGPoint(x: 200, y: 150),
            textBoxRect: CGRect(x: 250, y: 180, width: 150, height: 40),
            text: "CALLOUTTXT",
            red: 1, green: 0, blue: 0
        )
        try doc.save(to: out.path)
        let raw = try rawText(of: out)

        // In PDF (bottom-up) space on a 792pt page: target y = 792 - 100, box bottom = 792 - 220.
        #expect(raw.contains("100 692 m"))
        #expect(raw.contains("250 572 150 40 re"))
        // A callout without /CL is just a text box.
        #expect(raw.contains("/CL"))
        #expect(raw.contains("(CALLOUTTXT) Tj"))
    }

    @Test func measurementAppearancesAreValidContentStreams() throws {
        let src = scratchURL("measure_src.pdf")
        let out = scratchURL("measure_out.pdf")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: out)
        }
        writePlainTextPDF(at: src, lines: ["body"])
        let doc = try PDFDocumentCore(filePath: src.path)
        try doc.addPolylineDimension(
            pageIndex: 0,
            vertices: [CGPoint(x: 100, y: 400), CGPoint(x: 200, y: 420), CGPoint(x: 300, y: 400)],
            text: "POLYLINE", red: 0, green: 1, blue: 0
        )
        try doc.addPolygonDimension(
            pageIndex: 0,
            vertices: [CGPoint(x: 100, y: 500), CGPoint(x: 200, y: 500), CGPoint(x: 200, y: 600), CGPoint(x: 100, y: 600)],
            text: "POLYGON", red: 1, green: 0, blue: 1
        )
        try doc.addAngleMeasurement(
            pageIndex: 0,
            points: [CGPoint(x: 400, y: 300), CGPoint(x: 350, y: 350), CGPoint(x: 450, y: 350)],
            text: "ANGLE45", red: 0, green: 0, blue: 1
        )
        try doc.save(to: out.path)
        let raw = try rawText(of: out)

        // `arc` is PostScript, not a PDF operator.
        #expect(!raw.contains(" arc\n"))
        // Polyline vertex (200, 420) top-down is (200, 372) bottom-up.
        #expect(raw.contains("200 372 l"))
        // The label font must actually be declared by the stream that uses it.
        #expect(raw.contains("/BaseFont/Helvetica"))
        // The polygon's fill is applied through a transparency graphics state.
        #expect(raw.contains("/GSa gs"))
        // Angle measurements are written to the file at all.
        #expect(raw.contains("(ANGLE45) Tj"))
        #expect(raw.contains("(POLYLINE) Tj"))
        #expect(raw.contains("(POLYGON) Tj"))
    }

    @Test func annotationAppearanceBBoxMatchesRect() throws {
        let src = scratchURL("bbox_src.pdf")
        let out = scratchURL("bbox_out.pdf")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: out)
        }
        writePlainTextPDF(at: src, lines: ["body"])
        let doc = try PDFDocumentCore(filePath: src.path)
        try doc.addLineDimension(
            pageIndex: 0,
            startPoint: CGPoint(x: 100, y: 300),
            endPoint: CGPoint(x: 300, y: 300),
            leaderOffset: 20,
            text: "LINEDIM", red: 0, green: 0, blue: 1
        )
        try doc.save(to: out.path)
        let raw = try rawText(of: out)

        // A stream whose /BBox differs from the annotation's /Rect gets stretched to fit by viewers.
        let rect = try #require(raw.firstMatch(of: /\/Subtype\/Line[^\n]*?\/Rect\[([^\]]+)\]/)?.1)
        #expect(raw.contains("/BBox[\(rect)]"))
        // /L carries the measured endpoints (y = 792 - 300), not the offset dimension line.
        #expect(raw.contains("/L[100 492 300 492]"))
    }

    @Test func freeTextHandlesLongAndNonASCIILines() throws {
        let src = scratchURL("text_src.pdf")
        let out = scratchURL("text_out.pdf")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: out)
        }
        writePlainTextPDF(at: src, lines: ["body"])
        let doc = try PDFDocumentCore(filePath: src.path)
        let longLine = String(repeating: "x", count: 1500)
        try doc.addFreeText(
            pageIndex: 0,
            rect: CGRect(x: 50, y: 50, width: 200, height: 40),
            text: longLine + "\ncafé",
            fontSize: 12, red: 0, green: 0, blue: 0
        )
        try doc.save(to: out.path)
        let raw = try rawText(of: out)

        // Verify long lines are preserved.
        #expect(raw.contains("(\(longLine)) Tj"))
        // é is 0xE9 in WinAnsi, written as an octal escape rather than two raw UTF-8 bytes.
        #expect(raw.contains("(caf\\351) Tj"))
    }

    // MARK: - Page scale

    @Test func pageScaleRoundTripsAndDoesNotAccumulate() throws {
        let src = scratchURL("scale_src.pdf")
        let out = scratchURL("scale_out.pdf")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: out)
        }
        writePlainTextPDF(at: src, lines: ["body"])
        let doc = try PDFDocumentCore(filePath: src.path)
        #expect(doc.loadPageScale(pageIndex: 0) == nil)

        let quarterInch = PDFScaleConfiguration.standardArchitecturalQuarterInch
        let first = PDFScaleConfiguration.standardMetricOneToOneHundred
        for config in [first, quarterInch] {
            try doc.setPageScale(
                pageIndex: 0,
                ratioString: config.ratioString,
                unitString: config.linearUnit.shortSymbol,
                pointsPerUnit: config.pointsPerUnit
            )
        }
        try doc.save(to: out.path)

        // Setting the scale twice leaves one viewport, not two.
        let raw = try rawText(of: out)
        #expect(raw.components(separatedBy: "(Drawing Scale)").count - 1 == 1)

        let restored = try #require(try PDFDocumentCore(filePath: out.path).loadPageScale(pageIndex: 0))
        #expect(restored.linearUnit == .footInch)
        #expect(abs(restored.pointsPerUnit - 18.0) < 0.001)
        #expect(restored.ratioString == quarterInch.ratioString)
    }

    @Test func metricPresetsMeasureInTheirOwnUnit() throws {
        let oneToOne = try #require(ScalePreset.standardPresets.first { $0.id == "met_1_1" })
        let oneToTen = try #require(ScalePreset.standardPresets.first { $0.id == "met_1_10" })
        let oneToHundred = try #require(ScalePreset.standardPresets.first { $0.id == "met_1_100" })
        // 72pt is one inch of paper: 25.4 mm at 1:1, 25.4 cm at 1:10, 2.54 m at 1:100.
        #expect(PDFScaleConfiguration(preset: oneToOne).formatLength(points: 72) == "25 mm")
        #expect(PDFScaleConfiguration(preset: oneToTen).formatLength(points: 72) == "25.4 cm")
        #expect(PDFScaleConfiguration(preset: oneToHundred).formatLength(points: 72) == "2.54 m")
        // One square inch of paper at 1:1 is 0.00064516 m².
        let area = PDFScaleConfiguration(preset: oneToOne).convertAreaPointsToReal(pointsArea: 72 * 72)
        #expect(abs(area - 0.00064516) < 1e-8)
    }

    @Test func areaConversionHonoursTheLinearUnit() {
        // 10 pt per millimetre: a 100pt x 100pt square is 10mm x 10mm = 100 mm².
        let squareInches = PDFScaleConfiguration(pointsPerUnit: 10, linearUnit: .millimeters, areaUnit: .squareInches)
        #expect(abs(squareInches.convertAreaPointsToReal(pointsArea: 10_000) - 100.0 / 645.16) < 1e-6)
        let squareYards = PDFScaleConfiguration(pointsPerUnit: 10, linearUnit: .centimeters, areaUnit: .squareYards)
        // 10cm x 10cm = 0.01 m² = 0.01 / 0.83612736 sq yd.
        #expect(abs(squareYards.convertAreaPointsToReal(pointsArea: 10_000) - 0.01 / 0.83612736) < 1e-9)
    }

    // MARK: - MuPDF exception stack

    @Test func repeatedNoOpReorderDoesNotExhaustTheContext() throws {
        let src = scratchURL("reorder.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        createSamplePDF(at: src)
        let doc = try PDFDocumentCore(filePath: src.path)
        for _ in 0..<400 {
            try doc.reorderPage(from: 0, to: 0)
        }
        #expect(doc.pageCount == 2)
        try doc.rotatePage(0, by: 90)
    }

    // MARK: - View model

    @MainActor
    @Test func pageOperationsDropStaleFormWidgetCache() async throws {
        let src = scratchURL("widgets.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        createSamplePDF(at: src)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: src.path)
        vm.loadPageMetadata(0)
        vm.loadPageMetadata(1)
        #expect(vm.pageFormWidgets[1] != nil)

        vm.deletePage(0)
        // The cache is keyed by page index, and every index after the deleted page just shifted.
        for _ in 0..<200 where vm.pageFormWidgets[1] != nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(vm.pageFormWidgets[1] == nil)
        #expect(vm.document?.pageCount == 1)
    }

    @MainActor
    @Test func angleMeasurementIsSavedToTheDocument() async throws {
        let src = scratchURL("angle.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        writePlainTextPDF(at: src, lines: ["body"])

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: src.path)
        let annot = vm.addMeasurementAnnotation(
            pageIndex: 0,
            type: .measureAngle,
            points: [CGPoint(x: 400, y: 300), CGPoint(x: 350, y: 350), CGPoint(x: 450, y: 350)],
            value: 90,
            formattedText: "90.0 deg"
        )
        #expect(annot != nil)
        vm.saveDocument()
        #expect(vm.isDocumentEdited == false)
        #expect(try rawText(of: src).contains("(90.0 deg) Tj"))
    }

    // MARK: - Anchors and page edits

    @MainActor
    @Test func pageEditsOnlyFlagAnchorsTheyWouldMove() async throws {
        let src = scratchURL("anchors_range.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        createSamplePDF(at: src)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true   // keep this test's anchors out of the stored reading state
        await vm.loadDocument(from: src.path)
        vm.activeSnapshots = [
            SnapshotTarget(label: "first", targetPage: 0),
            SnapshotTarget(label: "second", targetPage: 1)
        ]
        // Deleting or inserting at page 1 shifts everything from there on; page 0 is untouched.
        #expect(vm.anchorsAffected(byPageEditFrom: 1).map(\.label) == ["second"])
        #expect(vm.anchorsAffected(byPageEditFrom: 0).count == 2)
        // A move only disturbs the pages between its two ends.
        #expect(vm.anchorsAffected(byPageEditFrom: 0, through: 0).map(\.label) == ["first"])
        #expect(vm.anchorsAffected(byPageEditFrom: 2).isEmpty)
    }

    @MainActor
    @Test func pageEditCanContinueInACopyWithoutAnchors() async throws {
        let src = scratchURL("anchors_src.pdf")
        let copy = scratchURL("anchors_copy.pdf")
        defer {
            try? FileManager.default.removeItem(at: src)
            try? FileManager.default.removeItem(at: copy)
        }
        createSamplePDF(at: src)

        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: src.path)
        vm.addSnapshotTarget(SnapshotTarget(label: "keep me", targetPage: 1))
        defer { ReadingStateManager.shared.updateState(for: src.path, lastPageIndex: 0, zoomScale: 1, snapshots: []) }

        // Saving over the original would keep its anchors, so it is refused.
        let refused = await vm.continuePageEdit(onCopyAt: src) { vm.deletePage(0) }
        #expect(refused == false)
        #expect(vm.document?.pageCount == 2)

        let applied = await vm.continuePageEdit(onCopyAt: copy) { vm.deletePage(0) }
        #expect(applied)
        #expect(vm.activeSnapshots.isEmpty)
        #expect(vm.document?.pageCount == 1)
        #expect(vm.document.map { URL(fileURLWithPath: $0.filePath).lastPathComponent } == copy.lastPathComponent)

        // The original keeps both its pages and its anchor.
        #expect(try PDFDocumentCore(filePath: src.path).pageCount == 2)
        #expect(ReadingStateManager.shared.state(for: src.path)?.snapshots.map(\.label) == ["keep me"])
    }

    @MainActor
    @Test func pageEditsResetBackForwardHistory() async throws {
        let src = scratchURL("history.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        createSamplePDF(at: src)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: src.path)
        vm.jumpToPage(1)
        #expect(vm.canGoBack)

        vm.deletePage(1)
        for _ in 0..<200 where vm.canGoBack {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        #expect(vm.canGoBack == false)
    }

    // MARK: - Annotation identity

    @MainActor
    @Test func removingAnInSessionAnnotationLeavesTheFileAnnotationBeneathIt() async throws {
        let src = scratchURL("identity.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        try writePDFWithHighlight(at: src)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: src.path)
        let note = try #require(vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 75, width: 80, height: 20), text: "probenote"))
        #expect(note.documentObjectNumber != nil)

        vm.removeAnnotation(note)
        vm.saveDocument()
        let raw = try rawText(of: src)
        #expect(raw.contains("/Highlight"))
        #expect(!raw.contains("probenote"))
    }

    @MainActor
    @Test func clickingATextBoxDoesNotRecreateIt() async throws {
        let src = scratchURL("click.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        try writePDFWithHighlight(at: src)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: src.path)
        vm.selectedFontSize = 11
        let note = try #require(vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 75, width: 80, height: 20), text: "probenote", fontSize: 13))

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1200), styleMask: [.titled], backing: .buffered, defer: true)
        let canvas = PDFCanvasView(viewModel: vm)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 1200)
        window.contentView = canvas
        let pFrame = try #require(canvas.pageFrame(for: 0))
        let pb = try #require(vm.document?.pageBounds[0])
        let local = NSPoint(x: pFrame.minX + (140 - pb.minX) * vm.effectiveZoom, y: pFrame.minY + (85 - pb.minY) * vm.effectiveZoom)
        let winPt = canvas.convert(local, to: nil)
        func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: winPt, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown))
        try await Task.sleep(nanoseconds: 100_000_000)
        canvas.mouseUp(with: mouse(.leftMouseUp))
        try await Task.sleep(nanoseconds: 100_000_000)

        // Selecting it sets the font-size control to 13; that must not re-create the annotation.
        #expect(vm.pageAnnotations[0]?.map(\.id) == [note.id])
        vm.saveDocument()
        #expect(try rawText(of: src).contains("/Highlight"))
    }

    @MainActor
    @Test func arrowKeysDoNotDeleteASelectedMeasurement() async throws {
        let src = scratchURL("measure_keys.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        createSamplePDF(at: src)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: src.path)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1200), styleMask: [.titled], backing: .buffered, defer: true)
        let canvas = PDFCanvasView(viewModel: vm)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 1200)
        window.contentView = canvas
        vm.canvasMode = .measureLength
        try await Task.sleep(nanoseconds: 50_000_000)

        let pFrame = try #require(canvas.pageFrame(for: 0))
        func mouse(_ type: NSEvent.EventType, pageX: CGFloat) -> NSEvent {
            let local = NSPoint(x: pFrame.minX + pageX * vm.effectiveZoom, y: pFrame.minY + 300 * vm.effectiveZoom)
            return NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        canvas.mouseDown(with: mouse(.leftMouseDown, pageX: 100))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, pageX: 250))
        canvas.mouseUp(with: mouse(.leftMouseUp, pageX: 250))
        #expect(vm.pageAnnotations[0]?.count == 1)

        canvas.keyDown(with: keyEvent("\u{F703}", keyCode: 124))
        canvas.keyDown(with: keyEvent("\r", keyCode: 36))
        #expect(vm.pageAnnotations[0]?.first?.type == .measureLength)
        #expect(vm.document?.measurementAnnotations(pageIndex: 0).count == 1)
    }

    // MARK: - Forms

    @MainActor
    @Test func combFieldKeyHandling() {
        let vm = PDFViewerViewModel()
        let widget = PDFFormWidget(pageIndex: 0, widgetIndex: 0, type: .text, rect: CGRect(x: 0, y: 0, width: 100, height: 20), name: "PIN", value: "", maxLen: 4, isComb: true)
        let field = PDFFormCombTextField(widget: widget, viewModel: vm, frame: NSRect(x: 0, y: 0, width: 100, height: 20))
        for (ch, code) in [("a", UInt16(0)), ("b", 11), ("c", 8), ("d", 2)] {
            field.keyDown(with: keyEvent(ch, keyCode: code))
        }
        #expect(field.stringValue == "abcd")

        // Escape, an up arrow and ⌘C type nothing.
        field.keyDown(with: keyEvent("\u{1B}", keyCode: 53))
        field.keyDown(with: keyEvent("\u{F700}", keyCode: 126))
        field.keyDown(with: keyEvent("c", keyCode: 8, modifiers: .command))
        #expect(field.stringValue == "abcd")

        // Backspace on a full field removes the last character.
        field.keyDown(with: keyEvent("\u{7F}", keyCode: 51))
        #expect(field.stringValue == "abc")
    }

    @MainActor
    @Test func committingAnUnchangedFieldDoesNotMarkTheDocumentEdited() async throws {
        let src = scratchURL("form_unchanged.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        PDFEngineTests().createFormSamplePDF(at: src)

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: src.path)
        vm.loadPageMetadata(0)
        let field = try #require(vm.pageFormWidgets[0]?.first { $0.type == .text })

        vm.updateWidgetValue(pageIndex: 0, widgetIndex: field.widgetIndex, value: field.value)
        #expect(vm.isDocumentEdited == false)
        vm.updateWidgetValue(pageIndex: 0, widgetIndex: field.widgetIndex, value: field.value + "!")
        #expect(vm.isDocumentEdited == true)
    }

    // MARK: - Redaction presets

    @Test func redactionPresetsCatchAmexAndLabelledPhoneNumbers() throws {
        func count(_ preset: RedactionPreset, in text: String) throws -> Int {
            let regex = try NSRegularExpression(pattern: try #require(preset.regexPattern))
            return regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        }
        #expect(try count(.creditCard, in: "Amex 3782 822463 10005 on file") == 1)
        #expect(try count(.creditCard, in: "Visa 4111-2222-3333-4444.") == 1)
        #expect(try count(.creditCard, in: "SSN 123-45-6789") == 0)
        #expect(try count(.phone, in: "Tel:555-123-4567") == 1)
    }

    // MARK: - Export

    @Test func twoColumnPagesExportColumnByColumn() throws {
        let src = scratchURL("two_column.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        // Prose-length lines: short side-by-side lines would rightly read as a two-column table.
        var lines: [(x: Int, y: Int, text: String)] = [(x: 160, y: 740, text: "A Title Spanning Both Columns Of This Page Here")]
        for i in 1...8 {
            lines.append((x: 40, y: 700 - i * 12, text: "Left column line \(i) carries ordinary running prose text"))
            lines.append((x: 330, y: 700 - i * 12, text: "Right column line \(i) carries ordinary running prose text"))
        }
        writePositionedTextPDF(at: src, lines: lines)

        let text = PDFDocumentExporter().exportPlainText(from: try PDFDocumentCore(filePath: src.path))
        let lastLeft = try #require(text.range(of: "Left column line 8"))
        let firstRight = try #require(text.range(of: "Right column line 1"))
        #expect(lastLeft.lowerBound < firstRight.lowerBound)
        #expect(try #require(text.range(of: "Title")).lowerBound < lastLeft.lowerBound)
    }

    // MARK: - Agent index

    @MainActor
    @Test func redactionResetsTheAgentIndex() async throws {
        let src = scratchURL("agent_redact.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        writePlainTextPDF(at: src, lines: ["SECRETTOKEN alpha", "PUBLIC beta"])

        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: src.path)
        vm.agentIndexState = .ready
        vm.applyRedactionRegion(pageIndex: 0, rect: CGRect(x: 60, y: 60, width: 300, height: 40))
        // Redaction invalidates the semantic index.
        #expect(vm.agentIndexState == .idle)
    }
}
