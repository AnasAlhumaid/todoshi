import Foundation

/// Pure reconcile plan between expected Nexus reminders and pending system request IDs.
public struct NotificationReconcilePlan: Equatable, Sendable {
    public let toSchedule: [TaskReminderRequest]
    public let toCancel: Set<String>
    public let dailySummary: DailySummaryScheduleRequest?
    public let cancelDailySummary: Bool

    public init(
        toSchedule: [TaskReminderRequest],
        toCancel: Set<String>,
        dailySummary: DailySummaryScheduleRequest? = nil,
        cancelDailySummary: Bool = false
    ) {
        self.toSchedule = toSchedule
        self.toCancel = toCancel
        self.dailySummary = dailySummary
        self.cancelDailySummary = cancelDailySummary
    }
}

public enum NotificationReconcilePlanner: Sendable {
    /// `pendingIdentifiers` should include only currently pending request IDs from the system.
    /// Foreign (non-Nexus) IDs are never cancelled.
    public static func plan(
        tasks: [TaskReminderInput],
        pendingIdentifiers: Set<String>,
        dailySummaryPreferences: DailySummaryPreferences,
        dashboardTasks: [DashboardTaskInput],
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> NotificationReconcilePlan {
        let expectedRequests = TaskReminderPolicy.expectedRequests(tasks: tasks, now: now)
        let expectedByID = Dictionary(uniqueKeysWithValues: expectedRequests.map { ($0.identifier, $0) })
        let expectedIDs = Set(expectedByID.keys)

        let pendingNexusTaskIDs = pendingIdentifiers.filter {
            NotificationIdentifier.taskID(from: $0) != nil
        }

        let stale = pendingNexusTaskIDs.subtracting(expectedIDs)

        // Schedule missing or always re-queue expected (caller may de-dupe identical content).
        // We include all expected so title/date changes reschedule after cancel of same id.
        var toSchedule: [TaskReminderRequest] = []
        for request in expectedRequests {
            // Always replace pending for the same identifier when expected — scheduler removes first.
            toSchedule.append(request)
        }

        let summary = DailySummaryPolicy.scheduleRequest(
            preferences: dailySummaryPreferences,
            tasks: dashboardTasks,
            now: now,
            calendar: calendar
        )

        let hasPendingSummary = pendingIdentifiers.contains(NotificationIdentifier.dailySummary)
        let cancelDaily = summary == nil && hasPendingSummary

        // When summary should exist, cancel first then schedule (same identifier).
        return NotificationReconcilePlan(
            toSchedule: toSchedule,
            toCancel: stale,
            dailySummary: summary,
            cancelDailySummary: cancelDaily || summary != nil
        )
    }
}
