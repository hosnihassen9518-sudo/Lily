import Foundation
import Security
import CryptoKit
import WidgetKit
import Darwin

struct LilyWidgetDevice: Codable, Identifiable {
    let id: Int
    let generation: Int?
    let name: String
    let status: String
    let online: Bool
    let enabled: Bool?
    let can_control: Bool
}
struct LilyWidgetSnapshot: Codable {
    var devices: [LilyWidgetDevice]
    var updated_at: String?
    var message: String?
    var context_id: String?
    static var empty: LilyWidgetSnapshot { .init(devices: [], message: "Open Lily to sign in or add a device.") }
}
struct LilyWidgetConfig: Codable {
    let backend_url: String
    let token: String
    let expires_at: String
    var identity: String {
        SHA256.hash(data: Data((backend_url + "|" + token).utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var expired: Bool {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = fractional.date(from: expires_at) ?? ISO8601DateFormatter().date(from: expires_at)
        return date == nil || date! <= Date()
    }
}

enum LilyWidgetStore {
    static var group: String { Bundle.main.object(forInfoDictionaryKey: "LilyWidgetAppGroup") as? String ?? "group.com.example.lilyMobile" }
    static var keychainGroup: String { Bundle.main.object(forInfoDictionaryKey: "LilyWidgetKeychainGroup") as? String ?? "" }
    static var available: Bool { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil }
    private static var defaults: UserDefaults? { available ? UserDefaults(suiteName: group) : nil }
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "LilyWidget",
         kSecAttrAccount as String: "delegated-session", kSecAttrAccessGroup as String: keychainGroup]
    }
    // Runner and the extension are separate processes. Protect both credential
    // and snapshot transitions with the same App Group file lock.
    private static func locked<T>(_ action: () throws -> T) throws -> T {
        guard let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { throw NSError(domain: "LilyWidgets", code: 3) }
        let fd = open(directory.appendingPathComponent("widget.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NSError(domain: "LilyWidgets", code: 4) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw NSError(domain: "LilyWidgets", code: 5) }
        defer { flock(fd, LOCK_UN) }
        return try action()
    }
    private static func rawConfig() -> LilyWidgetConfig? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(LilyWidgetConfig.self, from: data)
    }
    static func config() -> LilyWidgetConfig? { try? locked { rawConfig() } }
    private static func rawSnapshot() -> LilyWidgetSnapshot {
        guard let data = defaults?.data(forKey: "snapshot"),
              let value = try? JSONDecoder().decode(LilyWidgetSnapshot.self, from: data) else { return .empty }
        return value
    }
    static func snapshot() -> LilyWidgetSnapshot {
        (try? locked {
            guard let config = rawConfig() else { return LilyWidgetSnapshot.empty }
            let value = rawSnapshot()
            return value.context_id == config.identity ? value : .empty
        }) ?? .empty
    }
    static func configure(_ data: [String: Any]) throws {
        guard available else { throw NSError(domain: "LilyWidgets", code: 1) }
        let config = try JSONDecoder().decode(LilyWidgetConfig.self, from: JSONSerialization.data(withJSONObject: data))
        var snapshot = try JSONDecoder().decode(LilyWidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: data["snapshot"] as Any))
        let bytes = try JSONEncoder().encode(config)
        snapshot.context_id = config.identity
        let publicData = try JSONEncoder().encode(snapshot)
        try locked {
            let attributes: [String: Any] = [kSecValueData as String: bytes, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
            let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var q = query
                attributes.forEach { q[$0.key] = $0.value }
                guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw NSError(domain: "LilyWidgets", code: 2) }
            } else if status != errSecSuccess { throw NSError(domain: "LilyWidgets", code: Int(status)) }
            defaults?.set(publicData, forKey: "snapshot")
        }
    }
    static func save(_ value: LilyWidgetSnapshot, expected: String? = nil) {
        try? locked {
            guard let config = rawConfig(), expected == nil || expected == config.identity else { return }
            var copy = value
            copy.context_id = config.identity
            if let data = try? JSONEncoder().encode(copy) { defaults?.set(data, forKey: "snapshot") }
        }
    }
    static func message(_ text: String, expected: String) {
        try? locked {
            guard rawConfig()?.identity == expected else { return }
            var value = rawSnapshot()
            value.message = text
            if let data = try? JSONEncoder().encode(value) { defaults?.set(data, forKey: "snapshot") }
        }
    }
    static func clear(expected: String? = nil) {
        try? locked {
            guard expected == nil || rawConfig()?.identity == expected else { return }
            SecItemDelete(query as CFDictionary)
            defaults?.removeObject(forKey: "snapshot")
        }
    }
    static func reload() {
        if #available(iOS 14.0, *) { WidgetCenter.shared.reloadTimelines(ofKind: "LilyDevices") }
    }
}
