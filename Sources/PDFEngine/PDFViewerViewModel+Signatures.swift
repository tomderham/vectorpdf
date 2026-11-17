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
import Security
import SecurityInterface

extension PDFViewerViewModel {
    /// Certificates trusted besides the Mac's own, for tests.
    nonisolated(unsafe) static var extraSignatureAnchors: [SecCertificate] = []

    /// Checks the document's signatures, as its file is saved, off the main thread.
    func checkSignatures() {
        signatureValidationTask?.cancel()
        signatureValidationTask = nil
        signatureValidations = nil
        guard let doc = document, documentContentsSummary.signatureCount > 0 else { return }
        let path = doc.filePath, password = currentDocumentPassword
        let anchors = Self.extraSignatureAnchors
        signatureValidationTask = Task { [weak self] in
            let results = await Task.detached(priority: .utility) { () -> [PDFSignatureValidation] in
                // A copy of its own: checking reads every signature's data, and the window's own
                // may hold unsaved changes the file doesn't.
                guard let reader = try? PDFDocumentCore(filePath: path, password: password) else { return [] }
                return reader.validateSignatures(extraAnchors: anchors)
            }.value
            guard let self, !Task.isCancelled, self.document === doc else { return }
            self.signatureValidations = results
            self.signatureValidationTask = nil
        }
    }

    /// Waits for the check started by `checkSignatures`, for tests.
    func waitForSignatureCheck() async {
        await signatureValidationTask?.value
    }

    /// What the banner above the page says about the signatures, if anything.
    public var signatureBanner: SignatureBanner? {
        guard let results = signatureValidations, !results.isEmpty, !isSignatureBannerDismissed else { return nil }
        return SignatureBanner(results)
    }

    /// Shows the certificates of a signature, as checked, in the system's certificate panel.
    public func showCertificate(of signature: PDFSignatureValidation) {
        guard !Self.isRunningTests,
              let trust = SignatureValidator.makeTrust(certificates: signature.certificates,
                                                       at: signature.timestamp ?? signature.claimedSigningTime,
                                                       extraAnchors: Self.extraSignatureAnchors) else { return }
        var error: CFError?
        _ = SecTrustEvaluateWithError(trust, &error)
        let panel = SFCertificatePanel.shared()!
        if let window = currentWindow ?? NSApp.keyWindow {
            panel.beginSheet(for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, showGroup: true)
        } else {
            panel.runModal(for: trust, showGroup: true)
        }
    }
}

/// The line above the page when a document is signed.
public struct SignatureBanner: Equatable {
    public enum Kind: Equatable { case valid, unverified, invalid, unchecked }
    public let kind: Kind
    public let message: String

    init(_ results: [PDFSignatureValidation]) {
        // Kinds VectorPDF can't check (such as document timestamps) count only if there's nothing else.
        let checked = results.filter { if case .unsupported = $0.integrity { return false } else { return true } }
        let names = (checked.isEmpty ? results : checked).map(\.displayName)
        let who = names.count == 1 ? names[0] : "\(names.count) people"
        if checked.contains(where: \.hasProblems) {
            kind = .invalid
            message = checked.count == 1 ? "The signature by \(who) is invalid" : "At least one signature has problems"
        } else if checked.isEmpty {
            kind = .unchecked
            message = "Signed by \(who). VectorPDF can't check this kind of signature yet"
        } else if checked.allSatisfy(\.isFullyValid) {
            kind = .valid
            message = checked.count == 1 ? "Signed by \(who). The signature is valid" : "Signed by \(who). All signatures are valid"
        } else {
            kind = .unverified
            message = "Signed by \(who). The document is unchanged, but the signer's identity isn't verified on this Mac"
        }
    }

    public var systemImage: String {
        switch kind {
        case .valid: return "checkmark.seal.fill"
        case .unverified: return "exclamationmark.triangle.fill"
        case .invalid: return "xmark.seal.fill"
        case .unchecked: return "questionmark.circle.fill"
        }
    }
}
