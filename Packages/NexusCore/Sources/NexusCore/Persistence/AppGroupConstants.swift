import Foundation

public enum AppGroupConstants: Sendable {
    /// Shared suite used by the main app and future widget extension.
    public static let suiteName = "group.com.anashamad.Nexus"

    public static let storeFileName = "Nexus.store"

    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
    }

    public static var storeURL: URL? {
        containerURL?.appendingPathComponent(storeFileName)
    }
}
