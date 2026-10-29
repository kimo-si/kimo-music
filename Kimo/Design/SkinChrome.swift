//
//  SkinChrome.swift
//  Kimo
//
//  播放键、进度条、音量旋钮。只有关键控件跟着皮肤变材质，列表保持能读。
//

import SwiftUI

struct ThemedPlayButton: View {
    @Environment(\.theme) private var theme
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            PlayPauseGlyph(playing: playing, size: 15, color: theme.accentStrong)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "暂停" : "播放")
        .padding(.horizontal, 4)
        .hoverLift(active: hovering, amount: 1.12)
        .onHover { hovering = $0 }
        .shadow(color: theme.accent.opacity(hovering ? 0.35 : 0), radius: hovering ? 10 : 0)
    }

}

// 在不同播放控制栏中统一播放和暂停图标的切换效果。
struct PlayPauseGlyph: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let playing: Bool
    let size: CGFloat
    let color: Color

    var body: some View {
        Image(systemName: playing ? "pause.fill" : "play.fill")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
            .offset(x: playing ? 0 : 1)
            .contentTransition(.symbolEffect(.replace))
            .animation(theme.allowsMotion && !reduceMotion ? .easeInOut(duration: 0.25) : nil, value: playing)
    }
}

struct ThemedProgress: View {
    @Environment(\.theme) private var theme
    let ratio: CGFloat
    let dragging: Bool
    let playing: Bool
    @State private var hovering = false

    private var lifted: Bool { hovering || dragging }
    private var thickness: CGFloat { lifted ? 6 : 4 }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width * ratio)
            let knob: CGFloat = dragging ? 14 : 11
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.playerRail)
                    .frame(height: thickness)

                progressFill(width: width)
                    .frame(width: max(width, thickness), height: thickness)
                    .shadow(color: theme.accent.opacity(playing ? 0.7 : 0.35), radius: playing ? 7 : 3)

                Circle()
                    .fill(theme.accentStrong)
                    .frame(width: knob, height: knob)
                    .overlay(Circle().strokeBorder(Color.white.opacity(theme.isDark ? 0.9 : 1), lineWidth: 2))
                    .shadow(color: theme.accent.opacity(0.55), radius: 5, y: 1)
                    .offset(x: max(0, width - knob / 2))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.16), value: lifted)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
    }

    private func progressFill(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule()
                .fill(LinearGradient(
                    colors: [theme.accent.opacity(0.82), theme.accentStrong],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
            if playing, theme.allowsMotion, !dragging, width > 12 {
                ProgressSheen()
                    .frame(width: width)
                    .mask(Capsule())
            }
        }
    }
}

// 在进度条上方显示鼠标位置对应的播放时间。
struct ProgressTimeHover: ViewModifier {
    @Environment(\.theme) private var theme
    @State private var hoverX: CGFloat?
    let duration: TimeInterval

    private static let labelWidth: CGFloat = 64
    private static let labelHeight: CGFloat = 24
    private static let labelGap: CGFloat = 4

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                // 跟踪鼠标在进度条内的位置，离开时隐藏提示。
                updateHover(phase)
            }
            .overlay(alignment: .topLeading) {
                GeometryReader { geometry in
                    if let hoverX, let time = timeText(at: hoverX, width: geometry.size.width) {
                        timeLabel(time, at: hoverX, width: geometry.size.width)
                    }
                }
                .allowsHitTesting(false)
            }
    }

    // 更新悬停位置，避免无有效时长时显示时间。
    private func updateHover(_ phase: HoverPhase) {
        switch phase {
        case .active(let location):
            hoverX = duration.isFinite && duration > 0 ? location.x : nil
        case .ended:
            hoverX = nil
        }
    }

    // 将悬停位置换算为有界的播放时间。
    private func timeText(at x: CGFloat, width: CGFloat) -> String? {
        guard duration.isFinite, duration > 0, duration < Double(Int.max), width > 0 else { return nil }
        let ratio = min(1, max(0, x / width))
        let seconds = Int(duration * Double(ratio))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    // 限制提示的位置，防止靠近进度条两端时溢出窗口。
    private func timeLabel(_ time: String, at x: CGFloat, width: CGFloat) -> some View {
        let labelWidth = min(Self.labelWidth, width)
        let center = min(max(x, labelWidth / 2), width - labelWidth / 2)
        return Text(time)
            .font(.system(size: 11, weight: .medium).monospacedDigit())
            .foregroundStyle(theme.textStrong)
            .frame(width: labelWidth, height: Self.labelHeight)
            .background(RoundedRectangle(cornerRadius: 7).fill(theme.solid))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.glassEdge, lineWidth: 1))
            .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
            .position(x: center, y: -Self.labelHeight / 2 - Self.labelGap)
    }
}

/// 播放时沿已走过的进度滑过一道浅光。
private struct ProgressSheen: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let period = 2.2
            let phase = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
            GeometryReader { geo in
                LinearGradient(
                    colors: [.clear, Color.white.opacity(0.15), Color.white.opacity(0.8), .clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 56)
                .offset(x: -56 + (geo.size.width + 56) * phase)
            }
        }
        .allowsHitTesting(false)
    }
}

struct ThemedKnob: View {
    @Environment(\.theme) private var theme
    @Binding var volume: Double
    @State private var start: Double?

    var body: some View {
        let angle = Angle.degrees(-140 + 280 * volume)
        ZStack {
            Circle().stroke(ring, lineWidth: theme.flavor == .liquid ? 2.5 : 2)
            Circle().fill(face).padding(4)
            Capsule()
                .fill(needle)
                .frame(width: 2, height: 8)
                .offset(y: -7)
                .rotationEffect(angle)
        }
        .frame(width: 30, height: 30)
        .contentShape(Circle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if start == nil { start = volume }
                    let next = (start ?? volume) + Double(-value.translation.height / 90)
                    volume = min(1, max(0, next))
                }
                .onEnded { value in
                    if abs(value.translation.height) < 3, abs(value.translation.width) < 3 {
                        volume = volume > 0 ? 0 : 0.8
                    }
                    start = nil
                }
        )
        .help("音量")
    }

    private var ring: Color {
        theme.flavor == .liquid ? Color(hex: "C9C6D0") : Color(hex: "C6A36A")
    }

    private var face: some ShapeStyle {
        if theme.flavor == .liquid {
            return AnyShapeStyle(AngularGradient(
                colors: [Color.white, Color(hex: "B7B4BE"), Color(hex: "F4F4F6"), Color(hex: "8E8A96")],
                center: .center
            ))
        }
        return AnyShapeStyle(Color(hex: "1A1612"))
    }

    private var needle: Color {
        theme.flavor == .liquid ? theme.accent : Color(hex: "E8A317")
    }
}

struct MiniWave: View {
    let color: Color
    let playing: Bool
    let motion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.12, paused: !playing || !motion)) { context in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<4, id: \.self) { index in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let level = playing && motion ? abs(sin(t * 6 + Double(index) * 0.9)) : 0.25
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color)
                        .frame(width: 2, height: 3 + level * 9)
                }
            }
            .frame(height: 12, alignment: .bottom)
        }
    }
}

struct MiniNotes: View {
    let color: Color
    let playing: Bool
    let motion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.16, paused: !playing || !motion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 1) {
                note("music.note", bounce: sin(t * 5))
                note("music.note", bounce: sin(t * 5 + 1.2))
            }
        }
    }

    private func note(_ name: String, bounce: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .offset(y: playing && motion ? -bounce * 2.5 : 0)
    }
}

struct VUMeter: View {
    let playing: Bool
    let motion: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !playing || !motion)) { context in
            HStack(alignment: .bottom, spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    let t = context.date.timeIntervalSinceReferenceDate
                    let level = playing && motion ? abs(sin(t * 7 + Double(index))) : 0.2
                    RoundedRectangle(cornerRadius: 1)
                        .fill(index >= 4 ? Color(hex: "E07A4A") : Color(hex: "E8A317"))
                        .frame(width: 3, height: 3 + level * 11)
                }
            }
            .frame(width: 24, height: 16, alignment: .bottom)
        }
        .help("电平")
    }
}
