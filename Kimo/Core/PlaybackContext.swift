import Foundation

// 播放入口作为值对象随歌曲保存，浏览页面变化不会改变播放来源。
enum PlaybackSource: Hashable, Codable {
    case queue
    case liked
    case playlist(id: String, title: String)
    case rank(id: String, title: String)
    case artist(id: String, title: String)
    case search(keyword: String)
    case recommended
    case newSongs
    case recent
    case local

    var title: String {
        switch self {
        case .queue: return "播放列表"
        case .liked: return "我喜欢"
        case .playlist(_, let title), .rank(_, let title), .artist(_, let title): return title
        case .search(let keyword): return "搜索：\(keyword)"
        case .recommended: return "推荐歌曲"
        case .newSongs: return "新歌速递"
        case .recent: return "最近播放"
        case .local: return "本地音乐"
        }
    }

    var symbol: String {
        switch self {
        case .liked: return "heart.fill"
        case .search: return "magnifyingglass"
        case .local: return "folder"
        case .recent: return "clock"
        default: return "music.note.list"
        }
    }
}

// 保留点歌时的完整列表；插播歌曲可携带自己的来源，不污染原歌单。
struct PlaybackContext: Codable, Equatable {
    let source: PlaybackSource
    let songs: [Song]

    // 收藏来源始终使用当前收藏数据，其他来源使用点歌时的列表快照。
    func resolvedSongs(likedSongs: [Song]) -> [Song] {
        source == .liked ? likedSongs : songs
    }
}
