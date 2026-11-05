import Foundation
import Testing
@testable import PDFEngine

private func scratchDirectory() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("attachments-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

/// A one-page PDF with a file attachment annotation, whose file is also the document's
/// associated file (/AF), as e-invoices list theirs; written by hand, without a cross-reference
/// table, which MuPDF rebuilds.
private func writePDFWithAnnotationAttachment(at url: URL, alsoAssociated: Bool = true) throws {
    let pdf = """
    %PDF-1.7
    1 0 obj << /Type /Catalog /Pages 2 0 R \(alsoAssociated ? "/AF [5 0 R] " : "")>> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [4 0 R] >> endobj
    4 0 obj << /Type /Annot /Subtype /FileAttachment /Rect [100 100 120 120] /FS 5 0 R /Contents (Site photo) >> endobj
    5 0 obj << /Type /Filespec /F (notes.txt) /UF (notes.txt) /Desc (Inspection notes) /EF << /F 6 0 R >> >> endobj
    6 0 obj << /Type /EmbeddedFile /Subtype /text#2Fplain /Length 11 /Params << /Size 11 >> >> stream
    hello notes
    endstream endobj
    trailer << /Root 1 0 R >>
    %%EOF
    """
    try pdf.data(using: .ascii)!.write(to: url)
}

@Suite struct AttachmentTests {
    @Test func documentWithoutAttachmentsHasNone() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("plain.pdf")
        makeLabelledPDF(at: url, labels: ["Page0"])
        #expect(try PDFDocumentCore(filePath: url.path).attachments().isEmpty)
    }

    @Test func documentAttachmentsAreListedSavedAndKept() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("package.pdf")
        let saved = dir.appendingPathComponent("saved.pdf")
        makeLabelledPDF(at: url, labels: ["Page0"])

        let doc = try PDFDocumentCore(filePath: url.path)
        let csv = Data("a,b\n1,2\n".utf8)
        try doc.addAttachment(name: "quantities.csv", data: csv, mimeType: "text/csv", description: "Bill of quantities")
        try doc.addAttachment(name: "model.ifc", data: Data(repeating: 7, count: 1000))
        try doc.save(to: saved.path)

        let reopened = try PDFDocumentCore(filePath: saved.path)
        let attachments = reopened.attachments()
        #expect(attachments.map(\.name).sorted() == ["model.ifc", "quantities.csv"])
        let sheet = try #require(attachments.first { $0.name == "quantities.csv" })
        #expect(sheet.mimeType == "text/csv")
        #expect(sheet.size == csv.count)
        #expect(sheet.description == "Bill of quantities")
        #expect(sheet.pageIndex == nil)
        #expect(sheet.created != nil)

        let out = dir.appendingPathComponent(sheet.fileName)
        try reopened.saveAttachment(sheet, to: out.path)
        #expect(try Data(contentsOf: out) == csv)

        let model = try #require(attachments.first { $0.name == "model.ifc" })
        let modelOut = dir.appendingPathComponent(model.fileName)
        try reopened.saveAttachment(model, to: modelOut.path)
        #expect(try Data(contentsOf: modelOut) == Data(repeating: 7, count: 1000))
    }

    @Test func annotationAttachmentsAreListedOnceWithTheirPage() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("annotated.pdf")
        try writePDFWithAnnotationAttachment(at: url)

        let doc = try PDFDocumentCore(filePath: url.path)
        let attachments = doc.attachments()
        // Listed by /AF and by the annotation: still one file, attached to the document first.
        #expect(attachments.count == 1)
        let notes = try #require(attachments.first)
        #expect(notes.name == "notes.txt")
        #expect(notes.mimeType == "text/plain")
        #expect(notes.description == "Inspection notes")
        let out = dir.appendingPathComponent(notes.fileName)
        try doc.saveAttachment(notes, to: out.path)
        #expect(try String(contentsOf: out, encoding: .utf8) == "hello notes")
    }

    @Test func annotationOnlyAttachmentsKnowTheirPage() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("annotated.pdf")
        try writePDFWithAnnotationAttachment(at: url, alsoAssociated: false)
        let attachments = try PDFDocumentCore(filePath: url.path).attachments()
        #expect(attachments.count == 1)
        #expect(attachments.first?.pageIndex == 0)
    }

    /// The fixture for trying the Attachments tab by hand reads as its README says.
    @Test func sampleFixtureListsEveryKindOfAttachment() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.attachmentSample.path)
        let attachments = doc.attachments()
        #expect(attachments.map(\.name) == ["factur-x.xml", "quantities.csv", "readme.txt", "site-photo.png", "inspection-notes.txt"])
        #expect(attachments.map(\.pageIndex) == [nil, nil, nil, nil, 1])
        #expect(attachments.first { $0.name == "site-photo.png" }?.description == nil)
        #expect(attachments.first { $0.name == "quantities.csv" }?.description == "Bill of quantities for level 2")

        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let photo = try #require(attachments.first { $0.name == "site-photo.png" })
        let out = dir.appendingPathComponent(photo.fileName)
        try doc.saveAttachment(photo, to: out.path)
        #expect(try Data(contentsOf: out).prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
        #expect(try Data(contentsOf: out).count == photo.size)
    }

    @Test func fileNamesCantLeaveTheirFolder() {
        func named(_ name: String) -> String {
            PDFAttachment(id: 0, name: name, mimeType: nil, size: nil, created: nil, modified: nil, description: nil, pageIndex: nil).fileName
        }
        #expect(named("../../etc/passwd") == "passwd")
        #expect(named("C:\\Users\\example\\report.xlsx") == "report.xlsx")
        #expect(named("..") == "Attachment")
        #expect(named("dir/") == "dir")
        #expect(named(".hidden") == "Attachment.hidden")
        #expect(named("a:b.txt") == "a-b.txt")
        #expect(named("plan.dwg") == "plan.dwg")
    }
}

/// Two pages, the second carrying a file attachment annotation.
private func writeTwoPagePDFWithAttachmentOnSecondPage(at url: URL) throws {
    let pdf = """
    %PDF-1.7
    1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
    2 0 obj << /Type /Pages /Kids [3 0 R 7 0 R] /Count 2 >> endobj
    3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] >> endobj
    7 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Annots [4 0 R] >> endobj
    4 0 obj << /Type /Annot /Subtype /FileAttachment /Rect [100 100 120 120] /FS 5 0 R >> endobj
    5 0 obj << /Type /Filespec /F (photo.jpg) /EF << /F 6 0 R >> >> endobj
    6 0 obj << /Type /EmbeddedFile /Length 4 >> stream
    JPEG
    endstream endobj
    trailer << /Root 1 0 R >>
    %%EOF
    """
    try pdf.data(using: .ascii)!.write(to: url)
}

@Suite @MainActor struct AttachmentViewModelTests {
    private func eventually(_ condition: () -> Bool) async throws -> Bool {
        for _ in 0..<500 where !condition() {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        return condition()
    }

    private func open(_ url: URL) async throws -> PDFViewerViewModel {
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: url.path)
        try #require(vm.document != nil)
        return vm
    }

    @Test func attachmentsLoadWithTheDocumentAndShowTheSidebar() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let plain = dir.appendingPathComponent("plain.pdf")
        let invoice = dir.appendingPathComponent("invoice.pdf")
        makeLabelledPDF(at: plain, labels: ["Page0"])
        let doc = try PDFDocumentCore(filePath: plain.path)
        try doc.addAttachment(name: "factur-x.xml", data: Data("<Invoice/>".utf8), mimeType: "text/xml")
        try doc.save(to: invoice.path)

        let vm = try await open(plain)
        #expect(vm.attachments.isEmpty)
        // One page and nothing attached: nothing to show in a sidebar.
        #expect(!vm.isSidebarVisible)

        await vm.loadDocument(from: invoice.path)
        #expect(vm.attachments.map(\.name) == ["factur-x.xml"])
        #expect(vm.isSidebarVisible)
    }

    @Test func extractedAttachmentsAreQuarantined() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("annotated.pdf")
        try writePDFWithAnnotationAttachment(at: url)
        let vm = try await open(url)
        let attachment = try #require(vm.attachments.first)

        let extracted = try vm.extractAttachment(attachment)
        defer { try? FileManager.default.removeItem(at: extracted.deletingLastPathComponent()) }
        #expect(extracted.lastPathComponent == "notes.txt")
        #expect(extracted.deletingLastPathComponent().lastPathComponent.hasPrefix("VectorPDF"))
        #expect(try String(contentsOf: extracted, encoding: .utf8) == "hello notes")
        let values = try extracted.resourceValues(forKeys: [.quarantinePropertiesKey])
        #expect(values.quarantineProperties?[kLSQuarantineAgentNameKey as String] as? String == "VectorPDF")
    }

    @Test func savingAllNumbersNamesThatClash() throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data().write(to: dir.appendingPathComponent("plan.dwg"))
        func attachment(_ id: Int, _ name: String) -> PDFAttachment {
            PDFAttachment(id: id, name: name, mimeType: nil, size: nil, created: nil, modified: nil, description: nil, pageIndex: nil)
        }
        let names = PDFViewerViewModel.uniqueNames(
            for: [attachment(0, "plan.dwg"), attachment(1, "PLAN.dwg"), attachment(2, "notes"), attachment(3, "notes")],
            in: dir
        )
        #expect(names == ["plan 2.dwg", "PLAN 3.dwg", "notes", "notes 2"])
    }

    @Test func deletingTheirPageRemovesPageAttachments() async throws {
        let dir = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("two.pdf")
        try writeTwoPagePDFWithAttachmentOnSecondPage(at: url)
        let vm = try await open(url)
        #expect(vm.attachments.map(\.pageIndex) == [1])

        vm.deletePage(1)
        #expect(try await eventually { vm.attachments.isEmpty })
    }
}

import AppKit
import Quartz
import SwiftUI

@Suite @MainActor struct AttachmentsTabWindowTests {
    private func table(in view: NSView) -> AttachmentsNSTableView? {
        if let table = view as? AttachmentsNSTableView { return table }
        for sub in view.subviews { if let found = table(in: sub) { return found } }
        return nil
    }

    private func previewedName() -> String? {
        (QLPreviewPanel.shared().currentPreviewItem?.previewItemURL)?.lastPathComponent
    }

    private func key(_ characters: String, code: UInt16, in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber,
                         context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    @Test(.showsWindows) func doubleClickAndSpacePreviewWithQuickLook() async throws {
        let vm = PDFViewerViewModel()
        vm.isTransientWindow = true
        await vm.loadDocument(from: Fixture.attachmentSample.path)
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 280, height: 420), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: AttachmentsSidebarView(viewModel: vm))
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        window.layoutIfNeeded()
        try await Task.sleep(nanoseconds: 200_000_000)
        let content = try #require(window.contentView)
        let table = try #require(table(in: content))
        let coordinator = try #require(table.coordinator)
        var quickLooks = 0
        coordinator.presentQuickLook = { quickLooks += 1 }
        #expect(table.numberOfRows == 5)
        #expect(table.visibleRect.height > 100)

        // Double-clicking a row runs the coordinator's handler, which opens Quick Look on it. (Real
        // clicks can't be sent here: the table's tracking loop ends the test process.)
        #expect(table.doubleAction == #selector(AttachmentsTableView.Coordinator.doubleClicked(_:)))
        #expect(table.target === coordinator)
        let row = 3
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        coordinator.showQuickLook()
        #expect(quickLooks == 1)
        #expect(window.firstResponder === table)

        // What the panel would show: the selected attachment, taken out of the PDF.
        let panel = QLPreviewPanel.shared()!
        #expect(coordinator.numberOfPreviewItems(in: panel) == 1)
        let item = coordinator.previewPanel(panel, previewItemAt: 0)
        #expect(item?.previewItemURL?.lastPathComponent == "site-photo.png")
        if let url = item?.previewItemURL { #expect(FileManager.default.fileExists(atPath: url.path)) }

        // Space asks for Quick Look too.
        table.keyDown(with: key(" ", code: 49, in: window))
        #expect(quickLooks == 2)

        // The down arrow moves to the next attachment, which the panel then shows.
        table.keyDown(with: key(String(UnicodeScalar(NSDownArrowFunctionKey)!), code: 125, in: window))
        #expect(table.selectedRow == 4)
        #expect(coordinator.previewPanel(panel, previewItemAt: 0)?.previewItemURL?.lastPathComponent == "inspection-notes.txt")
    }
}
