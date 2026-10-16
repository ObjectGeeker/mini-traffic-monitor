import AppKit
import Foundation

// 生成 AppIcon.iconset 所需的各尺寸 PNG
// 遵循 Apple 图标网格：squircle 占画布约 80%（留 10% 边距），内部元素相对 squircle 定位，
// 否则在 Launchpad/Dock 里会显得比遵循模板的邻居图标大一圈
func draw(size s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()

    let m = s * 0.10
    let shape = NSRect(x: m, y: m, width: s - m * 2, height: s - m * 2)
    let radius = shape.width * 0.225
    NSColor(calibratedRed: 0.11, green: 0.11, blue: 0.13, alpha: 1).setFill()
    NSBezierPath(roundedRect: shape, xRadius: radius, yRadius: radius).fill()

    // squircle 内相对坐标 → 画布坐标
    func px(_ v: CGFloat) -> CGFloat { shape.minX + v * shape.width }
    func py(_ v: CGFloat) -> CGFloat { shape.minY + v * shape.height }

    // 折线（网速曲线意象）
    let pts: [(CGFloat, CGFloat)] = [(0.16, 0.42), (0.32, 0.58), (0.48, 0.36), (0.64, 0.62), (0.84, 0.46)]
    let path = NSBezierPath()
    for (i, p) in pts.enumerated() {
        let pt = NSPoint(x: px(p.0), y: py(p.1))
        if i == 0 { path.move(to: pt) } else { path.line(to: pt) }
    }
    NSColor.systemGreen.setStroke()
    path.lineWidth = shape.width * 0.055
    path.lineJoinStyle = .round
    path.lineCapStyle = .round
    path.stroke()

    // 右上三态点：绿 / 黄 / 红
    let colors: [NSColor] = [.systemGreen, .systemYellow, .systemRed]
    let d = shape.width * 0.09
    for (i, c) in colors.enumerated() {
        let x = px(0.58 + 0.14 * CGFloat(i))
        let y = py(0.76)
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: x, y: y, width: d, height: d)).fill()
    }

    img.unlockFocus()
    return img
}

func png(_ img: NSImage) -> Data {
    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        fatalError("png encode failed")
    }
    return data
}

let outDir = "Resources/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let mapping: [(size: Int, name: String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
for m in mapping {
    let data = png(draw(size: CGFloat(m.size)))
    try? data.write(to: URL(fileURLWithPath: "\(outDir)/\(m.name)"))
}
print("iconset written to \(outDir)")
