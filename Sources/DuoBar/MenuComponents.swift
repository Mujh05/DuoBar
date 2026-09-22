import SwiftUI

// 仿 macOS 26 的菜单栏菜单（Wi-Fi、电池、声音）和控制中心的几种部件。
// 行的高亮离面板边缘 6 点，文字和图标离边缘 14 点，和系统菜单一样。

enum MenuMetrics {
    /// 面板宽度，和系统的 Wi-Fi 菜单差不多。
    static let width: CGFloat = 320
    /// 文字、图标离面板边缘的距离。
    static let inset: CGFloat = 14
    /// 鼠标悬停时高亮的圆角矩形离面板边缘的距离。
    static let highlightInset: CGFloat = 6
    static let highlightRadius: CGFloat = 8
}

/// 圆形图标。打开的状态是白底、符号带颜色，和控制中心一样；关闭时是半透明的灰底。
struct IconCircle<Glyph: View>: View {
    var active: Bool
    var size: CGFloat = 26
    /// 打开时符号的颜色；关闭时如果给了颜色，符号也用它（比如低电量的红色）。
    var tint: Color?
    /// 圆底的不透明度，拆分动画里用来淡入。
    var backgroundOpacity: Double = 1
    @ViewBuilder var glyph: () -> Glyph

    var body: some View {
        ZStack {
            Circle()
                .fill(active ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.primary.opacity(0.1)))
                .shadow(color: .black.opacity(active ? 0.12 : 0), radius: 1, y: 0.5)
                .opacity(backgroundOpacity)
            glyph()
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(active ? Color.fixedLight(tint ?? .accentColor) : tint ?? Color.primary.opacity(0.75))
        }
        .frame(width: size, height: size)
    }
}

extension Color {
    /// 白底上的颜色：取系统颜色在浅色外观下的值，变成固定颜色。
    /// 深色模式下玻璃的透光效果会把系统颜色冲淡，白底上的绿色几乎看不见。
    static func fixedLight(_ color: Color) -> Color {
        let dynamic = NSColor(color)
        var fixed = dynamic
        NSAppearance(named: .aqua)?.performAsCurrentDrawingAppearance {
            fixed = dynamic.usingColorSpace(.sRGB) ?? dynamic
        }
        return Color(nsColor: fixed)
    }
}

extension IconCircle where Glyph == SymbolGlyph {
    init(symbol: String, variable: Double? = nil, active: Bool, size: CGFloat = 26, tint: Color? = nil) {
        self.init(active: active, size: size, tint: tint) { SymbolGlyph(name: symbol, variable: variable) }
    }
}

/// SF Symbol，可以带可变值（信号格、音量波纹）。
struct SymbolGlyph: View {
    var name: String
    var variable: Double?

    var body: some View {
        if let variable {
            Image(systemName: name, variableValue: variable)
        } else {
            Image(systemName: name)
        }
    }
}

/// 鼠标悬停时整行高亮的背景。
private struct HoverHighlight: ViewModifier {
    var enabled: Bool
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, MenuMetrics.inset - MenuMetrics.highlightInset)
            .background(
                RoundedRectangle(cornerRadius: MenuMetrics.highlightRadius, style: .continuous)
                    .fill(hovering && enabled ? Color.primary.opacity(0.1) : .clear)
            )
            .padding(.horizontal, MenuMetrics.highlightInset)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    /// 系统菜单那样的行：左右留出边距，鼠标移上去时高亮。
    func menuRowHighlight(_ enabled: Bool = true) -> some View {
        modifier(HoverHighlight(enabled: enabled))
    }
}

/// 带图标的一行，比如一个 Wi-Fi 网络。action 为 nil 时不能点，也不高亮。
struct MenuRow<Leading: View, Trailing: View>: View {
    var title: String
    var subtitle: String?
    var emphasized = false
    var help: String?
    var action: (() -> Void)?
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .help(help ?? "")
        } else {
            content
                .help(help ?? "")
        }
    }

    private var content: some View {
        HStack(spacing: 9) {
            leading()
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: emphasized ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 8)
            trailing()
        }
        .frame(minHeight: 32)
        .menuRowHighlight(action != nil)
    }
}

extension MenuRow where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, emphasized: Bool = false, help: String? = nil,
         action: (() -> Void)? = nil, @ViewBuilder leading: @escaping () -> Leading) {
        self.init(title: title, subtitle: subtitle, emphasized: emphasized, help: help, action: action,
                  leading: leading, trailing: { EmptyView() })
    }
}

/// 只有文字的菜单项，比如“Wi-Fi 设置…”“立即充满电”。
struct MenuItem: View {
    var title: String
    var enabled = true
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(enabled ? .primary : .secondary)
                Spacer(minLength: 0)
            }
            .frame(minHeight: 24)
            .menuRowHighlight(enabled)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 菜单的标题行：粗体标题，右边放开关或数值。
struct MenuTitleRow<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .bold))
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, MenuMetrics.inset)
        .frame(minHeight: 30)
    }
}

/// 灰色的分组标题，比如“已知网络”。
struct MenuSectionHeader: View {
    var title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.top, 5)
            .padding(.bottom, 1)
    }
}

/// 一行灰色说明文字，比如“电源：电源适配器”。
struct MenuNote: View {
    var text: String
    var color: Color = .secondary

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 1)
    }
}

/// 左边名称、右边数值的一行，比如“占用 34%”。
struct MenuValueRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        }
        .font(.system(size: 13))
        .padding(.horizontal, MenuMetrics.inset)
        .padding(.vertical, 2)
    }
}

struct MenuDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 1)
            .padding(.horizontal, MenuMetrics.inset)
            .padding(.vertical, 5)
    }
}

/// 控制中心样式的胶囊：左边圆形图标（可以单独点，比如开关 Wi-Fi），中间标题和小字，右边箭头。
/// macOS 26 起胶囊本身是系统的玻璃，跟着系统的玻璃样式和深浅变化；更早的系统用半透明的灰底。
struct ModuleTile<Glyph: View>: View {
    var title: String
    var subtitle: String
    var active: Bool
    var tint: Color?
    var expanded: Bool
    /// 拆分动画里还没滑到位时小于 1：圆底、文字和箭头逐渐出现，图标一直显示。
    var reveal: Double = 1
    /// 点圆形图标做的事；nil 时和点整个胶囊一样。
    var iconAction: (() -> Void)?
    var iconHelp: String?
    var action: () -> Void
    @ViewBuilder var glyph: () -> Glyph
    @State private var hovering = false

    static var height: CGFloat { 52 }

    var body: some View {
        HStack(spacing: 10) {
            icon
            Button(action: action) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .lineLimit(1)
                    .truncationMode(.tail)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .opacity(reveal)
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .frame(height: Self.height)
        .modifier(TileBackground(hovering: hovering, reveal: reveal))
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }

    @ViewBuilder
    private var icon: some View {
        let circle = IconCircle(active: active, size: 36, tint: tint, backgroundOpacity: reveal, glyph: glyph)
        if let iconAction {
            Button(action: iconAction) { circle }
                .buttonStyle(.plain)
                .help(iconHelp ?? "")
        } else {
            Button(action: action) { circle }
                .buttonStyle(.plain)
        }
    }
}

/// 胶囊的底：macOS 26 起用系统玻璃（鼠标移上去时玻璃自己有反馈），更早的系统用半透明的灰底。
private struct TileBackground: ViewModifier {
    var hovering: Bool
    var reveal: Double

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            content.background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.1 : 0.065))
                    .overlay(Capsule(style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 1))
                    .opacity(reveal)
            )
        }
    }
}

/// 放胶囊的容器：macOS 26 起挨得近的玻璃会像液体一样连在一起，拆分时就像一滴水分成几滴。
struct TileGlassContainer<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 26, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
    }
}
