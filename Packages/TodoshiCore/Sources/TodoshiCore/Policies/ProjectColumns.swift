import Foundation

/// What a board column means to the rest of the app (completion, overdue, reminders, widgets).
public enum ProjectColumnKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case todo
    case doing
    case done

    public var id: String { rawValue }

    /// Stored workflow status a task gets when it enters a column of this kind.
    public var status: TaskStatus {
        switch self {
        case .todo: return .todo
        case .doing: return .inProgress
        case .done: return .done
        }
    }

    public static func kind(for status: TaskStatus) -> ProjectColumnKind {
        switch status {
        case .backlog, .todo: return .todo
        case .inProgress, .review: return .doing
        case .done: return .done
        }
    }

    public func displayName(locale: Locale = AppLanguageStore.resolvedLocale) -> String {
        TodoshiL10n.tr("column.kind.\(rawValue)", locale: locale)
    }
}

/// A user-defined board column on a personal Tasks project.
public struct ProjectColumn: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var colorHex: String
    public var kind: ProjectColumnKind

    public init(id: UUID = UUID(), name: String, colorHex: String, kind: ProjectColumnKind) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.kind = kind
    }
}

public enum ProjectColumnsValidationError: Error, Equatable, Sendable {
    case emptyName
    case missingKind(ProjectColumnKind)
    case tooMany
}

public enum ProjectColumnsPolicy: Sendable {
    public static let maximumColumns = 12

    /// Stable IDs so default columns resolve identically before and after customization.
    public static let defaultTodoID = UUID(uuidString: "00000000-0000-0000-0000-00000000C001")!
    public static let defaultDoingID = UUID(uuidString: "00000000-0000-0000-0000-00000000C002")!
    public static let defaultDoneID = UUID(uuidString: "00000000-0000-0000-0000-00000000C003")!

    public static func defaultColumns(locale: Locale = AppLanguageStore.resolvedLocale) -> [ProjectColumn] {
        [
            ProjectColumn(id: defaultTodoID, name: TodoshiL10n.tr("board.lane.todo", locale: locale), colorHex: "#5248D9", kind: .todo),
            ProjectColumn(id: defaultDoingID, name: TodoshiL10n.tr("board.lane.doing", locale: locale), colorHex: "#E8920C", kind: .doing),
            ProjectColumn(id: defaultDoneID, name: TodoshiL10n.tr("board.lane.done", locale: locale), colorHex: "#30A46C", kind: .done),
        ]
    }

    public static func decode(_ json: String?) -> [ProjectColumn]? {
        guard let json, let data = json.data(using: .utf8),
              let columns = try? JSONDecoder().decode([ProjectColumn].self, from: data),
              !columns.isEmpty else { return nil }
        return columns
    }

    public static func encode(_ columns: [ProjectColumn]) -> String? {
        guard let data = try? JSONEncoder().encode(columns) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Custom columns apply to Tasks projects (personal or shared); checklists use the defaults.
    public static func supportsCustomColumns(_ project: Project) -> Bool {
        project.projectType == .tasks
    }

    /// Personal projects: always. Shared: only the owner edits columns (Firestore enforces it).
    public static func canEditColumns(_ project: Project, isOwner: Bool) -> Bool {
        supportsCustomColumns(project) && (!project.isShared || isOwner)
    }

    public static func columns(for project: Project, locale: Locale = AppLanguageStore.resolvedLocale) -> [ProjectColumn] {
        guard supportsCustomColumns(project), let custom = decode(project.columnsJSON) else {
            return defaultColumns(locale: locale)
        }
        return custom
    }

    /// The task's own column when it still matches its status; otherwise the first column of
    /// the status's kind (e.g. a task completed from Home lands in the first Done column).
    public static func column(
        forColumnID columnID: UUID?,
        status: TaskStatus,
        in columns: [ProjectColumn]
    ) -> ProjectColumn? {
        let kind = ProjectColumnKind.kind(for: status)
        if let columnID, let own = columns.first(where: { $0.id == columnID }), own.kind == kind {
            return own
        }
        return columns.first { $0.kind == kind } ?? columns.first
    }

    public static func validate(_ columns: [ProjectColumn]) throws {
        guard columns.count <= maximumColumns else { throw ProjectColumnsValidationError.tooMany }
        for column in columns where column.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ProjectColumnsValidationError.emptyName
        }
        // Every kind needs a home so completing or reopening a task always has a column.
        for kind in ProjectColumnKind.allCases where !columns.contains(where: { $0.kind == kind }) {
            throw ProjectColumnsValidationError.missingKind(kind)
        }
    }
}
