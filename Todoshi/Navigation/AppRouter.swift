import Foundation
import Observation
import TodoshiCore

@Observable
@MainActor
public final class AppRouter {
    public var selectedTab: AppTab = .dashboard
    public var dashboardPath: [AppRoute] = []
    public var projectsPath: [AppRoute] = []
    public var calendarPath: [AppRoute] = []
    public var searchPath: [AppRoute] = []
    public var isPresentingQuickAdd = false
    /// When set, the next Quick Add sheet preselects this active project (widget handoff).
    public var quickAddPreselectedProjectID: UUID?
    /// Sheet for live Project Tasks widget override (`todoshi://widget/project-picker`; legacy `nexus://` also parses).
    public var isPresentingWidgetProjectPicker = false
    public var widgetProjectPickerBaseProjectID: UUID?
    /// Capability invite preview (`todoshi://invite/<token>`).
    public var pendingInviteTokenForPreview: String?
    public var isPresentingInvitePreview = false

    public init() {}

    public func presentQuickAdd(projectID: UUID? = nil) {
        quickAddPreselectedProjectID = projectID
        isPresentingWidgetProjectPicker = false
        isPresentingQuickAdd = true
    }

    public func presentWidgetProjectPicker(baseProjectID: UUID?) {
        isPresentingQuickAdd = false
        widgetProjectPickerBaseProjectID = baseProjectID
        isPresentingWidgetProjectPicker = true
    }

    public func dismissWidgetProjectPicker() {
        isPresentingWidgetProjectPicker = false
        widgetProjectPickerBaseProjectID = nil
    }

    public func presentInvitePreview(token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProjectInviteTokenGenerator.isValidFormat(trimmed) else { return }
        isPresentingQuickAdd = false
        isPresentingWidgetProjectPicker = false
        pendingInviteTokenForPreview = trimmed
        isPresentingInvitePreview = true
    }

    public func dismissInvitePreview() {
        isPresentingInvitePreview = false
        pendingInviteTokenForPreview = nil
    }

    /// Clears pushed collaboration/account navigation after sign-out or account deletion.
    /// Always selects Settings when `selectSettings` is true — terminal deletion destination.
    public func resetAuthenticatedNavigation(selectSettings: Bool = true) {
        dashboardPath = []
        projectsPath = []
        calendarPath = []
        searchPath = []
        isPresentingQuickAdd = false
        quickAddPreselectedProjectID = nil
        dismissWidgetProjectPicker()
        dismissInvitePreview()
        if selectSettings {
            selectedTab = .settings
        }
    }

    public func showDashboardTab() {
        selectedTab = .dashboard
        dashboardPath = []
    }

    public func showSettings() {
        selectedTab = .settings
    }

    public func showCalendarTab() {
        selectedTab = .calendar
        calendarPath = []
    }

    public func open(_ deepLink: TodoshiDeepLink) {
        switch deepLink {
        case .quickAdd(let projectID):
            presentQuickAdd(projectID: projectID)
        case .task(let id):
            isPresentingQuickAdd = false
            isPresentingWidgetProjectPicker = false
            selectedTab = .dashboard
            dashboardPath = [.task(id)]
        case .project(let id):
            isPresentingQuickAdd = false
            isPresentingWidgetProjectPicker = false
            selectedTab = .dashboard
            dashboardPath = [.project(id)]
        case .dashboard:
            isPresentingQuickAdd = false
            isPresentingWidgetProjectPicker = false
            showDashboardTab()
        case .projects:
            isPresentingQuickAdd = false
            isPresentingWidgetProjectPicker = false
            selectedTab = .projects
            projectsPath = []
        case .widgetProjectPicker(let baseID):
            presentWidgetProjectPicker(baseProjectID: baseID)
        case .invite(let token):
            presentInvitePreview(token: token)
        }
    }

    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let link = TodoshiDeepLink(url: url) else { return false }
        open(link)
        return true
    }
}
