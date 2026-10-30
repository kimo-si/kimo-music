import SwiftUI

enum ControlMaterial { case flat, glass, soft, hardware, paper, arcade, chrome }
enum ProgressAppearance { case continuous, ruled, segmented }
enum ThemeSurfaceRole { case button, field, selection }

// 控件的形状、材质和反馈集中定义，页面只描述按钮的语义。
struct ThemeControlTokens {
    let material: ControlMaterial
    let cornerRadius: CGFloat
    let fieldRadius: CGFloat
    let borderWidth: CGFloat
    let depth: CGFloat
    let pressDistance: CGFloat
    let progress: ProgressAppearance
    let iconWeight: Font.Weight
    let fontDesign: Font.Design
    var usesKnob: Bool { material == .hardware || material == .chrome }

    // 每个主题只在这里声明控件设计，避免页面重复判断主题名称。
    static func resolve(flavor: SkinFlavor) -> Self {
        switch flavor {
        case .solid: return .init(.flat, radius: 10, field: 12)
        case .standard: return .init(.glass, radius: 10, field: 20)
        case .night: return .init(.flat, radius: 6, field: 8, progress: .ruled)
        case .cream: return .init(.soft, radius: 14, field: 18, depth: 2, font: .rounded)
        case .hifi: return .init(.hardware, radius: 5, field: 5, depth: 2, progress: .ruled)
        case .liquid: return .init(.chrome, radius: 16, field: 20, depth: 1)
        case .record: return .init(.paper, radius: 3, field: 4, depth: 1, progress: .ruled, font: .serif)
        case .mint: return .init(.arcade, radius: 10, field: 12, border: 1.5, depth: 3,
                                 progress: .segmented, weight: .semibold, font: .rounded)
        case .chiikawa: return .init(.soft, radius: 14, field: 16, depth: 2, font: .rounded)
        }
    }

    // 为常用的控件参数提供统一默认值。
    private init(_ material: ControlMaterial, radius: CGFloat, field: CGFloat,
                 border: CGFloat = 1, depth: CGFloat = 0,
                 progress: ProgressAppearance = .continuous,
                 weight: Font.Weight = .regular, font: Font.Design = .default) {
        self.material = material
        cornerRadius = radius
        fieldRadius = field
        borderWidth = border
        self.depth = depth
        pressDistance = min(depth, 2)
        self.progress = progress
        iconWeight = weight
        fontDesign = font
    }
}

// 输入框、选中态和按钮共用主题表面，同时保持各自的交互语义。
struct ThemedSurface: ViewModifier {
    @Environment(\.theme) private var theme
    var role: ThemeSurfaceRole = .button
    var active = false
    var hovering = false
    var primary = false
    var pressed = false
    var radius: CGFloat?

    private var rounding: CGFloat { radius ?? (role == .field ? theme.controls.fieldRadius : theme.controls.cornerRadius) }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: rounding) }
    private var depth: CGFloat { role == .selection ? 0 : max(0, theme.controls.depth - (pressed ? 2 : 0)) }

    // 将背景层和描边限制在控件内部，不改变点击范围或页面排版。
    func body(content: Content) -> some View {
        content.background {
            if depth > 0 {
                shape.fill(theme.textStrong.opacity(theme.isDark ? 0.30 : 0.20)).offset(y: depth)
            }
            shape.fill(fill)
            shape.strokeBorder(edge, lineWidth: theme.controls.borderWidth)
            if role != .selection && (theme.controls.material == .hardware || theme.controls.material == .chrome) {
                shape.inset(by: 1).strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            }
        }
    }

    private var edge: Color {
        if role == .selection && !active && !hovering { return .clear }
        if active || primary { return theme.accentStrong.opacity(0.65) }
        return theme.controls.material == .arcade || theme.controls.material == .paper
            ? theme.textStrong.opacity(0.22) : theme.glassEdge
    }

    private var base: Color {
        if role == .selection { return active ? theme.navActive : (hovering ? theme.hover : .clear) }
        if role == .field { return active ? theme.fieldFocus : theme.field }
        if primary { return theme.accentStrong }
        if active { return theme.accentSoft }
        if hovering || pressed { return theme.hoverStrong }
        return theme.chip
    }

    private var fill: AnyShapeStyle {
        guard role != .selection else { return AnyShapeStyle(base) }
        switch theme.controls.material {
        case .hardware, .chrome:
            return AnyShapeStyle(LinearGradient(colors: [base, base.opacity(0.72), base],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
        case .soft:
            return AnyShapeStyle(LinearGradient(colors: [base, base.opacity(0.85)], startPoint: .top, endPoint: .bottom))
        case .flat, .glass, .paper, .arcade:
            return AnyShapeStyle(base)
        }
    }
}

// 所有主题按钮统一处理按压、禁用和系统减弱动态效果。
struct ThemedButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var primary = false
    var active = false
    var radius: CGFloat?

    // 按压仅改变控件的视觉位置，按钮本身的布局和操作语义保持一致。
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(ThemedSurface(active: active, primary: primary,
                                   pressed: enabled && configuration.isPressed, radius: radius))
            .offset(y: enabled && configuration.isPressed ? theme.controls.pressDistance : 0)
            .opacity(enabled ? 1 : 0.45)
            .animation(theme.allowsMotion && !reduceMotion ? .easeOut(duration: 0.12) : nil,
                       value: configuration.isPressed)
    }
}

extension Theme {
    // 为实心播放键选择与实际填充色对比清楚的前景色。
    var primaryButtonInk: Color {
        ColorMath.foreground(on: [RGB(r: Double(accentStrongRGB.0),
                                    g: Double(accentStrongRGB.1), b: Double(accentStrongRGB.2))]).color
    }

    // 控件文字与主题字体统一，歌曲正文仍保持易读的系统字体。
    func controlFont(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: controls.fontDesign)
    }
}
