// 与 Kimo 下除 KimoApp.swift 外的 Swift 源码一起编译，测试使用独立临时设置。
import AppKit
import Foundation
import SwiftUI

@main
struct SearchCheck {
    // 验证真实响应结构、异步切词保护以及各皮肤的搜索框底色。
    @MainActor
    static func main() async throws {
        checkSuggestionMapping()
        try await checkSuggestionOrdering()
        try checkFieldColors()
        print("搜索检查通过：候选映射、空输入、异步切词、清除状态、8 套皮肤和自定义配色")
    }

    // 联想词只读取首个通用分组，过滤空值、非文本和重复项。
    @MainActor
    private static func checkSuggestionMapping() {
        let rows: [JSON] = [" 周杰伦 ", "周杰伦", "", "晴天", "稻香", "夜曲", "青花瓷", "七里香", "多余"]
            .map { ["HintInfo": $0] }
        let payload: [JSON] = [["RecordDatas": rows + [["HintInfo": 42]]],
                               ["RecordDatas": [["HintInfo": "其他分组"]]]]
        check(MusicAPI.suggestionKeywords(from: payload) == ["周杰伦", "晴天", "稻香", "夜曲", "青花瓷", "七里香"], "联想词过滤或排序错误")
        check(MusicAPI.suggestionKeywords(from: [JSON]()).isEmpty, "空分组应返回空列表")
        check(MusicAPI.suggestionKeywords(from: ["unexpected": true]).isEmpty, "无效响应应返回空列表")
    }

    // 旧词响应晚于新词时不能覆盖结果；清除后旧请求也不能重新打开建议。
    @MainActor
    private static func checkSuggestionOrdering() async throws {
        let state = SearchSuggestionState()
        var calls = 0
        await state.load(.init(text: "  ", active: true)) { _ in calls += 1; return ["无效"] }
        check(calls == 0 && state.items.isEmpty, "空输入不应请求接口")
        let old = Task { await state.load(.init(text: "旧词", active: true)) { _ in
            try await Task.sleep(for: .milliseconds(600)); return ["旧结果"]
        } }
        try await Task.sleep(for: .milliseconds(350))
        let latest = Task { await state.load(.init(text: "新词", active: true)) { _ in ["新结果"] } }
        await latest.value
        await old.value
        check(state.words(for: "新词") == ["新结果"], "旧响应覆盖了新词")
        check(state.words(for: "旧词").isEmpty, "旧词结果不应显示")
        let pending = Task { await state.load(.init(text: "待清除", active: true)) { _ in
            try await Task.sleep(for: .milliseconds(200)); return ["过期结果"]
        } }
        try await Task.sleep(for: .milliseconds(350))
        state.clear()
        await pending.value
        check(state.items.isEmpty, "清除后旧响应重新出现")
    }

    // 实际渲染聚焦和未聚焦输入框，检查颜色与每套皮肤的 raisedRGB 一致。
    @MainActor
    private static func checkFieldColors() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kimo-search-check-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = AppSettings(storageURL: directory.appendingPathComponent("settings.json"))
        settings.appearanceMode = .theme
        for skin in Skin.allCases {
            let theme = Theme.make(skin: skin, settings: settings, isDark: false)
            checkField(theme, focused: false, name: skin.title)
            checkField(theme, focused: true, name: skin.title)
        }
        settings.appearanceMode = .solid
        settings.backgroundHex = "#345678"
        settings.accentHex = "#D12A40"
        let solid = Theme.make(settings: settings, isDark: true)
        checkField(solid, focused: false, name: "自定义配色")
        checkField(solid, focused: true, name: "自定义配色")
    }

    // 从输入框中心采样，避免边框、圆角和主题材质影响颜色对比。
    @MainActor
    private static func checkField(_ theme: Theme, focused: Bool, name: String) {
        let view = Color.clear.frame(width: 100, height: 40)
            .modifier(ThemedSurface(role: .field, active: focused)).environment(\.theme, theme)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let actual = NSBitmapImageRep(cgImage: image).colorAt(x: image.width / 2, y: image.height / 2),
              let expected = NSColor(Color(rgb: theme.raisedRGB)).usingColorSpace(.sRGB) else {
            fail("\(name) 的搜索框无法渲染")
        }
        // ImageRenderer 输出 sRGB 像素；colorAt 已解开预乘 alpha，直接比较通道值。
        let difference = max(abs(actual.redComponent - expected.redComponent),
                             abs(actual.greenComponent - expected.greenComponent),
                             abs(actual.blueComponent - expected.blueComponent))
        // 部分皮肤在半透明表面下叠加立体阴影，因此允许阴影引起的明度变化。
        check(difference < 0.16, "\(name) 的\(focused ? "聚焦" : "未聚焦")搜索框颜色不符：实际 \(actual)，预期 \(expected)")
    }

    // 检查失败时使用非零退出码，便于自动化构建发现回归。
    private static func check(_ condition: Bool, _ message: String) { if !condition { fail(message) } }

    // 输出简洁的失败原因并结束检查。
    private static func fail(_ message: String) -> Never { fputs("搜索检查失败：\(message)\n", stderr); exit(EXIT_FAILURE) }
}
