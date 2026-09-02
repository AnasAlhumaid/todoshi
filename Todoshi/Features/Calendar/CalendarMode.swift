import Foundation
import NexusCore

public enum CalendarMode: String, CaseIterable, Identifiable, Sendable {
    case day
    case week
    case month

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .day: return CalendarStrings.day
        case .week: return CalendarStrings.week
        case .month: return CalendarStrings.month
        }
    }
}

public enum CalendarPreferences {
    public static let modeKey = "nexus.calendar.mode"
    public static let showCompletedKey = "nexus.calendar.showCompleted"
    public static let defaultMode: CalendarMode = .week
}
