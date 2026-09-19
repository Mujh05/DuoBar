import AppKit
import SwiftUI

// MARK: - 菜单栏

/// “菜单栏”页：电量百分比、图标位置、系统自带的图标。
struct MenuBarSettingsPage: View {
    @Bindable var model: AppModel

    var body: some View {
        Section {
            Picker("显示位置", selection: $model.percentMode.animation(.spring(duration: 0.35))) {
                ForEach(PercentMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            PercentPreview(model: model)
            if model.percentMode == .onRing, model.layout[.ring] == nil {
                Label {
                    Text("“圆环顶部”需要先在“图标”页里显示外圈圆环。")
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        } header: {
            Text("电量百分比")
        } footer: {
            SectionNote(model.percentMode.detail)
        }

        Section {
            DragHint(state: model.iconState)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } header: {
            Text("图标位置")
        } footer: {
            SectionNote("按住 ⌘，把菜单栏里的 DuoBar 图标拖到想要的位置（比如控制中心左边），macOS 会记住。")
        }

        Section {
            LabeledContent {
                Button("打开菜单栏设置…") { model.openMenuBarSettings() }
            } label: {
                Text("系统自带的 Wi-Fi 和电池图标")
                Text("macOS 不允许其他 App 移除系统图标。想只留下 DuoBar，需要在“系统设置 › 菜单栏”里把它们关掉。")
            }
        }
    }
}

private extension PercentMode {
    var detail: String {
        switch self {
        case .never: "菜单栏里只显示图标。"
        case .whenLow: "电量不高于 20% 时，在图标左边显示百分比。"
        case .always: "一直在图标左边显示百分比。"
        case .onRing: "百分比嵌在外圈圆环顶部的开口里，切换时圆环会让出位置。"
        }
    }
}

/// 选中的样式在浅色和深色菜单栏里的样子。电量低时才显示的样式也照样画出数字，方便对比。
private struct PercentPreview: View {
    let model: AppModel

    var body: some View {
        let mode = model.percentMode
        let percent = model.battery.hasBattery ? model.battery.percent : 56
        HStack(spacing: 10) {
            ForEach([false, true], id: \.self) { dark in
                MenuBarMock(state: model.iconState, scale: CGFloat(model.iconScale),
                            percentTitle: mode == .always || mode == .whenLow ? "\(percent)%" : nil,
                            embeddedPercent: mode == .onRing ? percent : nil,
                            embeddedProgress: mode == .onRing ? 1 : 0,
                            dark: dark)
            }
        }
        .fixedSize()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
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
        Section {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text("DuoBar \(UpdateChecker.currentVersion)")
                        .font(.headline)
                    HStack(spacing: 5) {
                        statusIcon
                        Text(statusText)
                            .contentTransition(.opacity)
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    if let message = model.updateMessage {
                        Text(message)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }
                Spacer(minLength: 12)
                actions
            }
            .padding(.vertical, 4)
            .animation(.snappy, value: model.updateStatus)
            .animation(.snappy, value: model.updateMessage)
        }

        Section {
            Toggle(isOn: $model.autoCheckUpdates) {
                Text("每天检查一次更新")
                Text("向 GitHub 查询最新版本，不会发送任何个人信息。发现新版本时，面板里会出现提示。")
            }
        }

        Section {
            LabeledContent {
                Link("在 GitHub 上查看", destination: UpdateChecker.releasesPage)
            } label: {
                Text("所有版本")
                Text("每个版本的更新内容和安装包都在 GitHub 的发布页面上。")
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
                    .font(.subheadline)
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
        Section("面板") {
            Toggle(isOn: $model.showWiFiControls) {
                Text("显示 Wi-Fi 开关和附近的网络")
                Text("网络放在图标上时，点面板里的网络图标展开；否则从面板底部的 Wi-Fi 按钮打开。")
            }
        }

        Section("启动") {
            Toggle("登录时自动启动", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            if let note = model.loginItemNote {
                Button(note) { model.openLoginItemsSettings() }
                    .buttonStyle(.link)
            }
        }

        Section {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DuoBar")
                        .font(.headline)
                    Text("版本 \(UpdateChecker.currentVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("把 iPhone Duo 外屏的三合一状态图标搬到 Mac 菜单栏。")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 4)
            LabeledContent("项目主页") {
                Link("在 GitHub 上查看", destination: Self.homepage)
            }
            LabeledContent("反馈问题") {
                Link("提交到 GitHub", destination: Self.issues)
            }
        } header: {
            Text("关于")
        } footer: {
            SectionNote("DuoBar 是独立的非官方项目，与 Apple Inc. 没有关联。")
        }
    }
}
