import Foundation
import SwiftData

/// Shared App Group store access for widgets — never destroys the store, never falls back to a local store.
public enum WidgetStoreAccess {
    /// Open the shared App Group store for widget reads / App Intent writes.
    /// Failures propagate; callers must not create a secondary container.
    public static func makeReadContainer() throws -> ModelContainer {
        try makeSharedContainer()
    }

    /// Same non-destructive App Group open used for interactive widget writes.
    public static func makeSharedContainer() throws -> ModelContainer {
        guard let storeURL = AppGroupConstants.storeURL else {
            throw ModelContainerError.appGroupUnavailable
        }
        let schema = NexusSchema.makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: NexusSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            throw ModelContainerError.appGroupOpenFailed(underlying: String(describing: error))
        }
    }

    /// Explicit policy gate for tests / callers — always false.
    public static var createsFallbackStoreOnSharedFailure: Bool {
        WidgetQuickAddService.createsFallbackStoreOnSharedFailure
    }

    @MainActor
    public static func loadActiveProjects(from context: ModelContext) throws -> [WidgetProjectOption] {
        let projects = try context.fetch(FetchDescriptor<Project>())
        return projects
            .filter { $0.status == .active }
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            .map {
                WidgetProjectOption(
                    id: $0.id,
                    name: $0.name,
                    icon: $0.icon,
                    colorHex: $0.colorHex,
                    position: $0.position
                )
            }
    }

    @MainActor
    public static func loadDashboardInputs(from context: ModelContext) throws -> [DashboardTaskInput] {
        let projects = try context.fetch(FetchDescriptor<Project>())
        return projects
            .flatMap { $0.tasks ?? [] }
            .compactMap(DashboardMapping.taskInput(from:))
    }

    @MainActor
    public static func todaySnapshot(
        context: ModelContext,
        limit: Int = WidgetSnapshotBuilder.defaultTodayLimit,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) throws -> WidgetTaskSnapshot {
        let tasks = try loadDashboardInputs(from: context)
        return WidgetSnapshotBuilder.todaySnapshot(tasks: tasks, limit: limit, calendar: calendar, now: now)
    }

    @MainActor
    public static func highPrioritySnapshot(
        context: ModelContext,
        limit: Int = WidgetSnapshotBuilder.defaultPriorityLimit,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) throws -> WidgetTaskSnapshot {
        let tasks = try loadDashboardInputs(from: context)
        return WidgetSnapshotBuilder.highPrioritySnapshot(tasks: tasks, limit: limit, calendar: calendar, now: now)
    }

    @MainActor
    public static func projectSnapshot(
        projectID: UUID?,
        context: ModelContext,
        limit: Int = WidgetSnapshotBuilder.defaultProjectLimit,
        calendar: Calendar = .autoupdatingCurrent,
        now: Date = .now
    ) throws -> WidgetTaskSnapshot {
        guard let projectID else {
            return .needsConfiguration(generatedAt: now)
        }
        let projects = try context.fetch(FetchDescriptor<Project>())
        guard let project = projects.first(where: { $0.id == projectID }) else {
            return WidgetTaskSnapshot(
                generatedAt: now,
                title: NexusL10n.tr("common.project"),
                tasks: [],
                totalCount: 0,
                projectID: projectID,
                projectAvailability: .unavailable
            )
        }
        let tasks = try loadDashboardInputs(from: context)
        return WidgetSnapshotBuilder.projectSnapshot(
            projectID: project.id,
            projectName: project.name,
            projectIcon: project.icon,
            projectColorHex: project.colorHex,
            projectIsActive: project.status == .active,
            tasks: tasks,
            limit: limit,
            calendar: calendar,
            now: now
        )
    }
}
