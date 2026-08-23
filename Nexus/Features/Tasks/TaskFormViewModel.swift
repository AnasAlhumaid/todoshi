import Foundation
import Observation
import SwiftData
import NexusCore

@Observable
@MainActor
final class TaskFormViewModel {
    var draft: TaskDraft
    var errorMessage: String?
    var schedulingWarning: String?
    var showPermissionExplainer = false
    var authorizationState: NotificationAuthorizationState = .unknown
    var availableLabels: [LabelSummary] = []
    var parentTitle: String?

    private let projectID: UUID
    private let taskID: UUID?
    private let context: ModelContext
    private let scheduler = LocalNotificationScheduler()

    var isEditing: Bool { taskID != nil }
    var isCreatingSubtask: Bool { !isEditing && draft.parentTaskID != nil }
    var canSave: Bool {
        draft.isValid && draft.reminderValidationIssue() == nil && draft.checklistDraftsAreValid && draft.resourceDraftsAreValid
    }

    /// Recurrence is root-task only (not Quick Add, not subtasks).
    var showsRecurrenceControls: Bool {
        draft.parentTaskID == nil
    }
    var navigationTitle: String {
        if isEditing {
            return NexusL10n.tr("task.edit")
        }
        return isCreatingSubtask ? SubtaskStrings.newSubtaskTitle : NexusL10n.tr("task.new")
    }

    /// Focus target after adding a draft checklist row.
    var focusedChecklistDraftID: UUID?

    /// Owner id for staged file imports (real task id when editing).
    private let resourceOwnerID: UUID
    private let fileStore: TaskResourceFileStore

    var reminderValidationMessage: String? {
        guard let issue = draft.reminderValidationIssue() else { return nil }
        return TaskReminderValidation.message(for: issue)
    }

    var selectedLabelSummaries: [LabelSummary] {
        availableLabels.filter { draft.labelIDs.contains($0.id) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    init(
        context: ModelContext,
        projectID: UUID,
        taskID: UUID? = nil,
        initialStatus: TaskStatus = .todo,
        parentTaskID: UUID? = nil,
        initialDueDate: Date? = nil,
        fileStore: TaskResourceFileStore = .shared
    ) {
        self.context = context
        self.projectID = projectID
        self.taskID = taskID
        self.fileStore = fileStore
        self.resourceOwnerID = taskID ?? UUID()
        if let taskID,
           let task = try? TaskRepository(context: context).fetchTask(id: taskID) {
            self.draft = TaskDraft(task: task)
            if let parent = task.parentTask {
                self.parentTitle = parent.title
            }
        } else {
            var draft = TaskDraft(status: initialStatus)
            draft.parentTaskID = parentTaskID
            if let initialDueDate {
                draft.hasDueDate = true
                draft.dueDate = initialDueDate
            }
            self.draft = draft
            if let parentTaskID,
               let parent = try? TaskRepository(context: context).fetchTask(id: parentTaskID) {
                self.parentTitle = parent.title
            }
        }
        reloadLabels()
    }

    /// Remove staged imported files when the form is cancelled.
    func discardStagedResourceFiles() {
        let paths = TaskResourceDraftCleanup.stagedRelativePaths(in: draft.resources)
        for path in paths {
            fileStore.deleteIfExists(at: path)
        }
    }

    func addResourceDraft(_ resource: TaskResourceDraft) {
        var copy = resource
        copy.position = TaskResourceDraftBuilder.nextPosition(after: draft.resources)
        draft.resources.append(copy)
    }

    func updateResourceDraft(_ resource: TaskResourceDraft) {
        guard let index = draft.resources.firstIndex(where: { $0.id == resource.id }) else {
            addResourceDraft(resource)
            return
        }
        draft.resources[index] = resource
    }

    func deleteResourceDraft(id: UUID) {
        if let existing = draft.resources.first(where: { $0.id == id }),
           existing.importState == .staged,
           let path = existing.relativeFilePath {
            fileStore.deleteIfExists(at: path)
        }
        draft.resources.removeAll { $0.id == id }
    }

    func moveResourceDrafts(from source: IndexSet, to destination: Int) {
        draft.resources.move(fromOffsets: source, toOffset: destination)
        let positions = FractionalPosition.normalizedPositions(count: draft.resources.count)
        for index in draft.resources.indices {
            draft.resources[index].position = positions[index]
        }
    }

    func importFile(from url: URL, preferredKind: TaskResourceKind? = nil) throws {
        let resourceID = UUID()
        let imported = try fileStore.importFile(from: url, taskID: resourceOwnerID, resourceID: resourceID)
        let kind = preferredKind ?? imported.inferredKind
        var draft = TaskResourceDraft(
            id: resourceID,
            kind: kind,
            title: "",
            relativeFilePath: imported.relativePath,
            originalFileName: imported.originalFileName,
            mimeType: imported.mimeType,
            fileSize: imported.fileSize,
            position: TaskResourceDraftBuilder.nextPosition(after: self.draft.resources),
            importState: .staged
        )
        self.draft.resources.append(draft)
        _ = draft
    }

    func reloadLabels() {
        availableLabels = (try? LabelRepository(context: context).summaries()) ?? []
        draft.pruneMissingLabels(validIDs: Set(availableLabels.map(\.id)))
    }

    func refreshAuthorization() async {
        authorizationState = await scheduler.authorizationStatus()
    }

    func setReminderEnabled(_ enabled: Bool) {
        if enabled {
            if authorizationState == .notDetermined {
                showPermissionExplainer = true
            }
            draft.enableReminder()
            if draft.status == .done {
                errorMessage = TaskReminderValidation.message(for: .completedTaskCannotHaveReminder)
            }
        } else {
            draft.disableReminder()
            errorMessage = nil
        }
    }

    func requestPermissionFromExplainer() async {
        do {
            _ = try await scheduler.requestAuthorization()
            authorizationState = await scheduler.authorizationStatus()
        } catch {
            errorMessage = UserFacingError.message(for: error)
        }
    }

    func addChecklistDraft() {
        let next = ChecklistItemDraft(
            title: "",
            position: ChecklistDraftBuilder.nextPosition(after: draft.checklistItems)
        )
        draft.checklistItems.append(next)
        focusedChecklistDraftID = next.id
    }

    func deleteChecklistDraft(id: UUID) {
        draft.checklistItems.removeAll { $0.id == id }
        if focusedChecklistDraftID == id {
            focusedChecklistDraftID = nil
        }
    }

    func moveChecklistDrafts(from source: IndexSet, to destination: Int) {
        draft.checklistItems.move(fromOffsets: source, toOffset: destination)
        let positions = FractionalPosition.normalizedPositions(count: draft.checklistItems.count)
        for index in draft.checklistItems.indices {
            draft.checklistItems[index].position = positions[index]
        }
    }

    @discardableResult
    func save() -> Bool {
        errorMessage = nil
        schedulingWarning = nil

        if let issue = draft.reminderValidationIssue() {
            errorMessage = TaskReminderValidation.message(for: issue)
            return false
        }

        if !draft.checklistDraftsAreValid {
            errorMessage = ChecklistStrings.invalidItem
            return false
        }
        if !draft.resourceDraftsAreValid {
            errorMessage = TaskResourceStrings.emptyResource
            return false
        }

        reloadLabels()

        let tasks = TaskRepository(context: context)
        let projects = ProjectRepository(context: context)
        let checklists = ChecklistRepository(context: context)
        let resources = TaskResourceRepository(context: context, fileStore: fileStore)
        do {
            let savedTaskID: UUID
            if let taskID {
                guard let task = try tasks.fetchTask(id: taskID) else {
                    errorMessage = NexusL10n.tr("task.notFound")
                    return false
                }
                try tasks.update(
                    task,
                    title: draft.title,
                    taskDescription: draft.taskDescription,
                    status: draft.status,
                    priority: draft.priority,
                    dueDate: draft.resolvedDueDate,
                    reminderDate: draft.resolvedReminderDate,
                    notes: draft.notes,
                    labelIDs: draft.labelIDs,
                    recurrenceRule: showsRecurrenceControls ? draft.resolvedRecurrenceRule : nil,
                    updateRecurrence: showsRecurrenceControls
                )
                savedTaskID = task.id
            } else if let parentTaskID = draft.parentTaskID {
                guard try tasks.fetchTask(id: parentTaskID) != nil else {
                    errorMessage = SubtaskStrings.invalidParent
                    return false
                }
                let created = try tasks.createSubtask(
                    parentTaskID: parentTaskID,
                    title: draft.title,
                    taskDescription: draft.taskDescription,
                    status: draft.status,
                    priority: draft.priority,
                    dueDate: draft.resolvedDueDate,
                    reminderDate: draft.resolvedReminderDate,
                    notes: draft.notes,
                    labelIDs: draft.labelIDs
                )
                savedTaskID = created.id
            } else {
                guard let project = try projects.fetchProject(id: projectID) else {
                    errorMessage = NexusL10n.tr("project.notFound")
                    return false
                }
                guard project.status == .active else {
                    errorMessage = NexusL10n.tr("task.activeProjectRequired")
                    return false
                }
                let created = try tasks.create(
                    in: project,
                    title: draft.title,
                    taskDescription: draft.taskDescription,
                    status: draft.status,
                    priority: draft.priority,
                    dueDate: draft.resolvedDueDate,
                    reminderDate: draft.resolvedReminderDate,
                    notes: draft.notes,
                    labelIDs: draft.labelIDs,
                    recurrenceRule: draft.resolvedRecurrenceRule
                )
                savedTaskID = created.id
            }

            try checklists.replaceChecklist(taskID: savedTaskID, drafts: draft.checklistItems)

            var resourceDrafts = draft.resources
            if savedTaskID != resourceOwnerID {
                try fileStore.rehomeTaskDirectory(from: resourceOwnerID, to: savedTaskID)
                for index in resourceDrafts.indices {
                    if let path = resourceDrafts[index].relativeFilePath {
                        resourceDrafts[index].relativeFilePath = TaskResourceFileStore.rehomeRelativePath(
                            path,
                            from: resourceOwnerID,
                            to: savedTaskID
                        )
                    }
                }
            }
            try resources.replaceDraftResources(taskID: savedTaskID, drafts: resourceDrafts)

            if draft.hasReminder, authorizationState == .denied {
                schedulingWarning = NotificationStrings.deniedMessage
            }
            return true
        } catch RepositoryValidationError.emptyName {
            errorMessage = NexusL10n.tr("task.titleRequired")
            return false
        } catch RepositoryValidationError.checklistTitleTooLong {
            errorMessage = ChecklistStrings.titleTooLong
            return false
        } catch RepositoryValidationError.hierarchyInvalid(let result) {
            errorMessage = hierarchyMessage(result)
            return false
        } catch RepositoryValidationError.resourceInvalid(let issue) {
            errorMessage = TaskResourceValidation.message(for: issue)
            return false
        } catch RepositoryValidationError.recurrenceInvalid(let issue) {
            errorMessage = issue.message
            return false
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }

    private func hierarchyMessage(_ result: TaskHierarchyValidationResult) -> String {
        switch result {
        case .valid: return ""
        case .parentNotFound: return SubtaskStrings.invalidParent
        case .parentIsAlreadySubtask, .nestedHierarchyNotAllowed: return SubtaskStrings.cannotAddNested
        case .projectMismatch: return SubtaskStrings.sameProjectRequired
        case .selfParenting, .cycleDetected: return SubtaskStrings.invalidParent
        case .missingChild: return NexusL10n.tr("task.notFound")
        }
    }
}