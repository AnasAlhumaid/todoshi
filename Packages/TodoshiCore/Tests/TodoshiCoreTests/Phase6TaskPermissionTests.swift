import Foundation
import SwiftData
import Testing
@testable import TodoshiCore

struct Phase6TaskPermissionTests {
    @Test("Legacy membership without accessLevel resolves to full")
    func legacyDefault() {
        #expect(ProjectMemberAccessLevel.resolved(raw: nil) == .full)
        #expect(ProjectMemberAccessLevel.resolved(raw: "") == .full)
        #expect(ProjectMemberAccessLevel.resolved(raw: "full") == .full)
        #expect(ProjectMemberAccessLevel.resolved(raw: "restricted") == .restricted)
        #expect(ProjectMemberAccessLevel.inviteDefault == .restricted)
        #expect(ProjectMemberAccessLevel.legacyDefault == .full)
    }

    @Test("Owner always can edit regardless of editorUIDs")
    func ownerAlwaysEdits() {
        #expect(
            SharedTaskEditAuthorization.canEditTaskContent(
                role: .owner,
                accessLevel: .restricted,
                viewerUID: "owner",
                rootEditorUIDs: []
            )
        )
        #expect(SharedTaskEditAuthorization.canManageAccessLevels(role: .owner))
        #expect(SharedTaskEditAuthorization.canManageTaskEditorUIDs(role: .owner))
        #expect(!SharedTaskEditAuthorization.canManageAccessLevels(role: .member))
        #expect(!SharedTaskEditAuthorization.canManageTaskEditorUIDs(role: .member))
    }

    @Test("Full member can edit any task")
    func fullMemberPolicy() {
        #expect(
            SharedTaskEditAuthorization.canEditTaskContent(
                role: .member,
                accessLevel: .full,
                viewerUID: "m1",
                rootEditorUIDs: []
            )
        )
        #expect(
            SharedTaskEditAuthorization.canCreateRootTask(role: .member, accessLevel: .full)
        )
        #expect(
            SharedTaskEditAuthorization.canMutateProjectLabels(role: .member, accessLevel: .full)
        )
    }

    @Test("Restricted member allowed and denied by editorUIDs")
    func restrictedPolicy() {
        #expect(
            SharedTaskEditAuthorization.canEditTaskContent(
                role: .member,
                accessLevel: .restricted,
                viewerUID: "m1",
                rootEditorUIDs: ["m1"]
            )
        )
        #expect(
            !SharedTaskEditAuthorization.canEditTaskContent(
                role: .member,
                accessLevel: .restricted,
                viewerUID: "m1",
                rootEditorUIDs: ["other"]
            )
        )
        #expect(
            !SharedTaskEditAuthorization.canCreateRootTask(role: .member, accessLevel: .restricted)
        )
        #expect(
            !SharedTaskEditAuthorization.canMutateProjectLabels(role: .member, accessLevel: .restricted)
        )
    }

    @Test("Nil accessLevel on member treated as full (legacy)")
    func nilAccessLevelFull() {
        #expect(
            SharedTaskEditAuthorization.canEditTaskContent(
                role: .member,
                accessLevel: nil,
                viewerUID: "m1",
                rootEditorUIDs: []
            )
        )
    }

    @Test("Editor lookup on a hard-deleted task returns empty instead of trapping")
    @MainActor
    func editorLookupAfterRemoteDelete() throws {
        let context = ModelContext(try ModelContainerFactory.makeContainer(kind: .inMemory))
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let task = try TaskRepository(context: context).create(in: project, title: "Milk")
        task.editorUIDs = ["editor-a"]
        try context.save()
        #expect(task.isLive)
        #expect(SharedTaskEditorInheritance.editorUIDs(for: task) == ["editor-a"])

        // Mirrors SharedProjectSyncService applying a remote soft-delete.
        context.delete(task)
        try context.save()
        #expect(!task.isLive)
        #expect(SharedTaskEditorInheritance.editorUIDs(for: task).isEmpty)
    }

    @Test("Root → subtask editor inheritance")
    func rootSubtaskInheritance() {
        let root = TaskItem(title: "Root", project: nil)
        root.editorUIDs = ["editor-a"]
        let child = TaskItem(title: "Child", project: nil)
        child.parentTask = root
        #expect(SharedTaskEditorInheritance.rootTaskID(for: child) == root.id)
        #expect(SharedTaskEditorInheritance.editorUIDs(for: child) == ["editor-a"])
        #expect(SharedTaskEditorInheritance.editorUIDs(for: root) == ["editor-a"])
        #expect(
            SharedTaskEditAuthorization.canCreateSubtask(
                role: .member,
                accessLevel: .restricted,
                viewerUID: "editor-a",
                rootEditorUIDs: SharedTaskEditorInheritance.editorUIDs(for: child)
            )
        )
    }

    @Test("withEditor toggles UID set")
    func withEditor() {
        #expect(
            SharedTaskEditorInheritance.withEditor([], including: "a", enabled: true) == ["a"]
        )
        #expect(
            SharedTaskEditorInheritance.withEditor(["a", "b"], including: "a", enabled: false) == ["b"]
        )
    }

    @Test("Comments remain independent of task edit permission")
    func commentsIndependent() {
        #expect(SharedTaskEditAuthorization.canCommentIndependentlyOfTaskEdit())
        #expect(SharedProjectRolePermissions.canCreateComments(role: .member))
    }

    @Test("Permission presentation localization keys resolve")
    func presentationStrings() {
        #expect(!SharedTaskPermissionPresentation.sectionTitle.isEmpty)
        #expect(!SharedTaskPermissionPresentation.fullAccess.isEmpty)
        #expect(!SharedTaskPermissionPresentation.selectedTasksOnly.isEmpty)
        #expect(!SharedTaskPermissionPresentation.readOnly.isEmpty)
        #expect(!SharedTaskPermissionPresentation.permissionRevoked.isEmpty)
        let ar = Locale(identifier: "ar")
        #expect(TodoshiL10n.tr("project.permissions.taskAccess", locale: ar) == "صلاحيات المهام")
        #expect(TodoshiL10n.tr("project.permissions.fullAccess", locale: ar) == "صلاحية كاملة")
        #expect(TodoshiL10n.tr("task.permissions.revoked", locale: ar).contains("صلاحية"))
    }

    @Test("Local gate blocks restricted without editorUID")
    func localGate() {
        #expect(
            SharedTaskPermissionGate.shouldBlockLocalMutation(
                isShared: true,
                role: .member,
                accessLevel: .restricted,
                viewerUID: "m1",
                rootEditorUIDs: []
            )
        )
        #expect(
            !SharedTaskPermissionGate.shouldBlockLocalMutation(
                isShared: false,
                role: .member,
                accessLevel: .restricted,
                viewerUID: "m1",
                rootEditorUIDs: []
            )
        )
    }

    @Test("DTO member resolvedAccessLevel and task editorUIDs round-trip")
    @MainActor
    func dtoMapping() throws {
        let member = FirebaseProjectMemberDTO(
            userId: "u1",
            role: .member,
            displayName: "A",
            joinedAt: .now,
            accessLevel: nil
        )
        #expect(member.resolvedAccessLevel == .full)

        let container = try ModelContainerFactory.makeContainer(kind: .inMemory)
        let context = ModelContext(container)
        let project = Project(name: "P")
        context.insert(project)
        let task = TaskItem(title: "T", project: project)
        task.editorUIDs = ["u1", "u2"]
        context.insert(task)
        let dto = try #require(FirestoreTaskMapping.dto(from: task))
        #expect(dto.editorUIDs == ["u1", "u2"])
        let other = TaskItem(title: "X", project: project)
        context.insert(other)
        FirestoreTaskMapping.apply(dto, to: other)
        #expect(other.editorUIDs == ["u1", "u2"])
    }

    @Test("Permission-denied error maps to revoked message")
    func permissionDeniedMessage() {
        let msg = UserFacingError.message(for: CollaborationError.taskEditPermissionDenied)
        #expect(msg == SharedTaskPermissionPresentation.permissionRevoked)
    }
}
