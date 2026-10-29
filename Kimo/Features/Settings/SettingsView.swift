//
//  SettingsView.swift
//  Kimo
//
//  设置页：外观（含窗口/面板透明度与主题色）/ 播放 / 歌词页 / 账号 / 关于。
//  每一项都真正接到运行时，不摆空开关；版式沿用 cocomusic 的 Section + Row。
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme

    private var settings: AppSettings { model.settings }

    private let accentPresets: [(String, String)] = [
        ("薰衣草", "#9b87bf"),
        ("网易红", "#e5473e"),
        ("海盐蓝", "#4a7fd4"),
        ("薄荷绿", "#3faa86"),
    ]

    private let qualities: [(String, String)] = [
        ("标准", "128"),
        ("较高", "320"),
        ("无损", "flac"),
    ]

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                Text("设置")
                    .font(theme.titleFont(26))
                    .foregroundStyle(theme.textStrong)

                appearanceSection
                playbackSection
                lyricsSection
                desktopLyricsSection
                accountSection
                aboutSection
            }
            .pagePadding()
            .frame(maxWidth: 860, alignment: .leading)
            .offset(y: -model.debugScroll)
        }
    }

    // MARK: - 外观

    private var appearanceSection: some View {
        section(icon: "tshirt",
                title: "外观",
                description: "皮肤、深浅色、窗口透明与毛玻璃") {
            row("当前皮肤", "从顶栏的皮肤按钮更换，选中后整套配色一起换") {
                Text(settings.skin.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.accentStrong)
            }

            row("外观模式", settings.skin == .standard
                ? "跟随系统时，系统切换深浅色会自动同步"
                : "这套皮肤自带深浅色，切回雾紫玻璃后再生效") {
                segmented(ThemeMode.allCases.map { ($0.label, $0.rawValue) },
                          selected: settings.themeMode.rawValue) { value in
                    if let mode = ThemeMode(rawValue: value) { settings.themeMode = mode }
                }
                .disabled(settings.skin != .standard)
                .opacity(settings.skin == .standard ? 1 : 0.45)
            }

            groupLabel("窗口")

            row("窗口效果",
                effectHint) {
                segmented(WindowEffect.allCases.map { ($0.label, $0.rawValue) },
                          selected: settings.windowEffect.rawValue) { value in
                    if let effect = WindowEffect(rawValue: value) { settings.windowEffect = effect }
                }
            }

            row("窗口不透明度",
                settings.windowEffect == .none
                    ? "先选择毛玻璃或透明"
                    : "越低越能看到背后的桌面，文字和按钮始终保持清晰") {
                sliderRow(value: Binding(get: { settings.windowOpacity },
                                         set: { settings.windowOpacity = $0 }),
                          range: 0...100, step: 5,
                          enabled: settings.windowEffect != .none) { "\(Int($0))%" }
            }

            groupLabel("面板毛玻璃")

            row("面板不透明度", "内容区、播放栏和卡片的透明程度") {
                sliderRow(value: Binding(get: { settings.glassOpacity },
                                         set: { settings.glassOpacity = $0 }),
                          range: 0...100, step: 1) { "\(Int($0))%" }
            }

            row("面板模糊", "面板背后内容的模糊程度，设为 0 时为清透玻璃") {
                sliderRow(value: Binding(get: { settings.glassBlur },
                                         set: { settings.glassBlur = $0 }),
                          range: 0...60, step: 2) { "\(Int($0))px" }
            }

            groupLabel("颜色与显示")

            row("主题色", settings.skin == .standard
                ? "按钮、进度条、高亮等强调色，点最后一个色块可自定义"
                : "这套皮肤自带配色，切回雾紫玻璃后可以改") {
                accentPicker
                    .disabled(settings.skin != .standard)
                    .opacity(settings.skin == .standard ? 1 : 0.45)
            }

            row("减弱动态效果", "关闭页面过渡、封面旋转等动画") {
                Toggle("", isOn: Binding(get: { settings.reduceMotion },
                                         set: { settings.reduceMotion = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(theme.accentStrong)
            }
        }
    }

    private var effectHint: String {
        switch settings.windowEffect {
        case .vibrancy: return "桌面被系统模糊后透出，再蒙一层应用底色"
        case .transparent: return "不画自己的底色，桌面直接透出来"
        case .none: return "窗口自带底色，桌面完全看不到"
        }
    }

    private var accentPicker: some View {
        HStack(spacing: 8) {
            ForEach(accentPresets, id: \.0) { _, hex in
                Button {
                    settings.accentHex = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 22, height: 22)
                        .overlay {
                            Circle()
                                .strokeBorder(theme.textStrong,
                                              lineWidth: settings.accentHex.lowercased() == hex.lowercased() ? 2 : 0)
                                .padding(-3)
                        }
                }
                .buttonStyle(.plain)
                .help(hex)
            }

            AccentColorWell(hex: Binding(get: { settings.accentHex },
                                         set: { settings.accentHex = $0 }))
        }
    }

    // MARK: - 播放

    private var playbackSection: some View {
        section(icon: "play.circle",
                title: "播放",
                description: "音质、过渡与续播") {
            row("在线播放音质", "更高音质需要账号有对应权限，不满足时自动降级") {
                segmented(qualities.map { ("\($0.0) \($0.1 == "flac" ? "FLAC" : $0.1 + "k")", $0.1) },
                          selected: settings.quality) { settings.quality = $0 }
            }

            row("淡入淡出", "播放、暂停时音量平滑过渡") {
                sliderRow(value: Binding(get: { settings.fadeMs },
                                         set: { settings.fadeMs = $0 }),
                          range: 0...1500, step: 100) { $0 == 0 ? "关闭" : String(format: "%.1f 秒", $0 / 1000) }
            }

            row("播放速度", "调整速度时保持原有音调") {
                segmented([("0.75×", "0.75"), ("1×", "1.0"), ("1.25×", "1.25"), ("1.5×", "1.5"), ("2×", "2.0")],
                          selected: String(format: "%.2g", settings.playbackRate)) { value in
                    if let v = Double(value) { settings.playbackRate = v }
                }
            }

            row("双击歌曲", "在歌单、排行榜等列表中双击一首歌时") {
                segmented([("播放整个列表", "replace"), ("仅插入这首", "insert")],
                          selected: settings.doubleClick) { settings.doubleClick = $0 }
            }

            row("播放失败自动下一首", "当前歌曲拿不到播放地址时跳过") {
                Toggle("", isOn: Binding(get: { settings.skipOnError },
                                         set: { settings.skipOnError = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(theme.accentStrong)
            }

            row("启动时恢复上次播放", "记住上一首歌曲和播放位置") {
                Toggle("", isOn: Binding(get: { settings.resumeOnLaunch },
                                         set: { settings.resumeOnLaunch = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(theme.accentStrong)
            }
        }
    }

    // MARK: - 歌词页

    private var lyricsSection: some View {
        section(icon: "text.alignleft",
                title: "歌词页",
                description: "字号、对齐、背景与偏移") {
            row("字号", "歌词行的文字大小") {
                sliderRow(value: Binding(get: { settings.lyricsFontSize },
                                         set: { settings.lyricsFontSize = $0 }),
                          range: 14...26, step: 1) { "\(Int($0))px" }
            }

            row("对齐", "左对齐更接近逐句阅读") {
                segmented([("左对齐", "left"), ("居中", "center")],
                          selected: settings.lyricsAlign.rawValue) { value in
                    if let align = LyricAlign(rawValue: value) { settings.lyricsAlign = align }
                }
            }

            row("背景", "封面会重度模糊后作为背景") {
                segmented([("模糊封面", "cover"), ("纯色", "plain")],
                          selected: settings.lyricsBackground) { settings.lyricsBackground = $0 }
            }

            row("唱片旋转", "播放时彩胶缓慢旋转，唱臂保持不动") {
                Toggle("", isOn: Binding(get: { settings.lyricsSpinCover },
                                         set: { settings.lyricsSpinCover = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(theme.accentStrong)
            }

            row("显示播放底栏", "关闭后隐藏播放页底部控制栏，保留更多歌词空间") {
                Toggle("显示播放底栏", isOn: Binding(get: { settings.showLyricsPlayerBar },
                                                    set: { settings.showLyricsPlayerBar = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(theme.accentStrong)
            }

            row("歌词偏移", "正值让歌词提前出现，负值延后") {
                sliderRow(value: Binding(get: { settings.lyricsOffset },
                                         set: { settings.lyricsOffset = $0 }),
                          range: -2000...2000, step: 100) {
                    $0 == 0 ? "0" : String(format: "%+.1f 秒", $0 / 1000)
                }
            }
        }
    }

    // MARK: - 桌面歌词

    private var desktopLyricsSection: some View {
        section(icon: "textformat",
                title: "桌面歌词",
                description: "浮在桌面上的置顶歌词条，可拖动") {
            row("显示桌面歌词", "等价于播放栏右侧的「词」按钮") {
                Toggle("", isOn: Binding(
                    get: { DesktopLyricsController.shared.isVisible },
                    set: { $0 ? DesktopLyricsController.shared.show() : DesktopLyricsController.shared.hide() }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .tint(theme.accentStrong)
            }

            row("字号", "桌面歌词条的文字大小") {
                sliderRow(value: Binding(get: { settings.desktopLyricsFontSize },
                                         set: { settings.desktopLyricsFontSize = $0 }),
                          range: 20...48, step: 1) { "\(Int($0))px" }
            }

            row("显示下一句", "在下方灰字提示下一句歌词") {
                Toggle("", isOn: Binding(get: { settings.desktopLyricsShowNext },
                                         set: { settings.desktopLyricsShowNext = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(theme.accentStrong)
            }

            row("文字描边", "浅色壁纸上更清楚") {
                Toggle("", isOn: Binding(get: { settings.desktopLyricsStroke },
                                         set: { settings.desktopLyricsStroke = $0 }))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(theme.accentStrong)
            }

            row("位置", "直接拖动桌面歌词条，位置会自动记住") {
                Button {
                    DesktopLyricsController.shared.resetPosition()
                } label: {
                    Text("重置")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accentStrong)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(theme.accentSoft))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 账号

    private var accountSection: some View {
        section(icon: "person.circle",
                title: "账号",
                description: auth.isLoggedIn ? "已连接酷狗账号" : "登录后才能播放完整歌曲") {
            row("酷狗账号", auth.isLoggedIn ? auth.nickname : "未登录") {
                Button {
                    model.showLogin = true
                } label: {
                    Text(auth.isLoggedIn ? "管理" : "登录")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accentStrong)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(theme.accentSoft))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 关于

    private var aboutSection: some View {
        section(icon: "info.circle",
                title: "关于",
                description: "Kimo") {
            infoRow("版本", "0.1.0 (1)")
            divider
            infoRow("界面", "CoCo Music · GPL-3.0")
            divider
            infoRow("核心", "MoeKoe Music / kugoumusicapi · GPL-2.0")
            divider
            infoRow("核心服务", CoreService.shared.isReady ? "运行中 · 127.0.0.1:6520" : "未就绪")
            divider
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("恢复默认设置")
                        .font(.system(size: 14))
                        .foregroundStyle(theme.textStrong)
                    Text("外观、播放、歌词设置回到初始状态，不影响登录")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMuted)
                }
                Spacer()
                Button {
                    settings.reset()
                } label: {
                    Text("恢复")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.like)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(Capsule().fill(theme.chip))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 56)
        }
    }

    // MARK: - 组件

    private func section<Content: View>(icon: String,
                                        title: String,
                                        description: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .light))
                    .foregroundStyle(theme.accentStrong)
                Text(title)
                    .font(theme.titleFont(16))
                    .foregroundStyle(theme.textStrong)
                Text(description)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
                Spacer(minLength: 0)
            }
            .padding(.bottom, 10)

            VStack(spacing: 0) { content() }
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
                .background {
                    RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous)
                        .fill(theme.card)
                    RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous)
                        .strokeBorder(theme.glassEdge, lineWidth: 1)
                }
        }
    }

    private func groupLabel(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
            Spacer()
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
    }

    private func row<Control: View>(_ title: String,
                                    _ detail: String,
                                    @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textStrong)
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textMuted)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 56)
        .padding(.vertical, 2)
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
                .foregroundStyle(theme.textStrong)
            Spacer()
            Text(value)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(height: 46)
    }

    private var divider: some View {
        Rectangle().fill(theme.divider).frame(height: 1)
    }

    private func segmented(_ options: [(String, String)],
                           selected: String,
                           onSelect: @escaping (String) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { label, value in
                let active = value == selected
                Button {
                    onSelect(value)
                } label: {
                    Text(label)
                        .font(.system(size: 12))
                        .foregroundStyle(active ? theme.textStrong : theme.textSecondary)
                        .padding(.horizontal, 11)
                        .frame(height: 28)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(active ? theme.hoverStrong : Color.clear)
                                .shadow(color: .black.opacity(active ? 0.06 : 0), radius: 2, y: 1)
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.chip)
        }
    }

    private func sliderRow(value: Binding<Double>,
                           range: ClosedRange<Double>,
                           step: Double,
                           enabled: Bool = true,
                           format: @escaping (Double) -> String) -> some View {
        HStack(spacing: 10) {
            Slider(value: value, in: range, step: step)
                .controlSize(.small)
                .tint(theme.accentStrong)
                .frame(width: 150)
            Text(format(value.wrappedValue))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.textSecondary)
                .frame(width: 64, alignment: .trailing)
        }
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }
}

// MARK: - 自定义颜色

/// 圆形色块，点击打开系统取色器（比原生 ColorPicker 的胶囊外形更贴合这套 UI）。
struct AccentColorWell: View {
    @Binding var hex: String
    @State private var coordinator = ColorWellCoordinator()

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 22, height: 22)
            Circle()
                .strokeBorder(Color.primary.opacity(0.18), lineWidth: 1)
                .frame(width: 22, height: 22)
            Image(systemName: "plus")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .contentShape(Circle())
        .onTapGesture {
            coordinator.onChange = { color in
                if let value = color.hexString { hex = value }
            }
            let panel = NSColorPanel.shared
            panel.showsAlpha = false
            panel.color = NSColor(Color(hex: hex))
            panel.setTarget(coordinator)
            panel.setAction(#selector(ColorWellCoordinator.colorChanged(_:)))
            panel.makeKeyAndOrderFront(nil)
        }
        .help("自定义主题色")
    }
}

final class ColorWellCoordinator: NSObject {
    var onChange: ((NSColor) -> Void)?

    @objc func colorChanged(_ sender: NSColorPanel) {
        onChange?(sender.color)
    }
}

// MARK: - Color → hex

extension NSColor {
    var hexString: String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        return String(format: "#%02x%02x%02x",
                      Int(round(rgb.redComponent * 255)),
                      Int(round(rgb.greenComponent * 255)),
                      Int(round(rgb.blueComponent * 255)))
    }
}
