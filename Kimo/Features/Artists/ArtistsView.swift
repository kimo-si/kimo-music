//
//  ArtistsView.swift
//  Kimo
//
//  歌手目录 + 歌手详情。版式沿用 cocomusic 的圆形头像栅格与详情头图。
//

import Observation
import SwiftUI

struct ArtistsView: View {
    @State private var state = HotArtistsState()

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: "歌手", subtitle: "酷狗热门歌手")

                HotArtistsContent(state: state)
            }
            .pagePadding()
        }
    }
}

// 管理热门歌手的加载状态，供首页和歌手目录复用。
@MainActor
@Observable
final class HotArtistsState {
    private static let artistLimit = 30
    private(set) var artists: [Artist] = []
    private(set) var loading = false
    private(set) var errorText: String?
    private var hasLoaded = false

    // 首次显示时加载，切换标签后复用已获取的歌手。
    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        // 调用统一的热门歌手加载流程。
        await reload()
    }

    // 加载热门歌手，失败后保留可重试状态。
    func reload() async {
        guard !loading else { return }
        loading = true
        errorText = nil
        defer { loading = false }
        do {
            // 从音乐核心读取热门歌手。
            artists = try await MusicAPI.shared.hotArtists(limit: Self.artistLimit)
            hasLoaded = true
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// 统一展示热门歌手列表和加载、错误、空状态。
struct HotArtistsContent: View {
    @Environment(\.theme) private var theme
    let state: HotArtistsState

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 24, alignment: .top), count: 6)

    var body: some View {
        Group {
            if state.loading && state.artists.isEmpty {
                skeletonGrid
            } else if let error = state.errorText, state.artists.isEmpty {
                InlineError(text: error) { Task { await state.reload() } }
            } else if state.artists.isEmpty {
                EmptyHint(icon: "music.mic", text: "暂时没有热门歌手")
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
                    ForEach(state.artists) { artist in
                        ArtistCardView(artist: artist)
                    }
                }
            }
        }
        .task {
            // 在栏目首次出现时加载热门歌手。
            await state.loadIfNeeded()
        }
    }

    private var skeletonGrid: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 24) {
            ForEach(0..<18, id: \.self) { _ in
                VStack(spacing: 10) {
                    Circle().fill(theme.chip).aspectRatio(1, contentMode: .fit)
                    SkeletonBlock(radius: 4).frame(height: 12).padding(.horizontal, 16)
                }
            }
        }
    }
}

// MARK: - 卡片

struct ArtistCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let artist: Artist

    @State private var hovering = false

    var body: some View {
        Button {
            // 打开选中歌手的详情页。
            model.navigate(.artist(id: artist.id, title: artist.name))
        } label: {
            VStack(spacing: 10) {
                avatar
                Text(artist.name)
                    .font(.system(size: 13))
                    .foregroundStyle(hovering ? theme.accentStrong : theme.textStrong)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(artist.name)，查看歌手详情")
        .onHover { hovering = $0 }
    }

    private var avatar: some View {
        ZStack {
            if let url = artist.avatar {
                CoverImage(url: url, radius: 999, seed: artist.id)
                    .scaleEffect(hovering ? 1.05 : 1)
                    .animation(theme.allowsMotion ? .spring(response: 0.42, dampingFraction: 0.85) : nil,
                               value: hovering)
            } else {
                Circle()
                    .fill(theme.chip)
                    .overlay {
                        Image(systemName: "music.mic")
                            .font(.system(size: 22, weight: .light))
                            .foregroundStyle(theme.textMuted)
                    }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(Circle())
        .shadow(color: .black.opacity(hovering ? 0.18 : 0.08),
                radius: hovering ? 14 : 8, y: hovering ? 8 : 4)
    }
}

// MARK: - 详情

struct ArtistDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    let id: String
    let title: String

    @State private var profile: MusicAPI.ArtistProfile?
    @State private var hot: [Song] = []
    @State private var latest: [Song] = []
    @State private var sort = "hot"
    @State private var loading = true
    @State private var expanded = false

    private var songs: [Song] { sort == "hot" ? hot : latest }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 22) {
                header
                if loading {
                    VStack(spacing: 4) {
                        ForEach(0..<8, id: \.self) { _ in
                            SkeletonBlock(radius: 8).frame(height: 52)
                        }
                    }
                    .padding(.horizontal, 10)
                } else {
                    TabBar(items: ["热门歌曲", "最新发布"], value: Binding(
                        get: { sort == "hot" ? "热门歌曲" : "最新发布" },
                        set: { sort = $0 == "热门歌曲" ? "hot" : "new" }
                    ))
                    .padding(.top, -8)

                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongRowView(song: song, index: index + 1, queue: songs, source: .artist(id: id, title: title))
                        }
                    }
                }
            }
            .pagePadding()
        }
        .task(id: id) { await load() }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 22) {
            ZStack {
                if let url = profile?.avatar {
                    CoverImage(url: url, radius: 999, seed: id)
                } else {
                    Circle().fill(theme.chip)
                        .overlay {
                            Image(systemName: "music.mic")
                                .font(.system(size: 34, weight: .ultraLight))
                                .foregroundStyle(theme.textMuted)
                        }
                }
            }
            .frame(width: 148, height: 148)
            .clipShape(Circle())
            .shadow(color: .black.opacity(0.16), radius: 16, y: 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(profile?.name ?? title)
                    .font(theme.titleFont(26))
                    .foregroundStyle(theme.textStrong)
                    .lineLimit(1)

                HStack(spacing: 14) {
                    if let p = profile {
                        metaItem("粉丝", formatCount(p.fans))
                        metaItem("专辑", "\(p.albumCount)")
                        metaItem("MV", "\(p.mvCount)")
                    }
                }

                if let intro = profile?.intro, !intro.isEmpty {
                    Text(intro)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(expanded ? nil : 2)
                        .fixedSize(horizontal: false, vertical: true)
                        .onTapGesture { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } }
                }

                HStack(spacing: 10) {
                    Button {
                        if let first = songs.first { model.player.play(first, queue: songs, source: .artist(id: id, title: title)) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.fill").font(.system(size: 12))
                            Text("播放热门").font(.system(size: 13))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .frame(height: 34)
                        .background(Capsule().fill(theme.accentStrong))
                    }
                    .buttonStyle(.plain)
                    .disabled(songs.isEmpty)
                    .padding(.top, 4)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func metaItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(theme.textStrong)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(theme.textMuted)
        }
    }

    private func load() async {
        loading = true
        async let p = try? MusicAPI.shared.artistProfile(id: id)
        async let h = try? MusicAPI.shared.artistSongs(id: id, size: 50, hot: true)
        async let l = try? MusicAPI.shared.artistSongs(id: id, size: 50, hot: false)
        profile = await p
        hot = await h ?? []
        latest = await l ?? []
        loading = false
    }
}
