//
//  AppSettings.swift
//  Kimo
//
//  设置项与持久化。字段和默认值对齐 cocomusic/src/lib/settings.ts，
//  只保留能在原生端真正生效的那些（不摆空开关）。
//

import Observation
import SwiftUI

enum AppearanceMode: String, CaseIterable, Identifiable {
    case solid, theme
    var id: String { rawValue }
    var title: String { self == .solid ? "纯色" : "主题" }
}

enum ThemeMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
}

enum WindowEffect: String, CaseIterable, Identifiable {
    /// 系统毛玻璃：桌面被系统模糊后透出来，应用再蒙一层自己的底色。
    case vibrancy
    /// 透明：不画自己的底色，桌面直接透出来。
    case transparent
    /// 不透明：窗口自带底色，桌面完全看不到。
    case none

    var id: String { rawValue }
    var label: String {
        switch self {
        case .vibrancy: return "毛玻璃"
        case .transparent: return "透明"
        case .none: return "不透明"
        }
    }
}

enum LyricAlign: String, CaseIterable, Identifiable {
    case left, center
    var id: String { rawValue }
    var label: String { self == .left ? "左对齐" : "居中" }
}

@MainActor
@Observable
final class AppSettings {
    // ── 外观 ──
    var themeMode: ThemeMode = .light { didSet { save() } }
    var windowEffect: WindowEffect = .vibrancy { didSet { save() } }
    /// 0–100：画在系统毛玻璃之上的底色浓度，越低越透。
    var windowOpacity: Double = 100 { didSet { save() } }
    /// 0–100：面板（内容区、播放栏、卡片）的不透明度。
    var glassOpacity: Double = 100 { didSet { save() } }
    /// 0–60px：面板毛玻璃强度，0 = 清透玻璃。
    var glassBlur: Double = 36 { didSet { save() } }
    var accentHex: String = "#9b87bf" { didSet { save() } }
    var backgroundHex: String = AppearanceDefaults.backgroundHex { didSet { save() } }
    var appearanceMode: AppearanceMode = .theme { didSet { save() } }
    var skin: Skin = .standard { didSet { save() } }
    var reduceMotion: Bool = false { didSet { save() } }

    // ── 播放 ──
    /// 酷狗音质标识：128 / 320 / flac。
    var quality: String = "128" { didSet { save() } }
    var fadeMs: Double = 400 { didSet { save() } }
    var playbackRate: Double = 1.0 { didSet { save() } }
    var resumeOnLaunch: Bool = true { didSet { save() } }
    var skipOnError: Bool = true { didSet { save() } }
    /// replace = 播放整个列表；insert = 只把这首插到当前曲后面。
    var doubleClick: String = "replace" { didSet { save() } }

    // ── 歌词页 ──
    var lyricsFontSize: Double = 18 { didSet { save() } }
    var lyricsAlign: LyricAlign = .left { didSet { save() } }
    var lyricsBackground: String = "cover" { didSet { save() } }
    var lyricsSpinCover: Bool = true { didSet { save() } }
    /// 是否在播放页显示底部播放控制栏。
    var showLyricsPlayerBar: Bool = true { didSet { save() } }
    /// 毫秒：正值让歌词提前出现。
    var lyricsOffset: Double = 0 { didSet { save() } }

    // ── 桌面歌词 ──
    var desktopLyricsFontSize: Double = 30 { didSet { save() } }
    var desktopLyricsShowNext: Bool = true { didSet { save() } }
    var desktopLyricsStroke: Bool = true { didSet { save() } }

    // ── 持久化 ──

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Kimo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("settings.json")
    }

    private struct Snapshot: Codable {
        var appearanceMode: String?
        var backgroundHex: String?
        var themeMode: String?
        var windowEffect: String?
        var windowOpacity: Double?
        var glassOpacity: Double?
        var glassBlur: Double?
        var accentHex: String?
        var skin: String?
        var reduceMotion: Bool?
        var quality: String?
        var fadeMs: Double?
        var playbackRate: Double?
        var resumeOnLaunch: Bool?
        var skipOnError: Bool?
        var doubleClick: String?
        var lyricsFontSize: Double?
        var lyricsAlign: String?
        var lyricsBackground: String?
        var lyricsSpinCover: Bool?
        var showLyricsPlayerBar: Bool?
        var lyricsOffset: Double?
        var desktopLyricsFontSize: Double?
        var desktopLyricsShowNext: Bool?
        var desktopLyricsStroke: Bool?
    }

    private var loading = false
    private let storageURL: URL

    // 允许检查脚本使用隔离的设置文件，避免修改用户的真实外观设置。
    init(storageURL: URL? = nil) {
        self.storageURL = storageURL ?? Self.fileURL
        // 恢复已保存的设置，缺少的新字段继续使用默认值。
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let s = try? JSONDecoder().decode(Snapshot.self, from: data) else { return }
        loading = true
        defer { loading = false }

        // 独立恢复纯色模式和主题选择，并校验持久化颜色。
        restoreAppearance(s)
        if let v = s.themeMode.flatMap(ThemeMode.init(rawValue:)) { themeMode = v }
        if let v = s.windowEffect.flatMap(WindowEffect.init(rawValue:)) { windowEffect = v }
        if let v = s.windowOpacity { windowOpacity = v }
        if let v = s.glassOpacity { glassOpacity = v }
        if let v = s.glassBlur { glassBlur = v }
        if let v = s.accentHex.flatMap(ColorMath.parseHex) { accentHex = v.hex }
        if let v = s.skin.flatMap(Skin.init(rawValue:)) { skin = v }
        if let v = s.reduceMotion { reduceMotion = v }
        if let v = s.quality { quality = v }
        if let v = s.fadeMs { fadeMs = v }
        if let v = s.playbackRate { playbackRate = v }
        if let v = s.resumeOnLaunch { resumeOnLaunch = v }
        if let v = s.skipOnError { skipOnError = v }
        if let v = s.doubleClick { doubleClick = v }
        if let v = s.lyricsFontSize { lyricsFontSize = v }
        if let v = s.lyricsAlign.flatMap(LyricAlign.init(rawValue:)) { lyricsAlign = v }
        if let v = s.lyricsBackground { lyricsBackground = v }
        if let v = s.lyricsSpinCover { lyricsSpinCover = v }
        if let v = s.showLyricsPlayerBar { showLyricsPlayerBar = v }
        if let v = s.lyricsOffset { lyricsOffset = v }
        if let v = s.desktopLyricsFontSize { desktopLyricsFontSize = v }
        if let v = s.desktopLyricsShowNext { desktopLyricsShowNext = v }
        if let v = s.desktopLyricsStroke { desktopLyricsStroke = v }
    }

    // 兼容旧设置文件：未记录模式时继续使用原来的内置主题。
    private func restoreAppearance(_ snapshot: Snapshot) {
        appearanceMode = snapshot.appearanceMode.flatMap(AppearanceMode.init(rawValue:)) ?? .theme
        if let color = snapshot.backgroundHex.flatMap(ColorMath.parseHex) { backgroundHex = color.hex }
    }

    private func save() {
        guard !loading else { return }
        let s = Snapshot(
            appearanceMode: appearanceMode.rawValue,
            backgroundHex: backgroundHex,
            themeMode: themeMode.rawValue,
            windowEffect: windowEffect.rawValue,
            windowOpacity: windowOpacity,
            glassOpacity: glassOpacity,
            glassBlur: glassBlur,
            accentHex: accentHex,
            skin: skin.rawValue,
            reduceMotion: reduceMotion,
            quality: quality,
            fadeMs: fadeMs,
            playbackRate: playbackRate,
            resumeOnLaunch: resumeOnLaunch,
            skipOnError: skipOnError,
            doubleClick: doubleClick,
            lyricsFontSize: lyricsFontSize,
            lyricsAlign: lyricsAlign.rawValue,
            lyricsBackground: lyricsBackground,
            lyricsSpinCover: lyricsSpinCover,
            showLyricsPlayerBar: showLyricsPlayerBar,
            lyricsOffset: lyricsOffset,
            desktopLyricsFontSize: desktopLyricsFontSize,
            desktopLyricsShowNext: desktopLyricsShowNext,
            desktopLyricsStroke: desktopLyricsStroke
        )
        if let data = try? JSONEncoder().encode(s) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }

    func reset() {
        let keepEffect = windowEffect
        themeMode = .light
        windowEffect = keepEffect
        windowOpacity = 100
        glassOpacity = 100
        glassBlur = 36
        accentHex = "#9b87bf"
        backgroundHex = AppearanceDefaults.backgroundHex
        appearanceMode = .theme
        skin = .standard
        reduceMotion = false
        quality = "128"
        fadeMs = 400
        playbackRate = 1
        resumeOnLaunch = true
        skipOnError = true
        doubleClick = "replace"
        lyricsFontSize = 18
        lyricsAlign = .left
        lyricsBackground = "cover"
        lyricsSpinCover = true
        showLyricsPlayerBar = true
        lyricsOffset = 0
        desktopLyricsFontSize = 30
        desktopLyricsShowNext = true
        desktopLyricsStroke = true
    }

    // 纯色按背景亮度匹配系统控件；主题使用自己的深浅色设计。
    var fixedDarkAppearance: Bool? {
        appearanceMode == .solid ? SolidPalette(backgroundHex: backgroundHex, accentHex: accentHex).isDark : skin.forcesDark
    }

    var appearanceTitle: String { appearanceMode == .solid ? "纯色自定义" : skin.title }

    // ── 派生值：透明度换算（与 ApplyAppearance.tsx 完全一致）──

    /// 面板 alpha 系数：0 → ×0.15，50 → ×1，100 → 不透明。
    static func scale(_ alpha: Double, _ opacity: Double) -> Double {
        let o = max(0, min(100, opacity))
        if o <= 50 { return alpha * (0.15 + (o / 50) * 0.85) }
        return alpha + (1 - alpha) * ((o - 50) / 50)
    }

    /// 窗口整体浓度；不透明窗口恒为 1。
    var effectiveWindowOpacity: Double {
        windowEffect == .none ? 1 : max(0, min(100, windowOpacity)) / 100
    }

    /// 面板透明度还要乘上窗口浓度（否则窗口很透时面板仍是实心）。
    /// 下限 0.35：拖到 0 时如果面板完全消失，深色主题的浅色文字会糊在桌面壁纸上。
    var panelFactor: Double {
        windowEffect == .none ? 1 : max(0.35, 0.12 + 0.88 * effectiveWindowOpacity)
    }

    /// 背景底色浓度，同样留一个下限，保证文字始终有落脚点。
    var backdropOpacity: Double {
        windowEffect == .none ? 1 : max(0.2, effectiveWindowOpacity)
    }

    func surfaceAlpha(_ base: Double) -> Double {
        Self.scale(base, glassOpacity) * panelFactor
    }
}
