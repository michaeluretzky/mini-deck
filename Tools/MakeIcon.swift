// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

// Draws the app icon (a notch pill with a cover square and a play button) into an .iconset folder.
// Usage: MakeIcon <output.iconset>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let charcoal = NSColor(red: 22 / 255, green: 24 / 255, blue: 30 / 255, alpha: 1)
let teal = NSColor(red: 63 / 255, green: 212 / 255, blue: 192 / 255, alpha: 1)

func draw(_ px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                     samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    // Layout is drawn on a 1024 grid measured from the top, then flipped for AppKit.
    func box(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
        NSRect(x: x * s / 1024, y: s - (top + h) * s / 1024, width: w * s / 1024, height: h * s / 1024)
    }
    func pt(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * s / 1024, y: s - y * s / 1024) }

    charcoal.setFill()
    NSBezierPath(roundedRect: box(100, 100, 824, 824), xRadius: s * 0.18, yRadius: s * 0.18).fill()

    NSColor.white.setFill()
    let pill = box(225, 368, 574, 226)
    NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()

    teal.setFill()
    let cover = box(276, 413, 134, 135)
    NSBezierPath(roundedRect: cover, xRadius: s * 30 / 1024, yRadius: s * 30 / 1024).fill()

    // Play triangle with softly rounded corners.
    let play = NSBezierPath()
    play.move(to: pt(642, 437))
    play.line(to: pt(642, 526))
    play.line(to: pt(722, 481))
    play.close()
    play.lineJoinStyle = .round
    play.lineWidth = s * 24 / 1024
    teal.setStroke()
    play.fill()
    play.stroke()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        if let data = draw(base * scale) { try? data.write(to: out.appendingPathComponent(name)) }
    }
}
