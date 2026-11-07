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

/// Settings > LaTeX: one row, since most people don't write LaTeX, saying which editor is chosen;
/// Set Up… opens the rest (`LaTeXSetupView`).
struct LaTeXSettingsView: View {
    @AppStorage(EditorLauncher.editorDefaultsKey) private var editorID = ""
    @State private var isShowingSetup = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("LaTeX (SyncTeX)")
                Text(LaTeXEditor.preset(id: editorID).map { "Source editor: \($0.name)" } ?? "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Set Up…") { isShowingSetup = true }
                .controlSize(.small)
        }
        .sheet(isPresented: $isShowingSetup) {
            LaTeXSetupView()
        }
    }
}

/// The editor ⇧⌘-click opens source in, and the `displayline` command editors run to show a line
/// in VectorPDF.
struct LaTeXSetupView: View {
    @AppStorage(EditorLauncher.editorDefaultsKey) private var editorID = ""
    @AppStorage(EditorLauncher.customCommandDefaultsKey) private var customCommand = ""
    @State private var programStatus: String?
    @Environment(\.dismiss) private var dismiss

    /// Where `displayline` is in this copy of the app.
    static var displaylinePath: String {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/displayline").path
    }

    private var command: String? {
        guard let editor = LaTeXEditor.preset(id: editorID) else { return nil }
        return editor == .custom ? customCommand : editor.command
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LaTeX (SyncTeX)")
                .font(.headline)
            Text("For PDFs built by TeX with SyncTeX on (-synctex=1): jump between a line of source and what it made.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 4)

            Picker("Source Editor", selection: $editorID) {
                Text("None").tag("")
                Divider()
                ForEach(LaTeXEditor.presets) { editor in
                    Text(editor.name).tag(editor.id)
                }
                Divider()
                Text(LaTeXEditor.custom.name).tag(LaTeXEditor.custom.id)
            }
            .pickerStyle(.menu)

            if editorID == LaTeXEditor.custom.id {
                TextField("Command", text: $customCommand, prompt: Text("editor +%line %file"))
                    .font(.system(.body, design: .monospaced))
                Text("%file, %line and %column stand for the place to open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let command {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let programStatus {
                Text(programStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("⇧⌘-click a PDF built with SyncTeX to open its source here. To show a line of source in VectorPDF, have your editor run:")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            HStack(alignment: .firstTextBaseline) {
                Text("\(Self.displaylinePath) %line %pdf %tex")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(Self.displaylinePath, forType: .string)
                }
                .controlSize(.small)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .frame(width: 520)
        .task(id: command ?? "") {
            await checkProgram()
        }
    }

    /// Says whether the chosen editor's program can be found, so a missing command-line tool
    /// shows up here rather than on the first ⇧⌘-click.
    private func checkProgram() async {
        guard let command, !command.isEmpty else {
            programStatus = editorID == LaTeXEditor.custom.id ? "Enter the command to run." : nil
            return
        }
        let known = LaTeXEditor.preset(id: editorID)?.knownLocations ?? []
        let status: String = await Task.detached {
            guard let words = try? EditorLauncher.split(command), let program = words.first else {
                return "The command has a quote that isn't closed."
            }
            if let found = EditorLauncher.resolve(program: program, knownLocations: known, searchPath: EditorLauncher.loginShellPath) {
                return "Uses \(found)"
            }
            return "“\(program)” wasn't found. Install the editor's command-line tool, or give its full path (choose Other)."
        }.value
        programStatus = status
    }
}
