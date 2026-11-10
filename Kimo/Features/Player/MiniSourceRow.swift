import SwiftUI

// 紧凑歌曲行：封面、曲名、歌手和收藏操作共用当前皮肤。
struct MiniSourceRow: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme
    let song: Song
    let isCurrent: Bool
    let onPlay: () -> Void
    @State private var hovering = false
    @State private var changingLike = false

    private var liked: Bool { model.likes.isLiked(song) }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPlay) {
                HStack(spacing: 10) {
                    cover
                    labels
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放 \(song.name)，\(song.artist)")
            .accessibilityValue(isCurrent ? "当前歌曲" : "")
            likeButton
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: theme.radiusRow)
                .fill(isCurrent ? theme.nowPlaying : (hovering ? theme.rowHover : .clear))
        }
        .onHover { hovering = $0 }
    }

    private var cover: some View {
        ZStack(alignment: .bottomTrailing) {
            CoverImage(url: song.cover, radius: min(9, theme.radiusCard), seed: song.id)
            if isCurrent {
                Image(systemName: model.player.isPlaying ? "waveform" : "pause.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.primaryButtonInk)
                    .padding(4)
                    .background(theme.accentStrong, in: RoundedRectangle(cornerRadius: 4))
                    .padding(3)
            }
        }
        .frame(width: 38, height: 38)
        .accessibilityHidden(true)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(song.name)
                .font(theme.titleFont(14, weight: isCurrent ? .semibold : .medium))
                .foregroundStyle(isCurrent ? theme.accentStrong : theme.textStrong)
                .lineLimit(1)
            Text(song.artist)
                .font(.system(size: 11))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
        }
    }

    private var likeButton: some View {
        IconButton(size: 28, disabled: changingLike || song.localURL != nil,
                   tint: liked ? theme.like : theme.textMuted) {
            Task { await toggleLike() }
        } content: {
            Image(systemName: liked ? "heart.fill" : "heart")
                .font(.system(size: 15, weight: .regular))
        }
        .help(song.localURL != nil ? "本地歌曲不支持云端收藏" : (liked ? "取消喜欢" : "加入我喜欢"))
        .accessibilityLabel(liked ? "取消喜欢 \(song.name)" : "喜欢 \(song.name)")
    }

    // 收藏修改交给同一个收藏仓库，来源为我喜欢时列表会即时同步。
    private func toggleLike() async {
        guard auth.isLoggedIn else {
            model.setMini(false)
            model.showLogin = true
            return
        }
        changingLike = true
        defer { changingLike = false }
        // 使用仓库的远程同步与失败恢复，避免小窗维护第二份收藏状态。
        if let message = await model.likes.toggle(song) {
            model.player.showNotice(message)
        }
    }
}
