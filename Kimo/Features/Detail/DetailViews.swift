//
//  DetailViews.swift
//  Kimo
//
//  搜索 / 歌单详情 / 榜单详情 / 排行榜 / 发现音乐 / 占位页。
//

import SwiftUI

// MARK: - Search

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let keyword: String

    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "搜索", subtitle: "“\(keyword)” 的歌曲结果")
                if loading {
                    VStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { _ in
                            SkeletonBlock(radius: 8).frame(height: 52)
                        }
                    }
                    .padding(.horizontal, 10)
                } else if let errorText {
                    InlineError(text: errorText) { Task { await load() } }
                } else if songs.isEmpty {
                    EmptyHint(icon: "magnifyingglass", text: "没有找到相关歌曲")
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongRowView(song: song, index: index + 1, queue: songs, source: .search(keyword: keyword))
                        }
                    }
                }
            }
            .pagePadding()
        }
        .task(id: keyword) { await load() }
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            songs = try await MusicAPI.shared.search(keyword, size: 40)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Playlist detail

struct PlaylistView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let id: String
    let title: String

    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: title,
                    subtitle: songs.isEmpty ? "正在加载…" : "共 \(songs.count) 首",
                    cover: songs.first?.cover
                ) {
                    Button {
                        if let first = songs.first { model.player.play(first, queue: songs, source: .playlist(id: id, title: title)) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12))
                            Text("播放全部").font(.system(size: 13))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(theme.accentStrong))
                    }
                    .buttonStyle(.plain)
                    .disabled(songs.isEmpty)
                }

                if loading {
                    VStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { _ in
                            SkeletonBlock(radius: 8).frame(height: 52)
                        }
                    }
                    .padding(.horizontal, 10)
                } else if let errorText {
                    InlineError(text: errorText) { Task { await load() } }
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongRowView(song: song, index: index + 1, queue: songs, source: .playlist(id: id, title: title))
                        }
                    }
                }
            }
            .pagePadding()
        }
        .task(id: id) { await load() }
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            songs = try await MusicAPI.shared.playlistTracks(id: id, size: 100)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Rank detail

struct RankView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let rankId: String
    let title: String

    @State private var songs: [Song] = []
    @State private var loading = true
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: title,
                    subtitle: songs.isEmpty ? "" : "共 \(songs.count) 首",
                    cover: songs.first?.cover
                ) {
                    Button {
                        if let first = songs.first { model.player.play(first, queue: songs, source: .rank(id: rankId, title: title)) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12))
                            Text("播放全部").font(.system(size: 13))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(theme.accentStrong))
                    }
                    .buttonStyle(.plain)
                    .disabled(songs.isEmpty)
                }

                if loading {
                    VStack(spacing: 4) {
                        ForEach(0..<10, id: \.self) { _ in
                            SkeletonBlock(radius: 8).frame(height: 52)
                        }
                    }
                    .padding(.horizontal, 10)
                } else if let errorText {
                    InlineError(text: errorText) { Task { await load() } }
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongRowView(song: song, index: index + 1, queue: songs, source: .rank(id: rankId, title: title))
                        }
                    }
                }
            }
            .pagePadding()
        }
        .task(id: rankId) { await load() }
    }

    private func load() async {
        loading = true
        errorText = nil
        do {
            songs = try await MusicAPI.shared.rankTracks(rankId: rankId, size: 100)
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

// MARK: - Charts

struct ChartsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var sections: [ChartSection] = []
    @State private var loading = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "排行榜", subtitle: "酷狗音乐榜单")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: 2),
                          alignment: .leading, spacing: 20) {
                    if loading {
                        ForEach(0..<4, id: \.self) { _ in
                            SkeletonBlock(radius: Metrics.radiusCard).frame(height: 170)
                        }
                    } else {
                        ForEach(sections) { section in
                            ChartCardView(chart: section.rank, songs: section.songs)
                        }
                    }
                }
            }
            .pagePadding()
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        var out: [ChartSection] = []
        if let ranks = try? await MusicAPI.shared.charts(limit: 8) {
            for rank in ranks {
                let list = (try? await MusicAPI.shared.rankTracks(rankId: rank.id, size: 5)) ?? []
                out.append(ChartSection(rank: rank, songs: list))
            }
        }
        sections = out
        loading = false
    }
}

// MARK: - Discover

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var playlists: [Playlist] = []
    @State private var loading = true
    @State private var page = 1

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: 6)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "发现音乐", subtitle: "按热度推荐的歌单")
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    if loading && playlists.isEmpty {
                        ForEach(0..<18, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: 8) {
                                SkeletonBlock(radius: Metrics.radiusCover).aspectRatio(1, contentMode: .fit)
                                SkeletonBlock(radius: 4).frame(height: 12)
                            }
                        }
                    } else {
                        ForEach(playlists) { playlist in
                            PlaylistCardView(playlist: playlist)
                        }
                    }
                }
                if !loading {
                    Button {
                        Task { await loadMore() }
                    } label: {
                        Text("加载更多")
                            .font(.system(size: 13))
                            .foregroundStyle(theme.accentStrong)
                            .padding(.horizontal, 20)
                            .frame(height: 36)
                            .background(Capsule().fill(theme.accentSoft))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
                }
            }
            .pagePadding()
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        playlists = (try? await MusicAPI.shared.featuredPlaylists(page: 1, size: 30)) ?? []
        loading = false
    }

    private func loadMore() async {
        page += 1
        loading = true
        let more = (try? await MusicAPI.shared.featuredPlaylists(page: page, size: 30)) ?? []
        let existing = Set(playlists.map(\.id))
        playlists.append(contentsOf: more.filter { !existing.contains($0.id) })
        loading = false
    }
}

// MARK: - Placeholder

struct PlaceholderView: View {
    @Environment(\.theme) private var theme
    let route: Route

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .ultraLight))
                .foregroundStyle(theme.textMuted)
            Text(route.title)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(theme.textStrong)
            Text("这个页面还没接上，下一步会按 cocomusic 的版式补齐。")
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch route {
        case .liked: return "heart"
        case .recent: return "clock.arrow.circlepath"
        case .local: return "externaldrive"
        case .downloads: return "arrow.down.to.line"
        case .artists: return "music.mic"
        case .settings: return "gearshape"
        default: return "square.grid.2x2"
        }
    }
}

// MARK: - Shared bits

struct PageHeader<Trailing: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let subtitle: String
    var cover: URL?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: 18) {
            if let cover {
                CoverImage(url: cover, radius: 12, seed: title)
                    .frame(width: 132, height: 132)
                    .shadow(color: .black.opacity(0.16), radius: 14, y: 8)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(theme.titleFont(26))
                    .foregroundStyle(theme.textStrong)
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            Spacer(minLength: 16)
            trailing()
        }
        .padding(.bottom, 6)
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String, cover: URL? = nil) {
        self.init(title: title, subtitle: subtitle, cover: cover) { EmptyView() }
    }
}

struct InlineError: View {
    @Environment(\.theme) private var theme
    let text: String
    var retry: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("加载失败：\(text)")
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Button("重试", action: retry)
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.accentStrong)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

struct EmptyHint: View {
    @Environment(\.theme) private var theme
    let icon: String
    let text: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24, weight: .ultraLight))
                .foregroundStyle(theme.textMuted)
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 80)
    }
}

extension View {
    func pagePadding() -> some View {
        padding(.top, 22)
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
