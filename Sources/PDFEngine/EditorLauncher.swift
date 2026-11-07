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

/// A text editor SyncTeX's backward search can open a source file in, at a line.
public struct LaTeXEditor: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// The command, with `%file`, `%line` and `%column` standing for the place to open. Split into
    /// arguments like a shell would (quotes group), but never run through one.
    public let command: String
    /// Where the program usually is when it isn't on PATH, such as inside its app.
    public let knownLocations: [String]

    public static let custom = LaTeXEditor(id: "custom", name: "Other", command: "", knownLocations: [])

    public static let presets: [LaTeXEditor] = [
        LaTeXEditor(id: "vscode", name: "Visual Studio Code", command: "code --goto %file:%line",
                    knownLocations: ["/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"]),
        LaTeXEditor(id: "vscodium", name: "VSCodium", command: "codium --goto %file:%line",
                    knownLocations: ["/Applications/VSCodium.app/Contents/Resources/app/bin/codium"]),
        LaTeXEditor(id: "cursor", name: "Cursor", command: "cursor --goto %file:%line",
                    knownLocations: ["/Applications/Cursor.app/Contents/Resources/app/bin/cursor"]),
        LaTeXEditor(id: "zed", name: "Zed", command: "zed %file:%line",
                    knownLocations: ["/Applications/Zed.app/Contents/MacOS/cli"]),
        LaTeXEditor(id: "sublime", name: "Sublime Text", command: "subl %file:%line",
                    knownLocations: ["/Applications/Sublime Text.app/Contents/SharedSupport/bin/subl"]),
        LaTeXEditor(id: "bbedit", name: "BBEdit", command: "bbedit +%line %file",
                    knownLocations: ["/Applications/BBEdit.app/Contents/Helpers/bbedit_tool"]),
        LaTeXEditor(id: "textmate", name: "TextMate", command: "mate --line %line %file",
                    knownLocations: ["/Applications/TextMate.app/Contents/MacOS/mate",
                                     "/Applications/TextMate.app/Contents/Resources/mate"]),
        LaTeXEditor(id: "macvim", name: "MacVim", command: "mvim --remote-silent +%line %file",
                    knownLocations: ["/Applications/MacVim.app/Contents/bin/mvim"]),
        LaTeXEditor(id: "emacs", name: "Emacs", command: "emacsclient --no-wait +%line %file",
                    knownLocations: ["/Applications/Emacs.app/Contents/MacOS/bin/emacsclient"]),
        LaTeXEditor(id: "texstudio", name: "TeXstudio", command: "texstudio --line %line %file",
                    knownLocations: ["/Applications/texstudio.app/Contents/MacOS/texstudio",
                                     "/Applications/TeXstudio.app/Contents/MacOS/texstudio"]),
    ]

    public static let all = presets + [custom]

    public static func preset(id: String) -> LaTeXEditor? {
        all.first { $0.id == id }
    }
}

/// Opens a source file at a line in the editor chosen in Settings.
public enum EditorLauncher {
    public static let editorDefaultsKey = "synctexEditor"
    public static let customCommandDefaultsKey = "synctexCustomEditorCommand"

    public enum LaunchError: LocalizedError, Equatable {
        case noEditorChosen
        case emptyCommand
        case unbalancedQuotes
        case programNotFound(String)
        case sourceNotFound(String)
        case couldNotStart(String)

        public var errorDescription: String? {
            switch self {
            case .noEditorChosen:
                return "Choose the editor to open source files in, in Settings ▸ LaTeX."
            case .emptyCommand:
                return "The editor command in Settings ▸ LaTeX is empty."
            case .unbalancedQuotes:
                return "The editor command in Settings ▸ LaTeX has a quote that isn't closed."
            case .programNotFound(let program):
                return "“\(program)” wasn't found. Install the editor's command-line tool, or give its full path in Settings ▸ LaTeX."
            case .sourceNotFound(let path):
                return "The source file “\((path as NSString).lastPathComponent)” isn't at \((path as NSString).deletingLastPathComponent)."
            case .couldNotStart(let reason):
                return "The editor couldn't be started: \(reason)"
            }
        }
    }

    /// The command for the editor chosen in Settings; nil if none is.
    public static func chosenCommand(defaults: UserDefaults = .standard) -> String? {
        guard let id = defaults.string(forKey: editorDefaultsKey), let editor = LaTeXEditor.preset(id: id) else { return nil }
        if editor == .custom { return defaults.string(forKey: customCommandDefaultsKey) ?? "" }
        return editor.command
    }

    /// The chosen editor's known locations, to look in when its program isn't on PATH.
    static func chosenKnownLocations(defaults: UserDefaults = .standard) -> [String] {
        defaults.string(forKey: editorDefaultsKey).flatMap(LaTeXEditor.preset(id:))?.knownLocations ?? []
    }

    /// `command` split into arguments as a shell would split it — on unquoted spaces, with single
    /// or double quotes grouping and a backslash escaping the next character outside single
    /// quotes — but nothing else a shell does: no variables, globs, pipes or `;`.
    public static func split(_ command: String) throws -> [String] {
        var words: [String] = []
        var current = ""
        var inWord = false
        var quote: Character?
        var escaping = false
        for character in command {
            if escaping {
                current.append(character)
                escaping = false
                inWord = true
                continue
            }
            if let open = quote {
                if character == open {
                    quote = nil
                } else if character == "\\" && open == "\"" {
                    escaping = true
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "\"", "'":
                quote = character
                inWord = true
            case "\\":
                escaping = true
            case " ", "\t", "\n":
                if inWord { words.append(current) }
                current = ""
                inWord = false
            default:
                current.append(character)
                inWord = true
            }
        }
        guard quote == nil, !escaping else { throw LaunchError.unbalancedQuotes }
        if inWord { words.append(current) }
        return words
    }

    /// The arguments to run for `location`: `command` split, then `%file`, `%line` and `%column`
    /// filled in within each argument, so a file name with spaces or quotes stays one argument.
    public static func arguments(for command: String, location: SyncTeXSourceLocation) throws -> [String] {
        let words = try split(command)
        guard !words.isEmpty else { throw LaunchError.emptyCommand }
        return words.map { word in
            word.replacingOccurrences(of: "%file", with: location.file)
                .replacingOccurrences(of: "%line", with: String(location.line))
                .replacingOccurrences(of: "%column", with: String(location.column ?? 0))
        }
    }

    /// Folders GUI apps don't have on PATH but command-line tools are usually installed in.
    static let commonFolders = ["/opt/homebrew/bin", "/usr/local/bin", "/Library/TeX/texbin", "/usr/bin", "/bin"]

    /// The program `name` names: itself if it's a path, else the first executable of that name in
    /// the common folders or the login shell's PATH, else the first of `knownLocations` there is
    /// (inside the editor's app, where it can have another name, such as Zed's `cli`).
    static func resolve(program name: String, knownLocations: [String], searchPath: [String]) -> String? {
        let fm = FileManager.default
        if name.contains("/") {
            let expanded = (name as NSString).expandingTildeInPath
            return fm.isExecutableFile(atPath: expanded) ? expanded : nil
        }
        let candidates = (commonFolders + searchPath).map { ($0 as NSString).appendingPathComponent(name) } + knownLocations
        return candidates.first { fm.isExecutableFile(atPath: $0) }
    }

    /// The login shell's PATH, read once: GUI apps start with a minimal one, without the folders
    /// a user's shell profile adds (Homebrew, TeX, ~/.local/bin).
    static let loginShellPath: [String] = {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-c", "printf %s \"$PATH\""]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return [] }
        let deadline = Date().addingTimeInterval(3)
        while process.isRunning && Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate(); return [] }
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return output.split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
    }()

    /// Opens `location` with `command` (the one chosen in Settings by default). Throws when there's
    /// no editor, the source file is missing, or the program can't be found or started; doesn't
    /// wait for the editor.
    public static func open(_ location: SyncTeXSourceLocation, command: String? = nil, knownLocations: [String]? = nil) throws {
        guard let command = command ?? chosenCommand() else { throw LaunchError.noEditorChosen }
        guard FileManager.default.fileExists(atPath: location.file) else { throw LaunchError.sourceNotFound(location.file) }
        var arguments = try arguments(for: command, location: location)
        let program = arguments.removeFirst()
        let searchPath = loginShellPath
        guard let executable = resolve(program: program, knownLocations: knownLocations ?? chosenKnownLocations(), searchPath: searchPath) else {
            throw LaunchError.programNotFound(program)
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        let path = (searchPath + commonFolders + (environment["PATH"].map { $0.split(separator: ":").map(String.init) } ?? []))
        var seen = Set<String>()
        environment["PATH"] = path.filter { seen.insert($0).inserted }.joined(separator: ":")
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.currentDirectoryURL = URL(fileURLWithPath: location.file).deletingLastPathComponent()
        do {
            try process.run()
        } catch {
            throw LaunchError.couldNotStart(error.localizedDescription)
        }
    }
}
