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

/// Signatures made to mislead: byte ranges that leave more than the signature unsigned or point
/// outside the file, and timestamps that aren't what they claim.
@Suite(.serialized) struct SignatureHardeningTests {
    private func data(_ ranges: [(Int64, Int64)], contents: Data) -> PDFSignatureData {
        PDFSignatureData(objectNumber: 1, byteRanges: ranges.map { (offset: $0.0, length: $0.1) }, hasMoreRanges: false,
                         contents: contents, subFilter: "adbe.pkcs7.detached", laterChangesBreakIt: 0,
                         laterChangesAllowed: true, laterChangesOnlyComments: false, pageIndex: 0, rect: .zero,
                         fieldName: "Signature1", nameInDocument: nil, reason: nil, location: nil)
    }

    /// A file of `before`, the hex string of `contents`, then `after`; and the ranges around it.
    private func file(before: String, contents: Data, after: String) -> (Data, [(Int64, Int64)]) {
        let hex = "<" + contents.map { String(format: "%02X", $0) }.joined() + ">"
        let bytes = Data((before + hex + after).utf8)
        let gapStart = Int64(before.utf8.count), gapEnd = gapStart + Int64(hex.utf8.count)
        return (bytes, [(0, gapStart), (gapEnd, Int64(bytes.count) - gapEnd)])
    }

    @Test func aGapThatIsTheSignatureCoversTheFile() {
        let contents = Data([0x30, 0x03, 0x02, 0x01, 0x05, 0, 0, 0])
        let (bytes, ranges) = file(before: "1 0 obj <</Contents ", contents: contents, after: ">> endobj\n%%EOF\n")
        #expect(SignatureValidator.changes(data(ranges, contents: contents), fileLength: Int64(bytes.count), file: bytes) == .none)
    }

    /// A gap from an earlier < to the signature's > leaves what's between unsigned.
    @Test func aGapWithMoreThanTheSignatureIsPartial() {
        let contents = Data([0x30, 0x03, 0x02, 0x01, 0x05])
        let hex = "<" + contents.map { String(format: "%02X", $0) }.joined() + ">"
        let text = "1 0 obj <</Evil (unsigned) /Contents " + hex + ">> endobj\n%%EOF\n"
        let bytes = Data(text.utf8)
        // All ASCII: characters are bytes.
        let gapStart = Int64(text.distance(from: text.startIndex, to: text.range(of: "<</Evil")!.lowerBound))
        let gapEnd = Int64(text.distance(from: text.startIndex, to: text.range(of: hex)!.upperBound))
        let ranges: [(Int64, Int64)] = [(0, gapStart), (gapEnd, Int64(bytes.count) - gapEnd)]
        #expect(SignatureValidator.changes(data(ranges, contents: contents), fileLength: Int64(bytes.count), file: bytes) == .partialCoverage)
    }

    /// A hex string that isn't the signature's (its digits changed) doesn't count either.
    @Test func aGapThatIsAnotherHexStringIsPartial() {
        let contents = Data([0x30, 0x03, 0x02, 0x01, 0x05])
        let (bytes, ranges) = file(before: "<</Contents ", contents: Data([0x30, 0x03, 0x02, 0x01, 0x06]), after: ">>")
        #expect(SignatureValidator.changes(data(ranges, contents: contents), fileLength: Int64(bytes.count), file: bytes) == .partialCoverage)
    }

    /// Ranges outside the file, negative or so long they overflow, are reported, not a crash.
    @Test func rangesOutsideTheFileDontCrash() {
        let bytes = Data(repeating: 0x20, count: 64)
        for ranges: [(Int64, Int64)] in [[(0, -10), (20, 10)], [(0, 10), (-5, 10)], [(0, 10), (20, .max)],
                                         [(0, .max), (20, 10)], [(0, 10), (.max, 1)], [(0, 100), (20, 10)]] {
            let signature = data(ranges, contents: Data([0x30, 0x00]))
            #expect(SignatureValidator.changes(signature, fileLength: Int64(bytes.count), file: bytes) == .partialCoverage)
            #expect(SignatureValidator.signedBytes(signature, file: bytes) == nil)
        }
    }

    @Test func hexStringsAreDecodedAsPDFReadsThem() {
        #expect(SignatureValidator.isSignatureHexString(Data("<30 0a\n1F>".utf8), contents: Data([0x30, 0x0A, 0x1F])))
        // An odd last digit is followed by a 0.
        #expect(SignatureValidator.isSignatureHexString(Data("<301>".utf8), contents: Data([0x30, 0x10])))
        #expect(!SignatureValidator.isSignatureHexString(Data("<30>>".utf8), contents: Data([0x30])))
        #expect(!SignatureValidator.isSignatureHexString(Data("<<30>".utf8), contents: Data([0x30])))
    }

    /// A signature in BER of indefinite length (as some software writes it) is read.
    @Test func anIndefiniteLengthSignatureIsTrimmed() throws {
        // SEQUENCE (indefinite) { INTEGER 5 } end, then padding.
        let ber = Data([0x30, 0x80, 0x02, 0x01, 0x05, 0x00, 0x00, 0x00, 0x00, 0x00])
        #expect(SignatureValidator.trimmedDER(ber) == Data([0x30, 0x03, 0x02, 0x01, 0x05]))
    }

    /// Only the timestamp authority's certificate counts as one; the signer's and the
    /// authority's own aren't certificates for signing.
    @Test func certificatesAreToldApartByTheirExtensions() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        func certificate(_ name: String) throws -> SecCertificate {
            let pem = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
            let der = try #require(Data(base64Encoded: pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()))
            return try #require(SecCertificateCreateWithData(nil, der as CFData))
        }
        #expect(Timestamps.isTimestampingCertificate(try certificate("tsa.pem")))
        #expect(!Timestamps.isTimestampingCertificate(try certificate("signer.pem")))
        #expect(!Timestamps.isTimestampingCertificate(signer.authority))
        #expect(SigningIdentity.isCertificateAuthority(signer.authority))
        #expect(!SigningIdentity.isCertificateAuthority(try certificate("signer.pem")))
        #expect(try signer.identity().canSign)
    }

    /// A reply to another request (an earlier one, replayed) isn't taken as the timestamp.
    @Test func aReplayedTimestampReplyIsRefused() throws {
        let dir = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let signer = try TestSigner(in: dir)
        let real = signer.timestampAuthority
        let recorded = RecordedReply()
        let recording = TimestampAuthority(url: real.url) { request in
            let reply = try real.send(request)
            recorded.reply = reply
            return reply
        }
        let first = dir.appendingPathComponent("First.pdf")
        makeLabelledPDF(at: first, labels: ["One"])
        let doc = try PDFDocumentCore(filePath: first.path)
        try doc.sign(page: 0, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity(), timestamp: recording)
        try doc.save(to: first.path)
        let reply = try #require(recorded.reply)

        let second = dir.appendingPathComponent("Second.pdf")
        makeLabelledPDF(at: second, labels: ["Two"])
        let replaying = TimestampAuthority(url: real.url) { _ in reply }
        let other = try PDFDocumentCore(filePath: second.path)
        let failed = try other.sign(page: 0, rect: CGRect(x: 72, y: 100, width: 200, height: 60), with: signer.identity(), timestamp: replaying)
        #expect(throws: (any Error).self) { try other.save(to: second.path) }
        #expect(failed.failure?.contains("couldn't be read") == true)
    }
}

private final class RecordedReply: @unchecked Sendable {
    var reply: Data?
}
