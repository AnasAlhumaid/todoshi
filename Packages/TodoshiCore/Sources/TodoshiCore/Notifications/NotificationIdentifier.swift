import Foundation

/// Stable local-notification request identifiers owned by Nexus.
public enum NotificationIdentifier: Sendable {
    public static let taskReminderPrefix = "nexus.task."
    public static let dailySummary = "nexus.dailySummary"

    public static func taskReminder(taskID: UUID) -> String {
        "\(taskReminderPrefix)\(taskID.uuidString)"
    }

    public static func taskID(from identifier: String) -> UUID? {
        guard identifier.hasPrefix(taskReminderPrefix) else { return nil }
        let raw = String(identifier.dropFirst(taskReminderPrefix.count))
        return UUID(uuidString: raw)
    }

    public static func isNexusOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(taskReminderPrefix) || identifier == dailySummary
    }
}
