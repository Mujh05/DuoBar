import AppKit

let arguments = CommandLine.arguments

func argument(after flag: String) -> String? {
    guard let index = arguments.firstIndex(of: flag) else { return nil }
    return index + 1 < arguments.count ? arguments[index + 1] : ""
}

if let directory = argument(after: "--render-previews") {
    PreviewRenderer.renderAll(to: URL(fileURLWithPath: directory.isEmpty ? "previews" : directory))
    exit(0)
}

if let directory = argument(after: "--render-app-icon") {
    AppIconRenderer.renderIconSet(to: URL(fileURLWithPath: directory.isEmpty ? "AppIcon.iconset" : directory))
    exit(0)
}

var debugAction: AppDelegate.DebugAction?
if let directory = argument(after: "--debug-snapshot") {
    debugAction = .snapshot(URL(fileURLWithPath: directory.isEmpty ? "snapshots" : directory))
} else if arguments.contains("--report-position") {
    debugAction = .reportPosition
} else if arguments.contains("--debug-wifi") {
    debugAction = .wifiReport
} else if let directory = argument(after: "--debug-update") {
    debugAction = .updateReport(URL(fileURLWithPath: directory.isEmpty ? "updates" : directory))
} else if arguments.contains("--debug-self-update") {
    debugAction = .selfUpdate
}

let app = NSApplication.shared
let delegate = AppDelegate(debugAction: debugAction)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
