import AppKit

/// 图片 + 识别框叠加视图（对齐 OcrImg.vue：polygon 边框，hover 显示文本+置信度）
private final class OCRImageView: NSView {
    var image: NSImage? { didSet { needsDisplay = true } }
    var result: VisionOCR.Result? { didSet { rebuildTips(); needsDisplay = true } }
    var showBoxes = true { didSet { rebuildTips(); needsDisplay = true } }
    override var isFlipped: Bool { true }

    /// 图片等比缩放后在视图内的绘制区域
    private var imageRect: CGRect {
        guard let image, image.size.width > 0, image.size.height > 0 else { return .zero }
        let s = min(bounds.width / image.size.width, bounds.height / image.size.height, 1)
        let w = image.size.width * s, h = image.size.height * s
        return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
    }

    /// OCR 像素坐标（左上原点）→ 视图坐标；result 宽高是识别时（可能缩放过）的像素尺寸
    private func viewRect(_ box: CGRect) -> CGRect {
        guard let r = result, r.width > 0, r.height > 0 else { return .zero }
        let ir = imageRect
        let sx = ir.width / CGFloat(r.width), sy = ir.height / CGFloat(r.height)
        return CGRect(x: ir.minX + box.minX * sx, y: ir.minY + box.minY * sy, width: box.width * sx, height: box.height * sy)
    }

    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); rebuildTips() }

    private func rebuildTips() {
        removeAllToolTips()
        guard showBoxes, let r = result else { return }
        for l in r.lines {
            addToolTip(viewRect(l.box), owner: "\(l.text)  (\(Int((l.confidence * 100).rounded()))%)" as NSString, userData: nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image else { return }
        image.draw(in: imageRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard showBoxes, let r = result else { return }
        // 对齐 Lite #468cff：1.5px 描边 + 8% 填充
        NSColor(red: 0x46/255.0, green: 0x8c/255.0, blue: 0xff/255.0, alpha: 0.08).setFill()
        NSColor(red: 0x46/255.0, green: 0x8c/255.0, blue: 0xff/255.0, alpha: 1).setStroke()
        for l in r.lines {
            let p = NSBezierPath(rect: viewRect(l.box)); p.lineWidth = 1.5
            p.fill(); p.stroke()
        }
    }
}

/// 截图 OCR 窗口（对齐 Ocr.ts / Ocr.vue）：810x430 无边框透明、预创建、关闭转隐藏、失焦未置顶自动隐藏；
/// 左半图片（识别框开关、复制图片），右半只读文本（复制文本、调起翻译）。
final class OCRWindow: NSWindow, NSWindowDelegate {
    static let shared = OCRWindow()

    private let imgView = OCRImageView()
    private let textView = NSTextView()
    private let leftPanel = NSView(), rightPanel = NSView()
    private let leftLoading = OCRWindow.loadingView(), rightLoading = OCRWindow.loadingView()
    private let boxCheck = NSButton(checkboxWithTitle: "识别框", target: nil, action: nil)
    private var imageFile: URL?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 810, height: 430),
                   styleMask: [.borderless, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovableByWindowBackground = true
        minSize = NSSize(width: 810, height: 430)
        collectionBehavior = [.moveToActiveSpace, .transient]   // skipTaskbar 等价：不进 Dock/窗口切换
        delegate = self
        center()

        let bg = NSVisualEffectView()
        bg.material = .popover; bg.state = .active; bg.wantsLayer = true
        bg.layer?.cornerRadius = 10; bg.layer?.masksToBounds = true
        contentView = bg

        boxCheck.state = .on
        boxCheck.target = self; boxCheck.action = #selector(toggleBoxes)
        let copyImg = Self.button("复制图片", self, #selector(copyImage))
        let copyTxt = Self.button("复制文本", self, #selector(copyText))
        let translate = Self.button("调起翻译", self, #selector(sendToTranslate))
        let settings = Self.button("设置", self, #selector(openSettings))
        let close = Self.button("✕", self, #selector(hideWindow))
        let pin = Self.button("📌", self, #selector(togglePin))

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.drawsBackground = false
        textView.isEditable = true; textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.isVerticallyResizable = true; textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        scroll.documentView = textView

        for v in [leftPanel, rightPanel] { v.translatesAutoresizingMaskIntoConstraints = false; bg.addSubview(v) }
        let leftBar = NSStackView(views: [boxCheck, copyImg]), rightBar = NSStackView(views: [copyTxt, translate, close])
        for v: NSView in [imgView, leftBar, leftLoading] { v.translatesAutoresizingMaskIntoConstraints = false; leftPanel.addSubview(v) }
        for v: NSView in [scroll, rightBar, rightLoading] { v.translatesAutoresizingMaskIntoConstraints = false; rightPanel.addSubview(v) }

        // 两栏各占一半（maxWidth = width/2 - 10），内容高 = height - 60
        NSLayoutConstraint.activate([
            leftPanel.leadingAnchor.constraint(equalTo: bg.leadingAnchor, constant: 5),
            leftPanel.topAnchor.constraint(equalTo: bg.topAnchor, constant: 10),
            leftPanel.bottomAnchor.constraint(equalTo: bg.bottomAnchor, constant: -10),
            leftPanel.widthAnchor.constraint(equalTo: bg.widthAnchor, multiplier: 0.5, constant: -10),
            rightPanel.trailingAnchor.constraint(equalTo: bg.trailingAnchor, constant: -5),
            rightPanel.topAnchor.constraint(equalTo: leftPanel.topAnchor),
            rightPanel.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
            rightPanel.widthAnchor.constraint(equalTo: leftPanel.widthAnchor),

            leftBar.topAnchor.constraint(equalTo: leftPanel.topAnchor), leftBar.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            imgView.topAnchor.constraint(equalTo: leftPanel.topAnchor, constant: 40),
            imgView.leadingAnchor.constraint(equalTo: leftPanel.leadingAnchor),
            imgView.trailingAnchor.constraint(equalTo: leftPanel.trailingAnchor),
            imgView.bottomAnchor.constraint(equalTo: leftPanel.bottomAnchor),
            rightBar.topAnchor.constraint(equalTo: rightPanel.topAnchor), rightBar.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: rightPanel.topAnchor, constant: 40),
            scroll.leadingAnchor.constraint(equalTo: rightPanel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: rightPanel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: rightPanel.bottomAnchor),
            leftLoading.centerXAnchor.constraint(equalTo: imgView.centerXAnchor), leftLoading.centerYAnchor.constraint(equalTo: imgView.centerYAnchor),
            rightLoading.centerXAnchor.constraint(equalTo: scroll.centerXAnchor), rightLoading.centerYAnchor.constraint(equalTo: scroll.centerYAnchor),
        ])
        EscMonitor.add(self)
        // Esc 联动：主窗为 key 时按 Esc，OCR 窗未置顶则一并隐藏（对齐 Lite 主窗/OCR 窗 Esc 联动）。
        // 只观察不吞事件，主窗自身隐藏仍由 EscMonitor 处理（含置顶例外）。
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53, let self, NSApp.keyWindow === MainWindow.shared,
               self.isVisible, self.level == .normal {
                self.orderOut(nil)
            }
            return e
        }
    }

    private static func button(_ t: String, _ target: AnyObject, _ a: Selector) -> NSButton {
        let b = NSButton(title: t, target: target, action: a); b.bezelStyle = .rounded; return b
    }

    private static func loadingView() -> NSStackView {
        let spin = NSProgressIndicator(); spin.style = .spinning; spin.controlSize = .small; spin.startAnimation(nil)
        let s = NSStackView(views: [spin, NSTextField(labelWithString: "文字识别中")])
        s.isHidden = true
        return s
    }

    private func setLoading(_ on: Bool) { leftLoading.isHidden = !on; rightLoading.isHidden = !on }

    /// 关闭被拦截转隐藏（预创建窗口复用）
    override func performClose(_ sender: Any?) { orderOut(nil) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { orderOut(nil); return false }
    /// 失焦且未置顶时自动隐藏
    func windowDidResignKey(_ notification: Notification) { if !pinned { orderOut(nil) } }

    /// 图钉置顶（对齐 Lite ocrThumbtack/ocrAlwaysOnTop）
    private var pinned = false
    @objc private func togglePin() {
        pinned.toggle()
        level = pinned ? .floating : .normal
    }
    @objc private func openSettings() { SettingsWindow.shared.showSettings() }

    func run(imageFile: URL) {
        self.imageFile = imageFile
        imgView.image = NSImage(contentsOf: imageFile)
        imgView.result = nil
        textView.string = ""
        setLoading(true)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        VisionOCR.recognizeDetailed(fileURL: imageFile) { [weak self] result in
            guard let self else { return }
            self.setLoading(false)
            switch result {
            case .success(let r):
                self.imgView.result = r
                self.textView.string = r.allText
                log("[OCR] 完成 行=\(r.lines.count) 长度=\(r.allText.count)")
            case .failure(let error):
                self.textView.string = ""
                log("[OCR] 失败：\(error.localizedDescription)")
                MainWindow.shared.showToast("文字识别失败：\(error.localizedDescription)", kind: .error)
            }
        }
    }

    @objc private func toggleBoxes() { imgView.showBoxes = boxCheck.state == .on }
    @objc private func hideWindow() { orderOut(nil) }

    @objc private func copyImage() {
        guard let img = imgView.image else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([img])
        MainWindow.shared.showToast("复制成功", kind: .success)
    }

    @objc private func copyText() {
        let text = textView.string
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            MainWindow.shared.showToast("复制的文本内容为空", kind: .warning); return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        MainWindow.shared.showToast("复制成功", kind: .success)
    }

    @objc private func sendToTranslate() {
        let t = textView.string.trimmingCharacters(in: .newlines)
        orderOut(nil)
        MainWindow.shared.showForInput(t.isEmpty ? nil : t)
    }
}
