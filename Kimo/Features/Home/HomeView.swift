//
//  HomeView.swift
//  Kimo
//
//  「发现好音乐」：推荐歌单 6 列 / 推荐歌曲 3 列 / 热门榜单 2 列。
//  栅格与间距来自 Home.module.css。
//

import Observation
import SwiftUI

private enum HomeTab: String, CaseIterable {
    case featured = "精选"
    case newSongs = "新歌速递"
    case hotArtists = "热门歌手"
}

struct ChartSection: Identifiable, Hashable {
    let rank: Rank
    let songs: [Song]
    var id: String { rank.id }
}

struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    @State private var tab: HomeTab = .featured
    @State private var newSongsState = NewSongsState()
    @State private var hotArtistsState = HotArtistsState()
    @State private var playlists: [Playlist] = []
    @State private var songs: [Song] = []
    @State private var charts: [ChartSection] = []
    @State private var loading = true
    @State private var errorText: String?

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: 6)

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 24) {
                header
                TabBar(items: HomeTab.allCases.map(\.rawValue), value: Binding(
                    get: { tab.rawValue },
                    set: { if let selected = HomeTab(rawValue: $0) { tab = selected } }
                ))
                    .padding(.top, -10)

                switch tab {
                case .featured:
                    if let errorText { errorState(errorText) } else { featured }
                case .newSongs:
                    NewSongsView(state: newSongsState)
                case .hotArtists:
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(title: "热门歌手")
                        HotArtistsContent(state: hotArtistsState)
                    }
                }
            }
            .padding(.top, 22)
            .padding(.horizontal, 28)
            .padding(.bottom, 32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .offset(y: -model.debugScroll)
        }
        .task { await load() }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top) {
                Text("发现好音乐")
                    .font(theme.titleFont(26))
                .foregroundStyle(theme.textStrong)
            Spacer(minLength: 24)
            Button {
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 12, weight: .regular))
                    Text("导入歌单").font(.system(size: 13))
                }
                .foregroundStyle(theme.textStrong)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(theme.chip)
                    RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(theme.glassEdge, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: Featured

    private var featured: some View {
        VStack(alignment: .leading, spacing: 28) {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "推荐歌单", actionLabel: "歌单广场") {
                    model.navigate(.discover)
                }
                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    if loading {
                        ForEach(0..<12, id: \.self) { _ in skeletonCard }
                    } else {
                        ForEach(playlists) { playlist in
                            PlaylistCardView(playlist: playlist)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "推荐歌曲", actionLabel: "播放全部") {
                    if let first = songs.first { model.player.play(first, queue: songs) }
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16, alignment: .top), count: 3),
                          alignment: .leading, spacing: 4) {
                    if loading {
                        ForEach(0..<9, id: \.self) { _ in SkeletonBlock(radius: 10).frame(height: 48) }
                    } else {
                        ForEach(songs.prefix(9)) { song in
                            TrackTileView(song: song, queue: songs)
                        }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "热门榜单", actionLabel: "查看全部") {
                    model.navigate(.charts)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: 2),
                          alignment: .leading, spacing: 24) {
                    if loading {
                        ForEach(0..<2, id: \.self) { _ in
                            SkeletonBlock(radius: Metrics.radiusCard).frame(height: 160)
                        }
                    } else {
                        ForEach(charts) { section in
                            ChartCardView(chart: section.rank, songs: section.songs)
                        }
                    }
                }
            }
        }
    }

    private var skeletonCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            SkeletonBlock(radius: Metrics.radiusCover)
                .aspectRatio(1, contentMode: .fit)
            SkeletonBlock(radius: 4).frame(height: 12).padding(.trailing, 20)
            SkeletonBlock(radius: 4).frame(width: 60, height: 10)
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(theme.textMuted)
            Text("内容加载失败")
                .font(.system(size: 14))
                .foregroundStyle(theme.textStrong)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(theme.textSecondary)
            Button("重试") { Task { await load() } }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(theme.accentStrong)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Capsule().fill(theme.accentSoft))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 80)
    }

    // MARK: Load

    private func load() async {
        guard CoreService.shared.isReady || true else { return }
        loading = true
        errorText = nil
        do {
            async let pl = MusicAPI.shared.featuredPlaylists()
            async let sg = MusicAPI.shared.recommendedSongs()
            async let ch = MusicAPI.shared.charts(limit: 2)

            playlists = try await pl
            songs = try await sg
            let ranks = try await ch

            // 补齐曲目数：卡片上的「N首」来自 /playlist/detail 的 count，一次批量取。
            if let counts = try? await MusicAPI.shared.playlistCounts(ids: playlists.map(\.id)) {
                playlists = playlists.map { item in
                    var copy = item
                    if let n = counts[item.id] { copy.trackCount = n }
                    return copy
                }
            }

            var sections: [ChartSection] = []
            for rank in ranks {
                let list = (try? await MusicAPI.shared.rankTracks(rankId: rank.id, size: 6)) ?? []
                sections.append(ChartSection(rank: rank, songs: list))
            }
            charts = sections
        } catch {
            errorText = error.localizedDescription
        }
        loading = false
    }
}

// 管理新歌分页、去重和请求状态，切换首页标签时保留已加载内容。
@MainActor
@Observable
private final class NewSongsState {
    private static let pageSize = 30
    private(set) var songs: [Song] = []
    private(set) var loading = false
    private(set) var hasMore = true
    private(set) var errorText: String?
    private var nextPage = 1

    // 首次进入新歌页时加载数据，已加载过的内容直接复用。
    func loadIfNeeded() async {
        guard nextPage == 1, songs.isEmpty else { return }
        // 从第一页请求新歌。
        await loadMore()
    }

    // 请求下一页并保留已有歌曲，失败后允许重试。
    func loadMore() async {
        guard !loading, hasMore else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            // 调用新歌接口，随后合并去重后的歌曲。
            let page = try await MusicAPI.shared.newSongs(page: nextPage, size: Self.pageSize)
            let added = appendUnique(page.songs)
            hasMore = page.hasMore && added > 0
            nextPage += 1
        } catch {
            errorText = error.localizedDescription
        }
    }

    // 保持接口原有顺序，避免跨页重复歌曲。
    private func appendUnique(_ incoming: [Song]) -> Int {
        var known = Set(songs.map { $0.hash.lowercased() })
        let unique = incoming.filter { known.insert($0.hash.lowercased()).inserted }
        songs.append(contentsOf: unique)
        return unique.count
    }
}

// 展示新歌速递及其分页、空状态和播放入口。
private struct NewSongsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let state: NewSongsState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 20, alignment: .top), count: 2)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionHeader(title: "新歌速递", actionLabel: state.songs.isEmpty ? nil : "播放全部") {
                // 用当前已加载的新歌建立播放队列。
                playAll()
            }
            content
        }
        .task {
            // 首次打开栏目时加载新歌。
            await state.loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if state.loading && state.songs.isEmpty {
            loadingSkeleton
        } else if let error = state.errorText, state.songs.isEmpty {
            InlineError(text: error) { Task { await state.loadMore() } }
        } else if state.songs.isEmpty {
            EmptyHint(icon: "music.note.list", text: "暂时没有新歌")
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 4) {
                ForEach(Array(state.songs.enumerated()), id: \.element.id) { index, song in
                    SongRowView(song: song, index: index + 1, queue: state.songs)
                }
            }
            pageFooter
        }
    }

    private var loadingSkeleton: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(0..<8, id: \.self) { _ in
                SkeletonBlock(radius: 8).frame(height: 52)
            }
        }
    }

    @ViewBuilder
    private var pageFooter: some View {
        if state.loading {
            ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.vertical, 16)
        } else if let error = state.errorText {
            InlineError(text: error) { Task { await state.loadMore() } }
        } else if state.hasMore {
            Button("加载更多") { Task { await state.loadMore() } }
                .buttonStyle(.plain)
                .foregroundStyle(theme.accentStrong)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
        }
    }

    // 从第一首开始播放已加载的新歌。
    private func playAll() {
        guard let first = state.songs.first else { return }
        // 将已加载的歌曲交给播放器作为队列。
        model.player.play(first, queue: state.songs)
    }
}
