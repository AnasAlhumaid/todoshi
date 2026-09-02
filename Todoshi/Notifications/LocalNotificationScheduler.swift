import Foundation
import UserNotifications
import NexusCore

/// Thin wrapper around `UNUserNotificationCenter` for Nexus-owned local notifications.
@MainActor
final class LocalNotificationScheduler {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationStatus() async -> NotificationAuthorizationState {
        await NotificationAuthorizationManager.currentState(center: center)
    }

    func requestAuthorization() async throws -> Bool {
        try await NotificationAuthorizationManager.requestAuthorization(center: center)
    }

    func scheduleTaskReminder(_ request: TaskReminderRequest, now: Date = .now) async throws {
        guard request.reminderDate > now else { return }

        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])

        let content = UNMutableNotificationContent()
        content.title = request.taskTitle
        content.body = body(for: request)
        content.sound = .default
        content.userInfo = [
            NotificationUserInfoKey.deepLink: NexusDeepLink.task(request.taskID).url.absoluteString,
            NotificationUserInfoKey.taskID: request.taskID.uuidString
        ]
        content.categoryIdentifier = "NEXUS_TASK_REMINDER"

        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.reminderDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(notificationRequest)
    }

    func cancelTaskReminder(taskID: UUID) {
        center.removePendingNotificationRequests(
            withIdentifiers: [NotificationIdentifier.taskReminder(taskID: taskID)]
        )
    }

    func cancelTaskReminders(taskIDs: [UUID]) {
        let ids = taskIDs.map { NotificationIdentifier.taskReminder(taskID: $0) }
        guard !ids.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    func pendingTaskReminderIDs() async -> Set<UUID> {
        let pending = await center.pendingNotificationRequests()
        return Set(pending.compactMap { NotificationIdentifier.taskID(from: $0.identifier) })
    }

    func pendingIdentifiers() async -> Set<String> {
        let pending = await center.pendingNotificationRequests()
        return Set(pending.map(\.identifier))
    }

    func cancel(identifiers: [String]) {
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func scheduleDailySummary(_ request: DailySummaryScheduleRequest, now: Date = .now) async throws {
        guard request.fireDate > now else { return }
        center.removePendingNotificationRequests(withIdentifiers: [request.identifier])

        let content = UNMutableNotificationContent()
        content.title = request.content.title
        content.body = request.content.body
        content.sound = .default
        content.userInfo = [
            NotificationUserInfoKey.deepLink: request.content.deepLinkURL.absoluteString
        ]
        content.categoryIdentifier = "NEXUS_DAILY_SUMMARY"

        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: request.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let notificationRequest = UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: trigger
        )
        try await center.add(notificationRequest)
    }

    func cancelDailySummary() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationIdentifier.dailySummary])
    }

    private func body(for request: TaskReminderRequest) -> String {
        if let due = request.dueDate {
            let formatted = due.formatted(date: .abbreviated, time: .omitted)
            return "\(request.projectName) · Due \(formatted)"
        }
        return request.projectName
    }
}
