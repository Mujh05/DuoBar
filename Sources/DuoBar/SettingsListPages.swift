import SwiftUI

// MARK: - 状态

/// “状态”页：9 种状态和它们的实时数值，右边的菜单写着放在哪里。
struct MetricsSettingsPage: View {
    let model: AppModel

    var body: some View {
        Section {
            ForEach(MetricKind.allCases) { kind in
                MetricRow(kind: kind, model: model)
            }
        } footer: {
            SectionNote("右边的按钮写着它在图标上的位置。点按钮或者右键一行，可以把它放到别的位置。")
        }
    }
}

private struct MetricRow: View {
    let kind: MetricKind
    let model: AppModel

    var body: some View {
        let reading = model.reading(kind)
        HStack(spacing: 10) {
            IconBadge(symbol: kind.symbol, color: kind.color, size: 24)
            RowLabel(title: kind.title, detail: kind.summary)
            Spacer(minLength: 12)
            Text(reading.value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .contentTransition(.numericText())
                .animation(.snappy, value: reading.value)
            PlacementMenu(places: model.layout.slots(showing: kind).map(\.title)) {
                placeButtons
            }
        }
        .contextMenu { placeButtons }
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

/// “指示灯”页：上面是 4 个圆点，下面按类别列出全部指示灯，可以拖到圆点上。
struct IndicatorsSettingsPage: View {
    @Bindable var model: AppModel
    @State private var dropTarget: String?

    /// 按 IndicatorKind 里的顺序排的类别。
    private static let groups: [String] = IndicatorKind.allCases.reduce(into: []) { groups, kind in
        if !groups.contains(kind.group) { groups.append(kind.group) }
    }

    var body: some View {
        if !model.layout.usesIndicators {
            Section {
                LabeledContent {
                    Button("切换到独立指示灯") {
                        withAnimation(.snappy) { model.setContent(.indicators, for: .dots) }
                    }
                } label: {
                    Text("底部圆点现在显示“\(model.layout[.dots]?.title ?? "不显示")”")
                    Text("切换后，4 个圆点会各自显示下面选的状态。")
                }
            }
        }

        Section {
            ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
                IndicatorDotRow(model: model, index: index, dropTarget: $dropTarget)
            }
        } header: {
            Text("4 个圆点")
        } footer: {
            SectionNote("把下面的指示灯拖到圆点上，或者直接选择。圆点之间也可以拖动交换。")
        }

        ForEach(Self.groups, id: \.self) { group in
            Section(group) {
                ForEach(IndicatorKind.allCases.filter { $0.group == group }) { kind in
                    IndicatorRow(kind: kind, model: model)
                }
            }
        }
    }
}

/// 一个指示灯：亮起时图标用自己的颜色。鼠标停在上面可以看到说明。
private struct IndicatorRow: View {
    let kind: IndicatorKind
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            IndicatorBadge(kind: kind, on: model.indicatorStates[kind] == true, size: 24)
            RowLabel(title: kind.title, detail: model.indicatorText(kind))
            Spacer(minLength: 12)
            PlacementMenu(places: model.layout.dots(showing: kind).map { "圆点 \($0 + 1)" }) {
                placeButtons
            }
        }
        .contentShape(Rectangle())
        .help(kind.summary)
        .draggable("duobar-indicator:\(kind.rawValue)") {
            IndicatorBadge(kind: kind, on: true, size: 32)
        }
        .contextMenu { placeButtons }
    }

    @ViewBuilder
    private var placeButtons: some View {
        ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
            Button("显示在圆点 \(index + 1)") {
                withAnimation(.snappy) { model.showIndicator(kind, atDot: index) }
            }
        }
    }
}
