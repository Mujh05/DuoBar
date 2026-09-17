import SwiftUI

/// “图标”页：预览、三个位置、大小、颜色。
struct IconSettingsPage: View {
    @Bindable var model: AppModel
    @State private var dropTarget: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            IconHero(model: model)
            layoutCard
            sizeCard
            colorCard
        }
    }

    // MARK: - 三个位置

    private var layoutCard: some View {
        SettingsCard("三个位置", subtitle: "每个位置选一种内容。按住一行拖到另一行上，可以交换两个位置（或两个圆点）。") {
            Button("恢复默认") {
                withAnimation(.snappy) { model.resetLayout() }
            }
            .controlSize(.small)
        } content: {
            VStack(spacing: 6) {
                ForEach(Slot.allCases) { slot in
                    slotRow(slot)
                    if slot == .dots, model.layout.usesIndicators {
                        VStack(spacing: 4) {
                            ForEach(0 ..< IconLayout.dotCount, id: \.self) { index in
                                dotRow(index)
                            }
                        }
                        .transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .top)),
                                                removal: .opacity))
                    }
                }
            }
            .animation(.snappy(duration: 0.3), value: model.layout)
        }
    }

    private func slotRow(_ slot: Slot) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            SlotDiagram(slot: slot)
                .frame(width: 30, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(slot.title)
                    .font(.system(size: 13, weight: .medium))
                Text(slot.hint)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Picker(slot.title, selection: Binding(
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
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
        .dragRow(id: "slot:\(slot.rawValue)", target: $dropTarget,
                 preview: model.layout[slot]?.title ?? "不显示") { source in
            guard source.hasPrefix("slot:"), let raw = Int(source.dropFirst(5)),
                  let from = Slot(rawValue: raw), from != slot
            else { return false }
            return withAnimation(.snappy) { model.swapSlots(from, slot) }
        }
    }

    private func dotRow(_ index: Int) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
            DotDiagram(index: index)
                .frame(width: 30, height: 16)
            Text("圆点 \(index + 1)")
                .font(.system(size: 12))
            Spacer(minLength: 12)
            if let kind = model.layout.indicators[index] {
                IndicatorBadge(kind: kind, on: model.indicatorStates[kind] == true, size: 18)
            }
            Picker("圆点 \(index + 1)", selection: Binding(
                get: { model.layout.indicators[index] },
                set: { model.setIndicator($0, atDot: index) }
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
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.leading, 34)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .dragRow(id: "dot:\(index)", target: $dropTarget,
                 preview: model.layout.indicators[index]?.title ?? "空着") { source in
            guard source.hasPrefix("dot:"), let from = Int(source.dropFirst(4)), from != index else { return false }
            withAnimation(.snappy) { model.swapIndicators(from, index) }
            return true
        }
    }

    // MARK: - 大小

    private var sizeCard: some View {
        SettingsCard("图标大小", subtitle: "拖动滑块无级调节，菜单栏里的图标会跟着实时变化。") {
            Button {
                withAnimation(.snappy) { model.iconScale = 1 }
            } label: {
                Label("100%", systemImage: "arrow.counterclockwise")
            }
            .controlSize(.small)
            .disabled(abs(model.iconScale - 1) < 0.005)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: "circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Slider(value: $model.iconScale, in: MenuBarIcon.scaleRange)
                    Image(systemName: "circle")
                        .font(.system(size: 17))
                        .foregroundStyle(.secondary)
                    Text("\(Int((model.iconScale * 100).rounded()))%")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .frame(width: 46, alignment: .trailing)
                }
                if let warning = iconSizeWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: iconSizeWarning)
        }
    }

    /// 图标比某块屏幕的菜单栏还高时提醒：外接显示器的菜单栏通常比刘海屏矮。
    private var iconSizeWarning: String? {
        guard let bar = MenuBarIcon.smallestMenuBarHeight() else { return nil }
        let icon = MenuBarIcon.metrics(scale: model.iconScale).contentHeight
        guard icon > bar else { return nil }
        return "有屏幕的菜单栏只有 \(Int(bar)) 点高，图标超出的部分会被裁掉。"
    }

    // MARK: - 颜色

    private var colorCard: some View {
        SettingsCard("颜色", subtitle: "图标带颜色时，DuoBar 会按菜单栏的深浅自己选择黑色或白色。") {
            VStack(alignment: .leading, spacing: 12) {
                SettingToggle(title: "电量变色", detail: "电量放在哪个位置都会跟着变色。", isOn: $model.batteryColors)
                HStack(spacing: 8) {
                    RingChip(tint: .red, label: "不高于 20%", enabled: model.batteryColors)
                    RingChip(tint: .yellow, label: "低电量模式", enabled: model.batteryColors)
                    RingChip(tint: .green, label: "接着电源", enabled: model.batteryColors && model.chargingGreen)
                }
                SettingToggle(title: "接着电源时显示绿色", isOn: $model.chargingGreen)
                    .disabled(!model.batteryColors)
                    .opacity(model.batteryColors ? 1 : 0.5)
                Divider()
                SettingToggle(title: "指示灯亮起时用各自的颜色", detail: "比如蓝牙蓝色、麦克风橙色、静音红色。",
                              isOn: $model.indicatorColors)
                HStack(spacing: 6) {
                    ForEach([IndicatorKind.bluetooth, .microphone, .muted, .vpn, .lowPower], id: \.self) { kind in
                        IndicatorBadge(kind: kind, on: model.indicatorColors, size: 22)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: model.batteryColors)
            .animation(.easeInOut(duration: 0.25), value: model.chargingGreen)
        }
    }
}

/// 顶部的大预览：点图标播放打开面板时的展开动画，右边是菜单栏里的实际效果。
private struct IconHero: View {
    let model: AppModel
    @State private var split = false
    @State private var demo: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var embeddedPercent: Int? {
        model.battery.hasBattery && model.layout[.ring] != nil ? model.battery.percent : nil
    }

    var body: some View {
        HStack(spacing: 22) {
            Button(action: playDemo) {
                SplitGlyphView(progress: split ? 1 : 0, state: model.iconState)
                    .frame(width: 288, height: 104)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .environment(\.colorScheme, .dark)
            .help("点击预览打开面板时的展开动画")

            VStack(alignment: .leading, spacing: 8) {
                Text("菜单栏里的样子")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                ForEach([false, true], id: \.self) { dark in
                    MenuBarMock(state: model.iconState, scale: CGFloat(model.iconScale),
                                percentTitle: model.percentTitle,
                                embeddedPercent: embeddedPercent,
                                embeddedProgress: model.percentMode == .onRing ? 1 : 0,
                                dark: dark)
                }
                Label("点左边的图标，看打开面板时的动画", systemImage: "play.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.65))
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(background)
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

    private var background: some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.24, green: 0.27, blue: 0.35),
                                          Color(red: 0.07, green: 0.08, blue: 0.11)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(alignment: .leading) {
                // 图标后面缓慢呼吸的光晕。
                Circle()
                    .fill(RadialGradient(colors: [Color.accentColor.opacity(0.45), .clear],
                                         center: .center, startRadius: 0, endRadius: 95))
                    .frame(width: 190, height: 190)
                    .offset(x: 45)
                    .phaseAnimator([0.55, 1.0]) { content, phase in
                        content
                            .opacity(reduceMotion ? 0.8 : phase)
                            .scaleEffect(reduceMotion ? 1 : 0.88 + 0.12 * phase)
                    } animation: { _ in
                        .easeInOut(duration: 2.6)
                    }
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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

/// 说明电量颜色含义的小标签。
private struct RingChip: View {
    let tint: DuoTint
    let label: String
    let enabled: Bool

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .trim(from: 0.17, to: 0.83)
                .stroke(tint.color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(90))
                .frame(width: 13, height: 13)
            Text(label)
                .font(.system(size: 11))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.color.opacity(0.13)))
        .saturation(enabled ? 1 : 0)
        .opacity(enabled ? 1 : 0.45)
    }
}
