import AppKit

/// 语言栏按钮：显示当前语种，点击弹出语种面板（对齐 Lite LanguageSelect.vue 的自绘面板形态）
final class LanguageBarButton: NSButton {
    let isSource: Bool
    weak var rootWindow: NSWindow?
    static var openPanel: LanguagePanelWindow?

    init(isSource: Bool) {
        self.isSource = isSource
        super.init(frame: .zero)
        setButtonType(.momentaryPushIn)
        isBordered = false
        font = .systemFont(ofSize: 12)
        wantsLayer = true
        layer?.cornerRadius = 5
        contentTintColor = .labelColor
        target = nil
        action = nil
        refreshTitle(current: isSource ? "auto" : "zh")
    }
    required init?(coder: NSCoder) { fatalError() }

    func refreshTitle(current: String) {
        title = current == "auto" ? "自动识别" : TLanguage.find(current).name
    }

    override func mouseDown(with event: NSEvent) { togglePanel() }

    private func togglePanel() {
        if let p = Self.openPanel, p.isVisible {
            p.closePanel()
            return
        }
        let panel = LanguagePanelWindow(isSource: isSource, anchor: self) { [weak self] type in
            DispatchQueue.main.async {
                if self?.isSource == true { Pref.inputLanguage = type }
                else { Pref.resultLanguage = type == "auto" ? OllamaClient.autoTarget(for: Pref.inputLanguage == "auto" ? "" : Pref.inputLanguage) : type }
                self?.refreshTitle(current: type)
                self?.rootWindow?.makeKeyAndOrderFront(nil)
            }
        }
        Self.openPanel = panel
        panel.showPanel()
    }
}

/// 语种面板：搜索框 + chip 网格（129 语种全量，对齐 Lite LanguageSelect.vue）
final class LanguagePanelWindow: NSPanel {
    private let isSource: Bool
    private let onSelect: (String) -> Void
    private let anchor: NSView
    private let searchField = NSSearchField()
    private let chipsView = NSView()
    private var outsideMonitor: Any?
    private var escMonitor: Any?

    init(isSource: Bool, anchor: NSView, onSelect: @escaping (String) -> Void) {
        self.isSource = isSource
        self.anchor = anchor
        self.onSelect = onSelect
        let size = NSSize(width: 340, height: 380)
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .titled], backing: .buffered, defer: false)
        styleMask.insert(.fullSizeContentView)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        isMovableByWindowBackground = false
        level = .floating + 1
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let content = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        content.material = .popover
        content.state = .active
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        contentView = content

        searchField.frame = NSRect(x: 12, y: size.height - 40, width: size.width - 24, height: 26)
        searchField.placeholderString = "搜索语种…"
        searchField.font = .systemFont(ofSize: 12)
        searchField.target = self
        searchField.action = #selector(searchChanged)
        content.addSubview(searchField)

        let scroll = NSScrollView(frame: NSRect(x: 8, y: 10, width: size.width - 16, height: size.height - 58))
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        chipsView.frame = NSRect(x: 0, y: 0, width: scroll.contentSize.width, height: 0)
        scroll.documentView = chipsView
        content.addSubview(scroll)

        rebuildChips(filter: "")
    }

    private var chipButtons: [ChipLanguageButton] = []

    /// 手排 chip 网格（纯 frame，无自动布局依赖）
    private func rebuildChips(filter: String) {
        chipButtons.forEach { $0.removeFromSuperview() }
        chipButtons.removeAll()
        let current = isSource ? Pref.inputLanguage : Pref.resultLanguage
        let list = LanguageList.all.filter {
            filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.type.localizedCaseInsensitiveContains(filter)
        }
        let sourceList: [(String, String)] = isSource ? [("自动识别", "auto")] + list : list
        let perRow = 3
        let chipW: CGFloat = 102, chipH: CGFloat = 24, gap: CGFloat = 6, pad: CGFloat = 4
        let contentW = chipsView.superview?.bounds.width ?? 324
        let rows = Int(ceil(Double(sourceList.count) / Double(perRow)))
        let contentH = max(CGFloat(rows) * (chipH + gap) + pad, chipsView.superview?.bounds.height ?? 0)
        chipsView.frame.size.height = contentH
        for (i, item) in sourceList.enumerated() {
            let row = i / perRow, col = i % perRow
            let chip = ChipLanguageButton(name: item.0, type: item.1, current: current) { [weak self] picked in
                self?.closePanel()
                self?.onSelect(picked)
            }
            // documentView 原点在左下：第 0 行放最上面
            let y = contentH - pad - chipH - CGFloat(row) * (chipH + gap)
            chip.frame = NSRect(x: pad + CGFloat(col) * (chipW + gap), y: y,
                                width: chipW, height: chipH)
            chipsView.addSubview(chip)
            chipButtons.append(chip)
        }
    }

    @objc private func searchChanged() {
        rebuildChips(filter: searchField.stringValue)
    }

    func showPanel() {
        // 定位：锚点按钮正下方（屏幕坐标）
        guard let window = anchor.window else { return }
        let btnFrame = window.convertPoint(toScreen: NSPoint(x: anchor.frame.midX, y: anchor.frame.minY))
        let size = frame.size
        var origin = NSPoint(x: btnFrame.x - size.width / 2, y: btnFrame.y - size.height - 6)
        let vf = (NSScreen.screens.first { $0.frame.contains(btnFrame) } ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        if origin.y < vf.minY { origin.y = btnFrame.y + anchor.frame.height + 6 }
        origin.x = min(max(origin.x, vf.minX + 4), vf.maxX - size.width - 4)
        setFrameOrigin(origin)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        searchField.becomeFirstResponder()
        // 点击面板外 / Esc 关闭（面板自身监视器先于全局 EscMonitor 注册）
        escMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.closePanel(); return nil }
            return e
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.closePanel()
        }
    }

    func closePanel() {
        if let m = escMonitor { NSEvent.removeMonitor(m); escMonitor = nil }
        chipsView.frame.origin.y = 0
        if let m = outsideMonitor { NSEvent.removeMonitor(m); outsideMonitor = nil }
        orderOut(nil)
        if LanguageBarButton.openPanel === self { LanguageBarButton.openPanel = nil }
    }
}

/// 语种 chip 按钮：选中态强调色
final class ChipLanguageButton: NSButton {
    let type: String
    private var onSelect: (String) -> Void

    init(name: String, type: String, current: String, onSelect: @escaping (String) -> Void) {
        self.type = type
        self.onSelect = onSelect
        super.init(frame: .zero)
        title = name
        setButtonType(.momentaryPushIn)
        isBordered = false
        font = .systemFont(ofSize: 11)
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        target = self
        action = #selector(pickedChip)
        updateSelected(current == type)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func updateSelected(_ selected: Bool) {
        if selected {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
            contentTintColor = .white
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            contentTintColor = .labelColor
        }
    }

    @objc private func pickedChip() {
        updateSelected(true)
        onSelect(type)
    }
}
