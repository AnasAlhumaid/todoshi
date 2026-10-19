import AppIntents
import WidgetKit
import SwiftUI
import TodoshiCore

// MARK: - Entity & configuration

struct TodoshiProjectEntity: AppEntity {
    // App Intents metadata requires string-literal LocalizedStringResource initializers.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: "widget.configProject"
    )
    static var defaultQuery = TodoshiProjectEntityQuery()

    var id: UUID
    var name: String
    var icon: String
    var colorHex: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: nil,
            image: .init(systemName: icon)
        )
    }

    init(id: UUID, name: String, icon: String, colorHex: String) {
        self.id = id
        self.name = name
        self.icon = icon
        self.colorHex = colorHex
    }

    init(option: WidgetProjectOption) {
        self.id = option.id
        self.name = option.name
        self.icon = option.icon
        self.colorHex = option.colorHex
    }
}

struct TodoshiProjectEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [TodoshiProjectEntity] {
        let projects = (try? await loadProjects()) ?? []
        return identifiers.compactMap { id in
            projects.first(where: { $0.id == id }).map(TodoshiProjectEntity.init)
        }
    }

    func suggestedEntities() async throws -> [TodoshiProjectEntity] {
        try await loadProjects().map(TodoshiProjectEntity.init)
    }

    func defaultResult() async -> TodoshiProjectEntity? {
        try? await loadProjects().first.map(TodoshiProjectEntity.init)
    }

    private func loadProjects() async throws -> [WidgetProjectOption] {
        try await MainActor.run {
            try WidgetSnapshotLoader.loadActiveProjects()
        }
    }
}

struct ProjectWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "widget.projectTasks"
    static var description = IntentDescription("widget.projectTasksDesc")

    @Parameter(title: "widget.project")
    var project: TodoshiProjectEntity?

    init() {}

    init(project: TodoshiProjectEntity?) {
        self.project = project
    }
}

// MARK: - Provider

struct ProjectTasksProvider: AppIntentTimelineProvider {
    typealias Intent = ProjectWidgetConfigurationIntent
    typealias Entry = TodoshiWidgetEntry

    func placeholder(in context: Context) -> TodoshiWidgetEntry {
        TodoshiWidgetEntry(
            date: .now,
            snapshot: WidgetPreviewData.projectPlaceholder(),
            state: .content,
            projectInteraction: ProjectWidgetInteraction(
                baseConfigurationProjectID: UUID(),
                displayedProjectID: UUID(),
                projectName: WidgetPreviewData.projectPlaceholder().title,
                projectIcon: "folder.fill",
                projectColorHex: ProjectColorCatalog.defaultHex,
                projectType: .tasks,
                allowsProjectSelection: true,
                allowsQuickAdd: true
            )
        )
    }

    func snapshot(for configuration: ProjectWidgetConfigurationIntent, in context: Context) async -> TodoshiWidgetEntry {
        await MainActor.run {
            Self.loadEntry(configuration: configuration, now: .now)
        }
    }

    func timeline(for configuration: ProjectWidgetConfigurationIntent, in context: Context) async -> Timeline<TodoshiWidgetEntry> {
        let entry = await MainActor.run {
            Self.loadEntry(configuration: configuration, now: .now)
        }
        return TodoshiWidgetTimeline.timeline(for: entry)
    }

    @MainActor
    private static func loadEntry(configuration: ProjectWidgetConfigurationIntent, now: Date) -> TodoshiWidgetEntry {
        do {
            let baseID = configuration.project?.id
            let loaded = try WidgetSnapshotLoader.loadConfiguredProjectEntry(
                baseConfigurationProjectID: baseID,
                referenceDate: now,
                limit: WidgetSnapshotBuilder.defaultProjectLimit
            )
            let state: WidgetLoadState
            switch loaded.snapshot.projectAvailability {
            case .missingSelection:
                state = .needsConfiguration
            case .unavailable:
                state = .projectUnavailable
            case .available:
                state = WidgetProjectPresentation.isProjectWidgetEmpty(
                    projectType: loaded.snapshot.projectType,
                    remainingCount: loaded.snapshot.totalCount,
                    allRootCount: loaded.snapshot.allRootCount
                ) ? .empty : .content
            }
            return TodoshiWidgetEntry(
                date: now,
                snapshot: loaded.snapshot,
                state: state,
                projectInteraction: loaded.interaction
            )
        } catch {
            return TodoshiWidgetEntry(
                date: now,
                snapshot: .unavailable(title: TodoshiL10n.tr("common.project"), generatedAt: now),
                state: .storeUnavailable
            )
        }
    }
}

// MARK: - View

struct ProjectTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: TodoshiWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .storeUnavailable:
                emptyShell(
                    title: WidgetStrings.openTodoshi,
                    message: WidgetStrings.openTodoshi,
                    link: TodoshiDeepLink.projects.url,
                    allowsProjectSelection: false,
                    allowsQuickAdd: false
                )
            case .needsConfiguration:
                let noActive = entry.projectInteraction?.hasActiveProjects == false
                emptyShell(
                    title: noActive ? WidgetStrings.noActiveProjects : WidgetStrings.chooseProject,
                    message: noActive ? WidgetStrings.noActiveProjectsHint : WidgetStrings.chooseProjectHint,
                    link: TodoshiDeepLink.projects.url,
                    allowsProjectSelection: false,
                    allowsQuickAdd: false
                )
            case .projectUnavailable:
                emptyShell(
                    title: WidgetStrings.projectUnavailable,
                    message: WidgetStrings.projectUnavailable,
                    link: TodoshiDeepLink.projects.url,
                    allowsProjectSelection: entry.projectInteraction?.allowsProjectSelection == true,
                    allowsQuickAdd: false
                )
            case .empty:
                projectLayout(isEmpty: true)
            case .content:
                projectLayout(isEmpty: false)
            }
        }
        .fontDesign(.rounded)
        // Follow the in-app language direction, which can differ from the system's.
        .environment(\.layoutDirection, AppLanguageStore.isRightToLeft ? .rightToLeft : .leftToRight)
        .containerBackground(for: .widget) {
            ZStack {
                WidgetTheme.canvas
                projectTint.opacity(0.10)
            }
        }
        .widgetURL(projectLink)
    }

    private var projectTint: Color {
        Color(hex: entry.projectInteraction?.projectColorHex ?? entry.snapshot.projectColorHex ?? ProjectColorCatalog.defaultHex)
    }

    private var projectLink: URL {
        if let id = entry.snapshot.projectID,
           entry.state != .projectUnavailable,
           entry.state != .needsConfiguration,
           entry.state != .storeUnavailable {
            return TodoshiDeepLink.project(id).url
        }
        return TodoshiDeepLink.projects.url
    }

    private var projectType: ProjectType {
        entry.snapshot.projectType
    }

    private var presentationProjectType: ProjectType {
        entry.projectInteraction?.projectType ?? projectType
    }

    private var displayLimit: Int {
        switch family {
        case .systemSmall: return WidgetSnapshotBuilder.projectFamilyLimitSmall
        case .systemMedium: return WidgetSnapshotBuilder.projectFamilyLimitMedium
        default: return WidgetSnapshotBuilder.projectFamilyLimitLarge
        }
    }

    private var shownTasks: [WidgetTaskItem] {
        Array(entry.snapshot.tasks.prefix(displayLimit))
    }

    // MARK: Layouts

    @ViewBuilder
    private func emptyShell(
        title: String,
        message: String,
        link: URL,
        allowsProjectSelection: Bool,
        allowsQuickAdd: Bool
    ) -> some View {
        ProjectWidgetChrome(
            interaction: entry.projectInteraction,
            title: title,
            openCount: nil,
            projectType: presentationProjectType,
            projectLink: link,
            allowsQuickAdd: allowsQuickAdd,
            allowsProjectSelection: allowsProjectSelection,
            family: family,
            showIcon: family != .systemSmall
        ) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(family == .systemSmall ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(family == .systemSmall ? 3 : 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func projectLayout(isEmpty: Bool) -> some View {
        switch family {
        case .systemSmall:
            smallLayout(isEmpty: isEmpty)
        case .systemMedium:
            mediumLayout(isEmpty: isEmpty)
        default:
            largeLayout(isEmpty: isEmpty)
        }
    }

    // MARK: Small — identity, count, optional first task, add

    @ViewBuilder
    private func smallLayout(isEmpty: Bool) -> some View {
        ProjectWidgetChrome(
            interaction: entry.projectInteraction,
            title: entry.snapshot.title,
            openCount: entry.snapshot.totalCount,
            projectType: presentationProjectType,
            projectLink: projectLink,
            allowsQuickAdd: entry.projectInteraction?.allowsQuickAdd == true,
            allowsProjectSelection: entry.projectInteraction?.allowsProjectSelection == true,
            family: .systemSmall,
            showIcon: false
        ) {
            if isEmpty {
                Text(WidgetProjectPresentation.emptyTitle(for: presentationProjectType))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let first = shownTasks.first {
                Link(destination: TodoshiDeepLink.task(first.id).url) {
                    ProjectWidgetTaskTitle(
                        task: first,
                        projectType: presentationProjectType,
                        style: .compact
                    )
                }
            }
        }
        .accessibilityLabel(
            WidgetProjectPresentation.openCountAccessibilityLabel(
                title: entry.snapshot.title,
                remaining: entry.snapshot.totalCount,
                projectType: presentationProjectType
            )
        )
    }

    // MARK: Medium — name + switchers, up to 3 tasks, add

    @ViewBuilder
    private func mediumLayout(isEmpty: Bool) -> some View {
        ProjectWidgetChrome(
            interaction: entry.projectInteraction,
            title: entry.snapshot.title,
            openCount: entry.snapshot.totalCount,
            projectType: presentationProjectType,
            projectLink: projectLink,
            allowsQuickAdd: entry.projectInteraction?.allowsQuickAdd == true,
            allowsProjectSelection: entry.projectInteraction?.allowsProjectSelection == true,
            family: .systemMedium,
            showIcon: false
        ) {
            if isEmpty {
                emptyBody(compact: true)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(shownTasks) { task in
                        ProjectWidgetTaskRow(task: task, projectType: presentationProjectType, style: .compact)
                    }
                    if entry.snapshot.totalCount > shownTasks.count {
                        Text(WidgetStrings.remaining(entry.snapshot.totalCount - shownTasks.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(
            WidgetProjectPresentation.openCountAccessibilityLabel(
                title: entry.snapshot.title,
                remaining: entry.snapshot.totalCount,
                projectType: presentationProjectType
            )
        )
    }

    // MARK: Large — full header, up to 6 tasks, footer actions

    @ViewBuilder
    private func largeLayout(isEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectWidgetHeader(
                interaction: entry.projectInteraction,
                title: entry.snapshot.title,
                openCount: entry.snapshot.totalCount,
                projectType: presentationProjectType,
                projectLink: projectLink,
                allowsProjectSelection: entry.projectInteraction?.allowsProjectSelection == true,
                showIcon: true,
                showOpenCount: true
            )

            if isEmpty {
                emptyBody(compact: false)
                Spacer(minLength: 0)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(shownTasks) { task in
                        ProjectWidgetTaskRow(task: task, projectType: presentationProjectType, style: .detailed)
                    }
                }
                Spacer(minLength: 0)
            }

            ProjectWidgetFooter(
                interaction: entry.projectInteraction,
                projectType: presentationProjectType,
                projectLink: projectLink,
                remaining: max(0, entry.snapshot.totalCount - shownTasks.count),
                allowsQuickAdd: entry.projectInteraction?.allowsQuickAdd == true
            )
        }
        .accessibilityLabel(
            WidgetProjectPresentation.openCountAccessibilityLabel(
                title: entry.snapshot.title,
                remaining: entry.snapshot.totalCount,
                projectType: presentationProjectType
            )
        )
    }

    @ViewBuilder
    private func emptyBody(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WidgetProjectPresentation.emptyTitle(for: presentationProjectType))
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(WidgetProjectPresentation.emptySubtitle(for: presentationProjectType))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Header / chrome

private struct ProjectWidgetChrome<Content: View>: View {
    let interaction: ProjectWidgetInteraction?
    let title: String
    let openCount: Int?
    let projectType: ProjectType
    let projectLink: URL
    let allowsQuickAdd: Bool
    let allowsProjectSelection: Bool
    let family: WidgetFamily
    let showIcon: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: family == .systemSmall ? 6 : 8) {
            ProjectWidgetHeader(
                interaction: interaction,
                title: title,
                openCount: openCount,
                projectType: projectType,
                projectLink: projectLink,
                allowsProjectSelection: allowsProjectSelection,
                showIcon: showIcon,
                showOpenCount: openCount != nil && family != .systemMedium,
                addButton: family == .systemMedium && allowsQuickAdd
                    ? ProjectAddTaskButton(
                        projectID: interaction?.displayedProjectID,
                        projectName: interaction?.projectName ?? title,
                        projectType: projectType
                    )
                    : nil
            )
            content()
            Spacer(minLength: 0)
            if family == .systemSmall {
                HStack {
                    if allowsQuickAdd {
                        ProjectAddTaskButton(
                            projectID: interaction?.displayedProjectID,
                            projectName: interaction?.projectName ?? title,
                            projectType: projectType
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct ProjectWidgetHeader: View {
    let interaction: ProjectWidgetInteraction?
    let title: String
    let openCount: Int?
    let projectType: ProjectType
    let projectLink: URL
    /// Shows the hamburger project selector when a base Edit Widget project exists.
    let allowsProjectSelection: Bool
    let showIcon: Bool
    let showOpenCount: Bool
    /// Medium places the add button here so the task list gets the full height.
    var addButton: ProjectAddTaskButton? = nil

    var body: some View {
        HStack(spacing: 6) {
            if showIcon {
                let tint = Color(hex: interaction?.projectColorHex ?? ProjectColorCatalog.defaultHex)
                Image(systemName: projectType == .checklist ? "checklist" : (interaction?.projectIcon ?? "folder"))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 26, height: 26)
                    .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
            }

            Link(destination: projectLink) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if showOpenCount, let openCount {
                        Text(WidgetProjectPresentation.primaryCountText(remaining: openCount, projectType: projectType))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .accessibilityLabel(WidgetStrings.currentProject(title))

            Spacer(minLength: 4)

            if allowsProjectSelection, let base = interaction?.baseConfigurationProjectID {
                // Deep link opens in-app picker. App Intent parameter UI is unreliable from Home Screen widgets.
                Link(destination: TodoshiDeepLink.widgetProjectPicker(baseProjectID: base).url) {
                    Image(systemName: "line.3.horizontal")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WidgetStrings.selectProject)
            }

            if let addButton {
                addButton
            }
        }
    }
}

private struct ProjectWidgetFooter: View {
    let interaction: ProjectWidgetInteraction?
    let projectType: ProjectType
    let projectLink: URL
    let remaining: Int
    let allowsQuickAdd: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if remaining > 0 {
                Text(WidgetStrings.remaining(remaining))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if allowsQuickAdd {
                    ProjectAddTaskButton(
                        projectID: interaction?.displayedProjectID,
                        projectName: interaction?.projectName ?? "",
                        projectType: projectType,
                        style: .labeled
                    )
                }
                Link(destination: projectLink) {
                    Label(
                        WidgetProjectPresentation.openActionTitle(for: projectType),
                        systemImage: "arrow.up.right.square"
                    )
                    .font(.caption.weight(.semibold))
                    .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel(WidgetProjectPresentation.openActionTitle(for: projectType))
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ProjectAddTaskButton: View {
    let projectID: UUID?
    let projectName: String
    let projectType: ProjectType
    var style: Style = .icon

    enum Style {
        case icon
        case labeled
    }

    var body: some View {
        if let projectID {
            Link(destination: TodoshiDeepLink.quickAdd(projectID: projectID).url) {
                label
            }
            .accessibilityLabel(
                WidgetProjectPresentation.addAccessibilityLabel(projectName: projectName, projectType: projectType)
            )
        } else {
            Link(destination: TodoshiDeepLink.quickAdd().url) {
                label
            }
            .accessibilityLabel(WidgetProjectPresentation.addActionTitle(for: projectType))
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .icon:
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(WidgetTheme.accent, in: Circle())
        case .labeled:
            Label(
                WidgetProjectPresentation.addActionTitle(for: projectType),
                systemImage: "plus"
            )
            .font(.caption.weight(.bold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(WidgetTheme.accent, in: Capsule())
        }
    }
}

// MARK: - Task rows

private struct ProjectWidgetTaskTitle: View {
    let task: WidgetTaskItem
    let projectType: ProjectType
    let style: ProjectWidgetTaskRow.Style

    private var isCompleted: Bool { task.status == .done }

    var body: some View {
        HStack(spacing: 4) {
            if projectType == .checklist && isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(task.title)
                .font(style == .compact ? .footnote.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(isCompleted ? .secondary : .primary)
                .strikethrough(isCompleted, color: .secondary)
                .lineLimit(style == .compact ? 1 : 2)
                .minimumScaleFactor(0.85)
                .privacySensitive()
        }
    }
}

private struct ProjectWidgetTaskRow: View {
    enum Style {
        case compact
        case detailed
    }

    let task: WidgetTaskItem
    let projectType: ProjectType
    let style: Style

    private var isCompleted: Bool { task.status == .done }

    var body: some View {
        Link(destination: TodoshiDeepLink.task(task.id).url) {
            VStack(alignment: .leading, spacing: 2) {
                ProjectWidgetTaskTitle(task: task, projectType: projectType, style: style)

                // Compact rows (small/medium) stay one line each so the add button never clips.
                if style == .detailed {
                    HStack(spacing: 4) {
                        Text(WidgetProjectPresentation.statusLabel(task.status, projectType: projectType))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        if style == .detailed, projectType == .tasks {
                            if task.priority == .urgent || task.priority == .high {
                                Text(task.priority.displayName)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(task.priority == .urgent ? .red : .orange)
                                    .lineLimit(1)
                            }
                            if task.isOverdue {
                                Text(TodoshiL10n.tr("common.overdue"))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.red)
                                    .lineLimit(1)
                            } else if let due = task.dueDate {
                                Text(due, style: .date)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(
            WidgetProjectPresentation.taskRowAccessibilityLabel(
                title: task.title,
                status: task.status,
                projectType: projectType,
                priority: task.priority,
                isOverdue: task.isOverdue
            )
        )
    }
}

// MARK: - Widget definition

struct ProjectTasksWidget: Widget {
    let kind = TodoshiWidgetKind.project

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProjectWidgetConfigurationIntent.self, provider: ProjectTasksProvider()) { entry in
            ProjectTasksWidgetView(entry: entry)
        }
        .configurationDisplayName(TodoshiL10n.tr("widget.projectTasks"))
        .description(TodoshiL10n.tr("widget.projectTasksDesc"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
