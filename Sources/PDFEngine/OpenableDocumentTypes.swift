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
import UniformTypeIdentifiers

/// The documents VectorPDF opens: PDFs, and the e-book, comic and XPS formats MuPDF reads but
/// can't save, which open for reading only (see `PDFViewerViewModel.isReadOnlyDocument`).
/// The app bundle's Info.plist declares the same extensions (Scripts/build_app_bundle.sh).
public enum OpenableDocumentTypes {
    public static let readOnlyExtensions: Set<String> = ["epub", "xps", "oxps", "cbz", "fb2"]

    public static func canOpen(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || readOnlyExtensions.contains(ext)
    }

    /// For open panels. Types no installed app declares come back as dynamic types, which still
    /// match by extension.
    public static var contentTypes: [UTType] {
        [.pdf, .epub] + ["xps", "oxps", "cbz", "fb2"].compactMap { UTType(filenameExtension: $0) }
    }
}
