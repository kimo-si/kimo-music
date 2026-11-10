import SwiftUI

// 小窗下半部只展示当前歌曲的来源列表，搜索不会缩减实际播放队列。
struct MiniSourceList: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var context: PlaybackContext { model.player.playbackContext }
    private var songs: [Song] { context.resolvedSongs(likedSongs: model.likes.songs) }
    private var visibleSongs: [Song] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return songs }
        return songs.filter { $0.name.localizedStandardContains(keyword) || $0.artist.localizedStandardContains(keyword) }
    }

    var body: some View {
        VStack(spacing: 10) {
            header
            if searching { searchField }
            if let notice = model.player.notice { noticeView(notice) }
            content
            footer
        }
        .onChange(of: context.source) { _, _ in
            query = ""
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: context.source.symbol)
                .foregroundStyle(theme.accentStrong)
                .accessibilityHidden(true)
            Text(context.source.title)
                .font(theme.titleFont(14, weight: .medium))
                .foregroundStyle(theme.textStrong)
                .lineLimit(1)
                .help(context.source.title)
            Spacer(minLength: 8)
            HStack(spacing: 3) {
                IconButton(size: 28, active: searching, action: beginSearch) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14))
                }
                .help("搜索当前列表")
                .accessibilityLabel("搜索当前列表")
                IconButton(size: 28, active: !searching, action: showAll) {
                    Image(systemName: "music.note.list").font(.system(size: 15))
                }
                .help("显示全部歌曲")
                .accessibilityLabel("显示全部歌曲")
            }
            .padding(3)
            .modifier(ThemedSurface(radius: theme.controls.fieldRadius))
        }
        .font(.system(size: 13))
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.textMuted)
            TextField("搜索歌曲或歌手", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .onExitCommand(perform: showAll)
                .accessibilityLabel("搜索当前来源列表")
            Button("清除搜索", systemImage: "xmark.circle.fill") { query = "" }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(theme.textMuted)
                .opacity(query.isEmpty ? 0 : 1)
                .disabled(query.isEmpty)
        }
        .font(.system(size: 13))
        .foregroundStyle(theme.textStrong)
        .padding(10)
        .modifier(ThemedSurface(role: .field))
    }

    @ViewBuilder
    private var content: some View {
        if context.source == .liked && !auth.isLoggedIn {
            emptyState("登录后查看我喜欢", symbol: "heart")
        } else if songs.isEmpty, context.source == .liked, model.likes.loading {
            ProgressView("正在同步我喜欢…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if songs.isEmpty, context.source == .liked, let error = model.likes.errorText {
            InlineError(text: error) { Task { await model.likes.refresh() } }
                .frame(maxHeight: .infinity)
        } else if visibleSongs.isEmpty {
            emptyState(query.isEmpty ? "从歌单或我喜欢中播放一首歌" : "没有找到匹配的歌曲", symbol: "music.note")
        } else {
            songList
        }
    }

    private var songList: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(visibleSongs.enumerated()), id: \.offset) { index, song in
                        MiniSourceRow(song: song, isCurrent: model.player.current?.matches(song) == true) {
                            play(song)
                        }
                        .id(song.id)
                        .id(index)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .onAppear { revealCurrent(in: proxy) }
            .onChange(of: model.player.current?.id) { _, _ in revealCurrent(in: proxy) }
            .onChange(of: context.source) { _, _ in revealCurrent(in: proxy) }
            .onChange(of: query) { _, _ in proxy.scrollTo(0, anchor: .top) }
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text(query.isEmpty ? "\(songs.count) 首歌曲" : "\(visibleSongs.count) / \(songs.count) 首歌曲")
            Spacer()
            if model.player.isLoadingStream {
                ProgressView().controlSize(.mini)
                Text("正在加载音频…")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.textMuted)
        .frame(height: 18)
    }

    // 小窗内展示播放或收藏错误，登录操作先恢复可容纳登录框的完整窗口。
    private func noticeView(_ notice: String) -> some View {
        HStack(spacing: 8) {
            Text(notice).lineLimit(2)
            Spacer(minLength: 0)
            if model.player.noticeNeedsLogin {
                Button("登录", action: openLogin).buttonStyle(.plain).foregroundStyle(theme.accentStrong)
            }
            Button("关闭提示", systemImage: "xmark") { model.player.notice = nil }
                .labelStyle(.iconOnly).buttonStyle(.plain)
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.textSecondary)
        .padding(10)
        .background(theme.chip, in: RoundedRectangle(cornerRadius: theme.radiusRow))
    }

    // 空状态保留可读提示，并提供回到完整窗口选歌的入口。
    private func emptyState(_ title: String, symbol: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light))
            Text(title).font(.system(size: 13))
            Button("打开音乐库") { model.setMini(false) }
                .buttonStyle(.plain).foregroundStyle(theme.accentStrong)
        }
        .foregroundStyle(theme.textMuted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // 点击搜索后聚焦输入框，搜索范围固定在当前来源列表。
    private func beginSearch() {
        searching = true
        searchFocused = true
    }

    // 退出筛选并显示完整来源列表。
    private func showAll() {
        searching = false
        query = ""
        searchFocused = false
    }

    // 从筛选结果点歌时仍将完整来源列表作为队列。
    private func play(_ song: Song) {
        model.player.play(song, queue: songs, source: context.source)
    }

    // 切歌时定位当前曲目；不重置正在使用的筛选条件。
    private func revealCurrent(in proxy: ScrollViewProxy) {
        guard let current = model.player.current,
              let index = visibleSongs.firstIndex(where: { $0.matches(current) }) else { return }
        proxy.scrollTo(index, anchor: .center)
    }

    // 登录弹窗沿用主界面流程，避免在小窗中被裁切。
    private func openLogin() {
        model.setMini(false)
        model.showLogin = true
    }
}
