//
//  AppModel.swift
//  Kimo
//
//  全局状态：路由（带前进/后退栈）、侧栏折叠、主题、播放器。
//  对应 cocomusic 的 navigation.tsx / sidebar-state.ts / ApplyAppearance。
//

import Observation
import SwiftUI

enum Route: Hashable {
    case home
    case discover
    case artists
    case charts
    case liked
    case recent
    case local
    case downloads
    case settings
    case playlist(id: String, title: String)
    case rank(id: String, title: String)
    case artist(id: String, title: String)
    case search(keyword: String)

    var title: String {
        switch self {
        case .home: return "首页"
        case .discover: return "发现音乐"
        case .artists: return "歌手"
        case .charts: return "排行榜"
        case .liked: return "我喜欢"
        case .recent: return "最近播放"
        case .local: return "本地音乐"
        case .downloads: return "下载管理"
        case .settings: return "设置"
        case .playlist(_, let t): return t
        case .rank(_, let t): return t
        case .artist(_, let t): return t
        case .search(let k): return "搜索：\(k)"
        }
    }
}

@MainActor
@Observable
final class AppModel {
    var route: Route = .home
    private var backStack: [Route] = []
    private var forwardStack: [Route] = []

    var sidebarCollapsed = false
    /// 系统外观（由 RootView 跟随 colorScheme 更新）。
    var systemIsDark = false
    var showQueue = false
    var showLogin = false
    var showLyrics = false
    var isMini = false
    var debugScroll: Double = 0
    var searchText = ""

    let settings: AppSettings
    let player: PlayerEngine
    let recent = RecentStore()
    let local = LocalLibrary()
    let lyrics = LyricsEngine()
    let likes = LikeStore()

    init() {
        let settings = AppSettings()
        self.settings = settings
        self.player = PlayerEngine(settings: settings)
        player.onTrackStarted = { [weak self] song in
            self?.recent.record(song)
            self?.lyrics.ensure(for: song)
        }
        applyDebugRoute()
    }

    /// 设置里的「深色」按钮：直接改 themeMode，而不是一个独立状态。
    var isDark: Bool {
        get { settings.themeMode == .dark }
        set { settings.themeMode = newValue ? .dark : .light }
    }

    var resolvedIsDark: Bool {
        if let fixed = settings.skin.forcesDark { return fixed }
        switch settings.themeMode {
        case .light: return false
        case .dark: return true
        case .system: return systemIsDark
        }
    }

    var theme: Theme { Theme.make(settings: settings, isDark: resolvedIsDark) }
    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// 开发期截图用：环境变量或 Application Support/Kimo/debug.json 指定初始页面。
    /// 例：{"route":"playlist","id":"collection_3_...","title":"歌单","dark":true,"login":true}
    private func applyDebugRoute() {
        var env = ProcessInfo.processInfo.environment
        if let debugFile = Self.debugFileURL,
           let data = try? Data(contentsOf: debugFile),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (k, v) in dict {
                if let s = v as? String { env[k.uppercased()] = s }
                if let b = v as? Bool { env[k.uppercased()] = b ? "1" : "0" }
                if let n = v as? Int { env[k.uppercased()] = "\(n)" }
            }
        }
        if let pos = env["POSITION"], let seconds = Double(pos) {
            Task {
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                self.player.seek(to: seconds)
            }
        }
        if env["DESKTOPLYRICS"] == "1" {
            Task {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                DesktopLyricsController.shared.bind(self)
                DesktopLyricsController.shared.show()
            }
        }
        if env["MINI"] == "1" || env["KIMO_MINI"] == "1" {
            isMini = true
            WindowBridge.shared.setMini(true)
        }
        if env["LOGIN"] == "1" || env["KIMO_LOGIN"] == "1" { showLogin = true }
        if env["QUEUE"] == "1" || env["KIMO_QUEUE"] == "1" { showQueue = true }
        if env["LYRICS"] == "1" || env["KIMO_LYRICS"] == "1" { showLyrics = true }
        if env["DARK"] == "1" || env["KIMO_DARK"] == "1" { settings.themeMode = .dark }
        if let s = env["SCROLL"] ?? env["KIMO_SCROLL"], let v = Double(s) { debugScroll = v }

        guard let name = env["ROUTE"] ?? env["KIMO_ROUTE"] else {
            applyDebugSong(env)
            return
        }
        let id = env["ID"] ?? env["KIMO_ID"] ?? ""
        switch name {
        case "playlist": route = .playlist(id: id, title: env["TITLE"] ?? env["KIMO_TITLE"] ?? "歌单")
        case "rank": route = .rank(id: id, title: env["TITLE"] ?? env["KIMO_TITLE"] ?? "榜单")
        case "charts": route = .charts
        case "discover": route = .discover
        case "search": route = .search(keyword: env["TITLE"] ?? env["KIMO_TITLE"] ?? "周杰伦")
        case "settings": route = .settings
        case "artist": route = .artist(id: id, title: env["TITLE"] ?? env["KIMO_TITLE"] ?? "歌手")
        case "recent": route = .recent
        case "local": route = .local
        case "artists": route = .artists
        default: route = .home
        }
        applyDebugSong(env)
    }

    /// 截图用：{"song":"<hash>","title":"…","artist":"…","albumId":"…"} 直接把歌塞进播放器。
    private func applyDebugSong(_ env: [String: String]) {
        if let path = env["LOCALPATH"], !path.isEmpty {
            local.importFrom(urls: [URL(fileURLWithPath: path)])
            if env["LOCALPLAY"] == "1" {
                Task {
                    try? await Task.sleep(nanoseconds: 2_500_000_000)
                    let songs = self.local.tracks.map(\.song)
                    if let first = songs.first { self.player.play(first, queue: songs) }
                }
            }
        }
        if env["RECENTDEMO"] == "1" {
            for (i, name) in ["晴天", "七里香", "夜曲", "稻香", "告白气球", "安静"].enumerated() {
                recent.record(Song(id: "demo-\(i)", hash: "demo-\(i)", albumId: 0, albumAudioId: 0,
                                   name: name, artist: "周杰伦", album: "叶惠美", cover: nil, duration: 269))
            }
        }
        if env["QUEUEDEMO"] == "1" || env["QUEUE_DEMO"] == "1" {
            let demo = ["晴天", "七里香", "夜曲", "稻香", "告白气球", "安静"].enumerated().map { i, name in
                Song(id: "demo-\(i)", hash: "demo-\(i)", albumId: 0, albumAudioId: 0,
                     name: name, artist: "周杰伦", album: "叶惠美", cover: nil, duration: 269)
            }
            player.setQueueForPreview(demo, currentIndex: 1)
        }
        guard let hash = env["SONG"] ?? env["KIMO_SONG"], !hash.isEmpty else { return }
        let song = Song(
            id: hash,
            hash: hash,
            albumId: Int(env["ALBUMID"] ?? "") ?? 0,
            albumAudioId: Int(env["AUDIOID"] ?? "") ?? 0,
            name: env["TITLE"] ?? "调试曲目",
            artist: env["ARTIST"] ?? "未知歌手",
            album: env["ALBUM"] ?? "",
            cover: (env["COVER"]).flatMap { URL(string: $0) },
            duration: 245
        )
        player.loadForPreview(song)
        lyrics.ensure(for: song)
        if env["AUTOPLAY"] == "1" {
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                self.player.play(song, queue: [song])
            }
        }
    }

    static var debugFileURL: URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        return base.appendingPathComponent("Kimo/debug.json")
    }

    func navigate(_ next: Route) {
        guard next != route else { return }
        backStack.append(route)
        forwardStack.removeAll()
        route = next
    }

    func back() {
        guard let last = backStack.popLast() else { return }
        forwardStack.append(route)
        route = last
    }

    func forward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(route)
        route = next
    }

    func setMini(_ mini: Bool) {
        guard mini != isMini else { return }
        isMini = mini
        WindowBridge.shared.setMini(mini)
    }

    func toggleSidebar() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            sidebarCollapsed.toggle()
        }
    }

    func submitSearch() {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        navigate(.search(keyword: q))
    }
}
