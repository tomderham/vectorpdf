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
import SwiftUI

/// OpenAI-compatible services the Agent can answer with, using the person's own API key (macOS 27).
public enum OnlineModelService: String, CaseIterable, Codable, Sendable {
    case openAI
    case gemini
    case openRouter

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .gemini: return "Google Gemini"
        case .openRouter: return "OpenRouter"
        }
    }

    /// Base URL of the service's OpenAI-compatible API (chat completions and model list).
    public var baseURL: URL {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1")!
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")!
        }
    }

    /// Where to create an API key.
    public var keyPageURL: URL {
        switch self {
        case .openAI: return URL(string: "https://platform.openai.com/api-keys")!
        case .gemini: return URL(string: "https://aistudio.google.com/apikey")!
        case .openRouter: return URL(string: "https://openrouter.ai/keys")!
        }
    }
}

/// A fully set-up online model: service, model name, and API key.
public struct OnlineModelConfiguration: Sendable, Equatable {
    public let service: OnlineModelService
    public let model: String
    public let apiKey: String

    /// Shown in the Agent tab, e.g. "gpt-5-mini (OpenAI)".
    public var displayName: String { "\(model) (\(service.displayName))" }
}

/// API keys for online models, kept in the login keychain rather than in preferences.
public enum APIKeyStore {
    public static let defaultKeychainService = "com.thomasderham.vectorpdf.api-key"

    public static func key(for service: OnlineModelService, keychainService: String = defaultKeychainService) -> String? {
        var query = baseQuery(service, keychainService)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8), !key.isEmpty else { return nil }
        return key
    }

    /// Saves `key` for `service`, or removes the stored key when `key` is nil or blank.
    public static func setKey(_ key: String?, for service: OnlineModelService, keychainService: String = defaultKeychainService) {
        let query = baseQuery(service, keychainService)
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else {
            SecItemDelete(query as CFDictionary)
            return
        }
        let data = Data(trimmed.utf8)
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "VectorPDF \(service.displayName) API key"
            SecItemAdd(item as CFDictionary, nil)
        }
    }

    private static func baseQuery(_ service: OnlineModelService, _ keychainService: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: service.rawValue,
        ]
    }
}

/// Lists the models a service offers, via its OpenAI-compatible `GET /models`.
public enum OnlineModelCatalog {
    public struct RequestError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    public static func modelIDs(
        for service: OnlineModelService,
        apiKey: String,
        session: URLSession = .shared
    ) async throws -> [String] {
        var request = URLRequest(url: service.baseURL.appendingPathComponent("models"))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RequestError(message: serverMessage(in: data) ?? "The server returned HTTP \(http.statusCode).")
        }
        return try parseModelIDs(data)
    }

    /// Sends a tiny chat request to confirm `model` answers with this key. This catches models the
    /// key can't use, such as Gemini models with no free-tier quota.
    public static func checkModel(
        _ model: String,
        for service: OnlineModelService,
        apiKey: String,
        session: URLSession = .shared
    ) async throws {
        var request = URLRequest(url: service.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        // A model that takes longer than this for "OK" is overloaded or too slow to be useful.
        request.timeoutInterval = 30
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [["role": "user", "content": "Reply with OK."]],
            "max_completion_tokens": 16,
        ])
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw RequestError(message: serverMessage(in: data) ?? "The server returned HTTP \(http.statusCode).")
        }
    }

    /// Model IDs from an OpenAI-style `{"data": [{"id": …}]}` list, sorted and without duplicates.
    /// Gemini prefixes IDs with "models/", which its chat endpoint doesn't need.
    static func parseModelIDs(_ data: Data) throws -> [String] {
        struct List: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let ids = try JSONDecoder().decode(List.self, from: data).data.map { model in
            model.id.hasPrefix("models/") ? String(model.id.dropFirst("models/".count)) : model.id
        }
        return Array(Set(ids)).sorted()
    }

    /// The first sentence of the human-readable message in an error response: `{"error": {"message": …}}`,
    /// or the same wrapped in an array (Gemini). Later sentences are usually links and quota details.
    static func serverMessage(in data: Data) -> String? {
        fullServerMessage(in: data).map(firstSentence)
    }

    static func firstSentence(_ message: String) -> String {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = [text.range(of: ". "), text.range(of: "\n")].compactMap { $0 }.min { $0.lowerBound < $1.lowerBound }
        guard let end else { return text }
        let sentence = text[..<end.lowerBound].trimmingCharacters(in: .whitespaces)
        return sentence.hasSuffix(".") ? sentence : sentence + "."
    }

    private static func fullServerMessage(in data: Data) -> String? {
        struct Envelope: Decodable {
            struct Detail: Decodable { let message: String? }
            let error: Detail
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data) {
            return envelope.error.message
        }
        return (try? JSONDecoder().decode([Envelope].self, from: data))?.first?.error.message
    }
}

/// Settings for the online model engine: service, API key, and model.
struct OnlineModelSettingsView: View {
    private enum ModelList: Equatable {
        case needsKey, loading, loaded([String]), failed(String)
    }

    @ObservedObject private var coordinator = PDFViewerAppCoordinator.shared
    @State private var apiKey = ""
    @State private var modelList = ModelList.needsKey
    @State private var modelCheck = ""
    @State private var checkTask: Task<Void, Never>?

    var body: some View {
        let service = coordinator.onlineModelService
        let model = coordinator.onlineModelNames[service.rawValue] ?? ""
        Picker("Service", selection: $coordinator.onlineModelService) {
            ForEach(OnlineModelService.allCases, id: \.self) { service in
                Text(service.displayName).tag(service)
            }
        }
        .pickerStyle(.menu)

        SecureField("API Key", text: $apiKey)
            .onChange(of: apiKey) { _, newValue in
                APIKeyStore.setKey(newValue, for: service)
            }
        Link("Get a \(service.displayName) API key", destination: service.keyPageURL)
            .font(.caption)

        switch modelList {
        case .loaded(let models):
            Picker("Model", selection: modelBinding(for: service)) {
                Text("Choose a model").tag("")
                // Keep a saved choice visible even if the service stops listing it.
                if !model.isEmpty && !models.contains(model) {
                    Text(model).tag(model)
                }
                ForEach(models, id: \.self) { Text($0).tag($0) }
            }
            .pickerStyle(.menu)
        case .failed(let reason):
            // Without a list, the model can still be typed.
            TextField("Model", text: modelBinding(for: service), prompt: Text("Model name"))
            caption("Couldn't load models: \(reason)")
        case .loading:
            caption("Loading models…")
        case .needsKey:
            caption("Enter an API key to choose a model.")
        }
        if !modelCheck.isEmpty {
            caption(modelCheck)
        }

        caption("Your questions and the passages used to answer them are sent to \(service.displayName) with your key, and billed to your account. If it can't answer, VectorPDF answers on-device.")
            .padding(.bottom, 8)
            .task(id: service) {
                modelCheck = ""
                apiKey = APIKeyStore.key(for: service) ?? ""
            }
            .task(id: "\(service.rawValue)|\(apiKey)") {
                await loadModels(for: service)
            }
            .onChange(of: model) { _, newModel in
                checkTask?.cancel()
                checkTask = Task { await check(newModel, for: service) }
            }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func modelBinding(for service: OnlineModelService) -> Binding<String> {
        Binding(
            get: { coordinator.onlineModelNames[service.rawValue] ?? "" },
            set: { coordinator.onlineModelNames[service.rawValue] = $0.trimmingCharacters(in: .whitespaces) }
        )
    }

    private func loadModels(for service: OnlineModelService) async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            modelList = .needsKey
            return
        }
        // Wait for typing or pasting to settle before checking the key.
        try? await Task.sleep(for: .milliseconds(600))
        guard !Task.isCancelled else { return }
        modelList = .loading
        do {
            let ids = try await OnlineModelCatalog.modelIDs(for: service, apiKey: key)
            guard !Task.isCancelled else { return }
            modelList = ids.isEmpty ? .failed("the service listed no models") : .loaded(ids)
        } catch {
            guard !Task.isCancelled else { return }
            modelList = .failed(error.localizedDescription)
        }
    }

    /// Runs when the person picks or types a model (not when Settings opens, which would use up
    /// free-tier requests).
    private func check(_ model: String, for service: OnlineModelService) async {
        modelCheck = ""
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty, !key.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(800))
        guard !Task.isCancelled else { return }
        modelCheck = "Checking \(model)…"
        do {
            try await OnlineModelCatalog.checkModel(model, for: service, apiKey: key)
            guard !Task.isCancelled else { return }
            modelCheck = "\(model) is working."
        } catch {
            guard !Task.isCancelled else { return }
            if (error as? URLError)?.code == .timedOut {
                modelCheck = "\(model) didn't respond within 30 seconds. It may be busy; try again later or choose another model."
            } else {
                modelCheck = "\(model) can't be used: \(error.localizedDescription)"
            }
        }
    }
}
