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

/// What an internal link points at, from destination data only: hyperref destination names
/// (`equation.2.3`, `cite.<key>`, …), or a destination shared with an outline entry (a heading).
public enum LinkTargetKind: Equatable, Sendable {
    case citation
    case footnote
    case equation
    case heading
    case table
    case figure
    case algorithm
    /// Theorem-like environments: theorems, lemmas, definitions, …
    case statement
    case listItem
    case unknown

    public init(uri: String?, outlineDestinationKeys: Set<String>) {
        if let name = Self.destinationName(from: uri),
           let kind = Self.kindsByCounterName[Self.counterName(of: name)] {
            self = kind
        } else if let key = Self.destinationKey(for: uri), outlineDestinationKeys.contains(key) {
            self = .heading
        } else {
            self = .unknown
        }
    }

    /// Peek extent around the destination, in page points; `nil` shows just the target line.
    /// Equations reach upwards since the destination is usually the (centred) number line.
    /// Unknown targets are mostly deep headings or captions, so get heading context.
    public var peekContext: (above: CGFloat, below: CGFloat)? {
        switch self {
        case .citation, .footnote: return nil
        case .listItem: return (0, 48)
        case .equation: return (48, 84)
        case .statement, .algorithm: return (0, 120)
        case .heading, .unknown: return (0, 144)
        // Beyond the peek's maximum height, so cut off with a fade.
        case .table, .figure: return (0, 600)
        }
    }

    /// hyperref counter names (the part of a destination name before the first `.`).
    private static let kindsByCounterName: [String: LinkTargetKind] = [
        "cite": .citation,
        "Hfootnote": .footnote,
        "equation": .equation,
        "AMS": .equation,
        "part": .heading,
        "chapter": .heading,
        "section": .heading,
        "subsection": .heading,
        "subsubsection": .heading,
        "paragraph": .heading,
        "subparagraph": .heading,
        "appendix": .heading,
        "table": .table,
        "subtable": .table,
        "figure": .figure,
        "subfigure": .figure,
        "algorithm": .algorithm,
        "algocf": .algorithm,
        "lstlisting": .algorithm,
        "theorem": .statement,
        "lemma": .statement,
        "proposition": .statement,
        "corollary": .statement,
        "definition": .statement,
        "remark": .statement,
        "example": .statement,
        "conjecture": .statement,
        "assumption": .statement,
        "Item": .listItem,
    ]

    static func destinationName(from uri: String?) -> String? {
        guard let uri, uri.hasPrefix("#nameddest=") else { return nil }
        let raw = String(uri.dropFirst("#nameddest=".count))
        let name = raw.removingPercentEncoding ?? raw
        return name.isEmpty ? nil : name
    }

    static func counterName(of destinationName: String) -> String {
        String(destinationName.prefix { $0 != "." })
    }

    /// Comparable destination identity: the name, or page and point from `#page=N&zoom=Z,X,Y`.
    /// Whole-page destinations return nil — sharing one doesn't make the target a heading.
    static func destinationKey(for uri: String?) -> String? {
        guard let uri else { return nil }
        if let name = destinationName(from: uri) { return "name:" + name }
        guard uri.hasPrefix("#page=") else { return nil }
        let params = uri.dropFirst().split(separator: "&")
        guard let page = params.first?.split(separator: "=").last,
              let zoom = params.first(where: { $0.hasPrefix("zoom=") }) else { return nil }
        let parts = zoom.dropFirst("zoom=".count).split(separator: ",")
        guard parts.count == 3, let x = Double(parts[1]), let y = Double(parts[2]), x.isFinite, y.isFinite else { return nil }
        return "page:\(page):\(Int(x.rounded())):\(Int(y.rounded()))"
    }
}
