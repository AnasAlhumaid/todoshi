import Foundation

// MARK: - Strings

public enum CalendarStrings: Sendable {
    public static var calendar: String { NexusL10n.tr("calendar.title") }
    public static var day: String { NexusL10n.tr("calendar.day") }
    public static var week: String { NexusL10n.tr("calendar.week") }
    public static var month: String { NexusL10n.tr("calendar.month") }
    public static var today: String { NexusL10n.tr("calendar.today") }
    public static var upcoming: String { NexusL10n.tr("calendar.upcoming") }
    public static var unscheduled: String { NexusL10n.tr("calendar.unscheduled") }
    public static var overdue: String { NexusL10n.tr("calendar.overdue") }
    public static var showCompleted: String { NexusL10n.tr("calendar.showCompleted") }
    public static var noTasksThisDay: String { NexusL10n.tr("calendar.noTasksThisDay") }
    public static var noUpcoming: String { NexusL10n.tr("calendar.noUpcoming") }
    public static var noUnscheduled: String { NexusL10n.tr("calendar.noUnscheduled") }
    public static var addTask: String { NexusL10n.tr("calendar.addTask") }
    public static var createProjectFirst: String { NexusL10n.tr("calendar.createProjectFirst") }
    public static var createProjectFirstMessage: String { NexusL10n.tr("calendar.createProjectFirstMessage") }
    public static var changeDueDate: String { NexusL10n.tr("calendar.changeDueDate") }
    public static var removeDueDate: String { NexusL10n.tr("calendar.removeDueDate") }
    public static var markDone: String { NexusL10n.tr("calendar.markDone") }
    public static var markIncomplete: String { NexusL10n.tr("calendar.markIncomplete") }
    public static var recurringTask: String { NexusL10n.tr("calendar.recurringTask") }
    public static var openTasksFormat: String { NexusL10n.tr("calendar.openTasks") }
    public static var completedTasksFormat: String { NexusL10n.tr("calendar.completedTasks") }
    public static var tasksDueFormat: String { NexusL10n.tr("calendar.tasksDue") }
    public static var previousPeriod: String { NexusL10n.tr("calendar.previous") }
    public static var nextPeriod: String { NexusL10n.tr("calendar.next") }
    public static var tomorrow: String { NexusL10n.tr("calendar.tomorrow") }
    public static var thisWeek: String { NexusL10n.tr("calendar.thisWeek") }
    public static var nextWeek: String { NexusL10n.tr("calendar.nextWeek") }
    public static var later: String { NexusL10n.tr("calendar.later") }
    public static var includeCompletedHint: String { NexusL10n.tr("calendar.includeCompletedHint") }
    public static var dueTime: String { NexusL10n.tr("calendar.dueTime") }
    public static var selectDate: String { NexusL10n.tr("calendar.selectDate") }

    public static func openTasks(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        NexusL10n.plural("calendar.openTasks", count: count, locale: locale)
    }

    public static func completedTasks(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        NexusL10n.format("calendar.completedTasks", locale: locale, count)
    }

    public static func tasksDue(_ count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        NexusL10n.format("calendar.tasksDue", locale: locale, count)
    }
}
