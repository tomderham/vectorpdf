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

import AppKit
import Foundation

/// What the Shortcuts actions (App Intents, in the VectorPDF target) do. The intents only turn
/// their parameters into these calls, so the work can be tested without the App Intents runtime.
@MainActor
public enum AppIntentActions {
    public enum Failure: LocalizedError, Equatable {
        case noOpenDocument
        case fileNotFound(String)
        case couldNotOpen(String)
        case passwordProtected(String)
        case pageOutOfRange(page: Int, pageCount: Int)
        case invalidPageRange(String)
        case notAPDF(String)
        case agentTurnedOff
        case agentUnavailable(String)
        case agentFailed(String)

        public var errorDescription: String? {
            switch self {
            case .noOpenDocument:
                return "No document is open in VectorPDF. Choose a document."
            case .fileNotFound(let name):
                return "Couldn't find “\(name)”."
            case .couldNotOpen(let name):
                return "Couldn't open “\(name)”."
            case .passwordProtected(let name):
                return "“\(name)” is password-protected. Open it in VectorPDF and enter the password first."
            case .pageOutOfRange(let page, let pageCount):
                return "There's no page \(page): the document has \(pageCount) page\(pageCount == 1 ? "" : "s")."
            case .invalidPageRange(let text):
                return "“\(text)” isn't a list of pages. Use page numbers and ranges, such as 1-3, 5."
            case .notAPDF(let name):
                return "“\(name)” isn't a PDF. Pages can only be extracted from PDFs."
            case .agentTurnedOff:
                return "The Agent is turned off. Turn on Use Agent in VectorPDF Settings."
            case .agentUnavailable(let reason):
                return reason
            case .agentFailed(let reason):
                return reason
            }
        }
    }

    /// One search match, for the Search Document action.
    public struct SearchHit: Sendable, Equatable {
        /// 1-based, as the page numbers people see.
        public let pageNumber: Int
        public let snippet: String

        public var summary: String { "Page \(pageNumber): \(snippet)" }
    }

    /// The Agent's answer, for the Ask About Document action.
    public struct AgentAnswer: Sendable, Equatable {
        public let text: String
        /// 1-based pages of the passages it used, in order.
        public let pageNumbers: [Int]
    }

    private static var coordinator: PDFViewerAppCoordinator { .shared }

    /// The file in the front document tab, when the action wasn't given one.
    public static func frontDocumentPath() throws -> String {
        guard let path = coordinator.activeViewModel?.document?.filePath else { throw Failure.noOpenDocument }
        return path
    }

    private static func displayName(_ path: String) -> String {
        FileManager.default.displayName(atPath: path)
    }

    private static func requireFile(_ path: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw Failure.fileNotFound(displayName(path))
        }
    }

    // MARK: - Open

    /// Shows `path` in its tab (opening one if no tab has it) and, with `page` (1-based), goes there.
    public static func open(path: String, page: Int? = nil) async throws {
        try requireFile(path)
        guard let viewModel = await coordinator.showDocument(atPath: path, inBackground: false) else {
            throw Failure.couldNotOpen(displayName(path))
        }
        NSApp.activate(ignoringOtherApps: true)
        guard let page else { return }
        let pageCount = viewModel.document?.pageCount ?? 0
        guard (1...max(pageCount, 1)).contains(page), pageCount > 0 else {
            throw Failure.pageOutOfRange(page: page, pageCount: pageCount)
        }
        viewModel.jumpToPage(page - 1)
    }

    // MARK: - Search

    /// Searches `path` as the search field does (Smart Search, with the ignored patterns from
    /// Settings), without opening a window. A document open in a tab is searched as it is there:
    /// with its unsaved edits, password and hidden layers.
    public static func search(
        path: String,
        query: String,
        matchCase: Bool = false,
        wholeWord: Bool = false,
        limit: Int = 100
    ) async throws -> (hits: [SearchHit], total: Int) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ([], 0) }
        try requireFile(path)

        let actor = PDFSearchActor()
        let open = coordinator.viewModel(showingFileAt: path)
        do {
            if let open, let doc = open.document {
                try await actor.openDocument(filePath: open.workingCopyPath ?? doc.filePath, password: open.currentDocumentPassword)
                await actor.setLayerStates(doc.layerStates())
            } else {
                try await actor.openDocument(filePath: path)
            }
        } catch PDFError.passwordRequired, PDFError.incorrectPassword {
            throw Failure.passwordProtected(displayName(path))
        } catch {
            throw Failure.couldNotOpen(displayName(path))
        }
        let options = SearchOptions(
            matchCase: matchCase,
            wholeWord: wholeWord,
            ignoredPatterns: coordinator.enabledIgnoredSearchPatterns
        )
        let results = try await actor.search(query: trimmed, options: options)
        let hits = results.prefix(max(0, limit)).map {
            SearchHit(pageNumber: $0.pageIndex + 1, snippet: Self.oneLine($0.snippet))
        }
        return (Array(hits), results.count)
    }

    private static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    // MARK: - Ask the Agent

    /// Asks the Agent about `path` in its tab (opening one behind the front window if no tab has
    /// it), so the question and answer also appear in the Agent tab's conversation.
    public static func ask(path: String, question: String) async throws -> AgentAnswer {
        guard coordinator.showAgentTab else { throw Failure.agentTurnedOff }
        try requireFile(path)
        guard let viewModel = await coordinator.showDocument(atPath: path, inBackground: true) else {
            throw Failure.couldNotOpen(displayName(path))
        }
        let turn = try await viewModel.answerAgentQuestion(question)
        let pages = turn.passages.map { $0.pageIndex + 1 }
        let answer = turn.answerText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !answer.isEmpty {
            return AgentAnswer(text: answer, pageNumbers: pages)
        }
        if let error = turn.errorMessage, !error.isEmpty {
            throw Failure.agentFailed(error)
        }
        // Without answer synthesis on this Mac, the passages are the answer, as in the Agent tab.
        guard !turn.passages.isEmpty else { throw Failure.agentFailed("The Agent found nothing about that in this document.") }
        let text = turn.passages
            .map { "Page \($0.pageIndex + 1): \(oneLine($0.text))" }
            .joined(separator: "\n\n")
        return AgentAnswer(text: text, pageNumbers: pages)
    }

    // MARK: - Extract pages

    /// Saves the pages `ranges` lists ("1-3, 5", 1-based, in the order given) from the PDF at
    /// `path` to a new PDF in a temporary folder, and returns its URL. Reads the file as saved.
    public nonisolated static func extractPages(path: String, ranges: String) async throws -> URL {
        let name = FileManager.default.displayName(atPath: path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw Failure.fileNotFound(name)
        }
        return try await Task.detached(priority: .userInitiated) {
            let document: PDFDocumentCore
            do {
                document = try PDFDocumentCore(filePath: path)
            } catch PDFError.passwordRequired, PDFError.incorrectPassword {
                throw Failure.passwordProtected(name)
            } catch {
                throw Failure.couldNotOpen(name)
            }
            guard document.isPDF else { throw Failure.notAPDF(name) }
            let pages = try PageRangeList.parse(ranges, pageCount: document.pageCount)
            let base = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("VectorPDF Extracted Pages", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let pageWord = pages.count == 1 ? "Page" : "Pages"
            // Not so long a name the file system refuses it (a long list of pages).
            var label = PageRangeList.describe(ranges)
            if label.utf8.count > 60 { label = String(label.prefix(57)) + "…" }
            let destination = folder.appendingPathComponent("\(base) (\(pageWord) \(label)).pdf")
            try document.extractPages(pages.map { $0 - 1 }, to: destination)
            return destination
        }.value
    }
}

/// A list of pages typed as numbers and ranges ("1-3, 5, 8–10"), 1-based.
public enum PageRangeList {
    /// The pages `text` lists, in the order given (repeats kept, as a page list for extracting
    /// means them). Throws when a part isn't a page number or range, or names a page past `pageCount`.
    public static func parse(_ text: String, pageCount: Int) throws -> [Int] {
        let parts = text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !parts.isEmpty else { throw AppIntentActions.Failure.invalidPageRange(text) }
        var pages: [Int] = []
        for part in parts {
            let bounds = part.split(whereSeparator: { $0 == "-" || $0 == "–" || $0 == "—" })
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard part.first?.isNumber == true, (1...2).contains(bounds.count), let first = Int(bounds[0]), first >= 1 else {
                throw AppIntentActions.Failure.invalidPageRange(text)
            }
            // "5-" runs to the last page.
            let endsAtLastPage = bounds.count == 1 && part.last.map { "-–—".contains($0) } == true
            let last: Int
            if bounds.count == 2 {
                guard let end = Int(bounds[1]) else { throw AppIntentActions.Failure.invalidPageRange(text) }
                last = end
            } else {
                last = endsAtLastPage ? pageCount : first
            }
            for page in [first, last] where page > pageCount {
                throw AppIntentActions.Failure.pageOutOfRange(page: page, pageCount: pageCount)
            }
            pages += first <= last ? Array(first...last) : Array((last...first).reversed())
        }
        return pages
    }

    /// `text` tidied for a file name: "1 -3,5" becomes "1-3, 5".
    public static func describe(_ text: String) -> String {
        text.split(whereSeparator: { $0 == "," || $0 == ";" })
            .map { part in
                part.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "-" || $0 == "–" || $0 == "—" })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .joined(separator: "-")
            }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

extension PDFViewerAppCoordinator {
    /// The tab showing `path`, brought to the front (behind the active app's windows when
    /// `inBackground`), or a new tab opened for it once its document has loaded. Nil when it
    /// didn't load within ten seconds.
    public func showDocument(atPath path: String, inBackground: Bool) async -> PDFViewerViewModel? {
        if let open = viewModel(showingFileAt: path) {
            if let window = open.currentWindow {
                if let group = window.tabGroup, group.selectedWindow !== window {
                    group.selectedWindow = window
                }
                if inBackground {
                    window.orderFront(nil)
                } else {
                    // Its window minimized: restored, from whichever of its tabs is minimized.
                    if let minimized = window.isMiniaturized ? window : window.tabGroup?.windows.first(where: \.isMiniaturized) {
                        minimized.deminiaturize(nil)
                    }
                    window.makeKeyAndOrderFront(nil)
                }
            }
            return open
        }
        let window = DocumentWindowing.openDocumentHandlingEmptyStart(url: URL(fileURLWithPath: path))
        if inBackground { window.orderFront(nil) }
        // Wait for the new tab's view model to load the file.
        for _ in 0..<200 {
            if let candidate = viewModel(showingFileAt: path), !candidate.isLoadingDocument {
                return candidate
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return nil
    }
}

extension PDFViewerViewModel {
    /// Asks the Agent `question` as if typed in the Agent tab, once the document is indexed, and
    /// returns the finished turn. Keeps whatever was being typed in the Agent tab's field.
    func answerAgentQuestion(_ question: String) async throws -> AgentTurn {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AppIntentActions.Failure.agentFailed("Ask a question.") }

        guard document != nil else { throw AppIntentActions.Failure.agentFailed("There's no document to ask about.") }
        startAgentIndexingIfNeeded()
        // The first is the state now: idle until the indexing just started begins.
        var isFirst = true, restarted = false
        indexing: for await state in $agentIndexState.values {
            try Task.checkCancellation()
            defer { isFirst = false }
            switch state {
            case .ready: break indexing
            case .unavailable(let reason): throw AppIntentActions.Failure.agentUnavailable(reason)
            case .building: restarted = false
            case .idle where isFirst: continue
            case .idle:
                // Indexing stopped (the document changed, say) and nothing started it again:
                // start it, once, rather than wait for nothing.
                guard document != nil, !restarted else { throw AppIntentActions.Failure.agentFailed("The document couldn't be indexed.") }
                restarted = true
                startAgentIndexingIfNeeded()
            }
        }
        // One question at a time, as in the Agent tab.
        for await answering in $agentIsAnswering.values where !answering { break }
        try Task.checkCancellation()

        let draft = agentQuestion
        let turnsBefore = agentConversation.count
        agentQuestion = trimmed
        askAgentQuestion()
        agentQuestion = draft
        guard agentConversation.count > turnsBefore, let id = agentConversation.last?.id else {
            throw AppIntentActions.Failure.agentFailed("The Agent couldn't take the question.")
        }
        for await turns in $agentConversation.values {
            try Task.checkCancellation()
            guard let turn = turns.first(where: { $0.id == id }) else {
                throw AppIntentActions.Failure.agentFailed("The conversation was cleared before the Agent answered.")
            }
            if !turn.isStreaming { return turn }
        }
        throw CancellationError()
    }
}
