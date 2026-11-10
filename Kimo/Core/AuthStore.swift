//
//  AuthStore.swift
//  Kimo
//
//  酷狗登录：扫码（默认）+ 手机号验证码（备用）。
//  核心从 Authorization 读 token/userid。请求头只能放 ASCII，
//  昵称和头像不能放进去，否则整段头会被丢掉，接口变成未登录。
//
//  状态机与 MoeKoeMusic 一致：0 过期 / 1 等待扫码 / 2 待确认 / 4 成功。
//

import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI

struct UserProfile: Codable, Hashable {
    var userid: String
    var nickname: String
    var avatar: String?
    var vip: Bool
}

@MainActor
@Observable
final class AuthStore {
    enum LoginTab: Hashable {
        case qr
        case phone
    }

    enum Phase: Equatable {
        case idle
        case loadingQR
        case waiting          // 已出码，等扫码
        case scanned          // 已扫，等确认
        case verifying
        case authorized
        case expired
        case failed(String)
    }

    enum PhoneState: Equatable {
        case idle
        case sending
        case sent(Int)        // 倒计时秒数
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    private(set) var qrImage: NSImage?
    /// 二维码模块矩阵：交给 QRCodeView 按设备像素整格绘制，避免缩放啃掉模块。
    private(set) var qrMatrix: [[Bool]]?
    private(set) var profile: UserProfile?
    /// 状态 2 时酷狗会带昵称，用来提示「谁扫的码」。
    private(set) var scannedNickname: String?
    /// 登录返回的全部标量字段（token / userid / t1 …），API 鉴权要原样带上。
    private(set) var authFields: [String: String] = [:]
    /// 登录后用一次真实请求验证会话是否被服务端接受；失败时把原因显示出来。
    private(set) var sessionError: String?

    // MARK: 手机号登录

    var loginTab: LoginTab = .qr
    var phone: String = ""
    var code: String = ""
    private(set) var phoneState: PhoneState = .idle
    private(set) var phoneError: String?
    private(set) var submitting = false

    var isLoggedIn: Bool { profile != nil }
    var nickname: String { profile?.nickname ?? "点击登录" }

    var isPhoneValid: Bool {
        phone.count == 11 && phone.hasPrefix("1") && phone.allSatisfy(\.isNumber)
    }

    var codeButtonTitle: String {
        switch phoneState {
        case .sending: return "发送中…"
        case .sent(let s): return "\(s)s 后重发"
        case .failed: return "重新获取"
        case .idle: return "获取验证码"
        }
    }

    var canSendCode: Bool {
        switch phoneState {
        case .sending, .sent: return false
        case .idle, .failed: return true
        }
    }

    private var qrKey: String = ""
    private var qrIssuedAt: Date?
    /// 每次重新取码自增，用来丢弃上一轮还没返回的异步结果。
    private var qrGeneration = 0
    private var pollTask: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    private let storeURL: URL

    private static var defaultStoreURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Kimo/Core", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("auth.json")
    }

    /// 指定会话缓存位置，默认沿用原有账号文件。
    init(storeURL: URL? = nil) {
        self.storeURL = storeURL ?? Self.defaultStoreURL
        // 开发期截图用：debug.json 里写 logintab / phone 可以直接落到手机号登录页。
        var env = ProcessInfo.processInfo.environment
        if let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
           let data = try? Data(contentsOf: base.appendingPathComponent("Kimo/debug.json")),
           let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            for (k, v) in dict {
                if let s = v as? String { env[k.uppercased()] = s }
                if let b = v as? Bool { env[k.uppercased()] = b ? "1" : "0" }
            }
        }
        if (env["LOGINTAB"] ?? "").lowercased() == "phone" {
            loginTab = .phone
        }
        if let p = env["PHONE"] {
            phone = p
        }
    }

    // MARK: - 启动时恢复

    /// 恢复旧版 cookie 或当前字段格式，校验结束后再展示缓存的资料。
    func restore() {
        guard phase == .idle, let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return }
        var fields = saved.fields ?? [:]
        if fields.isEmpty { fields = Self.cookieFields(saved.cookie ?? "") }
        guard let session = beginSession(fields) else { return }
        let candidate = Self.filled(saved.profile, fields: fields)
        Task { await verifySession(candidate, session: session) }
    }

    /// 安装可安全发送的凭据，并将当前会话的失效通知绑定到统一清理入口。
    private func beginSession(_ fields: [String: String]) -> UUID? {
        guard let token = fields["token"], Self.isHeaderSafe(token),
              let userid = fields["userid"], Self.isHeaderSafe(userid) else {
            invalidateSession("登录信息不完整，请重新登录")
            return nil
        }
        qrGeneration &+= 1
        authFields = fields
        sessionError = nil
        phase = .verifying
        // 在收藏、播放或校验接口明确报告过期时一起清除账号资料和凭据。
        CoreService.shared.setAuthCookie(Self.cookieString(from: fields)) { [weak self] in
            self?.invalidateSession("登录已失效，请重新登录")
        }
        return CoreService.shared.sessionID
    }

    /// 校验账号后发布资料。网络或服务异常时保留凭据，允许稍后重试。
    private func verifySession(_ candidate: UserProfile, session: UUID) async {
        guard session == CoreService.shared.sessionID else { return }
        let warning: String?
        do {
            let response = try await CoreService.shared.getRaw("/user/playlist", ["page": "1", "pagesize": "1"])
            let code = J.int(response, "error_code") ?? 0
            let valid = code == 0 && J.int(response, "status") == 1
            warning = valid ? nil : "暂时无法校验登录状态（\(code)）"
        } catch {
            warning = "无法连接核心服务，暂时无法校验登录状态"
        }
        // 失效、退出或换号后，不允许迟到的响应重新显示或保存旧头像。
        guard session == CoreService.shared.sessionID else { return }
        sessionError = warning
        profile = candidate
        phase = .authorized
        save(profile: candidate)
        if warning == nil { await refreshProfile(session: session) }
    }

    /// 刷新同一会话的昵称、头像和会员标记。
    private func refreshProfile(session: UUID) async {
        guard var current = profile else { return }
        let userid = authFields["userid"] ?? current.userid
        guard let payload = try? await CoreService.shared.get("/user/detail", ["userid": userid]),
              session == CoreService.shared.sessionID, let dict = payload as? JSON else { return }
        if let name = J.str(dict, "nickname", "username", "nick_name") {
            current.nickname = name
        }
        if let pic = J.str(dict, "pic", "avatar", "user_pic") {
            current.avatar = pic
        }
        current.vip = (J.int(dict, "vip_type", "vipType") ?? 0) > 0
        profile = current
        save(profile: current)
    }

    // MARK: - 扫码

    func startLogin() {
        pollTask?.cancel()
        qrGeneration &+= 1
        let gen = qrGeneration
        qrImage = nil
        qrMatrix = nil
        scannedNickname = nil
        phase = .loadingQR

        pollTask = Task { [weak self] in
            guard let self else { return }
            if await self.fetchQR(gen: gen) {
                await self.poll(gen: gen)
            }
        }
    }

    /// 取一张新码。silent = true 时不切到 loading 态（后台自动换码用）。
    @discardableResult
    private func fetchQR(gen: Int) async -> Bool {
        do {
            // 与 MoeKoeMusic 完全一致的流程：
            // 1) /login/qr/key 只取 key
            // 2) /login/qr/create?key=&qrimg=true 拿真正要编进二维码的地址
            // 注意：key 接口里的 qrcode_img 编的是带 appid 的页面地址，酷狗 App 认不出来。
            let payload = try await CoreService.shared.get("/login/qr/key")
            guard gen == qrGeneration else { return false }
            guard let dict = payload as? JSON, let key = J.str(dict, "qrcode") else {
                phase = .failed("二维码生成失败")
                return false
            }
            qrKey = key

            let created = try await CoreService.shared.get("/login/qr/create", [
                "key": key, "qrimg": "true",
            ])
            guard gen == qrGeneration else { return false }
            let createdDict = created as? JSON ?? [:]

            var message = J.str(createdDict, "url")
            var fallbackImage: NSImage?
            if message == nil, let base64 = J.str(createdDict, "base64") {
                fallbackImage = Self.decodeDataURI(base64)
                if let cg = fallbackImage?.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                    message = QRCodeRenderer.message(in: cg)
                }
            }
            guard let message else {
                phase = .failed("二维码生成失败")
                return false
            }

            qrMatrix = QRCodeRenderer.matrix(from: message)
            qrImage = qrMatrix == nil ? fallbackImage : QRCodeRenderer.image(from: message)
            guard qrMatrix != nil || qrImage != nil else {
                phase = .failed("二维码生成失败")
                return false
            }
            qrIssuedAt = Date()
            if phase != .scanned { phase = .waiting }
            return true
        } catch {
            if gen == qrGeneration {
                phase = .failed(error.localizedDescription)
            }
            return false
        }
    }

    private func poll(gen: Int) async {
        while !Task.isCancelled && gen == qrGeneration {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if Task.isCancelled || gen != qrGeneration { return }

            // 二维码在手机上放久了会被判失效；到点自动换一张，用户无感。
            if phase == .waiting, let issued = qrIssuedAt,
               Date().timeIntervalSince(issued) > 110 {
                if await fetchQR(gen: gen) { continue }
                return
            }

            do {
                let payload = try await CoreService.shared.get("/login/qr/check", [
                    "key": qrKey,
                    "timestamp": "\(Int(Date().timeIntervalSince1970 * 1000))",
                ])
                guard gen == qrGeneration else { return }
                guard let dict = payload as? JSON else { continue }
                let status = J.int(dict, "status") ?? 1

                switch status {
                case 2:
                    scannedNickname = J.str(dict, "nickname")
                    phase = .scanned
                case 4:
                    let token = J.str(dict, "token") ?? ""
                    let userid = J.str(dict, "userid") ?? ""
                    guard !token.isEmpty else {
                        phase = .failed("登录返回缺少 token")
                        return
                    }
                    // 不能只留 token/userid：酷狗校验还会看 t1 等字段，
                    // 少一个就会被判成 token 失效（20017）。
                    await finishLogin(userid: userid, login: dict, fields: Self.scalarFields(from: dict))
                    return
                case 0:
                    // 过期就换一张新的，不把用户卡死在「已失效」上。
                    if await fetchQR(gen: gen) { continue }
                    phase = .expired
                    return
                default:
                    if phase != .scanned { phase = .waiting }
                }
            } catch {
                // 网络抖动继续轮询
                continue
            }
        }
    }

    // MARK: - 手机号验证码

    func sendCode() async {
        guard isPhoneValid else {
            phoneError = "请输入 11 位手机号"
            return
        }
        phoneError = nil
        phoneState = .sending
        do {
            let dict = try await CoreService.shared.getRaw("/captcha/sent", ["mobile": phone])
            let errCode = J.int(dict, "error_code") ?? 0
            let ok = errCode == 0 && (J.int(dict, "status") ?? 0) == 1
            if ok {
                phoneState = .sent(60)
                startCountdown()
            } else {
                let message = (dict["data"] as? String) ?? "验证码发送失败"
                phoneState = .failed(message)
                phoneError = message
            }
        } catch {
            phoneState = .failed(error.localizedDescription)
            phoneError = error.localizedDescription
        }
    }

    func loginWithCode() async {
        guard isPhoneValid else {
            phoneError = "请输入 11 位手机号"
            return
        }
        guard code.count >= 4 else {
            phoneError = "请输入收到的验证码"
            return
        }
        guard !submitting else { return }
        let session = CoreService.shared.sessionID
        submitting = true
        phoneError = nil
        defer { submitting = false }

        do {
            let dict = try await CoreService.shared.getRaw("/login/cellphone", [
                "mobile": phone, "code": code,
            ])
            guard session == CoreService.shared.sessionID else { return }
            let data = dict["data"] as? JSON ?? [:]
            let token = J.str(data, "token") ?? J.str(dict, "token")
            let userid = J.str(data, "userid") ?? J.str(dict, "userid")
            guard (J.int(dict, "status") ?? 0) == 1, let token, !token.isEmpty, let userid else {
                phoneError = (dict["data"] as? String)
                    ?? J.str(dict, "error", "msg")
                    ?? "登录失败（\(J.int(dict, "error_code") ?? -1)）"
                return
            }

            var fields = Self.scalarFields(from: data)
            fields["token"] = token
            fields["userid"] = userid
            await finishLogin(userid: userid, login: data, fields: fields)
        } catch {
            phoneError = error.localizedDescription
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { [weak self] in
            for remaining in stride(from: 59, through: 0, by: -1) {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                if remaining == 0 {
                    self?.phoneState = .idle
                } else {
                    self?.phoneState = .sent(remaining)
                }
            }
        }
    }

    // MARK: - 完成登录

    /// 将两种登录入口交给同一套会话校验。
    private func finishLogin(userid: String, login: JSON, fields: [String: String]) async {
        guard let session = beginSession(fields) else { return }
        let profile = UserProfile(
            userid: userid,
            nickname: J.str(login, "nickname", "username", "nick_name") ?? "酷狗用户",
            avatar: J.str(login, "pic", "avatar", "user_pic"),
            vip: (J.int(login, "vip_type", "vipType") ?? 0) > 0
        )
        // 校验后再发布和持久化新账号。
        await verifySession(profile, session: session)
    }

    /// 清理被拒绝的会话，并在登录入口解释原因。
    private func invalidateSession(_ reason: String) {
        logout()
        sessionError = reason
    }

    /// 撤销凭据并清理账号资料、缓存及登录中的临时状态。
    func logout() {
        qrGeneration &+= 1
        pollTask?.cancel()
        countdownTask?.cancel()
        CoreService.shared.setAuthCookie(nil)
        profile = nil
        qrImage = nil
        qrMatrix = nil
        authFields = [:]
        sessionError = nil
        phoneState = .idle
        scannedNickname = nil
        phoneError = nil
        code = ""
        phase = .idle
        try? FileManager.default.removeItem(at: storeURL)
    }

    /// 只保留字符串/数字字段，忽略嵌套对象（如 user_detail）。
    static func scalarFields(from dict: JSON) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in dict {
            switch value {
            case let s as String where !s.isEmpty:
                out[key] = s
            case let n as NSNumber:
                out[key] = n.stringValue
            default:
                break
            }
        }
        return out
    }

    /// 只放鉴权字段。昵称、头像是非 ASCII，放进 Authorization 后
    /// HTTP 客户端会丢掉整段头，接口等于没登录，酷狗回 20010。
    /// cookieToJson 按 ';' 和第一个 '=' 切，值里也不能有这两个字符，分号后不能有空格。
    static let headerKeys = ["token", "userid", "t1", "vip_token", "vip_type"]

    static func cookieString(from fields: [String: String]) -> String {
        headerKeys.compactMap { key -> String? in
            guard let value = fields[key], isHeaderSafe(value) else { return nil }
            return "\(key)=\(value)"
        }.joined(separator: ";")
    }

    /// 读取旧版会话中的凭据供校验及下次保存。
    private static func cookieFields(_ raw: String) -> [String: String] {
        var fields: [String: String] = [:]
        for part in raw.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            fields[pair[0].trimmingCharacters(in: .whitespaces)] = pair[1]
        }
        return fields
    }

    private static func isHeaderSafe(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            // 排除 ';' 和 '='，否则 cookieToJson 会把 token 切碎。
            return v >= 0x21 && v <= 0x7e && v != 0x3b && v != 0x3d
        }
    }

    /// 旧资料里昵称可能还是占位符，登录返回的字段里有真名和头像。
    private static func filled(_ saved: UserProfile, fields: [String: String]) -> UserProfile {
        var profile = saved
        if profile.nickname.isEmpty || profile.nickname == "酷狗用户",
           let nick = fields["nickname"], !nick.isEmpty {
            profile.nickname = nick
        }
        if profile.avatar == nil, let pic = fields["pic"], !pic.isEmpty {
            profile.avatar = pic
        }
        return profile
    }

    // MARK: - 持久化

    private struct Saved: Codable {
        var cookie: String?
        var fields: [String: String]?
        let profile: UserProfile
    }

    private func save(profile: UserProfile) {
        let payload = Saved(cookie: Self.cookieString(from: authFields), fields: authFields, profile: profile)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: storeURL, options: .atomic)
        }
    }

    // MARK: - Helpers

    static func decodeDataURI(_ raw: String) -> NSImage? {
        let base64 = raw.components(separatedBy: ",").last ?? raw
        guard let data = Data(base64Encoded: base64), let image = NSImage(data: data) else { return nil }

        // 酷狗给的图只有 196px、没有静区，缩放后经常扫不出来。
        // 先从图里把内容解出来，再用系统生成器重画一张干净的。
        if let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
           let message = QRCodeRenderer.message(in: cg),
           let clean = QRCodeRenderer.image(from: message) {
            return clean
        }
        return image
    }
}

/// 把二维码内容转成模块矩阵，或重画成干净的黑白码。
enum QRCodeRenderer {
    static func message(in cgImage: CGImage) -> String? {
        let ci = CIImage(cgImage: cgImage)
        let detector = CIDetector(ofType: CIDetectorTypeQRCode,
                                  context: CIContext(),
                                  options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let features = detector?.features(in: ci) ?? []
        for case let qr as CIQRCodeFeature in features {
            if let text = qr.messageString, !text.isEmpty { return text }
        }
        return nil
    }

    /// 生成 1 像素 = 1 个模块的布尔矩阵（不含静区），供 SwiftUI 按设备像素绘制。
    static func matrix(from message: String) -> [[Bool]]? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let extent = output.extent.integral
        let width = Int(extent.width)
        let height = Int(extent.height)
        guard width > 0, height > 0,
              let cg = CIContext().createCGImage(output, from: extent) else { return nil }

        var bytes = [UInt8](repeating: 255, count: width * height)
        guard let ctx = CGContext(data: &bytes,
                                  width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: width,
                                  space: CGColorSpaceCreateDeviceGray(),
                                  bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.interpolationQuality = .none
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))

        var rows: [[Bool]] = []
        rows.reserveCapacity(height)
        for y in 0..<height {
            // CGContext 的原点在左下，缓冲区首行是图像底部，这里翻回自上而下。
            let sourceRow = height - 1 - y
            rows.append((0..<width).map { bytes[sourceRow * width + $0] < 128 })
        }
        return rows
    }

    /// 生成 4 个模块静区的黑白二维码图片（用作矩阵不可用时的兜底）。
    static func image(from message: String, moduleScale: CGFloat = 10) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(message.utf8)
        filter.correctionLevel = "M"
        guard let base = filter.outputImage else { return nil }

        let quiet: CGFloat = 4
        let padded = base.extent.insetBy(dx: -quiet, dy: -quiet)
        let white = CIImage(color: .white).cropped(to: padded)
        let composed = base.composited(over: white)

        let scaled = composed.transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))
        let ctx = CIContext()
        guard let cg = ctx.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: scaled.extent.width, height: scaled.extent.height))
    }
}

/// 按设备像素整格绘制二维码：不做任何位图缩放，模块边缘永远是直的。
struct QRCodeView: View {
    let matrix: [[Bool]]
    var size: CGFloat = 216
    var quiet: Int = 4

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, canvas in
            let total = matrix.count + quiet * 2
            guard total > 0 else { return }

            // 把模块尺寸对齐到整数设备像素，避免半像素造成的灰边。
            let pixels = canvas.width * displayScale
            let modulePixels = max(1, (pixels / CGFloat(total)).rounded(.down))
            let module = modulePixels / displayScale
            let side = module * CGFloat(total)
            let origin = CGPoint(x: (canvas.width - side) / 2, y: (canvas.height - side) / 2)

            context.fill(Path(CGRect(origin: origin, size: CGSize(width: side, height: side))),
                         with: .color(.white))

            var path = Path()
            for (y, row) in matrix.enumerated() {
                for (x, on) in row.enumerated() where on {
                    path.addRect(CGRect(x: origin.x + CGFloat(quiet + x) * module,
                                        y: origin.y + CGFloat(quiet + y) * module,
                                        width: module, height: module))
                }
            }
            context.fill(path, with: .color(.black))
        }
        .frame(width: size, height: size)
    }
}
