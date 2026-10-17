import Foundation
import Security

enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
}

struct KeychainStore {
    let service: String
    let account: String

    func read() -> String? {
        var result: AnyObject?
        let status = SecItemCopyMatching(readQuery() as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func write(_ value: String) throws {
        delete()
        var item = baseQuery()
        item[kSecValueData as String] = Data(value.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readQuery() -> [String: Any] {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        return query
    }
}
