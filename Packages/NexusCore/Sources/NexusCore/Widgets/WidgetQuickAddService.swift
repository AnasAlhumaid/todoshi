import Foundation
import SwiftData

/// Minimal root-task creation for interactive widgets / App Intents.
///
/// Always uses the caller-provided `ModelContext` (shared App Group in production).
/// Never creates a secondary fallback store.
public enum WidgetQuickAddService: Sendable {
    public enum Error: Swift.Error, Equatable, Sendable {
        case emptyTitle
        case projectUnavailable
        case sharedStoreUnavailable
    }

    /// Policy: widget/App Intent write path must never invent an alternate store.
    public static var createsFallbackStoreOnSharedFailure: Bool { false }

    /// Creates exactly one root task with widget defaults in `projectID` when it is active.
    @MainActor
    @discardableResult
    public static func createRootTask(
        title: String,
        projectID: UUID,
        context: ModelContext,
        at date: Date = .now
    ) throws -> TaskItem {
        guard FieldValidation.requiredName(title) != nil else {
            throw Error.emptyTitle
        }

        let projects = try context.fetch(FetchDescriptor<Project>())
        guard let project = projects.first(where: { $0.id == projectID }),
              project.status == .active else {
            throw Error.projectUnavailable
        }

        return try TaskRepository(context: context).create(
            in: project,
            title: title,
            taskDescription: "",
            status: .todo,
            priority: .none,
            dueDate: nil,
            reminderDate: nil,
            notes: "",
            labelIDs: [],
            recurrenceRule: nil,
            at: date,
            announcement: .widget
        )
    }
}
