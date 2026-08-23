import Foundation

public struct ProjectBoardSection: Equatable, Sendable, Identifiable {
    public let status: TaskStatus
    public let tasks: [HomeTaskSummary]

    public var id: String { status.rawValue }
    public var count: Int { tasks.count }

    public init(status: TaskStatus, tasks: [HomeTaskSummary]) {
        self.status = status
        self.tasks = tasks
    }
}

public struct ProjectBoardSnapshot: Equatable, Sendable {
    public static let workflowStatusOrder: [TaskStatus] = TaskStatus.allCases
    public static let donePreviewLimit = 12

    public let projectID: UUID
    public let sections: [ProjectBoardSection]

    public init(projectID: UUID, sections: [ProjectBoardSection]) {
        self.projectID = projectID
        self.sections = sections
    }

    public func section(for status: TaskStatus) -> ProjectBoardSection? {
        sections.first { $0.status == status }
    }
}

public enum ProjectBoardTaskOrdering: Sendable {
    public static func sort(_ tasks: [HomeTaskSummary]) -> [HomeTaskSummary] {
        tasks.sorted(by: areInOrder)
    }

    public static func areInOrder(_ lhs: HomeTaskSummary, _ rhs: HomeTaskSummary) -> Bool {
        if lhs.position != rhs.position { return lhs.position < rhs.position }
        return lhs.createdAt < rhs.createdAt
    }
}
