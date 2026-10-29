//
//  CoreService.swift
//  Kimo
//
//  把 MoeKoeMusic 的核心（kugoumusicapi + express 路由）作为子进程托管，
//  原生端只通过 127.0.0.1 的 HTTP 访问它，与 MoeKoeMusic 网页端调用的是同一套接口。
//

import Foundation

@MainActor
final class CoreService {
    static let shared = CoreService()

    private(set) var isReady = false
    private(set) var lastError: String?
    private var process: Process?
    private let port: Int = 6520
    private var baseURL: URL { URL(string: "http://127.0.0.1:\(port)")! }

    private var bootTask: Task<Void, Never>?

    /// 登录后的 `token=..; userid=..`，随每个请求以 Authorization 头发给核心。
    /// 核心用 cookieToJson 解析后合并进 cookie，与网页端行为一致。
    private var authCookie: String?

    func setAuthCookie(_ cookie: String?) {
        authCookie = cookie
    }

    // MARK: - Lifecycle

    func boot() {
        guard bootTask == nil else { return }
        bootTask = Task { await startCore() }
    }

    /// 核心被外部杀掉（例如上一个实例退出）时重新拉起，并等它就绪。
    private func restart() async {
        process?.terminate()
        process = nil
        isReady = false
        await startCore()
    }

    private func startCore() async {
        // 1) 外部已经跑了一份核心（开发期 `npm run core`），直接复用。
        if await ping() { isReady = true; return }

        // 2) 启动子进程。
        guard let script = locateServerScript() else {
            lastError = "找不到 CoreRuntime/server.mjs"
            return
        }
        guard let node = locateNode() else {
            lastError = "找不到 Node.js 运行时（可安装 Node 20+，或把 node 放进 App 资源目录）"
            return
        }

        let p = Process()
        p.executableURL = node
        p.arguments = [script.path]
        p.currentDirectoryURL = script.deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["KIMO_CORE_PORT"] = "\(port)"
        env["KIMO_CORE_PLATFORM"] = "lite"
        if let dataDir = coreDataDirectory() {
            env["KIMO_CORE_DATA"] = dataDir.path
        }
        p.environment = env

        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { h in
            let d = h.availableData
            guard !d.isEmpty, let s = String(data: d, encoding: .utf8) else { return }
            #if DEBUG
            print("[core]", s.trimmingCharacters(in: .whitespacesAndNewlines))
            #endif
        }

        do {
            try p.run()
            process = p
        } catch {
            lastError = "核心启动失败：\(error.localizedDescription)"
            return
        }

        // 3) 等待端口就绪（最多 12 秒）。
        for _ in 0..<60 {
            if await ping() { isReady = true; return }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        lastError = "核心未在预期时间内就绪"
    }

    func shutdown() {
        process?.terminate()
        process = nil
    }

    // MARK: - Locations

    private func locateServerScript() -> URL? {
        // 打包后：Contents/Resources/CoreRuntime/server.mjs
        if let res = Bundle.main.resourceURL?
            .appendingPathComponent("CoreRuntime/server.mjs"),
           FileManager.default.fileExists(atPath: res.path) {
            return res
        }
        // 开发期：源码目录（可执行文件在 DerivedData 里，向上找到工程根）
        var dir = Bundle.main.bundleURL
        for _ in 0..<6 {
            let candidate = dir.appendingPathComponent("CoreRuntime/server.mjs")
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private func locateNode() -> URL? {
        if let bundled = Bundle.main.resourceURL?.appendingPathComponent("node"),
           FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        let candidates = [
            "/opt/homebrew/bin/node",
            "/usr/local/bin/node",
            "/usr/bin/node",
            "\(NSHomeDirectory())/.nvm/versions/node/bin/node",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) {
            return URL(fileURLWithPath: c)
        }
        // 退回 PATH 探测
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v node"]
        let out = Pipe()
        p.standardOutput = out
        try? p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        if let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty {
            return URL(fileURLWithPath: s)
        }
        return nil
    }

    private func coreDataDirectory() -> URL? {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = base.appendingPathComponent("Kimo/Core", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - HTTP

    private func ping() async -> Bool {
        var req = URLRequest(url: baseURL.appendingPathComponent("__kimo/health"))
        req.timeoutInterval = 1.5
        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            return (resp as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// 调用核心接口，返回 `data` 节点（没有 data 时返回根对象）。
    /// 连接被拒说明核心进程没了（上一个实例退出时会 terminate 掉子进程），
    /// 这里自动重启一次再重试，避免整个界面变成「全都在报错」。
    func get(_ path: String, _ query: [String: String] = [:]) async throws -> Any {
        let dict = try await getRaw(path, query)
        return dict["data"] ?? dict
    }

    /// 返回完整 JSON（含 error_code / status），登录类接口需要看这些字段。
    func getRaw(_ path: String, _ query: [String: String] = [:]) async throws -> JSON {
        do {
            return try await performGet(path, query)
        } catch let error as URLError where error.code == .cannotConnectToHost
                                            || error.code == .networkConnectionLost
                                            || error.code == .cannotFindHost {
            isReady = false
            await restart()
            return try await performGet(path, query)
        }
    }

    private func performGet(_ path: String, _ query: [String: String]) async throws -> JSON {
        var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: comps.url!)
        req.timeoutInterval = 20
        // 登录轮询必须每次都真的发出去；URLSession 的默认缓存会让状态停在「等待扫码」。
        req.cachePolicy = .reloadIgnoringLocalCacheData
        if let authCookie, !authCookie.isEmpty {
            req.setValue(authCookie, forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? -1
        // 核心会把上游的 502 连同 JSON 一起透传（例如「本次请求需要验证」），
        // 所以先解析 body，解析不出来才当作 HTTP 错误。
        guard let obj = try? JSONSerialization.jsonObject(with: data) else {
            throw CoreError.http(status)
        }
        // 酷狗有时在 JSON 外面包一层 <!--KG_TAG_RES_START-->，这里容错剥掉。
        if let dict = obj as? JSON {
            return dict
        }
        if let raw = String(data: data, encoding: .utf8), let s = stripWrapper(raw),
           let inner = try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? JSON {
            return inner
        }
        throw CoreError.shape
    }

    private func stripWrapper(_ s: String) -> String? {
        guard let start = s.range(of: "<!--KG_TAG_RES_START-->"),
              let end = s.range(of: "<!--KG_TAG_RES_END-->") else { return nil }
        return String(s[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum CoreError: LocalizedError {
    case http(Int)
    case shape
    case service(String)

    var errorDescription: String? {
        switch self {
        case .http(let code): return "核心返回 HTTP \(code)"
        case .shape: return "数据格式不正确"
        case .service(let message): return message
        }
    }
}
