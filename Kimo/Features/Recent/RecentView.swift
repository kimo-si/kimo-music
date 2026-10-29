//
//  RecentView.swift
//  Kimo
//
//  最近播放：本机历史，点行播放整段历史，右上角可清空。
//

import SwiftUI

struct RecentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private var songs: [Song] { model.recent.songs }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(title: "最近播放",
                           subtitle: songs.isEmpty ? "还没有播放记录" : "共 \(songs.count) 首") {
                    HStack(spacing: 10) {
                        if !songs.isEmpty {
                            Button {
                                if let first = songs.first { model.player.play(first, queue: songs) }
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

                            Button {
                                model.recent.clear()
                            } label: {
                                Text("清空")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.textSecondary)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(Capsule().fill(theme.chip))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if songs.isEmpty {
                    EmptyHint(icon: "clock.arrow.circlepath", text: "播放过的歌会出现在这里")
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.hash) { index, song in
                            SongRowView(song: song, index: index + 1, queue: songs)
                        }
                    }
                }
            }
            .pagePadding()
        }
    }
}
