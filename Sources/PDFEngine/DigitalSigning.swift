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
import Foundation
import MuPDFBridge
import Security

/// A certificate with its private key, to sign with: from the Keychain, or a .p12 file.
public struct SigningIdentity: @unchecked Sendable, Identifiable, Equatable {
    public let identity: SecIdentity
    public let certificate: SecCertificate
    /// The certificates above it, from its issuer up, as far as they're known.
    public let chain: [SecCertificate]
    public let name: String
    public let organization: String?
    public let organizationalUnit: String?
    public let email: String?
    public let country: String?
    public let issuer: String?
    public let expires: Date?

    public var id: Data { SecCertificateCopyData(certificate) as Data }
    public static func == (a: Self, b: Self) -> Bool { a.id == b.id }

    init?(identity: SecIdentity, chain: [SecCertificate]? = nil) {
        var cert: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert else { return nil }
        self.identity = identity
        self.certificate = cert
        let subject = Self.nameFields(cert, kSecOIDX509V1SubjectName)
        let issuerFields = Self.nameFields(cert, kSecOIDX509V1IssuerName)
        email = subject[kSecOIDEmailAddress as String]
        name = subject[kSecOIDCommonName as String] ?? email ?? (SecCertificateCopySubjectSummary(cert) as String?) ?? "Unknown"
        organization = subject[kSecOIDOrganizationName as String]
        organizationalUnit = subject[kSecOIDOrganizationalUnitName as String]
        country = subject[kSecOIDCountryName as String]
        issuer = issuerFields[kSecOIDCommonName as String] ?? issuerFields[kSecOIDOrganizationName as String]
        expires = Self.notAfter(cert)
        self.chain = (chain ?? Self.chainAbove(cert)).filter { SecCertificateCopyData($0) as Data != SecCertificateCopyData(cert) as Data }
    }

    /// Whether its certificate is for signing: in date, not a certificate authority's, and its key
    /// usage (if it says) allows signatures.
    public var canSign: Bool {
        if let expires, expires < Date() { return false }
        let values = SecCertificateCopyValues(certificate, [kSecOIDKeyUsage, kSecOIDBasicConstraints] as CFArray, nil) as? [String: [String: Any]]
        if let usage = values?[kSecOIDKeyUsage as String]?[kSecPropertyKeyValue as String] as? NSNumber {
            // digitalSignature (bit 0) or nonRepudiation (bit 1), as Security numbers them.
            if usage.uint32Value & 0b11 == 0 { return false }
        }
        if let constraints = values?[kSecOIDBasicConstraints as String]?[kSecPropertyKeyValue as String] as? [[String: Any]],
           constraints.contains(where: { ($0[kSecPropertyKeyLabel as String] as? String) == "Certificate Authority" && ($0[kSecPropertyKeyValue as String] as? String) == "Yes" }) {
            return false
        }
        return true
    }

    /// The identities in the Keychain that can sign, by name.
    public static func keychainIdentities() -> [SigningIdentity] {
        let query: [String: Any] = [kSecClass as String: kSecClassIdentity, kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnRef as String: true]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let items = result as? [SecIdentity] else { return [] }
        var seen = Set<Data>()
        return items.compactMap { SigningIdentity(identity: $0) }
            .filter { $0.canSign && seen.insert($0.id).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public enum ImportError: LocalizedError {
        case wrongPassword, noIdentity, failed(OSStatus)
        public var errorDescription: String? {
            switch self {
            case .wrongPassword: return "The password is incorrect."
            case .noIdentity: return "The file has no certificate with a private key."
            case .failed(let status): return (SecCopyErrorMessageString(status, nil) as String?) ?? "The file couldn't be read (\(status))."
            }
        }
    }

    /// The identity in a PKCS #12 (.p12, .pfx) file, kept in memory, not added to the Keychain.
    public static func fromPKCS12(_ data: Data, password: String) throws -> SigningIdentity {
        var items: CFArray?
        let options: [String: Any] = [kSecImportExportPassphrase as String: password, kSecImportToMemoryOnly as String: true]
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        if status == errSecAuthFailed || status == errSecPkcs12VerifyFailure { throw ImportError.wrongPassword }
        guard status == errSecSuccess else { throw ImportError.failed(status) }
        guard let first = (items as? [[String: Any]])?.first,
              let value = first[kSecImportItemIdentity as String] else { throw ImportError.noIdentity }
        let identity = value as! SecIdentity
        let chain = first[kSecImportItemCertChain as String] as? [SecCertificate]
        guard let signing = SigningIdentity(identity: identity, chain: chain) else { throw ImportError.noIdentity }
        return signing
    }

    private static func nameFields(_ cert: SecCertificate, _ oid: CFString) -> [String: String] {
        guard let values = SecCertificateCopyValues(cert, [oid] as CFArray, nil) as? [String: [String: Any]],
              let parts = values[oid as String]?[kSecPropertyKeyValue as String] as? [[String: Any]] else { return [:] }
        var fields: [String: String] = [:]
        for part in parts {
            if let label = part[kSecPropertyKeyLabel as String] as? String, let value = part[kSecPropertyKeyValue as String] as? String, fields[label] == nil {
                fields[label] = value
            }
        }
        return fields
    }

    private static func notAfter(_ cert: SecCertificate) -> Date? {
        guard let values = SecCertificateCopyValues(cert, [kSecOIDX509V1ValidityNotAfter] as CFArray, nil) as? [String: [String: Any]],
              let seconds = values[kSecOIDX509V1ValidityNotAfter as String]?[kSecPropertyKeyValue as String] as? NSNumber else { return nil }
        return Date(timeIntervalSinceReferenceDate: seconds.doubleValue)
    }

    /// The chain the Mac builds above `cert` from the certificates it knows.
    private static func chainAbove(_ cert: SecCertificate) -> [SecCertificate] {
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates(cert, SecPolicyCreateBasicX509(), &trust) == errSecSuccess, let trust else { return [] }
        _ = SecTrustEvaluateWithError(trust, nil)
        return (SecTrustCopyCertificateChain(trust) as? [SecCertificate]) ?? []
    }
}

/// Makes a detached CMS signature (adbe.pkcs7.detached: SHA-256, with the signing time and the
/// certificates up to the root) of the bytes MuPDF hands it as the document is saved.
public final class CMSSignature: @unchecked Sendable {
    let signer: SigningIdentity
    /// Where to get a timestamp of the signature, if one's wanted.
    let timestampAuthority: TimestampAuthority?
    private var encoder: CMSEncoder?
    /// Why the signature couldn't be made, if it couldn't.
    public private(set) var failure: String?

    init(signer: SigningIdentity, timestampAuthority: TimestampAuthority? = nil) {
        self.signer = signer
        self.timestampAuthority = timestampAuthority
    }

    /// The most a signature can take: the certificates, and room for the signature and its
    /// attributes.
    var maxSize: Int {
        let certificates = ([signer.certificate] + signer.chain).reduce(0) { $0 + CFDataGetLength(SecCertificateCopyData($1)) }
        // A timestamp token carries the authority's certificates too.
        let timestamp = timestampAuthority == nil ? 0 : 24 * 1024
        return (certificates + 8192 + timestamp + 1023) / 1024 * 1024
    }

    private func fail(_ what: String, _ status: OSStatus) -> Int32 {
        failure = status == errSecUserCanceled || status == errSecAuthFailed
            ? "Access to the certificate's private key was denied."
            : "\(what): \((SecCopyErrorMessageString(status, nil) as String?) ?? "error \(status)")"
        encoder = nil
        return -1
    }

    func begin() -> Int32 {
        failure = nil
        var created: CMSEncoder?
        var status = CMSEncoderCreate(&created)
        guard status == errSecSuccess, let encoder = created else { return fail("The signature couldn't be started", status) }
        status = CMSEncoderAddSigners(encoder, signer.identity)
        guard status == errSecSuccess else { return fail("The certificate can't sign", status) }
        _ = CMSEncoderSetHasDetachedContent(encoder, true)
        _ = CMSEncoderSetSignerAlgorithm(encoder, kCMSEncoderDigestAlgorithmSHA256)
        _ = CMSEncoderAddSignedAttributes(encoder, .attrSigningTime)
        _ = CMSEncoderSetCertificateChainMode(encoder, .signerOnly)
        if !signer.chain.isEmpty {
            _ = CMSEncoderAddSupportingCerts(encoder, signer.chain as CFArray)
        }
        self.encoder = encoder
        return 0
    }

    func update(_ bytes: UnsafePointer<UInt8>, _ count: Int) -> Int32 {
        guard let encoder else { return -1 }
        let status = CMSEncoderUpdateContent(encoder, bytes, count)
        return status == errSecSuccess ? 0 : fail("The document couldn't be signed", status)
    }

    func finish(_ out: UnsafeMutablePointer<UInt8>, _ capacity: Int) -> Int {
        guard let encoder else { return 0 }
        self.encoder = nil
        var data: CFData?
        let status = CMSEncoderCopyEncodedContent(encoder, &data)
        guard status == errSecSuccess, let encoded = data as Data? else { _ = fail("The signature couldn't be made", status); return 0 }
        // CMSEncoder writes BER, with lengths left open; PDF readers want DER.
        guard var signature = BERToDER.convert(encoded) else {
            failure = "The signature couldn't be encoded."
            return 0
        }
        if let timestampAuthority {
            do {
                signature = try timestampAuthority.timestamped(signature)
            } catch {
                failure = error.localizedDescription
                return 0
            }
        }
        guard signature.count <= capacity else {
            failure = "The signature is larger than the room for it."
            return 0
        }
        signature.copyBytes(to: out, count: signature.count)
        return signature.count
    }
}

extension PDFDocumentCore {
    /// What a signature field shows besides who signed and when.
    public struct SignatureAppearance: Sendable {
        public var reason: String?
        public var location: String?
        /// An image (PNG) drawn on the left: a handwritten signature. Without one, the name is.
        public var graphic: Data?

        public init(reason: String? = nil, location: String? = nil, graphic: Data? = nil) {
            self.reason = reason
            self.location = location
            self.graphic = graphic
        }
    }

    /// What a signature allows of the document after it, besides its own appearance.
    public struct SigningPermissions: Sendable, Equatable {
        /// Certifying the document: the changes it allows from then on. Only its first signature can.
        public enum Certification: Int, Sendable, CaseIterable {
            case noChanges = 1, formFillingAndSigning = 2, formFillingSigningAndComments = 3
        }
        public enum FieldLock: Sendable, Equatable {
            /// The form's other fields as they were (a field's own lock, if it has one, applies).
            case none
            case all
            /// These fields, by full name.
            case fields([String])
        }
        public var certification: Certification?
        public var lock: FieldLock

        public init(certification: Certification? = nil, lock: FieldLock = .none) {
            self.certification = certification
            self.lock = lock
        }
    }

    /// What signing draws in a field `size` points big, at `scale` pixels a point.
    public func signaturePreview(size: CGSize, scale: CGFloat, name: String, appearance: SignatureAppearance) -> CGImage? {
        try? withLockedDocument { ctx, doc -> CGImage? in
            let flags = Self.signatureFlags(hasGraphic: appearance.graphic != nil)
            let graphic = appearance.graphic ?? Data()
            let pix = graphic.withUnsafeBytes { png in
                mupdf_signature_preview(ctx, Float(size.width), Float(size.height), Float(scale), name,
                                        appearance.graphic == nil ? nil : png.bindMemory(to: UInt8.self).baseAddress, png.count,
                                        appearance.reason, appearance.location, flags, nil)
            }
            guard let pix else { return nil }
            defer { mupdf_pixmap_drop(ctx, pix) }
            let width = Int(mupdf_pixmap_width(pix)), height = Int(mupdf_pixmap_height(pix))
            let stride = Int(mupdf_pixmap_stride(pix))
            guard width > 0, height > 0, mupdf_pixmap_n(pix) == 4, let samples = mupdf_pixmap_samples(pix),
                  let provider = CGDataProvider(data: Data(bytes: samples, count: stride * height) as CFData) else { return nil }
            return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: stride,
                           space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        } ?? nil
    }

    static func signatureFlags(hasGraphic: Bool) -> Int32 {
        Int32(PDF_SIGNATURE_SHOW_LABELS | PDF_SIGNATURE_SHOW_TEXT_NAME | PDF_SIGNATURE_SHOW_DATE)
            | (hasGraphic ? 0 : Int32(PDF_SIGNATURE_SHOW_GRAPHIC_NAME))
    }

    /// Whether the page's `widgetIndex`'th widget is a signature field signed already.
    public func isSignedSignatureField(page: Int, widgetIndex: Int) -> Bool {
        guard isPDF else { return false }
        return (try? withLockedDocument { ctx, doc in mupdf_page_widget_is_signed(ctx, doc, Int32(page), Int32(widgetIndex)) != 0 }) == true
    }

    /// Signs a signature field: the page's `widgetIndex`'th widget, or a new field at `rect`
    /// (page space). The signature itself is made as the document is next saved; the returned
    /// object says why, if it couldn't be.
    @discardableResult
    public func sign(page: Int, widgetIndex: Int? = nil, rect: CGRect = .zero, with signer: SigningIdentity,
                     appearance: SignatureAppearance = SignatureAppearance(),
                     permissions: SigningPermissions = SigningPermissions(),
                     timestamp: TimestampAuthority? = nil) throws -> CMSSignature {
        guard isPDF else { throw PDFError.operationFailed("Only a PDF can be signed") }
        let signature = CMSSignature(signer: signer, timestampAuthority: timestamp)
        try withLockedDocument { ctx, doc in
            let context = Unmanaged.passRetained(signature).toOpaque()
            let callbacks = vp_signer_callbacks(
                context: context,
                begin: { Unmanaged<CMSSignature>.fromOpaque($0!).takeUnretainedValue().begin() },
                update: { Unmanaged<CMSSignature>.fromOpaque($0!).takeUnretainedValue().update($1!, $2) },
                finish: { Unmanaged<CMSSignature>.fromOpaque($0!).takeUnretainedValue().finish($1!, $2) },
                release: { Unmanaged<CMSSignature>.fromOpaque($0!).release() })
            guard let pkcs7 = mupdf_new_signer(ctx, callbacks, signer.name, signer.organization, signer.organizationalUnit,
                                               signer.email, signer.country, signature.maxSize) else {
                Unmanaged<CMSSignature>.fromOpaque(context).release()
                throw PDFError.operationFailed("The signature couldn't be prepared")
            }
            defer { mupdf_drop_signer(ctx, pkcs7) }
            var error: UnsafePointer<CChar>?
            let flags = Self.signatureFlags(hasGraphic: appearance.graphic != nil)
            let box = fz_rect(x0: Float(rect.minX), y0: Float(rect.minY), x1: Float(rect.maxX), y1: Float(rect.maxY))
            let lockCode: Int32
            var lockNames: [String] = []
            switch permissions.lock {
            case .none: lockCode = 0
            case .all: lockCode = 1
            case .fields(let names): lockCode = 2; lockNames = names
            }
            let names = lockNames.map { strdup($0) }
            defer { names.forEach { free($0) } }
            let namePointers = names.map { UnsafePointer($0) }
            let status = (appearance.graphic ?? Data()).withUnsafeBytes { png in
                namePointers.withUnsafeBufferPointer { lockFields in
                    mupdf_pdf_sign(ctx, doc, Int32(page), Int32(widgetIndex ?? -1), box, pkcs7,
                                   appearance.graphic == nil ? nil : png.bindMemory(to: UInt8.self).baseAddress, png.count,
                                   appearance.reason, appearance.location, flags,
                                   Int32(permissions.certification?.rawValue ?? 0), lockCode, lockFields.baseAddress, Int32(lockNames.count), &error)
                }
            }
            guard status == 0 else {
                throw PDFError.operationFailed(error.map { String(cString: $0) } ?? "The field couldn't be signed")
            }
        }
        return signature
    }
}

/// Re-encodes BER as DER where they differ in what CMS encoders write: indefinite lengths
/// become definite, and strings split into constructed parts become one primitive string.
enum BERToDER {
    static func convert(_ data: Data) -> Data? {
        let bytes = [UInt8](data)
        var index = 0
        guard let element = parse(bytes, &index, depth: 0), index == bytes.count || bytes[index...].allSatisfy({ $0 == 0 }) else { return nil }
        return Data(element)
    }

    /// Tags of string types, which DER keeps primitive (OCTET STRING, BIT STRING, and the text
    /// strings).
    private static let stringTags: Set<UInt8> = [0x03, 0x04, 0x0C, 0x12, 0x13, 0x14, 0x16, 0x19, 0x1A, 0x1E]

    private static func parse(_ b: [UInt8], _ i: inout Int, depth: Int) -> [UInt8]? {
        guard depth < 64, i < b.count else { return nil }
        let tagStart = i
        let first = b[i]
        i += 1
        if first & 0x1F == 0x1F {  // a tag number in more bytes
            while i < b.count, b[i] & 0x80 != 0 { i += 1 }
            i += 1
        }
        guard i < b.count else { return nil }
        let tag = Array(b[tagStart..<i])
        let isConstructed = first & 0x20 != 0
        let lengthByte = b[i]
        i += 1
        var content: [UInt8] = []
        if lengthByte == 0x80 {
            guard isConstructed else { return nil }
            var parts: [[UInt8]] = []
            while true {
                guard i + 1 < b.count else { return nil }
                if b[i] == 0, b[i + 1] == 0 { i += 2; break }
                guard let child = parse(b, &i, depth: depth + 1) else { return nil }
                parts.append(child)
            }
            content = merged(parts, tag: first)
        } else {
            var length = 0
            if lengthByte & 0x80 == 0 {
                length = Int(lengthByte)
            } else {
                let count = Int(lengthByte & 0x7F)
                guard count <= 4, i + count <= b.count else { return nil }
                for _ in 0..<count { length = length << 8 | Int(b[i]); i += 1 }
            }
            guard i + length <= b.count else { return nil }
            if isConstructed {
                let end = i + length
                var parts: [[UInt8]] = []
                while i < end {
                    guard let child = parse(b, &i, depth: depth + 1) else { return nil }
                    parts.append(child)
                }
                guard i == end else { return nil }
                content = merged(parts, tag: first)
            } else {
                content = Array(b[i..<(i + length)])
                i += length
            }
        }
        var outTag = tag
        // A string in parts becomes one primitive string.
        if isConstructed, first & 0xC0 == 0, stringTags.contains(first & 0x1F) { outTag[0] &= ~0x20 }
        return outTag + encodedLength(content.count) + content
    }

    /// The content of a constructed element: its parts, or for a string, their contents joined.
    private static func merged(_ parts: [[UInt8]], tag: UInt8) -> [UInt8] {
        guard tag & 0xC0 == 0, stringTags.contains(tag & 0x1F) else { return parts.flatMap { $0 } }
        return parts.flatMap { part -> [UInt8] in
            // Each part is itself a primitive string: skip its tag and length.
            var j = 1
            let lengthByte = part[j]
            j += 1 + (lengthByte & 0x80 != 0 ? Int(lengthByte & 0x7F) : 0)
            return Array(part[j...])
        }
    }

    private static func encodedLength(_ n: Int) -> [UInt8] {
        if n < 0x80 { return [UInt8(n)] }
        var bytes: [UInt8] = []
        var v = n
        while v > 0 { bytes.insert(UInt8(v & 0xFF), at: 0); v >>= 8 }
        return [0x80 | UInt8(bytes.count)] + bytes
    }
}
