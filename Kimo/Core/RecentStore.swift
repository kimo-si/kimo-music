//
//  RecentStore.swift
//  Kimo
//
//  最近播放：本机记录，最多 200 条，按最后一次播放时间倒序。
//  与 cocomusic 的 recent-plays.ts 行为一致（同一首歌只保留一条）。
//

import Foundation
import Observation

@MainActor
@Observable
final class RecentStore {
    private(set) var songs: [Song] = []
    private let limit = 200

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Kimo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("recent.json")
    }

    init() { load() }

    func record(_ song: Song) {
        songs.removeAll { $0.hash == song.hash }
        songs.insert(song, at: 0)
        if songs.count > limit { songs.removeLast(songs.count - limit) }
        save()
    }

    func clear() {
        songs.removeAll()
        save()
    }

    // MARK: - 持久化

    private struct Stored: Codable {
        let hash: String
        let name: String
        let artist: String
        let album: String
        let albumId: Int
        let albumAudioId: Int
        let cover: String?
        let duration: Double
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([Stored].self, from: data) else { return }
        songs = list.map {
            Song(id: $0.hash, hash: $0.hash, albumId: $0.albumId, albumAudioId: $0.albumAudioId,
                 name: $0.name, artist: $0.artist, album: $0.album,
                 cover: $0.cover.flatMap { URL(string: $0) }, duration: $0.duration)
        }
    }

    private func save() {
        let list = songs.map {
            Stored(hash: $0.hash, name: $0.name, artist: $0.artist, album: $0.album,
                   albumId: $0.albumId, albumAudioId: $0.albumAudioId,
                   cover: $0.cover?.absoluteString, duration: $0.duration)
        }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: Self.fileURL)
        }
    }
}
