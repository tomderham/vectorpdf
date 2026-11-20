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
import Security
import Testing
@testable import PDFEngine

/// A certificate authority and a signer it certified, made with the openssl tool for a test and
/// thrown away after it: the signer as a .p12 file, and the authority's certificate to trust.
struct TestSigner {
    let p12: Data
    let password = "vectorpdf-test"
    let authority: SecCertificate

    init(in dir: URL) throws {
        func openssl(_ args: String...) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = args
            process.currentDirectoryURL = dir
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw PDFError.operationFailed("openssl \(args.first ?? "") failed") }
        }
        try openssl("req", "-x509", "-newkey", "rsa:2048", "-nodes", "-keyout", "ca.key", "-out", "ca.pem", "-days", "2",
                    "-subj", "/CN=VectorPDF Signing Test CA/O=VectorPDF Tests",
                    "-addext", "basicConstraints=critical,CA:TRUE", "-addext", "keyUsage=critical,keyCertSign,cRLSign")
        try openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", "signer.key", "-out", "signer.csr",
                    "-subj", "/CN=Signing Test Person/O=VectorPDF Tests/emailAddress=person@example.com")
        try "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,nonRepudiation\n".write(to: dir.appendingPathComponent("signer.ext"), atomically: true, encoding: .utf8)
        try openssl("x509", "-req", "-in", "signer.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
                    "-out", "signer.pem", "-days", "2", "-extfile", "signer.ext")
        try openssl("pkcs12", "-export", "-inkey", "signer.key", "-in", "signer.pem", "-certfile", "ca.pem", "-out", "signer.p12",
                    "-passout", "pass:\(password)", "-certpbe", "PBE-SHA1-3DES", "-keypbe", "PBE-SHA1-3DES", "-macalg", "sha1")
        p12 = try Data(contentsOf: dir.appendingPathComponent("signer.p12"))
        let pem = try String(contentsOf: dir.appendingPathComponent("ca.pem"), encoding: .utf8)
        let der = try #require(Data(base64Encoded: pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()))
        authority = try #require(SecCertificateCreateWithData(nil, der as CFData))
        // A timestamp authority, certified by the same authority, answering with openssl ts.
        try "basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature\nextendedKeyUsage=critical,timeStamping\n".write(
            to: dir.appendingPathComponent("tsa.ext"), atomically: true, encoding: .utf8)
        try openssl("req", "-newkey", "rsa:2048", "-nodes", "-keyout", "tsa.key", "-out", "tsa.csr", "-subj", "/CN=VectorPDF Test Timestamps/O=VectorPDF Tests")
        try openssl("x509", "-req", "-in", "tsa.csr", "-CA", "ca.pem", "-CAkey", "ca.key", "-CAcreateserial",
                    "-out", "tsa.pem", "-days", "2", "-extfile", "tsa.ext")
        try """
        [ tsa ]
        default_tsa = tsa_config
        [ tsa_config ]
        dir = \(dir.path)
        serial = \(dir.path)/tsaserial
        signer_cert = \(dir.path)/tsa.pem
        certs = \(dir.path)/ca.pem
        signer_key = \(dir.path)/tsa.key
        default_policy = 1.2.3.4.1
        digests = sha256
        signer_digest = sha256
        accuracy = secs:1
        ordering = yes
        tsa_name = no
        ess_cert_id_chain = no
        """.write(to: dir.appendingPathComponent("tsa.cnf"), atomically: true, encoding: .utf8)
        try "01\n".write(to: dir.appendingPathComponent("tsaserial"), atomically: true, encoding: .utf8)
        self.dir = dir
        for name in ["ca.key", "signer.key"] { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
    }

    let dir: URL

    /// The test timestamp authority: each request answered by openssl ts -reply.
    var timestampAuthority: TimestampAuthority {
        let dir = self.dir
        return TimestampAuthority(url: URL(string: "http://localhost/tsa")!) { request in
            let query = dir.appendingPathComponent("request-\(UUID().uuidString).tsq"), reply = dir.appendingPathComponent("reply.tsr")
            try request.write(to: query)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
            process.arguments = ["ts", "-reply", "-queryfile", query.path, "-config", dir.appendingPathComponent("tsa.cnf").path, "-out", reply.path]
            process.currentDirectoryURL = dir
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return try Data(contentsOf: reply)
        }
    }

    func identity() throws -> SigningIdentity { try SigningIdentity.fromPKCS12(p12, password: password) }
}

@Suite(.serialized) struct DigitalSigningTests {
    @Test func aP12IdentityIsReadWithItsChain() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let identity = try signer.identity()
        #expect(identity.name == "Signing Test Person")
        #expect(identity.organization == "VectorPDF Tests")
        #expect(identity.email == "person@example.com")
        #expect(identity.issuer == "VectorPDF Signing Test CA")
        #expect(identity.chain.count == 1)
        #expect(identity.canSign)
        #expect(throws: SigningIdentity.ImportError.self) { try SigningIdentity.fromPKCS12(signer.p12, password: "wrong") }
    }

    /// A new signature field, signed and saved, checks out: intact, covering the whole file, and
    /// trusted once its authority is.
    @Test func signingANewFieldMakesAValidSignature() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Agreement.pdf")
        makeLabelledPDF(at: url, labels: ["Terms", "Signatures"])
        let doc = try PDFDocumentCore(filePath: url.path)
        let signature = try doc.sign(page: 1, rect: CGRect(x: 72, y: 600, width: 200, height: 60), with: signer.identity(),
                                     appearance: .init(reason: "I agree", location: "Example City"))
        try doc.save(to: url.path)
        #expect(signature.failure == nil)

        let results = try PDFDocumentCore(filePath: url.path).validateSignatures(extraAnchors: [signer.authority])
        let result = try #require(results.first)
        #expect(results.count == 1)
        #expect(result.integrity == .intact)
        #expect(result.changes == .none)
        #expect(result.identity == .trusted)
        #expect(result.signerName == "Signing Test Person")
        #expect(result.issuerName == "VectorPDF Signing Test CA")
        #expect(result.reason == "I agree" && result.location == "Example City")
        #expect(result.pageIndex == 1)
        #expect(result.certificates.count == 2)
        #expect(abs((result.claimedSigningTime ?? .distantPast).timeIntervalSinceNow) < 120)

        // Without trusting the authority, the document is still unchanged.
        let untrusted = try #require(PDFDocumentCore(filePath: url.path).validateSignatures().first)
        #expect(untrusted.isIntact && untrusted.identity != .trusted)
    }

    /// A second signature on a signed document leaves the first one valid.
    @Test func signingASignedDocumentKeepsTheFirstSignature() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Signed.pdf")
        try FileManager.default.copyItem(at: Fixture.signedValid, to: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.sign(page: 0, rect: CGRect(x: 300, y: 100, width: 200, height: 60), with: signer.identity())
        try doc.save(to: url.path)

        let results = try PDFDocumentCore(filePath: url.path).validateSignatures(extraAnchors: [signer.authority])
        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.integrity == .intact })
        #expect(results.map(\.changes).sorted { "\($0)" < "\($1)" } == [.allowed, .none])
        #expect(results.contains { $0.signerName == "Signing Test Person" && $0.identity == .trusted })
        #expect(results.contains { $0.signerName == "VectorPDF Test Signer" })
    }

    /// A timestamp from an authority is added to the signature, and checking reports its time.
    @Test func aTimestampIsAddedAndChecked() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Stamped.pdf")
        makeLabelledPDF(at: url, labels: ["One"])
        let doc = try PDFDocumentCore(filePath: url.path)
        let signature = try doc.sign(page: 0, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity(),
                                     timestamp: signer.timestampAuthority)
        try doc.save(to: url.path)
        #expect(signature.failure == nil)
        let result = try #require(PDFDocumentCore(filePath: url.path).validateSignatures(extraAnchors: [signer.authority]).first)
        #expect(result.integrity == .intact && result.changes == PDFSignatureValidation.Changes.none)
        #expect(result.identity == .trusted)
        let stamped = try #require(result.timestamp)
        #expect(abs(stamped.timeIntervalSinceNow) < 120)
        #expect(result.timestampProblem == nil)
        // Its authority not trusted: the signature still checks out, the timestamp isn't counted.
        let untrusted = try #require(PDFDocumentCore(filePath: url.path).validateSignatures().first)
        #expect(untrusted.isIntact && untrusted.timestamp == nil)
        #expect(untrusted.timestampProblem?.contains("isn't trusted") == true)

        // A server that can't be reached stops the signing, leaving the file as it was.
        let before = try Data(contentsOf: url)
        let unreachable = TimestampAuthority(url: URL(string: "http://localhost/none")!) { _ in throw TimestampAuthority.Failure.unreachable("test") }
        let again = try PDFDocumentCore(filePath: url.path)
        let failed = try again.sign(page: 0, rect: CGRect(x: 300, y: 100, width: 200, height: 60), with: signer.identity(), timestamp: unreachable)
        #expect(throws: (any Error).self) { try again.save(to: url.path) }
        #expect(failed.failure?.contains("couldn't be reached") == true)
        #expect(try Data(contentsOf: url) == before)
    }

    /// A certifying signature allows what it says: form filling and signing here, so another
    /// signature is fine and a comment isn't. Only a document's first signature can certify.
    @Test func aCertificationAllowsWhatItSays() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Certified.pdf")
        makeLabelledPDF(at: url, labels: ["One", "Two"])
        let doc = try PDFDocumentCore(filePath: url.path)
        try doc.sign(page: 0, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity(),
                     permissions: .init(certification: .formFillingAndSigning))
        try doc.save(to: url.path)
        let certified = try PDFDocumentCore(filePath: url.path)
        let field = try #require(certified.formFieldEntries(pageIndex: 0).first { $0.type == .signature })
        #expect(field.signature?.certification == .formFillingAndSigning)
        #expect(throws: (any Error).self) {
            try certified.sign(page: 1, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity(),
                               permissions: .init(certification: .noChanges))
        }

        // Another signature: allowed.
        let again = try PDFDocumentCore(filePath: url.path)
        try again.sign(page: 1, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity())
        try again.save(to: url.path)
        var results = try PDFDocumentCore(filePath: url.path).validateSignatures(extraAnchors: [signer.authority])
        #expect(results.first { $0.fieldName == "Signature1" }?.changes == .allowed)

        // A comment: not.
        let commented = try PDFDocumentCore(filePath: url.path)
        try commented.addNote(pageIndex: 0, rect: CGRect(x: 300, y: 300, width: 20, height: 20), text: "Hmm", red: 1, green: 1, blue: 0)
        try commented.save(to: url.path)
        results = try PDFDocumentCore(filePath: url.path).validateSignatures(extraAnchors: [signer.authority])
        #expect(results.first { $0.fieldName == "Signature1" }?.changes == .notAllowed)
    }

    /// A signature can lock the form's fields, all or those chosen: they become read-only.
    @Test func aSignatureLocksTheFieldsChosen() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Form.pdf")
        try FileManager.default.copyItem(at: Fixture.form1040, to: url)
        let doc = try PDFDocumentCore(filePath: url.path)
        let fields = doc.formFieldEntries(pageIndex: 0).filter { $0.type == .text && !$0.isReadOnly }
        #expect(fields.count >= 3)
        let chosen = Array(fields.prefix(2)).map(\.name)
        try doc.sign(page: 0, rect: CGRect(x: 400, y: 20, width: 150, height: 40), with: signer.identity(),
                     permissions: .init(lock: .fields(chosen)))
        try doc.save(to: url.path)
        let signed = try PDFDocumentCore(filePath: url.path)
        let after = Dictionary(signed.formFieldEntries(pageIndex: 0).map { ($0.name, $0.isReadOnly) }, uniquingKeysWith: { a, _ in a })
        #expect(chosen.allSatisfy { after[$0] == true })
        #expect(after[fields[2].name] == false)
        let result = try #require(signed.validateSignatures(extraAnchors: [signer.authority]).first { $0.signerName == "Signing Test Person" })
        #expect(result.isIntact)
    }

    /// Signed twice here: the first signature allows the second, and doesn't lock the form's
    /// other fields.
    @Test func aSecondSignatureIsAllowedByTheFirst() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Twice.pdf")
        makeLabelledPDF(at: url, labels: ["One", "Two"])
        let first = try PDFDocumentCore(filePath: url.path)
        try first.sign(page: 0, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity())
        try first.save(to: url.path)
        let once = try PDFDocumentCore(filePath: url.path)
        try once.sign(page: 1, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity())
        try once.save(to: url.path)

        let results = try PDFDocumentCore(filePath: url.path).validateSignatures(extraAnchors: [signer.authority])
        #expect(results.map(\.fieldName).sorted() == ["Signature1", "Signature2"])
        #expect(results.allSatisfy { $0.isFullyValid })
        #expect(results.first { $0.fieldName == "Signature1" }?.changes == .allowed)
        #expect(results.first { $0.fieldName == "Signature2" }?.changes == PDFSignatureValidation.Changes.none)
        #expect(results.map(\.pageIndex).sorted { ($0 ?? -1) < ($1 ?? -1) } == [0, 1])
    }
}

/// Signing in the window: placing the field, signing and saving, and opening the result.
@MainActor
@Suite(.serialized) struct DigitalSigningViewModelTests {
    @Test func placingAndSigningSavesAValidSignature() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Form.pdf")
        makeLabelledPDF(at: url, labels: ["One", "Two"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        // Unsaved changes are saved first.
        vm.isDocumentEdited = true
        vm.beginCertificateSignature()
        #expect(!vm.isDocumentEdited)
        #expect(vm.canvasMode == .placeSignatureField)
        vm.placeCertificateSignature(page: 1, at: CGPoint(x: 5, y: 5))
        #expect(vm.canvasMode == .select)
        let placement = try #require(vm.certificateSignaturePlacement)
        // Kept on the page, at its corner.
        #expect(placement.page == 1 && placement.rect.minX == 0 && placement.rect.size == PDFViewerViewModel.certificateSignatureSize)

        #expect(await vm.completeCertificateSignature(placement, with: try signer.identity(), appearance: .init(reason: "Approved")))
        #expect(vm.certificateSignaturePlacement == nil)
        #expect(!vm.isDocumentEdited)
        await vm.waitForSignatureCheck()
        let result = try #require(vm.signatureValidations?.first)
        // Whether its signer is trusted is up to the Mac (the test authority isn't): checked above.
        #expect(result.isIntact && result.changes == .none && result.reason == "Approved" && result.pageIndex == 1)
        #expect(result.signerName == "Signing Test Person")
    }

    /// The signed file is opened once, and then stays open: each reload used to set off another,
    /// until the app ran out of files to open.
    @Test func signingDoesNotKeepReloading() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: url, labels: ["One"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        let placement = CertificateSignaturePlacement(page: 0, widgetIndex: nil, rect: CGRect(x: 10, y: 10, width: 200, height: 60))
        #expect(await vm.completeCertificateSignature(placement, with: try signer.identity(), appearance: .init()))
        let signed = try #require(vm.document)
        try await Task.sleep(nanoseconds: 2_000_000_000)
        #expect(vm.document === signed)
    }

    /// A box dragged out is where the field goes; the sheet's preview is drawn at its size.
    @Test func aDraggedBoxIsTheFieldAndItsPreviewIsDrawn() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: url, labels: ["One"])
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        vm.canvasMode = .placeSignatureField
        vm.placeCertificateSignature(page: 0, in: CGRect(x: 100, y: 500, width: 240, height: 80))
        let placement = try #require(vm.certificateSignaturePlacement)
        #expect(placement.rect == CGRect(x: 100, y: 500, width: 240, height: 80))
        #expect(vm.canvasMode == .select)
        // Too small a box is made big enough.
        vm.placeCertificateSignature(page: 0, in: CGRect(x: 100, y: 500, width: 10, height: 5))
        #expect(vm.certificateSignaturePlacement?.rect.size == CGSize(width: 60, height: 20))

        let image = try #require(vm.document?.signaturePreview(size: placement.rect.size, scale: 2, name: "Signing Test Person",
                                                               appearance: .init(reason: "Approved")))
        #expect(image.width == 480 && image.height == 160)
    }

    /// A field that can't be signed leaves the file as it was.
    @Test func aFailedSignatureLeavesTheFileAlone() async throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let url = dir.appendingPathComponent("Plain.pdf")
        makeLabelledPDF(at: url, labels: ["One"])
        let before = try Data(contentsOf: url)
        let vm = PDFViewerViewModel()
        await vm.loadDocument(from: url.path)
        let placement = CertificateSignaturePlacement(page: 0, widgetIndex: 0, rect: CGRect(x: 0, y: 0, width: 10, height: 10))
        #expect(await vm.completeCertificateSignature(placement, with: try signer.identity(), appearance: .init()) == false)
        #expect(try Data(contentsOf: url) == before)
        #expect(!vm.isDocumentEdited && vm.document != nil)
    }
}
