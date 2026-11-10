// 与 Kimo 下除 KimoApp.swift 外的 Swift 源码一起编译，检查原生媒体控制。
import AppKit
import AVFoundation
import MediaPlayer

@main
struct MediaControlsCheck {
    // 使用隔离配置和静音音源验证系统接线，不访问账号或远程歌曲。
    @MainActor
    static func main() async throws {
        NSApplication.shared.setActivationPolicy(.accessory)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kimo-media-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = makeSettings(in: directory)
        let player = PlayerEngine(settings: settings)
        player.volume = 0
        let controls = SystemMediaControls()
        controls.start(player: player)
        defer { player.clearQueue(); controls.stop() }
        checkEmptyQueue(controls)
        let songs = try makeSongs(in: directory)
        // 逐项验证真实 AVPlayer 状态及系统正在播放信息。
        try await checkPlayback(controls, player: player, songs: songs)
        try await checkNavigation(controls, player: player, songs: songs)
        try await checkSeeking(controls, player: player)
        try await checkRapidCommands(controls, player: player, settings: settings)
        try await checkLoadingCancellation(controls, player: player)
        try await checkLifecycle(controls, player: player, songs: songs)
        print("系统媒体控制检查通过：幂等播放暂停、切歌、进度边界、淡出竞态、取流取消、状态同步、监听清理")
    }

    // 禁用续播和失败自动切歌，避免测试读写真实会话或触发网络。
    @MainActor
    private static func makeSettings(in directory: URL) -> AppSettings {
        let settings = AppSettings(storageURL: directory.appendingPathComponent("settings.json"))
        settings.resumeOnLaunch = false
        settings.fadeMs = 0
        settings.skipOnError = false
        return settings
    }

    // 空队列不会向系统暴露可用指令，也不会接收无效切歌。
    @MainActor
    private static func checkEmptyQueue(_ controls: SystemMediaControls) {
        let center = MPRemoteCommandCenter.shared()
        check(!center.playCommand.isEnabled && !center.nextTrackCommand.isEnabled, "空队列应禁用媒体键")
        for command in [SystemMediaControls.Command.play, .pause, .toggle, .next, .previous] {
            check(controls.perform(command) == .noSuchContent, "空队列应返回无可播放内容")
        }
        check(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil, "空队列不应占用正在播放信息")
    }

    // 真实本地播放接入系统，重复的播放或暂停指令均保持幂等。
    @MainActor
    private static func checkPlayback(_ controls: SystemMediaControls, player: PlayerEngine,
                                      songs: [Song]) async throws {
        player.setQueueForPreview(songs)
        try await waitFor("恢复的暂停曲目不能抢占系统媒体信息") {
            MPRemoteCommandCenter.shared().playCommand.isEnabled
        }
        check(MPNowPlayingInfoCenter.default().nowPlayingInfo == nil, "开始播放前不能发布恢复曲目")
        controls.start(player: player)
        check(controls.perform(.play) == .success, "播放指令应成功")
        try await waitFor("系统应显示正在播放") { systemState == .playing && player.progress > 0 }
        check(title == songs[0].name, "系统歌曲标题应与播放器一致")
        check(controls.perform(.play) == .success && player.isPlaying, "重复播放不应变为暂停")
        check(controls.perform(.pause) == .success && !player.isPlaying, "暂停应立即更新意图")
        check(controls.perform(.pause) == .success && !player.isPlaying, "重复暂停不应恢复播放")
        try await waitFor("系统应同步暂停状态") { systemState == .paused }
        check(MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double == 0,
              "暂停时系统播放速率应为零")
        check(controls.perform(.toggle) == .success && player.isPlaying, "耳机切换指令应恢复播放")
    }

    // 连续媒体切歌保留来源和索引，首尾循环规则与界面保持一致。
    @MainActor
    private static func checkNavigation(_ controls: SystemMediaControls, player: PlayerEngine,
                                        songs: [Song]) async throws {
        let source = PlaybackSource.playlist(id: "headphone-check", title: "耳机控制检查")
        player.play(songs[0], queue: songs, source: source)
        check(controls.perform(.next) == .success && player.current == songs[1], "下一曲应切换到第二首")
        try await waitFor("系统应同步下一曲标题") { title == songs[1].name }
        check(controls.perform(.previous) == .success && player.current == songs[0], "上一曲应返回第一首")
        check(controls.perform(.previous) == .success && player.current == songs[1], "上一曲应支持首尾循环")
        check(player.playbackContext.source == source, "耳机切歌不能丢失播放来源")
        try await waitFor("切歌后音频应实际继续播放") { player.progress > 0 && systemState == .playing }
    }

    // 系统进度指令拒绝非有限值，并与播放器共同限制在歌曲时长内。
    @MainActor
    private static func checkSeeking(_ controls: SystemMediaControls, player: PlayerEngine) async throws {
        controls.perform(.pause)
        check(controls.perform(.seek(.nan)) == .commandFailed, "NaN 进度必须拒绝")
        check(controls.perform(.seek(.infinity)) == .commandFailed, "无穷进度必须拒绝")
        check(controls.perform(.seek(-1)) == .success && player.progress == 0, "负进度应限制到零")
        check(controls.perform(.seek(player.duration + 1)) == .success && player.progress == player.duration,
              "超时进度应限制到歌曲末尾")
        controls.perform(.seek(1))
        try await waitFor("系统进度应同步到指定位置") {
            let progress = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double
            return progress.map { abs($0 - 1) < 0.1 } ?? false
        }
    }

    // 暂停淡出期间快速恢复，旧任务不得在稍后再次暂停新播放。
    @MainActor
    private static func checkRapidCommands(_ controls: SystemMediaControls, player: PlayerEngine,
                                           settings: AppSettings) async throws {
        settings.fadeMs = 120
        controls.perform(.play)
        controls.perform(.pause)
        controls.perform(.play)
        try await Task.sleep(for: .milliseconds(300))
        check(player.isPlaying && player.playbackRate > 0, "取消的淡出任务不得再次暂停播放器")
        controls.perform(.toggle)
        controls.perform(.toggle)
        try await Task.sleep(for: .milliseconds(300))
        check(player.isPlaying && player.playbackRate > 0, "连续两次耳机切换应恢复播放")
        controls.perform(.pause)
        controls.perform(.pause)
        try await Task.sleep(for: .milliseconds(300))
        check(!player.isPlaying && systemState == .paused, "重复暂停应保持暂停状态")
        settings.fadeMs = 0
    }

    // 主执行器让出前取消取流，确保测试不发请求且暂停不会被旧任务覆盖。
    @MainActor
    private static func checkLoadingCancellation(_ controls: SystemMediaControls, player: PlayerEngine) async throws {
        let song = Song(id: "cancelled", hash: "cancelled", albumId: 0, albumAudioId: 0,
                        name: "取消取流", artist: "测试歌手", album: "", cover: nil, duration: 10)
        player.play(song)
        check(player.isLoadingStream, "远程歌曲应先进入取流状态")
        check(controls.perform(.seek(1)) == .commandFailed, "取流期间不接受进度指令")
        controls.perform(.pause)
        check(!player.isLoadingStream && !player.isPlaying, "暂停应取消正在进行的取流")
        try await Task.sleep(for: .milliseconds(100))
        check(!player.isPlaying && !player.isLoadingStream, "取消后的任务不能恢复播放")
        controls.perform(.play)
        check(player.isLoadingStream, "暂停取流后允许重新播放")
        controls.perform(.toggle)
        check(!player.isLoadingStream, "耳机切换键也应取消取流")
    }

    // 清空队列和停止监听后清除元数据，已排队观察回调不得重新启用媒体键。
    @MainActor
    private static func checkLifecycle(_ controls: SystemMediaControls, player: PlayerEngine,
                                       songs: [Song]) async throws {
        player.clearQueue()
        try await waitFor("清空队列应清除系统信息") {
            MPNowPlayingInfoCenter.default().nowPlayingInfo == nil
                && !MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled
        }
        player.setQueueForPreview(songs)
        controls.stop()
        try await Task.sleep(for: .milliseconds(100))
        check(!MPRemoteCommandCenter.shared().playCommand.isEnabled, "过期观察回调不能重新注册控制")
        check(controls.perform(.play) == .commandFailed, "解绑后不能再操作播放器")
        controls.start(player: player)
        check(MPRemoteCommandCenter.shared().playCommand.isEnabled, "解绑后应允许重新绑定")
    }

    private static var systemState: MPNowPlayingPlaybackState { MPNowPlayingInfoCenter.default().playbackState }
    private static var title: String? { MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPMediaItemPropertyTitle] as? String }

    // 等待真实观察链提交，超时输出场景名称而不是无限轮询。
    @MainActor
    private static func waitFor(_ message: String, condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(3)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        check(condition(), message)
    }

    // 创建两首共享静音音源的歌曲，足够覆盖播放和切歌检查。
    private static func makeSongs(in directory: URL) throws -> [Song] {
        let url = directory.appendingPathComponent("silence.wav")
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 80000),
              let samples = buffer.floatChannelData?[0] else { fatalError("无法创建测试音频") }
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) { samples[index] = 0 }
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
        return ["first", "second"].map { id in
            Song(id: id, hash: id, albumId: 0, albumAudioId: 0, name: id,
                 artist: "测试歌手", album: "测试专辑", cover: nil, duration: 10, localURL: url)
        }
    }

    // 失败时给出具体原因并退出，方便脚本与持续集成直接判断结果。
    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("系统媒体控制检查失败：\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }
}
