import Foundation

/// Authenticated member who performed a completion action (Shared Checklist).
public struct TaskCompletionActor: Sendable, Equatable {
    public let uid: String
    /// Membership `displayName` snapshot at completion time. May be nil when unavailable.
    public let displayName: String?

    public init(uid: String, displayName: String?) {
        self.uid = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.displayName = trimmed.isEmpty ? nil : trimmed
    }

    public var isValid: Bool { !uid.isEmpty }
}

/// Completion attribution independent of Phase 7 assignment (`assigneeUID`).
public enum TaskCompletionAttribution: Sendable {
    /// Applies status transition rules for `completedAt` and completion actor fields.
    public static func apply(
        from previous: TaskStatus,
        to newStatus: TaskStatus,
        completedAt: inout Date?,
        completedByUID: inout String?,
        completedByDisplayName: inout String?,
        actor: TaskCompletionActor?,
        at date: Date = .now
    ) {
        if previous != .done, newStatus == .done {
            recordEnteringDone(
                completedAt: &completedAt,
                completedByUID: &completedByUID,
                completedByDisplayName: &completedByDisplayName,
                actor: actor,
                at: date
            )
        } else if previous == .done, newStatus != .done {
            clear(
                completedAt: &completedAt,
                completedByUID: &completedByUID,
                completedByDisplayName: &completedByDisplayName
            )
        } else if previous == .done, newStatus == .done {
            // Done→Done: preserve historical attribution and completedAt.
            TaskStatusTransitions.apply(newStatus, to: &completedAt, at: date)
        } else {
            TaskStatusTransitions.apply(newStatus, to: &completedAt, at: date)
        }
    }

    /// Records a new completion. Replaces any previous actor (after reopen).
    public static func recordEnteringDone(
        completedAt: inout Date?,
        completedByUID: inout String?,
        completedByDisplayName: inout String?,
        actor: TaskCompletionActor?,
        at date: Date = .now
    ) {
        if completedAt == nil {
            completedAt = date
        }
        if let actor, actor.isValid {
            completedByUID = actor.uid
            completedByDisplayName = actor.displayName
        } else {
            // Personal / no collaboration identity — do not invent attribution.
            completedByUID = nil
            completedByDisplayName = nil
        }
    }

    public static func clear(
        completedAt: inout Date?,
        completedByUID: inout String?,
        completedByDisplayName: inout String?
    ) {
        completedAt = nil
        completedByUID = nil
        completedByDisplayName = nil
    }

    /// Soft-deleted completed items may retain historical attribution.
    public static func shouldPreserveOnSoftDelete() -> Bool { true }
}

/// Checklist-facing completion copy (not shown on Tasks project rows in Phase 8.1).
public enum TaskCompletionPresentation: Sendable {
    public static var completedByLabel: String {
        TodoshiL10n.tr("project.checklist.completedByLabel")
    }

    public static func resolvedCompleterName(
        completedByUID: String?,
        completedByDisplayName: String?,
        members: [AssignmentCandidate] = []
    ) -> String? {
        guard let uid = completedByUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !uid.isEmpty
        else {
            return nil
        }
        if let member = members.first(where: { $0.uid == uid }),
           let current = CollaborationDisplayNamePolicy.normalized(member.displayName) {
            return current
        }
        return CollaborationDisplayNamePolicy.normalized(completedByDisplayName)
    }

    /// Returns localized "Completed by Name" when attribution exists; nil for legacy/unattributed.
    public static func completedByLine(
        completedByUID: String?,
        completedByDisplayName: String?,
        members: [AssignmentCandidate] = []
    ) -> String? {
        guard let uid = completedByUID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !uid.isEmpty
        else {
            return nil
        }
        let name: String
        if let member = members.first(where: { $0.uid == uid }),
           let current = CollaborationDisplayNamePolicy.normalized(member.displayName) {
            name = current
        } else {
            name = TaskAssignmentPresentation.memberDisplayName(completedByDisplayName)
        }
        return TodoshiL10n.format("project.checklist.completedBy", name)
    }

    public static func accessibilitySuffix(
        completedByUID: String?,
        completedByDisplayName: String?
    ) -> String? {
        completedByLine(
            completedByUID: completedByUID,
            completedByDisplayName: completedByDisplayName
        )
    }
}
