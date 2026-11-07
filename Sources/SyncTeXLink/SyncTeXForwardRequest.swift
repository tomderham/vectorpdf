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

/// A forward search: show the place in a PDF that a line of its TeX source made. `displayline`
/// sends it to the app as a `vectorpdf://synctex?...` URL (see `url`), and the app reads it back
/// with `init?(url:)`.
///
/// Any web page can link to a `vectorpdf:` URL, so reading one is strict: anything not exactly as
/// `url` writes it is refused rather than guessed at. Even a well-formed request can only show a
/// PDF that has SyncTeX data beside it; it never starts an editor or changes a file.
public struct SyncTeXForwardRequest: Equatable, Sendable {
    public static let scheme = "vectorpdf"
    public static let host = "synctex"

    /// Longest path accepted; macOS's own limit is 1024 bytes.
    public static let maximumPathLength = 1024
    /// Longest URL accepted: two paths, percent-encoded, and the numbers.
    public static let maximumURLLength = 8 * 1024
    public static let maximumLine = 10_000_000
    public static let maximumColumn = 100_000

    /// The PDF, as an absolute, standardized path.
    public let pdfPath: String
    /// 1-based, as editors count.
    public let line: Int
    /// 0-based column, or nil when the editor doesn't say.
    public let column: Int?
    /// The source file the line is in, as an absolute path; nil for the main file.
    public let sourcePath: String?
    /// Leave VectorPDF behind the editor (`displayline -g`).
    public let inBackground: Bool
    /// Read the PDF and its SyncTeX file again first, even if they look unchanged (`displayline -r`).
    public let reloads: Bool

    public init?(pdfPath: String, line: Int, column: Int? = nil, sourcePath: String? = nil, inBackground: Bool = false, reloads: Bool = false) {
        guard let pdf = Self.validatedPath(pdfPath), pdf.lowercased().hasSuffix(".pdf"),
              (1...Self.maximumLine).contains(line) else { return nil }
        if let column, !(0...Self.maximumColumn).contains(column) { return nil }
        var source: String?
        if let sourcePath {
            guard let valid = Self.validatedPath(sourcePath) else { return nil }
            source = valid
        }
        self.pdfPath = pdf
        self.line = line
        self.column = column
        self.sourcePath = source
        self.inBackground = inBackground
        self.reloads = reloads
    }

    // MARK: - URL

    private enum Key: String, CaseIterable {
        case pdf, line, column, source, background, reload
    }

    /// `vectorpdf://synctex?pdf=…&line=…[&column=…][&source=…][&background=1][&reload=1]`
    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = Self.host
        var items = [URLQueryItem(name: Key.pdf.rawValue, value: pdfPath),
                     URLQueryItem(name: Key.line.rawValue, value: String(line))]
        if let column { items.append(URLQueryItem(name: Key.column.rawValue, value: String(column))) }
        if let sourcePath { items.append(URLQueryItem(name: Key.source.rawValue, value: sourcePath)) }
        if inBackground { items.append(URLQueryItem(name: Key.background.rawValue, value: "1")) }
        if reloads { items.append(URLQueryItem(name: Key.reload.rawValue, value: "1")) }
        // URLQueryItem leaves "+" and "&"-adjacent characters that some readers treat specially;
        // encode everything but unreserved characters and "/" so a path reads back exactly.
        components.percentEncodedQueryItems = items.map { item in
            URLQueryItem(name: item.name, value: item.value?.addingPercentEncoding(withAllowedCharacters: Self.valueCharacters))
        }
        return components.url!
    }

    private static let valueCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")

    /// Reads a URL `url` wrote; nil for anything else: another scheme or host, a user, port,
    /// path or fragment, an unknown, repeated or empty key, a value that isn't exactly what's
    /// expected (digits only, `1` for flags), a relative or overlong path, or one with a NUL.
    public init?(url: URL) {
        guard url.absoluteString.utf8.count <= Self.maximumURLLength,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == Self.scheme,
              components.host?.lowercased() == Self.host,
              components.user == nil, components.password == nil, components.port == nil,
              components.percentEncodedPath.isEmpty || components.percentEncodedPath == "/",
              components.fragment == nil,
              let encodedItems = components.percentEncodedQueryItems, !encodedItems.isEmpty else { return nil }

        var values: [Key: String] = [:]
        for item in encodedItems {
            guard let key = Key(rawValue: item.name), values[key] == nil,
                  let encoded = item.value, !encoded.isEmpty,
                  let value = encoded.removingPercentEncoding else { return nil }
            values[key] = value
        }

        guard let pdf = values[.pdf], let lineText = values[.line], let line = Self.number(lineText) else { return nil }
        var column: Int?
        if let text = values[.column] {
            guard let value = Self.number(text) else { return nil }
            column = value
        }
        guard let inBackground = Self.flag(values[.background]), let reloads = Self.flag(values[.reload]) else { return nil }
        self.init(pdfPath: pdf, line: line, column: column, sourcePath: values[.source], inBackground: inBackground, reloads: reloads)
    }

    /// Digits only, no sign or spaces, at most 9 of them (so it can't overflow).
    private static func number(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 9, text.utf8.allSatisfy({ (0x30...0x39).contains($0) }) else { return nil }
        return Int(text)
    }

    /// Absent is false; present must be exactly "1".
    private static func flag(_ text: String?) -> Bool? {
        guard let text else { return false }
        return text == "1" ? true : nil
    }

    /// `path` with "." and ".." resolved, if it's absolute, not too long and free of
    /// NULs and other control characters.
    static func validatedPath(_ path: String) -> String? {
        guard path.hasPrefix("/"), path.utf8.count <= maximumPathLength,
              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        // "." and ".." only: NSString's standardizingPath also rewrites /private/tmp as /tmp,
        // which isn't the name TeX recorded.
        let standardized = URL(fileURLWithPath: path).standardized.path
        guard standardized.hasPrefix("/"), standardized != "/" else { return nil }
        return standardized
    }
}

// MARK: - displayline

extension SyncTeXForwardRequest {
    /// What `displayline` was asked for, or why it can't do it.
    public enum CommandLine: Equatable {
        case request(SyncTeXForwardRequest)
        case help
        case invalid(String)
    }

    public static let usage = """
    Usage: displayline [-r] [-b] [-g] LINE PDFFILE [TEXSOURCEFILE]
      Shows in VectorPDF the place in PDFFILE that LINE of TEXSOURCEFILE made, using the
      SyncTeX file TeX wrote beside it (compile with -synctex=1). LINE may be LINE:COLUMN.
      -r  read the PDF again first        -g  leave VectorPDF in the background
      -b  accepted for compatibility with Skim (VectorPDF always highlights the line)
    """

    /// Reads `displayline`'s arguments (without the program name), as Skim's `displayline` takes
    /// them, so editors set up for Skim work by pointing at this one. Relative paths are taken
    /// from `currentDirectory`.
    public static func parseCommandLine(_ arguments: [String], currentDirectory: String) -> CommandLine {
        var reloads = false
        var inBackground = false
        var positional: [String] = []
        var optionsEnded = false
        for argument in arguments {
            if !optionsEnded, argument.hasPrefix("-"), argument.count > 1 {
                switch argument {
                case "-r", "--reload": reloads = true
                case "-g", "--background": inBackground = true
                case "-b", "--readingbar": break
                case "-h", "--help": return .help
                case "--": optionsEnded = true
                default: return .invalid("Unknown option \(argument)")
                }
            } else {
                positional.append(argument)
            }
        }
        guard (2...3).contains(positional.count) else { return .invalid("Expected LINE PDFFILE [TEXSOURCEFILE]") }

        let lineParts = positional[0].split(separator: ":", omittingEmptySubsequences: false)
        guard (1...2).contains(lineParts.count), let line = number(String(lineParts[0])) else {
            return .invalid("LINE must be a number, or LINE:COLUMN")
        }
        var column: Int?
        if lineParts.count == 2 {
            guard let value = number(String(lineParts[1])) else { return .invalid("COLUMN must be a number") }
            column = value
        }

        func absolute(_ path: String) -> String {
            path.hasPrefix("/") ? path : (currentDirectory as NSString).appendingPathComponent(path)
        }
        var pdf = absolute(positional[1])
        // Skim accepts the file without its extension.
        if !pdf.lowercased().hasSuffix(".pdf") { pdf += ".pdf" }
        let source = positional.count == 3 ? absolute(positional[2]) : nil
        guard let request = SyncTeXForwardRequest(pdfPath: pdf, line: line, column: column, sourcePath: source,
                                                  inBackground: inBackground, reloads: reloads) else {
            return .invalid("Invalid line or path")
        }
        return .request(request)
    }
}
