import SwiftUI

/// 独立刷新背景画布，不让音频采样触发整条播放栏重新布局。
struct PlayerWaveformBackground: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let levels: PlaybackAudioLevels
    let playing: Bool
    let volume: Double

    private static let frameInterval = 1.0 / 30
    private static let barSpacing: CGFloat = 5
    private var active: Bool { playing && volume > 0 && theme.allowsMotion && !reduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: Self.frameInterval, paused: !active)) { timeline in
            // 显式依赖每帧时间，并在画布外读取数据，确保 SwiftUI 更新绘制输入。
            let frameTime = ProcessInfo.processInfo.systemUptime + timeline.date.timeIntervalSinceNow
            let samples = levels.snapshot(at: frameTime)
            Canvas { context, size in
                // 将真实音量包络绘制到控件背后，顶部淡出以保留文字对比度。
                draw(samples, in: &context, size: size)
            }
        }
        .opacity(active ? 1 : 0)
        .animation(reduceMotion || !theme.allowsMotion ? nil : .easeOut(duration: 0.35), value: active)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // 使用两端渐隐的圆角音柱，让背景覆盖整条播放栏但不遮挡交互。
    private func draw(_ samples: [Double], in context: inout GraphicsContext, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let step = size.width / CGFloat(samples.count)
        let width = max(1, step - Self.barSpacing)
        let tint = theme.accent
        let gradient = Gradient(colors: [tint.opacity(0.02), tint.opacity(theme.isDark ? 0.28 : 0.18)])
        for (index, sample) in samples.enumerated() {
            let edge = sin(Double(index + 1) / Double(samples.count + 1) * .pi)
            let height = max(1, size.height * 0.86 * sample * edge)
            let rect = CGRect(x: CGFloat(index) * step, y: size.height - height, width: width, height: height)
            let path = Path(roundedRect: rect, cornerRadius: min(width / 2, 3))
            context.fill(path, with: .linearGradient(gradient,
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: size.height)))
        }
    }
}
