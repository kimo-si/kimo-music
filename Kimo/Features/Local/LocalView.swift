//
//  LocalView.swift
//  Kimo
//
//  本地音乐：添加文件/文件夹、拖拽导入、直接播放（不依赖账号）。
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LocalView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var dropTargeted = false

    private var library: LocalLibrary { model.local }
    private var songs: [Song] { library.tracks.map(\.song) }

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 18) {
                header

                if library.tracks.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            SongRowView(song: song, index: index + 1, queue: songs)
                        }
                    }
                }
            }
            .pagePadding()
        }
        .dropDestination(for: URL.self) { urls, _ in
            library.importFrom(urls: urls)
            return true
        } isTargeted: { dropTargeted = $0 }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(theme.accent.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(theme.accentSoft)
                    )
                    .overlay {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc")
                                .font(.system(size: 26, weight: .light))
                                .foregroundStyle(theme.accentStrong)
                            Text("松手导入到本地音乐")
                                .font(.system(size: 13))
                                .foregroundStyle(theme.accentStrong)
                        }
                    }
                    .padding(24)
                    .allowsHitTesting(false)
            }
        }
    }

    private var header: some View {
        PageHeader(
            title: "本地音乐",
            subtitle: library.importing
                ? "正在读取 \(library.scanned)/\(library.pending)…"
                : (library.tracks.isEmpty ? "还没有导入歌曲" : "共 \(library.tracks.count) 首")
        ) {
            HStack(spacing: 10) {
                Button {
                    pickFiles()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 11, weight: .medium))
                        Text("添加文件").font(.system(size: 13))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .frame(height: 34)
                    .background(Capsule().fill(theme.accentStrong))
                }
                .buttonStyle(.plain)

                Button {
                    pickFolder()
                } label: {
                    Text("添加文件夹")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textStrong)
                        .padding(.horizontal, 14)
                        .frame(height: 34)
                        .background(Capsule().fill(theme.chip))
                }
                .buttonStyle(.plain)

                if !library.tracks.isEmpty {
                    Button {
                        library.clear()
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
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(theme.textMuted)
            Text("把音乐文件或文件夹拖到这里")
                .font(.system(size: 15))
                .foregroundStyle(theme.textStrong)
            Text("支持 mp3 / m4a / flac / wav / aiff / aac / ogg")
                .font(.system(size: 12))
                .foregroundStyle(theme.textMuted)
            HStack(spacing: 10) {
                Button("选择文件") { pickFiles() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.accentStrong)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Capsule().fill(theme.accentSoft))
                Button("选择文件夹") { pickFolder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.accentStrong)
                    .padding(.horizontal, 16)
                    .frame(height: 32)
                    .background(Capsule().fill(theme.accentSoft))
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 90)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(theme.divider, style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
        }
    }

    // MARK: - 选择

    private func pickFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.audio, .mp3, .mpeg4Audio, .wav, .aiff]
        panel.message = "选择要导入的音频文件"
        if panel.runModal() == .OK {
            library.importFrom(urls: panel.urls)
        }
    }

    private func pickFolder() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "选择包含音乐的文件夹"
        if panel.runModal() == .OK {
            library.importFrom(urls: panel.urls)
        }
    }
}
