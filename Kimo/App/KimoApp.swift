//
//  KimoApp.swift
//  Kimo
//
//  无边框玻璃窗口：标题栏隐藏，红绿灯保留在左上角，顶栏空白处可拖动窗口。
//  「窗口效果」决定 NSWindow 是否透明——这是窗口透明度能真正生效的前提。
//

import AppKit
import SwiftUI

@main
struct KimoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()
    @State private var auth = AuthStore()

    private var colorScheme: ColorScheme? {
        if let fixed = model.settings.fixedDarkAppearance {
            return fixed ? .dark : .light
        }
        switch model.settings.themeMode {
        case .light: return .light
        case .dark: return .dark
        case .system: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(auth)
                .environment(\.theme, model.theme)
                .preferredColorScheme(colorScheme)
                .background(WindowConfigurator(effect: model.settings.windowEffect,
                                                shell: model.theme.shellRGB))
                .onAppear {
                    CoreService.shared.boot()
                    auth.restore()
                    // 将系统媒体控制绑定到播放器，窗口关闭后仍可由耳机操作。
                    appDelegate.bind(model)
                    DesktopLyricsController.shared.bind(model)
                    DesktopLyricsController.shared.restoreIfNeeded()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .toolbar) {
                Button("切换侧边栏") { model.toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .control])
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var model: AppModel?
    private let mediaControls = SystemMediaControls()
    private var keyMonitor: Any?

    // 统一绑定应用级播放控制，重复显示窗口不会重复注册系统指令。
    func bind(_ model: AppModel) {
        self.model = model
        mediaControls.start(player: model.player)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        installShortcuts()
        // 窗口可能被恢复到外接屏上：以鼠标所在屏幕为准，不在那儿就挪过去。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let mouse = NSEvent.mouseLocation
            let target = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
            guard let target else { return }
            for window in NSApp.windows where window.isVisible && window.canBecomeMain {
                let hit = target.visibleFrame.intersection(window.frame)
                let onTargetScreen = !hit.isNull && hit.width > 240 && hit.height > 200
                if !onTargetScreen {
                    let size = window.frame.size
                    let origin = NSPoint(
                        x: target.visibleFrame.midX - size.width / 2,
                        y: target.visibleFrame.midY - size.height / 2
                    )
                    window.setFrame(NSRect(origin: origin, size: size), display: true)
                }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        // 退出前释放系统媒体监听，避免留下过期的正在播放状态。
        mediaControls.stop()
        CoreService.shared.shutdown()
    }

    /// 全局快捷键：空格播放/暂停、⌘←/→ 上下曲、⌘↑/↓ 音量、Esc 退出歌词页。
    private func installShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let model = self?.model else { return event }
            // 正在输入文字时不抢键
            if let responder = NSApp.keyWindow?.firstResponder, responder is NSTextView {
                return event
            }
            let cmd = event.modifierFlags.contains(.command)
            let shift = event.modifierFlags.contains(.shift)

            switch event.keyCode {
            case 49 where !cmd && !shift:              // space
                model.player.togglePlayPause()
                return nil
            case 123 where cmd:                        // ⌘←
                model.player.previous()
                return nil
            case 124 where cmd:                        // ⌘→
                model.player.next()
                return nil
            case 126 where cmd:                        // ⌘↑
                model.player.volume = min(1, model.player.volume + 0.05)
                return nil
            case 125 where cmd:                        // ⌘↓
                model.player.volume = max(0, model.player.volume - 0.05)
                return nil
            case 53:                                   // esc
                if model.showLyrics { model.showLyrics = false; return nil }
                if model.showQueue { model.showQueue = false; return nil }
                return event
            default:
                return event
            }
        }
    }

    // 关闭最后一个窗口后继续在程序坞后台运行，仅在明确退出时关闭播放与核心服务。
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// 让 SwiftUI 窗口变成「内容铺满 + 透明标题栏」，并按设置切换窗口是否透出桌面。
struct WindowConfigurator: NSViewRepresentable {
    let effect: WindowEffect
    let shell: (Int, Int, Int)

    // 创建窗口配置视图，让新窗口先接收快捷键而不是自动进入搜索输入。
    func makeNSView(context: Context) -> NSView {
        let view = WindowInitialFocusView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            WindowBridge.shared.window = window
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            window.isMovableByWindowBackground = false
            // 首次显示时居中，避免恢复到一个已经不存在的外接屏坐标上。
            if let screen = window.screen ?? NSScreen.main,
               !screen.visibleFrame.contains(window.frame.origin) {
                window.center()
            }
            apply(to: window)
            // 红绿灯位置与 cocomusic 一致：左上留 14pt 内缩。
            for (i, button) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
                guard let b = window.standardWindowButton(button), let superview = b.superview else { continue }
                b.frame.origin.x = 14 + CGFloat(i) * 18
                b.frame.origin.y = superview.bounds.height - 24
            }
            // 完成窗口基础配置后再应用启动模式，避免覆盖小窗的拖动与按钮状态。
            WindowBridge.shared.applyPending()
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            apply(to: window)
        }
    }

    private func apply(to window: NSWindow) {
        let seeThrough = effect != .none
        window.isOpaque = !seeThrough
        window.backgroundColor = seeThrough ? .clear : NSColor(
            srgbRed: CGFloat(shell.0) / 255,
            green: CGFloat(shell.1) / 255,
            blue: CGFloat(shell.2) / 255,
            alpha: 1
        )
        window.hasShadow = true
        window.contentView?.wantsLayer = true
    }
}

// 为窗口提供初始焦点，不增加 Tab 停靠点，也不影响鼠标操作。
private final class WindowInitialFocusView: NSView {
    private weak var configuredWindow: NSWindow?
    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { false }

    // 视图挂入新窗口时设置初始焦点，避免系统自动激活首个输入框。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window, window !== configuredWindow else { return }
        configuredWindow = window
        window.initialFirstResponder = self
        // 将初始键盘事件交给窗口，搜索框仍可由用户主动点击聚焦。
        window.makeFirstResponder(self)
    }

    // 背景配置层不截获鼠标点击，保留原有窗口拖动和控件交互。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
