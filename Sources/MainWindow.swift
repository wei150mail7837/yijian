import AppKit

/// 主窗口：上输入框（含语种栏）下译文结果，复刻 TTime 双栏交互
final class MainWindow: NSWindow, NSTextViewDelegate {
    static let shared = MainWindow()

    private let langPop = NSPopUpButton(frame: .zero, pullsDown: false)
    private let inputView = NSTextView()
    private let inputScroll = NSScrollView()
    private let resultView = NSTextView()
    private let resultScroll = NSScrollView()
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
        content.addSubview(langPop)

        pinButton.bezelStyle = .texturedRounded
        pinButton.target = self
        pinButton.action = #selector(togglePin)
        content.addSubview(pinButton)

        copyButton.bezelStyle = .texturedRounded
        copyButton.target = self
        copyButton.action = #selector(copyResult)
        content.addSubview(copyButton)

        // 输入区
        inputScroll.hasVerticalScroller = true
        inputScroll.borderType = .bezelBorder
        inputView.font = NSFont.systemFont(ofSize: 14)
        inputView.delegate = self
        inputView.isRichText = false
        inputScroll.documentView = inputView
        content.addSubview(inputScroll)

        // 状态行
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        // 结果区
        resultScroll.hasVerticalScroller = true
        resultScroll.borderType = .bezelBorder
        resultView.font = NSFont.systemFont(ofSize: 14)
        resultView.isEditable = false
        resultView.isRichText = false
        resultScroll.documentView = resultView
        content.addSubview(resultScroll)

        layoutContent()
        // 尺寸变化时显式重排（固定掩码在拉高窗口时会让结果区越过输入区）
        NotificationCenter.default.addObserver(self, selector: #selector(relayout),
                                               name: NSWindow.didResizeNotification, object: self)

        // Esc 隐藏
        NSApp.addMonitorIfNeeded(self)
    }

    // MARK: - 布局：顶栏/输入区锚定顶部，状态行+结果区填充剩余

    @objc private func relayout() {
        layoutContent()
    }

    private func layoutContent() {
        guard let content = contentView else { return }
        let w = content.frame.width
        let h = content.frame.height
        let margin: CGFloat = 12
        let barH: CGFloat = 26

        langPop.frame = NSRect(x: margin, y: h - margin - barH, width: 130, height: barH)
        pinButton.frame = NSRect(x: w - margin - 44 - 48, y: h - margin - barH, width: 40, height: barH)
        copyButton.frame = NSRect(x: w - margin - 44, y: h - margin - barH, width: 44, height: barH)

        let inputY = h - margin - barH - 8 - inputH
        inputScroll.frame = NSRect(x: margin, y: inputY, width: w - margin * 2, height: inputH)

        statusLabel.frame = NSRect(x: margin, y: inputY - 24, width: w - margin * 2, height: 18)

        resultScroll.frame = NSRect(x: margin, y: copyBarH, width: w - margin * 2,
                                    height: inputY - 24 - copyBarH)
        resultView.frame = NSRect(x: 0, y: 0, width: resultScroll.contentSize.width, height: resultScroll.contentSize.height)
    }

    private let copyBarH: CGFloat = 36
    private let inputH: CGFloat = 82

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
