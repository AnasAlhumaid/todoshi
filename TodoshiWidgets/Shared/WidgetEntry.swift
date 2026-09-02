import Foundation
import WidgetKit
import NexusCore

struct NexusWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetTaskSnapshot
    let state: WidgetLoadState
    /// Project Tasks only — stable IDs + flags for interactive chrome.
    var projectInteraction: ProjectWidgetInteraction? = nil
}

/// Immutable per-timeline interaction metadata (no live SwiftData).
struct ProjectWidgetInteraction: Hashable, Sendable {
    /// Edit Widget configuration project (selection slot / override key).
    let baseConfigurationProjectID: UUID?
    /// Project currently shown after override resolution.
    let displayedProjectID: UUID?
    let projectName: String
    let projectIcon: String
    let projectColorHex: String
    /// Hamburger selector available when a base is configured and active projects exist.
    let allowsProjectSelection: Bool
    let allowsQuickAdd: Bool
    /// Whether any active projects exist (for empty-configuration messaging).
    var hasActiveProjects: Bool = true
}

enum WidgetLoadState: Hashable, Sendable {
    case content
    case empty
    case storeUnavailable
    case needsConfiguration
    case projectUnavailable
}

enum WidgetStrings {
    static var today: String { NexusL10n.tr("widget.today") }
    static var highPriority: String { NexusL10n.tr("widget.highPriority") }
    static var quickAdd: String { NexusL10n.tr("widget.quickAdd") }
    static var nothingToday: String { NexusL10n.tr("widget.nothingToday") }
    static var noHighPriority: String { NexusL10n.tr("widget.noHighPriority") }
    static var noOpenTasks: String { NexusL10n.tr("widget.noOpenTasks") }
    static var noOpenTasksHint: String { NexusL10n.tr("widget.noOpenTasksHint") }
    static var noActiveProjects: String { NexusL10n.tr("widget.noActiveProjects") }
    static var noActiveProjectsHint: String { NexusL10n.tr("widget.noActiveProjectsHint") }
    static var openNexus: String { NexusL10n.tr("widget.openNexus") }
    static var chooseProject: String { NexusL10n.tr("widget.chooseProject") }
    static var chooseProjectHint: String { NexusL10n.tr("widget.chooseProjectHint") }
    static var projectUnavailable: String { NexusL10n.tr("widget.projectUnavailable") }
    static var fullEditor: String { NexusL10n.tr("widget.fullEditor") }
    static var previousProject: String { NexusL10n.tr("widget.previousProject") }
    static var nextProject: String { NexusL10n.tr("widget.nextProject") }
    static var selectProject: String { NexusL10n.tr("widget.selectProject") }
    static var openProject: String { NexusL10n.tr("widget.openProject") }
    static var addTask: String { NexusL10n.tr("widget.addTask") }
    static var openTasks: String { NexusL10n.tr("widget.openTasks") }

    static func remaining(_ count: Int) -> String {
        NexusL10n.format("widget.remaining", count)
    }

    static func openTasksCount(_ count: Int) -> String {
        NexusL10n.plural("widget.openTasksCount", count: count)
    }

    static func currentProject(_ name: String) -> String {
        NexusL10n.format("widget.currentProject", name)
    }

    static func addTaskTo(_ name: String) -> String {
        NexusL10n.format("widget.addTaskTo", name)
    }

    static func openCountA11y(title: String, count: Int) -> String {
        NexusL10n.format("widget.a11yOpenCount", title, count)
    }

    static func tasksCount(_ count: Int) -> String {
        NexusL10n.format("widget.a11yTasks", count)
    }
}

enum WidgetPreviewData {
    static func today(now: Date = .now) -> WidgetTaskSnapshot {
        let pid = UUID()
        return WidgetTaskSnapshot(
            generatedAt: now,
            title: WidgetStrings.today,
            tasks: [
                sample(id: UUID(), title: "Fix login layout", projectID: pid, name: "Nexus", priority: .high, due: now),
                sample(id: UUID(), title: "Review App Store build", projectID: pid, name: "Nexus", priority: .medium, due: now),
                sample(id: UUID(), title: "Update API documentation", projectID: pid, name: "Core", priority: .low, due: now)
            ],
            totalCount: 3
        )
    }

    static func projectPlaceholder(now: Date = .now) -> WidgetTaskSnapshot {
        let pid = UUID()
        return WidgetTaskSnapshot(
            generatedAt: now,
            title: "Nexus",
            tasks: [
                sample(id: UUID(), title: "Ship project widget", projectID: pid, name: "Nexus", priority: .high, due: nil, status: .inProgress),
                sample(id: UUID(), title: "Polish empty states", projectID: pid, name: "Nexus", priority: .medium, due: now, status: .todo)
            ],
            totalCount: 2,
            projectID: pid,
            projectIcon: "folder.fill",
            projectColorHex: ProjectColorCatalog.defaultHex
        )
    }

    static func sample(
        id: UUID,
        title: String,
        projectID: UUID,
        name: String,
        priority: TaskPriority,
        due: Date?,
        status: TaskStatus = .todo
    ) -> WidgetTaskItem {
        WidgetTaskItem(
            id: id,
            title: title,
            projectID: projectID,
            projectName: name,
            projectIcon: "shippingbox.fill",
            projectColorHex: ProjectColorCatalog.defaultHex,
            status: status,
            priority: priority,
            dueDate: due,
            isOverdue: false
        )
    }
}

enum NexusWidgetTimeline {
    static func nextDate(from snapshot: WidgetTaskSnapshot, now: Date = .now) -> Date {
        WidgetTimelinePolicy.nextRefreshDate(
            after: now,
            dueDates: snapshot.tasks.compactMap(\.dueDate)
        )
    }

    static func timeline(for entry: NexusWidgetEntry, now: Date = .now) -> Timeline<NexusWidgetEntry> {
        let next = nextDate(from: entry.snapshot, now: now)
        return Timeline(entries: [entry], policy: .after(next))
    }
}
