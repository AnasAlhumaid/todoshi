import Foundation
import SwiftData

public struct TaskResourceDeletionPlan: Equatable, Sendable {
    public let relativePaths: [String]
    public let taskIDs: [UUID]

    public init(relativePaths: [String], taskIDs: [UUID] = []) {
        self.relativePaths = relativePaths
        self.taskIDs = taskIDs
    }
}

@MainActor
public final class TaskResourceRepository {
    private let context: ModelContext
    private let fileStore: any TaskResourceFileStoring

    public init(context: ModelContext, fileStore: (any TaskResourceFileStoring)? = nil) {
        self.context = context
        self.fileStore = fileStore ?? TaskResourceFileAccess.current
    }

    public func fetchResources(taskID: UUID) throws -> [TaskResource] {
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        return ordered(task.resources ?? [])
    }

    public func fetchResource(id: UUID) throws -> TaskResource? {
        let descriptor = FetchDescriptor<TaskResource>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    public func fetchAllRelativePaths() throws -> Set<String> {
        let all = try context.fetch(FetchDescriptor<TaskResource>())
        return Set(all.compactMap(\.relativeFilePath))
    }

    public func managedPaths(for task: TaskItem) -> [String] {
        (task.resources ?? []).compactMap(\.relativeFilePath)
    }

    public func managedPaths(forTasks tasks: [TaskItem]) -> TaskResourceDeletionPlan {
        var paths: [String] = []
        var taskIDs: [UUID] = []
        for task in tasks {
            taskIDs.append(task.id)
            paths.append(contentsOf: managedPaths(for: task))
        }
        return TaskResourceDeletionPlan(relativePaths: paths, taskIDs: Array(Set(taskIDs)))
    }

    public func applyFileCleanup(_ plan: TaskResourceDeletionPlan) {
        for path in plan.relativePaths {
            fileStore.deleteIfExists(at: path)
        }
        for taskID in plan.taskIDs {
            try? fileStore.deleteAllFiles(for: taskID)
        }
    }

    @discardableResult
    public func createTextResource(
        taskID: UUID,
        kind: TaskResourceKind,
        title: String?,
        body: String,
        languageIdentifier: String? = nil,
        at date: Date = .now
    ) throws -> TaskResource {
        guard kind.isTextBacked else {
            throw RepositoryValidationError.resourceInvalid(.emptyContent)
        }
        if let issue = TaskResourceValidation.issueForTextBody(title: title ?? "", body: body) {
            throw RepositoryValidationError.resourceInvalid(issue)
        }
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        let resource = TaskResource(
            kind: kind,
            title: TaskResourceValidation.trimTitle(title ?? ""),
            body: TaskResourceValidation.normalizeBody(body),
            languageIdentifier: languageIdentifier,
            position: nextPosition(for: task),
            createdAt: date,
            updatedAt: date,
            task: task
        )
        // preserve code whitespace for body - normalize only edges - for save body should preserve lines
        // Re-assign with edge-trim only without collapsing:
        resource.body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        context.insert(resource)
        task.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.resourcesUpdated)
        return resource
    }

    @discardableResult
    public func createLink(
        taskID: UUID,
        title: String?,
        url: URL,
        at date: Date = .now
    ) throws -> TaskResource {
        let urlString = url.absoluteString
        if let issue = TaskResourceValidation.issueForLink(title: title ?? "", urlString: urlString) {
            throw RepositoryValidationError.resourceInvalid(issue)
        }
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        let resource = TaskResource(
            kind: .link,
            title: TaskResourceValidation.trimTitle(title ?? ""),
            externalURLString: urlString,
            position: nextPosition(for: task),
            createdAt: date,
            updatedAt: date,
            task: task
        )
        context.insert(resource)
        task.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.resourcesUpdated)
        return resource
    }

    @discardableResult
    public func createImportedFile(
        taskID: UUID,
        resourceID: UUID,
        importedFile: ImportedTaskFile,
        title: String? = nil,
        kind: TaskResourceKind? = nil,
        at date: Date = .now
    ) throws -> TaskResource {
        if let issue = TaskResourceValidation.issueForImportedFile(
            title: title ?? "",
            relativePath: importedFile.relativePath,
            fileSize: importedFile.fileSize
        ) {
            fileStore.deleteIfExists(at: importedFile.relativePath)
            throw RepositoryValidationError.resourceInvalid(issue)
        }
        guard fileStore.fileExists(at: importedFile.relativePath) else {
            throw RepositoryValidationError.resourceInvalid(.missingFilePath)
        }
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            fileStore.deleteIfExists(at: importedFile.relativePath)
            throw RepositoryValidationError.missingTask
        }
        let resource = TaskResource(
            id: resourceID,
            kind: kind ?? importedFile.inferredKind,
            title: TaskResourceValidation.trimTitle(title ?? ""),
            relativeFilePath: importedFile.relativePath,
            originalFileName: importedFile.originalFileName,
            mimeType: importedFile.mimeType,
            fileSize: importedFile.fileSize,
            position: nextPosition(for: task),
            createdAt: date,
            updatedAt: date,
            task: task
        )
        context.insert(resource)
        do {
            task.updatedAt = date
            try context.save()
        } catch {
            context.delete(resource)
            fileStore.deleteIfExists(at: importedFile.relativePath)
            throw error
        }
        NexusDataChangeCenter.post(.resourcesUpdated)
        return resource
    }

    public func updateResource(
        resourceID: UUID,
        title: String?,
        body: String?,
        externalURL: URL?,
        languageIdentifier: String?,
        at date: Date = .now
    ) throws {
        guard let resource = try fetchResource(id: resourceID) else {
            throw RepositoryValidationError.missingResource
        }
        let nextTitle = title.map { TaskResourceValidation.trimTitle($0) } ?? resource.title
        if let issue = TaskResourceValidation.issue(title: nextTitle) {
            throw RepositoryValidationError.resourceInvalid(issue)
        }

        switch resource.kind {
        case .link:
            let urlString = externalURL?.absoluteString ?? resource.externalURLString ?? ""
            if let issue = TaskResourceValidation.issueForLink(title: nextTitle, urlString: urlString) {
                throw RepositoryValidationError.resourceInvalid(issue)
            }
            resource.externalURLString = urlString
        case .codeSnippet, .terminalCommand, .text:
            let nextBody = body ?? resource.body ?? ""
            if let issue = TaskResourceValidation.issueForTextBody(title: nextTitle, body: nextBody) {
                throw RepositoryValidationError.resourceInvalid(issue)
            }
            resource.body = nextBody.trimmingCharacters(in: .whitespacesAndNewlines)
            if resource.kind == .codeSnippet {
                resource.languageIdentifier = languageIdentifier
            }
        case .file, .image, .pdf:
            break
        }

        resource.title = nextTitle
        resource.updatedAt = date
        resource.task?.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.resourcesUpdated)
    }

    @discardableResult
    public func deleteResource(resourceID: UUID, at date: Date = .now) throws -> TaskResourceDeletionPlan {
        guard let resource = try fetchResource(id: resourceID) else {
            throw RepositoryValidationError.missingResource
        }
        let path = resource.relativeFilePath
        let task = resource.task
        context.delete(resource)
        task?.updatedAt = date
        try context.save()
        if let path {
            fileStore.deleteIfExists(at: path)
        }
        NexusDataChangeCenter.post(.resourcesUpdated)
        return TaskResourceDeletionPlan(relativePaths: path.map { [$0] } ?? [])
    }

    @discardableResult
    public func moveResource(
        resourceID: UUID,
        before targetResourceID: UUID?,
        at date: Date = .now
    ) throws -> Bool {
        guard let resource = try fetchResource(id: resourceID),
              let task = resource.task else {
            throw RepositoryValidationError.missingResource
        }
        if targetResourceID == resourceID { return false }

        let orderedItems = ordered(task.resources ?? [])
        guard let fromIndex = orderedItems.firstIndex(where: { $0.id == resourceID }) else {
            return false
        }
        if let targetResourceID {
            if fromIndex + 1 < orderedItems.count, orderedItems[fromIndex + 1].id == targetResourceID {
                return false
            }
        } else if fromIndex == orderedItems.count - 1 {
            return false
        }

        var without = orderedItems.filter { $0.id != resourceID }
        let insertIndex: Int
        if let targetResourceID {
            guard let idx = without.firstIndex(where: { $0.id == targetResourceID }) else {
                throw RepositoryValidationError.missingResource
            }
            insertIndex = idx
        } else {
            insertIndex = without.count
        }

        let lower = insertIndex > 0 ? without[insertIndex - 1].position : nil
        let upper = insertIndex < without.count ? without[insertIndex].position : nil
        resource.position = FractionalPosition.between(lower: lower, upper: upper)
        resource.updatedAt = date
        without.insert(resource, at: insertIndex)
        normalizeIfNeeded(without, at: date)
        task.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.resourcesUpdated)
        return true
    }

    public func replaceDraftResources(
        taskID: UUID,
        drafts: [TaskResourceDraft],
        at date: Date = .now
    ) throws {
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        let prepared = try TaskResourceDraftBuilder.preparedForSave(drafts)
        let existing = task.resources ?? []
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })
        let keepIDs = Set(prepared.compactMap(\.persistedResourceID))

        var pathsToDelete: [String] = []
        for item in existing where !keepIDs.contains(item.id) {
            if let path = item.relativeFilePath {
                pathsToDelete.append(path)
            }
            context.delete(item)
        }

        for draft in prepared {
            if let pid = draft.persistedResourceID, let resource = existingByID[pid] {
                applyDraft(draft, to: resource, at: date)
            } else {
                let resource = makeResource(from: draft, task: task, at: date)
                context.insert(resource)
            }
        }

        task.updatedAt = date
        try context.save()
        for path in pathsToDelete {
            fileStore.deleteIfExists(at: path)
        }
        NexusDataChangeCenter.post(.resourcesUpdated)
    }

    /// Removes unmanaged files older than `olderThan` that are not referenced.
    /// Default safety window: 24 hours (avoids deleting recently staged files).
    public func cleanupOrphans(
        olderThan: TimeInterval = 24 * 60 * 60,
        now: Date = .now
    ) throws -> Int {
        let referenced = try fetchAllRelativePaths()
        let onDisk = try fileStore.listManagedRelativePaths()
        var removed = 0
        for path in onDisk where !referenced.contains(path) {
            guard let url = try? fileStore.fileURL(for: path) else { continue }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let modified = attrs?[.modificationDate] as? Date ?? .distantPast
            if now.timeIntervalSince(modified) >= olderThan {
                fileStore.deleteIfExists(at: path)
                removed += 1
            }
        }
        if removed > 0 {
            NexusDataChangeCenter.post(.resourceOrphanCleanupCompleted)
        }
        return removed
    }

    private func applyDraft(_ draft: TaskResourceDraft, to resource: TaskResource, at date: Date) {
        resource.kind = draft.kind
        resource.title = TaskResourceValidation.trimTitle(draft.title)
        resource.body = draft.body.isEmpty ? nil : draft.body.trimmingCharacters(in: .whitespacesAndNewlines)
        resource.externalURLString = draft.externalURLString.isEmpty ? nil : draft.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        resource.relativeFilePath = draft.relativeFilePath
        resource.originalFileName = draft.originalFileName
        resource.mimeType = draft.mimeType
        resource.fileSize = draft.fileSize
        resource.languageIdentifier = draft.languageIdentifier
        resource.position = draft.position
        resource.updatedAt = date
    }

    private func makeResource(from draft: TaskResourceDraft, task: TaskItem, at date: Date) -> TaskResource {
        TaskResource(
            id: draft.persistedResourceID ?? draft.id,
            kind: draft.kind,
            title: TaskResourceValidation.trimTitle(draft.title),
            body: draft.body.isEmpty ? nil : draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            externalURLString: draft.externalURLString.isEmpty
                ? nil
                : draft.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines),
            relativeFilePath: draft.relativeFilePath,
            originalFileName: draft.originalFileName,
            mimeType: draft.mimeType,
            fileSize: draft.fileSize,
            languageIdentifier: draft.languageIdentifier,
            position: draft.position,
            createdAt: date,
            updatedAt: date,
            task: task
        )
    }

    private func nextPosition(for task: TaskItem) -> Double {
        let peers = ordered(task.resources ?? [])
        if let last = peers.last {
            return FractionalPosition.after(last.position)
        }
        return FractionalPosition.initial()
    }

    private func ordered(_ items: [TaskResource]) -> [TaskResource] {
        items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.createdAt < $1.createdAt
        }
    }

    private func normalizeIfNeeded(_ items: [TaskResource], at date: Date) {
        let positions = items.map(\.position)
        guard FractionalPosition.needsNormalization(positions: positions) else { return }
        let normalized = FractionalPosition.normalizedPositions(count: items.count)
        for (item, position) in zip(items, normalized) {
            item.position = position
            item.updatedAt = date
        }
    }
}
