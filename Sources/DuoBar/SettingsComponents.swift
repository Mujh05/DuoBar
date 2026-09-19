import AppKit
import SwiftUI

// 设置窗口里共用的小部件。页面本身和系统设置一样用分组表单（Form + .grouped），这里只放表单里没有的东西。

/// 彩色圆角方块里的白色图形。侧边栏的页面图标（PageIcon）也用它当底座。
struct IconBadge<Glyph: View>: View {
    let color: Color
    var size: CGFloat
    var dimmed: Bool
    let glyph: Glyph

    init(color: Color, size: CGFloat = 26, dimmed: Bool = false, @ViewBuilder glyph: () -> Glyph) {
        self.color = color
        self.size = size
        self.dimmed = dimmed
        self.glyph = glyph()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        glyph
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background {
                shape.fill(dimmed ? AnyShapeStyle(Color.secondary.opacity(0.35)) : AnyShapeStyle(color))
                // 顶部略亮、底部略暗的光泽。
                shape.fill(LinearGradient(colors: [.white.opacity(0.16), .clear, .black.opacity(0.08)],
                                          startPoint: .top, endPoint: .bottom))
            }
            .shadow(color: .black.opacity(0.15), radius: size * 0.03, y: size * 0.02)
    }
}

extension IconBadge where Glyph == Image {
    init(symbol: String, color: Color, size: CGFloat = 26, dimmed: Bool = false) {
        self.init(color: color, size: size, dimmed: dimmed) { Image(systemName: symbol) }
    }
}

/// 指示灯的彩色底座：亮起时用自己的颜色，关闭时变灰，状态变化时图标跳一下。
struct IndicatorBadge: View {
    let kind: IndicatorKind
    let on: Bool
    var size: CGFloat = 30

    var body: some View {
        IconBadge(color: kind.tint?.color ?? .gray, size: size, dimmed: !on) {
            IndicatorIcon(kind: kind, size: size * 0.55)
        }
        .symbolEffect(.bounce, value: on)
        .animation(.easeInOut(duration: 0.25), value: on)
    }
}

/// 自己排版的一行里的标题，下面是小一号的灰色说明，和表单里带说明的行一样。
struct RowLabel: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// 分组下面的说明，和系统设置一样是靠左的灰色小字，右边可以放一个按钮。
struct SectionNote<Accessory: View>: View {
    let text: String
    let accessory: Accessory

    init(_ text: String, @ViewBuilder accessory: () -> Accessory) {
        self.text = text
        self.accessory = accessory()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            accessory
        }
        // 和分组的标题、行里的文字对齐。
        .padding(.leading, 10)
    }
}

extension SectionNote where Accessory == EmptyView {
    init(_ text: String) {
        self.init(text) { EmptyView() }
    }
}

/// 一行右边的下拉菜单：按钮上写着现在放在哪里，菜单里选“显示在…”。
struct PlacementMenu<Items: View>: View {
    let places: [String]
    @ViewBuilder let items: () -> Items

    var body: some View {
        Menu(places.isEmpty ? "未使用" : places.joined(separator: "、"), content: items)
            .fixedSize()
            // 留出固定的宽度，各行左边的数值才能对齐。
            .frame(minWidth: 96, alignment: .trailing)
    }
}

/// 模拟一段菜单栏：搜索、DuoBar、控制中心、时间，看图标在菜单栏里的实际效果。
struct MenuBarMock: View {
    let state: IconState
    var scale: CGFloat = 1
    var percentTitle: String?
    var embeddedPercent: Int?
    var embeddedProgress: CGFloat = 0
    let dark: Bool

    var body: some View {
        let metrics = MenuBarIcon.metrics(scale: scale)
        let ink: Color = dark ? .white : .black.opacity(0.85)
        HStack(spacing: 11) {
            Image(systemName: "magnifyingglass")
            HStack(spacing: 3) {
                if let percentTitle {
                    Text(percentTitle)
                        .monospacedDigit()
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                }
                Canvas { context, size in
                    let offset = metrics.center.y - metrics.size.height / 2
                    let center = CGPoint(x: size.width / 2, y: size.height / 2 + offset)
                    context.draw(DuoParts.combined(state, center: center, radius: metrics.radius, style: metrics.style,
                                                   embeddedPercent: embeddedPercent,
                                                   embeddedPercentProgress: embeddedProgress),
                                 color: ink)
                }
                .frame(width: metrics.size.width, height: metrics.size.height)
            }
            Image(systemName: "switch.2")
            Text("9:41")
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(ink)
        .padding(.horizontal, 12)
        .frame(height: max(28, metrics.size.height + 6))
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(dark ? Color(white: 0.13) : Color(white: 0.93))
        )
        // 让系统颜色按这条菜单栏的深浅取值。
        .environment(\.colorScheme, dark ? .dark : .light)
    }
}

/// 设置里每一行左边的小图：高亮这一行对应的位置。
struct SlotDiagram: View {
    let slot: Slot

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2.35
            context.draw(DuoParts.diagram(highlight: slot, center: center, radius: radius, style: .menuBar),
                         color: .primary)
        }
    }
}

/// 4 个圆点里高亮第 index 个，排成和图标底部一样的弧形。
struct DotDiagram: View {
    let index: Int

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0 ..< IconLayout.dotCount, id: \.self) { i in
                Circle()
                    .fill(Color.primary.opacity(i == index ? 1 : 0.2))
                    .frame(width: 4.5, height: 4.5)
                    .offset(y: i == 0 || i == IconLayout.dotCount - 1 ? -1.5 : 1.5)
            }
        }
    }
}

/// 某个圆点显示哪个指示灯，“图标”页和“指示灯”页共用。
/// 可以把“指示灯”页列表里的指示灯拖进来，圆点之间也可以互相拖动交换。
struct IndicatorDotRow: View {
    let model: AppModel
    let index: Int
    @Binding var dropTarget: String?

    var body: some View {
        let current = model.layout.indicators[index]
        Picker(selection: Binding(
            get: { current },
            set: { kind in
                withAnimation(.snappy) {
                    if let kind {
                        model.showIndicator(kind, atDot: index)
                    } else {
                        model.setIndicator(nil, atDot: index)
                    }
                }
            }
        )) {
            Text("空着").tag(IndicatorKind?.none)
            Divider()
            ForEach(IndicatorKind.allCases) { kind in
                if let symbol = kind.symbol {
                    Label(kind.title, systemImage: symbol).tag(IndicatorKind?.some(kind))
                } else {
                    Text(kind.title).tag(IndicatorKind?.some(kind))
                }
            }
        } label: {
            HStack(spacing: 10) {
                DotDiagram(index: index)
                    .frame(width: 26, height: 16)
                Text("圆点 \(index + 1)")
                if let current {
                    IndicatorBadge(kind: current, on: model.indicatorStates[current] == true, size: 18)
                }
            }
        }
        .dragRow(id: "dot:\(index)", target: $dropTarget, preview: current?.title ?? "空着") { source in
            if source.hasPrefix("dot:"), let from = Int(source.dropFirst(4)), from != index {
                withAnimation(.snappy) { model.swapIndicators(from, index) }
                return true
            }
            if source.hasPrefix("indicator:"), let kind = IndicatorKind(rawValue: String(source.dropFirst(10))) {
                withAnimation(.snappy) { model.showIndicator(kind, atDot: index) }
                return true
            }
            return false
        }
    }
}

extension MetricKind {
    /// 设置里图标用的颜色。
    var color: Color {
        switch self {
        case .battery: .green
        case .network: .blue
        case .cpu: .orange
        case .gpu: .purple
        case .memory: .pink
        case .disk: .gray
        case .throughput: .teal
        case .volume: .red
        case .accessory: .indigo
        }
    }
}

// MARK: - 拖动

extension View {
    /// 这一行可以拖动，拖动时带着 "duobar-" + id；别的行拖到这一行上时整行高亮，
    /// 松手后 onDrop 收到被拖动那一行的 id。
    func dragRow(id: String, target: Binding<String?>, preview: String,
                 onDrop: @escaping (String) -> Bool) -> some View {
        let prefix = "duobar-"
        return contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(target.wrappedValue == id ? Color.accentColor.opacity(0.18) : .clear)
                    .padding(-5)
            )
            .draggable(prefix + id) {
                Text(preview)
                    .padding(8)
            }
            .dropDestination(for: String.self) { items, _ in
                guard let item = items.first, item.hasPrefix(prefix) else { return false }
                return onDrop(String(item.dropFirst(prefix.count)))
            } isTargeted: { targeted in
                withAnimation(.easeOut(duration: 0.15)) {
                    if targeted {
                        target.wrappedValue = id
                    } else if target.wrappedValue == id {
                        target.wrappedValue = nil
                    }
                }
            }
    }
}
