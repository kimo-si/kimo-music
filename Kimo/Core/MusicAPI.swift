//
//  MusicAPI.swift
//  Kimo
//
//  业务接口封装：把酷狗原始返回映射成 Kimo 的领域模型。
//  接口路径与 MoeKoeMusic 内置 API 完全一致（/module 名，下划线转斜杠）。
//

import Foundation

@MainActor
final class MusicAPI {
    static let shared = MusicAPI()
    private static let hotArtistsGroupTitle = "热门"
    private static let unsupportedStreamFormats: Set<String> = ["mp4", "ogg", "oga", "opus"]
    private let core = CoreService.shared

    // MARK: - 首页

    func featuredPlaylists(page: Int = 1, size: Int = 12) async throws -> [Playlist] {
        let payload = try await core.get("/top/playlist", [
            "category_id": "0", "page": "\(page)", "pagesize": "\(size)", "withtag": "1",
        ])
        let dict = payload as? JSON ?? [:]
        let list = J.array(dict, "special_list").isEmpty
            ? J.array(dict, "info")
            : J.array(dict, "special_list")
        // 分类 0 是推荐流，pagesize 会被忽略（固定返回 35 条），这里自己截断。
        return list.prefix(size).compactMap { Playlist.from($0) }
    }

    func recommendedSongs() async throws -> [Song] {
        let payload = try await core.get("/everyday/recommend")
        let dict = payload as? JSON ?? [:]
        return J.array(dict, "song_list").compactMap { Song.from($0) }
    }

    struct NewSongsPage {
        let songs: [Song]
        let hasMore: Bool
    }

    // 获取一页新歌，并保留接口的分页信息。
    func newSongs(page: Int, size: Int) async throws -> NewSongsPage {
        // 请求音乐核心的新歌速递接口。
        let response = try await core.getRaw("/top/song", ["page": "\(page)", "pagesize": "\(size)"])
        // 校验上游响应并映射为歌曲领域对象。
        let items = try newSongItems(from: response)
        return NewSongsPage(songs: items.compactMap { Song.from($0) }, hasMore: items.count >= size)
    }

    // 区分接口错误、正常空页与歌曲列表。
    private func newSongItems(from response: JSON) throws -> [JSON] {
        // 验证上游状态后读取数据节点。
        let data = try responseData(from: response, fallback: "新歌速递暂时不可用")
        if let items = data as? [JSON] { return items }
        if let empty = data as? JSON, empty.isEmpty { return [] }
        throw CoreError.shape
    }

    // 统一校验音乐接口的状态，并保留上游错误信息。
    private func responseData(from response: JSON, fallback: String) throws -> Any {
        if let status = J.int(response, "status"), status != 1 {
            throw CoreError.service(J.str(response, "error", "errmsg", "msg") ?? fallback)
        }
        guard let data = response["data"] else { throw CoreError.shape }
        return data
    }

    func charts(limit: Int = 4) async throws -> [Rank] {
        let payload = try await core.get("/rank/list")
        let dict = payload as? JSON ?? [:]
        return J.array(dict, "info").compactMap { Rank.from($0) }.prefix(limit).map { $0 }
    }

    // MARK: - 歌手

    struct ArtistProfile {
        let id: String
        let name: String
        var avatar: URL?
        let fans: Int
        let albumCount: Int
        let mvCount: Int
        let intro: String
    }

    // 获取热门分组中的歌手，避免混入按字母排列的普通歌手。
    func hotArtists(limit: Int = 30) async throws -> [Artist] {
        guard limit > 0 else { return [] }
        // 调用歌手列表接口并校验返回状态。
        let response = try await core.getRaw("/artist/lists", ["hotsize": "\(limit)"])
        let data = try responseData(from: response, fallback: "热门歌手暂时不可用")
        guard let payload = data as? JSON, let groups = payload["info"] as? [JSON] else { throw CoreError.shape }
        guard !groups.isEmpty else { return [] }
        guard let hot = groups.first(where: { J.str($0, "title") == Self.hotArtistsGroupTitle }),
              let entries = hot["singer"] as? [JSON] else { throw CoreError.shape }
        // 映射歌手并按 ID 去重，保持接口返回顺序。
        return uniqueArtists(from: entries, limit: limit)
    }

    // 将热门分组映射为不重复的歌手对象。
    private func uniqueArtists(from entries: [JSON], limit: Int) -> [Artist] {
        var seen = Set<String>()
        let artists = entries.compactMap { artistFromListEntry($0) }
            .filter { seen.insert($0.id).inserted }
        return Array(artists.prefix(limit))
    }

    // 兼容歌手列表中的头像与名称字段。
    private func artistFromListEntry(_ d: JSON) -> Artist? {
        guard let id = J.str(d, "singerid", "author_id", "id") else { return nil }
        var raw = J.str(d, "sizable_avatar", "avatar")
        if raw == nil, let cover = d["dycover"] as? JSON {
            raw = J.str(cover, "first_frame_image")
        }
        if raw == nil { raw = J.str(d, "imgurl", "pic") }
        return Artist(
            id: id,
            name: J.str(d, "singername", "author_name", "name") ?? "未知歌手",
            avatar: raw.flatMap { URL(string: sized($0, 240)) }
        )
    }

    func artistProfile(id: String) async throws -> ArtistProfile {
        let payload = try await core.get("/artist/detail", ["id": id])
        let dict = payload as? JSON ?? [:]
        var intro = ""
        if let blocks = dict["long_intro"] as? [JSON] {
            intro = blocks.compactMap { J.str($0, "content") }.joined(separator: "\n")
        }
        if intro.isEmpty { intro = J.str(dict, "intro") ?? "" }
        return ArtistProfile(
            id: J.str(dict, "author_id", "singerid") ?? id,
            name: J.str(dict, "author_name", "singername") ?? "未知歌手",
            avatar: J.str(dict, "sizable_avatar", "avatar").flatMap { URL(string: sized($0, 480)) },
            fans: J.int(dict, "fansnums", "fanscount") ?? 0,
            albumCount: J.int(dict, "album_count", "albumcount") ?? 0,
            mvCount: J.int(dict, "mv_count", "mvcount") ?? 0,
            intro: intro
        )
    }

    func artistSongs(id: String, page: Int = 1, size: Int = 60, hot: Bool = true) async throws -> [Song] {
        let payload = try await core.get("/artist/audios", [
            "id": id, "page": "\(page)", "pagesize": "\(size)", "sort": hot ? "hot" : "new",
        ])
        let list: [JSON]
        if let arr = payload as? [JSON] {
            list = arr
        } else {
            list = J.array(payload as? JSON ?? [:], "data")
        }
        return list.compactMap { Song.from($0) }
    }

    // MARK: - 搜索

    func search(_ keyword: String, page: Int = 1, size: Int = 30) async throws -> [Song] {
        let payload = try await core.get("/search", [
            "keywords": keyword, "type": "song", "page": "\(page)", "pagesize": "\(size)",
        ])
        let dict = payload as? JSON ?? [:]
        return J.array(dict, "lists").compactMap { Song.from($0) }
    }

    // 输入联想来自酷狗搜索提示接口，空输入无需发起请求。
    func searchSuggestions(_ keyword: String) async throws -> [String] {
        let word = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return [] }
        // 调用同一音乐核心，并沿用统一的接口状态校验。
        let response = try await core.getRaw("/search/suggest", ["keywords": word, "musicTipCount": "6"])
        let payload = try responseData(from: response, fallback: "搜索建议暂时不可用")
        return Self.suggestionKeywords(from: payload)
    }

    // 仅提取通用词组，按上游顺序去重，最多展示六条。
    static func suggestionKeywords(from payload: Any) -> [String] {
        guard let group = (payload as? [JSON])?.first else { return [] }
        var seen = Set<String>()
        let words = J.array(group, "RecordDatas").compactMap { row -> String? in
            guard let value = row["HintInfo"] as? String else { return nil }
            let word = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return !word.isEmpty && seen.insert(word).inserted ? word : nil
        }
        return Array(words.prefix(6))
    }

    // MARK: - 歌单

    func playlistTracks(id: String, page: Int = 1, size: Int = 60) async throws -> [Song] {
        let payload = try await core.get("/playlist/track/all", [
            "id": id, "page": "\(page)", "pagesize": "\(size)",
        ])
        let dict = payload as? JSON ?? [:]
        return J.array(dict, "songs").compactMap { Song.from($0) }
    }

    /// 一次性把歌单的曲目数补齐。/playlist/detail 支持 ids 逗号分隔，但超过 3 个
    /// 就会返回 20010（参数错误），所以按 3 个一批并发请求。
    func playlistCounts(ids: [String]) async throws -> [String: Int] {
        guard !ids.isEmpty else { return [:] }
        let chunks = stride(from: 0, to: ids.count, by: 3).map {
            Array(ids[$0..<min($0 + 3, ids.count)])
        }
        var out: [String: Int] = [:]
        try await withThrowingTaskGroup(of: [String: Int].self) { group in
            for chunk in chunks {
                group.addTask { [core] in
                    let payload = try await core.get("/playlist/detail", ["ids": chunk.joined(separator: ",")])
                    let list = payload as? [JSON] ?? []
                    var map: [String: Int] = [:]
                    for item in list {
                        if let gid = J.str(item, "global_collection_id"), let n = J.int(item, "count") {
                            map[gid] = n
                        }
                    }
                    return map
                }
            }
            for try await part in group {
                out.merge(part) { a, _ in a }
            }
        }
        return out
    }

    func rankTracks(rankId: String, page: Int = 1, size: Int = 60) async throws -> [Song] {
        let payload = try await core.get("/rank/audio", [
            "rankid": rankId, "page": "\(page)", "pagesize": "\(size)",
        ])
        let dict = payload as? JSON ?? [:]
        let rows = J.array(dict, "songlist")
        return (rows.isEmpty ? J.array(dict, "info") : rows).compactMap { Song.from($0) }
    }

    // MARK: - 播放

    struct StreamInfo {
        let url: URL
        let bitrate: Int
    }

    /// 取音频地址。登录态由核心带上，酷狗按这个账号的权益返回能播的音质。
    /// 请求音质拿不到时往下降，直到 128。`url` 是字符串数组，不在 `data` 里。
    /// 「我喜欢」常存 ogg hash；把 audio_id 当 album_audio_id 也会返回 ogg。
    /// AVPlayer 播不了 ogg，所以遇到不支持的格式会改 mixsongid / 改用 std_hash 再试。
    func streamURL(for song: Song, quality: String = "128") async throws -> StreamInfo {
        var blocked = false
        var pending = [song.hash]
        var seen = Set<String>()
        let albumAudioIds = song.albumAudioId > 0 ? [song.albumAudioId, 0] : [0]
        var index = 0
        while index < pending.count {
            let hash = pending[index]
            index += 1
            let token = hash.lowercased()
            if seen.contains(token) { continue }
            seen.insert(token)
            for candidate in Self.qualityChain(quality) {
                for albumAudioId in albumAudioIds {
                    let dict = try await core.getRaw("/song/url", [
                        "hash": hash,
                        "album_id": "\(song.albumId)",
                        "album_audio_id": "\(albumAudioId)",
                        "quality": candidate,
                    ])
                    if let info = try Self.stream(from: dict, fallbackBitrate: candidate) {
                        return info
                    }
                    blocked = true
                    if let std = J.str(dict, "std_hash"), std.count >= 32,
                       !seen.contains(std.lowercased()) {
                        pending.append(std)
                    }
                }
            }
        }
        throw PlaybackError.unavailable(blocked ? "当前账号没有这首歌的播放权限" : "无法获取播放地址")
    }

    /// 从高到低：flac → 320 → 128，只保留请求音质及其以下。
    private static func qualityChain(_ quality: String) -> [String] {
        let ladder = ["128", "320", "flac"]
        let selected = ladder.contains(quality) ? quality : "128"
        guard let index = ladder.firstIndex(of: selected) else { return ["128"] }
        return Array(ladder[0...index].reversed())
    }

    /// 成功时返回地址；这一档没有权益时返回 nil，交给下一档。登录失效和风控直接抛出。
    private static func stream(from dict: JSON, fallbackBitrate: String) throws -> StreamInfo? {
        let errcode = J.int(dict, "errcode", "error_code") ?? 0
        if errcode == 20017 || errcode == 20018 {
            throw PlaybackError.sessionExpired
        }
        if errcode == 20028 {
            throw PlaybackError.verificationRequired
        }
        if errcode != 0 {
            throw PlaybackError.unavailable(J.str(dict, "error", "errmsg", "error_msg") ?? "无法获取播放地址")
        }
        guard (J.int(dict, "status") ?? 0) == 1, let raw = firstURL(dict) else { return nil }
        let cleaned = raw.replacingOccurrences(of: "\\/", with: "/")
        let ext = (J.str(dict, "extName", "extname") ?? URL(string: cleaned)?.pathExtension ?? "").lowercased()
        guard !unsupportedStreamFormats.contains(ext), let url = URL(string: cleaned) else { return nil }
        let rate = J.int(dict, "bitRate", "bitrate") ?? 0
        let kbps: Int
        if rate > 1000 {
            kbps = rate / 1000
        } else if rate > 0 {
            kbps = rate
        } else {
            kbps = Int(fallbackBitrate) ?? 999
        }
        return StreamInfo(url: url, bitrate: kbps)
    }

    private static func firstURL(_ dict: JSON) -> String? {
        if let text = J.str(dict, "play_url", "playUrl"), text.hasPrefix("http") { return text }
        if let text = dict["url"] as? String, text.hasPrefix("http") { return text }
        let lists = (dict["url"] as? [Any] ?? []) + (dict["backupUrl"] as? [Any] ?? [])
        for item in lists {
            if let text = item as? String, text.hasPrefix("http") { return text }
        }
        return nil
    }

    // MARK: - 我喜欢

    struct FavoriteList {
        let listId: Int
        let count: Int
    }

    struct FavoriteTrack {
        let song: Song
        let fileId: Int
    }

    /// 账号里的「我喜欢」。is_def = 2 是酷狗默认收藏歌单。
    func favoriteList() async throws -> FavoriteList? {
        let dict = try await core.getRaw("/user/playlist", ["page": "1", "pagesize": "100"])
        try Self.requireOK(dict, fallback: "读取我喜欢失败")
        let data = dict["data"] as? JSON ?? [:]
        guard let liked = J.array(data, "info").first(where: { item in
            J.str(item, "name") == "我喜欢" || (J.int(item, "is_def") ?? 0) == 2
        }), let listId = J.int(liked, "listid") else { return nil }
        return FavoriteList(listId: listId, count: J.int(liked, "count") ?? 0)
    }

    func favoriteTracks(listId: Int) async throws -> [FavoriteTrack] {
        var page = 1
        var out: [FavoriteTrack] = []
        var total = Int.max
        while out.count < total, page <= 20 {
            let dict = try await core.getRaw("/playlist/track/all/new", [
                "listid": "\(listId)",
                "page": "\(page)",
                "pagesize": "300",
                "type": "0",
            ])
            try Self.requireOK(dict, fallback: "读取我喜欢失败")
            let data = dict["data"] as? JSON ?? [:]
            total = J.int(data, "count") ?? out.count
            let info = J.array(data, "info")
            if info.isEmpty { break }
            for row in info {
                guard let song = Song.from(row)?.cleanedCloudTitle(),
                      let fileId = J.int(row, "fileid"), fileId > 0 else { continue }
                out.append(FavoriteTrack(song: song, fileId: fileId))
            }
            if info.count < 300 { break }
            page += 1
        }
        return out
    }

    /// 歌名用占位符。空字符串会被酷狗判成 20010，真正的歌名由 hash 解析。
    func addToFavorites(listId: Int, song: Song) async throws {
        let dict = try await core.getRaw("/playlist/tracks/add", [
            "listid": "\(listId)",
            "data": "-|\(song.hash)|\(song.albumId)|\(song.albumAudioId)",
        ])
        try Self.requireOK(dict, fallback: "加入我喜欢失败")
    }

    func removeFromFavorites(listId: Int, fileId: Int) async throws {
        let dict = try await core.getRaw("/playlist/tracks/del", [
            "listid": "\(listId)",
            "fileids": "\(fileId)",
        ])
        try Self.requireOK(dict, fallback: "取消喜欢失败")
    }

    private static func requireOK(_ dict: JSON, fallback: String) throws {
        let code = J.int(dict, "error_code") ?? 0
        let status = J.int(dict, "status") ?? 0
        if code == 20017 || code == 20018 {
            throw FavoriteError.expired
        }
        if status != 1 || code != 0 {
            let message = J.str(dict, "error", "errmsg", "error_msg") ?? "\(fallback)（\(code)）"
            throw FavoriteError.failed(message)
        }
    }

    // MARK: - 歌词

    struct LyricLine: Identifiable {
        let id = UUID()
        let time: TimeInterval
        let text: String
    }

    func lyrics(for song: Song) async throws -> [LyricLine] {
        // 1) 先按 hash 找歌词候选，拿到 id + accesskey
        let searchPayload = try await core.get("/search/lyric", ["hash": song.hash])
        let dict = searchPayload as? JSON ?? [:]
        guard let candidate = J.array(dict, "candidates").first,
              let lid = J.str(candidate, "id"),
              let key = J.str(candidate, "accesskey") else { return [] }

        // 2) 下载并解码
        let payload = try await core.get("/lyric", ["id": lid, "accesskey": key, "decode": "true", "fmt": "lrc"])
        let lyricDict = payload as? JSON ?? [:]
        let text = J.str(lyricDict, "decodeContent") ?? J.str(lyricDict, "content") ?? ""
        return parseLRC(text)
    }

    private func parseLRC(_ text: String) -> [LyricLine] {
        var out: [LyricLine] = []
        // 酷狗返回的 LRC 可能只用 \r 分行（Mac 风格），所以按任意换行符切。
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = String(raw)
            guard let close = line.firstIndex(of: "]"), line.hasPrefix("[") else { continue }
            let stamp = String(line[line.index(after: line.startIndex)..<close])
            let body = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty else { continue }
            let parts = stamp.split(separator: ":")
            guard parts.count >= 2,
                  let m = Double(parts[0]),
                  let s = Double(parts[1]) else { continue }
            out.append(LyricLine(time: m * 60 + s, text: body))
        }
        return out.sorted { $0.time < $1.time }
    }
}

enum PlaybackError: LocalizedError {
    case unavailable(String)
    case needLogin
    case sessionExpired
    case verificationRequired

    var errorDescription: String? {
        switch self {
        case .unavailable(let m): return m
        case .needLogin: return "需要登录酷狗账号才能播放"
        case .sessionExpired: return "登录已失效，请重新扫码登录"
        case .verificationRequired: return "播放被安全验证拦住了，请稍后重试"
        }
    }
}
