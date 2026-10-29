//
//  ShellView.swift
//  Kimo
//
//  应用外壳：侧边栏 200/72 + 顶栏 56 + 内容玻璃面板 + 播放栏 76。
//  尺寸与 cocomusic 的 AppShell.module.css 完全对应。
//

import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if model.isMini {
                MiniPlayerView()
            } else {
                fullShell
            }
        }
        .task(id: auth.isLoggedIn) {
            if auth.isLoggedIn {
                await model.likes.refresh()
            } else {
                model.likes.reset()
            }
        }
    }

    private var fullShell: some View {
        ZStack(alignment: .topLeading) {
            // 毛玻璃模式：系统把窗口背后的桌面模糊掉；透明模式不铺这层，桌面保持清晰。
            if model.settings.windowEffect == .vibrancy {
                WindowMaterial(material: .underWindowBackground)
                    .ignoresSafeArea()
            }
            Backdrop(theme: theme)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SidebarView()
                        .frame(width: model.sidebarCollapsed ? Metrics.sidebarCollapsedWidth : Metrics.sidebarWidth)
                        .padding(.top, Metrics.sidebarInset)
                        .padding(.leading, Metrics.sidebarInset)

                    MainColumn()
                        .padding(.top, Metrics.sidebarInset)
                        .padding(.leading, Metrics.mainInsetLeft)
                }
                .frame(maxHeight: .infinity)

                PlayerBarView()
                    .frame(height: Metrics.playerHeight)
            }
            // 播放页背景需要透出窗口级皮肤，而不是透出下面的主界面。
            .opacity(model.showLyrics ? 0 : 1)
            .allowsHitTesting(!model.showLyrics)

            WindowDragStrip()
                .frame(height: 16)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 窗口透明时不能铺底色，否则桌面永远透不过来。
        .background(model.settings.windowEffect == .none ? theme.shell : Color.clear)
        .ignoresSafeArea()
        .onAppear { model.systemIsDark = colorScheme == .dark }
        .onChange(of: colorScheme) { _, value in model.systemIsDark = value == .dark }
        .overlay {
            GeometryReader { geo in
                let seam = 1 - Metrics.playerHeight / max(geo.size.height, 1)
                ZStack {
                    if model.showLyrics {
                        LyricsDrawer()
                            .frame(width: geo.size.width, height: geo.size.height)
                            .transition(PlayerMotion.lyricsTransition(
                                reduceMotion: model.settings.reduceMotion,
                                seam: seam
                            ))
                            .zIndex(40)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .animation(PlayerMotion.lyricsAnimation(reduceMotion: model.settings.reduceMotion), value: model.showLyrics)
        .overlay(alignment: .top) {
            if model.showQueue {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    QueuePanel()
                }
                .padding(.top, 16)
                .padding(.trailing, 12)
                .padding(.bottom, 84)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.86), value: model.showQueue)
        .overlay {
            if model.showLogin {
                LoginDialog()
                    .zIndex(50)
            }
        }
        .animation(.easeOut(duration: 0.18), value: model.showLogin)
        .onExitCommand {
            if model.showLyrics {
                withAnimation(PlayerMotion.lyricsAnimation(reduceMotion: model.settings.reduceMotion)) {
                    model.showLyrics = false
                }
            } else if model.showQueue {
                model.showQueue = false
            }
        }
    }
}

// MARK: - Main column

private struct MainColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            TopBarView()
                .frame(height: Metrics.topBarHeight)
                .padding(.bottom, Metrics.topBarGap)

            ContentSheet {
                RouteView(route: model.route)
            }
        }
    }
}

// MARK: - Content sheet

struct ContentSheet<Content: View>: View {
    @Environment(\.theme) private var theme
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                ZStack {
                    if theme.glassBlur > 0 {
                        Rectangle().fill(.ultraThinMaterial)
                    }
                    Rectangle().fill(theme.sheet)
                }
            }
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: theme.radiusSheet, style: .continuous)
            )
    }
}

// MARK: - Route

struct RouteView: View {
    @Environment(AppModel.self) private var model
    let route: Route

    var body: some View {
        switch route {
        case .home:
            HomeView()
        case .search(let keyword):
            SearchView(keyword: keyword)
        case .playlist(let id, let title):
            PlaylistView(id: id, title: title)
        case .rank(let id, let title):
            RankView(rankId: id, title: title)
        case .charts:
            ChartsView()
        case .artists:
            ArtistsView()
        case .artist(let id, let title):
            ArtistDetailView(id: id, title: title)
        case .recent:
            RecentView()
        case .liked:
            LikedView()
        case .local:
            LocalView()
        case .discover:
            DiscoverView()
        case .settings:
            SettingsView()
        default:
            PlaceholderView(route: route)
        }
    }
}

// MARK: - Drag strip

/// 窗口最顶部 16pt 拖动带（cocomusic 的 .dragStrip）。
struct WindowDragStrip: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override func hitTest(_ point: NSPoint) -> NSView? {
            super.hitTest(point)
        }
    }
}

/// 顶栏空白处的拖动区（按钮在上层，仍能正常点击）。
/// NSVisualEffectView 底座：`.behindWindow` 让系统模糊窗口背后的桌面。
struct WindowMaterial: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
    }
}

struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}
