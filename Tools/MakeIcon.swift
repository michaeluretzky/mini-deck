// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

// Draws the app icon (a record with a player arm) into an .iconset folder.
// Usage: MakeIcon <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let tile = NSRect(x: s * 0.1, y: s * 0.1, width: s * 0.8, height: s * 0.8)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(colors: [NSColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 1),
                        NSColor(red: 0.05, green: 0.30, blue: 0.34, alpha: 1)])?.draw(in: tilePath, angle: -60)

    let center = NSPoint(x: s * 0.46, y: s * 0.46)
    let r = s * 0.28
    NSColor(white: 0.06, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)).fill()
    NSColor(white: 1, alpha: 0.10).setStroke()
    for i in 1...5 {
        let gr = r * (0.45 + CGFloat(i) * 0.1)
        let groove = NSBezierPath(ovalIn: NSRect(x: center.x - gr, y: center.y - gr, width: gr * 2, height: gr * 2))
        groove.lineWidth = max(1, s * 0.004)
        groove.stroke()
    }
    let lr = r * 0.36
    NSGradient(colors: [NSColor(red: 0.20, green: 0.85, blue: 0.70, alpha: 1),
                        NSColor(red: 0.35, green: 0.50, blue: 0.95, alpha: 1)])?
        .draw(in: NSBezierPath(ovalIn: NSRect(x: center.x - lr, y: center.y - lr, width: lr * 2, height: lr * 2)), angle: 45)
    NSColor(white: 0.06, alpha: 1).setFill()
    let hole = r * 0.06
    NSBezierPath(ovalIn: NSRect(x: center.x - hole, y: center.y - hole, width: hole * 2, height: hole * 2)).fill()

    // player arm
    let pivot = NSPoint(x: s * 0.76, y: s * 0.74)
    NSColor(white: 0.85, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: pivot.x - s * 0.045, y: pivot.y - s * 0.045, width: s * 0.09, height: s * 0.09)).fill()
    let arm = NSBezierPath()
    arm.move(to: pivot)
    arm.line(to: NSPoint(x: s * 0.70, y: s * 0.42))
    arm.line(to: NSPoint(x: s * 0.60, y: s * 0.33))
    arm.lineWidth = s * 0.028
    arm.lineCapStyle = .round
    arm.lineJoinStyle = .round
    NSColor(white: 0.88, alpha: 1).setStroke()
    arm.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = draw(base * scale) { try? data.write(to: out.appendingPathComponent(name)) }
    }
}
