import AppKit
import SwiftUI

// 同一份颜色值同时支持取色器、HEX 和 RGB 输入，输入未合法前不修改持久化设置。
struct RGBColorEditor: View {
    @Environment(\.theme) private var theme
    let title: String
    @Binding var hex: String
    @State private var draftHex = ""
    @State private var invalid = false
    @FocusState private var editingHex: Bool

    private var color: RGB { ColorMath.parseHex(hex) ?? RGB(r: 0, g: 0, b: 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading
            hexInput
            ForEach(RGBChannel.allCases) { channel in
                channelRow(channel)
            }
            Text(invalid ? "请输入 3 位或 6 位 HEX 色值" : "RGB 0–255 · 输入 HEX 后按回车")
                .font(.system(size: 11))
                .foregroundStyle(invalid ? theme.danger : theme.textMuted)
        }
        .onAppear { draftHex = hex.uppercased() }
        .onChange(of: hex) { _, value in
            if !editingHex { draftHex = value.uppercased(); invalid = false }
        }
        .onChange(of: editingHex) { _, focused in
            if !focused { commitHex() }
        }
    }

    private var heading: some View {
        HStack {
            Text(title).font(theme.controlFont(14)).foregroundStyle(theme.textStrong)
            Spacer()
            ColorPicker(title, selection: colorBinding, supportsOpacity: false)
                .labelsHidden()
                .accessibilityLabel("选择\(title)")
        }
    }

    private var hexInput: some View {
        TextField("#RRGGBB", text: $draftHex)
            .textFieldStyle(.plain)
            .font(.system(size: 13).monospaced())
            .foregroundStyle(theme.textStrong)
            .padding(.horizontal, 10)
            .frame(height: 34)
            .modifier(ThemedSurface(role: .field, active: editingHex))
            .focused($editingHex)
            .onSubmit(commitHex)
            .accessibilityLabel("\(title) HEX")
    }

    // RGB 数值和滑块共享有界绑定，避免越界值写入配置。
    private func channelRow(_ channel: RGBChannel) -> some View {
        HStack(spacing: 8) {
            Text(channel.rawValue).font(.system(size: 12).monospaced()).frame(width: 12)
            Slider(value: channelBinding(channel), in: 0...255, step: 1)
                .tint(theme.accentStrong)
                .controlSize(.mini)
                .accessibilityLabel("\(title)\(channel.title)滑块")
            TextField(channel.rawValue, value: integerBinding(channel), format: .number.grouping(.never))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 12).monospacedDigit())
                .frame(width: 34)
                .accessibilityLabel("\(title)\(channel.title)数值")
        }
        .foregroundStyle(theme.textSecondary)
    }

    private var colorBinding: Binding<Color> {
        Binding(get: { color.color }, set: { selected in
            guard let value = NSColor(selected).hexString else { return }
            hex = value.uppercased()
            draftHex = hex
            invalid = false
        })
    }

    // 为 RGB 滑块提供与当前颜色双向同步的通道值。
    private func channelBinding(_ channel: RGBChannel) -> Binding<Double> {
        Binding(get: { color[keyPath: channel.keyPath] }, set: { update(channel, value: $0) })
    }

    // 数值输入使用整数绑定，避免 RGB 显示小数。
    private func integerBinding(_ channel: RGBChannel) -> Binding<Int> {
        Binding(get: { Int(color[keyPath: channel.keyPath].rounded()) },
                set: { update(channel, value: Double($0)) })
    }

    // 只更新所编辑的通道，并将结果规范化成六位 HEX。
    private func update(_ channel: RGBChannel, value: Double) {
        guard value.isFinite else { return }
        var next = color
        next[keyPath: channel.keyPath] = min(255, max(0, value))
        hex = next.hex
        draftHex = hex
        invalid = false
    }

    // 提交合法的 HEX；错误输入保留在编辑区并给出反馈。
    private func commitHex() {
        guard let parsed = ColorMath.parseHex(draftHex) else { invalid = true; return }
        invalid = false
        draftHex = parsed.hex
        if hex != parsed.hex { hex = parsed.hex }
    }
}

private enum RGBChannel: String, CaseIterable, Identifiable {
    case red = "R", green = "G", blue = "B"
    var id: String { rawValue }
    var title: String {
        switch self { case .red: return "红色"; case .green: return "绿色"; case .blue: return "蓝色" }
    }
    var keyPath: WritableKeyPath<RGB, Double> {
        switch self { case .red: return \.r; case .green: return \.g; case .blue: return \.b }
    }
}

extension NSColor {
    // 系统取色器转换为统一的 sRGB HEX，不保存显示器专用色彩空间。
    var hexString: String? {
        guard let rgb = usingColorSpace(.sRGB) else { return nil }
        return RGB(r: rgb.redComponent * 255, g: rgb.greenComponent * 255, b: rgb.blueComponent * 255).hex
    }
}
