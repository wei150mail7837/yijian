import AppKit
import Carbon.HIToolbox

/// 设置窗口：850x600、隐藏标题栏、不可调大小、单例；左侧 4 项菜单
final class SettingsWindow: NSWindow, NSWindowDelegate {
    static let shared = SettingsWindow()
    /// 对应 setPageMenuIndex：下次打开跳到该页（读后即删）
    static var pendingPageIndex: Int?

    private let menuTitles = ["偏好设置", "高级设置", "全局快捷键设置", "翻译源设置"]
    private var menuItems: [SidebarItem] = []
    private let tabs = NSTabView()
    private let statusLabel = NSTextField(labelWithString: "")
    private var checks: [(NSButton, (Bool) -> Void, () -> Bool)] = []
    private var shortcutFields: [String: ShortcutRecorder] = [:]

    // 偏好设置控件
    private let themePop = NSPopUpButton()
    private let positionPop = NSPopUpButton()
    private let topField = NSTextField()
    private let delayField = NSTextField()
    private let fontField = NSTextField()
    // 翻译源
    private let urlField = NSTextField()
    private let modelField = NSTextField()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        delegate = self
        center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 850, height: 600))
        contentView = content
        let side = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 180, height: 600))
        side.material = .sidebar
        content.addSubview(side)
        for (i, t) in menuTitles.enumerated() {
            let item = SidebarItem(title: t, tag: i) { [weak self] idx in
                DispatchQueue.main.async { self?.select(idx) }
            }
            item.frame = NSRect(x: 16, y: 540 - i * 36, width: 150, height: 28)
            side.addSubview(item)
            menuItems.append(item)
        }
        tabs.tabViewType = .noTabsNoBorder
        tabs.frame = NSRect(x: 190, y: 40, width: 640, height: 530)
        content.addSubview(tabs)
        statusLabel.frame = NSRect(x: 200, y: 12, width: 630, height: 18)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        addPage(buildPreference())
        addPage(buildAdvanced())
        addPage(buildShortcuts())
        addPage(buildSource())
        EscMonitor.add(self)
    }

    // MARK: - 页面搭建

    private func addPage(_ v: NSView) {
        let item = NSTabViewItem(); item.view = v; tabs.addTabViewItem(item)
    }

    private func page() -> NSView { NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 530)) }

    private func note(_ s: String) -> NSView {
        let v = page()
        let l = NSTextField(wrappingLabelWithString: s)
        l.frame = NSRect(x: 0, y: 440, width: 600, height: 60)
        v.addSubview(l); return v
    }

    private func label(_ v: NSView, _ text: String, _ y: CGFloat) {
        let l = NSTextField(labelWithString: text)
        l.frame = NSRect(x: 0, y: y, width: 150, height: 20); l.alignment = .right
        v.addSubview(l)
    }

    private func header(_ v: NSView, _ text: String, _ y: CGFloat) {
        let l = NSTextField(labelWithString: text)
        l.font = .boldSystemFont(ofSize: 13)
        l.frame = NSRect(x: 0, y: y, width: 400, height: 20)
        v.addSubview(l)
    }

    private func check(_ v: NSView, _ title: String, _ y: CGFloat, get: @escaping () -> Bool, set: @escaping (Bool) -> Void) {
        let b = NSButton(checkboxWithTitle: title, target: self, action: #selector(checkChanged(_:)))
        b.frame = NSRect(x: 20, y: y, width: 600, height: 22)
        v.addSubview(b)
        checks.append((b, set, get))
    }

    private func buildPreference() -> NSView {
        let v = page()
        label(v, "主题", 490)
        themePop.addItems(withTitles: ["跟随系统", "明亮", "暗黑"])
        themePop.frame = NSRect(x: 160, y: 486, width: 160, height: 26)
        themePop.target = self; themePop.action = #selector(prefChanged)
        v.addSubview(themePop)
        label(v, "语言", 455)
        let lang = NSPopUpButton(frame: NSRect(x: 160, y: 451, width: 160, height: 26))
        lang.addItem(withTitle: "简体中文"); v.addSubview(lang)
        check(v, "开机自启", 420, get: { Config.launchAtLogin }, set: { [weak self] on in
            if let err = AutoLaunch.apply(on) { self?.statusLabel.stringValue = "开机自启设置失败：\(err)" }
        })
        check(v, "隐藏翻译输入框", 392, get: { Config.hideInput }, set: { Config.hideInput = $0 })
        check(v, "隐藏语言选择栏", 364, get: { Config.hideLanguageBar }, set: { Config.hideLanguageBar = $0 })
        label(v, "显示位置", 330)
        positionPop.addItems(withTitles: ["上次位置", "距顶部百分比", "跟随鼠标"])
        positionPop.frame = NSRect(x: 160, y: 326, width: 160, height: 26)
        positionPop.target = self; positionPop.action = #selector(prefChanged)
        v.addSubview(positionPop)
        for (f, t, y) in [(topField, "距顶部百分比", CGFloat(295)), (delayField, "划词延迟(ms)", 262), (fontField, "字体大小(10-30)", 229)] {
            label(v, t, y)
            f.frame = NSRect(x: 160, y: y - 2, width: 100, height: 22)
            f.target = self; f.action = #selector(prefChanged)
            v.addSubview(f)
        }
        return v
    }

    private func buildAdvanced() -> NSView {
        let v = page()
        header(v, "翻译设置", 495)
        check(v, "换行替换为空格", 468, get: { Config.wrapReplaceSpace }, set: { Config.wrapReplaceSpace = $0 })
        check(v, "显示翻译窗口时保留上次内容", 444, get: { Config.showTranslateNotEmpty }, set: { Config.showTranslateNotEmpty = $0 })
        header(v, "OCR 设置", 410)
        check(v, "OCR 换行替换为空格", 383, get: { Config.ocrWrapReplaceSpace }, set: { Config.ocrWrapReplaceSpace = $0 })
        check(v, "OCR 去除换行", 359, get: { Config.ocrWrapReplace }, set: { Config.ocrWrapReplace = $0 })
        check(v, "OCR 结果写入剪贴板", 335, get: { Config.ocrWriteClipboard }, set: { Config.ocrWriteClipboard = $0 })
        header(v, "功能设置", 301)
        check(v, "置顶时允许 Esc 隐藏", 274, get: { Config.alwaysOnTopAllowEsc }, set: { Config.alwaysOnTopAllowEsc = $0 })
        check(v, "使用系统截图（screencapture -i）", 250, get: { Config.systemScreenshot }, set: { Config.systemScreenshot = $0 })
        check(v, "隐藏菜单栏图标（立即生效）", 226, get: { Config.hideTrayIcon }, set: { on in
            Config.hideTrayIcon = on
            NotificationCenter.default.post(name: .trayVisibilityChanged, object: nil)
        })
        check(v, "输入时自动翻译", 202, get: { Config.inputTranslationAuto }, set: { Config.inputTranslationAuto = $0 })
        check(v, "复制结果为小驼峰", 178, get: { Config.copyCamelCaseResult }, set: { Config.copyCamelCaseResult = $0 })
        check(v, "复制结果为下划线", 154, get: { Config.copySnakeCaseResult }, set: { Config.copySnakeCaseResult = $0 })
        let ax = NSButton(title: "申请辅助功能权限（划词取词需要）", target: self, action: #selector(grantAX))
        ax.bezelStyle = .rounded
        ax.frame = NSRect(x: 20, y: 110, width: 300, height: 28)
        v.addSubview(ax)
        return v
    }

    private func buildShortcuts() -> NSView {
        let v = page()
        header(v, "点击输入框后直接按下组合键即录入；Esc 取消，Delete 清空（注销）。", 495)
        for (i, item) in Config.shortcutKeys.enumerated() {
            let y = CGFloat(455 - i * 38)
            label(v, item.name, y)
            let f = ShortcutRecorder(frame: NSRect(x: 160, y: y - 4, width: 220, height: 26))
            f.slot = item.key
            f.onCommit = { [weak self] key, raw in self?.commitShortcut(key: key, raw: raw) }
            v.addSubview(f)
            shortcutFields[item.key] = f
        }
        return v
    }

    private func buildSource() -> NSView {
        let v = page()
        label(v, "翻译通道", 520)
        let ch = NSTextField(labelWithString: "Ollama（本地 / 自建 OpenAI 兼容接口）")
        ch.frame = NSRect(x: 160, y: 520, width: 380, height: 20)
        ch.textColor = .secondaryLabelColor
        v.addSubview(ch)
        label(v, "接口地址", 490)
        urlField.frame = NSRect(x: 160, y: 488, width: 460, height: 22)
        urlField.placeholderString = "http://127.0.0.1:11434/v1/chat/completions"
        v.addSubview(urlField)
        label(v, "模型名", 455)
        modelField.frame = NSRect(x: 160, y: 453, width: 460, height: 22)
        modelField.placeholderString = "Ollama 模型名，如 hymt2"
        v.addSubview(modelField)
        let save = NSButton(title: "保存", target: self, action: #selector(saveSource))
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        save.frame = NSRect(x: 520, y: 340, width: 100, height: 28)
        v.addSubview(save)
        return v
    }

    // MARK: - 展示

    func showSettings() {
        reload()
        let idx = Self.pendingPageIndex ?? 0
        Self.pendingPageIndex = nil
        select(idx)
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func reload() {
        for (b, _, get) in checks { b.state = get() ? .on : .off }
        themePop.selectItem(at: Config.theme)
        positionPop.selectItem(at: Config.showPosition)
        topField.stringValue = "\(Config.topPercent)"
        delayField.stringValue = "\(Config.selectionDelay)"
        fontField.stringValue = "\(Config.winFontSize)"
        urlField.stringValue = Config.ollamaURL
        modelField.stringValue = Config.model
        for (k, f) in shortcutFields { f.stringValue = Config.shortcut(k) }
        applyTheme()
    }

    private func select(_ i: Int) {
        tabs.selectTabViewItem(at: i)
        for item in menuItems { item.selected = (item.tag == i) }
        statusLabel.stringValue = ""
    }

    private func applyTheme() {
        switch Config.theme {
        case 1: NSApp.appearance = NSAppearance(named: .aqua)
        case 2: NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    // MARK: - 事件

    @objc private func checkChanged(_ b: NSButton) {
        guard let entry = checks.first(where: { $0.0 === b }) else { return }
        entry.1(b.state == .on)
        b.state = entry.2() ? .on : .off
        log("[设置] 开关变更")
    }

    @objc private func prefChanged() {
        Config.theme = themePop.indexOfSelectedItem
        Config.showPosition = positionPop.indexOfSelectedItem
        if let n = Int(topField.stringValue) { Config.topPercent = n }
        if let n = Int(delayField.stringValue) { Config.selectionDelay = n }
        if let n = Int(fontField.stringValue) { Config.winFontSize = n }
        reload()
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
    }

    /// 更新流程：先注册新键，成功后注销旧键；新键为空则直接注销旧键并写空串
    private func commitShortcut(key: String, raw rawIn: String) {
        guard let f = shortcutFields[key],
              let item = Config.shortcutKeys.first(where: { $0.key == key }),
              let app = NSApp.delegate as? AppDelegate else { return }
        let raw = rawIn.trimmingCharacters(in: .whitespaces)
        if raw.isEmpty {
            Shortcuts.shared.unregister(slot: key)
            Config.setShortcut(key, "")
            statusLabel.stringValue = "\(item.name)快捷键已清空"
            return
        }
        guard let norm = ShortcutParser.normalize(raw) else {
            statusLabel.stringValue = "无效的快捷键（需含主键，纯修饰键/空格/+-* 不可用）"
            f.stringValue = Config.shortcut(key); return
        }
        if ShortcutParser.conflictsWithSystem(norm) {
            statusLabel.stringValue = "当前按下的快捷键可能与系统的冲突，无法进行设置"
            f.stringValue = Config.shortcut(key); return
        }
        if let err = Shortcuts.shared.register(slot: key, name: item.name, combo: norm, handler: app.action(for: key)) {
            statusLabel.stringValue = err
            f.stringValue = Config.shortcut(key); return
        }
        Config.setShortcut(key, norm)
        f.stringValue = norm
        statusLabel.stringValue = "\(item.name)快捷键已设置为 \(norm)"
    }

    @objc private func saveSource() {
        Config.ollamaURL = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        Config.model = modelField.stringValue.trimmingCharacters(in: .whitespaces)
        statusLabel.stringValue = "已保存"
        log("[设置] 翻译源已保存")
    }

    @objc private func grantAX() { SelectionReader.promptAccessibility() }
}

extension Notification.Name {
    static let trayVisibilityChanged = Notification.Name("trayVisibilityChanged")
    static let settingsChanged = Notification.Name("ttimeSettingsChanged")
}

/// 实时按键捕获控件：点击进入录入态，按下即显示修饰键，按下主键即提交。
/// IME 保护：只用 keyCode（物理键位）映射主键，不读 characters，也不接入 NSTextInputContext，
/// 故中文输入法开启时不会进入组字态；录入期间临时注销全局热键，避免已占用组合被系统先吞。
final class ShortcutRecorder: NSButton {
    var slot = ""
    var onCommit: ((String, String) -> Void)?
    var stringValueStore = ""
    private var recording = false { didSet { refresh() } }
    private var liveMods = ""

    override var stringValue: String {
        get { stringValueStore }
        set { stringValueStore = newValue; refresh() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self; action = #selector(begin)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError() }

    override var acceptsFirstResponder: Bool { true }
    override var inputContext: NSTextInputContext? { nil }

    private static let codeToName: [Int: String] = {
        var m: [Int: String] = [:]
        for (k, v) in ShortcutParser.keyMap { m[v] = k.count == 1 ? k : k.prefix(1) + k.dropFirst().lowercased() }
        m[kVK_Return] = "Enter"; m[kVK_Escape] = "Esc"; m[kVK_Tab] = "Tab"
        return m
    }()

    private func refresh() {
        if recording {
            title = liveMods.isEmpty ? "请按下组合键…" : liveMods + "+…"
            contentTintColor = .controlAccentColor
        } else {
            title = stringValueStore.isEmpty ? "未配置（点击录入）" : stringValueStore
            contentTintColor = stringValueStore.isEmpty ? .secondaryLabelColor : nil
        }
    }

    private static func modString(_ f: NSEvent.ModifierFlags) -> String {
        var p: [String] = []
        if f.contains(.option) { p.append("Alt") }
        if f.contains(.control) { p.append("Ctrl") }
        if f.contains(.command) { p.append("Command") }
        if f.contains(.shift) { p.append("Shift") }
        return p.joined(separator: "+")
    }

    @objc private func begin() {
        if recording { end(commit: nil); return }
        Shortcuts.shared.unregisterAll()
        liveMods = ""
        recording = true
        window?.makeFirstResponder(self)
        // 保险：点窗口其他任何地方都结束录入并恢复热键
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] e in
            guard let self, self.recording, let w = self.window else { return e }
            let loc = e.locationInWindow
            let inRecorder = w.contentView?.hitTest(loc) === self
            if !inRecorder { self.end(commit: nil) }
            return e
        }
    }
    private var clickMonitor: Any?

    private func end(commit raw: String?) {
        guard recording else { return }
        recording = false
        if let m = clickMonitor { NSEvent.removeMonitor(m); clickMonitor = nil }
        let errors = (NSApp.delegate as? AppDelegate)?.registerAllShortcuts() ?? []
        if !errors.isEmpty { log("快捷键恢复失败：\(errors.joined(separator: "；"))") }
        if let raw { onCommit?(slot, raw) }
    }

    override func resignFirstResponder() -> Bool {
        end(commit: nil)
        return super.resignFirstResponder()
    }

    override func flagsChanged(with event: NSEvent) {
        guard recording else { return super.flagsChanged(with: event) }
        liveMods = Self.modString(event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        refresh()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        handle(event); return true
    }

    override func keyDown(with event: NSEvent) {
        guard recording else { return super.keyDown(with: event) }
        handle(event)
    }

    private func handle(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection([.option, .control, .command, .shift])
        let code = Int(event.keyCode)
        if flags.isEmpty && code == kVK_Escape { end(commit: nil); return }
        if flags.isEmpty && (code == kVK_Delete || code == kVK_ForwardDelete) { end(commit: ""); return }
        guard let name = Self.codeToName[code] else { NSSound.beep(); return }
        let mods = Self.modString(flags)
        end(commit: mods.isEmpty ? name : mods + "+" + name)
    }
}


/// 侧栏菜单项：自绘视图（无 NSButton 状态机）。悬停淡底、选中强调色底白字。
final class SidebarItem: NSView {
    let itemTag: Int
    var selected = false { didSet { needsDisplay = true } }
    private var hover = false { didSet { needsDisplay = true } }
    private let label: NSTextField
    private var onSelect: (Int) -> Void

    init(title: String, tag: Int, onSelect: @escaping (Int) -> Void) {
        self.itemTag = tag
        self.onSelect = onSelect
        label = NSTextField(labelWithString: title)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerRadius = 6
        label.frame = NSRect(x: 12, y: 5, width: 130, height: 18)
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if trackingAreas.contains(where: { $0.options.contains(.mouseEnteredAndExited) }) { return }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func mouseEntered(with event: NSEvent) { hover = true }
    override func mouseExited(with event: NSEvent) { hover = false }
    override func mouseDown(with event: NSEvent) { onSelect(itemTag) }

    override func draw(_ dirtyRect: NSRect) {
        if selected {
            NSColor.controlAccentColor.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            label.textColor = .white
        } else {
            if hover {
                NSColor.quaternaryLabelColor.setFill()
                NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            }
            label.textColor = .labelColor
        }
    }
}
