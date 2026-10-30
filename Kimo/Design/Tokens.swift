//
//  Tokens.swift
//  Kimo
//
//  设计令牌：与 cocomusic/src/app/globals.css 一一对应。
//  面板 alpha 由 AppSettings 的「窗口不透明度 / 面板不透明度」实时换算，
//  主题色由 Accent.swift 生成，所以同一个 Theme 会在设置变化时整体重建。
//

import SwiftUI

// MARK: - Hex

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        switch s.count {
        case 8:
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        default:
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    init(rgb: (Int, Int, Int), alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double(rgb.0) / 255,
            green: Double(rgb.1) / 255,
            blue: Double(rgb.2) / 255,
            opacity: alpha
        )
    }
}

// MARK: - Theme

struct Theme {
    let isDark: Bool

    // 基础色调（RGB 分量，alpha 由各自的 surface 决定）
    let surfaceRGB: (Int, Int, Int)
    let raisedRGB: (Int, Int, Int)
    let playerRGB: (Int, Int, Int)
    let inkRGB: (Int, Int, Int)

    // 面板 alpha（受设置影响）
    let sheetAlpha: Double
    let sheetPinnedAlpha: Double
    let cardAlpha: Double
    let cardHoverAlpha: Double
    let playerAlpha: Double
    let navActiveAlpha: Double

    // 文本
    let textStrong: Color
    let text: Color
    let textSecondary: Color
    let textMuted: Color

    // 强调色
    let accent: Color
    let accentStrong: Color
    let accentRGB: (Int, Int, Int)
    let accentStrongRGB: (Int, Int, Int)
    let accentTint: Color
    let accentTintStrong: Color

    // 玻璃与窗口（受设置影响）
    let glassBlur: Double
    let windowEffect: WindowEffect
    let backdropOpacity: Double

    // 语义色
    let like: Color
    let trendUp: Color
    let trendNew: Color
    let danger: Color

    /// 皮肤决定的材质：底色、圆角、播放键、纹理。
    let chrome: ThemeChrome
    let allowsMotion: Bool

    // 面板
    var sheet: Color { Color(rgb: surfaceRGB, alpha: sheetAlpha) }
    var sheetPinned: Color { Color(rgb: chrome.pinnedRGB, alpha: sheetPinnedAlpha) }
    var card: Color { Color(rgb: raisedRGB, alpha: cardAlpha) }
    var cardHover: Color { Color(rgb: raisedRGB, alpha: cardHoverAlpha) }
    var player: Color { Color(rgb: playerRGB, alpha: playerAlpha) }
    var navActive: Color { Color(rgb: raisedRGB, alpha: navActiveAlpha) }
    var glassEdge: Color { chrome.glassEdge }
    var solid: Color { Color(rgb: surfaceRGB) }

    // 交互
    private var solidControlSurface: Color? { flavor == .solid ? Color(rgb: raisedRGB) : nil }
    var hover: Color { solidControlSurface ?? (isDark ? Color.white.opacity(0.07) : Color(rgb: raisedRGB, alpha: 0.55)) }
    var hoverStrong: Color { solidControlSurface ?? (isDark ? Color.white.opacity(0.12) : Color(rgb: raisedRGB, alpha: 0.8)) }
    var field: Color { solidControlSurface ?? Color(rgb: raisedRGB, alpha: isDark ? 0.76 : 0.70) }
    var fieldFocus: Color { solidControlSurface ?? Color(rgb: raisedRGB, alpha: 0.92) }
    var chip: Color { solidControlSurface ?? (isDark ? Color.white.opacity(0.07) : Color(rgb: raisedRGB, alpha: 0.55)) }
    var rowHover: Color { solidControlSurface ?? (isDark ? Color.white.opacity(0.07) : Color(rgb: raisedRGB, alpha: 0.62)) }
    var divider: Color { isDark ? Color.white.opacity(0.08) : Color(rgb: accentStrongRGB, alpha: 0.10) }
    var playerRail: Color { isDark ? Color.white.opacity(0.10) : Color(rgb: inkRGB, alpha: 0.14) }
    var playerHairline: Color { isDark ? Color.white.opacity(0.12) : Color(rgb: inkRGB, alpha: 0.12) }
    var accentSoft: Color { solidControlSurface ?? Color(rgb: accentRGB, alpha: isDark ? 0.20 : 0.16) }
    var inkScrim: Color { isDark ? Color.black.opacity(0.45) : Color(rgb: inkRGB, alpha: 0.22) }

    var shell: Color { Color(rgb: chrome.shellRGB) }
    var shellRGB: (Int, Int, Int) { chrome.shellRGB }
    var blobs: [Color] { chrome.blobs }
    var nowPlaying: Color { chrome.nowPlaying }
    var radiusSheet: CGFloat { chrome.radiusSheet }
    var radiusCard: CGFloat { chrome.radiusCard }
    var radiusRow: CGFloat { chrome.radiusRow }
    var serifTitles: Bool { chrome.serifTitles }
    var flavor: SkinFlavor { chrome.flavor }
    var texture: SkinTexture { chrome.texture }
    var controls: ThemeControlTokens { .resolve(flavor: flavor) }
    var usesGlassMaterial: Bool { controls.material == .glass || controls.material == .chrome }

    func titleFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        serifTitles
            ? .system(size: size, weight: weight, design: .serif)
            : .system(size: size, weight: weight)
    }

    // MARK: 构造

    @MainActor
    static func make(settings: AppSettings, isDark: Bool) -> Theme {
        if settings.appearanceMode == .solid {
            return SolidPalette(backgroundHex: settings.backgroundHex, accentHex: settings.accentHex).make(settings: settings)
        }
        // 内置主题使用自己的配色，不覆盖用户单独保存的纯色设置。
        return make(skin: settings.skin, settings: settings, isDark: isDark)
    }

    // 为实际界面和主题缩略图使用同一套主题构造逻辑。
    @MainActor
    static func make(skin: Skin, settings: AppSettings, isDark: Bool) -> Theme {
        if let paint = skin.paint {
            return paint.make(settings: settings)
        }
        let palette = ColorMath.accentPalette(hex: AppearanceDefaults.accentHex, isDark: isDark)
        return build(
            isDark: isDark,
            palette: palette,
            sheetAlpha: settings.surfaceAlpha(0.5),
            sheetPinnedAlpha: settings.surfaceAlpha(0.9),
            cardAlpha: settings.surfaceAlpha(0.46),
            cardHoverAlpha: settings.surfaceAlpha(0.72),
            playerAlpha: settings.surfaceAlpha(0.58),
            navActiveAlpha: settings.surfaceAlpha(0.7),
            glassBlur: settings.glassBlur,
            windowEffect: settings.windowEffect,
            backdropOpacity: settings.backdropOpacity,
            allowsMotion: !settings.reduceMotion
        )
    }

    /// 默认外观（不依赖设置对象，供 Environment 默认值使用）。
    static func plain(isDark: Bool) -> Theme {
        build(
            isDark: isDark,
            palette: ColorMath.accentPalette(hex: "#9b87bf", isDark: isDark),
            sheetAlpha: 0.5, sheetPinnedAlpha: 0.9, cardAlpha: 0.46,
            cardHoverAlpha: 0.72, playerAlpha: 0.58, navActiveAlpha: 0.7,
            glassBlur: 36, windowEffect: .vibrancy, backdropOpacity: 1,
            allowsMotion: true
        )
    }

    private static func build(isDark: Bool,
                              palette: AccentPalette,
                              sheetAlpha: Double,
                              sheetPinnedAlpha: Double,
                              cardAlpha: Double,
                              cardHoverAlpha: Double,
                              playerAlpha: Double,
                              navActiveAlpha: Double,
                              glassBlur: Double,
                              windowEffect: WindowEffect,
                              backdropOpacity: Double,
                              allowsMotion: Bool) -> Theme {
        Theme(
            isDark: isDark,
            surfaceRGB: isDark ? (34, 31, 50) : (246, 246, 255),
            raisedRGB: isDark ? (58, 53, 82) : (255, 255, 255),
            playerRGB: isDark ? (26, 24, 38) : (244, 244, 255),
            inkRGB: isDark ? (0, 0, 0) : (40, 32, 80),
            sheetAlpha: sheetAlpha,
            sheetPinnedAlpha: sheetPinnedAlpha,
            cardAlpha: cardAlpha,
            cardHoverAlpha: cardHoverAlpha,
            playerAlpha: playerAlpha,
            navActiveAlpha: navActiveAlpha,
            textStrong: isDark ? Color(hex: "F1EFFA") : Color(hex: "25294A"),
            text: isDark ? Color(hex: "D9D6E6") : Color(hex: "353342"),
            textSecondary: isDark ? Color(hex: "B3AFC6") : Color(hex: "57546A"),
            textMuted: isDark ? Color(hex: "9B97B0") : Color(hex: "5F627A"),
            accent: palette.accent.color,
            accentStrong: palette.strong.color,
            accentRGB: palette.accent.triplet,
            accentStrongRGB: palette.strong.triplet,
            accentTint: palette.tint.color,
            accentTintStrong: palette.tintStrong.color,
            glassBlur: glassBlur,
            windowEffect: windowEffect,
            backdropOpacity: backdropOpacity,
            like: isDark ? Color(hex: "F07A70") : Color(hex: "E0605A"),
            trendUp: isDark ? Color(hex: "F07A70") : Color(hex: "E0605A"),
            trendNew: isDark ? Color(hex: "5CC58A") : Color(hex: "3FA96B"),
            danger: isDark ? Color(hex: "F0716B") : Color(hex: "D9534F"),
            chrome: .standard(isDark: isDark, palette: palette),
            allowsMotion: allowsMotion
        )
    }

    static let light = Theme.plain(isDark: false)
    static let dark = Theme.plain(isDark: true)
}

// MARK: - Metrics

enum Metrics {
    static let sidebarWidth: CGFloat = 200
    static let sidebarCollapsedWidth: CGFloat = 72
    static let sidebarInset: CGFloat = 16
    static let mainInsetLeft: CGFloat = 20
    static let topBarHeight: CGFloat = 56
    static let topBarGap: CGFloat = 16
    static let playerHeight: CGFloat = 76
    static let miniPlayerWidth: CGFloat = 420
    static let miniPlayerHeight: CGFloat = 80
    static let brandHeight: CGFloat = 50
    static let brandTopOffset: CGFloat = 22

    static let radiusSheet: CGFloat = 24
    static let radiusCard: CGFloat = 12
    static let radiusCover: CGFloat = 10
}

// MARK: - Environment

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.light
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
