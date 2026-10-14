import Foundation
import SwiftData

@MainActor
public enum HomeMapping {
    public static func projectSummaries(
        from projects: [Project],
        collaborationUID: String? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) -> [HomeProjectSummary] {
        projects
            .filter { $0.status == .active }
            .filter {
                SharedProjectAccountIsolationPolicy.isVisible(
                    sharingMode: $0.sharingMode,
                    collaborationOwnerUID: $0.collaborationOwnerUID,
                    currentUID: collaborationUID
                )
            }
            .sorted(by: areProjectsInOrder)
            .map { mapProject($0, collaborationUID: collaborationUID, calendar: calendar, now: now) }
    }

    public static func areProjectsInOrder(_ lhs: Project, _ rhs: Project) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.createdAt < rhs.createdAt
    }

    private static func mapProject(
        _ project: Project,
        collaborationUID: String?,
        calendar: Calendar,
        now: Date
    ) -> HomeProjectSummary {
        let openTasks = (project.tasks ?? [])
            .filter { $0.isRoot && $0.status != .done && $0.deletedAt == nil }
            .map {
                taskSummary(
                    from: $0,
                    projectID: project.id,
                    isShared: project.isShared,
                    viewerUID: collaborationUID,
                    calendar: calendar,
                    now: now
                )
            }
        let sortedTasks = HomeTaskOrdering.sort(openTasks)

        return HomeProjectSummary(
            id: project.id,
            name: project.name,
            icon: project.icon,
            colorHex: project.colorHex,
            projectDescription: project.projectDescription,
            position: project.position,
            createdAt: project.createdAt,
            openTaskCount: sortedTasks.count,
            isShared: project.isShared,
            projectType: project.projectType,
            tasks: sortedTasks
        )
    }

    public static func taskSummary(
        from task: TaskItem,
        projectID: UUID,
        isShared: Bool = false,
        viewerUID: String? = nil,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now,
        assigneeDisplayName: String? = nil
    ) -> HomeTaskSummary {
        mapTask(
            task,
            projectID: projectID,
            isShared: isShared,
            viewerUID: viewerUID,
            calendar: calendar,
            now: now,
            assigneeDisplayName: assigneeDisplayName
        )
    }

    private static func mapTask(
        _ task: TaskItem,
        projectID: UUID,
        isShared: Bool,
        viewerUID: String?,
        calendar: Calendar,
        now: Date,
        assigneeDisplayName: String? = nil
    ) -> HomeTaskSummary {
        let checklist = ChecklistProgress.from(completedFlags: (task.checklist ?? []).map(\.isCompleted))
        let subtasks = SubtaskProgress.from(tasks: task.subtasks ?? [])
        let labels = (task.labels ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .prefix(2)
            .map { HomeLabelSummary(id: $0.id, name: $0.name, colorHex: $0.colorHex) }

        return HomeTaskSummary(
            id: task.id,
            projectID: projectID,
            title: task.title,
            status: task.status,
            priority: task.priority,
            dueDate: task.dueDate,
            position: task.position,
            createdAt: task.createdAt,
            checklistProgress: checklist.hasProgress ? checklist : nil,
            subtaskProgress: subtasks.hasProgress ? subtasks : nil,
            labels: Array(labels),
            isOverdue: TaskPredicates.isOverdue(task.dueDate, status: task.status, calendar: calendar, now: now),
            assigneeDisplayName: assigneeDisplayName,
            hasUnreadActivity: TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: isShared,
                lastActivityAt: task.lastActivityAt,
                lastActivityByUID: task.lastActivityByUID,
                viewerUID: viewerUID,
                lastSeenAt: TaskActivitySeenStore.lastSeen(
                    uid: viewerUID,
                    projectID: projectID,
                    rootTaskID: task.id
                )
            ),
            columnID: task.columnIDRaw.flatMap(UUID.init(uuidString:))
        )
    }
}
