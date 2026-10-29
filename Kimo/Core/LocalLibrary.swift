//
//  LocalLibrary.swift
//  Kimo
//
//  本地音乐库：选择文件/文件夹 → 扫描音频 → 读元数据 → 落盘。
//  播放时直接走 AVPlayer 的本地文件，不经过酷狗取流，所以不需要登录。
//

import AVFoundation
import Foundation
import Observation
import SwiftUI

struct LocalTrack: Identifiable, Hashable {
    let path: String
    let name: String
    let artist: String
    let album: String
    let duration: TimeInterval

    var id: String { path }

    var song: Song {
        Song(
            id: path,
            hash: path,
            albumId: 0,
            albumAudioId: 0,
            name: name,
            artist: artist,
            album: album,
            cover: nil,
            duration: duration,
            localURL: URL(fileURLWithPath: path)
        )
    }
}

@MainActor
@Observable
final class LocalLibrary {
    private(set) var tracks: [LocalTrack] = []
    private(set) var importing = false
    private(set) var scanned = 0
    private(set) var pending = 0

    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "flac", "wav", "aiff", "aif", "aac", "ogg", "opus", "wma",
    ]

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Kimo", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("local.json")
    }

    init() { load() }

    // MARK: - 导入

    /// 展开文件夹，返回所有音频文件。
    func collectAudioFiles(from urls: [URL]) -> [URL] {
        var out: [URL] = []
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey]
                guard let e = fm.enumerator(at: url, includingPropertiesForKeys: keys,
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
                for case let file as URL in e where Self.audioExtensions.contains(file.pathExtension.lowercased()) {
                    out.append(file)
                }
            } else if Self.audioExtensions.contains(url.pathExtension.lowercased()) {
                out.append(url)
            }
        }
        return out
    }

    func importFrom(urls: [URL]) {
        let files = collectAudioFiles(from: urls)
        guard !files.isEmpty else { return }
        let existing = Set(tracks.map(\.path))
        let fresh = files.filter { !existing.contains($0.path) }
        guard !fresh.isEmpty else { return }

        importing = true
        pending = fresh.count
        scanned = 0

        Task {
            var loaded: [LocalTrack] = []
            for url in fresh {
                if let track = await Self.readTrack(url) {
                    loaded.append(track)
                }
                scanned += 1
            }
            tracks.append(contentsOf: loaded)
            tracks.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            importing = false
            save()
        }
    }

    /// 用 AVAsset 读标题/歌手/专辑/时长；读不到就用文件名。
    private static func readTrack(_ url: URL) async -> LocalTrack? {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "未知歌手"
        var album = ""
        var duration: TimeInterval = 0

        if let d = try? await asset.load(.duration) {
            let s = d.seconds
            if s.isFinite, s > 0 { duration = s }
        }

        if let items = try? await asset.load(.commonMetadata) {
            for item in items {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case .commonKeyArtist, .commonKeyAuthor:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case .commonKeyAlbumName:
                    if let v = try? await item.load(.stringValue), !v.isEmpty { album = v }
                default: break
                }
            }
        }

        return LocalTrack(path: url.path, name: title, artist: artist, album: album, duration: duration)
    }

    // MARK: - 维护

    func remove(_ track: LocalTrack) {
        tracks.removeAll { $0.path == track.path }
        save()
    }

    func clear() {
        tracks.removeAll()
        save()
    }

    // MARK: - 持久化

    private struct Stored: Codable {
        let path: String
        let name: String
        let artist: String
        let album: String
        let duration: Double
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let list = try? JSONDecoder().decode([Stored].self, from: data) else { return }
        let fm = FileManager.default
        tracks = list.compactMap { item in
            // 文件被删掉就顺手清掉记录
            guard fm.fileExists(atPath: item.path) else { return nil }
            return LocalTrack(path: item.path, name: item.name, artist: item.artist,
                              album: item.album, duration: item.duration)
        }
    }

    private func save() {
        let list = tracks.map {
            Stored(path: $0.path, name: $0.name, artist: $0.artist,
                   album: $0.album, duration: $0.duration)
        }
        if let data = try? JSONEncoder().encode(list) {
            try? data.write(to: Self.fileURL)
        }
    }
}
