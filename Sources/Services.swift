import AppKit

let logFile: URL = {
    let dir = appSupportDir.appendingPathComponent("logs", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.appendingPathComponent(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none).replacingOccurrences(of: "/", with: "-") + ".log")
}()

let appSupportDir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("TTimeNative", isDirectory: true)

/// 轻量日志：只记事件与长度，不落用户内容原文（隐私纪律）
func log(_ items: Any...) {
    let line = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        + "  " + items.map { "\($0)" }.joined(separator: " ") + "\n"
    if let handle = try? FileHandle(forWritingTo: logFile) {
        handle.seekToEndOfFile()
        handle.write(Data(line.utf8))
        try? handle.close()
    } else {
        try? line.write(to: logFile, atomically: true, encoding: .utf8)
    }
}

/// 截图入口：systemScreenshot=true → screencapture -i；false → 内置 SelectionOverlay 选区。
/// 前置（对齐 GlobalShortcutEvent.ts:152-158 / Screenshot.ts:263-293）：先隐藏主窗与 OCR 窗，避免拍进自身。
/// 退出码≠0 或文件不存在视为取消：静默、删临时文件。读取后删除临时文件由调用方负责（OCRWindow 需保留预览）。
enum ScreenshotService {
    static func capture(completion: @escaping (URL?) -> Void) {
        MainWindow.shared.orderOut(nil)
        OCRWindow.shared.orderOut(nil)
        // 等窗口离屏动画结束再起选区
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if !Config.systemScreenshot {
                log("[截图] 内置选区引擎")
                SelectionOverlay.begin(completion: completion)
            } else {
                systemCapture(completion: completion)
            }
        }
    }

    private static func systemCapture(completion: @escaping (URL?) -> Void) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ttime-capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", file.path]
        log("[截图] screencapture -i 启动，等待框选…")
        task.terminationHandler = { t in
            let ok = t.terminationStatus == 0 && FileManager.default.fileExists(atPath: file.path)
            log("[截图] screencapture 结束 status=\(t.terminationStatus) 文件存在=\(FileManager.default.fileExists(atPath: file.path))")
            if !ok { try? FileManager.default.removeItem(at: file) }
            DispatchQueue.main.async { completion(ok ? file : nil) }
        }
        do { try task.run() } catch { log("[截图] screencapture 启动失败：\(error.localizedDescription)"); DispatchQueue.main.async { completion(nil) } }
    }
}

/// 划词取词（对齐 GlobalShortcutEvent.ts:186-258）：防重入 → 释放修饰键 → 备份并清空剪贴板 →
/// 等 delay/2 → 模拟 Cmd+C（按下/抬起各等 delay/2）→ 读新文本 → 完整还原原剪贴板 → 驼峰/下划线拆分
enum SelectionReader {
    private static var isChoice = false

    /// 划词延迟：唯一来源 Config.selectionDelay（设置页读写的同一键 translateChoiceDelay，默认 600，范围 100-1000）。
    /// 旧版曾优先读未被任何代码写入的 "selectionDelay" 键，残留值会盖过设置页 → 已删除该分支。
    static var delayMs: Int { Config.selectionDelay }

    static func hasAccessibility() -> Bool { AXIsProcessTrusted() }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func readSelection(completion: @escaping (String?) -> Void) {
        guard hasAccessibility() else { promptAccessibility(); completion(nil); return }
        guard !isChoice else { return }
        isChoice = true
        let pb = NSPasteboard.general
        // 完整备份所有条目的所有类型（不只纯文本）
        let saved: [[NSPasteboard.PasteboardType: Data]] = (pb.pasteboardItems ?? []).map { item in
            var d: [NSPasteboard.PasteboardType: Data] = [:]
            for t in item.types { if let v = item.data(forType: t) { d[t] = v } }
            return d
        }
        let changeBefore = pb.clearContents()
        let half = UInt32(delayMs / 2) * 1000
        DispatchQueue.global(qos: .userInitiated).async {
            releaseModifiers()
            usleep(half)
            postCommandC(halfDelay: half)
            let text = pb.changeCount != changeBefore ? (pb.string(forType: .string) ?? "") : ""
            DispatchQueue.main.async {
                pb.clearContents()
                let items: [NSPasteboardItem] = saved.map { d in
                    let it = NSPasteboardItem(); for (t, v) in d { it.setData(v, forType: t) }; return it
                }
                if !items.isEmpty { pb.writeObjects(items) }
                isChoice = false
                completion(splitWords(text).trimmingCharacters(in: .newlines))
            }
        }
    }

    /// 驼峰拆分（仅纯字母：aB→a B）与下划线拆分（snake_case→snake case）
    static func splitWords(_ s: String) -> String {
        var t = s
        if t.range(of: "^[A-Za-z]+$", options: .regularExpression) != nil {
            t = t.replacingOccurrences(of: "([a-z])([A-Z])", with: "$1 $2", options: .regularExpression)
        }
        if t.range(of: "^[A-Za-z0-9]+(_[A-Za-z0-9]+)+$", options: .regularExpression) != nil {
            t = t.replacingOccurrences(of: "_", with: " ")
        }
        return t
    }

    /// 释放可能粘连的按键：Ctrl/Alt/Shift/Cmd（左右）、Space、Tab、Esc
    private static func releaseModifiers() {
        guard let src = CGEventSource(stateID: .hidSystemState) else { return }
        for key: CGKeyCode in [0x3B, 0x3E, 0x3A, 0x3D, 0x38, 0x3C, 0x37, 0x36, 0x31, 0x30, 0x35] {
            CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)?.post(tap: .cghidEventTap)
        }
    }

    private static func postCommandC(halfDelay: UInt32) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(halfDelay)
        up?.post(tap: .cghidEventTap)
        usleep(halfDelay)
    }
}
