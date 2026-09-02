import Foundation
import Observation
import SwiftData
import NexusCore

@Observable
@MainActor
final class NotificationSettingsViewModel {
    var authorizationState: NotificationAuthorizationState = .unknown
    var pendingReminderCount: Int = 0
    var preferences: DailySummaryPreferences
    var isRequesting = false
    var statusMessage: String?
    var showPermissionExplainer = false

    private let scheduler = LocalNotificationScheduler()
    private let reconciler = NotificationReconciler()

    init(preferences: DailySummaryPreferences = DailySummaryStore.load()) {
        self.preferences = preferences
    }

    var authorizationLabel: String {
        switch authorizationState {
        case .notDetermined: return NexusL10n.tr("notification.auth.notRequested")
        case .denied: return NexusL10n.tr("notification.auth.denied")
        case .authorized: return NexusL10n.tr("notification.auth.authorized")
        case .provisional: return NexusL10n.tr("notification.auth.provisional")
        case .ephemeral: return NexusL10n.tr("notification.auth.ephemeral")
        case .unknown: return NexusL10n.tr("notification.auth.unknown")
        }
    }

    var canRequestAuthorization: Bool {
        authorizationState == .notDetermined
    }

    var isDenied: Bool {
        authorizationState == .denied
    }

    var isAuthorized: Bool {
        authorizationState == .authorized
            || authorizationState == .provisional
            || authorizationState == .ephemeral
    }

    func refreshStatus() async {
        authorizationState = await scheduler.authorizationStatus()
        pendingReminderCount = await scheduler.pendingTaskReminderIDs().count
    }

    func requestAuthorization(context: ModelContext) async {
        isRequesting = true
        defer { isRequesting = false }
        do {
            let granted = try await scheduler.requestAuthorization()
            authorizationState = await scheduler.authorizationStatus()
            if granted {
                await reconciler.reconcile(context: context, preferences: preferences)
                statusMessage = nil
            } else {
                statusMessage = NotificationStrings.deniedMessage
            }
            pendingReminderCount = await scheduler.pendingTaskReminderIDs().count
        } catch {
            statusMessage = UserFacingError.message(for: error)
        }
    }

    func openSystemSettings() {
        NotificationAuthorizationManager.openSystemSettings()
    }

    func savePreferences(context: ModelContext) async {
        DailySummaryStore.save(preferences)
        await reconciler.reconcile(context: context, preferences: preferences)
        pendingReminderCount = await scheduler.pendingTaskReminderIDs().count
    }

    func repair(context: ModelContext) async {
        statusMessage = nil
        await reconciler.reconcile(context: context, preferences: preferences)
        pendingReminderCount = await scheduler.pendingTaskReminderIDs().count
        statusMessage = NexusL10n.tr("notification.refreshed")
    }
}
