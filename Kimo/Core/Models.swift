//
//  Models.swift
//  Kimo
//
//  酷狗（MoeKoeMusic 核心）返回的数据字段命名不统一（play_count / playcount、
//  time_length / timelength…），这里统一用宽松取值器映射成领域模型。
//

import Foundation

// MARK: - JSON helpers

typealias JSON = [String: Any]

enum J {
    static func int(_ d: JSON, _ keys: String...) -> Int? {
        for k in keys {
            switch d[k] {
            case let v as Int: return v
            case let v as Double: return Int(v)
            case let v as String: if let n = Int(v) { return n }
            case let v as NSNumber:
                // JSON 布尔也是 NSNumber；id 字段不会是布尔。
                if CFGetTypeID(v) == CFBooleanGetTypeID() { continue }
                return Int(truncatingIfNeeded: v.int64Value)
            default: continue
            }
        }
        return nil
    }

    static func double(_ d: JSON, _ keys: String...) -> Double? {
        for k in keys {
            switch d[k] {
            case let v as Double: return v
            case let v as Int: return Double(v)
            case let v as String: if let n = Double(v) { return n }
            case let v as NSNumber: return v.doubleValue
            default: continue
            }
        }
        return nil
    }

    static func str(_ d: JSON, _ keys: String...) -> String? {
        for k in keys {
            switch d[k] {
            case let v as String where !v.isEmpty: return v
            case let v as NSNumber: return v.stringValue
            default: continue
            }
        }
        return nil
    }

    static func dict(_ d: JSON, _ key: String) -> JSON? {
        d[key] as? JSON
    }

    static func array(_ d: JSON, _ key: String) -> [JSON] {
        (d[key] as? [JSON]) ?? []
    }
}

// MARK: - Models

struct Song: Identifiable, Hashable {
    let id: String
    let hash: String
    let albumId: Int
    let albumAudioId: Int
    let name: String
    let artist: String
    let album: String
    var cover: URL?
    let duration: TimeInterval
    /// 本地文件：有值时播放器直接播它，不走酷狗取流。
    var localURL: URL? = nil

    var durationText: String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func from(_ d: JSON) -> Song? {
        // 榜单 /rank/audio 把 hash、时长、封面放在 audio_info / album_info 里。
        let row = flattened(d)
        guard let hash = J.str(row, "hash", "FileHash"), !hash.isEmpty else { return nil }
        let name = J.str(row, "songname", "audio_name", "FileName", "filename", "name", "ori_audio_name") ?? "未知歌曲"
        var artist = J.str(row, "author_name", "singername", "SingerName") ?? ""
        if artist.isEmpty, let singers = row["singerinfo"] as? [JSON] {
            artist = singers.compactMap { J.str($0, "name") }.joined(separator: "、")
        }
        if artist.isEmpty, let authors = row["authors"] as? [JSON] {
            artist = authors.compactMap { J.str($0, "author_name", "name") }.joined(separator: "、")
        }
        if artist.isEmpty { artist = "未知歌手" }
        let ms = J.double(row, "time_length", "timelength", "timelen", "Duration", "duration_128") ?? 0
        let seconds = ms > 10000 ? ms / 1000 : ms
        var album = J.str(row, "album_name", "AlbumName") ?? ""
        if album.isEmpty, let info = row["albuminfo"] as? JSON {
            album = J.str(info, "name", "albumname") ?? ""
        }
        let coverRaw = J.str(row, "sizable_cover", "album_sizable_cover", "cover", "img", "album_img", "Image")
        return Song(
            id: hash,
            hash: hash,
            albumId: J.int(row, "album_id", "AlbumID") ?? 0,
            albumAudioId: albumAudioIdentifier(from: row),
            name: name,
            artist: artist,
            album: album,
            cover: coverRaw.flatMap { URL(string: sized($0, 240)) },
            duration: seconds
        )
    }

    /// 把榜单接口的嵌套字段提到顶层，让后面的宽松取值器和普通搜索结果走同一套逻辑。
    /// hash 只用 mp3 的 hash_128 / hash_320，不用 trans_param 里的 ogg hash。
    private static func flattened(_ data: JSON) -> JSON {
        var row = data
        if let audio = data["audio_info"] as? JSON {
            if row["hash"] == nil, let hash = J.str(audio, "hash_128", "hash_320", "hash") {
                row["hash"] = hash
            }
            if row["timelen"] == nil, let ms = J.double(audio, "duration_128", "duration_320", "duration") {
                row["timelen"] = ms
            }
        }
        if let album = data["album_info"] as? JSON {
            if row["album_name"] == nil, let name = J.str(album, "album_name", "albumname") {
                row["album_name"] = name
            }
            if row["sizable_cover"] == nil, let cover = J.str(album, "sizable_cover", "cover") {
                row["sizable_cover"] = cover
            }
        }
        if let deprecated = data["deprecated"] as? JSON {
            if row["hash"] == nil, let hash = J.str(deprecated, "hash") {
                row["hash"] = hash
            }
            if row["timelen"] == nil, let ms = J.double(deprecated, "duration") {
                row["timelen"] = ms
            }
        }
        if row["sizable_cover"] == nil, let trans = data["trans_param"] as? JSON,
           let cover = J.str(trans, "union_cover") {
            row["sizable_cover"] = cover
        }
        return row
    }

    // `/song/url` 的 album_audio_id 必须是 mixsongid。
    // 歌单里的 audio_id 是另一套编号，传上去会拿到 AVPlayer 播不了的 ogg。
    private static func albumAudioIdentifier(from data: JSON) -> Int {
        let keys = ["album_audio_id", "mixsongid", "MixSongID"]
        for key in keys {
            if let id = J.int(data, key), id > 0 { return id }
        }
        return 0
    }

    /// 云歌单的 name 常是「歌手 - 歌名.mp3」，展示时拆开，避免和歌手行重复。
    func cleanedCloudTitle() -> Song {
        var title = name.trimmingCharacters(in: .whitespaces)
        for ext in [".mp3", ".flac", ".ogg", ".m4a", ".wav", ".ape", ".wma"] where title.lowercased().hasSuffix(ext) {
            title = String(title.dropLast(ext.count))
            break
        }
        if artist != "未知歌手", let range = title.range(of: " - ") {
            let head = String(title[..<range.lowerBound])
            if head == artist || artist.hasPrefix(head) {
                title = String(title[range.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        guard !title.isEmpty, title != name else { return self }
        return Song(id: id, hash: hash, albumId: albumId, albumAudioId: albumAudioId,
                    name: title, artist: artist, album: album, cover: cover,
                    duration: duration, localURL: localURL)
    }
}

struct Playlist: Identifiable, Hashable {
    let id: String
    let name: String
    var cover: URL?
    let playCount: Int
    var trackCount: Int
    let tag: String
    let creator: String
    let intro: String

    static func from(_ d: JSON) -> Playlist? {
        // 歌单歌曲接口只认 global_collection_id；specialid 仅用于展示与跳转。
        guard let sid = J.str(d, "global_collection_id", "specialid", "specialId", "listid", "id")
        else { return nil }
        let coverRaw = J.str(d, "flexible_cover", "imgurl", "img_cover", "cover")
        return Playlist(
            id: sid,
            name: J.str(d, "specialname", "name", "title") ?? "未命名歌单",
            cover: coverRaw.flatMap { URL(string: sized($0, 480)) },
            playCount: J.int(d, "play_count", "playcount", "play_times", "show_play_count") ?? 0,
            trackCount: J.int(d, "percount", "songcount", "song_count", "count", "total") ?? 0,
            tag: (d["tags"] as? [JSON])?.compactMap { J.str($0, "tag_name") }.first ?? J.str(d, "tag", "special_tag") ?? "",
            creator: J.str(d, "nickname", "username", "create_user_name") ?? "",
            intro: J.str(d, "intro", "description") ?? ""
        )
    }
}

struct Rank: Identifiable, Hashable {
    let id: String
    let name: String
    var cover: URL?
    let playCount: Int
    let updateText: String

    static func from(_ d: JSON) -> Rank? {
        guard let rid = J.str(d, "rankid", "id") else { return nil }
        let raw = J.str(d, "img_9", "banner_9", "imgurl", "album_img_9", "img_cover")
        return Rank(
            id: rid,
            name: J.str(d, "rankname", "name") ?? "榜单",
            cover: raw.flatMap { URL(string: sized($0, 400)) },
            playCount: J.int(d, "play_times", "play_count") ?? 0,
            updateText: J.str(d, "update_frequency", "intro") ?? ""
        )
    }
}

struct Artist: Identifiable, Hashable {
    let id: String
    let name: String
    var avatar: URL?

    static func from(_ d: JSON) -> Artist? {
        guard let aid = J.str(d, "author_id", "singerid", "id", "AuthorId") else { return nil }
        let raw = J.str(d, "avatar", "sizable_avatar", "img", "pic")
        return Artist(
            id: aid,
            name: J.str(d, "author_name", "singername", "name") ?? "未知歌手",
            avatar: raw.flatMap { URL(string: sized($0, 240)) }
        )
    }
}

// MARK: - Utilities

/// 酷狗图片地址用 `{size}` 占位，替换成实际边长。
func sized(_ url: String, _ size: Int) -> String {
    url.replacingOccurrences(of: "{size}", with: "\(size)")
}

/// 12.8万 / 1.9万 / 8247 —— 与 cocomusic 的 formatCount 一致。
func formatCount(_ n: Int) -> String {
    if n >= 100_000_000 { return String(format: "%.1f亿", Double(n) / 100_000_000) }
    if n >= 10_000 { return String(format: "%.1f万", Double(n) / 10_000) }
    return "\(n)"
}
