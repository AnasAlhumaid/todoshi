import Foundation
import Observation
import SwiftData
import NexusCore

@Observable
@MainActor
final class CalendarViewModel {
    var selectedDate: Date
    var dayBoundaryToken: Date
    var actionError: String?

    private let context: ModelContext

    init(context: ModelContext, selectedDate: Date = .now) {
        self.context = context
        let cal = Calendar.autoupdatingCurrent
        self.selectedDate = cal.startOfDay(for: selectedDate)
        self.dayBoundaryToken = .now
    }

    var calendar: Calendar { .autoupdatingCurrent }

    func sources(from projects: [Project]) -> [CalendarTaskSource] {
        CalendarMapping.taskSources(projects: projects)
    }

    func goToToday() {
        selectedDate = calendar.startOfDay(for: .now)
    }

    func select(_ date: Date) {
        selectedDate = calendar.startOfDay(for: date)
    }

    func shiftWeek(_ delta: Int) {
        if let next = calendar.date(byAdding: .day, value: delta * 7, to: selectedDate) {
            selectedDate = calendar.startOfDay(for: next)
        }
    }

    func shiftMonth(_ delta: Int) {
        if delta > 0 {
            selectedDate = CalendarDatePolicy.nextMonth(after: selectedDate, calendar: calendar)
        } else {
            selectedDate = CalendarDatePolicy.previousMonth(before: selectedDate, calendar: calendar)
        }
        // Keep selection on same day-of-month when possible
        // startOfMonth navigation already handled; keep day 1 of new month is fine when shifting months
        selectedDate = calendar.startOfDay(for: selectedDate)
    }

    func shiftDay(_ delta: Int) {
        if let next = calendar.date(byAdding: .day, value: delta, to: selectedDate) {
            selectedDate = calendar.startOfDay(for: next)
        }
    }

    func refreshDayBoundary() {
        dayBoundaryToken = .now
        // If we were viewing "today" conceptually and day rolled, pull to new today only when selected was yesterday? Keep selection.
    }

    func complete(taskID: UUID) {
        do {
            let repo = TaskRepository(context: context)
            guard let task = try repo.fetchTask(id: taskID) else { return }
            try repo.complete(task)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    func reopen(taskID: UUID) {
        do {
            let repo = TaskRepository(context: context)
            guard let task = try repo.fetchTask(id: taskID) else { return }
            try repo.reopen(task)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    func updateDueDate(taskID: UUID, dueDate: Date?) {
        do {
            let repo = TaskRepository(context: context)
            guard let task = try repo.fetchTask(id: taskID) else { return }
            try repo.updateDueDate(task, dueDate: dueDate)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    /// Preserves time-of-day when changing calendar day only.
    func reschedule(taskID: UUID, toDay day: Date) {
        do {
            let repo = TaskRepository(context: context)
            guard let task = try repo.fetchTask(id: taskID) else { return }
            let dayStart = calendar.startOfDay(for: day)
            let nextDue: Date
            if let existing = task.dueDate {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: existing)
                var merged = calendar.dateComponents([.year, .month, .day], from: dayStart)
                merged.hour = parts.hour
                merged.minute = parts.minute
                merged.second = parts.second
                nextDue = calendar.date(from: merged) ?? dayStart
            } else {
                nextDue = dayStart
            }
            try repo.updateDueDate(task, dueDate: nextDue)
        } catch {
            actionError = UserFacingError.message(for: error)
        }
    }

    func secondsUntilNextMidnight() -> TimeInterval {
        CalendarDatePolicy.secondsUntilNextMidnight(now: .now, calendar: calendar)
    }
}
