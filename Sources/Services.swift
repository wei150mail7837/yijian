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

/// 系统截图（screencapture -i 原生选区）
enum ScreenshotService {
    static func capture(completion: @escaping (URL?) -> Void) {
        let file = appSupportDir.appendingPathComponent("capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", file.path]
        task.terminationHandler = { _ in
            DispatchQueue.main.async {
                completion(FileManager.default.fileExists(atPath: file.path) ? file : nil)
            }
        }
        try? task.run()
    }
}

/// 划词取词：模拟 Cmd+C 读剪贴板，用后还原（需要辅助功能权限）
enum SelectionReader {
    static func hasAccessibility() -> Bool {
        AXIsProcessTrusted()
    }

    static func promptAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func readSelection(completion: @escaping (String?) -> Void) {
        guard hasAccessibility() else {
            promptAccessibility()
            completion(nil)
            return
        }
        let pasteboard = NSPasteboard.general
        let saved = pasteboard.data(forType: .string)
        pasteboard.clearContents()
        pasteboard.setString(" ", forType: .string)

        postCommandC()
        // 轮询等待剪贴板更新
        let deadline = Date().addingTimeInterval(1.5)
        DispatchQueue.global().async {
            var text: String?
            while Date() < deadline {
                if let current = pasteboard.string(forType: .string), current != " " {
                    text = current
                    break
                }
                usleep(50_000)
            }
            // 还原剪贴板
            pasteboard.clearContents()
            if let saved, let original = String(data: saved, encoding: .utf8) {
                pasteboard.setString(original, forType: .string)
            }
            DispatchQueue.main.async { completion(text) }
        }
    }

    private static func postCommandC() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // C
        let up = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        usleep(20_000)
        up?.post(tap: .cghidEventTap)
    }
}
