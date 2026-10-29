// 使用 swiftc Kimo/Core/Models.swift scripts/check-favorite-song-ids.swift -o /tmp/kimo-song-id-check 运行。
import Foundation

@main
struct FavoriteSongIdentifierCheck {
    // 验证收藏记录的 ID 优先级和其他接口的兼容回退。
    static func main() {
        check("收藏歌曲优先使用 mixsongid", ["hash": "abc", "audio_id": 123, "mixsongid": 456], 456)
        check("空的专辑歌曲 ID 继续回退", ["hash": "abc", "album_audio_id": 0, "mixsongid": 456], 456)
        check("有效的 album_audio_id 优先", ["hash": "abc", "album_audio_id": 789, "mixsongid": 456], 789)
        check("字符串形式的 mixsongid", ["hash": "abc", "audio_id": 123, "mixsongid": "456"], 456)
        check("搜索接口使用 MixSongID", ["hash": "abc", "Audioid": 321, "MixSongID": "872928539"], 872928539)
        check("audio_id 不能当作 mixsongid", ["hash": "abc", "audio_id": 123], 0)
        check("Audioid 不能当作 mixsongid", ["hash": "abc", "Audioid": 321], 0)
        check("缺少标识时使用零", ["hash": "abc"], 0)
        print("收藏歌曲标识映射检查通过")
    }

    // 检查单个接口记录映射出的播放标识。
    private static func check(_ name: String, _ record: JSON, _ expected: Int) {
        let actual = Song.from(record)?.albumAudioId
        guard actual == expected else {
            fputs("\(name)失败：期望 \(expected)，实际 \(actual.map(String.init) ?? "nil")\n", stderr)
            exit(1)
        }
    }
}
