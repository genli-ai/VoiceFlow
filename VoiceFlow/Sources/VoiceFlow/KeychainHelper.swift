import Foundation
import Security

/// 把 OpenAI API Key 存在系统钥匙串里（不落明文文件）
enum KeychainHelper {
    private static let service = "com.ligen.voiceflow"

    /// 不传 account 时默认操作"当前选中的服务商"的 Key
    static func saveAPIKey(_ value: String, account: String? = nil) {
        let acct = account ?? Settings.shared.llmProvider.keychainAccount
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        deleteAPIKey(account: acct)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func loadAPIKey(account: String? = nil) -> String? {
        let acct = account ?? Settings.shared.llmProvider.keychainAccount
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        let key = String(data: data, encoding: .utf8)
        return (key?.isEmpty == false) ? key : nil
    }

    static func deleteAPIKey(account: String? = nil) {
        let acct = account ?? Settings.shared.llmProvider.keychainAccount
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: acct,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
