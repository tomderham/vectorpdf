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
