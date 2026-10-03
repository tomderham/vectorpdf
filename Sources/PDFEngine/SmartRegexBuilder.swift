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

public struct SmartRegexBuilder {
    /// Strips a single layer of surrounding straight or curly quotes.
    private static func stripSurroundingQuotes(_ query: String) -> String {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("“") && trimmed.hasSuffix("”")) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// Compiles a search query into a regular expression pattern matching hyphens, dashes, quotes, and whitespace variations.
    public static func buildPattern(from query: String) -> String {
        let trimmed = stripSurroundingQuotes(query)
        guard !trimmed.isEmpty else { return "" }

        let separatorChars: Set<Character> = [" ", "\t", "-", "\u{00AD}", "–", "—", "−"]
        
        var pattern = ""
        var inSeparator = false
        
        for char in trimmed {
            if separatorChars.contains(char) {
                if !inSeparator {
                    // Match combinations of hyphens, dashes, or whitespace
                    pattern.append("[-–—−\u{00AD}\\s]+")
                    inSeparator = true
                }
            } else {
                inSeparator = false
                switch char {
                case "\"", "“", "”", "„":
                    pattern.append("[\"“”„]")
                case "'", "‘", "’":
                    pattern.append("['‘’]")
                default:
                    pattern.append(NSRegularExpression.escapedPattern(for: String(char)))
                }
            }
        }
        
        return pattern
    }

    /// Compiles a search query into a literal regex pattern with escaped metacharacters.
    public static func buildLiteralPattern(from query: String) -> String {
        let trimmed = stripSurroundingQuotes(query)
        guard !trimmed.isEmpty else { return "" }
        return NSRegularExpression.escapedPattern(for: trimmed)
    }

    /// Wraps a compiled pattern with word-boundary anchors to match whole words.
    public static func applyWholeWord(_ pattern: String) -> String {
        guard !pattern.isEmpty else { return pattern }
        return "\\b(?:\(pattern))\\b"
    }
}
