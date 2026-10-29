//
//  LyricsEngine.swift
//  Kimo
//
//  歌词的唯一来源：按当前曲目拉取、按进度算当前行。
//  歌词页和桌面歌词都读它，避免同一首歌请求两次。
//

import Foundation
import Observation

@MainActor
@Observable
final class LyricsEngine {
    private(set) var lines: [MusicAPI.LyricLine] = []
    private(set) var loading = false
    private(set) var loadedHash = ""
    private(set) var errorText: String?

    private var task: Task<Void, Never>?

    /// 换歌时重新拉取；同一首歌不重复请求。
    func ensure(for song: Song?) {
        guard let song else {
            lines = []
            loadedHash = ""
            return
        }
        // 本地文件没有酷狗歌词，不做无谓请求。
        if song.localURL != nil {
            lines = []
            loadedHash = song.hash
            loading = false
            return
        }
        guard loadedHash != song.hash else { return }

        task?.cancel()
        loadedHash = song.hash
        lines = []
        errorText = nil
        loading = true

        task = Task { [weak self] in
            guard let self else { return }
            var result: [MusicAPI.LyricLine] = []
            var message: String?
            // 核心刚启动时可能连不上，重试两次。
            for attempt in 0..<3 {
                do {
                    result = try await MusicAPI.shared.lyrics(for: song)
                    message = nil
                } catch {
                    result = []
                    message = error.localizedDescription
                }
                if !result.isEmpty { break }
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                }
            }
            guard !Task.isCancelled, self.loadedHash == song.hash else { return }
            self.lines = result
            self.errorText = result.isEmpty ? message : nil
            self.loading = false
            // 仍然为空就放开锁，下次进入还能再试。
            if result.isEmpty { self.loadedHash = "" }
        }
    }

    /// 按播放进度取当前行下标（offset 为正表示歌词提前）。
    func index(at time: TimeInterval, offsetMs: Double = 0) -> Int? {
        guard !lines.isEmpty else { return nil }
        let t = time + offsetMs / 1000
        var current: Int?
        for (i, line) in lines.enumerated() where line.time <= t + 0.15 {
            current = i
        }
        return current
    }

    func line(at index: Int?) -> String? {
        guard let index, lines.indices.contains(index) else { return nil }
        return lines[index].text
    }

    func nextLine(after index: Int?) -> String? {
        let next = (index ?? -1) + 1
        guard lines.indices.contains(next) else { return nil }
        return lines[next].text
    }
}
