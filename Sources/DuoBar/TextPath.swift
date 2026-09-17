import AppKit
import CoreText
import SwiftUI

/// 把短文字（数字、网速）转成轮廓路径，这样菜单栏和面板都能当普通图形来画。
enum TextPath {
    nonisolated(unsafe) private static let font: CTFont = {
        let base = NSFont.systemFont(ofSize: 100, weight: .bold)
        let descriptor = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        return (NSFont(descriptor: descriptor, size: 100) ?? base) as CTFont
    }()

    /// 按字形的实际墨迹范围缩放，居中放进 box。
    static func path(_ string: String, in box: CGRect) -> Path {
        guard !string.isEmpty, box.width > 0, box.height > 0 else { return Path() }
        let outline = outline(string)
        let bounds = outline.boundingBoxOfPath
        guard bounds.width > 0, bounds.height > 0 else { return Path() }

        let scale = min(box.width / bounds.width, box.height / bounds.height)
        // 字形坐标 y 轴向上，这里翻转成向下。
        var transform = CGAffineTransform(translationX: box.midX, y: box.midY)
            .scaledBy(x: scale, y: -scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        guard let result = outline.copy(using: &transform) else { return Path() }
        return Path(result)
    }

    private static func outline(_ string: String) -> CGPath {
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
