import Foundation

/// Global MVP preference for project task presentation.
public enum ProjectTaskDisplayMode: String, CaseIterable, Identifiable, Sendable {
    case board
    case list

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .board: return TodoshiL10n.tr("display.board")
        case .list: return TodoshiL10n.tr("display.list")
        }
    }

    public static let storageKey = "todoshi.projectTaskDisplayMode"
    public static let `default`: ProjectTaskDisplayMode = .board
}
