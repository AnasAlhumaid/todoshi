import Foundation

/// Pure classification of which widget kinds should reload after a write.
public enum WidgetReloadClassifier: Sendable {
    public enum Event: String, Equatable, Sendable {
        case taskCreated
        case taskContentChanged
        case taskDueDateChanged
        case taskPriorityChanged
        case taskCompletedOrReopened
        case taskDeleted
        case taskReminderChanged
        case taskLabelsChanged
        case labelListChanged
        case labelContentChanged
        case labelDeleted
        case checklistUpdated
        case checklistItemToggled
        case subtaskCreated
        case subtaskUpdated
        case subtaskCompletedOrReopened
        case subtaskReordered
        case subtaskPromoted
        case resourcesUpdated
        case resourceOrphanCleanupCompleted
        case recurrenceEnabled
        case recurrenceUpdated
        case recurrenceDisabled
        case recurringOccurrenceGenerated
        case projectStructureChanged
        case projectArchiveStateChanged
        case projectDeleted
        case projectListChanged
        /// Task created from a widget App Intent — reload task widgets, no notification reconcile.
        case widgetTaskCreated
        /// Widget-only configuration/selection change — project widget only.
        case widgetProjectSelectionChanged
    }

    public static func kinds(for event: Event) -> [String] {
        switch event {
        case .taskCreated, .taskContentChanged, .taskCompletedOrReopened, .taskDeleted, .subtaskPromoted,
                .recurringOccurrenceGenerated, .widgetTaskCreated:
            return TodoshiWidgetKind.allTaskListKinds
        case .widgetProjectSelectionChanged:
            return [TodoshiWidgetKind.project]
        case .taskDueDateChanged:
            return [TodoshiWidgetKind.today, TodoshiWidgetKind.todayCountAccessory, TodoshiWidgetKind.project, TodoshiWidgetKind.highPriority]
        case .taskPriorityChanged:
            return [TodoshiWidgetKind.highPriority, TodoshiWidgetKind.project, TodoshiWidgetKind.today]
        case .taskReminderChanged, .taskLabelsChanged, .labelListChanged, .labelContentChanged, .labelDeleted,
                .checklistUpdated, .checklistItemToggled,
                .subtaskCreated, .subtaskUpdated, .subtaskCompletedOrReopened, .subtaskReordered,
                .resourcesUpdated, .resourceOrphanCleanupCompleted,
                .recurrenceEnabled, .recurrenceUpdated, .recurrenceDisabled:
            return []
        case .projectStructureChanged:
            return [TodoshiWidgetKind.project, TodoshiWidgetKind.today, TodoshiWidgetKind.highPriority, TodoshiWidgetKind.todayCountAccessory]
        case .projectArchiveStateChanged, .projectDeleted, .projectListChanged:
            return TodoshiWidgetKind.allKinds
        }
    }

    /// Whether a data-change event should trigger notification reconciliation.
    public static func shouldReconcileNotifications(for event: Event) -> Bool {
        switch event {
        case .taskReminderChanged, .taskCreated, .taskContentChanged, .taskCompletedOrReopened,
                .taskDeleted, .taskDueDateChanged, .projectArchiveStateChanged,
                .projectDeleted, .projectListChanged,
                .subtaskCreated, .subtaskUpdated, .subtaskCompletedOrReopened, .subtaskPromoted,
                .recurringOccurrenceGenerated:
            return true
        case .taskLabelsChanged, .labelListChanged, .labelContentChanged, .labelDeleted,
                .taskPriorityChanged, .projectStructureChanged,
                .checklistUpdated, .checklistItemToggled,
                .subtaskReordered,
                .resourcesUpdated, .resourceOrphanCleanupCompleted,
                .recurrenceEnabled, .recurrenceUpdated, .recurrenceDisabled,
                .widgetTaskCreated, .widgetProjectSelectionChanged:
            return false
        }
    }
}
