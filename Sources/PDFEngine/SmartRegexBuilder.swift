import Foundation

public struct SmartRegexBuilder {
    /// Strips a single layer of surrounding straight or curly quotes used to mark an
    /// exact phrase, shared by both the smart and literal pattern builders below.
    private static func stripSurroundingQuotes(_ query: String) -> String {
        var trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if (trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"")) ||
           (trimmed.hasPrefix("“") && trimmed.hasSuffix("”")) {
            trimmed = String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return trimmed
    }

    /// Compiles a user search query into a regular expression pattern invariant to
    /// line-break hyphens, dashes, quotation marks, and whitespace variations.
    /// Specifically treats spaces and hyphens/dashes interchangeably (e.g. "MU MIMO" matches "MU-MIMO").
    public static func buildPattern(from query: String) -> String {
        let trimmed = stripSurroundingQuotes(query)
        guard !trimmed.isEmpty else { return "" }

        let separatorChars: Set<Character> = [" ", "\t", "-", "\u{00AD}", "–", "—", "−"]
        
        var pattern = ""
        var inSeparator = false
        
        for char in trimmed {
            if separatorChars.contains(char) {
                if !inSeparator {
                    // Match any combination of hyphens, dashes, or whitespace
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

    /// Compiles a user search query into a regex pattern that matches the query literally
    /// (regex metacharacters escaped, but no hyphen/dash/quote normalization) — used when
    /// `SearchOptions.smartSearch` is disabled.
    public static func buildLiteralPattern(from query: String) -> String {
        let trimmed = stripSurroundingQuotes(query)
        guard !trimmed.isEmpty else { return "" }
        return NSRegularExpression.escapedPattern(for: trimmed)
    }

    /// Wraps a compiled pattern with word-boundary anchors so it only matches whole words,
    /// i.e. the boundary applies to the two ends of the whole search term (matching how
    /// "whole word" works in apps like Xcode/Word), not to any separators inside it.
    public static func applyWholeWord(_ pattern: String) -> String {
        guard !pattern.isEmpty else { return pattern }
        return "\\b(?:\(pattern))\\b"
    }
}
