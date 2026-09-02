import Foundation
import Observation
import NexusCore

@Observable
@MainActor
public final class AppRouter {
    public var selectedTab: AppTab = .dashboard
    public var dashboardPath: [AppRoute] = []
    public var calendarPath: [AppRoute] = []
    public var searchPath: [AppRoute] = []
    public var isPresentingQuickAdd = false
    /// Sheet for live Project Tasks widget override (`nexus://widget/project-picker`).
    public var isPresentingWidgetProjectPicker = false
    public var widgetProjectPickerBaseProjectID: UUID?

    public init() {}

    public func presentQuickAdd() {
        selectedTab = .dashboard
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

    public func showDashboardTab() {
        selectedTab = .dashboard
        dashboardPath = []
    }

    public func showCalendarTab() {
        selectedTab = .calendar
        calendarPath = []
    }

    public func open(_ deepLink: NexusDeepLink) {
        switch deepLink {
        case .quickAdd:
            presentQuickAdd()
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
        case .dashboard, .projects:
            isPresentingQuickAdd = false
            isPresentingWidgetProjectPicker = false
            showDashboardTab()
        case .widgetProjectPicker(let baseID):
            presentWidgetProjectPicker(baseProjectID: baseID)
        }
    }

    @discardableResult
    public func handle(url: URL) -> Bool {
        guard let link = NexusDeepLink(url: url) else { return false }
        open(link)
        return true
    }
}
