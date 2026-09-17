import SwiftUI

// MARK: - 状态

/// “状态”页：9 种状态做成卡片，带实时数值和小圆环。
struct MetricsSettingsPage: View {
    let model: AppModel
    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("点卡片右上角的按钮，或者右键卡片，可以把它放到某个位置。正在使用的卡片带蓝色边框。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(MetricKind.allCases) { kind in
                    MetricCard(kind: kind, model: model)
                }
            }
        }
    }
}

private struct MetricCard: View {
    let kind: MetricKind
    let model: AppModel

    var body: some View {
        let reading = model.reading(kind)
        let slots = model.layout.slots(showing: kind)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                IconBadge(symbol: kind.symbol, color: kind.color, size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(slots.isEmpty ? "未使用" : slots.map(\.title).joined(separator: "、"))
                        .font(.system(size: 11))
                        .foregroundStyle(slots.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                }
                Spacer(minLength: 4)
                placeMenu
            }
            HStack(alignment: .center) {
                Text(reading.value)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: reading.value)
                Spacer(minLength: 8)
                MiniGauge(level: reading.level, active: reading.active, color: kind.color)
            }
            Text(kind.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(slots.isEmpty ? Color.primary.opacity(0.07) : Color.accentColor.opacity(0.8),
                              lineWidth: slots.isEmpty ? 1 : 1.5)
        )
        .animation(.easeInOut(duration: 0.25), value: slots)
        .hoverLift()
        .contextMenu { placeButtons }
    }

    private var placeMenu: some View {
        Menu {
            placeButtons
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 15))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("放到某个位置")
    }

    @ViewBuilder
    private var placeButtons: some View {
        ForEach(Slot.allCases) { slot in
            Button("显示在\(slot.title)") {
                withAnimation(.snappy) { model.setContent(.metric(kind), for: slot) }
            }
        }
    }
}

// MARK: - 指示灯

/// “指示灯”页：上面是 4 个圆点的卡槽，下面是全部指示灯，可以拖进卡槽。
struct IndicatorsSettingsPage: View {
    @Bindable var model: AppModel
    @State private var dropTarget: Int?
    @State private var choosingDot: Int?
    private let columns = [GridItem(.adaptive(minimum: 180), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !model.layout.usesIndicators {
                modeBanner
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.96))))
            }
            SettingsCard("四个圆点", subtitle: "把下面的指示灯拖到圆点上，或者点圆点选择。圆点之间也可以互相拖动交换。") {
                HStack(spacing: 10) {
                    ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
                        dotSlot(index)
                    }
                }
            }
            .opacity(model.layout.usesIndicators ? 1 : 0.55)
            SettingsCard("全部指示灯", subtitle: "亮起时用各自的颜色，关闭时变暗。鼠标停在上面可以看到说明。") {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(IndicatorKind.allCases) { kind in
                        IndicatorTile(kind: kind, model: model)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.3), value: model.layout)
    }

    private var modeBanner: some View {
        SettingsCard {
            HStack(spacing: 12) {
                IconBadge(symbol: "circle.grid.2x2.fill", color: .orange, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text("底部圆点现在显示“\(model.layout[.dots]?.title ?? "不显示")”")
                        .font(.system(size: 13, weight: .semibold))
                    Text("切换到独立指示灯后，4 个点会各自显示下面选的状态。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("切换到独立指示灯") {
                    withAnimation(.snappy) { model.setContent(.indicators, for: .dots) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func dotSlot(_ index: Int) -> some View {
        let kind = model.layout.indicators[index]
        let targeted = dropTarget == index
        return Button {
            choosingDot = index
        } label: {
            VStack(spacing: 6) {
                Text("圆点 \(index + 1)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                if let kind {
                    IndicatorBadge(kind: kind, on: model.indicatorStates[kind] == true, size: 36)
                        .transition(.scale.combined(with: .opacity))
                    Text(kind.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(model.indicatorText(kind))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        .foregroundStyle(.tertiary)
                        .frame(width: 36, height: 36)
                    Text("空着")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("拖到这里")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(targeted ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(targeted ? Color.accentColor : .clear, lineWidth: 1.5)
            )
            .scaleEffect(targeted ? 1.04 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.3), value: targeted)
        .animation(.spring(duration: 0.35), value: kind)
        .popover(isPresented: Binding(
            get: { choosingDot == index },
            set: { if !$0 { choosingDot = nil } }
        )) {
            IndicatorChooser(model: model, index: index) { choosingDot = nil }
        }
        .draggable("duobar-dot:\(index)") {
            if let kind {
                IndicatorBadge(kind: kind, on: true, size: 36)
            }
        }
        .dropDestination(for: String.self) { items, _ in
            guard let item = items.first else { return false }
            if item.hasPrefix("duobar-indicator:"),
               let dropped = IndicatorKind(rawValue: String(item.dropFirst("duobar-indicator:".count))) {
                withAnimation(.spring(duration: 0.35)) { model.showIndicator(dropped, atDot: index) }
                return true
            }
            if item.hasPrefix("duobar-dot:"), let from = Int(item.dropFirst("duobar-dot:".count)), from != index {
                withAnimation(.spring(duration: 0.35)) { model.swapIndicators(from, index) }
                return true
            }
            return false
        } isTargeted: { inside in
            if inside {
                dropTarget = index
            } else if dropTarget == index {
                dropTarget = nil
            }
        }
    }
}

/// 点圆点后弹出的选择列表。
private struct IndicatorChooser: View {
    let model: AppModel
    let index: Int
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("圆点 \(index + 1) 显示")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    option(nil)
                    ForEach(IndicatorKind.allCases) { option($0) }
                }
            }
            .frame(height: 300)
        }
        .padding(10)
        .frame(width: 210)
    }

    private func option(_ kind: IndicatorKind?) -> some View {
        let selected = model.layout.indicators[index] == kind && model.layout.usesIndicators
        return Button {
            withAnimation(.spring(duration: 0.35)) {
                if let kind {
                    model.showIndicator(kind, atDot: index)
                } else {
                    model.setIndicator(nil, atDot: index)
                }
            }
            done()
        } label: {
            HStack(spacing: 8) {
                if let kind {
                    IndicatorBadge(kind: kind, on: true, size: 20)
                    Text(kind.title)
                } else {
                    Circle()
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(.secondary)
                    Text("空着")
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(ChooserRowStyle())
    }
}

private struct ChooserRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(pressed: configuration.isPressed) { configuration.label }
    }

    private struct HoverRow<Label: View>: View {
        let pressed: Bool
        @ViewBuilder let label: Label
        @State private var hovering = false

        var body: some View {
            label
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(pressed ? 0.25 : hovering ? 0.12 : 0))
                )
                .onHover { hovering = $0 }
        }
    }
}

/// 全部指示灯里的一格，可以拖到上面的圆点里。
private struct IndicatorTile: View {
    let kind: IndicatorKind
    let model: AppModel

    var body: some View {
        let on = model.indicatorStates[kind] == true
        let dots = model.layout.dots(showing: kind)
        HStack(spacing: 10) {
            IndicatorBadge(kind: kind, on: on, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(kind.title)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    ForEach(dots, id: \.self) { index in
                        Badge(text: "\(index + 1)")
                    }
                }
                Text(model.indicatorText(kind))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(dots.isEmpty ? 0.035 : 0.07))
        )
        .contentShape(Rectangle())
        .help(kind.summary)
        .hoverLift()
        .draggable("duobar-indicator:\(kind.rawValue)") {
            IndicatorBadge(kind: kind, on: true, size: 36)
        }
        .contextMenu {
            ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
                Button("显示在圆点 \(index + 1)") {
                    withAnimation(.spring(duration: 0.35)) { model.showIndicator(kind, atDot: index) }
                }
            }
        }
    }
}
