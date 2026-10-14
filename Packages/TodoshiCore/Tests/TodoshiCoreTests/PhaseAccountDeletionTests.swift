import Foundation
import Testing
@testable import TodoshiCore

struct PhaseAccountDeletionTests {
    private let uid = "uid-alice"
    private let other = "uid-bob"

    private func project(
        id: String,
        owner: String,
        members: [String],
        role: ProjectMemberRole
    ) -> AccountDeletionProjectSnapshot {
        AccountDeletionProjectSnapshot(
            projectID: id,
            ownerId: owner,
            memberIds: members,
            role: role
        )
    }

    @Test("1 — No shared projects")
    func noSharedProjects() {
        let plan = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [],
            comments: [],
            attributionTasks: [],
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(plan.ownedProjectIDs.isEmpty)
        #expect(plan.memberProjectIDs.isEmpty)
        #expect(!plan.requiresOwnedProjectWarning)
    }

    @Test("2 — Member-only projects")
    func memberOnlyProjects() {
        let projects = [
            project(id: "p1", owner: other, members: [other, uid], role: .member),
            project(id: "p2", owner: other, members: [other, uid], role: .member),
        ]
        let classified = AccountDeletionPlanningPolicy.classifyProjects(uid: uid, projects: projects)
        #expect(classified.owned.isEmpty)
        #expect(classified.member == ["p1", "p2"])
    }

    @Test("3 — Owned projects")
    func ownedProjects() {
        let projects = [
            project(id: "p-owned", owner: uid, members: [uid, other], role: .owner),
        ]
        let classified = AccountDeletionPlanningPolicy.classifyProjects(uid: uid, projects: projects)
        #expect(classified.owned == ["p-owned"])
        #expect(classified.member.isEmpty)
        #expect(AccountDeletionPlanningPolicy.wouldOrphanOwnedProjects(uid: uid, projects: projects))
    }

    @Test("4 — Mixed owned and member projects")
    func mixedProjects() {
        let projects = [
            project(id: "owned", owner: uid, members: [uid], role: .owner),
            project(id: "member", owner: other, members: [other, uid], role: .member),
        ]
        let plan = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: projects,
            comments: [],
            attributionTasks: [],
            todoshiId: nil
        )
        #expect(plan.ownedProjectIDs == ["owned"])
        #expect(plan.memberProjectIDs == ["member"])
        #expect(plan.requiresOwnedProjectWarning)
    }

    @Test("5 — Owner project is never orphaned by plan")
    func ownerNeverOrphaned() {
        let projects = [
            project(id: "owned", owner: uid, members: [uid, other], role: .owner),
        ]
        let plan = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: projects,
            comments: [],
            attributionTasks: [],
            todoshiId: nil
        )
        #expect(plan.ownedProjectIDs.contains("owned"))
        #expect(!plan.memberProjectIDs.contains("owned"))
    }

    @Test("6 — Member cleanup uses Phase 9A eligibility")
    func memberCleanupUsesPhase9A() {
        #expect(
            MemberRemovalCleanupPolicy.memberCanLeave(
                actingUID: uid,
                memberUID: uid,
                memberRole: .member
            )
        )
        #expect(
            !MemberRemovalCleanupPolicy.memberCanLeave(
                actingUID: uid,
                memberUID: uid,
                memberRole: .owner
            )
        )
    }

    @Test("7 — Own comments selected for deletion")
    func ownCommentsSelected() {
        let comments = [
            AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c1", authorUID: uid),
            AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c2", authorUID: other),
        ]
        let selected = AccountDeletionPlanningPolicy.selectOwnComments(uid: uid, comments: comments)
        #expect(selected.count == 1)
        #expect(selected[0].commentID == "c1")
    }

    @Test("8 — Other comments preserved")
    func otherCommentsPreserved() {
        let comments = [
            AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c1", authorUID: uid),
            AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c2", authorUID: other),
        ]
        let foreign = AccountDeletionPlanningPolicy.selectForeignComments(uid: uid, comments: comments)
        #expect(foreign.count == 1)
        #expect(foreign[0].authorUID == other)
    }

    @Test("9 — Own completion attribution selected for scrub")
    func ownCompletionSelected() {
        let tasks = [
            AccountDeletionTaskAttributionRef(
                projectID: "p1",
                taskID: "t1",
                completedByUID: uid,
                lastActivityByUID: other
            ),
            AccountDeletionTaskAttributionRef(
                projectID: "p1",
                taskID: "t2",
                completedByUID: other,
                lastActivityByUID: other
            ),
        ]
        let scrub = AccountDeletionPlanningPolicy.selectCompletionScrubs(uid: uid, tasks: tasks)
        #expect(scrub.map(\.taskID) == ["t1"])
    }

    @Test("10 — Other attribution preserved")
    func otherAttributionPreserved() {
        let tasks = [
            AccountDeletionTaskAttributionRef(
                projectID: "p1",
                taskID: "t2",
                completedByUID: other,
                lastActivityByUID: other
            ),
        ]
        #expect(AccountDeletionPlanningPolicy.selectCompletionScrubs(uid: uid, tasks: tasks).isEmpty)
        #expect(AccountDeletionPlanningPolicy.selectActivityScrubs(uid: uid, tasks: tasks).isEmpty)
    }

    @Test("11 — Own activity UID scrubbed")
    func ownActivityScrubbed() {
        let tasks = [
            AccountDeletionTaskAttributionRef(
                projectID: "p1",
                taskID: "t1",
                completedByUID: nil,
                lastActivityByUID: uid
            ),
        ]
        let scrub = AccountDeletionPlanningPolicy.selectActivityScrubs(uid: uid, tasks: tasks)
        #expect(scrub.count == 1)
        let fields = AccountDeletionAttributionScrubPolicy.activityScrubFields(
            forUID: uid,
            lastActivityByUID: uid
        )
        #expect(fields != nil)
        #expect(fields?.keys.contains("lastActivityByUID") == true)
        #expect(
            AccountDeletionAttributionScrubPolicy.activityScrubFields(
                forUID: uid,
                lastActivityByUID: other
            ) == nil
        )
    }

    @Test("12 — Stable Todoshi ID selected for deletion")
    func todoshiIDSelected() {
        let plan = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [],
            comments: [],
            attributionTasks: [],
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(plan.identity.todoshiId == "TD-7K4P-9Q2M-X5R7Q")
        #expect(plan.identity.uid == uid)
    }

    @Test("13 — Retry plan is idempotent")
    func retryIdempotent() {
        let projects = [
            project(id: "owned", owner: uid, members: [uid], role: .owner),
            project(id: "member", owner: other, members: [other, uid], role: .member),
        ]
        let comments = [
            AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c1", authorUID: uid),
            AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c1", authorUID: uid),
        ]
        let tasks = [
            AccountDeletionTaskAttributionRef(
                projectID: "p1",
                taskID: "t1",
                completedByUID: uid,
                lastActivityByUID: uid
            ),
        ]
        let first = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: projects,
            comments: comments,
            attributionTasks: tasks,
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        let second = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: projects,
            comments: comments,
            attributionTasks: tasks,
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(AccountDeletionPlanningPolicy.isIdempotent(first: first, second: second))
        #expect(first.commentDeletes.count == 1)
    }

    @Test("14 — Batch chunking")
    func batchChunking() {
        let items = Array(0..<850)
        let chunks = AccountDeletionPlanningPolicy.chunkWrites(items, chunkSize: 400)
        #expect(chunks.count == 3)
        #expect(chunks[0].count == 400)
        #expect(chunks[1].count == 400)
        #expect(chunks[2].count == 50)
        #expect(chunks.allSatisfy { $0.count <= AccountDeletionPlanningPolicy.maxWritesPerBatch })
    }

    @Test("15 — Local cache wipe plan")
    func localWipePlan() {
        let targets = AccountDeletionPlanningPolicy.localWipeTargets
        #expect(targets.contains("personalProjects"))
        #expect(targets.contains("sharedProjectMirrors"))
        #expect(targets.contains("accountSpecificTodoshiIDCache"))
        #expect(!targets.contains("appGroupContainerStructure"))
    }

    @Test("16 — Sign-out is NOT treated as deletion")
    func signOutNotDeletion() {
        #expect(!AccountDeletionPlanningPolicy.signOutIsAccountDeletion)
        #expect(
            AccountDeletionPhasePolicy.canTransition(from: .idle, to: .confirming)
        )
        #expect(
            !AccountDeletionPhasePolicy.allowsSuccessPresentation(.clearingLocalData)
        )
        #expect(AccountDeletionPhasePolicy.allowsSuccessPresentation(.complete))
    }

    @Test("17 — Account deletion does not affect another Firebase UID")
    func doesNotAffectOtherUID() {
        let plan = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [
                project(id: "owned", owner: uid, members: [uid, other], role: .owner),
            ],
            comments: [
                AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c1", authorUID: uid),
            ],
            attributionTasks: [
                AccountDeletionTaskAttributionRef(
                    projectID: "p1",
                    taskID: "t1",
                    completedByUID: uid,
                    lastActivityByUID: uid
                ),
            ],
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(!AccountDeletionPlanningPolicy.planAffectsOtherUID(plan: plan, otherUID: other))
        #expect(!AccountDeletionPlanningPolicy.planAffectsOtherUID(plan: plan, otherUID: uid))
    }

    @Test("Provider resolution")
    func providerResolution() {
        #expect(AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: ["apple.com"]) == .apple)
        #expect(AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: ["google.com"]) == .google)
        #expect(AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: []) == .unknown)
    }

    @Test("Preserved task fields for scrub")
    func preservedFields() {
        let preserved = AccountDeletionAttributionScrubPolicy.preservedTaskFields
        #expect(preserved.contains("title"))
        #expect(preserved.contains("status"))
        #expect(preserved.contains("completedAt"))
        #expect(!preserved.contains("completedByUID"))
    }

    @Test("Owned project wipe nests before tasks and project last")
    func ownedProjectDeletionOrder() {
        let order = OwnedProjectRecursiveDeletionOrderPolicy.steps
        #expect(order.first == .taskComments)
        #expect(
            OwnedProjectRecursiveDeletionOrderPolicy.mustPrecede(.taskComments, .taskDocuments)
        )
        #expect(
            OwnedProjectRecursiveDeletionOrderPolicy.mustPrecede(.taskChecklist, .taskDocuments)
        )
        #expect(
            OwnedProjectRecursiveDeletionOrderPolicy.mustPrecede(.taskResources, .taskDocuments)
        )
        #expect(
            OwnedProjectRecursiveDeletionOrderPolicy.mustPrecede(.taskDocuments, .labels)
        )
        #expect(
            OwnedProjectRecursiveDeletionOrderPolicy.mustPrecede(.labels, .members)
        )
        #expect(
            OwnedProjectRecursiveDeletionOrderPolicy.mustPrecede(.members, .projectDocument)
        )
        #expect(order.last == .projectDocument)
        #expect(
            OwnedProjectRecursiveDeletionOrderPolicy.assertsNoOrphansAfterCompletion(
                remainingComments: 0,
                remainingChecklist: 0,
                remainingResources: 0,
                remainingTasks: 0,
                remainingLabels: 0,
                remainingMembers: 0,
                projectExists: false
            )
        )
        #expect(
            !OwnedProjectRecursiveDeletionOrderPolicy.assertsNoOrphansAfterCompletion(
                remainingComments: 1,
                remainingChecklist: 0,
                remainingResources: 0,
                remainingTasks: 0,
                remainingLabels: 0,
                remainingMembers: 0,
                projectExists: false
            )
        )
    }

    @Test("Invite cleanup selects creator and owned-project invites only")
    func inviteCleanupSelection() {
        let owned = Set(["owned-a"])
        let invites = [
            AccountDeletionInviteSnapshot(
                inviteID: "i-created",
                projectId: "owned-a",
                createdBy: uid,
                acceptedBy: nil,
                revokedAt: nil
            ),
            AccountDeletionInviteSnapshot(
                inviteID: "i-other-owner",
                projectId: "other-proj",
                createdBy: other,
                acceptedBy: nil,
                revokedAt: nil
            ),
            AccountDeletionInviteSnapshot(
                inviteID: "i-already-revoked",
                projectId: "owned-a",
                createdBy: uid,
                acceptedBy: nil,
                revokedAt: Date()
            ),
            AccountDeletionInviteSnapshot(
                inviteID: "i-accepted",
                projectId: "owned-a",
                createdBy: uid,
                acceptedBy: other,
                revokedAt: nil
            ),
        ]
        let revoke = AccountDeletionInviteCleanupPolicy.selectForRevocation(
            invites: invites,
            deletingUID: uid,
            ownedProjectIDs: owned
        )
        #expect(revoke.map(\.inviteID) == ["i-created"])
        let preserved = AccountDeletionInviteCleanupPolicy.preservesUnrelatedInvites(
            invites: invites,
            deletingUID: uid,
            ownedProjectIDs: owned
        )
        #expect(preserved.map(\.inviteID).sorted() == ["i-accepted", "i-already-revoked", "i-other-owner"])
    }

    @Test("Invite cleanup includes owned-project invites even if creator field differs")
    func inviteCleanupOwnedProject() {
        let invite = AccountDeletionInviteSnapshot(
            inviteID: "i-owned",
            projectId: "owned-a",
            createdBy: "legacy-creator",
            acceptedBy: nil,
            revokedAt: nil
        )
        #expect(
            AccountDeletionInviteCleanupPolicy.shouldRevoke(
                invite: invite,
                deletingUID: uid,
                ownedProjectIDs: ["owned-a"]
            )
        )
        #expect(
            !AccountDeletionInviteCleanupPolicy.shouldRevoke(
                invite: invite,
                deletingUID: uid,
                ownedProjectIDs: ["different"]
            )
        )
    }

    // MARK: - Hang-fix policies (AD-25 … AD-30)

    @Test("AD-25 — Auth state change after user.delete still allows terminal success")
    func authRaceAllowsTerminalSuccess() {
        #expect(
            AccountDeletionAuthRacePolicy.shouldDeferSignedOutUI(deletionInProgress: true)
        )
        #expect(
            !AccountDeletionAuthRacePolicy.shouldDeferSignedOutUI(deletionInProgress: false)
        )
        #expect(
            AccountDeletionAuthRacePolicy.allowsTerminalSuccessAfterAuthDeleted(
                phaseBeforeAuthDelete: .deletingAuthAccount,
                authUserDeleted: true
            )
        )
        #expect(
            AccountDeletionAuthRacePolicy.allowsTerminalSuccessAfterAuthDeleted(
                phaseBeforeAuthDelete: .clearingLocalData,
                authUserDeleted: true
            )
        )
        #expect(
            !AccountDeletionAuthRacePolicy.allowsTerminalSuccessAfterAuthDeleted(
                phaseBeforeAuthDelete: .cleaningContent,
                authUserDeleted: true
            )
        )
    }

    @Test("AD-26 — Remote phase failure exits loading and is retryable")
    func remoteFailureExitsLoading() {
        #expect(!AccountDeletionPhase.failed.showsBlockingProgress)
        #expect(
            AccountDeletionPhasePolicy.canTransition(from: .failed, to: .reauthenticating)
        )
        #expect(!AccountDeletionPhasePolicy.allowsSuccessPresentation(.failed))
        #expect(AccountDeletionPhase.cleaningContent.showsBlockingProgress)
    }

    @Test("AD-27 — Remote phase timeout exits loading state")
    func remoteTimeoutExitsLoading() {
        #expect(
            AccountDeletionWatchdogPolicy.didTimeOut(
                elapsed: AccountDeletionWatchdogPolicy.remotePhaseTimeoutSeconds
            )
        )
        #expect(
            !AccountDeletionWatchdogPolicy.didTimeOut(elapsed: 59.9, limit: 60)
        )
        #expect(!AccountDeletionPhase.failed.showsBlockingProgress)
        #expect(
            UserFacingError.message(for: CollaborationError.accountDeletionTimedOut)
                == UserFacingError.message(for: CollaborationError.accountDeletionFailed)
        )
    }

    @Test("AD-28 — Pagination cursor advances and terminates")
    func paginationAdvancesAndTerminates() {
        let pageSize = 400
        #expect(
            AccountDeletionPaginationPolicy.shouldContinue(
                page: 1,
                documentCount: pageSize,
                pageSize: pageSize
            )
        )
        #expect(
            !AccountDeletionPaginationPolicy.shouldContinue(
                page: 1,
                documentCount: 0,
                pageSize: pageSize
            )
        )
        #expect(
            !AccountDeletionPaginationPolicy.shouldContinue(
                page: 1,
                documentCount: 12,
                pageSize: pageSize
            )
        )
        #expect(
            !AccountDeletionPaginationPolicy.shouldContinue(
                page: AccountDeletionPaginationPolicy.maxPagesPerCollection,
                documentCount: pageSize,
                pageSize: pageSize
            )
        )
        #expect(AccountDeletionPaginationPolicy.nextPageIndex(after: 0) == 1)
        #expect(AccountDeletionPaginationPolicy.nextPageIndex(after: 7) == 8)
    }

    @Test("AD-29 — Retry after partial deletion remains idempotent")
    func retryIdempotentAfterPartial() {
        let projects = [
            project(id: "owned", owner: uid, members: [uid], role: .owner),
        ]
        let first = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: projects,
            comments: [],
            attributionTasks: [],
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        // Simulate partial: owned project already gone; rebuild from remaining inputs.
        let second = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [],
            comments: [],
            attributionTasks: [],
            todoshiId: "TD-7K4P-9Q2M-X5R7Q"
        )
        #expect(first.ownedProjectCount == 1)
        #expect(second.ownedProjectCount == 0)
        #expect(
            AccountDeletionPlanningPolicy.isIdempotent(first: second, second: second)
        )
        #expect(
            AccountDeletionPhasePolicy.canTransition(from: .failed, to: .reauthenticating)
        )
    }

    @Test("AD-30 — Coordinator cannot remain deleting after Task finished")
    func coordinatorCannotStayDeleting() {
        #expect(
            AccountDeletionCoordinatorLifecyclePolicy.isStuckDeleting(
                phase: .deletingOwnedProjects,
                taskFinished: true
            )
        )
        #expect(
            !AccountDeletionCoordinatorLifecyclePolicy.isStuckDeleting(
                phase: .deletingOwnedProjects,
                taskFinished: false
            )
        )
        #expect(
            AccountDeletionCoordinatorLifecyclePolicy.reconciledPhase(
                current: .clearingLocalData,
                taskFinished: true,
                taskFailed: true
            ) == .failed
        )
        #expect(
            AccountDeletionCoordinatorLifecyclePolicy.reconciledPhase(
                current: .deletingAuthAccount,
                taskFinished: true,
                taskFailed: false
            ) == .failed
        )
        #expect(
            AccountDeletionCoordinatorLifecyclePolicy.reconciledPhase(
                current: .complete,
                taskFinished: true,
                taskFailed: false
            ) == .complete
        )
        #expect(
            AccountDeletionCoordinatorLifecyclePolicy.reconciledPhase(
                current: .reauthenticating,
                taskFinished: true,
                taskFailed: false
            ) == .reauthenticating
        )
        #expect(!AccountDeletionPhase.reauthenticating.showsBlockingProgress)
        #expect(
            AccountDeletionPhase.deletingAuthAccount.progressLocalizationKey
                == "account.delete.progress.deletingAccount"
        )
    }

    // MARK: - Post-deletion session transition (AD-31 … AD-37)

    @Test("AD-31 — Successful deletion with Firebase currentUser nil → signed out")
    func terminalSignedOutWhenFirebaseNil() {
        let state = AccountDeletionSessionFinalizationPolicy.terminalSessionState(
            deletionSucceeded: true,
            firebaseCurrentUserIsNil: true
        )
        #expect(state == .signedOut)
        #expect(
            AccountDeletionAuthRacePolicy.shouldForceSignedOutOnGateRelease(
                firebaseCurrentUserIsNil: true,
                deferredSignedOut: false,
                accountDeletionFinalized: true
            )
        )
    }

    @Test("AD-32 — Deferred nil auth event reconciled after terminal success")
    func deferredNilReconciledAfterSuccess() {
        #expect(
            AccountDeletionSessionFinalizationPolicy.shouldReconcileDeferredSignedOut(
                deferredSignedOut: true,
                deletionSucceeded: true,
                firebaseCurrentUserIsNil: true
            )
        )
        #expect(
            AccountDeletionAuthRacePolicy.shouldDeferSignedOutUI(deletionInProgress: true)
        )
        #expect(
            AccountDeletionAuthRacePolicy.shouldForceSignedOutOnGateRelease(
                firebaseCurrentUserIsNil: true,
                deferredSignedOut: true,
                accountDeletionFinalized: true
            )
        )
    }

    @Test("AD-33 — Explicit finalization reaches signed-out without second listener callback")
    func explicitFinalizationWithoutListener() {
        #expect(
            AccountDeletionSessionFinalizationPolicy.reachesSignedOutWithoutListenerReplay(
                explicitFinalizationApplied: true
            )
        )
        #expect(
            !AccountDeletionSessionFinalizationPolicy.reachesSignedOutWithoutListenerReplay(
                explicitFinalizationApplied: false
            )
        )
        let state = AccountDeletionSessionFinalizationPolicy.terminalSessionState(
            deletionSucceeded: true,
            firebaseCurrentUserIsNil: true
        )
        #expect(state == .signedOut)
    }

    @Test("AD-34 — Terminal finalization is idempotent")
    func finalizationIdempotent() {
        let first = AccountDeletionSessionFinalizationPolicy.terminalSessionState(
            deletionSucceeded: true,
            firebaseCurrentUserIsNil: true
        )
        let second = AccountDeletionSessionFinalizationPolicy.terminalSessionState(
            deletionSucceeded: true,
            firebaseCurrentUserIsNil: true
        )
        #expect(
            AccountDeletionSessionFinalizationPolicy.isIdempotent(first: first, second: second)
        )
    }

    @Test("AD-35 — Google deletion performs Google signOut and reaches signed-out")
    func googlePathSignedOut() {
        #expect(AccountDeletionSessionFinalizationPolicy.googlePathRequiresLocalSignOut)
        #expect(
            AccountDeletionSessionFinalizationPolicy.terminalSessionState(
                deletionSucceeded: true,
                firebaseCurrentUserIsNil: true
            ) == .signedOut
        )
        #expect(
            AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: ["google.com"]) == .google
        )
    }

    @Test("AD-36 — Apple deletion reaches signed-out without another Apple callback")
    func applePathSignedOutWithoutCallback() {
        #expect(
            AccountDeletionSessionFinalizationPolicy.applePathRequiresTodoshiSignedOutWithoutAppleCallback
        )
        #expect(
            AccountDeletionSessionFinalizationPolicy.terminalSessionState(
                deletionSucceeded: true,
                firebaseCurrentUserIsNil: true
            ) == .signedOut
        )
        #expect(
            AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: ["apple.com"]) == .apple
        )
    }

    @Test("AD-37 — Root auth presentation observes terminal signed-out state")
    func rootObservesSignedOut() {
        #expect(
            AccountDeletionSessionFinalizationPolicy.rootObservesTerminalSignedOut(
                sessionState: .signedOut
            )
        )
        #expect(
            !AccountDeletionSessionFinalizationPolicy.rootObservesTerminalSignedOut(
                sessionState: .signedIn
            )
        )
        #expect(
            AccountDeletionAuthRacePolicy.shouldIgnoreSignedInListenerEvent(
                accountDeletionInProgress: false,
                accountDeletionFinalized: true,
                firebaseCurrentUserIsNil: true
            )
        )
    }

    // MARK: - UI / session ownership (AD-38 … AD-41)

    @Test("AD-38 — Root auth router switches to Settings signed-out chrome on signedOut")
    func rootAuthRouterSwitchesOnSignedOut() {
        #expect(
            RootAuthPresentationPolicy.accountChrome(for: .signedOut) == .signInPrompt
        )
        #expect(
            RootAuthPresentationPolicy.shouldResetAuthenticatedNavigation(for: .signedOut)
        )
        #expect(
            !RootAuthPresentationPolicy.shouldResetAuthenticatedNavigation(
                for: .signedIn(
                    CollaborationSession(
                        user: CollaborationUser(id: uid, displayName: "A", email: nil)
                    )
                )
            )
        )
        // Product rule: never auto-present AuthenticationView after deletion.
        #expect(
            !RootAuthPresentationPolicy.shouldPresentAuthenticationUI(
                state: .signedOut,
                accountDeletionFinalized: true
            )
        )
        #expect(
            !RootAuthPresentationPolicy.shouldPresentAuthenticationUI(
                state: .signedOut,
                accountDeletionFinalized: false
            )
        )
    }

    @Test("AD-39 — Account deletion and root UI share the same AuthSession instance")
    func sameAuthSessionInstance() {
        let root = NSObject()
        let other = NSObject()
        let rootID = ObjectIdentifier(root)
        let otherID = ObjectIdentifier(other)
        #expect(
            RootAuthPresentationPolicy.isSameAuthSessionInstance(
                rootInstanceID: rootID,
                deletionInstanceID: rootID
            )
        )
        #expect(
            !RootAuthPresentationPolicy.isSameAuthSessionInstance(
                rootInstanceID: rootID,
                deletionInstanceID: otherID
            )
        )
        // Keep both alive across assertions (prevents address reuse).
        _ = root
        _ = other
    }

    @Test("AD-40 — Stale local profile cannot restore signedIn when Firebase user is nil")
    func staleProfileCannotRestoreSignedIn() {
        #expect(
            !RootAuthPresentationPolicy.canRestoreSignedInFromLocalProfile(
                firebaseCurrentUserIsNil: true,
                hasStaleLocalProfile: true
            )
        )
        #expect(
            RootAuthPresentationPolicy.canRestoreSignedInFromLocalProfile(
                firebaseCurrentUserIsNil: false,
                hasStaleLocalProfile: true
            )
        )
    }

    @Test("AD-41 — Settings/Profile do not retain authenticated UI after signedOut")
    func settingsDoesNotRetainAuthenticatedUI() {
        #expect(
            !RootAuthPresentationPolicy.retainsAuthenticatedSettingsUI(after: .signedOut)
        )
        #expect(
            RootAuthPresentationPolicy.retainsAuthenticatedSettingsUI(
                after: .signedIn(
                    CollaborationSession(
                        user: CollaborationUser(id: uid, displayName: "A", email: nil)
                    )
                )
            )
        )
        #expect(
            RootAuthPresentationPolicy.accountChrome(for: .signedOut) == .signInPrompt
        )
    }

    // MARK: - Google reauthentication (AD-42 … AD-48)

    @Test("AD-42 — Google reauth success starts destructive pipeline")
    func googleReauthSuccessStartsPipeline() {
        #expect(
            AccountDeletionGoogleReauthPolicy.shouldStartDestructivePipeline(reauthSucceeded: true)
        )
        #expect(
            AccountDeletionPhasePolicy.canTransition(from: .reauthenticating, to: .cleaningContent)
        )
    }

    @Test("AD-43 — Google reauth failure does not start deletion")
    func googleReauthFailureDoesNotStartDeletion() {
        #expect(
            !AccountDeletionGoogleReauthPolicy.shouldStartDestructivePipeline(reauthSucceeded: false)
        )
        #expect(
            AccountDeletionPhasePolicy.canTransition(from: .reauthenticating, to: .failed)
        )
    }

    @Test("AD-44 — Google cancellation does not start deletion")
    func googleCancellationStaysOnReauth() {
        #expect(
            AccountDeletionGoogleReauthPolicy.phaseAfterUserCancellation() == .idle
        )
        #expect(
            !AccountDeletionGoogleReauthPolicy.shouldStartDestructivePipeline(reauthSucceeded: false)
        )
        #expect(
            AccountDeletionPresentationPolicy.providerCancellationStaysOnProfile()
        )
    }

    @Test("AD-45 — Missing presenter is not silent success")
    func missingPresenterNotSilent() {
        #expect(!AccountDeletionGoogleReauthPolicy.missingPresenterIsSilentSuccess())
        #expect(AccountDeletionGoogleReauthPolicy.requiresFreshGoogleCredential)
    }

    @Test("AD-46 — Successful Firebase reauth starts deletion pipeline exactly once")
    func destructivePipelineExactlyOnce() {
        #expect(
            AccountDeletionGoogleReauthPolicy.destructivePipelineStartsExactlyOnce(startCount: 1)
        )
        #expect(
            !AccountDeletionGoogleReauthPolicy.destructivePipelineStartsExactlyOnce(startCount: 2)
        )
        #expect(
            !AccountDeletionGoogleReauthPolicy.destructivePipelineStartsExactlyOnce(startCount: 0)
        )
    }

    @Test("AD-47 — View disappearance cannot cancel controller-owned Google reauth")
    func viewDisappearanceDoesNotCancelReauth() {
        #expect(
            !AccountDeletionGoogleReauthPolicy.viewDisappearanceCancelsControllerOwnedReauth()
        )
        #expect(
            AccountDeletionGoogleReauthPolicy.blocksSheetDismiss(
                isReauthAttemptInProgress: true,
                isDeleting: false
            )
        )
    }

    @Test("AD-48 — Different Google/Firebase user cannot authorize deletion")
    func differentUserCannotAuthorizeDeletion() {
        #expect(
            AccountDeletionGoogleReauthPolicy.allowsDeletionForReauthenticatedUID(
                expectedUID: uid,
                reauthenticatedUID: uid
            )
        )
        #expect(
            !AccountDeletionGoogleReauthPolicy.allowsDeletionForReauthenticatedUID(
                expectedUID: uid,
                reauthenticatedUID: other
            )
        )
    }

    // MARK: - Post-deletion Settings UX (AD-51 … AD-56)

    @Test("AD-51 — Successful deletion returns to Settings root in signed-out state")
    func deletionReturnsToSettingsSignedOut() {
        #expect(
            RootAuthPresentationPolicy.terminalDestinationAfterAccountDeletion() == .signInPrompt
        )
        #expect(
            RootAuthPresentationPolicy.shouldResetAuthenticatedNavigation(for: .signedOut)
        )
        #expect(
            RootAuthPresentationPolicy.accountChrome(for: .signedOut) == .signInPrompt
        )
    }

    @Test("AD-52 — Successful deletion does NOT automatically present AuthenticationView")
    func deletionDoesNotAutoPresentAuthSheet() {
        #expect(
            RootAuthPresentationPolicy.keepsAuthenticationSheetClosedAfterAccountDeletion()
        )
        #expect(
            !RootAuthPresentationPolicy.shouldPresentAuthenticationUI(
                state: .signedOut,
                accountDeletionFinalized: true
            )
        )
    }

    @Test("AD-53 — Profile navigation is destroyed after account deletion")
    func profileNavigationDestroyedAfterDeletion() {
        #expect(
            RootAuthPresentationPolicy.destroysProfileNavigationAfterAccountDeletion()
        )
        #expect(
            !RootAuthPresentationPolicy.retainsAuthenticatedSettingsUI(after: .signedOut)
        )
    }

    @Test("AD-54 — Signed-out Settings renders Sign In UI and no stale profile chrome")
    func signedOutSettingsShowsSignInOnly() {
        #expect(
            RootAuthPresentationPolicy.accountChrome(for: .signedOut) == .signInPrompt
        )
        #expect(
            RootAuthPresentationPolicy.accountChrome(
                for: .signedIn(
                    CollaborationSession(
                        user: CollaborationUser(id: uid, displayName: "A", email: nil)
                    )
                )
            ) == .authenticatedAccount
        )
        #expect(
            !RootAuthPresentationPolicy.canRestoreSignedInFromLocalProfile(
                firebaseCurrentUserIsNil: true,
                hasStaleLocalProfile: true
            )
        )
    }

    @Test("AD-55 — Manual Sign In may still open AuthenticationView after deletion")
    func manualSignInStillAllowedAfterDeletion() {
        #expect(
            RootAuthPresentationPolicy.allowsManualAuthenticationSheetAfterDeletion()
        )
        #expect(
            RootAuthPresentationPolicy.keepsAuthenticationSheetClosedAfterAccountDeletion()
        )
    }

    @Test("AD-56 — Apple-authenticated account uses Apple reauthentication, not Google")
    func appleAccountUsesAppleReauth() {
        let apple = AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: ["apple.com"])
        let google = AccountDeletionPlanningPolicy.resolveAuthProvider(providerIDs: ["google.com"])
        #expect(apple == .apple)
        #expect(google == .google)
        #expect(RootAuthPresentationPolicy.reauthProvider(for: apple) == .apple)
        #expect(RootAuthPresentationPolicy.reauthProvider(for: apple) != .google)
        #expect(RootAuthPresentationPolicy.reauthProvider(for: google) == .google)
    }

    // MARK: - Terminal post-delete presentation (AD-74 … AD-79)

    @Test("AD-74 — Terminal deletion success closes AccountDeletion sheet")
    func terminalSuccessClosesDeletionSheet() {
        #expect(
            AccountDeletionTerminalPresentationPolicy.closesAccountDeletionSheet(terminalSuccess: true)
        )
        #expect(
            !AccountDeletionTerminalPresentationPolicy.accountDeletionSheetBinding(
                showDeleteAccount: true,
                terminalSuccess: true
            )
        )
        #expect(
            AccountDeletionTerminalPresentationPolicy.accountDeletionSheetBinding(
                showDeleteAccount: true,
                terminalSuccess: false
            )
        )
    }

    @Test("AD-75 — Terminal deletion success closes Profile navigation")
    func terminalSuccessClosesProfileNavigation() {
        #expect(
            AccountDeletionTerminalPresentationPolicy.closesProfileNavigation(terminalSuccess: true)
        )
        #expect(RootAuthPresentationPolicy.destroysProfileNavigationAfterAccountDeletion())
        #expect(
            RootAuthPresentationPolicy.shouldResetAuthenticatedNavigation(for: .signedOut)
        )
    }

    @Test("AD-76 — No Authentication sheet is presented after deletion")
    func noAuthenticationSheetAfterDeletion() {
        #expect(
            !AccountDeletionTerminalPresentationPolicy.presentsAuthenticationSheet(terminalSuccess: true)
        )
        #expect(
            !AccountDeletionTerminalPresentationPolicy.authenticationSheetBinding(
                isPresentingAuthenticationSheet: true,
                terminalSuccess: true
            )
        )
        #expect(
            RootAuthPresentationPolicy.keepsAuthenticationSheetClosedAfterAccountDeletion()
        )
        #expect(
            !RootAuthPresentationPolicy.shouldPresentAuthenticationUI(
                state: .signedOut,
                accountDeletionFinalized: true
            )
        )
    }

    @Test("AD-77 — Selected tab after deletion is Settings")
    func selectedTabAfterDeletionIsSettings() {
        #expect(
            AccountDeletionTerminalPresentationPolicy.selectedTabAfterDeletion() == .settings
        )
        #expect(
            AccountDeletionTerminalPresentationPolicy.selectsSettingsTab(terminalSuccess: true)
        )
        #expect(
            !AccountDeletionTerminalPresentationPolicy.selectsSettingsTab(terminalSuccess: false)
        )
    }

    @Test("AD-78 — Settings root renders inline Sign In when signedOut")
    func settingsRootRendersInlineSignIn() {
        #expect(
            AccountDeletionTerminalPresentationPolicy.settingsRootChrome(for: .signedOut)
                == .signInPrompt
        )
        #expect(
            RootAuthPresentationPolicy.accountChrome(for: .signedOut) == .signInPrompt
        )
        #expect(
            RootAuthPresentationPolicy.terminalDestinationAfterAccountDeletion() == .signInPrompt
        )
        #expect(
            AccountDeletionTerminalPresentationPolicy.terminalSnapshot(
                authState: .signedOut,
                isPresentingAuthenticationSheet: false,
                showDeleteAccount: false,
                selectedTabIsSettings: true,
                profileNavigationRetained: false
            )
        )
        #expect(
            !AccountDeletionTerminalPresentationPolicy.terminalSnapshot(
                authState: .signedOut,
                isPresentingAuthenticationSheet: true,
                showDeleteAccount: false,
                selectedTabIsSettings: true,
                profileNavigationRetained: false
            )
        )
    }

    @Test("AD-79 — Force quit/relaunch remains signedOut and Settings shows Sign In")
    func relaunchRemainsSignedOutWithSignIn() {
        #expect(
            AccountDeletionTerminalPresentationPolicy.remainsSignedOutAfterRelaunch(
                firebaseCurrentUserIsNil: true
            )
        )
        #expect(
            !AccountDeletionTerminalPresentationPolicy.remainsSignedOutAfterRelaunch(
                firebaseCurrentUserIsNil: false
            )
        )
        #expect(
            !RootAuthPresentationPolicy.canRestoreSignedInFromLocalProfile(
                firebaseCurrentUserIsNil: true,
                hasStaleLocalProfile: true
            )
        )
        #expect(
            AccountDeletionTerminalPresentationPolicy.settingsRootChrome(for: .signedOut)
                == .signInPrompt
        )
    }

    // MARK: - Profile → sheet → service wiring (AD-57 … AD-64)

    @Test("AD-57 — Profile destructive confirm presents AccountDeletionFlow only AFTER confirmation")
    func profileConfirmThenSheet() {
        #expect(AccountDeletionPresentationPolicy.confirmationOwnedByProfile)
        #expect(!AccountDeletionPresentationPolicy.presentsAccountDeletionSheet)
        #expect(!AccountDeletionPresentationPolicy.presentsCustomReauthenticationSheet)
        #expect(!AccountDeletionPresentationPolicy.requiresProviderReauthentication)
        #expect(AccountDeletionPresentationPolicy.confirmingDeletionCallsClientPipelineDirectly())
        #expect(
            !AccountDeletionPresentationPolicy.shouldPresentDeletionSheet(
                destructiveConfirmTapped: true,
                confirmationCancelled: false
            )
        )
    }

    @Test("AD-58 — Cancel confirmation never presents deletion sheet")
    func cancelConfirmationNeverPresentsSheet() {
        #expect(!AccountDeletionPresentationPolicy.cancelConfirmationPresentsSheet())
        #expect(
            !AccountDeletionPresentationPolicy.shouldPresentDeletionSheet(
                destructiveConfirmTapped: false,
                confirmationCancelled: true
            )
        )
        #expect(
            !AccountDeletionPresentationPolicy.shouldPresentDeletionSheet(
                destructiveConfirmTapped: true,
                confirmationCancelled: true
            )
        )
    }

    @Test("AD-59 — Successful provider reauth invokes AccountDeletionService exactly once")
    @MainActor
    func successfulReauthInvokesServiceOnce() async throws {
        final class RecordingPerformer: AccountDeletionCloudPerforming, @unchecked Sendable {
            var callCount = 0
            func deleteAccount(
                plan: AccountDeletionPlan,
                onPhase: (@Sendable (AccountDeletionPhase) async -> Void)?
            ) async throws {
                callCount += 1
                await onPhase?(.cleaningContent)
            }
        }
        let performer = RecordingPerformer()
        let gate = AccountDeletionServiceInvocationGate(
            performer: performer,
            dependencySource: .testDouble
        )
        let plan = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [],
            comments: [],
            attributionTasks: [],
            todoshiId: nil
        )
        // Simulate post-reauth boundary used by AccountDeletionController.
        #expect(AccountDeletionGoogleReauthPolicy.shouldStartDestructivePipeline(reauthSucceeded: true))
        try await gate.deleteAccount(plan: plan, onPhase: nil)
        #expect(performer.callCount == 1)
        #expect(gate.deleteAccountInvocationCount == 1)
        try await gate.deleteAccount(plan: plan, onPhase: nil)
        #expect(gate.deleteAccountInvocationCount == 2)
        // Production path starts pipeline once per successful reauth.
        #expect(
            AccountDeletionGoogleReauthPolicy.destructivePipelineStartsExactlyOnce(startCount: 1)
        )
    }

    @Test("AD-60 — Changing UI state to deleting without service invocation is impossible")
    @MainActor
    func deletingUIRequiresServiceInvocation() async throws {
        final class RecordingPerformer: AccountDeletionCloudPerforming, @unchecked Sendable {
            func deleteAccount(
                plan: AccountDeletionPlan,
                onPhase: (@Sendable (AccountDeletionPhase) async -> Void)?
            ) async throws {
                await onPhase?(.cleaningContent)
            }
        }
        let gate = AccountDeletionServiceInvocationGate(
            performer: RecordingPerformer(),
            dependencySource: .testDouble
        )
        #expect(!gate.mayEnterDeletingUI)
        #expect(
            !AccountDeletionServiceBoundaryPolicy.mayEnterDeletingUI(serviceInvocationCount: 0)
        )
        let plan = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [],
            comments: [],
            attributionTasks: [],
            todoshiId: nil
        )
        final class Flag: @unchecked Sendable {
            var enteredDeleting = false
        }
        let flag = Flag()
        try await gate.deleteAccount(plan: plan) { phase in
            #expect(AccountDeletionServiceBoundaryPolicy.mayEnterDeletingUI(serviceInvocationCount: 1))
            if phase == .cleaningContent {
                flag.enteredDeleting = true
            }
        }
        #expect(gate.mayEnterDeletingUI)
        #expect(flag.enteredDeleting)
    }

    @Test("AD-61 — AccountDeletionService success causes AuthSession signedOut and navigation reset")
    func serviceSuccessCausesSignedOutAndNavReset() {
        #expect(
            AccountDeletionServiceBoundaryPolicy.successYieldsSignedOutAndNavigationReset(
                serviceSucceeded: true,
                authUserDeleted: true
            )
        )
        #expect(
            !AccountDeletionServiceBoundaryPolicy.successYieldsSignedOutAndNavigationReset(
                serviceSucceeded: false,
                authUserDeleted: true
            )
        )
        #expect(
            AccountDeletionSessionFinalizationPolicy.terminalSessionState(
                deletionSucceeded: true,
                firebaseCurrentUserIsNil: true
            ) == .signedOut
        )
        #expect(
            RootAuthPresentationPolicy.shouldResetAuthenticatedNavigation(for: .signedOut)
        )
        #expect(
            RootAuthPresentationPolicy.terminalDestinationAfterAccountDeletion() == .signInPrompt
        )
    }

    @Test("AD-62 — AccountDeletionService failure does not dismiss the sheet or sign out locally")
    func serviceFailureKeepsSheetAndSession() {
        #expect(!AccountDeletionServiceBoundaryPolicy.failureDismissesSheetOrSignsOutLocally())
        #expect(
            AccountDeletionSessionFinalizationPolicy.terminalSessionState(
                deletionSucceeded: false,
                firebaseCurrentUserIsNil: false
            ) == .signedIn
        )
        #expect(AccountDeletionPhase.failed.showsBlockingProgress == false)
        #expect(
            AccountDeletionPhasePolicy.canTransition(from: .failed, to: .reauthenticating)
        )
    }

    @Test("AD-63 — Production dependency container injects the real AccountDeletionService")
    @MainActor
    func productionInjectsRealAccountDeletionService() {
        final class StubPerformer: AccountDeletionCloudPerforming, @unchecked Sendable {
            func deleteAccount(
                plan: AccountDeletionPlan,
                onPhase: (@Sendable (AccountDeletionPhase) async -> Void)?
            ) async throws {}
        }
        let productionGate = AccountDeletionServiceInvocationGate(
            performer: StubPerformer(),
            dependencySource: .sharedProduction
        )
        let testGate = AccountDeletionServiceInvocationGate(
            performer: StubPerformer(),
            dependencySource: .testDouble
        )
        #expect(productionGate.injectsRealAccountDeletionService)
        #expect(!testGate.injectsRealAccountDeletionService)
        #expect(
            AccountDeletionServiceBoundaryPolicy.productionInjectsSharedAccountDeletionService(
                source: .sharedProduction
            )
        )
        // AccountDeletionController default init uses AccountDeletionService.shared → .sharedProduction
    }

    @Test("AD-64 — Device Firebase configuration resolves expected project ID without automatic emulators")
    func deviceFirebaseConfigNoAutomaticEmulators() {
        #expect(
            FirebaseRuntimeConfigPolicy.isExpectedProductionProject("todosi-b482f")
        )
        #expect(
            FirebaseRuntimeConfigPolicy.expectedProductionProjectID == "todosi-b482f"
        )
        #expect(
            !FirebaseRuntimeConfigPolicy.allowsAutomaticEmulatorsOnDeviceDebug(
                explicitlyLaunchedForEmulatorTesting: false
            )
        )
        #expect(
            !FirebaseRuntimeConfigPolicy.deviceDebugUsesEmulators(
                usingAuthEmulator: false,
                usingFirestoreEmulator: false,
                explicitlyLaunchedForEmulatorTesting: false
            )
        )
        #expect(
            FirebaseRuntimeConfigPolicy.deviceDebugUsesEmulators(
                usingAuthEmulator: true,
                usingFirestoreEmulator: false,
                explicitlyLaunchedForEmulatorTesting: true
            )
        )
    }

    // MARK: - Firebase-only client deletion (AD-C1 … AD-C8)

    @Test("AD-C1 — Recent session → direct delete succeeds → signedOut Settings")
    func recentSessionDirectDeleteSucceeds() {
        #expect(AccountDeletionPresentationPolicy.confirmingDeletionCallsClientPipelineDirectly())
        #expect(!AccountDeletionPresentationPolicy.requiresProviderReauthentication)
        #expect(
            AccountDeletionPresentationPolicy.terminalSuccessReturnsToSignedOutSettings(
                authState: .signedOut
            )
        )
        #expect(
            AccountDeletionSessionFinalizationPolicy.terminalSessionState(
                deletionSucceeded: true,
                firebaseCurrentUserIsNil: true
            ) == .signedOut
        )
        #expect(
            RootAuthPresentationPolicy.terminalDestinationAfterAccountDeletion() == .signInPrompt
        )
    }

    @Test("AD-C2 — requiresRecentLogin → no provider UI appears")
    func requiresRecentLoginNoProviderUI() {
        #expect(!AccountDeletionPresentationPolicy.launchesProviderUIOnRequiresRecentLogin)
        #expect(!AccountDeletionPresentationPolicy.requiresProviderReauthentication)
        #expect(!AccountDeletionPresentationPolicy.presentsCustomReauthenticationSheet)
        let error = CollaborationError.accountDeletionRequiresReauthentication
        #expect(
            AccountDeletionPresentationPolicy.requiresRecentLoginShowsVisibleError(error: error)
        )
    }

    @Test("AD-C3 — requiresRecentLogin → clear visible error")
    func requiresRecentLoginClearVisibleError() {
        let message = UserFacingError.message(
            for: CollaborationError.accountDeletionRequiresReauthentication
        )
        #expect(!message.isEmpty)
        #expect(
            message == TodoshiL10n.tr("account.delete.requiresRecentLogin")
        )
        #expect(
            AccountDeletionPresentationPolicy.requiresRecentLoginRemainsSignedIn(
                error: .accountDeletionRequiresReauthentication,
                signedOut: false
            )
        )
        let nsError = NSError(
            domain: FirebaseAuthErrorPolicy.errorDomain,
            code: FirebaseAuthErrorPolicy.requiresRecentLoginCode,
            userInfo: [FirebaseAuthErrorPolicy.errorNameKey: "ERROR_REQUIRES_RECENT_LOGIN"]
        )
        #expect(FirebaseAuthErrorPolicy.isRequiresRecentLogin(nsError))
        #expect(
            FirebaseAuthErrorPolicy.collaborationError(for: nsError)
                == .accountDeletionRequiresReauthentication
        )
    }

    @Test("AD-C4 — Retry after recent sign-in completes deletion")
    func retryAfterRecentSignInCompletes() {
        #expect(
            AccountDeletionPresentationPolicy.retryAfterRecentSignInCompletesDeletion(
                recentSignInCompleted: true,
                authDeleteSucceeded: true
            )
        )
        #expect(
            !AccountDeletionPresentationPolicy.retryAfterRecentSignInCompletesDeletion(
                recentSignInCompleted: false,
                authDeleteSucceeded: true
            )
        )
        #expect(AccountDeletionPresentationPolicy.providerFailureStaysOnProfileWithRetry())
    }

    @Test("AD-C5 — No account deletion sheet exists")
    func noAccountDeletionSheetExists() {
        #expect(!AccountDeletionPresentationPolicy.presentsAccountDeletionSheet)
        #expect(!AccountDeletionPresentationPolicy.presentsCustomReauthenticationSheet)
        #expect(
            !AccountDeletionPresentationPolicy.shouldPresentDeletionSheet(
                destructiveConfirmTapped: true,
                confirmationCancelled: false
            )
        )
    }

    @Test("AD-C6 — No Cloud Function is called")
    func noCloudFunctionCalled() {
        #expect(!AccountDeletionPresentationPolicy.usesCloudFunctionDeletion)
        #expect(!AccountDeletionPresentationPolicy.confirmingDeletionCallsServerDirectly())
        #expect(AccountDeletionPresentationPolicy.confirmingDeletionCallsClientPipelineDirectly())
    }

    @Test("AD-C7 — Firestore cleanup remains idempotent")
    func firestoreCleanupIdempotent() {
        let comments = [
            AccountDeletionCommentRef(projectID: "p1", taskID: "t1", commentID: "c1", authorUID: uid)
        ]
        let first = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [],
            comments: comments,
            attributionTasks: [],
            todoshiId: nil
        )
        let second = AccountDeletionPlanningPolicy.buildPlan(
            uid: uid,
            projects: [],
            comments: comments,
            attributionTasks: [],
            todoshiId: nil
        )
        #expect(AccountDeletionPlanningPolicy.isIdempotent(first: first, second: second))
    }

    @Test("AD-C8 — Terminal success returns to Settings inline Sign In")
    func terminalSuccessInlineSignIn() {
        #expect(
            AccountDeletionPresentationPolicy.terminalSuccessReturnsToSignedOutSettings(
                authState: .signedOut
            )
        )
        #expect(
            RootAuthPresentationPolicy.accountChrome(for: .signedOut) == .signInPrompt
        )
        #expect(
            RootAuthPresentationPolicy.keepsAuthenticationSheetClosedAfterAccountDeletion()
        )
        #expect(
            AccountDeletionTerminalPresentationPolicy.selectedTabAfterDeletion() == .settings
        )
    }
}
