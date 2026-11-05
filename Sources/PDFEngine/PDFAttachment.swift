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
import MuPDFBridge
import UniformTypeIdentifiers

/// A file embedded in a PDF: attached to the document (as in a portfolio or an e-invoice), or
/// to a page by a file attachment annotation.
public struct PDFAttachment: Identifiable, Equatable, Sendable {
    /// Its position in the document's list, which is how it's read back: valid until the
    /// document changes, when the list is read again.
    public let id: Int
    public let name: String
    /// As the PDF gives it, or nil if it doesn't.
    public let mimeType: String?
    public let size: Int?
    public let created: Date?
    public let modified: Date?
    public let description: String?
    /// The page whose annotation it's attached to, or nil for one attached to the document.
    public let pageIndex: Int?

    /// A name that's safe to create in a folder: the PDF's name can hold any text, including
    /// slashes and `..`, which mustn't reach outside the folder it's saved in.
    public var fileName: String {
        let last = name.replacingOccurrences(of: "\\", with: "/").split(separator: "/").last.map(String.init) ?? ""
        let cleaned = last
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !cleaned.isEmpty, cleaned != ".", cleaned != ".." else { return "Attachment" }
        // Not hidden in the Finder.
        return cleaned.hasPrefix(".") ? "Attachment" + cleaned : cleaned
    }

    /// The kind of file it is, for its icon and description: from its name, else its MIME type.
    public var contentType: UTType? {
        let ext = (fileName as NSString).pathExtension
        if !ext.isEmpty, let type = UTType(filenameExtension: ext) { return type }
        return mimeType.flatMap { UTType(mimeType: $0) }
    }
}

extension PDFDocumentCore {
    /// The PDF's embedded files, in a fixed order: the document's attachments, then its other
    /// associated files, then those attached to pages. Empty for a document that isn't a PDF.
    public func attachments() -> [PDFAttachment] {
        guard isPDF else { return [] }
        return withLockedDocument { ctx, doc in
            let count = Int(mupdf_pdf_list_attachments(ctx, doc, nil, 0))
            guard count > 0 else { return [] }
            var entries = [mupdf_attachment](repeating: mupdf_attachment(), count: count)
            let listed = min(count, Int(mupdf_pdf_list_attachments(ctx, doc, &entries, Int32(count))))
            return (0..<listed).map { index in
                var entry = entries[index]
                func text<T>(_ field: inout T) -> String {
                    withUnsafeBytes(of: &field) { raw in
                        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
                    }
                }
                func date(_ seconds: Int64) -> Date? { seconds >= 0 ? Date(timeIntervalSince1970: TimeInterval(seconds)) : nil }
                let name = text(&entry.name)
                let mime = text(&entry.mime_type)
                let description = text(&entry.description).trimmingCharacters(in: .whitespacesAndNewlines)
                return PDFAttachment(
                    id: index,
                    name: name.isEmpty ? "Attachment \(index + 1)" : name,
                    mimeType: mime.isEmpty ? nil : mime,
                    size: entry.size >= 0 ? Int(entry.size) : nil,
                    created: date(entry.created),
                    modified: date(entry.modified),
                    description: description.isEmpty ? nil : description,
                    pageIndex: entry.page >= 0 ? Int(entry.page) : nil
                )
            }
        }
    }

    /// Writes the contents of `attachment` to `path`.
    public func saveAttachment(_ attachment: PDFAttachment, to path: String) throws {
        try withLockedDocument { ctx, doc in
            var errorMsg: UnsafePointer<CChar>?
            guard mupdf_pdf_save_attachment(ctx, doc, Int32(attachment.id), path, &errorMsg) == 0 else {
                throw PDFError.saveFailed(errorMsg != nil ? String(cString: errorMsg!) : "Couldn't save the attachment")
            }
        }
    }

    /// Attaches a file to the document. Only tests use it for now.
    func addAttachment(name: String, data: Data, mimeType: String? = nil, description: String? = nil) throws {
        try withLockedDocument { ctx, doc in
            var errorMsg: UnsafePointer<CChar>?
            let ret = data.withUnsafeBytes { raw in
                mupdf_pdf_add_attachment(ctx, doc, name, mimeType, raw.bindMemory(to: UInt8.self).baseAddress, data.count, description, &errorMsg)
            }
            guard ret == 0 else {
                throw PDFError.saveFailed(errorMsg != nil ? String(cString: errorMsg!) : "Couldn't attach the file")
            }
        }
    }
}
