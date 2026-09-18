import CryptoKit
import Foundation

/// GitHub 上的一个发布版本。
struct ReleaseInfo: Sendable, Equatable {
    var version: String
    var pageURL: URL
    var dmgURL: URL?
    var dmgName: String?
    /// 发布说明里写的安装包 SHA-256，用来校验下载的文件。
    var sha256: String?
}

enum UpdateError: LocalizedError {
    case badResponse(Int)
    case noAsset
    case checksumMismatch

    var errorDescription: String? {
        switch self {
        case let .badResponse(code): "GitHub 返回了错误（\(code)）"
        case .noAsset: "这个版本没有可下载的安装包"
        case .checksumMismatch: "下载的文件和发布说明里的 SHA-256 不一致，已删除"
        }
    }
}

/// 通过 GitHub Releases 检查和下载新版本。只请求公开的发布信息，不发送任何个人数据。
enum UpdateChecker {
    static let repository = "Mujh05/DuoBar"
    static let releasesPage = URL(string: "https://github.com/\(repository)/releases")!

    static var currentVersion: String {
        // 调试用：假装是旧版本，用来检查更新提示的界面。
        ProcessInfo.processInfo.environment["DUOBAR_PRETEND_VERSION"]
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 最新版本的接口。调试时可以用 DUOBAR_UPDATE_API 指向本地的假数据，测试完整的更新过程。
    private static var latestReleaseAPI: URL {
        ProcessInfo.processInfo.environment["DUOBAR_UPDATE_API"].flatMap(URL.init(string:))
            ?? URL(string: "https://api.github.com/repos/\(repository)/releases/latest")!
    }

    static func latestRelease() async throws -> ReleaseInfo {
        var request = URLRequest(url: latestReleaseAPI)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DuoBar/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else { throw UpdateError.badResponse(status) }

        struct Payload: Decodable {
            struct Asset: Decodable {
                var name: String
                var browser_download_url: URL
            }
            var tag_name: String
            var html_url: URL
            var body: String?
            var assets: [Asset]
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let dmg = payload.assets.first { $0.name.hasSuffix(".dmg") && $0.name.contains(architecture) }
            ?? payload.assets.first { $0.name.hasSuffix(".dmg") }
        return ReleaseInfo(
            version: payload.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "vV")),
            pageURL: payload.html_url,
            dmgURL: dmg?.browser_download_url,
            dmgName: dmg?.name,
            sha256: payload.body.flatMap(checksum(in:))
        )
    }

    /// 按数字逐段比较版本号，“1.10” 比 “1.9” 新。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        func parts(_ version: String) -> [Int] {
            version.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = parts(candidate), b = parts(current)
        for index in 0 ..< max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0
            let y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// 按数字比较是不是同一个版本，“1.2” 和 “1.2.0” 算同一个。
    static func isSameVersion(_ a: String, _ b: String) -> Bool {
        !isNewer(a, than: b) && !isNewer(b, than: a)
    }

    /// 把安装包下载到 directory；发布说明里有 SHA-256 时先校验。
    static func download(_ release: ReleaseInfo, to directory: URL) async throws -> URL {
        guard let source = release.dmgURL else { throw UpdateError.noAsset }
        let (temporary, response) = try await URLSession.shared.download(from: source)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            try? FileManager.default.removeItem(at: temporary)
            throw UpdateError.badResponse(status)
        }

        if let expected = release.sha256 {
            let digest = try SHA256.hash(data: Data(contentsOf: temporary, options: .mappedIfSafe))
                .map { String(format: "%02x", $0) }.joined()
            guard digest == expected.lowercased() else {
                try? FileManager.default.removeItem(at: temporary)
                throw UpdateError.checksumMismatch
            }
        }

        let destination = uniqueURL(in: directory, name: release.dmgName ?? source.lastPathComponent)
        try FileManager.default.moveItem(at: temporary, to: destination)
        return destination
    }

    /// 把文件挪进“下载”文件夹，自动安装不成功时留给用户手动安装。
    static func moveToDownloads(_ file: URL) throws -> URL {
        let folder = try FileManager.default.url(for: .downloadsDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
        let destination = uniqueURL(in: folder, name: file.lastPathComponent)
        try FileManager.default.moveItem(at: file, to: destination)
        return destination
    }

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #else
            "x86_64"
        #endif
    }

    private static func checksum(in notes: String) -> String? {
        guard let range = notes.range(of: #"SHA-256:\s*`?([0-9a-fA-F]{64})"#, options: .regularExpression) else {
            return nil
        }
        return String(notes[range].suffix(64))
    }

    /// 同名文件已存在时加上 “ 2”“ 3”。
    private static func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(base) \(index)").appendingPathExtension(ext)
            index += 1
        }
        return candidate
    }
}
