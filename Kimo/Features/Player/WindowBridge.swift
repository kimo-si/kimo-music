import AppKit
import Observation
import SwiftUI

// 统一管理大小窗尺寸、布局提交与过渡生命周期。
@MainActor
@Observable
final class WindowBridge {
    static let shared = WindowBridge()
    weak var window: NSWindow?
    private(set) var isMiniPinned = false
    private(set) var isTransitioning = false
    private(set) var transitionContentSize: NSSize = .zero

    private var normalFrame: NSRect?
    private var normalMinimum: NSSize?
    private var activeMini = false
    private var pending: ModeRequest?
    private var transition: WindowModeTransition?

    private struct ModeRequest {
        let mini: Bool
        let reduceMotion: Bool
        let updateContent: () -> Void
    }

    // 每次请求都进入协调器，连续点击只保留最后一次目标模式。
    func setMini(_ mini: Bool, reduceMotion: Bool = false, updateContent: @escaping () -> Void = {}) {
        let request = ModeRequest(mini: mini, reduceMotion: reduceMotion, updateContent: updateContent)
        guard let window else {
            pending = request
            updateContent()
            return
        }
        guard !isTransitioning else { pending = request; return }
        guard mini != activeMini else { updateContent(); return }
        // 先确定目标尺寸和旧窗口状态，再捕获旧界面并提交新布局。
        begin(request, in: window)
    }

    // 窗口挂载后应用启动时暂存的模式，无可见窗口时不播放过渡。
    func applyPending() {
        guard let request = pending else { return }
        pending = nil
        setMini(request.mini, reduceMotion: request.reduceMotion, updateContent: request.updateContent)
    }

    // 关闭窗口并清除未执行的切换请求，保留既有后台播放行为。
    func closeWindow() {
        pending = nil
        window?.performClose(nil)
    }

    // 切换本次运行中的小窗置顶选择，并同步原生窗口层级。
    func toggleMiniPinned() {
        guard let window else { return }
        isMiniPinned.toggle()
        // 窗口层级统一按当前模式应用，避免完整窗口继承小窗置顶。
        updateWindowLevel(in: window)
    }

    // 仅在小窗模式应用置顶，恢复完整窗口时回到普通层级。
    private func updateWindowLevel(in window: NSWindow) {
        window.level = activeMini && isMiniPinned ? .floating : .normal
    }

    // 获取目标后先松开尺寸约束，防止恢复大窗时被最小宽度瞬间撑开。
    private func begin(_ request: ModeRequest, in window: NSWindow) {
        let target = targetFrame(for: request.mini, in: window)
        let animated = window.isVisible && !request.reduceMotion
            && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        transition = animated ? WindowModeTransition(window: window) : nil
        isTransitioning = true
        transitionContentSize = window.contentRect(forFrameRect: target).size
        window.minSize = NSSize(width: Metrics.miniPlayerWidth, height: Metrics.miniPlayerMinimumHeight)
        setTrafficLights(in: window, hidden: true)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        // 原生快照承担过渡，避免 SwiftUI 再叠加一次布局动画。
        withTransaction(transaction) { request.updateContent() }
        guard transition != nil else {
            window.setFrame(target, display: true)
            finish(request, in: window)
            return
        }
        // 等新布局提交后再启动原生动画，不用固定延时猜测布局完成时间。
        DispatchQueue.main.async { [weak self] in self?.animate(to: target, request: request, in: window) }
    }

    // 保存大窗位置并计算小窗目标；恢复前保留原始快照，防止反复切换漂移。
    private func targetFrame(for mini: Bool, in window: NSWindow) -> NSRect {
        if mini {
            normalFrame = window.frame
            normalMinimum = window.minSize
            let frame = NSRect(x: window.frame.midX - Metrics.miniPlayerWidth / 2,
                               y: window.frame.maxY - Metrics.miniPlayerHeight,
                               width: Metrics.miniPlayerWidth, height: Metrics.miniPlayerHeight)
            return visibleFrame(frame, for: window)
        }
        return visibleFrame(normalFrame ?? window.frame, for: window)
    }

    // 采用平滑减速曲线缩放窗口，快照淡出与目标内容淡入共享同一时长。
    private func animate(to target: NSRect, request: ModeRequest, in window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        // 先安排图层淡入，再让窗口位置和尺寸在同一轮刷新中变化。
        transition?.revealContent()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = PlayerMotion.windowResizeDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.8, 0.25, 1)
            window.animator().setFrame(target, display: true)
        } completionHandler: { [weak self] in
            Task { @MainActor in self?.finish(request, in: window) }
        }
    }

    // 动画结束后恢复尺寸约束和交互，再执行等待中的最新目标。
    private func finish(_ request: ModeRequest, in window: NSWindow) {
        transition?.finish()
        transition = nil
        activeMini = request.mini
        // 模式提交后恢复相应窗口层级，保留小窗的置顶选择。
        updateWindowLevel(in: window)
        window.isMovableByWindowBackground = request.mini
        window.minSize = request.mini
            ? NSSize(width: Metrics.miniPlayerWidth, height: Metrics.miniPlayerMinimumHeight)
            : (normalMinimum ?? NSSize(width: 1100, height: 680))
        if !request.mini { normalFrame = nil; normalMinimum = nil }
        setTrafficLights(in: window, hidden: request.mini)
        isTransitioning = false
        // 合并动画期间的重复请求，避免旧完成回调覆盖最新模式。
        applyPending()
    }

    // 在窗口进入最终形态后显示对应的系统按钮。
    private func setTrafficLights(in window: NSWindow, hidden: Bool) {
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = hidden
        }
    }

    // 将窗口限制在可见桌面区域，兼容显示器切换和较小屏幕。
    private func visibleFrame(_ frame: NSRect, for window: NSWindow) -> NSRect {
        guard let screen = window.screen ?? NSScreen.main else { return frame }
        let bounds = screen.visibleFrame
        var result = frame
        result.size.width = min(result.width, bounds.width)
        result.size.height = min(result.height, bounds.height)
        result.origin.x = min(max(result.minX, bounds.minX), bounds.maxX - result.width)
        result.origin.y = min(max(result.minY, bounds.minY), bounds.maxY - result.height)
        return result
    }
}
