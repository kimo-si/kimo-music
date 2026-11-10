// 与 Kimo 下除 KimoApp.swift 外的 Swift 源码一起编译，验证真实播放器的队列控制。
import Foundation

@main
struct PlayerControlsCheck {
    // 验证空队列、单曲重播、循环切歌与队列删除后的按钮状态。
    @MainActor
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kimo-player-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(storageURL: directory.appendingPathComponent("settings.json"))
        settings.resumeOnLaunch = false
        let player = PlayerEngine(settings: settings)
        // 清理可能恢复的状态，让每项检查使用明确的播放队列。
        player.clearQueue()
        checkEmptyQueue(player)
        checkSingleTrack(player)
        checkTrackNavigation(player)
        checkQueueRemoval(player)
        // 验证来源在切歌、插播、删歌、收藏更新和编解码中的完整性。
        checkPlaybackSources(player)
        checkInsertedSources(player)
        checkSourceRemoval(player)
        try checkContextCoding()
        checkSessionRestoration(settings)
        print("播放器控制检查通过：空队列、循环切歌、来源切换、插播来源、队列删除、收藏同步、来源恢复")
        // 所有检查同步执行，退出前不运行测试曲目的远程取流任务。
        exit(EXIT_SUCCESS)
    }

    // 模拟退出后重新创建播放器，确认来源、完整列表与当前索引一起恢复。
    @MainActor
    private static func checkSessionRestoration(_ settings: AppSettings) {
        let suite = "kimo-player-check-\(UUID())"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("无法创建隔离会话") }
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.resumeOnLaunch = true
        let songs = [makeSong("persist-first"), makeSong("persist-second")]
        let source = PlaybackSource.playlist(id: "saved-list", title: "恢复测试")
        let original = PlayerEngine(settings: settings, sessionDefaults: defaults)
        original.setQueueForPreview(songs, currentIndex: 1, source: source)
        original.seek(to: 42)
        let restored = PlayerEngine(settings: settings, sessionDefaults: defaults)
        check(restored.playbackContext.source == source, "续播应恢复原歌单身份")
        check(restored.queue == songs && restored.index == 1, "续播应恢复列表与歌曲位置")
        check(restored.current == songs[1] && restored.progress == 42, "续播应保留当前曲目与进度")
    }

    // 同一首歌从不同入口播放时采用实际入口，收藏更新不污染歌单快照。
    @MainActor
    private static func checkPlaybackSources(_ player: PlayerEngine) {
        let songs = [makeSong("shared"), makeSong("playlist-only")]
        let source = PlaybackSource.playlist(id: "list-a", title: "测试歌单")
        player.play(songs[0], queue: songs, source: source)
        check(player.playbackContext.source == source, "歌单播放应记录歌单身份")
        player.next()
        check(player.playbackContext.songs == songs, "切歌应保留完整歌单")
        player.playQueued(at: 0)
        check(player.playbackContext.source == source, "队列选歌不得丢失来源")
        check(player.playbackContext.resolvedSongs(likedSongs: []) == songs, "收藏变化不应影响歌单来源")
        let liked = [songs[0], makeSong("favorite-only")]
        player.play(songs[0], queue: liked, source: .liked)
        check(player.playbackContext.source == .liked, "同曲从我喜欢播放必须切换来源")
        check(player.playbackContext.resolvedSongs(likedSongs: [liked[1]]) == [liked[1]], "取消喜欢应更新来源列表")
        check(player.playbackContext.resolvedSongs(likedSongs: []).isEmpty, "收藏清空后不得退回旧快照")
    }

    // 插入同一首歌也保存独立来源，上一首和下一首均按队列位置解析。
    @MainActor
    private static func checkInsertedSources(_ player: PlayerEngine) {
        let songs = [makeSong("same"), makeSong("next")]
        let source = PlaybackSource.playlist(id: "list-b", title: "另一张歌单")
        player.setQueueForPreview(songs, source: source)
        player.insertNext(songs[0], context: PlaybackContext(source: .liked, songs: [songs[0]]))
        check(player.playbackContext.source == source, "插播不能立即覆盖当前来源")
        player.next()
        check(player.index == 1 && player.playbackContext.source == .liked, "重复歌曲应保留插播入口")
        player.next()
        check(player.playbackContext.source == source, "插播结束后应恢复原歌单")
        player.playQueued(at: 1)
        check(player.playbackContext.source == .liked, "队列点击重复歌曲必须选中正确条目")
    }

    // 删除条目后来源与索引仍对齐，清空和无来源播放不复用旧歌单。
    @MainActor
    private static func checkSourceRemoval(_ player: PlayerEngine) {
        let songs = [makeSong("remove-first"), makeSong("keep-last")]
        let source = PlaybackSource.playlist(id: "list-c", title: "删除测试")
        player.setQueueForPreview(songs, currentIndex: 1, source: source)
        player.remove(at: 0)
        check(player.index == 0 && player.playbackContext.source == source, "删除前曲后来源应对齐")
        check(player.playbackContext.songs == songs, "编辑队列不应改写来源歌单")
        player.clearQueue()
        check(player.playbackContext.source == .queue && player.playbackContext.songs.isEmpty, "清空应清除来源")
        player.append([makeSong("fresh")])
        check(player.playbackContext.source == .queue, "无来源播放不应使用旧歌单")
        player.remove(at: 0)
        check(!player.isLoadingStream && player.index == 0, "删空应取消加载并复位索引")
    }

    // 来源快照可完整编码恢复，云端 hash 大小写和元数据变化不影响身份匹配。
    private static func checkContextCoding() throws {
        let song = makeSong("source-song")
        let context = PlaybackContext(source: .playlist(id: "persisted", title: "保存的来源"), songs: [song])
        let data = try JSONEncoder().encode(context)
        let restored = try JSONDecoder().decode(PlaybackContext.self, from: data)
        check(restored == context, "来源快照应完整恢复")
        let renamed = Song(id: "different-id", hash: "SOURCE-SONG", albumId: 0, albumAudioId: 0,
                           name: "更新的标题", artist: "歌手", album: "", cover: nil, duration: 180)
        check(song.matches(renamed), "歌曲身份应独立于大小写和展示元数据")
    }

    // 空队列禁用切歌，并且调用切歌不会产生无效索引。
    @MainActor
    private static func checkEmptyQueue(_ player: PlayerEngine) {
        check(!player.canGoPrevious && !player.canGoNext, "空队列应禁用切歌")
        player.previous()
        player.next()
        check(player.current == nil && player.index == 0, "空队列切歌应安全返回")
    }

    // 单曲队列保留两个按钮，点击任一按钮仍选中当前歌曲。
    @MainActor
    private static func checkSingleTrack(_ player: PlayerEngine) {
        let song = makeSong("single")
        player.setQueueForPreview([song])
        check(player.canGoPrevious && player.canGoNext, "单曲队列应允许重新播放")
        player.previous()
        check(player.current == song && player.index == 0, "上一首应重新播放单曲")
        player.next()
        check(player.current == song && player.index == 0, "下一首应重新播放单曲")
    }

    // 多曲队列支持正常前后切歌，并在首尾循环。
    @MainActor
    private static func checkTrackNavigation(_ player: PlayerEngine) {
        let songs = [makeSong("first"), makeSong("second"), makeSong("third")]
        player.setQueueForPreview(songs)
        check(player.canGoPrevious && player.canGoNext, "多曲队列应启用切歌")
        player.next()
        check(player.current == songs[1] && player.index == 1, "下一首应切到第二首")
        player.previous()
        check(player.current == songs[0] && player.index == 0, "上一首应返回第一首")
        player.previous()
        check(player.current == songs[2] && player.index == 2, "第一首的上一首应循环到末尾")
        player.next()
        check(player.current == songs[0] && player.index == 0, "最后一首的下一首应循环到开头")
    }

    // 队列从多曲删为单曲时仍可操作，删空后立即禁用。
    @MainActor
    private static func checkQueueRemoval(_ player: PlayerEngine) {
        player.setQueueForPreview([makeSong("keep"), makeSong("remove")])
        player.remove(at: 1)
        check(player.canGoPrevious && player.canGoNext, "删除后剩一首仍应允许重播")
        player.remove(at: 0)
        check(!player.canGoPrevious && !player.canGoNext, "队列删空后应禁用切歌")
        check(player.current == nil, "队列删空后应清除当前曲目")
    }

    // 在行为不符合预期时输出明确原因，并以失败状态结束检查。
    private static func check(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("播放器控制检查失败：\(message)\n", stderr)
            exit(EXIT_FAILURE)
        }
    }

    // 创建仅用于同步队列状态检查的曲目，不使用真实歌曲标识。
    private static func makeSong(_ id: String) -> Song {
        Song(id: id, hash: id, albumId: 0, albumAudioId: 0,
             name: id, artist: "测试歌手", album: "", cover: nil, duration: 180)
    }
}
