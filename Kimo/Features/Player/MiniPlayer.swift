// 迷你模式：跟随当前皮肤的播放器与播放来源列表。
import AppKit
import SwiftUI

struct MiniPlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 12) {
            header
            MiniPlayerControls()
            Rectangle().fill(theme.divider).frame(height: 1)
            MiniSourceList()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if model.settings.windowEffect == .vibrancy {
                WindowMaterial(material: .underWindowBackground)
            }
            Backdrop(theme: theme)
            theme.sheet.opacity(0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: theme.radiusSheet))
        .overlay {
            RoundedRectangle(cornerRadius: theme.radiusSheet)
                .strokeBorder(theme.glassEdge, lineWidth: 1)
        }
        .ignoresSafeArea()
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(theme.accentStrong)
                .accessibilityHidden(true)
            Text("Kimo")
                .font(theme.titleFont(18, weight: .bold))
                .foregroundStyle(theme.textStrong)
            Spacer()
            headerButton("恢复完整窗口", symbol: "arrow.up.left.and.arrow.down.right") {
                // 通过窗口协调器恢复原有大窗尺寸和界面。
                model.setMini(false)
            }
            pinButton
        }
        .frame(height: 28)
        .background { WindowDragArea() }
    }

    private var pinButton: some View {
        let bridge = WindowBridge.shared
        return headerButton(bridge.isMiniPinned ? "取消窗口置顶" : "窗口置顶",
                            symbol: bridge.isMiniPinned ? "pin.fill" : "pin",
                            active: bridge.isMiniPinned, action: bridge.toggleMiniPinned)
            .accessibilityValue(bridge.isMiniPinned ? "已置顶" : "未置顶")
    }

    // 统一窗口按钮的主题外观、选中状态、提示和辅助功能名称。
    private func headerButton(_ title: String, symbol: String, active: Bool = false,
                              action: @escaping () -> Void) -> some View {
        IconButton(size: 28, active: active, action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: theme.controls.iconWeight))
        }
        .help(title)
        .accessibilityLabel(title)
    }
}
