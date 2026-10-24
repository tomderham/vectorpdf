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

/// Resolves a web link to a document that is already open in another tab, so a peek can show the
/// target from that tab. Covers IETF RFCs: their PDFs link to each other by URL
/// (`https://www.rfc-editor.org/rfc/rfc9110#section-5.6.1`), and the fragment is a named
/// destination that the RFC's own PDF also carries.
public enum CrossDocLinkResolver {

    /// RFC hosts whose URLs name an RFC in their last path component.
    private static let rfcHosts = ["rfc-editor.org", "ietf.org"]

    /// The RFC number and fragment ("section-5.6.1") a URL points to: rfc-editor.org/rfc/rfc9110,
    /// …/info/rfc9110, datatracker.ietf.org/doc/html/rfc9110, ietf.org/rfc/rfc9110.txt, ….
    static func rfcReference(in uri: String) -> (number: Int, fragment: String?)? {
        guard let components = URLComponents(string: uri), let host = components.host?.lowercased(),
              rfcHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        let name = ((components.path as NSString).lastPathComponent as NSString).deletingPathExtension.lowercased()
        guard name.hasPrefix("rfc"), let number = Int(name.dropFirst(3)), number > 0 else { return nil }
        let fragment = components.fragment.flatMap { $0.isEmpty ? nil : $0 }
        return (number, fragment)
    }

    private static let fileNamePattern = try! NSRegularExpression(
        pattern: #"(?:^|[^a-z])rfc[ _-]*0*([1-9][0-9]{0,4})(?![0-9])"#, options: [.caseInsensitive])

    /// "RFC 9111" as the opening title line (rfc-editor.org PDFs), or the "Request for Comments:
    /// 9111" header of the plain-text layout.
    private static let firstPagePattern = try! NSRegularExpression(
        pattern: #"\A\s*RFC\s+([1-9][0-9]{0,4})\s*$|Request for Comments:\s*([1-9][0-9]{0,4})\b"#,
        options: [.anchorsMatchLines])

    /// The RFC number in a file name such as "rfc9110.pdf" or "RFC 9110 HTTP Semantics.pdf".
    static func rfcNumber(fileName: String) -> Int? {
        firstNumber(fileNamePattern, in: fileName)
    }

    /// The RFC number declared on an RFC's first page.
    static func rfcNumber(firstPageText text: String) -> Int? {
        firstNumber(firstPagePattern, in: String(text.prefix(2000)))
    }

    private static func firstNumber(_ pattern: NSRegularExpression, in text: String) -> Int? {
        let ns = text as NSString
        guard let match = pattern.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        for group in 1..<match.numberOfRanges where match.range(at: group).location != NSNotFound {
            return Int(ns.substring(with: match.range(at: group)))
        }
        return nil
    }

    /// First-page lookups, by file path: hovering asks on every mouse move.
    @MainActor private static var firstPageRFCNumbers: [String: Int?] = [:]

    /// The RFC an open document is, from its file name or else its first page.
    @MainActor static func rfcNumber(of viewModel: PDFViewerViewModel) -> Int? {
        guard let doc = viewModel.document else { return nil }
        if let number = rfcNumber(fileName: viewModel.documentTitle) { return number }
        if let cached = firstPageRFCNumbers[doc.filePath] { return cached }
        let number = doc.extractText(pageIndex: 0).flatMap { rfcNumber(firstPageText: $0) }
        firstPageRFCNumbers[doc.filePath] = number
        return number
    }

    /// Where web link `link` leads in one of `viewModels`, or nil when it names no open document.
    /// The returned target keeps the link's id and source, so it can stand in for the link.
    @MainActor public static func target(for link: SnapshotTarget, in viewModels: [PDFViewerViewModel]) -> (viewModel: PDFViewerViewModel, target: SnapshotTarget)? {
        guard link.targetPage < 0, let uri = link.uri, let reference = rfcReference(in: uri),
              let viewModel = viewModels.first(where: { rfcNumber(of: $0) == reference.number }),
              let doc = viewModel.document, doc.pageCount > 0 else { return nil }

        let destination: (page: Int, point: CGPoint)
        if let fragment = reference.fragment {
            guard let resolved = doc.resolveLinkDestination(uri: "#nameddest=" + fragment)
                    ?? outlineDestination(forFragment: fragment, in: viewModel) else { return nil }
            destination = resolved
        } else {
            // The document as a whole ("[HTTP]" citations link to its info page): its first page.
            let bounds = doc.pageBounds[0]
            destination = (0, CGPoint(x: bounds.minX, y: bounds.minY))
        }
        return (viewModel, SnapshotTarget(
            id: link.id,
            label: link.label,
            targetPage: destination.page,
            targetPoint: destination.point,
            sourceRect: link.sourceRect,
            sourcePage: link.sourcePage,
            uri: reference.fragment.map { "#nameddest=" + $0 }
        ))
    }

    /// For PDFs without named destinations: "section-5.6.1" or "appendix-B.1" matched against the
    /// outline, as a written reference to that section would be.
    @MainActor private static func outlineDestination(forFragment fragment: String, in viewModel: PDFViewerViewModel) -> (page: Int, point: CGPoint)? {
        let parts = fragment.split(separator: "-", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return nil }
        let kind: ParsedReference.Kind
        switch parts[0].lowercased() {
        case "section": kind = .section
        case "appendix": kind = .appendix
        default: return nil
        }
        let reference = ParsedReference(
            kind: kind, label: parts[0].capitalized, identifier: parts[1], quotedTitle: nil,
            docHint: nil, range: NSRange(location: 0, length: 0)
        )
        let candidates = CrossDocReferenceFinder.outlineCandidates(for: reference, in: [viewModel])
        guard CrossDocReferenceFinder.isConfident(candidates), let best = candidates.first else { return nil }
        return (best.target.targetPage, best.target.targetPoint ?? .zero)
    }
}
