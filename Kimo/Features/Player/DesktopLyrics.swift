//
//  DesktopLyrics.swift
//  Kimo
//
//  桌面歌词：一个无边框、置顶、不抢焦点的浮动条，可拖动、可跨桌面。
//  对应的设置项在 设置 › 桌面歌词。
//

import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class DesktopLyricsController {
    static let shared = DesktopLyricsController()

    private var panel: NSPanel?
    private weak var model: AppModel?
    private(set) var isVisible = false

    private let visibleKey = "kimo.desktopLyricsVisible"
    private let originKey = "kimo.desktopLyricsOrigin"

    func bind(_ model: AppModel) {
        self.model = model
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        guard let model else { return }
        if panel == nil { panel = makePanel(model: model) }
        panel?.orderFrontRegardless()
        isVisible = true
        UserDefaults.standard.set(true, forKey: visibleKey)
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
        UserDefaults.standard.set(false, forKey: visibleKey)
    }

    /// 把歌词条拉回主屏底部居中。
    func resetPosition() {
        UserDefaults.standard.removeObject(forKey: originKey)
        guard let panel, let screen = NSScreen.main else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2,
                                     y: screen.visibleFrame.minY + 140))
    }

    func restoreIfNeeded() {
        guard UserDefaults.standard.bool(forKey: visibleKey) else { return }
        show()
    }

    // MARK: - 构建

    private func makePanel(model: AppModel) -> NSPanel {
        let size = NSSize(width: 980, height: 140)
        let saved = UserDefaults.standard.string(forKey: originKey)
        var origin = NSPoint(x: 0, y: 0)
        if let saved {
            let parts = saved.split(separator: ",").compactMap { Double($0) }
            if parts.count == 2 { origin = NSPoint(x: parts[0], y: parts[1]) }
        } else if let screen = NSScreen.main {
            origin = NSPoint(
                x: screen.visibleFrame.midX - size.width / 2,
                y: screen.visibleFrame.minY + 140
            )
        }

        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false

        let host = NSHostingView(rootView: DesktopLyricsView().environment(model))
        host.frame = NSRect(origin: .zero, size: size)
        panel.contentView = host

        // 记住位置
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            guard let frame = self?.panel?.frame else { return }
            UserDefaults.standard.set("\(frame.origin.x),\(frame.origin.y)", forKey: self?.originKey ?? "")
        }

        return panel
    }
}

// MARK: - 视图

struct DesktopLyricsView: View {
    @Environment(AppModel.self) private var model
    @State private var hovering = false

    private var settings: AppSettings { model.settings }
    private var theme: Theme { model.theme }

    private var index: Int? {
        model.lyrics.index(at: model.player.progress, offsetMs: settings.lyricsOffset)
    }

    private var currentText: String {
        model.lyrics.line(at: index)
            ?? model.player.current?.name
            ?? "Kimo"
    }

    private var nextText: String? {
        model.lyrics.nextLine(after: index)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 10) {
                Spacer(minLength: 0)
                Text(currentText)
                    .font(.system(size: settings.desktopLyricsFontSize, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .modifier(OutlineModifier(enabled: settings.desktopLyricsStroke, isDark: true))
                    .shadow(color: .black.opacity(0.55), radius: 6, y: 2)

                if settings.desktopLyricsShowNext, let nextText {
                    Text(nextText)
                        .font(.system(size: settings.desktopLyricsFontSize * 0.52, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .modifier(OutlineModifier(enabled: settings.desktopLyricsStroke, isDark: true))
                        .shadow(color: .black.opacity(0.5), radius: 4, y: 1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)
            .padding(.vertical, 8)

            if hovering {
                HStack(spacing: 6) {
                    IconButton(size: 26, radius: 8, muted: true) {
                        withAnimation(PlayerMotion.lyricsAnimation(reduceMotion: settings.reduceMotion)) {
                            model.showLyrics = true
                        }
                    } content: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .help("打开歌词页")

                    IconButton(size: 26, radius: 8, muted: true) {
                        DesktopLyricsController.shared.hide()
                    } content: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .help("关闭桌面歌词")
                }
                .padding(6)
                .background {
                    Capsule().fill(Color.black.opacity(0.35))
                }
                .padding(6)
                .transition(.opacity)
            }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
        // 面板本身透明，这里只给一点阴影保证任何壁纸上都读得清。
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(hovering ? 0.18 : 0.001))
        )
    }
}

/// 用四向阴影模拟描边，让白字在浅色壁纸上也不糊。
struct OutlineModifier: ViewModifier {
    let enabled: Bool
    let isDark: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: .black.opacity(0.85), radius: 0.6, x: 1, y: 0)
                .shadow(color: .black.opacity(0.85), radius: 0.6, x: -1, y: 0)
                .shadow(color: .black.opacity(0.85), radius: 0.6, x: 0, y: 1)
                .shadow(color: .black.opacity(0.85), radius: 0.6, x: 0, y: -1)
        } else {
            content
        }
    }
}
