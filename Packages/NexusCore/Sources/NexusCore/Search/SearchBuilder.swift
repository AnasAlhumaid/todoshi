import Foundation

public struct SearchableProject: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let projectDescription: String
    public let icon: String
    public let colorHex: String
    public let position: Double
    public let isArchived: Bool
    public let openRootCount: Int
    public let totalRootCount: Int

    public init(
        id: UUID = UUID(),
        name: String,
        projectDescription: String = "",
        icon: String = ProjectIconCatalog.defaultSymbol,
        colorHex: String = ProjectColorCatalog.defaultHex,
        position: Double = FractionalPosition.initial(),
        isArchived: Bool = false,
        openRootCount: Int = 0,
        totalRootCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.projectDescription = projectDescription
        self.icon = icon
        self.colorHex = colorHex
        self.position = position
        self.isArchived = isArchived
        self.openRootCount = openRootCount
        self.totalRootCount = totalRootCount
    }
}

public struct SearchableLabel: Equatable, Sendable, Hashable, Identifiable {
    public let id: UUID
    public let name: String
    public let colorHex: String

    public init(id: UUID = UUID(), name: String, colorHex: String) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

public struct SearchableTask: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let title: String
    public let taskDescription: String
    public let notes: String
    public let status: TaskStatus
    public let priority: TaskPriority
    public let dueDate: Date?
    public let updatedAt: Date
    public let isRoot: Bool
    public let projectID: UUID
    public let projectName: String
    public let projectIcon: String
    public let projectColorHex: String
    public let projectIsArchived: Bool
    public let labelNames: [String]
    public let labels: [SearchableLabel]

    public init(
        id: UUID = UUID(),
        title: String,
        taskDescription: String = "",
        notes: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        updatedAt: Date = .now,
        isRoot: Bool = true,
        projectID: UUID,
        projectName: String,
        projectIcon: String = ProjectIconCatalog.defaultSymbol,
        projectColorHex: String = ProjectColorCatalog.defaultHex,
        projectIsArchived: Bool = false,
        labelNames: [String] = [],
        labels: [SearchableLabel] = []
    ) {
        self.id = id
        self.title = title
        self.taskDescription = taskDescription
        self.notes = notes
        self.status = status
        self.priority = priority
        self.dueDate = dueDate
        self.updatedAt = updatedAt
        self.isRoot = isRoot
        self.projectID = projectID
        self.projectName = projectName
        self.projectIcon = projectIcon
        self.projectColorHex = projectColorHex
        self.projectIsArchived = projectIsArchived
        self.labels = labels.isEmpty && !labelNames.isEmpty
            ? labelNames.map { SearchableLabel(name: $0, colorHex: LabelColorCatalog.defaultHex) }
            : labels
        self.labelNames = self.labels.map(\.name)
    }
}
public struct ScoredSearchProject: Equatable, Sendable, Identifiable {
    public let project: SearchableProject
    public let score: Int
    public var id: UUID { project.id }
}

public struct ScoredSearchTask: Equatable, Sendable, Identifiable {
    public let task: SearchableTask
    public let score: Int
    public var id: UUID { task.id }
}

public struct SearchSnapshot: Equatable, Sendable {
    public var projects: [ScoredSearchProject]
    public var tasks: [ScoredSearchTask]
    public var projectTotalCount: Int
    public var taskTotalCount: Int
    public var query: String
    public var isEmptyQuery: Bool

    public init(
        projects: [ScoredSearchProject] = [],
        tasks: [ScoredSearchTask] = [],
        projectTotalCount: Int = 0,
        taskTotalCount: Int = 0,
        query: String = "",
        isEmptyQuery: Bool = true
    ) {
        self.projects = projects
        self.tasks = tasks
        self.projectTotalCount = projectTotalCount
        self.taskTotalCount = taskTotalCount
        self.query = query
        self.isEmptyQuery = isEmptyQuery
    }

    public var hasResults: Bool {
        !projects.isEmpty || !tasks.isEmpty
    }
}

public enum SearchBuilder: Sendable {
    public static let defaultProjectPreviewLimit = 5
    public static let defaultTaskPreviewLimit = 10

    public static func build(
        query: String,
        projects: [SearchableProject],
        tasks: [SearchableTask],
        includeArchived: Bool,
        locale: Locale = .current,
        projectPreviewLimit: Int = defaultProjectPreviewLimit,
        taskPreviewLimit: Int = defaultTaskPreviewLimit
    ) -> SearchSnapshot {
        let normalized = SearchText.normalizeQuery(query)
        guard !normalized.isEmpty else {
            return SearchSnapshot(query: "", isEmptyQuery: true)
        }

        let scoredProjects: [ScoredSearchProject] = projects
            .filter { includeArchived || !$0.isArchived }
            .compactMap { project in
                let score = SearchRelevance.projectScore(
                    name: project.name,
                    description: project.projectDescription,
                    query: normalized,
                    locale: locale
                )
                guard score > 0 else { return nil }
                return ScoredSearchProject(project: project, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                if lhs.project.position != rhs.project.position {
                    return lhs.project.position < rhs.project.position
                }
                return lhs.project.name.localizedCaseInsensitiveCompare(rhs.project.name) == .orderedAscending
            }

        let scoredTasks: [ScoredSearchTask] = tasks
            .filter { $0.isRoot }
            .filter { includeArchived || !$0.projectIsArchived }
            .compactMap { task in
                let score = SearchRelevance.taskScore(
                    title: task.title,
                    projectName: task.projectName,
                    description: task.taskDescription,
                    notes: task.notes,
                    labelNames: task.labelNames,
                    query: normalized,
                    locale: locale
                )
                guard score > 0 else { return nil }
                return ScoredSearchTask(task: task, score: score)
            }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.task.updatedAt > rhs.task.updatedAt
            }

        return SearchSnapshot(
            projects: Array(scoredProjects.prefix(projectPreviewLimit)),
            tasks: Array(scoredTasks.prefix(taskPreviewLimit)),
            projectTotalCount: scoredProjects.count,
            taskTotalCount: scoredTasks.count,
            query: normalized,
            isEmptyQuery: false
        )
    }
}
