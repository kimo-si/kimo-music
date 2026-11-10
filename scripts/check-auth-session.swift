// 与 Kimo/Core 下的 Models.swift、CoreService.swift、AuthStore.swift 一起用 swiftc 编译运行。
import Foundation

/// 只在本检查进程内模拟本机核心服务，使用测试凭据。
private final class SessionFixture: URLProtocol {
    static let delayed = AsyncStream<SessionFixture>.makeStream()

    // 拦截核心请求，避免访问真实账号及远端服务。
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "127.0.0.1" }

    // 保留请求的鉴权头用于验证失效清理。
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    // 用 HTTP 层的真实响应格式区分离线、过期、正常和匿名请求。
    override func startLoading() {
        if request.url?.query == "delayed=1" {
            Self.delayed.continuation.yield(self)
            return
        }
        let header = request.value(forHTTPHeaderField: "Authorization") ?? ""
        if header.contains("token=offline;") {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let body: String
        switch request.url?.path {
        case "/song/url": body = #"{"errcode":20018}"#
        case "/login/cellphone": body = #"{"status":1,"data":{"userid":"1","token":"valid","nickname":"新账号"}}"#
        case "/user/playlist" where header.contains("token=expired;"): body = #"{"status":0,"error_code":20017}"#
        default: body = header.isEmpty ? #"{"status":0}"# : #"{"status":1}"#
        }
        reply(body)
    }

    // 通过相同的传输入口返回即时响应或测试控制的延迟响应。
    func reply(_ body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    // 测试不建立真实连接。
    override func stopLoading() {}
}

@MainActor
@main
private struct AuthSessionCheck {
    // 使用临时缓存通过真实的会话恢复和扫码以外的重新登录入口验证状态变化。
    static func main() async throws {
        precondition(URLProtocol.registerClass(SessionFixture.self))
        defer { URLProtocol.unregisterClass(SessionFixture.self) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        let auth = AuthStore(storeURL: file)
        try await restore(auth, file, token: "expired")
        try await checkExpired(auth, file)
        auth.restore()
        precondition(!auth.isLoggedIn && auth.phase == .idle)
        // 使用手机号入口重新登录后，从播放请求触发另一种过期响应。
        auth.phone = "13800000000"
        auth.code = "123456"
        await auth.loginWithCode()
        precondition(auth.nickname == "新账号" && auth.sessionError == nil)
        _ = try await CoreService.shared.getRaw("/song/url")
        try await checkExpired(auth, file)
        // 超时保留资料，旧版 cookie 仍能恢复为可用的鉴权字段。
        try await restore(auth, file, token: "offline")
        precondition(auth.isLoggedIn && auth.sessionError != nil && auth.authFields["token"] == "offline")
        auth.logout()
        try await restore(auth, file, token: "valid")
        precondition(auth.isLoggedIn && auth.sessionError == nil)
        try await checkLateExpiry(auth, file)
        print("登录会话检查通过：恢复校验、失效清理、重新登录、离线、旧版缓存和过期响应竞态")
    }

    // 让旧播放请求在相同凭据再次登录后才返回失效，确认新会话不受影响。
    private static func checkLateExpiry(_ auth: AuthStore, _ file: URL) async throws {
        let old = Task { try await CoreService.shared.getRaw("/song/url", ["delayed": "1"]) }
        var requests = SessionFixture.delayed.stream.makeAsyncIterator()
        guard let delayed = await requests.next() else { preconditionFailure("未收到旧会话请求") }
        auth.logout()
        try await restore(auth, file, token: "valid")
        delayed.reply(#"{"errcode":20018}"#)
        _ = try await old.value
        precondition(auth.isLoggedIn && auth.sessionError == nil)
        precondition(FileManager.default.fileExists(atPath: file.path))
    }

    // 写入旧版缓存并等待异步校验完成，检查校验期间是否泄露旧头像。
    private static func restore(_ auth: AuthStore, _ file: URL, token: String) async throws {
        let saved = #"{"cookie":"token=\#(token);userid=1","profile":{"userid":"1","nickname":"旧账号","avatar":"old","vip":false}}"#
        try Data(saved.utf8).write(to: file, options: .atomic)
        auth.restore()
        precondition(auth.phase == .verifying && auth.profile == nil)
        for _ in 0..<200 where auth.phase == .verifying {
            try await Task.sleep(for: .milliseconds(10))
        }
        precondition(auth.phase != .verifying)
    }

    // 确认视图依赖的账号状态、磁盘文件和下一次实际发出的请求都已退出。
    private static func checkExpired(_ auth: AuthStore, _ file: URL) async throws {
        precondition(!auth.isLoggedIn && auth.profile == nil && auth.nickname == "点击登录")
        precondition(auth.phase == .idle && auth.authFields.isEmpty && auth.sessionError != nil)
        precondition(!FileManager.default.fileExists(atPath: file.path))
        let result = try await CoreService.shared.getRaw("/user/playlist")
        precondition(J.int(result, "status") == 0)
    }
}
