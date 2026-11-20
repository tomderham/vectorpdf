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
import Testing
@testable import PDFEngine

/// Settings floats and takes every click while it's open, except clicks on what it opens above
/// itself, such as Check Now's alerts and download window.
struct SettingsModalTests {

    @MainActor
    private func window(level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        window.level = level
        return window
    }

    @Test @MainActor
    func documentWindowsDontTakeClicksButWindowsAboveSettingsDo() {
        let settings = window(level: .floating)
        #expect(!SettingsModalManager.passesEvents(to: window(level: .normal), over: settings))
        #expect(SettingsModalManager.passesEvents(to: window(level: .floating), over: settings))
        #expect(SettingsModalManager.passesEvents(to: window(level: .modalPanel), over: settings))
    }
}
