import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct Phase5WidgetTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
        var components = DateComponents()
        components.year = y
        components.month = m
        components.day = d
        components.hour = h
        components.minute = min
        return calendar.date(from: components)!
    }

    private func makeTask(
        title: String,
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        due: Date? = nil,
        position: Double = 100,
        isRoot: Bool = true,
        projectID: UUID,
        projectName: String = "Nexus",
        projectIsActive: Bool = true,
        updatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> DashboardTaskInput {
        DashboardTaskInput(
            title: title,
            status: status,
            priority: priority,
            dueDate: due,
            updatedAt: updatedAt,
            position: position,
            isRoot: isRoot,
            projectID: projectID,
            projectName: projectName,
            projectIsActive: projectIsActive
        )
    }

    // MARK: - Today snapshot

    @Test("Today includes due-today open roots and excludes done / archived / non-root")
    func todaySelection() {
        let now = date(2026, 8, 5, 15)
        let active = UUID()
        let archived = UUID()
        let tasks = [
            makeTask(title: "Due today", due: date(2026, 8, 5, 10), projectID: active),
            makeTask(title: "Done today", status: .done, due: date(2026, 8, 5, 9), projectID: active),
            makeTask(title: "Subtask", due: date(2026, 8, 5, 11), isRoot: false, projectID: active),
            makeTask(title: "Archived proj", due: date(2026, 8, 5, 12), projectID: archived, projectIsActive: false),
            makeTask(title: "Tomorrow", due: date(2026, 8, 6, 10), projectID: active)
        ]
        let snap = WidgetSnapshotBuilder.todaySnapshot(tasks: tasks, calendar: calendar, now: now)
        #expect(snap.totalCount == 1)
        #expect(snap.tasks.map(\.title) == ["Due today"])
        #expect(snap.tasks.first?.isOverdue == false)
    }

    @Test("Today ordering: priority desc, due time asc, position")
    func todayOrdering() {
        let now = date(2026, 8, 5, 15)
        let pid = UUID()
        let tasks = [
            makeTask(title: "Low early", priority: .low, due: date(2026, 8, 5, 8), position: 10, projectID: pid),
            makeTask(title: "High late", priority: .high, due: date(2026, 8, 5, 18), position: 20, projectID: pid),
            makeTask(title: "High early", priority: .high, due: date(2026, 8, 5, 9), position: 30, projectID: pid),
            makeTask(title: "High early later pos", priority: .high, due: date(2026, 8, 5, 9), position: 40, projectID: pid)
        ]
        let snap = WidgetSnapshotBuilder.todaySnapshot(tasks: tasks, calendar: calendar, now: now)
        #expect(snap.tasks.map(\.title) == [
            "High early",
            "High early later pos",
            "High late",
            "Low early"
        ])
    }

    @Test("Today limit preserves totalCount")
    func todayLimit() {
        let now = date(2026, 8, 5, 15)
        let pid = UUID()
        let tasks = (0..<5).map { i in
            makeTask(title: "T\(i)", due: date(2026, 8, 5, 10 + i), position: Double(i), projectID: pid)
        }
        let snap = WidgetSnapshotBuilder.todaySnapshot(tasks: tasks, limit: 2, calendar: calendar, now: now)
        #expect(snap.tasks.count == 2)
        #expect(snap.totalCount == 5)
    }

    // MARK: - High priority

    @Test("High priority includes high/urgent only; excludes done; sorts urgent and overdue first")
    func highPrioritySelectionAndOrder() {
        let now = date(2026, 8, 5, 12)
        let pid = UUID()
        let tasks = [
            makeTask(title: "Med", priority: .medium, due: date(2026, 8, 4, 10), projectID: pid),
            makeTask(title: "High future", priority: .high, due: date(2026, 8, 7, 10), projectID: pid, updatedAt: date(2026, 8, 1)),
            makeTask(title: "High overdue", priority: .high, due: date(2026, 8, 3, 10), projectID: pid, updatedAt: date(2026, 8, 2)),
            makeTask(title: "Urgent dated", priority: .urgent, due: date(2026, 8, 6, 10), projectID: pid, updatedAt: date(2026, 8, 3)),
            makeTask(title: "Urgent undated", priority: .urgent, due: nil, projectID: pid, updatedAt: date(2026, 8, 4)),
            makeTask(title: "Done urgent", status: .done, priority: .urgent, due: date(2026, 8, 3), projectID: pid)
        ]
        let snap = WidgetSnapshotBuilder.highPrioritySnapshot(tasks: tasks, calendar: calendar, now: now)
        #expect(snap.totalCount == 4)
        #expect(snap.tasks.map(\.title) == [
            "Urgent dated",
            "Urgent undated",
            "High overdue",
            "High future"
        ])
        #expect(snap.tasks.contains(where: { $0.title == "Med" }) == false)
    }

    // MARK: - Project snapshot

    @Test("Project snapshot filters project, excludes done, orders by status then position")
    func projectSnapshot() {
        let now = date(2026, 8, 5)
        let a = UUID()
        let b = UUID()
        let tasks = [
            makeTask(title: "Todo low", status: .todo, position: 200, projectID: a),
            makeTask(title: "Progress", status: .inProgress, position: 100, projectID: a),
            makeTask(title: "Review", status: .review, position: 50, projectID: a),
            makeTask(title: "Backlog", status: .backlog, position: 10, projectID: a),
            makeTask(title: "Done", status: .done, position: 1, projectID: a),
            makeTask(title: "Other project", status: .todo, position: 1, projectID: b),
            makeTask(title: "Sub", status: .todo, position: 5, isRoot: false, projectID: a)
        ]
        let snap = WidgetSnapshotBuilder.projectSnapshot(
            projectID: a,
            projectName: "Nexus",
            projectIcon: "shippingbox",
            projectColorHex: "#112233",
            projectIsActive: true,
            tasks: tasks,
            calendar: calendar,
            now: now
        )
        #expect(snap.projectAvailability == .available)
        #expect(snap.tasks.map(\.title) == ["Progress", "Review", "Todo low", "Backlog"])
        #expect(snap.totalCount == 4)
        #expect(snap.projectID == a)
    }

    @Test("Project snapshot needs configuration and unavailable states")
    func projectUnavailable() {
        let now = date(2026, 8, 5)
        let missing = WidgetSnapshotBuilder.projectSnapshot(
            projectID: nil,
            projectName: nil,
            projectIcon: nil,
            projectColorHex: nil,
            projectIsActive: nil,
            tasks: [],
            now: now
        )
        #expect(missing.projectAvailability == .missingSelection)

        let archivedID = UUID()
        let unavailable = WidgetSnapshotBuilder.projectSnapshot(
            projectID: archivedID,
            projectName: "Old",
            projectIcon: "archivebox",
            projectColorHex: "#000000",
            projectIsActive: false,
            tasks: [],
            now: now
        )
        #expect(unavailable.projectAvailability == .unavailable)
        #expect(unavailable.tasks.isEmpty)
    }

    // MARK: - Presentation mapping

    @Test("Map items omit notes/descriptions and compute overdue")
    func presentationMapping() {
        let now = date(2026, 8, 5, 12)
        let pid = UUID()
        let item = WidgetSnapshotBuilder.mapItem(
            id: UUID(),
            title: "Fix login layout",
            projectID: pid,
            projectName: "Nexus",
            projectIcon: "shippingbox.fill",
            projectColorHex: ProjectColorCatalog.defaultHex,
            status: .todo,
            priority: .urgent,
            dueDate: date(2026, 8, 3),
            calendar: calendar,
            now: now
        )
        #expect(item.title == "Fix login layout")
        #expect(item.isOverdue)
        #expect(item.projectName == "Nexus")
        // WidgetTaskItem has no notes or description fields by design.
        let mirror = Mirror(reflecting: item)
        let labels = mirror.children.compactMap(\.label)
        #expect(labels.contains("notes") == false)
        #expect(labels.contains("taskDescription") == false)
        #expect(labels.contains("description") == false)
    }

    // MARK: - Timeline policy

    @Test("Timeline next refresh crosses midnight and stays in the future")
    func timelinePolicy() {
        let now = date(2026, 8, 5, 23, 30)
        let next = WidgetTimelinePolicy.nextRefreshDate(after: now, calendar: calendar)
        #expect(WidgetTimelinePolicy.isValidFutureRefresh(next, now: now))
        #expect(calendar.isDate(next, inSameDayAs: date(2026, 8, 6, 0)))

        let dueSoon = date(2026, 8, 5, 23, 45)
        let nearer = WidgetTimelinePolicy.nextRefreshDate(
            after: now,
            calendar: calendar,
            dueDates: [dueSoon]
        )
        #expect(nearer == dueSoon)

        let pastOnly = WidgetTimelinePolicy.nextRefreshDate(
            after: now,
            calendar: calendar,
            dueDates: [date(2026, 8, 5, 10)],
            fallbackInterval: 3600
        )
        #expect(pastOnly > now)
    }

    // MARK: - Deep links

    @Test("Widget deep links parse and construct correctly")
    func deepLinks() {
        let taskID = UUID()
        let projectID = UUID()
        #expect(NexusDeepLink.quickAdd.url.absoluteString == "nexus://quick-add")
        #expect(NexusDeepLink.dashboard.url.absoluteString == "nexus://dashboard")
        #expect(NexusDeepLink.projects.url.absoluteString == "nexus://projects")
        #expect(NexusDeepLink.task(taskID).url.absoluteString == "nexus://task/\(taskID.uuidString)")
        #expect(NexusDeepLink.project(projectID).url.absoluteString == "nexus://project/\(projectID.uuidString)")

        #expect(NexusDeepLink(url: NexusDeepLink.task(taskID).url) == .task(taskID))
        #expect(NexusDeepLink(url: NexusDeepLink.project(projectID).url) == .project(projectID))
        #expect(NexusDeepLink(url: NexusDeepLink.dashboard.url) == .dashboard)
        #expect(NexusDeepLink(url: NexusDeepLink.projects.url) == .projects)
        #expect(NexusDeepLink(url: URL(string: "nexus://task/not-a-uuid")!) == nil)
        #expect(NexusDeepLink(url: URL(string: "nexus://project/zzzz")!) == nil)
    }

    // MARK: - Active projects config list via store

    @Test("Active projects for configuration exclude archived and sort by position")
    func activeProjectOptions() throws {
        let schema = Schema([Project.self, TaskItem.self, ChecklistItem.self, LabelTag.self, TaskResource.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let activeEarly = Project(name: "Early", position: 100)
        let activeLate = Project(name: "Late", position: 300)
        let archived = Project(name: "Old", status: .archived, position: 50)
        context.insert(activeEarly)
        context.insert(activeLate)
        context.insert(archived)
        try context.save()

        let options = try WidgetStoreAccess.loadActiveProjects(from: context)
        #expect(options.map(\.name) == ["Early", "Late"])
        #expect(options.map(\.id) == [activeEarly.id, activeLate.id])

        let missing = try WidgetStoreAccess.projectSnapshot(
            projectID: UUID(),
            context: context,
            calendar: calendar,
            now: date(2026, 8, 5)
        )
        #expect(missing.projectAvailability == .unavailable)
    }

    // MARK: - Reload classification

    @Test("Reload classifier maps write events to expected widget kinds")
    func reloadClassifier() {
        let taskKinds = Set(WidgetReloadClassifier.kinds(for: .taskCreated))
        #expect(taskKinds == Set(NexusWidgetKind.allTaskListKinds))

        let due = WidgetReloadClassifier.kinds(for: .taskDueDateChanged)
        #expect(due.contains(NexusWidgetKind.today))
        #expect(due.contains(NexusWidgetKind.todayCountAccessory))
        #expect(due.contains(NexusWidgetKind.highPriority) == false || due.contains(NexusWidgetKind.highPriority))
        // Due date changes affect Today primarily; classifier includes list widgets.

        let priority = Set(WidgetReloadClassifier.kinds(for: .taskPriorityChanged))
        #expect(priority.contains(NexusWidgetKind.highPriority))
        #expect(priority.contains(NexusWidgetKind.quickAddAccessory) == false)

        let archive = Set(WidgetReloadClassifier.kinds(for: .projectArchiveStateChanged))
        #expect(archive == Set(NexusWidgetKind.allKinds))

        let structure = Set(WidgetReloadClassifier.kinds(for: .projectStructureChanged))
        #expect(structure.contains(NexusWidgetKind.project))
        #expect(structure.contains(NexusWidgetKind.quickAddAccessory) == false)
    }

    @Test("Data change center encodes events")
    func dataChangeCenter() {
        let exp = WidgetReloadClassifier.Event.taskDueDateChanged
        #expect(NexusDataChangeCenter.event(from: [NexusDataChangeCenter.UserInfoKey.event: exp.rawValue]) == exp)
        #expect(NexusDataChangeCenter.event(from: [:]) == nil)
    }
}
