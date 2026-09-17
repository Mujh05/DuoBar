import AppKit
import SwiftUI

/// 用 Core Graphics 画 DuoMark。
enum CGMarkRenderer {
    /// - Parameters:
    ///   - ink: 普通图形的颜色。
    ///   - colorful: false 时忽略 tinted（模板图像只看透明度）。
    static func draw(_ marks: [DuoMark], in cg: CGContext,
                     ink: CGColor = CGColor(gray: 0, alpha: 1), colorful: Bool = false) {
        for mark in marks {
            switch mark {
            case let .stroke(path, width):
                cg.addPath(path.cgPath)
                cg.setLineWidth(width)
                cg.setLineCap(.round)
                cg.setLineJoin(.round)
                cg.setStrokeColor(ink)
                cg.strokePath()

            case let .fill(path):
                cg.addPath(path.cgPath)
                cg.setFillColor(ink)
                cg.fillPath()

            case let .knockout(path, width):
                cg.saveGState()
                cg.setBlendMode(.clear)
                cg.addPath(path.cgPath)
                cg.setLineWidth(width)
                cg.setLineCap(.round)
                cg.strokePath()
                cg.restoreGState()

            case let .symbol(name, rect, variable):
                guard let symbol = SymbolCache.placed(name, in: rect, variable: variable) else { continue }
                cg.saveGState()
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                drawImage(symbol.image, in: symbol.frame, cg: cg, operation: .sourceOver)
                // 模板符号的像素颜色不一定是想要的颜色，统一染色。
                cg.setBlendMode(.sourceIn)
                cg.setFillColor(ink)
                cg.fill(symbol.frame)
                cg.endTransparencyLayer()
                cg.restoreGState()

            case let .knockoutSymbol(name, rect):
                guard let symbol = SymbolCache.placed(name, in: rect) else { continue }
                drawImage(symbol.image, in: symbol.frame, cg: cg, operation: .destinationOut)

            case let .layer(alpha, children):
                cg.saveGState()
                cg.setAlpha(alpha)
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                draw(children, in: cg, ink: ink, colorful: colorful)
                cg.endTransparencyLayer()
                cg.restoreGState()

            case let .tinted(tint, children):
                draw(children, in: cg, ink: colorful ? resolve(tint) : ink, colorful: colorful)
            }
        }
    }

    private static func drawImage(_ image: NSImage, in rect: CGRect, cg: CGContext, operation: NSCompositingOperation) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        image.draw(in: rect, from: .zero, operation: operation, fraction: 1, respectFlipped: true, hints: nil)
        NSGraphicsContext.restoreGraphicsState()
    }

    /// 系统颜色在深色和浅色外观下不一样，按当前绘制的外观取值。
    private static func resolve(_ tint: DuoTint) -> CGColor {
        var color = tint.nsColor.cgColor
        NSAppearance.currentDrawing().performAsCurrentDrawingAppearance {
            color = tint.nsColor.cgColor
        }
        return color
    }
}

extension GraphicsContext {
    /// 在 SwiftUI Canvas 里画 DuoMark。
    func draw(_ marks: [DuoMark], color: Color) {
        for mark in marks {
            switch mark {
            case let .stroke(path, width):
                stroke(path, with: .color(color),
                       style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))

            case let .fill(path):
                fill(path, with: .color(color))

            case let .knockout(path, width):
                var context = self
                context.blendMode = .clear
                context.stroke(path, with: .color(.black), style: StrokeStyle(lineWidth: width, lineCap: .round))

            case let .symbol(name, rect, variable):
                // SF Symbol 的 NSImage 在 Canvas 里不认 shading，用它当遮罩再填色。
                guard let symbol = SymbolCache.placed(name, in: rect, variable: variable) else { continue }
                let image = resolve(Image(nsImage: symbol.image))
                var context = self
                context.clipToLayer { layer in
                    layer.draw(image, in: symbol.frame)
                }
                context.fill(Path(symbol.frame), with: .color(color))

            case let .knockoutSymbol(name, rect):
                guard let symbol = SymbolCache.placed(name, in: rect) else { continue }
                let image = resolve(Image(nsImage: symbol.image))
                var context = self
                context.blendMode = .destinationOut
                context.draw(image, in: symbol.frame)

            case let .layer(alpha, children):
                var context = self
                context.opacity *= alpha
                context.drawLayer { layer in
                    layer.draw(children, color: color)
                }

            case let .tinted(tint, children):
                draw(children, color: tint.color)
            }
        }
    }
}
