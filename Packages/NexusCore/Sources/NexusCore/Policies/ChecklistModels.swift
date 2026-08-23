import Foundation

/// Deterministic checklist completion stats (does not imply parent task Done).
public struct ChecklistProgress: Hashable, Sendable {
    public let completed: Int
    public let total: Int

    public init(completed: Int, total: Int) {
        self.completed = max(0, completed)
        self.total = max(0, total)
    }

    public var fraction: Double {
        guard total > 0 else { return 0 }
        return Double(completed) / Double(total)
    }

    public var isComplete: Bool {
        total > 0 && completed >= total
    }

    public var hasProgress: Bool {
        total > 0
    }

    public var compactLabel: String {
        "\(completed)/\(total)"
    }

    public var accessibilityLabel: String {
        ChecklistStrings.progress(completed: completed, total: total)
    }

    public static func from(completedFlags: [Bool]) -> ChecklistProgress {
        let completed = completedFlags.filter { $0 }.count
        return ChecklistProgress(completed: completed, total: completedFlags.count)
    }
}

/// Value-type draft used by Task Form — never live `ChecklistItem` models.
public struct ChecklistItemDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var isCompleted: Bool
    public var position: Double
    public var persistedItemID: UUID?

    public init(
        id: UUID = UUID(),
        title: String = "",
        isCompleted: Bool = false,
        position: Double = FractionalPosition.initial(),
        persistedItemID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.isCompleted = isCompleted
        self.position = position
        self.persistedItemID = persistedItemID
    }

    public init(item: ChecklistItem) {
        self.id = item.id
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.position = item.position
        self.persistedItemID = item.id
    }

    public var normalizedTitle: String {
        ChecklistValidation.normalizeTitle(title)
    }

    public var isPersistable: Bool {
        ChecklistValidation.issue(title: title) == nil
    }
}

public enum ChecklistDraftBuilder: Sendable {
    public static func drafts(from items: [ChecklistItem]) -> [ChecklistItemDraft] {
        items
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.createdAt < $1.createdAt
            }
            .map(ChecklistItemDraft.init(item:))
    }

    /// Drops empty/non-persistable rows and re-assigns ascending draft positions.
    public static func preparedForSave(_ drafts: [ChecklistItemDraft]) -> [ChecklistItemDraft] {
        let valid = drafts.filter(\.isPersistable)
        let positions = FractionalPosition.normalizedPositions(count: valid.count)
        return zip(valid, positions).map { draft, position in
            var copy = draft
            copy.title = draft.normalizedTitle
            copy.position = position
            return copy
        }
    }

    public static func nextPosition(after drafts: [ChecklistItemDraft]) -> Double {
        if let last = drafts.map(\.position).max() {
            return FractionalPosition.after(last)
        }
        return FractionalPosition.initial()
    }

    public static func progress(from drafts: [ChecklistItemDraft]) -> ChecklistProgress {
        ChecklistProgress.from(completedFlags: drafts.map(\.isCompleted))
    }
}
