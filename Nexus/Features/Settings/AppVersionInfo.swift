import Foundation

/// App version presentation (marketing + build) for Settings About.
public enum AppVersionInfo: Sendable {
    public static var marketingVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }

    public static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    public static var displayVersion: String {
        "\(marketingVersion) (\(buildNumber))"
    }
}
