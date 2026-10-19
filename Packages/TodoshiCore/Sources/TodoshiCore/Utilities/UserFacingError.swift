import Foundation

/// User-visible error messages without technical or sensitive detail.
public enum UserFacingError: Sendable {
    public static var storeUnavailable: String {
        TodoshiL10n.tr("error.storeUnavailable")
    }

    public static var storeOpenFailed: String {
        TodoshiL10n.tr("error.storeOpenFailed")
    }

    public static var genericSave: String {
        TodoshiL10n.tr("error.genericSave")
    }

    public static var missingTask: String {
        TodoshiL10n.tr("error.missingTask")
    }

    public static var missingProject: String {
        TodoshiL10n.tr("error.missingProject")
    }

    public static var notificationPermission: String {
        TodoshiL10n.tr("notification.disabled")
    }

    public static var resourceUnavailable: String {
        TodoshiL10n.tr("error.resourceUnavailable")
    }

    public static var importFailed: String {
        TodoshiL10n.tr("error.importFailed")
    }

    /// Maps repository / container errors to safe presentation text.
    public static func message(for error: Error, locale: Locale = AppLanguageStore.resolvedLocale) -> String {
        if let container = error as? ModelContainerError {
            switch container {
            case .appGroupUnavailable:
                return TodoshiL10n.tr("error.storeOpenFailed", locale: locale)
            case .appGroupOpenFailed:
                return TodoshiL10n.tr("error.storeUnavailable", locale: locale)
            }
        }
        if let validation = error as? RepositoryValidationError {
            switch validation {
            case .emptyName:
                return TodoshiL10n.tr("error.nameRequired", locale: locale)
            case .missingProject:
                return TodoshiL10n.tr("error.missingProject", locale: locale)
            case .missingTask:
                return TodoshiL10n.tr("error.missingTask", locale: locale)
            case .missingLabel:
                return TodoshiL10n.tr("error.missingLabel", locale: locale)
            case .missingChecklistItem:
                return TodoshiL10n.tr("error.missingChecklist", locale: locale)
            case .missingResource:
                return TodoshiL10n.tr("error.resourceUnavailable", locale: locale)
            case .duplicateLabelName:
                return TodoshiL10n.tr("error.duplicateLabel", locale: locale)
            case .labelNameTooLong:
                return TodoshiL10n.tr("error.labelTooLong", locale: locale)
            case .invalidLabelColor:
                return TodoshiL10n.tr("error.invalidLabelColor", locale: locale)
            case .checklistTitleTooLong:
                return TodoshiL10n.tr("error.checklistTooLong", locale: locale)
            case .hierarchyInvalid(let result):
                return hierarchyMessage(result, locale: locale)
            case .resourceInvalid(let issue):
                return TaskResourceValidation.message(for: issue, locale: locale)
            case .recurrenceInvalid(let issue):
                return issue.message(locale: locale)
            case .invalidTaskStatusForProjectType, .subtasksNotSupportedForProjectType:
                return TodoshiL10n.tr("error.genericSave", locale: locale)
            }
        }
        if let collaboration = error as? CollaborationError {
            return collaborationMessage(collaboration, locale: locale)
        }
        if let authError = FirebaseAuthErrorPolicy.collaborationError(for: error) {
            return collaborationMessage(authError, locale: locale)
        }
        return TodoshiL10n.tr("error.genericSave", locale: locale)
    }

    private static func collaborationMessage(
        _ error: CollaborationError,
        locale: Locale
    ) -> String {
        switch error {
        case .notConfigured:
            return TodoshiL10n.tr("account.error.unavailable", locale: locale)
        case .notAuthenticated:
            return TodoshiL10n.tr("account.error.notSignedIn", locale: locale)
        case .unavailable:
            return TodoshiL10n.tr("account.error.unavailable", locale: locale)
        case .signInCancelled:
            return TodoshiL10n.tr("account.error.cancelled", locale: locale)
        case .appleCredentialUnavailable:
            return TodoshiL10n.tr("account.error.appleUnavailable", locale: locale)
        case .missingIdentityToken:
            return TodoshiL10n.tr("account.error.invalidCredential", locale: locale)
        case .invalidCredential:
            return TodoshiL10n.tr("account.error.invalidCredential", locale: locale)
        case .signInFailed:
            return TodoshiL10n.tr("account.error.signInFailed", locale: locale)
        case .googleCredentialUnavailable, .googlePresentationFailed, .googleSignInFailed:
            return TodoshiL10n.tr("account.error.googleSignInFailed", locale: locale)
        case .accountExistsWithDifferentCredential:
            return TodoshiL10n.tr("account.error.providerCollision", locale: locale)
        case .profileSyncFailed:
            return TodoshiL10n.tr("account.error.profileSync", locale: locale)
        case .profileLoadFailed:
            return TodoshiL10n.tr("profile.error.loadFailed", locale: locale)
        case .profileNameInvalid:
            return TodoshiL10n.tr("profile.error.nameInvalid", locale: locale)
        case .profileNameTooLong:
            return TodoshiL10n.tr("profile.error.nameTooLong", locale: locale)
        case .profileUpdateFailed:
            return TodoshiL10n.tr("profile.error.updateFailed", locale: locale)
        case .shareConversionDisabled:
            return TodoshiL10n.tr("project.share.unavailable", locale: locale)
        case .shareFailed:
            return TodoshiL10n.tr("project.share.failed", locale: locale)
        case .shareLocalSaveFailed:
            return TodoshiL10n.tr("project.share.localSaveFailed", locale: locale)
        case .shareConflict:
            return TodoshiL10n.tr("project.share.conflict", locale: locale)
        case .alreadyShared:
            return TodoshiL10n.tr("project.share.alreadyShared", locale: locale)
        case .membersLoadFailed:
            return TodoshiL10n.tr("project.members.loadFailed", locale: locale)
        case .inviteInvalid:
            return TodoshiL10n.tr("project.invite.invalid", locale: locale)
        case .inviteExpired:
            return TodoshiL10n.tr("project.invite.expired", locale: locale)
        case .inviteAlreadyUsed:
            return TodoshiL10n.tr("project.invite.alreadyUsed", locale: locale)
        case .inviteRevoked:
            return TodoshiL10n.tr("project.invite.revoked", locale: locale)
        case .inviteCreateFailed:
            return TodoshiL10n.tr("project.invite.createFailed", locale: locale)
        case .inviteAcceptFailed:
            return TodoshiL10n.tr("project.invite.acceptFailed", locale: locale)
        case .inviteNotOwner:
            return TodoshiL10n.tr("project.invite.ownerOnly", locale: locale)
        case .commentInvalidBody:
            return TodoshiL10n.tr("task.comments.error.empty", locale: locale)
        case .commentPostFailed:
            return TodoshiL10n.tr("task.comments.error.postFailed", locale: locale)
        case .taskEditPermissionDenied:
            return TodoshiL10n.tr("task.permissions.revoked", locale: locale)
        case .memberRemoveFailed:
            return TodoshiL10n.tr("project.members.removeFailed", locale: locale)
        case .memberLeaveFailed:
            return TodoshiL10n.tr("project.members.leaveFailed", locale: locale)
        case .identityProvisioningFailed:
            return TodoshiL10n.tr("identity.todoshiId.provisioningFailed", locale: locale)
        case .accountDeletionFailed:
            return TodoshiL10n.tr("account.delete.error", locale: locale)
        case .accountDeletionRequiresReauthentication:
            return TodoshiL10n.tr("account.delete.requiresRecentLogin", locale: locale)
        case .accountDeletionCancelled:
            return TodoshiL10n.tr("account.error.cancelled", locale: locale)
        case .accountDeletionProviderRevokeFailed:
            return TodoshiL10n.tr("account.delete.revokeFailed", locale: locale)
        case .accountDeletionTimedOut:
            return TodoshiL10n.tr("account.delete.error", locale: locale)
        }
    }

    private static func hierarchyMessage(
        _ result: TaskHierarchyValidationResult,
        locale: Locale
    ) -> String {
        switch result {
        case .valid:
            return TodoshiL10n.tr("error.genericSave", locale: locale)
        case .parentNotFound, .missingChild, .selfParenting, .cycleDetected:
            return TodoshiL10n.tr("error.hierarchyInvalid", locale: locale)
        case .parentIsAlreadySubtask, .nestedHierarchyNotAllowed:
            return TodoshiL10n.tr("error.noNested", locale: locale)
        case .projectMismatch:
            return TodoshiL10n.tr("error.sameProject", locale: locale)
        }
    }
}

/// Debug-only diagnostic logging. Never write user content in any build configuration.
public enum TodoshiDiagnostics: Sendable {
    public static func note(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Todoshi] \(message())")
        #endif
    }

    public static func failure(_ category: String) {
        #if DEBUG
        print("[Todoshi] failure: \(category)")
        #endif
    }
}
