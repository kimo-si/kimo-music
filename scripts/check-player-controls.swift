// 与 Kimo 下除 KimoApp.swift 外的 Swift 源码一起编译，验证真实播放器的队列控制。
import Foundation

@main
struct PlayerControlsCheck {
    // 验证空队列、单曲重播、循环切歌与队列删除后的按钮状态。
    @MainActor
    static func main() {
        let player = PlayerEngine(settings: AppSettings())
        // 清理可能恢复的状态，让每项检查使用明确的播放队列。
        player.clearQueue()
        checkEmptyQueue(player)
        checkSingleTrack(player)
        checkTrackNavigation(player)
        checkQueueRemoval(player)
        print("播放器控制检查通过：空队列、单曲重播、循环切歌、队列删除")
        // 所有检查同步执行，退出前不运行测试曲目的远程取流任务。
        exit(EXIT_SUCCESS)
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
