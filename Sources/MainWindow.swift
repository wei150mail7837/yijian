import AppKit

/// 主窗口：上输入框（含语种栏）下译文结果，复刻 TTime 双栏交互
final class MainWindow: NSWindow, NSTextViewDelegate {
    static let shared = MainWindow()

    private let langPop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let inputView = NSTextView()
    private let resultView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "复制", target: nil, action: nil)
    private let pinButton = NSButton(title: "📌", target: nil, action: nil)
    private var pinned = false
    private var lastFullResult = ""
    private var currentJob: Int = 0

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                   styleMask: [.titled, .closable, .resizable, .miniaturizable],
                   backing: .buffered, defer: false)
        title = "TTime Native"
        isReleasedWhenClosed = false
        center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 380))
        contentView = content

        // 语种栏（自动方向：中→英，其他→中）
        langPop.addItems(withTitles: ["自动方向", "中 → 英", "英 → 中"])
        langPop.frame = NSRect(x: 12, y: 340, width: 130, height: 26)
        langPop.autoresizingMask = [.maxXMargin]
        content.addSubview(langPop)

        pinButton.bezelStyle = .texturedRounded
        pinButton.frame = NSRect(x: 380, y: 340, width: 40, height: 26)
        pinButton.autoresizingMask = [.minXMargin]
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        content.addSubview(pinButton)

        copyButton.bezelStyle = .texturedRounded
        copyButton.frame = NSRect(x: 424, y: 340, width: 44, height: 26)
        copyButton.autoresizingMask = [.minXMargin]
        copyButton.target = self
        copyButton.action = #selector(copyResult)
        content.addSubview(copyButton)

        // 输入区
        let inputScroll = NSScrollView(frame: NSRect(x: 12, y: 250, width: 456, height: 82))
        inputScroll.autoresizingMask = [.width]
        inputScroll.hasVerticalScroller = true
        inputScroll.borderType = .bezelBorder
        inputView.frame = NSRect(x: 0, y: 0, width: 456, height: 82)
        inputView.font = NSFont.systemFont(ofSize: 14)
        inputView.delegate = self
        inputView.isRichText = false
        inputScroll.documentView = inputView
        content.addSubview(inputScroll)

        // 状态行
        statusLabel.frame = NSRect(x: 12, y: 226, width: 456, height: 18)
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.autoresizingMask = [.width]
        content.addSubview(statusLabel)

        // 结果区
        let resultScroll = NSScrollView(frame: NSRect(x: 12, y: 36, width: 456, height: 184))
        resultScroll.frame.origin.y = 36
        resultScroll.autoresizingMask = [.width, .height]
        resultScroll.hasVerticalScroller = true
        resultScroll.borderType = .bezelBorder
        resultView.frame = NSRect(x: 0, y: 0, width: 456, height: 184)
        resultView.font = NSFont.systemFont(ofSize: 14)
        resultView.isEditable = false
        resultView.isRichText = false
        resultScroll.documentView = resultView
        content.addSubview(resultScroll)

        // Esc 隐藏
        NSApp.addMonitorIfNeeded(self)
    }

    // MARK: - 动作

    func showForInput(_ text: String?) {
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let text, !text.isEmpty {
            inputView.string = text
            startTranslate()
        } else {
            inputView.becomeFirstResponder()
        }
    }

    func startTranslate() {
        let text = inputView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        currentJob += 1
        resultView.string = ""
        lastFullResult = ""
        statusLabel.stringValue = "翻译中…"
        let job = currentJob
        OllamaClient.shared.translate(text: text, onDelta: { [weak self] piece in
            DispatchQueue.main.async {
                guard let self, job == self.currentJob else { return }
                self.lastFullResult += piece
                self.resultView.string = self.lastFullResult
                self.resultView.scrollToEndOfDocument(nil)
            }
        }, onDone: { [weak self] result in
            DispatchQueue.main.async {
                guard let self, job == self.currentJob else { return }
                switch result {
                case .success(let full):
                    self.lastFullResult = full
                    self.resultView.string = full
                    self.statusLabel.stringValue = "完成 · \(full.count) 字符"
                    log("[翻译] 完成 长度=\(full.count)")
                case .failure(let error):
                    self.statusLabel.stringValue = "失败：\(error.localizedDescription)"
                    log("[翻译] 失败")
                }
            }
        })
        log("[翻译] 开始 长度=\(text.count)")
    }

    @objc private func togglePin() {
        pinned.toggle()
        pinButton.contentTintColor = pinned ? .systemBlue : .secondaryLabelColor
        level = pinned ? .floating : .normal
    }

    func showErrorMessage(_ message: String) {
        makeKeyAndOrderFront(nil)
        statusLabel.stringValue = "失败：\(message)"
    }

    @objc private func copyResult() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(lastFullResult, forType: .string)
        statusLabel.stringValue = "已复制"
    }

    // MARK: - NSTextViewDelegate：输入回车即翻译（Shift+回车换行）

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(insertNewline(_:)),
           !NSEvent.modifierFlags.contains(.shift) {
            startTranslate()
            return true
        }
        return false
    }
}

/// Esc 隐藏窗口的事件监视器（主/OCR 窗口共用）
enum EscMonitor {
    private static var monitor: Any?
    private static var targets = NSHashTable<NSWindow>.weakObjects()

    static func add(_ window: NSWindow) {
        targets.add(window)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53, let keyWindow = NSApp.keyWindow, targets.contains(keyWindow) {
                keyWindow.orderOut(nil)
                return nil
            }
            return event
        }
    }
}

private extension NSApplication {
    func addMonitorIfNeeded(_ window: NSWindow) {
        EscMonitor.add(window)
    }
}
