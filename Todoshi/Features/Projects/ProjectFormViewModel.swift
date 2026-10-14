import Foundation
import Observation
import SwiftData
import TodoshiCore

@Observable
@MainActor
final class ProjectFormViewModel {
    enum Step: Equatable {
        case chooseType
        case details
    }

    var draft: ProjectDraft
    var errorMessage: String?
    var step: Step

    private let projectID: UUID?
    private let context: ModelContext

    var isEditing: Bool { projectID != nil }
    var canSave: Bool { draft.isValid && (isEditing || step == .details) }
    var navigationTitle: String {
        if isEditing { return TodoshiL10n.tr("project.edit") }
        if step == .chooseType { return ProjectTerminologyPolicy.chooseTypeTitle }
        return TodoshiL10n.tr("project.new")
    }

    init(context: ModelContext, projectID: UUID? = nil) {
        self.context = context
        self.projectID = projectID
        if let projectID,
           let project = try? ProjectRepository(context: context).fetchProject(id: projectID) {
            self.draft = ProjectDraft(project: project)
            self.step = .details
        } else {
            self.draft = ProjectDraft()
            self.step = .chooseType
        }
    }

    func selectType(_ type: ProjectType) {
        guard !isEditing else { return }
        draft.projectType = type
        if draft.icon == ProjectIconCatalog.defaultSymbol || draft.icon == "checklist" {
            draft.icon = ProjectTypeCapabilities.defaultIcon(for: type)
        }
        step = .details
    }

    func goBackToTypeSelection() {
        guard !isEditing else { return }
        step = .chooseType
    }

    @discardableResult
    func save() -> Bool {
        errorMessage = nil
        let repo = ProjectRepository(context: context)
        do {
            if let projectID {
                guard let project = try repo.fetchProject(id: projectID) else {
                    errorMessage = TodoshiL10n.tr("project.notFound")
                    return false
                }
                try repo.update(
                    project,
                    name: draft.name,
                    icon: draft.icon,
                    colorHex: draft.colorHex,
                    projectDescription: draft.projectDescription
                )
            } else {
                _ = try repo.create(
                    name: draft.name,
                    icon: draft.icon,
                    colorHex: draft.colorHex,
                    projectDescription: draft.projectDescription,
                    projectType: draft.projectType
                )
            }
            return true
        } catch RepositoryValidationError.emptyName {
            errorMessage = TodoshiL10n.tr("project.nameRequired")
            return false
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }
}
