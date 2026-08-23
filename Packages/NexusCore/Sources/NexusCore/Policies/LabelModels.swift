import Foundation

/// Lightweight presentation values for labels (no live models).
public struct LabelSummary: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let name: String
    public let colorHex: String
    public let assignedTaskCount: Int
    public let createdAt: Date

    public init(
        id: UUID,
        name: String,
        colorHex: String,
        assignedTaskCount: Int = 0,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.assignedTaskCount = assignedTaskCount
        self.createdAt = createdAt
    }
}

public struct LabelTaskRow: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let title: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let position: Double
    public let projectID: UUID
    public let projectName: String
    public let projectIsActive: Bool

    public init(
        id: UUID,
        title: String,
        status: TaskStatus,
        priority: TaskPriority,
        position: Double,
        projectID: UUID,
        projectName: String,
        projectIsActive: Bool
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.priority = priority
        self.position = position
        self.projectID = projectID
        self.projectName = projectName
        self.projectIsActive = projectIsActive
    }
}

public enum LabelTaskListBuilder: Sendable {
    private static let statusOrder: [TaskStatus: Int] = [
        .inProgress: 0,
        .review: 1,
        .todo: 2,
        .backlog: 3,
        .done: 4
    ]

    /// Root tasks for a label, ordered by project name → status → priority → position.
    public static func build(
        tasks: [LabelTaskRow],
        includeArchived: Bool = false
    ) -> [LabelTaskRow] {
        tasks
            .filter { includeArchived || $0.projectIsActive }
            .sorted { lhs, rhs in
                let nameCmp = lhs.projectName.localizedStandardCompare(rhs.projectName)
                if nameCmp != .orderedSame { return nameCmp == .orderedAscending }
                let ls = statusOrder[lhs.status] ?? 99
                let rs = statusOrder[rhs.status] ?? 99
                if ls != rs { return ls < rs }
                if lhs.priority.sortRank != rhs.priority.sortRank {
                    return lhs.priority.sortRank > rhs.priority.sortRank
                }
                return lhs.position < rhs.position
            }
    }
}

public struct LabelDraft: Equatable, Sendable {
    public var name: String
    public var colorHex: String

    public init(name: String = "", colorHex: String = LabelColorCatalog.defaultHex) {
        self.name = name
        self.colorHex = colorHex
    }

    public init(label: LabelTag) {
        self.name = label.name
        self.colorHex = label.colorHex
    }

    public var normalizedName: String {
        LabelValidation.normalizeDisplayName(name)
    }

    public func validationIssue(
        existing: [(id: UUID, name: String)],
        excludingLabelID: UUID? = nil,
        locale: Locale = .current
    ) -> LabelValidation.Issue? {
        LabelValidation.issue(
            name: name,
            colorHex: colorHex,
            existingNames: [],
            excludingLabelID: excludingLabelID,
            existingLabels: existing,
            locale: locale
        )
    }

    public var isValidColor: Bool {
        let upper = colorHex.uppercased()
        return LabelColorCatalog.swatches.contains { $0.hex.uppercased() == upper }
    }
}
