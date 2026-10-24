// Renders the ClayMore app icon into an .iconset folder.
// Usage: swift tools/make_icon.swift <out.iconset> && iconutil -c icns <out.iconset>
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)

    // Base squircle with drop shadow (macOS icon grid: 824pt body inside 1024 canvas).
    let body = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0x000000, 0.35)
    shadow.shadowBlurRadius = 28
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.set()
    color(0x15161B).setFill()
    body.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: color(0x30333F), ending: color(0x121318))!.draw(in: body, angle: -90)

    // Left half: kanban columns with cards (Todo / In Progress / Done).
    let accents = [color(0x5B8DEF), color(0xF0A33A), color(0x3FBF7F)]
    let cardsPerColumn = [3, 2, 1]
    for (i, accent) in accents.enumerated() {
        let x = 196 + CGFloat(i) * 106
        for j in 0..<cardsPerColumn[i] {
            let y = 690 - CGFloat(j) * 112
            accent.setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 86, height: 92), xRadius: 18, yRadius: 18).fill()
        }
    }

    // Divider.
    color(0xFFFFFF, 0.14).setFill()
    NSBezierPath(roundedRect: NSRect(x: 524, y: 250, width: 6, height: 532), xRadius: 3, yRadius: 3).fill()

    // Right half: lines of a note.
    let widths: [CGFloat] = [250, 210, 250, 160, 230, 120]
    for (i, w) in widths.enumerated() {
        color(0xFFFFFF, i == 0 ? 0.95 : 0.6).setFill()
        let y = 740 - CGFloat(i) * 82
        NSBezierPath(roundedRect: NSRect(x: 574, y: y, width: w, height: 34), xRadius: 17, yRadius: 17).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: out.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: out.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
