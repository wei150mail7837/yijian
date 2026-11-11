import AppKit
import Carbon.HIToolbox
import ServiceManagement

/// 应用入口：单实例、托盘、快捷键、窗口编排
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    static let reopenNote = Notification.Name("com.isa.ttimenative.reopen")

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 单实例：已有同 bundle 实例在跑 → 通知它 translateInput 后本实例退出
        let me = ProcessInfo.processInfo.processIdentifier
        let bid = Bundle.main.bundleIdentifier ?? "com.isa.ttimenative"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bid)
            .filter { $0.processIdentifier != me }
        if !others.isEmpty {
            DistributedNotificationCenter.default().postNotificationName(Self.reopenNote, object: nil,
                                                                         userInfo: nil, deliverImmediately: true)
            log("[单实例] 已有实例运行，本实例退出")
            exit(0)
        }
        // uncaughtException 兜底：只记日志（Swift 运行时致命错误无法拦截，仅 ObjC 异常可记）
        NSSetUncaughtExceptionHandler { ex in log("[异常] \(ex.name.rawValue) \(ex.reason ?? "")") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(secondInstance),
                                                            name: Self.reopenNote, object: nil)
        rebuildTray()
        registerAllShortcuts()
        NotificationCenter.default.addObserver(self, selector: #selector(trayChanged),
                                               name: .trayVisibilityChanged, object: nil)
        // 启动 5s 后同步一次自启状态（对应 autoLaunchFront 初始化检测）
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { AutoLaunch.sync() }
        log("[启动] 完成")
    }

    func applicationWillTerminate(_ notification: Notification) {
        Shortcuts.shared.unregisterAll()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        translateInput()
        return true
    }

    @objc private func secondInstance() { translateInput() }

    @objc private func trayChanged() { rebuildTray() }

    // MARK: - 托盘

    private func rebuildTray() {
        if let old = statusItem { NSStatusBar.system.removeStatusItem(old); statusItem = nil }
        guard !Config.hideTrayIcon else {
            log("[托盘] 已隐藏菜单栏图标")
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = makeTrayIcon()
            button.toolTip = "TTime"
        }
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let v = NSMenuItem(title: "TTime 版本 " + version, action: nil, keyEquivalent: "")
        v.isEnabled = false
        menu.autoenablesItems = false
        menu.addItem(v)
        menu.addItem(.separator())
        menu.addItem(withTitle: "输入翻译", action: #selector(showMain), keyEquivalent: "")
        menu.addItem(withTitle: "截图翻译", action: #selector(screenshotTranslate), keyEquivalent: "")
        menu.addItem(withTitle: "截图OCR", action: #selector(screenshotOCR), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "查看日志", action: #selector(openLogs), keyEquivalent: "")
        menu.addItem(withTitle: "设置", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "重启TTime", action: #selector(relaunch), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
        for menuItem in menu.items where menuItem.action != nil { menuItem.target = self }
        item.menu = menu
        statusItem = item
    }

    /// 程序化 16pt template 图标：对话气泡 + 「T」与「文」交叠（翻译意象）
    private func makeTrayIcon() -> NSImage? {
        // 优先使用 build.sh 生成并打包的 template 资产（与 App 图标同母题），缺失时回退手绘
        if let img = Bundle.main.image(forResource: "trayTemplate") {
            img.size = NSSize(width: 18, height: 18); img.isTemplate = true
            return img
        }
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            NSColor.black.set()
            // 左气泡（实心）带尾巴
            let left = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 5, width: 9.5, height: 10.5), xRadius: 2.5, yRadius: 2.5)
            left.move(to: NSPoint(x: 2.5, y: 5.5)); left.line(to: NSPoint(x: 2, y: 2.5)); left.line(to: NSPoint(x: 5.5, y: 5.5))
            left.fill()
            // 镂空 T
            NSGraphicsContext.current?.compositingOperation = .clear
            NSRect(x: 2.5, y: 12, width: 5.5, height: 1.6).fill()
            NSRect(x: 4.45, y: 7, width: 1.6, height: 5).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            // 右气泡（描边）
            let right = NSBezierPath(roundedRect: NSRect(x: 6.5, y: 1, width: 9, height: 9), xRadius: 2.2, yRadius: 2.2)
            NSGraphicsContext.current?.compositingOperation = .clear
            right.fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            right.lineWidth = 1.2
            right.stroke()
            // 右气泡内「文」字简笔
            let wen = NSBezierPath()
            wen.lineWidth = 1.1
            wen.move(to: NSPoint(x: 11, y: 8.6)); wen.line(to: NSPoint(x: 11, y: 7.6))
            wen.move(to: NSPoint(x: 8.6, y: 7.4)); wen.line(to: NSPoint(x: 13.4, y: 7.4))
            wen.move(to: NSPoint(x: 9.4, y: 6.6)); wen.line(to: NSPoint(x: 12.8, y: 2.6))
            wen.move(to: NSPoint(x: 12.6, y: 6.6)); wen.line(to: NSPoint(x: 9.2, y: 2.6))
            wen.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - 快捷键

    /// 按配置注册全部快捷键；返回失败文案列表
    @discardableResult
    func registerAllShortcuts() -> [String] {
        Shortcuts.shared.unregisterAll()
        var errors: [String] = []
        for (key, name, _) in Config.shortcutKeys {
            let combo = Config.shortcut(key)
            guard !combo.isEmpty else { continue }
            if let err = Shortcuts.shared.register(slot: key, name: name, combo: combo, handler: action(for: key)) {
                errors.append(err)
            }
        }
        return errors
    }

    func action(for key: String) -> () -> Void {
        switch key {
        case "translateShortcutKey": return { [weak self] in self?.translateInput() }
        case "screenshotTranslateShortcutKey": return { [weak self] in self?.screenshotTranslate() }
        case "selectionTranslateShortcutKey": return { [weak self] in self?.wordSelection() }
        case "showOcrShortcutKey": return { OCRWindow.shared.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
        default: return { [weak self] in self?.screenshotOCR() }
        }
    }

    // MARK: - 动作

    /// 对应 Electron translateInput()：显示主窗口；showTranslateNotEmpty=N 时清空
    func translateInput() {
        MainWindow.shared.showForInput(nil)
    }

    @objc private func showMain() { translateInput() }

    @objc private func screenshotTranslate() {
        log("[截图翻译] 托盘/快捷键触发")
        captureWithEngine { file in
            guard let file else { return }
            VisionOCR.recognize(fileURL: file) { result in
                switch result {
                case .success(let text):
                    log("[截图翻译] 识别 长度=\(text.count)")
                    MainWindow.shared.showForInput(text.isEmpty ? nil : text)
                case .failure(let error):
                    log("[截图翻译] 失败：\(error.localizedDescription)")
                    MainWindow.shared.showForInput(nil)
                    MainWindow.shared.showErrorMessage(error.localizedDescription)
                }
            }
        }
    }

    @objc private func screenshotOCR() {
        captureWithEngine { file in
            guard let file else { return }
            OCRWindow.shared.run(imageFile: file)
        }
    }

    @objc private func wordSelection() {
        SelectionReader.readSelection { text in
            if let text, !text.isEmpty { MainWindow.shared.showForInput(text) }
        }
    }

    private func captureWithEngine(completion: @escaping (URL?) -> Void) {
        ScreenshotService.capture { url in
            if url == nil { log("[截图] 已取消") }
            completion(url)
        }
    }

    @objc private func openLogs() {
        NSWorkspace.shared.open(logFile.deletingLastPathComponent())
    }

    @objc private func openSettings() { SettingsWindow.shared.showSettings() }

    @objc private func relaunch() {
        let path = Bundle.main.bundlePath
        // 先退出再拉起，避免被单实例检测拦下
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 0.8; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quitApp() { NSApp.terminate(nil) }
}

extension MainWindow {
    static func showErrorMessage(_ message: String) { shared.showErrorMessage(message) }
}


// MARK: - 开机自启（SMAppService，查状态幂等）

enum AutoLaunch {
    /// 按 Config.launchAtLogin 写入；已是目标状态则不重复操作；结果回写配置。返回错误文案
    @discardableResult
    static func apply(_ want: Bool) -> String? {
        guard #available(macOS 13.0, *) else { return "系统版本不支持" }
        if Bundle.main.bundlePath.hasSuffix(".app") == false { return nil } // 开发环境（裸二进制）跳过
        let svc = SMAppServiceBridge.self
        do {
            if want, !svc.enabled { try svc.register() }
            if !want, svc.enabled { try svc.unregister() }
            Config.launchAtLogin = svc.enabled
            return nil
        } catch {
            Config.launchAtLogin = svc.enabled
            log("[自启] 失败 \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    static func sync() {
        guard #available(macOS 13.0, *) else { return }
        if UserDefaults.standard.object(forKey: "launchAtLogin") == nil {
            Config.launchAtLogin = SMAppServiceBridge.enabled
        }
    }
}

@available(macOS 13.0, *)
enum SMAppServiceBridge {
    static var enabled: Bool { SMAppService.mainApp.status == .enabled }
    static func register() throws { try SMAppService.mainApp.register() }
    static func unregister() throws { try SMAppService.mainApp.unregister() }
}

// MARK: - 可配置全局快捷键（Carbon，独立签名，支持注销）

final class Shortcuts {
    static let shared = Shortcuts()
    private var refs: [String: EventHotKeyRef] = [:]
    private var combos: [String: String] = [:]
    private var handlers: [UInt32: () -> Void] = [:]
    private var ids: [String: UInt32] = [:]
    private var nextID: UInt32 = 100
    private var installed = false

    /// 注册；成功返回 nil，失败返回 '{name}快捷键已注册/注册失败'
    func register(slot: String, name: String, combo: String, handler: @escaping () -> Void) -> String? {
        install()
        guard let (code, mods) = ShortcutParser.parse(combo) else {
            log("[快捷键] 解析失败 \(name)=\(combo)")
            return "\(name)快捷键注册失败"
        }
        if combos.contains(where: { $0.key != slot && $0.value == combo }) {
            log("[快捷键] 已注册 \(name)=\(combo)")
            return "\(name)快捷键已注册"
        }
        let id = nextID; nextID += 1
        var ref: EventHotKeyRef?
        let st = RegisterEventHotKey(code, mods, EventHotKeyID(signature: OSType(0x54544D45), id: id),
                                     GetApplicationEventTarget(), 0, &ref)
        guard st == noErr, let ref else {
            log("[快捷键] 注册失败 \(name)=\(combo) status=\(st)")
            return st == eventHotKeyExistsErr ? "\(name)快捷键已注册" : "\(name)快捷键注册失败"
        }
        unregister(slot: slot)
        refs[slot] = ref; combos[slot] = combo; ids[slot] = id; handlers[id] = handler
        log("[快捷键] 已注册 \(name)=\(combo)")
        return nil
    }

    func unregister(slot: String) {
        if let r = refs.removeValue(forKey: slot) { UnregisterEventHotKey(r) }
        combos.removeValue(forKey: slot)
        if let id = ids.removeValue(forKey: slot) { handlers.removeValue(forKey: id) }
    }

    func unregisterAll() { for k in Array(refs.keys) { unregister(slot: k) } }

    private func install() {
        guard !installed else { return }
        installed = true
        var t = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard hk.signature == OSType(0x54544D45) else { return OSStatus(eventNotHandledErr) }
            let id = hk.id
            DispatchQueue.main.async { Shortcuts.shared.handlers[id]?() }
            return noErr
        }, 1, &t, nil, nil)
    }
}

/// "Alt+Ctrl+Command+Shift+Key" ↔ Carbon 键码
enum ShortcutParser {
    static let keyMap: [String: Int] = [
        "A": kVK_ANSI_A, "B": kVK_ANSI_B, "C": kVK_ANSI_C, "D": kVK_ANSI_D, "E": kVK_ANSI_E, "F": kVK_ANSI_F,
        "G": kVK_ANSI_G, "H": kVK_ANSI_H, "I": kVK_ANSI_I, "J": kVK_ANSI_J, "K": kVK_ANSI_K, "L": kVK_ANSI_L,
        "M": kVK_ANSI_M, "N": kVK_ANSI_N, "O": kVK_ANSI_O, "P": kVK_ANSI_P, "Q": kVK_ANSI_Q, "R": kVK_ANSI_R,
        "S": kVK_ANSI_S, "T": kVK_ANSI_T, "U": kVK_ANSI_U, "V": kVK_ANSI_V, "W": kVK_ANSI_W, "X": kVK_ANSI_X,
        "Y": kVK_ANSI_Y, "Z": kVK_ANSI_Z,
        "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
        "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
        "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4, "F5": kVK_F5, "F6": kVK_F6,
        "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11, "F12": kVK_F12,
        "TAB": kVK_Tab, "ENTER": kVK_Return, "ESC": kVK_Escape,
        "UP": kVK_UpArrow, "DOWN": kVK_DownArrow, "LEFT": kVK_LeftArrow, "RIGHT": kVK_RightArrow,
        ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash, ";": kVK_ANSI_Semicolon,
        "'": kVK_ANSI_Quote, "[": kVK_ANSI_LeftBracket, "]": kVK_ANSI_RightBracket, "`": kVK_ANSI_Grave,
        "=": kVK_ANSI_Equal,
    ]
    static let modOrder = ["Alt", "Ctrl", "Command", "Shift"]

    static func parse(_ combo: String) -> (UInt32, UInt32)? {
        let parts = combo.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let main = parts.last, let code = keyMap[main.uppercased()] else { return nil }
        var mods: UInt32 = 0
        for p in parts.dropLast() {
            switch p.lowercased() {
            case "alt", "option": mods |= UInt32(optionKey)
            case "ctrl", "control": mods |= UInt32(controlKey)
            case "command", "cmd", "commandorcontrol": mods |= UInt32(cmdKey)
            case "shift": mods |= UInt32(shiftKey)
            default: return nil
            }
        }
        return (UInt32(code), mods)
    }

    /// 规范化为 Alt+Ctrl+Command+Shift+主键(大写)；纯修饰键/空格/+-* 返回 nil
    static func normalize(_ combo: String) -> String? {
        let parts = combo.split(separator: "+").map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let main = parts.last?.uppercased(), !main.isEmpty, keyMap[main] != nil else { return nil }
        var set = Set<String>()
        for p in parts.dropLast() {
            switch p.lowercased() {
            case "alt", "option": set.insert("Alt")
            case "ctrl", "control": set.insert("Ctrl")
            case "command", "cmd": set.insert("Command")
            case "shift": set.insert("Shift")
            default: return nil
            }
        }
        return (modOrder.filter { set.contains($0) } + [main]).joined(separator: "+")
    }

    /// 系统冲突：Ctrl/Command+Z/X/C/V、Command+Q、Alt+Tab
    static func conflictsWithSystem(_ normalized: String) -> Bool {
        let blocked = ["Ctrl+Z", "Ctrl+X", "Ctrl+C", "Ctrl+V", "Command+Z", "Command+X", "Command+C",
                       "Command+V", "Command+Q", "Alt+TAB"]
        return blocked.contains(normalized)
    }
}
