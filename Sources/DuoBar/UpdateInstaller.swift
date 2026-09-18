import AppKit
import Security

/// 没能自动安装的原因。
enum InstallError: LocalizedError {
    /// DuoBar 所在的位置不能直接替换，只能打开安装包手动拖动。
    case notReplaceable(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case let .notReplaceable(reason), let .failed(reason): reason
        }
    }
}

/// 把下载好的安装包直接装到 DuoBar 现在所在的位置，然后重新打开，不用再手动拖进“应用程序”。
///
/// 安装包挂载在临时目录里，不在 Finder 里显示；新版本也先复制到临时目录，再和旧版本对调。
/// Finder 打开的安装包会被 Spotlight 收录，启动台里就会多出一个 DuoBar，这里都避开了。
enum UpdateInstaller {
    /// 当前 App 的位置；不能原地替换时抛出原因。
    static func replaceableApp() throws -> URL {
        let app = Bundle.main.bundleURL.resolvingSymlinksInPath()
        guard app.pathExtension == "app" else {
            throw InstallError.notReplaceable("DuoBar 不是以 App 的形式运行的")
        }
        // 直接打开“下载”等文件夹里带隔离标记的 App 时，macOS 会把它放到一个只读的临时位置运行。
        if app.path.contains("/AppTranslocation/") {
            throw InstallError.notReplaceable("DuoBar 是从“下载”等文件夹直接打开的，macOS 让它在临时位置运行")
        }
        if (try? app.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly == true {
            throw InstallError.notReplaceable("DuoBar 在只读的磁盘上（比如安装包里）")
        }
        let folder = app.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: folder.path),
              FileManager.default.isWritableFile(atPath: app.path) else {
            throw InstallError.notReplaceable("没有权限替换“\(folder.path)”里的 DuoBar")
        }
        return app
    }

    /// 挂载安装包，核对里面的 App，复制到和当前 App 同一块磁盘上的临时目录，再和当前 App 对调。
    /// 结束后安装包会卸载，旧版本会删掉。
    static func install(_ dmg: URL, version: String, replacing app: URL) async throws {
        try await Task.detached {
            try installNow(dmg, version: version, replacing: app)
        }.value
    }

    /// 等这个进程退出后重新打开 app（对调之后那里已经是新版本），然后退出。
    @MainActor
    static func relaunch(_ app: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 最多等 20 秒。路径作为 $0 传进去，不用处理引号。
        process.arguments = ["-c", """
            i=0; while /bin/kill -0 \(pid) 2>/dev/null && [ $i -lt 100 ]; do /bin/sleep 0.2; i=$((i+1)); done
            /usr/bin/open "$0"
            """, app.path]
        try process.run()
        NSApp.terminate(nil)
    }

    private static func installNow(_ dmg: URL, version: String, replacing app: URL) throws {
        let fileManager = FileManager.default
        let mountPoint = dmg.deletingLastPathComponent().appendingPathComponent("mount", isDirectory: true)
        try fileManager.createDirectory(at: mountPoint, withIntermediateDirectories: true)
        try attach(dmg, at: mountPoint)
        defer { detach(mountPoint) }

        let source = try newApp(in: mountPoint, version: version)
        // 和当前 App 在同一块磁盘上，才能直接对调。
        let staging = try fileManager.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                          appropriateFor: app, create: true)
        defer { try? fileManager.removeItem(at: staging) }
        let staged = staging.appendingPathComponent(app.lastPathComponent)
        try run("/usr/bin/ditto", source.path, staged.path)
        // DuoBar 自己下载的安装包一般没有隔离标记；万一有，去掉它，免得重新打开时被 Gatekeeper 拦下。
        _ = try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", staged.path)

        // 对调后旧版本在 staged 的位置，随临时目录一起删掉。
        try swapItems(staged, app)
    }

    /// 把安装包只读挂载到 mountPoint。nobrowse：不在 Finder 和桌面上显示，Spotlight 也不收录。
    /// macOS 27 上 hdiutil 已不推荐使用，先用 diskutil image；老系统上的 diskutil 不支持这些参数时改用 hdiutil。
    private static func attach(_ dmg: URL, at mountPoint: URL) throws {
        do {
            try run("/usr/sbin/diskutil", "image", "attach", "--readOnly", "--mountOptions", "nobrowse",
                    "--mountPoint", mountPoint.path, dmg.path)
        } catch {
            // 都不行时报告 diskutil 的错误：以后的系统上可能已经没有 hdiutil 了。
            guard (try? run("/usr/bin/hdiutil", "attach", dmg.path, "-nobrowse", "-readonly", "-noautoopen",
                            "-mountpoint", mountPoint.path)) != nil else { throw error }
        }
    }

    /// 卸载安装包，里面的文件还开着也强制卸载；diskutil 卸载不了时改用 hdiutil。
    private static func detach(_ mountPoint: URL) {
        if (try? run("/usr/sbin/diskutil", "eject", "force", mountPoint.path)) == nil {
            _ = try? run("/usr/bin/hdiutil", "detach", mountPoint.path, "-force")
        }
    }

    /// 安装包里的 App：必须是 DuoBar，版本号和发布的一致，签名完整。
    private static func newApp(in folder: URL, version: String) throws -> URL {
        let apps = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        guard let app = apps.first(where: {
            $0.pathExtension == "app" && Bundle(url: $0)?.bundleIdentifier == Bundle.main.bundleIdentifier
        }) else {
            throw InstallError.failed("安装包里没有找到 DuoBar")
        }
        let found = Bundle(url: app)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let found, UpdateChecker.isSameVersion(found, version) else {
            throw InstallError.failed("安装包里是 \(found ?? "未知版本")，不是 \(version)")
        }
        var code: SecStaticCode?
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw InstallError.failed("新版本的签名校验没有通过")
        }
        return app
    }

    /// 把 staged 和 app 对调。APFS 上一步完成；不支持的磁盘先挪开旧版本再放入新版本，失败时挪回去。
    private static func swapItems(_ staged: URL, _ app: URL) throws {
        if renamex_np(staged.path, app.path, UInt32(RENAME_SWAP)) == 0 { return }
        let old = staged.deletingLastPathComponent().appendingPathComponent("Old " + app.lastPathComponent)
        guard rename(app.path, old.path) == 0 else { throw posixFailure("没法挪开旧版本") }
        guard rename(staged.path, app.path) == 0 else {
            let failure = posixFailure("没法放入新版本")
            _ = rename(old.path, app.path)
            throw failure
        }
    }

    private static func posixFailure(_ action: String) -> InstallError {
        let reason = POSIXErrorCode(rawValue: errno).map { POSIXError($0).localizedDescription } ?? "错误 \(errno)"
        return .failed("\(action)：\(reason)")
    }

    /// 运行系统自带的命令行工具，失败时把它的输出带进错误信息。
    @discardableResult
    private static func run(_ tool: String, _ arguments: String...) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // 先读到结尾再等退出，输出多的时候不会卡住。
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw InstallError.failed("\(URL(fileURLWithPath: tool).lastPathComponent) 出错：\(output)")
        }
        return output
    }
}
