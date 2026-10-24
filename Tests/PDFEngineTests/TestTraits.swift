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
import Foundation
import Testing

extension Trait where Self == ConditionTrait {
    /// For tests that put real windows on screen (window, tab, and click handling). They take
    /// focus and flash windows, so they only run with `VECTORPDF_UI_TESTS=1 swift test`.
    static var showsWindows: Self {
        .enabled(if: ProcessInfo.processInfo.environment["VECTORPDF_UI_TESTS"] == "1",
                 "Shows windows; run with VECTORPDF_UI_TESTS=1")
    }
}

/// End of a test view's responder chain. Keys a view deliberately ignores would otherwise reach
/// the top of the chain unhandled, and AppKit beeps.
final class KeySinkResponder: NSResponder {
    override func keyDown(with event: NSEvent) {}
}
