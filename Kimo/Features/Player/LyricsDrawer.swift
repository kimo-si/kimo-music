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
            if theme.flavor != .solid {
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
                .contentShape(Rectangle())
                .simultaneousGesture(dismissGesture)
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

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: Self.dragRecognitionDistance)
            .onEnded { dismissOnDrag($0.translation) }
    }

    // 向下拖动达到阈值且以纵向为主时收起播放页。
    private func dismissOnDrag(_ translation: CGSize) {
        guard translation.height >= Self.dismissDragDistance,
              translation.height > abs(translation.width) * Self.dismissVerticalRatio else { return }
        // 复用封面的返回动作和页面动画。
        closeLyrics()
    }

    @ViewBuilder
    private var lyricsColumn: some View {
        if !lines.isEmpty {
            PlaybackLyricsList(lines: lines, currentIndex: currentIndex,
                               centered: settings.lyricsAlign == .center,
                               fontSize: settings.lyricsFontSize,
                               timeLabel: { timeText(seekTime(for: $0)) }) { line in
                // 点击和拖动松手共用定位入口，保留播放器的播放或暂停状态。
                player.seek(to: seekTime(for: line))
            }
            .id(player.current?.id)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                if loading {
                    ProgressView().controlSize(.small).tint(theme.accent)
                } else {
                    Text("暂无歌词").font(.system(size: 15))
                    if let message = engine.errorText {
                        Text(message).font(.system(size: 11)).lineLimit(3)
                    }
                }
            }
            .foregroundStyle(theme.textMuted)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
    }

    /// 将歌词时间还原为播放器时间，兼容歌词偏移和歌曲首尾。
    private func seekTime(for line: MusicAPI.LyricLine) -> TimeInterval {
        let seconds = max(0, line.time - settings.lyricsOffset / 1000)
        return player.duration > 0 ? min(seconds, player.duration) : seconds
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

            ThemedPlayButton(playing: player.isPlaying, size: 40) {
                player.togglePlayPause()
            }

            IconButton(size: 32, radius: 16, muted: false, disabled: !player.canGoNext) {
                player.next()
            } content: {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 13, weight: .semibold))
            }

            ThemedVolumeControl()
        }
    }

    private var lyricsSeekRail: some View {
        GeometryReader { geo in
            let ratio: CGFloat = player.duration > 0
                ? min(1, max(0, CGFloat(player.progress / player.duration)))
                : 0
            ThemedProgress(ratio: ratio, dragging: draggingProgress, playing: player.isPlaying, compact: true)
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

// 记录每行的真实边界，长句换行或调整字号后仍能对准中心。
private struct LyricRowBounds: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] { [] }

    /// 按歌词顺序收集布局完成后的行边界。
    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value.append(contentsOf: nextValue())
    }
}

private struct LyricDragPreview {
    let centers: [CGFloat]
    let midpoint: CGFloat
    var offset: CGFloat = 0
    var index = 0

    /// 限制首尾拖动距离，并选择距视口中心最近的歌词。
    mutating func move(by translation: CGFloat) {
        guard let first = centers.first, let last = centers.last else { return }
        offset = min(midpoint - first, max(midpoint - last, translation))
        let target = midpoint - offset
        index = centers.indices.min { abs(centers[$0] - target) < abs(centers[$1] - target) } ?? 0
    }
}

private struct PlaybackLyricsList: View {
    @Namespace private var viewportSpace
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @GestureState private var translation: CGFloat?
    @State private var dragOrigin: LyricDragPreview?

    let lines: [MusicAPI.LyricLine]
    let currentIndex: Int?
    let centered: Bool
    let fontSize: CGFloat
    let timeLabel: (MusicAPI.LyricLine) -> String
    let seek: (MusicAPI.LyricLine) -> Void

    private var preview: LyricDragPreview? {
        guard var target = dragOrigin, let translation else { return nil }
        target.move(by: translation)
        return target
    }

    private var lineAnimation: Animation? {
        theme.allowsMotion && !systemReduceMotion ? .easeInOut(duration: 0.35) : nil
    }

    var body: some View {
        let selection = preview
        let focus = selection?.index ?? currentIndex
        return GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
                            row(line, index: index, focus: focus).id(index)
                        }
                    }
                    .padding(.vertical, viewport.size.height / 2)
                    .offset(y: selection?.offset ?? 0)
                    .overlayPreferenceValue(LyricRowBounds.self) { bounds in
                        gestureSurface(bounds, viewportHeight: viewport.size.height, proxy: proxy)
                    }
                }
                .coordinateSpace(name: viewportSpace)
                .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                     startPoint: .top, endPoint: .bottom))
                .onChange(of: currentIndex, initial: true) { old, index in
                    guard translation == nil, let index else { return }
                    // 手动拖动期间暂停跟随，正常播放时将新行平滑移到中心。
                    withAnimation(old == index ? nil : lineAnimation) { proxy.scrollTo(index, anchor: .center) }
                }
                .overlay(alignment: .bottom) { previewHint(selection?.index) }
            }
        }
    }

    /// 用视觉缩放和淡入淡出切换焦点，保持每行占用的布局高度稳定。
    private func row(_ line: MusicAPI.LyricLine, index: Int, focus: Int?) -> some View {
        let active = focus == index
        let distance = abs(index - (focus ?? 0))
        let opacity = active ? 1.0 : max(0.26, 0.62 - Double(distance) * 0.09)
        return Text(line.text)
            .font(.system(size: fontSize * 1.18, weight: .medium))
            .foregroundStyle(theme.textStrong)
            .multilineTextAlignment(centered ? .center : .leading)
            .scaleEffect(active ? 1 : 0.86, anchor: centered ? .center : .leading)
            .opacity(opacity)
            .animation(translation == nil ? lineAnimation : nil, value: focus)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            .anchorPreference(key: LyricRowBounds.self, value: .bounds) { [$0] }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { seek(line) }
    }

    /// 在固定视口内区分点击与拖动，拖动使用起始位置快照，不受歌词移动影响。
    private func gestureSurface(_ bounds: [Anchor<CGRect>], viewportHeight: CGFloat, proxy: ScrollViewProxy) -> some View {
        GeometryReader { geo in
            let drag = DragGesture(minimumDistance: 5)
                .updating($translation) { value, state, _ in
                    guard bounds.count == lines.count else { return }
                    if state == nil {
                        let midpoint = viewportHeight / 2 - geo.frame(in: .named(viewportSpace)).minY
                        dragOrigin = LyricDragPreview(centers: bounds.map { geo[$0].midY }, midpoint: midpoint)
                    }
                    state = value.translation.height
                }
                .onEnded { value in
                    // GestureState 在松手回调前可能已复位，使用按下时的快照完成定位。
                    guard var target = dragOrigin else { return }
                    dragOrigin = nil
                    target.move(by: value.translation.height)
                    // 松手后只定位一次，同时将选中的歌词对齐到中心。
                    select(target.index, proxy: proxy)
                }
            Color.clear.contentShape(Rectangle())
                .gesture(drag.exclusively(before: SpatialTapGesture().onEnded { tap in
                    if let index = bounds.firstIndex(where: { geo[$0].contains(tap.location) }) {
                        select(index, proxy: proxy)
                    }
                }))
                .accessibilityHidden(true)
        }
    }

    /// 同步视觉焦点和播放位置，包括停在同一行的情况。
    private func select(_ index: Int, proxy: ScrollViewProxy) {
        guard lines.indices.contains(index) else { return }
        proxy.scrollTo(index, anchor: .center)
        seek(lines[index])
    }

    /// 拖动时显示松手将要跳转的时间。
    @ViewBuilder private func previewHint(_ index: Int?) -> some View {
        if let index, lines.indices.contains(index) {
            Text("\(timeLabel(lines[index]))  ·  松开跳转")
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.textStrong)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Capsule().fill(theme.chip))
                .padding(.bottom, 16)
                .allowsHitTesting(false)
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
