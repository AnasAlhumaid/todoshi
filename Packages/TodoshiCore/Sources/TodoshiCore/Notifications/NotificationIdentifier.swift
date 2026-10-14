import Foundation

/// Stable local-notification request identifiers owned by Todoshi.
public enum NotificationIdentifier: Sendable {
    public static let taskReminderPrefix = "todoshi.task."
    public static let dailySummary = "todoshi.dailySummary"

    /// Legacy prefix retained for cancellation/reconciliation compatibility.
    public static let legacyTaskReminderPrefix = "nexus.task."
    public static let legacyDailySummary = "nexus.dailySummary"

    public static func taskReminder(taskID: UUID) -> String {
        "\(taskReminderPrefix)\(taskID.uuidString)"
    }

    public static func legacyTaskReminder(taskID: UUID) -> String {
        "\(legacyTaskReminderPrefix)\(taskID.uuidString)"
    }

    /// Request identifiers to cancel when replacing or removing a task reminder.
    public static func taskReminderCancellationIDs(taskID: UUID) -> [String] {
        [taskReminder(taskID: taskID), legacyTaskReminder(taskID: taskID)]
    }

    public static func taskID(from identifier: String) -> UUID? {
        for prefix in [taskReminderPrefix, legacyTaskReminderPrefix] {
            guard identifier.hasPrefix(prefix) else { continue }
            let raw = String(identifier.dropFirst(prefix.count))
            if let id = UUID(uuidString: raw) { return id }
        }
        return nil
    }

    public static func isTodoshiOwned(_ identifier: String) -> Bool {
        identifier.hasPrefix(taskReminderPrefix)
            || identifier == dailySummary
            || identifier.hasPrefix(legacyTaskReminderPrefix)
            || identifier == legacyDailySummary
    }
}
