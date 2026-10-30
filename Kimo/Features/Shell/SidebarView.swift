//
//  SidebarView.swift
//  Kimo
//
//  侧边导航：品牌行 + 音乐馆 / 我的音乐 / 我的歌单。
//  折叠后收成 72pt 图标栏，分组标题变成细线（对应 Sidebar.module.css）。
//

import SwiftUI

struct NavItem: Identifiable {
    let id: Route
    let label: String
    let icon: String
}

enum SidebarData {
    static let library: [NavItem] = [
        .init(id: .home, label: "首页", icon: "house"),
        .init(id: .discover, label: "发现音乐", icon: "safari"),
        .init(id: .artists, label: "歌手", icon: "music.mic"),
        .init(id: .charts, label: "排行榜", icon: "chart.line.uptrend.xyaxis"),
    ]
    static let mine: [NavItem] = [
        .init(id: .liked, label: "我喜欢", icon: "heart"),
        .init(id: .recent, label: "最近播放", icon: "clock.arrow.circlepath"),
        .init(id: .local, label: "本地音乐", icon: "externaldrive"),
        .init(id: .downloads, label: "下载管理", icon: "arrow.down.to.line"),
    ]
}

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    @State private var hoveringBrand = false

    private var collapsed: Bool { model.sidebarCollapsed }

    var body: some View {
        VStack(spacing: 0) {
            brandRow
                .padding(.top, Metrics.brandTopOffset)
                .frame(height: Metrics.brandTopOffset + Metrics.brandHeight)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    group(title: "音乐馆", items: SidebarData.library)
                    group(title: "我的音乐", items: SidebarData.mine)
                }
                .padding(.vertical, 8)
            }

            if theme.flavor == .chiikawa && !collapsed {
                ChiikawaArtwork()
                    .frame(width: 164, height: 104)
                    .padding(.bottom, 10)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .clipped()
    }

    // MARK: Brand

    private var brandRow: some View {
        HStack(spacing: 10) {
            if !collapsed {
                BrandMark()
                    .opacity(collapsed ? 0 : 1)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            IconButton(size: 30, radius: 9, muted: true) {
                model.toggleSidebar()
            } content: {
                Image(systemName: collapsed ? "sidebar.left" : "sidebar.leading")
                    .font(.system(size: 15, weight: .light))
            }
            .opacity(hoveringBrand || collapsed ? 1 : 0)
        }
        .padding(.horizontal, collapsed ? 0 : 16)
        .frame(maxWidth: .infinity)
        .frame(height: Metrics.brandHeight)
        .contentShape(Rectangle())
        .onHover { hoveringBrand = $0 }
        .background(WindowDragArea())
    }

    // MARK: Groups

    private func group(title: String, items: [NavItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            groupLabel(title)
            VStack(spacing: 4) {
                ForEach(items) { item in
                    NavRow(item: item, collapsed: collapsed)
                }
            }
        }
    }

    private func groupLabel(_ title: String) -> some View {
        Group {
            if collapsed {
                Rectangle()
                    .fill(theme.accentStrong.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
            } else {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 16)
                    .padding(.trailing, 10)
                    .frame(height: 28)
                    .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Row

private struct NavRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme
    let item: NavItem
    let collapsed: Bool
    @State private var hovering = false

    private var active: Bool { model.route == item.id }

    var body: some View {
        Button {
            model.navigate(item.id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .light))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(active ? theme.accentStrong : theme.textSecondary)
                if !collapsed {
                    Text(item.label)
                        .font(theme.controlFont(15))
                        .foregroundStyle(active ? theme.accentStrong : theme.textStrong)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, collapsed ? 11 : 14)
            .frame(width: collapsed ? 40 : nil, height: 40)
            .frame(maxWidth: collapsed ? nil : .infinity, alignment: .leading)
            .modifier(ThemedSurface(role: .selection, active: active, hovering: hovering,
                                   radius: theme.radiusRow))
            .overlay(alignment: .leading) {
                if active {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(theme.accentStrong).frame(width: 3, height: 16)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: theme.radiusCard, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(collapsed ? item.label : "")
        .frame(maxWidth: .infinity, alignment: collapsed ? .center : .leading)
        .padding(.horizontal, collapsed ? 0 : 16)
    }
}

// MARK: - Brand mark

struct BrandMark: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Group {
            if let word = BundleImage.named("wordmark") {
                Image(nsImage: word)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 32)
            } else {
                Text("kimo")
                    .font(theme.titleFont(22, weight: .bold))
                    .foregroundStyle(theme.textStrong)
            }
        }
        .accessibilityLabel("kimo")
    }
}

enum BundleImage {
    static func named(_ name: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
}
