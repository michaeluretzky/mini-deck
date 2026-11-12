// Mini Deck. Copyright (c) 2026 Michael Uretzky. All rights reserved.
// Free for personal use. See LICENSE.

import AppKit
import Accelerate
import SwiftUI

struct RGB: Equatable {
    var r: Double, g: Double, b: Double
}

extension RGB {
    init(h: Double, s: Double, v: Double) {
        let i = floor(h * 6), f = h * 6 - i
        let p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s)
        switch Int(i) % 6 {
        case 0: self.init(r: v, g: t, b: p)
        case 1: self.init(r: q, g: v, b: p)
        case 2: self.init(r: p, g: v, b: t)
        case 3: self.init(r: p, g: q, b: v)
        case 4: self.init(r: t, g: p, b: v)
        default: self.init(r: v, g: p, b: q)
        }
    }

    var hsv: (h: Double, s: Double, v: Double) {
        let hi = max(r, g, b), lo = min(r, g, b), d = hi - lo
        var h = 0.0
        if d > 0 {
            if hi == r { h = (g - b) / d } else if hi == g { h = (b - r) / d + 2 } else { h = (r - g) / d + 4 }
            h /= 6
            if h < 0 { h += 1 }
        }
        return (h, hi == 0 ? 0 : d / hi, hi)
    }

    func distance2(_ o: RGB) -> Double { (r - o.r) * (r - o.r) + (g - o.g) * (g - o.g) + (b - o.b) * (b - o.b) }

    /// Same hue, bright enough to glow on a dark card.
    var glowing: RGB {
        let c = hsv
        let s = c.s < 0.1 ? c.s : min(0.85, max(0.45, c.s))
        return RGB(h: c.h, s: s, v: max(0.85, c.v))
    }

    /// Same hue, deep enough to be the card's base.
    var shadowed: RGB {
        let c = hsv
        let s = c.s < 0.1 ? c.s : min(0.7, max(0.4, c.s))
        return RGB(h: c.h, s: s, v: 0.16)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}

/// Three colors taken from the cover: two accents and a deep base.
struct Swatch: Equatable {
    var lead: Color
    var echo: Color
    var ground: Color

    static let fallback = Swatch.make(primary: RGB(r: 0.16, g: 0.72, b: 0.62), secondary: RGB(r: 0.32, g: 0.45, b: 0.86))

    static func make(primary: RGB, secondary: RGB) -> Swatch {
        Swatch(lead: primary.glowing.color, echo: secondary.glowing.color, ground: primary.shadowed.color)
    }
}

enum Palette {
    /// Small k-means over the cover's colorful pixels, ranked by size and saturation.
    static func swatch(for image: CGImage) -> Swatch {
        let side = 24
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                  space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return .fallback }
        ctx.interpolationQuality = .medium
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        guard let data = ctx.data else { return .fallback }
        let bytes = data.bindMemory(to: UInt8.self, capacity: side * side * 4)
        var pixels: [RGB] = []
        pixels.reserveCapacity(side * side)
        for i in 0..<(side * side) {
            pixels.append(RGB(r: Double(bytes[i * 4]) / 255, g: Double(bytes[i * 4 + 1]) / 255, b: Double(bytes[i * 4 + 2]) / 255))
        }
        let colorful = pixels.filter { let c = $0.hsv; return c.s > 0.25 && c.v > 0.2 }
        // Mostly black-and-white covers get a soft neutral tint instead of a random speck of color.
        guard colorful.count >= max(3, pixels.count / 20) else {
            let avg = mean(pixels)
            return .make(primary: avg, secondary: avg)
        }
        let groups = cluster(colorful, k: 4, rounds: 8)
        let ranked = groups.sorted { score($0) > score($1) }
        let top = ranked[0]
        let second = ranked.dropFirst().first {
            $0.members >= top.members / 4 && $0.center.distance2(top.center) > 0.02
        }?.center ?? top.center
        return .make(primary: top.center, secondary: second)
    }

    private static func score(_ g: (center: RGB, members: Int)) -> Double {
        Double(g.members) * (0.4 + g.center.hsv.s)
    }

    private static func mean(_ items: [RGB]) -> RGB {
        guard !items.isEmpty else { return RGB(r: 0.5, g: 0.5, b: 0.5) }
        let n = Double(items.count)
        return RGB(r: items.map(\.r).reduce(0, +) / n, g: items.map(\.g).reduce(0, +) / n, b: items.map(\.b).reduce(0, +) / n)
    }

    private static func cluster(_ points: [RGB], k: Int, rounds: Int) -> [(center: RGB, members: Int)] {
        let byHue = points.sorted { $0.hsv.h < $1.hsv.h }
        let count = min(k, byHue.count)
        var centers = (0..<count).map { byHue[$0 * byHue.count / count] }
        var members = [Int](repeating: 0, count: count)
        for _ in 0..<rounds {
            var sums = [RGB](repeating: RGB(r: 0, g: 0, b: 0), count: count)
            members = [Int](repeating: 0, count: count)
            for p in points {
                var best = 0
                var bestD = Double.infinity
                for (i, c) in centers.enumerated() {
                    let d = p.distance2(c)
                    if d < bestD { bestD = d; best = i }
                }
                sums[best].r += p.r; sums[best].g += p.g; sums[best].b += p.b
                members[best] += 1
            }
            for i in 0..<count where members[i] > 0 {
                let n = Double(members[i])
                centers[i] = RGB(r: sums[i].r / n, g: sums[i].g / n, b: sums[i].b / n)
            }
        }
        return zip(centers, members).map { ($0, $1) }.filter { $0.1 > 0 }
    }
}

enum CoverArt {
    /// Resamples the cover to the exact pixel size of the current screen so small cover text stays sharp.
    static func render(_ image: CGImage, side: CGFloat, scale: CGFloat) -> NSImage {
        let size = NSSize(width: side, height: side)
        let fallback = NSImage(cgImage: image, size: size)
        let px = max(1, Int((side * scale).rounded()))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let format = vImage_CGImageFormat(bitsPerComponent: 8, bitsPerPixel: 32, colorSpace: space,
                                                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)),
              var source = try? vImage_Buffer(cgImage: image, format: format) else { return fallback }
        defer { source.free() }
        guard var target = try? vImage_Buffer(width: px, height: px, bitsPerPixel: 32) else { return fallback }
        defer { target.free() }
        let status = vImageScale_ARGB8888(&source, &target, nil, vImage_Flags(kvImageHighQualityResampling))
        guard status == kvImageNoError, let out = try? target.createCGImage(format: format) else { return fallback }
        return NSImage(cgImage: out, size: size)
    }
}
