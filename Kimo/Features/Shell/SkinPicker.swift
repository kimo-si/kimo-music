//
//  SkinPicker.swift
//  Kimo
//
//  顶栏皮肤按钮弹出的选择面板。点一张卡片立刻换上，并记住。
//

import SwiftUI

struct SkinPicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("皮肤")
                    .font(theme.titleFont(18))
                    .foregroundStyle(theme.textStrong)
                Text("点一张卡片，整套界面马上换上")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
            }

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(Skin.allCases) { skin in
                    SkinCard(skin: skin, selected: model.settings.skin == skin) {
                        withAnimation(.easeInOut(duration: 0.35)) {
                            model.settings.skin = skin
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 520)
        .background(theme.solid)
    }
}

private struct SkinCard: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let skin: Skin
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                preview
                    .frame(height: 78)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                Text(skin.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textStrong)
                    .lineLimit(1)
                Text(skin.subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textMuted)
                    .lineLimit(1)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? theme.accentSoft : (hovering ? theme.hover : theme.card))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? theme.accentStrong : theme.glassEdge,
                                  lineWidth: selected ? 1.5 : 1)
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var preview: some View {
        let sample = sampleColors
        return ZStack(alignment: .bottom) {
            sample.shell
            HStack(spacing: 4) {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(sample.panel.opacity(0.92))
                    .frame(width: 22)
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(sample.panel)
                    HStack(spacing: 4) {
                        Circle().fill(sample.disc).frame(width: 12, height: 12)
                        Capsule().fill(sample.accent).frame(height: 3)
                    }
                    .frame(height: 14)
                }
            }
            .padding(6)

            if skin == .chiikawa {
                ChiikawaArtwork()
                    .frame(width: 60, height: 40)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(5)
            }
        }
    }

    private var sampleColors: (shell: Color, panel: Color, accent: Color, disc: Color) {
        if let paint = skin.paint {
            return (
                Color(rgb: paint.chrome.shellRGB),
                Color(rgb: paint.surfaceRGB),
                paint.accent,
                paint.chrome.playDisc
            )
        }
        let dark = model.resolvedIsDark
        return (
            dark ? Color(hex: "15131F") : Color(hex: "DFE1F5"),
            dark ? Color(hex: "221F32") : Color(hex: "F6F6FF"),
            Color(hex: model.settings.accentHex),
            dark ? Color(hex: "3A3458") : Color(hex: "E6DFF5")
        )
    }
}
