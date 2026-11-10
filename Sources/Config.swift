import Foundation

/// 全局配置（UserDefaults 持久化）
enum Config {
    private static let d = UserDefaults.standard

    static var ollamaURL: String {
        get { d.string(forKey: "ollamaURL") ?? "http://127.0.0.1:11434/v1/chat/completions" }
        set { d.set(newValue, forKey: "ollamaURL") }
    }

    static var model: String {
        get { d.string(forKey: "model") ?? "" }
        set { d.set(newValue, forKey: "model") }
    }

    /// 截图引擎：true=系统 screencapture -i，false=暂无内置（保留扩展位）
    static var systemScreenshot: Bool {
        get { d.object(forKey: "systemScreenshot") as? Bool ?? true }
        set { d.set(newValue, forKey: "systemScreenshot") }
    }

    static var hideTrayIcon: Bool {
        get { d.bool(forKey: "hideTrayIcon") }
        set { d.set(newValue, forKey: "hideTrayIcon") }
    }

    static var launchAtLogin: Bool {
        get { d.bool(forKey: "launchAtLogin") }
        set { d.set(newValue, forKey: "launchAtLogin") }
    }
}
