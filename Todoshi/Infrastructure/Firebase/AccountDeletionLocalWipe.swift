import Foundation
import SwiftData
import TodoshiCore

/// Clears local Todoshi content after successful cloud + Auth account deletion.
/// Preserves App Group container structure and does not destroy the store files.
@MainActor
enum AccountDeletionLocalWipe {
    static func wipeAllUserContent(context: ModelContext, uid: String?) throws {
        let projectRepo = ProjectRepository(context: context)
        let projects = try projectRepo.fetchAll()
        for project in projects {
            try projectRepo.delete(project)
        }

        let labelRepo = LabelRepository(context: context)
        let labels = try labelRepo.fetchAll()
        for label in labels {
            try labelRepo.delete(labelID: label.id)
        }

        if let uid {
            TodoshiIdentityCache.clear(for: uid)
            TaskActivitySeenStore.clearAll(for: uid)
        } else {
            TodoshiIdentityCache.clearAll()
            TaskActivitySeenStore.clearAll()
        }

        TodoshiDataChangeCenter.post(.projectStructureChanged)
    }
}
