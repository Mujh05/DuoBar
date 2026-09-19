import SwiftUI

/// 设置侧边栏每一页的图标。圆角方块里用 DuoBar 自己的圆环和圆点画出这一页管的东西，
/// 和 App 图标、菜单栏里的图标是一家人。
struct PageIcon: View {
    let page: SettingsPage
    var size: CGFloat = 20

    var body: some View {
        IconBadge(color: page.color, size: size) {
            Canvas { context, canvas in
                let box = CGRect(origin: .zero, size: canvas).insetBy(dx: canvas.width * 0.17, dy: canvas.height * 0.17)
                context.draw(PageGlyph.marks(page, in: box), color: .white)
            }
        }
    }
}

/// 每一页图标里的图形，按 box 的大小画，用白色。
enum PageGlyph {
    /// 图标只有 20 点左右，线条和圆点都比菜单栏里的再粗一些。
    private static let style = DuoStyle(ringWidth: 0.22, dotRadius: 0.15, wifiWeight: 1.25, wifiScale: 1.05, dimAlpha: 0.4)

    static func marks(_ page: SettingsPage, in box: CGRect) -> [DuoMark] {
        let g = box.width
        let c = CGPoint(x: box.midX, y: box.midY)
        switch page {
        case .icon:
            // 三合一图标本身：圆环读数、Wi-Fi、底部圆点。
            let R = g * 0.44
            return DuoParts.ring(loop: DuoParts.circle(c, R), lineWidth: style.ringWidth * R, level: 0.76,
                                 bottomGap: DuoSpec.bottomGapFraction, topGap: 0, trackAlpha: style.dimAlpha, fillAlpha: 1)
                + DuoParts.centerGlyph(.wifi(connected: true), center: c, radius: R, style: style)
                + DuoParts.dots(center: c, radius: R, style: style,
                                lights: [DotLight(on: true), DotLight(on: true), DotLight(on: true), DotLight(on: false)])

        case .metrics:
            // 一个读数圆环：底部开口小一些，像仪表。
            let R = g * 0.45
            let center = CGPoint(x: c.x, y: c.y + 0.06 * R)
            return DuoParts.ring(loop: DuoParts.circle(center, R), lineWidth: 0.26 * R, level: 0.68,
                                 bottomGap: DuoSpec.compactGapFraction, topGap: 0, trackAlpha: style.dimAlpha, fillAlpha: 1)
                + [.fill(TextPath.path("%", height: R * 0.78, centeredAt: center, face: .plain))]

        case .indicators:
            // 底部那 4 个圆点：外侧两个略高，像图标底部的弧线；三个亮，一个灭。
            let xs: [CGFloat] = [-0.39, -0.13, 0.13, 0.39], ys: [CGFloat] = [-0.05, 0.05, 0.05, -0.05]
            let dots = (0 ..< 4).map { DuoMark.fill(DuoParts.dot(at: CGPoint(x: c.x + xs[$0] * g, y: c.y + ys[$0] * g),
                                                                  radius: g * 0.1)) }
            return [dots[0], .layer(alpha: style.dimAlpha, [dots[1]]), dots[2], dots[3]]

        case .menuBar:
            // 一块屏幕，顶上是菜单栏；菜单栏里镂空出左边的菜单文字和右边 DuoBar 的圆环。
            let screen = CGRect(x: box.minX, y: box.minY + g * 0.1, width: g, height: g * 0.8)
            let line = g * 0.08
            let outline = Path(roundedRect: screen.insetBy(dx: line / 2, dy: line / 2), cornerRadius: g * 0.12, style: .continuous)
            let bar = Path(roundedRect: screen, cornerRadius: g * 0.14, style: .continuous)
                .intersection(Path(CGRect(x: screen.minX, y: screen.minY, width: screen.width, height: g * 0.32)))
            let barY = screen.minY + g * 0.16
            var menu = Path()
            menu.move(to: CGPoint(x: screen.minX + g * 0.17, y: barY))
            menu.addLine(to: CGPoint(x: screen.minX + g * 0.4, y: barY))
            let ring = DuoParts.circle(CGPoint(x: screen.maxX - g * 0.22, y: barY), g * 0.075)
                .path(from: DuoSpec.bottomGapFraction, to: 1 - DuoSpec.bottomGapFraction)
            return [.stroke(outline, width: line), .fill(bar), .knockout(menu, width: g * 0.065), .knockout(ring, width: g * 0.05)]

        case .updates:
            return [.symbol("arrow.clockwise", rect: box.insetBy(dx: g * 0.04, dy: g * 0.04))]

        case .general:
            return [.symbol("gearshape.fill", rect: box)]
        }
    }
}
