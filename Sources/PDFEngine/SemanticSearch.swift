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
import NaturalLanguage
import CryptoKit

/// A chunk of document text associated with a page.
public struct SemanticChunk: Sendable, Codable, Equatable {
    public let pageIndex: Int
    public let text: String
}

/// A text chunk paired with its embedding vector.
public struct EmbeddedChunk: Sendable, Codable, Equatable {
    public let chunk: SemanticChunk
    public let vector: [Float]
}

/// A document's full semantic index.
public struct DocumentSemanticIndex: Sendable, Codable, Equatable {
    /// Current format version for cached semantic indices.
    public static let currentFormatVersion = 5
    public var formatVersion: Int = DocumentSemanticIndex.currentFormatVersion
    public let sourcePath: String
    public let sourceModifiedAt: Date
    public var chunks: [EmbeddedChunk]
}


/// Splits a page's extracted text into bounded chunks with overlap across boundaries.
func chunkPageText(_ rawText: String, pageIndex: Int, maxChunkChars: Int = 1500, overlapChars: Int = 200) -> [SemanticChunk] {
    let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard text.count >= 20 else { return [] }
    if text.count <= maxChunkChars {
        return [SemanticChunk(pageIndex: pageIndex, text: text)]
    }

    var chunks: [String] = []
    var current = ""
    for rawParagraph in text.components(separatedBy: "\n\n") {
        let paragraph = rawParagraph.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !paragraph.isEmpty else { continue }

        if paragraph.count > maxChunkChars {
            // Split oversized paragraph with stride overlap.
            if !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            var remaining = Substring(paragraph)
            let stride = max(maxChunkChars - overlapChars, maxChunkChars / 2)
            while remaining.count > maxChunkChars {
                let sliceEnd = remaining.index(remaining.startIndex, offsetBy: maxChunkChars)
                chunks.append(String(remaining[remaining.startIndex..<sliceEnd]))
                let advance = remaining.index(remaining.startIndex, offsetBy: stride)
                remaining = remaining[advance...]
            }
            if !remaining.isEmpty {
                current = String(remaining)
            }
            continue
        }

        if !current.isEmpty && current.count + paragraph.count + 2 > maxChunkChars {
            chunks.append(current)
            let overlap = String(current.suffix(overlapChars))
            current = overlap.isEmpty ? paragraph : overlap + "\n\n" + paragraph
        } else {
            current = current.isEmpty ? paragraph : current + "\n\n" + paragraph
        }
    }
    if !current.isEmpty {
        chunks.append(current)
    }
    return chunks.map { SemanticChunk(pageIndex: pageIndex, text: $0) }
}

/// Words a lexical-match comparison ignores — common enough to appear in almost any passage
/// regardless of topic, so they'd otherwise dilute the signal from the terms that actually matter.
private let lexicalStopwords: Set<String> = [
    "the", "a", "an", "of", "to", "in", "on", "for", "and", "or", "is", "are", "was", "were",
    "what", "how", "does", "do", "did", "this", "that", "these", "those", "with", "by", "as",
    "at", "from", "be", "it", "its", "which", "when", "where", "who", "whom", "why", "can",
    "could", "should", "would", "will", "shall", "about", "into", "than", "then",
]

/// Fraction of query terms present in candidate text.
func lexicalOverlapScore(query: String, text: String) -> Float {
    let queryWords = Set(
        query.lowercased()
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !lexicalStopwords.contains($0) }
    )
    guard !queryWords.isEmpty else { return 0 }
    let lowerText = text.lowercased()
    let matched = queryWords.filter { lowerText.contains($0) }.count
    return Float(matched) / Float(queryWords.count)
}

/// Leading question phrases stripped when extracting subject terms.
private let questionLeadIns: [String] = [
    "what is the", "what is a", "what is an", "what's the", "what's a", "what's an",
    "tell me about the", "tell me about", "what are the", "define the", "explain the",
    "describe the", "what is", "what's", "what are", "define", "explain", "describe",
]

/// Strips leading question phrasing and trailing punctuation to isolate the subject phrase.
func extractSubjectPhrase(from question: String) -> String? {
    var q = question.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = q.lowercased()
    if let leadIn = questionLeadIns.first(where: { lower.hasPrefix($0) }) {
        q = String(q.dropFirst(leadIn.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    while let last = q.last, ".?!".contains(last) {
        q.removeLast()
    }
    return q.count >= 3 ? q : nil
}

/// Lowercases and collapses whitespace runs to a single space.
private func normalizedForPhraseMatch(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

/// Connectors following a term that indicate a definition rather than passing mention.
private let definitionConnectors: [String] = [
    "field indicates", "indicates", "is defined as", "is a unique", "is a", "refers to", "means",
    "specifies", "denotes", "represents", "is used to", "field is",
]

/// Whether `text` contains `subjectPhrase` followed by a definition connector.
private func definitionPatternScore(subjectPhrase: String, text: String) -> Float {
    let normalizedText = normalizedForPhraseMatch(text)
    guard let range = normalizedText.range(of: normalizedForPhraseMatch(subjectPhrase)) else { return 0 }
    let after = normalizedText[range.upperBound...].trimmingCharacters(in: .whitespaces)
    return definitionConnectors.contains { after.hasPrefix($0) } ? 1.0 : 0.0
}

/// Combines word overlap, exact-phrase containment, and definition pattern matching.
func lexicalRelevanceScore(query: String, text: String) -> Float {
    let wordScore = lexicalOverlapScore(query: query, text: text)
    guard let phrase = extractSubjectPhrase(from: query) else { return wordScore }
    let phraseScore: Float = normalizedForPhraseMatch(text).contains(normalizedForPhraseMatch(phrase)) ? 1.0 : 0.0
    let definitionScore = definitionPatternScore(subjectPhrase: phrase, text: text)
    return 0.25 * wordScore + 0.35 * phraseScore + 0.4 * definitionScore
}

/// Blends embedding similarity with lexical relevance scoring.
func hybridRelevanceScore(embeddingScore: Float, lexicalScore: Float) -> Float {
    0.7 * embeddingScore + 0.3 * lexicalScore
}

/// Cosine similarity between two equal-length vectors; -1 (the lowest possible score) for any
/// mismatched-length or zero-magnitude input, so a bad comparison always sorts last rather than
/// crashing or silently scoring as a match.
func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
    guard a.count == b.count, !a.isEmpty else { return -1 }
    var dot: Float = 0, normA: Float = 0, normB: Float = 0
    for i in 0..<a.count {
        dot += a[i] * b[i]
        normA += a[i] * a[i]
        normB += b[i] * b[i]
    }
    guard normA > 0, normB > 0 else { return -1 }
    return dot / (sqrt(normA) * sqrt(normB))
}

/// Embeds text on-device using the Natural Language framework, with contextual embedding and word-vector fallback.
actor TextEmbedder {
    private enum Backend {
        case contextual(NLContextualEmbedding)
        case wordAverage(NLEmbedding)
    }

    private var backend: Backend?
    private var resolved = false

    private func resolveBackend() -> Backend? {
        if resolved { return backend }
        resolved = true
        if let contextual = NLContextualEmbedding(language: .english), contextual.hasAvailableAssets {
            do {
                try contextual.load()
                backend = .contextual(contextual)
                return backend
            } catch {
                // Fallback to word-vector backend.
            }
        }
        if let wordEmbedding = NLEmbedding.wordEmbedding(for: .english) {
            backend = .wordAverage(wordEmbedding)
            return backend
        }
        backend = nil
        return nil
    }

    /// Determines whether an embedding backend is available.
    func isAvailable() -> Bool {
        resolveBackend() != nil
    }

    func embed(_ text: String) -> [Float]? {
        guard !text.isEmpty, let backend = resolveBackend() else { return nil }
        switch backend {
        case .contextual(let model):
            return embedContextual(text, using: model)
        case .wordAverage(let model):
            return embedWordAverage(text, using: model)
        }
    }

    private func embedContextual(_ text: String, using model: NLContextualEmbedding) -> [Float]? {
        guard let result = try? model.embeddingResult(for: text, language: .english) else { return nil }
        var sum: [Double]?
        var count = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            if sum == nil {
                sum = vector
            } else {
                for i in 0..<vector.count { sum![i] += vector[i] }
            }
            count += 1
            return true
        }
        guard let sum, count > 0 else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }

    private func embedWordAverage(_ text: String, using model: NLEmbedding) -> [Float]? {
        var sum = [Double](repeating: 0, count: model.dimension)
        var count = 0
        text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: [.byWords, .localized]) { word, _, _, _ in
            guard let word, let vector = model.vector(for: word.lowercased()) else { return }
            for i in 0..<vector.count { sum[i] += vector[i] }
            count += 1
        }
        guard count > 0 else { return nil }
        return sum.map { Float($0 / Double(count)) }
    }
}

/// Disk-backed cache for semantic indexes stored as JSON files under Application Support.
actor SemanticIndexStore {
    static let shared = SemanticIndexStore()

    private let directory: URL

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = base.appendingPathComponent("VectorPDF/SemanticIndex", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for path: String) -> URL {
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("\(digest).json")
    }

    /// Returns the cached index for `path`, or nil if missing or invalid.
    func load(for path: String) -> DocumentSemanticIndex? {
        let url = fileURL(for: path)
        guard let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(DocumentSemanticIndex.self, from: data),
              index.sourcePath == path,
              index.formatVersion == DocumentSemanticIndex.currentFormatVersion else {
            return nil
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let modDate = attrs[.modificationDate] as? Date,
           abs(modDate.timeIntervalSince(index.sourceModifiedAt)) > 1 {
            return nil
        }
        return index
    }

    /// Deletes the cached index for `path`, if any.
    func remove(for path: String) {
        try? FileManager.default.removeItem(at: fileURL(for: path))
    }

    func save(_ index: DocumentSemanticIndex) {
        let url = fileURL(for: index.sourcePath)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
