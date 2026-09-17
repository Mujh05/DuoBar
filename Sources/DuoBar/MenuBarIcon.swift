import AppKit

/// 生成菜单栏图标。没有颜色时用模板图像，由系统适配深色/浅色菜单栏；
/// 有颜色时只能画成普通图像，自己按菜单栏的外观选文字颜色。
enum MenuBarIcon {
    /// 圆环半径（点）。圆环外径约 18.8 点，和系统菜单栏图标的视觉大小相当。
    static let radius: CGFloat = 8.6
    static let size = NSSize(width: 20, height: 22)

    /// 圆环中心。整体（圆环 + 圆点）在图像里上下居中，顶部留出充电符号的空间。
    static var center: CGPoint {
        let style = DuoStyle.menuBar
        let top = -(1 + style.ringWidth / 2) * radius
        let bottom = (sin(radians(DuoSpec.dotDegrees[1])) + style.dotRadius) * radius
        return CGPoint(x: size.width / 2, y: size.height / 2 - (top + bottom) / 2)
    }

    static func image(for state: IconState, embeddedPercent: Int? = nil,
                      embeddedPercentProgress: CGFloat = 0) -> NSImage {
        let colorful = state.hasTint
        let image = NSImage(size: size, flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let marks = DuoParts.combined(state, center: center, radius: radius, style: .menuBar,
                                           embeddedPercent: embeddedPercent,
                                           embeddedPercentProgress: embeddedPercentProgress)
            if colorful {
                CGMarkRenderer.draw(marks, in: cg, ink: inkColor(), colorful: true)
            } else {
                CGMarkRenderer.draw(marks, in: cg)
            }
            return true
        }
        image.isTemplate = !colorful
        if colorful {
            // 菜单栏随壁纸在深浅之间切换时，每次重画都重新取颜色。
            image.cacheMode = .never
        }
        return image
    }

    /// 跟菜单栏里其他图标一样：深色菜单栏用白色，浅色用接近黑色。
    private static func inkColor() -> CGColor {
        let match = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        let dark = match == .darkAqua || match == .vibrantDark
        return dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 0.85)
    }
}
