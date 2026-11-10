import AppKit
import ServiceManagement

/// 设置窗口：接口/模型 + 三个开关
final class SettingsWindow: NSWindow, NSTextFieldDelegate {
    static let shared = SettingsWindow()

    private let urlField = NSTextField()
    private let modelField = NSTextField()
    private let systemShotCheck = NSButton(checkboxWithTitle: "使用系统截图（screencapture -i）", target: nil, action: nil)
    private let hideTrayCheck = NSButton(checkboxWithTitle: "隐藏菜单栏图标（保存后立即生效）", target: nil, action: nil)
    private let launchCheck = NSButton(checkboxWithTitle: "开机自启", target: nil, action: nil)
    private let axButton = NSButton(title: "申请辅助功能权限（划词取词需要）", target: nil, action: nil)
    private let saveButton = NSButton(title: "保存", target: nil, action: nil)
    private let statusLabel = NSTextField(labelWithString: "")

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 300),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        title = "设置"
        isReleasedWhenClosed = false
        center()

        let content = NSView(frame: NSRect(x: 0, y: 0, width: 520, height: 300))
        contentView = content
        let label = { (text: String, y: CGFloat) -> NSTextField in
            let l = NSTextField(labelWithString: text)
            l.frame = NSRect(x: 16, y: y, width: 96, height: 20)
            l.alignment = .right
            return l
        }

        urlField.frame = NSRect(x: 120, y: 250, width: 380, height: 22)
        urlField.placeholderString = "http://127.0.0.1:11434/v1/chat/completions"
        urlField.delegate = self
        content.addSubview(label("接口地址", 252)); content.addSubview(urlField)

        modelField.frame = NSRect(x: 120, y: 218, width: 380, height: 22)
        modelField.placeholderString = "Ollama 模型名，如 hymt2"
        content.addSubview(label("模型名", 220)); content.addSubview(modelField)

        systemShotCheck.frame = NSRect(x: 120, y: 186, width: 380, height: 22)
        hideTrayCheck.frame = NSRect(x: 120, y: 160, width: 380, height: 22)
        launchCheck.frame = NSRect(x: 120, y: 134, width: 380, height: 22)
        content.addSubview(systemShotCheck); content.addSubview(hideTrayCheck); content.addSubview(launchCheck)

        axButton.bezelStyle = .texturedRounded
        axButton.frame = NSRect(x: 120, y: 104, width: 260, height: 24)
        axButton.target = self
        axButton.action = #selector(grantAX)
        content.addSubview(axButton)

        saveButton.bezelStyle = .texturedRounded
        saveButton.frame = NSRect(x: 404, y: 40, width: 96, height: 28)
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)
        content.addSubview(saveButton)

        statusLabel.frame = NSRect(x: 16, y: 12, width: 488, height: 18)
        statusLabel.textColor = .secondaryLabelColor
        content.addSubview(statusLabel)

        EscMonitor.add(self)
    }

    func showSettings() {
        urlField.stringValue = Config.ollamaURL
        modelField.stringValue = Config.model
        systemShotCheck.state = Config.systemScreenshot ? .on : .off
        hideTrayCheck.state = Config.hideTrayIcon ? .on : .off
        launchCheck.state = Config.launchAtLogin ? .on : .off
        axButton.title = SelectionReader.hasAccessibility() ? "辅助功能权限：已授予" : "申请辅助功能权限（划词取词需要）"
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func grantAX() {
        SelectionReader.promptAccessibility()
    }

    @objc private func save() {
        Config.ollamaURL = urlField.stringValue.trimmingCharacters(in: .whitespaces)
        Config.model = modelField.stringValue.trimmingCharacters(in: .whitespaces)
        let wasHidden = Config.hideTrayIcon
        Config.systemScreenshot = systemShotCheck.state == .on
        Config.hideTrayIcon = hideTrayCheck.state == .on
        Config.launchAtLogin = launchCheck.state == .on
        applyLaunchAtLogin()
        if Config.hideTrayIcon != wasHidden {
            NotificationCenter.default.post(name: .trayVisibilityChanged, object: nil)
        }
        statusLabel.stringValue = "已保存"
        log("[设置] 已保存")
        orderOut(nil)
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        do {
            if Config.launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            statusLabel.stringValue = "开机自启设置失败：\(error.localizedDescription)"
        }
    }
}

extension Notification.Name {
    static let trayVisibilityChanged = Notification.Name("trayVisibilityChanged")
}
