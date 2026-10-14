import Foundation
import UIKit
import UserNotifications
import TodoshiCore

enum NotificationStrings {
    static var enableTitle: String { TodoshiL10n.tr("notification.enableTitle") }
    static var enableMessage: String { TodoshiL10n.tr("notification.enableMessage") }
    static var deniedTitle: String { TodoshiL10n.tr("notification.deniedTitle") }
    static var deniedMessage: String { TodoshiL10n.tr("notification.deniedMessage") }
    static var openSettings: String { TodoshiL10n.tr("notification.openSettings") }
    static var notNow: String { TodoshiL10n.tr("notification.notNow") }
    static var allow: String { TodoshiL10n.tr("notification.allow") }
    static var privacyNote: String { TodoshiL10n.tr("notification.privacyNote") }
    static var repair: String { TodoshiL10n.tr("notification.repair") }
    static var pendingCount: String { TodoshiL10n.tr("notification.pendingCount") }
    static var dailySummary: String { TodoshiL10n.tr("notification.dailySummary") }
    static var dailySummaryTime: String { TodoshiL10n.tr("notification.dailySummaryTime") }
    static var schedulingFailed: String { TodoshiL10n.tr("notification.schedulingFailed") }
    static var authorization: String { TodoshiL10n.tr("notification.authorization") }
}

enum NotificationAuthorizationManager {
    static func map(_ status: UNAuthorizationStatus) -> NotificationAuthorizationState {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }

    static func currentState(center: UNUserNotificationCenter = .current()) async -> NotificationAuthorizationState {
        let settings = await center.notificationSettings()
        return map(settings.authorizationStatus)
    }

    static func requestAuthorization(center: UNUserNotificationCenter = .current()) async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    static func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
