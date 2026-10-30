//
//  Skins.swift
//  Kimo
//
//  内置主题自带配色、圆角和控件材质；「雾紫玻璃」可跟随系统深浅色。
//  RGB 纯色使用独立的 SolidPalette，切换主题不会覆盖用户颜色。
//

import SwiftUI

enum SkinFlavor: String {
    case solid, standard, night, cream, hifi, liquid, record, mint, chiikawa
}

enum SkinTexture: String {
    case aurora, flat, fiber, wood, orbit
}

/// 一套皮肤里不随透明度设置变化的部分。
struct ThemeChrome {
    var pinnedRGB: (Int, Int, Int)
    var shellRGB: (Int, Int, Int)
    var glassEdge: Color
    var blobs: [Color]
    var playDisc: Color
    var nowPlaying: Color
    var radiusSheet: CGFloat
    var radiusCard: CGFloat
    var radiusRow: CGFloat
    var serifTitles: Bool
    var flavor: SkinFlavor
    var texture: SkinTexture

    static func standard(isDark: Bool, palette: AccentPalette) -> ThemeChrome {
        ThemeChrome(
            pinnedRGB: isDark ? (30, 27, 44) : (238, 237, 252),
            shellRGB: isDark ? (21, 19, 31) : (223, 225, 245),
            glassEdge: isDark ? Color.white.opacity(0.08) : Color.white.opacity(0.62),
            blobs: isDark
                ? [
                    Color(hex: "6046AA").opacity(0.55),
                    Color(hex: "345296").opacity(0.50),
                    Color(hex: "6E3C8C").opacity(0.45),
                    Color(hex: "285A82").opacity(0.40),
                    Color(hex: "3A2E52").opacity(0.40),
                ]
                : [
                    Color(hex: "C4B2F6").opacity(0.95),
                    Color(hex: "B0CEFC").opacity(0.90),
                    Color(hex: "D6BEF4").opacity(0.85),
                    Color(hex: "B4DEF6").opacity(0.80),
                    Color(hex: "F0DEF6").opacity(0.70),
                ],
            playDisc: isDark ? palette.tint.color.opacity(0.85) : Color(hex: "E6DFF5"),
            nowPlaying: .clear,
            radiusSheet: 24,
            radiusCard: 12,
            radiusRow: 8,
            serifTitles: false,
            flavor: .standard,
            texture: .aurora
        )
    }
}

enum Skin: String, CaseIterable, Identifiable {
    case standard
    case night
    case cream
    case hifi
    case liquid
    case record
    case mint
    case chiikawa

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: return "雾紫玻璃"
        case .night: return "极夜银蓝"
        case .cream: return "奶油焦糖"
        case .hifi: return "复古 Hi-Fi"
        case .liquid: return "液态银"
        case .record: return "独立唱片店"
        case .mint: return "薄荷游戏机"
        case .chiikawa: return "Chiikawa 奶油日常"
        }
    }

    var subtitle: String {
        switch self {
        case .standard: return "原来的样子"
        case .night: return "冷静科技"
        case .cream: return "温暖生活"
        case .hifi: return "胡桃木 · 实体按键 · 音量旋钮"
        case .liquid: return "Y2K 未来感"
        case .record: return "纸张材质 · 印章按键 · 刻度轨道"
        case .mint: return "立体按键 · 按压反馈 · 分段进度"
        case .chiikawa: return "吉伊 · 小八 · 乌萨奇"
        }
    }

    /// 预设皮肤锁死深浅色。默认皮肤跟随外观模式。
    var forcesDark: Bool? {
        switch self {
        case .standard: return nil
        case .night, .hifi: return true
        case .cream, .liquid, .record, .mint, .chiikawa: return false
        }
    }

    var paint: SkinPaint? {
        switch self {
        case .standard: return nil
        case .night: return .night
        case .cream: return .cream
        case .hifi: return .hifi
        case .liquid: return .liquid
        case .record: return .record
        case .mint: return .mint
        case .chiikawa: return .chiikawa
        }
    }
}

struct SkinPaint {
    var isDark: Bool
    var surfaceRGB: (Int, Int, Int)
    var raisedRGB: (Int, Int, Int)
    var playerRGB: (Int, Int, Int)
    var inkRGB: (Int, Int, Int)
    var textStrong: Color
    var text: Color
    var textSecondary: Color
    var textMuted: Color
    var accent: Color
    var accentStrong: Color
    var accentRGB: (Int, Int, Int)
    var accentStrongRGB: (Int, Int, Int)
    var like: Color
    var trendUp: Color
    var trendNew: Color
    var danger: Color
    var chrome: ThemeChrome

    @MainActor
    func make(settings: AppSettings) -> Theme {
        Theme(
            isDark: isDark,
            surfaceRGB: surfaceRGB,
            raisedRGB: raisedRGB,
            playerRGB: playerRGB,
            inkRGB: inkRGB,
            sheetAlpha: settings.surfaceAlpha(isDark ? 0.72 : 0.62),
            sheetPinnedAlpha: settings.surfaceAlpha(0.94),
            cardAlpha: settings.surfaceAlpha(isDark ? 0.55 : 0.72),
            cardHoverAlpha: settings.surfaceAlpha(0.86),
            playerAlpha: settings.surfaceAlpha(isDark ? 0.82 : 0.78),
            navActiveAlpha: settings.surfaceAlpha(0.78),
            textStrong: textStrong,
            text: text,
            textSecondary: textSecondary,
            textMuted: textMuted,
            accent: accent,
            accentStrong: accentStrong,
            accentRGB: accentRGB,
            accentStrongRGB: accentStrongRGB,
            accentTint: chrome.playDisc,
            accentTintStrong: accentStrong,
            glassBlur: settings.glassBlur,
            windowEffect: settings.windowEffect,
            backdropOpacity: settings.backdropOpacity,
            like: like,
            trendUp: trendUp,
            trendNew: trendNew,
            danger: danger,
            chrome: chrome,
            allowsMotion: !settings.reduceMotion
        )
    }
}

private func rgb(_ hex: String) -> (Int, Int, Int) {
    ColorMath.parseHex(hex)?.triplet ?? (0, 0, 0)
}

private func paint(
    dark: Bool,
    surface: String, raised: String, player: String, pinned: String, ink: String, shell: String,
    strong: String, body: String, secondary: String, muted: String,
    accent: String, accentStrong: String,
    like: String, up: String, fresh: String, danger: String,
    edge: Color,
    blobs: [Color],
    disc: String, now: String,
    sheet: CGFloat, card: CGFloat, row: CGFloat,
    serif: Bool = false,
    flavor: SkinFlavor,
    texture: SkinTexture
) -> SkinPaint {
    SkinPaint(
        isDark: dark,
        surfaceRGB: rgb(surface),
        raisedRGB: rgb(raised),
        playerRGB: rgb(player),
        inkRGB: rgb(ink),
        textStrong: Color(hex: strong),
        text: Color(hex: body),
        textSecondary: Color(hex: secondary),
        textMuted: Color(hex: muted),
        accent: Color(hex: accent),
        accentStrong: Color(hex: accentStrong),
        accentRGB: rgb(accent),
        accentStrongRGB: rgb(accentStrong),
        like: Color(hex: like),
        trendUp: Color(hex: up),
        trendNew: Color(hex: fresh),
        danger: Color(hex: danger),
        chrome: ThemeChrome(
            pinnedRGB: rgb(pinned),
            shellRGB: rgb(shell),
            glassEdge: edge,
            blobs: blobs,
            playDisc: Color(hex: disc),
            nowPlaying: Color(hex: now),
            radiusSheet: sheet,
            radiusCard: card,
            radiusRow: row,
            serifTitles: serif,
            flavor: flavor,
            texture: texture
        )
    )
}

extension SkinPaint {
    static let night = paint(
        dark: true,
        surface: "101824", raised: "1A2636", player: "0B1018", pinned: "0E1622", ink: "05080C", shell: "070B12",
        strong: "E6EEF4", body: "C5D0DA", secondary: "8E9DAB", muted: "6A7A8A",
        accent: "7EC8E3", accentStrong: "D4F1FA",
        like: "E7A0A8", up: "E7A0A8", fresh: "6FCBB2", danger: "E07A72",
        edge: Color.white.opacity(0.10),
        blobs: [
            Color(hex: "1A4E72").opacity(0.50),
            Color(hex: "12344E").opacity(0.42),
            Color(hex: "0E3A4A").opacity(0.32),
        ],
        disc: "163044", now: "173044",
        sheet: 16, card: 8, row: 6,
        flavor: .night, texture: .flat
    )

    static let cream = paint(
        dark: false,
        surface: "FBF6EE", raised: "F3E4D2", player: "F7F0E6", pinned: "F8F1E6", ink: "4A3428", shell: "F4EBDF",
        strong: "3A2A22", body: "4E382C", secondary: "7A5C48", muted: "A08B78",
        accent: "C17A3A", accentStrong: "8F5524",
        like: "C45C4A", up: "C45C4A", fresh: "6E9A62", danger: "B94A42",
        edge: Color(hex: "E4D0B8").opacity(0.95),
        blobs: [
            Color(hex: "F0CBA6").opacity(0.85),
            Color(hex: "E7D3B4").opacity(0.75),
            Color(hex: "F6E2CC").opacity(0.70),
        ],
        disc: "E7B07A", now: "F6E3CF",
        sheet: 28, card: 16, row: 12,
        flavor: .cream, texture: .aurora
    )

    static let hifi = paint(
        dark: true,
        surface: "3A2618", raised: "4A3220", player: "14110F", pinned: "2C1C12", ink: "0C0A09", shell: "24160F",
        strong: "F6EBD8", body: "E7D7C0", secondary: "C4B09A", muted: "9A8672",
        accent: "E0A23A", accentStrong: "F0C56A",
        like: "E07A4A", up: "E07A4A", fresh: "C6A15A", danger: "C4543A",
        edge: Color(hex: "E8D2A8").opacity(0.28),
        blobs: [],
        disc: "E4C98A", now: "4A3018",
        sheet: 8, card: 4, row: 4,
        flavor: .hifi, texture: .wood
    )

    static let liquid = paint(
        dark: false,
        surface: "F8F6FA", raised: "E7E4EC", player: "F1EEF5", pinned: "F4F1F7", ink: "2A2433", shell: "F3F0F6",
        strong: "241E2E", body: "3A3344", secondary: "6C6478", muted: "948CA0",
        accent: "7B4DFF", accentStrong: "5A2AD6",
        like: "C43AD4", up: "C43AD4", fresh: "3A9E9A", danger: "C4476A",
        edge: Color.white.opacity(0.85),
        blobs: [
            Color(hex: "D9C8FF").opacity(0.55),
            Color(hex: "B9E6FF").opacity(0.40),
            Color(hex: "F2F0F6").opacity(0.50),
        ],
        disc: "D9D7DE", now: "EDE4FF",
        sheet: 22, card: 14, row: 12,
        flavor: .liquid, texture: .orbit
    )

    static let record = paint(
        dark: false,
        surface: "F7F3EC", raised: "EFE6D8", player: "F6F1E8", pinned: "F4EFE6", ink: "1A1614", shell: "F3EEE6",
        strong: "1C1614", body: "2A2420", secondary: "5E7384", muted: "8A8178",
        accent: "8E2F3A", accentStrong: "6E222C",
        like: "8E2F3A", up: "8E2F3A", fresh: "5E7384", danger: "8E2F3A",
        edge: Color(hex: "1A1614").opacity(0.12),
        blobs: [Color(hex: "E6D3BE").opacity(0.40)],
        disc: "8E2F3A", now: "F6E6E4",
        sheet: 12, card: 4, row: 2,
        serif: true,
        flavor: .record, texture: .fiber
    )

    static let mint = paint(
        dark: false,
        surface: "F7FBF8", raised: "FFFFFF", player: "F4FBF7", pinned: "F3FBF7", ink: "14352A", shell: "D5F2E6",
        strong: "14352A", body: "1C4034", secondary: "3E6556", muted: "6E8F80",
        accent: "FF7A72", accentStrong: "D84E48",
        like: "FF7A72", up: "E06A64", fresh: "2F8F6B", danger: "C4473E",
        edge: Color.white.opacity(0.80),
        blobs: [
            Color(hex: "A8E4CC").opacity(0.75),
            Color(hex: "F6C9C4").opacity(0.28),
            Color(hex: "E7F7F0").opacity(0.60),
        ],
        disc: "FF7A72", now: "E4F6EE",
        sheet: 28, card: 18, row: 14,
        flavor: .mint, texture: .aurora
    )

    static let chiikawa = paint(
        dark: false,
        surface: "FFFAF8", raised: "FCEFEB", player: "FFF5F1", pinned: "FFF7F4", ink: "48353F", shell: "FFF8F5",
        strong: "49343B", body: "60484F", secondary: "80636C", muted: "92757E",
        accent: "E99AAA", accentStrong: "A94961",
        like: "D76D84", up: "D66F81", fresh: "588B9A", danger: "B64D63",
        edge: Color(hex: "EFCFD4").opacity(0.82),
        blobs: [
            Color(hex: "F8D9E0").opacity(0.48),
            Color(hex: "DBEDF4").opacity(0.42),
            Color(hex: "FFF1D5").opacity(0.34),
        ],
        disc: "F2B4C0", now: "FBE6EB",
        sheet: 24, card: 14, row: 10,
        flavor: .chiikawa, texture: .aurora
    )
}

// 在皮肤预览与界面角落复用同一张透明角色插画。
struct ChiikawaArtwork: View {
    private static let artwork = BundleImage.named("chiikawa-trio")

    var body: some View {
        if let artwork = Self.artwork {
            Image(nsImage: artwork)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .accessibilityHidden(true)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - 背景纹理

struct SkinBackdrop: View {
    let theme: Theme
    /// 沉浸式页面（播放页）不想被窗口透明度拖到看不见，可以单独给一个不透明度。
    var opacityOverride: Double? = nil

    var body: some View {
        ZStack {
            theme.shell
            switch theme.texture {
            case .fiber:
                FiberOverlay()
            case .wood:
                WoodGrain()
            case .orbit:
                OrbitMarks()
            case .aurora, .flat:
                EmptyView()
            }
        }
        .opacity(opacityOverride ?? theme.backdropOpacity)
        .ignoresSafeArea()
    }
}

private struct FiberOverlay: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 42)
            for _ in 0..<160 {
                let x = rng.next() * size.width
                let y = rng.next() * size.height
                var path = Path()
                path.move(to: CGPoint(x: x, y: y))
                path.addLine(to: CGPoint(x: x + 10 + rng.next() * 26, y: y + rng.next() * 1.6))
                context.stroke(path, with: .color(Color(hex: "8A7358").opacity(0.055)), lineWidth: 0.7)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct WoodGrain: View {
    var body: some View {
        Canvas { context, size in
            var rng = SeededRandom(seed: 7)
            for i in 0..<18 {
                let y = size.height * (CGFloat(i) / 18) + CGFloat(rng.next() * 12)
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addQuadCurve(
                    to: CGPoint(x: size.width, y: y + CGFloat(rng.next() * 10 - 5)),
                    control: CGPoint(x: size.width * 0.5, y: y + CGFloat(rng.next() * 16 - 8))
                )
                context.stroke(path, with: .color(Color.black.opacity(0.06)), lineWidth: 1)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct OrbitMarks: View {
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Ellipse()
                    .stroke(Color(hex: "7B4DFF").opacity(0.16), lineWidth: 1)
                    .frame(width: geo.size.width * 0.42, height: geo.size.height * 0.22)
                    .rotationEffect(.degrees(-18))
                    .position(x: geo.size.width * 0.78, y: geo.size.height * 0.22)
                Ellipse()
                    .stroke(Color(hex: "7ED0E8").opacity(0.28), lineWidth: 1)
                    .frame(width: geo.size.width * 0.30, height: geo.size.height * 0.16)
                    .rotationEffect(.degrees(12))
                    .position(x: geo.size.width * 0.18, y: geo.size.height * 0.72)
            }
        }
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

private struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1 }
    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(state % 10_000) / 10_000
    }
}

// MARK: - 顶栏图标

struct SkinGlyph: View {
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .stroke(theme.textSecondary, lineWidth: 1.15)
                .frame(width: 11, height: 13)
                .rotationEffect(.degrees(-16))
                .offset(x: -2.5, y: 0.5)
            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(theme.accent)
                .frame(width: 11, height: 13)
                .overlay {
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .stroke(theme.textStrong.opacity(0.28), lineWidth: 0.8)
                }
                .rotationEffect(.degrees(12))
                .offset(x: 2.5, y: -0.5)
        }
        .frame(width: 18, height: 18)
    }
}
