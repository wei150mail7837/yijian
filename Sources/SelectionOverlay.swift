import AppKit

/// 内置截图选区（对齐 Lite 架构：先冻结整屏，在冻结图上框选）：
/// screencapture -x 逐屏冻结 → 每个显示器一张透明全屏窗口铺冻结图；
/// 拖拽框选（全局坐标，可跨屏）；角标显示像素尺寸；拖拽时放大镜（从冻结图采样，2.5x）；
/// 松开显示确认/取消工具条；Esc/右键取消；确认后直接从冻结图裁剪（无需再起 screencapture）。
final class SelectionOverlay {
    private static var active: SelectionOverlay?

    struct FrozenScreen {
        let screen: NSScreen
        let image: CGImage          // 像素级
        let scale: CGFloat          // 像素/点
    }

    private var frozen: [FrozenScreen] = []
    private var windows: [OverlayWindow] = []
    private var completion: ((URL?) -> Void)?
    private var keyMonitor: Any?
    fileprivate var start: NSPoint?        // 全局 Cocoa 坐标
    fileprivate var current: NSPoint?
    fileprivate var dragging = false
    fileprivate var magnifier = MagnifierView()
    fileprivate var toolbar: [NSButton] = []

    static func begin(completion: @escaping (URL?) -> Void) {
        guard active == nil else { return }
        let o = SelectionOverlay(); active = o; o.completion = completion
        o.freezeThenShow()
    }

    fileprivate func frozenScreen(containing point: NSPoint) -> FrozenScreen? {
        frozen.first { $0.screen.frame.contains(point) } ?? frozen.first
    }

    /// 逐屏冻结（screencapture -x -D n），完成后显示遮罩
    private func freezeThenShow() {
        let screens = NSScreen.screens
        let dir = FileManager.default.temporaryDirectory
        var collected: [SelectionOverlay.FrozenScreen] = []
        var step: ((Int) -> Void)!
        step = { [weak self] index in
            guard let owner = self else { return }
            guard index < screens.count else {
                DispatchQueue.main.async {
                    if collected.isEmpty {
                        log("[截图] 屏幕冻结失败")
                        owner.finish(nil)
                    } else {
                        owner.frozen = collected
                        owner.show()
                    }
                }
                return
            }
            let screen = screens[index]
            let file = dir.appendingPathComponent("ttime-freeze-\(index).png")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-D", "\(index + 1)", file.path]
            task.terminationHandler = { t in
                DispatchQueue.main.async {
                    if t.terminationStatus == 0, let img = NSImage(contentsOf: file),
                       let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                        let scale = CGFloat(cg.width) / screen.frame.width
                        collected.append(SelectionOverlay.FrozenScreen(screen: screen, image: cg, scale: scale))
                    }
                    try? FileManager.default.removeItem(at: file)
                    step(index + 1)
                }
            }
            try? task.run()
        }
        step(0)
    }

    fileprivate var selection: NSRect? {
        guard let s = start, let c = current else { return nil }
        return NSRect(x: min(s.x, c.x), y: min(s.y, c.y), width: abs(s.x - c.x), height: abs(s.y - c.y))
    }

    private func show() {
        for f in frozen {
            let w = OverlayWindow(screen: f.screen, image: f.image, owner: self)
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

    /// 松开：选区有效则进入工具条确认态，否则结束
    fileprivate func mouseUp() {
        dragging = false
        magnifier.hide()
        guard let r = selection, r.width >= 3, r.height >= 3 else { finish(nil); return }
        showToolbar(for: r)
        redraw()
    }

    /// 重新开始拖拽：退出确认态并撤掉工具条
    fileprivate func restartDrag(at point: NSPoint) {
        hideToolbar()
        start = point
        current = point
        dragging = true
        redraw()
    }

    private func showToolbar(for rect: NSRect) {
        hideToolbar()
        let corner = NSPoint(x: rect.maxX, y: rect.maxY)
        let host = windows.last(where: { $0.frame.contains(corner) }) ?? windows.first
        guard let window = host else { return }
        let origin = window.frame.origin
        let local = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        let bw: CGFloat = 44
        let bh: CGFloat = 30
        let gap: CGFloat = 6
        let edge: CGFloat = 4
        let totalW = bw * 2 + gap
        var x = min(local.maxX - totalW - edge, window.frame.width - totalW - 8)
        var y = local.minY - bh - 8
        if y < edge { y = local.maxY + 8 }
        if x < edge { x = edge }

        let confirm = NSButton(title: "✓ 确认", target: self, action: #selector(toolbarConfirm))
        confirm.bezelStyle = .texturedRounded
        confirm.frame = NSRect(x: x, y: y, width: bw, height: bh)
        let cancel = NSButton(title: "✕", target: self, action: #selector(toolbarCancel))
        cancel.bezelStyle = .texturedRounded
        cancel.frame = NSRect(x: x + bw + gap, y: y, width: bw, height: bh)
        for b in [confirm, cancel] {
            window.contentView?.addSubview(b)
            toolbar.append(b)
        }
    }

    private func hideToolbar() {
        toolbar.forEach { $0.removeFromSuperview() }
        toolbar.removeAll()
    }

    @objc private func toolbarConfirm() { finish(selection) }

    @objc private func toolbarCancel() { finish(nil) }

    fileprivate func finish(_ rect: NSRect?) {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        magnifier.hide()
        NSCursor.pop()
        hideToolbar()
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        let done = completion; completion = nil
        SelectionOverlay.active = nil
        guard let rect else { log("[截图] 内置选区已取消"); done?(nil); return }
        // 从冻结图裁剪：找包含选区中心的屏
        let center = NSPoint(x: rect.midX, y: rect.midY)
        guard let fs = frozenScreen(containing: center) else { done?(nil); return }
        let origin = fs.screen.frame.origin
        let local = rect.offsetBy(dx: -origin.x, dy: -origin.y)
        // 坐标系说明（终审曾疑 Y 轴镜像，实为误判）：
        // Cocoa 全局坐标 y 向下、主屏左上 = (0,0)，screen.frame.origin.y 即本屏【顶边】的全局 y。
        // 故 local.y = 全局 y - 顶边 y = 「距屏顶距离」（左上原点向下），与 CGImage 像素坐标
        // （同为左上原点、行 0 = 屏幕顶行）方向一致：像素 y = 距顶距离 × scale，无需翻转。
        // 副屏 origin.y 为负值时公式同样成立（minY 恒为该屏顶边）。
        let px = CGRect(x: local.minX * fs.scale, y: local.minY * fs.scale,
                        width: local.width * fs.scale, height: local.height * fs.scale)
        guard let cropped = fs.image.cropping(to: px) else { done?(nil); return }
        let rep = NSBitmapImageRep(cgImage: cropped)
        guard let png = rep.representation(using: .png, properties: [:]) else { done?(nil); return }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("ttime-capture-\(Int(Date().timeIntervalSince1970 * 1000)).png")
        do {
            try png.write(to: file)
            DispatchQueue.main.async { done?(file) }
        } catch {
            log("[截图] 裁剪写入失败")
            done?(nil)
        }
    }
}

private final class OverlayWindow: NSWindow {
    init(screen: NSScreen, image: CGImage, owner: SelectionOverlay) {
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
        contentView = OverlayView(owner: owner, frozen: image)
    }
    override var canBecomeKey: Bool { true }
}

private final class OverlayView: NSView {
    weak var owner: SelectionOverlay?
    private let frozen: CGImage
    private var lastMagnifyAt = Date.distantPast

    init(owner: SelectionOverlay, frozen: CGImage) {
        self.owner = owner
        self.frozen = frozen
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    private func global(_ e: NSEvent) -> NSPoint {
        guard let w = window else { return .zero }
        return w.convertPoint(toScreen: e.locationInWindow)
    }

    override func mouseDown(with e: NSEvent) {
        // 确认态下重新按下 = 放弃旧选区重新框选
        owner?.restartDrag(at: global(e))
    }
    // 拖拽事件只送达按下所在窗口，但 locationInWindow 越界仍有效 → 全局坐标天然支持跨屏
    override func mouseDragged(with e: NSEvent) {
        let p = global(e)
        owner?.current = p
        owner?.redraw()
        updateMagnifier(at: p)
    }
    override func mouseUp(with e: NSEvent) { owner?.current = global(e); owner?.mouseUp() }
    override func rightMouseDown(with e: NSEvent) { owner?.finish(nil) }

    /// 从冻结图采样放大镜内容（无实时抓屏、无额外权限）
    private func updateMagnifier(at cursor: NSPoint) {
        guard let owner, let fs = owner.frozenScreen(containing: cursor) else { return }
        let origin = fs.screen.frame.origin
        let srcSide: CGFloat = 44                       // 采样 44pt 区域 → 110pt 视图 ≈ 2.5x
        // local.y 为距屏顶距离（Cocoa y 向下），与 CGImage 左上原点行方向一致，无需翻转
        let local = NSPoint(x: cursor.x - origin.x, y: cursor.y - origin.y)
        let px = CGRect(x: (local.x - srcSide / 2) * fs.scale, y: (local.y - srcSide / 2) * fs.scale,
                        width: srcSide * fs.scale, height: srcSide * fs.scale)
        if let cut = fs.image.cropping(to: px) {
            owner.magnifier.update(image: cut)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let w = window, let owner else { return }
        // 冻结图铺底
        if let fs = owner.frozenScreen(containing: w.convertPoint(toScreen: NSPoint(x: bounds.midX, y: bounds.midY))) {
            let img = NSImage(cgImage: fs.image, size: fs.screen.frame.size)
            img.draw(in: bounds)
        }
        let dim = NSBezierPath(rect: bounds)
        var local: NSRect?
        if let sel = owner.selection {
            let o = w.frame.origin
            let r = sel.offsetBy(dx: -o.x, dy: -o.y)
            if r.intersects(bounds) { local = r; dim.append(NSBezierPath(rect: r)); dim.windingRule = .evenOdd }
        }
        NSColor.black.withAlphaComponent(0.35).setFill()
        dim.fill()
        guard let r = local, let sel = owner.selection else { return }
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
        // 放大镜只画在包含光标的窗口，位于光标侧边
        if owner.dragging, let cursor = owner.current, owner.magnifier.ready,
           let mf = owner.magnifier.frame(in: w, cursorGlobal: cursor) {
            owner.magnifier.drawContent(in: mf, screenPoint: cursor, frozen: owner.frozenScreen(containing: cursor) ?? owner.frozenScreen(containing: NSPoint.zero)!)
        }
    }
}

/// 拖拽时的放大镜：冻结图上光标周围 44pt 放大 2.5x 显示
final class MagnifierView {
    private(set) var snapshot: CGImage?
    private let size: CGFloat = 110
    var ready: Bool { snapshot != nil }

    func update(image: CGImage) { snapshot = image }
    func hide() { snapshot = nil }

    /// 放大镜几何（窗口局部坐标）；不在本窗口时返回 nil
    func frame(in window: NSWindow, cursorGlobal: NSPoint) -> NSRect? {
        let origin = window.frame.origin
        let cursor = NSPoint(x: cursorGlobal.x - origin.x, y: cursorGlobal.y - origin.y)
        let side = size
        let gap: CGFloat = 18
        let edge: CGFloat = 4
        var x = cursor.x + gap
        var y = cursor.y + gap
        if x + side > window.frame.width - edge { x = cursor.x - gap - side }
        if y + side > window.frame.height - edge - 24 { y = cursor.y - gap - side - 24 }
        if x < edge { x = edge }
        if y < edge { y = edge }
        return NSRect(x: x, y: y, width: side, height: side)
    }

    func drawContent(in rect: NSRect, screenPoint: NSPoint, frozen: SelectionOverlay.FrozenScreen) {
        NSColor.black.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6).fill()
        if let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 5, yRadius: 5).addClip()
            let origin = frozen.screen.frame.origin
            let local = NSPoint(x: screenPoint.x - origin.x, y: screenPoint.y - origin.y)
            let srcSide: CGFloat = 44
            let px = CGRect(x: (local.x - srcSide / 2) * frozen.scale, y: (local.y - srcSide / 2) * frozen.scale,
                            width: srcSide * frozen.scale, height: srcSide * frozen.scale)
            if let cut = frozen.image.cropping(to: px.integral) {
                ctx.interpolationQuality = .none
                ctx.draw(cut, in: rect.insetBy(dx: 2, dy: 2))
            }
            NSColor.systemGreen.withAlphaComponent(0.9).setStroke()
            let mid = NSPoint(x: rect.midX, y: rect.midY)
            let cross = NSBezierPath()
            cross.move(to: NSPoint(x: mid.x - 10, y: mid.y)); cross.line(to: NSPoint(x: mid.x + 10, y: mid.y))
            cross.move(to: NSPoint(x: mid.x, y: mid.y - 10)); cross.line(to: NSPoint(x: mid.x, y: mid.y + 10))
            cross.lineWidth = 1
            cross.stroke()
            ctx.restoreGState()
        }
        NSColor.systemBlue.setStroke()
        let border = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        border.lineWidth = 1.5
        border.stroke()
    }
}
