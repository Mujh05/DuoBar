import Foundation
import Security

/// 记住在 DuoBar 里输过的 Wi-Fi 密码，下次加入同一个网络就不用再问。
///
/// macOS 不让普通 App 读取系统保存的 Wi-Fi 密码（不带密码加入会被拒绝：kCWInvalidParameterErr），
/// 所以 DuoBar 把用户输入的密码单独存进用户的钥匙串。实测钥匙串不会按签名隔离这些条目（ad-hoc 和自签名证书都一样），
/// 同一台 Mac 上的其他程序也能读到，所以只在用户勾选“记住密码”时才存。
/// 读取时不允许弹出钥匙串授权框：DuoBar 更新后签名会变，旧条目读不到就当没存过，重新问一次并覆盖。
enum WiFiPasswords {
    private static let service = "DuoBar Wi-Fi"

    static func password(for ssid: String) -> String? {
        var query = baseQuery(ssid)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        // 需要用户点“允许”的条目直接跳过，不弹钥匙串授权框。
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUISkip
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, let password = String(data: data, encoding: .utf8), !password.isEmpty
        else { return nil }
        return password
    }

    static func save(_ password: String, for ssid: String) {
        let data = Data(password.utf8)
        let query = baseQuery(ssid)
        let update = [kSecValueData as String: data]
        if SecItemUpdate(query as CFDictionary, update as CFDictionary) == errSecSuccess { return }
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrLabel as String] = "DuoBar：\(ssid) 的 Wi-Fi 密码"
        SecItemAdd(item as CFDictionary, nil)
    }

    static func forget(_ ssid: String) {
        SecItemDelete(baseQuery(ssid) as CFDictionary)
    }

    /// 记住了密码的网络名称。
    static func storedSSIDs() -> [String] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUISkip,
        ]
        query[kSecReturnData as String] = false
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let entries = items as? [[String: Any]] else { return [] }
        return entries.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    static func forgetAll() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ] as CFDictionary)
    }

    private static func baseQuery(_ ssid: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: ssid,
        ]
    }
}
