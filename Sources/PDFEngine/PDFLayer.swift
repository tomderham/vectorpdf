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
    /// The layer's PDF object number, which annotations on it refer to (their /OC). Nil for a
    /// heading, or where it can't be found.
    public let objectNumber: Int?

    public init(id: Int, name: String, depth: Int, kind: Kind, isVisible: Bool, isLocked: Bool, objectNumber: Int? = nil) {
        self.id = id
        self.name = name
        self.depth = depth
        self.kind = kind
        self.isVisible = isVisible
        self.isLocked = isLocked
        self.objectNumber = objectNumber
    }

    public var canToggle: Bool { kind != .heading && !isLocked }

    /// Whether annotations can be put on it.
    public var canHoldAnnotations: Bool { kind != .heading && objectNumber != nil }

    public var displayName: String { name.isEmpty ? "Untitled Layer" : name }
}

/// One of the ways a document offers its layers to be shown (its optional content
/// configurations): the default, and any alternatives, such as a plot set-up or a language.
public struct PDFLayerConfiguration: Identifiable, Equatable, Sendable {
    /// -1 for the document's default configuration; otherwise its place among the alternatives.
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    public var isDefault: Bool { id == -1 }

    public var displayName: String {
        if !name.isEmpty { return name }
        return isDefault ? "Default" : "Configuration \(id + 1)"
    }
}

/// Which layers are shown, and the configuration they were chosen from, to give the other copies
/// of the file that draw it or read its text (from `PDFDocumentCore.layerStates`).
public struct PDFLayerStates: Equatable, Sendable {
    /// `PDFLayerConfiguration.id` of the configuration chosen.
    public var configuration: Int
    /// Whether each layer is shown, in MuPDF's order.
    public var states: [Int32]

    public init(configuration: Int = -1, states: [Int32] = []) {
        self.configuration = configuration
        self.states = states
    }

    /// For a document without layers.
    public var isEmpty: Bool { states.isEmpty }

    /// Shows and hides layers in another copy of the file as these say, taking the configuration
    /// too, as it decides which layers apply to viewing. Leaves a copy with other layers alone
    /// (one not yet opened again since a layer was added), returning false.
    @discardableResult
    func apply(ctx: FZContext, doc: FZDocument) -> Bool {
        guard !states.isEmpty else { return false }
        return mupdf_pdf_select_layer_config(ctx, doc, Int32(configuration), states, Int32(states.count), nil) == 0
    }
}
