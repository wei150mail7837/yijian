// 译见定稿概念：双圆交叠 → 交叠区天然形成「眼/透镜」形（vesica）→ 中心瞳点
// 名字贴合：两个圆 = 两种语言；交叠出的眼睛 = 「见」。译见 = 两种语言相遇而生出的看见。
// 用法: swift assets/icon_yijian.swift <输出目录>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try! FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func png(_ px: Int, _ name: String, _ draw: (CGFloat) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(CGFloat(px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
}

func squircle(_ s: CGFloat) -> NSBezierPath {
    let inset = s * 100 / 1024
    let r = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    return NSBezierPath(roundedRect: r, xRadius: s * 185 / 1024, yRadius: s * 185 / 1024)
}

func deepBase(_ s: CGFloat, _ shape: NSBezierPath) {
    NSGraphicsContext.saveGraphicsState()
    let sh = NSShadow(); sh.shadowColor = NSColor.black.withAlphaComponent(0.35)
    sh.shadowOffset = NSSize(width: 0, height: -s * 0.008); sh.shadowBlurRadius = s * 0.02; sh.set()
    NSColor.white.setFill(); shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 1),
                        NSColor(red: 0.13, green: 0.16, blue: 0.29, alpha: 1)])!.draw(in: shape, angle: -90)
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.08), NSColor.white.withAlphaComponent(0)])!
        .draw(in: NSBezierPath(roundedRect: NSRect(x: shape.bounds.minX, y: shape.bounds.midY,
                                                   width: shape.bounds.width, height: shape.bounds.height / 2),
                               xRadius: s * 185 / 1024, yRadius: s * 185 / 1024), angle: -90)
}

func iconYijian(_ s: CGFloat) {
    let shape = squircle(s)
    deepBase(s, shape)
    let d = s * 0.36                      // 圆直径
    let y = s * 0.48
    // 圆心间距 = d * 0.52（交叠区足够形成清晰的眼睛形）
    let r1 = NSRect(x: s * 0.19, y: y - d / 2, width: d, height: d)
    let r2 = NSRect(x: s * 0.19 + d * 0.52, y: y - d / 2, width: d, height: d)

    // 左圆：暖白磨砂（半透明）
    NSColor.white.withAlphaComponent(0.15).setFill()
    NSBezierPath(roundedRect: r1, xRadius: d / 2, yRadius: d / 2).fill()
    // 右圆：冷白磨砂
    NSColor.white.withAlphaComponent(0.22).setFill()
    NSBezierPath(roundedRect: r2, xRadius: d / 2, yRadius: d / 2).fill()

    // 交叠区 = vesica 眼形：裁剪到左圆，再以更亮的白填充右圆 → 交集高亮
    NSGraphicsContext.saveGraphicsState()
    let clip = NSBezierPath(roundedRect: r1, xRadius: d / 2, yRadius: d / 2)
    clip.addClip()
    NSGradient(colors: [NSColor.white.withAlphaComponent(0.30), NSColor.white.withAlphaComponent(0.50)])!
        .draw(in: NSBezierPath(roundedRect: r2, xRadius: d / 2, yRadius: d / 2), angle: 0)
    NSGraphicsContext.restoreGraphicsState()

    // 瞳点：交叠区中心一枚小圆（眼睛的瞳孔）
    let midX = (r1.midX + r2.midX) / 2
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: NSRect(x: midX - s * 0.028, y: y - s * 0.028, width: s * 0.056, height: s * 0.056),
                 xRadius: s * 0.028, yRadius: s * 0.028).fill()

    // 眼睛上下各一道极淡弧线，勾勒「眼睑」暗示（可选强化，保持极简）
    NSColor.white.withAlphaComponent(0.20).setStroke()
    let lid = NSBezierPath()
    lid.lineWidth = s * 0.008; lid.lineCapStyle = .round
    lid.appendArc(withCenter: NSPoint(x: midX, y: y - s * 0.16), radius: d * 0.52,
                  startAngle: 35, endAngle: 145, clockwise: false)
    lid.stroke()
}

for (name, px) in [("512", 512), ("512@2x", 1024), ("256", 256), ("128", 128), ("64", 64), ("32", 32)] {
    png(px, "yijian-\(name).png", iconYijian)
}
print("done: \(out.path)")
