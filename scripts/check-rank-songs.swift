// 使用 swiftc Kimo/Core/Models.swift scripts/check-rank-songs.swift -o /tmp/kimo-rank-song-check 运行。
import Foundation

@main
struct RankSongMappingCheck {
    static func main() {
        let row: JSON = [
            "songname": "我好像在哪见过你",
            "author_name": "薛之谦",
            "album_id": 1747549,
            "album_audio_id": 39679370,
            "audio_id": 22080184,
            "audio_info": [
                "hash_128": "6A350E487263733359E7F2B64BD974AC",
                "hash_320": "81FC5A37D3D2BFEF54795B0C43CAEA99",
                "duration_128": 279196,
            ] as JSON,
            "album_info": [
                "album_name": "初学者",
                "sizable_cover": "http://imge.kugou.com/stdmusic/{size}/cover.jpg",
            ] as JSON,
        ]
        guard let song = Song.from(row) else {
            fputs("榜单嵌套字段无法映射成歌曲\n", stderr)
            exit(1)
        }
        check("hash 使用 mp3 的 hash_128", song.hash, "6A350E487263733359E7F2B64BD974AC")
        check("歌名", song.name, "我好像在哪见过你")
        check("歌手", song.artist, "薛之谦")
        check("专辑", song.album, "初学者")
        guard song.albumAudioId == 39679370 else {
            fputs("album_audio_id 失败：\(song.albumAudioId)\n", stderr)
            exit(1)
        }
        guard abs(song.duration - 279.196) < 0.01 else {
            fputs("时长失败：\(song.duration)\n", stderr)
            exit(1)
        }
        guard song.cover?.absoluteString.contains("240") == true else {
            fputs("封面未替换 size\n", stderr)
            exit(1)
        }
        print("榜单歌曲映射检查通过")
    }

    private static func check(_ name: String, _ actual: String, _ expected: String) {
        guard actual == expected else {
            fputs("\(name)失败：期望 \(expected)，实际 \(actual)\n", stderr)
            exit(1)
        }
    }
}
