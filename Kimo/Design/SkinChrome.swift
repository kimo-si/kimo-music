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
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            PlayPauseGlyph(playing: playing, size: size * 0.38, color: theme.primaryButtonInk)
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(ThemedButtonStyle(primary: true))
        .accessibilityLabel(playing ? "暂停" : "播放")
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

// 所有播放页面共用的主题进度条，紧凑模式只改变尺寸。
struct ThemedProgress: View {
    @Environment(\.theme) private var theme
    let ratio: CGFloat
    let dragging: Bool
    let playing: Bool
    var compact = false
    var showsThumb = true
    @State private var hovering = false

    private var position: CGFloat { ratio.isFinite ? min(1, max(0, ratio)) : 0 }
    private var thickness: CGFloat { compact ? 3 : (dragging || hovering ? 6 : 4) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                rail(width: geometry.size.width)
                if showsThumb { thumb(width: geometry.size.width) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .accessibilityHidden(true)
    }

    // 根据主题绘制连续轨道、刻度轨道或游戏机分段轨道。
    @ViewBuilder
    private func rail(width: CGFloat) -> some View {
        if theme.controls.progress == .segmented {
            SegmentedProgressRail(ratio: position, color: theme.accentStrong, track: theme.playerRail)
                .frame(height: compact ? 4 : 6)
        } else {
            ZStack(alignment: .leading) {
                Capsule().fill(theme.playerRail)
                Capsule().fill(theme.accentStrong).frame(width: width * position)
                if theme.controls.progress == .ruled {
                    ProgressRuler(color: theme.textStrong.opacity(0.30))
                }
            }
            .frame(height: thickness)
        }
    }

    // 拖动标记保持在轨道范围内，并随主题切换圆点、刻度指针或方块。
    private func thumb(width: CGFloat) -> some View {
        let ruler = theme.controls.progress == .ruled
        let side: CGFloat = compact ? 8 : 10
        let thumbWidth: CGFloat = ruler ? 4 : side
        let radius: CGFloat = theme.controls.progress == .continuous ? side / 2 : 1.5
        return RoundedRectangle(cornerRadius: radius)
            .fill(theme.accentStrong)
            .frame(width: thumbWidth, height: ruler ? side + 3 : side)
            .shadow(color: theme.textStrong.opacity(0.18), radius: 1, y: 1)
            .offset(x: min(max(0, width * position - thumbWidth / 2), max(0, width - thumbWidth)))
    }
}

// 分段轨道按实际进度裁切填充，零进度不显示虚假的已播放部分。
private struct SegmentedProgressRail: View {
    let ratio: CGFloat
    let color: Color
    let track: Color

    var body: some View {
        Canvas { context, size in
            let count = max(1, Int(size.width / 9))
            let step = size.width / CGFloat(count)
            for index in 0..<count {
                let rect = CGRect(x: CGFloat(index) * step, y: 0, width: max(1, step - 2), height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color(track))
                let fill = max(0, min(rect.width, size.width * ratio - rect.minX))
                if fill > 0 {
                    context.fill(Path(CGRect(x: rect.minX, y: 0, width: fill, height: size.height)), with: .color(color))
                }
            }
        }
    }
}

// Hi-Fi 与唱片店使用静态刻度，不为装饰引入额外的动画循环。
private struct ProgressRuler: View {
    let color: Color

    var body: some View {
        Canvas { context, size in
            let count = max(1, Int(size.width / 12))
            for index in 1..<count {
                let x = CGFloat(index) * size.width / CGFloat(count)
                let rect = CGRect(x: x, y: 0, width: 1, height: size.height)
                context.fill(Path(rect), with: .color(color))
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

// 主播放栏与歌词页复用音量控件，主题决定显示旋钮或滑块。
struct ThemedVolumeControl: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false

    var body: some View {
        @Bindable var player = model.player
        Group {
            if theme.controls.usesKnob {
                ThemedKnob(volume: $player.volume)
            } else {
                HStack(spacing: 8) {
                    muteButton
                    if hovering {
                        Slider(value: $player.volume, in: 0...1)
                            .controlSize(.mini).tint(theme.accentStrong).frame(width: 64)
                            .accessibilityLabel("音量")
                    }
                }
                .onHover { hovering = $0 }
            }
        }
        .animation(theme.allowsMotion && !reduceMotion ? .easeOut(duration: 0.16) : nil, value: hovering)
    }

    private var muteButton: some View {
        IconButton(size: 30) {
            model.player.volume = model.player.volume > 0 ? 0 : 0.8
        } content: {
            Image(systemName: model.player.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                .font(.system(size: 14))
        }
        .help(model.player.volume == 0 ? "取消静音" : "静音")
        .accessibilityLabel(model.player.volume == 0 ? "取消静音" : "静音")
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("音量")
        .accessibilityValue("\(Int(volume * 100))%")
        .accessibilityAdjustableAction { direction in
            // 为辅助功能提供与拖动旋钮一致的有界音量调整。
            adjustVolume(direction)
        }
    }

    // 通过键盘和辅助功能按固定步长调整音量。
    private func adjustVolume(_ direction: AccessibilityAdjustmentDirection) {
        switch direction {
        case .increment: volume = min(1, volume + 0.05)
        case .decrement: volume = max(0, volume - 0.05)
        @unknown default: break
        }
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
