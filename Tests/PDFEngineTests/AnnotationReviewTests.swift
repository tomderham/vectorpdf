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

    private func mouse(_ type: NSEvent.EventType, _ canvas: PDFCanvasView, page x: CGFloat, _ y: CGFloat, vm: PDFViewerViewModel, clicks: Int = 1) throws -> NSEvent {
        let pFrame = try #require(canvas.pageFrame(for: 0))
        let bounds = try #require(vm.document?.pageBounds[0])
        let local = NSPoint(x: pFrame.minX + (x - bounds.minX) * vm.effectiveZoom, y: pFrame.minY + (y - bounds.minY) * vm.effectiveZoom)
        return try #require(NSEvent.mouseEvent(with: type, location: canvas.convert(local, to: nil), modifierFlags: [], timestamp: 0, windowNumber: canvas.window?.windowNumber ?? 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1))
    }

    /// The cloud tool makes a cloud from a drag, with the arc size chosen in the toolbar.
    @Test func draggingWithTheCloudToolAddsACloud() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let (vm, _) = try await openDocument(in: dir)
        let (window, canvas) = makeCanvas(for: vm)
        defer { withExtendedLifetime(window) {} }
        do {
            vm.isMarkupBarVisible = true
            vm.canvasMode = .cloud
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
        for mode in [CanvasMode.select, .draw, .text, .callout, .note, .cloud, .eraser, .stamp] {
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
