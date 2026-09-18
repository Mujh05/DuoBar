import AppKit
import SwiftUI

// MARK: - 菜单栏

/// “菜单栏”页：电量百分比样式、图标位置、系统自带图标。
struct MenuBarSettingsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard("电量百分比", subtitle: "选择数字显示在哪里。放在圆环顶部时，切换会有让位动画。") {
                VStack(alignment: .leading, spacing: 10) {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                              spacing: 10) {
                        ForEach(PercentMode.allCases) { mode in
                            PercentOption(mode: mode, model: model)
                        }
                    }
                    if model.percentMode == .onRing, model.layout[.ring] == nil {
                        Label("“圆环顶部”需要先在“图标”页里显示外圈圆环。", systemImage: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }
            SettingsCard("图标位置", subtitle: "按住 ⌘，把菜单栏里的 DuoBar 图标拖到想要的位置（比如控制中心左边），macOS 会记住。") {
                DragHint(state: model.iconState)
                    .frame(maxWidth: .infinity)
            }
            SettingsCard("系统自带的图标",
                         subtitle: "macOS 不允许其他 App 移除系统图标。想只留下 DuoBar，需要在“系统设置 › 菜单栏”里关掉 Wi-Fi 和电池。") {
                Button {
                    model.openMenuBarSettings()
                } label: {
                    Label("打开菜单栏设置…", systemImage: "arrow.up.right.square")
                }
            }
        }
    }
}

/// 电量百分比的一个选项，带小预览。
private struct PercentOption: View {
    let mode: PercentMode
    let model: AppModel

    private var selected: Bool { model.percentMode == mode }

    var body: some View {
        let percent = model.battery.hasBattery ? model.battery.percent : 56
        Button {
            withAnimation(.spring(duration: 0.35)) { model.percentMode = mode }
        } label: {
            VStack(spacing: 8) {
                MenuBarMock(state: model.iconState,
                            percentTitle: mode == .always || mode == .whenLow ? "\(percent)%" : nil,
                            embeddedPercent: mode == .onRing ? percent : nil,
                            embeddedProgress: mode == .onRing ? 1 : 0,
                            dark: true)
                    .opacity(mode == .whenLow ? 0.85 : 1)
                VStack(spacing: 1) {
                    Text(mode.title)
                        .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.13) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(.white, Color.accentColor)
                        .padding(6)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverLift()
    }

    private var detail: String {
        switch mode {
        case .never: "只显示图标"
        case .whenLow: "电量不高于 20% 时才显示"
        case .always: "一直显示在图标左边"
        case .onRing: "嵌在圆环顶部的开口里"
        }
    }
}

/// 演示“按住 ⌘ 拖动”的小动画：DuoBar 图标从左边滑到控制中心旁边。
private struct DragHint: View {
    let state: IconState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let travel: CGFloat = 128

    struct Motion {
        var x: CGFloat = 0
        var lift: CGFloat = 0
        var key: Double = 0
        var opacity: Double = 1
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color(white: 0.13))
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass")
                    .frame(width: 30)
                Color.clear.frame(width: 38)
                Image(systemName: "bubble.left.fill")
                    .frame(width: 30)
                Image(systemName: "clock.arrow.circlepath")
                    .frame(width: 30)
                Image(systemName: "bolt.horizontal.circle")
                    .frame(width: 30)
                Color.clear.frame(width: 38)
                Image(systemName: "switch.2")
                    .frame(width: 30)
                Text("9:41")
                    .frame(width: 44)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.leading, 8)

            if reduceMotion {
                icon.offset(x: 38 + Self.travel)
            } else {
                icon
                    .keyframeAnimator(initialValue: Motion(), repeating: true) { content, motion in
                        content
                            .overlay(alignment: .top) { CommandKeycap().opacity(motion.key).offset(y: -20) }
                            .scaleEffect(1 + motion.lift * 0.12)
                            .shadow(color: .black.opacity(0.4 * motion.lift), radius: 4, y: 2)
                            .offset(x: 38 + motion.x)
                            .opacity(motion.opacity)
                    } keyframes: { _ in
                        KeyframeTrack(\.x) {
                            LinearKeyframe(0, duration: 1.0)
                            CubicKeyframe(Self.travel, duration: 1.3)
                            LinearKeyframe(Self.travel, duration: 1.4)
                            LinearKeyframe(0, duration: 0.01)
                            LinearKeyframe(0, duration: 0.5)
                        }
                        KeyframeTrack(\.lift) {
                            LinearKeyframe(0, duration: 0.6)
                            SpringKeyframe(1, duration: 0.4)
                            LinearKeyframe(1, duration: 1.3)
                            SpringKeyframe(0, duration: 0.5)
                            LinearKeyframe(0, duration: 1.41)
                        }
                        KeyframeTrack(\.key) {
                            LinearKeyframe(0, duration: 0.5)
                            LinearKeyframe(1, duration: 0.2)
                            LinearKeyframe(1, duration: 1.6)
                            LinearKeyframe(0, duration: 0.3)
                            LinearKeyframe(0, duration: 1.61)
                        }
                        KeyframeTrack(\.opacity) {
                            LinearKeyframe(1, duration: 3.3)
                            LinearKeyframe(0, duration: 0.4)
                            LinearKeyframe(0, duration: 0.01)
                            LinearKeyframe(1, duration: 0.5)
                        }
                    }
            }
        }
        .frame(width: 330, height: 34)
        .padding(.top, 18)
        .environment(\.colorScheme, .dark)
    }

    private var icon: some View {
        let metrics = MenuBarIcon.metrics(scale: 0.95)
        return Canvas { context, size in
            let offset = metrics.center.y - metrics.size.height / 2
            let center = CGPoint(x: size.width / 2, y: size.height / 2 + offset)
            context.draw(DuoParts.combined(state, center: center, radius: metrics.radius, style: metrics.style),
                         color: .white)
        }
        .frame(width: 38, height: 34)
    }

}

/// 小小的 ⌘ 键帽。
private struct CommandKeycap: View {
    var body: some View {
        Image(systemName: "command")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 18)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Color.accentColor))
            .fixedSize()
    }
}

// MARK: - 更新

/// “更新”页。
struct UpdatesSettingsPage: View {
    @Bindable var model: AppModel
    @State private var spinning = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard {
                HStack(spacing: 16) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DuoBar \(UpdateChecker.currentVersion)")
                            .font(.system(size: 17, weight: .semibold))
                        HStack(spacing: 6) {
                            statusIcon
                            Text(statusText)
                                .contentTransition(.opacity)
                        }
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        if let message = model.updateMessage {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(.red)
                                .transition(.opacity)
                        }
                    }
                    Spacer(minLength: 12)
                    actions
                }
                .animation(.snappy, value: model.updateStatus)
                .animation(.snappy, value: model.updateMessage)
            }
            SettingsCard("自动检查") {
                SettingToggle(title: "每天检查一次更新",
                              detail: "向 GitHub 查询最新版本，不会发送任何个人信息。发现新版本时，面板里会出现提示。",
                              isOn: $model.autoCheckUpdates)
            }
            SettingsCard("所有版本", subtitle: "每个版本的更新内容和安装包都在 GitHub 的发布页面上。") {
                Link(destination: UpdateChecker.releasesPage) {
                    Label("在 GitHub 上查看", systemImage: "arrow.up.right.square")
                }
            }
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch model.updateStatus {
        case .checking, .downloading, .installing:
            Image(systemName: "arrow.triangle.2.circlepath")
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
                .onAppear { spinning = true }
                .onDisappear { spinning = false }
        case .upToDate:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .transition(.scale.combined(with: .opacity))
        case .available:
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.bounce, value: model.updateStatus)
        case .idle:
            Image(systemName: "clock")
        }
    }

    private var statusText: String {
        switch model.updateStatus {
        case .checking:
            return "正在检查…"
        case .upToDate:
            return "已经是最新版本"
        case let .available(release):
            return "发现新版本 \(release.version)"
        case let .downloading(release):
            return "正在下载 \(release.version)…"
        case let .installing(release):
            return "正在安装 \(release.version)，完成后会自动重新打开…"
        case .idle:
            guard let last = model.lastUpdateCheck else { return "还没有检查过" }
            return "上次检查：\(last.formatted(.relative(presentation: .named)))"
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch model.updateStatus {
        case .available:
            VStack(alignment: .trailing, spacing: 6) {
                Button("立即更新") { model.installUpdate() }
                    .buttonStyle(.borderedProminent)
                    .help("下载并校验新版本，替换当前的 DuoBar 后自动重新打开")
                Button("查看更新内容") { model.openReleasePage() }
                    .buttonStyle(.link)
                    .font(.system(size: 11))
            }
        case .checking, .downloading, .installing:
            ProgressView()
                .controlSize(.small)
        case .idle, .upToDate:
            Button("检查更新") {
                Task { await model.checkForUpdates(manual: true) }
            }
        }
    }
}

// MARK: - 通用

/// “通用”页：面板、启动、关于。
struct GeneralSettingsPage: View {
    @Bindable var model: AppModel

    private static let homepage = URL(string: "https://github.com/\(UpdateChecker.repository)")!
    private static let issues = URL(string: "https://github.com/\(UpdateChecker.repository)/issues")!

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard("面板") {
                SettingToggle(title: "显示 Wi-Fi 开关和附近的网络",
                              detail: "网络放在图标上时，点面板里的网络图标展开；否则从面板底部的 Wi-Fi 按钮打开。",
                              isOn: $model.showWiFiControls)
            }
            SettingsCard("启动") {
                VStack(alignment: .leading, spacing: 8) {
                    SettingToggle(title: "登录时自动启动", isOn: Binding(
                        get: { model.launchAtLogin },
                        set: { model.setLaunchAtLogin($0) }
                    ))
                    if let note = model.loginItemNote {
                        Button(note) { model.openLoginItemsSettings() }
                            .buttonStyle(.link)
                            .font(.system(size: 11))
                    }
                }
            }
            SettingsCard("关于") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 52, height: 52)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("DuoBar")
                                .font(.system(size: 15, weight: .semibold))
                            Text("版本 \(UpdateChecker.currentVersion)")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                            Text("把 iPhone Duo 外屏的三合一状态图标搬到 Mac 菜单栏。")
                                .font(.system(size: 12))
                        }
                    }
                    HStack(spacing: 16) {
                        Link(destination: Self.homepage) {
                            Label("GitHub 主页", systemImage: "chevron.left.forwardslash.chevron.right")
                        }
                        Link(destination: Self.issues) {
                            Label("反馈问题", systemImage: "exclamationmark.bubble.fill")
                        }
                    }
                    .font(.system(size: 12))
                    Text("DuoBar 是独立的非官方项目，与 Apple Inc. 没有关联。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
