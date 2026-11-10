import AppKit
import QuartzCore

// 使用旧界面的快照衔接窗口尺寸变化，避免复杂列表在缩放途中反复排版。
@MainActor
final class WindowModeTransition {
    private let content: NSView
    private let snapshot: NSView

    // 在布局切换前捕获真实界面，快照与内容视图同级，不受其透明度影响。
    init?(window: NSWindow) {
        guard let content = window.contentView, let parent = content.superview,
              content.bounds.width > 0, content.bounds.height > 0,
              let bitmap = content.bitmapImageRepForCachingDisplay(in: content.bounds) else { return nil }
        content.cacheDisplay(in: content.bounds, to: bitmap)
        guard let image = bitmap.cgImage else { return nil }
        self.content = content
        snapshot = NSView(frame: content.frame)
        snapshot.autoresizingMask = [.width, .height]
        snapshot.wantsLayer = true
        snapshot.layer?.contents = image
        snapshot.layer?.contentsGravity = .resizeAspectFill
        snapshot.layer?.masksToBounds = true
        parent.addSubview(snapshot, positioned: .above, relativeTo: content)
        content.alphaValue = 0
    }

    // 让新界面先完成最终尺寸的布局，再与窗口缩放同步交叉淡入。
    func revealContent() {
        content.layoutSubtreeIfNeeded()
        content.alphaValue = 1
        // 使用关键帧延后新布局显现，避免缩放初期暴露目标布局的边缘。
        animateOpacity(content, values: [0, 0, 1])
        animateOpacity(snapshot, values: [1, 1, 0])
    }

    // 清除临时图层并恢复交互，重复切换不会留下快照遮挡按钮。
    func finish() {
        content.layer?.removeAnimation(forKey: Self.animationKey)
        content.alphaValue = 1
        snapshot.removeFromSuperview()
    }

    private static let animationKey = "kimo.window-mode.opacity"

    // 与原生窗口尺寸动画共享时长，让图层淡入淡出在同一帧结束。
    private func animateOpacity(_ view: NSView, values: [Double]) {
        view.wantsLayer = true
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = values
        animation.keyTimes = [0, NSNumber(value: PlayerMotion.windowRevealStart), 1]
        animation.duration = PlayerMotion.windowResizeDuration
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        animation.timingFunctions = [CAMediaTimingFunction(name: .linear), CAMediaTimingFunction(name: .easeInEaseOut)]
        view.layer?.add(animation, forKey: Self.animationKey)
    }
}
