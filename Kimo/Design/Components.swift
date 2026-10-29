//
//  Components.swift
//  Kimo
//
//  通用视觉件：毛玻璃面板、图标按钮、封面、区块标题、标签页。
//

import SwiftUI

// MARK: - Backdrop

/// 窗口背后的色场。颜色和纹理跟着当前皮肤走。
struct Backdrop: View {
    let theme: Theme

    var body: some View {
        SkinBackdrop(theme: theme)
    }
}

// MARK: - Glass

struct GlassPanel: ViewModifier {
    @Environment(\.theme) private var theme
    var tint: Color?
    var radius: CGFloat = 0
    var corners: RectCorner = .all

    func body(content: Content) -> some View {
        content
            .background {
                let shape = UnevenRoundedRectangle(
                    topLeadingRadius: corners.contains(.topLeading) ? radius : 0,
                    bottomLeadingRadius: corners.contains(.bottomLeading) ? radius : 0,
                    bottomTrailingRadius: corners.contains(.bottomTrailing) ? radius : 0,
                    topTrailingRadius: corners.contains(.topTrailing) ? radius : 0
                )
                ZStack {
                    // 面板模糊设为 0 时用清透填充，不叠毛玻璃层。
                    if theme.glassBlur > 0 {
                        shape.fill(.ultraThinMaterial)
                    }
                    shape.fill(tint ?? theme.sheet)
                }
            }
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeading = RectCorner(rawValue: 1 << 0)
    static let bottomLeading = RectCorner(rawValue: 1 << 1)
    static let bottomTrailing = RectCorner(rawValue: 1 << 2)
    static let topTrailing = RectCorner(rawValue: 1 << 3)
    static let all: RectCorner = [.topLeading, .bottomLeading, .bottomTrailing, .topTrailing]
    static let topLeft: RectCorner = [.topLeading]
}

extension View {
    func glass(tint: Color? = nil, radius: CGFloat = 0, corners: RectCorner = .all) -> some View {
        modifier(GlassPanel(tint: tint, radius: radius, corners: corners))
    }
}

// MARK: - Icon button

struct IconButton<Content: View>: View {
    @Environment(\.theme) private var theme
    var size: CGFloat = 34
    var radius: CGFloat = 10
    var active = false
    var muted = true
    var disabled = false
    var tint: Color? = nil
    var action: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            content()
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(tint ?? (active ? theme.accentStrong : (muted ? theme.textSecondary : theme.textStrong)))
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(hovering && !disabled ? theme.hover : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.55 : 1)
        .hoverLift(active: hovering, pressed: false, enabled: !disabled)
        .onHover { hovering = $0 && !disabled }
    }
}

/// 悬停时轻轻浮起，按下时略微收回。减弱动态效果时只换颜色。
struct HoverLiftModifier: ViewModifier {
    @Environment(\.theme) private var theme
    var active: Bool
    var pressed: Bool = false
    var enabled: Bool = true
    var amount: CGFloat = 1.1

    func body(content: Content) -> some View {
        let scale: CGFloat = {
            guard enabled, theme.allowsMotion else { return 1 }
            if pressed { return 0.9 }
            if active { return amount }
            return 1
        }()
        content
            .scaleEffect(scale)
            .animation(.spring(response: 0.32, dampingFraction: 0.62), value: active)
            .animation(.spring(response: 0.22, dampingFraction: 0.7), value: pressed)
    }
}

extension View {
    func hoverLift(active: Bool, pressed: Bool = false, enabled: Bool = true, amount: CGFloat = 1.1) -> some View {
        modifier(HoverLiftModifier(active: active, pressed: pressed, enabled: enabled, amount: amount))
    }
}

// MARK: - Cover

struct CoverImage: View {
    @Environment(\.theme) private var theme
    let url: URL?
    var radius: CGFloat = Metrics.radiusCover
    var seed: String = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                placeholder
                if let url {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
                        if let image = phase.image {
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        }
                    }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        }
    }

    /// 没有封面时的占位：围绕主题色的低饱和渐变，避免每条列表都出现彩虹块。
    private var placeholder: some View {
        let h = abs(seed.hashValue)
        let base = ColorMath.rgbToHsl(RGB(r: Double(theme.accentRGB.0),
                                          g: Double(theme.accentRGB.1),
                                          b: Double(theme.accentRGB.2))).h
        let drift = (Double(h % 40) / 40.0 - 0.5) * 26
        let hue1 = ((base + drift) / 360).truncatingRemainder(dividingBy: 1)
        let hue2 = ((base + drift + 18) / 360).truncatingRemainder(dividingBy: 1)
        return LinearGradient(
            colors: [
                Color(hue: hue1, saturation: theme.isDark ? 0.26 : 0.16, brightness: theme.isDark ? 0.38 : 0.96),
                Color(hue: hue2, saturation: theme.isDark ? 0.32 : 0.22, brightness: theme.isDark ? 0.28 : 0.86),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

// MARK: - Section header

struct SectionHeader: View {
    @Environment(\.theme) private var theme
    let title: String
    var actionLabel: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.textStrong)
            Spacer(minLength: 16)
            if let actionLabel {
                Button {
                    action?()
                } label: {
                    HStack(spacing: 2) {
                        Text(actionLabel)
                            .font(.system(size: 13))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(theme.textSecondary)
                    .padding(.vertical, 4)
                    .padding(.leading, 8)
                    .padding(.trailing, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ActionLinkStyle())
            }
        }
    }
}

struct ActionLinkStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.accentSoft)
                    .opacity(configuration.isPressed ? 1 : 0)
            )
            .onHover { _ in }
    }
}

// MARK: - Tabs

struct TabBar: View {
    @Environment(\.theme) private var theme
    let items: [String]
    @Binding var value: String
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 28) {
            ForEach(items, id: \.self) { item in
                let active = item == value
                Button {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) { value = item }
                } label: {
                    Text(item)
                        .font(.system(size: 15))
                        .foregroundStyle(active ? theme.accentStrong : theme.textSecondary)
                        .padding(.top, 2)
                        .padding(.bottom, 9)
                        .overlay(alignment: .bottom) {
                            if active {
                                Capsule()
                                    .fill(theme.accent)
                                    .frame(height: 2.5)
                                    .padding(.horizontal, 8)
                                    .matchedGeometryEffect(id: "tab-indicator", in: ns)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Skeleton

struct SkeletonBlock: View {
    @Environment(\.theme) private var theme
    var radius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(theme.chip)
            .opacity(0.75)
    }
}

// MARK: - Hover tracking

struct HoverState: ViewModifier {
    @Binding var hovering: Bool
    func body(content: Content) -> some View {
        content.onHover { hovering = $0 }
    }
}

extension View {
    func trackHover(_ binding: Binding<Bool>) -> some View {
        modifier(HoverState(hovering: binding))
    }
}
