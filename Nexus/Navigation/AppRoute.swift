import Foundation
import NexusCore

public enum AppTab: String, Hashable, CaseIterable, Identifiable, Sendable {
    case dashboard
    case calendar
    case search
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dashboard: return NexusL10n.tr("tab.dashboard")
        case .calendar: return NexusL10n.tr("tab.calendar")
        case .search: return NexusL10n.tr("tab.search")
        case .settings: return NexusL10n.tr("tab.settings")
        }
    }

    public func title(locale: Locale) -> String {
        switch self {
        case .dashboard: return NexusL10n.tr("tab.dashboard", locale: locale)
        case .calendar: return NexusL10n.tr("tab.calendar", locale: locale)
        case .search: return NexusL10n.tr("tab.search", locale: locale)
        case .settings: return NexusL10n.tr("tab.settings", locale: locale)
        }
    }

    public var systemImage: String {
        switch self {
        case .dashboard: return "house.fill"
        case .calendar: return "calendar"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape.fill"
        }
    }
}

public enum AppRoute: Hashable, Sendable {
    case project(UUID)
    case task(UUID)
    case archivedProjects
    case allOverdue
    case projectEditor(UUID?)
    case taskEditor(projectID: UUID?, taskID: UUID?)
    case quickAdd
    case labels
    case labelEditor(UUID?)
    case labelTasks(UUID)
    case upcoming
    case unscheduled
    /// Dedicated route for widget project override picker (usually presented as a sheet).
    case widgetProjectPicker(baseProjectID: UUID?)
}
