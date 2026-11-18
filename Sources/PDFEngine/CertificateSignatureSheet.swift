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

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Signing with a certificate: which one, and what the signature says besides who and when.
struct CertificateSignatureSheet: View {
    @ObservedObject var viewModel: PDFViewerViewModel
    let placement: CertificateSignaturePlacement
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var signatureStore = SignatureStore.shared

    @State private var identities: [SigningIdentity] = []
    @State private var isLoading = true
    @State private var selection: Data?
    /// One read from a .p12 file this time, kept in memory only.
    @State private var fileIdentity: SigningIdentity?
    @State private var pendingFile: (name: String, data: Data)?
    @State private var password = ""
    @State private var fileError: String?
    @State private var isSigning = false
    @AppStorage("VectorPDF_SigningCertificate") private var lastCertificate = ""
    @AppStorage("VectorPDF_SigningReason") private var reason = ""
    @AppStorage("VectorPDF_SigningLocation") private var location = ""
    @AppStorage("VectorPDF_SigningShowsHandwriting") private var showsHandwriting = true

    private var choices: [SigningIdentity] { (fileIdentity.map { [$0] } ?? []) + identities }
    private var chosen: SigningIdentity? { choices.first { $0.id == selection } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Sign with Certificate")
                .font(.headline)
                .padding([.horizontal, .top], 20)
            Form {
                Section {
                    if isLoading {
                        ProgressView().controlSize(.small)
                    } else if choices.isEmpty {
                        Text("There are no certificates for signing in your keychain. Choose a certificate file (.p12 or .pfx), such as one your organization or a certificate authority gave you.")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Picker("Certificate", selection: $selection) {
                            ForEach(choices) { identity in
                                Text(identity.name + (identity.issuer.map { " (\($0))" } ?? "")).tag(Optional(identity.id))
                            }
                        }
                        if let chosen {
                            Text(details(of: chosen))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let pendingFile {
                        HStack {
                            SecureField("Password for “\(pendingFile.name)”", text: $password)
                                .onSubmit(openFile)
                            Button("Open", action: openFile)
                                .disabled(password.isEmpty)
                        }
                        if let fileError {
                            Text(fileError).font(.callout).foregroundStyle(.red)
                        }
                    }
                    Button("Choose Certificate File…", action: chooseFile)
                }
                Section {
                    TextField("Reason", text: $reason, prompt: Text("Optional, such as “I approve this document”"))
                    TextField("Location", text: $location, prompt: Text("Optional"))
                    if placement.rect.width > 0, signatureStore.savedSignatureData != nil {
                        Toggle("Show my handwritten signature", isOn: $showsHandwriting)
                    }
                } footer: {
                    Text("Signing saves the document. Anyone can then check that it hasn't changed since, and who signed it.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Sign", action: sign)
                    .keyboardShortcut(.defaultAction)
                    .disabled(chosen == nil || isSigning)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 500)
        .task {
            let found = await Task.detached(priority: .userInitiated) { SigningIdentity.keychainIdentities() }.value
            identities = found
            isLoading = false
            if selection == nil {
                selection = found.first { $0.id.base64EncodedString() == lastCertificate }?.id ?? found.first?.id
            }
        }
    }

    private func details(of identity: SigningIdentity) -> String {
        var parts: [String] = []
        if let email = identity.email { parts.append(email) }
        if let organization = identity.organization { parts.append(organization) }
        if let expires = identity.expires { parts.append("expires \(expires.formatted(date: .abbreviated, time: .omitted))") }
        return parts.joined(separator: " · ")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "p12"), UTType(filenameExtension: "pfx")].compactMap { $0 }
        panel.message = "Choose a certificate file with its private key (.p12 or .pfx)."
        guard panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) else { return }
        pendingFile = (url.lastPathComponent, data)
        password = ""
        fileError = nil
    }

    private func openFile() {
        guard let pendingFile else { return }
        do {
            let identity = try SigningIdentity.fromPKCS12(pendingFile.data, password: password)
            guard identity.canSign else {
                fileError = "This certificate can't be used to sign: it has expired, or isn't for signing."
                return
            }
            fileIdentity = identity
            selection = identity.id
            self.pendingFile = nil
            password = ""
        } catch {
            fileError = error.localizedDescription
        }
    }

    private func sign() {
        guard let identity = chosen else { return }
        isSigning = true
        if identity.id != fileIdentity?.id { lastCertificate = identity.id.base64EncodedString() }
        let trimmed = { (s: String) -> String? in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let graphic = placement.rect.width > 0 && showsHandwriting ? signatureStore.savedSignatureData : nil
        let appearance = PDFDocumentCore.SignatureAppearance(reason: trimmed(reason), location: trimmed(location), graphic: graphic)
        dismiss()
        Task { await viewModel.completeCertificateSignature(placement, with: identity, appearance: appearance) }
    }
}
