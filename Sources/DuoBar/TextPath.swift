import AppKit
import CoreText
import SwiftUI

/// 把短文字（数字、网速）转成轮廓路径，这样菜单栏和面板都能当普通图形来画。
enum TextPath {
    /// 一般用圆体；圆环顶部的电量数字和 iPhone Duo 一样用 SF Pro 粗体。
    enum Face {
        case rounded, plain
    }

    nonisolated(unsafe) private static let roundedFont: CTFont = {
        let base = NSFont.systemFont(ofSize: 100, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return (NSFont(descriptor: descriptor, size: 100) ?? base) as CTFont
    }()

    nonisolated(unsafe) private static let plainFont = NSFont.systemFont(ofSize: 100, weight: .bold) as CTFont

    /// 按字形的实际墨迹范围缩放，居中放进 box。
    static func path(_ string: String, in box: CGRect) -> Path {
        guard !string.isEmpty, box.width > 0, box.height > 0 else { return Path() }
        let outline = outline(string, face: .rounded)
        let bounds = outline.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return Path() }
        let scale = min(box.width / bounds.width, box.height / bounds.height)
        return place(outline, bounds: bounds, scale: scale, at: CGPoint(x: box.midX, y: box.midY))
    }

    /// 按墨迹高度缩放，中心放在 center。位数不同时字高不变，宽度跟着变。
    static func path(_ string: String, height: CGFloat, centeredAt center: CGPoint, face: Face = .rounded) -> Path {
        guard !string.isEmpty, height > 0 else { return Path() }
        let outline = outline(string, face: face)
        let bounds = outline.boundingBoxOfPath
        guard bounds.height > 0 else { return Path() }
        return place(outline, bounds: bounds, scale: height / bounds.height, at: center)
    }

    /// 墨迹高度为 height 时的宽度。
    static func width(_ string: String, height: CGFloat, face: Face = .rounded) -> CGFloat {
        let bounds = outline(string, face: face).boundingBoxOfPath
        return bounds.height > 0 ? bounds.width * height / bounds.height : 0
    }

    private static func place(_ outline: CGPath, bounds: CGRect, scale: CGFloat, at center: CGPoint) -> Path {
        // 字形坐标 y 轴向上，这里翻转成向下。
        var transform = CGAffineTransform(translationX: center.x, y: center.y)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        guard let result = outline.copy(using: &transform) else { return Path() }
        return Path(result)
    }

    private static func outline(_ string: String, face: Face) -> CGPath {
        let font = face == .plain ? plainFont : roundedFont
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: string, attributes: [.font: font])
        )
        let path = CGMutablePath()
        for run in CTLineGetGlyphRuns(line) as? [CTRun] ?? [] {
            let count = CTRunGetGlyphCount(run)
            var glyphs = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
            for index in 0 ..< count {
                guard let glyph = CTFontCreatePathForGlyph(font, glyphs[index], nil) else { continue }
                path.addPath(glyph, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
            }
        }
        return path
    }
}
