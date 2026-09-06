import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One retrieved passage, ready to show in the Agent tab's results list and to jump to on tap.
public struct AgentPassage: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let pageIndex: Int
    public let text: String
    public let score: Float
}

/// Backend provider that produced or would produce an Agent turn's answer.
public enum AgentSynthesisProvider: Sendable, Equatable {
    case onDevice
    case privateCloudCompute
}

/// One question/answer exchange in the Agent conversation.
public struct AgentTurn: Sendable, Identifiable, Equatable {
    public let id: UUID
    public let question: String
    public var passages: [AgentPassage]
    public var answerText: String
    public var isStreaming: Bool
    public var providerUsed: AgentSynthesisProvider?

    public init(id: UUID = UUID(), question: String, passages: [AgentPassage] = [], answerText: String = "", isStreaming: Bool = false, providerUsed: AgentSynthesisProvider? = nil) {
        self.id = id
        self.question = question
        self.passages = passages
        self.answerText = answerText
        self.isStreaming = isStreaming
        self.providerUsed = providerUsed
    }
}

/// Manages per-document Agent conversation history and streaming answer synthesis.
@MainActor
public final class DocumentAgentConversation {
    private var turnHistory: [(question: String, answer: String)] = []

    private static let instructions = """
    You are a research assistant answering questions about one PDF document, using only the \
    provided excerpts. Answer in about 4 sentences with the relevant specific detail, not just a \
    bare one-line fact, and without reproducing excerpt text verbatim. If nothing here answers the \
    question, say so rather than guessing. Don't cite page numbers — they're already shown \
    separately in the UI.
    """

    public init() {}

    /// Clears conversation history.
    public func reset() {
        turnHistory = []
    }

    /// Returns the active synthesis backend, or nil if none is available.
    public func activeSynthesisProvider() -> AgentSynthesisProvider? {
#if canImport(FoundationModels)
#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *) {
            if PrivateCloudComputeLanguageModel().isAvailable {
                return .privateCloudCompute
            }
        }
#endif
        if #available(macOS 26.0, *) {
            guard case .available = SystemLanguageModel.default.availability else { return nil }
            return .onDevice
        }
#endif
        return nil
    }

    public func isSynthesisAvailable() -> Bool {
        activeSynthesisProvider() != nil
    }

    /// Recommended number of passages to include based on available model capacity.
    public func recommendedPassageCount(onDeviceDefault: Int) -> Int {
#if canImport(FoundationModels)
#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *), activeSynthesisProvider() == .privateCloudCompute {
            return onDeviceDefault * 4
        }
#endif
#endif
        return onDeviceDefault
    }

    /// Streams an answer to `question` using `passages` as context.
    public func streamAnswer(
        question: String,
        passages: [AgentPassage],
        onPartial: @escaping (String) -> Void
    ) async -> String? {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await streamAnswerImpl(question: question, passages: passages, onPartial: onPartial)
        }
#endif
        return nil
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func streamAnswerImpl(
        question: String,
        passages: [AgentPassage],
        onPartial: @escaping (String) -> Void
    ) async -> String? {
        guard isSynthesisAvailable(), !passages.isEmpty else { return nil }

#if VECTORPDF_MACOS27_SDK
        let session: LanguageModelSession
        if #available(macOS 27.0, *), activeSynthesisProvider() == .privateCloudCompute {
            session = LanguageModelSession(model: PrivateCloudComputeLanguageModel(), instructions: Self.instructions)
        } else {
            session = LanguageModelSession(instructions: Self.instructions)
        }
#else
        let session = LanguageModelSession(instructions: Self.instructions)
#endif

        let excerpts = passages.map { $0.text }.joined(separator: "\n\n---\n\n")
        var promptSections: [String] = []
        if !turnHistory.isEmpty {
            let historyText = turnHistory.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
            promptSections.append("Previous conversation (for context only, not the current question):\n\(historyText)")
        }
        promptSections.append("Excerpts:\n\(excerpts)")
        promptSections.append("Question: \(question)")
        let prompt = promptSections.joined(separator: "\n\n")
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 4000)

        var last = ""
        do {
            let stream = session.streamResponse(to: prompt, options: options)
            for try await partial in stream {
                last = partial.content
                onPartial(last)
            }
        } catch {
            // Retain any partial text generated prior to error
        }
        if !last.isEmpty {
            turnHistory.append((question: question, answer: last))
        }
        return last.isEmpty ? nil : last
    }
#endif
}
