import AppKit

/// 应用入口：托盘、快捷键、窗口编排
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
        rebuildTray()
        registerHotKeys()
        NotificationCenter.default.addObserver(self, selector: #selector(trayChanged),
                                               name: .trayVisibilityChanged, object: nil)
        log("[启动] 完成")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 双击 app 唤起主窗口（单实例场景）
        MainWindow.shared.showForInput(nil)
        return true
    }

    @objc private func trayChanged() {
        rebuildTray()
    }

    // MARK: - 托盘

    private func rebuildTray() {
        statusItem?.isVisible = false
        guard !Config.hideTrayIcon else {
            log("[托盘] 已隐藏菜单栏图标")
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = makeTrayIcon()
            button.toolTip = "TTime Native"
        }
        let menu = NSMenu()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        menu.addItem(withTitle: "版本 " + version, action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "输入翻译", action: #selector(showMain), keyEquivalent: "")
        menu.addItem(withTitle: "截图翻译", action: #selector(screenshotTranslate), keyEquivalent: "")
        menu.addItem(withTitle: "截图 OCR", action: #selector(screenshotOCR), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "设置", action: #selector(openSettings), keyEquivalent: "")
        menu.addItem(withTitle: "重启", action: #selector(relaunch), keyEquivalent: "")
        menu.addItem(withTitle: "退出", action: #selector(quitApp), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    private func makeTrayIcon() -> NSImage? {
        // 程序化生成 template 图标：圆角方 + T 字
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.black.setStroke()
        let path = NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 16, height: 16), xRadius: 4, yRadius: 4)
        path.lineWidth = 1.5
        path.stroke()
        NSColor.black.set()
        let t = NSBezierPath()
        t.lineWidth = 2
        t.move(to: NSPoint(x: 5, y: 12)); t.line(to: NSPoint(x: 13, y: 12))
        t.move(to: NSPoint(x: 9, y: 12)); t.line(to: NSPoint(x: 9, y: 5))
        t.stroke()
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    // MARK: - 快捷键

    private func registerHotKeys() {
        HotKeys.shared.register(id: 1, keyCode: HK.q, modifiers: HK.opt) { [weak self] in
            self?.showMain()
        }
        HotKeys.shared.register(id: 2, keyCode: HK.w, modifiers: HK.opt) { [weak self] in
            self?.screenshotTranslate()
        }
        HotKeys.shared.register(id: 3, keyCode: HK.e, modifiers: HK.opt) { [weak self] in
            self?.wordSelection()
        }
        HotKeys.shared.register(id: 4, keyCode: HK.w, modifiers: HK.opt | HK.shift) { [weak self] in
            self?.screenshotOCR()
        }
    }

    // MARK: - 动作

    @objc private func showMain() {
        MainWindow.shared.showForInput(nil)
    }

    @objc private func screenshotTranslate() {
        captureWithEngine { [weak self] file in
            guard let self, let file else { return }
            VisionOCR.recognize(fileURL: file) { result in
                switch result {
                case .success(let text):
                    log("[截图翻译] 识别 长度=\(text.count)")
                    MainWindow.shared.showForInput(text.isEmpty ? nil : text)
                case .failure(let error):
                    log("[截图翻译] 失败")
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
            if let text, !text.isEmpty {
                MainWindow.shared.showForInput(text)
            }
        }
    }

    private func captureWithEngine(completion: @escaping (URL?) -> Void) {
        guard Config.systemScreenshot else {
            log("[截图] 内置引擎未实现，回落系统截图")
            ScreenshotService.capture(completion: completion)
            return
        }
        ScreenshotService.capture { url in
            if url == nil { log("[截图] 已取消") }
            completion(url)
        }
    }

    @objc private func openSettings() {
        SettingsWindow.shared.showSettings()
    }

    @objc private func relaunch() {
        let url = URL(fileURLWithPath: Bundle.main.bundlePath)
        NSWorkspace.shared.open(url)
        NSApp.terminate(nil)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

// 小工具：MainWindow 的错误展示桥（避免把错误逻辑塞进窗口类）
extension MainWindow {
    static func showErrorMessage(_ message: String) {
        shared.showErrorMessage(message)
    }
}
