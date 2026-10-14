import SwiftUI
import TodoshiCore

/// Owner-only task ACL editor for root tasks (restricted members toggled into `editorUIDs`).
struct TaskDetailPermissionsSection: View {
    let projectID: UUID
    let rootTask: TaskItem
    let members: [ProjectMemberRow]
    var onError: (String) -> Void
    /// Surfaced when a change is blocked by an assignment integrity rule rather than failing.
    var onGuard: (String) -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Section(SharedTaskPermissionPresentation.taskPermissions) {
            ForEach(members) { member in
                row(for: member)
            }
        }
    }

    @ViewBuilder
    private func row(for member: ProjectMemberRow) -> some View {
        let name = displayName(for: member)
        if member.role == .owner {
            HStack {
                Text(name)
                Spacer()
                Text(SharedTaskPermissionPresentation.alwaysOwner)
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
            }
        } else if member.resolvedAccessLevel == .full {
            HStack {
                Text(name)
                Spacer()
                Text(SharedTaskPermissionPresentation.hasFullAccess)
                    .font(TodoshiTypography.metadata)
                    .foregroundStyle(.secondary)
            }
        } else {
            Toggle(isOn: Binding(
                get: { (rootTask.editorUIDs ?? []).contains(member.userId) },
                set: { enabled in setEditor(enabled, for: member) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    if member.userId == rootTask.assigneeUID {
                        Text(TaskAssignmentPresentation.assigneeLabel)
                            .font(TodoshiTypography.metadata)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func displayName(for member: ProjectMemberRow) -> String {
        let trimmed = member.displayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return TodoshiL10n.tr("project.members.unnamed")
        }
        return trimmed
    }

    private func setEditor(_ enabled: Bool, for member: ProjectMemberRow) {
        let uid = member.userId
        // Never leave the responsible restricted member without the access their work needs.
        if !enabled,
           !TaskAssignmentIntegrityPolicy.canRemoveEditor(
               uid: uid,
               assigneeUID: rootTask.assigneeUID,
               candidate: member.assignmentCandidate
           ) {
            onGuard(TaskAssignmentPresentation.assigneeAclGuard)
            return
        }
        let next = SharedTaskEditorInheritance.withEditor(
            rootTask.editorUIDs ?? [],
            including: uid,
            enabled: enabled
        )
        rootTask.editorUIDs = next
        rootTask.updatedAt = .now
        do {
            try modelContext.save()
            SharedProjectMutationHook.emit(.taskUpsert(projectID: projectID, taskID: rootTask.id))
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }
}
