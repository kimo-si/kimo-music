//
//  QueuePanel.swift
//  Kimo
//
//  右侧播放列表抽屉：贴顶 16、右边 12、底 84（让开播放栏），宽 380。
//  版式对应 QueuePanel.module.css。
//

import SwiftUI

struct QueuePanel: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    private var player: PlayerEngine { model.player }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(theme.divider)
            list
        }
        .frame(width: 380)
        .background {
            if theme.glassBlur > 0 {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            }
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.solid.opacity(0.96))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(theme.glassEdge, lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.22), radius: 30, y: 12)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("播放列表")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(theme.textStrong)
                Text(player.queue.isEmpty ? "列表是空的" : "共 \(player.queue.count) 首")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
            }
            Spacer()
            HStack(spacing: 2) {
                IconButton(size: 30, radius: 8, disabled: player.queue.isEmpty) {
                    player.clearQueue()
                } content: {
                    Image(systemName: "trash").font(.system(size: 12, weight: .regular))
                }
                IconButton(size: 30, radius: 8) {
                    model.showQueue = false
                } content: {
                    Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 14)
        .padding(.leading, 6)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 1)
        }
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 2) {
                    ForEach(Array(player.queue.enumerated()), id: \.offset) { index, song in
                        QueueRow(song: song,
                                 index: index,
                                 isCurrent: player.current == song)
                            .id(index)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
            }
            .onAppear {
                if let idx = player.queue.firstIndex(where: { $0 == player.current }) {
                    proxy.scrollTo(idx, anchor: .center)
                }
            }
        }
    }
}

private struct QueueRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let song: Song
    let index: Int
    let isCurrent: Bool

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(theme.textMuted.opacity(0.6))
                .frame(width: 12)
                .opacity(hovering ? 1 : 0.45)

            Button {
                model.player.play(song, queue: model.player.queue)
            } label: {
                HStack(spacing: 10) {
                    ZStack {
                        CoverImage(url: song.cover, radius: 6, seed: song.id)
                        if isCurrent {
                            RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.42))
                            EqualizerBars(active: model.player.isPlaying)
                        }
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(song.name)
                            .font(.system(size: 13, weight: isCurrent ? .medium : .regular))
                            .foregroundStyle(isCurrent ? theme.accentStrong : theme.textStrong)
                            .lineLimit(1)
                        Text(song.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(song.durationText)
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(theme.textMuted)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                model.player.remove(at: index)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.textMuted)
                    .frame(width: 22, height: 22)
            }
            .buttonStyle(.plain)
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(height: 52)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isCurrent ? theme.accentSoft.opacity(0.7) : (hovering ? theme.hover : Color.clear))
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - Equalizer

struct EqualizerBars: View {
    var active: Bool
    @State private var phase: CGFloat = 0

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(.white)
                    .frame(width: 2.5, height: barHeight(i))
            }
        }
        .frame(width: 16, height: 14)
        .onAppear { animate() }
        .onChange(of: active) { _, _ in animate() }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        guard active else { return 4 }
        let offsets: [CGFloat] = [0, 0.45, 0.9]
        let v = sin((phase + offsets[i]) * .pi * 2)
        return 4 + (v + 1) * 4
    }

    private func animate() {
        guard active else { return }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            phase = 1
        }
    }
}
