import Foundation

// MARK: - Strings

public enum CalendarStrings: Sendable {
    public static var calendar: String { TodoshiL10n.tr("calendar.title") }
    public static var day: String { TodoshiL10n.tr("calendar.day") }
    public static var week: String { TodoshiL10n.tr("calendar.week") }
    public static var month: String { TodoshiL10n.tr("calendar.month") }
    public static var today: String { TodoshiL10n.tr("calendar.today") }
    public static var upcoming: String { TodoshiL10n.tr("calendar.upcoming") }
    public static var unscheduled: String { TodoshiL10n.tr("calendar.unscheduled") }
    public static var overdue: String { TodoshiL10n.tr("calendar.overdue") }
    public static var showCompleted: String { TodoshiL10n.tr("calendar.showCompleted") }
    public static var noTasksThisDay: String { TodoshiL10n.tr("calendar.noTasksThisDay") }
    public static var noUpcoming: String { TodoshiL10n.tr("calendar.noUpcoming") }
    public static var noUnscheduled: String { TodoshiL10n.tr("calendar.noUnscheduled") }
    public static var addTask: String { TodoshiL10n.tr("calendar.addTask") }
    public static var createProjectFirst: String { TodoshiL10n.tr("calendar.createProjectFirst") }
    public static var createProjectFirstMessage: String { TodoshiL10n.tr("calendar.createProjectFirstMessage") }
    public static var changeDueDate: String { TodoshiL10n.tr("calendar.changeDueDate") }
    public static var removeDueDate: String { TodoshiL10n.tr("calendar.removeDueDate") }
    public static var markDone: String { TodoshiL10n.tr("calendar.markDone") }
    public static var markIncomplete: String { TodoshiL10n.tr("calendar.markIncomplete") }
    public static var recurringTask: String { TodoshiL10n.tr("calendar.recurringTask") }
    public static var openTasksFormat: String { TodoshiL10n.tr("calendar.openTasks") }
    public static var completedTasksFormat: String { TodoshiL10n.tr("calendar.completedTasks") }
    public static var tasksDueFormat: String { TodoshiL10n.tr("calendar.tasksDue") }
    public static var previousPeriod: String { TodoshiL10n.tr("calendar.previous") }
    public static var nextPeriod: String { TodoshiL10n.tr("calendar.next") }
    public static var tomorrow: String { TodoshiL10n.tr("calendar.tomorrow") }
    public static var thisWeek: String { TodoshiL10n.tr("calendar.thisWeek") }
    public static var nextWeek: String { TodoshiL10n.tr("calendar.nextWeek") }
    public static var later: String { TodoshiL10n.tr("calendar.later") }
    public static var includeCompletedHint: String { TodoshiL10n.tr("calendar.includeCompletedHint") }
    public static var dueTime: String { TodoshiL10n.tr("calendar.dueTime") }
    public static var selectDate: String { TodoshiL10n.tr("calendar.selectDate") }

    public static func openTasks(_ count: Int, locale: Locale = AppLanguageStore.resolvedLocale) -> String {
        TodoshiL10n.plural("calendar.openTasks", count: count, locale: locale)
    }

    public static func completedTasks(_ count: Int, locale: Locale = AppLanguageStore.resolvedLocale) -> String {
        TodoshiL10n.format("calendar.completedTasks", locale: locale, count)
    }

    public static func tasksDue(_ count: Int, locale: Locale = AppLanguageStore.resolvedLocale) -> String {
        TodoshiL10n.format("calendar.tasksDue", locale: locale, count)
    }
}
