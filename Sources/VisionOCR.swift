import AppKit
import Vision

/// macOS Vision 离线 OCR（进程内调用，无网络、无子进程）
enum VisionOCR {
    struct Line {
        let text: String
        let y: CGFloat
    }

    /// 识别图片文件，按行输出（自上而下）
    static func recognize(fileURL: URL, completion: @escaping (Result<String, Error>) -> Void) {
        guard let image = NSImage(contentsOf: fileURL),
              var cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(NSError(domain: "ocr", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法读取图片"])))
            return
        }
        // 超大图等比缩到 2000px 以内，加速识别
        let maxSide = max(cg.width, cg.height)
        if maxSide > 2000 {
            let scale = 2000.0 / CGFloat(maxSide)
            let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            cg = ctx.makeImage()!
        }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                let lines: [Line] = (request.results ?? []).compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    return Line(text: top.string, y: 1 - obs.boundingBox.origin.y)
                }
                let text = lines.sorted { $0.y > $1.y }.map(\.text).joined(separator: "\n")
                DispatchQueue.main.async { completion(.success(text)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }
}
