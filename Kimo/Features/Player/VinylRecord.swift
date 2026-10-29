//
//  VinylRecord.swift
//  Kimo
//
//  播放页大唱片：彩色透明彩胶、中央圆形封面、固定唱臂。光晕跟封面主色走。
//

import AppKit
import SwiftUI

struct VinylRecord: View {
    @Environment(\.theme) private var theme
    let url: URL?
    let seed: String
    let side: CGFloat
    let spin: Bool
    let playing: Bool

    @State private var tint: Color?
    @State private var frozenAngle: Double = 0

    private var discColor: Color { tint ?? theme.accent }
    private var labelSide: CGFloat { side * 0.52 }

    var body: some View {
        ZStack {
            glow
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !(spin && playing))) { context in
                disc
                    .rotationEffect(.degrees(angle(at: context.date)))
            }
            highlight
            TonearmView(side: side)
        }
        .frame(width: side * 1.28, height: side * 1.22)
        .task(id: url?.absoluteString) {
            tint = await Self.vinylTint(from: url, fallback: theme.accent)
        }
        .onChange(of: playing) { _, isPlaying in
            if !isPlaying {
                frozenAngle = angle(at: Date())
            }
        }
    }

    private var glow: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        discColor.opacity(theme.isDark ? 0.72 : 0.48),
                        discColor.opacity(theme.isDark ? 0.32 : 0.22),
                        .clear,
                    ],
                    center: .center,
                    startRadius: side * 0.30,
                    endRadius: side * 0.70
                )
            )
            .frame(width: side * 1.40, height: side * 1.40)
            .blur(radius: side * 0.055)
    }

    private var disc: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            discColor.opacity(0.78),
                            discColor.opacity(0.96),
                            discColor,
                            discColor.opacity(0.72),
                        ],
                        center: .center,
                        startRadius: labelSide * 0.36,
                        endRadius: side * 0.50
                    )
                )

            if let url {
                CoverImage(url: url, radius: side / 2, seed: seed)
                    .frame(width: side, height: side)
                    .opacity(0.11)
                    .blur(radius: 1.4)
                    .saturation(0.65)
                    .clipShape(Circle())
                    .blendMode(.overlay)
            }

            VinylGrooves(side: side, labelRatio: 0.52, dark: theme.isDark)

            Circle()
                .stroke(Color.black.opacity(theme.isDark ? 0.28 : 0.14), lineWidth: max(2, side * 0.01))
                .frame(width: labelSide + side * 0.018, height: labelSide + side * 0.018)

            CoverImage(url: url, radius: labelSide / 2, seed: seed)
                .frame(width: labelSide, height: labelSide)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .strokeBorder(Color.white.opacity(theme.isDark ? 0.30 : 0.55), lineWidth: 1.6)
                }
                .shadow(color: .black.opacity(0.28), radius: 7)

            Circle()
                .fill(Color.black.opacity(0.82))
                .frame(width: side * 0.030, height: side * 0.030)
            Circle()
                .fill(Color.white.opacity(0.52))
                .frame(width: side * 0.011, height: side * 0.011)
        }
        .frame(width: side, height: side)
        .overlay {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme.isDark ? 0.22 : 0.34),
                            Color.black.opacity(0.18),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
        .shadow(color: discColor.opacity(0.40), radius: 20, y: 8)
    }

    private var highlight: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(theme.isDark ? 0.20 : 0.30),
                            Color.white.opacity(theme.isDark ? 0.05 : 0.10),
                            .clear,
                        ],
                        center: UnitPoint(x: 0.30, y: 0.26),
                        startRadius: 0,
                        endRadius: side * 0.40
                    )
                )
                .frame(width: side, height: side)
                .blendMode(.screen)

            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(theme.isDark ? 0.26 : 0.38),
                            Color.white.opacity(0.04),
                            .clear,
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(2, side * 0.011)
                )
                .frame(width: side, height: side)
        }
        .allowsHitTesting(false)
    }

    private func angle(at date: Date) -> Double {
        guard spin else { return 0 }
        guard playing else { return frozenAngle }
        return (date.timeIntervalSinceReferenceDate * 15).truncatingRemainder(dividingBy: 360)
    }

    private static func vinylTint(from url: URL?, fallback: Color) async -> Color {
        guard let sampled = await averageRGB(from: url) else { return fallback }
        var hsl = ColorMath.rgbToHsl(sampled)
        hsl.s = ColorMath.clamp(max(0.50, hsl.s * 1.55), 0.50, 0.90)
        hsl.l = ColorMath.clamp(hsl.l * 1.08, 0.40, 0.60)
        return ColorMath.hslToRgb(hsl).color
    }

    private static func averageRGB(from url: URL?) async -> RGB? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let image = NSImage(data: data),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 4, height > 4 else { return nil }
        let step = max(1, min(width, height) / 28)
        var red = 0.0, green = 0.0, blue = 0.0, count = 0.0
        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                guard let raw = bitmap.colorAt(x: x, y: y),
                      let color = raw.usingColorSpace(.sRGB) else { continue }
                let luma = 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
                if luma < 0.08 || luma > 0.92 { continue }
                red += color.redComponent
                green += color.greenComponent
                blue += color.blueComponent
                count += 1
            }
        }
        guard count > 0 else { return nil }
        return RGB(r: red / count * 255, g: green / count * 255, b: blue / count * 255)
    }
}

private struct TonearmView: View {
    let side: CGFloat

    var body: some View {
        let radius = side / 2
        let pivot = polar(28, radius: radius * 1.045)
        let head = polar(82, radius: radius * 0.71)
        let mid = CGPoint(x: (pivot.x + head.x) / 2, y: (pivot.y + head.y) / 2)
        let length = hypot(head.x - pivot.x, head.y - pivot.y)
        let angle = atan2(head.x - pivot.x, -(head.y - pivot.y)) * 180 / .pi
        let armWidth = max(3.6, side * 0.011)

        ZStack {
            TonearmCable(origin: pivot, side: side)
                .stroke(
                    Color.white,
                    style: StrokeStyle(lineWidth: max(2.2, side * 0.007), lineCap: .round, lineJoin: .round)
                )
                .shadow(color: .black.opacity(0.12), radius: 1)
                .frame(width: side, height: side)

            Capsule()
                .fill(Color.white)
                .frame(width: armWidth, height: length)
                .rotationEffect(.degrees(angle))
                .offset(x: mid.x, y: mid.y)
                .shadow(color: .black.opacity(0.18), radius: 3, y: 1)

            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(width: armWidth + 5, height: max(10, side * 0.042))
                .rotationEffect(.degrees(angle))
                .offset(x: head.x, y: head.y)
                .shadow(color: .black.opacity(0.16), radius: 2)

            Circle()
                .fill(Color.white)
                .frame(width: side * 0.046, height: side * 0.046)
                .overlay {
                    Circle()
                        .fill(Color.black.opacity(0.10))
                        .frame(width: side * 0.018, height: side * 0.018)
                }
                .shadow(color: .black.opacity(0.2), radius: 4, y: 1)
                .offset(x: pivot.x, y: pivot.y)
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }

    private func polar(_ clock: Double, radius: CGFloat) -> CGPoint {
        let rad = clock * .pi / 180
        return CGPoint(x: CGFloat(sin(rad)) * radius, y: CGFloat(-cos(rad)) * radius)
    }
}

private struct TonearmCable: Shape {
    var origin: CGPoint
    var side: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pivot = CGPoint(x: center.x + origin.x, y: center.y + origin.y)
        let up = CGPoint(x: pivot.x + side * 0.006, y: pivot.y - side * 0.075)
        let end = CGPoint(x: pivot.x + side * 0.072, y: pivot.y - side * 0.006)
        let control = CGPoint(x: pivot.x + side * 0.09, y: pivot.y - side * 0.09)
        var path = Path()
        path.move(to: pivot)
        path.addLine(to: up)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}

private struct VinylGrooves: View {
    let side: CGFloat
    let labelRatio: CGFloat
    let dark: Bool

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2
            let inner = maxRadius * labelRatio + 4
            let outer = maxRadius - 3
            let cut = Color.black.opacity(dark ? 0.10 : 0.08)
            let ridge = Color.white.opacity(dark ? 0.07 : 0.10)
            var radius = inner
            var index = 0
            while radius < outer {
                var path = Path()
                path.addEllipse(in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                ))
                let ink = index.isMultiple(of: 2) ? cut : ridge
                context.stroke(path, with: .color(ink), lineWidth: index.isMultiple(of: 6) ? 1.15 : 0.65)
                radius += 2.45
                index += 1
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
    }
}
