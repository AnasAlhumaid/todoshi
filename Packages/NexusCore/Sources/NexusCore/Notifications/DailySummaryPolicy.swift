import Foundation

/// Pure daily-summary scheduling preferences + content building.
public struct DailySummaryPreferences: Equatable, Sendable {
    public var isEnabled: Bool
    public var hour: Int
    public var minute: Int

    public static let defaultHour = 9
    public static let defaultMinute = 0

    public init(isEnabled: Bool = false, hour: Int = defaultHour, minute: Int = defaultMinute) {
        self.isEnabled = isEnabled
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }
}

public struct DailySummaryCounts: Equatable, Sendable {
    public let dueToday: Int
    public let overdue: Int
    public let highPriority: Int

    public init(dueToday: Int, overdue: Int, highPriority: Int) {
        self.dueToday = dueToday
        self.overdue = overdue
        self.highPriority = highPriority
    }

    public var hasContent: Bool {
        dueToday > 0 || overdue > 0 || highPriority > 0
    }

    public var totalRelevant: Int {
        dueToday + overdue + highPriority
    }
}

public struct DailySummaryContent: Equatable, Sendable {
    public let title: String
    public let body: String
    public let deepLinkURL: URL

    public init(title: String, body: String, deepLinkURL: URL) {
        self.title = title
        self.body = body
        self.deepLinkURL = deepLinkURL
    }
}

public struct DailySummaryScheduleRequest: Equatable, Sendable {
    public let fireDate: Date
    public let content: DailySummaryContent

    public var identifier: String { NotificationIdentifier.dailySummary }
}

public enum DailySummaryPolicy: Sendable {
    public static var title: String { NexusL10n.tr("notification.title") }

    /// Next local wall-clock occurrence at `hour`:`minute` strictly after `now`.
    public static func nextFireDate(
        hour: Int,
        minute: Int,
        after now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = minute
        components.second = 0
        if let today = calendar.date(from: components), today > now {
            return today
        }
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            ?? now.addingTimeInterval(86_400)
        var tomorrow = calendar.dateComponents([.year, .month, .day], from: tomorrowStart)
        tomorrow.hour = hour
        tomorrow.minute = minute
        tomorrow.second = 0
        return calendar.date(from: tomorrow) ?? now.addingTimeInterval(86_400)
    }

    public static func counts(
        tasks: [DashboardTaskInput],
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> DailySummaryCounts {
        let openActiveRoots = tasks.filter {
            $0.isRoot && $0.projectIsActive && $0.status != .done
        }
        let dueToday = openActiveRoots.filter {
            TaskPredicates.isDueToday($0.dueDate, status: $0.status, calendar: calendar, now: now)
        }.count
        let overdue = openActiveRoots.filter {
            TaskPredicates.isOverdue($0.dueDate, status: $0.status, calendar: calendar, now: now)
        }.count
        let highPriority = openActiveRoots.filter {
            $0.priority == .high || $0.priority == .urgent
        }.count
        return DailySummaryCounts(dueToday: dueToday, overdue: overdue, highPriority: highPriority)
    }

    /// Count-only body; never includes task titles.
    public static func content(
        for counts: DailySummaryCounts,
        locale: Locale = .autoupdatingCurrent
    ) -> DailySummaryContent {
        var parts: [String] = []
        if counts.dueToday > 0 {
            parts.append(NexusL10n.plural("summary.due_today", count: counts.dueToday, locale: locale))
        }
        if counts.overdue > 0 {
            parts.append(NexusL10n.plural("summary.overdue", count: counts.overdue, locale: locale))
        }
        if counts.highPriority > 0 && counts.dueToday == 0 && counts.overdue == 0 {
            parts.append(NexusL10n.plural("summary.high_priority_only", count: counts.highPriority, locale: locale))
        } else if counts.highPriority > 0 {
            parts.append(NexusL10n.plural("summary.high_priority_short", count: counts.highPriority, locale: locale))
        }
        let body = parts.isEmpty
            ? NexusL10n.tr("summary.allCaughtUp", locale: locale)
            : parts.joined(separator: " · ")
        return DailySummaryContent(
            title: NexusL10n.tr("notification.title", locale: locale),
            body: body,
            deepLinkURL: NexusDeepLink.dashboard.url
        )
    }

    /// Schedules next concrete trigger during reconciliation.
    /// Empty days are skipped (no summary request) when counts report no relevant open work.
    public static func scheduleRequest(
        preferences: DailySummaryPreferences,
        tasks: [DashboardTaskInput],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> DailySummaryScheduleRequest? {
        guard preferences.isEnabled else { return nil }
        let summaryCounts = counts(tasks: tasks, calendar: calendar, now: now)
        guard summaryCounts.hasContent else { return nil }
        let fire = nextFireDate(
            hour: preferences.hour,
            minute: preferences.minute,
            after: now,
            calendar: calendar
        )
        return DailySummaryScheduleRequest(
            fireDate: fire,
            content: content(for: summaryCounts)
        )
    }
}
