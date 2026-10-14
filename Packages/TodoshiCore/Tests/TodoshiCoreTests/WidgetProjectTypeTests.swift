import Foundation
import Testing
@testable import TodoshiCore

struct WidgetProjectTypeTests {
    private let projectID = UUID()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func taskInput(
        title: String,
        status: TaskStatus,
        position: Double = 0,
        completedAt: Date? = nil
    ) -> DashboardTaskInput {
        DashboardTaskInput(
            title: title,
            status: status,
            completedAt: completedAt,
            updatedAt: now,
            position: position,
            projectID: projectID,
            projectName: "البيت"
        )
    }

    @Test("Tasks widget uses Add Task / Open Project copy")
    func tasksPresentationCopy() {
        #expect(WidgetProjectPresentation.addActionTitle(for: .tasks) == TodoshiL10n.tr("widget.addTask"))
        #expect(WidgetProjectPresentation.openActionTitle(for: .tasks) == TodoshiL10n.tr("widget.openProject"))
        #expect(WidgetProjectPresentation.emptyTitle(for: .tasks) == TodoshiL10n.tr("widget.noOpenTasks"))
    }

    @Test("Checklist widget uses Add Item / Open List copy")
    func checklistPresentationCopy() {
        #expect(WidgetProjectPresentation.addActionTitle(for: .checklist) == TodoshiL10n.tr("widget.addItem"))
        #expect(WidgetProjectPresentation.openActionTitle(for: .checklist) == TodoshiL10n.tr("widget.openList"))
        #expect(WidgetProjectPresentation.emptyTitle(for: .checklist) == TodoshiL10n.tr("widget.noItems"))
        #expect(WidgetProjectPresentation.emptySubtitle(for: .checklist) == TodoshiL10n.tr("widget.noItemsHint"))
    }

    @Test("Checklist count uses remaining-item pluralization")
    func checklistCountPluralization() {
        let en = Locale(identifier: "en")
        #expect(
            WidgetProjectPresentation.primaryCountText(remaining: 1, projectType: .checklist)
            == TodoshiL10n.plural("widget.itemsRemainingCount", count: 1)
        )
        #expect(
            TodoshiL10n.plural("widget.itemsRemainingCount", count: 1, locale: en) == "1 item remaining"
        )
        #expect(
            TodoshiL10n.plural("widget.itemsRemainingCount", count: 2, locale: en) == "2 items remaining"
        )
        #expect(
            TodoshiL10n.plural("widget.itemsRemainingCount", count: 1, locale: Locale(identifier: "ar")) == "عنصر واحد متبقٍ"
        )
    }

    @Test("Tasks count terminology unchanged")
    func tasksCountPluralization() {
        #expect(
            WidgetProjectPresentation.primaryCountText(remaining: 1, projectType: .tasks)
            == TodoshiL10n.plural("widget.openTasksCount", count: 1)
        )
    }

    @Test("Checklist status labels avoid Tasks workflow wording")
    func checklistStatusLabels() {
        #expect(WidgetProjectPresentation.statusLabel(.todo, projectType: .checklist) == TodoshiL10n.tr("project.checklist.status.todo"))
        #expect(WidgetProjectPresentation.statusLabel(.inProgress, projectType: .checklist) == TodoshiL10n.tr("project.checklist.status.inProgress"))
        #expect(WidgetProjectPresentation.statusLabel(.done, projectType: .checklist) == TodoshiL10n.tr("project.checklist.status.done"))
    }

    @Test("Tasks status labels remain workflow-based")
    func tasksStatusLabels() {
        #expect(WidgetProjectPresentation.statusLabel(.todo, projectType: .tasks) == TaskStatus.todo.displayName)
    }

    @Test("Legacy missing project type defaults to Tasks snapshot behavior")
    func legacyProjectTypeDefaultsToTasks() {
        let snapshot = WidgetSnapshotBuilder.projectSnapshot(
            projectID: projectID,
            projectName: "Legacy",
            projectIcon: "folder",
            projectColorHex: ProjectColorCatalog.defaultHex,
            projectIsActive: true,
            projectType: .tasks,
            tasks: [taskInput(title: "One", status: .todo)],
            now: now
        )
        #expect(snapshot.projectType == .tasks)
        #expect(snapshot.totalCount == 1)
    }

    @Test("Checklist snapshot prioritizes incomplete items and includes completed rows")
    func checklistSnapshotOrderingAndCompletion() {
        let tasks = [
            taskInput(title: "Done item", status: .done, position: 1, completedAt: now),
            taskInput(title: "Active", status: .inProgress, position: 2),
            taskInput(title: "Pending", status: .todo, position: 3)
        ]
        let snapshot = WidgetSnapshotBuilder.projectSnapshot(
            projectID: projectID,
            projectName: "البيت",
            projectIcon: "checklist",
            projectColorHex: ProjectColorCatalog.defaultHex,
            projectIsActive: true,
            projectType: .checklist,
            tasks: tasks,
            limit: 3,
            now: now
        )
        #expect(snapshot.totalCount == 2)
        #expect(snapshot.allRootCount == 3)
        #expect(snapshot.tasks.map(\.title) == ["Active", "Pending", "Done item"])
        #expect(snapshot.tasks.last?.status == .done)
    }

    @Test("Checklist empty when no root items exist")
    func checklistEmptyDetection() {
        #expect(
            WidgetProjectPresentation.isProjectWidgetEmpty(
                projectType: .checklist,
                remainingCount: 0,
                allRootCount: 0
            )
        )
        #expect(
            WidgetProjectPresentation.isProjectWidgetEmpty(
                projectType: .checklist,
                remainingCount: 0,
                allRootCount: 2
            ) == false
        )
    }

    @Test("Tasks empty when no open tasks remain")
    func tasksEmptyDetection() {
        #expect(
            WidgetProjectPresentation.isProjectWidgetEmpty(
                projectType: .tasks,
                remainingCount: 0,
                allRootCount: 0
            )
        )
    }

    @Test("Quick-add deep link carries project ID for widget Add action")
    func quickAddDeepLinkCarriesProjectID() {
        let url = TodoshiDeepLink.quickAdd(projectID: projectID).url
        #expect(url.absoluteString.contains("quick-add"))
        #expect(url.absoluteString.contains(projectID.uuidString))
        #expect(TodoshiDeepLink(url: url) == .quickAdd(projectID: projectID))
    }

    @Test("Generic quick-add deep link remains project-agnostic")
    func genericQuickAddDeepLink() {
        let url = TodoshiDeepLink.quickAdd().url
        #expect(TodoshiDeepLink(url: url) == .quickAdd(projectID: nil))
    }

    @Test("Completed checklist row accessibility includes completed status")
    func completedRowAccessibility() {
        let label = WidgetProjectPresentation.taskRowAccessibilityLabel(
            title: "برتقال",
            status: .done,
            projectType: .checklist,
            priority: .none,
            isOverdue: false
        )
        #expect(label.contains("برتقال"))
        #expect(label.contains(TodoshiL10n.tr("project.checklist.status.done")))
    }
}
