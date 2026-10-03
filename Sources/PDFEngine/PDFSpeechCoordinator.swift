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
import AVFoundation

/// Coordinates on-device Text-to-Speech using macOS native speech synthesis for reading
/// selected passages and document sections aloud.
@MainActor
public final class PDFSpeechCoordinator: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    public static let shared = PDFSpeechCoordinator()

    private var synthesizer: AVSpeechSynthesizer?
    @Published public private(set) var isSpeaking: Bool = false

    private override init() {
        super.init()
    }

    public func startSpeaking(_ text: String) {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }

        if synthesizer == nil {
            let synth = AVSpeechSynthesizer()
            synth.delegate = self
            synthesizer = synth
        }

        stopSpeaking()
        isSpeaking = true

        let utterance = AVSpeechUtterance(string: clean)
        synthesizer?.speak(utterance)
    }

    public func stopSpeaking() {
        if synthesizer?.isSpeaking == true {
            synthesizer?.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    public func toggleSpeaking(_ text: String) {
        if isSpeaking {
            stopSpeaking()
        } else {
            startSpeaking(text)
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated public func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
