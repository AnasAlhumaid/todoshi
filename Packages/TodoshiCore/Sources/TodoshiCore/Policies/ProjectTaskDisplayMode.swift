import Foundation

/// Global MVP preference for project task presentation.
public enum ProjectTaskDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case board
    case list

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .board: return NexusL10n.tr("display.board")
        case .list: return NexusL10n.tr("display.list")
        }
    }

    public static let storageKey = "nexus.projectTaskDisplayMode"
    public static let `default`: ProjectTaskDisplayMode = .board
}
