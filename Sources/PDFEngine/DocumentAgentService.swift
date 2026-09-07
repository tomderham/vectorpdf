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
    public func recommendedPassageCount(onDeviceDefault: Int) -> Int {
#if canImport(FoundationModels)
#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *) {
            if activeSynthesisProvider() == .privateCloudCompute {
                return onDeviceDefault * 4
            }
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
    ) async -> AgentStreamResult {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await streamAnswerImpl(question: question, passages: passages, onPartial: onPartial)
        }
#endif
        return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: "Synthesis is unavailable on this macOS version.")
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func streamAnswerImpl(
        question: String,
        passages: [AgentPassage],
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
                        let session = LanguageModelSession(model: pcc, instructions: Self.instructions)
                        let prompt = buildPrompt(question: question, passages: passages)
                        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: 4000)
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
        let prompt = buildPrompt(question: question, passages: onDevicePassages)
        let session = LanguageModelSession(instructions: Self.instructions)
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
            let err = "On-device synthesis error: \(error.localizedDescription)"
            return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: err)
        }

        if !last.isEmpty {
            turnHistory.append((question: question, answer: last))
            let note = attemptedPCC ? "PCC unavailable (\(pccFailureReason ?? "requires developer entitlement")); answered via on-device model" : nil
            return AgentStreamResult(text: last, providerUsed: .onDevice, statusNote: note, errorMessage: nil)
        }

        let finalError = pccFailureReason.map { "Unable to respond: \($0)" } ?? "Unable to respond; conversational length limit or synthesis error."
        return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: finalError)
    }

    private func buildPrompt(question: String, passages: [AgentPassage]) -> String {
        let excerpts = passages.map { $0.text }.joined(separator: "\n\n---\n\n")
        var promptSections: [String] = []
        if !turnHistory.isEmpty {
            let historyText = turnHistory.map { "Q: \($0.question)\nA: \($0.answer)" }.joined(separator: "\n\n")
            promptSections.append("Previous conversation (for context only, not the current question):\n\(historyText)")
        }
        promptSections.append("Excerpts:\n\(excerpts)")
        promptSections.append("Question: \(question)")
        return promptSections.joined(separator: "\n\n")
    }
#endif
}
