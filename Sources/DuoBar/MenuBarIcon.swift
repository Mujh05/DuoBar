import AppKit

/// 生成菜单栏图标。没有颜色时用模板图像，由系统适配深色/浅色菜单栏；
/// 有颜色时只能画成普通图像，自己按菜单栏的外观选文字颜色。
enum MenuBarIcon {
    /// 100% 时的圆环半径（点）。圆环外径约 18.8 点，和系统菜单栏图标的视觉大小相当。
    static let baseRadius: CGFloat = 8.6
    static let baseSize = NSSize(width: 20, height: 22)
    /// 设置里“图标大小”滑块的范围。
    static let scaleRange: ClosedRange<Double> = 0.7 ... 1.5

    struct Metrics {
        var size: NSSize
        var radius: CGFloat
        /// 圆环中心。整体（圆环 + 圆点）在图像里上下居中，顶部留出充电符号的空间。
        var center: CGPoint
        var style: DuoStyle

        /// 实际画出来的高度：从顶部电源符号到底部圆点。
        var contentHeight: CGFloat {
            let top = -(DuoSpec.powerSymbolOffset - DuoSpec.powerSymbolHeight / 2)
            let bottom = sin(radians(DuoSpec.dotDegrees[1])) + style.dotRadius
            return (top + bottom) * radius
        }
    }

    static func metrics(scale: CGFloat) -> Metrics {
        let radius = baseRadius * scale
        let size = NSSize(width: (baseSize.width * scale).rounded(.up),
                          height: (baseSize.height * scale).rounded(.up))
        let style = DuoStyle.menuBar(scale: scale)
        let top = -(1 + style.ringWidth / 2) * radius
        let bottom = (sin(radians(DuoSpec.dotDegrees[1])) + style.dotRadius) * radius
        let center = CGPoint(x: size.width / 2, y: size.height / 2 - (top + bottom) / 2)
        return Metrics(size: size, radius: radius, center: center, style: style)
    }

    static func image(for state: IconState, scale: CGFloat = 1, embeddedPercent: Int? = nil,
                      embeddedPercentProgress: CGFloat = 0) -> NSImage {
        let colorful = state.hasTint
        let metrics = metrics(scale: scale)
        let image = NSImage(size: metrics.size, flipped: true) { _ in
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            let marks = DuoParts.combined(state, center: metrics.center, radius: metrics.radius, style: metrics.style,
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

    /// 各屏幕菜单栏里最矮的高度（点）；菜单栏自动隐藏的屏幕不算。
    @MainActor
    static func smallestMenuBarHeight() -> CGFloat? {
        NSScreen.screens
            .map { $0.frame.maxY - $0.visibleFrame.maxY }
            .filter { $0 > 0 }
            .min()
    }

    /// 跟菜单栏里其他图标一样：深色菜单栏用白色，浅色用接近黑色。
    private static func inkColor() -> CGColor {
        let match = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua, .vibrantLight, .vibrantDark])
        let dark = match == .darkAqua || match == .vibrantDark
        return dark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 0.85)
    }
}
