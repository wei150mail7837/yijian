import AppKit

// CLI 自检模式：无 GUI 跑 OCR / 翻译，供构建门禁使用
let args = CommandLine.arguments
if let index = args.firstIndex(of: "--selftest-ocr"), args.count > index + 1 {
    let file = URL(fileURLWithPath: args[index + 1])
    VisionOCR.recognize(fileURL: file) { result in
        switch result {
        case .success(let text):
            print("OCR_RESULT:\(text)")
            exit(text.isEmpty ? 1 : 0)
        case .failure(let error):
            print("OCR_FAIL:\(error.localizedDescription)")
            exit(1)
        }
    }
    dispatchMain()
}
if let index = args.firstIndex(of: "--selftest-translate"), args.count > index + 1 {
    OllamaClient.shared.translate(text: args[index + 1], onDelta: { _ in }, onDone: { result in
        switch result {
        case .success(let text):
            print("TRANSLATE_RESULT:\(text)")
            exit(text.isEmpty ? 1 : 0)
        case .failure(let error):
            print("TRANSLATE_FAIL:\(error.localizedDescription)")
            exit(1)
        }
    })
    dispatchMain()
}

// 正常 GUI 启动
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
