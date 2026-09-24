import Foundation
import CoreGraphics
import Vision

/// Represents a single recognized line of text from Vision OCR with its PDF-space bounding geometry.
public struct PDFOCRLine: Sendable, Codable, Equatable {
    public let text: String
    public let confidence: Float
    public let boundingBox: CGRect // In native PDF point coordinates (top-down or matching pageBounds)

    public init(text: String, confidence: Float, boundingBox: CGRect) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

/// Results of running OCR on a single scanned PDF page.
public struct PDFOCRPageResult: Sendable, Codable, Equatable {
    public let pageIndex: Int
    public let lines: [PDFOCRLine]
    public let fullText: String

    public init(pageIndex: Int, lines: [PDFOCRLine], fullText: String) {
        self.pageIndex = pageIndex
        self.lines = lines
        self.fullText = fullText
    }
}

/// High-performance on-device OCR pipeline leveraging Apple's Vision framework and Apple Silicon Neural Engine.
public actor PDFOCREngine {
    public static let shared = PDFOCREngine()

    public init() {}

    /// Performs on-device text recognition on a rendered page image, mapping Vision's normalized
    /// coordinates to the page's native point bounds.
    public func recognizeText(
        in image: CGImage,
        pageIndex: Int,
        pageBounds: CGRect,
        languages: [String] = ["en-US"]
    ) async throws -> PDFOCRPageResult {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: PDFOCRPageResult(pageIndex: pageIndex, lines: [], fullText: ""))
                    return
                }

                var ocrLines: [PDFOCRLine] = []
                var fullTextParts: [String] = []

                let width = pageBounds.width
                let height = pageBounds.height

                for obs in observations {
                    guard let candidate = obs.topCandidates(1).first else { continue }
                    let str = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !str.isEmpty else { continue }

                    // Vision coordinates: (0,0) is bottom-left, normalized 0.0...1.0.
                    // Convert to PDF top-down coordinate space:
                    // x = obs.boundingBox.minX * width + pageBounds.minX
                    // y = (1.0 - obs.boundingBox.maxY) * height + pageBounds.minY
                    let box = obs.boundingBox
                    let pdfX = pageBounds.minX + box.minX * width
                    let pdfY = pageBounds.minY + (1.0 - box.maxY) * height
                    let pdfW = box.width * width
                    let pdfH = box.height * height

                    let lineRect = CGRect(x: pdfX, y: pdfY, width: pdfW, height: pdfH)
                    ocrLines.append(PDFOCRLine(text: str, confidence: candidate.confidence, boundingBox: lineRect))
                    fullTextParts.append(str)
                }

                let fullText = fullTextParts.joined(separator: "\n")
                continuation.resume(returning: PDFOCRPageResult(pageIndex: pageIndex, lines: ocrLines, fullText: fullText))
            }

            request.recognitionLevel = .accurate
            request.recognitionLanguages = languages

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
