// 与 Kimo 下除 KimoApp.swift 外的 Swift 源码一起编译，检查真实窗口过渡。
import AppKit
import SwiftUI

@main
struct WindowTransitionCheck {
    // 使用独立配置与预览歌曲检查原生动画，避免修改账号与实际播放状态。
    @MainActor
    static func main() throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kimo-window-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = makeModel(in: directory)
        let window = makeWindow(model: model)
        defer { window.close(); WindowBridge.shared.window = nil }
        let original = window.frame
        let originalSubviews = window.contentView?.superview?.subviews.count
        // 检查中间尺寸、重复反向请求和最终恢复状态。
        checkRoundTrips(model, window: window, original: original)
        checkLatestRequest(model, window: window, original: original)
        checkReducedMotion(model, window: window, original: original)
        check(window.contentView?.superview?.subviews.count == originalSubviews, "过渡快照应全部释放")
        check(window.contentView?.alphaValue == 1, "真实内容透明度应恢复")
        check(model.player.playbackContext.source == .playlist(id: "test", title: "动画测试"), "切换不得改变播放来源")
        print("窗口过渡检查通过：连续往返、中间尺寸、最新请求优先、减弱动态、尺寸恢复、快照清理")
    }

    // 隔离设置并固定在设置页，防止测试期间触发首页远程加载。
    @MainActor
    private static func makeModel(in directory: URL) -> AppModel {
        let settings = AppSettings(storageURL: directory.appendingPathComponent("settings.json"))
        settings.resumeOnLaunch = false
        settings.reduceMotion = false
        settings.windowEffect = .none
        let model = AppModel(settings: settings, configureDebug: false)
        model.route = .settings
        let song = Song(id: "animation", hash: "animation", albumId: 0, albumAudioId: 0,
                        name: "窗口动画测试", artist: "测试歌曲", album: "", cover: nil, duration: 180)
        model.player.setQueueForPreview([song], source: .playlist(id: "test", title: "动画测试"))
        return model
    }

    // 用真实 RootView 建立可见窗口，覆盖 SwiftUI 布局与 AppKit 尺寸约束的交互。
    @MainActor
    private static func makeWindow(model: AppModel) -> NSWindow {
        let root = RootView().environment(model).environment(AuthStore()).environment(\.theme, model.theme)
        let window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1100, height: 680),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Kimo 窗口过渡检查"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 1100, height: 680)
        window.contentView = NSHostingView(rootView: root)
        window.center()
        window.orderFrontRegardless()
        WindowBridge.shared.window = window
        pump(for: 0.15)
        return window
    }

    // 反复缩小和放大，检查动画确实经过中间尺寸而非直接跳到目标。
    @MainActor
    private static func checkRoundTrips(_ model: AppModel, window: NSWindow, original: NSRect) {
        let minimum = window.minSize
        for _ in 0..<3 {
            model.setMini(true)
            let sizes = awaitTransition(window)
            check(model.isMini, "缩小后应处于 mini 模式")
            check(window.frame.size == NSSize(width: Metrics.miniPlayerWidth, height: Metrics.miniPlayerHeight), "小窗尺寸错误")
            if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                check(sizes.contains { $0.width > Metrics.miniPlayerWidth + 1 && $0.width < original.width - 1 }, "缩小应经过中间尺寸")
            }
            model.setMini(false)
            _ = awaitTransition(window)
            check(!model.isMini && window.frame == original, "大窗位置与尺寸不应漂移")
            check(window.minSize == minimum, "恢复后应还原大窗约束")
        }
    }

    // 动画途中反复改变目标，最终模式应遵循最后一次调用。
    @MainActor
    private static func checkLatestRequest(_ model: AppModel, window: NSWindow, original: NSRect) {
        model.setMini(true)
        model.setMini(false)
        model.setMini(true)
        _ = awaitTransition(window)
        check(model.isMini && window.frame.width == Metrics.miniPlayerWidth, "最后一次 mini 请求应覆盖等待中的返回请求")
        model.setMini(false)
        model.setMini(true)
        model.setMini(false)
        _ = awaitTransition(window)
        check(!model.isMini && window.frame == original, "最后一次大窗请求应正确恢复")
        model.setMini(true)
        model.setMini(false)
        _ = awaitTransition(window)
        check(!model.isMini && window.frame == original, "等待中的反向请求应在过渡后完成")
    }

    // 用户减弱动态效果时立即切换，不遗留过渡状态或错误尺寸限制。
    @MainActor
    private static func checkReducedMotion(_ model: AppModel, window: NSWindow, original: NSRect) {
        model.settings.reduceMotion = true
        model.setMini(true)
        check(model.isMini && !WindowBridge.shared.isTransitioning, "减弱动态时应立即完成小窗切换")
        pump(for: 0.03)
        model.setMini(false)
        check(!model.isMini && !WindowBridge.shared.isTransitioning, "减弱动态时应立即恢复大窗")
        check(window.frame == original, "减弱动态时也应恢复原位置")
    }

    // 驱动主运行循环并采样真实窗口尺寸，超时视为动画状态机卡住。
    @MainActor
    private static func awaitTransition(_ window: NSWindow) -> [NSSize] {
        let deadline = Date().addingTimeInterval(3)
        var samples: [NSSize] = []
        while WindowBridge.shared.isTransitioning && Date() < deadline {
            pump(for: 0.01)
            samples.append(window.frame.size)
        }
        check(!WindowBridge.shared.isTransitioning, "窗口过渡超时")
        pump(for: 0.03)
        return samples
    }

    // 让主线程处理布局提交与原生动画完成回调。
    @MainActor
    private static func pump(for duration: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(duration))
    }

    // 失败时输出具体场景并以非零状态结束。
    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("窗口过渡检查失败：\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
