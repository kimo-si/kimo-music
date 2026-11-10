//
//  LoginDialog.swift
//  Kimo
//
//  登录弹层：扫码为主，手机号验证码兜底。
//  版式沿用 cocomusic 的 Dialog（毛玻璃卡片 + 遮罩）。
//

import SwiftUI

struct LoginDialog: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme

    var body: some View {
        @Bindable var auth = auth

        ZStack {
            Rectangle()
                .fill(theme.inkScrim)
                .ignoresSafeArea()
                .onTapGesture { model.showLogin = false }

            card(auth: $auth)
                .frame(width: 372)
                .background {
                    if theme.glassBlur > 0 {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.solid.opacity(0.96))
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(theme.glassEdge, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 30, y: 12)
                .transition(.scale(scale: 0.96).combined(with: .opacity))
        }
    }

    private func card(auth: Bindable<AuthStore>) -> some View {
        VStack(spacing: 16) {
            HStack {
                Text(auth.wrappedValue.isLoggedIn ? "账号" : "登录酷狗音乐")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.textStrong)
                Spacer()
                IconButton(size: 28, radius: 8) {
                    model.showLogin = false
                } content: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .semibold))
                }
            }

            if let error = auth.wrappedValue.sessionError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.like)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            if auth.wrappedValue.phase == .verifying {
                ProgressView("正在校验登录状态…")
                    .controlSize(.small)
            } else if auth.wrappedValue.isLoggedIn {
                loggedIn
            } else {
                loginFlow(auth: auth)
            }
        }
        .padding(20)
    }

    // MARK: 已登录

    private var loggedIn: some View {
        VStack(spacing: 14) {
            avatar(size: 64)
            Text(auth.nickname)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(theme.textStrong)
            if auth.profile?.vip == true {
                Text("VIP")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.accentStrong)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(theme.accentSoft))
            }
            Button {
                auth.logout()
            } label: {
                Text("退出登录")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 9).fill(theme.chip))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: 登录

    private func loginFlow(auth: Bindable<AuthStore>) -> some View {
        VStack(spacing: 14) {
            Picker("", selection: auth.loginTab) {
                Text("扫码登录").tag(AuthStore.LoginTab.qr)
                Text("手机号登录").tag(AuthStore.LoginTab.phone)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch auth.wrappedValue.loginTab {
            case .qr:
                qrSection.onAppear {
                    // 仅当扫码页可见时才为新登录流程取码。
                    if auth.wrappedValue.phase == .idle { auth.wrappedValue.startLogin() }
                }
            case .phone:
                phoneSection(auth: auth)
            }
        }
    }

    // MARK: 扫码

    private var qrSection: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white)
                    .frame(width: 244, height: 244)

                switch auth.phase {
                case .waiting, .scanned:
                    if let matrix = auth.qrMatrix {
                        QRCodeView(matrix: matrix, size: 212)
                    } else if let img = auth.qrImage {
                        Image(nsImage: img)
                            .resizable()
                            .interpolation(.none)
                            .frame(width: 204, height: 204)
                    }
                case .loadingQR:
                    ProgressView().controlSize(.small)
                case .expired, .failed:
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .light))
                            .foregroundStyle(theme.accentStrong)
                        Text("二维码已失效")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    }
                default:
                    Image(systemName: "qrcode")
                        .font(.system(size: 60, weight: .ultraLight))
                        .foregroundStyle(theme.textMuted)
                }
            }
            .frame(width: 244, height: 244)
            .overlay {
                if case .scanned = auth.phase {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.white.opacity(0.92))
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(theme.trendNew)
                        Text(auth.scannedNickname.map { "\($0) 已扫码，请在手机上确认" } ?? "扫码成功，请在手机上确认")
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
            }

            statusText

            HStack(spacing: 16) {
                Button("刷新二维码") { auth.startLogin() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.accentStrong)
                if case .failed(let msg) = auth.phase {
                    Text(msg)
                        .font(.system(size: 11))
                        .foregroundStyle(theme.like)
                        .lineLimit(1)
                }
            }
        }
    }

    private var statusText: some View {
        Group {
            switch auth.phase {
            case .scanned:
                Text(auth.scannedNickname.map { "\($0) 已扫码，等待确认" } ?? "已扫码，等待手机端确认")
            case .waiting:
                Text("用酷狗音乐 App 扫一扫（微信扫码无效）")
            case .loadingQR:
                Text("正在生成二维码…")
            case .expired:
                Text("二维码已过期，正在换新…")
            case .failed:
                Text("登录失败")
            default:
                Text("用酷狗音乐 App 扫一扫")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.textSecondary)
    }

    // MARK: 手机号

    private func phoneSection(auth: Bindable<AuthStore>) -> some View {
        VStack(spacing: 10) {
            field(icon: "iphone") {
                TextField("手机号", text: auth.phone)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(theme.textStrong)
                    .onSubmit { Task { await auth.wrappedValue.sendCode() } }
            }

            field(icon: "number") {
                HStack(spacing: 8) {
                    TextField("验证码", text: auth.code)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textStrong)
                        .onSubmit { Task { await auth.wrappedValue.loginWithCode() } }

                    Button {
                        Task { await auth.wrappedValue.sendCode() }
                    } label: {
                        Text(auth.wrappedValue.codeButtonTitle)
                            .font(.system(size: 12))
                            .foregroundStyle(auth.wrappedValue.canSendCode ? theme.accentStrong : theme.textMuted)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .background(Capsule().fill(theme.accentSoft.opacity(
                                auth.wrappedValue.canSendCode ? 1 : 0.5)))
                    }
                    .buttonStyle(.plain)
                    .disabled(!auth.wrappedValue.canSendCode)
                }
            }

            if let error = auth.wrappedValue.phoneError {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.like)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 2)
            }

            Button {
                Task { await auth.wrappedValue.loginWithCode() }
            } label: {
                HStack(spacing: 6) {
                    if auth.wrappedValue.submitting {
                        ProgressView().controlSize(.small)
                    }
                    Text(auth.wrappedValue.submitting ? "登录中…" : "登录")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.accentStrong.opacity(auth.wrappedValue.isPhoneValid ? 1 : 0.5))
                )
            }
            .buttonStyle(.plain)
            .disabled(!auth.wrappedValue.isPhoneValid || auth.wrappedValue.submitting)

            Text("会收到酷狗发送的短信验证码，登录态与扫码一致")
                .font(.system(size: 11))
                .foregroundStyle(theme.textMuted)
        }
    }

    private func field<Content: View>(icon: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(theme.textMuted)
                .frame(width: 14)
            content()
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(theme.chip)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.glassEdge, lineWidth: 1)
        )
    }

    // MARK: Avatar

    @ViewBuilder
    private func avatar(size: CGFloat) -> some View {
        if let raw = auth.profile?.avatar, let url = URL(string: sized(raw, 120)) {
            AsyncImage(url: url) { phase in
                if let img = phase.image {
                    img.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholderAvatar
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(theme.glassEdge, lineWidth: 1))
        } else {
            placeholderAvatar
                .frame(width: size, height: size)
        }
    }

    private var placeholderAvatar: some View {
        ZStack {
            Circle().fill(theme.chip)
            Image(systemName: "person.fill")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(theme.textSecondary)
        }
    }
}
