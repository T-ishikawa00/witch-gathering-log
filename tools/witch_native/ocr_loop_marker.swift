import Foundation
import Vision

// Read-only QA OCR. Recognition is evidence to inspect, never art approval.
var results: [[String: Any]] = []
for path in CommandLine.arguments.dropFirst() {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    do {
        try VNImageRequestHandler(url: URL(fileURLWithPath: path), options: [:]).perform([request])
        results.append(["path": path, "text": (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")])
    } catch { results.append(["path": path, "error": String(describing: error)]) }
}
let data = try JSONSerialization.data(withJSONObject: results, options: [.sortedKeys])
if let text = String(data: data, encoding: .utf8) { print(text) }
