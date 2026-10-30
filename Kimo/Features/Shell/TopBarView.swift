//
//  TopBarView.swift
//  Kimo
//
//  顶栏：前进/后退 + 搜索胶囊 + 账号/皮肤/迷你/设置。
//  高度 56，底部留 16 给内容面板（TopBar.module.css）。
//

import AppKit
import Observation
import SwiftUI

struct TopBarView: View {
    @Environment(AppModel.self) private var model
    @Environment(AuthStore.self) private var auth
    @Environment(\.theme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var showSkins = false
    @State private var hoveringSuggestions = false
    @State private var suggestionPanelHeight: CGFloat = 0
    @State private var suggestions = SearchSuggestionState()

    private var searchActive: Bool { searchFocused || hoveringSuggestions }

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
        .onChange(of: model.route) { _, _ in dismissSearchSuggestions() }
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

    // 搜索框与候选面板使用当前皮肤的色板；输入变化只更新联想，不直接发起搜索。
    private func searchField(text: Binding<String>) -> some View {
        let request = SearchSuggestionRequest(text: text.wrappedValue, active: searchActive)
        return searchInput(text: text)
            .frame(width: searchActive ? SearchLayout.expandedWidth : SearchLayout.collapsedWidth, height: SearchLayout.fieldHeight)
            .modifier(ThemedSurface(role: .field, active: searchActive))
            .background {
                SearchOutsideClickMonitor(active: searchActive, panelHeight: suggestionPanelHeight, onOutside: dismissSearchSuggestions)
            }
            .animation(theme.allowsMotion && !reduceMotion ? .spring(response: 0.3, dampingFraction: 0.85) : nil, value: searchActive)
            .onTapGesture { searchFocused = true }
            .overlay(alignment: .topLeading) {
                if searchActive { suggestionPanel(for: request) }
            }
            .task(id: request) {
                // 输入停顿后请求联想，页面离开或关键词改变时取消旧任务。
                await suggestions.load(request) { try await MusicAPI.shared.searchSuggestions($0) }
            }
    }

    // 组装搜索输入、图标与清空按钮，保留原有回车搜索行为。
    private func searchInput(text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(searchFocused ? theme.accentStrong : theme.textMuted)
            TextField("搜索歌曲、歌手、歌单", text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(theme.text)
                .focused($searchFocused)
                .onSubmit(submitSearch)
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索词")
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
    }

    // 测量候选面板的实际高度，确保鼠标点击范围与面板内容同步。
    private func suggestionPanel(for request: SearchSuggestionRequest) -> some View {
        SearchSuggestionPanel(query: request.keyword, words: suggestions.words(for: request.keyword), onSelect: selectSuggestion)
            .frame(width: SearchLayout.expandedWidth)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { suggestionPanelHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in suggestionPanelHeight = height }
            })
            .offset(y: SearchLayout.fieldHeight + SearchLayout.panelGap)
            .onHover { hoveringSuggestions = $0 }
    }

    // 选择建议后复用现有搜索导航，结果仍来自真实酷狗曲库。
    private func selectSuggestion(_ keyword: String) {
        model.searchText = keyword
        submitSearch()
    }

    // 回车与点击建议共用提交入口，关闭联想并释放输入焦点。
    private func submitSearch() {
        dismissSearchSuggestions()
        model.submitSearch()
    }

    // 关闭候选时使旧请求失效，其他页面和按钮继续接收原始点击。
    private func dismissSearchSuggestions() {
        suggestions.clear()
        hoveringSuggestions = false
        searchFocused = false
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
            .help("外观：纯色与主题")
            .accessibilityLabel("外观")
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
        .buttonStyle(ThemedButtonStyle())
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

// 搜索框尺寸和候选面板间距同时用于布局与鼠标命中计算。
private enum SearchLayout {
    static let collapsedWidth: CGFloat = 300
    static let expandedWidth: CGFloat = 380
    static let fieldHeight: CGFloat = 40
    static let panelGap: CGFloat = 8
}

struct SearchSuggestionRequest: Equatable {
    let text: String
    let active: Bool
    var keyword: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

// 监听窗口内的鼠标点击，离开搜索区域时收起建议且不吞掉原事件。
private struct SearchOutsideClickMonitor: NSViewRepresentable {
    let active: Bool
    let panelHeight: CGFloat
    let onOutside: () -> Void

    // 创建不参与命中测试的窗口监听视图。
    func makeNSView(context: Context) -> SearchOutsideClickView { SearchOutsideClickView() }

    // 同步最新搜索区域和关闭回调。
    func updateNSView(_ view: SearchOutsideClickView, context: Context) {
        view.panelHeight = panelHeight
        view.onOutside = onOutside
        view.active = active
    }

    // 移除视图时注销事件监听，避免重复监听和持有已关闭窗口。
    static func dismantleNSView(_ view: SearchOutsideClickView, coordinator: ()) { view.stopMonitoring() }
}

// 只观察所属窗口中的点击，输入框和实际候选面板都属于内部区域。
private final class SearchOutsideClickView: NSView {
    var active = false { didSet { updateMonitoring() } }
    var panelHeight: CGFloat = 0
    var onOutside: () -> Void = {}
    private var monitor: Any?
    override var isFlipped: Bool { true }

    // 监听层不参与鼠标命中，原有按钮和搜索输入保持可点击。
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // 窗口创建或销毁后同步监听生命周期。
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); updateMonitoring() }

    // 仅在搜索激活且视图属于窗口时注册一次本地监听。
    private func updateMonitoring() {
        guard active, window != nil else { stopMonitoring(); return }
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self, event.window === self.window else { return event }
            let point = self.convert(event.locationInWindow, from: nil)
            let panel = CGRect(x: 0, y: self.bounds.height + SearchLayout.panelGap, width: self.bounds.width, height: self.panelHeight)
            if !self.bounds.contains(point) && !panel.contains(point) { self.onOutside() }
            return event
        }
    }

    // 关闭搜索或移除视图时释放 AppKit 监听。
    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
    }
}

// 只保留当前输入的联想结果，旧请求即使晚返回也不能覆盖新结果。
@MainActor
@Observable
final class SearchSuggestionState {
    private(set) var keyword = ""
    private(set) var items: [String] = []
    private var generation = 0
    private static let debounce = Duration.milliseconds(250)

    // 输入停顿后加载建议，空输入、取消和网络失败都保留普通搜索入口。
    func load(_ request: SearchSuggestionRequest, fetch: (String) async throws -> [String]) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let current = generation
        keyword = request.keyword
        items = []
        guard request.active && !keyword.isEmpty else { return }
        do {
            try await Task.sleep(for: Self.debounce)
            let values = try await fetch(request.keyword)
            try Task.checkCancellation()
            guard current == generation else { return }
            items = values
        } catch { /* 联想失败时仍可直接按回车搜索。 */ }
    }

    // 只有与输入框当前内容一致的结果才允许展示。
    func words(for query: String) -> [String] { keyword == query ? items : [] }

    // 提交或选择建议后立即取消旧结果的展示资格。
    func clear() { generation += 1; keyword = ""; items = [] }
}

// 候选面板采用当前皮肤的实体表面，避免底层内容透过文字。
private struct SearchSuggestionPanel: View {
    @Environment(\.theme) private var theme
    let query: String
    let words: [String]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("搜索建议").font(theme.controlFont(11, weight: .semibold))
                .foregroundStyle(theme.textMuted).padding(.horizontal, 10).padding(.vertical, 6)
            if query.isEmpty {
                Text("输入歌名、歌手或歌单，查看相关建议")
                    .font(.system(size: 12)).foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 9)
            } else if words.isEmpty {
                SearchSuggestionRow(title: "搜索「\(query)」", hint: "按回车搜索") { onSelect(query) }
            } else {
                ForEach(words, id: \.self) { word in
                    SearchSuggestionRow(title: word) { onSelect(word) }
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: theme.controls.fieldRadius).fill(Color(rgb: theme.raisedRGB)))
        .overlay(RoundedRectangle(cornerRadius: theme.controls.fieldRadius).strokeBorder(theme.glassEdge, lineWidth: 1))
        .shadow(color: .black.opacity(theme.isDark ? 0.3 : 0.12), radius: 12, y: 5)
    }
}

// 每个候选词可单独点击，并随皮肤提供悬停反馈和读屏名称。
private struct SearchSuggestionRow: View {
    @Environment(\.theme) private var theme
    @State private var hovering = false
    let title: String
    var hint: String? = nil
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(theme.textMuted)
                Text(title).font(.system(size: 13)).foregroundStyle(theme.text).lineLimit(1)
                Spacer(minLength: 4)
                if let hint { Text(hint).font(.system(size: 11)).foregroundStyle(theme.textMuted) }
                else { Image(systemName: "arrow.up.left").font(.system(size: 10)).foregroundStyle(theme.textMuted) }
            }
            .padding(.horizontal, 10).frame(height: 34).contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 7).fill(hovering ? theme.hover : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("搜索建议：\(title)")
    }
}
