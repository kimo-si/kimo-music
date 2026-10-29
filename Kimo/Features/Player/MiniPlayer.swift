//
//  MiniPlayer.swift
//  Kimo
//
//  迷你模式：窗口收成一条胶囊，只留封面、曲名和传输控制。
//  对应 cocomusic 的 MiniPlayer + use-mini-mode。
//

import AppKit
import SwiftUI

@MainActor
final class WindowBridge {
    static let shared = WindowBridge()
    weak var window: NSWindow?

    private var normalFrame: NSRect?
    private var pending: Bool?

    /// 切换窗口尺寸与操作方式，退出迷你模式时恢复完整窗口。
    func setMini(_ mini: Bool) {
        guard let window else {
            pending = mini
            return
        }
        if mini {
            normalFrame = window.frame
            // 以整个窗口计算胶囊高度，保留顶部位置并压缩上下留白。
            let target = NSRect(
                x: window.frame.midX - Metrics.miniPlayerWidth / 2,
                y: window.frame.maxY - Metrics.miniPlayerHeight,
                width: Metrics.miniPlayerWidth,
                height: Metrics.miniPlayerHeight
            )
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: Metrics.miniPlayerWidth, height: Metrics.miniPlayerHeight)
            // 迷你胶囊是自绘窗口，红绿灯收起来；用右下角按钮回到完整界面。
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = true
            }
            window.setFrame(target, display: true, animate: true)
            window.level = .normal
        } else {
            window.isMovableByWindowBackground = false
            window.minSize = NSSize(width: 1100, height: 680)
            for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(type)?.isHidden = false
            }
            // 恢复时把窗口拉回可用屏幕内。
            var frame = normalFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 820)
            if let screen = window.screen ?? NSScreen.main {
                frame.origin.x = min(max(frame.origin.x, screen.visibleFrame.minX),
                                     screen.visibleFrame.maxX - frame.width)
                frame.origin.y = min(max(frame.origin.y, screen.visibleFrame.minY),
                                     screen.visibleFrame.maxY - frame.height)
            }
            window.setFrame(frame, display: true, animate: true)
        }
    }

    /// 窗口还没挂上时先记下，等 NSWindow 就绪再套用。
    func applyPending() {
        guard let pending else { return }
        self.pending = nil
        setMini(pending)
    }
}

struct MiniPlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private var player: PlayerEngine { model.player }

    var body: some View {
        ZStack {
            Backdrop(theme: theme)
            HStack(spacing: 14) {
                cover
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.current?.name ?? "未在播放")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(theme.textStrong)
                        .lineLimit(1)
                    Text(player.current?.artist ?? "选一首歌，开始聆听")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                controls
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.bottom, 4)

            // 底部进度细线
            progressRail
                .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(theme.glassEdge, lineWidth: 1)
        }
        .ignoresSafeArea()
    }

    private var cover: some View {
        ZStack {
            if let song = player.current {
                CoverImage(url: song.cover, radius: 10, seed: song.id)
            } else {
                RoundedRectangle(cornerRadius: 10).fill(theme.chip)
                Image(systemName: "music.note")
                    .font(.system(size: 16, weight: .light))
                    .foregroundStyle(theme.textMuted)
            }
        }
        .frame(width: 54, height: 54)
        .shadow(color: .black.opacity(0.18), radius: 5, y: 2)
    }

    private var controls: some View {
        HStack(spacing: 10) {
            IconButton(size: 30, radius: 9, muted: true, disabled: !player.canGoPrevious) {
                player.previous()
            } content: {
                Image(systemName: "backward.end").font(.system(size: 13, weight: .light))
            }
            .help("上一首")
            .accessibilityLabel("上一首")

            Button {
                player.togglePlayPause()
            } label: {
                PlayPauseGlyph(playing: player.isPlaying, size: 12, color: theme.accentStrong)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(player.isPlaying ? "暂停" : "播放")

            IconButton(size: 30, radius: 9, muted: true, disabled: !player.canGoNext) {
                player.next()
            } content: {
                Image(systemName: "forward.end").font(.system(size: 13, weight: .light))
            }
            .help("下一首")
            .accessibilityLabel("下一首")

            IconButton(size: 30, radius: 9, muted: true) {
                model.setMini(false)
            } content: {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
            }
            .help("退出迷你模式")
        }
    }

    private var progressRail: some View {
        GeometryReader { geo in
            let ratio = player.duration > 0
                ? min(1, max(0, CGFloat(player.progress / player.duration)))
                : 0
            ZStack(alignment: .leading) {
                Rectangle().fill(theme.playerRail)
                Rectangle().fill(theme.accentStrong).frame(width: geo.size.width * ratio)
            }
            .frame(height: 3)
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .frame(height: 16)
        .modifier(ProgressTimeHover(duration: player.duration))
    }
}
