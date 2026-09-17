import AppKit
import SwiftUI

/// `DuoBar --render-previews <目录>`：把各种状态画成 PNG，方便调整图标时对照。
@MainActor
enum PreviewRenderer {
    // MARK: - 示例数据

    static func battery(_ percent: Int, _ power: PowerState, hasBattery: Bool = true,
                        lowPower: Bool = false, colorful: Bool = false) -> IconPart {
        let info = BatteryInfo(
            hasBattery: hasBattery, percent: percent, power: power, isCharged: percent == 100,
            minutesToEmpty: 200, minutesToFull: 40, lowPowerMode: lowPower
        )
        return IconPart(kind: .battery, reading: .battery(info), tint: colorful ? info.tint(chargingGreen: true) : nil)
    }

    static func network(_ link: LinkKind, rssi: Int = -50, powered: Bool = true) -> IconPart {
        var info = NetworkInfo.placeholder
        info.link = link
        info.hasWiFiHardware = true
        info.wifiPowered = powered
        info.wifiAssociated = powered && (link == .wifi || link == .hotspot)
        info.rssi = info.wifiAssociated ? rssi : nil
        return IconPart(kind: .network, reading: .network(info))
    }

    static func part(_ kind: MetricKind, _ reading: MetricReading) -> IconPart {
        IconPart(kind: kind, reading: reading)
    }

    static func meter(_ part: IconPart) -> DotsPart {
        .meter(part)
    }

    /// 独立指示灯：nil 表示空着的圆点。
    static func lights(_ items: [(IndicatorKind, Bool)?]) -> DotsPart {
        DotsPart(lights: items.map { item in
            item.map { DotLight(on: $0.1, tint: $0.0.tint, indicator: $0.0) }
        }, metric: nil)
    }

    static let samples: [(String, IconState)] = [
        ("默认：电量·网络·CPU", IconState(ring: battery(76, .battery), center: network(.wifi), dots: meter(part(.cpu, .cpu(0.34))))),
        ("充电·信号3格·CPU满载", IconState(ring: battery(45, .charging), center: network(.wifi, rssi: -60),
                                     dots: meter(part(.cpu, .cpu(0.92))))),
        ("彩色：低电量红", IconState(ring: battery(12, .battery, colorful: true), center: network(.wifi),
                                dots: meter(part(.cpu, .cpu(0.34))))),
        ("彩色：省电黄+充电", IconState(ring: battery(45, .charging, lowPower: true, colorful: true),
                                  center: network(.wifi), dots: meter(part(.cpu, .cpu(0.2))))),
        ("彩色：接电源绿", IconState(ring: battery(100, .pluggedIn, colorful: true), center: network(.ethernet),
                                dots: meter(part(.throughput, .throughput(ThroughputSample(upload: 300_000, download: 2_000_000)))))),
        ("独立指示灯（彩色）", IconState(ring: battery(76, .battery), center: network(.wifi),
                                  dots: lights([(.wifi, true), (.bluetooth, true), (.vpn, false), (.microphone, true)]))),
        ("指示灯·有空位·电量数字", IconState(ring: part(.cpu, .cpu(0.4)), center: battery(18, .battery, colorful: true),
                                     dots: lights([(.muted, true), nil, (.capsLock, false), (.headphones, true)]))),
        ("CPU·内存数字·电量", IconState(ring: part(.cpu, .cpu(0.63)),
                                   center: part(.memory, .memory(MemorySample(used: 37_800_000_000, total: 68_719_476_736, pressure: 1))),
                                   dots: meter(battery(30, .battery)))),
        ("磁盘·音量·GPU", IconState(ring: part(.disk, .disk(DiskSample(total: 2_000_000_000_000, available: 1_600_000_000_000))),
                                center: part(.volume, .volume(AudioSample(level: 0.6, muted: false, deviceName: nil, bluetoothOutput: false))),
                                dots: meter(part(.gpu, .gpu(0.12))))),
        ("不显示外圈·网速", IconState(ring: nil,
                                 center: part(.throughput, .throughput(ThroughputSample(upload: 200_000, download: 1_000_000))),
                                 dots: meter(network(.wifi)))),
        ("不显示圆点", IconState(ring: battery(60, .battery), center: network(.wifi), dots: nil)),
        ("外设未连接·Wi-Fi关", IconState(ring: part(.accessory, .accessories([])), center: network(.none, powered: false),
                                   dots: meter(part(.cpu, .cpu(0.05))))),
        ("台式机·以太网·GPU", IconState(ring: battery(100, .pluggedIn, hasBattery: false), center: network(.ethernet),
                                   dots: meter(part(.gpu, .gpu(0.8))))),
    ]

    /// 不同图标大小放进两种高度的菜单栏（外接显示器常见的 24 点、刘海屏的 33 点），超出部分按实际情况裁掉。
    static func scaleSheet() -> NSBitmapImageRep {
        let scales: [CGFloat] = [0.7, 0.85, 1, 1.15, 1.3, 1.5]
        let bars: [CGFloat] = [24, 33]
        let columnWidth: CGFloat = 96
        let size = CGSize(width: 110 + columnWidth * CGFloat(scales.count), height: 40 + CGFloat(bars.count) * 2 * 52)
        let state = samples[1].1
        return bitmap(size: size, scale: 2) { cg in
            NSColor.white.setFill()
            CGRect(origin: .zero, size: size).fill()
            let font = NSFont.systemFont(ofSize: 12)
            for (index, scale) in scales.enumerated() {
                ("\(Int((scale * 100).rounded()))%" as NSString)
                    .draw(at: CGPoint(x: 110 + CGFloat(index) * columnWidth + 30, y: 12), withAttributes: [.font: font])
            }
            var y: CGFloat = 40
            for bar in bars {
                for dark in [false, true] {
                    ("菜单栏 \(Int(bar)) 点" as NSString).draw(at: CGPoint(x: 10, y: y + bar / 2 - 8), withAttributes: [.font: font])
                    for (index, scale) in scales.enumerated() {
                        let strip = CGRect(x: 110 + CGFloat(index) * columnWidth, y: y, width: columnWidth - 10, height: bar)
                        (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
                        strip.fill()
                        let icon = MenuBarIcon.image(for: state, scale: scale)
                        let rect = CGRect(x: strip.midX - icon.size.width / 2, y: strip.midY - icon.size.height / 2,
                                          width: icon.size.width, height: icon.size.height)
                        cg.saveGState()
                        cg.clip(to: strip)
                        drawIcon(icon, in: rect, dark: dark)
                        cg.restoreGState()
                    }
                    y += 52
                }
            }
        }
    }

    static func renderAll(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        write(iconSheet(), to: directory.appendingPathComponent("icons.png"))
        write(percentTransitionSheet(), to: directory.appendingPathComponent("percent-transition.png"))
        write(scaleSheet(), to: directory.appendingPathComponent("scales.png"))
        render(splitSheet(), to: directory.appendingPathComponent("split.png"))

        // 面板用本机的真实数据，等网络状态回调先到。
        let model = AppModel()
        model.start()
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        render(panelSheet(model), to: directory.appendingPathComponent("panel.png"))
        print("previews written to \(directory.path)")
    }

    // MARK: - 拆分动画逐帧

    static func splitSheet() -> some View {
        let frames: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        return HStack(alignment: .top, spacing: 16) {
            frameColumn(frames, samples[3].1, dark: false)
            frameColumn(frames, samples[5].1, dark: false)
            frameColumn(frames, samples[6].1, dark: true)
        }
        .padding(16)
        .background(Color.white)
    }

    private static func frameColumn(_ frames: [CGFloat], _ state: IconState, dark: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(frames, id: \.self) { progress in
                VStack(spacing: 2) {
                    Text("progress \(progress, specifier: "%.1f")")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    SplitGlyphView(progress: progress, state: state)
                        .frame(width: 288, height: 76)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(dark ? Color(white: 0.16) : Color(white: 0.95)))
            }
        }
        .environment(\.colorScheme, dark ? .dark : .light)
    }

    // MARK: - 面板

    static func panelSheet(_ model: AppModel) -> some View {
        HStack(alignment: .top, spacing: 20) {
            ForEach([false, true], id: \.self) { dark in
                PanelView(model: model, previewSplit: true)
                    .background(RoundedRectangle(cornerRadius: 12).fill(dark ? Color(white: 0.17) : Color(white: 0.97)))
                    .environment(\.colorScheme, dark ? .dark : .light)
            }
        }
        .padding(20)
        .background(Color(white: 0.8))
    }

    static func render(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { return }
        write(NSBitmapImageRep(cgImage: image), to: url)
    }

    // MARK: - 菜单栏图标

    static func iconSheet() -> NSBitmapImageRep {
        let rowHeight: CGFloat = 104
        let size = CGSize(width: 720, height: rowHeight * CGFloat(samples.count + 3) + 16)
        return bitmap(size: size, scale: 2) { cg in
            NSColor.white.setFill()
            CGRect(origin: .zero, size: size).fill()

            // 第一行：和系统自带的 Wi-Fi、电池图标放在一起比大小。
            let wifi = SymbolCache.image("wifi", height: 15).map { templateCopy($0) }
            let battery = SymbolCache.image("battery.75percent", height: 15).map { templateCopy($0) }
            drawRow(y: 8, label: "对比：系统图标", icon: MenuBarIcon.image(for: samples[1].1), extras: [wifi, battery].compactMap { $0 })

            drawRow(y: 8 + rowHeight, label: "圆环顶部电量百分比",
                    icon: MenuBarIcon.image(for: samples[0].1, embeddedPercent: 50,
                                            embeddedPercentProgress: 1), extras: [])
            drawRow(y: 8 + rowHeight * 2, label: "圆环顶部三位数",
                    icon: MenuBarIcon.image(for: samples[0].1, embeddedPercent: 100,
                                            embeddedPercentProgress: 1), extras: [])

            for (index, sample) in samples.enumerated() {
                drawRow(y: 8 + rowHeight * CGFloat(index + 3), label: sample.0,
                        icon: MenuBarIcon.image(for: sample.1), extras: [])
            }
        }
    }

    /// “左侧文字 → 圆环顶部”切换过程的关键帧。
    static func percentTransitionSheet() -> NSBitmapImageRep {
        let state = samples[0].1
        let frames: [CGFloat] = [0, 0.2, 0.4, 0.6, 0.8, 1]
        let size = CGSize(width: 520, height: 120)
        return bitmap(size: size, scale: 2) { _ in
            NSColor.white.setFill()
            CGRect(origin: .zero, size: size).fill()
            let labelFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            for (index, progress) in frames.enumerated() {
                let x = 28 + CGFloat(index) * 80
                let icon = MenuBarIcon.image(for: state, embeddedPercent: 50,
                                             embeddedPercentProgress: progress)
                drawIcon(icon, in: CGRect(x: x, y: 28, width: 60, height: 66), dark: false)
                (String(format: "%.1f", progress) as NSString).draw(
                    at: CGPoint(x: x + 20, y: 98),
                    withAttributes: [.font: labelFont, .foregroundColor: NSColor.secondaryLabelColor]
                )
            }
        }
    }

    private static func templateCopy(_ image: NSImage) -> NSImage {
        let copy = image.copy() as! NSImage
        copy.isTemplate = true
        return copy
    }

    private static func drawRow(y: CGFloat, label: String, icon: NSImage, extras: [NSImage]) {
        let font = NSFont.systemFont(ofSize: 13)
        (label as NSString).draw(at: CGPoint(x: 12, y: y + 38), withAttributes: [.font: font, .foregroundColor: NSColor.black])

        // 浅色和深色菜单栏各一条，图标按实际大小画。
        for (index, dark) in [false, true].enumerated() {
            let strip = CGRect(x: 170 + CGFloat(index) * 150, y: y + 30, width: 136, height: 32)
            (dark ? NSColor(white: 0.14, alpha: 1) : NSColor(white: 0.93, alpha: 1)).setFill()
            NSBezierPath(roundedRect: strip, xRadius: 6, yRadius: 6).fill()
            var x = strip.minX + 12
            for image in [icon] + extras {
                let rect = CGRect(x: x, y: strip.midY - image.size.height / 2, width: image.size.width, height: image.size.height)
                drawIcon(image, in: rect, dark: dark)
                x += image.size.width + 14
            }
        }

        // 放大 4 倍看细节。
        let big = CGRect(x: 480, y: y, width: icon.size.width * 4, height: icon.size.height * 4)
        NSColor(white: 0.93, alpha: 1).setFill()
        NSBezierPath(roundedRect: big.insetBy(dx: -6, dy: -4), xRadius: 8, yRadius: 8).fill()
        drawIcon(icon, in: big, dark: false)

        let bigDark = big.offsetBy(dx: big.width + 30, dy: 0)
        NSColor(white: 0.14, alpha: 1).setFill()
        NSBezierPath(roundedRect: bigDark.insetBy(dx: -6, dy: -4), xRadius: 8, yRadius: 8).fill()
        drawIcon(icon, in: bigDark, dark: true)
    }

    /// 模板图像按菜单栏深浅染成黑或白；彩色图像在对应外观下自己选颜色。
    private static func drawIcon(_ image: NSImage, in rect: CGRect, dark: Bool) {
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            let source = image.isTemplate ? tinted(image, dark ? .white : .black) : image
            source.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        }
    }

    static func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { rect in
            image.draw(in: rect)
            color.set()
            rect.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: - 工具

    static func bitmap(size: CGSize, scale: CGFloat, draw: (CGContext) -> Void) -> NSBitmapImageRep {
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )!
        rep.size = size
        let context = NSGraphicsContext(bitmapImageRep: rep)!
        let cg = context.cgContext
        cg.translateBy(x: 0, y: size.height)
        cg.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
        draw(cg)
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func write(_ rep: NSBitmapImageRep, to url: URL) {
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        try? data.write(to: url)
    }
}
