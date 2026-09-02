import Foundation
import SwiftData
import NexusCore

/// App-layer bridge that repairs pending system notifications against SwiftData.
@MainActor
final class NotificationReconciler {
    private let scheduler: LocalNotificationScheduler

    init(scheduler: LocalNotificationScheduler = LocalNotificationScheduler()) {
        self.scheduler = scheduler
    }

    func reconcile(
        context: ModelContext,
        preferences: DailySummaryPreferences = DailySummaryStore.load(),
        now: Date = .now
    ) async {
        let auth = await scheduler.authorizationStatus()
        guard auth == .authorized || auth == .provisional || auth == .ephemeral else {
            // Still cancel anything we can if denied? If denied, pending may be empty.
            // Clear daily if disabled is already handled when authorized later.
            return
        }

        do {
            let reminderInputs = try TaskReminderMapping.loadAll(from: context)
            let dashboardTasks = try WidgetStoreAccess.loadDashboardInputs(from: context)
            let pending = await scheduler.pendingIdentifiers()
            let plan = NotificationReconcilePlanner.plan(
                tasks: reminderInputs,
                pendingIdentifiers: pending,
                dailySummaryPreferences: preferences,
                dashboardTasks: dashboardTasks,
                now: now
            )

            if !plan.toCancel.isEmpty {
                scheduler.cancel(identifiers: Array(plan.toCancel))
            }
            if plan.cancelDailySummary {
                scheduler.cancelDailySummary()
            }

            for request in plan.toSchedule {
                try? await scheduler.scheduleTaskReminder(request, now: now)
            }
            if let summary = plan.dailySummary {
                try? await scheduler.scheduleDailySummary(summary, now: now)
            }
        } catch {
            // Scheduling failures must never corrupt task data.
        }
    }

    func applyDecision(_ decision: NotificationSchedulingDecision, now: Date = .now) async {
        let auth = await scheduler.authorizationStatus()
        guard auth == .authorized || auth == .provisional || auth == .ephemeral else {
            if case .cancel(let taskID) = decision {
                scheduler.cancelTaskReminder(taskID: taskID)
            }
            return
        }

        switch decision {
        case .schedule(let request):
            try? await scheduler.scheduleTaskReminder(request, now: now)
        case .cancel(let taskID):
            scheduler.cancelTaskReminder(taskID: taskID)
        case .ignore:
            break
        }
    }
}

/// Throttled coordinator for post-write and lifecycle reconciliation.
@MainActor
final class NotificationCoordinator {
    static let shared = NotificationCoordinator()

    private let reconciler = NotificationReconciler()
    private var lastReconcileAt: Date?
    private let throttle: TimeInterval = 2

    func reconcile(context: ModelContext, force: Bool = false) {
        let now = Date()
        if !force, let last = lastReconcileAt, now.timeIntervalSince(last) < throttle {
            return
        }
        lastReconcileAt = now
        Task {
            await reconciler.reconcile(context: context, now: now)
        }
    }

    func handleDataChange(context: ModelContext) {
        reconcile(context: context)
    }
}
