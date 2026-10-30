import SwiftUI

// 外观入口：纯色编辑和内置主题共用即时预览，两种模式分别保留自己的设置。
struct SkinPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            AppearanceModePicker()
            ScrollView {
                if model.settings.appearanceMode == .solid {
                    SolidAppearanceEditor()
                } else {
                    themeGrid
                }
            }
            .frame(height: 440)
        }
        .padding(20)
        .frame(width: 580)
        .background(theme.solid)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("外观").font(theme.titleFont(22)).foregroundStyle(theme.textStrong)
            Text("自由配色，或换一整套设计。更改即时生效。")
                .font(.system(size: 12)).foregroundStyle(theme.textSecondary)
        }
    }

    private var themeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 14) {
            ForEach(Skin.allCases) { skin in
                SkinCard(skin: skin)
            }
        }
        .padding(.bottom, 6)
    }
}

// 顶栏和设置页复用同一外观模式选择，选项不会重置另一模式的配置。
struct AppearanceModePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppearanceMode.allCases) { mode in
                Button {
                    model.settings.appearanceMode = mode
                } label: {
                    Label(mode.title, systemImage: mode == .solid ? "slider.horizontal.3" : "square.grid.2x2")
                        .font(theme.controlFont(13))
                        .foregroundStyle(model.settings.appearanceMode == mode ? theme.accentStrong : theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                }
                .buttonStyle(ThemedButtonStyle(active: model.settings.appearanceMode == mode))
                .accessibilityAddTraits(model.settings.appearanceMode == mode ? .isSelected : [])
            }
        }
    }
}

// 纯色模式同时编辑背景和强调色，预览与真正界面使用同一个 Theme。
struct SolidAppearanceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var settings = model.settings
        VStack(alignment: .leading, spacing: 20) {
            ThemeSampleView(title: "你的配色")
                .frame(height: 116)
                .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard))
            HStack(alignment: .top, spacing: 24) {
                RGBColorEditor(title: "背景色", hex: $settings.backgroundHex)
                RGBColorEditor(title: "强调色", hex: $settings.accentHex)
            }
            Text("背景保持纯色；文字、面板和高亮会自动匹配对比度。透明度仍可在设置中调整。")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }
}

private struct SkinCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let skin: Skin

    private var selected: Bool { model.settings.skin == skin }
    private var sample: Theme {
        Theme.make(skin: skin, settings: model.settings, isDark: model.resolvedIsDark)
    }

    var body: some View {
        Button(action: selectTheme) {
            VStack(alignment: .leading, spacing: 8) {
                ThemeSampleView(title: skin.title)
                    .environment(\.theme, sample)
                    .frame(height: 116)
                    .clipShape(RoundedRectangle(cornerRadius: sample.radiusCard))
                caption
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(selected ? theme.accentStrong : theme.glassEdge, lineWidth: selected ? 2 : 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(skin.title)
        .accessibilityValue(selected ? "已选择" : "未选择")
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(skin.title).font(theme.controlFont(13)).lineLimit(1)
                Spacer(minLength: 0)
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.accentStrong) }
            }
            .foregroundStyle(theme.textStrong)
            Text(skin.subtitle).font(.system(size: 11)).foregroundStyle(theme.textSecondary).lineLimit(1)
        }
    }

    // 只更新内置主题选择，保留纯色颜色和用户的透明度偏好。
    private func selectTheme() {
        withAnimation(theme.allowsMotion && !reduceMotion ? .easeInOut(duration: 0.20) : nil) {
            model.settings.skin = skin
        }
    }
}

// 预览显示真实主题的输入框、按钮、选中行和进度条，避免仅用色块代表整套主题。
struct ThemeSampleView: View {
    @Environment(\.theme) private var theme
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            topLine
            sampleTrack
            transport
        }
        .padding(10)
        .background { SkinBackdrop(theme: theme).clipped() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var topLine: some View {
        HStack {
            Text("KIMO").font(theme.titleFont(11, weight: .semibold)).tracking(2)
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Text("搜索音乐")
            }
            .font(theme.controlFont(9)).padding(.horizontal, 7).padding(.vertical, 4)
            .modifier(ThemedSurface(role: .field))
        }
        .foregroundStyle(theme.textSecondary)
    }

    private var sampleTrack: some View {
        HStack(spacing: 8) {
            Image(systemName: "opticaldisc")
                .font(.system(size: 22)).foregroundStyle(theme.accentStrong)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(theme.controlFont(11)).foregroundStyle(theme.textStrong)
                Text("把喜欢，留在此刻").font(.system(size: 9)).foregroundStyle(theme.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(5)
        .modifier(ThemedSurface(role: .selection, active: true, radius: theme.radiusRow))
    }

    private var transport: some View {
        HStack(spacing: 7) {
            Image(systemName: "backward.end.fill").font(.system(size: 8))
                .frame(width: 20, height: 20).modifier(ThemedSurface())
            Image(systemName: "play.fill").font(.system(size: 9))
                .foregroundStyle(theme.primaryButtonInk)
                .frame(width: 22, height: 22).modifier(ThemedSurface(primary: true))
            ThemedProgress(ratio: 0.54, dragging: false, playing: false, compact: true)
                .frame(height: 12)
            Text("01:24").font(.system(size: 8).monospacedDigit())
        }
        .foregroundStyle(theme.textSecondary)
    }
}
