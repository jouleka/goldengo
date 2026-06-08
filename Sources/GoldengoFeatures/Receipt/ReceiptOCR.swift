import Foundation
import Vision
import CoreGraphics
import GoldengoCore

/// On-device OCR: a receipt page image → recognized text lines with positions.
/// Vision processes entirely on-device. Synchronous + `nonisolated` so callers run it off the
/// main actor (e.g. via `Task.detached`).
public enum ReceiptOCR {
    public static func recognizeLines(in cgImage: CGImage) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        return (request.results ?? []).compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return RecognizedLine(text: text, boundingBox: obs.boundingBox)
        }
    }
}
