import Foundation

public enum TaskPriority: String, Codable, CaseIterable, Sendable {
    case none
    case low
    case medium
    case high
    case urgent

    public var displayName: String {
        displayName(locale: .autoupdatingCurrent)
    }

    public func displayName(locale: Locale) -> String {
        switch self {
        case .none: return NexusL10n.tr("priority.none", locale: locale)
        case .low: return NexusL10n.tr("priority.low", locale: locale)
        case .medium: return NexusL10n.tr("priority.medium", locale: locale)
        case .high: return NexusL10n.tr("priority.high", locale: locale)
        case .urgent: return NexusL10n.tr("priority.urgent", locale: locale)
        }
    }

    /// Elevated priorities for widgets and dashboard highlights.
    public var isElevated: Bool {
        self == .high || self == .urgent
    }
}
