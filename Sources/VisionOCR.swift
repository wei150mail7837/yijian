import AppKit
import Vision

/// macOS Vision 离线 OCR（进程内调用）。对齐 Lite 版 OcrResult.ts：
/// sortOcrLines（top 排序 + 垂直重叠>50% 同行 + 行内 left 排序）→ 段落合并 → 后处理链。
enum VisionOCR {
    /// 坐标为图片像素、左上原点
    struct Line {
        let text: String
        let confidence: Float
        let box: CGRect
    }

    struct Result {
        let width: Int
        let height: Int
        let lines: [Line]
        let allText: String
    }

    static func recognize(fileURL: URL, completion: @escaping (Swift.Result<String, Error>) -> Void) {
        recognizeDetailed(fileURL: fileURL) { completion($0.map(\.allText)) }
    }

    static func recognizeDetailed(fileURL: URL, completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        guard let image = NSImage(contentsOf: fileURL),
              var cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            completion(.failure(err("无法读取图片")))
            return
        }
        let maxSide = max(cg.width, cg.height)
        if maxSide > 2000 {
            let scale = 2000.0 / CGFloat(maxSide)
            let w = Int(CGFloat(cg.width) * scale), h = Int(CGFloat(cg.height) * scale)
            if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8,
                                   bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                ctx.interpolationQuality = .high
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
                if let scaled = ctx.makeImage() { cg = scaled }
            }
        }
        let W = CGFloat(cg.width), H = CGFloat(cg.height)
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = false
        let handler = VNImageRequestHandler(cgImage: cg, options: [:])
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try handler.perform([request])
                let raw: [Line] = (request.results ?? []).compactMap { obs in
                    guard let top = obs.topCandidates(1).first else { return nil }
                    let b = obs.boundingBox  // 归一化、左下原点 → 像素、左上原点
                    let rect = CGRect(x: b.minX * W, y: (1 - b.maxY) * H, width: b.width * W, height: b.height * H)
                    return Line(text: top.string, confidence: top.confidence, box: rect)
                }
                let sorted = sortLines(raw)
                let merge = UserDefaults.standard.object(forKey: "localOcrMergeParagraphs") as? Bool ?? true
                let text = postProcess(merge ? mergeParagraphs(sorted) : sorted.map(\.text).joined(separator: "\n"))
                let r = Result(width: Int(W), height: Int(H), lines: sorted, allText: text)
                DispatchQueue.main.async { completion(.success(r)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(err("Vision OCR 失败：\(error.localizedDescription)"))) }
            }
        }
    }

    private static func err(_ s: String) -> NSError {
        NSError(domain: "ocr", code: -1, userInfo: [NSLocalizedDescriptionKey: s])
    }

    /// sortOcrLines：按 top 排序，与当前行首块垂直重叠 > 50%（以较矮者计）归同一行，行内按 left 排序
    static func sortLines(_ lines: [Line]) -> [Line] {
        let byTop = lines.sorted { $0.box.minY < $1.box.minY }
        var rows: [[Line]] = []
        for l in byTop {
            if let ref = rows.last?.first {
                let overlap = min(ref.box.maxY, l.box.maxY) - max(ref.box.minY, l.box.minY)
                if overlap > 0.5 * min(ref.box.height, l.box.height) {
                    rows[rows.count - 1].append(l); continue
                }
            }
            rows.append([l])
        }
        return rows.flatMap { $0.sorted { $0.box.minX < $1.box.minX } }
    }

    private static func isCJK(_ c: Character?) -> Bool {
        guard let s = c?.unicodeScalars.first?.value else { return false }
        return (0x3000...0x9FFF).contains(s) || (0xAC00...0xD7AF).contains(s) || (0xFF00...0xFFEF).contains(s)
    }

    /// joinText：CJK 相邻直接拼接，西文补空格
    static func joinText(_ a: String, _ b: String) -> String {
        if a.isEmpty { return b }
        if isCJK(a.last) || isCJK(b.first) { return a + b }
        return a + " " + b
    }

    private static func isListStart(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let f = t.first, "-•●▪".contains(f) { return true }
        return t.range(of: #"^\d+[.、)]"#, options: .regularExpression) != nil
    }

    /// localOcrMergeParagraphs：同行水平间距<size*1.5，或下一行左对齐(<size*1.5)+垂直间距<size*0.7+字号相近(<1.4x)+非列表起始
    /// （Vision 返回的行框为轴对齐矩形，旋转判定无从获得，故省略）
    static func mergeParagraphs(_ lines: [Line]) -> String {
        var paras: [String] = []
        var cur = ""
        var prev: Line?
        var paraLeft: CGFloat = 0
        for l in lines {
            guard let p = prev else { cur = l.text; prev = l; paraLeft = l.box.minX; continue }
            let size = max(min(p.box.height, l.box.height), 1)
            let ratio = max(p.box.height, l.box.height) / size
            let sameRow = abs(l.box.midY - p.box.midY) < size * 0.5
            let join: Bool
            if sameRow {
                join = l.box.minX - p.box.maxX < size * 1.5
            } else {
                join = abs(l.box.minX - paraLeft) < size * 1.5
                    && l.box.minY - p.box.maxY < size * 0.7
                    && ratio < 1.4 && !isListStart(l.text)
            }
            if join { cur = joinText(cur, l.text) } else { paras.append(cur); cur = l.text; paraLeft = l.box.minX }
            prev = l
        }
        if prev != nil { paras.append(cur) }
        return paras.joined(separator: "\n")
    }

    /// 后处理链：换行替换空格 → 换行删除 → 写剪贴板 → 首尾空行剔除（三项默认 N）
    static func postProcess(_ text: String) -> String {
        let d = UserDefaults.standard
        var t = text
        if d.bool(forKey: "ocrWrapReplaceSpaceStatus") { t = t.replacingOccurrences(of: "\n", with: " ") }
        if d.bool(forKey: "ocrWrapReplaceStatus") { t = t.replacingOccurrences(of: "\n", with: "") }
        if d.bool(forKey: "ocrWriteClipboardStatus") {
            let s = t
            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(s, forType: .string)
            }
        }
        return t.trimmingCharacters(in: .newlines)
    }
}
