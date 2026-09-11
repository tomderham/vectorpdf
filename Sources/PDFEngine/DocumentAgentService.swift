import Foundation
import Security
#if canImport(FoundationModels)
import FoundationModels
#endif

/// One retrieved passage, ready to show in the Agent tab's results list and to jump to on tap.
public struct AgentPassage: Sendable, Identifiable, Equatable {
    public let id = UUID()
    public let pageIndex: Int
    public let text: String
    public let score: Float

    public init(pageIndex: Int, text: String, score: Float) {
        self.pageIndex = pageIndex
        self.text = text
        self.score = score
    }
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
    public var statusNote: String?
    public var errorMessage: String?

    public init(
        id: UUID = UUID(),
        question: String,
        passages: [AgentPassage] = [],
        answerText: String = "",
        isStreaming: Bool = false,
        providerUsed: AgentSynthesisProvider? = nil,
        statusNote: String? = nil,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.question = question
        self.passages = passages
        self.answerText = answerText
        self.isStreaming = isStreaming
        self.providerUsed = providerUsed
        self.statusNote = statusNote
        self.errorMessage = errorMessage
    }
}

/// Result returned from streaming synthesis.
public struct AgentStreamResult: Sendable {
    public let text: String?
    public let providerUsed: AgentSynthesisProvider?
    public let statusNote: String?
    public let errorMessage: String?

    public init(text: String?, providerUsed: AgentSynthesisProvider?, statusNote: String? = nil, errorMessage: String? = nil) {
        self.text = text
        self.providerUsed = providerUsed
        self.statusNote = statusNote
        self.errorMessage = errorMessage
    }
}

/// Manages per-document Agent conversation history and streaming answer synthesis.
@MainActor
public final class DocumentAgentConversation {
    private var turnHistory: [(question: String, answer: String)] = []

    /// Context window limits in tokens for supported models.
    public static let onDeviceContextSize = 4096
    public static let pccContextSize = 32768

    /// Response token limits: on-device is constrained to 800 tokens to preserve the 4,096-token context window; PCC can use up to 4,000.
    public static let onDeviceMaxResponseTokens = 800
    public static let pccMaxResponseTokens = 4000

    /// Ultra-compact instructions for on-device generation to maximize available token space for excerpts.
    public static let onDeviceInstructions = "Answer in 2-4 sentences using only the excerpts. Cite [Page X] for facts. Say if unsure."

    /// Detailed instructions for Private Cloud Compute (32,768-token context window).
    public static let pccInstructions = """
    You are a research assistant answering questions about a PDF document using only the provided excerpts. \
    Answer thoroughly with specific details without repeating excerpts verbatim. \
    Always cite your sources with page tags like [Page X] directly after each factual claim. \
    If the answer cannot be determined from the excerpts, state that clearly.
    """

    /// Backward-compatible alias for default instructions.
    public static var instructions: String { onDeviceInstructions }

    /// Maximum estimated tokens across all document text to qualify for direct full-document synthesis under PCC without RAG chunking.
    public static let fullDocumentTokenThreshold = 20_000

    public init() {}

    /// Clears conversation history.
    public func reset() {
        turnHistory = []
    }

    /// Checks whether the current process possesses Apple's managed entitlement for Private Cloud Compute.
    public static func hasPrivateCloudComputeEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        guard let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.private-cloud-compute" as CFString, nil) else {
            return false
        }
        if let boolVal = value as? Bool {
            return boolVal
        }
        if CFGetTypeID(value) == CFBooleanGetTypeID() {
            return CFBooleanGetValue((value as! CFBoolean))
        }
        return false
    }

    /// Returns the active synthesis backend, or nil if none is available.
    public func activeSynthesisProvider() -> AgentSynthesisProvider? {
#if canImport(FoundationModels)
#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *) {
            let pref = PDFViewerAppCoordinator.shared.agentSynthesisPreference
            if pref == .privateCloudCompute {
                return .privateCloudCompute
            } else if pref == .automatic && Self.hasPrivateCloudComputeEntitlement() && PrivateCloudComputeLanguageModel().isAvailable {
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
    public func recommendedPassageCount(onDeviceDefault: Int = 6) -> Int {
#if canImport(FoundationModels)
#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *) {
            if activeSynthesisProvider() == .privateCloudCompute {
                return 45
            }
        }
#endif
#endif
        return onDeviceDefault
    }

    /// Candidate pool sizes (embedding pool, lexical pool) for candidate union filtering.
    public func recommendedCandidatePoolSizes() -> (embedding: Int, lexical: Int) {
#if canImport(FoundationModels)
#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *) {
            if activeSynthesisProvider() == .privateCloudCompute {
                return (embedding: 100, lexical: 40)
            }
        }
#endif
#endif
        return (embedding: 24, lexical: 10)
    }

    /// Streams an answer to `question` using `passages` as context.
    public func streamAnswer(
        question: String,
        passages: [AgentPassage],
        isFullDocument: Bool = false,
        onPartial: @escaping (String) -> Void
    ) async -> AgentStreamResult {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await streamAnswerImpl(question: question, passages: passages, isFullDocument: isFullDocument, onPartial: onPartial)
        }
#endif
        return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: "Synthesis is unavailable on this macOS version.")
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func streamAnswerImpl(
        question: String,
        passages: [AgentPassage],
        isFullDocument: Bool,
        onPartial: @escaping (String) -> Void
    ) async -> AgentStreamResult {
        guard isSynthesisAvailable(), !passages.isEmpty else {
            return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: "No passages retrieved or synthesis unavailable.")
        }

        let pref = PDFViewerAppCoordinator.shared.agentSynthesisPreference
        var attemptedPCC = false
        var pccFailureReason: String?

#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *), pref != .onDevice {
            let entitled = Self.hasPrivateCloudComputeEntitlement()
            if pref == .privateCloudCompute || (pref == .automatic && entitled) {
                attemptedPCC = true
                if !entitled && pref == .privateCloudCompute {
                    pccFailureReason = "Requires Apple Developer entitlement 'com.apple.developer.private-cloud-compute'"
                } else if !PrivateCloudComputeLanguageModel().isAvailable {
                    pccFailureReason = "Private Cloud Compute model unavailable on this system"
                } else {
                    do {
                        let pcc = PrivateCloudComputeLanguageModel()
                        let session = LanguageModelSession(model: pcc, instructions: Self.pccInstructions)
                        let prompt = buildPrompt(question: question, passages: passages, isFullDocument: isFullDocument, provider: .privateCloudCompute)
                        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.pccMaxResponseTokens)
                        let stream = session.streamResponse(to: prompt, options: options)
                        var last = ""
                        for try await partial in stream {
                            last = partial.content
                            onPartial(last)
                        }
                        if !last.isEmpty {
                            turnHistory.append((question: question, answer: last))
                            return AgentStreamResult(text: last, providerUsed: .privateCloudCompute, statusNote: nil, errorMessage: nil)
                        }
                    } catch {
                        pccFailureReason = error.localizedDescription
                    }
                }
            }
        }
#endif

        // On-device fallback (or primary if onDevice preferred or unentitled in automatic mode)
        guard case .available = SystemLanguageModel.default.availability else {
            let err = pccFailureReason.map { "Private Cloud Compute failed (\($0)) and on-device model is unavailable." } ?? "On-device model is unavailable."
            return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: err)
        }

        let onDevicePassages = Array(passages.prefix(6))
        let prompt = buildPrompt(question: question, passages: onDevicePassages, isFullDocument: false, provider: .onDevice)
        let session = LanguageModelSession(instructions: Self.onDeviceInstructions)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.onDeviceMaxResponseTokens)

        var last = ""
        do {
            let stream = session.streamResponse(to: prompt, options: options)
            for try await partial in stream {
                last = partial.content
                onPartial(last)
            }
        } catch {
            // Retain any partial text generated prior to error
            let err = "On-device synthesis error: \(error.localizedDescription)"
            return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: err)
        }

        if !last.isEmpty {
            turnHistory.append((question: question, answer: last))
#if VECTORPDF_MACOS27_SDK
            let note = attemptedPCC ? "PCC unavailable (\(pccFailureReason ?? "requires developer entitlement")); answered via on-device model" : nil
#else
            let note: String? = nil
#endif
            return AgentStreamResult(text: last, providerUsed: .onDevice, statusNote: note, errorMessage: nil)
        }

        let finalError = pccFailureReason.map { "Unable to respond: \($0)" } ?? "Unable to respond; conversational length limit or synthesis error."
        return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: finalError)
    }

    private func buildPrompt(
        question: String,
        passages: [AgentPassage],
        isFullDocument: Bool,
        provider: AgentSynthesisProvider
    ) -> String {
        let label = isFullDocument ? "Document Content" : "Excerpts"
        let formattedExcerpts = passages.map { "[Page \($0.pageIndex + 1)]\n\($0.text)" }.joined(separator: "\n\n---\n\n")
        var promptSections: [String] = []

        // History budgeting: on-device keeps only the immediate previous turn (trimmed to 400 chars)
        // to stay comfortably within the 4,096-token limit. PCC keeps up to 4 turns.
        let historyToInclude: [(question: String, answer: String)]
        if provider == .onDevice {
            historyToInclude = turnHistory.suffix(1).map {
                let trimmedAnswer = $0.answer.count > 400 ? String($0.answer.prefix(400)) + "…" : $0.answer
                return (question: $0.question, answer: trimmedAnswer)
            }
        } else {
            historyToInclude = Array(turnHistory.suffix(4))
        }

        if !historyToInclude.isEmpty {
            let historyText = historyToInclude.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
            if provider == .onDevice {
                promptSections.append("History:\n\(historyText)")
            } else {
                promptSections.append("Previous conversation (for context only, not the current question):\n\(historyText)")
            }
        }

        promptSections.append("\(label):\n\(formattedExcerpts)")
        promptSections.append("Question: \(question)")
        return promptSections.joined(separator: "\n\n")
    }
#endif
}
