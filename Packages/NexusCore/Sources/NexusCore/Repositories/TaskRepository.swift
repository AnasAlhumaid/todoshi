import Foundation
import SwiftData

@MainActor
public final class TaskRepository {
    private let context: ModelContext

    public init(context: ModelContext) {
        self.context = context
    }

    public func insert(_ task: TaskItem) {
        context.insert(task)
    }

    public func save() throws {
        try context.save()
    }

    public func fetchTask(id: UUID) throws -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>(
            predicate: #Predicate { $0.id == id }
        )
        return try context.fetch(descriptor).first
    }

    public func fetchAllTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<TaskItem>())
    }

    public func fetchRootTasks(projectID: UUID) throws -> [TaskItem] {
        let all = try context.fetch(FetchDescriptor<TaskItem>())
        return all
            .filter { $0.project?.id == projectID && $0.isRoot }
            .sorted(by: Self.rootSort)
    }

    public func fetchRootTasks(projectID: UUID, status: TaskStatus) throws -> [TaskItem] {
        try fetchRootTasks(projectID: projectID).filter { $0.status == status }
    }

    /// Last fractional position among root tasks in a project status column.
    public func lastPosition(projectID: UUID, status: TaskStatus) throws -> Double? {
        try fetchRootTasks(projectID: projectID, status: status).map(\.position).max()
    }

    public func nextPosition(projectID: UUID, status: TaskStatus) throws -> Double {
        if let last = try lastPosition(projectID: projectID, status: status) {
            return FractionalPosition.after(last)
        }
        return FractionalPosition.initial()
    }

    /// How repository create announces data changes after a successful save.
    public enum CreateAnnouncement: Sendable {
        /// App UI path — full event fan-out (may reconcile notifications).
        case standard
        /// Widget / App Intent path — reload task widgets only, no notification reconcile.
        case widget
    }

    @discardableResult
    public func create(
        in project: Project,
        title: String,
        taskDescription: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        notes: String = "",
        labelIDs: Set<UUID> = [],
        recurrenceRule: TaskRecurrenceRule? = nil,
        at date: Date = .now,
        announcement: CreateAnnouncement = .standard
    ) throws -> TaskItem {
        guard let trimmedTitle = FieldValidation.requiredName(title) else {
            throw RepositoryValidationError.emptyName
        }

        if let issue = TaskRecurrencePolicy.validationIssue(
            rule: recurrenceRule,
            dueDate: dueDate,
            isRoot: true
        ) {
            throw RepositoryValidationError.recurrenceInvalid(issue)
        }

        // Done tasks never carry an active reminder; keep pre-clear value for recurrence offset.
        let sourceReminderForRecurrence = reminderDate
        let resolvedReminder = (status == .done) ? nil : reminderDate

        let position = try nextPosition(projectID: project.id, status: status)
        let encoded = TaskRecurrencePolicy.encode(recurrenceRule)
        let seriesID = recurrenceRule == nil ? nil : UUID()
        let task = TaskItem(
            title: trimmedTitle,
            taskDescription: FieldValidation.trimmed(taskDescription),
            status: status,
            priority: priority,
            dueDate: dueDate,
            reminderDate: resolvedReminder,
            notes: FieldValidation.trimmed(notes),
            position: position,
            createdAt: date,
            updatedAt: date,
            project: project,
            recurrenceRuleRaw: encoded.ruleRaw,
            recurrenceInterval: encoded.interval,
            recurrenceSeriesID: seriesID,
            recurrenceGeneration: 0
        )
        if status == .done {
            task.applyStatus(.done, at: date)
        }
        if !labelIDs.isEmpty {
            let labels = try LabelRepository(context: context).fetchAll()
                .filter { labelIDs.contains($0.id) }
            task.labels = labels
        }
        context.insert(task)

        var generated = false
        if status == .done {
            generated = try generateNextOccurrenceIfNeeded(
                for: task,
                sourceReminderBeforeClear: sourceReminderForRecurrence,
                at: date
            )
        }
        try context.save()

        switch announcement {
        case .widget:
            NexusDataChangeCenter.post(.widgetTaskCreated)
        case .standard:
            if generated {
                NexusDataChangeCenter.post(.recurringOccurrenceGenerated)
            } else {
                NexusDataChangeCenter.post(.taskCreated)
                if resolvedReminder != nil {
                    NexusDataChangeCenter.post(.taskReminderChanged)
                }
                if !labelIDs.isEmpty {
                    NexusDataChangeCenter.post(.taskLabelsChanged)
                }
                if recurrenceRule != nil {
                    NexusDataChangeCenter.post(.recurrenceEnabled)
                }
            }
        }
        return task
    }

    public func update(
        _ task: TaskItem,
        title: String,
        taskDescription: String,
        status: TaskStatus,
        priority: TaskPriority,
        dueDate: Date?,
        reminderDate: Date? = nil,
        notes: String,
        labelIDs: Set<UUID>? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil,
        updateRecurrence: Bool = false,
        at date: Date = .now
    ) throws {
        guard let trimmedTitle = FieldValidation.requiredName(title) else {
            throw RepositoryValidationError.emptyName
        }

        let previousStatus = task.status
        let previousPriority = task.priority
        let previousDue = task.dueDate
        let previousReminder = task.reminderDate
        let previousLabelIDs = Set((task.labels ?? []).map(\.id))
        let previousRule = task.recurrenceRule
        let reminderForGeneration = previousReminder ?? reminderDate

        if updateRecurrence {
            let resolvedIsRoot = task.isRoot
            if let issue = TaskRecurrencePolicy.validationIssue(
                rule: recurrenceRule,
                dueDate: dueDate,
                isRoot: resolvedIsRoot
            ) {
                throw RepositoryValidationError.recurrenceInvalid(issue)
            }
        }

        task.title = trimmedTitle
        task.taskDescription = FieldValidation.trimmed(taskDescription)
        task.priority = priority
        task.dueDate = dueDate
        // Completed tasks cannot keep a schedulable reminder.
        task.reminderDate = (status == .done) ? nil : reminderDate
        task.notes = FieldValidation.trimmed(notes)

        if updateRecurrence {
            if task.isRoot {
                applyRecurrence(rule: recurrenceRule, to: task)
            } else {
                // Subtasks never carry recurrence.
                applyRecurrence(rule: nil, to: task)
            }
        }

        var labelsChanged = false
        if let labelIDs {
            let labels = try LabelRepository(context: context).fetchAll()
                .filter { labelIDs.contains($0.id) }
            let nextIDs = Set(labels.map(\.id))
            if nextIDs != previousLabelIDs {
                task.labels = labels
                labelsChanged = true
            }
        }

        if status != previousStatus {
            if task.isRoot {
                try appendToColumn(task, status: status, at: date)
            } else {
                // Subtask status is independent of Kanban columns; position stays in parent list.
                task.applyStatus(status, at: date)
                if status == .done {
                    task.reminderDate = nil
                }
                task.parentTask?.updatedAt = date
            }
        } else {
            task.updatedAt = date
            if !task.isRoot {
                task.parentTask?.updatedAt = date
            }
        }

        var generated = false
        if previousStatus != .done, task.status == .done, task.isRoot {
            generated = try generateNextOccurrenceIfNeeded(
                for: task,
                sourceReminderBeforeClear: reminderForGeneration,
                at: date
            )
        }

        try context.save()

        if generated {
            NexusDataChangeCenter.post(.recurringOccurrenceGenerated)
            return
        }

        let isSubtask = task.parentTask != nil
        if previousReminder != task.reminderDate {
            NexusDataChangeCenter.post(.taskReminderChanged)
        }
        if labelsChanged {
            NexusDataChangeCenter.post(.taskLabelsChanged)
        }
        if updateRecurrence {
            if previousRule == nil, task.recurrenceRule != nil {
                NexusDataChangeCenter.post(.recurrenceEnabled)
            } else if previousRule != nil, task.recurrenceRule == nil {
                NexusDataChangeCenter.post(.recurrenceDisabled)
            } else if previousRule != task.recurrenceRule {
                NexusDataChangeCenter.post(.recurrenceUpdated)
            }
        }
        if previousDue != dueDate {
            NexusDataChangeCenter.post(isSubtask ? .subtaskUpdated : .taskDueDateChanged)
            if isSubtask {
                NexusDataChangeCenter.post(.taskReminderChanged)
            }
        } else if previousPriority != priority {
            NexusDataChangeCenter.post(isSubtask ? .subtaskUpdated : .taskPriorityChanged)
        } else if previousStatus != status {
            NexusDataChangeCenter.post(isSubtask ? .subtaskCompletedOrReopened : .taskCompletedOrReopened)
        } else if previousReminder == task.reminderDate && !labelsChanged && !updateRecurrence {
            NexusDataChangeCenter.post(isSubtask ? .subtaskUpdated : .taskContentChanged)
        }
    }

    /// Moves a root task to a status column, appending at the end by default.
    public func moveToStatus(
        _ task: TaskItem,
        _ status: TaskStatus,
        at date: Date = .now
    ) throws {
        try move(taskID: task.id, to: status, before: nil, at: date)
    }

    /// Kanban move: place `taskID` into `status` before `targetTaskID`, or at the end when `targetTaskID` is nil.
    /// Returns `true` when a write occurred, `false` when the placement was a no-op.
    @discardableResult
    public func move(
        taskID: UUID,
        to status: TaskStatus,
        before targetTaskID: UUID?,
        at date: Date = .now
    ) throws -> Bool {
        guard let task = try fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        guard task.isRoot else {
            throw RepositoryValidationError.missingTask
        }
        guard let projectID = task.project?.id else {
            throw RepositoryValidationError.missingProject
        }

        if let targetTaskID, targetTaskID == taskID {
            return false
        }

        let previousStatus = task.status
        let reminderBeforeClear = task.reminderDate
        let destinationPeers = try fetchRootTasks(projectID: projectID, status: status)
            .filter { $0.id != taskID }

        let insertIndex: Int
        if let targetTaskID {
            guard let idx = destinationPeers.firstIndex(where: { $0.id == targetTaskID }) else {
                throw RepositoryValidationError.missingTask
            }
            insertIndex = idx
        } else {
            insertIndex = destinationPeers.count
        }

        if task.status == status {
            let currentOrder = try fetchRootTasks(projectID: projectID, status: status)
            if let currentIndex = currentOrder.firstIndex(where: { $0.id == taskID }),
               insertIndex == currentIndex {
                return false
            }
        }

        let lower = insertIndex > 0 ? destinationPeers[insertIndex - 1].position : nil
        let upper = insertIndex < destinationPeers.count ? destinationPeers[insertIndex].position : nil
        let newPosition = FractionalPosition.between(lower: lower, upper: upper)

        task.applyStatus(status, at: date)
        task.position = newPosition
        if status == .done {
            task.reminderDate = nil
        }

        var columnTasks = destinationPeers
        columnTasks.append(task)
        normalizeIfNeeded(columnTasks)

        var generated = false
        if previousStatus != .done, status == .done {
            generated = try generateNextOccurrenceIfNeeded(
                for: task,
                sourceReminderBeforeClear: reminderBeforeClear,
                at: date
            )
        }

        try context.save()
        if generated {
            NexusDataChangeCenter.post(.recurringOccurrenceGenerated)
        } else if previousStatus != status, status == .done || previousStatus == .done {
            NexusDataChangeCenter.post(.taskCompletedOrReopened)
            NexusDataChangeCenter.post(.taskReminderChanged)
        } else {
            NexusDataChangeCenter.post(.taskContentChanged)
        }
        return true
    }

    /// Move one slot earlier in the current status column (accessibility).
    public func moveEarlier(taskID: UUID, at date: Date = .now) throws -> Bool {
        guard let task = try fetchTask(id: taskID), let projectID = task.project?.id else {
            throw RepositoryValidationError.missingTask
        }
        let peers = try fetchRootTasks(projectID: projectID, status: task.status)
        guard let index = peers.firstIndex(where: { $0.id == taskID }), index > 0 else {
            return false
        }
        return try move(taskID: taskID, to: task.status, before: peers[index - 1].id, at: date)
    }

    /// Move one slot later in the current status column (accessibility).
    public func moveLater(taskID: UUID, at date: Date = .now) throws -> Bool {
        guard let task = try fetchTask(id: taskID), let projectID = task.project?.id else {
            throw RepositoryValidationError.missingTask
        }
        let peers = try fetchRootTasks(projectID: projectID, status: task.status)
        guard let index = peers.firstIndex(where: { $0.id == taskID }) else {
            return false
        }
        if index >= peers.count - 1 {
            return false
        }
        // Place after the next peer: before peer at index+2, or end.
        if index + 2 < peers.count {
            return try move(taskID: taskID, to: task.status, before: peers[index + 2].id, at: date)
        }
        return try move(taskID: taskID, to: task.status, before: nil, at: date)
    }

    /// Moves a task into a status column and assigns a fractional position between neighbors.
    public func move(
        _ task: TaskItem,
        to status: TaskStatus,
        lowerNeighbor: Double?,
        upperNeighbor: Double?,
        at date: Date = .now
    ) {
        task.applyStatus(status, at: date)
        task.position = FractionalPosition.between(lower: lowerNeighbor, upper: upperNeighbor)
    }

    /// Reindexes `position` for the given tasks when values become too dense.
    public func normalizePositions(_ tasks: [TaskItem]) {
        let sorted = tasks.sorted(by: Self.rootSort)
        let positions = FractionalPosition.normalizedPositions(count: sorted.count)
        for (task, position) in zip(sorted, positions) {
            task.position = position
            task.updatedAt = .now
        }
    }

    public func normalizeIfNeeded(_ tasks: [TaskItem]) {
        let positions = tasks.map(\.position)
        guard FractionalPosition.needsNormalization(positions: positions) else { return }
        normalizePositions(tasks)
    }

    public func delete(_ task: TaskItem, mode: TaskDeletionMode = .deleteDescendants) throws {
        switch mode {
        case .deleteDescendants:
            try deleteWithDescendants(task)
        case .promoteChildren:
            try promoteChildrenAndDelete(task)
        }
    }

    public func descendantCount(of task: TaskItem) -> Int {
        collectDescendants(of: task).count
    }

    /// Marks a task Done. Roots move to the Done column; subtasks update status only.
    public func complete(_ task: TaskItem, at date: Date = .now) throws {
        if task.isRoot {
            try move(taskID: task.id, to: .done, before: nil, at: date)
        } else {
            try applySubtaskStatus(task, .done, at: date)
        }
    }

    /// Updates only the due date (and clears recurrence when due becomes nil). Reminder absolute value is preserved.
    public func updateDueDate(
        _ task: TaskItem,
        dueDate: Date?,
        at date: Date = .now
    ) throws {
        let clearsDue = dueDate == nil
        let wasRecurring = task.isRecurring
        try update(
            task,
            title: task.title,
            taskDescription: task.taskDescription,
            status: task.status,
            priority: task.priority,
            dueDate: dueDate,
            reminderDate: task.reminderDate,
            notes: task.notes,
            labelIDs: nil,
            recurrenceRule: clearsDue ? nil : task.recurrenceRule,
            updateRecurrence: clearsDue && wasRecurring,
            at: date
        )
    }

    /// Reopens a completed task to Todo. Roots append to the Todo column; subtasks keep list position.
    public func reopen(_ task: TaskItem, at date: Date = .now) throws {
        if task.isRoot {
            try move(taskID: task.id, to: .todo, before: nil, at: date)
        } else {
            try applySubtaskStatus(task, .todo, at: date)
        }
    }

    // MARK: - Hierarchy

    public func fetchSubtasks(parentTaskID: UUID) throws -> [TaskItem] {
        guard let parent = try fetchTask(id: parentTaskID) else {
            throw RepositoryValidationError.missingTask
        }
        return TaskHierarchyPolicy.orderedSubtasks(parent.subtasks ?? [])
    }

    public func subtaskProgress(parentTaskID: UUID) throws -> SubtaskProgress {
        SubtaskProgress.from(tasks: try fetchSubtasks(parentTaskID: parentTaskID))
    }

    public func subtaskProgress(for parent: TaskItem) -> SubtaskProgress {
        SubtaskProgress.from(tasks: TaskHierarchyPolicy.orderedSubtasks(parent.subtasks ?? []))
    }

    @discardableResult
    public func createSubtask(
        parentTaskID: UUID,
        title: String,
        taskDescription: String = "",
        status: TaskStatus = .todo,
        priority: TaskPriority = .none,
        dueDate: Date? = nil,
        reminderDate: Date? = nil,
        notes: String = "",
        labelIDs: Set<UUID> = [],
        at date: Date = .now
    ) throws -> TaskItem {
        guard let parent = try fetchTask(id: parentTaskID) else {
            throw RepositoryValidationError.hierarchyInvalid(.parentNotFound)
        }
        guard let project = parent.project else {
            throw RepositoryValidationError.missingProject
        }

        let validation = TaskHierarchyPolicy.validateAttach(
            childID: UUID(),
            parentID: parent.id,
            parentExists: true,
            parentIsRoot: parent.isRoot,
            childExists: true,
            childHasChildren: false,
            childProjectID: project.id,
            parentProjectID: project.id
        )
        guard validation == .valid else {
            throw RepositoryValidationError.hierarchyInvalid(validation)
        }

        guard let trimmedTitle = FieldValidation.requiredName(title) else {
            throw RepositoryValidationError.emptyName
        }

        let resolvedReminder = (status == .done) ? nil : reminderDate
        let peers = TaskHierarchyPolicy.orderedSubtasks(parent.subtasks ?? [])
        let position = peers.last.map { FractionalPosition.after($0.position) } ?? FractionalPosition.initial()

        let task = TaskItem(
            title: trimmedTitle,
            taskDescription: FieldValidation.trimmed(taskDescription),
            status: status,
            priority: priority,
            dueDate: dueDate,
            reminderDate: resolvedReminder,
            notes: FieldValidation.trimmed(notes),
            position: position,
            createdAt: date,
            updatedAt: date,
            project: project,
            parentTask: parent
        )
        if status == .done {
            task.applyStatus(.done, at: date)
        }
        if !labelIDs.isEmpty {
            let labels = try LabelRepository(context: context).fetchAll()
                .filter { labelIDs.contains($0.id) }
            task.labels = labels
        }
        context.insert(task)
        parent.updatedAt = date
        try context.save()

        NexusDataChangeCenter.post(.subtaskCreated)
        if resolvedReminder != nil {
            NexusDataChangeCenter.post(.taskReminderChanged)
        }
        if !labelIDs.isEmpty {
            NexusDataChangeCenter.post(.taskLabelsChanged)
        }
        return task
    }

    public func attachAsSubtask(taskID: UUID, parentTaskID: UUID, at date: Date = .now) throws {
        guard let child = try fetchTask(id: taskID) else {
            throw RepositoryValidationError.hierarchyInvalid(.missingChild)
        }
        guard let parent = try fetchTask(id: parentTaskID) else {
            throw RepositoryValidationError.hierarchyInvalid(.parentNotFound)
        }

        let parentIsDescendantOfChild = collectDescendants(of: child).contains { $0.id == parentTaskID }

        let validation = TaskHierarchyPolicy.validateAttach(
            childID: child.id,
            parentID: parent.id,
            parentExists: true,
            parentIsRoot: parent.isRoot,
            childExists: true,
            childHasChildren: !(child.subtasks ?? []).isEmpty,
            childProjectID: child.project?.id,
            parentProjectID: parent.project?.id,
            parentIsDescendantOfChild: parentIsDescendantOfChild
        )
        guard validation == .valid else {
            throw RepositoryValidationError.hierarchyInvalid(validation)
        }

        if child.parentTask?.id == parent.id {
            return
        }

        let peers = TaskHierarchyPolicy.orderedSubtasks(parent.subtasks ?? []).filter { $0.id != child.id }
        child.parentTask = parent
        child.project = parent.project
        child.position = peers.last.map { FractionalPosition.after($0.position) } ?? FractionalPosition.initial()
        child.updatedAt = date
        parent.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.subtaskUpdated)
    }

    public func promoteToRoot(taskID: UUID, at date: Date = .now) throws {
        guard let child = try fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        guard let parent = child.parentTask else {
            return // already root
        }
        guard let project = child.project ?? parent.project else {
            throw RepositoryValidationError.missingProject
        }

        child.parentTask = nil
        child.project = project
        let last = try lastPosition(projectID: project.id, status: child.status)
        child.position = FractionalPosition.between(lower: last, upper: nil)
        child.updatedAt = date
        parent.updatedAt = date

        let column = try fetchRootTasks(projectID: project.id, status: child.status)
        normalizeIfNeeded(column)

        try context.save()
        NexusDataChangeCenter.post(.subtaskPromoted)
        if child.reminderDate != nil {
            NexusDataChangeCenter.post(.taskReminderChanged)
        }
    }

    @discardableResult
    public func reorderSubtask(
        taskID: UUID,
        before targetTaskID: UUID?,
        at date: Date = .now
    ) throws -> Bool {
        guard let task = try fetchTask(id: taskID),
              let parent = task.parentTask else {
            throw RepositoryValidationError.missingTask
        }
        if targetTaskID == taskID { return false }

        let ordered = TaskHierarchyPolicy.orderedSubtasks(parent.subtasks ?? [])
        guard let fromIndex = ordered.firstIndex(where: { $0.id == taskID }) else {
            return false
        }

        if let targetTaskID {
            if fromIndex + 1 < ordered.count, ordered[fromIndex + 1].id == targetTaskID {
                return false
            }
        } else if fromIndex == ordered.count - 1 {
            return false
        }

        var without = ordered.filter { $0.id != taskID }
        let insertIndex: Int
        if let targetTaskID {
            guard let idx = without.firstIndex(where: { $0.id == targetTaskID }) else {
                throw RepositoryValidationError.missingTask
            }
            insertIndex = idx
        } else {
            insertIndex = without.count
        }

        let lower = insertIndex > 0 ? without[insertIndex - 1].position : nil
        let upper = insertIndex < without.count ? without[insertIndex].position : nil
        task.position = FractionalPosition.between(lower: lower, upper: upper)
        task.updatedAt = date
        without.insert(task, at: insertIndex)
        normalizeSubtaskPositionsIfNeeded(without, at: date)
        parent.updatedAt = date
        try context.save()
        NexusDataChangeCenter.post(.subtaskReordered)
        return true
    }

    public func deleteTask(taskID: UUID, mode: TaskDeletionMode = .deleteDescendants) throws {
        guard let task = try fetchTask(id: taskID) else {
            throw RepositoryValidationError.missingTask
        }
        try delete(task, mode: mode)
    }

    private func applySubtaskStatus(_ task: TaskItem, _ status: TaskStatus, at date: Date) throws {
        let previous = task.status
        let previousReminder = task.reminderDate
        task.applyStatus(status, at: date)
        if status == .done {
            task.reminderDate = nil
        }
        task.parentTask?.updatedAt = date
        try context.save()
        if previous != status {
            NexusDataChangeCenter.post(.subtaskCompletedOrReopened)
        }
        if previousReminder != task.reminderDate {
            NexusDataChangeCenter.post(.taskReminderChanged)
        }
    }

    private func normalizeSubtaskPositionsIfNeeded(_ items: [TaskItem], at date: Date) {
        let positions = items.map(\.position)
        guard FractionalPosition.needsNormalization(positions: positions) else { return }
        let normalized = FractionalPosition.normalizedPositions(count: items.count)
        for (item, position) in zip(items, normalized) {
            item.position = position
            item.updatedAt = date
        }
    }

    private func applyRecurrence(rule: TaskRecurrenceRule?, to task: TaskItem) {
        let encoded = TaskRecurrencePolicy.encode(rule)
        task.recurrenceRuleRaw = encoded.ruleRaw
        task.recurrenceInterval = encoded.interval
        if rule == nil {
            // Stop repeating on this occurrence only. Series ID / linkage retained for history.
            return
        }
        if task.recurrenceSeriesID == nil {
            task.recurrenceSeriesID = UUID()
            task.recurrenceGeneration = 0
        }
    }

    /// Creates the next occurrence once for a completed recurring root task. Idempotent.
    @discardableResult
    private func generateNextOccurrenceIfNeeded(
        for task: TaskItem,
        sourceReminderBeforeClear: Date?,
        at date: Date
    ) throws -> Bool {
        guard task.isRoot else { return false }

        let decision = TaskRecurrencePolicy.generationDecision(
            isRoot: true,
            statusBecomingDone: true,
            ruleRaw: task.recurrenceRuleRaw,
            interval: task.recurrenceInterval,
            dueDate: task.dueDate,
            reminderDate: sourceReminderBeforeClear,
            seriesID: task.recurrenceSeriesID,
            generation: task.recurrenceGeneration,
            nextOccurrenceID: task.nextOccurrenceID,
            now: date
        )

        guard case .generate(let draft) = decision else {
            return false
        }
        guard let project = task.project else { return false }

        if task.recurrenceSeriesID == nil {
            task.recurrenceSeriesID = draft.seriesID
        }

        let position = try nextPosition(projectID: project.id, status: .todo)
        let next = TaskItem(
            title: task.title,
            taskDescription: task.taskDescription,
            status: .todo,
            priority: task.priority,
            dueDate: draft.dueDate,
            reminderDate: draft.reminderDate,
            notes: task.notes,
            position: position,
            createdAt: date,
            updatedAt: date,
            project: project,
            recurrenceRuleRaw: task.recurrenceRuleRaw,
            recurrenceInterval: task.recurrenceInterval,
            recurrenceSeriesID: draft.seriesID,
            recurrenceGeneration: draft.generation,
            previousOccurrenceID: task.id
        )
        next.labels = task.labels ?? []

        // Checklist: titles and order; all incomplete; new IDs. Do not share models.
        let sourceChecklist = orderedChecklist(task.checklist ?? [])
        var copiedChecklist: [ChecklistItem] = []
        for item in sourceChecklist {
            let copy = ChecklistItem(
                title: item.title,
                isCompleted: false,
                position: item.position,
                createdAt: date,
                updatedAt: date,
                task: next
            )
            context.insert(copy)
            copiedChecklist.append(copy)
        }
        next.checklist = copiedChecklist

        // Text/link/code/command only. Imported files are not copied.
        let sourceResources = orderedResources(task.resources ?? [])
        var copiedResources: [TaskResource] = []
        for resource in sourceResources {
            let kind = resource.kind
            if kind.isFileBacked { continue }
            let copy = TaskResource(
                kind: kind,
                title: resource.title,
                body: resource.body,
                externalURLString: resource.externalURLString,
                languageIdentifier: resource.languageIdentifier,
                position: resource.position,
                createdAt: date,
                updatedAt: date,
                task: next
            )
            context.insert(copy)
            copiedResources.append(copy)
        }
        next.resources = copiedResources

        context.insert(next)
        task.nextOccurrenceID = next.id
        task.updatedAt = date
        // Subtasks stay on the completed occurrence; not copied.
        return true
    }

    private func orderedChecklist(_ items: [ChecklistItem]) -> [ChecklistItem] {
        items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.createdAt < $1.createdAt
        }
    }

    private func orderedResources(_ items: [TaskResource]) -> [TaskResource] {
        items.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.createdAt < $1.createdAt
        }
    }

    private func appendToColumn(
        _ task: TaskItem,
        status: TaskStatus,
        at date: Date
    ) throws {
        let projectID = task.project?.id
        task.applyStatus(status, at: date)
        if let projectID {
            let peers = try fetchRootTasks(projectID: projectID, status: status)
                .filter { $0.id != task.id }
            let last = peers.map(\.position).max()
            task.position = FractionalPosition.between(lower: last, upper: nil)
            var column = peers
            column.append(task)
            normalizeIfNeeded(column)
        }
    }

    private func deleteWithDescendants(_ task: TaskItem) throws {
        let parent = task.parentTask
        let descendants = collectDescendants(of: task)
        var doomed: [TaskItem] = descendants
        doomed.append(task)
        let plan = TaskResourceRepository(context: context).managedPaths(forTasks: doomed)

        for leaf in descendants.reversed() {
            context.delete(leaf)
        }
        context.delete(task)
        if let parent {
            parent.updatedAt = .now
        }
        try context.save()
        TaskResourceRepository(context: context).applyFileCleanup(plan)
        NexusDataChangeCenter.post(.taskDeleted)
    }

    private func promoteChildrenAndDelete(_ task: TaskItem) throws {
        let date = Date.now
        // Only parent's resource files are removed; promoted children keep theirs.
        let plan = TaskResourceRepository(context: context).managedPaths(forTasks: [task])

        guard let project = task.project else {
            context.delete(task)
            try context.save()
            TaskResourceRepository(context: context).applyFileCleanup(plan)
            NexusDataChangeCenter.post(.taskDeleted)
            return
        }

        let children = TaskHierarchyPolicy.orderedSubtasks(task.subtasks ?? [])
        var lastByStatus: [TaskStatus: Double] = [:]
        for status in TaskStatus.allCases {
            lastByStatus[status] = try lastPosition(projectID: project.id, status: status)
        }

        for child in children {
            child.parentTask = nil
            child.project = project
            let last = lastByStatus[child.status]
            let next = FractionalPosition.between(lower: last, upper: nil)
            child.position = next
            lastByStatus[child.status] = next
            child.updatedAt = date
        }

        context.delete(task)
        try context.save()
        TaskResourceRepository(context: context).applyFileCleanup(plan)
        NexusDataChangeCenter.post(.taskDeleted)
        if !children.isEmpty {
            NexusDataChangeCenter.post(.subtaskPromoted)
        }
    }

    /// Depth-first collection of all descendants (not including `root`).
    public func collectDescendants(of root: TaskItem) -> [TaskItem] {
        var result: [TaskItem] = []
        func visit(_ node: TaskItem) {
            let children = node.subtasks ?? []
            for child in children {
                result.append(child)
                visit(child)
            }
        }
        visit(root)
        return result
    }

    private static func rootSort(_ lhs: TaskItem, _ rhs: TaskItem) -> Bool {
        if lhs.position != rhs.position {
            return lhs.position < rhs.position
        }
        return lhs.createdAt < rhs.createdAt
    }
}
