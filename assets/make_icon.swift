// 程序化生成正式图标：AppIcon.icns（青蓝渐变圆角方块 + 「译」字主视觉）与托盘 template PNG
// 用法：swift assets/make_icon.swift <输出目录>
import AppKit
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func png(_ px: Int, _ draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func glyph(_ s: CGFloat, _ text: String, _ rect: NSRect, _ color: NSColor, _ weight: NSFont.Weight) {
    let f = NSFont.systemFont(ofSize: rect.height * 0.62, weight: weight)
    let a: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: color]
    let sz = (text as NSString).size(withAttributes: a)
    (text as NSString).draw(at: NSPoint(x: rect.midX - sz.width / 2, y: rect.midY - sz.height / 2), withAttributes: a)
}

func appIcon(_ s: CGFloat) {
    // macOS Big Sur 网格：内容 824/1024，圆角 ~185/1024
    let inset = s * 100 / 1024, r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let shape = NSBezierPath(roundedRect: r, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.3)
    sh.shadowOffset = NSSize(width: 0, height: -s * 0.01); sh.shadowBlurRadius = s * 0.025; sh.set()
    NSColor.white.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.10, green: 0.62, blue: 0.85, alpha: 1),
                        NSColor(red: 0.12, green: 0.78, blue: 0.62, alpha: 1)])!.draw(in: shape, angle: -60)
    // 高光
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.22), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: NSRect(x: r.minX, y: r.midY, width: r.width, height: r.height / 2),
                               xRadius: s * 185 / 1024, yRadius: s * 185 / 1024), angle: -90)
    // 单气泡「译」主视觉（居中，带小尾巴指向右下）
    let b1 = NSRect(x: r.minX + r.width * 0.14, y: r.minY + r.height * 0.16, width: r.width * 0.72, height: r.height * 0.62)
    let p1 = NSBezierPath(roundedRect: b1, xRadius: b1.width * 0.18, yRadius: b1.width * 0.18)
    p1.move(to: NSPoint(x: b1.maxX - b1.width * 0.28, y: b1.minY + 1))
    p1.line(to: NSPoint(x: b1.maxX - b1.width * 0.18, y: b1.minY - b1.height * 0.16))
    p1.line(to: NSPoint(x: b1.maxX - b1.width * 0.02, y: b1.minY + 1))
    NSColor.white.withAlphaComponent(0.95).setFill(); p1.fill()
    glyph(s, "译", b1.insetBy(dx: s * 0.02, dy: s * 0.02), NSColor(red: 0.08, green: 0.55, blue: 0.62, alpha: 1), .heavy)
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! png(px, appIcon).write(to: iconset.appendingPathComponent("icon_\(name).png"))
}

// 托盘 template：同母题（双气泡 T/文），黑色+透明，交由系统着色
func tray(_ s: CGFloat) {
    let u = s / 18
    NSColor.black.setFill()
    let b1 = NSRect(x: 0.5 * u, y: 6 * u, width: 10.5 * u, height: 11 * u)
    let p1 = NSBezierPath(roundedRect: b1, xRadius: 2.8 * u, yRadius: 2.8 * u)
    p1.move(to: NSPoint(x: 2.5 * u, y: 6.5 * u)); p1.line(to: NSPoint(x: 1.8 * u, y: 3.4 * u)); p1.line(to: NSPoint(x: 5.6 * u, y: 6.5 * u))
    p1.fill()
    NSGraphicsContext.current?.compositingOperation = .clear
    glyph(s, "译", b1.insetBy(dx: 0.6 * u, dy: 0.6 * u), .black, .heavy)
    let b2 = NSRect(x: 7 * u, y: 0.8 * u, width: 10.5 * u, height: 10.5 * u)
    let p2 = NSBezierPath(roundedRect: b2.insetBy(dx: -1.2 * u, dy: -1.2 * u), xRadius: 3.4 * u, yRadius: 3.4 * u)
    p2.fill()
    NSGraphicsContext.current?.compositingOperation = .sourceOver
    let p3 = NSBezierPath(roundedRect: b2, xRadius: 2.6 * u, yRadius: 2.6 * u)
    p3.lineWidth = 1.3 * u; p3.stroke()
    glyph(s, "文", b2.insetBy(dx: 0.5 * u, dy: 0.5 * u), .black, .semibold)
}
try! png(18, tray).write(to: out.appendingPathComponent("trayTemplate.png"))
try! png(36, tray).write(to: out.appendingPathComponent("trayTemplate@2x.png"))
