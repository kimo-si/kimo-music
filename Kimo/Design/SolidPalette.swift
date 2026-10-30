import SwiftUI

enum AppearanceDefaults {
    static let backgroundHex = "#E9EDF2"
    static let accentHex = "#9B87BF"
}

// 从用户选择的两个 RGB 颜色推导可读的纯色界面，不附加纹理或色斑。
struct SolidPalette {
    let background: RGB
    let surface: RGB
    let raised: RGB
    let foreground: RGB
    let accent: RGB
    let isDark: Bool

    var backgrounds: [RGB] { [background, surface, raised] }

    // 对中等亮度背景向安全方向生成面板层次，避免黑白文字同时失去对比度。
    init(backgroundHex: String, accentHex: String) {
        let base = ColorMath.parseHex(backgroundHex) ?? ColorMath.parseHex(AppearanceDefaults.backgroundHex)!
        let ink = ColorMath.foreground(on: [base])
        let dark = ink.r > 127
        let target = dark && ColorMath.luminance(base) > 0.08
            ? RGB(r: 0, g: 0, b: 0) : RGB(r: 255, g: 255, b: 255)
        background = base
        surface = ColorMath.mix(base, target, amount: dark ? 0.04 : 0.12)
        raised = ColorMath.mix(base, target, amount: dark ? 0.08 : 0.24)
        foreground = ink
        accent = ColorMath.parseHex(accentHex) ?? ColorMath.parseHex(AppearanceDefaults.accentHex)!
        isDark = dark
    }

    // 通过现有 SkinPaint 管线继承透明度设置和全局动态效果偏好。
    @MainActor
    func make(settings: AppSettings) -> Theme {
        let paint = SkinPaint(
            isDark: isDark, surfaceRGB: surface.triplet, raisedRGB: raised.triplet,
            playerRGB: surface.triplet, inkRGB: foreground.triplet,
            textStrong: text(amount: 0), text: text(amount: 0.10),
            textSecondary: text(amount: 0.28), textMuted: text(amount: 0.40),
            accent: accent.color, accentStrong: readableAccent.color,
            accentRGB: accent.triplet, accentStrongRGB: readableAccent.triplet,
            like: semantic("#C94C65"), trendUp: semantic("#C94C65"),
            trendNew: semantic("#238063"), danger: semantic("#C34343"), chrome: chrome
        )
        // 统一应用用户的窗口透明度和减弱动态效果设置。
        return paint.make(settings: settings)
    }

    var readableAccent: RGB { ColorMath.readable(accent, on: backgrounds) }

    // 保持纯色模式的表面形状简洁，当前播放行仍有明确的选中反馈。
    private var chrome: ThemeChrome {
        ThemeChrome(
            pinnedRGB: surface.triplet, shellRGB: background.triplet,
            glassEdge: foreground.color.opacity(0.12), blobs: [],
            playDisc: raised.color, nowPlaying: raised.color,
            radiusSheet: 20, radiusCard: 12, radiusRow: 8,
            serifTitles: false, flavor: .solid, texture: .flat
        )
    }

    // 为次要文字保留层次，同时保证其对比度不会随用户颜色失效。
    private func text(amount: Double) -> Color {
        ColorMath.readable(ColorMath.mix(foreground, background, amount: amount), on: backgrounds).color
    }

    // 将错误、喜欢等语义色调校到自定义背景可读的范围。
    private func semantic(_ hex: String) -> Color {
        ColorMath.readable(ColorMath.parseHex(hex)!, on: backgrounds).color
    }
}
