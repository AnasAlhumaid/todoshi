import Foundation
import SwiftData
import Testing
@testable import TodoshiCore

@MainActor
struct Phase7TaskAssignmentTests {
    private func makeContainer() throws -> ModelContainer {
        try ModelContainerFactory.makeContainer(kind: .inMemory)
    }

    private func owner(_ uid: String = "owner-uid") -> AssignmentCandidate {
        AssignmentCandidate(uid: uid, role: .owner, accessLevel: .full, displayName: "Owner")
    }

    private func fullMember(_ uid: String = "full-uid") -> AssignmentCandidate {
        AssignmentCandidate(uid: uid, role: .member, accessLevel: .full, displayName: "Full")
    }

    private func restrictedMember(_ uid: String = "restricted-uid") -> AssignmentCandidate {
        AssignmentCandidate(uid: uid, role: .member, accessLevel: .restricted, displayName: "Restricted")
    }

    // MARK: - 1/2/3/4 Schema + DTO round trip

    @Test("Schema V8 is current; V7 assigneeUID remains additive")
    func schemaV7() {
        #expect(TodoshiSchema.currentVersion == TodoshiSchemaV9.versionIdentifier)
        #expect(TodoshiSchemaV7.versionIdentifier == Schema.Version(7, 0, 0))
        #expect(TodoshiSchemaMigrationPlan.schemas.count == 1)
        #expect(TodoshiSchemaMigrationPlan.stages.isEmpty)
    }

    @Test("Root task assignee survives the SwiftData → DTO → SwiftData round trip")
    func rootAssigneeRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let task = try TaskRepository(context: context).create(in: project, title: "Root")
        task.assigneeUID = "member-b"

        let dto = try #require(FirestoreTaskMapping.dto(from: task))
        #expect(dto.assigneeUID == "member-b")

        let rebuilt = TaskItem(id: task.id, title: "Placeholder", position: 1)
        FirestoreTaskMapping.apply(dto, to: rebuilt)
        #expect(rebuilt.assigneeUID == "member-b")
    }

    @Test("Unassigned tasks map to nil in both directions")
    func unassignedRoundTrip() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let task = try TaskRepository(context: context).create(in: project, title: "Root")

        let dto = try #require(FirestoreTaskMapping.dto(from: task))
        #expect(dto.assigneeUID == nil)

        let existing = TaskItem(id: task.id, title: "X", position: 1, assigneeUID: "stale-uid")
        FirestoreTaskMapping.apply(dto, to: existing)
        #expect(existing.assigneeUID == nil)
    }

    @Test("Subtasks never carry an independent assignee and inherit the root's")
    func subtaskAssignmentInherits() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let root = try repo.create(in: project, title: "Root")
        root.assigneeUID = "member-b"
        let subtask = try repo.createSubtask(parentTaskID: root.id, title: "Child")

        #expect(!TaskAssignmentPolicy.canAssign(task: subtask))
        #expect(TaskAssignmentPolicy.canAssign(task: root))
        #expect(subtask.assigneeUID == nil)
        #expect(subtask.effectiveAssigneeUID == "member-b")

        // Even a client that sets it locally must not publish subtask assignment.
        subtask.assigneeUID = "member-c"
        let dto = try #require(FirestoreTaskMapping.dto(from: subtask))
        #expect(dto.assigneeUID == nil)
    }

    // MARK: - 5/6/7/8 Assignment authority + editor grant

    @Test("Only the owner may assign")
    func onlyOwnerAssigns() {
        #expect(TaskAssignmentPolicy.canAssign(role: .owner))
        #expect(!TaskAssignmentPolicy.canAssign(role: .member))
        #expect(!TaskAssignmentPolicy.canAssign(role: nil))
        #expect(TaskAssignmentPolicy.allowsAssignedCreation(role: .owner))
        #expect(!TaskAssignmentPolicy.allowsAssignedCreation(role: .member))
    }

    @Test("Owner and full-member assignees need no ACL grant")
    func noGrantForOwnerOrFull() {
        #expect(TaskAssignmentPolicy.requiredEditorGrant(assigneeMembership: owner(), currentEditorUIDs: []) == nil)
        #expect(TaskAssignmentPolicy.requiredEditorGrant(assigneeMembership: fullMember(), currentEditorUIDs: []) == nil)

        let ownerPlan = TaskAssignmentPolicy.plan(assignTo: owner(), currentEditorUIDs: [])
        #expect(ownerPlan.assigneeUID == "owner-uid")
        #expect(!ownerPlan.grantsEditAccess)
        #expect(ownerPlan.editorUIDs.isEmpty)

        let fullPlan = TaskAssignmentPolicy.plan(assignTo: fullMember(), currentEditorUIDs: ["x"])
        #expect(!fullPlan.grantsEditAccess)
        #expect(fullPlan.editorUIDs == ["x"])
    }

    @Test("Restricted assignee receives an editor grant in the same plan")
    func restrictedReceivesGrant() {
        let plan = TaskAssignmentPolicy.plan(assignTo: restrictedMember(), currentEditorUIDs: [])
        #expect(plan.assigneeUID == "restricted-uid")
        #expect(plan.grantsEditAccess)
        #expect(plan.editorUIDs == ["restricted-uid"])
    }

    @Test("Restricted assignee already in editorUIDs is not duplicated")
    func restrictedNoDuplicate() {
        let grant = TaskAssignmentPolicy.requiredEditorGrant(
            assigneeMembership: restrictedMember(),
            currentEditorUIDs: ["restricted-uid"]
        )
        #expect(grant == nil)

        let plan = TaskAssignmentPolicy.plan(
            assignTo: restrictedMember(),
            currentEditorUIDs: ["restricted-uid", "other"]
        )
        #expect(!plan.grantsEditAccess)
        #expect(plan.editorUIDs == ["other", "restricted-uid"])
    }

    // MARK: - 9/10 Unassign + reassign preserve ACL

    @Test("Unassignment clears responsibility but never revokes edit access")
    func unassignPreservesEditors() {
        let plan = TaskAssignmentPolicy.plan(assignTo: nil, currentEditorUIDs: ["restricted-uid"])
        #expect(plan.assigneeUID == nil)
        #expect(plan.editorUIDs == ["restricted-uid"])
        #expect(!plan.grantsEditAccess)
    }

    @Test("Reassignment keeps the previous editor and adds the new restricted one")
    func reassignKeepsOldEditor() {
        let newAssignee = AssignmentCandidate(uid: "member-c", role: .member, accessLevel: .restricted)
        let plan = TaskAssignmentPolicy.plan(assignTo: newAssignee, currentEditorUIDs: ["member-b"])
        #expect(plan.assigneeUID == "member-c")
        #expect(plan.editorUIDs == ["member-b", "member-c"])
        #expect(plan.grantsEditAccess)
    }

    @Test("Valid assignees must be current members of the same project")
    func validAssignee() {
        let members = [owner(), restrictedMember()]
        #expect(TaskAssignmentPolicy.isValidAssignee(uid: "restricted-uid", members: members))
        #expect(TaskAssignmentPolicy.isValidAssignee(uid: "owner-uid", members: members))
        #expect(!TaskAssignmentPolicy.isValidAssignee(uid: "stranger", members: members))
        #expect(!TaskAssignmentPolicy.isValidAssignee(uid: "", members: members))
    }

    // MARK: - 11 Recurrence

    @Test("Recurring successor inherits assignee and task ACL")
    func recurrenceInheritsAssignee() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let task = try repo.create(
            in: project,
            title: "Weekly report",
            dueDate: Date(timeIntervalSince1970: 1_800_000_000),
            recurrenceRule: TaskRecurrenceRule(kind: .weekly)
        )
        task.assigneeUID = "member-b"
        task.editorUIDs = ["member-b"]

        try repo.complete(task, at: Date(timeIntervalSince1970: 1_800_003_600))
        let successorID = try #require(task.nextOccurrenceID)
        let successor = try #require(try repo.fetchTask(id: successorID))
        #expect(successor.assigneeUID == "member-b")
        #expect(successor.editorUIDs == ["member-b"])
        #expect(successor.status == .todo)
    }

    // MARK: - 12/18 My Tasks filtering + account isolation

    @Test("My Tasks includes only the current UID's assignments")
    func myTasksFiltering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let mine = try repo.create(in: project, title: "Mine")
        let theirs = try repo.create(in: project, title: "Theirs")
        let unassigned = try repo.create(in: project, title: "Unassigned")
        mine.assigneeUID = "me"
        theirs.assigneeUID = "them"

        let roots = [mine, theirs, unassigned]
        #expect(TaskAssignmentFilter.all.apply(to: roots, viewerUID: "me").count == 3)

        let filtered = TaskAssignmentFilter.mine.apply(to: roots, viewerUID: "me")
        #expect(filtered.map(\.id) == [mine.id])
        #expect(!filtered.contains { $0.id == theirs.id })
    }

    @Test("My Tasks is empty without an authenticated UID and never reuses another account")
    func accountIsolation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let task = try repo.create(in: project, title: "Assigned to previous account")
        task.assigneeUID = "previous-account"

        #expect(TaskAssignmentFilter.mine.apply(to: [task], viewerUID: nil).isEmpty)
        #expect(TaskAssignmentFilter.mine.apply(to: [task], viewerUID: "").isEmpty)
        #expect(TaskAssignmentFilter.mine.apply(to: [task], viewerUID: "new-account").isEmpty)
        #expect(TaskAssignmentFilter.mine.apply(to: [task], viewerUID: "previous-account").count == 1)
    }

    // MARK: - 13/14/15 Member progress

    @Test("Member progress counts assigned root tasks by status")
    func progressCounts() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")

        var roots: [TaskItem] = []
        let plan: [(String, TaskStatus)] = [
            ("A", .todo), ("B", .todo),
            ("C", .inProgress), ("D", .inProgress), ("E", .inProgress),
            ("F", .review),
            ("G", .done), ("H", .done),
        ]
        for (title, status) in plan {
            let task = try repo.create(in: project, title: title)
            task.status = status
            task.assigneeUID = "member-b"
            roots.append(task)
        }
        let other = try repo.create(in: project, title: "Other")
        other.assigneeUID = "member-c"
        roots.append(other)

        let progress = MemberAssignmentProgressPolicy.progress(for: "member-b", in: roots)
        #expect(progress.total == 8)
        #expect(progress.count(for: .todo) == 2)
        #expect(progress.count(for: .inProgress) == 3)
        #expect(progress.count(for: .review) == 1)
        #expect(progress.count(for: .done) == 2)
        #expect(progress.count(for: .backlog) == 0)
    }

    @Test("Soft-deleted assigned tasks drop out of progress and the assigned list")
    func deletedExcludedFromProgress() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let live = try repo.create(in: project, title: "Live")
        let removed = try repo.create(in: project, title: "Removed")
        live.assigneeUID = "member-b"
        removed.assigneeUID = "member-b"
        removed.deletedAt = .now

        let roots = [live, removed]
        #expect(MemberAssignmentProgressPolicy.progress(for: "member-b", in: roots).total == 1)
        #expect(
            MemberAssignmentProgressPolicy.assignedRootTasks(for: "member-b", in: roots).map(\.id) == [live.id]
        )
        // The tombstone keeps its historical assignee.
        #expect(removed.assigneeUID == "member-b")
    }

    @Test("Completed tasks stay assigned and stay visible in the member's history")
    func doneRemainsAssigned() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let task = try repo.create(in: project, title: "Finish report")
        task.assigneeUID = "member-b"

        try repo.complete(task, at: .now)
        #expect(task.status == .done)
        #expect(task.assigneeUID == "member-b")

        let assigned = MemberAssignmentProgressPolicy.assignedRootTasks(for: "member-b", in: [task])
        #expect(assigned.count == 1)
        #expect(MemberAssignmentProgressPolicy.progress(for: "member-b", in: [task]).count(for: .done) == 1)
    }

    // MARK: - 16/17 Integrity guards

    @Test("Owner cannot strip edit access from the current restricted assignee")
    func aclRemovalGuard() {
        #expect(
            !TaskAssignmentIntegrityPolicy.canRemoveEditor(
                uid: "restricted-uid",
                assigneeUID: "restricted-uid",
                candidate: restrictedMember()
            )
        )
        // Not the assignee → removal is fine.
        #expect(
            TaskAssignmentIntegrityPolicy.canRemoveEditor(
                uid: "restricted-uid",
                assigneeUID: "someone-else",
                candidate: restrictedMember()
            )
        )
        // Full members and owners do not depend on editorUIDs.
        #expect(
            TaskAssignmentIntegrityPolicy.canRemoveEditor(
                uid: "full-uid",
                assigneeUID: "full-uid",
                candidate: fullMember()
            )
        )
        #expect(
            TaskAssignmentIntegrityPolicy.canRemoveEditor(
                uid: "restricted-uid",
                assigneeUID: nil,
                candidate: restrictedMember()
            )
        )
    }

    @Test("full → restricted repairs assigned tasks idempotently")
    func demotionRepair() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")

        let needsRepair = try repo.create(in: project, title: "Needs repair")
        needsRepair.assigneeUID = "member-b"

        let alreadyGranted = try repo.create(in: project, title: "Already granted")
        alreadyGranted.assigneeUID = "member-b"
        alreadyGranted.editorUIDs = ["member-b"]

        let notAssigned = try repo.create(in: project, title: "Not assigned")

        let deletedAssigned = try repo.create(in: project, title: "Deleted")
        deletedAssigned.assigneeUID = "member-b"
        deletedAssigned.deletedAt = .now

        let roots = [needsRepair, alreadyGranted, notAssigned, deletedAssigned]
        let pending = TaskAssignmentIntegrityPolicy.rootTasksNeedingRepair(
            forDemotedUID: "member-b",
            rootTasks: roots
        )
        #expect(pending.map(\.id) == [needsRepair.id])

        for task in pending {
            task.editorUIDs = TaskAssignmentIntegrityPolicy.repairedEditorUIDs(for: task, uid: "member-b")
        }
        #expect(needsRepair.editorUIDs == ["member-b"])

        // Running it again is a no-op.
        #expect(
            TaskAssignmentIntegrityPolicy
                .rootTasksNeedingRepair(forDemotedUID: "member-b", rootTasks: roots)
                .isEmpty
        )
    }

    // MARK: - Presentation

    @Test("Assignment presentation resolves membership names without exposing UIDs")
    func presentation() {
        let members = [owner(), restrictedMember(), AssignmentCandidate(uid: "blank", role: .member)]
        #expect(TaskAssignmentPresentation.assigneeName(for: nil, members: members)
            == TaskAssignmentPresentation.unassigned)
        #expect(TaskAssignmentPresentation.assigneeName(for: "restricted-uid", members: members) == "Restricted")
        #expect(TaskAssignmentPresentation.assigneeName(for: "stranger", members: members)
            == TaskAssignmentPresentation.unassigned)
        #expect(TaskAssignmentPresentation.assigneeName(for: "blank", members: members)
            == TodoshiL10n.tr("project.members.unnamed"))

        #expect(TaskAssignmentFilter.all.title == TaskAssignmentPresentation.allTasks)
        #expect(TaskAssignmentFilter.mine.title == TaskAssignmentPresentation.myTasks)
        #expect(!TaskAssignmentPresentation.autoGrantFooter.isEmpty)
        #expect(!TaskAssignmentPresentation.assigneeAclGuard.isEmpty)
    }

    @Test("Owner gets the assignment editor; members see it read-only")
    func assignmentControlVisibility() {
        #expect(TaskAssignmentPolicy.canAssign(role: .owner))
        #expect(!TaskAssignmentPolicy.canAssign(role: .member))
        // Read-only presentation still resolves a name for every viewer.
        let members = [owner(), fullMember(), restrictedMember()]
        #expect(TaskAssignmentPresentation.assigneeName(for: "full-uid", members: members) == "Full")
    }

    @Test("Assignee picker offers every current membership plus Unassigned")
    func pickerCandidates() {
        let members = [owner(), fullMember(), restrictedMember()]
        for member in members {
            #expect(TaskAssignmentPolicy.isValidAssignee(uid: member.uid, members: members))
        }
        #expect(TaskAssignmentPolicy.plan(assignTo: nil, currentEditorUIDs: []).assigneeUID == nil)
    }

    @Test("Restricted member becomes an authorized editor through the assignment grant")
    func restrictedBecomesEditableAfterAssignment() {
        let candidate = restrictedMember()
        #expect(
            !SharedTaskEditAuthorization.canEditTaskContent(
                role: candidate.role,
                accessLevel: candidate.resolvedAccessLevel,
                viewerUID: candidate.uid,
                rootEditorUIDs: []
            )
        )
        let plan = TaskAssignmentPolicy.plan(assignTo: candidate, currentEditorUIDs: [])
        #expect(
            SharedTaskEditAuthorization.canEditTaskContent(
                role: candidate.role,
                accessLevel: candidate.resolvedAccessLevel,
                viewerUID: candidate.uid,
                rootEditorUIDs: plan.editorUIDs
            )
        )
    }

    @Test("Board mapping projects assignee names and honours the responsibility filter")
    func boardMapping() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let repo = TaskRepository(context: context)
        let project = try ProjectRepository(context: context).create(name: "Shared")
        let mine = try repo.create(in: project, title: "Mine", status: .inProgress)
        let theirs = try repo.create(in: project, title: "Theirs", status: .inProgress)
        mine.assigneeUID = "me"
        theirs.assigneeUID = "them"

        let names = ["me": "Anas", "them": "Jameel"]
        let all = ProjectBoardMapping.snapshot(from: project, assigneeNames: names, viewerUID: "me")
        let allInProgress = try #require(all.sections.first { $0.status == .inProgress })
        #expect(allInProgress.tasks.count == 2)
        #expect(allInProgress.tasks.first { $0.id == mine.id }?.assigneeDisplayName == "Anas")
        #expect(allInProgress.tasks.first { $0.id == theirs.id }?.assigneeDisplayName == "Jameel")

        let onlyMine = ProjectBoardMapping.snapshot(
            from: project,
            assigneeNames: names,
            filter: .mine,
            viewerUID: "me"
        )
        let mineInProgress = try #require(onlyMine.sections.first { $0.status == .inProgress })
        #expect(mineInProgress.tasks.map(\.id) == [mine.id])

        // Personal projects get no assignment presentation.
        let personal = ProjectBoardMapping.snapshot(from: project)
        let personalInProgress = try #require(personal.sections.first { $0.status == .inProgress })
        #expect(personalInProgress.tasks.allSatisfy { $0.assigneeDisplayName == nil })
    }
}
