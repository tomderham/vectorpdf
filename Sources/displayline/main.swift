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

// displayline: SyncTeX forward search for VectorPDF, taking the same arguments as Skim's, so an
// editor set up for Skim works by pointing it here. It lives in VectorPDF.app/Contents/Helpers and
// hands the request to the app it's inside as a vectorpdf://synctex URL.

import AppKit
import Foundation
import SyncTeXLink

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("displayline: \(message)\n".utf8))
    exit(1)
}

let request: SyncTeXForwardRequest
switch SyncTeXForwardRequest.parseCommandLine(Array(CommandLine.arguments.dropFirst()),
                                             currentDirectory: FileManager.default.currentDirectoryPath) {
case .help:
    print(SyncTeXForwardRequest.usage)
    exit(0)
case .invalid(let message):
    fail("\(message)\n\(SyncTeXForwardRequest.usage)")
case .request(let parsed):
    request = parsed
}

guard FileManager.default.fileExists(atPath: request.pdfPath) else {
    fail("No such file: \(request.pdfPath)")
}

/// The app this tool is inside (…/VectorPDF.app/Contents/Helpers/displayline, perhaps through a
/// symlink on PATH), so the request goes to that copy rather than whichever claims the URL scheme;
/// nil when run from a build folder.
func enclosingApp() -> URL? {
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    var folder = executable.resolvingSymlinksInPath().deletingLastPathComponent()
    while folder.path != "/" {
        if folder.pathExtension == "app" { return folder }
        folder = folder.deletingLastPathComponent()
    }
    return nil
}

let configuration = NSWorkspace.OpenConfiguration()
configuration.activates = !request.inBackground
configuration.addsToRecentItems = false

/// The open's result, set once on NSWorkspace's queue before `done` is signalled.
final class Outcome: @unchecked Sendable { var error: Error? }
let outcome = Outcome()
let done = DispatchSemaphore(value: 0)
let completion: @Sendable (NSRunningApplication?, Error?) -> Void = { _, error in
    outcome.error = error
    done.signal()
}
if let app = enclosingApp() {
    NSWorkspace.shared.open([request.url], withApplicationAt: app, configuration: configuration, completionHandler: completion)
} else {
    NSWorkspace.shared.open(request.url, configuration: configuration, completionHandler: completion)
}
if done.wait(timeout: .now() + 30) == .timedOut {
    fail("VectorPDF didn't respond")
}
if let openError = outcome.error {
    fail("Couldn't reach VectorPDF: \(openError.localizedDescription)")
}
