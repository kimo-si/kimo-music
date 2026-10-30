//
//  MusicCards.swift
//  Kimo
//
//  歌单卡 / 榜单卡 / 歌曲行，尺寸与 cocomusic 的 *Card.module.css 对齐。
//

import SwiftUI

// MARK: - Playlist card

struct PlaylistCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let playlist: Playlist
    var subtitle: String?

    @State private var hovering = false

    private var meta: String {
        if let subtitle { return subtitle }
        var parts: [String] = []
        if playlist.trackCount > 0 { parts.append("\(playlist.trackCount)首") }
        if !playlist.tag.isEmpty { parts.append(playlist.tag) }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            cover
                .padding(.bottom, 8)
            Text(playlist.name)
                .font(.system(size: 14))
                .foregroundStyle(hovering ? theme.accentStrong : theme.textStrong)
                .lineLimit(1)
                .truncationMode(.tail)
            if !meta.isEmpty {
                Text(meta)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
        }
        .onHover { hovering = $0 }
        .onTapGesture {
            model.navigate(.playlist(id: playlist.id, title: playlist.name))
        }
    }

    private var cover: some View {
        ZStack {
            CoverImage(url: playlist.cover, radius: theme.radiusCard, seed: playlist.id)
                .scaleEffect(hovering ? 1.05 : 1)
                .animation(.spring(response: 0.42, dampingFraction: 0.85), value: hovering)

            LinearGradient(
                colors: [Color(hex: "1E183C").opacity(0.12), Color(hex: "1E183C").opacity(0.42)],
                startPoint: .top, endPoint: .bottom
            )
            .opacity(hovering ? 1 : 0)
            .animation(.easeOut(duration: 0.24), value: hovering)

            if playlist.playCount > 0 {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "headphones").font(.system(size: 9))
                            Text(formatCount(playlist.playCount)).font(.system(size: 11))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(hex: "141028").opacity(0.58)))
                    }
                    Spacer()
                }
                .padding(8)
            }

            ThemedPlayButton(playing: false, size: 42) {
                Task { await playAll() }
            }
            .accessibilityLabel("播放歌单：\(playlist.name)")
            .opacity(hovering ? 1 : 0)
            .offset(y: hovering ? -3 : 5)
            .animation(.spring(response: 0.34, dampingFraction: 0.8), value: hovering)
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
        .shadow(color: Color.black.opacity(hovering ? 0.16 : 0.08),
                radius: hovering ? 14 : 9, y: hovering ? 10 : 6)
        .offset(y: hovering ? -3 : 0)
        .animation(.spring(response: 0.36, dampingFraction: 0.85), value: hovering)
    }

    private func playAll() async {
        guard let songs = try? await MusicAPI.shared.playlistTracks(id: playlist.id, size: 60),
              let first = songs.first else { return }
        model.player.play(first, queue: songs)
    }
}

// MARK: - Chart card

struct ChartCardView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let chart: Rank
    let songs: [Song]

    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Button {
                    model.navigate(.rank(id: chart.id, title: chart.name))
                } label: {
                    HStack(spacing: 2) {
                        Text(chart.name)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(hovering ? theme.accentStrong : theme.textStrong)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.textMuted)
                            .opacity(hovering ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                if !chart.updateText.isEmpty {
                    Text(chart.updateText)
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textSecondary)
                        .lineLimit(1)
                }
            }

            HStack(alignment: .top, spacing: 16) {
                coverStack
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(songs.prefix(4).enumerated()), id: \.offset) { index, song in
                        Button {
                            model.player.play(song, queue: songs)
                        } label: {
                            HStack(spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12).monospacedDigit())
                                    .foregroundStyle(theme.textMuted)
                                    .frame(width: 14, alignment: .leading)
                                Text(song.name)
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.textStrong)
                                    .lineLimit(1)
                                Text("— \(song.artist)")
                                    .font(.system(size: 13))
                                    .foregroundStyle(theme.textSecondary)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 16)
        .background {
            RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous)
                .fill(hovering ? theme.cardHover : theme.card)
            RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous)
                .strokeBorder(theme.glassEdge, lineWidth: 1)
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.22), value: hovering)
    }

    private var coverStack: some View {
        ZStack {
            if songs.isEmpty {
                CoverImage(url: chart.cover, radius: 9, seed: chart.id)
                    .frame(width: 108, height: 108)
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
            } else {
                ForEach(Array(songs.prefix(3).enumerated().reversed()), id: \.offset) { index, song in
                    CoverImage(url: song.cover, radius: 9, seed: song.id)
                        .frame(width: 108, height: 108)
                        .offset(x: CGFloat(-index) * 10, y: CGFloat(-index) * 8)
                        .shadow(color: .black.opacity(0.18), radius: 8, y: 4)
                }
            }
        }
        .frame(width: 120, height: 120, alignment: .bottomTrailing)
    }
}

struct RowButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: theme.radiusRow)
                    .fill(configuration.isPressed ? theme.hover : Color.clear)
            )
    }
}

// MARK: - Song row

struct SongRowView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let song: Song
    let index: Int?
    let queue: [Song]
    var showCover = true

    @State private var hovering = false

    private var current: Bool {
        guard let playing = model.player.current else { return false }
        return playing.hash.lowercased() == song.hash.lowercased()
            || (song.albumAudioId > 0 && playing.albumAudioId == song.albumAudioId)
    }

    /// 默认皮肤不改列表里正在播放的那一行，预设皮肤才铺底色。
    private var highlighted: Bool { current && theme.flavor != .standard }

    var body: some View {
        HStack(spacing: 12) {
            if let index {
                Text("\(index)")
                    .font(theme.serifTitles
                          ? .system(size: 13, weight: .regular, design: .serif)
                          : .system(size: 13).monospacedDigit())
                    .foregroundStyle(highlighted ? theme.accentStrong : theme.textMuted)
                    .frame(width: 22, alignment: .trailing)
            }
            if showCover {
                CoverImage(url: song.cover, radius: min(10, theme.radiusCard), seed: song.id)
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(song.name)
                    .font(.system(size: 14, weight: highlighted ? .medium : .regular))
                    .foregroundStyle(highlighted ? theme.accentStrong : theme.textStrong)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if current, theme.flavor == .night {
                MiniWave(color: theme.accent, playing: model.player.isPlaying, motion: theme.allowsMotion)
            }
            if current, theme.flavor == .mint {
                MiniNotes(color: theme.accent, playing: model.player.isPlaying, motion: theme.allowsMotion)
            }
            if hovering {
                Button {
                    model.player.play(song, queue: queue)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.accentStrong)
                }
                .buttonStyle(.plain)
            }
            Text(song.durationText)
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(theme.textMuted)
        }
        .padding(.horizontal, 10)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: theme.radiusRow, style: .continuous)
                .fill(highlighted ? theme.nowPlaying : (hovering ? theme.rowHover : Color.clear))
        }
        .overlay(alignment: .bottom) {
            if theme.controls.material == .paper {
                Rectangle().fill(theme.divider).frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(
            TapGesture(count: 2)
                .onEnded { playSong(double: true) }
                .exclusively(before: TapGesture().onEnded { playSong(double: false) })
        )
    }

    /// 双击行为由设置决定：replace = 播放整个列表，insert = 只插到当前曲后面。
    private func playSong(double: Bool) {
        if double, model.settings.doubleClick == "insert" {
            model.player.insertNext(song)
        } else {
            model.player.play(song, queue: queue)
        }
    }
}

// MARK: - Track tile (home 推荐歌曲)

struct TrackTileView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let song: Song
    let queue: [Song]

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .center) {
                CoverImage(url: song.cover, radius: 8, seed: song.id)
                if hovering {
                    RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.35))
                    Image(systemName: "play.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.name)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textStrong)
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: theme.radiusRow, style: .continuous)
                .fill(hovering ? theme.hover : Color.clear)
        }
        .overlay(alignment: .bottom) {
            if theme.controls.material == .paper {
                Rectangle().fill(theme.divider).frame(height: 0.5)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .gesture(
            TapGesture(count: 2)
                .onEnded { playSong(double: true) }
                .exclusively(before: TapGesture().onEnded { playSong(double: false) })
        )
    }

    private func playSong(double: Bool) {
        if double, model.settings.doubleClick == "insert" {
            model.player.insertNext(song)
        } else {
            model.player.play(song, queue: queue)
        }
    }
}
