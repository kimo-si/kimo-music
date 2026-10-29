//
//  PlayerEngine.swift
//  Kimo
//
//  AVPlayer 队列播放器。位置、时长、音量与 cocomusic 的 player-store 语义对齐；
//  音质、淡入淡出、倍速、失败跳过、启动续播都读 AppSettings。
//

import AVFoundation
import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerEngine {
    private static let failedTrackSkipDelay: UInt64 = 1_200_000_000
    // 队列
    private(set) var queue: [Song] = []
    private(set) var index: Int = 0
    private(set) var current: Song?

    // 传输状态
    private(set) var isPlaying = false
    private(set) var progress: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var volume: Double = 0.8 {
        didSet {
            if fadeTask == nil { player.volume = Float(volume) }
        }
    }

    /// 开始播放某首歌时通知外部（最近播放记录）。
    var onTrackStarted: ((Song) -> Void)?

    // 提示
    var notice: String?
    /// 提示是否因为「没登录」——这种情况下不自动跳下一首，免得整张列表空转。
    private(set) var noticeNeedsLogin = false

    func showNotice(_ text: String) {
        notice = text
        noticeNeedsLogin = false
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_600_000_000)
            if self?.notice == text { self?.notice = nil }
        }
    }
    private(set) var isLoadingStream = false

    private let settings: AppSettings
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    @ObservationIgnored private var itemStatusObserver: NSKeyValueObservation?

    var hasQueue: Bool { !queue.isEmpty }
    // 非空队列均可切歌；只有一首时由循环逻辑重新播放当前歌曲。
    var canGoNext: Bool { hasQueue }
    var canGoPrevious: Bool { hasQueue }

    init(settings: AppSettings) {
        self.settings = settings
        player.volume = Float(volume)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] t in
            Task { @MainActor in
                guard let self else { return }
                self.progress = t.seconds.isFinite ? t.seconds : 0
                if let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.next() }
        }
        restoreLastSession()
    }

    // MARK: - Controls

    func play(_ song: Song, queue newQueue: [Song]? = nil) {
        if let newQueue, !newQueue.isEmpty {
            queue = newQueue
            index = newQueue.firstIndex(of: song) ?? 0
        } else if let existing = queue.firstIndex(of: song) {
            index = existing
        } else {
            queue = [song]
            index = 0
        }
        current = song
        load(song)
    }

    /// 双击歌曲：插入到当前曲之后（设置 › 双击歌曲 = 仅插入这首）。
    func insertNext(_ song: Song) {
        if queue.isEmpty {
            play(song, queue: [song])
            return
        }
        queue.insert(song, at: min(index + 1, queue.count))
        notice = "已插到下一首：\(song.name)"
    }

    /// 开发期预览：塞一批曲目进队列，不请求音频。
    func setQueueForPreview(_ songs: [Song], currentIndex: Int = 0) {
        guard !songs.isEmpty else { return }
        queue = songs
        index = min(max(0, currentIndex), songs.count - 1)
        current = songs[index]
        duration = current?.duration ?? 0
        progress = 0
    }

    /// 开发期预览：只设置当前曲目，不请求音频（截图歌词页用）。
    func loadForPreview(_ song: Song) {
        queue = [song]
        index = 0
        current = song
        duration = song.duration
        progress = 0
    }

    func togglePlayPause() {
        guard current != nil else {
            if let first = queue.first { play(first) }
            return
        }
        if isPlaying {
            fadeOutAndPause()
        } else {
            if player.currentItem == nil, let song = current {
                load(song)
            } else {
                resumePlayback()
            }
        }
    }

    func next() {
        guard !queue.isEmpty else { return }
        index = (index + 1) % queue.count
        current = queue[index]
        load(queue[index])
    }

    func previous() {
        guard !queue.isEmpty else { return }
        index = (index - 1 + queue.count) % queue.count
        current = queue[index]
        load(queue[index])
    }

    func seek(to seconds: TimeInterval) {
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600))
        progress = seconds
        persistSession()
    }

    func append(_ songs: [Song]) {
        queue.append(contentsOf: songs)
        if current == nil, let first = queue.first {
            play(first)
        }
    }

    func remove(at position: Int) {
        guard queue.indices.contains(position) else { return }
        let wasCurrent = position == index
        queue.remove(at: position)

        if queue.isEmpty {
            current = nil
            isPlaying = false
            player.pause()
            clearPlayerItem()
            progress = 0
            duration = 0
            return
        }

        if position < index {
            index -= 1
        } else if wasCurrent {
            index = min(position, queue.count - 1)
            current = queue[index]
            load(queue[index])
        }
    }

    func clearQueue() {
        queue.removeAll()
        index = 0
        current = nil
        isPlaying = false
        player.pause()
        clearPlayerItem()
        progress = 0
        duration = 0
    }

    // MARK: - Loading

    private func load(_ song: Song) {
        onTrackStarted?(song)
        loadTask?.cancel()
        isLoadingStream = true
        notice = nil
        noticeNeedsLogin = false
        duration = song.duration
        progress = 0
        player.pause()
        // 移除旧曲目及其状态监听，避免过期回调影响新曲目。
        clearPlayerItem()
        isPlaying = false
        fadeTask?.cancel()
        player.volume = 0

        // 本地文件：直接播，不经过核心。
        if let local = song.localURL {
            // 监听本地音频的加载状态。
            installPlayerItem(AVPlayerItem(url: local))
            player.playImmediately(atRate: Float(settings.playbackRate))
            isPlaying = true
            isLoadingStream = false
            fadeIn()
            persistSession()
            return
        }

        let quality = settings.quality
        let rate = Float(settings.playbackRate)
        loadTask = Task {
            do {
                let info = try await MusicAPI.shared.streamURL(for: song, quality: quality)
                guard !Task.isCancelled else { return }
                // 监听远程音频的加载状态，而不是仅依赖取流成功。
                installPlayerItem(AVPlayerItem(url: info.url))
                player.playImmediately(atRate: rate)
                isPlaying = true
                fadeIn()
                persistSession()
            } catch {
                guard !Task.isCancelled else { return }
                isPlaying = false
                clearPlayerItem()
                var hold = false
                if let pe = error as? PlaybackError {
                    notice = pe.errorDescription
                    switch pe {
                    case .needLogin, .sessionExpired:
                        noticeNeedsLogin = true
                        hold = true
                    case .verificationRequired:
                        hold = true
                    default:
                        break
                    }
                } else {
                    notice = "播放失败：\(error.localizedDescription)"
                }
                // 设置 › 播放失败自动下一首（登录失效、安全验证不连跳）
                if !hold {
                    // 根据用户设置处理播放失败后的自动切歌。
                    await skipFailedTrackIfNeeded()
                }
            }
            guard !Task.isCancelled else { return }
            isLoadingStream = false
        }
    }

    // 安装播放项，并在音频实际加载失败时更新播放状态。
    private func installPlayerItem(_ item: AVPlayerItem) {
        itemStatusObserver?.invalidate()
        itemStatusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .failed else { return }
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                // 仅处理当前播放项的失败，忽略已切换歌曲的回调。
                self.handlePlayerItemFailure()
            }
        }
        player.replaceCurrentItem(with: item)
    }

    // 清理播放项和对应的状态监听。
    private func clearPlayerItem() {
        itemStatusObserver?.invalidate()
        itemStatusObserver = nil
        player.replaceCurrentItem(with: nil)
    }

    // 处理播放器加载失败，避免界面错误地显示正在播放。
    private func handlePlayerItemFailure() {
        fadeTask?.cancel()
        fadeTask = nil
        player.pause()
        clearPlayerItem()
        isPlaying = false
        isLoadingStream = false
        player.volume = Float(volume)
        noticeNeedsLogin = false
        notice = "音频加载失败，请重试或切换音质"
        loadTask?.cancel()
        // 尊重播放失败自动下一首的设置。
        loadTask = Task { await skipFailedTrackIfNeeded() }
    }

    // 按设置延迟跳过无法播放的歌曲，并支持取消。
    private func skipFailedTrackIfNeeded() async {
        guard settings.skipOnError, queue.count > 1 else { return }
        try? await Task.sleep(nanoseconds: Self.failedTrackSkipDelay)
        guard !Task.isCancelled else { return }
        // 切换到播放队列中的下一首。
        next()
    }

    private func resumePlayback() {
        player.playImmediately(atRate: Float(settings.playbackRate))
        isPlaying = true
        fadeIn()
    }

    private func fadeIn() {
        fadeTask?.cancel()
        let target = volume
        guard settings.fadeMs > 0 else {
            player.volume = Float(target)
            fadeTask = nil
            return
        }
        let steps = max(1, Int(settings.fadeMs / 30))
        player.volume = 0
        fadeTask = Task { [weak self] in
            guard let self else { return }
            for i in 0...steps {
                guard !Task.isCancelled else { return }
                self.player.volume = Float(target * (Double(i) / Double(steps)))
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            self.fadeTask = nil
        }
    }

    private func fadeOutAndPause() {
        fadeTask?.cancel()
        guard settings.fadeMs > 0 else {
            player.pause()
            isPlaying = false
            return
        }
        let steps = max(1, Int(settings.fadeMs / 30))
        fadeTask = Task { [weak self] in
            guard let self else { return }
            let start = Double(self.player.volume)
            for i in 0...steps {
                guard !Task.isCancelled else { return }
                self.player.volume = Float(start * (1 - Double(i) / Double(steps)))
                try? await Task.sleep(nanoseconds: 30_000_000)
            }
            self.player.pause()
            self.isPlaying = false
            self.player.volume = Float(self.volume)
            self.fadeTask = nil
            self.persistSession()
        }
    }

    // MARK: - 续播

    private static let sessionKey = "kimo.lastSession"

    private func persistSession() {
        guard settings.resumeOnLaunch, let song = current else { return }
        let payload: [String: Any] = [
            "hash": song.hash,
            "name": song.name,
            "artist": song.artist,
            "album": song.album,
            "albumId": song.albumId,
            "albumAudioId": song.albumAudioId,
            "cover": song.cover?.absoluteString ?? "",
            "duration": song.duration,
            "position": progress,
            "localPath": song.localURL?.path ?? "",
        ]
        UserDefaults.standard.set(payload, forKey: Self.sessionKey)
    }

    private func restoreLastSession() {
        guard settings.resumeOnLaunch,
              let d = UserDefaults.standard.dictionary(forKey: Self.sessionKey),
              let hash = d["hash"] as? String, !hash.isEmpty else { return }
        let song = Song(
            id: hash,
            hash: hash,
            albumId: d["albumId"] as? Int ?? 0,
            albumAudioId: d["albumAudioId"] as? Int ?? 0,
            name: d["name"] as? String ?? "",
            artist: d["artist"] as? String ?? "",
            album: d["album"] as? String ?? "",
            cover: (d["cover"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) },
            duration: d["duration"] as? Double ?? 0,
            localURL: (d["localPath"] as? String).flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) }
        )
        queue = [song]
        current = song
        duration = song.duration
        progress = d["position"] as? Double ?? 0
    }
}
