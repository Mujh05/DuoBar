import SwiftUI

/// 面板顶部的动画：三合一图标拆成左、中、右三个独立图标。
/// progress = 0 是合体，1 是拆开；弹簧动画会让它略微超过 1。
struct SplitGlyphView: View, Animatable {
    var progress: CGFloat
    var state: IconState

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        Canvas { context, size in
            context.draw(SplitLayout(size: size, state: state).marks(at: progress), color: .primary)
        }
        .accessibilityHidden(true)
    }
}

/// 拆开后：底部圆点 → 左边（信号格，或一排指示灯图标），中间内容 → 中间，
/// 外圈 → 右边（电量变成电池，其他变成小圆环）。
struct SplitLayout {
    var size: CGSize
    var state: IconState
    var style = DuoStyle.reference

    /// 左、中、右三等分的中点。
    func slotX(_ index: Int) -> CGFloat { size.width * CGFloat(2 * index + 1) / 6 }

    var mid: CGFloat { size.height / 2 }
    var comboCenter: CGPoint { CGPoint(x: size.width / 2, y: mid) }
    var comboRadius: CGFloat { size.height / 2.5 }

    static let batteryBody = CGSize(width: 40, height: 20)
    static let batteryCorner: CGFloat = 6
    static let batteryLine: CGFloat = 1.7
    static let gaugeRadius: CGFloat = 15
    static let barWidth: CGFloat = 5
    static let barGap: CGFloat = 3.5
    static let barHeights: [CGFloat] = [7, 11, 15, 19]
    static let lightSize: CGFloat = 20
    static let lightGap: CGFloat = 3
    /// 拆开后中间内容对应的“圆环半径”，决定它的大小。
    static let centerRadius: CGFloat = 26

    func marks(at p: CGFloat) -> [DuoMark] {
        let q = min(max(p, 0), 1)
        var marks: [DuoMark] = []
        if let ring = state.ring {
            marks += ring.kind == .battery ? battery(ring, p, q) : gauge(ring, p, q)
        }
        if let center = state.center {
            let radius = lerp(comboRadius, Self.centerRadius, p)
            let position = lerp(comboCenter, CGPoint(x: slotX(1), y: mid), p)
            marks += DuoParts.centerContent(center, center: position, radius: radius, style: style,
                                            roomy: state.ring == nil ? 1 - q : 0)
        }
        if let dots = state.dots {
            marks += dots.isIndicators ? lights(dots, p, q) : bars(dots, p)
        }
        return marks
    }

    private var startGap: CGFloat { DuoParts.bottomGap(hasDots: state.dots != nil) }

    private func dotStart(_ index: Int) -> CGPoint {
        polar(comboCenter, comboRadius, DuoSpec.dotDegrees[index])
    }

    private var dotStartSize: CGFloat { 2 * style.dotRadius * comboRadius }

    // MARK: 圆环 → 电池

    private func battery(_ part: IconPart, _ p: CGFloat, _ q: CGFloat) -> [DuoMark] {
        let R0 = comboRadius
        let body = Self.batteryBody
        let target = CGPoint(x: slotX(2) - 2, y: mid)
        let loop = LoopShape(
            center: lerp(comboCenter, target, p),
            width: max(lerp(2 * R0, body.width, p), 1),
            height: max(lerp(2 * R0, body.height, p), 1),
            corner: max(lerp(R0, Self.batteryCorner, p), 0.5)
        )
        let lineWidth = max(lerp(style.ringWidth * R0, Self.batteryLine, p), 0.5)
        let showsPower = part.power != nil && part.power != .battery
        let outlineAlpha: CGFloat = 0.45

        var marks = DuoParts.ring(
            loop: loop, lineWidth: lineWidth, level: part.level,
            bottomGap: max(startGap * (1 - p), 0),
            topGap: showsPower ? max(DuoSpec.topGapFraction * (1 - p), 0) : 0,
            trackAlpha: lerp(style.dimAlpha, outlineAlpha, q),
            fillAlpha: 1 - smoothstep(0.15, 0.6, q),
            fillTint: part.tint
        )

        // 电源符号跟着圆环顶部走，同时淡出（拆开后由文字说明充电状态）。
        let powerAlpha = 1 - smoothstep(0, 0.35, q)
        if showsPower, powerAlpha > 0, let power = part.power {
            let radius = max(lerp(R0, body.height / 2, p), 1)
            let symbol = DuoParts.powerSymbol(power, center: loop.center, radius: radius)
            marks.append(.layer(alpha: powerAlpha, DuoMark.withTint(part.tint, symbol)))
        }

        // 电池里的电量条和右侧正极。
        let innerAlpha = smoothstep(0.7, 1, q)
        if innerAlpha > 0 {
            let inset = lineWidth / 2 + 1.5
            let frame = CGRect(x: loop.center.x - loop.width / 2, y: loop.center.y - loop.height / 2,
                               width: loop.width, height: loop.height)
            let full = frame.insetBy(dx: inset, dy: inset)
            let fill = CGRect(x: full.minX, y: full.minY, width: full.width * part.level, height: full.height)
            if fill.width > 0.5, fill.height > 0.5 {
                let corner = min(max(loop.corner - inset, 1), fill.width / 2, fill.height / 2)
                let bar = DuoMark.fill(Path(roundedRect: fill, cornerRadius: corner))
                marks.append(.layer(alpha: innerAlpha, DuoMark.withTint(part.tint, [bar])))
            }
            let nub = CGRect(x: frame.maxX + lineWidth / 2 + 1.2, y: loop.center.y - 3.5, width: 2.2, height: 7)
            marks.append(.layer(alpha: innerAlpha * outlineAlpha, [.fill(Path(roundedRect: nub, cornerRadius: 1.1))]))
        }
        return marks
    }

    // MARK: 圆环 → 小圆环 + 符号

    private func gauge(_ part: IconPart, _ p: CGFloat, _ q: CGFloat) -> [DuoMark] {
        let radius = max(lerp(comboRadius, Self.gaugeRadius, p), 1)
        let center = lerp(comboCenter, CGPoint(x: slotX(2), y: mid), p)
        var marks = DuoParts.gauge(
            part, loop: DuoParts.circle(center, radius), lineWidth: style.ringWidth * radius,
            bottomGap: max(lerp(startGap, DuoSpec.compactGapFraction, p), 0), style: style
        )
        let symbolAlpha = smoothstep(0.5, 1, q)
        if symbolAlpha > 0 {
            let height = radius * 0.8
            let rect = CGRect(x: center.x - height, y: center.y - height / 2, width: height * 2, height: height)
            marks.append(.layer(alpha: symbolAlpha * (part.active ? 1 : 0.5), [.symbol(part.kind.symbol, rect: rect)]))
        }
        return marks
    }

    // MARK: 圆点 → 信号格

    private func bars(_ dots: DotsPart, _ p: CGFloat) -> [DuoMark] {
        let totalWidth = 4 * Self.barWidth + 3 * Self.barGap
        let baseline = mid + Self.barHeights.last! / 2
        return dots.lights.enumerated().flatMap { i, light -> [DuoMark] in
            guard let light else { return [] }
            let height = Self.barHeights[i]
            let end = CGPoint(x: slotX(0) - totalWidth / 2 + Self.barWidth / 2 + CGFloat(i) * (Self.barWidth + Self.barGap),
                              y: baseline - height / 2)
            let position = lerp(dotStart(i), end, p)
            let w = max(lerp(dotStartSize, Self.barWidth, p), 0.5)
            let h = max(lerp(dotStartSize, height, p), 0.5)
            let rect = CGRect(x: position.x - w / 2, y: position.y - h / 2, width: w, height: h)
            let bar = DuoMark.fill(Path(roundedRect: rect, cornerRadius: min(w, h) / 2))
            return light.on ? DuoMark.withTint(light.tint, [bar]) : [.layer(alpha: style.dimAlpha, [bar])]
        }
    }

    // MARK: 圆点 → 一排指示灯

    /// 每个点放大成圆形徽章，图标从中间镂空长出来。
    private func lights(_ dots: DotsPart, _ p: CGFloat, _ q: CGFloat) -> [DuoMark] {
        let step = Self.lightSize + Self.lightGap
        let firstX = slotX(0) - step * CGFloat(IconLayout.dotCount - 1) / 2
        let glyphScale = smoothstep(0.55, 1, q)
        return dots.lights.enumerated().compactMap { i, light -> DuoMark? in
            guard let light else { return nil }
            let end = CGPoint(x: firstX + CGFloat(i) * step, y: mid)
            let position = lerp(dotStart(i), end, p)
            let size = max(lerp(dotStartSize, Self.lightSize, p), 0.5)
            var marks: [DuoMark] = [.fill(DuoParts.dot(at: position, radius: size / 2))]
            if glyphScale > 0, let kind = light.indicator {
                let height = size * 0.52 * glyphScale
                let rect = CGRect(x: position.x - height, y: position.y - height / 2, width: height * 2, height: height)
                marks.append(Glyphs.indicatorKnockout(kind, in: rect))
            }
            let content = light.on ? DuoMark.withTint(light.tint, marks) : marks
            return .layer(alpha: light.on ? 1 : style.dimAlpha + 0.1, content)
        }
    }
}
