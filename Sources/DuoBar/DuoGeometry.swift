import AppKit
import SwiftUI

// 坐标系统一为 y 轴向下（翻转的 NSImage 和 SwiftUI Canvas 都是这样），
// 角度增大 = 屏幕上顺时针：0° 在右，90° 在下，180° 在左，270° 在上。

/// 一个绘制指令。菜单栏（Core Graphics）和面板（SwiftUI Canvas）各自实现一遍。
enum DuoMark {
    case stroke(Path, width: CGFloat)
    case fill(Path)
    /// 沿路径擦掉已画的像素，用来给 Wi-Fi 斜杠留出缝隙。
    case knockout(Path, width: CGFloat)
    /// variable 是 SF Symbols 的可变值（比如音量波纹亮几格），nil 表示全亮。
    case symbol(String, rect: CGRect, variable: Double? = nil)
    /// 沿符号的形状擦掉已画的像素（拆开后的指示灯：实心圆里镂空图标）。
    case knockoutSymbol(String, rect: CGRect)
    /// 先把一组图形画成不透明的图层，再整体按 alpha 合成，避免重叠处颜色叠深。
    indirect case layer(alpha: CGFloat, [DuoMark])
    /// 这一组用指定颜色画；菜单栏模板图像里颜色会被忽略。
    indirect case tinted(DuoTint, [DuoMark])

    /// tint 为 nil 时原样返回。
    static func withTint(_ tint: DuoTint?, _ marks: [DuoMark]) -> [DuoMark] {
        guard let tint else { return marks }
        return [.tinted(tint, marks)]
    }
}

/// 线宽等比例，全部以圆环半径 R 为单位。
struct DuoStyle: Sendable {
    var ringWidth: CGFloat
    var dotRadius: CGFloat
    /// Wi-Fi 弧线线宽的倍数
    var wifiWeight: CGFloat
    /// Wi-Fi 图形整体大小的倍数
    var wifiScale: CGFloat
    /// 未点亮部分的透明度
    var dimAlpha: CGFloat

    /// 从新闻配图里的 iPhone Duo 图标量出来的原始比例。
    static let reference = DuoStyle(ringWidth: 0.156, dotRadius: 0.109, wifiWeight: 1, wifiScale: 1, dimAlpha: 0.28)
    /// 菜单栏里图标只有十几个点高，线条稍微加粗才看得清。
    static let menuBar = DuoStyle(ringWidth: 0.18, dotRadius: 0.13, wifiWeight: 1.15, wifiScale: 1.06, dimAlpha: 0.3)

    /// 菜单栏图标放大后，线条逐渐回到原始比例，免得大图标显得笨重。
    static func menuBar(scale: CGFloat) -> DuoStyle {
        let t = min(max((scale - 1) / 1, 0), 0.5)
        return DuoStyle(
            ringWidth: lerp(menuBar.ringWidth, reference.ringWidth, t),
            dotRadius: lerp(menuBar.dotRadius, reference.dotRadius, t),
            wifiWeight: lerp(menuBar.wifiWeight, reference.wifiWeight, t),
            wifiScale: lerp(menuBar.wifiScale, reference.wifiScale, t),
            dimAlpha: menuBar.dimAlpha
        )
    }
}

enum DuoSpec {
    /// 圆环底部开口的半角
    static let bottomGapDegrees: CGFloat = 59.5
    /// 底部不放圆点时，开口收小到这个半角
    static let compactGapDegrees: CGFloat = 32
    /// 充电时圆环顶部为闪电留出的开口半角
    static let topGapDegrees: CGFloat = 21
    /// 四个圆点的位置，从左到右
    static let dotDegrees: [CGFloat] = [120, 100, 80, 60]
    static let wifiApex: CGFloat = 0.37
    static let wifiHalfAngle: CGFloat = 40
    /// 由内到外的两条弧：半径、线宽
    static let wifiArcs: [(radius: CGFloat, width: CGFloat)] = [(0.385, 0.146), (0.63, 0.135)]
    static let wifiWedge: CGFloat = 0.198
    /// 顶部电源符号的中心相对圆环中心的偏移和高度
    static let powerSymbolOffset: CGFloat = -0.93
    static let powerSymbolHeight: CGFloat = 0.56

    /// 中间文字的范围（宽、高）
    static let textWidth: CGFloat = 1.2
    static let textHeight: CGFloat = 0.64

    static var bottomGapFraction: CGFloat { bottomGapDegrees / 360 }
    static var compactGapFraction: CGFloat { compactGapDegrees / 360 }
    static var topGapFraction: CGFloat { topGapDegrees / 360 }

    /// 圆环顶部嵌入电量数字时，为不同位数留出的开口半角。
    static func percentTopGapFraction(_ percent: Int) -> CGFloat {
        let degrees: CGFloat = switch String(percent).count {
        case 1: 25
        case 2: 32
        default: 40
        }
        return degrees / 360
    }
}

func radians(_ degrees: CGFloat) -> CGFloat { degrees * .pi / 180 }

func polar(_ center: CGPoint, _ radius: CGFloat, _ degrees: CGFloat) -> CGPoint {
    CGPoint(x: center.x + radius * cos(radians(degrees)), y: center.y + radius * sin(radians(degrees)))
}

func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat { a + (b - a) * t }

func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
    CGPoint(x: lerp(a.x, b.x, t), y: lerp(a.y, b.y, t))
}

/// 0...1 之间的平滑过渡，edge0 之前为 0，edge1 之后为 1。
func smoothstep(_ edge0: CGFloat, _ edge1: CGFloat, _ x: CGFloat) -> CGFloat {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - 圆角矩形闭环（圆是它的特例）

/// 从底边中点出发、沿屏幕顺时针走一圈的圆角矩形。宽高相等且圆角为一半时就是圆，
/// 所以圆环可以连续地变形成电池外框。
struct LoopShape {
    var center: CGPoint
    var width: CGFloat
    var height: CGFloat
    var corner: CGFloat

    private enum Segment {
        case line(CGPoint, CGPoint)
        case arc(center: CGPoint, radius: CGFloat, start: CGFloat, sweep: CGFloat)

        var length: CGFloat {
            switch self {
            case let .line(p, q): hypot(q.x - p.x, q.y - p.y)
            case let .arc(_, radius, _, sweep): radius * sweep
            }
        }

        func append(to path: inout Path, from t0: CGFloat, to t1: CGFloat, startsSubpath: Bool) {
            switch self {
            case let .line(p, q):
                let a = lerp(p, q, t0), b = lerp(p, q, t1)
                if startsSubpath { path.move(to: a) } else { path.addLine(to: a) }
                path.addLine(to: b)
            case let .arc(center, radius, start, sweep):
                let a0 = start + sweep * t0
                let start = CGPoint(x: center.x + radius * cos(a0), y: center.y + radius * sin(a0))
                if startsSubpath { path.move(to: start) }
                path.addRelativeArc(center: center, radius: radius,
                                    startAngle: .radians(a0), delta: .radians(sweep * (t1 - t0)))
            }
        }
    }

    private var segments: [Segment] {
        let k = min(corner, width / 2, height / 2)
        let l = center.x - width / 2, r = center.x + width / 2
        let t = center.y - height / 2, b = center.y + height / 2
        let quarter = CGFloat.pi / 2
        return [
            .line(CGPoint(x: center.x, y: b), CGPoint(x: l + k, y: b)),
            .arc(center: CGPoint(x: l + k, y: b - k), radius: k, start: quarter, sweep: quarter),
            .line(CGPoint(x: l, y: b - k), CGPoint(x: l, y: t + k)),
            .arc(center: CGPoint(x: l + k, y: t + k), radius: k, start: 2 * quarter, sweep: quarter),
            .line(CGPoint(x: l + k, y: t), CGPoint(x: r - k, y: t)),
            .arc(center: CGPoint(x: r - k, y: t + k), radius: k, start: 3 * quarter, sweep: quarter),
            .line(CGPoint(x: r, y: t + k), CGPoint(x: r, y: b - k)),
            .arc(center: CGPoint(x: r - k, y: b - k), radius: k, start: 0, sweep: quarter),
            .line(CGPoint(x: r - k, y: b), CGPoint(x: center.x, y: b)),
        ].filter { $0.length > 0.0001 }
    }

    var perimeter: CGFloat { segments.reduce(0) { $0 + $1.length } }

    /// 截取周长比例 [from, to] 这一段。
    func path(from: CGFloat, to: CGFloat) -> Path {
        var path = Path()
        let segments = segments
        let total = segments.reduce(0) { $0 + $1.length }
        guard total > 0, to > from else { return path }
        let lo = max(from, 0) * total, hi = min(to, 1) * total
        var offset: CGFloat = 0
        var started = false
        for segment in segments {
            let length = segment.length
            defer { offset += length }
            let s0 = max(lo, offset), s1 = min(hi, offset + length)
            guard s1 > s0 else { continue }
            segment.append(to: &path, from: (s0 - offset) / length, to: (s1 - offset) / length,
                           startsSubpath: !started)
            started = true
        }
        if from <= 0 && to >= 1 { path.closeSubpath() }
        return path
    }

    /// 在 span 里去掉 gaps，返回剩下的若干段。
    static func subtract(_ gaps: [ClosedRange<CGFloat>], from span: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        var pieces = [span]
        for gap in gaps where gap.upperBound > gap.lowerBound {
            pieces = pieces.flatMap { piece -> [ClosedRange<CGFloat>] in
                guard gap.overlaps(piece) else { return [piece] }
                var out: [ClosedRange<CGFloat>] = []
                if gap.lowerBound > piece.lowerBound { out.append(piece.lowerBound...gap.lowerBound) }
                if gap.upperBound < piece.upperBound { out.append(gap.upperBound...piece.upperBound) }
                return out
            }
        }
        return pieces
    }

    /// 从 pieces 的开头量出 fraction（按长度占比）那么长的部分。
    static func leading(_ fraction: CGFloat, of pieces: [ClosedRange<CGFloat>]) -> [ClosedRange<CGFloat>] {
        let total = pieces.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
        var remaining = min(max(fraction, 0), 1) * total
        var out: [ClosedRange<CGFloat>] = []
        for piece in pieces where remaining > 0 {
            let length = piece.upperBound - piece.lowerBound
            let take = min(length, remaining)
            out.append(piece.lowerBound...(piece.lowerBound + take))
            remaining -= take
        }
        return out
    }
}

// MARK: - 各个部件

enum DuoParts {
    /// 电量圆环（或变形中的电池外框）。
    /// - Parameters:
    ///   - bottomGap / topGap: 开口的半宽，按周长比例计
    ///   - fillAlpha: 电量部分的透明度（变形成电池时逐渐淡出）
    ///   - fillTint: 电量部分的颜色，轨道不上色
    static func ring(loop: LoopShape, lineWidth: CGFloat, level: CGFloat,
                     bottomGap: CGFloat, topGap: CGFloat,
                     trackAlpha: CGFloat, fillAlpha: CGFloat, fillTint: DuoTint? = nil) -> [DuoMark] {
        let span: ClosedRange<CGFloat> = bottomGap...(1 - bottomGap)
        let gaps = topGap > 0 ? [(0.5 - topGap)...(0.5 + topGap)] : []
        let visible = LoopShape.subtract(gaps, from: span)
        var marks: [DuoMark] = []
        if trackAlpha > 0 {
            marks.append(.layer(alpha: trackAlpha, visible.map { .stroke(loop.path(from: $0.lowerBound, to: $0.upperBound), width: lineWidth) }))
        }
        if fillAlpha > 0 && level > 0 {
            let filled = LoopShape.leading(level, of: visible)
            let strokes: [DuoMark] = filled.map { .stroke(loop.path(from: $0.lowerBound, to: $0.upperBound), width: lineWidth) }
            marks.append(.layer(alpha: fillAlpha, DuoMark.withTint(fillTint, strokes)))
        }
        return marks
    }

    static func dot(at center: CGPoint, radius: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
    }

    /// 4 个圆点；空着的位置不画，亮的点可以带颜色。
    static func dots(center: CGPoint, radius R: CGFloat, style: DuoStyle, lights: [DotLight?]) -> [DuoMark] {
        zip(DuoSpec.dotDegrees, lights).flatMap { degrees, light -> [DuoMark] in
            guard let light else { return [] }
            let mark = DuoMark.fill(dot(at: polar(center, R, degrees), radius: style.dotRadius * R))
            return light.on ? DuoMark.withTint(light.tint, [mark]) : [.layer(alpha: style.dimAlpha, [mark])]
        }
    }

    static func circle(_ center: CGPoint, _ radius: CGFloat) -> LoopShape {
        LoopShape(center: center, width: 2 * radius, height: 2 * radius, corner: radius)
    }

    /// 底部放圆点时开口大，不放时收小。
    static func bottomGap(hasDots: Bool) -> CGFloat {
        hasDots ? DuoSpec.bottomGapFraction : DuoSpec.compactGapFraction
    }

    /// 某个状态画成圆环：电量带顶部电源符号的开口，没数据或静音时填充变暗。
    static func gauge(_ part: IconPart, loop: LoopShape, lineWidth: CGFloat, bottomGap: CGFloat,
                      style: DuoStyle) -> [DuoMark] {
        let showsPower = part.power != nil && part.power != .battery
        return ring(loop: loop, lineWidth: lineWidth, level: part.level,
                    bottomGap: bottomGap,
                    topGap: showsPower ? DuoSpec.topGapFraction : 0,
                    trackAlpha: style.dimAlpha,
                    fillAlpha: part.active ? 1 : style.dimAlpha + 0.2,
                    fillTint: part.tint)
    }

    /// 中间的内容：网络画图形，音量画喇叭，其他状态画数字。
    /// - Parameter roomy: 0...1。外圈不显示时为 1，中间内容可以放大，用满圆环内的空间。
    static func centerContent(_ part: IconPart, center: CGPoint, radius R: CGFloat, style: DuoStyle,
                              roomy: CGFloat = 0) -> [DuoMark] {
        if let glyph = part.glyph {
            return centerGlyph(glyph, center: center, radius: R * lerp(1, 1.35, roomy), style: style)
        }
        let alpha = part.active ? 1 : style.dimAlpha + 0.1
        if let symbol = part.symbol {
            let height = lerp(0.72, 1.0, roomy) * style.wifiScale * R
            let rect = CGRect(x: center.x - height, y: center.y - height / 2, width: height * 2, height: height)
            return [.layer(alpha: alpha, [.symbol(symbol, rect: rect, variable: part.active ? part.level : nil)])]
        }
        let width = lerp(DuoSpec.textWidth, 2.0, roomy) * R
        let height = lerp(DuoSpec.textHeight, 0.95, roomy) * R
        let box = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
        return [.layer(alpha: alpha, DuoMark.withTint(part.tint, [.fill(TextPath.path(part.compact, in: box))]))]
    }

    /// Wi-Fi 扇形（两条弧 + 底部楔形），以圆环中心为基准缩放。
    static func wifiFan(center: CGPoint, radius R: CGFloat, style: DuoStyle) -> [DuoMark] {
        let s = style.wifiScale
        let apex = CGPoint(x: center.x, y: center.y + DuoSpec.wifiApex * s * R)
        let half = DuoSpec.wifiHalfAngle
        var marks: [DuoMark] = DuoSpec.wifiArcs.map { arc in
            var path = Path()
            path.addRelativeArc(center: apex, radius: arc.radius * s * R,
                                startAngle: .degrees(270 - half), delta: .degrees(2 * half))
            return .stroke(path, width: arc.width * style.wifiWeight * R)
        }
        // 楔形：填充后再描一圈细边，把尖角磨圆。
        let rounding = 0.04 * R
        var wedge = Path()
        wedge.move(to: apex)
        wedge.addRelativeArc(center: apex, radius: DuoSpec.wifiWedge * s * R - rounding / 2,
                             startAngle: .degrees(270 - half), delta: .degrees(2 * half))
        wedge.closeSubpath()
        marks.append(.fill(wedge))
        marks.append(.stroke(wedge, width: rounding))
        return marks
    }

    static func centerGlyph(_ glyph: CenterGlyph, center: CGPoint, radius R: CGFloat, style: DuoStyle) -> [DuoMark] {
        switch glyph {
        case let .wifi(connected):
            return [.layer(alpha: connected ? 1 : style.dimAlpha, wifiFan(center: center, radius: R, style: style))]

        case .wifiOff:
            // 斜杠从左上到右下，先在扇形上擦出一道缝，再画斜杠。
            let s = style.wifiScale
            var slash = Path()
            slash.move(to: CGPoint(x: center.x - 0.36 * s * R, y: center.y - 0.36 * s * R))
            slash.addLine(to: CGPoint(x: center.x + 0.36 * s * R, y: center.y + 0.36 * s * R))
            let width = 0.13 * style.wifiWeight * R
            return [
                .layer(alpha: style.dimAlpha + 0.1,
                       wifiFan(center: center, radius: R, style: style) + [.knockout(slash, width: width * 2.6)]),
                .stroke(slash, width: width),
            ]

        case .ethernet:
            // “<···>” 形状，和系统网络设置里的以太网图标一致。
            let s = style.wifiScale * R
            let c = CGPoint(x: center.x, y: center.y + 0.02 * R)
            var chevrons = Path()
            chevrons.move(to: CGPoint(x: c.x - 0.27 * s, y: c.y - 0.25 * s))
            chevrons.addLine(to: CGPoint(x: c.x - 0.49 * s, y: c.y))
            chevrons.addLine(to: CGPoint(x: c.x - 0.27 * s, y: c.y + 0.25 * s))
            chevrons.move(to: CGPoint(x: c.x + 0.27 * s, y: c.y - 0.25 * s))
            chevrons.addLine(to: CGPoint(x: c.x + 0.49 * s, y: c.y))
            chevrons.addLine(to: CGPoint(x: c.x + 0.27 * s, y: c.y + 0.25 * s))
            var marks: [DuoMark] = [.stroke(chevrons, width: 0.13 * style.wifiWeight * R)]
            for x in [-0.15, 0, 0.15] as [CGFloat] {
                marks.append(.fill(dot(at: CGPoint(x: c.x + x * s, y: c.y), radius: 0.068 * style.wifiWeight * R)))
            }
            return marks

        case .hotspot:
            let height = 0.72 * style.wifiScale * R
            let rect = CGRect(x: center.x - height, y: center.y + 0.02 * R - height / 2, width: height * 2, height: height)
            return [.symbol("personalhotspot", rect: rect)]
        }
    }

    /// 充电时的闪电 / 接通电源但没在充电时的插头，位于圆环顶部开口处。
    static func powerSymbol(_ power: PowerState, center: CGPoint, radius R: CGFloat) -> [DuoMark] {
        let name: String
        switch power {
        case .battery: return []
        case .charging: name = "bolt.fill"
        case .pluggedIn: name = "powerplug.portrait.fill"
        }
        let height = DuoSpec.powerSymbolHeight * R
        let mid = CGPoint(x: center.x, y: center.y + DuoSpec.powerSymbolOffset * R)
        return [.symbol(name, rect: CGRect(x: mid.x - height, y: mid.y - height / 2, width: height * 2, height: height))]
    }

    /// 参考 iPhone Duo 的样式，把电量数字嵌入圆环顶部。
    static func topPercent(_ percent: Int, progress rawProgress: CGFloat,
                           center: CGPoint, radius R: CGFloat) -> [DuoMark] {
        let progress = min(max(rawProgress, 0), 1)
        let alpha = smoothstep(0.12, 0.82, progress)
        guard alpha > 0 else { return [] }
        let text = String(percent)
        let scale = lerp(0.82, 1, progress)
        let width = (0.4 * CGFloat(text.count) + 0.2) * R * scale
        let height = 0.62 * R * scale
        let y = center.y + lerp(-0.70, -0.92, progress) * R
        let box = CGRect(x: center.x - width / 2, y: y - height / 2, width: width, height: height)
        return [.layer(alpha: alpha, [.fill(TextPath.path(text, in: box))])]
    }

    /// 完整的三合一图标。
    static func combined(_ state: IconState, center: CGPoint, radius R: CGFloat, style: DuoStyle,
                         embeddedPercent: Int? = nil, embeddedPercentProgress rawProgress: CGFloat = 0) -> [DuoMark] {
        let progress = embeddedPercent == nil ? 0 : min(max(rawProgress, 0), 1)
        var marks: [DuoMark] = []
        if let ring = state.ring {
            let powerGap = ring.power != nil && ring.power != .battery ? DuoSpec.topGapFraction : 0
            let percentGap = embeddedPercent.map(DuoSpec.percentTopGapFraction) ?? powerGap
            let topGap = lerp(powerGap, percentGap, progress)
            marks += DuoParts.ring(loop: circle(center, R), lineWidth: style.ringWidth * R, level: ring.level,
                                   bottomGap: bottomGap(hasDots: state.dots != nil), topGap: topGap,
                                   trackAlpha: style.dimAlpha,
                                   fillAlpha: ring.active ? 1 : style.dimAlpha + 0.2,
                                   fillTint: ring.tint)
            if let power = ring.power {
                marks += [.layer(alpha: 1 - progress,
                                 DuoMark.withTint(ring.tint, powerSymbol(power, center: center, radius: R)))]
            }
        }
        if let part = state.center {
            marks += centerContent(part, center: center, radius: R, style: style, roomy: state.ring == nil ? 1 : 0)
        }
        if let part = state.dots {
            marks += dots(center: center, radius: R, style: style, lights: part.lights)
        }
        if let embeddedPercent, state.ring != nil {
            marks += topPercent(embeddedPercent, progress: progress, center: center, radius: R)
        }
        return marks
    }

    /// 设置窗口里的位置示意图：高亮一个位置，其余变淡。
    static func diagram(highlight: Slot, center: CGPoint, radius R: CGFloat, style: DuoStyle) -> [DuoMark] {
        let ringMarks = ring(loop: circle(center, R), lineWidth: style.ringWidth * R, level: 0.7,
                             bottomGap: DuoSpec.bottomGapFraction, topGap: 0, trackAlpha: 0.35, fillAlpha: 1)
        let parts: [(Slot, [DuoMark])] = [
            (.ring, ringMarks),
            (.center, centerGlyph(.wifi(connected: true), center: center, radius: R, style: style)),
            (.dots, dots(center: center, radius: R, style: style,
                         lights: Array(repeating: DotLight(on: true), count: IconLayout.dotCount))),
        ]
        return parts.map { slot, marks in .layer(alpha: slot == highlight ? 1 : 0.18, marks) }
    }
}

// MARK: - SF Symbols

enum SymbolCache {
    static func image(_ name: String, height: CGFloat, variable: Double? = nil) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: height, weight: .semibold)
        let image = if let variable {
            NSImage(systemSymbolName: name, variableValue: variable, accessibilityDescription: nil)
        } else {
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
        }
        return image?.withSymbolConfiguration(config)
    }

    /// 按符号的宽高比，把它放进 rect 里居中。
    static func fitted(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let w = size.width * scale, h = size.height * scale
        return CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
    }
}
