import Foundation
import Observation
import SwiftData
import NexusCore

@Observable
@MainActor
final class ProjectFormViewModel {
    var draft: ProjectDraft
    var errorMessage: String?

    private let projectID: UUID?
    private let context: ModelContext

    var isEditing: Bool { projectID != nil }
    var canSave: Bool { draft.isValid }
    var navigationTitle: String { isEditing ? NexusL10n.tr("project.edit") : NexusL10n.tr("project.new") }

    init(context: ModelContext, projectID: UUID? = nil) {
        self.context = context
        self.projectID = projectID
        if let projectID,
           let project = try? ProjectRepository(context: context).fetchProject(id: projectID) {
            self.draft = ProjectDraft(project: project)
        } else {
            self.draft = ProjectDraft()
        }
    }

    @discardableResult
    func save() -> Bool {
        errorMessage = nil
        let repo = ProjectRepository(context: context)
        do {
            if let projectID {
                guard let project = try repo.fetchProject(id: projectID) else {
                    errorMessage = NexusL10n.tr("project.notFound")
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
                    projectDescription: draft.projectDescription
                )
            }
            return true
        } catch RepositoryValidationError.emptyName {
            errorMessage = NexusL10n.tr("project.nameRequired")
            return false
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }
}
