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
import Foundation
import PDFKit
import SwiftUI
import Testing
@testable import PDFEngine

@MainActor
@Suite(.serialized)
struct AnnotationReviewTests {

    private func openDocument(in dir: URL, pages: Int = 2) async throws -> (PDFViewerViewModel, URL) {
        let url = dir.appendingPathComponent("review.pdf")
        makeLabelledPDF(at: url, labels: (0..<pages).map { "Page\($0)" })
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        try #require(vm.document != nil)
        return (vm, url)
    }

    private func reopen(_ url: URL) async throws -> PDFViewerViewModel {
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        try #require(vm.document != nil)
        return vm
    }

    private func thread(_ vm: PDFViewerViewModel, _ annot: PDFEngine.PDFAnnotation) throws -> PDFAnnotationThread {
        let number = try #require(annot.documentObjectNumber)
        return try #require(vm.annotationThread(pageIndex: annot.pageIndex, objectNumber: number))
    }

    private func pdfKitPage(_ url: URL, _ index: Int = 0) throws -> PDFPage {
        let loaded = PDFKit.PDFDocument(url: url)
        let doc = try #require(loaded)
        return try #require(doc.page(at: index))
    }

    /// The page's /Annots as Core Graphics parses them, which shares no code with MuPDF and, unlike
    /// PDFKit, shows keys such as /BE and /IRT.
    private func withRawAnnotations(_ url: URL, _ body: ([CGPDFDictionaryRef]) throws -> Void) throws {
        let doc = try #require(CGPDFDocument(url as CFURL))
        try withExtendedLifetime(doc) {   // the dictionaries belong to it
            let pageDict = try #require(doc.page(at: 1)?.dictionary)
            var array: CGPDFArrayRef?
            try #require(CGPDFDictionaryGetArray(pageDict, "Annots", &array))
            let annots = try #require(array)
            try body((0..<CGPDFArrayGetCount(annots)).compactMap { index in
                var dict: CGPDFDictionaryRef?
                return CGPDFArrayGetDictionary(annots, index, &dict) ? dict : nil
            })
        }
    }

    private func name(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: UnsafePointer<CChar>?
        return CGPDFDictionaryGetName(dict, key, &value) ? value.map { String(cString: $0) } : nil
    }

    private func string(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var value: CGPDFStringRef?
        guard CGPDFDictionaryGetString(dict, key, &value), let value else { return nil }
        return CGPDFStringCopyTextString(value) as String?
    }

    /// Counts pixels that aren't near-white in a page region as MuPDF renders it.
    private func inkedPixels(_ vm: PDFViewerViewModel, page: Int, rect: CGRect) throws -> Int {
        let data = try #require(vm.document?.renderPageRect(pageIndex: page, rect: rect, scale: 2.0))
        let bitmap = try #require(NSBitmapImageRep(data: data))
        var count = 0
        for x in 0..<bitmap.pixelsWide {
            for y in 0..<bitmap.pixelsHigh {
                guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                if c.redComponent < 0.9 || c.greenComponent < 0.9 || c.blueComponent < 0.9 { count += 1 }
            }
        }
        return count
    }

    /// Annotations that came with a file are read back like any others, which `pageAnnotations`
    /// doesn't do: this is what the Annotations table and the export rely on.
    @Test func annotationsAreReadBackFromTheFileAfterReopening() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        vm.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 100, y: 200), CGPoint(x: 200, y: 220)])
        vm.addFreeTextAnnotation(pageIndex: 1, rect: CGRect(x: 72, y: 500, width: 150, height: 24), text: "Second page box")
        vm.addCalloutAnnotation(pageIndex: 1, targetPoint: CGPoint(x: 50, y: 50), kneePoint: CGPoint(x: 90, y: 50), textBoxRect: CGRect(x: 100, y: 40, width: 100, height: 24), text: "Look")
        vm.saveDocument()

        let reopened = try await reopen(url)
        #expect(reopened.pageAnnotations.isEmpty)
        let threads = reopened.annotationThreads()
        #expect(threads.map(\.root.typeName) == ["Drawing", "Text Box", "Callout"])
        #expect(threads.map(\.root.pageIndex) == [0, 1, 1])
        #expect(threads[1].root.text == "Second page box")

        let md = reopened.generateReviewSummaryMarkdown()
        #expect(md.contains("**Total Annotations:** 3"))
        #expect(md.contains("Second page box"))
        #expect(reopened.generateReviewSummaryCSV().contains("2,Callout,"))
    }

    /// Everything the app creates names its author and date, set in Settings or the Mac's user.
    @Test func newAnnotationsRecordTheirAuthorAndDate() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let key = PDFViewerViewModel.annotationAuthorDefaultsKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }
        UserDefaults.standard.set("Example Reviewer", forKey: key)

        let (vm, url) = try await openDocument(in: dir)
        let ink = try #require(vm.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 100, y: 200), CGPoint(x: 200, y: 220)]))
        let start = Date().addingTimeInterval(-5)
        vm.saveDocument()

        let root = try thread(vm, ink).root
        #expect(root.author == "Example Reviewer")
        #expect(try #require(root.created) > start)
        #expect(try pdfKitPage(url).annotations.first?.userName == "Example Reviewer")
    }

    /// A cloud is a real /BE cloudy square that another parser sees, and it draws a scalloped
    /// outline in the file itself rather than only on the VectorPDF overlay.
    @Test func revisionCloudIsAStandardCloudyBorder() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let rect = CGRect(x: 150, y: 300, width: 200, height: 120)
        let cloud = try #require(vm.addCloudAnnotation(pageIndex: 0, rect: rect, arcSize: .large, color: .red))
        #expect(try thread(vm, cloud).root.isCloud)
        vm.saveDocument()

        try withRawAnnotations(url) { annotations in
            let annotation = try #require(annotations.first)
            #expect(name(annotation, "Subtype") == "Square")
            var effect: CGPDFDictionaryRef?
            #expect(CGPDFDictionaryGetDictionary(annotation, "BE", &effect))
            let border = try #require(effect)
            #expect(name(border, "S") == "C")
            var intensity: CGPDFReal = 0
            #expect(CGPDFDictionaryGetNumber(border, "I", &intensity))
            #expect(intensity == 2)
        }

        let reopened = try await reopen(url)
        #expect(try inkedPixels(reopened, page: 0, rect: rect.insetBy(dx: -12, dy: -12)) > 200)
        #expect(reopened.annotationThreads().first?.root.typeName == "Revision Cloud")
    }

    /// The arc size reaches the file as a different radius, not just a different label.
    @Test func cloudArcSizeChangesTheDrawnArcs() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        vm.addCloudAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 100, width: 200, height: 100), arcSize: .small)
        vm.addCloudAnnotation(pageIndex: 1, rect: CGRect(x: 100, y: 100, width: 200, height: 100), arcSize: .large)
        vm.saveDocument()
        let annotations = try [pdfKitPage(url, 0), pdfKitPage(url, 1)].compactMap(\.annotations.first)
        #expect(annotations.count == 2)
        #expect(annotations[0].bounds.width < annotations[1].bounds.width)
    }

    /// Each ending is named in the file and drawn differently, and the drawing and /LE agree.
    @Test func calloutLineEndingsAreStoredAndDrawn() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir, pages: PDFLineEnding.allCases.count)
        let tipArea = CGRect(x: 40, y: 80, width: 24, height: 40)
        for (page, ending) in PDFLineEnding.allCases.enumerated() {
            vm.addCalloutAnnotation(
                pageIndex: page,
                targetPoint: CGPoint(x: 50, y: 100),
                kneePoint: CGPoint(x: 150, y: 100),
                textBoxRect: CGRect(x: 160, y: 90, width: 100, height: 24),
                text: "Check",
                color: .blue,
                lineEnding: ending
            )
        }
        vm.saveDocument()

        let reopened = try await reopen(url)
        var counts: [PDFLineEnding: Int] = [:]
        for (page, ending) in PDFLineEnding.allCases.enumerated() {
            counts[ending] = try inkedPixels(reopened, page: page, rect: tipArea)
        }
        let none = counts[.none] ?? 0
        #expect((counts[.closedArrow] ?? 0) > (counts[.openArrow] ?? 0))
        for ending in PDFLineEnding.allCases where ending != .none {
            #expect((counts[ending] ?? 0) > none, "\(ending)")
        }
    }

    /// Notes are Text annotations with a popup, and keep their comment across a save.
    @Test func noteIsAStandardTextAnnotation() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let note = try #require(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 200, y: 300)))
        vm.setComment("Check this dimension", of: try thread(vm, note))
        #expect(vm.pageAnnotations[0]?.first?.text == "Check this dimension")
        vm.saveDocument()

        let annotations = try pdfKitPage(url).annotations
        let text = try #require(annotations.first { $0.type == "Text" })
        #expect(text.contents == "Check this dimension")
        #expect(annotations.contains { $0.type == "Popup" })
        let reopened = try await reopen(url)
        #expect(reopened.annotationThreads().count == 1)
        #expect(reopened.annotationThreads().first?.root.typeName == "Note")
    }

    /// Replies and statuses survive a save, in standard /IRT and /State form, and don't show up as
    /// extra annotations or extra icons.
    @Test func repliesAndStatusAreThreadedAndInvisibleOnThePage() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let box = try #require(vm.addFreeTextAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 500, width: 150, height: 24), text: "Wrong"))
        vm.addReply(to: try thread(vm, box), text: "First reply")
        vm.addReply(to: try thread(vm, box), text: "Second reply")
        vm.setStatus(.rejected, of: try thread(vm, box))
        vm.setStatus(.accepted, of: try thread(vm, box))
        vm.saveDocument()

        let reopened = try await reopen(url)
        let threads = reopened.annotationThreads()
        #expect(threads.count == 1)
        let loaded = try #require(threads.first)
        #expect(loaded.replies.map(\.text).sorted() == ["First reply", "Second reply"])
        #expect(loaded.status == .accepted)

        try withRawAnnotations(url) { annotations in
            let replies = annotations.filter { name($0, "Subtype") == "Text" }
            #expect(replies.count == 4)
            for reply in replies {
                var parent: CGPDFDictionaryRef?
                #expect(CGPDFDictionaryGetDictionary(reply, "IRT", &parent))
                #expect(parent.flatMap { name($0, "Subtype") } == "FreeText")
                #expect(name(reply, "RT") == "R")
            }
            let states = replies.filter { string($0, "State") != nil }
            #expect(states.compactMap { string($0, "State") }.sorted() == ["Accepted", "Rejected"])
            #expect(states.allSatisfy { string($0, "StateModel") == "Review" })
        }

        // The replies copy the box's /Rect, so anything they drew would land on the box's corner.
        let outside = CGRect(x: 300, y: 400, width: 100, height: 100)
        #expect(try inkedPixels(reopened, page: 0, rect: outside) == 0)
    }

    /// Editing or moving re-creates the PDF object, and the thread has to come along.
    @Test func replacingAnAnnotationKeepsItsThreadAndAuthor() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let key = PDFViewerViewModel.annotationAuthorDefaultsKey
        let previous = UserDefaults.standard.string(forKey: key)
        defer { UserDefaults.standard.set(previous, forKey: key) }

        UserDefaults.standard.set("First Author", forKey: key)
        let cloud = try #require(vm.addCloudAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 100, width: 100, height: 100)))
        vm.addReply(to: try thread(vm, cloud), text: "Keep me")
        vm.setStatus(.completed, of: try thread(vm, cloud))

        UserDefaults.standard.set("Second Author", forKey: key)
        vm.beginReplacingAnnotation(cloud)
        let moved: PDFEngine.PDFAnnotation? = vm.addRestyled(cloud, rect: CGRect(x: 300, y: 300, width: 100, height: 100), color: .blue)
        vm.finishReplacingAnnotation()

        let movedCloud = try #require(moved)
        let updated = try thread(vm, movedCloud)
        #expect(updated.root.author == "First Author")
        #expect(updated.replies.map(\.text) == ["Keep me"])
        #expect(updated.status == .completed)
        #expect(vm.annotationThreads().count == 1)
        #expect(vm.pageAnnotations[0]?.count == 1)

        vm.saveDocument()
        let reopened = try await reopen(url)
        #expect(reopened.annotationThreads().count == 1)
        #expect(reopened.annotationThreads().first?.replies.count == 1)
    }

    /// Waits for the Comments sidebar's read of every page to finish.
    private func annotationThreadsLoaded(_ vm: PDFViewerViewModel) async throws -> [Int: [PDFAnnotationThread]] {
        for _ in 0..<500 where vm.annotationThreadsTask != nil || vm.annotationThreadsByPage == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return try #require(vm.annotationThreadsByPage)
    }

    /// Waits up to five seconds for `condition`, which the sidebar's page reads make true later.
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    /// The Comments tab is only there while the document has annotations, and keeps up with them.
    @Test func commentsTabFollowsTheDocumentsAnnotations() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir, pages: 3)
        #expect(try await annotationThreadsLoaded(vm).isEmpty)
        #expect(!vm.hasAnnotationThreads)

        let note = try #require(vm.addNoteAnnotation(pageIndex: 1, at: CGPoint(x: 200, y: 300), text: "First"))
        #expect(try await eventually { vm.hasAnnotationThreads })
        #expect(vm.annotationThreadsByPage?[1]?.map(\.root.text) == ["First"])

        vm.deleteThread(try thread(vm, note))
        #expect(try await eventually { !vm.hasAnnotationThreads })

        // Deleting a page with annotations reads the document again.
        _ = vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 200, y: 300), text: "On a deleted page")
        #expect(try await eventually { vm.hasAnnotationThreads })
        vm.deletePage(0)
        #expect(try await eventually { !vm.hasAnnotationThreads })

        _ = vm.addNoteAnnotation(pageIndex: 1, at: CGPoint(x: 200, y: 300), text: "Kept")
        vm.saveDocument()
        let reopened = try await reopen(url)
        #expect(try await annotationThreadsLoaded(reopened)[1]?.map(\.root.text) == ["Kept"])
        #expect(reopened.hasAnnotationThreads)
    }

    /// A reply can repeat what the annotation said, so it must not outlive it.
    @Test func deletingAnAnnotationDeletesItsReplies() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let note = try #require(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 200, y: 300), text: "Delete me"))
        let kept = try #require(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 400, y: 300), text: "Keep me"))
        vm.addReply(to: try thread(vm, note), text: "Gone too")
        vm.addReply(to: try thread(vm, kept), text: "Still here")

        vm.deleteThread(try thread(vm, note))
        vm.saveDocument()

        let contents = try pdfKitPage(url).annotations.compactMap(\.contents)
        #expect(!contents.contains("Gone too"))
        #expect(!contents.contains("Delete me"))
        #expect(contents.contains("Still here"))
    }

    /// Redacting an annotation has to remove the replies quoting it from the file too.
    @Test func redactionRemovesReplies() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let note = try #require(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 200, y: 300), text: "Secret"))
        vm.addReply(to: try thread(vm, note), text: "Repeats the secret")
        vm.applyRedactionRegion(pageIndex: 0, rect: CGRect(x: 190, y: 290, width: 50, height: 50))
        vm.saveDocument()
        let bytes = try Data(contentsOf: url)
        #expect(bytes.range(of: Data("Repeats the secret".utf8)) == nil)
        #expect(try pdfKitPage(url).annotations.isEmpty)
    }

    /// A duplicated page gets its own copy of a thread, not replies pointing at the original.
    @Test func duplicatingAPageCopiesItsThreads() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir, pages: 1)
        let note = try #require(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 200, y: 300), text: "Original"))
        vm.addReply(to: try thread(vm, note), text: "Answer")

        let doc = try #require(vm.document)
        _ = try doc.duplicatePages([0])
        let first = doc.annotationThreads(pageIndex: 0)
        let second = doc.annotationThreads(pageIndex: 1)
        #expect(first.count == 1 && second.count == 1)
        #expect(second.first?.replies.map(\.text) == ["Answer"])
        #expect(first.first?.root.objectNumber != second.first?.root.objectNumber)
        #expect(first.first?.replies.first?.objectNumber != second.first?.replies.first?.objectNumber)
    }

    /// The eraser path finds notes, and a click on one leaves the thread's neighbours alone.
    @Test func eraserRemovesANoteThatCameWithTheFile() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let note = try #require(vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 200, y: 300), text: "Erase"))
        vm.addReply(to: try thread(vm, note), text: "Also erased")
        vm.saveDocument()

        let reopened = try await reopen(url)
        reopened.removeAnnotation(at: CGPoint(x: 210, y: 310), pageIndex: 0)
        #expect(reopened.annotationThreads().isEmpty)
    }

    /// Dragging the eraser through a cloud's interior must not delete the PDF object while the
    /// on-screen cloud stays, and its outline still erases.
    @Test func eraserOnlyTakesACloudByItsOutline() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir)
        vm.addCloudAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 100, width: 300, height: 300))
        vm.removeAnnotation(at: CGPoint(x: 250, y: 250), pageIndex: 0)
        #expect(vm.annotationThreads().count == 1)
        #expect(vm.pageAnnotations[0]?.count == 1)
        vm.removeAnnotation(at: CGPoint(x: 100, y: 250), pageIndex: 0)
        #expect(vm.annotationThreads().isEmpty)
        #expect(vm.pageAnnotations[0]?.isEmpty == true)
    }

    /// Hit testing works for annotations the canvas doesn't track, and prefers the smaller one.
    @Test func hitTestingFindsFileAnnotationsSmallestFirst() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        vm.addCloudAnnotation(pageIndex: 0, rect: CGRect(x: 100, y: 100, width: 300, height: 300))
        vm.addNoteAnnotation(pageIndex: 0, at: CGPoint(x: 200, y: 200), text: "Inside")
        vm.saveDocument()
        let reopened = try await reopen(url)
        #expect(reopened.annotationThread(pageIndex: 0, at: CGPoint(x: 205, y: 205))?.root.typeName == "Note")
        #expect(reopened.annotationThread(pageIndex: 0, at: CGPoint(x: 120, y: 120))?.root.typeName == "Revision Cloud")
        #expect(reopened.annotationThread(pageIndex: 0, at: CGPoint(x: 500, y: 700)) == nil)
    }

    private func makeCanvas(for vm: PDFViewerViewModel) -> (NSWindow, PDFCanvasView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 1200), styleMask: [.titled], backing: .buffered, defer: true)
        let canvas = PDFCanvasView(viewModel: vm)
        canvas.frame = NSRect(x: 0, y: 0, width: 1000, height: 1200)
        window.contentView = canvas
        return (window, canvas)
    }

    private func mouse(_ type: NSEvent.EventType, _ canvas: PDFCanvasView, page x: CGFloat, _ y: CGFloat, vm: PDFViewerViewModel, clicks: Int = 1, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        let pFrame = try #require(canvas.pageFrame(for: 0))
        let bounds = try #require(vm.document?.pageBounds[0])
        let local = NSPoint(x: pFrame.minX + (x - bounds.minX) * vm.effectiveZoom, y: pFrame.minY + (y - bounds.minY) * vm.effectiveZoom)
        return try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: flags, timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
    }

    private func drag(_ canvas: PDFCanvasView, vm: PDFViewerViewModel, from start: CGPoint, to end: CGPoint, flags: NSEvent.ModifierFlags = []) throws {
        canvas.mouseDown(with: try mouse(.leftMouseDown, canvas, page: start.x, start.y, vm: vm, flags: flags))
        canvas.mouseDragged(with: try mouse(.leftMouseDragged, canvas, page: end.x, end.y, vm: vm, flags: flags))
        canvas.mouseUp(with: try mouse(.leftMouseUp, canvas, page: end.x, end.y, vm: vm, flags: flags))
    }

    /// The Shapes tool draws each shape from a drag, as the PDF annotation type other readers
    /// know; Shift squares a box, and dragging a line moves both its ends.
    @Test func shapesToolDrawsEachShape() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let (window, canvas) = makeCanvas(for: vm)
        defer { withExtendedLifetime(window) {} }
        vm.isMarkupBarVisible = true
        vm.canvasMode = .shape
        vm.selectedAnnotationColor = .blue
        try await Task.sleep(nanoseconds: 50_000_000)

        for (shape, ending, y) in [(PDFShapeKind.rectangle, PDFLineEnding.none, 100.0), (.oval, .none, 250), (.line, .none, 400), (.line, .closedArrow, 550)] {
            vm.selectedShape = shape
            vm.selectedShapeLineEnding = ending
            try drag(canvas, vm: vm, from: CGPoint(x: 100, y: y), to: CGPoint(x: 300, y: y + 100))
        }
        let annots = vm.pageAnnotations[0] ?? []
        #expect(annots.map(\.type) == [.square, .circle, .line, .line])
        #expect(annots.allSatisfy { $0.color == .blue && $0.documentObjectNumber != nil })
        #expect(annots[2].lineEnding == PDFLineEnding.none)
        #expect(annots[3].lineEnding == .closedArrow)
        let ends = annots[2].inkPoints
        #expect(ends.count == 2)
        #expect(abs(ends[0].x - 100) < 1 && abs(ends[0].y - 400) < 1 && abs(ends[1].x - 300) < 1 && abs(ends[1].y - 500) < 1)
        // Hit only on the outline of a box, or along a line.
        #expect(annots[0].contains(pagePoint: CGPoint(x: 100, y: 150)))
        #expect(!annots[0].contains(pagePoint: CGPoint(x: 200, y: 150)))
        #expect(annots[1].contains(pagePoint: CGPoint(x: 200, y: 250)))
        #expect(!annots[1].contains(pagePoint: CGPoint(x: 200, y: 300)))
        #expect(annots[2].contains(pagePoint: CGPoint(x: 200, y: 450)))
        #expect(!annots[2].contains(pagePoint: CGPoint(x: 200, y: 420)))

        // Dragging the line by its middle moves both ends.
        try drag(canvas, vm: vm, from: CGPoint(x: 200, y: 450), to: CGPoint(x: 220, y: 470))
        let moved = try #require(vm.pageAnnotations[0]?.last)
        #expect(moved.type == .line && moved.id != annots[2].id)
        #expect(abs(moved.inkPoints[0].x - 120) < 1 && abs(moved.inkPoints[0].y - 420) < 1)
        #expect(abs(moved.inkPoints[1].x - 320) < 1 && abs(moved.inkPoints[1].y - 520) < 1)

        // Dragging an end moves just that end.
        let arrow = try #require(vm.pageAnnotations[0]?.first { $0.lineEnding == .closedArrow })
        try drag(canvas, vm: vm, from: CGPoint(x: 300, y: 650), to: CGPoint(x: 400, y: 600))
        let longer = try #require(vm.pageAnnotations[0]?.last)
        #expect(longer.id != arrow.id && longer.lineEnding == .closedArrow)
        #expect(abs(longer.inkPoints[0].x - 100) < 1 && abs(longer.inkPoints[0].y - 550) < 1)
        #expect(abs(longer.inkPoints[1].x - 400) < 1 && abs(longer.inkPoints[1].y - 600) < 1)

        // With it selected, the toolbar's width and ending change it.
        vm.drawStrokeWidth = 4.5
        try await Task.sleep(nanoseconds: 50_000_000)
        vm.selectedShapeLineEnding = .diamond
        try await Task.sleep(nanoseconds: 50_000_000)
        let restyled = try #require(vm.pageAnnotations[0]?.last)
        #expect(restyled.strokeWidth == 4.5 && restyled.lineEnding == .diamond)
        #expect(restyled.inkPoints == longer.inkPoints)

        // Shift makes a rectangle square.
        vm.selectedShape = .rectangle
        try drag(canvas, vm: vm, from: CGPoint(x: 400, y: 100), to: CGPoint(x: 450, y: 180), flags: .shift)
        let square = try #require(vm.pageAnnotations[0]?.last?.rect)
        #expect(abs(square.width - 80) < 1 && abs(square.height - 80) < 1)

        vm.saveDocument()
        try withRawAnnotations(url) { dicts in
            #expect(dicts.compactMap { name($0, "Subtype") }.sorted() == ["Circle", "Line", "Line", "Square", "Square"])
            // The line's /LE names its ending, for other apps to draw.
            func endName(_ dict: CGPDFDictionaryRef) -> String? {
                var endings: CGPDFArrayRef?
                var value: UnsafePointer<CChar>?
                guard CGPDFDictionaryGetArray(dict, "LE", &endings), let endings, CGPDFArrayGetName(endings, 1, &value), let value else { return nil }
                return String(cString: value)
            }
            #expect(dicts.compactMap(endName).sorted() == ["Diamond", "None"])
        }
    }

    /// Edit > Undo takes back adding, deleting and moving an annotation, and Redo does it again.
    @Test func undoTakesBackAnnotationChanges() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir)
        let undo = vm.undoManager
        // A test has no events to group by, so each step is its own group.
        undo.groupsByEvent = false
        func step(_ body: () -> Void) {
            undo.beginUndoGrouping()
            body()
            undo.endUndoGrouping()
        }
        func types() -> [PDFAnnotationType] { vm.pageAnnotations[0]?.map(\.type) ?? [] }

        step { vm.addShapeAnnotation(pageIndex: 0, shape: .oval, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 160)) }
        step { vm.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 300, y: 300), CGPoint(x: 350, y: 320)]) }
        #expect(undo.undoMenuItemTitle == "Undo Add Annotation")
        undo.undo()
        #expect(undo.redoMenuItemTitle == "Redo Add Annotation")
        #expect(types() == [.circle])
        #expect(vm.annotationThreads().count == 1)
        undo.redo()
        #expect(types() == [.circle, .ink])
        #expect(vm.annotationThreads().count == 2)

        let oval = try #require(vm.pageAnnotations[0]?.first)
        step { vm.removeAnnotation(oval) }
        #expect(types() == [.ink])
        #expect(undo.undoMenuItemTitle == "Undo Delete Annotation")
        undo.undo()
        let restored = try #require(vm.pageAnnotations[0]?.first { $0.type == .circle })
        #expect(restored.rect == oval.rect && restored.strokeWidth == oval.strokeWidth)
        #expect(vm.annotationThreads().count == 2)

        // Undoing a move puts it back, and its replies stay with it.
        vm.addReply(to: try thread(vm, restored), text: "Keep me")
        step {
            vm.beginReplacingAnnotation(restored)
            defer { vm.finishReplacingAnnotation() }
            _ = vm.addRestyled(restored, rect: restored.rect!.offsetBy(dx: 50, dy: 0), color: .blue)
        }
        undo.undo()
        let back = try #require(vm.pageAnnotations[0]?.first { $0.type == .circle })
        #expect(back.rect == oval.rect && back.color == oval.color)
        #expect(types().count == 2)
        #expect(try thread(vm, back).replies.map(\.text) == ["Keep me"])
        undo.redo()
        #expect(vm.pageAnnotations[0]?.first { $0.type == .circle }?.color == .blue)
        #expect(types().count == 2)

        // The document window's Edit > Undo uses the same undo manager, even though the window
        // made one of its own before the document's delegate was attached.
        let window = PDFViewerWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100), styleMask: [.titled], backing: .buffered, defer: true)
        _ = window.undoManager
        let delegate = PDFViewerWindowDelegate(viewModel: vm)
        window.delegate = delegate
        #expect(window.undoManager === undo)
        let count = types().count
        window.undo(nil)
        #expect(types().count == count)  // undoing the redone color change: still one oval and the ink
        #expect(vm.pageAnnotations[0]?.first { $0.type == .circle }?.color == oval.color)
        withExtendedLifetime(delegate) {}
    }

    /// A cloud follows the outline dragged round an area, and saves as a cloudy Polygon.
    @Test func cloudFollowsTheOutlineDragged() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let (window, canvas) = makeCanvas(for: vm)
        defer { withExtendedLifetime(window) {} }
        vm.isMarkupBarVisible = true
        vm.canvasMode = .shape
        vm.selectedShape = .cloud
        try await Task.sleep(nanoseconds: 50_000_000)

        // An L-shaped loop, with a little wobble along each side.
        let corners = [CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 100), CGPoint(x: 300, y: 200),
                       CGPoint(x: 200, y: 200), CGPoint(x: 200, y: 300), CGPoint(x: 100, y: 300), CGPoint(x: 100, y: 102)]
        var path: [CGPoint] = []
        for (a, b) in zip(corners, corners.dropFirst()) {
            for step in 0..<10 {
                let t = CGFloat(step) / 10
                path.append(CGPoint(x: a.x + (b.x - a.x) * t + (step.isMultiple(of: 2) ? 1 : -1), y: a.y + (b.y - a.y) * t))
            }
        }
        canvas.mouseDown(with: try mouse(.leftMouseDown, canvas, page: path[0].x, path[0].y, vm: vm))
        for point in path.dropFirst() {
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, canvas, page: point.x, point.y, vm: vm))
        }
        canvas.mouseUp(with: try mouse(.leftMouseUp, canvas, page: path.last!.x, path.last!.y, vm: vm))

        let cloud = try #require(vm.pageAnnotations[0]?.first)
        #expect(cloud.type == .cloud)
        #expect((5...8).contains(cloud.inkPoints.count), "\(cloud.inkPoints)")
        // Only near the outline: not inside it, nor in the notch the L leaves.
        #expect(cloud.contains(pagePoint: CGPoint(x: 250, y: 200)))
        #expect(!cloud.contains(pagePoint: CGPoint(x: 150, y: 150)))
        #expect(!cloud.contains(pagePoint: CGPoint(x: 260, y: 260)))
        #expect(vm.annotationThreads().first?.root.isCloud == true)

        vm.saveDocument()
        try withRawAnnotations(url) { dicts in
            #expect(dicts.compactMap { name($0, "Subtype") } == ["Polygon"])
            var effect: CGPDFDictionaryRef?
            #expect(CGPDFDictionaryGetDictionary(dicts[0], "BE", &effect) && effect.map { name($0, "S") } == "C")
        }
    }

    @Test func cloudOutlineIsAnOvalForAStraightDrag() {
        let outline = CloudOutline.outline(for: [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 50), CGPoint(x: 200, y: 100)])
        #expect(outline.count == 16)
        let box = CGRect(enclosing: outline)
        #expect(abs(box.width - 200) < 0.01 && abs(box.height - 100) < 0.01)
    }

    /// The Shapes tool makes a revision cloud from a drag, with the arc size set on the model.
    @Test func draggingWithTheCloudToolAddsACloud() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir)
        let (window, canvas) = makeCanvas(for: vm)
        defer { withExtendedLifetime(window) {} }
        do {
            vm.isMarkupBarVisible = true
            vm.canvasMode = .shape
            vm.selectedShape = .cloud
            vm.selectedCloudArcSize = .large
            try await Task.sleep(nanoseconds: 50_000_000)

            canvas.mouseDown(with: try mouse(.leftMouseDown, canvas, page: 100, 100, vm: vm))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, canvas, page: 300, 250, vm: vm))
            canvas.mouseUp(with: try mouse(.leftMouseUp, canvas, page: 300, 250, vm: vm))

            let cloud = try #require(vm.pageAnnotations[0]?.first)
            #expect(cloud.type == .cloud)
            #expect(cloud.cloudIntensity == 2.0)
            #expect(abs((cloud.rect?.width ?? 0) - 200) < 2)
            #expect(vm.annotationThreads().first?.root.isCloud == true)

            // Moving it by its outline replaces the object without losing anything.
            vm.addReply(to: try thread(vm, cloud), text: "Moved with it")
            canvas.mouseDown(with: try mouse(.leftMouseDown, canvas, page: 100, 170, vm: vm))
            canvas.mouseDragged(with: try mouse(.leftMouseDragged, canvas, page: 150, 170, vm: vm))
            canvas.mouseUp(with: try mouse(.leftMouseUp, canvas, page: 150, 170, vm: vm))
            let moved = try #require(vm.pageAnnotations[0]?.first)
            #expect(moved.id != cloud.id)
            #expect(abs((moved.rect?.minX ?? 0) - 150) < 2)
            #expect(moved.cloudIntensity == 2.0)
            #expect(vm.annotationThreads().count == 1)
            #expect(vm.annotationThreads().first?.replies.map(\.text) == ["Moved with it"])

            vm.isMarkupBarVisible = false
            #expect(vm.canvasMode == .select)
        }
    }

    /// Double-clicking an annotation opens its comments: one made here wherever it's hit, and
    /// one from the file by its bounds, or near the edge for a shape, but never a line, whose
    /// bounds cover text it doesn't touch.
    @Test func doubleClickFindsWhichCommentsToOpen() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 300))
        vm.addShapeAnnotation(pageIndex: 0, shape: .line, from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 500))
        vm.addInkAnnotation(pageIndex: 0, points: [CGPoint(x: 400, y: 100), CGPoint(x: 450, y: 150)])
        vm.saveDocument()
        let fresh = try await reopen(url)
        let (window, canvas) = makeCanvas(for: fresh)
        defer { withExtendedLifetime(window) {} }
        func target(_ x: CGFloat, _ y: CGFloat) -> String? {
            canvas.commentsTarget(at: CGPoint(x: x, y: y), pageIndex: 0)
                .flatMap { number in fresh.annotationThreads(pageIndex: 0).first { $0.root.objectNumber == number }?.root.subtype }
        }
        #expect(target(100, 200) == "Square")
        #expect(target(200, 200) == nil)
        #expect(target(200, 450) == nil)
        #expect(target(420, 120) == nil)

        // Made in this session, each is hit along its own outline.
        fresh.addShapeAnnotation(pageIndex: 1, shape: .line, from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 500))
        let line = try #require(fresh.pageAnnotations[1]?.first)
        #expect(canvas.commentsTarget(at: CGPoint(x: 200, y: 450), pageIndex: 1) == line.documentObjectNumber)
        #expect(canvas.commentsTarget(at: CGPoint(x: 200, y: 420), pageIndex: 1) == nil)
    }

    /// The Comments sidebar hears which page changed, and a reveal goes to the annotation's page.
    @Test func commentsSidebarIsToldWhatChanged() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir)
        let before = vm.annotationChange.revision
        let note = try #require(vm.addNoteAnnotation(pageIndex: 1, at: CGPoint(x: 100, y: 100), text: "Check"))
        #expect(vm.annotationChange.page == 1 && vm.annotationChange.revision > before)
        let thread = try thread(vm, note)
        let afterAdd = vm.annotationChange.revision
        vm.addReply(to: thread, text: "Done")
        #expect(vm.annotationChange.page == 1 && vm.annotationChange.revision > afterAdd)

        vm.revealAnnotation(thread, opensComments: true)
        let reveal = try #require(vm.annotationReveal)
        #expect(vm.currentPageIndex == 1)
        #expect(reveal.objectNumber == note.documentObjectNumber && reveal.opensComments)
        vm.revealAnnotation(thread)
        #expect(vm.annotationReveal?.token != reveal.token)
    }

    /// Undoing a delete brings an annotation back as it was, replies, author and date included,
    /// whether it was made here or came with the file and was erased.
    @Test func undoingADeleteBringsBackReplies() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        vm.undoManager.groupsByEvent = false
        func step(_ body: () -> Void) {
            vm.undoManager.beginUndoGrouping()
            body()
            vm.undoManager.endUndoGrouping()
        }

        // Made here.
        var added: PDFEngine.PDFAnnotation?
        step { added = vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)) }
        let made = try #require(added)
        vm.addReply(to: try thread(vm, made), text: "Keep me")
        let created = try thread(vm, made).root.date
        step { vm.removeAnnotation(made) }
        #expect(vm.annotationThreads().isEmpty)
        vm.undoManager.undo()
        let back = try #require(vm.pageAnnotations[0]?.first)
        #expect(try thread(vm, back).replies.map(\.text) == ["Keep me"])
        #expect(try thread(vm, back).root.date == created)

        // From the file, erased.
        vm.saveDocument()
        let fresh = try await reopen(url)
        fresh.undoManager.groupsByEvent = false
        #expect(fresh.pageAnnotations.isEmpty)
        fresh.undoManager.beginUndoGrouping()
        fresh.removeAnnotation(at: CGPoint(x: 100, y: 150), pageIndex: 0)
        fresh.undoManager.endUndoGrouping()
        #expect(fresh.annotationThreads().isEmpty)
        #expect(fresh.hiddenAnnotationNumbers[0]?.isEmpty == false)
        fresh.undoManager.undo()
        let restored = try #require(fresh.annotationThreads().first)
        #expect(restored.root.subtype == "Square")
        #expect(restored.replies.map(\.text) == ["Keep me"])
        fresh.undoManager.redo()
        #expect(fresh.annotationThreads().isEmpty)
    }

    /// An annotation that came with the file can be picked up: moved, it keeps its own
    /// appearance, object number and replies; restyled or resized, MuPDF draws it again. Undo
    /// puts it back each time.
    @Test func annotationsFromTheFileCanBeMovedAndRestyled() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        let made = try #require(vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200), color: .red))
        vm.addReply(to: try thread(vm, made), text: "Still here")
        vm.addShapeAnnotation(pageIndex: 0, shape: .line, from: CGPoint(x: 100, y: 400), to: CGPoint(x: 300, y: 400), lineEnding: .openArrow, color: .blue)
        vm.saveDocument()

        let fresh = try await reopen(url)
        fresh.undoManager.groupsByEvent = false
        let (window, canvas) = makeCanvas(for: fresh)
        defer { withExtendedLifetime(window) {} }
        let square = try #require(fresh.annotationThreads().first { $0.root.subtype == "Square" })
        let number = square.root.objectNumber
        let before = try #require(fresh.document?.describeAnnotation(pageIndex: 0, objectNumber: number))

        // Dragging its outline picks it up and moves it.
        fresh.undoManager.beginUndoGrouping()
        try drag(canvas, vm: fresh, from: CGPoint(x: 100, y: 150), to: CGPoint(x: 130, y: 170))
        fresh.undoManager.endUndoGrouping()
        let picked = try #require(fresh.pageAnnotations[0]?.first)
        #expect(picked.isFromFile && picked.documentObjectNumber == number)
        #expect(fresh.hiddenAnnotationNumbers[0]?.contains(number) == true)
        let moved = try #require(fresh.document?.describeAnnotation(pageIndex: 0, objectNumber: number))
        #expect(abs(moved.rect.minX - before.rect.minX - 30) < 0.5 && abs(moved.rect.minY - before.rect.minY - 20) < 0.5)
        #expect(fresh.annotationThread(pageIndex: 0, objectNumber: number)?.replies.map(\.text) == ["Still here"])

        // Restyled from the toolbar while selected.
        fresh.undoManager.beginUndoGrouping()
        fresh.selectedAnnotationColor = .green
        try await Task.sleep(nanoseconds: 50_000_000)
        fresh.undoManager.endUndoGrouping()
        #expect(fresh.document?.describeAnnotation(pageIndex: 0, objectNumber: number)?.color == .green)
        fresh.undoManager.undo()
        #expect(fresh.document?.describeAnnotation(pageIndex: 0, objectNumber: number)?.color == .red)
        fresh.undoManager.undo()
        #expect(fresh.document?.describeAnnotation(pageIndex: 0, objectNumber: number)?.rect == before.rect)

        // A line's end can be dragged; the other stays put.
        let line = try #require(fresh.annotationThreads().first { $0.root.subtype == "Line" })
        fresh.undoManager.beginUndoGrouping()
        try drag(canvas, vm: fresh, from: CGPoint(x: 300, y: 400), to: CGPoint(x: 350, y: 450))
        fresh.undoManager.endUndoGrouping()
        let ends = try #require(fresh.document?.describeAnnotation(pageIndex: 0, objectNumber: line.root.objectNumber)).points
        #expect(abs(ends[0].x - 100) < 0.5 && abs(ends[0].y - 400) < 0.5)
        #expect(abs(ends[1].x - 350) < 0.5 && abs(ends[1].y - 450) < 0.5)
        #expect(fresh.document?.describeAnnotation(pageIndex: 0, objectNumber: line.root.objectNumber)?.lineEnding == .openArrow)

        // Saved, it's where it was left, for any app.
        fresh.saveDocument()
        let again = try await reopen(url)
        #expect(again.document?.describeAnnotation(pageIndex: 0, objectNumber: number)?.rect == before.rect)
        #expect(again.annotationThreads().count == 2)
    }

    /// The renderer leaves out what the canvas draws itself, so nothing is drawn twice.
    @Test func rendererLeavesOutHiddenAnnotations() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, url) = try await openDocument(in: dir)
        vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 300, y: 300), strokeWidth: 4.5, color: .red)
        vm.saveDocument()
        let number = try #require(vm.pageAnnotations[0]?.first?.documentObjectNumber)

        let actor = PDFRenderActor()
        try await actor.openDocument(filePath: url.path)
        func redAt100() async throws -> Bool {
            let image = try await actor.renderPage(pageIndex: 0, scale: 1).image
            let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            // (100, 200) on the page, top-down, is row 200 of the bitmap, whose rows run top-down too.
            let pixel = data + 200 * image.width * 4 + 100 * 4
            return pixel[0] > 200 && pixel[1] < 120
        }
        // The sharp render of part of a page, drawn over it at high zoom, leaves them out too.
        func detailRedAt100() async throws -> Bool {
            let image = try await actor.renderPageDetail(pageIndex: 0, rect: CGRect(x: 90, y: 190, width: 20, height: 20), scale: 1).image
            let context = try #require(CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let pixel = try #require(context.data).assumingMemoryBound(to: UInt8.self) + 10 * image.width * 4 + 10 * 4
            return pixel[0] > 200 && pixel[1] < 120
        }
        #expect(try await redAt100())
        #expect(try await detailRedAt100())
        await actor.setHiddenAnnotations([0: [number]])
        #expect(try await !redAt100())
        #expect(try await !detailRedAt100())
        #expect(vm.hiddenAnnotationNumbers[0] == [number])
    }

    /// Dragging across a cloud's interior leaves it alone for text selection underneath.
    @Test func cloudInteriorDoesNotCatchClicks() throws {
        let cloud = PDFEngine.PDFAnnotation(pageIndex: 0, type: .cloud, rect: CGRect(x: 100, y: 100, width: 200, height: 200))
        #expect(!cloud.contains(pagePoint: CGPoint(x: 200, y: 200)))
        #expect(cloud.contains(pagePoint: CGPoint(x: 100, y: 200)))
        #expect(!cloud.contains(pagePoint: CGPoint(x: 50, y: 200)))
    }

    /// The note tool places a note, opens its popover on the page and hands back to selection.
    @Test(.showsWindows) func noteToolOpensCommentsAndDiscardsAnEmptyNote() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir)
        let (window, canvas) = makeCanvas(for: vm)
        defer { withExtendedLifetime(window) {} }
        do {
            window.makeKeyAndOrderFront(nil)
            defer { window.orderOut(nil) }
            vm.canvasMode = .note
            try await Task.sleep(nanoseconds: 50_000_000)
            canvas.mouseDown(with: try mouse(.leftMouseDown, canvas, page: 200, 300, vm: vm))
            canvas.mouseUp(with: try mouse(.leftMouseUp, canvas, page: 200, 300, vm: vm))

            #expect(vm.canvasMode == .select)
            #expect(vm.pageAnnotations[0]?.first?.type == .note)
            #expect(canvas.commentsPopover?.isShown == true)
            try await Task.sleep(nanoseconds: 200_000_000)

            // Closing animates, and the test's run loop doesn't reliably finish an animation.
            let popover = try #require(canvas.commentsPopover)
            popover.animates = false
            popover.close()
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(!popover.isShown)
            #expect(canvas.commentsPopover == nil)
            #expect(vm.annotationThreads().isEmpty)
            #expect(vm.pageAnnotations[0]?.isEmpty == true)
        }
    }

    /// The new tools add to the Markup toolbar rather than a new one, so check it still fits.
    @Test func markupToolbarFitsAnOrdinaryWindowInEveryMode() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir)
        for mode in [CanvasMode.select, .draw, .text, .callout, .note, .shape, .eraser, .stamp] {
            vm.canvasMode = mode
            let view = NSHostingView(rootView: PDFMarkupToolbarView(viewModel: vm))
            view.layoutSubtreeIfNeeded()
            print("Markup toolbar width in \(mode): \(view.fittingSize.width)")
            #expect(view.fittingSize.width < 900, "\(mode)")
        }
    }

    private func comment(_ number: Int, parent: Int? = nil, subtype: String = "Text", author: String = "A", date: Date? = nil, state: String = "", model: String = "") -> PDFAnnotationComment {
        PDFAnnotationComment(objectNumber: number, parentObjectNumber: parent, pageIndex: 0, rect: .zero, color: .red, subtype: subtype, isCallout: false, isCloud: false, author: author, text: "", created: date, modified: date, state: state, stateModel: model)
    }

    @Test func threadsGatherNestedRepliesAndSurviveBrokenParents() {
        let threads = PDFAnnotationThread.threads(from: [
            comment(1),
            comment(2, parent: 1),
            comment(3, parent: 2),
            comment(4, parent: 99),   // parent missing from the page
            comment(5, parent: 6),    // a loop must not hang or lose both
            comment(6, parent: 5)
        ])
        #expect(threads.first { $0.id == 1 }?.replies.map(\.id).sorted() == [2, 3])
        #expect(threads.contains { $0.id == 4 })
        #expect(threads.count >= 3)
    }

    @Test func latestReviewStateWinsAndOtherModelsAreIgnored() {
        let early = Date(timeIntervalSince1970: 1000)
        let late = Date(timeIntervalSince1970: 2000)
        let thread = PDFAnnotationThread.threads(from: [
            comment(1),
            comment(2, parent: 1, date: late, state: "Rejected", model: "Review"),
            comment(3, parent: 1, date: early, state: "Accepted", model: "Review"),
            comment(4, parent: 1, date: late.addingTimeInterval(9), state: "Marked", model: "Marked")
        ]).first
        #expect(thread?.status == .rejected)
        #expect(thread?.replies.isEmpty == true)
    }

    @Test func filtersCombine() {
        let now = Date(timeIntervalSince1970: 100_000_000)
        let threads = PDFAnnotationThread.threads(from: [
            comment(1, subtype: "Text", author: "A", date: now),
            comment(2, subtype: "Highlight", author: "B", date: now.addingTimeInterval(-3 * 86_400)),
            comment(3, parent: 2, date: now, state: "Accepted", model: "Review"),
            comment(4, subtype: "Ink", author: "A", date: now.addingTimeInterval(-40 * 86_400))
        ])
        func ids(_ filter: PDFAnnotationFilter) -> [Int] { threads.filter { filter.matches($0, now: now) }.map(\.id) }
        #expect(ids(PDFAnnotationFilter()) == [1, 2, 4])
        #expect(ids(PDFAnnotationFilter(type: "Note")) == [1])
        #expect(ids(PDFAnnotationFilter(author: "A")) == [1, 4])
        #expect(ids(PDFAnnotationFilter(status: .accepted)) == [2])
        #expect(ids(PDFAnnotationFilter(date: .today)) == [1])
        #expect(ids(PDFAnnotationFilter(date: .lastWeek)) == [1, 2])
        #expect(ids(PDFAnnotationFilter(author: "A", date: .lastMonth)) == [1])
    }
}
