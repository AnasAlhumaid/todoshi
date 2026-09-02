import AppIntents
import WidgetKit
import SwiftUI
import NexusCore

// MARK: - Entity & configuration

struct NexusProjectEntity: AppEntity {
    // App Intents metadata requires string-literal LocalizedStringResource initializers.
    static var typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(
        name: "widget.configProject"
    )
    static var defaultQuery = NexusProjectEntityQuery()

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

struct NexusProjectEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [NexusProjectEntity] {
        let projects = (try? await loadProjects()) ?? []
        return identifiers.compactMap { id in
            projects.first(where: { $0.id == id }).map(NexusProjectEntity.init)
        }
    }

    func suggestedEntities() async throws -> [NexusProjectEntity] {
        try await loadProjects().map(NexusProjectEntity.init)
    }

    func defaultResult() async -> NexusProjectEntity? {
        try? await loadProjects().first.map(NexusProjectEntity.init)
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
    var project: NexusProjectEntity?

    init() {}

    init(project: NexusProjectEntity?) {
        self.project = project
    }
}

// MARK: - Provider

struct ProjectTasksProvider: AppIntentTimelineProvider {
    typealias Intent = ProjectWidgetConfigurationIntent
    typealias Entry = NexusWidgetEntry

    func placeholder(in context: Context) -> NexusWidgetEntry {
        NexusWidgetEntry(
            date: .now,
            snapshot: WidgetPreviewData.projectPlaceholder(),
            state: .content,
            projectInteraction: ProjectWidgetInteraction(
                baseConfigurationProjectID: UUID(),
                displayedProjectID: UUID(),
                projectName: WidgetPreviewData.projectPlaceholder().title,
                projectIcon: "folder.fill",
                projectColorHex: ProjectColorCatalog.defaultHex,
                allowsProjectSelection: true,
                allowsQuickAdd: true
            )
        )
    }

    func snapshot(for configuration: ProjectWidgetConfigurationIntent, in context: Context) async -> NexusWidgetEntry {
        await MainActor.run {
            Self.loadEntry(configuration: configuration, now: .now)
        }
    }

    func timeline(for configuration: ProjectWidgetConfigurationIntent, in context: Context) async -> Timeline<NexusWidgetEntry> {
        let entry = await MainActor.run {
            Self.loadEntry(configuration: configuration, now: .now)
        }
        return NexusWidgetTimeline.timeline(for: entry)
    }

    @MainActor
    private static func loadEntry(configuration: ProjectWidgetConfigurationIntent, now: Date) -> NexusWidgetEntry {
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
                state = loaded.snapshot.totalCount == 0 ? .empty : .content
            }
            return NexusWidgetEntry(
                date: now,
                snapshot: loaded.snapshot,
                state: state,
                projectInteraction: loaded.interaction
            )
        } catch {
            return NexusWidgetEntry(
                date: now,
                snapshot: .unavailable(title: NexusL10n.tr("common.project"), generatedAt: now),
                state: .storeUnavailable
            )
        }
    }
}

// MARK: - View

struct ProjectTasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: NexusWidgetEntry

    var body: some View {
        Group {
            switch entry.state {
            case .storeUnavailable:
                emptyShell(
                    title: WidgetStrings.openNexus,
                    message: WidgetStrings.openNexus,
                    link: NexusDeepLink.projects.url,
                    allowsProjectSelection: false,
                    allowsQuickAdd: false
                )
            case .needsConfiguration:
                let noActive = entry.projectInteraction?.hasActiveProjects == false
                emptyShell(
                    title: noActive ? WidgetStrings.noActiveProjects : WidgetStrings.chooseProject,
                    message: noActive ? WidgetStrings.noActiveProjectsHint : WidgetStrings.chooseProjectHint,
                    link: NexusDeepLink.projects.url,
                    allowsProjectSelection: false,
                    allowsQuickAdd: false
                )
            case .projectUnavailable:
                emptyShell(
                    title: WidgetStrings.projectUnavailable,
                    message: WidgetStrings.projectUnavailable,
                    link: NexusDeepLink.projects.url,
                    allowsProjectSelection: entry.projectInteraction?.allowsProjectSelection == true,
                    allowsQuickAdd: false
                )
            case .empty:
                projectLayout(isEmpty: true)
            case .content:
                projectLayout(isEmpty: false)
            }
        }
        .containerBackground(for: .widget) {
            Color(.systemBackground)
        }
        .widgetURL(projectLink)
    }

    private var projectLink: URL {
        if let id = entry.snapshot.projectID,
           entry.state != .projectUnavailable,
           entry.state != .needsConfiguration,
           entry.state != .storeUnavailable {
            return NexusDeepLink.project(id).url
        }
        return NexusDeepLink.projects.url
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
            projectLink: projectLink,
            allowsQuickAdd: entry.projectInteraction?.allowsQuickAdd == true,
            allowsProjectSelection: entry.projectInteraction?.allowsProjectSelection == true,
            family: .systemSmall,
            showIcon: true
        ) {
            if isEmpty {
                Text(WidgetStrings.noOpenTasks)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            } else if let first = shownTasks.first {
                Link(destination: NexusDeepLink.task(first.id).url) {
                    Text(first.title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .privacySensitive()
                }
            }
        }
        .accessibilityLabel(WidgetStrings.openCountA11y(title: entry.snapshot.title, count: entry.snapshot.totalCount))
    }

    // MARK: Medium — name + switchers, up to 3 tasks, add

    @ViewBuilder
    private func mediumLayout(isEmpty: Bool) -> some View {
        ProjectWidgetChrome(
            interaction: entry.projectInteraction,
            title: entry.snapshot.title,
            openCount: entry.snapshot.totalCount,
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
                        ProjectWidgetTaskRow(task: task, style: .compact)
                    }
                    if entry.snapshot.totalCount > shownTasks.count {
                        Text(WidgetStrings.remaining(entry.snapshot.totalCount - shownTasks.count))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityLabel(WidgetStrings.openCountA11y(title: entry.snapshot.title, count: entry.snapshot.totalCount))
    }

    // MARK: Large — full header, up to 6 tasks, footer actions

    @ViewBuilder
    private func largeLayout(isEmpty: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProjectWidgetHeader(
                interaction: entry.projectInteraction,
                title: entry.snapshot.title,
                openCount: entry.snapshot.totalCount,
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
                        ProjectWidgetTaskRow(task: task, style: .detailed)
                    }
                }
                Spacer(minLength: 0)
            }

            ProjectWidgetFooter(
                interaction: entry.projectInteraction,
                projectLink: projectLink,
                remaining: max(0, entry.snapshot.totalCount - shownTasks.count),
                allowsQuickAdd: entry.projectInteraction?.allowsQuickAdd == true
            )
        }
        .padding()
        .accessibilityLabel(WidgetStrings.openCountA11y(title: entry.snapshot.title, count: entry.snapshot.totalCount))
    }

    @ViewBuilder
    private func emptyBody(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(WidgetStrings.noOpenTasks)
                .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            Text(WidgetStrings.noOpenTasksHint)
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
                projectLink: projectLink,
                allowsProjectSelection: allowsProjectSelection,
                showIcon: showIcon,
                showOpenCount: openCount != nil && family != .systemMedium
            )
            content()
            Spacer(minLength: 0)
            if family == .systemMedium || family == .systemSmall {
                HStack {
                    if allowsQuickAdd {
                        ProjectAddTaskButton(
                            projectID: interaction?.displayedProjectID,
                            projectName: interaction?.projectName ?? title
                        )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(family == .systemSmall ? 12 : 16)
    }
}

private struct ProjectWidgetHeader: View {
    let interaction: ProjectWidgetInteraction?
    let title: String
    let openCount: Int?
    let projectLink: URL
    /// Shows the hamburger project selector when a base Edit Widget project exists.
    let allowsProjectSelection: Bool
    let showIcon: Bool
    let showOpenCount: Bool

    var body: some View {
        HStack(spacing: 6) {
            if showIcon {
                Image(systemName: interaction?.projectIcon ?? "folder")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(hex: interaction?.projectColorHex ?? ProjectColorCatalog.defaultHex))
                    .accessibilityHidden(true)
            }

            Link(destination: projectLink) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    if showOpenCount, let openCount {
                        Text(WidgetStrings.openTasksCount(openCount))
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
                Link(destination: NexusDeepLink.widgetProjectPicker(baseProjectID: base).url) {
                    Image(systemName: "line.3.horizontal")
                        .font(.body.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WidgetStrings.selectProject)
            }
        }
    }
}

private struct ProjectWidgetFooter: View {
    let interaction: ProjectWidgetInteraction?
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
                        style: .labeled
                    )
                }
                Link(destination: projectLink) {
                    Label(WidgetStrings.openProject, systemImage: "arrow.up.right.square")
                        .font(.caption.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                }
                .accessibilityLabel(WidgetStrings.openProject)
                Spacer(minLength: 0)
            }
        }
    }
}

private struct ProjectAddTaskButton: View {
    let projectID: UUID?
    let projectName: String
    var style: Style = .icon

    enum Style {
        case icon
        case labeled
    }

    var body: some View {
        if let projectID {
            Button(
                intent: AddTaskToSelectedProjectIntent(
                    projectID: projectID,
                    projectName: projectName
                )
            ) {
                label
            }
            .buttonStyle(.plain)
            .accessibilityLabel(WidgetStrings.addTaskTo(projectName))
        } else {
            Link(destination: NexusDeepLink.quickAdd.url) {
                label
            }
            .accessibilityLabel(WidgetStrings.addTask)
        }
    }

    @ViewBuilder
    private var label: some View {
        switch style {
        case .icon:
            Image(systemName: "plus.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.title3)
        case .labeled:
            Label(WidgetStrings.addTask, systemImage: "plus.circle.fill")
                .font(.caption.weight(.semibold))
                .labelStyle(.titleAndIcon)
        }
    }
}

// MARK: - Task rows

private struct ProjectWidgetTaskRow: View {
    enum Style {
        case compact
        case detailed
    }

    let task: WidgetTaskItem
    let style: Style

    var body: some View {
        Link(destination: NexusDeepLink.task(task.id).url) {
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(style == .compact ? 1 : 2)
                    .minimumScaleFactor(0.85)
                    .privacySensitive()

                HStack(spacing: 4) {
                    Text(task.status.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    if style == .detailed {
                        if task.priority == .urgent || task.priority == .high {
                            Text(task.priority.displayName)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(task.priority == .urgent ? .red : .orange)
                                .lineLimit(1)
                        }
                        if task.isOverdue {
                            Text(NexusL10n.tr("common.overdue"))
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
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        var parts = [task.title, task.status.displayName]
        if task.priority == .urgent || task.priority == .high {
            parts.append(task.priority.displayName)
        }
        if task.isOverdue {
            parts.append(NexusL10n.tr("common.overdue"))
        }
        return parts.joined(separator: ", ")
    }
}

// MARK: - Widget definition

struct ProjectTasksWidget: Widget {
    let kind = NexusWidgetKind.project

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ProjectWidgetConfigurationIntent.self, provider: ProjectTasksProvider()) { entry in
            ProjectTasksWidgetView(entry: entry)
        }
        .configurationDisplayName(NexusL10n.tr("widget.projectTasks"))
        .description(NexusL10n.tr("widget.projectTasksDesc"))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
