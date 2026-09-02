import Foundation
import SwiftData

@MainActor
public final class LabelRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func fetchAll() throws -> [LabelTag] {
        try context.fetch(FetchDescriptor<LabelTag>())
            .sorted { lhs, rhs in
                let cmp = lhs.name.localizedStandardCompare(rhs.name)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return lhs.createdAt < rhs.createdAt
            }
    }

    public func fetch(id: UUID) throws -> LabelTag? {
        let descriptor = FetchDescriptor<LabelTag>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    public func summaries() throws -> [LabelSummary] {
        try fetchAll().map { label in
            LabelSummary(
                id: label.id,
                name: label.name,
                colorHex: label.colorHex,
                assignedTaskCount: (label.tasks ?? []).count,
                createdAt: label.createdAt
            )
        }
    }

    @discardableResult
    public func create(
        name: String,
        colorHex: String = LabelColorCatalog.defaultHex,
        at date: Date = .now
    ) throws -> LabelTag {
        let cleaned = LabelValidation.normalizeDisplayName(name)
        let color = LabelColorCatalog.sanitized(colorHex)
        let existing = try fetchAll().map { (id: $0.id, name: $0.name) }
        if let issue = LabelValidation.issue(
            name: cleaned,
            colorHex: color,
            existingNames: [],
            existingLabels: existing
        ) {
            throw mapValidation(issue)
        }

        let label = LabelTag(
            name: cleaned,
            colorHex: color,
            createdAt: date,
            updatedAt: date
        )
        context.insert(label)
        try context.save()
        NexusDataChangeCenter.post(.labelListChanged)
        return label
    }

    public func update(
        labelID: UUID,
        name: String,
        colorHex: String,
        at date: Date = .now
    ) throws {
        guard let label = try fetch(id: labelID) else {
            throw RepositoryValidationError.missingLabel
        }
        let cleaned = LabelValidation.normalizeDisplayName(name)
        let color = LabelColorCatalog.sanitized(colorHex)
        let existing = try fetchAll().map { (id: $0.id, name: $0.name) }
        if let issue = LabelValidation.issue(
            name: cleaned,
            colorHex: color,
            existingNames: [],
            excludingLabelID: labelID,
            existingLabels: existing
        ) {
            throw mapValidation(issue)
        }

        label.name = cleaned
        label.colorHex = color
        label.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.labelContentChanged)
    }

    public func delete(labelID: UUID, at date: Date = .now) throws {
        guard let label = try fetch(id: labelID) else {
            throw RepositoryValidationError.missingLabel
        }
        let assigned = label.tasks ?? []
        for task in assigned {
            var current = task.labels ?? []
            current.removeAll { $0.id == labelID }
            task.labels = current
            task.updatedAt = date
        }
        context.delete(label)
        try context.save()
        NexusDataChangeCenter.post(.labelDeleted)
    }

    public func assign(labelID: UUID, to taskID: UUID, at date: Date = .now) throws {
        guard let label = try fetch(id: labelID) else {
            throw RepositoryValidationError.missingLabel
        }
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        var current = task.labels ?? []
        if current.contains(where: { $0.id == labelID }) {
            return
        }
        current.append(label)
        task.labels = current
        task.updatedAt = date
        label.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.taskLabelsChanged)
    }

    public func remove(labelID: UUID, from taskID: UUID, at date: Date = .now) throws {
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        var current = task.labels ?? []
        let before = current.count
        current.removeAll { $0.id == labelID }
        guard current.count != before else { return }
        task.labels = current
        task.updatedAt = date
        if let label = try fetch(id: labelID) {
            label.updatedAt = date
        }
        try context.save()
        NexusDataChangeCenter.post(.taskLabelsChanged)
    }

    public func replaceLabels(
        for taskID: UUID,
        with labelIDs: Set<UUID>,
        at date: Date = .now
    ) throws {
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        let allLabels = try fetchAll()
        let selected = allLabels.filter { labelIDs.contains($0.id) }
        let previousIDs = Set((task.labels ?? []).map(\.id))
        let nextIDs = Set(selected.map(\.id))
        guard previousIDs != nextIDs else { return }

        task.labels = selected
        task.updatedAt = date
        for label in selected where !previousIDs.contains(label.id) {
            label.updatedAt = date
        }
        try context.save()
        NexusDataChangeCenter.post(.taskLabelsChanged)
    }

    public func rootTaskRows(
        for labelID: UUID,
        includeArchived: Bool = false
    ) throws -> [LabelTaskRow] {
        guard let label = try fetch(id: labelID) else {
            throw RepositoryValidationError.missingLabel
        }
        let rows = (label.tasks ?? []).compactMap { task -> LabelTaskRow? in
            guard task.isRoot, let project = task.project else { return nil }
            return LabelTaskRow(
                id: task.id,
                title: task.title,
                status: task.status,
                priority: task.priority,
                position: task.position,
                projectID: project.id,
                projectName: project.name,
                projectIsActive: project.status == .active
            )
        }
        return LabelTaskListBuilder.build(tasks: rows, includeArchived: includeArchived)
    }

    private func mapValidation(_ issue: LabelValidation.Issue) -> RepositoryValidationError {
        switch issue {
        case .emptyName: return .emptyName
        case .tooLong: return .labelNameTooLong
        case .duplicateName: return .duplicateLabelName
        case .invalidColor: return .invalidLabelColor
        }
    }
}
