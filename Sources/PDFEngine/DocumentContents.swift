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
import CoreGraphics
import MuPDFBridge

/// The parts of the sidebar's Document tab, each shown only when the document has some.
public enum DocumentSidebarSection: String, CaseIterable, Sendable {
    case layers, attachments, fields, links, destinations

    public var title: String {
        switch self {
        case .layers: return "Layers"
        case .attachments: return "Attachments"
        case .fields: return "Form Fields"
        case .links: return "Links"
        case .destinations: return "Destinations"
        }
    }

    public var systemImage: String {
        switch self {
        case .layers: return "square.3.layers.3d"
        case .attachments: return "paperclip"
        case .fields: return "character.textbox"
        case .links: return "link"
        case .destinations: return "mappin.and.ellipse"
        }
    }
}

/// What the Document tab can show besides layers and attachments, found cheaply when a document
/// opens; the lists themselves are read when first shown.
public struct DocumentContentsSummary: Equatable, Sendable {
    public var hasFormFields = false
    public var hasLinks = false
    public var hasNamedDestinations = false

    public init(hasFormFields: Bool = false, hasLinks: Bool = false, hasNamedDestinations: Bool = false) {
        self.hasFormFields = hasFormFields
        self.hasLinks = hasLinks
        self.hasNamedDestinations = hasNamedDestinations
    }
}

/// What a signature field says about its signature. Whether the certificate can be trusted isn't
/// checked: that needs the signature's cryptography (see FUTURE_FEATURES section 2).
public struct PDFSignatureInfo: Equatable, Sendable {
    public var isSigned: Bool
    public var signer: String?
    public var date: Date?
    public var reason: String?
    public var location: String?
    /// The file was saved again after it was signed (a later revision can change what was
    /// signed); nil when that can't be told.
    public var changedSinceSigning: Bool?
    /// For a signature that certifies the document, the changes it allows.
    public var certification: Certification?

    public enum Certification: Int, Sendable {
        case noChanges = 1, formFillingAndSigning = 2, formFillingSigningAndAnnotations = 3

        public var description: String {
            switch self {
            case .noChanges: return "Certified: no changes allowed"
            case .formFillingAndSigning: return "Certified: form filling and signing allowed"
            case .formFillingSigningAndAnnotations: return "Certified: form filling, signing and comments allowed"
            }
        }
    }
}

/// A form field in the Document tab: one row per field on a page (a group of radio buttons or
/// checkboxes sharing a name is one).
public struct PDFFormFieldEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let pageIndex: Int
    public let type: PDFWidgetType
    /// Page (top-down) coordinates.
    public let rect: CGRect
    /// Fully qualified, as in `address.city`.
    public let name: String
    /// The field's own description (/TU), shown in place of its name when it has one.
    public let label: String?
    public let value: String
    public let isReadOnly: Bool
    public let isRequired: Bool
    public let signature: PDFSignatureInfo?

    /// The name shown for it: its description, else the last part of its name.
    public var displayName: String {
        if let label, !label.isEmpty { return label }
        let last = name.split(separator: ".").last.map(String.init) ?? name
        return last.isEmpty ? "Unnamed \(type.displayName.lowercased())" : last
    }

    /// Its value as shown in the list: "Off" for an unchecked box, for instance, reads as empty.
    public var displayValue: String {
        switch type {
        case .checkbox, .radiobutton:
            return value.isEmpty || value == "Off" ? "" : (value == "Yes" || value == "On" ? "Checked" : value)
        case .button, .signature:
            return ""
        default:
            return value
        }
    }
}

extension PDFWidgetType {
    public var displayName: String {
        switch self {
        case .unknown: return "Field"
        case .button: return "Button"
        case .checkbox: return "Checkbox"
        case .combobox: return "Pop-up menu"
        case .listbox: return "List"
        case .radiobutton: return "Radio buttons"
        case .signature: return "Signature"
        case .text: return "Text field"
        }
    }

    public var systemImage: String {
        switch self {
        case .unknown: return "rectangle.dashed"
        case .button: return "button.horizontal"
        case .checkbox: return "checkmark.square"
        case .combobox: return "filemenu.and.selection"
        case .listbox: return "list.bullet.rectangle"
        case .radiobutton: return "circle.inset.filled"
        case .signature: return "signature"
        case .text: return "character.textbox"
        }
    }
}

/// A link on a page, for the Document tab.
public struct PDFDocumentLink: Identifiable, Equatable, Sendable {
    public let id: String
    public let pageIndex: Int
    /// Page (top-down) coordinates.
    public let rect: CGRect
    /// The text under the link, or empty, read when its page is first shown in the list.
    public internal(set) var text: String
    public let uri: String?
    /// The page it goes to, for a link inside the document.
    public let targetPage: Int?
    public let targetPoint: CGPoint?

    public var isExternal: Bool { targetPage == nil }

    /// What it goes to, as the list shows it.
    public var destinationDescription: String {
        if let targetPage { return "Page \(targetPage + 1)" }
        guard let uri else { return "" }
        return uri.hasPrefix("mailto:") ? String(uri.dropFirst("mailto:".count)) : uri
    }
}

/// A named destination: a place in the document links can point to by name.
public struct PDFNamedDestination: Identifiable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let pageIndex: Int?
    public let point: CGPoint?
}

extension PDFDocumentCore {
    /// Whether the document has form fields, links or named destinations.
    public func contentsSummary() -> DocumentContentsSummary {
        guard isPDF else { return DocumentContentsSummary() }
        return withLockedDocument { ctx, doc in
            DocumentContentsSummary(
                hasFormFields: mupdf_pdf_has_form_fields(ctx, doc) != 0,
                hasLinks: mupdf_pdf_has_links(ctx, doc) != 0,
                hasNamedDestinations: mupdf_pdf_list_named_dests(ctx, doc, nil, 0) > 0
            )
        }
    }

    /// The form fields on a page, in the page's order, a group of radio buttons or checkboxes
    /// sharing a name once.
    public func formFieldEntries(pageIndex: Int) -> [PDFFormFieldEntry] {
        guard isPDF, pageIndex >= 0, pageIndex < pageCount else { return [] }
        let raw: [mupdf_form_field] = withLockedDocument { ctx, doc in
            let count = Int(mupdf_page_list_form_fields(ctx, doc, Int32(pageIndex), nil, 0))
            guard count > 0 else { return [] }
            var entries = [mupdf_form_field](repeating: mupdf_form_field(), count: count)
            let listed = Int(mupdf_page_list_form_fields(ctx, doc, Int32(pageIndex), &entries, Int32(count)))
            return Array(entries.prefix(max(0, min(listed, count))))
        }
        var result: [PDFFormFieldEntry] = []
        var seenGroups = Set<String>()
        for var entry in raw {
            func text<T>(_ field: inout T) -> String {
                withUnsafeBytes(of: &field) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            }
            func optional(_ string: String) -> String? {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let type = PDFWidgetType(rawValue: Int(entry.type)) ?? .unknown
            let name = text(&entry.name)
            if type == .radiobutton || type == .checkbox, !name.isEmpty {
                guard seenGroups.insert(name).inserted else { continue }
            }
            var signature: PDFSignatureInfo?
            if type == .signature {
                signature = PDFSignatureInfo(
                    isSigned: entry.is_signed != 0,
                    signer: optional(text(&entry.signer)),
                    date: entry.signed_time >= 0 ? Date(timeIntervalSince1970: TimeInterval(entry.signed_time)) : nil,
                    reason: optional(text(&entry.reason)),
                    location: optional(text(&entry.location)),
                    changedSinceSigning: entry.changed_since_signing < 0 ? nil : entry.changed_since_signing != 0,
                    certification: PDFSignatureInfo.Certification(rawValue: Int(entry.certification))
                )
            }
            result.append(PDFFormFieldEntry(
                id: "p\(pageIndex)_o\(entry.object_number)_\(result.count)",
                pageIndex: pageIndex,
                type: type,
                rect: CGRect(x: CGFloat(entry.x0), y: CGFloat(entry.y0), width: CGFloat(entry.x1 - entry.x0), height: CGFloat(entry.y1 - entry.y0)),
                name: name,
                label: optional(text(&entry.label)),
                value: text(&entry.value),
                isReadOnly: entry.flags & 1 != 0,
                isRequired: entry.flags & 2 != 0,
                signature: signature
            ))
        }
        return result
    }

    /// The links on a page, for the Document tab: where each is and goes, without the text
    /// under it, which needs the page's text read (see `linkTexts`).
    public func documentLinks(pageIndex: Int) -> [PDFDocumentLink] {
        guard pageIndex >= 0, pageIndex < pageCount else { return [] }
        return withLockedDocument { ctx, doc -> [PDFDocumentLink] in
            var pagePtr: FZPage?
            guard mupdf_page_load(ctx, doc, Int32(pageIndex), &pagePtr, nil) == 0, let page = pagePtr else { return [] }
            defer { mupdf_page_drop(ctx, page) }
            var linksPtr: FZLink?
            guard mupdf_links_load(ctx, page, &linksPtr, nil) == 0, let links = linksPtr else { return [] }
            defer { mupdf_links_drop(ctx, links) }
            var result: [PDFDocumentLink] = []
            var current: FZLink? = links
            while let link = current {
                defer { current = mupdf_link_next(link) }
                guard let cURI = mupdf_link_uri(link) else { continue }
                let uri = String(cString: cURI)
                let r = mupdf_link_rect(link)
                let rect = CGRect(x: CGFloat(r.x0), y: CGFloat(r.y0), width: CGFloat(r.x1 - r.x0), height: CGFloat(r.y1 - r.y0))
                var destPage: Int32 = -1
                var x: Float = 0, y: Float = 0
                let isInternal = mupdf_resolve_link_page(ctx, doc, uri, &destPage, &x, &y) == 0 && destPage >= 0
                // Only links that go somewhere: a page here, or a web or mail address.
                guard isInternal || uri.hasPrefix("http://") || uri.hasPrefix("https://") || uri.hasPrefix("mailto:") else { continue }
                result.append(PDFDocumentLink(
                    id: "p\(pageIndex)_l\(result.count)",
                    pageIndex: pageIndex,
                    rect: rect,
                    text: "",
                    uri: uri,
                    targetPage: isInternal ? Int(destPage) : nil,
                    targetPoint: isInternal ? CGPoint(x: CGFloat(x), y: CGFloat(y)) : nil
                ))
            }
            return result
        }
    }

    /// The text under each of `rects` on a page (empty where there's none, or it's long), from
    /// the page's text.
    public func linkTexts(pageIndex: Int, rects: [CGRect]) -> [String] {
        guard let page = loadStructuredPage(for: pageIndex) else { return rects.map { _ in "" } }
        let characters = page.allCharacters
        return rects.map { rect in
            let chars = characters.filter { ch in
                let overlap = rect.intersection(ch.boundingRect)
                guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return false }
                return overlap.height / ch.boundingRect.height >= 0.35
            }
            let text = String(chars.map(\.char))
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.count <= 100 ? text : ""
        }
    }

    /// The document's named destinations, in the order of its name tree (sorted by name), then
    /// any only in the PDF 1.1 /Dests dictionary. Not sorted again: there can be hundreds of
    /// thousands.
    public func namedDestinations() -> [PDFNamedDestination] {
        guard isPDF else { return [] }
        let raw: [mupdf_named_dest] = withLockedDocument { ctx, doc in
            let estimate = Int(mupdf_pdf_list_named_dests(ctx, doc, nil, 0))
            guard estimate > 0 else { return [] }
            var entries = [mupdf_named_dest](repeating: mupdf_named_dest(), count: estimate)
            let listed = Int(mupdf_pdf_list_named_dests(ctx, doc, &entries, Int32(estimate)))
            return Array(entries.prefix(min(listed, estimate)))
        }
        return raw.map { entry -> PDFNamedDestination in
            var entry = entry
            let name = withUnsafeBytes(of: &entry.name) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
            let page = entry.page >= 0 && Int(entry.page) < pageCount ? Int(entry.page) : nil
            return PDFNamedDestination(name: name, pageIndex: page, point: page == nil ? nil : CGPoint(x: CGFloat(entry.x), y: CGFloat(entry.y)))
        }
    }
}
