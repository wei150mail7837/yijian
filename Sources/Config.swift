import Foundation

/// 全局配置（UserDefaults 持久化，域 com.isa.ttimenative）
/// 键名与 Electron Lite 版 config store 对齐；默认值见 StoreService.ts
enum Config {
    private static let d = UserDefaults.standard

    /// 兼容 Bool 与 "Y"/"N" 字符串两种写法（defaults write 可写任一种）
    private static func flag(_ key: String, _ def: Bool) -> Bool {
        guard let obj = d.object(forKey: key) else { return def }
        if let s = obj as? String { return s == "Y" || s == "1" || s.lowercased() == "true" }
        return (obj as? Bool) ?? def
    }
    private static func setFlag(_ key: String, _ v: Bool) { d.set(v, forKey: key) }

    static var ollamaURL: String {
        get { d.string(forKey: "ollamaURL") ?? "http://127.0.0.1:11434/v1/chat/completions" }
        set { d.set(newValue, forKey: "ollamaURL") }
    }

    /// 翻译通道固定为 Ollama（OpenAI 兼容接口）；Web/MyMemory 通道因翻译质量缺陷已移除
    static let channel = "ollama"

    /// 模型名（空 = 提示用户去设置填写）
    static var model: String {
        get { d.string(forKey: "model") ?? "" }
        set { d.set(newValue, forKey: "model") }
    }

    // MARK: 功能设置
    static var systemScreenshot: Bool {
        get { flag("systemScreenshot", true) } set { setFlag("systemScreenshot", newValue) }
    }
    static var hideTrayIcon: Bool {
        get { flag("hideTrayIcon", false) } set { setFlag("hideTrayIcon", newValue) }
    }
    static var launchAtLogin: Bool {
        get { flag("launchAtLogin", false) } set { setFlag("launchAtLogin", newValue) }
    }
    static var alwaysOnTopAllowEsc: Bool {
        get { flag("alwaysOnTopAllowEscStatus", false) } set { setFlag("alwaysOnTopAllowEscStatus", newValue) }
    }
    static var inputTranslationAuto: Bool {
        get { flag("inputTranslationAutoStatus", false) } set { setFlag("inputTranslationAutoStatus", newValue) }
    }
    static var copyCamelCaseResult: Bool {
        get { flag("copyCamelCaseResultStatus", false) } set { setFlag("copyCamelCaseResultStatus", newValue) }
    }
    static var copySnakeCaseResult: Bool {
        get { flag("copySnakeCaseResultStatus", false) } set { setFlag("copySnakeCaseResultStatus", newValue) }
    }

    // MARK: 翻译设置
    static var wrapReplaceSpace: Bool {
        get { flag("wrapReplaceSpaceStatus", false) } set { setFlag("wrapReplaceSpaceStatus", newValue) }
    }
    static var showTranslateNotEmpty: Bool {
        get { flag("showTranslateNotEmptyStatus", false) } set { setFlag("showTranslateNotEmptyStatus", newValue) }
    }

    // MARK: OCR 设置
    static var ocrWrapReplaceSpace: Bool {
        get { flag("ocrWrapReplaceSpaceStatus", false) } set { setFlag("ocrWrapReplaceSpaceStatus", newValue) }
    }
    static var ocrWrapReplace: Bool {
        get { flag("ocrWrapReplaceStatus", false) } set { setFlag("ocrWrapReplaceStatus", newValue) }
    }
    static var ocrWriteClipboard: Bool {
        get { flag("ocrWriteClipboardStatus", false) } set { setFlag("ocrWriteClipboardStatus", newValue) }
    }

    // MARK: 偏好设置
    static var hideInput: Bool {
        // 键名与主窗读取（MainWindow Pref "hideTranslateInput"）及 Lite（StoreService.ts:199）一致；
        // 旧键 translateInputHideStatus 无读取方，已废弃
        get { flag("hideTranslateInput", false) } set { setFlag("hideTranslateInput", newValue) }
    }
    static var hideLanguageBar: Bool {
        get { flag("hideTranslateLanguage", false) } set { setFlag("hideTranslateLanguage", newValue) }
    }
    /// 显示位置：写入 MainWindow 读取的同一键 translateShowPositionType
    /// 下拉索引 0=LAST_TIME 1=FROM_TOP 2=FOLLOW_MOUSE
    static let positionTypes = ["LAST_TIME", "FROM_TOP", "FOLLOW_MOUSE"]
    static var showPosition: Int {
        get { positionTypes.firstIndex(of: d.string(forKey: "translateShowPositionType") ?? "LAST_TIME") ?? 0 }
        set { d.set(positionTypes[max(0, min(2, newValue))], forKey: "translateShowPositionType") }
    }
    /// 距顶部百分比：MainWindow 读 fromTopOfWindowPercentage（1-200，默认 30）
    static var topPercent: Int {
        get { let v = d.integer(forKey: "fromTopOfWindowPercentage"); return (1...200).contains(v) ? v : 30 }
        set { d.set(max(1, min(200, newValue)), forKey: "fromTopOfWindowPercentage") }
    }
    /// 划词延迟：Services.swift 读 translateChoiceDelay（100-1000，默认 600）
    static var selectionDelay: Int {
        get { let v = d.integer(forKey: "translateChoiceDelay"); return v == 0 ? 600 : min(max(v, 100), 1000) }
        set { d.set(max(100, min(1000, newValue)), forKey: "translateChoiceDelay") }
    }
    /// 字体大小 10-30，默认 14
    static var winFontSize: Int {
        get { d.object(forKey: "winFontSize") as? Int ?? 14 } set { d.set(max(10, min(30, newValue)), forKey: "winFontSize") }
    }
    /// 主题：0=跟随系统 1=明亮 2=暗黑
    static var theme: Int {
        get { d.object(forKey: "theme") as? Int ?? 0 } set { d.set(newValue, forKey: "theme") }
    }

    // MARK: 快捷键（"Alt+Shift+W" 形式，空串=未配置）
    static let shortcutKeys: [(key: String, name: String, def: String)] = [
        ("translateShortcutKey", "输入翻译", "Alt+Q"),
        ("screenshotTranslateShortcutKey", "截图翻译", "Alt+W"),
        ("selectionTranslateShortcutKey", "划词翻译", "Alt+E"),
        ("showOcrShortcutKey", "显示OCR窗口", ""),
        ("screenshotOcrShortcutKey", "截图OCR", "Alt+Shift+W"),
    ]
    static func shortcut(_ key: String) -> String {
        if let v = d.string(forKey: key) { return v }
        return shortcutKeys.first { $0.key == key }?.def ?? ""
    }
    static func setShortcut(_ key: String, _ value: String) { d.set(value, forKey: key) }
}
