//
//  Motion.swift
//  Kimo
//
//  播放页开合：从播放栏顶边那条缝向上下折叠，弹簧收住。
//

import SwiftUI

enum PlayerMotion {
    static let windowResizeDuration: TimeInterval = 0.44
    static let windowRevealStart = 0.35

    static func lyricsAnimation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.52, dampingFraction: 0.9)
    }

    static func lyricsTransition(reduceMotion: Bool, seam: CGFloat) -> AnyTransition {
        reduceMotion ? .opacity : .verticalFold(seam: seam)
    }
}

extension AnyTransition {
    /// 以 `seam`（0 顶 / 1 底）为折缝，页面向上下展开或收拢。
    static func verticalFold(seam: CGFloat) -> AnyTransition {
        .asymmetric(
            insertion: .modifier(
                active: VerticalFoldModifier(progress: 0, seam: seam),
                identity: VerticalFoldModifier(progress: 1, seam: seam)
            ),
            removal: .modifier(
                active: VerticalFoldModifier(progress: 0, seam: seam),
                identity: VerticalFoldModifier(progress: 1, seam: seam)
            )
        )
    }
}

struct VerticalFoldModifier: ViewModifier, Animatable {
    var progress: CGFloat
    var seam: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let t = progress
        let reveal = min(1, max(0.001, t))
        let settle = 0.97 + 0.03 * min(1, max(0, t))
        content
            .scaleEffect(
                x: 1,
                y: settle,
                anchor: UnitPoint(x: 0.5, y: seam)
            )
            .opacity(Double(min(1, max(0, t * 1.2))))
            .mask {
                Rectangle()
                    .scaleEffect(
                        x: 1,
                        y: reveal,
                        anchor: UnitPoint(x: 0.5, y: seam)
                    )
            }
    }
}
