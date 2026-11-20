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

import CoreGraphics
import CryptoKit
import Foundation
import MuPDFBridge
import Security

/// What a signature signs and with what, as the file holds it.
public struct PDFSignatureData: Sendable {
    /// The signature field's widget.
    public let objectNumber: Int
    /// The parts of the file signed: offsets into it as saved, and lengths.
    public let byteRanges: [(offset: Int64, length: Int64)]
    /// It lists more ranges than were read, which no proper signature does.
    public let hasMoreRanges: Bool
    /// The signature itself (DER, usually CMS), with the padding after it.
    public let contents: Data
    public let subFilter: String
    /// From MuPDF's check of the saves made after signing: 0 if they changed nothing the signature
    /// locks (or there are none), else how many saves ago it was broken; nil if it can't tell.
    public let laterChangesBreakIt: Int?
    /// When it does: whether those saves changed only comments and added only signatures, which
    /// a signature allows (comments unless it certifies the document for less).
    public let laterChangesAllowed: Bool
    /// Whether they changed comments, too.
    public let laterChangesOnlyComments: Bool
    /// Where it is: nil if its widget names no page. Page (top-down) coordinates.
    public let pageIndex: Int?
    public let rect: CGRect
    public let fieldName: String
    /// What the signature dictionary says, which the signer's software wrote: not checked.
    public let nameInDocument: String?
    public let reason: String?
    public let location: String?
}

/// What checking a signature found. Three things are told apart, as Acrobat does: whether the
/// signed bytes are the ones the signature was made over, whether the file was changed after
/// that, and whether the signer is who the certificate says (a chain to a certificate this Mac
/// trusts) — without the last, anyone could sign in anyone's name.
public struct PDFSignatureValidation: Sendable, Equatable {
    public let objectNumber: Int
    public var pageIndex: Int?
    /// Page (top-down) coordinates.
    public var rect: CGRect = .zero
    public var fieldName = ""
    /// The name, reason and location the signer's software wrote into the document.
    public var nameInDocument: String?
    public var reason: String?
    public var location: String?
    public var integrity: Integrity
    public var changes: Changes
    public var identity: Identity
    /// Who the certificate says signed: its common name, as Keychain Access shows it.
    public var signerName: String?
    public var signerEmail: String?
    /// The certificate's issuer, by name.
    public var issuerName: String?
    /// When the signer's computer says it was signed: not proof of anything.
    public var claimedSigningTime: Date?
    /// When a timestamp authority vouches it was signed: the time the certificate is checked at.
    public var timestamp: Date?
    /// Why a timestamp it carries isn't counted, if it has one that isn't.
    public var timestampProblem: String?
    /// The signer's certificate first, then the others the signature carries (DER), to show.
    public var certificates: [Data]

    public enum Integrity: Sendable, Equatable {
        /// The signed bytes are the ones it was made over.
        case intact
        /// The signed bytes have changed since, or the signature isn't the certificate's.
        case modified
        /// A kind of signature not checked yet (`SubFilter`).
        case unsupported(String)
        /// The signature or the parts of the file it says it covers can't be read.
        case malformed(String)
    }

    public enum Changes: Sendable, Equatable {
        /// It covers the whole file.
        case none
        /// Saved again after signing, with changes the signature allows: form filling, more
        /// signatures, document information.
        case allowed
        /// Saved again after signing, with comments added, changed or deleted (and perhaps the
        /// changes `allowed` allows): allowed, but a comment can cover what was signed.
        case commentsChanged
        /// Saved again after signing, with changes the signature doesn't allow.
        case notAllowed
        /// It doesn't cover the file from the start, or covers it with gaps besides its own.
        case partialCoverage
    }

    public enum Identity: Sendable, Equatable {
        /// The certificate chains to one this Mac trusts, and was valid when it signed.
        case trusted
        /// It doesn't, for the reason given.
        case notVerified(String)
    }

    /// Valid and unchanged in what it signed, whoever signed it.
    public var isIntact: Bool {
        integrity == .intact && (changes == .none || changes == .allowed || changes == .commentsChanged)
    }

    public var isFullyValid: Bool { isIntact && identity == .trusted }

    public var hasProblems: Bool {
        switch integrity {
        case .intact: return changes == .notAllowed || changes == .partialCoverage
        case .unsupported: return false
        case .modified, .malformed: return true
        }
    }

    /// One line on what it means, for the Document tab and the banner.
    public var statusLine: String {
        switch integrity {
        case .modified: return "Invalid: the document was changed after it was signed"
        case .malformed(let reason): return "Can't be checked: \(reason)"
        case .unsupported(let kind): return "Not checked: VectorPDF can't check \(kind) signatures yet"
        case .intact: break
        }
        switch changes {
        case .notAllowed: return "Invalid: the document was changed after it was signed, in a way the signature doesn't allow"
        case .partialCoverage: return "Invalid: the signature doesn't cover the whole document"
        case .none, .allowed, .commentsChanged: break
        }
        switch (identity, changes) {
        case (.trusted, .none): return "Valid and unchanged since it was signed"
        case (.trusted, .allowed): return "Valid. Changes the signature allows were made after signing"
        case (.trusted, _): return "Valid. Comments were added or changed after signing"
        case (.notVerified, .none): return "Unchanged since it was signed, but the signer's identity isn't verified"
        case (.notVerified, .allowed): return "Unchanged in what it signed, but the signer's identity isn't verified"
        case (.notVerified, _): return "Unchanged in what it signed, with comments added since, but the signer's identity isn't verified"
        }
    }

    /// The reason the identity isn't verified, when it isn't.
    public var identityDetail: String? {
        if case .notVerified(let reason) = identity { return reason }
        return nil
    }
}

// MARK: - Reading

extension PDFDocumentCore {
    /// The object numbers of the document's signed signature fields' widgets. Read from the
    /// form's field tree, without loading pages.
    public func signedSignatureObjectNumbers() -> [Int] {
        guard isPDF else { return [] }
        return withLockedDocument { ctx, doc in
            let count = Int(mupdf_pdf_list_signatures(ctx, doc, nil, 0))
            guard count > 0 else { return [] }
            var numbers = [Int32](repeating: 0, count: count)
            let listed = Int(mupdf_pdf_list_signatures(ctx, doc, &numbers, Int32(count)))
            return numbers.prefix(max(0, min(listed, count))).map(Int.init)
        }
    }

    public func signatureData(objectNumber: Int) throws -> PDFSignatureData {
        try withLockedDocument { ctx, doc in
            var raw = mupdf_signature_data()
            var error: UnsafePointer<CChar>?
            guard mupdf_pdf_signature_data(ctx, doc, Int32(objectNumber), &raw, &error) == 0 else {
                throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The signature can't be read")
            }
            defer { mupdf_pdf_free_signature_data(ctx, &raw) }
            let offsets = withUnsafeBytes(of: raw.range_offset) { Array($0.bindMemory(to: Int64.self)) }
            let lengths = withUnsafeBytes(of: raw.range_length) { Array($0.bindMemory(to: Int64.self)) }
            let count = Int(raw.range_count)
            func text<T>(_ field: T) -> String {
                withUnsafeBytes(of: field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            }
            func optional(_ field: some Any) -> String? {
                let trimmed = text(field).trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            return PDFSignatureData(
                objectNumber: objectNumber,
                byteRanges: (0..<count).map { (offsets[$0], lengths[$0]) },
                hasMoreRanges: raw.has_more_ranges != 0,
                contents: raw.contents.map { Data(bytes: $0, count: raw.contents_length) } ?? Data(),
                subFilter: text(raw.subfilter),
                laterChangesBreakIt: raw.later_changes == -2 ? nil : Int(raw.later_changes),
                laterChangesAllowed: raw.later_changes_allowed != 0,
                laterChangesOnlyComments: raw.later_changes_only_comments != 0,
                pageIndex: raw.page >= 0 ? Int(raw.page) : nil,
                rect: CGRect(x: CGFloat(raw.x0), y: CGFloat(raw.y0), width: CGFloat(raw.x1 - raw.x0), height: CGFloat(raw.y1 - raw.y0)),
                fieldName: text(raw.field_name),
                nameInDocument: optional(raw.signer),
                reason: optional(raw.reason),
                location: optional(raw.location)
            )
        }
    }

    /// Checks every signature in the file as saved at `filePath`. Slow (it reads the file, and
    /// checking a certificate can take a moment): call it off the main thread.
    public func validateSignatures(extraAnchors: [SecCertificate] = []) -> [PDFSignatureValidation] {
        let numbers = signedSignatureObjectNumbers()
        guard !numbers.isEmpty else { return [] }
        let file = try? Data(contentsOf: URL(fileURLWithPath: filePath), options: .mappedIfSafe)
        return numbers.map { number in
            guard let file else {
                return PDFSignatureValidation(malformed: "the file can't be read", objectNumber: number)
            }
            do {
                return SignatureValidator.validate(try signatureData(objectNumber: number), file: file, extraAnchors: extraAnchors)
            } catch {
                return PDFSignatureValidation(malformed: "its data can't be read", objectNumber: number)
            }
        }
    }
}

extension PDFSignatureValidation {
    init(malformed reason: String, objectNumber: Int) {
        self.init(objectNumber: objectNumber, integrity: .malformed(reason), changes: .none,
                  identity: .notVerified("The signature can't be read."), certificates: [])
    }

    /// The name to show: the certificate's, else the one written in the document.
    public var displayName: String {
        signerName ?? nameInDocument ?? (fieldName.isEmpty ? "Signature" : fieldName)
    }
}

// MARK: - Checking

/// Checks signatures with the Security framework: CMS (PKCS #7) for the signature, SecTrust for
/// the certificate. Nothing is fetched from the network (no revocation checks), so opening a
/// document doesn't tell anyone it was opened.
public enum SignatureValidator {
    public static func validate(_ data: PDFSignatureData, file: Data, extraAnchors: [SecCertificate] = []) -> PDFSignatureValidation {
        var result = PDFSignatureValidation(malformed: "", objectNumber: data.objectNumber)
        result.pageIndex = data.pageIndex
        result.rect = data.rect
        result.fieldName = data.fieldName
        result.nameInDocument = data.nameInDocument
        result.reason = data.reason
        result.location = data.location
        result.changes = changes(data, fileLength: Int64(file.count), file: file)

        guard let signed = signedBytes(data, file: file) else {
            result.integrity = .malformed("the parts of the file it says it signed aren't there")
            return result
        }
        let detached: Bool
        switch data.subFilter {
        case "adbe.pkcs7.detached", "ETSI.CAdES.detached": detached = true
        case "adbe.pkcs7.sha1": detached = false
        case "ETSI.RFC3161":
            result.integrity = .unsupported("document timestamp")
            return result
        default:
            result.integrity = .unsupported(data.subFilter.isEmpty ? "this kind of" : data.subFilter)
            return result
        }
        guard let full = trimmedDER(data.contents) else {
            result.integrity = .malformed("the signature isn't a PKCS #7 signature")
            return result
        }
        // A timestamp is checked on its own: the decoder would otherwise fail the whole
        // signature when it can't trust the timestamp's authority.
        let split = Timestamps.split(full)
        let message = split?.withoutTimestamp ?? full

        var decoderRef: CMSDecoder?
        guard CMSDecoderCreate(&decoderRef) == errSecSuccess, let decoder = decoderRef else {
            result.integrity = .malformed("the signature can't be read")
            return result
        }
        let read = message.withUnsafeBytes { CMSDecoderUpdateMessage(decoder, $0.baseAddress!, $0.count) }
        if detached { CMSDecoderSetDetachedContent(decoder, signed as CFData) }
        guard read == errSecSuccess, CMSDecoderFinalizeMessage(decoder) == errSecSuccess else {
            result.integrity = .malformed("the signature can't be read")
            return result
        }
        var signers = 0
        CMSDecoderGetNumSigners(decoder, &signers)
        guard signers > 0 else {
            result.integrity = .malformed("it has no signer")
            return result
        }

        var status = CMSSignerStatus.unsigned
        var verifyCode: OSStatus = 0
        CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &status, nil, &verifyCode)
        result.integrity = status == .valid ? .intact : .modified
        if !detached, result.integrity == .intact {
            // The signature is over a SHA-1 digest of the signed bytes, carried inside it.
            var content: CFData?
            CMSDecoderCopyContent(decoder, &content)
            let digest = Data(Insecure.SHA1.hash(data: signed))
            if (content as Data?) != digest { result.integrity = .modified }
        }

        var signingTime: CFAbsoluteTime = 0
        if CMSDecoderCopySignerSigningTime(decoder, 0, &signingTime) == errSecSuccess {
            result.claimedSigningTime = Date(timeIntervalSinceReferenceDate: signingTime)
        }
        if let token = split?.token, let value = split?.signatureValue {
            switch Timestamps.verify(token: token, signatureValue: value, extraAnchors: extraAnchors) {
            case .success(let time): result.timestamp = time
            case .failure(let why): result.timestampProblem = why.message
            }
        }

        var signerRef: SecCertificate?
        CMSDecoderCopySignerCert(decoder, 0, &signerRef)
        var allRef: CFArray?
        CMSDecoderCopyAllCerts(decoder, &allRef)
        let others = (allRef as? [SecCertificate]) ?? []
        guard let signer = signerRef else {
            result.identity = .notVerified("The signature doesn't include the signer's certificate.")
            return result
        }
        let chain = [signer] + others.filter { SecCertificateCopyData($0) as Data != SecCertificateCopyData(signer) as Data }
        result.certificates = chain.map { SecCertificateCopyData($0) as Data }
        result.signerName = SecCertificateCopySubjectSummary(signer) as String?
        var emails: CFArray?
        if SecCertificateCopyEmailAddresses(signer, &emails) == errSecSuccess { result.signerEmail = (emails as? [String])?.first }
        // At the time a timestamp authority vouches for, else now: the signing time the signature
        // gives is the signer's own say-so, and would let an expired certificate pass.
        result.identity = identity(chain, timestamp: result.timestamp, extraAnchors: extraAnchors, issuer: &result.issuerName)
        return result
    }

    /// A trust object for the certificates, as checked: for the certificate panel to show.
    public static func makeTrust(certificates: [Data], at date: Date?, extraAnchors: [SecCertificate] = []) -> SecTrust? {
        let certs = certificates.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
        guard !certs.isEmpty else { return nil }
        var trustRef: SecTrust?
        guard SecTrustCreateWithCertificates(certs as CFArray, SecPolicyCreateBasicX509(), &trustRef) == errSecSuccess,
              let trust = trustRef else { return nil }
        SecTrustSetNetworkFetchAllowed(trust, false)
        if let date { SecTrustSetVerifyDate(trust, date as CFDate) }
        if !extraAnchors.isEmpty {
            SecTrustSetAnchorCertificates(trust, extraAnchors as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, false)
        }
        return trust
    }

    private static func identity(_ chain: [SecCertificate], timestamp: Date?, extraAnchors: [SecCertificate], issuer: inout String?) -> PDFSignatureValidation.Identity {
        guard let trust = makeTrust(certificates: chain.map { SecCertificateCopyData($0) as Data }, at: timestamp ?? Date(), extraAnchors: extraAnchors) else {
            return .notVerified("The signer's certificate can't be read.")
        }
        var error: CFError?
        let trusted = SecTrustEvaluateWithError(trust, &error)
        let built = (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? chain
        if built.count > 1 { issuer = SecCertificateCopySubjectSummary(built[1]) as String? }
        if trusted { return .trusted }
        let selfSigned = built.count == 1 && isSelfIssued(built[0])
        let code = error.map { CFErrorGetCode($0) } ?? 0
        switch OSStatus(code) {
        case errSecCertificateExpired:
            return .notVerified(timestamp != nil ? "The signer's certificate had expired when it was signed."
                                : "The signer's certificate has expired, and the signature has no timestamp to show it was signed before then.")
        case errSecCertificateNotValidYet:
            return .notVerified(timestamp != nil ? "The signer's certificate wasn't valid yet when it was signed."
                                : "The signer's certificate isn't valid yet.")
        case errSecCertificateRevoked:
            return .notVerified("The signer's certificate has been revoked.")
        default:
            if selfSigned { return .notVerified("The certificate is self-signed: anyone can make one in any name.") }
            let root = built.last.flatMap { SecCertificateCopySubjectSummary($0) as String? }
            if let root { return .notVerified("It was issued by “\(root)”, which this Mac doesn't trust.") }
            return .notVerified("The certificate isn't issued by one this Mac trusts.")
        }
    }

    private static func isSelfIssued(_ cert: SecCertificate) -> Bool {
        guard let subject = SecCertificateCopyNormalizedSubjectSequence(cert),
              let issuer = SecCertificateCopyNormalizedIssuerSequence(cert) else { return false }
        return (subject as Data) == (issuer as Data)
    }

    /// Whether every range is inside a file of `fileLength` bytes (checked without overflowing).
    static func rangesAreInFile(_ ranges: [(offset: Int64, length: Int64)], fileLength: Int64) -> Bool {
        ranges.allSatisfy { $0.offset >= 0 && $0.length >= 0 && $0.offset <= fileLength && $0.length <= fileLength - $0.offset }
    }

    /// The bytes the signature covers, in order.
    static func signedBytes(_ data: PDFSignatureData, file: Data) -> Data? {
        guard !data.byteRanges.isEmpty, !data.hasMoreRanges, rangesAreInFile(data.byteRanges, fileLength: Int64(file.count)) else { return nil }
        var out = Data()
        for range in data.byteRanges {
            out.append(file.subdata(in: Int(range.offset)..<Int(range.offset + range.length)))
        }
        return out
    }

    /// Whether the signature covers the file from its start to its end, leaving out only the
    /// signature itself; if it ends sooner, the file was saved again after signing.
    static func changes(_ data: PDFSignatureData, fileLength: Int64, file: Data) -> PDFSignatureValidation.Changes {
        let ranges = data.byteRanges
        guard ranges.count == 2, !data.hasMoreRanges, ranges[0].offset == 0,
              rangesAreInFile(ranges, fileLength: min(fileLength, Int64(file.count))) else { return .partialCoverage }
        let gapStart = ranges[0].offset + ranges[0].length, gapEnd = ranges[1].offset
        // The one gap is the signature's hex string, < to >, and nothing else: anything else in
        // it (another object, say) wouldn't be signed.
        guard gapEnd > gapStart + 1, isSignatureHexString(file[Int(gapStart)..<Int(gapEnd)], contents: data.contents) else {
            return .partialCoverage
        }
        let end = ranges[1].offset + ranges[1].length
        if end == fileLength { return .none }
        guard end < fileLength else { return .partialCoverage }
        // What follows the end of the signed part should be a later save, but a file can end in
        // line breaks or other whitespace the signature didn't need to cover.
        let rest = file[Int(end)...]
        if rest.allSatisfy({ $0 == 0x0A || $0 == 0x0D || $0 == 0x20 || $0 == 0x00 }) { return .none }
        if let broken = data.laterChangesBreakIt, broken == 0 { return .allowed }
        guard data.laterChangesAllowed else { return .notAllowed }
        return data.laterChangesOnlyComments ? .commentsChanged : .allowed
    }

    /// Whether `gap` is a hex string (< and >, hex digits and white space between) of `contents`.
    static func isSignatureHexString(_ gap: Data, contents: Data) -> Bool {
        guard gap.count >= 2, gap.first == UInt8(ascii: "<"), gap.last == UInt8(ascii: ">") else { return false }
        func value(_ c: UInt8) -> UInt8? {
            switch c {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
            default: return nil
            }
        }
        var decoded = Data()
        decoded.reserveCapacity(contents.count)
        var high: UInt8?
        for c in gap.dropFirst().dropLast() {
            if let v = value(c) {
                if let h = high { decoded.append(h << 4 | v); high = nil } else { high = v }
            } else if ![0x00, 0x09, 0x0A, 0x0C, 0x0D, 0x20].contains(c) {
                return false
            }
        }
        // An odd last digit is followed by a 0.
        if let h = high { decoded.append(h << 4) }
        return decoded == contents
    }

    /// The DER signature without the zeros padding it out to the space left for it.
    static func trimmedDER(_ contents: Data) -> Data? {
        let bytes = [UInt8](contents.prefix(8))
        guard bytes.count >= 2, bytes[0] == 0x30 else { return nil }
        // BER, of indefinite length (as some software writes it): made DER, which ends it.
        if bytes[1] == 0x80 { return BERToDER.convert(contents) }
        var length = 0, header = 2
        if bytes[1] < 0x80 {
            length = Int(bytes[1])
        } else {
            let count = Int(bytes[1] & 0x7F)
            guard count >= 1, count <= 4, bytes.count >= 2 + count else { return nil }
            for i in 0..<count { length = length << 8 | Int(bytes[2 + i]) }
            header += count
        }
        guard header + length <= contents.count else { return nil }
        return contents.prefix(header + length)
    }
}

/// Timestamps (RFC 3161) in CMS signatures, checked apart from the signature they're on.
enum Timestamps {
    struct Problem: Error { let message: String }

    /// The signature without its timestamp, the timestamp token, and the signer's signature
    /// value (which the token vouches for); nil if it has no timestamp.
    static func split(_ der: Data) -> (withoutTimestamp: Data, token: Data, signatureValue: Data)? {
        guard var contentInfo = DERNode.parse(der), contentInfo.children?.count == 2,
              var explicit = contentInfo.children?[1], var signedData = explicit.children?.first,
              var signerInfos = signedData.children?.last, signerInfos.tag == [0x31],
              var signerInfo = signerInfos.children?.first, var parts = signerInfo.children,
              let unsignedIndex = parts.firstIndex(where: { $0.tag == [0xA1] }),
              let value = parts.first(where: { $0.tag == [0x04] }) else { return nil }
        var attributes = parts[unsignedIndex].children ?? []
        guard let index = attributes.firstIndex(where: { $0.children?.first?.content == TimestampAuthority.timeStampTokenOID }),
              let token = attributes[index].children?.dropFirst().first?.children?.first else { return nil }
        attributes.remove(at: index)
        if attributes.isEmpty { parts.remove(at: unsignedIndex) } else { parts[unsignedIndex].children = attributes }
        signerInfo.children = parts
        signerInfos.children![0] = signerInfo
        signedData.children![signedData.children!.count - 1] = signerInfos
        explicit.children![0] = signedData
        contentInfo.children![1] = explicit
        return (Data(contentInfo.encoded), Data(token.encoded), Data(value.content))
    }

    /// The time a token vouches for, if its own signature is sound, it's of this signature
    /// value, and its authority's certificate chains to one trusted (on this Mac, or in
    /// `extraAnchors`) at that time.
    static func verify(token: Data, signatureValue: Data, extraAnchors: [SecCertificate]) -> Result<Date, Problem> {
        // What it signs, its TSTInfo, is inside it; Apple's decoder wants it given as detached.
        guard let tokenNode = DERNode.parse(token), case let (tstInfo, fields)? = Self.tstInfo(of: tokenNode) else {
            return .failure(Problem(message: "The timestamp can't be read."))
        }
        var decoderRef: CMSDecoder?
        guard CMSDecoderCreate(&decoderRef) == errSecSuccess, let decoder = decoderRef,
              token.withUnsafeBytes({ CMSDecoderUpdateMessage(decoder, $0.baseAddress!, $0.count) }) == errSecSuccess else {
            return .failure(Problem(message: "The timestamp can't be read."))
        }
        CMSDecoderSetDetachedContent(decoder, Data(tstInfo) as CFData)
        guard CMSDecoderFinalizeMessage(decoder) == errSecSuccess else { return .failure(Problem(message: "The timestamp can't be read.")) }
        var status = CMSSignerStatus.unsigned
        var code: OSStatus = 0
        CMSDecoderCopySignerStatus(decoder, 0, SecPolicyCreateBasicX509(), false, &status, nil, &code)
        guard status == .valid else { return .failure(Problem(message: "The timestamp's own signature isn't valid.")) }
        guard let imprint = fields[2].children, imprint.count == 2,
              let algorithm = imprint[0].children?.first?.content else { return .failure(Problem(message: "The timestamp can't be read.")) }
        let expected: [UInt8]
        switch algorithm {
        case TimestampAuthority.sha256OID: expected = Array(SHA256.hash(data: signatureValue))
        case [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02]: expected = Array(SHA384.hash(data: signatureValue))
        case [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03]: expected = Array(SHA512.hash(data: signatureValue))
        case [0x2B, 0x0E, 0x03, 0x02, 0x1A]: expected = Array(Insecure.SHA1.hash(data: signatureValue))
        default: return .failure(Problem(message: "The timestamp uses a digest VectorPDF can't check."))
        }
        guard imprint[1].content == expected else { return .failure(Problem(message: "The timestamp is for something else.")) }
        guard let time = generalizedTime(fields[4].content) else { return .failure(Problem(message: "The timestamp's time can't be read.")) }

        var signerRef: SecCertificate?
        CMSDecoderCopySignerCert(decoder, 0, &signerRef)
        var allRef: CFArray?
        CMSDecoderCopyAllCerts(decoder, &allRef)
        guard let tsa = signerRef else { return .failure(Problem(message: "The timestamp doesn't include its authority's certificate.")) }
        // Only a certificate for timestamps may make one: any other a Mac trusts (a web site's,
        // say) could otherwise vouch for any time.
        guard isTimestampingCertificate(tsa) else {
            return .failure(Problem(message: "The timestamp's certificate isn't one for making timestamps."))
        }
        let others = ((allRef as? [SecCertificate]) ?? []).filter { SecCertificateCopyData($0) as Data != SecCertificateCopyData(tsa) as Data }
        var trustRef: SecTrust?
        guard SecTrustCreateWithCertificates(([tsa] + others) as CFArray, SecPolicyCreateBasicX509(), &trustRef) == errSecSuccess,
              let trust = trustRef else { return .failure(Problem(message: "The timestamp's authority can't be checked.")) }
        SecTrustSetNetworkFetchAllowed(trust, false)
        SecTrustSetVerifyDate(trust, time as CFDate)
        if !extraAnchors.isEmpty {
            SecTrustSetAnchorCertificates(trust, extraAnchors as CFArray)
            SecTrustSetAnchorCertificatesOnly(trust, false)
        }
        guard SecTrustEvaluateWithError(trust, nil) else {
            return .failure(Problem(message: "The timestamp's authority isn't trusted on this Mac."))
        }
        return .success(time)
    }

    // id-ct-TSTInfo: 1.2.840.113549.1.9.16.1.4; id-kp-timeStamping: 1.3.6.1.5.5.7.3.8;
    // extKeyUsage: 2.5.29.37
    static let tstInfoOID: [UInt8] = [0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x09, 0x10, 0x01, 0x04]
    static let timeStampingOID: [UInt8] = [0x2B, 0x06, 0x01, 0x05, 0x05, 0x07, 0x03, 0x08]
    static let extendedKeyUsageOID: [UInt8] = [0x55, 0x1D, 0x25]

    /// The TSTInfo a timestamp token (a CMS ContentInfo) carries, as DER and as its fields: at
    /// least version, policy, messageImprint, serialNumber and genTime (a GeneralizedTime).
    static func tstInfo(of token: DERNode) -> (der: [UInt8], fields: [DERNode])? {
        guard let signedData = token.children?.dropFirst().first?.children?.first,
              let encapsulated = signedData.children?.first(where: { $0.tag == [0x30] && $0.children?.first?.tag == [0x06] }),
              encapsulated.children?.first?.content == tstInfoOID,
              let der = encapsulated.children?.dropFirst().first?.children?.first?.content,
              let info = DERNode.parse(Data(der)), info.tag == [0x30], let fields = info.children, fields.count >= 5,
              fields[2].tag == [0x30], fields[4].tag == [0x18] else { return nil }
        return (der, fields)
    }

    /// Whether a certificate is a timestamp authority's (RFC 3161 2.3): its extended key usage
    /// marked critical and for timestamping.
    static func isTimestampingCertificate(_ certificate: SecCertificate) -> Bool {
        guard let cert = DERNode.parse(SecCertificateCopyData(certificate) as Data),
              let tbs = cert.children?.first, let wrapper = tbs.children?.first(where: { $0.tag == [0xA3] }),
              let extensions = wrapper.children?.first?.children else { return false }
        let usages = extensions.filter { $0.children?.first?.content == extendedKeyUsageOID }
        guard usages.count == 1, let parts = usages[0].children, parts.count == 3,
              parts[1].tag == [0x01], parts[1].content.first.map({ $0 != 0 }) == true,
              parts[2].tag == [0x04], let purposes = DERNode.parse(Data(parts[2].content))?.children else { return false }
        return purposes.contains { $0.tag == [0x06] && $0.content == timeStampingOID }
    }

    /// A GeneralizedTime (YYYYMMDDHHMMSS[.fff]Z).
    static func generalizedTime(_ bytes: [UInt8]) -> Date? {
        guard let text = String(bytes: bytes, encoding: .ascii), text.hasSuffix("Z"), text.count >= 15 else { return nil }
        let digits = String(text.prefix(14))
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMddHHmmss"
        guard var date = formatter.date(from: digits) else { return nil }
        let rest = text.dropFirst(14).dropLast()
        if rest.hasPrefix("."), let fraction = Double("0" + rest) { date += fraction }
        return date
    }
}
