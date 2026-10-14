import Foundation

/// UserDefaults-backed daily summary configuration.
public enum DailySummaryStore {
    public static let enabledKey = "todoshi.dailySummary.enabled"
    public static let hourKey = "todoshi.dailySummary.hour"
    public static let minuteKey = "todoshi.dailySummary.minute"

    public static func load(from defaults: UserDefaults = .standard) -> DailySummaryPreferences {
        DailySummaryPreferences(
            isEnabled: defaults.bool(forKey: enabledKey),
            hour: defaults.object(forKey: hourKey) as? Int ?? DailySummaryPreferences.defaultHour,
            minute: defaults.object(forKey: minuteKey) as? Int ?? DailySummaryPreferences.defaultMinute
        )
    }

    public static func save(_ preferences: DailySummaryPreferences, to defaults: UserDefaults = .standard) {
        defaults.set(preferences.isEnabled, forKey: enabledKey)
        defaults.set(preferences.hour, forKey: hourKey)
        defaults.set(preferences.minute, forKey: minuteKey)
    }
}

/// Authorization snapshot without UserNotifications types (for UI + tests).
public enum NotificationAuthorizationState: String, Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
    case unknown
}

public enum NotificationUserInfoKey {
    public static let deepLink = "todoshiDeepLink"
    /// Legacy notification payload key for pending notifications from pre-Todoshi builds.
    public static let legacyDeepLink = "nexusDeepLink"
    public static let taskID = "taskID"
}

public enum NotificationCategoryIdentifier {
    public static let taskReminder = "TODOSHI_TASK_REMINDER"
    public static let dailySummary = "TODOSHI_DAILY_SUMMARY"
}
