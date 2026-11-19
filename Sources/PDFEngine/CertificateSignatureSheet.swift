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
    @AppStorage("VectorPDF_SigningTimestamp") private var addsTimestamp = false
    @AppStorage("VectorPDF_SigningTimestampServer") private var timestampServer = "http://timestamp.digicert.com"
    /// Certifying (only a first signature can) and locking fields.
    @State private var certification: PDFDocumentCore.SigningPermissions.Certification?
    private enum LockChoice: Hashable { case none, all, chosen }
    @State private var lockChoice = LockChoice.none
    @State private var lockable: [String] = []
    @State private var chosenFields = Set<String>()
    private var canCertify: Bool { viewModel.documentContentsSummary.signatureCount == 0 }
    @State private var previewImage: CGImage?

    private struct PreviewKey: Equatable {
        var name: String, reason: String, location: String, handwriting: Bool
    }

    private var timestampServerIsValid: Bool {
        guard let url = URL(string: timestampServer.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return (url.scheme == "http" || url.scheme == "https") && url.host != nil
    }

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
                    if let previewImage {
                        HStack {
                            Spacer()
                            Image(decorative: previewImage, scale: 2)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: 320, maxHeight: 120)
                                .background(Color.white)
                                .overlay(Rectangle().stroke(Color.secondary.opacity(0.4), lineWidth: 0.5))
                            Spacer()
                        }
                    }
                    TextField("Reason", text: $reason, prompt: Text("Optional, such as “I approve this document”"))
                    TextField("Location", text: $location, prompt: Text("Optional"))
                    if placement.rect.width > 0, signatureStore.savedSignatureData != nil {
                        Toggle("Show my handwritten signature", isOn: $showsHandwriting)
                    }
                }
                Section {
                    Toggle("Add a timestamp", isOn: $addsTimestamp)
                    if addsTimestamp {
                        TextField("Timestamp server", text: $timestampServer, prompt: Text("http://timestamp.digicert.com"))
                    }
                } footer: {
                    Text("A timestamp server vouches for when you signed, so the signature can be checked after your certificate expires. It's sent a fingerprint of the signature, nothing of the document.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if canCertify || !lockable.isEmpty {
                    Section("After Signing") {
                        if canCertify {
                            Picker("Certify", selection: $certification) {
                                Text("Don't certify").tag(PDFDocumentCore.SigningPermissions.Certification?.none)
                                Text("Allow form filling, signing and comments").tag(Optional(PDFDocumentCore.SigningPermissions.Certification.formFillingSigningAndComments))
                                Text("Allow form filling and signing").tag(Optional(PDFDocumentCore.SigningPermissions.Certification.formFillingAndSigning))
                                Text("Allow no changes").tag(Optional(PDFDocumentCore.SigningPermissions.Certification.noChanges))
                            }
                            .help("Certifying says which changes keep the document valid. Only the first signature can certify.")
                        }
                        if !lockable.isEmpty {
                            Picker("Lock form fields", selection: $lockChoice) {
                                Text("None").tag(LockChoice.none)
                                Text("All").tag(LockChoice.all)
                                Text("Choose…").tag(LockChoice.chosen)
                            }
                            if lockChoice == .chosen {
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(lockable, id: \.self) { name in
                                            Toggle(name, isOn: Binding(
                                                get: { chosenFields.contains(name) },
                                                set: { if $0 { chosenFields.insert(name) } else { chosenFields.remove(name) } }
                                            ))
                                            .toggleStyle(.checkbox)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(height: 110)
                            }
                        }
                    }
                }
                Section {
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
                    .disabled(chosen == nil || isSigning || (addsTimestamp && !timestampServerIsValid))
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 500)
        .task(id: PreviewKey(name: chosen?.name ?? "", reason: reason, location: location, handwriting: showsHandwriting)) {
            guard let doc = viewModel.document, let name = chosen?.name else { previewImage = nil; return }
            previewImage = doc.signaturePreview(size: placement.rect.size, scale: 2, name: name, appearance: appearance())
        }
        .task {
            let found = await Task.detached(priority: .userInitiated) { SigningIdentity.keychainIdentities() }.value
            identities = found
            isLoading = false
            lockable = viewModel.lockableFormFieldNames()
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

    /// What the field will show, as chosen so far.
    private func appearance() -> PDFDocumentCore.SignatureAppearance {
        let trimmed = { (s: String) -> String? in
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let graphic = placement.rect.width > 0 && showsHandwriting ? signatureStore.savedSignatureData : nil
        return PDFDocumentCore.SignatureAppearance(reason: trimmed(reason), location: trimmed(location), graphic: graphic)
    }

    private func sign() {
        guard let identity = chosen else { return }
        isSigning = true
        if identity.id != fileIdentity?.id { lastCertificate = identity.id.base64EncodedString() }
        let appearance = appearance()
        let lock: PDFDocumentCore.SigningPermissions.FieldLock
        switch lockChoice {
        case .none: lock = .none
        case .all: lock = .all
        case .chosen: lock = chosenFields.isEmpty ? .none : .fields(lockable.filter(chosenFields.contains))
        }
        let permissions = PDFDocumentCore.SigningPermissions(certification: canCertify ? certification : nil, lock: lock)
        let server = timestampServer.trimmingCharacters(in: .whitespacesAndNewlines)
        let timestamp = addsTimestamp ? URL(string: server).flatMap { $0.scheme?.hasPrefix("http") == true ? TimestampAuthority(url: $0) : nil } : nil
        dismiss()
        Task { await viewModel.completeCertificateSignature(placement, with: identity, appearance: appearance, permissions: permissions, timestamp: timestamp) }
    }
}
