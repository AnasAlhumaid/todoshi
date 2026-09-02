import Foundation

/// User-visible error messages without technical or sensitive detail.
public enum UserFacingError: Sendable {
    public static var storeUnavailable: String {
        NexusL10n.tr("error.storeUnavailable")
    }

    public static var storeOpenFailed: String {
        NexusL10n.tr("error.storeOpenFailed")
    }

    public static var genericSave: String {
        NexusL10n.tr("error.genericSave")
    }

    public static var missingTask: String {
        NexusL10n.tr("error.missingTask")
    }

    public static var missingProject: String {
        NexusL10n.tr("error.missingProject")
    }

    public static var notificationPermission: String {
        NexusL10n.tr("notification.disabled")
    }

    public static var resourceUnavailable: String {
        NexusL10n.tr("error.resourceUnavailable")
    }

    public static var importFailed: String {
        NexusL10n.tr("error.importFailed")
    }

    /// Maps repository / container errors to safe presentation text.
    public static func message(for error: Error, locale: Locale = .autoupdatingCurrent) -> String {
        if let container = error as? ModelContainerError {
            switch container {
            case .appGroupUnavailable:
                return NexusL10n.tr("error.storeOpenFailed", locale: locale)
            case .appGroupOpenFailed:
                return NexusL10n.tr("error.storeUnavailable", locale: locale)
            }
        }
        if let validation = error as? RepositoryValidationError {
            switch validation {
            case .emptyName:
                return NexusL10n.tr("error.nameRequired", locale: locale)
            case .missingProject:
                return NexusL10n.tr("error.missingProject", locale: locale)
            case .missingTask:
                return NexusL10n.tr("error.missingTask", locale: locale)
            case .missingLabel:
                return NexusL10n.tr("error.missingLabel", locale: locale)
            case .missingChecklistItem:
                return NexusL10n.tr("error.missingChecklist", locale: locale)
            case .missingResource:
                return NexusL10n.tr("error.resourceUnavailable", locale: locale)
            case .duplicateLabelName:
                return NexusL10n.tr("error.duplicateLabel", locale: locale)
            case .labelNameTooLong:
                return NexusL10n.tr("error.labelTooLong", locale: locale)
            case .invalidLabelColor:
                return NexusL10n.tr("error.invalidLabelColor", locale: locale)
            case .checklistTitleTooLong:
                return NexusL10n.tr("error.checklistTooLong", locale: locale)
            case .hierarchyInvalid(let result):
                return hierarchyMessage(result, locale: locale)
            case .resourceInvalid(let issue):
                return TaskResourceValidation.message(for: issue, locale: locale)
            case .recurrenceInvalid(let issue):
                return issue.message(locale: locale)
            }
        }
        return NexusL10n.tr("error.genericSave", locale: locale)
    }

    private static func hierarchyMessage(
        _ result: TaskHierarchyValidationResult,
        locale: Locale
    ) -> String {
        switch result {
        case .valid:
            return NexusL10n.tr("error.genericSave", locale: locale)
        case .parentNotFound, .missingChild, .selfParenting, .cycleDetected:
            return NexusL10n.tr("error.hierarchyInvalid", locale: locale)
        case .parentIsAlreadySubtask, .nestedHierarchyNotAllowed:
            return NexusL10n.tr("error.noNested", locale: locale)
        case .projectMismatch:
            return NexusL10n.tr("error.sameProject", locale: locale)
        }
    }
}

/// Debug-only diagnostic logging. Never write user content in any build configuration.
public enum NexusDiagnostics: Sendable {
    public static func note(_ message: @autoclosure () -> String) {
        #if DEBUG
        print("[Nexus] \(message())")
        #endif
    }

    public static func failure(_ category: String) {
        #if DEBUG
        print("[Nexus] failure: \(category)")
        #endif
    }
}
