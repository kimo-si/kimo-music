// 与 Kimo 下除 KimoApp.swift 外的 Swift 源码一起编译；所有设置写入独立临时目录。
import AppKit
import Foundation

@main
struct AppearanceCheck {
    // 验证自定义颜色、主题解析和设置迁移，不读写用户的实际设置文件。
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kimo-appearance-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(storageURL: directory.appendingPathComponent("settings.json"))
        // 检查颜色边界和不同背景上的实际文本对比度。
        checkColorInputs()
        checkContrast(settings)
        // 检查模式切换、重启恢复和历史配置兼容。
        checkPersistence(settings, directory: directory)
        try checkLegacySettings(directory)
        checkThemeControls(settings)
        print("外观检查通过：RGB/HEX、54 组颜色对比度、独立设置恢复、旧配置迁移、8 套主题控件")
    }

    // 非法色值不能被解释为黑色，简写与完整 HEX 统一规范化。
    private static func checkColorInputs() {
        check(ColorMath.parseHex(" #abc ")?.hex == "#AABBCC", "简写 HEX 规范化失败")
        check(ColorMath.parseHex("010203")?.triplet.0 == 1, "RGB 分量解析失败")
        for invalid in ["", "#12", "#12345G", "#12345678", "blue"] {
            check(ColorMath.parseHex(invalid) == nil, "非法 HEX 被接受：\(invalid)")
        }
    }

    // 覆盖黑白、灰色阈值和高饱和背景，文字与强调色至少保持 4.5:1 对比度。
    @MainActor
    private static func checkContrast(_ settings: AppSettings) {
        let backgrounds = ["#000000", "#FFFFFF", "#777777", "#747474", "#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#E9EDF2"]
        let accents = ["#000000", "#FFFFFF", "#FF0000", "#00FF00", "#0000FF", "#9B87BF"]
        settings.appearanceMode = .solid
        settings.windowEffect = .none
        for background in backgrounds {
            for accent in accents {
                settings.backgroundHex = background
                settings.accentHex = accent
                let palette = SolidPalette(backgroundHex: background, accentHex: accent)
                let theme = Theme.make(settings: settings, isDark: false)
                check(theme.flavor == .solid && theme.blobs.isEmpty && theme.texture == .flat, "纯色残留主题装饰")
                check(theme.shellRGB.0 == palette.background.triplet.0, "用户背景色被更改")
                checkReadable(theme, backgrounds: palette.backgrounds)
            }
        }
    }

    // 使用最终 Theme 的颜色检查真实文本角色，而不只检查推导算法的中间值。
    private static func checkReadable(_ theme: Theme, backgrounds: [RGB]) {
        for color in [theme.textStrong, theme.text, theme.textSecondary, theme.textMuted, theme.accentStrong] {
            let rgb = NSColor(color).usingColorSpace(.sRGB)!
            let value = RGB(r: rgb.redComponent * 255, g: rgb.greenComponent * 255, b: rgb.blueComponent * 255)
            check(ColorMath.minimumContrast(value, on: backgrounds) >= 4.49, "自定义文字或强调色对比度不足")
        }
    }

    // 切换主题不覆盖纯色数值，重建设置对象后仍能恢复各自的选择。
    @MainActor
    private static func checkPersistence(_ settings: AppSettings, directory: URL) {
        settings.backgroundHex = "#112233"
        settings.accentHex = "#ABCDEF"
        settings.skin = .hifi
        settings.appearanceMode = .theme
        let original = Theme.make(settings: settings, isDark: false)
        settings.backgroundHex = "#F0E0D0"
        check(Theme.make(settings: settings, isDark: false).shellRGB == original.shellRGB, "纯色修改污染内置主题")
        settings.appearanceMode = .solid
        let restored = AppSettings(storageURL: directory.appendingPathComponent("settings.json"))
        check(restored.appearanceMode == .solid && restored.skin == .hifi, "模式与主题未独立恢复")
        check(restored.backgroundHex == "#F0E0D0" && restored.accentHex == "#ABCDEF", "自定义颜色未恢复")
        check(restored.fixedDarkAppearance == false, "浅色背景未同步系统控件外观")
        restored.backgroundHex = "#101010"
        check(restored.fixedDarkAppearance == true, "深色背景未同步系统控件外观")
    }

    // 旧版只有 skin 的配置应继续使用主题；无效颜色不覆盖安全默认值。
    @MainActor
    private static func checkLegacySettings(_ directory: URL) throws {
        struct LegacySettings: Encodable {
            let skin = "record"
            let backgroundHex = "invalid"
            let accentHex = "invalid"
        }
        let url = directory.appendingPathComponent("legacy.json")
        try JSONEncoder().encode(LegacySettings()).write(to: url)
        let settings = AppSettings(storageURL: url)
        check(settings.appearanceMode == .theme && settings.skin == .record, "旧版主题配置迁移失败")
        check(settings.backgroundHex == AppearanceDefaults.backgroundHex, "无效背景色未回退")
        check(ColorMath.parseHex(settings.accentHex) != nil, "无效强调色未回退")
    }

    // 主题的预览和实际界面共用解析，关键主题保持不同的材质和进度样式。
    @MainActor
    private static func checkThemeControls(_ settings: AppSettings) {
        settings.appearanceMode = .theme
        settings.reduceMotion = true
        for skin in Skin.allCases {
            settings.skin = skin
            let theme = Theme.make(settings: settings, isDark: false)
            let preview = Theme.make(skin: skin, settings: settings, isDark: false)
            check(theme.controls.material == preview.controls.material, "预览与实际控件材质不一致")
            check(!theme.allowsMotion, "主题忽略减弱动态效果")
        }
        check(ThemeControlTokens.resolve(flavor: .hifi).usesKnob, "Hi-Fi 缺少音量旋钮")
        check(ThemeControlTokens.resolve(flavor: .record).material == .paper, "唱片店缺少纸感控件")
        check(ThemeControlTokens.resolve(flavor: .mint).progress == .segmented, "游戏机缺少分段进度")
    }

    // 出错时返回明确的失败状态，方便自动检查直接阻止错误版本。
    private static func check(_ condition: Bool, _ message: String) {
        guard condition else { fputs("外观检查失败：\(message)\n", stderr); exit(EXIT_FAILURE) }
    }
}
