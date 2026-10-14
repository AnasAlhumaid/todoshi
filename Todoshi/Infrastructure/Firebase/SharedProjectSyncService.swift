import Foundation
import SwiftData
import FirebaseAuth
import FirebaseFirestore
import TodoshiCore

/// App-level shared-project sync: discovery, owner seed, listeners, write-through, reconcile.
@MainActor
final class SharedProjectSyncService {
    static let shared = SharedProjectSyncService()

    private let db: Firestore
    private var modelContext: ModelContext?
    private var currentUID: String?
    private var projectListeners: [UUID: [ListenerRegistration]] = [:]
    private var isRunning = false
    private var seedingProjects: Set<UUID> = []
    /// Desired parent links from remote snapshots (child → parent). Survives out-of-order delivery.
    private var desiredParentIDByChild: [UUID: UUID] = [:]

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool { FirebaseBootstrap.isConfigured }

    func bind(modelContext: ModelContext) {
        self.modelContext = modelContext
        SharedProjectMutationHook.handler = { [weak self] event in
            Task { @MainActor in
                self?.handleMutation(event)
            }
        }
    }

    func start(forUID uid: String) async {
        guard isConfigured else { return }
        guard !uid.isEmpty else { return }
        currentUID = uid
        isRunning = true
        #if DEBUG
        TodoshiDiagnostics.note("[Sync] started session")
        #endif
        await discoverAndSyncAll()
    }

    func stop() {
        isRunning = false
        currentUID = nil
        for (_, regs) in projectListeners {
            regs.forEach { $0.remove() }
        }
        projectListeners.removeAll()
        seedingProjects.removeAll()
        desiredParentIDByChild.removeAll()
        childListeners.values.forEach { $0.remove() }
        childListeners.removeAll()
        #if DEBUG
        TodoshiDiagnostics.note("[Sync] stopped")
        #endif
    }

    func isContentSeeding(projectID: UUID) -> Bool {
        seedingProjects.contains(projectID)
    }

    // MARK: - Discovery

    private func discoverAndSyncAll() async {
        guard let uid = currentUID, let context = modelContext else { return }
        do {
            let ids = try await ProjectInviteService.shared.discoverJoinedProjectIDs(uid: uid)
            for remoteID in ids {
                guard let projectID = UUID(uuidString: remoteID) else { continue }
                await ensureLocalShellAndListen(projectID: projectID, uid: uid, context: context)
            }
            await repairMembershipDisplayNamesIfNeeded(uid: uid)
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] discovery failed")
            #endif
        }
    }

    private func repairMembershipDisplayNamesIfNeeded(uid: String) async {
        guard let profile = try? await FirestoreUserProfileService.shared.loadProfile(uid: uid),
              let name = profile.displayName
        else { return }
        await MembershipDisplayNameSyncService.shared.repairStaleMembershipsIfNeeded(
            uid: uid,
            profileDisplayName: name
        )
    }

    private func ensureLocalShellAndListen(projectID: UUID, uid: String, context: ModelContext) async {
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        do {
            let snap = try await db.collection("projects").document(remoteID).getDocument()
            guard snap.exists, let data = snap.data() else { return }
            let title = (data["title"] as? String) ?? "Shared"
            let description = (data["description"] as? String) ?? ""
            let color = ProjectColorCatalog.sanitized((data["color"] as? String) ?? ProjectColorCatalog.defaultHex)
            let ownerId = data["ownerId"] as? String
            let seededAt = (data["contentSeededAt"] as? Timestamp)?.dateValue()
            let schemaVersion = data["contentSchemaVersion"] as? Int

            let shell = JoinedSharedProjectShellPolicy.make(
                projectID: projectID,
                title: title,
                description: description,
                color: color,
                projectType: ProjectType.resolve(data["projectType"] as? String)
            )
            let project = try ProjectRepository(context: context).upsertJoinedSharedProjectShell(
                shell,
                collaborationOwnerUID: uid
            )
            project.syncUnavailable = false

            if ownerId == uid,
               SharedProjectSeedPolicy.needsOwnerSeed(
                isOwner: true,
                contentSeededAt: seededAt,
                contentSchemaVersion: schemaVersion
               ) || SharedProjectSeedPolicy.needsOwnerContentRepair(
                isOwner: true,
                contentSeededAt: seededAt,
                contentSchemaVersion: schemaVersion
               ) {
                await seedOwnerContentIfNeeded(project: project, context: context)
            }

            attachListeners(projectID: projectID)
        } catch {
            handlePermissionLossIfNeeded(error, projectID: projectID, context: context)
        }
    }

    // MARK: - Listeners

    private func attachListeners(projectID: UUID) {
        guard projectListeners[projectID] == nil else { return }
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        var regs: [ListenerRegistration] = []

        let projectReg = db.collection("projects").document(remoteID)
            .addSnapshotListener { [weak self] snap, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.handlePermissionLossIfNeeded(error, projectID: projectID, context: self.modelContext)
                        return
                    }
                    guard let data = snap?.data() else { return }
                    self.applyRemoteProject(projectID: projectID, data: data)
                }
            }
        regs.append(projectReg)

        let tasksReg = db.collection("projects").document(remoteID).collection("tasks")
            .addSnapshotListener { [weak self] snap, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.handlePermissionLossIfNeeded(error, projectID: projectID, context: self.modelContext)
                        return
                    }
                    guard let snap else { return }
                    var didMutate = false
                    for change in snap.documentChanges {
                        if self.applyRemoteTaskChange(projectID: projectID, change: change) {
                            didMutate = true
                        }
                    }
                    if self.resolvePendingParentLinks(projectID: projectID) {
                        didMutate = true
                    }
                    if didMutate {
                        try? self.modelContext?.save()
                        TodoshiDataChangeCenter.post(.taskContentChanged)
                    }
                }
            }
        regs.append(tasksReg)

        let labelsReg = db.collection("projects").document(remoteID).collection("labels")
            .addSnapshotListener { [weak self] snap, error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.handlePermissionLossIfNeeded(error, projectID: projectID, context: self.modelContext)
                        return
                    }
                    guard let snap else { return }
                    for change in snap.documentChanges {
                        self.applyRemoteLabelChange(projectID: projectID, change: change)
                    }
                }
            }
        regs.append(labelsReg)

        // Board columns live in their own collection so existing project rules stay untouched.
        let boardRef = db.collection("projectBoards").document(remoteID)
        let boardReg = boardRef.addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                // A missing board or read failure just means "default columns"; never evict here.
                guard let self, let snap else { return }
                self.applyRemoteBoard(projectID: projectID, data: snap.exists ? snap.data() : nil)
            }
        }
        regs.append(boardReg)

        let placementsReg = boardRef.collection("placements").addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self, let snap else { return }
                self.applyRemotePlacements(projectID: projectID, changes: snap.documentChanges)
            }
        }
        regs.append(placementsReg)

        projectListeners[projectID] = regs
        #if DEBUG
        TodoshiDiagnostics.note("[Sync] started project \(projectID.uuidString.prefix(8))")
        #endif
    }

    private func detachListeners(projectID: UUID) {
        projectListeners[projectID]?.forEach { $0.remove() }
        projectListeners[projectID] = nil
    }

    // MARK: - Seed

    private func seedOwnerContentIfNeeded(project: Project, context: ModelContext) async {
        guard !seedingProjects.contains(project.id) else { return }
        seedingProjects.insert(project.id)
        defer { seedingProjects.remove(project.id) }

        #if DEBUG
        TodoshiDiagnostics.note("[Sync] initial seed \(project.id.uuidString.prefix(8))")
        #endif

        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: project.id)
        // Include roots AND subtasks — never filter to parentTask == nil.
        let tasks = SharedProjectSeedPolicy.tasksForCloudUpload(from: project.tasks ?? [])
        let labels = Set(tasks.flatMap { $0.labels ?? [] })

        do {
            // Labels first
            try await writeInChunks(labels.map { label in
                (db.collection("projects").document(remoteID).collection("labels").document(label.id.uuidString),
                 labelFirestoreData(label))
            })

            for task in tasks {
                try await upsertTaskTree(task: task, remoteID: remoteID)
            }

            // Best-effort: board columns must not block the core content seed.
            await pushBoard(project: project)
            for task in tasks where task.isRoot && task.columnIDRaw != nil {
                await pushPlacement(task: task, remoteID: remoteID)
            }

            try await db.collection("projects").document(remoteID).updateData([
                "contentSchemaVersion": SharedProjectContentSchema.currentVersion,
                "contentSeededAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
            ])
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] seed/repair complete \(project.id.uuidString.prefix(8)) tasks=\(tasks.count)")
            #endif
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] seed failed")
            #endif
        }
    }

    private func upsertTaskTree(
        task: TaskItem,
        remoteID: String,
        activityKind: TaskCollaborationActivityKind? = nil,
        actorUID: String? = nil
    ) async throws {
        let taskRef = db.collection("projects").document(remoteID).collection("tasks").document(task.id.uuidString)
        try await taskRef.setData(
            taskFirestoreData(task, activityKind: activityKind, actorUID: actorUID),
            merge: true
        )

        // Children are best-effort: a checklist/resource rule failure must not hide a successful task write.
        let checklist = task.checklist ?? []
        do {
            try await writeInChunks(checklist.map { item in
                (taskRef.collection("checklist").document(item.id.uuidString), checklistFirestoreData(item))
            })
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] checklist write failed: \(firestoreFailureLabel(error))")
            #endif
        }

        let resources = (task.resources ?? []).filter {
            SharedTaskResourceSyncPolicy.isCloudSyncable($0.kind)
        }
        do {
            try await writeInChunks(resources.map { resource in
                (taskRef.collection("resources").document(resource.id.uuidString), resourceFirestoreData(resource))
            })
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] resource write failed: \(firestoreFailureLabel(error))")
            #endif
        }
    }

    private func writeInChunks(_ pairs: [(DocumentReference, [String: Any])]) async throws {
        let chunkSize = SharedProjectSeedPolicy.maxWritesPerBatch
        var index = 0
        while index < pairs.count {
            let end = min(index + chunkSize, pairs.count)
            let slice = pairs[index..<end]
            let batch = db.batch()
            for (ref, data) in slice {
                batch.setData(data, forDocument: ref, merge: true)
            }
            try await batch.commit()
            index = end
        }
    }

    // MARK: - Outbound mutations

    private func handleMutation(_ event: SharedProjectMutationHook.Event) {
        guard isRunning, let uid = currentUID else { return }
        guard SharedProjectAccountIsolationPolicy.canMutateShared(
            sharingMode: .shared,
            currentUID: uid
        ) else { return }

        switch event {
        case .projectMetadata(let projectID):
            Task { await pushProjectMetadata(projectID) }
        case .taskUpsert(let projectID, let taskID):
            Task { await pushTask(projectID: projectID, taskID: taskID, activityKind: .taskUpdated) }
        case .taskSoftDelete(let projectID, let taskID):
            Task { await pushTask(projectID: projectID, taskID: taskID, activityKind: .taskUpdated) }
        case .checklistChanged(let projectID, let taskID):
            Task { await pushTask(projectID: projectID, taskID: taskID, activityKind: .checklistChanged) }
        case .labelsChanged(let projectID):
            Task { await pushLabels(projectID: projectID) }
        case .resourceChanged(let projectID, let taskID):
            Task { await pushTask(projectID: projectID, taskID: taskID, activityKind: .resourceChanged) }
        case .projectDeleted:
            break
        case .boardColumns(let projectID):
            Task {
                guard let context = modelContext,
                      let project = try? ProjectRepository(context: context).fetchProject(id: projectID),
                      project.isShared else { return }
                await pushBoard(project: project)
            }
        case .taskColumn(let projectID, let taskID):
            Task {
                guard let context = modelContext,
                      let task = try? TaskRepository(context: context).fetchTask(id: taskID),
                      task.project?.id == projectID else { return }
                await pushPlacement(task: task, remoteID: SharedProjectRemoteIDPolicy.documentID(for: projectID))
            }
        }
    }

    // MARK: - Board columns (/projectBoards)

    /// Owner-only write; members get permission-denied, which is expected and ignored.
    private func pushBoard(project: Project) async {
        guard let uid = currentUID,
              let json = project.columnsJSON,
              let columns = ProjectColumnsPolicy.decode(json) else { return }
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: project.id)
        let data: [String: Any] = [
            "projectId": remoteID,
            "columns": columns.map { column in
                [
                    "id": column.id.uuidString,
                    "name": column.name,
                    "colorHex": column.colorHex,
                    "kind": column.kind.rawValue,
                ]
            },
            "updatedAt": FieldValue.serverTimestamp(),
            "updatedBy": uid,
        ]
        do {
            try await db.collection("projectBoards").document(remoteID).setData(data)
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] board write failed: \(firestoreFailureLabel(error))")
            #endif
        }
    }

    private func pushPlacement(task: TaskItem, remoteID: String) async {
        guard let uid = currentUID, task.isRoot, let columnID = task.columnIDRaw else { return }
        do {
            try await db.collection("projectBoards").document(remoteID)
                .collection("placements").document(task.id.uuidString)
                .setData([
                    "taskId": task.id.uuidString,
                    "columnId": columnID,
                    "updatedAt": FieldValue.serverTimestamp(),
                    "updatedBy": uid,
                ])
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] placement write failed: \(firestoreFailureLabel(error))")
            #endif
        }
    }

    private func applyRemoteBoard(projectID: UUID, data: [String: Any]?) {
        guard let context = modelContext,
              let project = try? ProjectRepository(context: context).fetchProject(id: projectID)
        else { return }
        guard let raw = data?["columns"] as? [[String: Any]] else {
            // No remote board yet: keep any local columns (the owner pushes them on next edit/seed).
            return
        }
        let columns: [ProjectColumn] = raw.compactMap { entry in
            guard let idRaw = entry["id"] as? String, let id = UUID(uuidString: idRaw),
                  let name = entry["name"] as? String,
                  let kind = ProjectColumnKind(rawValue: entry["kind"] as? String ?? "") else { return nil }
            let color = ProjectColorCatalog.sanitized(entry["colorHex"] as? String ?? ProjectColorCatalog.defaultHex)
            return ProjectColumn(id: id, name: name, colorHex: color, kind: kind)
        }
        guard (try? ProjectColumnsPolicy.validate(columns)) != nil,
              let json = ProjectColumnsPolicy.encode(columns),
              json != project.columnsJSON else { return }
        project.columnsJSON = json
        try? context.save()
        TodoshiDataChangeCenter.post(.projectStructureChanged)
    }

    private func applyRemotePlacements(projectID: UUID, changes: [DocumentChange]) {
        guard let context = modelContext else { return }
        let repo = TaskRepository(context: context)
        var didMutate = false
        for change in changes {
            guard let taskID = UUID(uuidString: change.document.documentID),
                  let task = try? repo.fetchTask(id: taskID),
                  task.project?.id == projectID else { continue }
            let columnID = change.type == .removed ? nil : change.document.data()["columnId"] as? String
            if task.columnIDRaw != columnID {
                task.columnIDRaw = columnID
                didMutate = true
            }
        }
        if didMutate {
            try? context.save()
            TodoshiDataChangeCenter.post(.taskContentChanged)
        }
    }

    private func pushProjectMetadata(_ projectID: UUID) async {
        guard let context = modelContext,
              let project = try? ProjectRepository(context: context).fetchProject(id: projectID),
              project.isShared,
              let uid = currentUID
        else { return }
        // Only owner updates remote project metadata.
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        do {
            let snap = try await db.collection("projects").document(remoteID).getDocument()
            guard (snap.data()?["ownerId"] as? String) == uid else { return }
            try await db.collection("projects").document(remoteID).updateData([
                "title": project.name,
                "description": project.projectDescription,
                "color": project.colorHex,
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] write pending/failed project metadata")
            #endif
        }
    }

    private func pushTask(
        projectID: UUID,
        taskID: UUID,
        activityKind: TaskCollaborationActivityKind = .taskUpdated
    ) async {
        guard let context = modelContext,
              let task = try? TaskRepository(context: context).fetchTask(id: taskID),
              task.project?.id == projectID,
              task.project?.isShared == true,
              let uid = currentUID
        else { return }
        ensureListening(projectID: projectID)
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let resolvedKind = resolvedActivityKind(for: task, requested: activityKind)
        do {
            if task.isRoot {
                try await upsertTaskTree(
                    task: task,
                    remoteID: remoteID,
                    activityKind: resolvedKind,
                    actorUID: uid
                )
                applyLocalActivity(task: task, actorUID: uid, kind: resolvedKind, at: .now)
                try? context.save()
                if task.columnIDRaw != nil {
                    await pushPlacement(task: task, remoteID: remoteID)
                }
            } else {
                try await upsertTaskTree(task: task, remoteID: remoteID)
                try await bumpRootActivity(
                    projectID: projectID,
                    rootTaskID: TaskCollaborationActivityPolicy.rootTaskID(for: task),
                    remoteID: remoteID,
                    actorUID: uid,
                    kind: .subtaskChanged
                )
            }
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] write succeeded task \(taskID.uuidString.prefix(8))")
            #endif
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] task update failed: \(firestoreFailureLabel(error))")
            #endif
            if isPermissionDenied(error) {
                await reconcileTaskAfterPermissionDenied(projectID: projectID, taskID: taskID, remoteID: remoteID)
            }
        }
    }

    private func pushTaskSoftDelete(projectID: UUID, taskID: UUID) async {
        ensureListening(projectID: projectID)
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        do {
            try await db.collection("projects").document(remoteID)
                .collection("tasks").document(taskID.uuidString)
                .setData([
                    "deletedAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp(),
                ], merge: true)
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] soft-delete write failed: \(firestoreFailureLabel(error))")
            #endif
            if isPermissionDenied(error) {
                await reconcileTaskAfterPermissionDenied(projectID: projectID, taskID: taskID, remoteID: remoteID)
            }
        }
    }

    private func isPermissionDenied(_ error: Error) -> Bool {
        let ns = error as NSError
        return ns.domain == FirestoreErrorDomain
            && ns.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    /// Firestore remains authority: undo unauthorized optimistic local edits and notify UI.
    private func reconcileTaskAfterPermissionDenied(projectID: UUID, taskID: UUID, remoteID: String) async {
        do {
            let snap = try await db.collection("projects").document(remoteID)
                .collection("tasks").document(taskID.uuidString)
                .getDocument()
            await MainActor.run {
                guard let context = modelContext else { return }
                if snap.exists, let data = snap.data() {
                    let dto = mapTaskDTO(projectID: projectID, taskID: taskID, data: data)
                    if let existing = try? TaskRepository(context: context).fetchTask(id: taskID) {
                        FirestoreTaskMapping.apply(dto, to: existing)
                        applyLabelIDs(dto.labelIds, to: existing, context: context)
                        try? context.save()
                        TodoshiDataChangeCenter.post(.taskContentChanged)
                    }
                }
                SharedTaskPermissionDeniedCenter.post(projectID: projectID, taskID: taskID)
            }
        } catch {
            await MainActor.run {
                SharedTaskPermissionDeniedCenter.post(projectID: projectID, taskID: taskID)
            }
        }
    }

    private func pushLabels(projectID: UUID) async {
        guard let context = modelContext,
              let project = try? ProjectRepository(context: context).fetchProject(id: projectID),
              project.isShared
        else { return }
        ensureListening(projectID: projectID)
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let labels = Set((project.tasks ?? []).flatMap { $0.labels ?? [] })
        do {
            try await writeInChunks(labels.map { label in
                (db.collection("projects").document(remoteID).collection("labels").document(label.id.uuidString),
                 labelFirestoreData(label))
            })
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] labels write failed: \(firestoreFailureLabel(error))")
            #endif
        }
    }

    private func firestoreFailureLabel(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == FirestoreErrorDomain,
           ns.code == FirestoreErrorCode.permissionDenied.rawValue {
            return "permission-denied"
        }
        if ns.domain == FirestoreErrorDomain {
            return "firestore-\(ns.code)"
        }
        return "write-failed"
    }

    /// Re-attach project listeners after permission-loss detach or process resume.
    func resumeListeningIfNeeded() async {
        guard isRunning, currentUID != nil else { return }
        await discoverAndSyncAll()
    }

    /// Phase 9A — purge local shared cache after voluntary leave or confirmed access loss.
    func evictSharedProjectAfterDeparture(projectID: UUID, voluntary: Bool) async {
        detachListeners(projectID: projectID)
        guard SharedProjectMemberEvictionPolicy.removesLocalSharedCache,
              let context = modelContext,
              let project = try? ProjectRepository(context: context).fetchProject(id: projectID),
              project.isShared
        else { return }

        do {
            try ProjectRepository(context: context).delete(project)
        } catch {
            #if DEBUG
            TodoshiDiagnostics.note("[Sync] local eviction failed")
            #endif
            return
        }

        let message = TodoshiL10n.tr("project.members.accessLost")
        SharedProjectAccessLossCenter.post(
            projectID: projectID,
            message: message,
            voluntary: voluntary
        )
        TodoshiDataChangeCenter.post(.projectListChanged)
    }

    func confirmMembershipAndEvictIfNeeded(projectID: UUID) async {
        guard let uid = currentUID, isConfigured else { return }
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        do {
            let snap = try await db
                .collection("projects")
                .document(remoteID)
                .collection("members")
                .document(uid)
                .getDocument()
            if !snap.exists {
                await evictSharedProjectAfterDeparture(projectID: projectID, voluntary: false)
            }
        } catch {
            let ns = error as NSError
            if ns.domain == FirestoreErrorDomain,
               ns.code == FirestoreErrorCode.permissionDenied.rawValue {
                await evictSharedProjectAfterDeparture(projectID: projectID, voluntary: false)
            }
        }
    }

    private func ensureListening(projectID: UUID) {
        if projectListeners[projectID] == nil {
            attachListeners(projectID: projectID)
        }
    }

    // MARK: - Inbound reconcile

    private func applyRemoteProject(projectID: UUID, data: [String: Any]) {
        guard let context = modelContext,
              let project = try? ProjectRepository(context: context).fetchProject(id: projectID)
        else { return }
        if let title = data["title"] as? String, !title.isEmpty {
            project.name = title
        }
        if let description = data["description"] as? String {
            project.projectDescription = description
        }
        if let color = data["color"] as? String {
            project.colorHex = ProjectColorCatalog.sanitized(color)
        }
        // Legacy missing remote type → tasks only when local type is still unset.
        // Never overwrite an explicit local Checklist with an absent remote field.
        if let remoteTypeRaw = data["projectType"] as? String {
            let remoteType = ProjectType.resolve(remoteTypeRaw)
            if project.projectTypeRaw == nil || project.projectType == remoteType {
                project.projectType = remoteType
            }
        } else if project.projectTypeRaw == nil {
            project.projectType = .tasks
        }
        project.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? project.updatedAt
        try? context.save()
        TodoshiDataChangeCenter.post(.projectStructureChanged)
    }

    @discardableResult
    private func applyRemoteTaskChange(projectID: UUID, change: DocumentChange) -> Bool {
        guard let context = modelContext else { return false }
        let data = change.document.data()
        guard let taskID = UUID(uuidString: change.document.documentID) else { return false }

        let deletedAt = (data["deletedAt"] as? Timestamp)?.dateValue()
        let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()

        if change.type == .removed || deletedAt != nil {
            desiredParentIDByChild.removeValue(forKey: taskID)
            if let existing = try? TaskRepository(context: context).fetchTask(id: taskID) {
                if SharedProjectConflictPolicy.shouldApplyRemoteSoftDelete(
                    remoteDeletedAt: deletedAt ?? .now,
                    localExists: true
                ) {
                    context.delete(existing)
                    TodoshiDataChangeCenter.post(.taskDeleted)
                    return true
                }
            }
            return false
        }

        guard let project = try? ProjectRepository(context: context).fetchProject(id: projectID) else { return false }
        let dto = mapTaskDTO(projectID: projectID, taskID: taskID, data: data)
        let knownIDs = knownLocalTaskIDs(in: project)
        let link = SharedProjectHierarchyReconcilePolicy.parentLink(
            parentTaskId: dto.parentTaskId,
            knownLocalTaskIDs: knownIDs
        )

        if let existing = try? TaskRepository(context: context).fetchTask(id: taskID) {
            let winner = SharedProjectConflictPolicy.winner(
                localRemoteUpdatedAt: existing.remoteUpdatedAt,
                incomingRemoteUpdatedAt: remoteUpdatedAt
            )
            if winner == .local { return false }
            FirestoreTaskMapping.apply(dto, to: existing)
            existing.project = project
            applyParentLink(link, to: existing, context: context)
            applyLabelIDs(dto.labelIds, to: existing, context: context)
        } else {
            let task = TaskItem(
                id: taskID,
                title: dto.title,
                taskDescription: dto.description,
                status: TaskStatus(rawValue: dto.statusRaw) ?? .todo,
                priority: TaskPriority(rawValue: dto.priorityRaw) ?? .none,
                dueDate: dto.dueDate,
                reminderDate: dto.reminderDate,
                notes: dto.notes,
                position: dto.position,
                completedAt: dto.completedAt,
                completedByUID: dto.completedByUID,
                completedByDisplayName: dto.completedByDisplayName,
                createdAt: dto.createdAt,
                updatedAt: dto.updatedAt,
                deletedAt: dto.deletedAt,
                remoteUpdatedAt: dto.authoritativeRemoteUpdatedAt,
                editorUIDs: dto.parentTaskId == nil ? dto.editorUIDs : nil,
                assigneeUID: dto.assigneeUID,
                project: project,
                recurrenceRuleRaw: dto.recurrenceRuleRaw,
                recurrenceInterval: dto.recurrenceInterval,
                recurrenceSeriesID: dto.recurrenceSeriesID,
                recurrenceGeneration: dto.recurrenceGeneration,
                nextOccurrenceID: dto.nextOccurrenceID,
                previousOccurrenceID: dto.previousOccurrenceID
            )
            applyParentLink(link, to: task, context: context)
            context.insert(task)
            applyLabelIDs(dto.labelIds, to: task, context: context)
        }

        if let pending = link.pendingParentID {
            desiredParentIDByChild[taskID] = pending
        } else {
            desiredParentIDByChild.removeValue(forKey: taskID)
        }

        listenTaskChildren(projectID: projectID, taskID: taskID)

        #if DEBUG
        TodoshiDiagnostics.note("[Sync] applied remote change task \(taskID.uuidString.prefix(8)) parent=\(dto.parentTaskId?.uuidString.prefix(8) ?? "nil")")
        #endif
        return true
    }

    private func applyParentLink(
        _ link: SharedProjectHierarchyReconcilePolicy.ParentLinkResult,
        to task: TaskItem,
        context: ModelContext
    ) {
        if let parentID = link.attachParentID {
            task.parentTask = try? TaskRepository(context: context).fetchTask(id: parentID)
        } else if link.pendingParentID == nil {
            task.parentTask = nil
        }
        // When pending, keep any existing parentTask relationship; UUID is remembered in desiredParentIDByChild.
    }

    private func knownLocalTaskIDs(in project: Project) -> Set<UUID> {
        Set((project.tasks ?? []).compactMap { $0.deletedAt == nil ? $0.id : nil })
    }

    @discardableResult
    private func resolvePendingParentLinks(projectID: UUID) -> Bool {
        guard let context = modelContext,
              let project = try? ProjectRepository(context: context).fetchProject(id: projectID) else { return false }
        let known = knownLocalTaskIDs(in: project)
        let outcome = SharedProjectHierarchyReconcilePolicy.resolvePending(
            pendingByChild: desiredParentIDByChild,
            knownLocalTaskIDs: known
        )
        desiredParentIDByChild = outcome.stillPending
        guard !outcome.resolved.isEmpty else { return false }
        let repo = TaskRepository(context: context)
        for (childID, parentID) in outcome.resolved {
            guard let child = try? repo.fetchTask(id: childID),
                  let parent = try? repo.fetchTask(id: parentID) else { continue }
            child.parentTask = parent
            child.project = project
        }
        return true
    }

    private var childListeners: [String: ListenerRegistration] = [:]

    private func listenTaskChildren(projectID: UUID, taskID: UUID) {
        let key = "\(projectID.uuidString)/\(taskID.uuidString)"
        guard childListeners[key] == nil else { return }
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let taskRef = db.collection("projects").document(remoteID).collection("tasks").document(taskID.uuidString)

        let checklistReg = taskRef.collection("checklist").addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self, let snap else { return }
                self.applyRemoteChecklist(projectID: projectID, taskID: taskID, snapshot: snap)
            }
        }
        let resourcesReg = taskRef.collection("resources").addSnapshotListener { [weak self] snap, _ in
            Task { @MainActor in
                guard let self, let snap else { return }
                self.applyRemoteResources(projectID: projectID, taskID: taskID, snapshot: snap)
            }
        }
        // Track under projectListeners for cleanup by appending conceptually via childListeners map.
        childListeners[key + "/c"] = checklistReg
        childListeners[key + "/r"] = resourcesReg
        if var regs = projectListeners[projectID] {
            regs.append(checklistReg)
            regs.append(resourcesReg)
            projectListeners[projectID] = regs
        }
    }

    private func applyRemoteChecklist(projectID: UUID, taskID: UUID, snapshot: QuerySnapshot) {
        guard let context = modelContext,
              let task = try? TaskRepository(context: context).fetchTask(id: taskID)
        else { return }
        var keep = Set<UUID>()
        for doc in snapshot.documents {
            let data = doc.data()
            guard let id = UUID(uuidString: doc.documentID) else { continue }
            if data["deletedAt"] != nil { continue }
            keep.insert(id)
            let title = data["title"] as? String ?? ""
            let isCompleted = data["isCompleted"] as? Bool ?? false
            let position = data["position"] as? Double ?? FractionalPosition.initial()
            let updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now
            if let existing = (task.checklist ?? []).first(where: { $0.id == id }) {
                existing.title = title
                existing.isCompleted = isCompleted
                existing.position = position
                existing.updatedAt = updatedAt
            } else {
                let item = ChecklistItem(
                    id: id,
                    title: title,
                    isCompleted: isCompleted,
                    position: position,
                    updatedAt: updatedAt,
                    task: task
                )
                context.insert(item)
            }
        }
        for item in (task.checklist ?? []) where !keep.contains(item.id) {
            context.delete(item)
        }
        try? context.save()
        TodoshiDataChangeCenter.post(.taskContentChanged)
    }

    private func applyRemoteResources(projectID: UUID, taskID: UUID, snapshot: QuerySnapshot) {
        guard let context = modelContext,
              let task = try? TaskRepository(context: context).fetchTask(id: taskID)
        else { return }
        var keep = Set<UUID>()
        for doc in snapshot.documents {
            let data = doc.data()
            guard let id = UUID(uuidString: doc.documentID),
                  let kindRaw = data["kindRaw"] as? String,
                  let kind = TaskResourceKind.parse(kindRaw),
                  SharedTaskResourceSyncPolicy.isCloudSyncable(kind)
            else { continue }
            if data["deletedAt"] != nil { continue }
            keep.insert(id)
            let title = data["title"] as? String ?? ""
            let position = data["position"] as? Double ?? FractionalPosition.initial()
            if let existing = (task.resources ?? []).first(where: { $0.id == id }) {
                existing.title = title
                existing.body = data["body"] as? String
                existing.externalURLString = data["externalURLString"] as? String
                existing.languageIdentifier = data["languageIdentifier"] as? String
                existing.position = position
                existing.kindRaw = kindRaw
            } else {
                let resource = TaskResource(
                    id: id,
                    kind: kind,
                    title: title,
                    body: data["body"] as? String,
                    externalURLString: data["externalURLString"] as? String,
                    languageIdentifier: data["languageIdentifier"] as? String,
                    position: position,
                    task: task
                )
                context.insert(resource)
            }
        }
        // Do not delete local binary resources that were never cloud-synced.
        for resource in (task.resources ?? [])
        where SharedTaskResourceSyncPolicy.isCloudSyncable(resource.kind) && !keep.contains(resource.id) {
            context.delete(resource)
        }
        try? context.save()
        TodoshiDataChangeCenter.post(.taskContentChanged)
    }

    private func applyRemoteLabelChange(projectID: UUID, change: DocumentChange) {
        guard let context = modelContext else { return }
        let data = change.document.data()
        guard let id = UUID(uuidString: change.document.documentID) else { return }
        if change.type == .removed || data["deletedAt"] != nil {
            return
        }
        let name = data["name"] as? String ?? ""
        let color = ProjectColorCatalog.sanitized((data["color"] as? String) ?? ProjectColorCatalog.defaultHex)
        let labels = (try? LabelRepository(context: context).fetchAll()) ?? []
        if let existing = labels.first(where: { $0.id == id }) {
            existing.name = name
            existing.colorHex = color
            existing.updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? existing.updatedAt
        } else {
            let replacement = LabelTag(id: id, name: name, colorHex: color)
            context.insert(replacement)
        }
        try? context.save()
        TodoshiDataChangeCenter.post(.labelListChanged)
    }

    private func applyLabelIDs(_ ids: [UUID], to task: TaskItem, context: ModelContext) {
        let all = (try? LabelRepository(context: context).fetchAll()) ?? []
        task.labels = ids.compactMap { id in all.first(where: { $0.id == id }) }
    }

    private func handlePermissionLossIfNeeded(_ error: Error, projectID: UUID, context: ModelContext?) {
        let ns = error as NSError
        guard ns.domain == FirestoreErrorDomain,
              ns.code == FirestoreErrorCode.permissionDenied.rawValue else { return }
        guard SharedProjectPermissionLossPolicy.stopListenersOnPermissionDenied else { return }
        detachListeners(projectID: projectID)
        Task { @MainActor in
            await self.confirmMembershipAndEvictIfNeeded(projectID: projectID)
        }
    }

    // MARK: - Encoding helpers

    private func taskFirestoreData(
        _ task: TaskItem,
        activityKind: TaskCollaborationActivityKind? = nil,
        actorUID: String? = nil
    ) -> [String: Any] {
        var data: [String: Any] = [
            "id": task.id.uuidString,
            "projectId": task.project?.id.uuidString ?? "",
            "title": task.title,
            "description": task.taskDescription,
            "notes": task.notes,
            "statusRaw": task.statusRaw,
            "priorityRaw": task.priorityRaw,
            "position": task.position,
            "createdAt": Timestamp(date: task.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
            "labelIds": (task.labels ?? []).map { $0.id.uuidString },
            "recurrenceGeneration": task.recurrenceGeneration,
        ]
        data["parentTaskId"] = task.parentTask.map { $0.id.uuidString as Any } ?? NSNull()
        data["dueDate"] = task.dueDate.map { Timestamp(date: $0) as Any } ?? NSNull()
        data["reminderDate"] = task.reminderDate.map { Timestamp(date: $0) as Any } ?? NSNull()
        data["completedAt"] = task.completedAt.map { Timestamp(date: $0) as Any } ?? NSNull()
        data["completedByUID"] = task.completedByUID.map { $0 as Any } ?? NSNull()
        data["completedByDisplayName"] = task.completedByDisplayName.map { $0 as Any } ?? NSNull()
        data["deletedAt"] = task.deletedAt.map { Timestamp(date: $0) as Any } ?? NSNull()
        data["recurrenceRuleRaw"] = task.recurrenceRuleRaw.map { $0 as Any } ?? NSNull()
        data["recurrenceInterval"] = task.recurrenceInterval.map { $0 as Any } ?? NSNull()
        data["recurrenceSeriesID"] = task.recurrenceSeriesID.map { $0.uuidString as Any } ?? NSNull()
        data["nextOccurrenceID"] = task.nextOccurrenceID.map { $0.uuidString as Any } ?? NSNull()
        data["previousOccurrenceID"] = task.previousOccurrenceID.map { $0.uuidString as Any } ?? NSNull()
        // Only write editorUIDs when locally known so merge does not wipe remote ACL for members.
        if task.isRoot, let editors = task.editorUIDs {
            data["editorUIDs"] = editors
        }
        // Subtasks never carry independent assignment; responsibility resolves through the root.
        data["assigneeUID"] = task.isRoot ? (task.assigneeUID.map { $0 as Any } ?? NSNull()) : NSNull()
        if task.isRoot, let activityKind, let actorUID {
            data["lastActivityAt"] = FieldValue.serverTimestamp()
            data["lastActivityByUID"] = actorUID
            data["lastActivityKind"] = activityKind.rawValue
        }
        return data
    }

    private func resolvedActivityKind(
        for task: TaskItem,
        requested: TaskCollaborationActivityKind
    ) -> TaskCollaborationActivityKind {
        if requested != .taskUpdated { return requested }
        if !task.isRoot { return .subtaskChanged }
        return .taskUpdated
    }

    private func applyLocalActivity(
        task: TaskItem,
        actorUID: String,
        kind: TaskCollaborationActivityKind,
        at date: Date
    ) {
        guard task.isRoot else { return }
        task.lastActivityAt = date
        task.lastActivityByUID = actorUID
        task.lastActivityKindRaw = kind.rawValue
    }

    private func bumpRootActivity(
        projectID: UUID,
        rootTaskID: UUID,
        remoteID: String,
        actorUID: String,
        kind: TaskCollaborationActivityKind
    ) async throws {
        let ref = db.collection("projects").document(remoteID).collection("tasks").document(rootTaskID.uuidString)
        try await ref.updateData([
            "lastActivityAt": FieldValue.serverTimestamp(),
            "lastActivityByUID": actorUID,
            "lastActivityKind": kind.rawValue,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
        if let context = modelContext,
           let root = try? TaskRepository(context: context).fetchTask(id: rootTaskID) {
            applyLocalActivity(task: root, actorUID: actorUID, kind: kind, at: .now)
            try? context.save()
        }
    }

    /// Resolves the root task for comment/subtask activity bumps.
    func rootTaskIDForCollaboration(projectID: UUID, taskID: UUID) async -> UUID? {
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        if let context = modelContext,
           let task = try? TaskRepository(context: context).fetchTask(id: taskID) {
            return TaskCollaborationActivityPolicy.rootTaskID(for: task)
        }
        do {
            let snap = try await db.collection("projects").document(remoteID)
                .collection("tasks").document(taskID.uuidString).getDocument()
            guard let parent = snap.data()?["parentTaskId"] as? String,
                  let parentID = UUID(uuidString: parent) else {
                return taskID
            }
            return await rootTaskIDForCollaboration(projectID: projectID, taskID: parentID)
        } catch {
            return taskID
        }
    }

    private func checklistFirestoreData(_ item: ChecklistItem) -> [String: Any] {
        [
            "id": item.id.uuidString,
            "title": item.title,
            "isCompleted": item.isCompleted,
            "position": item.position,
            "createdAt": Timestamp(date: item.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
            "deletedAt": NSNull(),
        ]
    }

    private func resourceFirestoreData(_ resource: TaskResource) -> [String: Any] {
        [
            "id": resource.id.uuidString,
            "kindRaw": resource.kindRaw,
            "title": resource.title,
            "body": resource.body.map { $0 as Any } ?? NSNull(),
            "externalURLString": resource.externalURLString.map { $0 as Any } ?? NSNull(),
            "languageIdentifier": resource.languageIdentifier.map { $0 as Any } ?? NSNull(),
            "position": resource.position,
            "createdAt": Timestamp(date: resource.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
            "deletedAt": NSNull(),
        ]
    }

    private func labelFirestoreData(_ label: LabelTag) -> [String: Any] {
        [
            "id": label.id.uuidString,
            "name": label.name,
            "color": label.colorHex,
            "createdAt": Timestamp(date: label.createdAt),
            "updatedAt": FieldValue.serverTimestamp(),
            "deletedAt": NSNull(),
        ]
    }

    private func mapTaskDTO(projectID: UUID, taskID: UUID, data: [String: Any]) -> FirestoreTaskDTO {
        let labelIds = (data["labelIds"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        let remoteUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        return FirestoreTaskDTO(
            id: taskID,
            projectId: projectID,
            parentTaskId: (data["parentTaskId"] as? String).flatMap(UUID.init(uuidString:)),
            title: data["title"] as? String ?? "",
            description: data["description"] as? String ?? "",
            notes: data["notes"] as? String ?? "",
            statusRaw: data["statusRaw"] as? String ?? TaskStatus.todo.rawValue,
            priorityRaw: data["priorityRaw"] as? String ?? TaskPriority.none.rawValue,
            dueDate: (data["dueDate"] as? Timestamp)?.dateValue(),
            reminderDate: (data["reminderDate"] as? Timestamp)?.dateValue(),
            position: data["position"] as? Double ?? FractionalPosition.initial(),
            completedAt: (data["completedAt"] as? Timestamp)?.dateValue(),
            completedByUID: data["completedByUID"] as? String,
            completedByDisplayName: data["completedByDisplayName"] as? String,
            createdAt: (data["createdAt"] as? Timestamp)?.dateValue() ?? .now,
            updatedAt: remoteUpdatedAt ?? .now,
            deletedAt: (data["deletedAt"] as? Timestamp)?.dateValue(),
            labelIds: labelIds,
            recurrenceRuleRaw: data["recurrenceRuleRaw"] as? String,
            recurrenceInterval: data["recurrenceInterval"] as? Int,
            recurrenceSeriesID: (data["recurrenceSeriesID"] as? String).flatMap(UUID.init(uuidString:)),
            recurrenceGeneration: data["recurrenceGeneration"] as? Int ?? 0,
            nextOccurrenceID: (data["nextOccurrenceID"] as? String).flatMap(UUID.init(uuidString:)),
            previousOccurrenceID: (data["previousOccurrenceID"] as? String).flatMap(UUID.init(uuidString:)),
            hasAuthoritativeRemoteUpdatedAt: remoteUpdatedAt != nil,
            editorUIDs: data["editorUIDs"] as? [String] ?? [],
            assigneeUID: data["assigneeUID"] as? String,
            lastActivityAt: (data["lastActivityAt"] as? Timestamp)?.dateValue(),
            lastActivityByUID: data["lastActivityByUID"] as? String,
            lastActivityKindRaw: data["lastActivityKind"] as? String
        )
    }
}
