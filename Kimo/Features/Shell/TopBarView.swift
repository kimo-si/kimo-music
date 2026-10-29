//
//  TopBarView.swift
//  Kimo
//
//  顶栏：前进/后退 + 搜索胶囊 + 账号/皮肤/迷你/设置。
//  高度 56，底部留 16 给内容面板（TopBar.module.css）。
//

import SwiftUI

struct TopBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme
    @FocusState private var searchFocused: Bool
    @State private var showSkins = false

    var body: some View {
        @Bindable var model = model

        HStack(spacing: 16) {
            history
            searchField(text: $model.searchText)
            Spacer(minLength: 0)
            actions
        }
        .padding(.leading, 4)
        .padding(.trailing, 16)
        .background(WindowDragArea())
    }

    // MARK: History

    private var history: some View {
        HStack(spacing: 4) {
            IconButton(muted: false, disabled: !model.canGoBack) {
                model.back()
            } content: {
                Image(systemName: "chevron.left").font(.system(size: 16, weight: .light))
            }
            IconButton(muted: false, disabled: !model.canGoForward) {
                model.forward()
            } content: {
                Image(systemName: "chevron.right").font(.system(size: 16, weight: .light))
            }
        }
    }

    // MARK: Search

    private func searchField(text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(searchFocused ? theme.accentStrong : theme.textMuted)
            TextField("搜索歌曲、歌手、歌单", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(theme.text)
                .focused($searchFocused)
                .onSubmit { model.submitSearch() }
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .frame(width: searchFocused ? 380 : 300, height: 40)
        .background {
            Capsule().fill(searchFocused ? theme.fieldFocus : theme.chip)
            Capsule().strokeBorder(searchFocused ? theme.accent.opacity(0.4) : theme.glassEdge, lineWidth: 1)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: searchFocused)
        .onTapGesture { searchFocused = true }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 4) {
            accountButton
            Rectangle()
                .fill(Color.black.opacity(theme.isDark ? 0.35 : 0.16))
                .frame(width: 1, height: 18)
                .padding(.leading, 2)
                .padding(.trailing, 6)

            IconButton(active: showSkins) {
                showSkins.toggle()
            } content: {
                SkinGlyph()
            }
            .help("皮肤")
            .accessibilityLabel("皮肤")
            .popover(isPresented: $showSkins, arrowEdge: .top) {
                SkinPicker()
            }
            IconButton {
                model.setMini(true)
            } content: {
                Image(systemName: "pip").font(.system(size: 15, weight: .light))
            }
            .help("迷你模式")
            IconButton {
                model.navigate(.settings)
            } content: {
                Image(systemName: "gearshape").font(.system(size: 15, weight: .light))
            }
        }
    }

    private var accountButton: some View {
        Button {
            model.showLogin = true
        } label: {
            HStack(spacing: 8) {
                ZStack {
                    if let raw = auth.profile?.avatar, let url = URL(string: sized(raw, 80)) {
                        AsyncImage(url: url) { phase in
                            if let img = phase.image {
                                img.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                fallbackAvatar
                            }
                        }
                    } else {
                        fallbackAvatar
                    }
                }
                .frame(width: 28, height: 28)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(theme.glassEdge, lineWidth: 1))

                Text(auth.nickname)
                    .font(.system(size: 13))
                    .foregroundStyle(auth.isLoggedIn ? theme.textStrong : theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.leading, 3)
            .padding(.trailing, 10)
            .frame(height: 34)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(AccountButtonStyle())
    }

    private var fallbackAvatar: some View {
        ZStack {
            Circle().fill(theme.chip)
            Image(systemName: "person")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(theme.textSecondary)
        }
    }
}

private struct AccountButtonStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(configuration.isPressed ? theme.hover : Color.clear)
            )
    }
}
