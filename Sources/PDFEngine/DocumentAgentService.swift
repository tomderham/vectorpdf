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
    /// An online model with the person's API key; the value is its display name.
    case onlineModel(String)

    /// Large-context models get many passages, or the whole of a short document.
    public var hasLargeContext: Bool { self != .onDevice }
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

    /// Context window limits in tokens for supported models. The on-device size is a fallback; the model
    /// reports its own (8,192 tokens on macOS 27).
    public static let onDeviceContextSize = 4096
    public static let pccContextSize = 32768

    /// Response token limits: on-device answers are short (see onDeviceInstructions), so 800 tokens leaves the rest of the context for excerpts; PCC can use up to 4,000.
    public static let onDeviceMaxResponseTokens = 800
    public static let pccMaxResponseTokens = 4000
    /// Online reasoning models count their thinking against this limit, so it is higher than PCC's.
    public static let onlineMaxResponseTokens = 8000

    /// Ultra-compact instructions for on-device generation to maximize available token space for excerpts.
    public static let onDeviceInstructions = "Answer in 2-4 sentences using only the excerpts. Cite [Page X] for facts. Say if unsure."

    /// Added to the on-device instructions when the searchDocument tool is attached.
    public static let onDeviceSearchHint = "If the excerpts don't answer the question, call searchDocument to find more."

    /// The search tool is offered only when the context has room for its results (macOS 27's 8K, not 4K).
    static let minContextForSearchTool = 8192
    static let maxSearchesPerAnswer = 2

    /// Detailed instructions for Private Cloud Compute (32,768-token context window).
    public static let pccInstructions = """
    You are a research assistant answering questions about a PDF document using only the provided excerpts. \
    Answer thoroughly with specific details without repeating excerpts verbatim. \
    Always cite your sources with page tags like [Page X] directly after each factual claim. \
    If the answer cannot be determined from the excerpts, state that clearly.
    """

    /// Alias for default instructions.
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
            if pref == .onlineModel, let config = PDFViewerAppCoordinator.shared.onlineModelConfiguration {
                return .onlineModel(config.displayName)
            } else if pref == .privateCloudCompute {
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
            if activeSynthesisProvider()?.hasLargeContext == true {
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
            if activeSynthesisProvider()?.hasLargeContext == true {
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
        onDevicePassages: [AgentPassage]? = nil,
        isFullDocument: Bool = false,
        searchMore: (@MainActor (String) async -> [AgentPassage])? = nil,
        onProvider: @escaping (AgentSynthesisProvider) -> Void = { _ in },
        onSources: @escaping ([AgentPassage]) -> Void = { _ in },
        onPartial: @escaping (String) -> Void
    ) async -> AgentStreamResult {
#if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return await streamAnswerImpl(
                question: question, passages: passages, onDevicePassages: onDevicePassages, isFullDocument: isFullDocument,
                searchMore: searchMore, onProvider: onProvider, onSources: onSources, onPartial: onPartial
            )
        }
#endif
        return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: "Synthesis is unavailable on this macOS version.")
    }

#if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func streamAnswerImpl(
        question: String,
        passages: [AgentPassage],
        onDevicePassages: [AgentPassage]?,
        isFullDocument: Bool,
        searchMore: (@MainActor (String) async -> [AgentPassage])?,
        onProvider: @escaping (AgentSynthesisProvider) -> Void,
        onSources: @escaping ([AgentPassage]) -> Void,
        onPartial: @escaping (String) -> Void
    ) async -> AgentStreamResult {
        guard isSynthesisAvailable(), !passages.isEmpty else {
            return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: "No passages retrieved or synthesis unavailable.")
        }

        let pref = PDFViewerAppCoordinator.shared.agentSynthesisPreference
        // The remote model tried before on-device (PCC or an online model), and why it didn't answer.
        var remoteName: String?
        var remoteFailureReason: String?

#if VECTORPDF_MACOS27_SDK
        if #available(macOS 27.0, *), pref == .onlineModel {
            if let config = PDFViewerAppCoordinator.shared.onlineModelConfiguration {
                remoteName = config.service.displayName
                let model = ChatCompletionsLanguageModel(
                    name: config.model,
                    url: config.service.baseURL,
                    additionalHeaders: ["Authorization": "Bearer \(config.apiKey)"],
                    supportsGuidedGeneration: false
                )
                let session = LanguageModelSession(model: model, instructions: Self.pccInstructions)
                let provider = AgentSynthesisProvider.onlineModel(config.displayName)
                let prompt = buildPrompt(question: question, passages: passages, isFullDocument: isFullDocument, provider: provider)
                // No temperature: OpenAI's reasoning models accept only the default.
                let options = GenerationOptions(maximumResponseTokens: Self.onlineMaxResponseTokens)
                do {
                    let last = try await Self.streamWithFirstOutputTimeout(
                        session: session, prompt: prompt, options: options,
                        timeout: Self.onlineFirstOutputTimeout, onPartial: onPartial
                    )
                    if !last.isEmpty {
                        turnHistory.append((question: question, answer: last))
                        return AgentStreamResult(text: last, providerUsed: provider, statusNote: nil, errorMessage: nil)
                    }
                } catch {
                    remoteFailureReason = Self.describeOnlineError(error)
                }
            } else {
                remoteName = "Online model"
                remoteFailureReason = "add an API key and choose a model in Settings"
            }
        }

        if #available(macOS 27.0, *), pref == .privateCloudCompute {
            let entitled = Self.hasPrivateCloudComputeEntitlement()
            remoteName = "Private Cloud Compute"
            if !entitled && pref == .privateCloudCompute {
                remoteFailureReason = "this build isn't signed with the Private Cloud Compute entitlement"
            } else if !PrivateCloudComputeLanguageModel().isAvailable {
                remoteFailureReason = "it isn't available on this Mac"
            } else {
                let prompt = buildPrompt(question: question, passages: passages, isFullDocument: isFullDocument, provider: .privateCloudCompute)
                let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.pccMaxResponseTokens)
                // A request can occasionally stall before the server sees it; retry once on a fresh
                // session if nothing streamed back, then fall back to on-device.
                for attempt in 1...2 {
                    let pcc = PrivateCloudComputeLanguageModel()
                    let session = LanguageModelSession(model: pcc, instructions: Self.pccInstructions)
                    do {
                        let last = try await Self.streamWithFirstOutputTimeout(
                            session: session, prompt: prompt, options: options,
                            timeout: Self.pccFirstOutputTimeout, onPartial: onPartial
                        )
                        if !last.isEmpty {
                            turnHistory.append((question: question, answer: last))
                            return AgentStreamResult(text: last, providerUsed: .privateCloudCompute, statusNote: Self.pccQuotaNote(pcc.quotaUsage), errorMessage: nil)
                        }
                        break
                    } catch let error as FirstOutputTimeout {
                        remoteFailureReason = error.localizedDescription
                    } catch let error as PrivateCloudComputeLanguageModel.Error {
                        remoteFailureReason = Self.describe(error)
                        guard case .networkFailure = error else { break }
                    } catch let error as LanguageModelError {
                        remoteFailureReason = Self.describe(error)
                        break
                    } catch {
                        remoteFailureReason = error.localizedDescription
                        break
                    }
                    if attempt == 1 { onPartial("") }
                }
            }
        }
#endif

        // On-device: the chosen engine, or the fallback when a remote model didn't answer.
        guard case .available = SystemLanguageModel.default.availability else {
            let err = remoteFailureReason.map { "\(remoteName ?? "The remote model") unavailable: \($0). The on-device model is unavailable too." } ?? "On-device model is unavailable."
            return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: err)
        }

        onProvider(.onDevice)
        // Fill the context with as many of the best passages as fit, leaving room for the answer and,
        // when the search tool is offered, for what it returns.
        let contextSize = SystemLanguageModel.default.contextSize
        let searchResultTokens = contextSize / 10
        let useSearch = searchMore != nil && contextSize >= Self.minContextForSearchTool
        let instructions = useSearch ? "\(Self.onDeviceInstructions) \(Self.onDeviceSearchHint)" : Self.onDeviceInstructions
        let promptFrame = buildPrompt(question: question, passages: [], isFullDocument: false, provider: .onDevice)
        let fixedTokens = await Self.estimateTokens(instructions) + Self.estimateTokens(promptFrame) + (useSearch ? 150 : 0)
        let reserved = Self.onDeviceMaxResponseTokens + (useSearch ? searchResultTokens * Self.maxSearchesPerAnswer : 0) + contextSize / 20
        var excerpts = await Self.fitPassages(onDevicePassages ?? passages, tokenBudget: contextSize - reserved - fixedTokens)
        if excerpts.isEmpty, let best = (onDevicePassages ?? passages).first { excerpts = [best] }
        onSources(excerpts)

        var tools: [any Tool] = []
        if useSearch, let searchMore {
            let search = SearchState(shown: excerpts)
            tools.append(DocumentSearchTool { query in
                guard search.remaining > 0 else {
                    return "No more searches available. Answer with the excerpts you have."
                }
                search.remaining -= 1
                let fresh = await searchMore(query).filter { candidate in
                    !search.shown.contains { $0.pageIndex == candidate.pageIndex && $0.text == candidate.text }
                }
                let found = await Self.fitPassages(fresh, tokenBudget: searchResultTokens)
                guard !found.isEmpty else { return "No further relevant excerpts found." }
                search.shown += found
                onSources(search.shown)
                return Self.formatExcerpts(found)
            })
        }

        let prompt = buildPrompt(question: question, passages: excerpts, isFullDocument: false, provider: .onDevice)
        let session = LanguageModelSession(tools: tools, instructions: instructions)
        let options = GenerationOptions(temperature: 0.3, maximumResponseTokens: Self.onDeviceMaxResponseTokens)

        var last = ""
        do {
            let stream = session.streamResponse(to: prompt, options: options)
            for try await partial in stream {
                last = partial.content
                onPartial(last)
            }
        } catch {
            // Keep whatever was generated before the error, flagged as incomplete.
            guard !last.isEmpty else {
                let err = "On-device synthesis error: \(error.localizedDescription)"
                return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: err)
            }
            return AgentStreamResult(text: last, providerUsed: .onDevice, statusNote: "Answer may be incomplete: \(error.localizedDescription)", errorMessage: nil)
        }

        if !last.isEmpty {
            turnHistory.append((question: question, answer: last))
#if VECTORPDF_MACOS27_SDK
            let note = remoteName.map { "\($0) unavailable: \(remoteFailureReason ?? "unknown error")." }
#else
            let note: String? = nil
#endif
            return AgentStreamResult(text: last, providerUsed: .onDevice, statusNote: note, errorMessage: nil)
        }

        let finalError = remoteFailureReason.map { "Unable to respond. \(remoteName ?? "The remote model") unavailable: \($0)." } ?? "Unable to respond; conversational length limit or synthesis error."
        return AgentStreamResult(text: nil, providerUsed: nil, statusNote: nil, errorMessage: finalError)
    }

    /// How long to wait for the first streamed PCC output before treating the request as stalled.
    /// First output normally arrives in 2–7 s, including for a 45-passage prompt.
    static let pccFirstOutputTimeout: Duration = .seconds(20)
    /// Online reasoning models can think for a while before streaming any text.
    static let onlineFirstOutputTimeout: Duration = .seconds(90)

    struct FirstOutputTimeout: LocalizedError {
        var errorDescription: String? { "no response" }
    }

    /// Streams `prompt` into `onPartial`, failing with `FirstOutputTimeout` if nothing arrives within
    /// `timeout`. Returns without waiting for a stalled stream to notice cancellation, and stops
    /// forwarding its output so it can't overwrite a fallback answer.
    @available(macOS 26.0, *)
    private static func streamWithFirstOutputTimeout(
        session: LanguageModelSession,
        prompt: String,
        options: GenerationOptions,
        timeout: Duration,
        onPartial: @escaping (String) -> Void
    ) async throws -> String {
        let state = StreamState()
        return try await withCheckedThrowingContinuation { continuation in
            state.continuation = continuation
            let streamTask = Task { @MainActor in
                do {
                    var last = ""
                    for try await partial in session.streamResponse(to: prompt, options: options) {
                        guard state.continuation != nil else { return }
                        state.receivedOutput = true
                        last = partial.content
                        onPartial(last)
                    }
                    state.finish(.success(last))
                } catch {
                    state.finish(.failure(error))
                }
            }
            Task { @MainActor in
                try? await Task.sleep(for: timeout)
                if !state.receivedOutput {
                    streamTask.cancel()
                    state.finish(.failure(FirstOutputTimeout()))
                }
            }
        }
    }

    @MainActor
    private final class StreamState {
        var continuation: CheckedContinuation<String, Error>?
        var receivedOutput = false

        func finish(_ result: Result<String, Error>) {
            continuation?.resume(with: result)
            continuation = nil
        }
    }

#if VECTORPDF_MACOS27_SDK
    @available(macOS 27.0, *)
    static func describe(_ error: PrivateCloudComputeLanguageModel.Error) -> String {
        switch error {
        case .networkFailure:
            return "couldn't reach Private Cloud Compute"
        case .serviceUnavailable:
            return "Private Cloud Compute is temporarily unavailable"
        case .quotaLimitReached(let info):
            if let reset = info.resetDate {
                return "today's Private Cloud Compute limit is reached; it resets \(reset.formatted(.relative(presentation: .named)))"
            }
            return "today's Private Cloud Compute limit is reached"
        @unknown default:
            return error.localizedDescription
        }
    }

    @available(macOS 27.0, *)
    static func describe(_ error: LanguageModelError) -> String {
        switch error {
        case .contextSizeExceeded(let info):
            return "the question and excerpts are too long (\(info.tokenCount) of \(info.contextSize) tokens)"
        case .rateLimited:
            return "too many requests; try again shortly"
        case .timeout:
            return "Private Cloud Compute took too long to respond"
        case .guardrailViolation, .refusal:
            return "the model declined to answer"
        case .unsupportedLanguageOrLocale:
            return "this language isn't supported"
        default:
            return error.localizedDescription
        }
    }

    /// The server's own message for an online model failure (e.g. "Incorrect API key provided").
    @available(macOS 27.0, *)
    static func describeOnlineError(_ error: Error) -> String {
        switch error {
        case let error as ChatCompletionsLanguageModel.APIError:
            return error.message
        case ChatCompletionsLanguageModel.RequestError.httpError(let status, let data):
            return OnlineModelCatalog.serverMessage(in: data) ?? "the server returned HTTP \(status)"
        case let error as LanguageModelError:
            return describe(error)
        default:
            return error.localizedDescription
        }
    }

    /// A note to show under a PCC answer when the person is close to the daily limit.
    @available(macOS 27.0, *)
    static func pccQuotaNote(_ usage: PrivateCloudComputeLanguageModel.QuotaUsage) -> String? {
        guard case .belowLimit(let status) = usage.status, status.isApproachingLimit else { return nil }
        return "You're close to today's Private Cloud Compute limit."
    }
#endif

    static func formatExcerpts(_ passages: [AgentPassage]) -> String {
        passages.map { "[Page \($0.pageIndex + 1)]\n\($0.text)" }.joined(separator: "\n\n---\n\n")
    }

    /// Token count from the on-device tokenizer (macOS 26.4+), or an estimate before that.
    @available(macOS 26.0, *)
    static func estimateTokens(_ text: String) async -> Int {
        if #available(macOS 26.4, *), let count = try? await SystemLanguageModel.default.tokenCount(for: text) {
            return count
        }
        return text.count / 3 + 1
    }

    /// The passages, in order, that fit in `tokenBudget`; a passage too big for what's left is skipped.
    @available(macOS 26.0, *)
    static func fitPassages(_ candidates: [AgentPassage], tokenBudget: Int) async -> [AgentPassage] {
        var fitted: [AgentPassage] = []
        var used = 0
        for passage in candidates where tokenBudget - used > 50 {
            let cost = await estimateTokens(formatExcerpts([passage])) + 4
            if used + cost <= tokenBudget {
                fitted.append(passage)
                used += cost
            }
        }
        return fitted
    }

    /// Lets the on-device model fetch more excerpts, a limited number of times per answer.
    @available(macOS 26.0, *)
    struct DocumentSearchTool: Tool {
        let name = "searchDocument"
        let description = "Searches the open PDF and returns more excerpts, with page numbers."

        @Generable
        struct Arguments {
            @Guide(description: "What to look for, in a few words")
            var query: String
        }

        let search: @MainActor @Sendable (String) async -> String

        func call(arguments: Arguments) async throws -> String {
            await search(arguments.query)
        }
    }

    @MainActor
    private final class SearchState {
        var shown: [AgentPassage]
        var remaining = DocumentAgentConversation.maxSearchesPerAnswer

        init(shown: [AgentPassage]) {
            self.shown = shown
        }
    }

    private func buildPrompt(
        question: String,
        passages: [AgentPassage],
        isFullDocument: Bool,
        provider: AgentSynthesisProvider
    ) -> String {
        let label = isFullDocument ? "Document Content" : "Excerpts"
        let formattedExcerpts = Self.formatExcerpts(passages)
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
