import Foundation
import Vision
import ImageIO

// Offline Apple Vision OCR. Input/output are a private manifest and JSONL.
// Never reconstruct wire connectivity from text coordinates.
let args = CommandLine.arguments
if args.count != 3 { fatalError("usage: ocr_manual_pages input.json output.jsonl") }
let specs = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: args[1]))) as! [[String: Any]]
FileManager.default.createFile(atPath: args[2], contents: nil)
let output = try FileHandle(forWritingTo: URL(fileURLWithPath: args[2]))
let probe = VNRecognizeTextRequest()
probe.recognitionLevel = .accurate
let supported = try probe.supportedRecognitionLanguages()
let languages = ["ko-KR", "en-US"].filter { supported.contains($0) }
guard languages.contains("ko-KR") else { fatalError("Korean OCR unavailable") }
for (index, spec) in specs.enumerated() {
  try autoreleasepool {
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = languages
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.002
    let handler = VNImageRequestHandler(url: URL(fileURLWithPath: spec["path"] as! String), options: [:])
    try handler.perform([request])
    let lines: [[String: Any]] = (request.results ?? []).compactMap { item in
      guard let text = item.topCandidates(1).first else { return nil }
      let b = item.boundingBox
      return ["text": text.string, "confidence": text.confidence,
        "box": [b.minX, b.minY, b.width, b.height]]
    }
    let row: [String: Any] = ["page": spec["page"]!, "lines": lines,
      "text": lines.map { $0["text"] as! String }.joined(separator: "\n")]
    var bytes = try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
    bytes.append(0x0a)
    try output.write(contentsOf: bytes)
    try output.synchronize()
  }
  if (index + 1) % 25 == 0 { print("OCR pages \(index + 1)/\(specs.count)"); fflush(stdout) }
}
try output.close()
