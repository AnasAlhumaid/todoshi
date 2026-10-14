import SwiftUI
import SwiftData
import TodoshiCore

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppRouter.self) private var router
    @Environment(AuthSessionController.self) private var authSession
    @Query private var projects: [Project]

    @State private var isCreatingProject = false
    @State private var creatingTaskProjectID: UUID?
    @State private var actionError: String?
    /// Tasks checked off on Home stay visible (struck through) until the screen goes away,
    /// so a mistaken tap can be undone by tapping again.
    @State private var checkedOff: [UUID: CheckedOffTask] = [:]

    private struct CheckedOffTask {
        let task: DashboardTaskInput
        let previousStatus: TaskStatus
        let section: HomeListSection
        let index: Int
    }

    private enum HomeListSection { case today, unscheduled }

    private var summaries: [HomeProjectSummary] {
        HomeMapping.projectSummaries(
            from: projects,
            collaborationUID: authSession.currentSession?.user.id
        )
    }

    var body: some View {
        Group {
            if summaries.isEmpty {
                emptyNoProjects
            } else {
                projectOverview
            }
        }
        .navigationTitle(TodoshiL10n.tr("dashboard.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The greeting header replaces the bar title on Home.
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1) }
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    Button(TodoshiL10n.tr("project.new")) {
                        isCreatingProject = true
                    }
                    NavigationLink(value: AppRoute.archivedProjects) {
                        Text(TodoshiL10n.tr("project.archivedTitle"))
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel(TodoshiL10n.tr("home.projectActions"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.showSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .fontWeight(.semibold)
                }
                .accessibilityLabel(AppTab.settings.title)
            }
        }
        .sheet(isPresented: $isCreatingProject) {
            NavigationStack {
                ProjectFormView(context: modelContext)
            }
        }
        .sheet(isPresented: Binding(
            get: { creatingTaskProjectID != nil },
            set: { if !$0 { creatingTaskProjectID = nil } }
        )) {
            NavigationStack {
                if let creatingTaskProjectID {
                    TaskFormView(
                        context: modelContext,
                        projectID: creatingTaskProjectID,
                        taskID: nil,
                        initialStatus: .todo
                    )
                }
            }
        }
        .alert(
            TodoshiL10n.tr("common.somethingWrong"),
            isPresented: Binding(
                get: { actionError != nil },
                set: { if !$0 { actionError = nil } }
            )
        ) {
            Button(TodoshiL10n.tr("common.ok"), role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    private var todaySnapshot: DashboardSnapshot {
        DashboardMapping.snapshot(projects: projects)
    }

    private var projectOverview: some View {
        let today = todaySnapshot
        let todayTasks = withCheckedOff(today.overdue + today.dueToday, in: .today)
        return ScrollView {
            VStack(alignment: .leading, spacing: TodoshiSpacing.md) {
                homeHeader

                HomeTodayCard(
                    completed: today.metrics.completedToday,
                    remaining: todayTasks.filter { $0.status != .done }.count,
                    overdue: today.overdue.count
                )

                if todayTasks.isEmpty {
                    Text(TodoshiL10n.tr("home.today.empty"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, TodoshiSpacing.lg)
                        .todoshiSurface()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(todayTasks.enumerated()), id: \.element.id) { index, task in
                            HomeTodayTaskRow(task: task) {
                                toggleCompletion(task, at: index, in: .today)
                            }
                            if index < todayTasks.count - 1 {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    .padding(.horizontal, TodoshiSpacing.md)
                    .padding(.vertical, TodoshiSpacing.xxs)
                    .todoshiSurface()
                }

                if !unscheduled.isEmpty || checkedOff.values.contains(where: { $0.section == .unscheduled }) {
                    sectionHeader(
                        CalendarStrings.unscheduled,
                        count: unscheduled.count,
                        seeAll: unscheduled.count > Self.unscheduledPreviewLimit ? .unscheduled : nil
                    )
                    let preview = withCheckedOff(
                        Array(unscheduled.prefix(Self.unscheduledPreviewLimit)),
                        in: .unscheduled
                    )
                    VStack(spacing: 0) {
                        ForEach(Array(preview.enumerated()), id: \.element.id) { index, task in
                            HomeTodayTaskRow(task: task) {
                                toggleCompletion(task, at: index, in: .unscheduled)
                            }
                            if index < preview.count - 1 {
                                Divider().opacity(0.5)
                            }
                        }
                    }
                    .padding(.horizontal, TodoshiSpacing.md)
                    .padding(.vertical, TodoshiSpacing.xxs)
                    .todoshiSurface()
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(TodoshiL10n.tr("home.yourProjects"))
                        .font(.title3.weight(.bold))
                    Spacer()
                    NavigationLink(value: AppRoute.allProjects) {
                        Text(TodoshiL10n.tr("home.seeAll"))
                            .font(.subheadline.weight(.medium))
                    }
                }
                .padding(.top, TodoshiSpacing.xs)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: TodoshiSpacing.sm), GridItem(.flexible())],
                    spacing: TodoshiSpacing.sm
                ) {
                    ForEach(summaries) { project in
                        NavigationLink(value: AppRoute.project(project.id)) {
                            HomeProjectTile(project: project)
                        }
                        .buttonStyle(.plain)
                    }
                    Button {
                        isCreatingProject = true
                    } label: {
                        HomeNewProjectTile()
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, TodoshiSpacing.md)
            .padding(.top, TodoshiSpacing.xs)
            .padding(.bottom, TodoshiBrand.tabBarScrollInset)
        }
        .background(TodoshiBrand.groupedBackground)
        .onDisappear { checkedOff = [:] }
    }

    /// Re-inserts checked-off tasks at the row they occupied so the list does not jump.
    private func withCheckedOff(_ tasks: [DashboardTaskInput], in section: HomeListSection) -> [DashboardTaskInput] {
        var result = tasks.filter { checkedOff[$0.id] == nil }
        let kept = checkedOff.values
            .filter { $0.section == section }
            .sorted { $0.index < $1.index }
        for entry in kept {
            result.insert(entry.task, at: min(entry.index, result.count))
        }
        return result
    }

    private func toggleCompletion(_ task: DashboardTaskInput, at index: Int, in section: HomeListSection) {
        if let entry = checkedOff[task.id] {
            guard commitMove(taskID: task.id, to: entry.previousStatus) else { return }
            withAnimation(.snappy) { checkedOff[task.id] = nil }
            return
        }
        guard commitMove(taskID: task.id, to: .done) else { return }
        let doneTask = DashboardTaskInput(
            id: task.id,
            title: task.title,
            status: .done,
            priority: task.priority,
            dueDate: task.dueDate,
            completedAt: .now,
            updatedAt: .now,
            position: task.position,
            projectID: task.projectID,
            projectName: task.projectName,
            projectIcon: task.projectIcon,
            projectColorHex: task.projectColorHex,
            projectIsActive: task.projectIsActive
        )
        withAnimation(.snappy) {
            checkedOff[task.id] = CheckedOffTask(
                task: doneTask,
                previousStatus: task.status,
                section: section,
                index: index
            )
        }
    }

    private static let unscheduledPreviewLimit = 5

    /// Open root tasks without a due date, so undated work still surfaces on Home.
    private var unscheduled: [DashboardTaskInput] {
        CalendarScheduleBuilder.unscheduledSources(tasks: CalendarMapping.taskSources(projects: projects))
            .map { source in
                DashboardTaskInput(
                    id: source.id,
                    title: source.title,
                    status: source.status,
                    priority: source.priority,
                    dueDate: nil,
                    updatedAt: source.updatedAt,
                    position: source.position,
                    projectID: source.projectID,
                    projectName: source.projectName,
                    projectIcon: source.projectIcon,
                    projectColorHex: source.projectColorHex,
                    projectIsActive: source.projectIsActive
                )
            }
    }

    private func sectionHeader(_ title: String, count: Int, seeAll: AppRoute?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: TodoshiSpacing.xs) {
            Text(title)
                .font(.title3.weight(.bold))
            Text(count, format: .number)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            if let seeAll {
                NavigationLink(value: seeAll) {
                    Text(TodoshiL10n.tr("home.seeAll"))
                        .font(.subheadline.weight(.medium))
                }
            }
        }
        .padding(.top, TodoshiSpacing.xs)
    }

    private var homeHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now, format: .dateTime.weekday(.wide).day().month(.wide))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(greeting)
                .font(.largeTitle.weight(.bold))
        }
        .accessibilityElement(children: .combine)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let base: String
        switch hour {
        case 5..<12: base = TodoshiL10n.tr("home.greeting.morning")
        case 12..<17: base = TodoshiL10n.tr("home.greeting.afternoon")
        default: base = TodoshiL10n.tr("home.greeting.evening")
        }
        guard let name = authSession.currentSession?.user.displayName?
            .split(separator: " ").first, !name.isEmpty else { return base }
        return TodoshiL10n.format("home.greeting.named", base, String(name))
    }

    private var emptyNoProjects: some View {
        TodoshiEmptyState(
            title: TodoshiL10n.tr("home.noProjects"),
            message: TodoshiL10n.tr("home.noProjectsMessage"),
            systemImage: "folder.badge.plus",
            actionTitle: TodoshiL10n.tr("dashboard.createProject"),
            action: { isCreatingProject = true }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(TodoshiBrand.groupedBackground)
    }

    @discardableResult
    private func commitMove(taskID: UUID, to status: TaskStatus) -> Bool {
        let repo = TaskRepository(context: modelContext)
        do {
            let previousStatus = try repo.fetchTask(id: taskID)?.status
            let didWrite = try repo.move(taskID: taskID, to: status, before: nil)
            if didWrite {
                TodoshiHaptics.taskStatusChanged(crossStatus: previousStatus != status)
            }
            return didWrite
        } catch {
            actionError = UserFacingError.message(for: error)
            return false
        }
    }
}

// MARK: - Home components

struct HomeTodayCard: View {
    let completed: Int
    let remaining: Int
    let overdue: Int

    private var total: Int { completed + remaining }
    private var fraction: Double { total == 0 ? 1 : Double(completed) / Double(total) }

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.sm) {
            HStack(alignment: .firstTextBaseline) {
                Text(TodoshiL10n.tr("home.today.title"))
                    .font(.headline)
                Spacer()
                Text(TodoshiL10n.format("home.today.progress", completed, total))
                    .font(.subheadline)
                    .opacity(0.85)
            }
            ProgressView(value: fraction)
                .tint(.white)
                .background(Color.white.opacity(0.25), in: Capsule())
            if remaining > 0 {
                Text(subtitle)
                    .font(.footnote)
                    .opacity(0.85)
            }
        }
        .foregroundStyle(.white)
        .padding(TodoshiSpacing.md)
        // Fixed deep indigo in both appearances: the dark-mode accent is too light for white text.
        .background(Color(red: 0.322, green: 0.282, blue: 0.851), in: RoundedRectangle(cornerRadius: TodoshiRadius.card + 4, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        var parts = [TodoshiL10n.format("home.today.remaining", remaining)]
        if overdue > 0 {
            parts.append(TodoshiL10n.format("home.today.overdueSuffix", overdue))
        }
        return parts.joined(separator: " · ")
    }
}

struct HomeTodayTaskRow: View {
    let task: DashboardTaskInput
    let onComplete: () -> Void

    private var isOverdue: Bool { TaskPredicates.isOverdue(task.dueDate, status: task.status) }
    private var isDone: Bool { task.status == .done }

    var body: some View {
        HStack(spacing: TodoshiSpacing.sm) {
            TodoshiCompletionCircle(isDone: isDone, isOverdue: isOverdue, action: onComplete)

            NavigationLink(value: AppRoute.task(task.id)) {
                HStack(spacing: TodoshiSpacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title)
                            .font(.body)
                            .foregroundStyle(isDone ? .secondary : .primary)
                            .strikethrough(isDone, color: .secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Group {
                            if isOverdue && !isDone {
                                Text(TodoshiL10n.tr("common.overdue"))
                                    .foregroundStyle(.red)
                            } else {
                                Text(task.projectName)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.footnote)
                    }
                    Spacer(minLength: 0)
                    Circle()
                        .fill(TodoshiColor.from(hex: task.projectColorHex))
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: NavigationHitTargetPolicy.minimumRowHitHeightPoints)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, TodoshiSpacing.xs)
    }
}

struct HomeProjectTile: View {
    let project: HomeProjectSummary

    private var tint: Color { TodoshiColor.from(hex: project.colorHex) }

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.xs) {
            Image(systemName: project.projectType == .checklist ? "checklist" : project.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
            Spacer(minLength: TodoshiSpacing.xs)
            Text(project.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(countLabel)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .leading)
        .padding(TodoshiSpacing.md)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: TodoshiRadius.card + 2, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var countLabel: String {
        project.projectType == .checklist
            ? ProjectTerminologyPolicy.openItemsCount(project.openTaskCount)
            : TodoshiL10n.plural("widget.openTasksCount", count: project.openTaskCount)
    }
}

struct HomeNewProjectTile: View {
    var body: some View {
        VStack(spacing: TodoshiSpacing.xs) {
            Image(systemName: "plus")
                .font(.title3.weight(.semibold))
            Text(TodoshiL10n.tr("home.newProject"))
                .font(.subheadline.weight(.medium))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 112 + TodoshiSpacing.md * 2)
        .background {
            RoundedRectangle(cornerRadius: TodoshiRadius.card + 2, style: .continuous)
                .strokeBorder(TodoshiBrand.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
        }
        .contentShape(Rectangle())
    }
}

// MARK: - All projects

struct ProjectsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthSessionController.self) private var authSession
    @Query private var projects: [Project]

    @State private var filter: Filter = .all
    @State private var isCreatingProject = false

    enum Filter: CaseIterable, Identifiable {
        case all, tasks, checklists, shared
        var id: Self { self }
        var title: String {
            switch self {
            case .all: return TodoshiL10n.tr("projects.filter.all")
            case .tasks: return TodoshiL10n.tr("projects.filter.tasks")
            case .checklists: return TodoshiL10n.tr("projects.filter.checklists")
            case .shared: return TodoshiL10n.tr("projects.filter.shared")
            }
        }
    }

    private var summaries: [HomeProjectSummary] {
        HomeMapping.projectSummaries(from: projects, collaborationUID: authSession.currentSession?.user.id)
            .filter { summary in
                switch filter {
                case .all: return true
                case .tasks: return summary.projectType == .tasks
                case .checklists: return summary.projectType == .checklist
                case .shared: return summary.isShared
                }
            }
    }

    private func totals(for id: UUID) -> (open: Int, total: Int) {
        guard let project = projects.first(where: { $0.id == id }) else { return (0, 0) }
        let input = DashboardMapping.projectInput(from: project)
        return (input.openRootCount, input.totalRootCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: TodoshiSpacing.sm) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: TodoshiSpacing.xs) {
                        ForEach(Filter.allCases) { item in
                            Button(item.title) { filter = item }
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, TodoshiSpacing.md)
                                .padding(.vertical, TodoshiSpacing.xs)
                                .foregroundStyle(filter == item ? Color.white : Color.secondary)
                                .background(
                                    filter == item ? TodoshiBrand.accent : TodoshiBrand.cardBackground,
                                    in: Capsule()
                                )
                                .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(summaries) { project in
                    let counts = totals(for: project.id)
                    NavigationLink(value: AppRoute.project(project.id)) {
                        ProjectOverviewCard(project: project, open: counts.open, total: counts.total)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    isCreatingProject = true
                } label: {
                    Label(TodoshiL10n.tr("home.newProject"), systemImage: "plus")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 56)
                        .background {
                            RoundedRectangle(cornerRadius: TodoshiRadius.card, style: .continuous)
                                .strokeBorder(TodoshiBrand.borderStrong, style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, TodoshiSpacing.md)
            .padding(.bottom, TodoshiBrand.tabBarScrollInset)
        }
        .background(TodoshiBrand.groupedBackground)
        .navigationTitle(TodoshiL10n.tr("projects.title"))
        .navigationBarTitleDisplayMode(.large)
        .sheet(isPresented: $isCreatingProject) {
            NavigationStack {
                ProjectFormView(context: modelContext)
            }
        }
    }
}

struct ProjectOverviewCard: View {
    let project: HomeProjectSummary
    let open: Int
    let total: Int

    private var tint: Color { TodoshiColor.from(hex: project.colorHex) }
    private var overdueCount: Int { project.tasks.filter(\.isOverdue).count }
    private var fraction: Double { total == 0 ? 0 : Double(total - open) / Double(total) }

    var body: some View {
        VStack(alignment: .leading, spacing: TodoshiSpacing.sm) {
            HStack(spacing: TodoshiSpacing.sm) {
                TodoshiProjectIconWell(
                    systemName: project.icon,
                    colorHex: project.colorHex,
                    size: 42,
                    projectType: project.projectType
                )
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: TodoshiSpacing.xxs) {
                        Text(project.name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        if project.isShared {
                            Image(systemName: SharedProjectPresentation.indicatorSystemImage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(SharedProjectPresentation.accessibilityLabel())
                        }
                    }
                    subtitle
                        .font(.footnote)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            ProgressView(value: fraction)
                .tint(tint)
        }
        .padding(TodoshiSpacing.md)
        .todoshiSurface()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var subtitle: some View {
        if project.projectType == .checklist {
            Text(TodoshiL10n.format("projects.listProgress", total - open, total))
                .foregroundStyle(.secondary)
        } else if overdueCount > 0 {
            Text(TodoshiL10n.format("projects.openCount", open)).foregroundStyle(.secondary)
                + Text(" · ").foregroundStyle(.secondary)
                + Text(TodoshiL10n.format("projects.overdueCount", overdueCount)).foregroundStyle(.red)
        } else {
            Text(TodoshiL10n.format("projects.openCount", open))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        DashboardView()
    }
    .environment(AppRouter())
    .modelContainer(try! ModelContainerFactory.makeContainer(kind: .inMemory))
}
