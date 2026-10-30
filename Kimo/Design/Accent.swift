//
//  Accent.swift
//  Kimo
//
//  主题色算法，逐行移植自 cocomusic/src/lib/color.ts。
//  一个色值 → 四个强调色 token，按亮/暗分别做对比度调优。
//

import SwiftUI

struct RGB: Equatable {
    var r: Double
    var g: Double
    var b: Double

    var color: Color { Color(.sRGB, red: r / 255, green: g / 255, blue: b / 255, opacity: 1) }
    var triplet: (Int, Int, Int) { (Int(r.rounded()), Int(g.rounded()), Int(b.rounded())) }
    var hex: String {
        String(format: "#%02X%02X%02X", Int(r.rounded()), Int(g.rounded()), Int(b.rounded()))
    }
}

struct HSL {
    var h: Double
    var s: Double
    var l: Double
}

struct AccentPalette {
    let accent: RGB
    let strong: RGB
    let tint: RGB
    let tintStrong: RGB
}

enum ColorMath {
    // 在 RGB 空间内混合颜色，保留用户选择的背景色相。
    static func mix(_ source: RGB, _ target: RGB, amount: Double) -> RGB {
        let amount = clamp(amount)
        return RGB(r: source.r + (target.r - source.r) * amount,
                   g: source.g + (target.g - source.g) * amount,
                   b: source.b + (target.b - source.b) * amount)
    }

    // 选择在所有承载面上对比度最高的黑白前景色。
    static func foreground(on backgrounds: [RGB]) -> RGB {
        let black = RGB(r: 0, g: 0, b: 0)
        let white = RGB(r: 255, g: 255, b: 255)
        return minimumContrast(black, on: backgrounds) >= minimumContrast(white, on: backgrounds) ? black : white
    }

    // 调整文字和强调色，确保自定义颜色在各承载面上仍然可读。
    static func readable(_ color: RGB, on backgrounds: [RGB], ratio: Double = 4.5) -> RGB {
        let target = foreground(on: backgrounds)
        for step in 0...100 {
            let candidate = mix(color, target, amount: Double(step) / 100)
            if minimumContrast(candidate, on: backgrounds) >= ratio { return candidate }
        }
        return target
    }

    // 计算一个前景色在多种背景上的最差对比度。
    static func minimumContrast(_ color: RGB, on backgrounds: [RGB]) -> Double {
        backgrounds.map { contrast(color, $0) }.min() ?? 21
    }

    static func clamp(_ v: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
        min(hi, max(lo, v))
    }

    static func parseHex(_ input: String) -> RGB? {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 3 || hex.count == 6,
              hex.allSatisfy({ "0123456789abcdef".contains($0) }) else { return nil }
        if hex.count == 3 {
            hex = hex.map { "\($0)\($0)" }.joined()
        }
        guard let value = UInt32(hex, radix: 16) else { return nil }
        return RGB(r: Double((value >> 16) & 255), g: Double((value >> 8) & 255), b: Double(value & 255))
    }

    static func rgbToHsl(_ c: RGB) -> HSL {
        let r = c.r / 255, g = c.g / 255, b = c.b / 255
        let maxV = max(r, g, b), minV = min(r, g, b)
        let l = (maxV + minV) / 2
        let d = maxV - minV
        let s = d == 0 ? 0 : d / (1 - abs(2 * l - 1))
        var h = 0.0
        if d != 0 {
            if maxV == r { h = ((g - b) / d).truncatingRemainder(dividingBy: 6) }
            else if maxV == g { h = (b - r) / d + 2 }
            else { h = (r - g) / d + 4 }
            h *= 60
            if h < 0 { h += 360 }
        }
        return HSL(h: h, s: s, l: l)
    }

    static func hslToRgb(_ c: HSL) -> RGB {
        let cc = (1 - abs(2 * c.l - 1)) * c.s
        let x = cc * (1 - abs((c.h / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = c.l - cc / 2
        let rgb: (Double, Double, Double)
        switch c.h {
        case ..<60: rgb = (cc, x, 0)
        case ..<120: rgb = (x, cc, 0)
        case ..<180: rgb = (0, cc, x)
        case ..<240: rgb = (0, x, cc)
        case ..<300: rgb = (x, 0, cc)
        default: rgb = (cc, 0, x)
        }
        return RGB(r: (rgb.0 + m) * 255, g: (rgb.1 + m) * 255, b: (rgb.2 + m) * 255)
    }

    static func luminance(_ c: RGB) -> Double {
        func channel(_ v: Double) -> Double {
            let x = v / 255
            return x <= 0.03928 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b)
    }

    static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let x = luminance(a), y = luminance(b)
        let hi = max(x, y), lo = min(x, y)
        return (hi + 0.05) / (lo + 0.05)
    }

    private static func reachContrast(_ color: HSL,
                                      background: RGB,
                                      ratio: Double,
                                      direction: Double) -> HSL {
        var next = color
        var i = 0
        while i < 40 && contrast(hslToRgb(next), background) < ratio {
            next.l = clamp(next.l + direction * 0.02, 0.05, 0.95)
            i += 1
        }
        return next
    }

    private static let lightSurface = RGB(r: 220, g: 222, b: 243)
    private static let darkSurface = RGB(r: 34, g: 31, b: 50)

    /// 一个色值 → 亮/暗两套强调色。
    static func accentPalette(hex: String, isDark: Bool) -> AccentPalette {
        let base = parseHex(hex) ?? parseHex("#9b87bf")!
        let hsl = rgbToHsl(base)
        let s = max(hsl.s, 0.12)

        if !isDark {
            let accent = HSL(h: hsl.h, s: s, l: clamp(hsl.l, 0.42, 0.72))
            let strong = reachContrast(
                HSL(h: hsl.h, s: min(1, s * 1.05), l: min(accent.l, 0.5)),
                background: lightSurface, ratio: 4.5, direction: -1
            )
            let tint = HSL(h: hsl.h, s: clamp(s * 0.55, 0.12, 0.6), l: 0.92)
            return AccentPalette(accent: hslToRgb(accent), strong: hslToRgb(strong),
                                 tint: hslToRgb(tint), tintStrong: hslToRgb(HSL(h: tint.h, s: tint.s, l: 0.87)))
        }

        let accent = HSL(h: hsl.h, s: clamp(s * 0.9, 0.12, 0.85), l: clamp(hsl.l, 0.55, 0.72))
        let strong = reachContrast(
            HSL(h: hsl.h, s: clamp(s, 0.2, 0.9), l: max(accent.l, 0.7)),
            background: darkSurface, ratio: 4.5, direction: 1
        )
        let tint = HSL(h: hsl.h, s: clamp(s * 0.45, 0.12, 0.5), l: 0.26)
        return AccentPalette(accent: hslToRgb(accent), strong: hslToRgb(strong),
                             tint: hslToRgb(tint), tintStrong: hslToRgb(HSL(h: tint.h, s: tint.s, l: 0.31)))
    }
}
