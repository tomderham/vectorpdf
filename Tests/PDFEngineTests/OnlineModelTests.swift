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
import Testing
@testable import PDFEngine
#if canImport(FoundationModels)
import FoundationModels
#endif

@Test func testOnlineModelListParsing() throws {
    let openAI = Data(#"{"object":"list","data":[{"id":"gpt-b","object":"model"},{"id":"gpt-a","object":"model"},{"id":"gpt-a"}]}"#.utf8)
    #expect(try OnlineModelCatalog.parseModelIDs(openAI) == ["gpt-a", "gpt-b"])

    // Gemini's OpenAI-compatible list prefixes IDs with "models/".
    let gemini = Data(#"{"object":"list","data":[{"id":"models/gemini-x-flash","object":"model","owned_by":"google"}]}"#.utf8)
    #expect(try OnlineModelCatalog.parseModelIDs(gemini) == ["gemini-x-flash"])

    #expect(throws: (any Error).self) { try OnlineModelCatalog.parseModelIDs(Data("not json".utf8)) }
}

@Test func testOnlineModelServerErrorMessages() {
    let object = Data(#"{"error":{"message":"Incorrect API key provided","type":"invalid_request_error"}}"#.utf8)
    #expect(OnlineModelCatalog.serverMessage(in: object) == "Incorrect API key provided")
    let array = Data(#"[{"error":{"code":400,"message":"API key not valid","status":"INVALID_ARGUMENT"}}]"#.utf8)
    #expect(OnlineModelCatalog.serverMessage(in: array) == "API key not valid")
    #expect(OnlineModelCatalog.serverMessage(in: Data("<html>Bad Gateway</html>".utf8)) == nil)

    // Long quota errors are cut to their first sentence.
    let quota = Data(#"[{"error":{"code":429,"message":"You exceeded your current quota, please check your plan and billing details. For more information on this error, head to: https://example.com/rate-limits. \n* Quota exceeded for metric: free_tier_input_token_count, limit: 0"}}]"#.utf8)
    #expect(OnlineModelCatalog.serverMessage(in: quota) == "You exceeded your current quota, please check your plan and billing details.")
    #expect(OnlineModelCatalog.firstSentence("No period here\nsecond line") == "No period here.")
    #expect(OnlineModelCatalog.firstSentence("Single sentence.") == "Single sentence.")
}

@Test func testAPIKeyStoreRoundTrip() {
    let keychainService = "com.thomasderham.vectorpdf.api-key.tests"
    defer { APIKeyStore.setKey(nil, for: .openRouter, keychainService: keychainService) }

    #expect(APIKeyStore.key(for: .openRouter, keychainService: keychainService) == nil)
    APIKeyStore.setKey("  sk-test-1 \n", for: .openRouter, keychainService: keychainService)
    #expect(APIKeyStore.key(for: .openRouter, keychainService: keychainService) == "sk-test-1")
    APIKeyStore.setKey("sk-test-2", for: .openRouter, keychainService: keychainService)
    #expect(APIKeyStore.key(for: .openRouter, keychainService: keychainService) == "sk-test-2")
    #expect(APIKeyStore.key(for: .openAI, keychainService: keychainService) == nil)
    APIKeyStore.setKey("", for: .openRouter, keychainService: keychainService)
    #expect(APIKeyStore.key(for: .openRouter, keychainService: keychainService) == nil)
}

#if VECTORPDF_MACOS27_SDK && canImport(FoundationModels)
/// Records the request and answers 401, standing in for an online model's server.
private final class RecordingURLProtocol: URLProtocol {
    nonisolated(unsafe) static var lastRequest: URLRequest?
    nonisolated(unsafe) static var lastBody: Data?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lastRequest = request
        Self.lastBody = request.httpBody ?? request.httpBodyStream.map { stream in
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while case let count = stream.read(&buffer, maxLength: buffer.count), count > 0 {
                data.append(buffer, count: count)
            }
            return data
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"error":{"message":"Incorrect API key provided"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Test @MainActor func testOnlineModelRequestUsesGeminiVersionedPathAndKey() async throws {
    guard #available(macOS 27.0, *) else { return }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [RecordingURLProtocol.self]
    let model = ChatCompletionsLanguageModel(
        name: "gemini-x-flash",
        url: OnlineModelService.gemini.baseURL,
        additionalHeaders: ["Authorization": "Bearer test-key"],
        supportsGuidedGeneration: false,
        urlSessionConfiguration: configuration
    )
    let session = LanguageModelSession(model: model)

    var thrown: (any Error)?
    do {
        _ = try await session.respond(to: "Hello", options: GenerationOptions(maximumResponseTokens: 100))
    } catch {
        thrown = error
    }

    let request = try #require(RecordingURLProtocol.lastRequest)
    // Without VectorPDF's change, "v1beta" isn't seen as a version and "/v1" is appended.
    #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-key")
    let body = try #require(RecordingURLProtocol.lastBody)
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["model"] as? String == "gemini-x-flash")
    #expect(json["temperature"] == nil)  // reasoning models reject a non-default temperature

    let error = try #require(thrown)
    #expect(DocumentAgentConversation.describeOnlineError(error) == "Incorrect API key provided")
}
#endif

#if VECTORPDF_MACOS27_SDK && canImport(FoundationModels)
/// Live check against a real service; skipped unless VECTORPDF_ONLINE_TEST_KEY is set.
/// VECTORPDF_ONLINE_TEST_SERVICE (an OnlineModelService raw value, default "gemini") and
/// VECTORPDF_ONLINE_TEST_MODEL (default: first model listed) choose what to call.
@Test(.enabled(if: ProcessInfo.processInfo.environment["VECTORPDF_ONLINE_TEST_KEY"] != nil))
@MainActor func testOnlineModelLiveStreamingAnswer() async throws {
    guard #available(macOS 27.0, *) else { return }
    let env = ProcessInfo.processInfo.environment
    let key = try #require(env["VECTORPDF_ONLINE_TEST_KEY"])
    let service = OnlineModelService(rawValue: env["VECTORPDF_ONLINE_TEST_SERVICE"] ?? "gemini") ?? .gemini

    let models = try await OnlineModelCatalog.modelIDs(for: service, apiKey: key)
    #expect(!models.isEmpty)
    let modelName = try #require(env["VECTORPDF_ONLINE_TEST_MODEL"] ?? models.first)

    let model = ChatCompletionsLanguageModel(
        name: modelName,
        url: service.baseURL,
        additionalHeaders: ["Authorization": "Bearer \(key)"],
        supportsGuidedGeneration: false
    )
    let session = LanguageModelSession(model: model, instructions: DocumentAgentConversation.pccInstructions)
    let prompt = "Excerpts:\n[Page 3]\nThe bridge opened to traffic in 1932 after six years of construction.\n\nQuestion: When did the bridge open?"
    var partials = 0
    var last = ""
    for try await partial in session.streamResponse(to: prompt, options: GenerationOptions(maximumResponseTokens: DocumentAgentConversation.onlineMaxResponseTokens)) {
        partials += 1
        last = partial.content
    }
    #expect(last.contains("1932"))
    #expect(last.contains("[Page 3]"))
    print("Live \(service.displayName) \(modelName): \(partials) partials: \(last)")
}
#endif

@Test @MainActor func testSettingsOfferPCCOnlyWhenEntitled() {
    // The test runner isn't signed with the PCC entitlement, like the Developer ID DMG.
    let offered = PDFViewerAppCoordinator.shared.availableSynthesisPreferences
    #expect(!PDFViewerAppCoordinator.canUsePrivateCloudCompute)
    #expect(offered == [.onDevice, .onlineModel])
}
