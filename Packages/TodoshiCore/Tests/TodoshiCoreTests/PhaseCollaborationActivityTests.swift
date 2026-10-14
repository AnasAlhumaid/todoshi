import Foundation
import SwiftData
import Testing
@testable import TodoshiCore

@MainActor
struct PhaseCollaborationActivityTests {
    private let en = Locale(identifier: "en")
    private let ar = Locale(identifier: "ar")

    private func isolatedDefaults() -> UserDefaults {
        let name = "todoshi.collabActivity.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func makeRootTask(
        project: Project,
        activityAt: Date? = nil,
        activityBy: String? = nil
    ) -> TaskItem {
        TaskItem(
            title: "Root",
            status: .todo,
            lastActivityAt: activityAt,
            lastActivityByUID: activityBy,
            lastActivityKindRaw: activityBy == nil ? nil : TaskCollaborationActivityKind.taskUpdated.rawValue,
            project: project
        )
    }

    @Test("1 — no activity metadata → no unread badge")
    func noActivityNoBadge() {
        let project = Project(name: "Shared", sharingMode: .shared)
        let task = makeRootTask(project: project)
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                task: task,
                viewerUID: "viewer-a"
            ) == false
        )
    }

    @Test("2 — own activity → no unread badge")
    func ownActivityNoBadge() {
        let project = Project(name: "Shared", sharingMode: .shared)
        let at = Date()
        let task = makeRootTask(project: project, activityAt: at, activityBy: "viewer-a")
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                task: task,
                viewerUID: "viewer-a"
            ) == false
        )
    }

    @Test("3 — other member newer activity → unread")
    func otherMemberUnread() {
        let project = Project(name: "Shared", sharingMode: .shared)
        let at = Date()
        let task = makeRootTask(project: project, activityAt: at, activityBy: "member-b")
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                task: task,
                viewerUID: "viewer-a"
            )
        )
    }

    @Test("4 — task opened → seen clears unread")
    func taskOpenedMarksSeen() {
        let defaults = isolatedDefaults()
        let projectID = UUID()
        let rootID = UUID()
        let at = Date()
        TaskActivitySeenStore.markSeen(
            uid: "viewer-a",
            projectID: projectID,
            rootTaskID: rootID,
            lastSeenAt: at,
            defaults: defaults
        )
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                lastActivityAt: at,
                lastActivityByUID: "member-b",
                viewerUID: "viewer-a",
                lastSeenAt: TaskActivitySeenStore.lastSeen(
                    uid: "viewer-a",
                    projectID: projectID,
                    rootTaskID: rootID,
                    defaults: defaults
                )
            ) == false
        )
    }

    @Test("5 — older or equal activity → no unread")
    func olderActivityNoUnread() {
        let seen = Date()
        let older = seen.addingTimeInterval(-60)
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                lastActivityAt: older,
                lastActivityByUID: "member-b",
                viewerUID: "viewer-a",
                lastSeenAt: seen
            ) == false
        )
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                lastActivityAt: seen,
                lastActivityByUID: "member-b",
                viewerUID: "viewer-a",
                lastSeenAt: seen
            ) == false
        )
    }

    @Test("6 — account A seen state does not affect account B")
    func accountIsolation() {
        let defaults = isolatedDefaults()
        let projectID = UUID()
        let rootID = UUID()
        let at = Date()
        TaskActivitySeenStore.markSeen(
            uid: "account-a",
            projectID: projectID,
            rootTaskID: rootID,
            lastSeenAt: at,
            defaults: defaults
        )
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                lastActivityAt: at,
                lastActivityByUID: "member-b",
                viewerUID: "account-b",
                lastSeenAt: TaskActivitySeenStore.lastSeen(
                    uid: "account-b",
                    projectID: projectID,
                    rootTaskID: rootID,
                    defaults: defaults
                )
            )
        )
    }

    @Test("7 — root mutation metadata stays on root task")
    func rootMutationOnRoot() {
        let project = Project(name: "Shared", sharingMode: .shared)
        let root = makeRootTask(project: project, activityAt: .now, activityBy: "member-b")
        #expect(root.isRoot)
        #expect(root.lastActivityAt != nil)
        #expect(root.lastActivityByUID == "member-b")
    }

    @Test("8 — subtask activity resolves to root task ID")
    func subtaskResolvesRoot() {
        let project = Project(name: "Shared", sharingMode: .shared)
        let root = makeRootTask(project: project)
        let child = TaskItem(title: "Child", status: .todo, project: project, parentTask: root)
        #expect(TaskCollaborationActivityPolicy.rootTaskID(for: child) == root.id)
        #expect(TaskCollaborationActivityPolicy.rootTaskID(for: child.id, parentTaskID: root.id) == root.id)
    }

    @Test("9 — comment activity kind is supported")
    func commentActivityKind() {
        #expect(TaskCollaborationActivityKind.commentAdded.rawValue == "commentAdded")
        #expect(TaskCollaborationActivityKind.resolve("commentEdited") == .commentEdited)
    }

    @Test("10 — checklist item supports same unread policy")
    func checklistUnread() {
        let project = Project(name: "Checklist", sharingMode: .shared, projectType: .checklist)
        let item = makeRootTask(project: project, activityAt: .now, activityBy: "member-b")
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                task: item,
                viewerUID: "viewer-a"
            )
        )
    }

    @Test("11 — personal project never shows unread")
    func personalProjectNoUnread() {
        let project = Project(name: "Personal", sharingMode: .personal)
        let task = makeRootTask(project: project, activityAt: .now, activityBy: "member-b")
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: false,
                task: task,
                viewerUID: "viewer-a"
            ) == false
        )
    }

    @Test("12 — removed member UID remains valid historical activity metadata")
    func removedMemberActivityMetadata() {
        let project = Project(name: "Shared", sharingMode: .shared)
        let task = makeRootTask(project: project, activityAt: .now, activityBy: "removed-member")
        #expect(task.lastActivityByUID == "removed-member")
        #expect(
            TaskCollaborationActivityPolicy.hasUnreadActivity(
                isSharedProject: true,
                task: task,
                viewerUID: "viewer-a"
            )
        )
    }

    @Test("Unread badge copy localizes")
    func unreadBadgeLocalization() {
        #expect(TodoshiL10n.tr("task.activity.new", locale: en) == "New")
        #expect(TodoshiL10n.tr("task.activity.new", locale: ar) == "جديد")
        #expect(TaskCollaborationActivityPresentation.unreadBadge == "● New"
            || TaskCollaborationActivityPresentation.unreadBadge == "● جديد")
    }

    @Test("Board mapping surfaces unread for shared root tasks")
    func boardMappingUnread() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "Shared", sharingMode: .shared)
        context.insert(project)
        let task = TaskItem(
            title: "Server move",
            status: .inProgress,
            lastActivityAt: Date(),
            lastActivityByUID: "member-b",
            project: project
        )
        context.insert(task)
        try context.save()

        let summary = HomeMapping.taskSummary(
            from: task,
            projectID: project.id,
            isShared: true,
            viewerUID: "viewer-a"
        )
        #expect(summary.hasUnreadActivity)
        #expect(summary.status.displayName(locale: ar) == "قيد التنفيذ")
        #expect(ProjectStatusPolicy.displayName(.inProgress, for: .tasks) == TaskStatus.inProgress.displayName)
    }

    @Test("Arabic status labels via board policy match final terminology")
    func arabicStatusBoardMapping() {
        #expect(TaskStatus.backlog.displayName(locale: ar) == "قائمة المهام")
        #expect(TaskStatus.todo.displayName(locale: ar) == "جاهزة للبدء")
        #expect(TaskStatus.inProgress.displayName(locale: ar) == "قيد التنفيذ")
        #expect(TaskStatus.review.displayName(locale: ar) == "قيد المراجعة")
        #expect(TaskStatus.done.displayName(locale: ar) == "مكتملة")
        #expect(TaskStatus.backlog.displayName(locale: en) == "Backlog")
        #expect(TaskStatus.todo.displayName(locale: en) == "Todo")
        #expect(TaskStatus.inProgress.displayName(locale: en) == "In Progress")
        #expect(TaskStatus.review.displayName(locale: en) == "Review")
        #expect(TaskStatus.done.displayName(locale: en) == "Done")
    }
}
