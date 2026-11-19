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
import CoreGraphics

/// Where a signature with a certificate goes: a signature field already in the document, or a
/// new one at `rect` (page space).
public struct CertificateSignaturePlacement: Identifiable, Equatable {
    public let id = UUID()
    public let page: Int
    public let widgetIndex: Int?
    public let rect: CGRect
}

extension PDFViewerViewModel {
    /// The size of a new signature field, in points.
    public static let certificateSignatureSize = CGSize(width: 200, height: 60)

    public var canSignWithCertificate: Bool {
        document?.isPDF == true && !isReadOnlyDocument && !isTransientWindow && !isComparePane
    }

    /// Starts signing with a certificate: in `field`, a signature field, or else in a new field
    /// placed with a click. Asks to save unsaved changes first, as signing saves the document.
    public func beginCertificateSignature(in field: PDFFormWidget? = nil) {
        guard canSignWithCertificate, saveBeforeSigning() else { return }
        if let field {
            certificateSignaturePlacement = CertificateSignaturePlacement(page: field.pageIndex, widgetIndex: field.widgetIndex, rect: field.rect)
        } else {
            canvasMode = .placeSignatureField
        }
    }

    /// The new field's box for a click at `point` on `page`: centred on it, kept on the page.
    func certificateSignatureRect(page: Int, at point: CGPoint) -> CGRect? {
        guard let doc = document, page >= 0, page < doc.pageBounds.count else { return nil }
        let bounds = doc.pageBounds[page]
        let size = Self.certificateSignatureSize
        return CGRect(x: max(bounds.minX, min(point.x - size.width / 2, bounds.maxX - size.width)),
                      y: max(bounds.minY, min(point.y - size.height / 2, bounds.maxY - size.height)),
                      width: size.width, height: size.height)
    }

    /// A box dragged out while placing a new field (kept on the page, and no smaller than
    /// 60 × 20 points): the sheet to sign it opens.
    func placeCertificateSignature(page: Int, in rect: CGRect) {
        canvasMode = .select
        guard let doc = document, page >= 0, page < doc.pageBounds.count else { return }
        let bounds = doc.pageBounds[page]
        var box = rect.standardized
        box.size.width = max(box.width, 60)
        box.size.height = max(box.height, 20)
        box = box.intersection(bounds)
        guard !box.isNull, box.width >= 20, box.height >= 10 else { return }
        certificateSignaturePlacement = CertificateSignaturePlacement(page: page, widgetIndex: nil, rect: box)
    }

    /// A click while placing a new field: the sheet to sign it opens.
    func placeCertificateSignature(page: Int, at point: CGPoint) {
        canvasMode = .select
        guard let rect = certificateSignatureRect(page: page, at: point) else { return }
        certificateSignaturePlacement = CertificateSignaturePlacement(page: page, widgetIndex: nil, rect: rect)
    }

    /// Saves unsaved changes after asking; false if they're kept unsaved.
    private func saveBeforeSigning() -> Bool {
        guard isDocumentEdited else { return true }
        if !Self.isRunningTests {
            let alert = NSAlert()
            alert.messageText = "Save Changes Before Signing?"
            alert.informativeText = "Signing saves the document. Your changes are saved first, so that they're part of what you sign."
            alert.addButton(withTitle: "Save")
            alert.addButton(withTitle: "Cancel")
            guard alert.runModal() == .alertFirstButtonReturn else { return false }
        }
        saveDocument()
        return !isDocumentEdited
    }

    /// Signs where `placement` says and saves the document, which makes the signature; then opens
    /// it again from the file. If the signature can't be made, the file is left as it was and
    /// opened again too, without the unfinished signature. False then.
    @discardableResult
    public func completeCertificateSignature(_ placement: CertificateSignaturePlacement, with identity: SigningIdentity,
                                             appearance: PDFDocumentCore.SignatureAppearance,
                                             permissions: PDFDocumentCore.SigningPermissions = .init()) async -> Bool {
        certificateSignaturePlacement = nil
        guard let doc = document, canSignWithCertificate else { return false }
        flushPendingFormEdits()
        let path = doc.filePath
        var failure: String?
        fileChangeWatcher = nil
        do {
            let signature = try doc.sign(page: placement.page, widgetIndex: placement.widgetIndex, rect: placement.rect,
                                         with: identity, appearance: appearance, permissions: permissions)
            do {
                try doc.save(to: path)
            } catch {
                failure = signature.failure ?? error.localizedDescription
            }
        } catch {
            failure = error.localizedDescription
        }
        isDocumentEdited = false
        currentWindow?.isDocumentEdited = false
        cleanupWorkingCopy()
        await loadDocument(from: path, password: currentDocumentPassword)
        if let failure {
            showErrorAlert(title: "The Document Couldn't Be Signed", message: failure)
            return false
        }
        return true
    }

    /// The form's fields a signature could lock, by full name: all but signature fields.
    public func lockableFormFieldNames() -> [String] {
        guard let doc = document else { return [] }
        var names: [String] = []
        var seen = Set<String>()
        for page in 0..<doc.pageCount {
            for field in doc.formFieldEntries(pageIndex: page) where field.type != .signature && !field.name.isEmpty {
                if seen.insert(field.name).inserted { names.append(field.name) }
            }
        }
        return names
    }
}
