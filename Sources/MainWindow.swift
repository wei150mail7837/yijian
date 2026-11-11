import AppKit

/// 偏好读取（对齐 Electron StoreService 键名；Config.swift 属 shell 域，此处直接读 UserDefaults）
enum Pref {
    static let d = UserDefaults.standard
    static func flag(_ key: String) -> Bool { d.string(forKey: key) == "Y" || d.bool(forKey: key) }
    static var thumbtack: Bool {
        get { flag("thumbtackStatus") }
        set { d.set(newValue ? "Y" : "N", forKey: "thumbtackStatus") }
    }
    static var width: CGFloat {
        get { let w = d.double(forKey: "mainWinWidth"); return w >= 450 ? CGFloat(w) : 450 }
        set { d.set(Double(newValue), forKey: "mainWinWidth") }
    }
    static var inputLanguage: String {
        get { d.string(forKey: "inputLanguage") ?? "auto" }
        set { d.set(newValue, forKey: "inputLanguage") }
    }
    static var resultLanguage: String {
        get { d.string(forKey: "resultLanguage") ?? "auto" }
        set { d.set(newValue, forKey: "resultLanguage") }
    }
}

/// 输入框：回车翻译 / ⌘或⌃+回车换行 / ⌘V 粘贴后翻译
private final class InputTextView: NSTextView {
    var onEnter: (() -> Void)?
    var onPaste: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 {
            let mods = event.modifierFlags.intersection([.command, .control, .shift])
            if mods.contains(.command) || mods.contains(.control) {
                insertText("\n", replacementRange: selectedRange()); return
            }
            if !hasMarkedText() { onEnter?(); return }
        }
        super.keyDown(with: event)
    }
    override func paste(_ sender: Any?) {
        super.paste(sender)
        onPaste?()
    }
}

/// 翻转坐标容器（自上而下排版）
private final class FlippedView: NSView { override var isFlipped: Bool { true } }

/// 主窗口：无边框透明悬浮窗，Header → 输入区 → 语言栏 → 结果卡
final class MainWindow: NSWindow, NSWindowDelegate {
    static let shared = MainWindow()

    private let bg = NSVisualEffectView()
    private let root = FlippedView()
    // Header
    private let pinButton = IconButton()
    private let settingsButton = IconButton()
    // 输入区
    private let inputView = InputTextView()
    private let inputScroll = NSScrollView()
    // 语言栏
    private let srcButton = LanguageBarButton(isSource: true)
    private let dstButton = LanguageBarButton(isSource: false)
    private let swapButton = IconButton()
    // 结果卡
    private let card = NSView()
    private var cardIconView: NSImageView?
    private let cardTitle = NSTextField(labelWithString: "")
    private let spinner = NSProgressIndicator()
    private let foldButton = IconButton()
    private let resultView = NSTextView()
    private let resultScroll = NSScrollView()
    private let copyButton = IconButton()
    private let camelButton = IconButton()
    private let snakeButton = IconButton()
    private let sourceToggle = NSButton()
    private let sourceLabel = NSTextField(wrappingLabelWithString: "")
    private var sourceExpanded = false
    private var lastSourceText = ""
    // 逐字渲染：网络 delta 先入缓冲，由定时器按帧逐字吐出
    private var pendingChars: [Character] = []
    private var typeTimer: Timer?
    private var pendingDone: (() -> Void)?
    private var animateNextResize = false
    private var fontSize: CGFloat { CGFloat(Config.winFontSize) }
    // toast
    private let toastContainer = NSView()      // toast 堆叠容器（对齐 ElMessage 多条堆叠）
    private var toastCards: [ToastCardView] = []
    private let copyInputButton = IconButton()
    // 打字机：记录上次参与布局的结果高度，未变化帧跳过全量重排
    private var lastLaidResultH: CGFloat = -1

    private var pinned = false
    private var folded = false
    private var isError = false
    private var lastFullResult = ""
    private var activeRequestId = 0
    private var manualHeight = false
    private var adjustingFrame = false
    private var debounce: DispatchWorkItem?

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: Pref.width, height: 339),
                   styleMask: [.borderless, .resizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // 对齐 Lite（窗口无影）；边界靠 bg 的 1px 描边呈现
        isMovableByWindowBackground = true
        minSize = NSSize(width: 450, height: 150)
        collectionBehavior = [.fullScreenNone, .moveToActiveSpace, .transient]
        delegate = self
        center()

        bg.material = .popover
        bg.blendingMode = .behindWindow
        bg.state = .active
        bg.wantsLayer = true
        bg.layer?.cornerRadius = 10
        bg.layer?.masksToBounds = true
        bg.layer?.borderWidth = 1
        bg.layer?.borderColor = NSColor.separatorColor.cgColor
        contentView = bg
        root.frame = bg.bounds
        root.autoresizingMask = [.width, .height]
        bg.addSubview(root)

        buildHeader()
        buildInput()
        buildLanguageBar()
        buildCard()
        buildToast()

        pinned = Pref.thumbtack
        applyPin()
        layoutContent()
        EscMonitor.add(self)
        // 深浅主题切换：描边/底色用 cgColor 固化，需整体重刷（对齐 Lite css-dark/light-vars 即时切换）
        DistributedNotificationCenter.default.addObserver(self,
            selector: #selector(themeChanged), name: NSNotification.Name("AppleInterfaceThemeChangedNotification"), object: nil)
        // 设置页写入 winFontSize 后即时重应用到已显示主窗（对齐 Lite 即时生效）
        NotificationCenter.default.addObserver(self, selector: #selector(defaultsChanged),
                                               name: UserDefaults.didChangeNotification, object: nil)
    }

    @objc private func defaultsChanged() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.inputView.font?.pointSize != self.fontSize else { return }
            self.applyFontSize()
            self.layoutContent()
        }
    }

    /// 主题变化后重刷所有固化过的 cgColor 描边与卡片着色
    @objc private func themeChanged() {
        // cgColor 在下一次 runloop 才解析到新 trait
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.bg.layer?.borderColor = NSColor.separatorColor.cgColor
            self.inputScroll.layer?.borderColor = NSColor.separatorColor.cgColor
            self.inputScroll.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6).cgColor
            self.applyCardStyle()
            self.toastCards.forEach { $0.applyTheme() }
        }
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    /// 关闭=隐藏，窗口永不销毁
    override func close() { orderOut(nil) }
    override func performClose(_ sender: Any?) { orderOut(nil) }
    override func toggleFullScreen(_ sender: Any?) {} // 禁用全屏

    // MARK: - 构建

    private func iconButton(_ b: IconButton, symbol: String, tip: String, action: Selector) {
        b.configure(symbol: symbol, tip: tip, action: action)
    }

    private func textButton(_ b: NSButton, title: String, action: Selector) {
        b.title = title
        b.bezelStyle = .inline
        b.controlSize = .small
        b.font = .systemFont(ofSize: 11)
        b.target = self
        b.action = action
    }

    private func buildHeader() {
        iconButton(pinButton, symbol: "pin", tip: "置顶", action: #selector(togglePin))
        iconButton(copyInputButton, symbol: "doc.plaintext", tip: "复制输入内容", action: #selector(copyInput))
        iconButton(settingsButton, symbol: "gearshape", tip: "设置", action: #selector(openSettings))
        root.addSubview(pinButton)
        root.addSubview(copyInputButton)
        root.addSubview(settingsButton)
    }

    private func buildInput() {
        inputScroll.hasVerticalScroller = true
        inputScroll.autohidesScrollers = true
        inputScroll.borderType = .noBorder
        inputScroll.drawsBackground = false
        inputScroll.wantsLayer = true
        inputScroll.layer?.cornerRadius = 6
        inputScroll.layer?.borderWidth = 1
        inputScroll.layer?.borderColor = NSColor.separatorColor.cgColor
        inputScroll.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.6).cgColor
        inputView.font = .systemFont(ofSize: 14)
        inputView.isRichText = false
        inputView.allowsUndo = true
        inputView.drawsBackground = false
        inputView.textContainerInset = NSSize(width: 4, height: 5)
        inputView.isVerticallyResizable = true
        inputView.autoresizingMask = [.width]
        inputView.textContainer?.widthTracksTextView = true
        inputView.onEnter = { [weak self] in self?.enterPressed() }
        inputView.onPaste = { [weak self] in
            guard let self, !Config.inputTranslationAuto else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.startTranslate() }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(inputChanged),
                                               name: NSText.didChangeNotification, object: inputView)
        inputScroll.documentView = inputView
        root.addSubview(inputScroll)
        // placeholder
        placeholder.textColor = .placeholderTextColor
        placeholder.font = .systemFont(ofSize: 14)
        root.addSubview(placeholder)
    }
    private let placeholder = NSTextField(labelWithString: "请输入单词或文字")

    private func buildLanguageBar() {
        for (btn, sel) in [(srcButton, Pref.inputLanguage), (dstButton, Pref.resultLanguage)] {
            btn.refreshTitle(current: sel)
            btn.rootWindow = self
            root.addSubview(btn)
        }
        iconButton(swapButton, symbol: "arrow.left.arrow.right", tip: "互换", action: #selector(swapLanguages))
        root.addSubview(swapButton)
    }

    private func buildCard() {
        card.wantsLayer = true
        card.layer?.cornerRadius = 8
        card.layer?.borderWidth = 1
        root.addSubview(card)
        cardTitle.font = .boldSystemFont(ofSize: 12)
        let logo = NSImageView()
        logo.image = NSImage(size: NSSize(width: 14, height: 14), flipped: false) { rect in
            NSColor.labelColor.setStroke()
            let p = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
            p.lineWidth = 1.2; p.stroke()
            NSColor.labelColor.set()
            let t = NSBezierPath(); t.lineWidth = 1.6
            t.move(to: NSPoint(x: rect.width*0.28, y: rect.height*0.72))
            t.line(to: NSPoint(x: rect.width*0.72, y: rect.height*0.72))
            t.move(to: NSPoint(x: rect.width*0.5, y: rect.height*0.72))
            t.line(to: NSPoint(x: rect.width*0.5, y: rect.height*0.28))
            t.stroke()
            return true
        }
        cardIconView = logo
        card.addSubview(logo)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        spinner.isHidden = true
        card.addSubview(spinner)
        iconButton(foldButton, symbol: "chevron.up", tip: "折叠", action: #selector(toggleFold))
        card.addSubview(foldButton)
        resultView.font = .systemFont(ofSize: 14)
        resultView.isEditable = false
        resultView.isSelectable = true
        resultView.isRichText = false
        resultView.drawsBackground = false
        resultView.textContainerInset = NSSize(width: 2, height: 2)
        // 长译文滚动：内容超出结果区高度时可滚动（对齐 Lite .block-layer overflow:auto）
        resultScroll.hasVerticalScroller = true
        resultScroll.borderType = .noBorder
        resultScroll.drawsBackground = false
        resultScroll.documentView = resultView
        card.addSubview(resultScroll)
        // 原文折叠行（AI 卡：原文默认折叠）
        textButton(sourceToggle, title: "▸ 原文", action: #selector(toggleSource))
        sourceToggle.isBordered = false
        sourceToggle.contentTintColor = .secondaryLabelColor
        card.addSubview(sourceToggle)
        sourceLabel.textColor = .secondaryLabelColor
        sourceLabel.maximumNumberOfLines = 6
        sourceLabel.lineBreakMode = .byTruncatingTail
        sourceLabel.cell?.wraps = true
        card.addSubview(sourceLabel)
        iconButton(copyButton, symbol: "doc.on.doc", tip: "复制", action: #selector(copyResult))
        iconButton(camelButton, symbol: "textformat.abc", tip: "复制驼峰命名", action: #selector(copyCamel))
        iconButton(snakeButton, symbol: "underline", tip: "复制蛇形命名", action: #selector(copySnake))
        [copyButton, camelButton, snakeButton].forEach { card.addSubview($0) }
        cardTitle.lineBreakMode = .byTruncatingTail
        applyCardStyle()
    }

    private func buildToast() {
        // 堆叠式 toast 容器（对齐 ElMessage：可多条并存、滑入动画、图形图标、长文本换行）
        toastContainer.wantsLayer = true
        root.addSubview(toastContainer)
    }

    // MARK: - 布局（自上而下）

    private let margin: CGFloat = 10
    private let headerH: CGFloat = 26
    private let langH: CGFloat = 26

    private var lineHeight: CGFloat {
        let f = inputView.font ?? .systemFont(ofSize: 14)
        return ceil(inputView.layoutManager?.defaultLineHeight(for: f) ?? 17)
    }

    /// 输入区 autosize：2~10 行
    private var inputHeight: CGFloat {
        guard let lm = inputView.layoutManager, let tc = inputView.textContainer else { return lineHeight * 2 + 10 }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc).height
        let lines = max(2, min(10, Int(ceil(used / lineHeight))))
        return CGFloat(lines) * lineHeight + 10
    }

    private var resultTextHeight: CGFloat {
        guard let lm = resultView.layoutManager, let tc = resultView.textContainer else { return 20 }
        lm.ensureLayout(for: tc)
        return max(lineHeight * 2, ceil(lm.usedRect(for: tc).height) + 4)
    }

    private var hideInput: Bool { Config.hideInput }
    private var hideLanguage: Bool { Config.hideLanguageBar }
    private var showCamel: Bool { Config.copyCamelCaseResult && hasLatin }
    private var showSnake: Bool { Config.copySnakeCaseResult && hasLatin }
    private var hasLatin: Bool { !isError && lastFullResult.range(of: "[a-zA-Z]", options: .regularExpression) != nil }

    private func layoutContent() {
        let w = root.bounds.width
        let inner = w - margin * 2
        var y: CGFloat = 6
        pinButton.frame = NSRect(x: margin, y: y, width: 24, height: 22)
        copyInputButton.frame = NSRect(x: margin + 28, y: y, width: 24, height: 22)
        copyInputButton.isHidden = hideInput || inputView.string.isEmpty
        settingsButton.frame = NSRect(x: w - margin - 24, y: y, width: 24, height: 22)
        y += headerH

        inputScroll.isHidden = hideInput
        placeholder.isHidden = hideInput || !inputView.string.isEmpty
        if !hideInput {
            let ih = inputHeight
            inputScroll.frame = NSRect(x: margin, y: y, width: inner, height: ih)
            inputView.minSize = NSSize(width: 0, height: ih)
            inputView.frame.size.width = inputScroll.contentSize.width
            placeholder.frame = NSRect(x: margin + 9, y: y + 5, width: inner - 20, height: 18)
            y += ih + 6
        }

        [srcButton, dstButton, swapButton].forEach { $0.isHidden = hideLanguage }
        if !hideLanguage {
            let pw = (inner - 36) / 2
            srcButton.frame = NSRect(x: margin, y: y, width: pw, height: 24)
            swapButton.frame = NSRect(x: margin + pw + 6, y: y + 1, width: 24, height: 22)
            dstButton.frame = NSRect(x: margin + pw + 36, y: y, width: pw, height: 24)
            y += langH + 4
        }

        // 结果卡
        let cw = inner
        cardTitle.stringValue = "AI · \(Config.model.isEmpty ? "未配置模型" : Config.model)"
        cardIconView?.frame = NSRect(x: 10, y: 7, width: 14, height: 14)
        cardTitle.frame = NSRect(x: 28, y: 6, width: cw - 88, height: 16)
        spinner.frame = NSRect(x: cw - 52, y: 5, width: 16, height: 16)
        foldButton.frame = NSRect(x: cw - 30, y: 3, width: 22, height: 20)
        foldButton.image = NSImage(systemSymbolName: folded ? "chevron.down" : "chevron.up", accessibilityDescription: nil)
        var ch: CGFloat = 28
        let showBody = !folded && (!lastFullResult.isEmpty || spinner.isHidden == false)
        resultView.isHidden = !showBody
        sourceToggle.isHidden = !showBody || lastSourceText.isEmpty
        sourceLabel.isHidden = sourceToggle.isHidden || !sourceExpanded
        [copyButton, camelButton, snakeButton].forEach { $0.isHidden = true }
        if showBody {
            if !sourceToggle.isHidden {
                // 固定尺寸（勿用 sizeToFit：inline bezel 反复调用会累计 padding 导致按钮逐次变高）
                sourceToggle.title = sourceExpanded ? "▾ 原文" : "▸ 原文"
                sourceToggle.frame = NSRect(x: 6, y: ch - 2, width: 64, height: 16)
                ch += 18
                if sourceExpanded {
                    sourceLabel.font = .systemFont(ofSize: max(10, fontSize - 2))
                    sourceLabel.stringValue = lastSourceText
                    sourceLabel.preferredMaxLayoutWidth = cw - 20
                    // 确定性高度：按字体与宽度直接算，不经视图自身 sizeThatFits（其结果随 frame 漂移）
                    let sh = min(ceil((lastSourceText as NSString).boundingRect(
                        with: NSSize(width: cw - 20, height: .greatestFiniteMagnitude),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        attributes: [.font: NSFont.systemFont(ofSize: max(10, fontSize - 2))]
                    ).height), 120)
                    sourceLabel.frame = NSRect(x: 10, y: ch, width: cw - 20, height: sh)
                    ch += sh + 4
                }
            }
            resultScroll.frame = NSRect(x: 6, y: ch, width: cw - 12, height: 10)
            resultView.textContainer?.containerSize = NSSize(width: cw - 16, height: .greatestFiniteMagnitude)
            // 填充驱动：结果区 ≥ 内容高度，且填满窗口剩余空间（手动拉伸窗口时跟随）
            let availCard = root.bounds.height - y - margin
            let fillH = availCard - ch - 28   // 28 = 结果下方按钮行 + 卡片内边距
            let rh = max(resultTextHeight, fillH)
            resultScroll.frame.size.height = rh
            resultView.minSize = NSSize(width: resultScroll.contentSize.width, height: rh)
            resultView.frame.size.width = resultScroll.contentSize.width
            lastLaidResultH = rh // layoutContent 任何路径重排后同步基线，避免打字机误判
            ch += rh + 4
            if !lastFullResult.isEmpty && spinner.isHidden {
                var x: CGFloat = 8
                for (b, show) in [(copyButton, true), (camelButton, showCamel), (snakeButton, showSnake)] where show {
                    b.isHidden = false
                    b.frame = NSRect(x: x, y: ch, width: 22, height: 20)
                    x += 26
                }
                ch += 24
            }
        }
        card.frame = NSRect(x: margin, y: y, width: cw, height: ch + 4)
        y += ch + 4 + margin

        relayoutToasts()
        autoHeight(y)
    }

    /// MainWindowResize.autoHeight：用户手动调过高度后不再自动调高；保持左上角不动
    private func autoHeight(_ contentH: CGFloat) {
        guard !manualHeight, !inLiveResize else { return }
        let target = max(minSize.height, ceil(contentH))
        if adjustingFrame { return } // 动画进行中：过程帧不再重算
        guard abs(frame.height - target) > 0.5 else { return }
        var f = frame
        let top = f.maxY
        f.size.height = target
        f.origin.y = top - target
        let animate = animateNextResize && isVisible
        animateNextResize = false
        adjustingFrame = true
        if animate {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.12
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                self.animator().setFrame(f, display: true)
            }, completionHandler: { [weak self] in
                guard let self else { return }
                self.adjustingFrame = false
                self.layoutContent() // 动画期间如有新内容，收敛到最新目标
            })
        } else {
            setFrame(f, display: true, animate: false)
            adjustingFrame = false
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) {
        if inLiveResize && !adjustingFrame {
            manualHeight = true
            Pref.width = frame.width
        }
        layoutContent()
    }

    /// 失焦：未置顶则隐藏；showTranslateNotEmptyStatus=N 时清空
    func windowDidResignKey(_ notification: Notification) {
        guard !pinned, isVisible else { return }
        orderOut(nil)
        clearIfNeeded()
    }

    private func clearIfNeeded() {
        guard !Config.showTranslateNotEmpty else { return }
        OllamaClient.shared.cancel()
        stopTypewriter()
        activeRequestId += 1
        inputView.string = ""
        lastSourceText = ""
        lastFullResult = ""
        resultView.string = ""
        isError = false
        spinner.stopAnimation(nil)
        applyCardStyle()
        layoutContent()
    }

    // MARK: - 显示

    func showForInput(_ text: String?) {
        applyFontSize()
        if !isVisible {
            clearIfNeeded()
            positionWindow()
            if !manualHeight { layoutContent() }
        }
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let text, !text.isEmpty {
            inputView.string = text
            layoutContent()
            startTranslate()
        } else {
            makeFirstResponder(inputView)
        }
    }

    /// 显示位置（单一读取路径：Config.showPosition）：0=LAST_TIME 1=FROM_TOP 2=FOLLOW_MOUSE
    private func positionWindow() {
        let mouse = NSEvent.mouseLocation
        let scr = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let scr else { return }
        switch Config.showPosition {
        case 2: // FOLLOW_MOUSE
            // Electron (x, y+11) 是左上原点；Cocoa 左下原点 → 窗顶 = 鼠标y - 11
            setFrameTopLeftPoint(NSPoint(x: mouse.x, y: mouse.y - 11))
        case 1: // FROM_TOP
            let pct = Double(Config.topPercent)
            let sf = scr.frame
            // 对齐 Lite GlobalWin.ts:112-118：pct=50 时窗口垂直居中 → 分母含窗口自身高度
            let topOffset = (sf.height - frame.height) / 2 * (pct * 2 / 100)
            setFrameTopLeftPoint(NSPoint(x: sf.minX + (sf.width - frame.width) / 2, y: sf.maxY - topOffset))
        default:
            break
        }
        // 保证完整落在屏内
        let vf = scr.visibleFrame
        var f = frame
        f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
        f.origin.y = min(max(f.origin.y, vf.minY), vf.maxY - f.height)
        setFrame(f, display: false)
    }

    // MARK: - 输入事件

    private func enterPressed() {
        // 自动翻译模式下回车被吞掉
        if Config.inputTranslationAuto { return }
        startTranslate()
    }

    @objc private func inputChanged() {
        animateNextResize = true
        layoutContent()
        guard Config.inputTranslationAuto else { return }
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.cleaned(self.inputView.string).isEmpty { return }
            self.startTranslate()
        }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func cleaned(_ s: String) -> String {
        s.replacingOccurrences(of: "[\\n\\r ]", with: "", options: .regularExpression)
    }

    // MARK: - 翻译（requestId 竞态防护 + 流式增量）

    func startTranslate() {
        var text = inputView.string
        guard !cleaned(text).isEmpty else { showToast("内容不能为空", kind: .warning); return }
        if Config.wrapReplaceSpace {
            text = text.replacingOccurrences(of: "[\\n\\r]", with: " ", options: .regularExpression)
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        activeRequestId += 1
        let rid = activeRequestId
        stopTypewriter()
        lastSourceText = text
        sourceExpanded = false
        // START：清空结果
        lastFullResult = ""
        resultView.string = ""
        isError = false
        folded = false
        spinner.startAnimation(nil)
        spinner.isHidden = false
        applyCardStyle()
        animateNextResize = true
        layoutContent()
        let src = Pref.inputLanguage
        let dst = Pref.resultLanguage
        OllamaClient.shared.translate(text: text, source: src, target: dst, onDelta: { [weak self] piece in
            DispatchQueue.main.async {
                guard let self, rid == self.activeRequestId else { return } // 旧请求丢弃
                // ING：逐 chunk 入队，打字机逐字渲染
                self.enqueue(piece)
            }
        }, onDone: { [weak self] result in
            DispatchQueue.main.async {
                guard let self, rid == self.activeRequestId else { return }
                let finish = { [weak self] in
                    guard let self, rid == self.activeRequestId else { return }
                    self.finishTranslate(result)
                }
                // 成功时等缓冲吐完再收尾；失败立即呈现
                if case .success = result, !self.pendingChars.isEmpty { self.pendingDone = finish }
                else { self.stopTypewriter(); finish() }
            }
        })
        log("[翻译] 开始 长度=\(text.count)")
    }

    private func finishTranslate(_ result: Result<String, Error>) {
        do {
                self.spinner.stopAnimation(nil)
                self.spinner.isHidden = true
                switch result {
                case .success(let full):
                    if full != self.lastFullResult {
                        self.lastFullResult = full
                        self.resultView.string = full
                    }
                    log("[翻译] 完成 长度=\(full.count)")
                case .failure(let error):
                    // ERROR：错误文本作为结果显示并展开
                    self.isError = true
                    self.folded = false
                    self.lastFullResult = error.localizedDescription
                    self.resultView.string = "⚠︎ " + error.localizedDescription
                    log("[翻译] 失败")
                }
                self.applyCardStyle()
                self.animateNextResize = true
                self.layoutContent()
        }
    }

    private var resultAttrs: [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: isError ? NSColor.systemRed : NSColor.labelColor]
    }

    // MARK: - 逐字打字机（超 Lite 增强：Lite 为按 delta 成段追加）

    private func enqueue(_ piece: String) {
        pendingChars.append(contentsOf: piece)
        guard typeTimer == nil else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.typeTick() }
        RunLoop.main.add(t, forMode: .common)
        typeTimer = t
    }

    private func typeTick() {
        guard !pendingChars.isEmpty else {
            typeTimer?.invalidate(); typeTimer = nil
            if let done = pendingDone { pendingDone = nil; done() }
            return
        }
        // 积压越多吐得越快，保证不落后网络超过 ~0.5s
        let n = max(1, pendingChars.count / 30)
        let s = String(pendingChars.prefix(n))
        pendingChars.removeFirst(min(n, pendingChars.count))
        lastFullResult += s
        resultView.textStorage?.append(NSAttributedString(string: s, attributes: resultAttrs))
        // 高度变化才全量重排（含窗口自适应）；纯滚动帧只跟随，避免 60Hz 重排抖动
        let rh = resultTextHeight
        if abs(rh - lastLaidResultH) > 0.5 {
            lastLaidResultH = rh
            animateNextResize = true   // 打字增行同样走平滑动画
            layoutContent()
        }
        resultView.scrollToEndOfDocument(nil)
    }

    private func stopTypewriter() {
        typeTimer?.invalidate(); typeTimer = nil
        pendingChars.removeAll()
        pendingDone = nil
    }

    private func applyCardStyle() {
        card.layer?.backgroundColor = (isError ? NSColor.systemRed.withAlphaComponent(0.10)
                                               : NSColor.textBackgroundColor.withAlphaComponent(0.5)).cgColor
        card.layer?.borderColor = (isError ? NSColor.systemRed : NSColor.separatorColor).cgColor
        resultView.textColor = isError ? .systemRed : .labelColor
    }

    /// 外部（OCR 等）错误：toast 呈现
    func showErrorMessage(_ message: String) {
        if !isVisible { makeKeyAndOrderFront(nil) }
        showToast(message, kind: .error)
    }

    // MARK: - toast（success/warning 2.5s，error 5s，延迟 100ms 显示）

    enum ToastKind { case success, warning, error }

    func showToast(_ text: String, kind: ToastKind) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pushToast(text: text, kind: kind)
        }
    }

    /// 堆叠式 toast：最多 3 条并存，滑入动画，SF Symbol 图标，长文本换行
    private func pushToast(text: String, kind: ToastKind) {
        let color: NSColor = kind == .success ? .systemGreen : kind == .warning ? .systemOrange : .systemRed
        let symbol = kind == .success ? "checkmark.circle.fill" : kind == .warning ? "exclamationmark.triangle.fill" : "xmark.circle.fill"
        let card = ToastCardView(text: text, color: color, symbol: symbol)
        toastCards.append(card)
        toastContainer.addSubview(card)
        // 超过 3 条：最旧的立即移除
        while toastCards.count > 3 {
            let old = toastCards.removeFirst()
            old.removeFromSuperview()
        }
        relayoutToasts()
        card.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.animator().alphaValue = 1
        }
        let gen = ObjectIdentifier(card)
        DispatchQueue.main.asyncAfter(deadline: .now() + (kind == .error ? 5 : 2.5)) { [weak self, weak card] in
            guard let card else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                card.animator().alphaValue = 0
            }, completionHandler: { [weak self] in
                guard let self else { return }
                card.removeFromSuperview()
                self.toastCards.removeAll { ObjectIdentifier($0) == gen }
                self.relayoutToasts()
            })
        }
    }

    /// 依剩余卡片重排（顶部居中堆叠，最新在最上）
    private func relayoutToasts() {
        let w = root.bounds.width
        let top = w > 0 ? headerH + 4 : 8
        var yy: CGFloat = 0
        for card in toastCards {
            card.layoutSelf()
            let cw = min(root.bounds.width - margin * 2, max(card.frame.width + 40, 160))
            let chh = card.frame.height + 8
            card.frame = NSRect(x: (w - cw) / 2, y: 0, width: cw, height: chh)
            yy += chh + 6
        }
        // 自上而下：从容器顶往下排
        var fromTop: CGFloat = top
        for card in toastCards {
            card.frame.origin.y = root.bounds.height - fromTop - card.frame.height
            fromTop += card.frame.height + 6
        }
    }

    // MARK: - Header / 语言栏 / 结果卡 动作

    @objc private func togglePin() {
        pinned.toggle()
        Pref.thumbtack = pinned
        applyPin()
    }

    private func applyPin() {
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin", accessibilityDescription: "置顶")
        pinButton.emphasized = pinned   // 强调态由 IconButton.updateVisual 统一管理
        level = pinned ? .floating : .normal
    }

    var isPinned: Bool { pinned }

    @objc private func openSettings() {
        SettingsWindow.shared.showSettings()
    }

    @objc private func swapLanguages() {
        let a = Pref.inputLanguage
        Pref.inputLanguage = Pref.resultLanguage == "auto" ? OllamaClient.autoTarget(for: "x") : Pref.resultLanguage
        Pref.resultLanguage = a == "auto" ? OllamaClient.autoTarget(for: "x") : a
        srcButton.refreshTitle(current: Pref.inputLanguage)
        dstButton.refreshTitle(current: Pref.resultLanguage)
    }

    @objc private func toggleFold() {
        guard !lastFullResult.isEmpty else { return }   // Lite 空内容点击不动作
        folded.toggle()
        animateNextResize = true
        layoutContent()
    }

    @objc private func toggleSource() {
        sourceExpanded.toggle()
        animateNextResize = true
        layoutContent()
    }

    /// winFontSize（10-30）即时应用到输入/结果/placeholder
    private func applyFontSize() {
        let f = NSFont.systemFont(ofSize: fontSize)
        guard inputView.font?.pointSize != fontSize else { return }
        inputView.font = f
        placeholder.font = f
        resultView.font = f
        if let ts = resultView.textStorage { ts.addAttribute(.font, value: f, range: NSRange(location: 0, length: ts.length)) }
    }

    private func copy(_ s: String) {
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            showToast("复制的文本内容为空", kind: .warning); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
        showToast("复制成功", kind: .success)
    }

    @objc private func copyResult() { copy(isError ? "" : lastFullResult) }
    @objc private func copyInput() { copy(inputView.string) }
    @objc private func copyCamel() { copy(MainWindow.camelCase(lastFullResult)) }
    @objc private func copySnake() { copy(MainWindow.snakeCase(lastFullResult)) }

    private static func stripPunct(_ s: String) -> String {
        s.replacingOccurrences(of: "[\\p{P}\\p{S}]", with: "", options: .regularExpression)
    }

    /// 驼峰：去标点→小写→首词后各词首字母大写→去空格
    static func camelCase(_ s: String) -> String {
        let words = stripPunct(s).lowercased().split(whereSeparator: { $0.isWhitespace })
        return words.enumerated().map { i, w in i == 0 ? String(w) : w.prefix(1).uppercased() + w.dropFirst() }.joined()
    }

    /// 蛇形：去标点→空格转下划线小写→连续下划线合一→去尾下划线
    static func snakeCase(_ s: String) -> String {
        var r = stripPunct(s).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s", with: "_", options: .regularExpression).lowercased()
        r = r.replacingOccurrences(of: "_+", with: "_", options: .regularExpression)
        while r.hasSuffix("_") { r.removeLast() }
        return r
    }
}

/// Esc 隐藏窗口的事件监视器（主/OCR/设置窗口共用）
/// 置顶例外：主窗置顶时 Esc 不隐藏，除非设置开启"允许 Esc 隐藏"（Config.alwaysOnTopAllowEsc）
enum EscMonitor {
    private static var monitor: Any?
    private static var targets = NSHashTable<NSWindow>.weakObjects()

    static func add(_ window: NSWindow) {
        targets.add(window)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53, let keyWindow = NSApp.keyWindow, targets.contains(keyWindow) else { return event }
            // 快捷键录制器正在录入：Esc 归它处理（取消录入），不隐藏窗口
            if keyWindow.firstResponder is ShortcutRecorder { return event }
            if keyWindow === MainWindow.shared, MainWindow.shared.isPinned,
               !Config.alwaysOnTopAllowEsc {
                return event
            }
            keyWindow.orderOut(nil)
            return nil
        }
    }
}

/// 无边框图标按钮：悬停高亮、按压加深、执行后短暂闪烁，反馈明确
final class IconButton: NSButton {
    private var hover = false
    private var flash: Timer?

    init(symbol: String = "", tip: String = "", action: Selector? = nil) {
        super.init(frame: .zero)
        setButtonType(.momentaryPushIn)
        isBordered = false
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = 6
        configure(symbol: symbol, tip: tip, action: action)
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(symbol: String, tip: String, action: Selector?) {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
        toolTip = tip
        self.action = action
        target = nil                                    // nil = responder 链，最终命中所属窗口控制器
        contentTintColor = .secondaryLabelColor
        updateVisual()
    }

    /// 强调态（如置顶按钮按下时保持强调色，不被悬停/常态覆盖）
    var emphasized = false

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        // .inVisibleRect：bounds 变化（初始隐藏→显形）时跟踪区自动跟随，避免零尺寸死区
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hover = true; updateVisual() }
    override func mouseExited(with event: NSEvent) { hover = false; updateVisual() }

    // 按压态由 isHighlighted 驱动，NSButton 会在按下/抬起时置位
    override var isHighlighted: Bool {
        didSet { updateVisual() }
    }

    // 点击回执：flash 由动作侧触发，mouseUp 在 NSButton 跟踪循环内不可靠
    override func mouseDown(with event: NSEvent) {
        flashFeedback()
        super.mouseDown(with: event)
    }

    /// 动作执行后的视觉回执：闪一下强调色
    func flashFeedback() {
        flash?.invalidate()
        contentTintColor = .controlAccentColor
        flash = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
            self?.updateVisual()
        }
    }

    private func updateVisual() {
        if isHighlighted {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.28).cgColor
            contentTintColor = .controlAccentColor
        } else if emphasized {
            // 强调态（置顶）：常态保持强调色，悬停加深，按压更亮
            layer?.backgroundColor = (hover ? NSColor.controlAccentColor.withAlphaComponent(0.35)
                                            : NSColor.controlAccentColor.withAlphaComponent(0.22)).cgColor
            contentTintColor = .controlAccentColor
        } else if hover {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.cgColor
            contentTintColor = .labelColor
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = .secondaryLabelColor
        }
    }
}

/// 单条 toast 卡：SF Symbol 图标 + 换行文本
final class ToastCardView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(wrappingLabelWithString: "")
    private let color: NSColor

    init(text: String, color: NSColor, symbol: String) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 240, height: 30))
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.masksToBounds = true
        layer?.borderWidth = 1
        layer?.borderColor = color.withAlphaComponent(0.5).cgColor
        layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.92).cgColor

        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        icon.contentTintColor = color
        icon.frame = NSRect(x: 10, y: 8, width: 14, height: 14)
        addSubview(icon)

        label.stringValue = text
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = color
        label.preferredMaxLayoutWidth = 320
        addSubview(label)
        layoutSelf()
    }
    required init?(coder: NSCoder) { fatalError() }

    func applyTheme() {
        layer?.borderColor = NSColor.separatorColor.cgColor
    }

    func layoutSelf() {
        label.preferredMaxLayoutWidth = 320
        let sz = label.sizeThatFits(NSSize(width: 320, height: 400))
        let textH = max(sz.height, 16)
        label.frame = NSRect(x: 30, y: (textH + 12 - textH) / 2, width: sz.width + 2, height: textH)
        frame.size = NSSize(width: 30 + sz.width + 14, height: textH + 12)
    }
}
