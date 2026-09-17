import AppKit

/// `DuoBar --render-app-icon <xxx.iconset>`：画出应用图标的各个尺寸，交给 iconutil 打包。
@MainActor
enum AppIconRenderer {
    static func renderIconSet(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for points in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let name = scale == 1 ? "icon_\(points)x\(points).png" : "icon_\(points)x\(points)@2x.png"
                PreviewRenderer.write(render(pixels: points * scale), to: directory.appendingPathComponent(name))
            }
        }
    }

    static func render(pixels: Int) -> NSBitmapImageRep {
        let side = CGFloat(pixels)
        let unit = side / 1024
        return PreviewRenderer.bitmap(size: CGSize(width: side, height: side), scale: 1) { cg in
            // macOS 图标网格：1024 画布里 824 的圆角方块。
            let body = CGRect(x: 100, y: 100, width: 824, height: 824).applying(CGAffineTransform(scaleX: unit, y: unit))
            let shape = CGPath(roundedRect: body, cornerWidth: 185 * unit, cornerHeight: 185 * unit, transform: nil)

            cg.saveGState()
            // 阴影偏移不受坐标翻转影响，负值才是向下。
            cg.setShadow(offset: CGSize(width: 0, height: -10 * unit), blur: 24 * unit,
                         color: CGColor(gray: 0, alpha: 0.35))
            cg.addPath(shape)
            cg.setFillColor(CGColor(gray: 0.1, alpha: 1))
            cg.fillPath()
            cg.restoreGState()

            cg.saveGState()
            cg.addPath(shape)
            cg.clip()
            let colors = [CGColor(srgbRed: 0.27, green: 0.30, blue: 0.37, alpha: 1),
                          CGColor(srgbRed: 0.07, green: 0.08, blue: 0.10, alpha: 1)] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1]) {
                cg.drawLinearGradient(gradient, start: CGPoint(x: body.midX, y: body.minY),
                                      end: CGPoint(x: body.midX, y: body.maxY), options: [])
            }

            // 白色的三合一图标：76% 电量、Wi-Fi、3 个圆点。
            let dots = DotsPart(lights: (0 ..< IconLayout.dotCount).map { DotLight(on: $0 < 3) }, metric: nil)
            let state = IconState(ring: PreviewRenderer.battery(76, .battery), center: PreviewRenderer.network(.wifi), dots: dots)
            let style = pixels <= 32 ? DuoStyle.menuBar : DuoStyle.reference
            let marks = DuoParts.combined(state, center: CGPoint(x: body.midX, y: body.midY), radius: 290 * unit, style: style)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            CGMarkRenderer.draw(marks, in: cg)
            cg.setBlendMode(.sourceIn)
            cg.setFillColor(CGColor(gray: 1, alpha: 1))
            cg.fill(body)
            cg.endTransparencyLayer()
            cg.restoreGState()
        }
    }
}
