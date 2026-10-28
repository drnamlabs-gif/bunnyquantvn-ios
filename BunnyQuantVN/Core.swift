// Dr. Nam H. Le. drnamlabs.com, bunnyquant.com
import Foundation
import Security

/// Lưu chuỗi nhỏ trong Keychain (khóa phiên, key App Attest). Không bao giờ dùng UserDefaults cho token.
enum Keychain {
    private static func query(_ key: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.bunnyquant.vn", kSecAttrAccount as String: key]
    }

    static func get(_ key: String) -> Data? {
        var q = query(key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        return SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess ? out as? Data : nil
    }

    static func set(_ key: String, _ data: Data?) {
        SecItemDelete(query(key) as CFDictionary)
        guard let data else { return }
        var q = query(key)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(q as CFDictionary, nil)
    }
}
