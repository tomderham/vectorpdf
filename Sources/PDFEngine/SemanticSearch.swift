import Foundation
import NaturalLanguage
import CryptoKit

/// One chunk of a document's text, tagged with the page it came from — page-level (or, for very
/// long pages, a fragment of a page) is the smallest unit the Agent tab ever cites or jumps to.
public struct SemanticChunk: Sendable, Codable, Equatable {
    public let pageIndex: Int
    public let text: String
}

/// A chunk plus its embedding vector. `vector`'s length depends on which backend produced it
/// (512 for NLContextualEmbedding, 300 for the NLEmbedding word-average fallback — see
/// TextEmbedder) — never mixed within a single index, since a query embedded with one backend
/// isn't comparable to vectors from the other.
public struct EmbeddedChunk: Sendable, Codable, Equatable {
    public let chunk: SemanticChunk
    public let vector: [Float]
}

/// One document's full semantic index. Persisted to disk (see SemanticIndexStore) so that a
/// several-thousand-page document only has to be chunked and embedded once, not every time the
/// Agent tab is opened.
public struct DocumentSemanticIndex: Sendable, Codable, Equatable {
    /// Current format version for cached semantic indices.
    public static let currentFormatVersion = 5
    public var formatVersion: Int = DocumentSemanticIndex.currentFormatVersion
    public let sourcePath: String
    public let sourceModifiedAt: Date
    public var chunks: [EmbeddedChunk]
}


/// Splits one page's raw extracted text into chunks no longer than `maxChunkChars`, preferring to
/// break on paragraph boundaries, with a little overlap carried across chunk boundaries so a fact
/// sitting right at the boundary still appears whole in at least one chunk instead of being split
/// across two chunks that each retrieve poorly on their own. Most pages of most documents are
/// short enough to stay a single chunk; this only matters for unusually dense pages. Pages with
/// next to no text (blank pages, bare headers/footers) are dropped entirely rather than indexed as
/// noise.
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
            // A single paragraph longer than the whole chunk budget (rare, but happens with
            // reference lists / dense tables extracted as one run) — flush what's pending, then
            // hard-split the oversized paragraph itself, with a bit of stride overlap between the
            // resulting pieces.
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

        if current.count + paragraph.count + 2 > maxChunkChars {
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

/// Cheap lexical signal to complement embedding similarity: the fraction of the query's
/// significant words that also appear in the candidate text. Catches exact technical terms,
/// acronyms, and identifiers that a general-purpose embedding model can underweight in favor of
/// looser topical similarity. Word presence only, not adjacency — a chunk mentioning two of a
/// query's words in unrelated sentences scores identically to one that actually defines them
/// together as a term; see lexicalRelevanceScore below for the adjacency-aware score used for
/// ranking.
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

/// Leading question phrasing stripped off by extractSubjectPhrase below, longest first so e.g.
/// "what is the" matches before the shorter "what is" prefix it contains.
private let questionLeadIns: [String] = [
    "what is the", "what is a", "what is an", "what's the", "what's a", "what's an",
    "tell me about the", "tell me about", "what are the", "define the", "explain the",
    "describe the", "what is", "what's", "what are", "define", "explain", "describe",
]

/// Strips a leading question phrase and trailing punctuation from a natural-language question,
/// leaving the residual subject (e.g. "What is a Widget ID?" -> "Widget ID") — the term a
/// definition-style question is actually asking about. Returns nil if nothing substantial is left
/// (e.g. the question wasn't phrased this way at all).
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

/// Lowercases and collapses any run of whitespace (including line breaks) to a single space —
/// extracted PDF text preserves the source's literal line-wrapping, so a multi-word phrase can come
/// through with a line break in the middle of it if it happened to wrap there, which would
/// otherwise silently defeat a plain substring match.
private func normalizedForPhraseMatch(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
}

/// Connector words that typically follow a term immediately after its own name when a sentence is
/// actually defining it, rather than just using it in passing (e.g. "the Widget ID field
/// indicates...", "X is defined as...", "X refers to..."). A term can appear as an exact phrase in
/// many more places throughout a technical document than the one place that actually defines it —
/// this distinguishes "defines X" from "mentions X".
private let definitionConnectors: [String] = [
    "field indicates", "indicates", "is defined as", "is a unique", "is a", "refers to", "means",
    "specifies", "denotes", "represents", "is used to", "field is",
]

/// Whether `text` contains `subjectPhrase` immediately followed by one of definitionConnectors
/// above — i.e. whether this reads like an actual definition of the term, not just a mention.
private func definitionPatternScore(subjectPhrase: String, text: String) -> Float {
    let normalizedText = normalizedForPhraseMatch(text)
    guard let range = normalizedText.range(of: normalizedForPhraseMatch(subjectPhrase)) else { return 0 }
    let after = normalizedText[range.upperBound...].trimmingCharacters(in: .whitespaces)
    return definitionConnectors.contains { after.hasPrefix($0) } ? 1.0 : 0.0
}

/// Combines plain word overlap, exact-phrase containment, and the definition-pattern check above:
/// extracts the subject of a definition-style question (see extractSubjectPhrase), then checks
/// whether the candidate text contains that phrase verbatim and, further, actually defines it
/// there rather than just mentioning it. Weighted in three tiers — a genuine definition clearly
/// outranks a chunk that just uses the same phrase, which in turn outranks one that only contains
/// the same words scattered separately — since lexicalOverlapScore alone can't distinguish any of
/// these, only checking word presence.
func lexicalRelevanceScore(query: String, text: String) -> Float {
    let wordScore = lexicalOverlapScore(query: query, text: text)
    guard let phrase = extractSubjectPhrase(from: query) else { return wordScore }
    let phraseScore: Float = normalizedForPhraseMatch(text).contains(normalizedForPhraseMatch(phrase)) ? 1.0 : 0.0
    let definitionScore = definitionPatternScore(subjectPhrase: phrase, text: text)
    return 0.25 * wordScore + 0.35 * phraseScore + 0.4 * definitionScore
}

/// Blends embedding similarity with the lexical relevance score above — a lightweight stand-in for
/// the two-stage "wide embedding search, then rerank" pattern real RAG systems use, without a real
/// reranker model. Weighted so embedding similarity (the more reliable general signal) still
/// dominates, while exact-term matches get a meaningful boost.
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

/// Embeds text on-device via the Natural Language framework — deliberately independent of
/// FoundationModels/Apple Intelligence, since this is the retrieval half of the Agent tab and
/// needs to keep working even where on-device generation is disabled (e.g. many managed corporate
/// Macs). Prefers NLContextualEmbedding (sentence-level, higher quality); falls back to averaging
/// NLEmbedding word vectors if the contextual model's assets aren't available on this machine.
/// See Resources/test-files/agent_feasibility_check.swift for a standalone check of which backend
/// is actually available on a given machine.
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
                // Falls through to the word-vector backend below.
            }
        }
        if let wordEmbedding = NLEmbedding.wordEmbedding(for: .english) {
            backend = .wordAverage(wordEmbedding)
            return backend
        }
        backend = nil
        return nil
    }

    /// Resolves (once) whether any embedding backend works on this machine at all — callers use
    /// this to decide whether the Agent tab's retrieval feature is offered in the first place.
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

/// Disk-backed cache for semantic indexes, one JSON file per document under Application Support,
/// keyed by a hash of its path. Unlike Favorites/TabGroups/ReadingState — small enough for a
/// single UserDefaults blob — a semantic index for a several-thousand-page document can run into
/// tens of megabytes, which UserDefaults/plist storage handles poorly; a dedicated file per
/// document is the right fit here.
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

    /// Returns the cached index for `path`, or nil if missing, stale based on file modification
    /// date, or format version mismatch.
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

    func save(_ index: DocumentSemanticIndex) {
        let url = fileURL(for: index.sourcePath)
        guard let data = try? JSONEncoder().encode(index) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
