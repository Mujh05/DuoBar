import AppKit
import SwiftUI

// 设置窗口里共用的小部件。

/// 圆角卡片，标题右边可以放一个按钮之类的附件。
struct SettingsCard<Trailing: View, Content: View>: View {
    let title: String?
    let subtitle: String?
    let trailing: Trailing
    let content: Content

    init(_ title: String? = nil, subtitle: String? = nil,
         @ViewBuilder trailing: () -> Trailing,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if title != nil || subtitle != nil {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        if let title {
                            Text(title)
                                .font(.system(size: 13, weight: .semibold))
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 12)
                    trailing
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07))
        )
    }
}

extension SettingsCard where Trailing == EmptyView {
    init(_ title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// 系统设置风格的彩色图标底座。
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
        glyph
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(dimmed ? AnyShapeStyle(Color.secondary.opacity(0.35)) : AnyShapeStyle(color.gradient))
            )
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
            IndicatorIcon(kind: kind, size: size * 0.5)
        }
        .symbolEffect(.bounce, value: on)
        .animation(.easeInOut(duration: 0.25), value: on)
    }
}

/// 悬停时轻轻浮起。
struct HoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .scaleEffect(hovering && !reduceMotion ? 1.015 : 1)
            .shadow(color: .black.opacity(hovering ? 0.12 : 0), radius: hovering ? 8 : 0, y: hovering ? 3 : 0)
            .animation(.spring(duration: 0.25), value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift() -> some View {
        modifier(HoverLift())
    }
}

/// 左边标题说明、右边开关的一行。
struct SettingToggle: View {
    let title: String
    var detail: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingRow(title: title, detail: detail) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

/// 左边标题说明、右边任意控件的一行。
struct SettingRow<Control: View>: View {
    let title: String
    var detail: String?
    let control: Control

    init(title: String, detail: String? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            control
        }
    }
}

/// 小胶囊标签，比如“外圈圆环”“圆点 2”。
struct Badge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.accentColor.opacity(0.14)))
    }
}

/// 小圆环，数值变化时平滑过渡。
struct MiniGauge: View {
    let level: Double
    let active: Bool
    let color: Color
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), lineWidth: 3.5)
            Circle()
                .trim(from: 0, to: max(0.001, min(level, 1)))
                .stroke(active ? color : Color.secondary.opacity(0.5),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: size, height: size)
        .animation(.spring(duration: 0.6), value: level)
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

extension MetricKind {
    /// 设置里卡片用的颜色。
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

extension SlotContent {
    var color: Color {
        metric?.color ?? .orange
    }
}

// MARK: - 拖动交换

extension View {
    /// 整行可以拖到另一行上；onDrop 收到被拖动那一行的 id。
    func dragRow(id: String, target: Binding<String?>, preview: String,
                 onDrop: @escaping (String) -> Bool) -> some View {
        let prefix = "duobar-"
        return contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(target.wrappedValue == id ? Color.accentColor.opacity(0.18) : .clear)
                    .padding(-2)
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
