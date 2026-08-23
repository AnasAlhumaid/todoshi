import Foundation
import SwiftData
import NexusCore

enum WidgetContainerProvider {
    /// Short-lived container for a single timeline generation pass.
    static func makeContainer() throws -> ModelContainer {
        try WidgetStoreAccess.makeReadContainer()
    }
}

@MainActor
enum WidgetSnapshotLoader {
    static func loadTodaySnapshot(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        limit: Int = WidgetSnapshotBuilder.defaultTodayLimit
    ) throws -> WidgetTaskSnapshot {
        let container = try WidgetContainerProvider.makeContainer()
        let context = ModelContext(container)
        return try WidgetStoreAccess.todaySnapshot(
            context: context,
            limit: limit,
            calendar: calendar,
            now: referenceDate
        )
    }

    static func loadHighPrioritySnapshot(
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        limit: Int = WidgetSnapshotBuilder.defaultPriorityLimit
    ) throws -> WidgetTaskSnapshot {
        let container = try WidgetContainerProvider.makeContainer()
        let context = ModelContext(container)
        return try WidgetStoreAccess.highPrioritySnapshot(
            context: context,
            limit: limit,
            calendar: calendar,
            now: referenceDate
        )
    }

    static func loadProjectSnapshot(
        projectID: UUID?,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        limit: Int = WidgetSnapshotBuilder.defaultProjectLimit
    ) throws -> WidgetTaskSnapshot {
        let container = try WidgetContainerProvider.makeContainer()
        let context = ModelContext(container)
        return try WidgetStoreAccess.projectSnapshot(
            projectID: projectID,
            context: context,
            limit: limit,
            calendar: calendar,
            now: referenceDate
        )
    }

    /// Resolves Edit Widget base + App Group prev/next override, then loads snapshot.
    static func loadConfiguredProjectEntry(
        baseConfigurationProjectID: UUID?,
        referenceDate: Date = .now,
        calendar: Calendar = .autoupdatingCurrent,
        limit: Int = WidgetSnapshotBuilder.defaultProjectLimit
    ) throws -> (snapshot: WidgetTaskSnapshot, interaction: ProjectWidgetInteraction) {
        let container = try WidgetContainerProvider.makeContainer()
        let context = ModelContext(container)
        let active = try WidgetStoreAccess.loadActiveProjects(from: context)
        let ordered = WidgetProjectSelectionPolicy.orderedActive(active)
        let activeIDs = Set(ordered.map(\.id))

        let displayedID = WidgetProjectSelectionStore.effectiveProjectID(
            baseConfigurationID: baseConfigurationProjectID,
            activeIDs: activeIDs
        )

        let snapshot = try WidgetStoreAccess.projectSnapshot(
            projectID: displayedID,
            context: context,
            limit: limit,
            calendar: calendar,
            now: referenceDate
        )

        let option = ordered.first(where: { $0.id == displayedID })
        let interaction = ProjectWidgetInteraction(
            baseConfigurationProjectID: baseConfigurationProjectID,
            displayedProjectID: displayedID,
            projectName: option?.name ?? snapshot.title,
            projectIcon: option?.icon ?? snapshot.projectIcon ?? "folder",
            projectColorHex: option?.colorHex ?? snapshot.projectColorHex ?? ProjectColorCatalog.defaultHex,
            allowsProjectSelection: baseConfigurationProjectID != nil && !ordered.isEmpty,
            allowsQuickAdd: snapshot.projectAvailability == .available,
            hasActiveProjects: !ordered.isEmpty
        )
        return (snapshot, interaction)
    }

    static func loadActiveProjects() throws -> [WidgetProjectOption] {
        let container = try WidgetContainerProvider.makeContainer()
        let context = ModelContext(container)
        return try WidgetStoreAccess.loadActiveProjects(from: context)
    }
}
