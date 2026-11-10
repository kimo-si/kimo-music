import SwiftUI

// 小窗上半部：歌曲信息、紧凑播放控制和可拖动的主题进度条。
struct MiniPlayerControls: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var dragging = false
    @State private var volumeBeforeMute = 0.8

    private var player: PlayerEngine { model.player }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                nowPlaying
                    .frame(maxWidth: .infinity, alignment: .leading)
                transport
            }
            progress
        }
    }

    private var nowPlaying: some View {
        HStack(spacing: 10) {
            ZStack {
                if let song = player.current {
                    CoverImage(url: song.cover, radius: theme.radiusCard, seed: song.id)
                } else {
                    RoundedRectangle(cornerRadius: theme.radiusCard).fill(theme.chip)
                    Image(systemName: "waveform")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .frame(width: 50, height: 50)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(player.current?.name ?? "从一首好歌开始")
                    .font(theme.titleFont(15, weight: .semibold))
                    .foregroundStyle(theme.textStrong)
                    .lineLimit(2)
                Text(player.current?.artist ?? "打开你的歌单，开始聆听")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(height: 60)
    }

    private var transport: some View {
        HStack(spacing: 3) {
            control("从头播放", symbol: "arrow.counterclockwise", disabled: player.current == nil, action: restart)
            control("上一首", symbol: "backward.end.fill", disabled: !player.canGoPrevious, action: player.previous)
            ThemedPlayButton(playing: player.isPlaying, size: 28, action: player.togglePlayPause)
                .disabled(player.current == nil)
                .help(player.isPlaying ? "暂停" : "播放")
            control("下一首", symbol: "forward.end.fill", disabled: !player.canGoNext, action: player.next)
            Rectangle().fill(theme.divider).frame(width: 1, height: 16).padding(.horizontal, 3)
            volume
        }
        .padding(5)
        .modifier(ThemedSurface(radius: max(10, theme.controls.fieldRadius)))
        .fixedSize()
    }

    private var volume: some View {
        @Bindable var player = model.player
        return HStack(spacing: 2) {
            control(player.volume == 0 ? "取消静音" : "静音",
                    symbol: player.volume == 0 ? "speaker.slash" : "speaker.wave.2", action: toggleMute)
            if theme.controls.usesKnob {
                ThemedKnob(volume: $player.volume)
            } else {
                Slider(value: $player.volume, in: 0...1)
                    .controlSize(.mini)
                    .tint(theme.accentStrong)
                    .frame(width: 46)
                    .accessibilityLabel("音量")
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 12) {
            Text(timeText(player.progress)).frame(width: 35, alignment: .leading)
            progressRail
            Text(timeText(player.duration)).frame(width: 35, alignment: .trailing)
        }
        .font(.system(size: 12, weight: .medium).monospacedDigit())
        .foregroundStyle(theme.textSecondary)
        .frame(height: 20)
    }

    private var progressRail: some View {
        GeometryReader { geometry in
            ThemedProgress(ratio: player.duration > 0 ? player.progress / player.duration : 0,
                           dragging: dragging, playing: player.isPlaying)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        dragging = true
                        seek(fraction: value.location.x / max(1, geometry.size.width))
                    }
                    .onEnded { _ in dragging = false })
                .accessibilityHidden(false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("播放进度")
                .accessibilityValue("\(timeText(player.progress))，共 \(timeText(player.duration))")
                .accessibilityAdjustableAction { direction in
                    adjustProgress(direction)
                }
        }
        .modifier(ProgressTimeHover(duration: player.duration))
    }

    // 为紧凑图标按钮提供统一的主题反馈与禁用状态。
    private func control(_ title: String, symbol: String, disabled: Bool = false,
                         action: @escaping () -> Void) -> some View {
        IconButton(size: 24, disabled: disabled, action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: theme.controls.iconWeight))
        }
        .help(title)
        .accessibilityLabel(title)
    }

    // 从当前歌曲开头继续播放，不改变队列与播放来源。
    private func restart() {
        player.seek(to: 0)
        if !player.isPlaying { player.togglePlayPause() }
    }

    // 静音后恢复用户原先选择的音量。
    private func toggleMute() {
        if player.volume > 0 {
            volumeBeforeMute = player.volume
            player.volume = 0
            return
        }
        player.volume = volumeBeforeMute
    }

    // 进度拖动只接受有效时长与位置，并限制在歌曲范围内。
    private func seek(fraction: CGFloat) {
        guard fraction.isFinite, player.duration.isFinite, player.duration > 0 else { return }
        player.seek(to: player.duration * min(1, max(0, Double(fraction))))
    }

    // 辅助功能以五秒为步长调节进度，与拖动使用相同边界。
    private func adjustProgress(_ direction: AccessibilityAdjustmentDirection) {
        guard player.duration > 0 else { return }
        switch direction {
        case .increment: seek(fraction: (player.progress + 5) / player.duration)
        case .decrement: seek(fraction: (player.progress - 5) / player.duration)
        @unknown default: break
        }
    }

    // 安全格式化空时长与加载中的进度。
    private func timeText(_ time: TimeInterval) -> String {
        guard time.isFinite, time > 0 else { return "0:00" }
        let seconds = Int(time)
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
