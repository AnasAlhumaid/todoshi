import Foundation
import SwiftData
import Testing
@testable import NexusCore

@MainActor
struct ProjectSwitchingWidgetTests {
    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    private func option(
        name: String,
        position: Double,
        id: UUID = UUID()
    ) -> WidgetProjectOption {
        WidgetProjectOption(
            id: id,
            name: name,
            icon: "folder",
            colorHex: "#112233",
            position: position
        )
    }

    private func makeTask(
        title: String,
        status: TaskStatus = .todo,
        position: Double = 100,
        isRoot: Bool = true,
        projectID: UUID,
        projectIsActive: Bool = true
    ) -> DashboardTaskInput {
        DashboardTaskInput(
            title: title,
            status: status,
            priority: .none,
            dueDate: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            position: position,
            isRoot: isRoot,
            projectID: projectID,
            projectName: "Nexus",
            projectIsActive: projectIsActive
        )
    }

    // MARK: - Selection policy

    @Test("Active projects ordered by position then name")
    func orderedActive() {
        let c = option(name: "C", position: 200)
        let a1 = option(name: "A", position: 100)
        let a2 = option(name: "B", position: 100)
        let ordered = WidgetProjectSelectionPolicy.orderedActive([c, a2, a1])
        #expect(ordered.map(\.name) == ["A", "B", "C"])
    }

    @Test("Previous and next wrap at ends; missing selection has sensible defaults")
    func neighborWrap() {
        let a = option(name: "A", position: 1)
        let b = option(name: "B", position: 2)
        let c = option(name: "C", position: 3)
        let ordered = [a, b, c]

        #expect(WidgetProjectSelectionPolicy.neighbor(of: a.id, in: ordered, direction: .next)?.id == b.id)
        #expect(WidgetProjectSelectionPolicy.neighbor(of: c.id, in: ordered, direction: .next)?.id == a.id)
        #expect(WidgetProjectSelectionPolicy.neighbor(of: a.id, in: ordered, direction: .previous)?.id == c.id)
        #expect(WidgetProjectSelectionPolicy.neighbor(of: c.id, in: ordered, direction: .previous)?.id == b.id)

        #expect(WidgetProjectSelectionPolicy.neighbor(of: nil, in: ordered, direction: .next)?.id == a.id)
        #expect(WidgetProjectSelectionPolicy.neighbor(of: nil, in: ordered, direction: .previous)?.id == c.id)

        let missing = UUID()
        #expect(WidgetProjectSelectionPolicy.neighbor(of: missing, in: ordered, direction: .next)?.id == a.id)
        #expect(WidgetProjectSelectionPolicy.neighbor(of: missing, in: ordered, direction: .previous)?.id == c.id)
        #expect(WidgetProjectSelectionPolicy.neighbor(of: a.id, in: [], direction: .next) == nil)
    }

    @Test("Effective project prefers live override when still active")
    func effectiveProjectID() {
        let base = UUID()
        let override = UUID()
        let other = UUID()
        let active: Set<UUID> = [base, override]

        #expect(
            WidgetProjectSelectionPolicy.effectiveProjectID(
                baseConfigurationID: base,
                overrideID: override,
                activeIDs: active
            ) == override
        )
        #expect(
            WidgetProjectSelectionPolicy.effectiveProjectID(
                baseConfigurationID: base,
                overrideID: other,
                activeIDs: active
            ) == base
        )
        #expect(
            WidgetProjectSelectionPolicy.effectiveProjectID(
                baseConfigurationID: base,
                overrideID: nil,
                activeIDs: active
            ) == base
        )
        #expect(
            WidgetProjectSelectionPolicy.effectiveProjectID(
                baseConfigurationID: nil,
                overrideID: nil,
                activeIDs: active
            ) == nil
        )
        // Deleted/missing selected ID preserved for unavailable messaging.
        let deleted = UUID()
        #expect(
            WidgetProjectSelectionPolicy.effectiveProjectID(
                baseConfigurationID: deleted,
                overrideID: nil,
                activeIDs: active
            ) == deleted
        )
    }

    @Test("Per-base selection store does not use a single global key")
    func selectionStorePerBase() {
        let suiteName = "group.com.anashamad.Nexus.widgetSelectionTest.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test suite")
            return
        }
        defer {
            suite.removePersistentDomain(forName: suiteName)
        }

        let baseA = UUID()
        let baseB = UUID()
        let project1 = UUID()
        let project2 = UUID()
        WidgetProjectSelectionStore.setOverride(project1, forBase: baseA, suite: suite)
        WidgetProjectSelectionStore.setOverride(project2, forBase: baseB, suite: suite)
        #expect(WidgetProjectSelectionStore.overrideID(forBase: baseA, suite: suite) == project1)
        #expect(WidgetProjectSelectionStore.overrideID(forBase: baseB, suite: suite) == project2)

        let active: Set<UUID> = [project1, project2, baseA, baseB]
        #expect(
            WidgetProjectSelectionStore.effectiveProjectID(
                baseConfigurationID: baseA,
                suite: suite,
                activeIDs: active
            ) == project1
        )
        #expect(
            WidgetProjectSelectionStore.effectiveProjectID(
                baseConfigurationID: baseB,
                suite: suite,
                activeIDs: active
            ) == project2
        )
    }

    // MARK: - Snapshot filtering

    @Test("Project snapshot only selected project open roots; excludes done/subtasks; correct order")
    func projectSnapshotFocus() {
        let selected = UUID()
        let other = UUID()
        let tasks = [
            makeTask(title: "Todo", status: .todo, position: 20, projectID: selected),
            makeTask(title: "Progress", status: .inProgress, position: 10, projectID: selected),
            makeTask(title: "Review", status: .review, position: 5, projectID: selected),
            makeTask(title: "Backlog", status: .backlog, position: 1, projectID: selected),
            makeTask(title: "Done", status: .done, position: 1, projectID: selected),
            makeTask(title: "Sub", status: .todo, position: 1, isRoot: false, projectID: selected),
            makeTask(title: "Other", status: .todo, position: 1, projectID: other)
        ]
        let snap = WidgetSnapshotBuilder.projectSnapshot(
            projectID: selected,
            projectName: "Nexus",
            projectIcon: "folder",
            projectColorHex: "#000000",
            projectIsActive: true,
            tasks: tasks,
            limit: WidgetSnapshotBuilder.projectFamilyLimitLarge,
            calendar: calendar,
            now: Date(timeIntervalSince1970: 1_700_000_000)
        )
        #expect(snap.tasks.map(\.title) == ["Progress", "Review", "Todo", "Backlog"])
        #expect(snap.totalCount == 4)
        #expect(snap.projectID == selected)
    }

    @Test("Project snapshot includes undated, future, overdue, and today; never due-filtered")
    func projectSnapshotNotDueFiltered() {
        let projectID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000) // fixed
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today)!
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!

        let tasks = [
            DashboardTaskInput(
                title: "Undated",
                status: .todo,
                priority: .none,
                dueDate: nil,
                updatedAt: now,
                position: 10,
                projectID: projectID,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Future",
                status: .todo,
                priority: .none,
                dueDate: tomorrow,
                updatedAt: now,
                position: 20,
                projectID: projectID,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Overdue",
                status: .todo,
                priority: .none,
                dueDate: yesterday,
                updatedAt: now,
                position: 30,
                projectID: projectID,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Today",
                status: .todo,
                priority: .none,
                dueDate: today,
                updatedAt: now,
                position: 40,
                projectID: projectID,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Done",
                status: .done,
                dueDate: today,
                updatedAt: now,
                position: 50,
                projectID: projectID,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Subtask",
                status: .todo,
                dueDate: today,
                updatedAt: now,
                position: 60,
                isRoot: false,
                projectID: projectID,
                projectName: "P"
            ),
            DashboardTaskInput(
                title: "Other project",
                status: .todo,
                dueDate: today,
                updatedAt: now,
                position: 70,
                projectID: UUID(),
                projectName: "Other"
            ),
            DashboardTaskInput(
                title: "Archived root",
                status: .todo,
                dueDate: today,
                updatedAt: now,
                position: 80,
                projectID: projectID,
                projectName: "P",
                projectIsActive: false
            )
        ]

        let snap = WidgetSnapshotBuilder.projectSnapshot(
            projectID: projectID,
            projectName: "P",
            projectIcon: "folder",
            projectColorHex: "#111111",
            projectIsActive: true,
            tasks: tasks,
            limit: WidgetSnapshotBuilder.defaultProjectLimit,
            calendar: cal,
            now: now
        )

        let titles = Set(snap.tasks.map(\.title))
        #expect(titles.contains("Undated"))
        #expect(titles.contains("Future"))
        #expect(titles.contains("Overdue"))
        #expect(titles.contains("Today"))
        #expect(titles.contains("Done") == false)
        #expect(titles.contains("Subtask") == false)
        #expect(titles.contains("Other project") == false)
        #expect(titles.contains("Archived root") == false)
        #expect(snap.totalCount == 4)
    }

    @Test("Position order within status; priority breaks ties; totalCount not clipped by display limit")
    func projectSnapshotPositionPriorityAndTotalCount() {
        let projectID = UUID()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var tasks: [DashboardTaskInput] = []
        // 8 todo tasks — display limit 6 should still report totalCount 8
        for i in 0..<8 {
            tasks.append(DashboardTaskInput(
                title: "T\(i)",
                status: .todo,
                priority: i == 0 ? .low : .high,
                dueDate: nil,
                updatedAt: now.addingTimeInterval(TimeInterval(i)),
                position: Double(100 - i),
                projectID: projectID,
                projectName: "P"
            ))
        }
        // Same position: higher priority first, then newer updatedAt
        tasks.append(DashboardTaskInput(
            title: "SamePosLow",
            status: .inProgress,
            priority: .low,
            updatedAt: now,
            position: 50,
            projectID: projectID,
            projectName: "P"
        ))
        tasks.append(DashboardTaskInput(
            title: "SamePosUrgent",
            status: .inProgress,
            priority: .urgent,
            updatedAt: now.addingTimeInterval(-10),
            position: 50,
            projectID: projectID,
            projectName: "P"
        ))

        let snap = WidgetSnapshotBuilder.projectSnapshot(
            projectID: projectID,
            projectName: "P",
            projectIcon: "folder",
            projectColorHex: "#000",
            projectIsActive: true,
            tasks: tasks,
            limit: WidgetSnapshotBuilder.projectFamilyLimitLarge,
            calendar: calendar,
            now: now
        )
        #expect(snap.totalCount == 10)
        #expect(snap.tasks.count == WidgetSnapshotBuilder.projectFamilyLimitLarge)
        #expect(snap.tasks.first?.title == "SamePosUrgent")
        #expect(snap.tasks.dropFirst().first?.title == "SamePosLow")
        // Todos ordered by ascending position among remaining slots
        let todoTitles = snap.tasks.filter { $0.status == .todo }.map(\.title)
        #expect(todoTitles.first == "T7") // position 100-7 = 93 highest position index wait: position Double(100-i): T0=100, T7=93 so T7 has lower position and comes first
    }

    @Test("Family limits constants match product: 1 / 3 / 6")
    func familyLimits() {
        #expect(WidgetSnapshotBuilder.projectFamilyLimitSmall == 1)
        #expect(WidgetSnapshotBuilder.projectFamilyLimitMedium == 3)
        #expect(WidgetSnapshotBuilder.projectFamilyLimitLarge == 6)
        #expect(WidgetSnapshotBuilder.defaultProjectLimit == 6)
    }

    @Test("Arabic Project widget empty-state and gallery keys")
    func arabicProjectWidgetKeys() {
        let ar = Locale(identifier: "ar")
        #expect(NexusL10n.tr("widget.projectTasks", locale: ar) == "مهام المشروع")
        #expect(NexusL10n.tr("widget.today", locale: ar) == "مهام اليوم")
        #expect(NexusL10n.tr("widget.noOpenTasks", locale: ar) == "لا توجد مهام مفتوحة")
        #expect(NexusL10n.tr("widget.noOpenTasksHint", locale: ar) == "أضف مهمة للبدء بالعمل على هذا المشروع")
        #expect(NexusL10n.tr("widget.chooseProject", locale: ar) == "اختر مشروعًا")
        #expect(NexusL10n.tr("widget.chooseProjectHint", locale: ar).contains("تحرير") ||
                NexusL10n.tr("widget.chooseProjectHint", locale: ar).contains("تعديل"))
        #expect(NexusL10n.tr("widget.openProject", locale: ar) == "فتح المشروع")
        #expect(NexusL10n.tr("widget.selectProject", locale: ar) == "اختيار المشروع")
        #expect(NexusL10n.tr("intent.selectProject.title", locale: ar) == "اختيار المشروع")
        #expect(NexusL10n.tr("intent.unableChangeProject", locale: ar) == "تعذر تغيير المشروع")
        #expect(NexusL10n.tr("intent.projectUnavailable", locale: ar) == "المشروع غير متاح")
        #expect(NexusL10n.tr("widget.addTask", locale: ar) == "إضافة مهمة")
        #expect(NexusL10n.tr("widget.noActiveProjects", locale: ar) == "لا توجد مشاريع نشطة")
    }

    // MARK: - Hamburger selector override applier

    @Test("Project selector override persists per base key; rejects deleted/inactive")
    func selectorOverrideApplier() {
        let suiteName = "group.com.anashamad.Nexus.selectorTest.\(UUID().uuidString)"
        guard let suite = UserDefaults(suiteName: suiteName) else {
            Issue.record("Could not create test suite")
            return
        }
        defer { suite.removePersistentDomain(forName: suiteName) }

        let base = UUID()
        let a = option(name: "Alpha", position: 10)
        let b = option(name: "Beta", position: 20)
        let archivedGhost = UUID()

        #expect(
            WidgetProjectOverrideApplier.apply(
                selectedProjectID: b.id,
                baseProjectID: base,
                activeProjects: [b, a],
                suite: suite
            ) == .applied(projectID: b.id)
        )
        #expect(WidgetProjectSelectionStore.overrideID(forBase: base, suite: suite) == b.id)
        #expect(
            WidgetProjectSelectionStore.storageKey(forBase: base)
                == "nexus.widget.project.override.\(base.uuidString)"
        )

        // Different bases stay isolated
        let base2 = UUID()
        #expect(
            WidgetProjectOverrideApplier.apply(
                selectedProjectID: a.id,
                baseProjectID: base2,
                activeProjects: [a, b],
                suite: suite
            ) == .applied(projectID: a.id)
        )
        #expect(WidgetProjectSelectionStore.overrideID(forBase: base, suite: suite) == b.id)
        #expect(WidgetProjectSelectionStore.overrideID(forBase: base2, suite: suite) == a.id)

        #expect(
            WidgetProjectOverrideApplier.apply(
                selectedProjectID: archivedGhost,
                baseProjectID: base,
                activeProjects: [a, b],
                suite: suite
            ) == .projectUnavailable
        )
        #expect(
            WidgetProjectOverrideApplier.apply(
                selectedProjectID: a.id,
                baseProjectID: nil,
                activeProjects: [a],
                suite: suite
            ) == .invalidBase
        )
        #expect(
            WidgetProjectOverrideApplier.apply(
                selectedProjectID: a.id,
                baseProjectID: base,
                activeProjects: [a],
                suite: nil
            ) == .projectUnavailable
        )
    }

    @Test("Selector query helpers: active only, position order")
    func selectorQueryOrderingMatchesLoad() throws {
        let schema = Schema([Project.self, TaskItem.self, ChecklistItem.self, LabelTag.self, TaskResource.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let c = Project(name: "C", position: 300)
        let a = Project(name: "A", position: 100)
        let b = Project(name: "B", position: 200)
        let archived = Project(name: "Old", status: .archived, position: 0)
        for p in [c, a, b, archived] { context.insert(p) }
        try context.save()

        let loaded = try WidgetStoreAccess.loadActiveProjects(from: context)
        let ordered = WidgetProjectSelectionPolicy.orderedActive(loaded)
        #expect(ordered.map(\.name) == ["A", "B", "C"])
        #expect(ordered.contains(where: { $0.id == archived.id }) == false)
    }

    @Test("Widget selection change reloads only Project Tasks kind")
    func selectorReloadScope() {
        #expect(WidgetReloadClassifier.kinds(for: .widgetProjectSelectionChanged) == [NexusWidgetKind.project])
        #expect(NexusWidgetKind.project == "Nexus.ProjectTasks")
    }

    @Test("English and Arabic select-project intent metadata keys")
    func selectProjectIntentL10n() {
        let en = Locale(identifier: "en")
        let ar = Locale(identifier: "ar")
        #expect(NexusL10n.tr("intent.selectProject.title", locale: en) == "Select Project")
        #expect(NexusL10n.tr("intent.selectProject.prompt", locale: en) == "Choose a Project")
        #expect(NexusL10n.tr("intent.unableChangeProject", locale: en) == "Unable to Change Project")
        #expect(NexusL10n.tr("intent.selectProject.title", locale: ar) == "اختيار المشروع")
        #expect(NexusL10n.tr("intent.selectProject.prompt", locale: ar) == "اختر مشروعًا")
    }

    @Test("Archived projects excluded from configuration list")
    func archivedExcludedFromOptions() throws {
        let schema = Schema([Project.self, TaskItem.self, ChecklistItem.self, LabelTag.self, TaskResource.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        let context = ModelContext(container)

        let active = Project(name: "Live", position: 200)
        let archived = Project(name: "Old", status: .archived, position: 50)
        context.insert(active)
        context.insert(archived)
        try context.save()

        let options = try WidgetStoreAccess.loadActiveProjects(from: context)
        #expect(options.map(\.name) == ["Live"])
        #expect(options.contains(where: { $0.id == archived.id }) == false)
    }

    // MARK: - Quick Add

    @Test("Quick Add creates one root Todo with defaults in selected active project")
    func quickAddCreatesRoot() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "Nexus")
        let first = try TaskRepository(context: context).create(in: project, title: "Existing")

        let created = try WidgetQuickAddService.createRootTask(
            title: "From widget",
            projectID: project.id,
            context: context
        )

        #expect(created.title == "From widget")
        #expect(created.status == .todo)
        #expect(created.priority == .none)
        #expect(created.dueDate == nil)
        #expect(created.reminderDate == nil)
        #expect(created.parentTask == nil)
        #expect(created.isRoot)
        #expect(created.recurrenceRule == nil)
        #expect(created.project?.id == project.id)
        #expect(created.position == FractionalPosition.after(first.position))

        let roots = try TaskRepository(context: context).fetchRootTasks(projectID: project.id)
        #expect(roots.count == 2)
    }

    @Test("Quick Add rejects empty title, archived and deleted projects")
    func quickAddRejectsInvalidProject() throws {
        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let projects = ProjectRepository(context: context)
        let archived = try projects.create(name: "Archived")
        try projects.archive(archived)

        #expect(throws: WidgetQuickAddService.Error.emptyTitle) {
            try WidgetQuickAddService.createRootTask(title: "  ", projectID: archived.id, context: context)
        }
        #expect(throws: WidgetQuickAddService.Error.projectUnavailable) {
            try WidgetQuickAddService.createRootTask(title: "Nope", projectID: archived.id, context: context)
        }
        #expect(throws: WidgetQuickAddService.Error.projectUnavailable) {
            try WidgetQuickAddService.createRootTask(title: "Gone", projectID: UUID(), context: context)
        }
    }

    @Test("Widget quick-add announcement reloads task list widgets without notification reconcile")
    func widgetAnnouncementClassifier() {
        #expect(WidgetReloadClassifier.kinds(for: .widgetTaskCreated) == NexusWidgetKind.allTaskListKinds)
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .widgetTaskCreated) == false)
        #expect(WidgetReloadClassifier.kinds(for: .widgetProjectSelectionChanged) == [NexusWidgetKind.project])
        #expect(WidgetReloadClassifier.shouldReconcileNotifications(for: .widgetProjectSelectionChanged) == false)
    }

    @Test("Shared-store failure never creates a fallback store")
    func noFallbackStorePolicy() {
        #expect(WidgetQuickAddService.createsFallbackStoreOnSharedFailure == false)
        #expect(WidgetStoreAccess.createsFallbackStoreOnSharedFailure == false)
    }

    @Test("Widget project picker deep link with baseProjectID")
    func widgetProjectPickerDeepLink() {
        let base = UUID()
        let url = NexusDeepLink.widgetProjectPicker(baseProjectID: base).url
        #expect(url.scheme == "nexus")
        #expect(url.host == "widget")
        #expect(url.path.contains("project-picker"))
        #expect(NexusDeepLink(url: url) == .widgetProjectPicker(baseProjectID: base))

        let missingBase = URL(string: "nexus://widget/project-picker")!
        #expect(NexusDeepLink(url: missingBase) == .widgetProjectPicker(baseProjectID: nil))

        let badUUID = URL(string: "nexus://widget/project-picker?baseProjectID=not-a-uuid")!
        #expect(NexusDeepLink(url: badUUID) == .widgetProjectPicker(baseProjectID: nil))

        let wrongPath = URL(string: "nexus://widget/other")!
        #expect(NexusDeepLink(url: wrongPath) == nil)

        #expect(WidgetReloadClassifier.kinds(for: .widgetProjectSelectionChanged) == [NexusWidgetKind.project])
    }

    @Test("Arabic keys for picker failure and selection")
    func pickerArabicKeys() {
        let ar = Locale(identifier: "ar")
        #expect(NexusL10n.tr("widget.selectProject", locale: ar) == "اختيار المشروع")
        #expect(NexusL10n.tr("widgetPicker.unableIdentify", locale: ar) == "تعذر تحديد الويدجت")
        #expect(NexusL10n.tr("widget.noActiveProjects", locale: ar) == "لا توجد مشاريع نشطة")
        #expect(NexusL10n.tr("widget.projectUnavailable", locale: ar) == "المشروع غير متاح")
        let en = Locale(identifier: "en")
        #expect(NexusL10n.tr("widgetPicker.unableIdentify", locale: en) == "Unable to identify widget")
        #expect(NexusL10n.tr("widget.selectProject", locale: en) == "Select Project")
    }

    @Test("Full editor deep link still works")
    func fullEditorDeepLink() {
        #expect(NexusDeepLink.quickAdd.url.absoluteString == "nexus://quick-add")
        #expect(NexusDeepLink(url: NexusDeepLink.quickAdd.url) == .quickAdd)
        #expect(NexusDeepLink.projects.url.absoluteString == "nexus://projects")
    }
}
