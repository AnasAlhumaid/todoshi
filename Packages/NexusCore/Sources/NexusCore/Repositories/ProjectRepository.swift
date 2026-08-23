import Foundation
import SwiftData

@MainActor
public final class ProjectRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ project: Project) {
        context.insert(project)
    }

    public func save() throws {
        try context.save()
    }

    public func fetchProject(id: UUID) throws -> Project? {
        let descriptor = FetchDescriptor<Project>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    public func fetchAll() throws -> [Project] {
        try context.fetch(
            FetchDescriptor<Project>(
                sortBy: [
                    SortDescriptor(\.position),
                    SortDescriptor(\.createdAt)
                ]
            )
        )
    }

    public func fetch(status: ProjectStatus) throws -> [Project] {
        let raw = status.rawValue
        return try context.fetch(
            FetchDescriptor<Project>(
                predicate: #Predicate { $0.statusRaw == raw },
                sortBy: [
                    SortDescriptor(\.position),
                    SortDescriptor(\.createdAt)
                ]
            )
        )
    }

    /// Next fractional position after the last project (any status).
    public func nextListPosition() throws -> Double {
        var descriptor = FetchDescriptor<Project>(
            sortBy: [SortDescriptor(\.position, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        if let last = try context.fetch(descriptor).first {
            return FractionalPosition.after(last.position)
        }
        return FractionalPosition.initial()
    }

    @discardableResult
    public func create(
        name: String,
        icon: String = ProjectIconCatalog.defaultSymbol,
        colorHex: String = ProjectColorCatalog.defaultHex,
        projectDescription: String = "",
        at date: Date = .now
    ) throws -> Project {
        guard let trimmedName = FieldValidation.requiredName(name) else {
            throw RepositoryValidationError.emptyName
        }
        let description = FieldValidation.trimmed(projectDescription)
        let project = Project(
            name: trimmedName,
            icon: ProjectIconCatalog.sanitized(icon),
            colorHex: ProjectColorCatalog.sanitized(colorHex),
            projectDescription: description,
            status: .active,
            createdAt: date,
            updatedAt: date,
            position: try nextListPosition()
        )
        context.insert(project)
        try context.save()
        NexusDataChangeCenter.post(.projectListChanged)
        return project
    }

    public func update(
        _ project: Project,
        name: String,
        icon: String,
        colorHex: String,
        projectDescription: String,
        at date: Date = .now
    ) throws {
        guard let trimmedName = FieldValidation.requiredName(name) else {
            throw RepositoryValidationError.emptyName
        }
        project.name = trimmedName
        project.icon = ProjectIconCatalog.sanitized(icon)
        project.colorHex = ProjectColorCatalog.sanitized(colorHex)
        project.projectDescription = FieldValidation.trimmed(projectDescription)
        project.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.projectStructureChanged)
    }

    public func archive(_ project: Project, at date: Date = .now) throws {
        project.status = .archived
        project.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.projectArchiveStateChanged)
    }

    public func restore(_ project: Project, at date: Date = .now) throws {
        project.status = .active
        project.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.projectArchiveStateChanged)
    }

    /// Cascade-deletes project tasks via the model relationship and cleans managed resource files.
    public func delete(_ project: Project) throws {
        let tasks = project.tasks ?? []
        var allTasks: [TaskItem] = []
        let taskRepo = TaskRepository(context: context)
        for task in tasks {
            allTasks.append(task)
            allTasks.append(contentsOf: taskRepo.collectDescendants(of: task))
        }
        let plan = TaskResourceRepository(context: context).managedPaths(forTasks: allTasks)
        context.delete(project)
        try context.save()
        TaskResourceRepository(context: context).applyFileCleanup(plan)
        NexusDataChangeCenter.post(.projectDeleted)
    }

    public func openRootTaskCount(for project: Project) -> Int {
        ProjectTaskCounts.openRootCount(tasks: project.tasks ?? [])
    }

    public func totalTaskCount(for project: Project) -> Int {
        (project.tasks ?? []).count
    }
}

public enum RepositoryValidationError: Error, Equatable, Sendable {
    case emptyName
    case missingProject
    case missingTask
    case missingLabel
    case missingChecklistItem
    case missingResource
    case duplicateLabelName
    case labelNameTooLong
    case invalidLabelColor
    case checklistTitleTooLong
    case hierarchyInvalid(TaskHierarchyValidationResult)
    case resourceInvalid(TaskResourceValidation.Issue)
    case recurrenceInvalid(TaskRecurrenceValidationIssue)
}
