import Foundation

/// Pure validation + default timing for form drafts.
public enum TaskReminderValidation: Sendable {
    public enum Issue: Equatable, Sendable {
        case mustBeInFuture
        case completedTaskCannotHaveReminder
    }

    public static func issue(
        hasReminder: Bool,
        reminderDate: Date?,
        status: TaskStatus,
        now: Date = .now
    ) -> Issue? {
        guard hasReminder else { return nil }
        if status == .done {
            return .completedTaskCannotHaveReminder
        }
        guard let reminderDate, reminderDate > now else {
            return .mustBeInFuture
        }
        return nil
    }

    public static func message(for issue: Issue) -> String {
        switch issue {
        case .mustBeInFuture:
            return "Reminder must be set to a future date and time."
        case .completedTaskCannotHaveReminder:
            return "Completed tasks cannot have reminders."
        }
    }

    /// Proposes a sensible future reminder, never in the past.
    public static func defaultReminderDate(
        dueDate: Date?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date {
        let oneHour: TimeInterval = 60 * 60
        if let dueDate, dueDate > now {
            let beforeDue = dueDate.addingTimeInterval(-oneHour)
            if beforeDue > now {
                return beforeDue
            }
            // Due is sooner than one hour: use midpoint if still future, else +5 minutes.
            let midpoint = now.addingTimeInterval(dueDate.timeIntervalSince(now) / 2)
            if midpoint > now {
                return midpoint
            }
        }
        let candidate = now.addingTimeInterval(oneHour)
        // Ensure calendar-valid by rounding to next whole minute boundary when needed.
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: candidate
        )
        return calendar.date(from: components) ?? candidate
    }
}
