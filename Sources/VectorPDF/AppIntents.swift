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

// Actions for Shortcuts, Spotlight and Siri. They live in the app's own module because the App
// Intents metadata (Contents/Resources/Metadata.appintents, made by Scripts/build_app_bundle.sh)
// is read from the app binary's module; the work is in PDFEngine's AppIntentActions.

import AppIntents
import Foundation
import UniformTypeIdentifiers
import PDFEngine

/// The file a document parameter names: the file itself, or a temporary copy when Shortcuts
/// passes only its contents. Nil for no file, meaning the front document.
private func filePath(of file: IntentFile?) throws -> String? {
    guard let file else { return nil }
    if let url = file.fileURL {
        _ = url.startAccessingSecurityScopedResource()
        return url.path
    }
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("VectorPDF Shortcuts", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let url = folder.appendingPathComponent(file.filename.isEmpty ? "Document.pdf" : file.filename)
    try file.data.write(to: url)
    return url.path
}

struct OpenDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Document"
    static let description = IntentDescription("Opens a document in VectorPDF, at a page if you give one. If the document is already open, its tab comes to the front.")
    static let openAppWhenRun = true

    @Parameter(title: "Document", supportedContentTypes: [.pdf, .epub])
    var document: IntentFile

    @Parameter(title: "Page", description: "The page number to go to, starting at 1.", inclusiveRange: (1, 100_000))
    var page: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$document) at page \(\.$page)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let url = document.fileURL else {
            throw AppIntentActions.Failure.couldNotOpen(document.filename)
        }
        _ = url.startAccessingSecurityScopedResource()
        try await AppIntentActions.open(path: url.path, page: page)
        return .result()
    }
}

struct SearchDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Document"
    static let description = IntentDescription("Finds text in a document, as the search field does, and returns each match with its page number. Without a document, searches the front document in VectorPDF.")

    @Parameter(title: "Text", requestValueDialog: "What do you want to find?")
    var query: String

    @Parameter(title: "Document", supportedContentTypes: [.pdf, .epub])
    var document: IntentFile?

    @Parameter(title: "Match Case", default: false)
    var matchCase: Bool

    @Parameter(title: "Whole Words", default: false)
    var wholeWord: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Search \(\.$document) for \(\.$query)") {
            \.$matchCase
            \.$wholeWord
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let path = try filePath(of: document) ?? AppIntentActions.frontDocumentPath()
        let found = try await AppIntentActions.search(path: path, query: query, matchCase: matchCase, wholeWord: wholeWord)
        let name = FileManager.default.displayName(atPath: path)
        let dialog: IntentDialog
        switch found.total {
        case 0: dialog = "No matches for “\(query)” in \(name)."
        case 1: dialog = "Found 1 match for “\(query)” in \(name), on page \(found.hits[0].pageNumber)."
        default:
            let shown = found.total > found.hits.count ? " The first \(found.hits.count) are listed." : ""
            dialog = "Found \(found.total) matches for “\(query)” in \(name).\(shown)"
        }
        return .result(value: found.hits.map(\.summary), dialog: dialog)
    }
}

struct AskAboutDocumentIntent: AppIntent {
    static let title: LocalizedStringResource = "Ask About Document"
    static let description = IntentDescription("Asks the Agent a question about a document and returns its answer, with page citations. The question and answer also appear in the document's Agent tab. Without a document, asks about the front document in VectorPDF.")

    @Parameter(title: "Question", requestValueDialog: "What do you want to know?")
    var question: String

    @Parameter(title: "Document", supportedContentTypes: [.pdf, .epub])
    var document: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$question) about \(\.$document)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let path = try filePath(of: document) ?? AppIntentActions.frontDocumentPath()
        let answer = try await AppIntentActions.ask(path: path, question: question)
        return .result(value: answer.text, dialog: "\(answer.text)")
    }
}

struct ExtractPagesIntent: AppIntent {
    static let title: LocalizedStringResource = "Extract Pages"
    static let description = IntentDescription("Makes a new PDF from some of a PDF's pages, such as 1-3, 5. The document isn't changed. Without a document, uses the front document in VectorPDF as last saved.")

    @Parameter(title: "Pages", description: "Page numbers and ranges, such as 1-3, 5. A range like 5- goes to the last page.", requestValueDialog: "Which pages?")
    var pages: String

    @Parameter(title: "Document", supportedContentTypes: [.pdf])
    var document: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Extract pages \(\.$pages) from \(\.$document)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let path = try filePath(of: document) ?? AppIntentActions.frontDocumentPath()
        let url = try await AppIntentActions.extractPages(path: path, ranges: pages)
        return .result(value: IntentFile(fileURL: url, filename: url.lastPathComponent, type: .pdf))
    }
}

struct VectorPDFShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: AskAboutDocumentIntent(),
            phrases: [
                "Ask \(.applicationName) about this document",
                "Ask \(.applicationName) a question",
            ],
            shortTitle: "Ask About Document",
            systemImageName: "sparkles"
        )
        AppShortcut(
            intent: SearchDocumentIntent(),
            phrases: [
                "Search this document in \(.applicationName)",
                "Find text in \(.applicationName)",
            ],
            shortTitle: "Search Document",
            systemImageName: "magnifyingglass"
        )
        AppShortcut(
            intent: ExtractPagesIntent(),
            phrases: [
                "Extract pages in \(.applicationName)",
            ],
            shortTitle: "Extract Pages",
            systemImageName: "doc.on.doc"
        )
        AppShortcut(
            intent: OpenDocumentIntent(),
            phrases: [
                "Open a document in \(.applicationName)",
            ],
            shortTitle: "Open Document",
            systemImageName: "doc.richtext"
        )
    }
}
