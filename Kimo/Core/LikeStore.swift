//
//  LikeStore.swift
//  Kimo
//
//  播放栏爱心 ↔ 酷狗账号里的「我喜欢」。
//  用 hash 和 mixsongid 两边对齐：加入后酷狗可能换成另一条 hash。
//

import Foundation
import Observation

@MainActor
@Observable
final class LikeStore {
    private(set) var songs: [Song] = []
    private(set) var loading = false
    private(set) var errorText: String?

    private var listId: Int?
    private var byHash: [String: Int] = [:]
    private var byMix: [Int: Int] = [:]
    private var refreshing: Task<Void, Never>?
    private var busy = false

    func reset() {
        refreshing?.cancel()
        songs = []
        listId = nil
        byHash = [:]
        byMix = [:]
        errorText = nil
        loading = false
    }

    func isLiked(_ song: Song) -> Bool {
        fileId(for: song) != nil
    }

    func refresh() async {
        refreshing?.cancel()
        let task = Task { await load() }
        refreshing = task
        await task.value
    }

    /// 成功返回 nil。已喜欢则取消，否则加入。
    func toggle(_ song: Song) async -> String? {
        if busy { return nil }
        if song.localURL != nil { return "本地歌曲不能同步到酷狗的我喜欢" }
        busy = true
        defer { busy = false }
        if listId == nil { await refresh() }
        guard let listId else { return errorText ?? "还没有同步到酷狗账号" }

        if let fileId = fileId(for: song) {
            guard fileId > 0 else { return nil }
            drop(song)
            do {
                try await MusicAPI.shared.removeFromFavorites(listId: listId, fileId: fileId)
            } catch {
                await refresh()
                return error.localizedDescription
            }
            return nil
        }

        songs.insert(song, at: 0)
        byHash[song.hash.lowercased()] = 0
        if song.albumAudioId > 0 { byMix[song.albumAudioId] = 0 }
        do {
            try await MusicAPI.shared.addToFavorites(listId: listId, song: song)
        } catch {
            drop(song)
            return error.localizedDescription
        }
        await refresh()
        // 请求用的 hash 和云端存的 hash 可能不同，用 mixsongid 把两边接上。
        if song.albumAudioId > 0, let id = byMix[song.albumAudioId] {
            byHash[song.hash.lowercased()] = id
        }
        return nil
    }

    private func load() async {
        loading = songs.isEmpty
        errorText = nil
        defer { loading = false }
        do {
            guard let list = try await MusicAPI.shared.favoriteList() else {
                if !Task.isCancelled { errorText = "账号里没有「我喜欢」歌单" }
                return
            }
            if Task.isCancelled { return }
            listId = list.listId
            let tracks = try await MusicAPI.shared.favoriteTracks(listId: list.listId)
            if Task.isCancelled { return }
            // get_list_all_file 按 sort 从大到小返回，等于把歌单倒着给。
            // 酷狗「我喜欢」本身是 sort 从小到大，最近加入的在最上面。
            let ordered = Array(tracks.reversed())
            songs = ordered.map(\.song)
            byHash = [:]
            byMix = [:]
            for item in ordered {
                byHash[item.song.hash.lowercased()] = item.fileId
                if item.song.albumAudioId > 0 { byMix[item.song.albumAudioId] = item.fileId }
            }
        } catch {
            if !Task.isCancelled { errorText = error.localizedDescription }
        }
    }

    private func fileId(for song: Song) -> Int? {
        if let id = byHash[song.hash.lowercased()] { return id }
        if song.albumAudioId > 0 { return byMix[song.albumAudioId] }
        return nil
    }

    private func drop(_ song: Song) {
        let key = song.hash.lowercased()
        let doomed = songs.filter { item in
            item.hash.lowercased() == key
                || (song.albumAudioId > 0 && item.albumAudioId == song.albumAudioId)
        }
        for item in doomed {
            byHash.removeValue(forKey: item.hash.lowercased())
            if item.albumAudioId > 0 { byMix.removeValue(forKey: item.albumAudioId) }
        }
        byHash.removeValue(forKey: key)
        if song.albumAudioId > 0 { byMix.removeValue(forKey: song.albumAudioId) }
        let doomedHashes = Set(doomed.map { $0.hash.lowercased() })
        songs.removeAll { doomedHashes.contains($0.hash.lowercased()) }
    }
}

enum FavoriteError: LocalizedError {
    case failed(String)
    case expired

    var errorDescription: String? {
        switch self {
        case .failed(let message): return message
        case .expired: return "登录已失效，请重新扫码登录"
        }
    }
}
