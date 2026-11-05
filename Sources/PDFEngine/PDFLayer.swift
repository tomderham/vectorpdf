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

/// One row of a PDF's layers (optional content groups), as the Layers sidebar lists them.
public struct PDFLayer: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable {
        /// A heading that groups the layers under it; it can't be shown or hidden itself.
        case heading
        case checkbox
        /// One of a group of which only one is shown at a time.
        case radio
    }

    /// What `PDFDocumentCore.toggleLayer(id:)` takes.
    public let id: Int
    public let name: String
    /// How far it's nested under headings or other layers.
    public let depth: Int
    public let kind: Kind
    public let isVisible: Bool
    /// The document doesn't let it be shown or hidden.
    public let isLocked: Bool

    public init(id: Int, name: String, depth: Int, kind: Kind, isVisible: Bool, isLocked: Bool) {
        self.id = id
        self.name = name
        self.depth = depth
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
    }

    public var canToggle: Bool { kind != .heading && !isLocked }
}
