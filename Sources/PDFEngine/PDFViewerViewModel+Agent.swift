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

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import ObjectiveC

extension PDFViewerViewModel {
    // MARK: - Agent Tab

    /// True when on-device answer synthesis (not just passage retrieval) can be attempted on this
    /// Mac — used by the UI to set expectations before a query is even run (e.g. "showing matching
    /// passages only" vs. an actual generated answer).
    public func isAgentSynthesisAvailable() -> Bool {
        agentConversationEngine.isSynthesisAvailable()
    }

    /// Invalidates the semantic index and cancels any in-flight indexing tasks.
    func invalidateAgentIndex(deleteCache: Bool) {
        agentIndexingTask?.cancel()
        agentIndexingTask = nil
        agentIndexBuilder = nil
        agentChunks = []
        if agentIndexState != .idle {
            agentIndexState = .idle
        }
        if deleteCache, let path = document?.filePath {
            Task { await SemanticIndexStore.shared.remove(for: path) }
        }
    }

    /// Builds or loads from disk the semantic index for the current document if not already loaded.
    public func startAgentIndexingIfNeeded() {
        guard let doc = document, agentIndexState == .idle else { return }
        // Unsaved page edits or redactions live in the working copy; index that, not the file.
        let indexesWorkingCopy = workingCopyPath != nil
        let path = workingCopyPath ?? doc.filePath
        let password = currentDocumentPassword
        // The cache is plain JSON in Application Support: never write (or trust) one for a
        // password-protected document or a temporary working copy.
        let usesCache = password == nil && !indexesWorkingCopy

        agentIndexingTask?.cancel()
        agentIndexingTask = Task { [weak self] in
            guard let self else { return }

            // Guard resumptions so a cancelled task does not write stale index state.
            if password != nil {
                await SemanticIndexStore.shared.remove(for: path)
            }
            let cached = usesCache ? await SemanticIndexStore.shared.load(for: path) : nil
            guard !Task.isCancelled else { return }
            if let cached {
                self.agentChunks = cached.chunks
                self.agentIndexState = .ready
                return
            }

            let embedderAvailable = await self.agentEmbedder.isAvailable()
            guard !Task.isCancelled else { return }
            guard embedderAvailable else {
                self.agentIndexState = .unavailable("Semantic search isn't available on this Mac.")
                return
            }

            self.agentIndexState = .building(pagesDone: 0, totalPages: doc.pageCount)
            let builder = SemanticIndexBuilder()
            self.agentIndexBuilder = builder
            do {
                try await builder.openDocument(filePath: path, password: password)
            } catch {
                guard !Task.isCancelled else { return }
                self.agentIndexState = .unavailable("Couldn't open the document for indexing.")
                self.agentIndexBuilder = nil
                return
            }
            guard !Task.isCancelled else { return }

            let totalPages = await builder.pageCount()
            guard !Task.isCancelled else { return }
            var chunks: [EmbeddedChunk] = []
            var pagesDone = 0
            for await (pageIndex, text) in await builder.extractPageTexts() {
                if Task.isCancelled { return }
                for chunk in chunkPageText(text, pageIndex: pageIndex) {
                    if let vector = await self.agentEmbedder.embed(chunk.text) {
                        chunks.append(EmbeddedChunk(chunk: chunk, vector: vector))
                    }
                }
                pagesDone += 1
                // Updating on every page would mean thousands of @Published writes for a long
                // document; every 10 pages keeps the progress bar smooth without that overhead.
                if pagesDone % 10 == 0 || pagesDone == totalPages {
                    self.agentIndexState = .building(pagesDone: pagesDone, totalPages: totalPages)
                }
            }
            guard !Task.isCancelled else { return }

            self.agentIndexBuilder = nil
            guard !chunks.isEmpty else {
                self.agentIndexState = .unavailable("This document has no text the Agent can search.")
                return
            }
            self.agentChunks = chunks
            self.agentIndexState = .ready

            guard usesCache else { return }
            let attrs = try? FileManager.default.attributesOfItem(atPath: path)
            let modDate = (attrs?[.modificationDate] as? Date) ?? Date()
            await SemanticIndexStore.shared.save(
                DocumentSemanticIndex(sourcePath: path, sourceModifiedAt: modDate, chunks: chunks)
            )
        }
    }

    /// Resets an `.unavailable` index state and tries again — surfaced as a "Retry" button, since
    /// a transient failure (e.g. a document that failed to open for indexing) shouldn't need a
    /// document switch to recover from.
    public func retryAgentIndexing() {
        agentIndexState = .idle
        startAgentIndexingIfNeeded()
    }

    /// Clears the visible conversation and resets the conversation session.
    public func startNewAgentConversation() {
        agentConversation = []
        agentConversationEngine.reset()
    }

    /// Runs `agentQuestion` against the semantic index, appending a new turn to `agentConversation`.
    public func askAgentQuestion() {
        let question = agentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, agentIndexState == .ready, !agentChunks.isEmpty else { return }

        agentQuestion = ""
        agentIsAnswering = true
        // Capture previous question for follow-up query folding.
        let previousQuestion = agentConversation.last?.question
        let turnId = UUID()
        agentConversation.append(AgentTurn(id: turnId, question: question, isStreaming: true))

        let chunksSnapshot = agentChunks
        Task { [weak self] in
            guard let self else { return }
            let activeProvider = self.agentConversationEngine.activeSynthesisProvider()

            // For small documents under context limits, pass full document prose directly.
            let totalDocChars = chunksSnapshot.reduce(0) { $0 + $1.chunk.text.count }
            let estimatedTokens = totalDocChars / 4
            let isFullDocEligible = activeProvider == .privateCloudCompute && estimatedTokens <= DocumentAgentConversation.fullDocumentTokenThreshold

            let passages: [AgentPassage]
            let isFullDoc: Bool

            if isFullDocEligible {
                var pageMap: [Int: [String]] = [:]
                for c in chunksSnapshot {
                    pageMap[c.chunk.pageIndex, default: []].append(c.chunk.text)
                }
                let sortedPages = pageMap.keys.sorted()
                passages = sortedPages.map { pageIdx in
                    AgentPassage(pageIndex: pageIdx, text: pageMap[pageIdx]!.joined(separator: "\n\n"), score: 1.0)
                }
                isFullDoc = true
            } else {
                // Fold previous question into query for anaphoric follow-ups.
                let retrievalQuery: String
                if let prev = previousQuestion, self.shouldFoldPreviousQuestion(question) {
                    retrievalQuery = "\(prev)\n\(question)"
                } else {
                    retrievalQuery = question
                }
                guard let queryVector = await self.agentEmbedder.embed(retrievalQuery) else {
                    self.finishAgentTurn(id: turnId, text: "", errorMessage: "Couldn't process this question.")
                    return
                }

                // Hybrid retrieval combining embedding similarity and lexical relevance.
                let embeddingScores = chunksSnapshot.map { cosineSimilarity(queryVector, $0.vector) }
                let lexicalScores = chunksSnapshot.map { lexicalRelevanceScore(query: question, text: $0.chunk.text) }

                let pools = self.agentConversationEngine.recommendedCandidatePoolSizes()
                let topByEmbedding = chunksSnapshot.indices.sorted { embeddingScores[$0] > embeddingScores[$1] }.prefix(pools.embedding)
                let topByLexical = chunksSnapshot.indices
                    .filter { lexicalScores[$0] > 0 }
                    .sorted { lexicalScores[$0] > lexicalScores[$1] }
                    .prefix(pools.lexical)
                let candidateIndices = Set(topByEmbedding).union(topByLexical)
                let passageBudget = self.agentConversationEngine.recommendedPassageCount(onDeviceDefault: Self.maxPassagesForSynthesis)
                let ranked = candidateIndices
                    .map { i in (embedded: chunksSnapshot[i], score: hybridRelevanceScore(embeddingScore: embeddingScores[i], lexicalScore: lexicalScores[i])) }
                    .sorted { $0.score > $1.score }
                    .prefix(passageBudget)

                // Passages retain their full, natural chunk content with zero truncation
                passages = ranked.map { item in
                    AgentPassage(pageIndex: item.embedded.chunk.pageIndex, text: item.embedded.chunk.text, score: item.score)
                }
                isFullDoc = false
            }

            let initialProvider = self.agentConversationEngine.activeSynthesisProvider()
            self.updateAgentTurn(id: turnId) {
                $0.passages = passages
                $0.providerUsed = initialProvider
            }
            // Without on-device generation the passages are the answer — not an error.
            guard initialProvider != nil else {
                self.finishAgentTurn(id: turnId, text: "")
                return
            }

            let result = await self.agentConversationEngine.streamAnswer(
                question: question,
                passages: passages,
                isFullDocument: isFullDoc
            ) { [weak self] partial in
                self?.updateAgentTurn(id: turnId) { $0.answerText = partial }
            }
            self.finishAgentTurn(
                id: turnId,
                text: result.text ?? "",
                provider: result.providerUsed,
                statusNote: result.statusNote,
                errorMessage: result.errorMessage
            )
        }
    }

    /// Determines whether the question is an anaphoric follow-up referring to previous context.
    public func shouldFoldPreviousQuestion(_ question: String) -> Bool {
        let q = question.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.count <= 4 { return true }
        let followUpTriggers: Set<String> = [
            "it", "this", "that", "these", "those", "they", "them", "he", "she",
            "more", "why", "how", "details", "explain", "elaborate", "again", "also"
        ]
        return words.contains(where: { followUpTriggers.contains($0) })
    }

    private func updateAgentTurn(id: UUID, _ mutate: (inout AgentTurn) -> Void) {
        guard let index = agentConversation.firstIndex(where: { $0.id == id }) else { return }
        mutate(&agentConversation[index])
    }

    private func finishAgentTurn(
        id: UUID,
        text: String,
        provider: AgentSynthesisProvider? = nil,
        statusNote: String? = nil,
        errorMessage: String? = nil
    ) {
        updateAgentTurn(id: id) {
            $0.answerText = text
            $0.isStreaming = false
            if let provider {
                $0.providerUsed = provider
            }
            $0.statusNote = statusNote
            $0.errorMessage = errorMessage
        }
        agentIsAnswering = false
    }
}
