import SwiftUI
import TodoshiCore

/// Root-task responsibility. Owner edits; every other member sees it read-only.
///
/// Assignment is not authorization: when the chosen member is restricted, the same
/// task-document write also grants them `editorUIDs` access so the work is actionable.
struct TaskDetailAssignmentSection: View {
    let projectID: UUID
    let rootTask: TaskItem
    let members: [ProjectMemberRow]
    let canAssign: Bool
    var onError: (String) -> Void

    @Environment(\.modelContext) private var modelContext

    private var candidates: [AssignmentCandidate] { members.assignmentCandidates }

    private var currentName: String {
        TaskAssignmentPresentation.assigneeName(for: rootTask.assigneeUID, members: candidates)
    }

    private var showsGrantFooter: Bool {
        canAssign && candidates.contains(where: \.needsEditorGrant)
    }

    var body: some View {
        Section {
            if canAssign {
                Picker(
                    TaskAssignmentPresentation.assigneeLabel,
                    selection: Binding(
                        get: { rootTask.assigneeUID },
                        set: { apply($0) }
                    )
                ) {
                    Text(TaskAssignmentPresentation.unassigned)
                        .tag(String?.none)
                    ForEach(candidates) { candidate in
                        Text(TaskAssignmentPresentation.memberDisplayName(candidate.displayName))
                            .tag(String?.some(candidate.uid))
                    }
                }
                .pickerStyle(.navigationLink)
            } else {
                LabeledContent(TaskAssignmentPresentation.assigneeLabel) {
                    Label(currentName, systemImage: "person.fill")
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(rootTask.assigneeUID == nil ? .secondary : .primary)
                }
            }
        } header: {
            Text(TaskAssignmentPresentation.assigneeSectionTitle)
        } footer: {
            if showsGrantFooter {
                Text(TaskAssignmentPresentation.autoGrantFooter)
            }
        }
    }

    private func apply(_ uid: String?) {
        guard canAssign, TaskAssignmentPolicy.canAssign(task: rootTask) else { return }
        guard uid != rootTask.assigneeUID else { return }

        var candidate: AssignmentCandidate?
        if let uid {
            guard let match = candidates.first(where: { $0.uid == uid }) else {
                onError(UserFacingError.message(for: CollaborationError.membersLoadFailed))
                return
            }
            candidate = match
        }

        let plan = TaskAssignmentPolicy.plan(
            assignTo: candidate,
            currentEditorUIDs: rootTask.editorUIDs ?? []
        )
        rootTask.assigneeUID = plan.assigneeUID
        // Keep a nil (unknown) ACL untouched unless the assignment actually needs a grant.
        if plan.grantsEditAccess {
            rootTask.editorUIDs = plan.editorUIDs
        }
        rootTask.updatedAt = .now

        do {
            try modelContext.save()
            // One task-document upsert carries assigneeUID and editorUIDs together.
            SharedProjectMutationHook.emit(.taskUpsert(projectID: projectID, taskID: rootTask.id))
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }
}
