import Foundation

public enum AppGroupConstants: Sendable {
    /// Shared suite used by the main app and widget extension.
    public static let suiteName = "group.com.anashamad.Todoshi"

    /// Legacy App Group identifier retained for one-time migration from pre-Todoshi builds.
    public static let legacySuiteName = "group.com.anashamad.Nexus"

    public static let storeFileName = "Todoshi.store"

    /// Legacy store filename inside the legacy App Group container.
    public static let legacyStoreFileName = "Nexus.store"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    public static var legacyContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: legacySuiteName)
    }

    public static var storeURL: URL? {
        containerURL?.appendingPathComponent(storeFileName)
    }

    public static var legacyStoreURL: URL? {
        legacyContainerURL?.appendingPathComponent(legacyStoreFileName)
    }
}
