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
        projectType: ProjectType = .tasks,
        at date: Date = .now
    ) throws -> Project {
        guard let trimmedName = FieldValidation.requiredName(name) else {
            throw RepositoryValidationError.emptyName
        }
        let description = FieldValidation.trimmed(projectDescription)
        let resolvedIcon: String = {
            if icon.isEmpty || (projectType == .checklist && icon == ProjectIconCatalog.defaultSymbol) {
                return ProjectTypeCapabilities.defaultIcon(for: projectType)
            }
            return ProjectIconCatalog.sanitized(icon)
        }()
        let project = Project(
            name: trimmedName,
            icon: resolvedIcon,
            colorHex: ProjectColorCatalog.sanitized(colorHex),
            projectDescription: description,
            status: .active,
            createdAt: date,
            updatedAt: date,
            position: try nextListPosition(),
            projectType: projectType
        )
        context.insert(project)
        try context.save()
        TodoshiDataChangeCenter.post(.projectListChanged)
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
        TodoshiDataChangeCenter.post(.projectStructureChanged)
    }

    /// Replaces a personal Tasks project's board columns.
    ///
    /// `reassignments` maps removed column IDs to a remaining column of the same kind. Tasks in
    /// removed columns without a valid entry fall back to the first column of their kind, so
    /// statuses (and recurrence/reminder side effects) never change here.
    public func updateColumns(
        _ columns: [ProjectColumn],
        for project: Project,
        reassignments: [UUID: UUID] = [:],
        at date: Date = .now
    ) throws {
        guard ProjectColumnsPolicy.supportsCustomColumns(project) else { return }
        try ProjectColumnsPolicy.validate(columns)
        let keptIDs = Set(columns.map(\.id))
        for task in (project.tasks ?? []) where task.isRoot {
            guard let raw = task.columnIDRaw, let columnID = UUID(uuidString: raw),
                  !keptIDs.contains(columnID) else { continue }
            if let targetID = reassignments[columnID],
               let target = columns.first(where: { $0.id == targetID }),
               target.kind == ProjectColumnKind.kind(for: task.status) {
                task.columnIDRaw = target.id.uuidString
            } else {
                task.columnIDRaw = nil
            }
        }
        project.columnsJSON = ProjectColumnsPolicy.encode(columns)
        project.updatedAt = date
        try context.save()
        TodoshiDataChangeCenter.post(.projectStructureChanged)
        if project.isShared {
            SharedProjectMutationHook.emit(.boardColumns(project.id))
        }
    }

    public func archive(_ project: Project, at date: Date = .now) throws {
        project.status = .archived
        project.updatedAt = date
        try context.save()
        TodoshiDataChangeCenter.post(.projectArchiveStateChanged)
    }

    public func restore(_ project: Project, at date: Date = .now) throws {
        project.status = .active
        project.updatedAt = date
        try context.save()
        TodoshiDataChangeCenter.post(.projectArchiveStateChanged)
    }

    /// Applies shared metadata only after trusted remote bootstrap succeeds.
    public func markSharedAfterRemoteBootstrap(
        _ project: Project,
        collaborationOwnerUID: String?,
        at date: Date = .now
    ) throws {
        let transition = SharedProjectLocalStatePolicy.afterSuccessfulRemoteBootstrap(
            projectID: project.id,
            at: date
        )
        project.sharingMode = transition.sharingMode
        project.remoteProjectID = transition.remoteProjectID
        project.sharedAt = transition.sharedAt
        project.collaborationOwnerUID = collaborationOwnerUID
        project.syncUnavailable = false
        project.updatedAt = date
        try context.save()
        TodoshiDataChangeCenter.post(.projectStructureChanged)
        SharedProjectMutationHook.emit(.projectMetadata(project.id))
    }

    /// Creates or refreshes a minimal local shared project after invite acceptance (no tasks).
    @discardableResult
    public func upsertJoinedSharedProjectShell(
        _ shell: JoinedSharedProjectShell,
        collaborationOwnerUID: String?,
        at date: Date = .now
    ) throws -> Project {
        if let existing = try fetchProject(id: shell.id) {
            let shouldCreate = JoinedSharedProjectShellPolicy.shouldCreateLocalShell(
                existingLocalSharingMode: existing.sharingMode,
                existingRemoteProjectID: existing.remoteProjectID,
                projectID: shell.id
            )
            if !shouldCreate {
                existing.name = shell.title
                existing.projectDescription = shell.description
                existing.colorHex = shell.colorHex
                // Preserve an explicit local type; apply remote only when still unset (legacy shell).
                if existing.projectTypeRaw == nil {
                    existing.projectType = shell.projectType
                }
                existing.collaborationOwnerUID = collaborationOwnerUID
                existing.syncUnavailable = false
                existing.updatedAt = date
                try context.save()
                TodoshiDataChangeCenter.post(.projectStructureChanged)
                return existing
            }
            existing.name = shell.title
            existing.projectDescription = shell.description
            existing.colorHex = shell.colorHex
            existing.projectType = shell.projectType
            existing.sharingMode = .shared
            existing.remoteProjectID = shell.remoteProjectID
            existing.sharedAt = shell.sharedAt
            existing.collaborationOwnerUID = collaborationOwnerUID
            existing.syncUnavailable = false
            existing.updatedAt = date
            try context.save()
            TodoshiDataChangeCenter.post(.projectStructureChanged)
            return existing
        }

        let project = Project(
            id: shell.id,
            name: shell.title,
            icon: ProjectTypeCapabilities.defaultIcon(for: shell.projectType),
            colorHex: shell.colorHex,
            projectDescription: shell.description,
            sharingMode: .shared,
            remoteProjectID: shell.remoteProjectID,
            sharedAt: shell.sharedAt,
            collaborationOwnerUID: collaborationOwnerUID,
            projectType: shell.projectType
        )
        context.insert(project)
        try context.save()
        TodoshiDataChangeCenter.post(.projectStructureChanged)
        return project
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
        TodoshiDataChangeCenter.post(.projectDeleted)
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
    case invalidTaskStatusForProjectType
    case subtasksNotSupportedForProjectType
}
