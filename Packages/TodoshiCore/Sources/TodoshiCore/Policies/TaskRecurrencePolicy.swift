import Foundation

/// Supported recurrence patterns (MVP intentionally limited).
public enum TaskRecurrenceKind: String, Codable, CaseIterable, Sendable {
    case daily
    case weekdays
    case weekly
    case monthly
    case yearly
    case customDays
    case customWeeks
    case customMonths

    public var usesCustomInterval: Bool {
        switch self {
        case .customDays, .customWeeks, .customMonths: return true
        default: return false
        }
    }

    public var displayName: String {
        displayName(locale: .autoupdatingCurrent)
    }

    public func displayName(locale: Locale) -> String {
        switch self {
        case .daily: return NexusL10n.tr("recurrence.daily", locale: locale)
        case .weekdays: return NexusL10n.tr("recurrence.weekdays", locale: locale)
        case .weekly: return NexusL10n.tr("recurrence.weekly", locale: locale)
        case .monthly: return NexusL10n.tr("recurrence.monthly", locale: locale)
        case .yearly: return NexusL10n.tr("recurrence.yearly", locale: locale)
        case .customDays: return NexusL10n.tr("recurrence.everyNDays", locale: locale)
        case .customWeeks: return NexusL10n.tr("recurrence.everyNWeeks", locale: locale)
        case .customMonths: return NexusL10n.tr("recurrence.everyNMonths", locale: locale)
        }
    }
}

public struct TaskRecurrenceRule: Hashable, Codable, Sendable {
    public let kind: TaskRecurrenceKind
    public let interval: Int

    public init(kind: TaskRecurrenceKind, interval: Int = 1) {
        self.kind = kind
        let clamped: Int
        if kind.usesCustomInterval {
            clamped = max(1, min(TaskRecurrencePolicy.maxInterval, interval))
        } else {
            clamped = 1
        }
        self.interval = clamped
    }

    public var summary: String {
        summary(locale: .autoupdatingCurrent)
    }

    public func summary(locale: Locale) -> String {
        switch kind {
        case .daily: return TaskRecurrenceKind.daily.displayName(locale: locale)
        case .weekdays: return TaskRecurrenceKind.weekdays.displayName(locale: locale)
        case .weekly: return TaskRecurrenceKind.weekly.displayName(locale: locale)
        case .monthly: return TaskRecurrenceKind.monthly.displayName(locale: locale)
        case .yearly: return TaskRecurrenceKind.yearly.displayName(locale: locale)
        case .customDays:
            return NexusL10n.plural("recurrence.every_days", count: interval, locale: locale)
        case .customWeeks:
            return NexusL10n.plural("recurrence.every_weeks", count: interval, locale: locale)
        case .customMonths:
            return NexusL10n.plural("recurrence.every_months", count: interval, locale: locale)
        }
    }
}

public enum TaskRecurrenceStrings: Sendable {
    public static var repeatSection: String { NexusL10n.tr("recurrence.section") }
    public static var doesNotRepeat: String { NexusL10n.tr("recurrence.none") }
    public static var daily: String { NexusL10n.tr("recurrence.daily") }
    public static var weekdays: String { NexusL10n.tr("recurrence.weekdays") }
    public static var weekly: String { NexusL10n.tr("recurrence.weekly") }
    public static var monthly: String { NexusL10n.tr("recurrence.monthly") }
    public static var yearly: String { NexusL10n.tr("recurrence.yearly") }
    public static var everyNDays: String { NexusL10n.tr("recurrence.everyNDays") }
    public static var everyNWeeks: String { NexusL10n.tr("recurrence.everyNWeeks") }
    public static var everyNMonths: String { NexusL10n.tr("recurrence.everyNMonths") }
    public static var everyNDaysFormat: String { "%lld" } // unused legacy; use summary()
    public static var everyNWeeksFormat: String { "%lld" }
    public static var everyNMonthsFormat: String { "%lld" }
    public static var dueDateRequired: String { NexusL10n.tr("recurrence.dueRequired") }
    public static var recurringTask: String { NexusL10n.tr("recurrence.task") }
    public static var previousOccurrence: String { NexusL10n.tr("recurrence.previous") }
    public static var nextOccurrence: String { NexusL10n.tr("recurrence.next") }
    public static var thisOccurrenceOnly: String { NexusL10n.tr("recurrence.thisOnly") }
    public static var importedFilesNotCopied: String { NexusL10n.tr("recurrence.filesNotCopied") }
    public static var interval: String { NexusL10n.tr("recurrence.interval") }
    public static var cannotRecurSubtask: String { NexusL10n.tr("recurrence.cannotSubtask") }
    public static var stopRepeating: String { NexusL10n.tr("recurrence.stop") }
}

public struct NextOccurrenceDraft: Hashable, Sendable {
    public let dueDate: Date
    public let reminderDate: Date?
    public let seriesID: UUID
    public let generation: Int
    public let rule: TaskRecurrenceRule

    public init(
        dueDate: Date,
        reminderDate: Date?,
        seriesID: UUID,
        generation: Int,
        rule: TaskRecurrenceRule
    ) {
        self.dueDate = dueDate
        self.reminderDate = reminderDate
        self.seriesID = seriesID
        self.generation = generation
        self.rule = rule
    }
}

public enum RecurrenceGenerationDecision: Equatable, Sendable {
    case generate(NextOccurrenceDraft)
    case noRecurrence
    case invalidRule
    case alreadyGenerated
}

/// Pure recurrence validation and date math (no SwiftData / UI).
public enum TaskRecurrencePolicy: Sendable {
    public static let maxInterval = 365

    public static func parse(ruleRaw: String?, interval: Int?) -> TaskRecurrenceRule? {
        guard let raw = ruleRaw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty,
              let kind = TaskRecurrenceKind(rawValue: raw) else {
            return nil
        }
        let resolved = interval ?? 1
        guard resolved >= 1, resolved <= maxInterval else { return nil }
        return TaskRecurrenceRule(kind: kind, interval: resolved)
    }

    public static func encode(_ rule: TaskRecurrenceRule?) -> (ruleRaw: String?, interval: Int?) {
        guard let rule else { return (nil, nil) }
        return (rule.kind.rawValue, rule.interval)
    }

    public static func validationIssue(
        rule: TaskRecurrenceRule?,
        dueDate: Date?,
        isRoot: Bool
    ) -> TaskRecurrenceValidationIssue? {
        guard let rule else { return nil }
        if !isRoot { return .subtaskCannotRecur }
        if dueDate == nil { return .dueDateRequired }
        if rule.interval < 1 || rule.interval > maxInterval { return .invalidInterval }
        return nil
    }

    public static func nextDueDate(
        from dueDate: Date,
        rule: TaskRecurrenceRule,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Date? {
        var calendar = calendar
        if calendar.timeZone.identifier.isEmpty {
            calendar.timeZone = .current
        }
        switch rule.kind {
        case .daily, .customDays:
            return calendar.date(byAdding: .day, value: rule.interval, to: dueDate)
        case .weekdays:
            return nextWeekday(after: dueDate, calendar: calendar)
        case .weekly, .customWeeks:
            return calendar.date(byAdding: .weekOfYear, value: rule.interval, to: dueDate)
        case .monthly, .customMonths:
            return addMonthsPreservingComponents(interval: rule.interval, to: dueDate, calendar: calendar)
        case .yearly:
            return addYearsPreservingComponents(to: dueDate, calendar: calendar)
        }
    }

    /// Preserves offset of reminder relative to due date. Past reminders become `nil`.
    public static func nextReminderDate(
        sourceDue: Date?,
        sourceReminder: Date?,
        nextDue: Date,
        now: Date = .now
    ) -> Date? {
        guard let sourceDue, let sourceReminder else { return nil }
        let offset = sourceDue.timeIntervalSince(sourceReminder)
        let candidate = nextDue.addingTimeInterval(-offset)
        return candidate > now ? candidate : nil
    }

    public static func generationDecision(
        isRoot: Bool,
        statusBecomingDone: Bool,
        ruleRaw: String?,
        interval: Int?,
        dueDate: Date?,
        reminderDate: Date?,
        seriesID: UUID?,
        generation: Int,
        nextOccurrenceID: UUID?,
        now: Date = .now,
        calendar: Calendar = .autoupdatingCurrent
    ) -> RecurrenceGenerationDecision {
        guard statusBecomingDone else { return .noRecurrence }
        guard isRoot else { return .noRecurrence }
        if nextOccurrenceID != nil { return .alreadyGenerated }
        guard let rule = parse(ruleRaw: ruleRaw, interval: interval) else {
            if ruleRaw != nil { return .invalidRule }
            return .noRecurrence
        }
        guard let dueDate else { return .invalidRule }
        if let issue = validationIssue(rule: rule, dueDate: dueDate, isRoot: isRoot) {
            _ = issue
            return .invalidRule
        }
        guard let nextDue = nextDueDate(from: dueDate, rule: rule, calendar: calendar) else {
            return .invalidRule
        }
        let nextReminder = nextReminderDate(
            sourceDue: dueDate,
            sourceReminder: reminderDate,
            nextDue: nextDue,
            now: now
        )
        let series = seriesID ?? UUID()
        return .generate(
            NextOccurrenceDraft(
                dueDate: nextDue,
                reminderDate: nextReminder,
                seriesID: series,
                generation: max(0, generation) + 1,
                rule: rule
            )
        )
    }

    // MARK: - Calendar helpers

    /// Advance to next Monday–Friday. Friday → Monday.
    private static func nextWeekday(after date: Date, calendar: Calendar) -> Date? {
        var candidate = date
        for _ in 0..<8 {
            guard let next = calendar.date(byAdding: .day, value: 1, to: candidate) else {
                return nil
            }
            candidate = next
            let weekday = calendar.component(.weekday, from: candidate)
            // 1 = Sunday … 7 = Saturday (Gregorian)
            if weekday >= 2 && weekday <= 6 {
                return candidate
            }
        }
        return nil
    }

    /// Add months; clamp day-of-month when target month is shorter (Jan 31 → Feb 28/29).
    private static func addMonthsPreservingComponents(
        interval: Int,
        to date: Date,
        calendar: Calendar
    ) -> Date? {
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: date)
        guard var year = comps.year, var month = comps.month, let day = comps.day else { return nil }
        month += interval
        while month > 12 {
            month -= 12
            year += 1
        }
        while month < 1 {
            month += 12
            year -= 1
        }
        let range = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? date)
        let maxDay = range?.count ?? 28
        let clampedDay = min(day, maxDay)
        var next = DateComponents()
        next.year = year
        next.month = month
        next.day = clampedDay
        next.hour = comps.hour
        next.minute = comps.minute
        next.second = comps.second
        next.nanosecond = comps.nanosecond
        return calendar.date(from: next)
    }

    /// Add one year; Feb 29 → Feb 28 in non-leap years.
    private static func addYearsPreservingComponents(to date: Date, calendar: Calendar) -> Date? {
        addMonthsPreservingComponents(interval: 12, to: date, calendar: calendar)
    }
}

public enum TaskRecurrenceValidationIssue: Equatable, Sendable {
    case dueDateRequired
    case invalidInterval
    case subtaskCannotRecur

    public var message: String {
        message(locale: .autoupdatingCurrent)
    }

    public func message(locale: Locale) -> String {
        switch self {
        case .dueDateRequired:
            return NexusL10n.tr("recurrence.dueRequired", locale: locale)
        case .invalidInterval:
            return NexusL10n.format(
                "recurrence.invalidInterval",
                locale: locale,
                TaskRecurrencePolicy.maxInterval
            )
        case .subtaskCannotRecur:
            return NexusL10n.tr("recurrence.cannotSubtask", locale: locale)
        }
    }
}
