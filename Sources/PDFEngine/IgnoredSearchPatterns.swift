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
import SwiftUI

/// Text that Smart Search looks past, set in Settings: markup some documents put inside their
/// sentences, such as the comment-resolution tags in IEEE 802.11 drafts ("Header(#6820) field"),
/// which would otherwise split the phrases around them.
public struct IgnoredSearchPattern: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    /// A regular expression.
    public var pattern: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, pattern: String, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.pattern = pattern
        self.isEnabled = isEnabled
    }

    /// Why `pattern` can't be used, or nil if it can.
    public var validationError: String? {
        guard !pattern.isEmpty else { return "Enter a regular expression." }
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            if regex.firstMatch(in: "", range: NSRange(location: 0, length: 0)) != nil {
                return "Matches empty text."
            }
            return nil
        } catch {
            return "Not a valid regular expression."
        }
    }

    /// Ready-made patterns offered in Settings, none on until added. Each only adds matches:
    /// search still tries the text as it is.
    public static let templates: [IgnoredSearchPattern] = [
        IgnoredSearchPattern(
            name: "Numeric citations [12]",
            // "shown [12] that", "[3, 5]", "[3–7]"; with the space before, so "results [4]." joins up.
            pattern: #"\s*\[\d+(?:\s*[,–-]\s*\d+)*\]"#
        ),
        IgnoredSearchPattern(
            name: "Trademark symbols ™ ®",
            pattern: #"[™®℠]"#
        ),
        IgnoredSearchPattern(
            name: "Star paging *123",
            // Reporter page breaks in court opinions: "the court *456 held".
            pattern: #"\s*(?<![\p{L}\p{N}*])\*\d+\b"#
        ),
        IgnoredSearchPattern(
            name: "IEEE 802.11 comment tags (#1234)",
            // "(#6820)", "(#Ed)", "(#12236, Ed)"
            pattern: #"\(#[A-Za-z0-9]+(?:,\s*#?[A-Za-z0-9]+)*\)"#
        ),
    ]

    /// The template named `name`.
    static func template(_ name: String) -> IgnoredSearchPattern? {
        templates.first { $0.name.hasPrefix(name) }
    }

    /// One expression matching any of `patterns`, skipping invalid ones; nil if none are usable.
    public static func combinedRegex(_ patterns: [String]) -> NSRegularExpression? {
        let usable = patterns.filter { IgnoredSearchPattern(name: "", pattern: $0).validationError == nil }
        guard !usable.isEmpty else { return nil }
        return try? NSRegularExpression(pattern: usable.map { "(?:\($0))" }.joined(separator: "|"))
    }
}

/// Text with every match of an ignored pattern (or other ranges) removed, and where each of its
/// UTF-16 units came from in the original, so a match in it can be highlighted on the page.
struct TextWithoutIgnored {
    let text: String
    /// `offsets[i]` is the original UTF-16 offset of unit `i` of `text`; one more entry, at the
    /// end, is the original's length.
    let offsets: [Int]

    /// Nil when nothing in `original` matches `ignored`.
    init?(_ original: String, ignoring ignored: NSRegularExpression) {
        let ns = original as NSString
        self.init(original, removing: ignored.matches(in: original, range: NSRange(location: 0, length: ns.length)).map(\.range))
    }

    /// Nil when `ranges` is empty.
    init?(_ original: String, removing ranges: [NSRange]) {
        guard !ranges.isEmpty else { return nil }
        let ns = original as NSString
        var kept = ""
        var offsets: [Int] = []
        var cursor = 0
        for range in ranges.sorted(by: { $0.location < $1.location }) + [NSRange(location: ns.length, length: 0)] {
            if range.location > cursor {
                kept += ns.substring(with: NSRange(location: cursor, length: range.location - cursor))
                offsets.append(contentsOf: cursor..<range.location)
            }
            cursor = max(cursor, NSMaxRange(range))
        }
        offsets.append(ns.length)
        self.text = kept
        self.offsets = offsets
    }

    /// The range in the original covered by `range` of `text`, from its first unit to its last.
    func originalRange(of range: NSRange) -> NSRange {
        let start = offsets[range.location]
        let end = range.length > 0 ? offsets[NSMaxRange(range) - 1] + 1 : start
        return NSRange(location: start, length: end - start)
    }

    /// The original offsets of the units in `range` of `text`.
    func originalOffsets(of range: NSRange) -> [Int] {
        Array(offsets[range.location..<NSMaxRange(range)])
    }
}

// MARK: - Settings

/// Settings sheet listing the ignored search patterns: each can be switched off, renamed, edited
/// or removed, and more added blank or from a template.
struct IgnoredSearchPatternsView: View {
    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ignored Search Patterns")
                .font(.headline)
            Text("With Smart Search on, a phrase is found even if it is interrupted by text matching any of the following regular expressions.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if coordinator.ignoredSearchPatterns.isEmpty {
                Text("No patterns.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach($coordinator.ignoredSearchPatterns) { $item in
                            row($item)
                        }
                    }
                }
                .frame(minHeight: 60, maxHeight: 260)
            }

            HStack {
                Button {
                    coordinator.ignoredSearchPatterns.append(IgnoredSearchPattern(name: "New Pattern", pattern: ""))
                } label: {
                    Label("Add", systemImage: "plus")
                }
                Menu("Add from Template") {
                    ForEach(IgnoredSearchPattern.templates) { template in
                        Button(template.name) {
                            coordinator.ignoredSearchPatterns.append(IgnoredSearchPattern(name: template.name, pattern: template.pattern))
                        }
                    }
                }
                .fixedSize()
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func row(_ item: Binding<IgnoredSearchPattern>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle("", isOn: item.isEnabled)
                    .labelsHidden()
                TextField("Name", text: item.name)
                Button(role: .destructive) {
                    coordinator.ignoredSearchPatterns.removeAll { $0.id == item.wrappedValue.id }
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove Pattern")
            }
            TextField("Regular expression", text: item.pattern)
                .font(.system(.body, design: .monospaced))
                .disabled(!item.wrappedValue.isEnabled)
            if let error = item.wrappedValue.validationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }
}
