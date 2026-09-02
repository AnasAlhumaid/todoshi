import Foundation
import SwiftData

@MainActor
public final class ChecklistRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func fetchItems(taskID: UUID) throws -> [ChecklistItem] {
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        return ordered(task.checklist ?? [])
    }

    public func fetchItem(id: UUID) throws -> ChecklistItem? {
        let descriptor = FetchDescriptor<ChecklistItem>(predicate: #Predicate { $0.id == id })
        return try context.fetch(descriptor).first
    }

    @discardableResult
    public func createItem(
        taskID: UUID,
        title: String,
        position: Double? = nil,
        isCompleted: Bool = false,
        at date: Date = .now
    ) throws -> ChecklistItem {
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        let cleaned = ChecklistValidation.normalizeTitle(title)
        if let issue = ChecklistValidation.issue(title: cleaned) {
            throw mapValidation(issue)
        }
        let peers = ordered(task.checklist ?? [])
        let resolvedPosition = position ?? (peers.last.map { FractionalPosition.after($0.position) } ?? FractionalPosition.initial())
        let item = ChecklistItem(
            title: cleaned,
            isCompleted: isCompleted,
            position: resolvedPosition,
            createdAt: date,
            updatedAt: date,
            task: task
        )
        context.insert(item)
        task.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.checklistUpdated)
        return item
    }

    public func updateItem(itemID: UUID, title: String, at date: Date = .now) throws {
        guard let item = try fetchItem(id: itemID) else {
            throw RepositoryValidationError.missingChecklistItem
        }
        let cleaned = ChecklistValidation.normalizeTitle(title)
        if let issue = ChecklistValidation.issue(title: cleaned) {
            throw mapValidation(issue)
        }
        guard item.title != cleaned else { return }
        item.title = cleaned
        item.updatedAt = date
        item.task?.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.checklistUpdated)
    }

    public func setCompleted(itemID: UUID, isCompleted: Bool, at date: Date = .now) throws {
        guard let item = try fetchItem(id: itemID) else {
            throw RepositoryValidationError.missingChecklistItem
        }
        guard item.isCompleted != isCompleted else { return }
        item.isCompleted = isCompleted
        item.updatedAt = date
        item.task?.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.checklistItemToggled)
    }

    public func deleteItem(itemID: UUID, at date: Date = .now) throws {
        guard let item = try fetchItem(id: itemID) else {
            throw RepositoryValidationError.missingChecklistItem
        }
        let task = item.task
        context.delete(item)
        task?.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.checklistUpdated)
    }

    /// Move `itemID` before `targetItemID`, or to end when target is nil.
    @discardableResult
    public func moveItem(
        itemID: UUID,
        before targetItemID: UUID?,
        at date: Date = .now
    ) throws -> Bool {
        guard let item = try fetchItem(id: itemID),
              let task = item.task else {
            throw RepositoryValidationError.missingChecklistItem
        }
        if targetItemID == itemID { return false }

        let orderedItems = ordered(task.checklist ?? [])
        guard let fromIndex = orderedItems.firstIndex(where: { $0.id == itemID }) else {
            return false
        }

        // No-op when already immediately before the target (or already last when target is nil).
        if let targetItemID {
            if fromIndex + 1 < orderedItems.count, orderedItems[fromIndex + 1].id == targetItemID {
                return false
            }
        } else if fromIndex == orderedItems.count - 1 {
            return false
        }

        var without = orderedItems.filter { $0.id != itemID }
        let insertIndex: Int
        if let targetItemID {
            guard let idx = without.firstIndex(where: { $0.id == targetItemID }) else {
                throw RepositoryValidationError.missingChecklistItem
            }
            insertIndex = idx
        } else {
            insertIndex = without.count
        }

        let lower = insertIndex > 0 ? without[insertIndex - 1].position : nil
        let upper = insertIndex < without.count ? without[insertIndex].position : nil
        item.position = FractionalPosition.between(lower: lower, upper: upper)
        item.updatedAt = date

        without.insert(item, at: insertIndex)
        normalizeIfNeeded(without, at: date)
        task.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.checklistUpdated)
        return true
    }

    /// Applies the full draft list for a task in one save.
    public func replaceChecklist(
        taskID: UUID,
        drafts: [ChecklistItemDraft],
        at date: Date = .now
    ) throws {
        guard let task = try TaskRepository(context: context).fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        let prepared = ChecklistDraftBuilder.preparedForSave(drafts)
        let existing = task.checklist ?? []
        if prepared.isEmpty && existing.isEmpty {
            return
        }
        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.id, $0) })

        let keepIDs = Set(prepared.compactMap(\.persistedItemID))
        for item in existing where !keepIDs.contains(item.id) {
            context.delete(item)
        }

        for draft in prepared {
            if let pid = draft.persistedItemID, let item = existingByID[pid] {
                item.title = draft.normalizedTitle
                item.isCompleted = draft.isCompleted
                item.position = draft.position
                item.updatedAt = date
            } else {
                let item = ChecklistItem(
                    title: draft.normalizedTitle,
                    isCompleted: draft.isCompleted,
                    position: draft.position,
                    createdAt: date,
                    updatedAt: date,
                    task: task
                )
                context.insert(item)
            }
        }

        task.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.checklistUpdated)
    }

    public func progress(for taskID: UUID) throws -> ChecklistProgress {
        let items = try fetchItems(taskID: taskID)
        return ChecklistProgress.from(completedFlags: items.map(\.isCompleted))
    }

    public func progress(for task: TaskItem) -> ChecklistProgress {
        ChecklistProgress.from(completedFlags: (task.checklist ?? []).map(\.isCompleted))
    }

    private func ordered(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.createdAt < $1.createdAt
        }
    }

    private func normalizeIfNeeded(_ items: [ChecklistItem], at date: Date) {
        let positions = items.map(\.position)
        guard FractionalPosition.needsNormalization(positions: positions) else { return }
        let normalized = FractionalPosition.normalizedPositions(count: items.count)
        for (item, position) in zip(items, normalized) {
            item.position = position
            item.updatedAt = date
        }
    }

    private func mapValidation(_ issue: ChecklistValidation.Issue) -> RepositoryValidationError {
        switch issue {
        case .emptyTitle: return .emptyName
        case .tooLong: return .checklistTitleTooLong
        }
    }
}
