import SwiftUI

/// “图标”页：预览、三个位置、底部圆点、大小、颜色。
struct IconSettingsPage: View {
    @Bindable var model: AppModel
    @State private var dropTarget: String?

    var body: some View {
        Section {
            IconPreview(model: model)
        } footer: {
            SectionNote("点左边的图标，预览打开面板时的展开动画。")
        }

        Section {
            ForEach(Slot.allCases) { slot in
                slotRow(slot)
            }
        } header: {
            Text("三个位置")
        } footer: {
            SectionNote("按住一行拖到另一行上，可以交换两个位置。") {
                Button("恢复默认") {
                    withAnimation(.snappy) { model.resetLayout() }
                }
            }
        }

        if model.layout.usesIndicators {
            Section {
                ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
                    IndicatorDotRow(model: model, index: index, dropTarget: $dropTarget)
                }
            } header: {
                Text("独立指示灯")
            } footer: {
                SectionNote("底部 4 个圆点各自显示一项开关状态，按住一行拖到另一行上可以交换。")
            }
        }

        Section {
            sizeRow
            if let warning = iconSizeWarning {
                Label {
                    Text(warning)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("图标大小")
        } footer: {
            SectionNote("拖动滑块无级调节，菜单栏里的图标会跟着变化。") {
                Button("恢复 100%") {
                    withAnimation(.snappy) { model.iconScale = 1 }
                }
                .disabled(abs(model.iconScale - 1) < 0.005)
            }
        }

        Section {
            Toggle(isOn: $model.batteryColors) {
                Text("电量变色")
                Text("电量不高于 20% 且没接电源时变红，低电量模式时变黄。电量放在哪个位置都会变色。")
            }
            Toggle("接着电源时显示绿色", isOn: $model.chargingGreen)
                .disabled(!model.batteryColors)
            Toggle(isOn: $model.indicatorColors) {
                Text("指示灯亮起时用各自的颜色")
                Text("比如蓝牙蓝色、麦克风橙色、静音红色。")
            }
        } header: {
            Text("颜色")
        } footer: {
            SectionNote("图标带颜色时，DuoBar 会按菜单栏的深浅自己选择黑色或白色。")
        }
    }

    // MARK: - 三个位置

    private func slotRow(_ slot: Slot) -> some View {
        Picker(selection: Binding(
            get: { model.layout[slot] },
            set: { value in withAnimation(.snappy) { model.setContent(value, for: slot) } }
        )) {
            if model.layout.canClear(slot) {
                Text("不显示").tag(SlotContent?.none)
                Divider()
            }
            ForEach(MetricKind.allCases) { kind in
                Label(kind.title, systemImage: kind.symbol).tag(SlotContent?.some(.metric(kind)))
            }
            if slot == .dots {
                Divider()
                Label(SlotContent.indicators.title, systemImage: SlotContent.indicators.symbol)
                    .tag(SlotContent?.some(.indicators))
            }
        } label: {
            HStack(spacing: 10) {
                SlotDiagram(slot: slot)
                    .frame(width: 26, height: 28)
                RowLabel(title: slot.title, detail: slot.hint)
            }
        }
        .dragRow(id: "slot:\(slot.rawValue)", target: $dropTarget,
                 preview: model.layout[slot]?.title ?? "不显示") { source in
            guard source.hasPrefix("slot:"), let raw = Int(source.dropFirst(5)),
                  let from = Slot(rawValue: raw), from != slot
            else { return false }
            return withAnimation(.snappy) { model.swapSlots(from, slot) }
        }
    }

    // MARK: - 大小

    private var sizeRow: some View {
        LabeledContent("大小") {
            HStack(spacing: 8) {
                Image(systemName: "circle")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
                Slider(value: $model.iconScale, in: MenuBarIcon.scaleRange)
                Image(systemName: "circle")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                Text("\(Int((model.iconScale * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 42, alignment: .trailing)
            }
        }
    }

    /// 图标比某块屏幕的菜单栏还高时提醒：外接显示器的菜单栏通常比刘海屏矮。
    private var iconSizeWarning: String? {
        guard let bar = MenuBarIcon.smallestMenuBarHeight() else { return nil }
        let icon = MenuBarIcon.metrics(scale: model.iconScale).contentHeight
        guard icon > bar else { return nil }
        return "有屏幕的菜单栏只有 \(Int(bar)) 点高，图标超出的部分会被裁掉。"
    }
}

/// 最上面的预览：点左边的图标播放打开面板时的展开动画，右边是菜单栏里的实际效果。
private struct IconPreview: View {
    let model: AppModel
    @State private var split = false
    @State private var demo: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var embeddedPercent: Int? {
        model.battery.hasBattery && model.layout[.ring] != nil ? model.battery.percent : nil
    }

    var body: some View {
        // 窗口窄的时候，菜单栏的样子换到下面。
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 20) {
                glyph
                menuBars
            }
            VStack(spacing: 12) {
                glyph
                menuBars
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .onAppear {
            guard !reduceMotion else { return }
            demo = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                guard !Task.isCancelled else { return }
                playDemo()
            }
        }
        .onDisappear { demo?.cancel() }
    }

    /// 面板顶部的图标，和面板一样跟随系统的浅色或深色外观。
    private var glyph: some View {
        Button(action: playDemo) {
            SplitGlyphView(progress: split ? 1 : 0, state: model.iconState)
                .frame(width: 288, height: 104)
                .padding(.horizontal, 12)
                .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("点击预览打开面板时的展开动画")
    }

    private var menuBars: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([false, true], id: \.self) { dark in
                MenuBarMock(state: model.iconState, scale: CGFloat(model.iconScale),
                            percentTitle: model.percentTitle,
                            embeddedPercent: embeddedPercent,
                            embeddedProgress: model.percentMode == .onRing ? 1 : 0,
                            dark: dark)
            }
        }
        .fixedSize()
    }

    /// 拆开，停一会儿，再合回去。
    private func playDemo() {
        demo?.cancel()
        guard !reduceMotion else {
            split.toggle()
            return
        }
        demo = Task { @MainActor in
            withAnimation(.spring(duration: 0.8, bounce: 0.22)) { split = true }
            try? await Task.sleep(for: .seconds(2.2))
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.8, bounce: 0.12)) { split = false }
        }
    }
}
