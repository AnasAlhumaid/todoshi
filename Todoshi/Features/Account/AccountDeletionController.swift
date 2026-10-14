import Foundation
import Observation
import SwiftData
import TodoshiCore

/// Firebase-only account deletion: Firestore cleanup → Auth.currentUser.delete() → local sign-out.
/// No provider reauthentication UI and no Cloud Functions.
@Observable
@MainActor
final class AccountDeletionController {
    private(set) var phase: AccountDeletionPhase = .idle
    private(set) var errorMessage: String?
    private(set) var errorTitleKey: String = "account.delete.failedTitle"
    /// True while Firestore/Auth deletion is in flight (inline ProgressView on Profile).
    private(set) var isDeleting = false

    private let authService: FirebaseAuthService
    private let deletionService: AccountDeletionService
    private let googleCoordinator: GoogleSignInCoordinator
    private var deletionTask: Task<Void, Never>?

    var instanceID: ObjectIdentifier { ObjectIdentifier(self) }

    init(
        authService: FirebaseAuthService = .shared,
        deletionService: AccountDeletionService = .shared,
        googleCoordinator: GoogleSignInCoordinator = GoogleSignInCoordinator()
    ) {
        self.authService = authService
        self.deletionService = deletionService
        self.googleCoordinator = googleCoordinator
    }

    func reset() {
        deletionTask?.cancel()
        deletionTask = nil
        phase = .idle
        errorMessage = nil
        errorTitleKey = "account.delete.failedTitle"
        isDeleting = false
    }

    /// Production entry after Profile destructive confirmation.
    func deleteAccountWithoutReauthentication(
        modelContext: ModelContext,
        uid: String?,
        onAuthDeletionGate: @escaping (Bool) -> Void,
        onFinalizeSession: @escaping () -> Void,
        onFinished: @escaping () -> Void
    ) {
        guard !isDeleting, phase != .complete else { return }
        errorMessage = nil
        errorTitleKey = "account.delete.failedTitle"
        isDeleting = true
        phase = .cleaningContent

        deletionTask?.cancel()
        deletionTask = Task(priority: .userInitiated) { @MainActor in
            defer {
                if self.phase != .complete {
                    self.isDeleting = false
                    onAuthDeletionGate(false)
                }
            }
            do {
                guard let activeUID = uid ?? self.authService.currentSession()?.user.id else {
                    throw CollaborationError.notAuthenticated
                }

                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletion] client Firestore cleanup START")
                #endif

                let plan = try await self.deletionService.buildPlan(uid: activeUID)
                try await self.deletionService.deleteAccount(plan: plan) { next in
                    await MainActor.run { self.phase = next }
                }

                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletion] client Firestore cleanup SUCCESS")
                TodoshiDiagnostics.note("[AccountDeletion] Firebase Auth delete START")
                #endif

                self.phase = .deletingAuthAccount
                onAuthDeletionGate(true)
                try await self.authService.deleteCurrentUser()

                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletion] Firebase Auth delete SUCCESS")
                #endif

                self.phase = .clearingLocalData
                SharedProjectSyncService.shared.stop()
                self.googleCoordinator.clearLocalSession()
                try AccountDeletionLocalWipe.wipeAllUserContent(context: modelContext, uid: activeUID)

                self.phase = .complete
                self.isDeleting = false
                onFinalizeSession()
                onAuthDeletionGate(false)

                #if DEBUG
                TodoshiDiagnostics.note("[AccountDeletion] local signOut SUCCESS")
                TodoshiDiagnostics.note("[AccountDeletionUI] Settings root")
                #endif
                onFinished()
            } catch is CancellationError {
                self.fail(with: CollaborationError.accountDeletionCancelled)
            } catch {
                self.fail(with: error)
            }
        }
    }

    private func fail(with error: Error) {
        let mapped =
            (error as? CollaborationError)
            ?? FirebaseAuthErrorPolicy.collaborationError(for: error)
            ?? .accountDeletionFailed
        #if DEBUG
        TodoshiDiagnostics.note("[AccountDeletion] FAILURE \(String(describing: mapped))")
        #endif
        errorTitleKey = "account.delete.failedTitle"
        errorMessage = UserFacingError.message(for: mapped)
        phase = .failed
        isDeleting = false
        TodoshiDiagnostics.failure("account_deletion")
    }
}
