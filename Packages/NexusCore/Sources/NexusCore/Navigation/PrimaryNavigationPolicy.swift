import Foundation

/// Primary tab identifiers for the simplified four-tab shell.
public enum PrimaryNavigationPolicy: Sendable {
    public static let tabIdentifiers: [String] = ["dashboard", "calendar", "search", "settings"]

    /// Maps legacy `nexus://projects` deep links to Home after Projects tab removal.
    public static func opensHome(for deepLink: NexusDeepLink) -> Bool {
        switch deepLink {
        case .dashboard, .projects:
            return true
        case .project, .task, .quickAdd, .widgetProjectPicker:
            return false
        }
    }
}
