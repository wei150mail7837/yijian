import AppKit

/// 截图 OCR 窗口：图片预览 + 识别文本 + 复制
final class OCRWindow: NSWindow {
    static let shared = OCRWindow()

    private let imageView = NSImageView()
    private let textView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                   styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "截图 OCR"
        isReleasedWhenClosed = false
        center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 520))
        contentView = content

        let imageScroll = NSScrollView(frame: NSRect(x: 12, y: 330, width: 496, height: 160))
        imageScroll.autoresizingMask = [.width]
        imageScroll.borderType = .bezelBorder
        imageView.frame = NSRect(x: 0, y: 0, width: 496, height: 160)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageScroll.documentView = imageView
        content.addSubview(imageScroll)

        let copyButton = NSButton(title: "复制文本", target: self, action: #selector(copyText))
        copyButton.bezelStyle = .texturedRounded
        copyButton.frame = NSRect(x: 12, y: 296, width: 90, height: 26)
        copyButton.autoresizingMask = [.width]
        content.addSubview(copyButton)

        statusLabel.frame = NSRect(x: 112, y: 300, width: 396, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.autoresizingMask = [.width]
        content.addSubview(statusLabel)

        let textScroll = NSScrollView(frame: NSRect(x: 12, y: 36, width: 496, height: 250))
        textScroll.autoresizingMask = [.width, .height]
        textScroll.hasVerticalScroller = true
        textScroll.borderType = .bezelBorder
        textView.frame = NSRect(x: 0, y: 0, width: 496, height: 250)
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.isEditable = false
        textView.isRichText = false
        textScroll.documentView = textView
        content.addSubview(textScroll)

        EscMonitor.add(self)
    }

    func run(imageFile: URL) {
        imageView.image = NSImage(contentsOf: imageFile)
        textView.string = ""
        statusLabel.stringValue = "识别中…"
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        VisionOCR.recognize(fileURL: imageFile) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let text):
                self.textView.string = text
                self.statusLabel.stringValue = text.isEmpty ? "未识别到文字" : "识别 \(text.count) 字符"
                log("[OCR] 完成 长度=\(text.count)")
            case .failure(let error):
                self.statusLabel.stringValue = "失败：\(error.localizedDescription)"
                log("[OCR] 失败")
            }
        }
    }

    @objc private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(textView.string, forType: .string)
        statusLabel.stringValue = "已复制"
    }
}
