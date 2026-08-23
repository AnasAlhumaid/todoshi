import Foundation
import Observation
import SwiftData
import NexusCore

@Observable
@MainActor
final class LabelFormViewModel {
    var draft: LabelDraft
    var errorMessage: String?

    private let labelID: UUID?
    private let context: ModelContext

    var isEditing: Bool { labelID != nil }
    var navigationTitle: String { isEditing ? LabelStrings.editLabel : LabelStrings.newLabel }
    var canSave: Bool {
        errorMessage == nil && draft.validationIssue(existing: existingEntries, excludingLabelID: labelID) == nil
    }

    private var existingEntries: [(id: UUID, name: String)] {
        (try? LabelRepository(context: context).fetchAll().map { (id: $0.id, name: $0.name) }) ?? []
    }

    init(context: ModelContext, labelID: UUID? = nil) {
        self.context = context
        self.labelID = labelID
        if let labelID, let label = try? LabelRepository(context: context).fetch(id: labelID) {
            self.draft = LabelDraft(label: label)
        } else {
            self.draft = LabelDraft()
        }
    }

    func validateLive() {
        if let issue = draft.validationIssue(existing: existingEntries, excludingLabelID: labelID) {
            errorMessage = LabelValidation.message(for: issue)
        } else {
            errorMessage = nil
        }
    }

    @discardableResult
    func save() -> Bool {
        validateLive()
        guard canSave else { return false }
        let repo = LabelRepository(context: context)
        do {
            if let labelID {
                try repo.update(labelID: labelID, name: draft.name, colorHex: draft.colorHex)
            } else {
                _ = try repo.create(name: draft.name, colorHex: draft.colorHex)
            }
            return true
        } catch RepositoryValidationError.emptyName {
            errorMessage = LabelStrings.nameRequired
            return false
        } catch RepositoryValidationError.duplicateLabelName {
            errorMessage = LabelStrings.duplicateName
            return false
        } catch RepositoryValidationError.labelNameTooLong {
            errorMessage = LabelStrings.nameTooLong
            return false
        } catch {
            errorMessage = UserFacingError.message(for: error)
            return false
        }
    }
}
