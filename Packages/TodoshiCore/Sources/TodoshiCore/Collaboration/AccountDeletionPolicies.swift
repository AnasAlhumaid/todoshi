import Foundation

/// Auth provider used for fresh reauthentication before account deletion.
public enum AccountDeletionAuthProvider: String, Sendable, Equatable {
    case apple
    case google
    case unknown
}

/// Deterministic state machine for multi-step account deletion.
public enum AccountDeletionPhase: String, Sendable, Equatable {
    case idle
    case confirming
    case reauthenticating
    case cleaningContent
    case leavingProjects
    case deletingOwnedProjects
    case deletingIdentity
    case revokingProvider
    case deletingAuthAccount
    case clearingLocalData
    case complete
    case failed

    /// True only while destructive remote/local cleanup is running (not during reauth UI).
    public var showsBlockingProgress: Bool {
        switch self {
        case .cleaningContent, .leavingProjects, .deletingOwnedProjects,
             .deletingIdentity, .revokingProvider, .deletingAuthAccount, .clearingLocalData:
            return true
        case .idle, .confirming, .reauthenticating, .complete, .failed:
            return false
        }
    }

    /// Localization key for high-level progress copy (no Firebase details).
    public var progressLocalizationKey: String {
        switch self {
        case .cleaningContent:
            return "account.delete.progress.preparing"
        case .leavingProjects:
            return "account.delete.progress.leaving"
        case .deletingOwnedProjects:
            return "account.delete.progress.owned"
        case .deletingIdentity, .revokingProvider:
            return "account.delete.progress.removing"
        case .deletingAuthAccount:
            return "account.delete.progress.deletingAccount"
        case .clearingLocalData:
            return "account.delete.progress.finishing"
        case .idle, .confirming, .reauthenticating, .complete, .failed:
            return "account.delete.progress"
        }
    }
}

/// Watchdog around individual remote deletion phases (seconds).
public enum AccountDeletionWatchdogPolicy: Sendable {
    public static let remotePhaseTimeoutSeconds: TimeInterval = 60

    public static func didTimeOut(
        elapsed: TimeInterval,
        limit: TimeInterval = remotePhaseTimeoutSeconds
    ) -> Bool {
        elapsed >= limit
    }
}

/// Auth-state listener must not tear down deletion UI mid-flight.
public enum AccountDeletionAuthRacePolicy: Sendable {
    public static func shouldDeferSignedOutUI(deletionInProgress: Bool) -> Bool {
        deletionInProgress
    }

    /// After Firebase user.delete(), coordinator still owns terminal success.
    public static func allowsTerminalSuccessAfterAuthDeleted(
        phaseBeforeAuthDelete: AccountDeletionPhase,
        authUserDeleted: Bool
    ) -> Bool {
        authUserDeleted && (
            phaseBeforeAuthDelete == .deletingAuthAccount
                || phaseBeforeAuthDelete == .clearingLocalData
                || phaseBeforeAuthDelete == .complete
        )
    }

    /// When the deletion gate releases, Firebase currentUser is authoritative.
    public static func shouldForceSignedOutOnGateRelease(
        firebaseCurrentUserIsNil: Bool,
        deferredSignedOut: Bool,
        accountDeletionFinalized: Bool
    ) -> Bool {
        if accountDeletionFinalized { return true }
        if firebaseCurrentUserIsNil { return true }
        // Deferred nil was remembered but Firebase briefly still has a user — keep session.
        _ = deferredSignedOut
        return false
    }

    /// Stale signed-in listener events must not resurrect a deleted session.
    public static func shouldIgnoreSignedInListenerEvent(
        accountDeletionInProgress: Bool,
        accountDeletionFinalized: Bool,
        firebaseCurrentUserIsNil: Bool
    ) -> Bool {
        if accountDeletionInProgress && firebaseCurrentUserIsNil {
            return true
        }
        if accountDeletionFinalized && firebaseCurrentUserIsNil {
            return true
        }
        return false
    }
}

/// Local/session finalization after successful cloud + Auth deletion (no cloud I/O).
public enum AccountDeletionSessionFinalizationPolicy: Sendable {
    public enum TerminalSessionState: String, Sendable, Equatable {
        case signedOut
        case signedIn
    }

    /// Successful deletion with Firebase currentUser nil must present signed-out UI.
    public static func terminalSessionState(
        deletionSucceeded: Bool,
        firebaseCurrentUserIsNil: Bool
    ) -> TerminalSessionState {
        if deletionSucceeded {
            return .signedOut
        }
        return firebaseCurrentUserIsNil ? .signedOut : .signedIn
    }

    /// AD-33: explicit finalization reaches signed-out even without a second listener callback.
    public static func reachesSignedOutWithoutListenerReplay(
        explicitFinalizationApplied: Bool
    ) -> Bool {
        explicitFinalizationApplied
    }

    /// Calling finalization twice must remain signed-out.
    public static func isIdempotent(
        first: TerminalSessionState,
        second: TerminalSessionState
    ) -> Bool {
        first == .signedOut && second == .signedOut
    }

    /// Google path clears Google SDK session then Todoshi session.
    public static var googlePathRequiresLocalSignOut: Bool { true }

    /// Apple path has no local Apple SDK session — Todoshi must still clear auth state.
    public static var applePathRequiresTodoshiSignedOutWithoutAppleCallback: Bool { true }

    /// Root auth presentation observes AuthSessionController.state.
    public static func rootObservesTerminalSignedOut(
        sessionState: TerminalSessionState
    ) -> Bool {
        sessionState == .signedOut
    }

    /// Deferred nil auth event must be applied after terminal success.
    public static func shouldReconcileDeferredSignedOut(
        deferredSignedOut: Bool,
        deletionSucceeded: Bool,
        firebaseCurrentUserIsNil: Bool
    ) -> Bool {
        deletionSucceeded && (deferredSignedOut || firebaseCurrentUserIsNil)
    }
}

/// Ensures the coordinator cannot remain stuck in a deleting phase after its Task ended.
public enum AccountDeletionCoordinatorLifecyclePolicy: Sendable {
    public static func reconciledPhase(
        current: AccountDeletionPhase,
        taskFinished: Bool,
        taskFailed: Bool
    ) -> AccountDeletionPhase {
        guard taskFinished else { return current }
        if taskFailed { return .failed }
        // Reauth cancellation must remain on the reauthentication screen — never fall back to confirming.
        if current == .reauthenticating {
            return .reauthenticating
        }
        if current.showsBlockingProgress {
            return .failed
        }
        return current
    }

    public static func isStuckDeleting(
        phase: AccountDeletionPhase,
        taskFinished: Bool
    ) -> Bool {
        taskFinished && phase.showsBlockingProgress
    }
}

/// Google reauthentication before destructive account deletion.
public enum AccountDeletionGoogleReauthPolicy: Sendable {
    /// Fresh Google Sign-In is required — cached GID user is not enough.
    public static let requiresFreshGoogleCredential = true

    public static func phaseAfterUserCancellation() -> AccountDeletionPhase {
        // No custom reauth sheet — cancel returns Profile to idle.
        .idle
    }

    public static func shouldStartDestructivePipeline(reauthSucceeded: Bool) -> Bool {
        reauthSucceeded
    }

    public static func allowsDeletionForReauthenticatedUID(
        expectedUID: String,
        reauthenticatedUID: String
    ) -> Bool {
        !expectedUID.isEmpty && expectedUID == reauthenticatedUID
    }

    public static func blocksSheetDismiss(
        isReauthAttemptInProgress: Bool,
        isDeleting: Bool
    ) -> Bool {
        isReauthAttemptInProgress || isDeleting
    }

    public static func missingPresenterIsSilentSuccess() -> Bool { false }

    public static func destructivePipelineStartsExactlyOnce(
        startCount: Int
    ) -> Bool {
        startCount == 1
    }

    /// Controller-owned reauth Task survives transient SwiftUI view disappearance.
    public static func viewDisappearanceCancelsControllerOwnedReauth() -> Bool { false }
}

/// Apple reauthentication button → controller → ASAuthorizationController wiring.
public enum AccountDeletionAppleReauthUIPolicy: Sendable {
    /// Exactly one enabled Apple action while waiting for reauth.
    public static func appleButtonEnabled(
        phase: AccountDeletionPhase,
        provider: AccountDeletionAuthProvider,
        isReauthAttemptInProgress: Bool
    ) -> Bool {
        phase == .reauthenticating
            && provider == .apple
            && !isReauthAttemptInProgress
    }

    public static func startingReauthDismissesSheet() -> Bool { false }

    public static func usesSameControllerInstance(
        flowControllerID: ObjectIdentifier,
        actionControllerID: ObjectIdentifier
    ) -> Bool {
        flowControllerID == actionControllerID
    }
}

/// Testable sequencer mirroring production: Button → controller → performRequests.
@MainActor
public final class AccountDeletionAppleReauthWiring {
    public private(set) var buttonActionCount = 0
    public private(set) var controllerMethodCount = 0
    public private(set) var performRequestsCount = 0
    public private(set) var sheetDismissedOnStart = false
    public let flowControllerID: ObjectIdentifier
    public let actionControllerID: ObjectIdentifier

    public init(flowControllerID: ObjectIdentifier, actionControllerID: ObjectIdentifier) {
        self.flowControllerID = flowControllerID
        self.actionControllerID = actionControllerID
    }

    /// Mirrors SwiftUI Button action — synchronous entry before Task.
    public func buttonActionEntered(invokeController: () -> Void) {
        buttonActionCount += 1
        invokeController()
    }

    public func controllerMethodEntered(invokePerformRequests: () -> Void) {
        controllerMethodCount += 1
        invokePerformRequests()
    }

    public func performRequestsCalled() {
        performRequestsCount += 1
    }

    public var usesSameControllerInstance: Bool {
        AccountDeletionAppleReauthUIPolicy.usesSameControllerInstance(
            flowControllerID: flowControllerID,
            actionControllerID: actionControllerID
        )
    }
}

/// Profile owns the destructive confirmation; Firebase client deletion has no provider reauth UI.
public enum AccountDeletionPresentationPolicy: Sendable {
    public static var confirmationOwnedByProfile: Bool { true }
    public static var sheetOwnsInitialConfirmationAlert: Bool { false }
    public static var sheetOpensBeforeConfirmation: Bool { false }
    public static var presentsCustomReauthenticationSheet: Bool { false }
    public static var presentsAccountDeletionSheet: Bool { false }
    public static var requiresProviderReauthentication: Bool { false }
    public static var usesCloudFunctionDeletion: Bool { false }
    public static var launchesProviderUIOnRequiresRecentLogin: Bool { false }

    public static func shouldPresentDeletionSheet(
        destructiveConfirmTapped: Bool,
        confirmationCancelled: Bool
    ) -> Bool {
        _ = destructiveConfirmTapped
        _ = confirmationCancelled
        return false
    }

    public static func confirmingDeletionCallsClientPipelineDirectly() -> Bool { true }

    public static func confirmingDeletionCallsServerDirectly() -> Bool { false }

    public static func confirmingDeletionLaunchesNativeProviderAuthDirectly() -> Bool { false }

    public static func presentsProgressUI(
        reauthenticationSucceeded: Bool,
        destructiveDeletionStarted: Bool
    ) -> Bool {
        _ = reauthenticationSucceeded
        return destructiveDeletionStarted
    }

    public static func requiresRecentLoginShowsVisibleError(
        error: CollaborationError
    ) -> Bool {
        error == .accountDeletionRequiresReauthentication
    }

    public static func requiresRecentLoginRemainsSignedIn(
        error: CollaborationError,
        signedOut: Bool
    ) -> Bool {
        error == .accountDeletionRequiresReauthentication && !signedOut
    }

    public static func retryAfterRecentSignInCompletesDeletion(
        recentSignInCompleted: Bool,
        authDeleteSucceeded: Bool
    ) -> Bool {
        recentSignInCompleted && authDeleteSucceeded
    }

    public static func providerCancellationStaysOnProfile() -> Bool { true }

    public static func providerFailureStaysOnProfileWithRetry() -> Bool { true }

    public static func serverSuccessPerformsLocalSignOut(serverSucceeded: Bool) -> Bool {
        // Legacy name — client Auth.delete success drives local sign-out.
        serverSucceeded
    }

    public static func serverFailureRemainsSignedIn(serverSucceeded: Bool) -> Bool {
        !serverSucceeded
    }

    public static func appleSuccessStartsAccountDeletionService(
        reauthSucceeded: Bool,
        serviceInvocationCount: Int
    ) -> Bool {
        _ = reauthSucceeded
        _ = serviceInvocationCount
        return false
    }

    public static func terminalSuccessReturnsToSignedOutSettings(
        authState: AuthenticationState
    ) -> Bool {
        if case .signedOut = authState { return true }
        return false
    }

    public static func sheetInitialPhaseAfterConfirm() -> AccountDeletionPhase {
        .cleaningContent
    }

    public static func cancelConfirmationPresentsSheet() -> Bool { false }
}

/// Production Firebase project for device Debug builds (no automatic emulators).
public enum FirebaseRuntimeConfigPolicy: Sendable {
    public static let expectedProductionProjectID = "todosi-b482f"

    public static func isExpectedProductionProject(_ projectID: String?) -> Bool {
        projectID == expectedProductionProjectID
    }

    /// Device Debug must not auto-enable emulators unless explicitly launched for emulator testing.
    public static func allowsAutomaticEmulatorsOnDeviceDebug(
        explicitlyLaunchedForEmulatorTesting: Bool
    ) -> Bool {
        explicitlyLaunchedForEmulatorTesting
    }

    public static func deviceDebugUsesEmulators(
        usingAuthEmulator: Bool,
        usingFirestoreEmulator: Bool,
        explicitlyLaunchedForEmulatorTesting: Bool
    ) -> Bool {
        if explicitlyLaunchedForEmulatorTesting {
            return usingAuthEmulator || usingFirestoreEmulator
        }
        return false
    }
}

/// Where AccountDeletionController gets its cloud deletion performer.
public enum AccountDeletionDependencySource: String, Sendable, Equatable {
    case sharedProduction
    case testDouble
}

/// Boundary rules between UI deleting state and AccountDeletionService.
public enum AccountDeletionServiceBoundaryPolicy: Sendable {
    public static func mayEnterDeletingUI(serviceInvocationCount: Int) -> Bool {
        serviceInvocationCount >= 1
    }

    public static func productionInjectsSharedAccountDeletionService(
        source: AccountDeletionDependencySource
    ) -> Bool {
        source == .sharedProduction
    }

    public static func successYieldsSignedOutAndNavigationReset(
        serviceSucceeded: Bool,
        authUserDeleted: Bool
    ) -> Bool {
        serviceSucceeded && authUserDeleted
    }

    public static func failureDismissesSheetOrSignsOutLocally() -> Bool { false }
}

/// Cloud performer invoked exactly once after successful provider reauthentication.
public protocol AccountDeletionCloudPerforming: AnyObject, Sendable {
    func deleteAccount(
        plan: AccountDeletionPlan,
        onPhase: (@Sendable (AccountDeletionPhase) async -> Void)?
    ) async throws
}

/// Testable gate used by AccountDeletionController — UI deleting requires a real service call.
@MainActor
public final class AccountDeletionServiceInvocationGate {
    public private(set) var deleteAccountInvocationCount = 0
    public let dependencySource: AccountDeletionDependencySource
    private let performer: any AccountDeletionCloudPerforming

    public init(
        performer: any AccountDeletionCloudPerforming,
        dependencySource: AccountDeletionDependencySource
    ) {
        self.performer = performer
        self.dependencySource = dependencySource
    }

    public var mayEnterDeletingUI: Bool {
        AccountDeletionServiceBoundaryPolicy.mayEnterDeletingUI(
            serviceInvocationCount: deleteAccountInvocationCount
        )
    }

    public var injectsRealAccountDeletionService: Bool {
        AccountDeletionServiceBoundaryPolicy.productionInjectsSharedAccountDeletionService(
            source: dependencySource
        )
    }

    /// Increments invocation count, then calls the real (or test) cloud performer.
    public func deleteAccount(
        plan: AccountDeletionPlan,
        onPhase: (@Sendable (AccountDeletionPhase) async -> Void)? = nil
    ) async throws {
        deleteAccountInvocationCount += 1
        try await performer.deleteAccount(plan: plan, onPhase: onPhase)
    }
}

/// Pagination must advance and terminate.
public enum AccountDeletionPaginationPolicy: Sendable {
    public static let maxPagesPerCollection = 10_000

    public static func shouldContinue(
        page: Int,
        documentCount: Int,
        pageSize: Int,
        maxPages: Int = maxPagesPerCollection
    ) -> Bool {
        guard page < maxPages else { return false }
        guard documentCount > 0 else { return false }
        return documentCount >= pageSize
    }

    public static func nextPageIndex(after page: Int) -> Int {
        page + 1
    }
}

/// Remote project membership snapshot used to plan deletion.
public struct AccountDeletionProjectSnapshot: Sendable, Equatable {
    public let projectID: String
    public let ownerId: String
    public let memberIds: [String]
    public let role: ProjectMemberRole

    public init(
        projectID: String,
        ownerId: String,
        memberIds: [String],
        role: ProjectMemberRole
    ) {
        self.projectID = projectID
        self.ownerId = ownerId
        self.memberIds = memberIds
        self.role = role
    }
}

public struct AccountDeletionCommentRef: Sendable, Equatable, Hashable {
    public let projectID: String
    public let taskID: String
    public let commentID: String
    public let authorUID: String

    public init(projectID: String, taskID: String, commentID: String, authorUID: String) {
        self.projectID = projectID
        self.taskID = taskID
        self.commentID = commentID
        self.authorUID = authorUID
    }
}

public struct AccountDeletionTaskAttributionRef: Sendable, Equatable, Hashable {
    public let projectID: String
    public let taskID: String
    public let completedByUID: String?
    public let lastActivityByUID: String?

    public init(
        projectID: String,
        taskID: String,
        completedByUID: String?,
        lastActivityByUID: String?
    ) {
        self.projectID = projectID
        self.taskID = taskID
        self.completedByUID = completedByUID
        self.lastActivityByUID = lastActivityByUID
    }
}

public struct AccountDeletionIdentityRefs: Sendable, Equatable {
    public let uid: String
    public let todoshiId: String?

    public init(uid: String, todoshiId: String?) {
        self.uid = uid
        self.todoshiId = todoshiId
    }
}

/// Full deletion plan — pure, testable, idempotent when reapplied to the same inputs.
public struct AccountDeletionPlan: Sendable, Equatable {
    public let uid: String
    public let ownedProjectIDs: [String]
    public let memberProjectIDs: [String]
    public let commentDeletes: [AccountDeletionCommentRef]
    public let completionScrubs: [AccountDeletionTaskAttributionRef]
    public let activityScrubs: [AccountDeletionTaskAttributionRef]
    public let identity: AccountDeletionIdentityRefs
    public let ownedProjectCount: Int

    public init(
        uid: String,
        ownedProjectIDs: [String],
        memberProjectIDs: [String],
        commentDeletes: [AccountDeletionCommentRef],
        completionScrubs: [AccountDeletionTaskAttributionRef],
        activityScrubs: [AccountDeletionTaskAttributionRef],
        identity: AccountDeletionIdentityRefs
    ) {
        self.uid = uid
        self.ownedProjectIDs = ownedProjectIDs
        self.memberProjectIDs = memberProjectIDs
        self.commentDeletes = commentDeletes
        self.completionScrubs = completionScrubs
        self.activityScrubs = activityScrubs
        self.identity = identity
        self.ownedProjectCount = ownedProjectIDs.count
    }

    public var requiresOwnedProjectWarning: Bool { ownedProjectCount > 0 }
}

public enum AccountDeletionPlanningPolicy: Sendable {
    public static let maxWritesPerBatch = SharedProjectSeedPolicy.maxWritesPerBatch

    /// Classifies shared projects into owned vs member-only for the deleting UID.
    public static func classifyProjects(
        uid: String,
        projects: [AccountDeletionProjectSnapshot]
    ) -> (owned: [String], member: [String]) {
        var owned: [String] = []
        var member: [String] = []
        var seenOwned = Set<String>()
        var seenMember = Set<String>()

        for project in projects {
            guard project.memberIds.contains(uid) || project.ownerId == uid else { continue }
            if project.ownerId == uid {
                if seenOwned.insert(project.projectID).inserted {
                    owned.append(project.projectID)
                }
            } else if project.role != .owner {
                if seenMember.insert(project.projectID).inserted {
                    member.append(project.projectID)
                }
            }
        }

        return (
            owned: owned.sorted(),
            member: member.sorted()
        )
    }

    /// Owner projects must be deleted entirely — never orphaned with a deleted UID as owner.
    public static func wouldOrphanOwnedProjects(
        uid: String,
        projects: [AccountDeletionProjectSnapshot]
    ) -> Bool {
        projects.contains { $0.ownerId == uid }
    }

    public static func selectOwnComments(
        uid: String,
        comments: [AccountDeletionCommentRef]
    ) -> [AccountDeletionCommentRef] {
        deduplicated(
            comments.filter { $0.authorUID == uid }
        )
        .sorted { lhs, rhs in
            if lhs.projectID != rhs.projectID { return lhs.projectID < rhs.projectID }
            if lhs.taskID != rhs.taskID { return lhs.taskID < rhs.taskID }
            return lhs.commentID < rhs.commentID
        }
    }

    public static func selectForeignComments(
        uid: String,
        comments: [AccountDeletionCommentRef]
    ) -> [AccountDeletionCommentRef] {
        comments.filter { $0.authorUID != uid }
    }

    public static func selectCompletionScrubs(
        uid: String,
        tasks: [AccountDeletionTaskAttributionRef]
    ) -> [AccountDeletionTaskAttributionRef] {
        deduplicated(
            tasks.filter { $0.completedByUID == uid }
        )
        .sorted { lhs, rhs in
            if lhs.projectID != rhs.projectID { return lhs.projectID < rhs.projectID }
            return lhs.taskID < rhs.taskID
        }
    }

    public static func selectActivityScrubs(
        uid: String,
        tasks: [AccountDeletionTaskAttributionRef]
    ) -> [AccountDeletionTaskAttributionRef] {
        deduplicated(
            tasks.filter { $0.lastActivityByUID == uid }
        )
        .sorted { lhs, rhs in
            if lhs.projectID != rhs.projectID { return lhs.projectID < rhs.projectID }
            return lhs.taskID < rhs.taskID
        }
    }

    public static func buildPlan(
        uid: String,
        projects: [AccountDeletionProjectSnapshot],
        comments: [AccountDeletionCommentRef],
        attributionTasks: [AccountDeletionTaskAttributionRef],
        todoshiId: String?
    ) -> AccountDeletionPlan {
        let classified = classifyProjects(uid: uid, projects: projects)
        return AccountDeletionPlan(
            uid: uid,
            ownedProjectIDs: classified.owned,
            memberProjectIDs: classified.member,
            commentDeletes: selectOwnComments(uid: uid, comments: comments),
            completionScrubs: selectCompletionScrubs(uid: uid, tasks: attributionTasks),
            activityScrubs: selectActivityScrubs(uid: uid, tasks: attributionTasks),
            identity: AccountDeletionIdentityRefs(uid: uid, todoshiId: todoshiId)
        )
    }

    /// Rebuilding from the same inputs yields an identical plan (retry-safe).
    public static func isIdempotent(
        first: AccountDeletionPlan,
        second: AccountDeletionPlan
    ) -> Bool {
        first == second
    }

    public static func chunkWrites<T>(
        _ items: [T],
        chunkSize: Int = maxWritesPerBatch
    ) -> [[T]] {
        guard chunkSize > 0, !items.isEmpty else { return items.isEmpty ? [] : [items] }
        var result: [[T]] = []
        var index = 0
        while index < items.count {
            let end = min(index + chunkSize, items.count)
            result.append(Array(items[index..<end]))
            index = end
        }
        return result
    }

    public static func resolveAuthProvider(
        providerIDs: [String]
    ) -> AccountDeletionAuthProvider {
        let normalized = providerIDs.map { $0.lowercased() }
        if normalized.contains("apple.com") { return .apple }
        if normalized.contains("google.com") { return .google }
        return .unknown
    }

    /// Sign-out must never be treated as account deletion.
    public static var signOutIsAccountDeletion: Bool { false }

    /// Local wipe targets — content only; App Group container structure is preserved.
    public static let localWipeTargets: [String] = [
        "personalProjects",
        "sharedProjectMirrors",
        "tasks",
        "localCollaborationCache",
        "accountSpecificSeenState",
        "accountSpecificTodoshiIDCache",
        "userSpecificLocalState",
    ]

    public static func planAffectsOtherUID(
        plan: AccountDeletionPlan,
        otherUID: String
    ) -> Bool {
        guard !otherUID.isEmpty, plan.uid != otherUID else { return false }
        if plan.identity.uid == otherUID { return true }
        if plan.commentDeletes.contains(where: { $0.authorUID == otherUID }) { return true }
        if plan.completionScrubs.contains(where: { $0.completedByUID == otherUID }) { return true }
        if plan.activityScrubs.contains(where: { $0.lastActivityByUID == otherUID }) { return true }
        return false
    }

    private static func deduplicated<T: Hashable>(_ items: [T]) -> [T] {
        var seen = Set<T>()
        var result: [T] = []
        for item in items where seen.insert(item).inserted {
            result.append(item)
        }
        return result
    }
}

public enum AccountDeletionPhasePolicy: Sendable {
    public static func canTransition(from: AccountDeletionPhase, to: AccountDeletionPhase) -> Bool {
        switch (from, to) {
        case (.idle, .confirming),
             (.idle, .reauthenticating), // Profile-owned confirm → sheet opens in reauth
             (.confirming, .reauthenticating),
             (.confirming, .idle),
             (.reauthenticating, .cleaningContent),
             (.reauthenticating, .failed),
             (.reauthenticating, .idle),
             (.cleaningContent, .leavingProjects),
             (.cleaningContent, .failed),
             (.leavingProjects, .deletingOwnedProjects),
             (.leavingProjects, .failed),
             (.deletingOwnedProjects, .deletingIdentity),
             (.deletingOwnedProjects, .failed),
             (.deletingIdentity, .revokingProvider),
             (.deletingIdentity, .deletingAuthAccount),
             (.deletingIdentity, .failed),
             (.revokingProvider, .deletingAuthAccount),
             (.revokingProvider, .failed),
             (.deletingAuthAccount, .clearingLocalData),
             (.deletingAuthAccount, .failed),
             (.clearingLocalData, .complete),
             (.clearingLocalData, .failed),
             (.failed, .idle),
             (.failed, .reauthenticating),
             (.complete, .idle):
            return true
        default:
            return false
        }
    }

    /// Success may only be reported after Firebase Auth deletion + local clear.
    public static func allowsSuccessPresentation(_ phase: AccountDeletionPhase) -> Bool {
        phase == .complete
    }
}

/// Completion scrub payload — clears identity fields only.
public enum AccountDeletionAttributionScrubPolicy: Sendable {
    public static func completionScrubFields(forUID uid: String, completedByUID: String?) -> [String: Any?]? {
        guard completedByUID == uid else { return nil }
        return [
            "completedByUID": nil as Any?,
            "completedByDisplayName": nil as Any?,
        ]
    }

    public static func activityScrubFields(forUID uid: String, lastActivityByUID: String?) -> [String: Any?]? {
        guard lastActivityByUID == uid else { return nil }
        return [
            "lastActivityByUID": nil as Any?,
        ]
    }

    /// Fields that must never change during attribution scrub.
    public static let preservedTaskFields: Set<String> = [
        "title",
        "status",
        "completedAt",
        "assigneeUID",
        "editorUIDs",
        "lastActivityAt",
        "lastActivityKind",
        "parentTaskId",
        "projectId",
    ]
}

/// Canonical recursive wipe order for an owned shared project.
/// Firestore does not cascade-delete subcollections — nested paths must go first.
public enum OwnedProjectRecursiveDeletionOrderPolicy: Sendable {
    public enum Step: String, Sendable, Equatable, CaseIterable {
        case taskComments
        case taskChecklist
        case taskResources
        case taskDocuments
        case labels
        case members
        case projectDocument
    }

    public static let steps: [Step] = Array(Step.allCases)

    /// Nested task subcollections must complete before any task document delete.
    public static var nestedTaskSubcollections: [Step] {
        [.taskComments, .taskChecklist, .taskResources]
    }

    public static func mustPrecede(_ earlier: Step, _ later: Step) -> Bool {
        guard let a = steps.firstIndex(of: earlier),
              let b = steps.firstIndex(of: later)
        else { return false }
        return a < b
    }

    public static func assertsNoOrphansAfterCompletion(
        remainingComments: Int,
        remainingChecklist: Int,
        remainingResources: Int,
        remainingTasks: Int,
        remainingLabels: Int,
        remainingMembers: Int,
        projectExists: Bool
    ) -> Bool {
        remainingComments == 0
            && remainingChecklist == 0
            && remainingResources == 0
            && remainingTasks == 0
            && remainingLabels == 0
            && remainingMembers == 0
            && projectExists == false
    }
}

public struct AccountDeletionInviteSnapshot: Sendable, Equatable, Hashable {
    public let inviteID: String
    public let projectId: String
    public let createdBy: String
    public let acceptedBy: String?
    public let revokedAt: Date?

    public init(
        inviteID: String,
        projectId: String,
        createdBy: String,
        acceptedBy: String?,
        revokedAt: Date?
    ) {
        self.inviteID = inviteID
        self.projectId = projectId
        self.createdBy = createdBy
        self.acceptedBy = acceptedBy
        self.revokedAt = revokedAt
    }

    public var isActive: Bool {
        acceptedBy == nil && revokedAt == nil
    }
}

/// Selects invites that must be revoked during account deletion.
public enum AccountDeletionInviteCleanupPolicy: Sendable {
    /// Revoke when the deleting user created the invite, or when it targets an owned project.
    public static func shouldRevoke(
        invite: AccountDeletionInviteSnapshot,
        deletingUID: String,
        ownedProjectIDs: Set<String>
    ) -> Bool {
        guard invite.isActive else { return false }
        if invite.createdBy == deletingUID { return true }
        if ownedProjectIDs.contains(invite.projectId) { return true }
        return false
    }

    public static func selectForRevocation(
        invites: [AccountDeletionInviteSnapshot],
        deletingUID: String,
        ownedProjectIDs: Set<String>
    ) -> [AccountDeletionInviteSnapshot] {
        var seen = Set<String>()
        var selected: [AccountDeletionInviteSnapshot] = []
        for invite in invites {
            guard shouldRevoke(
                invite: invite,
                deletingUID: deletingUID,
                ownedProjectIDs: ownedProjectIDs
            ) else { continue }
            if seen.insert(invite.inviteID).inserted {
                selected.append(invite)
            }
        }
        return selected.sorted { $0.inviteID < $1.inviteID }
    }

    public static func preservesUnrelatedInvites(
        invites: [AccountDeletionInviteSnapshot],
        deletingUID: String,
        ownedProjectIDs: Set<String>
    ) -> [AccountDeletionInviteSnapshot] {
        invites.filter {
            !shouldRevoke(invite: $0, deletingUID: deletingUID, ownedProjectIDs: ownedProjectIDs)
        }
    }
}
