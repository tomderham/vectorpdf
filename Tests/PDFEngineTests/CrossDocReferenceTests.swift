import Foundation
import CoreGraphics
import Testing
@testable import PDFEngine

/// One-page PDF with each string on its own line, 14 pt Helvetica, 40 pt apart.
private func writeLinesPDF(at url: URL, lines: [String]) {
    var content = ""
    var y = 720
    for line in lines {
        content += "BT /F1 14 Tf 72 \(y) Td (\(line)) Tj ET\n"
        y -= 40
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
    FileManager.default.temporaryDirectory.appendingPathComponent("vpdf_crossref_\(UUID().uuidString)_\(name)")
}

private func reference(_ text: String) -> ParsedReference? {
    ReferenceExtractor.references(in: text).first
}

@Suite struct ReferenceExtractorTests {
    @Test func sectionWithSubItemAndDocumentHint() throws {
        let ref = try #require(reference("as provided in Section 4.2(b) of the Master Services Agreement."))
        #expect(ref.kind == .section)
        #expect(ref.identifier == "4.2(b)")
        #expect(ref.baseIdentifier == "4.2")
        #expect(ref.docHint == "Master Services Agreement")
        #expect(ref.displayText == "Section 4.2(b)")
    }

    @Test func lettersRomanNumeralsAndSectionSign() throws {
        let refs = ReferenceExtractor.references(in: "set out in Appendix C and Schedule 2, subject to Article II and § 12.3")
        #expect(refs.map(\.kind) == [.appendix, .schedule, .article, .section])
        #expect(refs.map(\.identifier) == ["C", "2", "II", "12.3"])
        #expect(refs[0].needsLabelToMatch)
        #expect(!refs[1].needsLabelToMatch)
        #expect(refs[3].displayText == "§ 12.3")
        #expect(refs[0].docHint == nil)
    }

    @Test func ignoresOrdinaryWords() {
        #expect(ReferenceExtractor.references(in: "See the Table of Contents, part a of it, and the Partnership 2 clause").isEmpty)
    }

    @Test func versionsAndAddressesAreNotSections() {
        let text = "Connect to 192.168.1.1, then retry with 1.0.2 or 2.03.1."
        #expect(ReferenceExtractor.references(in: text).isEmpty)
        // Section numbers still are, whatever comes before them.
        #expect(ReferenceExtractor.references(in: "as described in 35.5.2.3.1 and 9.4.2.170").map(\.identifier) == ["35.5.2.3.1", "9.4.2.170"])
    }

    @Test func documentHintNeedsADocumentName() throws {
        // Capitalised words after "in" or "to" that name no document.
        #expect(try #require(reference("per Section 3 in January.")).docHint == nil)
        #expect(try #require(reference("deliver under Section 3 to Buyer")).docHint == nil)
        // "the …", or a number or acronym, make it one.
        #expect(try #require(reference("Section 3 of the Supply Agreement")).docHint == "Supply Agreement")
        #expect(try #require(reference("Section 12 of Clean Air Act")).docHint == nil)
        #expect(try #require(reference("Section 5.6 of NIST SP 800-56A")).docHint == "NIST SP 800-56A")
    }

    @Test func labelledDocumentHintIsNotADocument() throws {
        let ref = try #require(reference("Section 4 of Schedule 2 applies"))
        #expect(ref.docHint == nil)
    }

    @Test func quotedHeading() throws {
        let ref = try #require(reference("under the heading “Payment Terms” in the Supply Agreement"))
        #expect(ref.kind == .quotedTitle)
        #expect(ref.quotedTitle == "Payment Terms")
        #expect(ref.docHint == "Supply Agreement")
        #expect(reference("so-called “synergies” here") == nil)
    }

    @Test func bareSubclauseNumbersAsStandardsCiteThem() throws {
        let ref = try #require(reference("shall follow the rules defined in 35.5.2.3.1 (General), where"))
        #expect(ref.kind == .section)
        #expect(ref.label.isEmpty)
        #expect(ref.identifier == "35.5.2.3.1")
        #expect(ref.title == "General")
        #expect(ref.displayText == "35.5.2.3.1 (General)")
        #expect(reference("as described in 9.4.2.1")?.identifier == "9.4.2.1")
        #expect(reference("see C.3 (MIB detail)")?.identifier == "C.3")
        #expect(reference("see 4.2 (Payment terms)")?.identifier == "4.2")
    }

    @Test func bareNumbersThatAreNotReferences() {
        #expect(ReferenceExtractor.references(in: "operates in the 2.4 GHz band per IEEE 802.11 and draft D3.0, about 1.5 times faster").isEmpty)
        #expect(ReferenceExtractor.references(in: "IEEE Std 802.11ax-2021 and 802.11be").isEmpty)
    }

    @Test func labelledReferenceIsNotAlsoBare() {
        #expect(ReferenceExtractor.references(in: "see Clause 35.5.2 (EHT UL MU operation)").map(\.label) == ["Clause"])
    }

    @Test func picksTheReferenceNearestTheClick() throws {
        let text = "Section 1 and Section 2"
        let offset = (text as NSString).range(of: "Section 2").location + 3
        #expect(ReferenceExtractor.reference(in: text, nearestTo: offset)?.identifier == "2")
        #expect(ReferenceExtractor.reference(in: text, nearestTo: 0)?.identifier == "1")
    }

    @Test func findsReferenceUnderPointOnPage() throws {
        let src = scratchURL("source.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        writeLinesPDF(at: src, lines: ["Fees are payable as set out in", "Section 4.2 of the Master Agreement."])
        let doc = try PDFDocumentCore(filePath: src.path)
        let page = try #require(doc.loadStructuredPage(for: 0))
        let line = try #require(page.blocks.flatMap(\.lines).first { $0.text.contains("Section 4.2") })
        let four = try #require(line.characters.first { $0.char == "4" })
        let click = CGPoint(x: four.boundingRect.midX, y: four.boundingRect.midY)

        let ref = try #require(ReferenceExtractor.reference(at: click, on: page))
        #expect(ref.identifier == "4.2")
        #expect(ref.docHint == "Master Agreement")
        let rect = try #require(ref.sourceRect)
        #expect(rect.contains(click))
    }
}

@Suite struct CrossDocReferenceMatcherTests {
    private let section42 = reference("Section 4.2")!

    @Test func outlineHeadings() {
        #expect(CrossDocReferenceMatcher.outlineScore(title: "Section 4.2 – Payment", for: section42) == 100)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "4.2 Payment Terms", for: section42) == 85)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "4.2. Payment Terms", for: section42) == 85)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "Article 4.2 Payment", for: section42) == 80)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "4.25 Other", for: section42) == nil)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "4.2.1 Invoices", for: section42) == nil)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "Table 4.2", for: section42) == nil)
    }

    @Test func subItemFallsBackToItsSection() {
        let ref = reference("Section 4.2(b)")!
        #expect(CrossDocReferenceMatcher.outlineScore(title: "4.2 Payment Terms", for: ref) == 60)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "4.2(b) Late Payment", for: ref) == 85)
    }

    @Test func letteredAppendixNeedsItsLabel() {
        let ref = reference("Appendix C")!
        #expect(CrossDocReferenceMatcher.outlineScore(title: "Appendix C – Pricing", for: ref) == 100)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "Schedule C", for: ref) == 80)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "C. Pricing", for: ref) == nil)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "Appendix CD", for: ref) == nil)
    }

    @Test func bareSubclauseAgainstOutline() {
        let ref = reference("defined in 35.5.2.3.1 (General), where")!
        #expect(CrossDocReferenceMatcher.outlineScore(title: "35.5.2.3.1 General", for: ref) == 95)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "35.5.2.3.1 Overview", for: ref) == 85)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "35.5.2.3 Non-AP STA behavior", for: ref) == nil)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "35.5.2.3.10 Other", for: ref) == nil)
        #expect(CrossDocReferenceFinder.searchQueries(for: ref) == ["35.5.2.3.1"])
    }

    @Test func quotedTitleAgainstNumberedHeading() {
        let ref = reference("“Payment Terms”")!
        #expect(CrossDocReferenceMatcher.outlineScore(title: "4.2 Payment Terms", for: ref) == 90)
        #expect(CrossDocReferenceMatcher.outlineScore(title: "Payment", for: ref) == nil)
    }

    @Test func headingHitsVersusMentions() {
        func score(_ prefix: String, _ hit: String, _ suffix: String, bold: Bool = false) -> Int? {
            CrossDocReferenceMatcher.headingHitScore(prefix: prefix, hit: hit, suffix: suffix, isEmphasised: bold, for: section42)
        }
        #expect(score("", "Section 4.2", " Payment Terms") == 80)
        #expect(score("", "4.2", " Payment Terms", bold: true) == 75)
        #expect(score("see ", "Section 4.2", " of the Agreement") == nil)
        #expect(score("", "4.2", "5 Other") == nil)
        #expect(score("", "4.2", ".1 Invoices") == nil)
        // Prose that happens to start a line, and table-of-contents entries, rank below the cut.
        #expect(score("", "4.2", " percent of the fee")! < CrossDocReferenceMatcher.minimumScore)
        #expect(score("", "4.2", " Payment Terms ........ 12")! < CrossDocReferenceMatcher.minimumScore)
    }

    @Test func documentHint() {
        #expect(CrossDocReferenceMatcher.docHintAdjustment(documentTitle: "Master Services Agreement.pdf", hint: "Master Services Agreement") == 20)
        // Its initials count as its name.
        #expect(CrossDocReferenceMatcher.docHintAdjustment(documentTitle: "MSA - Master Agreement v3.pdf", hint: "Master Services Agreement") == 20)
        #expect(CrossDocReferenceMatcher.docHintAdjustment(documentTitle: "Supply - Master Agreement v3.pdf", hint: "Master Services Agreement") == 8)
        #expect(CrossDocReferenceMatcher.docHintAdjustment(documentTitle: "MSA_final.pdf", hint: "Master Services Agreement") == 20)
        #expect(CrossDocReferenceMatcher.docHintAdjustment(documentTitle: "Schedule 2.pdf", hint: "Master Agreement") == -10)
        #expect(CrossDocReferenceMatcher.docHintAdjustment(documentTitle: "Anything.pdf", hint: nil) == 0)
    }

    @Test func confidenceAndRanking() {
        #expect(CrossDocReferenceMatcher.isConfident([90, 60]))
        #expect(CrossDocReferenceMatcher.isConfident([85]))
        #expect(!CrossDocReferenceMatcher.isConfident([85, 80]))
        #expect(!CrossDocReferenceMatcher.isConfident([70]))

        let ranked = CrossDocReferenceMatcher.rank([30, 90, 85, 50, 90], limit: 3, score: { $0 }, sameTarget: { $0 == $1 })
        #expect(ranked == [90, 85, 50])
    }
}

@MainActor
@Suite struct CrossDocReferenceFinderTests {
    @Test func findsTheHeadingNotTheMentionInAnotherDocument() async throws {
        let src = scratchURL("Master Agreement.pdf")
        defer { try? FileManager.default.removeItem(at: src) }
        writeLinesPDF(at: src, lines: [
            "Under Section 4.2 the fee is fixed.",
            "4.2 Payment Terms",
            "Fees are due within thirty days."
        ])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: src.path)

        let ref = try #require(reference("Section 4.2 of the Master Agreement"))
        let candidates = await CrossDocReferenceFinder.candidates(for: ref, in: [vm])
        let best = try #require(candidates.first)
        #expect(best.heading == "4.2 Payment Terms")
        #expect(best.viewModel === vm)
        #expect(best.target.targetPage == 0)
        #expect(!candidates.contains { $0.heading.hasPrefix("Under") })
    }

    @Test func sameHeadingInTwoTabsIsStillConfident() {
        let a = PDFViewerViewModel(), b = PDFViewerViewModel()
        let target = SnapshotTarget(label: "12.7.1.3", targetPage: 0)
        func candidate(_ vm: PDFViewerViewModel, _ score: Int) -> ReferenceCandidate {
            ReferenceCandidate(viewModel: vm, documentTitle: "", heading: "12.7.1.3 Pairwise key hierarchy", target: target, score: score)
        }
        // Another draft (or an amendment) with the same clause is not doubt about the heading…
        #expect(CrossDocReferenceFinder.isConfident([candidate(a, 85), candidate(b, 85)]))
        // …but two near-equal headings in one document are.
        #expect(!CrossDocReferenceFinder.isConfident([candidate(a, 85), candidate(a, 85)]))
    }

    @Test func untabbedViewModelIsItsOwnGroup() {
        let vm = PDFViewerViewModel()
        let group = PDFViewerAppCoordinator.shared.tabGroupViewModels(of: vm)
        #expect(group.count == 1 && group[0] === vm)
    }
}
