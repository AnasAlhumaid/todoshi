import Foundation
import Observation
import SwiftData
import TodoshiCore

@Observable
@MainActor
final class QuickAddViewModel {
    var draft: QuickAddDraft
    var errorMessage: String?
    private(set) var activeProjects: [Project] = []

    private let context: ModelContext
    private let lastProjectStorage: (String?) -> Void
    private let readLastProjectStorage: () -> String?

    var canSave: Bool { draft.isValid }
    var hasActiveProjects: Bool { !activeProjects.isEmpty }

    var selectedProjectType: ProjectType {
        guard let id = draft.projectID,
              let project = activeProjects.first(where: { $0.id == id })
        else { return .tasks }
        return project.projectType
    }

    var allowedStatuses: [TaskStatus] {
        ProjectTypeCapabilities.allowedStatuses(for: selectedProjectType)
    }

    init(
        context: ModelContext,
        lastProjectIDStored: String? = nil,
        preselectedProjectID: UUID? = nil,
        showsOptionalFields: Bool = false,
        persistLastProjectID: @escaping (String?) -> Void = { _ in },
        readLastProjectID: @escaping () -> String? = { nil }
    ) {
        self.context = context
        self.lastProjectStorage = persistLastProjectID
        self.readLastProjectStorage = readLastProjectID
        self.draft = QuickAddDraft(showsOptionalFields: showsOptionalFields)
        reloadProjects(
            preferredStoredID: lastProjectIDStored ?? readLastProjectID(),
            preselectedProjectID: preselectedProjectID
        )
    }

    func reloadProjects(preferredStoredID: String? = nil, preselectedProjectID: UUID? = nil) {
        do {
            activeProjects = try ProjectRepository(context: context).fetch(status: .active)
            let ids = Set(activeProjects.map(\.id))
            let stored = preferredStoredID ?? readLastProjectStorage()
            if let preselected = preselectedProjectID, ids.contains(preselected) {
                draft.projectID = preselected
            } else if let resolved = QuickAddPreferences.resolvedProjectID(stored: stored, activeProjectIDs: ids) {
                draft.projectID = resolved
            } else {
                if let current = draft.projectID, ids.contains(current) {
                    // keep selection
                } else {
                    draft.projectID = activeProjects.first?.id
                }
                if QuickAddPreferences.resolvedProjectID(stored: stored, activeProjectIDs: ids) == nil,
                   stored != nil {
                    lastProjectStorage(nil)
                }
            }
            clampStatusToSelectedProject()
        } catch {
            errorMessage = UserFacingError.message(for: error)
            activeProjects = []
        }
    }

    /// Returns created task ID on success.
    @discardableResult
    func save() -> UUID? {
        errorMessage = nil
        guard let projectID = draft.projectID else {
            errorMessage = TodoshiL10n.tr("task.chooseProject")
            return nil
        }
        do {
            let projects = ProjectRepository(context: context)
            guard let project = try projects.fetchProject(id: projectID),
                  project.status == .active else {
                errorMessage = TodoshiL10n.tr("task.chooseActiveProject")
                draft.projectID = nil
                reloadProjects()
                return nil
            }
            let task = try TaskRepository(context: context).create(
                in: project,
                title: draft.title,
                taskDescription: draft.taskDescription,
                status: draft.status,
                priority: draft.priority,
                dueDate: draft.resolvedDueDate,
                notes: draft.notes
            )
            lastProjectStorage(QuickAddPreferences.storageValue(for: project.id))
            return task.id
        } catch RepositoryValidationError.emptyName {
            errorMessage = TodoshiL10n.tr("task.titleRequired")
            return nil
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return nil
        }
    }

    func selectProject(_ projectID: UUID?) {
        draft.projectID = projectID
        clampStatusToSelectedProject()
    }

    private func clampStatusToSelectedProject() {
        let allowed = allowedStatuses
        if !allowed.contains(draft.status) {
            draft.status = ProjectTypeCapabilities.defaultStatus(for: selectedProjectType)
        }
        if selectedProjectType == .checklist {
            draft.priority = .none
        }
    }
}
