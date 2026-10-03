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

/// Redaction mode: manual region redaction or pattern search redaction.
public enum EditRedactTab: String, CaseIterable, Identifiable, Sendable {
    case redactRegion = "Redact Region"
    case findAndRedact = "Find & Redact"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .redactRegion: return "rectangle.dashed.badge.record"
        case .findAndRedact: return "magnifyingglass"
        }
    }

    // Aliases
    public static var redact: EditRedactTab { .redactRegion }
    public static var replace: EditRedactTab { .findAndRedact }
    public static var findAndReplace: EditRedactTab { .findAndRedact }
}

/// Harmonized color control for redacted areas (Black or White).
public enum RedactionColor: String, CaseIterable, Identifiable, Sendable {
    case black = "Black"
    case white = "White"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .black: return "circle.fill"
        case .white: return "circle"
        }
    }

    // Aliases
    public static var blackout: RedactionColor { .black }
    public static var whiteout: RedactionColor { .white }
}

public typealias RedactionStyle = RedactionColor

/// The operation to perform on found matches:
/// - redact: cover the text with a redact rectangle (in black or white)
/// - remove: excise the text permanently from the content stream
public enum RedactAction: String, CaseIterable, Identifiable, Sendable {
    case redact = "Redact"
    case remove = "Remove"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .redact: return "lock.slash.fill"
        case .remove: return "trash"
        }
    }

    // Aliases
    public static var delete: RedactAction { .remove }
    public static var text: RedactAction { .remove }
}

public typealias ReplaceAction = RedactAction

/// Preset search patterns for common sensitive data identification.
public enum RedactionPreset: String, CaseIterable, Identifiable, Sendable {
    case customText = "Text / Phrase"
    case customRegex = "Custom Regular Expression"
    case ssn = "Social Security Number (SSN)"
    case creditCard = "Credit Card Number"
    case email = "Email Address"
    case phone = "Phone Number"
    case date = "Date"

    public var id: String { rawValue }

    /// Returns the compiled regular expression pattern for built-in presets, or `nil` for custom text/regex.
    public var regexPattern: String? {
        switch self {
        case .customText, .customRegex:
            return nil
        case .ssn:
            return #"\b\d{3}[- ]?\d{2}[- ]?\d{4}\b"#
        case .creditCard:
            // 13–19 digits with optional separators
            return #"\b\d(?:[- ]?\d){12,18}\b"#
        case .email:
            return #"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b"#
        case .phone:
            // Matches phone numbers in international and national formats
            return #"(?:(?<![\w+])(?:\+\d{1,3}[-.\s]?)?(?:\(?\d{1,4}\)?[-.\s]?)?\d{3,4}[-.\s]?\d{3,4}\b)"#
        case .date:
            // Matches common date formats
            return #"\b(?:\d{1,2}[-/\.]\d{1,2}[-/\.]\d{2,4}|\d{4}[-/\.]\d{1,2}[-/\.]\d{1,2}|\d{1,2}[-\s](?:Jan(?:uary)?|Feb(?:ruary)?|Mar(?:ch)?|Apr(?:il)?|May|Jun(?:e)?|Jul(?:y)?|Aug(?:ust)?|Sep(?:tember)?|Oct(?:ober)?|Nov(?:ember)?|Dec(?:ember)?)[-\s]\d{2,4})\b"#
        }
    }

    public var placeholder: String {
        switch self {
        case .customText:
            return "Enter text to find..."
        case .customRegex:
            return #"Enter regex (e.g. [A-Z]{3}-\d{5})..."#
        case .ssn:
            return "Auto-detects SSNs (e.g. 123-45-6789)"
        case .creditCard:
            return "Auto-detects credit card numbers"
        case .email:
            return "Auto-detects email addresses"
        case .phone:
            return "Auto-detects phone numbers"
        case .date:
            return "Auto-detects dates (e.g. 12/31/2026, 25 Dec 2026)"
        }
    }

    public var iconName: String {
        switch self {
        case .customText:
            return "text.magnifyingglass"
        case .customRegex:
            return "chevron.left.forwardslash.chevron.right"
        case .ssn:
            return "person.text.rectangle"
        case .creditCard:
            return "creditcard"
        case .email:
            return "envelope"
        case .phone:
            return "phone"
        case .date:
            return "calendar"
        }
    }
}

/// Represents an identified search match candidate for redaction or replacement with selection state.
public struct RedactionMatchItem: Identifiable, Sendable {
    public let id: UUID
    public let result: SearchResult
    public var replacementText: String
    public var isSelected: Bool

    public init(id: UUID = UUID(), result: SearchResult, replacementText: String = "", isSelected: Bool = true) {
        self.id = id
        self.result = result
        self.replacementText = replacementText
        self.isSelected = isSelected
    }
}

public typealias EditRedactMatchItem = RedactionMatchItem
