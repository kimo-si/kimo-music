import Foundation
import MediaPlayer
import Observation

// 将系统媒体指令与正在播放信息连接到同一个播放器，不依赖窗口是否可见。
@MainActor
final class SystemMediaControls {
    enum Command: Sendable {
        case play, pause, toggle, next, previous
        case seek(TimeInterval)
    }

    private struct Registration {
        let command: MPRemoteCommand
        let target: Any
    }

    private struct Snapshot: Equatable {
        let song: Song?
        let playing: Bool
        let loading: Bool
        let progress: TimeInterval
        let duration: TimeInterval
        let rate: Double
        let queueCount: Int
        let index: Int

        // 在一次观察中读取媒体状态，后续发布不再直接访问播放器。
        @MainActor
        init(player: PlayerEngine) {
            song = player.current
            playing = player.isPlaying
            loading = player.isLoadingStream
            progress = player.progress.isFinite ? max(0, player.progress) : 0
            duration = player.duration.isFinite ? max(0, player.duration) : 0
            rate = player.playbackRate
            queueCount = player.queue.count
            index = player.index
        }
    }

    private let commands = MPRemoteCommandCenter.shared()
    private let nowPlaying = MPNowPlayingInfoCenter.default()
    private weak var player: PlayerEngine?
    private var registrations: [Registration] = []
    private var observationID = UUID()
    private var lastSnapshot: Snapshot?
    private var hasPlaybackSession = false

    // 重复挂载窗口时不重复注册，切换播放器时先释放原有指令。
    func start(player: PlayerEngine) {
        guard self.player !== player else { return }
        stop()
        self.player = player
        // 先注册系统入口，再观察状态以同步按钮可用性和媒体信息。
        registerCommands()
        observeState(id: observationID)
    }

    // 退出应用时移除自己的监听并清空系统媒体信息。
    func stop() {
        observationID = UUID()
        for registration in registrations {
            registration.command.removeTarget(registration.target)
            registration.command.isEnabled = false
        }
        registrations.removeAll()
        player = nil
        lastSnapshot = nil
        hasPlaybackSession = false
        nowPlaying.nowPlayingInfo = nil
        nowPlaying.playbackState = .stopped
    }

    // 所有媒体入口共享幂等控制和队列语义，空列表不伪报成功。
    @discardableResult
    func perform(_ command: Command) -> MPRemoteCommandHandlerStatus {
        guard let player else { return .commandFailed }
        guard player.current != nil || player.hasQueue else { return .noSuchContent }
        switch command {
        case .play: player.resume()
        case .pause: player.pause()
        case .toggle: player.togglePlayPause()
        case .next: player.next()
        case .previous: player.previous()
        case .seek(let position):
            guard position.isFinite, player.duration.isFinite, player.duration > 0,
                  !player.isLoadingStream else { return .commandFailed }
            player.seek(to: position)
        }
        return .success
    }

    // 系统回调可能来自非主线程；接受后交给主执行器，串行更新播放器。
    private nonisolated func receive(_ command: Command) -> MPRemoteCommandHandlerStatus {
        if Thread.isMainThread {
            return MainActor.assumeIsolated { perform(command) }
        }
        Task { @MainActor [weak self] in self?.perform(command) }
        return .success
    }

    // 注册 AirPods、媒体键及系统控制中心共用的标准媒体指令。
    private func registerCommands() {
        register(commands.playCommand, action: .play)
        register(commands.pauseCommand, action: .pause)
        register(commands.togglePlayPauseCommand, action: .toggle)
        register(commands.nextTrackCommand, action: .next)
        register(commands.previousTrackCommand, action: .previous)
        let target = commands.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
            guard let self, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            return self.receive(.seek(event.positionTime))
        }
        registrations.append(Registration(command: commands.changePlaybackPositionCommand, target: target))
        // 不支持的指令保持禁用，避免系统展示无法执行的操作。
        disableUnsupportedCommands()
    }

    // 保存每个注册句柄，释放时不会误删其他组件的系统监听。
    private func register(_ command: MPRemoteCommand, action: Command) {
        let target = command.addTarget { @Sendable [weak self] _ in
            self?.receive(action) ?? .commandFailed
        }
        registrations.append(Registration(command: command, target: target))
    }

    // 当前播放器未实现的系统操作不对外宣称支持。
    private func disableUnsupportedCommands() {
        let unsupported: [MPRemoteCommand] = [
            commands.stopCommand, commands.skipForwardCommand, commands.skipBackwardCommand,
            commands.seekForwardCommand, commands.seekBackwardCommand, commands.changePlaybackRateCommand,
            commands.changeRepeatModeCommand, commands.changeShuffleModeCommand, commands.ratingCommand,
            commands.likeCommand, commands.dislikeCommand, commands.bookmarkCommand,
            commands.enableLanguageOptionCommand, commands.disableLanguageOptionCommand,
        ]
        for command in unsupported { command.isEnabled = false }
    }

    // 观察播放状态而非视图生命周期，mini 模式和后台窗口使用同一条同步链。
    private func observeState(id: UUID) {
        guard id == observationID, let player else { return }
        let snapshot = withObservationTracking {
            Snapshot(player: player)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeState(id: id) }
        }
        // 读取提交后的完整状态，停止监听后的旧回调通过标识失效。
        publish(snapshot)
    }

    // 同步歌曲和播放状态；启动恢复的暂停歌曲不抢占其他应用的媒体控制。
    private func publish(_ snapshot: Snapshot) {
        guard snapshot != lastSnapshot else { return }
        lastSnapshot = snapshot
        updateCommands(snapshot)
        guard let song = snapshot.song else {
            hasPlaybackSession = false
            nowPlaying.nowPlayingInfo = nil
            nowPlaying.playbackState = .stopped
            return
        }
        guard hasPlaybackSession || snapshot.playing else { return }
        hasPlaybackSession = true
        nowPlaying.nowPlayingInfo = metadata(for: song, snapshot: snapshot)
        let state: MPNowPlayingPlaybackState = snapshot.playing ? .playing : .paused
        // macOS 要求显式发布播放状态，耳机才能持续控制暂停后的歌曲。
        if nowPlaying.playbackState != state { nowPlaying.playbackState = state }
    }

    // 空列表禁用媒体键；取流阶段仍接受暂停，但不接受进度跳转。
    private func updateCommands(_ snapshot: Snapshot) {
        let hasContent = snapshot.song != nil || snapshot.queueCount > 0
        commands.playCommand.isEnabled = hasContent
        commands.pauseCommand.isEnabled = hasContent
        commands.togglePlayPauseCommand.isEnabled = hasContent
        commands.nextTrackCommand.isEnabled = snapshot.queueCount > 0
        commands.previousTrackCommand.isEnabled = snapshot.queueCount > 0
        commands.changePlaybackPositionCommand.isEnabled = snapshot.song != nil
            && snapshot.duration > 0 && !snapshot.loading
    }

    // 仅在系统 API 边界构建必需的字典，业务层继续使用类型化状态。
    private func metadata(for song: Song, snapshot: Snapshot) -> [String: Any] {
        [
            MPMediaItemPropertyTitle: song.name,
            MPMediaItemPropertyArtist: song.artist,
            MPMediaItemPropertyAlbumTitle: song.album,
            MPMediaItemPropertyPlaybackDuration: snapshot.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: snapshot.progress,
            MPNowPlayingInfoPropertyPlaybackRate: snapshot.rate,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyPlaybackQueueCount: snapshot.queueCount,
            MPNowPlayingInfoPropertyPlaybackQueueIndex: snapshot.index,
        ]
    }
}
