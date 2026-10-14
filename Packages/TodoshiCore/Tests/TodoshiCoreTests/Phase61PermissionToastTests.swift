import Foundation
import Testing
@testable import TodoshiCore

struct Phase61PermissionToastTests {
    @Test("Denied task action requests permission feedback toast")
    func deniedEditRequestsToast() {
        let feedback = SharedTaskPermissionFeedback.forEditAttempt(canEditTaskContent: false)
        #expect(feedback == .deniedEdit(.tasks))
        #expect(feedback.shouldShowToast)
        #expect(feedback.toastMessage == SharedTaskPermissionPresentation.noEditPermission)
    }

    @Test("Allowed action does not request toast")
    func allowedEditNoToast() {
        let feedback = SharedTaskPermissionFeedback.forEditAttempt(canEditTaskContent: true)
        #expect(feedback == .none)
        #expect(!feedback.shouldShowToast)
        #expect(feedback.toastMessage == nil)
    }

    @Test("Comments do not trigger permission toast")
    func commentsExcluded() {
        #expect(SharedTaskPermissionFeedback.forCommentAction() == .none)
        #expect(!SharedTaskPermissionFeedback.forCommentAction().shouldShowToast)
    }

    @Test("Runtime permission revocation maps to same toast feedback channel")
    func revocationFeedback() {
        let feedback = SharedTaskPermissionFeedback.forPermissionDeniedWrite()
        #expect(feedback == .revoked)
        #expect(feedback.shouldShowToast)
        #expect(feedback.toastMessage == SharedTaskPermissionPresentation.permissionRevoked)
        #expect(
            UserFacingError.message(for: CollaborationError.taskEditPermissionDenied)
                == SharedTaskPermissionPresentation.permissionRevoked
        )
    }

    @Test("Toast state clears only for matching dismissal generation")
    func toastDismissalGeneration() {
        #expect(TodoshiToastPolicy.defaultVisibleDuration >= 2)
        #expect(TodoshiToastPolicy.defaultVisibleDuration <= 3)
        #expect(TodoshiToastPolicy.shouldClear(activeGeneration: 3, clearingGeneration: 3))
        #expect(!TodoshiToastPolicy.shouldClear(activeGeneration: 4, clearingGeneration: 3))
    }

    @Test("Denied-edit localization AR/EN")
    func localization() {
        let en = Locale(identifier: "en")
        let ar = Locale(identifier: "ar")
        #expect(
            TodoshiL10n.tr("task.permissions.noEdit", locale: en)
                == "You don't have permission to edit this task."
        )
        #expect(
            TodoshiL10n.tr("task.permissions.noEdit", locale: ar)
                == "ليس لديك صلاحية لتعديل هذه المهمة"
        )
    }
}
