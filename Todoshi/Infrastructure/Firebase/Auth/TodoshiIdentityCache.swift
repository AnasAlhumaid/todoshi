import Foundation
import TodoshiCore

enum TodoshiIdentityCache {
    private static let keyPrefix = "todoshi.identity."

    private static func key(for uid: String) -> String {
        "\(keyPrefix)\(uid)"
    }

    static func stored(for uid: String) -> String? {
        guard let raw = UserDefaults.standard.string(forKey: key(for: uid)) else { return nil }
        return TodoshiIdentityProvisioningPolicy.normalized(raw)
    }

    static func store(_ id: String, for uid: String) {
        guard let normalized = TodoshiIdentityProvisioningPolicy.normalized(id) else { return }
        UserDefaults.standard.set(normalized, forKey: key(for: uid))
    }

    static func clear(for uid: String) {
        UserDefaults.standard.removeObject(forKey: key(for: uid))
    }

    static func clearAll() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(keyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
