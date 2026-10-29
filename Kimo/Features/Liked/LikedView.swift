//
//  LikedView.swift
//  Kimo
//
//  侧栏「我喜欢」：内容来自酷狗账号的同名歌单。
//

import SwiftUI

struct LikedView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme

    private var likes: LikeStore { model.likes }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(
                    title: "我喜欢",
                    subtitle: subtitle,
                    cover: likes.songs.first?.cover
                ) {
                    if auth.isLoggedIn, !likes.songs.isEmpty {
                        Button {
                            if let first = likes.songs.first {
                                model.player.play(first, queue: likes.songs)
                            }
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
                    }
                }

                content
            }
            .pagePadding()
        }
        .task(id: auth.isLoggedIn) {
            guard auth.isLoggedIn else { return }
            await likes.refresh()
        }
    }

    private var subtitle: String {
        if !auth.isLoggedIn { return "登录后和酷狗的「我喜欢」同步" }
        if likes.loading, likes.songs.isEmpty { return "正在同步…" }
        if likes.songs.isEmpty { return "还没有喜欢的歌" }
        return "共 \(likes.songs.count) 首 · 已同步酷狗"
    }

    @ViewBuilder
    private var content: some View {
        if !auth.isLoggedIn {
            EmptyHint(icon: "heart", text: "登录酷狗账号后，点播放栏的爱心就会加入这里")
        } else if likes.loading, likes.songs.isEmpty {
            VStack(spacing: 4) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonBlock(radius: 8).frame(height: 52)
                }
            }
            .padding(.horizontal, 10)
        } else if let errorText = likes.errorText, likes.songs.isEmpty {
            InlineError(text: errorText) { Task { await likes.refresh() } }
        } else if likes.songs.isEmpty {
            EmptyHint(icon: "heart", text: "播放时点爱心，歌曲会写入酷狗的「我喜欢」")
        } else {
            LazyVStack(spacing: 2) {
                ForEach(Array(likes.songs.enumerated()), id: \.element.hash) { index, song in
                    SongRowView(song: song, index: index + 1, queue: likes.songs)
                }
            }
        }
    }
}
