//
//  PlayerBarView.swift
//  Kimo
//
//  底部播放栏：76pt。进度条贴顶，控件在剩下的高度里垂直居中。
//

import SwiftUI

struct PlayerBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme
    @State private var dragging = false

    private var player: PlayerEngine { model.player }
    private var currentLiked: Bool {
        guard let song = player.current else { return false }
        return model.likes.isLiked(song)
    }

    private func toggleLike() async {
        guard let song = player.current else { return }
        guard auth.isLoggedIn else {
            model.showLogin = true
            player.showNotice("登录后才能同步到酷狗的我喜欢")
            return
        }
        if let message = await model.likes.toggle(song) {
            player.showNotice(message)
        }
    }

    var body: some View {
        ZStack {
            if theme.usesGlassMaterial && theme.glassBlur > 0 {
                Rectangle().fill(.ultraThinMaterial)
            }
            Rectangle().fill(theme.player)

            VStack(spacing: 0) {
                progressRail
                HStack(alignment: .center, spacing: 16) {
                    nowPlaying
                        .frame(maxWidth: .infinity, alignment: .leading)
                    transport
                    tools
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .overlay(alignment: .top) {
            if let notice = player.notice {
                NoticeBanner(text: notice, needsLogin: player.noticeNeedsLogin) {
                    model.showLogin = true
                }
                .padding(.top, -44)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: player.notice)
    }

    // MARK: Now playing

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            Button {
                guard player.current != nil else { return }
                withAnimation(PlayerMotion.lyricsAnimation(reduceMotion: model.settings.reduceMotion)) {
                    model.showLyrics = true
                }
            } label: {
                HStack(spacing: 12) {
                    ZStack {
                        if let song = player.current {
                            CoverImage(url: song.cover, radius: 9, seed: song.id)
                        } else {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(theme.chip)
                            Image(systemName: "music.note")
                                .font(.system(size: 18, weight: .light))
                                .foregroundStyle(theme.textMuted)
                        }
                    }
                    .frame(width: 40, height: 40)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.current?.name ?? "未在播放")
                            .font(theme.titleFont(15, weight: .medium))
                            .foregroundStyle(player.current == nil ? theme.textMuted : theme.textStrong)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(player.current?.artist ?? "选一首歌，开始聆听")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(1)
                            if player.current != nil, theme.flavor == .night {
                                MiniWave(color: theme.accent, playing: player.isPlaying, motion: theme.allowsMotion)
                            }
                            if player.current != nil, theme.flavor == .mint {
                                MiniNotes(color: theme.accent, playing: player.isPlaying, motion: theme.allowsMotion)
                            }
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(player.current == nil)
            .help("打开播放页")
            .accessibilityLabel("打开播放页")

            IconButton(size: 30, radius: 9, muted: true,
                       disabled: player.current == nil,
                       tint: currentLiked ? theme.like : nil) {
                Task { await toggleLike() }
            } content: {
                Image(systemName: currentLiked ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: currentLiked ? .regular : .light))
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(currentLiked ? "取消喜欢" : "加入我喜欢")
        }
    }

    // MARK: Transport

    private var transport: some View {
        HStack(spacing: 14) {
            IconButton(size: 30, radius: 9, muted: true) {
            } content: {
                Image(systemName: "shuffle").font(.system(size: 15, weight: .light))
            }

            HStack(spacing: 8) {
                IconButton(size: 32, radius: 16, muted: false, disabled: !player.canGoPrevious) {
                    player.previous()
                } content: {
                    Image(systemName: "backward.end").font(.system(size: 16, weight: .light))
                }

                ThemedPlayButton(playing: player.isPlaying) {
                    player.togglePlayPause()
                }

                IconButton(size: 32, radius: 16, muted: false, disabled: !player.canGoNext) {
                    player.next()
                } content: {
                    Image(systemName: "forward.end").font(.system(size: 16, weight: .light))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            timeLabel
            if theme.flavor == .hifi {
                VUMeter(playing: player.isPlaying, motion: theme.allowsMotion)
            }
        }
    }

    private var timeLabel: some View {
        HStack(spacing: 7) {
            Text(timeText(player.progress))
                .foregroundStyle(theme.text)
            Text("/")
                .foregroundStyle(theme.textMuted)
            Text(timeText(player.duration))
                .foregroundStyle(theme.textMuted)
        }
        .font(.system(size: 13).monospacedDigit())
    }

    private func timeText(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "00:00" }
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    // MARK: Tools

    private var tools: some View {
        HStack(spacing: 10) {
            HoverChip {
                Text("标准")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7).fill(theme.chip))
            } action: {}

            ThemedVolumeControl()

            Rectangle()
                .fill(theme.playerHairline)
                .frame(width: 1, height: 26)
                .padding(.leading, 4)
                .padding(.trailing, 10)

            IconButton(size: 32, radius: 9, active: DesktopLyricsController.shared.isVisible, muted: true) {
                DesktopLyricsController.shared.toggle()
            } content: {
                Text("词")
                    .font(.system(size: 15))
            }
            .help(DesktopLyricsController.shared.isVisible ? "关闭桌面歌词" : "打开桌面歌词")

            Spacer(minLength: 8)

            HoverChip {
                HStack(spacing: 6) {
                    Image(systemName: "music.note.list")
                        .font(.system(size: 15, weight: .light))
                    if !player.queue.isEmpty {
                        Text("\(player.queue.count)")
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(theme.textMuted)
                    }
                }
                .foregroundStyle(model.showQueue ? theme.accentStrong : theme.textSecondary)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(model.showQueue ? theme.accentSoft : Color.clear)
                }
            } action: {
                model.showQueue.toggle()
            }
            .help("播放列表")
        }
    }

    // MARK: Progress

    private var progressRail: some View {
        GeometryReader { geo in
            let ratio: CGFloat = player.duration > 0
                ? min(1, max(0, CGFloat(player.progress / player.duration)))
                : 0
            ThemedProgress(ratio: ratio, dragging: dragging, playing: player.isPlaying)
                .frame(height: 16)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.duration > 0 else { return }
                            dragging = true
                            let r = min(1, max(0, value.location.x / geo.size.width))
                            player.seek(to: player.duration * Double(r))
                        }
                        .onEnded { _ in dragging = false }
                )
        }
        .frame(height: 16)
        .modifier(ProgressTimeHover(duration: player.duration))
    }
}

// MARK: - Hover chip

private struct HoverChip<Label: View>: View {
    @ViewBuilder var label: () -> Label
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action, label: label)
            .buttonStyle(ThemedButtonStyle())
            .hoverLift(active: hovering)
            .onHover { hovering = $0 }
    }
}

// MARK: - Notice

private struct NoticeBanner: View {
    @Environment(\.theme) private var theme
    let text: String
    var needsLogin = false
    var onAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(theme.textStrong)
            if needsLogin, let onAction {
                Button(action: onAction) {
                    Text("登录")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(theme.accentStrong)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(theme.accentSoft))
                }
                .buttonStyle(.plain)
            }
        }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background {
                Capsule().fill(.ultraThinMaterial)
                Capsule().fill(theme.isDark ? Color.black.opacity(0.4) : Color.white.opacity(0.75))
                Capsule().strokeBorder(theme.glassEdge, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
    }
}
