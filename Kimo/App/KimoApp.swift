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
                // 小窗的整体高度由 WindowBridge 约束，避免内容最小高度再叠加标题栏。
                .frame(minWidth: model.isMini ? Metrics.miniPlayerWidth : 1100,
                       minHeight: model.isMini ? 0 : 680)
                .background(WindowConfigurator(effect: model.settings.windowEffect,
                                                shell: model.theme.shellRGB))
                .onAppear {
                    CoreService.shared.boot()
                    auth.restore()
                    appDelegate.model = model
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?
    private var keyMonitor: Any?

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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// 让 SwiftUI 窗口变成「内容铺满 + 透明标题栏」，并按设置切换窗口是否透出桌面。
struct WindowConfigurator: NSViewRepresentable {
    let effect: WindowEffect
    let shell: (Int, Int, Int)

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            WindowBridge.shared.window = window
            WindowBridge.shared.applyPending()
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
