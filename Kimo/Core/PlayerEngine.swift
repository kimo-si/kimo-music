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
    private var queueContexts: [PlaybackContext?] = []

    var playbackContext: PlaybackContext {
        guard queueContexts.indices.contains(index), let context = queueContexts[index] else {
            return PlaybackContext(source: .queue, songs: queue)
        }
        return context
    }

    // 传输状态
    private(set) var isPlaying = false
    private(set) var progress: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var audioLevels = PlaybackAudioLevels()
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
    private let sessionDefaults: UserDefaults
    private let player = AVPlayer()
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var loadTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var audioAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var itemStatusObserver: NSKeyValueObservation?

    var hasQueue: Bool { !queue.isEmpty }
    // 非空队列均可切歌；只有一首时由循环逻辑重新播放当前歌曲。
    var canGoNext: Bool { hasQueue }
    var canGoPrevious: Bool { hasQueue }
    var playbackRate: Double { isPlaying ? Double(player.rate) : 0 }

    // 配置音频观察与续播存储，检查脚本可注入隔离的会话域。
    init(settings: AppSettings, sessionDefaults: UserDefaults = .standard) {
        self.settings = settings
        self.sessionDefaults = sessionDefaults
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
        ) { [weak self] notification in
            guard let item = notification.object as? AVPlayerItem else { return }
            Task { @MainActor [weak self, weak item] in
                guard let self, let item, self.player.currentItem === item else { return }
                // 快速切歌后忽略旧播放项迟到的结束通知。
                self.next()
            }
        }
        restoreLastSession()
    }

    // MARK: - Controls

    // 建立新队列时记录来源；从现有队列选歌时保留该条目的来源。
    func play(_ song: Song, queue newQueue: [Song]? = nil, source: PlaybackSource = .queue) {
        if let newQueue {
            // 将来源与队列一起切换，避免新歌曲误用上一张歌单。
            replaceQueue(newQueue, selecting: song, source: source)
        } else if let existing = queue.firstIndex(where: { $0.matches(song) }) {
            index = existing
        } else {
            replaceQueue([song], selecting: song, source: source)
        }
        // 按队列位置播放，重复歌曲也能保持各自的来源。
        playQueued(at: index)
    }

    // 原子替换歌曲与来源；未包含的点播歌曲补入队列首位。
    private func replaceQueue(_ songs: [Song], selecting song: Song, source: PlaybackSource) {
        queue = songs.contains(where: { $0.matches(song) }) ? songs : [song] + songs
        index = queue.firstIndex(where: { $0.matches(song) }) ?? 0
        let context = source == .queue ? nil : PlaybackContext(source: source, songs: queue)
        queueContexts = Array(repeating: context, count: queue.count)
    }

    // 从实际队列中选择位置，不重建队列或丢弃来源信息。
    func playQueued(at position: Int) {
        guard queue.indices.contains(position) else { return }
        index = position
        current = queue[position]
        load(queue[position])
    }

    /// 双击歌曲：插入到当前曲之后（设置 › 双击歌曲 = 仅插入这首）。
    func insertNext(_ song: Song, context: PlaybackContext? = nil) {
        if queue.isEmpty {
            replaceQueue([song], selecting: song, source: .queue)
            queueContexts[0] = context
            playQueued(at: 0)
            return
        }
        let position = min(index + 1, queue.count)
        queue.insert(song, at: position)
        queueContexts.insert(context, at: position)
        notice = "已插到下一首：\(song.name)"
    }

    /// 开发期预览：塞一批曲目进队列，不请求音频。
    func setQueueForPreview(_ songs: [Song], currentIndex: Int = 0, source: PlaybackSource = .queue) {
        guard !songs.isEmpty else { return }
        let position = min(max(0, currentIndex), songs.count - 1)
        replaceQueue(songs, selecting: songs[position], source: source)
        index = position
        current = songs[index]
        duration = current?.duration ?? 0
        progress = 0
    }

    /// 开发期预览：只设置当前曲目，不请求音频（截图歌词页用）。
    func loadForPreview(_ song: Song) {
        setQueueForPreview([song])
    }

    // 加载中也视为播放请求，再次操作应取消取流并暂停。
    func togglePlayPause() {
        if isPlaying || isLoadingStream {
            pause()
        } else {
            resume()
        }
    }

    // 幂等恢复播放，重复的耳机播放指令不会重新取流或切换为暂停。
    func resume() {
        guard !isPlaying, !isLoadingStream else { return }
        guard current != nil else {
            if let first = queue.first { play(first) }
            return
        }
        if player.currentItem == nil, let song = current {
            // 续播或加载被取消后重新取得音源。
            load(song)
        } else {
            resumePlayback()
        }
    }

    // 幂等暂停并取消取流和失败跳过，防止迟到的任务重新出声。
    func pause() {
        loadTask?.cancel()
        loadTask = nil
        isLoadingStream = false
        guard isPlaying else { return }
        // 立即提交暂停状态，让连续播放/暂停指令能取消旧淡出。
        isPlaying = false
        fadeOutAndPause()
    }

    // 按实际队列循环到下一曲，保留该条目的播放来源。
    func next() {
        guard !queue.isEmpty else { return }
        index = (index + 1) % queue.count
        current = queue[index]
        load(queue[index])
    }

    // 按实际队列循环到上一曲，保留该条目的播放来源。
    func previous() {
        guard !queue.isEmpty else { return }
        index = (index - 1 + queue.count) % queue.count
        current = queue[index]
        load(queue[index])
    }

    // 限制系统进度指令与界面拖动的范围，不向播放器传入无效时间。
    func seek(to seconds: TimeInterval) {
        guard current != nil, seconds.isFinite, duration.isFinite, duration > 0 else { return }
        let position = min(duration, max(0, seconds))
        player.seek(to: CMTime(seconds: position, preferredTimescale: 600))
        progress = position
        persistSession()
    }

    // 追加没有显式来源的歌曲，让它们展示当前实际队列。
    func append(_ songs: [Song]) {
        queue.append(contentsOf: songs)
        queueContexts.append(contentsOf: Array(repeating: nil, count: songs.count))
        if current == nil, let first = queue.first {
            play(first)
        }
    }

    // 同步删除歌曲与来源，并维护当前播放位置。
    func remove(at position: Int) {
        guard queue.indices.contains(position) else { return }
        let wasCurrent = position == index
        queue.remove(at: position)
        queueContexts.remove(at: position)

        if queue.isEmpty {
            // 删除最后一首时取消未完成取流，防止歌曲在空列表中恢复播放。
            clearQueue()
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

    // 清空队列、来源和加载任务，避免迟到的取流结果恢复已删除歌曲。
    func clearQueue() {
        loadTask?.cancel()
        fadeTask?.cancel()
        fadeTask = nil
        isLoadingStream = false
        queue.removeAll()
        queueContexts.removeAll()
        index = 0
        current = nil
        isPlaying = false
        player.pause()
        clearPlayerItem()
        progress = 0
        duration = 0
    }

    // MARK: - Loading

    // 编排本地音源与异步取流，取消后不再提交任何播放结果。
    private func load(_ song: Song) {
        // 先清理旧播放任务与状态，再准备新音源。
        prepareToLoad(song)
        if let local = song.localURL {
            startPlayback(from: local)
            return
        }
        let quality = settings.quality
        loadTask = Task {
            guard !Task.isCancelled else { return }
            do {
                // 取流只解析地址；暂停或切歌后丢弃迟到结果。
                let info = try await MusicAPI.shared.streamURL(for: song, quality: quality)
                guard !Task.isCancelled else { return }
                startPlayback(from: info.url)
            } catch {
                guard !Task.isCancelled else { return }
                await handleStreamFailure(error)
            }
            guard !Task.isCancelled else { return }
            isLoadingStream = false
        }
    }

    // 开始新曲目前取消旧任务、重置进度并隔离旧播放项的回调。
    private func prepareToLoad(_ song: Song) {
        onTrackStarted?(song)
        loadTask?.cancel()
        fadeTask?.cancel()
        fadeTask = nil
        isLoadingStream = true
        notice = nil
        noticeNeedsLogin = false
        duration = song.duration
        progress = 0
        player.pause()
        // 移除旧曲目及其状态监听，避免过期回调影响新曲目。
        clearPlayerItem()
        isPlaying = false
        player.volume = 0
    }

    // 为本地和远程音源复用播放项监听、淡入与续播保存。
    private func startPlayback(from url: URL) {
        installPlayerItem(AVPlayerItem(url: url))
        isLoadingStream = false
        resumePlayback()
        persistSession()
    }

    // 区分需要用户处理的取流失败与允许自动跳过的错误。
    private func handleStreamFailure(_ error: Error) async {
        isPlaying = false
        clearPlayerItem()
        if let playbackError = error as? PlaybackError {
            notice = playbackError.errorDescription
            switch playbackError {
            case .needLogin, .sessionExpired:
                noticeNeedsLogin = true
                return
            case .verificationRequired:
                return
            default:
                break
            }
        } else {
            notice = "播放失败：\(error.localizedDescription)"
        }
        // 仅非登录、非安全验证错误可以按设置自动切歌。
        await skipFailedTrackIfNeeded()
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
        // 每首歌使用独立采样器，异步准备音轨时不阻塞播放。
        installAudioAnalysis(for: item)
    }

    // 异步加载音轨并接入旁路采样；不支持的音源保留原有静态背景。
    private func installAudioAnalysis(for item: AVPlayerItem) {
        audioAnalysisTask?.cancel()
        let levels = PlaybackAudioLevels()
        audioLevels = levels
        audioAnalysisTask = Task { [weak self, weak item] in
            guard let item else { return }
            guard let tracks = try? await item.asset.loadTracks(withMediaType: .audio),
                  let track = tracks.first, !Task.isCancelled,
                  self?.player.currentItem === item else { return }
            // 仅为当前播放项安装采样，忽略切歌后完成的旧任务。
            item.audioMix = levels.makeMix(track: track)
        }
    }

    // 清理播放项和对应的状态监听。
    private func clearPlayerItem() {
        // 取消旧音轨准备并隔离迟到的音频回调。
        audioAnalysisTask?.cancel()
        audioAnalysisTask = nil
        audioLevels = PlaybackAudioLevels()
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

    // 恢复当前播放项，淡入会取消尚未完成的淡出任务。
    private func resumePlayback() {
        player.playImmediately(atRate: Float(settings.playbackRate))
        isPlaying = true
        fadeIn()
    }

    // 渐增音量；被新指令取消后不再修改新的淡入淡出任务状态。
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
            guard !Task.isCancelled else { return }
            self.fadeTask = nil
        }
    }

    // 暂停状态已提交；这里只完成音量淡出、实际停播和进度保存。
    private func fadeOutAndPause() {
        fadeTask?.cancel()
        guard settings.fadeMs > 0 else {
            fadeTask = nil
            player.pause()
            player.volume = Float(volume)
            persistSession()
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
            guard !Task.isCancelled else { return }
            self.player.pause()
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
            "context": (try? JSONEncoder().encode(playbackContext)) ?? Data(),
        ]
        sessionDefaults.set(payload, forKey: Self.sessionKey)
    }

    private func restoreLastSession() {
        guard settings.resumeOnLaunch,
              let d = sessionDefaults.dictionary(forKey: Self.sessionKey),
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
        // 新版本恢复来源列表；旧会话没有来源字段时仍兼容单曲续播。
        restoreContext(from: d["context"] as? Data, song: song)
        current = song
        duration = song.duration
        progress = d["position"] as? Double ?? 0
    }

    // 仅恢复包含当前歌曲的来源，避免损坏缓存把曲目绑定到无关列表。
    private func restoreContext(from data: Data?, song: Song) {
        guard let data, let context = try? JSONDecoder().decode(PlaybackContext.self, from: data),
              context.songs.contains(where: { $0.matches(song) }) else {
            replaceQueue([song], selecting: song, source: .queue)
            return
        }
        replaceQueue(context.songs, selecting: song, source: context.source)
    }
}
