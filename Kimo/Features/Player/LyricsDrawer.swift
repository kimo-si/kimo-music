//
//  LyricsDrawer.swift
//  Kimo
//
//  全窗口歌词页：左大唱片、右歌词。颜色、材质跟当前皮肤走。
//

import SwiftUI

struct LyricsDrawer: View {
    private static let dragRecognitionDistance: CGFloat = 12
    private static let dismissDragDistance: CGFloat = 80
    private static let dismissVerticalRatio: CGFloat = 1.2
    private static let trackNavigationWidth: CGFloat = 120
    private static let trackNavigationHeight: CGFloat = 220
    private static let trackNavigationWidthRatio: CGFloat = 0.15
    private static let lyricsBarHeight: CGFloat = 64

    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme

    private var player: PlayerEngine { model.player }
    private var settings: AppSettings { model.settings }
    private var engine: LyricsEngine { model.lyrics }
    private var lines: [MusicAPI.LyricLine] { engine.lines }
    private var loading: Bool { engine.loading }
    private var currentIndex: Int? {
        engine.index(at: player.progress, offsetMs: settings.lyricsOffset)
    }

    @State private var stageReady = false
    @State private var draggingProgress = false

    var body: some View {
        GeometryReader { geo in
            let barHeight = settings.showLyricsPlayerBar ? Self.lyricsBarHeight : 0
            let stageHeight = max(220, geo.size.height - 64)
            VStack(spacing: 0) {
                // 顶部只保留红绿灯安全区；返回入口已移到左侧封面。
                Color.clear
                    .frame(height: 64)
                    .allowsHitTesting(false)
                stage(available: max(220, stageHeight - barHeight * 0.4), width: geo.size.width)
                    .frame(height: stageHeight)
                    .overlay(alignment: .leading) {
                        TrackNavigationControl(
                            direction: .previous,
                            enabled: player.canGoPrevious,
                            width: min(Self.trackNavigationWidth, geo.size.width * Self.trackNavigationWidthRatio),
                            height: min(Self.trackNavigationHeight, stageHeight)
                        ) {
                            // 切换到播放队列中的上一首。
                            player.previous()
                        }
                    }
                    .overlay(alignment: .trailing) {
                        TrackNavigationControl(
                            direction: .next,
                            enabled: player.canGoNext,
                            width: min(Self.trackNavigationWidth, geo.size.width * Self.trackNavigationWidthRatio),
                            height: min(Self.trackNavigationHeight, stageHeight)
                        ) {
                            // 切换到播放队列中的下一首。
                            player.next()
                        }
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .overlay(alignment: .bottom) {
                if settings.showLyricsPlayerBar {
                    lyricsPlayerBar
                }
            }
        }
        // 背景用 background 层：ignoresSafeArea 不会撑大布局，否则上下两条栏会被挤出窗口。
        .background { backdrop }
        .overlay(alignment: .bottomLeading) {
            if theme.flavor == .chiikawa {
                ChiikawaArtwork()
                    .frame(width: 158, height: 100)
                    .padding(.leading, 20)
                    .padding(.bottom, settings.showLyricsPlayerBar ? Self.lyricsBarHeight + 8 : 16)
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: Self.dragRecognitionDistance)
                .onEnded { value in
                    // 判断拖动方向和距离，满足条件时返回上一页。
                    dismissOnDrag(value.translation)
                }
        )
        .onAppear {
            engine.ensure(for: player.current)
            revealStage()
        }
        .onChange(of: player.current?.hash) { _, _ in engine.ensure(for: player.current) }
    }

    private func revealStage() {
        if settings.reduceMotion {
            stageReady = true
            return
        }
        stageReady = false
        withAnimation(.spring(response: 0.62, dampingFraction: 0.84).delay(0.08)) {
            stageReady = true
        }
    }

    // MARK: 背景

    private var backdrop: some View {
        ZStack {
            // 窗口级 Backdrop 已负责皮肤底色、纹理和透明度；这里只叠加播放页氛围，
            // 不再垫不透明纯色，否则透明模式会失效，顶部也会和页面主体断层。
            if settings.lyricsBackground == "cover", let cover = player.current?.cover {
                coverVeil(cover)
            }

            RadialGradient(
                colors: [theme.accent.opacity(theme.isDark ? 0.10 : 0.06), .clear],
                center: UnitPoint(x: 0.28, y: 0.46),
                startRadius: 40,
                endRadius: 760
            )

            LinearGradient(
                colors: [
                    .clear,
                    theme.solid.opacity((theme.isDark ? 0.22 : 0.10) * theme.backdropOpacity)
                ],
                startPoint: .center,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private func coverVeil(_ url: URL) -> some View {
        AsyncImage(url: url) { phase in
            if let img = phase.image {
                img.resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 96, opaque: true)
                    .saturation(theme.isDark ? 1.0 : 0.5)
                    .scaleEffect(1.25)
                    .opacity(theme.isDark ? 0.09 : 0.05)
            }
        }
        .overlay {
            Rectangle().fill(theme.accent.opacity(theme.isDark ? 0.05 : 0.03))
        }
    }

    // MARK: 主体

    private func stage(available: CGFloat, width: CGFloat) -> some View {
        let disc = min(560, max(210, min(available * 0.82, width * 0.40)))
        return HStack(alignment: .center, spacing: min(56, max(28, width * 0.04))) {
            vinylButton(side: disc)
                .scaleEffect(stageReady ? 1 : 0.9)
                .opacity(stageReady ? 1 : 0.28)
                .frame(maxWidth: .infinity)
            lyricsColumn
                .offset(y: stageReady ? 0 : 18)
                .opacity(stageReady ? 1 : 0)
                .frame(minWidth: 240, maxWidth: 560)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, max(48, width * 0.06))
        .padding(.bottom, settings.showLyricsPlayerBar ? 28 : 8)
    }

    private func vinylButton(side: CGFloat) -> some View {
        let spin = settings.lyricsSpinCover && !settings.reduceMotion
        return Button {
            // 收起播放页并返回之前的界面。
            closeLyrics()
        } label: {
            VinylRecord(
                url: player.current?.cover,
                seed: player.current?.id ?? "",
                side: side,
                spin: spin,
                playing: player.isPlaying
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击唱片返回")
        .accessibilityLabel("返回")
        .accessibilityHint("收起播放页")
    }

    // 使用统一的动画收起播放页。
    private func closeLyrics() {
        withAnimation(PlayerMotion.lyricsAnimation(reduceMotion: settings.reduceMotion)) {
            model.showLyrics = false
        }
    }

    // 向下拖动达到阈值且以纵向为主时收起播放页。
    private func dismissOnDrag(_ translation: CGSize) {
        guard translation.height >= Self.dismissDragDistance,
              translation.height > abs(translation.width) * Self.dismissVerticalRatio else { return }
        // 复用封面的返回动作和页面动画。
        closeLyrics()
    }

    private var lyricsColumn: some View {
        lyricsList
            .frame(maxHeight: .infinity)
    }

    private var lyricsList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: settings.lyricsAlign == .center ? .center : .leading, spacing: 0) {
                    if loading && lines.isEmpty {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.accent)
                            .padding(.top, 40)
                    } else if lines.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("暂无歌词")
                                .font(.system(size: 15))
                                .foregroundStyle(theme.textMuted)
                            if let lyricError = engine.errorText {
                                Text(lyricError)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textMuted.opacity(0.8))
                                    .lineLimit(3)
                            }
                        }
                        .padding(.top, 40)
                    } else {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            lyricLine(line, index: index)
                                .id(index)
                        }
                    }
                }
                .padding(.vertical, 200)
                .padding(.bottom, settings.showLyricsPlayerBar ? 56 : 0)
                .frame(maxWidth: .infinity, alignment: settings.lyricsAlign == .center ? .center : .leading)
            }
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: settings.showLyricsPlayerBar ? 0.70 : 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }
            .onChange(of: currentIndex) { _, idx in
                guard let idx else { return }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
            .onAppear {
                if let idx = currentIndex {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
    }

    private func lyricLine(_ line: MusicAPI.LyricLine, index: Int) -> some View {
        let active = index == currentIndex
        let distance = abs(index - (currentIndex ?? index))
        let fade: Double = {
            if active { return 1 }
            switch distance {
            case 1: return 0.50
            case 2: return 0.36
            case 3: return 0.28
            default: return 0.20
            }
        }()
        let centered = settings.lyricsAlign == .center
        let size = settings.lyricsFontSize * (active ? 1.22 : 1)
        return Text(line.text)
            .font(.system(size: size, weight: active ? .semibold : .regular))
            .foregroundStyle(active ? theme.textStrong : theme.textSecondary.opacity(fade))
            .multilineTextAlignment(centered ? .center : .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, active ? 9 : 7)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                player.seek(to: line.time)
            }
            .animation(settings.reduceMotion ? nil : .easeOut(duration: 0.28), value: active)
    }

    // MARK: 播放栏

    private var currentLiked: Bool {
        guard let song = player.current else { return false }
        return model.likes.isLiked(song)
    }

    private var lyricsPlayerBar: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 2) {
                lyricsBarControls
                Text(lyricsBarTitle)
                    .font(theme.titleFont(13, weight: .regular))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .padding(.leading, 10)
                    .frame(minWidth: 148, maxWidth: 260, alignment: .leading)
                    .layoutPriority(1)
                Spacer(minLength: 12)
                lyricsBarSeek
                    .layoutPriority(0)
            }
            .frame(maxWidth: .infinity)

            lyricsBarTransport

            lyricsBarTrailing
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 28)
        .frame(height: Self.lyricsBarHeight)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [
                    .clear,
                    theme.solid.opacity((theme.isDark ? 0.18 : 0.06) * max(theme.backdropOpacity, 0.4)),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 96)
            .allowsHitTesting(false)
        }
    }

    private var lyricsBarControls: some View {
        HStack(spacing: 2) {
            IconButton(size: 32, radius: 9, muted: true) {
                closeLyrics()
            } content: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .medium))
            }
            .help("收起播放页")
            .accessibilityLabel("返回")
            .accessibilityHint("收起播放页")

            IconButton(size: 32, radius: 9, muted: true,
                       disabled: player.current == nil,
                       tint: currentLiked ? theme.like : nil) {
                Task { await toggleLike() }
            } content: {
                Image(systemName: currentLiked ? "heart.fill" : "heart")
                    .font(.system(size: 15, weight: currentLiked ? .regular : .light))
                    .contentTransition(.symbolEffect(.replace))
            }
            .help(currentLiked ? "取消喜欢" : "加入我喜欢")

            IconButton(size: 32, radius: 9, muted: true, disabled: true) {
            } content: {
                Image(systemName: "bubble.left")
                    .font(.system(size: 15, weight: .light))
            }
        }
    }

    private var lyricsBarTitle: String {
        let name = player.current?.name ?? "未在播放"
        let artist = player.current?.artist ?? ""
        if artist.isEmpty { return name }
        if name.contains(artist) { return name }
        return "\(name) - \(artist)"
    }

    private var lyricsBarSeek: some View {
        HStack(spacing: 8) {
            Text(timeText(player.progress))
                .foregroundStyle(theme.textMuted)
                .frame(width: 40, alignment: .trailing)
            lyricsSeekRail
                .frame(width: 148, height: 22)
            Text(timeText(player.duration))
                .foregroundStyle(theme.textMuted)
                .frame(width: 40, alignment: .leading)
        }
        .font(.system(size: 11).monospacedDigit())
    }

    private var lyricsBarTransport: some View {
        HStack(spacing: 6) {
            IconButton(size: 32, radius: 16, muted: false, disabled: !player.canGoPrevious) {
                player.previous()
            } content: {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
            }

            LyricsPlayButton(playing: player.isPlaying) {
                player.togglePlayPause()
            }

            IconButton(size: 32, radius: 16, muted: false, disabled: !player.canGoNext) {
                player.next()
            } content: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
            }

            LyricsVolumeButton()
        }
    }

    private var lyricsSeekRail: some View {
        GeometryReader { geo in
            let ratio: CGFloat = player.duration > 0
                ? min(1, max(0, CGFloat(player.progress / player.duration)))
                : 0
            LyricsSeekBar(ratio: ratio, dragging: draggingProgress, playing: player.isPlaying)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard player.duration > 0 else { return }
                            draggingProgress = true
                            let r = min(1, max(0, value.location.x / geo.size.width))
                            player.seek(to: player.duration * Double(r))
                        }
                        .onEnded { _ in draggingProgress = false }
                )
        }
        .modifier(ProgressTimeHover(duration: player.duration))
    }

    private var lyricsBarTrailing: some View {
        HStack(spacing: 4) {
            Text("标准")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(theme.chip.opacity(0.7)))

            IconButton(size: 32, radius: 9, active: DesktopLyricsController.shared.isVisible, muted: true) {
                DesktopLyricsController.shared.toggle()
            } content: {
                Text("词")
                    .font(.system(size: 14, weight: .medium))
            }
            .help(DesktopLyricsController.shared.isVisible ? "关闭桌面歌词" : "打开桌面歌词")

            IconButton(size: 32, radius: 9, active: model.showQueue, muted: true) {
                model.showQueue.toggle()
            } content: {
                Image(systemName: "music.note.list")
                    .font(.system(size: 15, weight: .light))
            }
            .help("播放列表")
        }
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

    private func timeText(_ t: TimeInterval) -> String {
        guard t.isFinite, t > 0 else { return "00:00" }
        let s = Int(t)
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

}

private struct LyricsPlayButton: View {
    @Environment(\.theme) private var theme
    let playing: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(theme.accentStrong)
                    .frame(width: 40, height: 40)
                PlayPauseGlyph(playing: playing, size: 15, color: .white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playing ? "暂停" : "播放")
        .hoverLift(active: hovering, amount: 1.08)
        .onHover { hovering = $0 }
        .shadow(color: theme.accent.opacity(hovering ? 0.45 : 0.22), radius: hovering ? 12 : 6)
    }
}

private struct LyricsVolumeButton: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        @Bindable var player = model.player
        Button {
            player.volume = player.volume > 0 ? 0 : 0.8
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(theme.textSecondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(player.volume > 0 ? "静音" : "取消静音")
        .overlay(alignment: .top) {
            if hovering {
                Slider(value: $player.volume, in: 0...1)
                    .controlSize(.mini)
                    .tint(theme.accentStrong)
                    .frame(width: 84)
                    .offset(y: -22)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.16)) { self.hovering = hovering }
        }
    }

    private var iconName: String {
        switch model.player.volume {
        case 0: return "speaker.slash"
        case ..<0.35: return "speaker"
        case ..<0.7: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }
}

private struct LyricsSeekBar: View {
    @Environment(\.theme) private var theme
    let ratio: CGFloat
    let dragging: Bool
    let playing: Bool
    @State private var hovering = false

    private var lifted: Bool { hovering || dragging }
    private var thickness: CGFloat { lifted ? 4 : 3 }

    var body: some View {
        GeometryReader { geo in
            let width = max(0, geo.size.width * ratio)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.isDark ? Color.white.opacity(0.16) : theme.playerRail)
                    .frame(height: thickness)
                Capsule()
                    .fill(theme.accentStrong)
                    .frame(width: max(width, thickness), height: thickness)
                    .shadow(color: theme.accent.opacity(playing ? 0.45 : 0.18), radius: playing ? 4 : 0)
                if lifted {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 10, height: 10)
                        .shadow(color: .black.opacity(0.22), radius: 2, y: 1)
                        .offset(x: max(0, width - 5))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .animation(.easeOut(duration: 0.14), value: lifted)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
    }
}

// 描述播放页两侧切歌控件的方向与图标。
private enum TrackNavigationDirection {
    case previous
    case next

    var label: String { self == .previous ? "上一首" : "下一首" }
    var symbol: String { self == .previous ? "backward.end.fill" : "forward.end.fill" }
    var hiddenOffset: CGFloat { self == .previous ? -12 : 12 }
}

// 鼠标进入页面边缘时平滑显示切歌按钮。
private struct TrackNavigationControl: View {
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    @FocusState private var focused: Bool

    let direction: TrackNavigationDirection
    let enabled: Bool
    let width: CGFloat
    let height: CGFloat
    let action: () -> Void

    private var visible: Bool { hovering || focused }
    private var allowsMotion: Bool { theme.allowsMotion && !reduceMotion }

    var body: some View {
        ZStack {
            Color.clear
            Button(action: action) {
                Image(systemName: direction.symbol)
                    .font(.system(size: 34, weight: .medium))
                    .foregroundStyle(theme.accentStrong)
                    .shadow(color: theme.isDark ? .black.opacity(0.7) : theme.solid.opacity(0.85), radius: 8)
                    .opacity(visible ? (enabled ? 1 : 0.35) : 0)
                    .offset(x: allowsMotion && !visible ? direction.hiddenOffset : 0)
                    .scaleEffect(allowsMotion && !visible ? 0.88 : 1)
                    .animation(allowsMotion ? .easeOut(duration: 0.24) : nil, value: visible)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .focused($focused)
            .accessibilityLabel(direction.label)
            .help(enabled ? direction.label : "播放列表中没有可切换的歌曲")
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}
