import SwiftUI

/// 面板胶囊里圆形图标上的图案：三合一图标的一部分（外圈、中间或底部圆点）。
///
/// 打开面板时几个胶囊叠在同一个位置，三部分拼成完整的三合一图标（progress = 0）；
/// 胶囊滑开的同时各部分变成自己单独的样子（progress = 1）：
/// 电量的圆环变成电池，其他外圈状态变成小圆环，中间内容不变，圆点排成 2×2（指示灯）或信号格（档位）。
struct DuoPartGlyph: View {
    var slot: Slot
    var state: IconState
    var progress: CGFloat
    /// 普通部分的颜色。
    var color: Color
    /// 画在白色圆底上：带颜色的部分取浅色外观下的固定颜色，否则在深色模式下会被冲淡。
    var onWhite: Bool

    var body: some View {
        Canvas { context, size in
            let layout = TilePartLayout(state: state, center: CGPoint(x: size.width / 2, y: size.height / 2))
            context.draw(layout.marks(slot, at: progress), color: color,
                         tint: onWhite ? { Color.fixedLight($0.color) } : { $0.color })
        }
        .accessibilityHidden(true)
    }
}

/// 各部分从合体到拆开的形状，尺寸按 36 点的圆形图标设计。
struct TilePartLayout {
    var state: IconState
    var center: CGPoint
    var style = DuoStyle.reference

    /// 合体时三合一图标的圆环半径，整个图标刚好放进圆形图标里。
    static let comboRadius: CGFloat = 11
    static let batteryBody = CGSize(width: 20, height: 11)
    static let batteryCorner: CGFloat = 3.2
    static let batteryLine: CGFloat = 1.5
    static let gaugeRadius: CGFloat = 9
    static let centerRadius: CGFloat = 15
    /// 2×2 圆点离中心的距离和半径。
    static let gridStep: CGFloat = 4.6
    static let gridDot: CGFloat = 3.1
    static let barWidth: CGFloat = 3
    static let barGap: CGFloat = 2
    static let barHeights: [CGFloat] = [5, 8, 11, 14]

    func marks(_ slot: Slot, at p: CGFloat) -> [DuoMark] {
        let q = min(max(p, 0), 1)
        switch slot {
        case .ring:
            guard let ring = state.ring else { return [] }
            return ring.kind == .battery ? battery(ring, p, q) : gauge(ring, p, q)
        case .center:
            guard let part = state.center else { return [] }
            return DuoParts.centerContent(part, center: center, radius: lerp(Self.comboRadius, Self.centerRadius, p),
                                          style: style, roomy: state.ring == nil ? 1 - q : 0)
        case .dots:
            guard let dots = state.dots else { return [] }
            return dots.isIndicators ? grid(dots, p) : bars(dots, p)
        }
    }

    private var startGap: CGFloat { DuoParts.bottomGap(hasDots: state.dots != nil) }

    private func dotStart(_ index: Int) -> CGPoint {
        polar(center, Self.comboRadius, DuoSpec.dotDegrees[index])
    }

    private var dotStartRadius: CGFloat { style.dotRadius * Self.comboRadius }

    // MARK: 圆环 → 电池

    private func battery(_ part: IconPart, _ p: CGFloat, _ q: CGFloat) -> [DuoMark] {
        let R0 = Self.comboRadius
        let body = Self.batteryBody
        // 右边留出正极的位置，电池整体往左一点。
        let loop = LoopShape(
            center: CGPoint(x: center.x - 1.2 * q, y: center.y),
            width: max(lerp(2 * R0, body.width, p), 1),
            height: max(lerp(2 * R0, body.height, p), 1),
            corner: max(lerp(R0, Self.batteryCorner, p), 0.5)
        )
        let lineWidth = max(lerp(style.ringWidth * R0, Self.batteryLine, p), 0.5)
        let showsPower = part.power != nil && part.power != .battery

        var marks = DuoParts.ring(
            loop: loop, lineWidth: lineWidth, level: part.level,
            bottomGap: max(startGap * (1 - p), 0),
            topGap: showsPower ? max(DuoSpec.topGapFraction * (1 - p), 0) : 0,
            trackAlpha: lerp(style.dimAlpha, 0.55, q),
            fillAlpha: 1 - smoothstep(0.15, 0.6, q),
            fillTint: part.tint
        )

        // 圆环顶部的电源符号淡出，拆开后换成电池里的闪电。
        let powerAlpha = 1 - smoothstep(0, 0.35, q)
        if showsPower, powerAlpha > 0, let power = part.power {
            let symbol = DuoParts.powerSymbol(power, center: loop.center, radius: max(lerp(R0, body.height / 2, p), 1))
            marks.append(.layer(alpha: powerAlpha, DuoMark.withTint(part.tint, symbol)))
        }

        // 电池里的电量条和右边的正极。
        let innerAlpha = smoothstep(0.6, 1, q)
        guard innerAlpha > 0 else { return marks }
        let frame = CGRect(x: loop.center.x - loop.width / 2, y: loop.center.y - loop.height / 2,
                           width: loop.width, height: loop.height)
        let inset = lineWidth / 2 + 1.1
        let full = frame.insetBy(dx: inset, dy: inset)
        let fill = CGRect(x: full.minX, y: full.minY, width: full.width * part.level, height: full.height)
        var inner: [DuoMark] = []
        if fill.width > 0.3, fill.height > 0.3 {
            let corner = min(max(loop.corner - inset, 0.6), fill.width / 2, fill.height / 2)
            inner += DuoMark.withTint(part.tint, [.fill(Path(roundedRect: fill, cornerRadius: corner))])
        }
        if part.power == .charging {
            // 闪电四周先擦出一圈空隙，电量多少都看得清。
            let bolt = CGRect(x: loop.center.x - 5, y: loop.center.y - 4.6, width: 10, height: 9.2)
            inner.append(.knockoutSymbol("bolt.fill", rect: bolt.insetBy(dx: -1.2, dy: -1.2)))
            inner.append(.symbol("bolt.fill", rect: bolt))
        }
        marks.append(.layer(alpha: innerAlpha, inner))
        let nub = CGRect(x: frame.maxX + lineWidth / 2 + 0.7, y: loop.center.y - 2, width: 1.5, height: 4)
        marks.append(.layer(alpha: innerAlpha * 0.6, [.fill(Path(roundedRect: nub, cornerRadius: 0.75))]))
        return marks
    }

    // MARK: 圆环 → 小圆环 + 符号

    private func gauge(_ part: IconPart, _ p: CGFloat, _ q: CGFloat) -> [DuoMark] {
        let radius = max(lerp(Self.comboRadius, Self.gaugeRadius, p), 1)
        var marks = DuoParts.gauge(part, loop: DuoParts.circle(center, radius),
                                   lineWidth: style.ringWidth * radius * lerp(1, 1.3, q),
                                   bottomGap: max(lerp(startGap, DuoSpec.compactGapFraction, p), 0), style: style)
        let symbolAlpha = smoothstep(0.5, 1, q)
        if symbolAlpha > 0 {
            let height = radius * 0.85
            let rect = CGRect(x: center.x - height, y: center.y - height / 2, width: height * 2, height: height)
            marks.append(.layer(alpha: symbolAlpha * (part.active ? 1 : 0.5), [.symbol(part.kind.symbol, rect: rect)]))
        }
        return marks
    }

    // MARK: 圆点 → 2×2

    /// 左边两个点去左列，右边两个去右列，移动路线不交叉。
    private static let gridOffsets: [CGPoint] = [
        CGPoint(x: -1, y: -1), CGPoint(x: -1, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: -1),
    ]

    private func grid(_ dots: DotsPart, _ p: CGFloat) -> [DuoMark] {
        dots.lights.prefix(4).enumerated().flatMap { index, light -> [DuoMark] in
            guard let light else { return [] }
            let offset = Self.gridOffsets[index]
            let end = CGPoint(x: center.x + offset.x * Self.gridStep, y: center.y + offset.y * Self.gridStep)
            let radius = max(lerp(dotStartRadius, Self.gridDot, p), 0.3)
            let mark = DuoMark.fill(DuoParts.dot(at: lerp(dotStart(index), end, p), radius: radius))
            return light.on ? DuoMark.withTint(light.tint, [mark]) : [.layer(alpha: style.dimAlpha + 0.1, [mark])]
        }
    }

    // MARK: 圆点 → 信号格

    private func bars(_ dots: DotsPart, _ p: CGFloat) -> [DuoMark] {
        let total = 4 * Self.barWidth + 3 * Self.barGap
        let baseline = center.y + Self.barHeights.last! / 2
        return dots.lights.prefix(4).enumerated().flatMap { index, light -> [DuoMark] in
            guard let light else { return [] }
            let height = Self.barHeights[index]
            let end = CGPoint(x: center.x - total / 2 + Self.barWidth / 2 + CGFloat(index) * (Self.barWidth + Self.barGap),
                              y: baseline - height / 2)
            let position = lerp(dotStart(index), end, p)
            let width = max(lerp(2 * dotStartRadius, Self.barWidth, p), 0.3)
            let barHeight = max(lerp(2 * dotStartRadius, height, p), 0.3)
            let rect = CGRect(x: position.x - width / 2, y: position.y - barHeight / 2, width: width, height: barHeight)
            let bar = DuoMark.fill(Path(roundedRect: rect, cornerRadius: min(width, barHeight) / 2))
            return light.on ? DuoMark.withTint(light.tint, [bar]) : [.layer(alpha: style.dimAlpha, [bar])]
        }
    }
}
