import Foundation
import Observation
import SwiftData
import NexusCore

@Observable
@MainActor
final class DashboardViewModel {
    private(set) var snapshot = DashboardSnapshot()
    private(set) var loadError: String?

    private let context: ModelContext
    var calendar: Calendar
    var now: () -> Date

    init(
        context: ModelContext,
        calendar: Calendar = .autoupdatingCurrent,
        now: @escaping () -> Date = { .now }
    ) {
        self.context = context
        self.calendar = calendar
        self.now = now
    }

    func refresh() {
        loadError = nil
        do {
            let projects = try ProjectRepository(context: context).fetchAll()
            snapshot = DashboardMapping.snapshot(
                projects: projects,
                calendar: calendar,
                now: now()
            )
        } catch {
            loadError = UserFacingError.message(for: error)
        }
    }

    @discardableResult
    func complete(taskID: UUID) -> Bool {
        do {
            guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
                return false
            }
            try TaskRepository(context: context).complete(task)
            refresh()
            return true
        } catch {
            loadError = UserFacingError.message(for: error)
            return false
        }
    }
}
