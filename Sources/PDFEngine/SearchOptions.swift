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

/// User-configurable search matching options.
public struct SearchOptions: Sendable, Equatable {
    /// When false (default), matching is case-insensitive.
    public var matchCase: Bool
    /// When true, only matches bounded by word boundaries at the start/end of the query.
    public var wholeWord: Bool
    /// When true (default), normalizes whitespace, dashes, and quotes. When false, matches literally.
    public var smartSearch: Bool
    /// When true, the query string is evaluated directly as a raw regular expression.
    public var isRegex: Bool

    public init(matchCase: Bool = false, wholeWord: Bool = false, smartSearch: Bool = true, isRegex: Bool = false) {
        self.matchCase = matchCase
        self.wholeWord = wholeWord
        self.smartSearch = smartSearch
        self.isRegex = isRegex
    }
}
