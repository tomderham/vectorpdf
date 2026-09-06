// Standalone feasibility check for VectorPDF's on-device Agent features.
// Run with: swift agent_feasibility_check.swift
import FoundationModels
import NaturalLanguage
import Foundation

print("=== 1. FoundationModels (on-device LLM synthesis) ===")
let model = SystemLanguageModel.default
print("Reported availability: \(model.availability)")

let sample = "VectorPDF is a macOS PDF reader built on MuPDF. It supports tabs, favorites, and dark mode."
do {
    let session = LanguageModelSession()
    let response = try await session.respond(to: "In one sentence, summarize: \(sample)")
    print("PASS: got a live response:")
    print(response.content)
} catch {
    print("FAIL: generation request failed:")
    print(error)
}

print("")
print("=== 2. NLContextualEmbedding (on-device semantic retrieval) ===")
if let embModel = NLContextualEmbedding(language: .english) {
    print("hasAvailableAssets: \(embModel.hasAvailableAssets)")
    do {
        try embModel.load()
        let result = try embModel.embeddingResult(for: sample, language: .english)
        var dim = 0
        result.enumerateTokenVectors(in: sample.startIndex..<sample.endIndex) { vector, _ in
            dim = vector.count
            return false
        }
        print("PASS: loaded and embedded, dimension \(dim)")
    } catch {
        print("FAIL: \(error)")
    }
} else {
    print("FAIL: could not construct NLContextualEmbedding")
}

print("")
print("=== 3. NLEmbedding word vectors (fallback, should always pass) ===")
if let wordEmb = NLEmbedding.wordEmbedding(for: .english) {
    print("PASS: word embedding available, dimension \(wordEmb.dimension)")
} else {
    print("FAIL: NLEmbedding.wordEmbedding returned nil")
}
