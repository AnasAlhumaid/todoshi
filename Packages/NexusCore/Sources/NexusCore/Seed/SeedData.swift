import Foundation
import SwiftData

/// Deterministic sample graph for previews and manual QA.
@MainActor
public enum SeedData {
    @discardableResult
    public static func populate(_ context: ModelContext) throws -> SeedResult {
        let project = Project(
            name: "Nexus",
            icon: "shippingbox.fill",
            colorHex: "#5B8DEF",
            projectDescription: "Personal developer workspace"
        )
        context.insert(project)

        let labelBug = LabelTag(name: "bug", colorHex: "#FF6B6B")
        let labelFeature = LabelTag(name: "feature", colorHex: "#51CF66")
        context.insert(labelBug)
        context.insert(labelFeature)

        let root = TaskItem(
            title: "Design data layer",
            taskDescription: "SwiftData schema and repositories",
            status: .inProgress,
            priority: .high,
            position: FractionalPosition.initial(),
            project: project
        )
        context.insert(root)
        root.labels = [labelFeature]

        let child = TaskItem(
            title: "Write persistence tests",
            status: .todo,
            priority: .medium,
            position: FractionalPosition.initial(),
            project: project,
            parentTask: root
        )
        context.insert(child)

        let checklist = ChecklistItem(
            title: "Cover cascade deletes",
            position: FractionalPosition.initial(),
            task: root
        )
        context.insert(checklist)

        let doneTask = TaskItem(
            title: "Create Xcode project shell",
            status: .done,
            priority: .medium,
            position: FractionalPosition.after(FractionalPosition.initial()),
            project: project
        )
        doneTask.applyStatus(.done)
        context.insert(doneTask)

        try context.save()

        return SeedResult(
            projectID: project.id,
            rootTaskID: root.id,
            childTaskID: child.id,
            labelIDs: [labelBug.id, labelFeature.id]
        )
    }
}

public struct SeedResult: Sendable {
    public let projectID: UUID
    public let rootTaskID: UUID
    public let childTaskID: UUID
    public let labelIDs: [UUID]
}
