import AppKit

/// 内置截图选区（对齐 Screenshot.ts captureByEngine 的自绘遮罩选区）：
/// 每个显示器一张透明全屏窗口；鼠标拖拽框选（选区以全局坐标记录，可跨屏）；角标显示尺寸；
/// Esc / 右键取消；松开即关闭遮罩并用 `screencapture -x -R` 非交互裁剪该区域。
/// 差异（如实）：Lite 先冻结整屏再在冻结图上框选并带标注工具条；此处为实时屏幕上框选、无工具条。
final class SelectionOverlay {
    private static var active: SelectionOverlay?

    private var windows: [OverlayWindow] = []
    private var completion: ((URL?) -> Void)?
    private var keyMonitor: Any?
    fileprivate var start: NSPoint?        // 全局 Cocoa 坐标
    fileprivate var current: NSPoint?

    static func begin(completion: @escaping (URL?) -> Void) {
        guard active == nil else { return }
        let o = SelectionOverlay(); active = o; o.completion = completion
        o.show()
    }

    fileprivate var selection: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    private func show() {
        for screen in NSScreen.screens {
            let w = OverlayWindow(screen: screen, owner: self)
            windows.append(w)
            w.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        (windows.first { $0.frame.contains(mouse) } ?? windows.first)?.makeKey()
        NSCursor.crosshair.push()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.keyCode == 53 { self?.finish(nil); return nil }   // Esc（含 Alt+Esc）取消
            return e
        }
    }

    fileprivate func redraw() { windows.forEach { $0.contentView?.needsDisplay = true } }

    fileprivate func mouseUp() {
        guard let r = selection, r.width >= 3, r.height >= 3 else { finish(nil); return }
        finish(r)
    }

    fileprivate func finish(_ rect: NSRect?) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        NSCursor.pop()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let done = completion; completion = nil
        SelectionOverlay.active = nil
        guard let rect else { log("[截图] 内置选区已取消"); done?(nil); return }
        // screencapture -R：以主屏左上为原点、单位为点
        let primaryH = NSScreen.screens.first?.frame.height ?? 0
        let x = Int(rect.minX.rounded()), y = Int((primaryH - rect.maxY).rounded())
        let w = Int(rect.width.rounded()), h = Int(rect.height.rounded())
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ttime-capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        // 等遮罩窗口真正离屏再拍，避免把遮罩拍进去
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-R", "\(x),\(y),\(w),\(h)", file.path]
            task.terminationHandler = { t in
                let ok = t.terminationStatus == 0 && FileManager.default.fileExists(atPath: file.path)
                if !ok { try? FileManager.default.removeItem(at: file) }
                DispatchQueue.main.async { done?(ok ? file : nil) }
            }
            do { try task.run() } catch { done?(nil) }
        }
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, owner: SelectionOverlay) {
        super.init(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        setFrame(screen.frame, display: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        contentView = OverlayView(owner: owner)
    }
    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    weak var owner: SelectionOverlay?
    init(owner: SelectionOverlay) { self.owner = owner; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private func global(_ e: NSEvent) -> NSPoint {
        guard let w = window else { return .zero }
        return w.convertPoint(toScreen: e.locationInWindow)
    }

    override func mouseDown(with e: NSEvent) { owner?.start = global(e); owner?.current = owner?.start; owner?.redraw() }
    // 拖拽事件只送达按下所在窗口，但 locationInWindow 越界仍有效 → 全局坐标天然支持跨屏
    override func mouseDragged(with e: NSEvent) { owner?.current = global(e); owner?.redraw() }
    override func mouseUp(with e: NSEvent) { owner?.current = global(e); owner?.mouseUp() }
    override func rightMouseDown(with e: NSEvent) { owner?.finish(nil) }

    override func draw(_ dirtyRect: NSRect) {
        guard let w = window else { return }
        let dim = NSBezierPath(rect: bounds)
        var local: NSRect?
        if let sel = owner?.selection {
            let o = w.frame.origin
            let r = sel.offsetBy(dx: -o.x, dy: -o.y)
            if r.intersects(bounds) { local = r; dim.append(NSBezierPath(rect: r)); dim.windingRule = .evenOdd }
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()
        guard let r = local, let sel = owner?.selection else { return }
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)); border.lineWidth = 1; border.stroke()
        // 尺寸角标（像素 = 点 × backingScale）
        let scale = w.backingScaleFactor
        let label = "\(Int(sel.width * scale)) × \(Int(sel.height * scale))" as NSString
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
                                                     .foregroundColor: NSColor.white]
        let sz = label.size(withAttributes: attrs)
        var badge = NSRect(x: r.minX, y: r.maxY + 4, width: sz.width + 10, height: sz.height + 4)
        if badge.maxY > bounds.maxY { badge.origin.y = r.maxY - badge.height - 4; badge.origin.x = r.minX + 4 }
        NSColor.black.withAlphaComponent(0.75).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        label.draw(at: NSPoint(x: badge.minX + 5, y: badge.minY + 2), withAttributes: attrs)
    }
}
