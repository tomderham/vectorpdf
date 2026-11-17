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

import Foundation
import PDFKit
import Security
import Testing
@testable import PDFEngine

/// Digital signatures are checked: the signed bytes, later saves, and the signer's certificate.
struct SignatureValidationTests {
    /// The certificate authority that issued the test signer's certificate.
    private func testAuthority() throws -> SecCertificate {
        let pem = try String(contentsOf: Fixture.signedSampleCA, encoding: .utf8)
        let base64 = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        let der = try #require(Data(base64Encoded: base64))
        return try #require(SecCertificateCreateWithData(nil, der as CFData))
    }

    private func validate(_ url: URL, trusting anchors: [SecCertificate] = []) throws -> PDFSignatureValidation {
        let doc = try PDFDocumentCore(filePath: url.path)
        let results = doc.validateSignatures(extraAnchors: anchors)
        #expect(results.count == 1)
        return try #require(results.first)
    }

    @Test func aValidSignatureFromATrustedAuthority() throws {
        let result = try validate(Fixture.signedValid, trusting: [testAuthority()])
        #expect(result.integrity == .intact)
        #expect(result.changes == .none)
        #expect(result.identity == .trusted)
        #expect(result.isFullyValid && !result.hasProblems)
        #expect(result.signerName == "VectorPDF Test Signer")
        #expect(result.signerEmail == "signer@example.com")
        #expect(result.issuerName == "VectorPDF Test CA")
        #expect(result.certificates.count == 2)
        #expect(result.statusLine == "Valid and unchanged since it was signed")
    }

    /// Anyone can make a certificate in any name: without a trusted issuer, the identity isn't
    /// vouched for, though the document is unchanged.
    @Test func aCertificateThisMacDoesntTrustIsntVerified() throws {
        let result = try validate(Fixture.signedValid)
        #expect(result.integrity == .intact)
        #expect(result.isIntact && !result.isFullyValid && !result.hasProblems)
        let reason = try #require(result.identityDetail)
        #expect(reason.contains("VectorPDF Test CA"))
        #expect(result.statusLine.contains("identity isn't verified"))
    }

    @Test func changingASignedByteBreaksIt() throws {
        let result = try validate(Fixture.signedTampered, trusting: [testAuthority()])
        #expect(result.integrity == .modified)
        #expect(result.hasProblems && !result.isIntact)
        #expect(result.statusLine.hasPrefix("Invalid"))
    }

    /// A save after signing that only adds document information is allowed: the signature
    /// doesn't lock it.
    @Test func aSaveAfterSigningIsReported() throws {
        let result = try validate(Fixture.signedThenChanged, trusting: [testAuthority()])
        #expect(result.integrity == .intact)
        #expect(result.changes == .allowed)
        #expect(result.isFullyValid)
        #expect(result.statusLine.contains("after signing"))
    }

    /// A save after signing that replaces the signed page's text isn't.
    @Test func aDisallowedChangeAfterSigningBreaksIt() throws {
        let result = try validate(Fixture.signedThenPageChanged, trusting: [testAuthority()])
        #expect(result.integrity == .intact)
        #expect(result.changes == .notAllowed)
        #expect(result.hasProblems && !result.isIntact)
        #expect(result.statusLine.hasPrefix("Invalid"))
    }

    @Test func aDocumentWithoutSignaturesHasNone() throws {
        let doc = try PDFDocumentCore(filePath: Fixture.form1040.path)
        #expect(doc.signedSignatureObjectNumbers().isEmpty)
        #expect(doc.validateSignatures().isEmpty)
    }

    @Test func paddingAfterTheSignatureIsTrimmed() {
        let der = Data([0x30, 0x82, 0x00, 0x03, 1, 2, 3])
        #expect(SignatureValidator.trimmedDER(der + Data(count: 10)) == der)
        #expect(SignatureValidator.trimmedDER(Data([0x30, 0x05, 1])) == nil)
        #expect(SignatureValidator.trimmedDER(Data(count: 8)) == nil)
    }
}

/// A signed document's window checks its signatures when it opens and says what it found.
@MainActor
@Suite(.serialized) struct SignatureBannerTests {
    private func open(_ url: URL, trusted: Bool) async throws -> PDFViewerViewModel {
        if trusted {
            let pem = try String(contentsOf: Fixture.signedSampleCA, encoding: .utf8)
            let der = try #require(Data(base64Encoded: pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()))
            PDFViewerViewModel.extraSignatureAnchors = [try #require(SecCertificateCreateWithData(nil, der as CFData))]
        }
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        await vm.waitForSignatureCheck()
        return vm
    }

    @Test func aValidSignatureIsSaidToBe() async throws {
        defer { PDFViewerViewModel.extraSignatureAnchors = [] }
        let vm = try await open(Fixture.signedValid, trusted: true)
        #expect(vm.documentContentsSummary.signatureCount == 1)
        #expect(vm.documentSidebarSections.contains(.signatures))
        #expect(vm.signatureValidations?.count == 1)
        let banner = try #require(vm.signatureBanner)
        #expect(banner.kind == .valid)
        #expect(banner.message == "Signed by VectorPDF Test Signer. The signature is valid")
        // Where it is, for Show on Page.
        let result = try #require(vm.signatureValidations?.first)
        #expect(result.pageIndex == 0)
        #expect(abs(result.rect.minX - 72) < 0.5 && abs(result.rect.minY - 142) < 0.5)
        #expect(result.reason == "Approval" && result.location == "Test")

        vm.isSignatureBannerDismissed = true
        #expect(vm.signatureBanner == nil)
    }

    @Test func anUntrustedSignerIsntVouchedFor() async throws {
        let vm = try await open(Fixture.signedValid, trusted: false)
        #expect(vm.signatureBanner?.kind == .unverified)
    }

    @Test func anInvalidSignatureIsSaidToBe() async throws {
        defer { PDFViewerViewModel.extraSignatureAnchors = [] }
        let vm = try await open(Fixture.signedTampered, trusted: true)
        #expect(vm.signatureBanner?.kind == .invalid)
        #expect(vm.signatureBanner?.message == "The signature by VectorPDF Test Signer is invalid")
    }

    @Test func anUnsignedDocumentHasNoBanner() async throws {
        let vm = try await open(Fixture.form1040, trusted: false)
        #expect(vm.signatureValidations == nil)
        #expect(vm.signatureBanner == nil)
        #expect(!vm.documentSidebarSections.contains(.signatures))
    }
}

/// Saving a signed document adds the changes after what was signed, rather than rewriting the
/// file, so its signatures stay valid where the changes are allowed.
@MainActor
@Suite(.serialized) struct SignedDocumentSavingTests {
    @Test func savingTwiceKeepsTheSignatureAndBothChanges() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Signed.pdf")
        try FileManager.default.copyItem(at: Fixture.signedValid, to: url)
        let original = try Data(contentsOf: url)
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        await vm.waitForSignatureCheck()
        #expect(vm.signatureValidations?.first?.changes == PDFSignatureValidation.Changes.none)

        try #require(vm.addShapeAnnotation(pageIndex: 0, shape: .rectangle, from: CGPoint(x: 100, y: 100), to: CGPoint(x: 200, y: 200)) != nil)
        vm.saveDocument()
        try #require(vm.addShapeAnnotation(pageIndex: 0, shape: .oval, from: CGPoint(x: 300, y: 100), to: CGPoint(x: 400, y: 200)) != nil)
        vm.saveDocument()
        await vm.waitForSignatureCheck()

        let saved = try Data(contentsOf: url)
        // What was signed is still there, byte for byte.
        #expect(saved.prefix(original.count) == original)
        let page = try #require(PDFKit.PDFDocument(url: url)?.page(at: 0))
        #expect(page.annotations.filter { $0.type == "Square" }.count == 1)
        #expect(page.annotations.filter { $0.type == "Circle" }.count == 1)
        let result = try #require(vm.signatureValidations?.first)
        #expect(result.integrity == .intact)
        // Comments the signature allows, though MuPDF alone doesn't.
        #expect(result.changes == .commentsChanged)
        #expect(result.isIntact && !result.hasProblems)
    }
}
