import Foundation

public enum ProjectSharingMode: String, Codable, Sendable, CaseIterable, Equatable {
    case personal
    case shared
}

public enum SharedProjectRemoteIDPolicy: Sendable {
    /// Firestore project document ID must equal the local Project UUID string.
    public static func documentID(for projectID: UUID) -> String {
        projectID.uuidString
    }

    public static func matchesLocalProject(remoteID: String?, projectID: UUID) -> Bool {
        remoteID == documentID(for: projectID)
    }
}

public enum SharedProjectLocalStatePolicy: Sendable {
    public struct Transition: Sendable, Equatable {
        public let sharingMode: ProjectSharingMode
        public let remoteProjectID: String?
        public let sharedAt: Date?

        public init(sharingMode: ProjectSharingMode, remoteProjectID: String?, sharedAt: Date?) {
            self.sharingMode = sharingMode
            self.remoteProjectID = remoteProjectID
            self.sharedAt = sharedAt
        }
    }

    /// Local shared metadata is applied only after trusted remote bootstrap succeeds.
    public static func afterSuccessfulRemoteBootstrap(
        projectID: UUID,
        at date: Date = .now
    ) -> Transition {
        Transition(
            sharingMode: .shared,
            remoteProjectID: SharedProjectRemoteIDPolicy.documentID(for: projectID),
            sharedAt: date
        )
    }

    public static func personalDefault() -> Transition {
        Transition(sharingMode: .personal, remoteProjectID: nil, sharedAt: nil)
    }

    public static func isValidSharedMetadata(
        sharingMode: ProjectSharingMode,
        remoteProjectID: String?,
        sharedAt: Date?,
        projectID: UUID
    ) -> Bool {
        switch sharingMode {
        case .personal:
            return remoteProjectID == nil && sharedAt == nil
        case .shared:
            return SharedProjectRemoteIDPolicy.matchesLocalProject(
                remoteID: remoteProjectID,
                projectID: projectID
            ) && sharedAt != nil
        }
    }
}

/// Recovery when remote bootstrap succeeded but local SwiftData save failed.
public enum SharedProjectRecoveryPolicy: Sendable {
    /// Retry uses the same deterministic project UUID; do not delete remote data.
    public static let shouldDeleteRemoteOnLocalSaveFailure = false

    public static func shouldRetryBootstrap(
        localSharingMode: ProjectSharingMode,
        remoteBootstrapSucceeded: Bool
    ) -> Bool {
        remoteBootstrapSucceeded && localSharingMode == .personal
    }
}

/// Gates production share conversion. Firestore-only owner bootstrap is enabled on Spark.
public enum SharedProjectBootstrapPolicy: Sendable {
    public static var isShareConversionEnabled: Bool { true }

    public static let requiredTrustedBackend = "Firestore WriteBatch + Security Rules (owner bootstrap only)"
    public static let billingNote = "Phase 2 uses Auth + Firestore only; Cloud Functions / Blaze are not required for owner bootstrap."
}

public enum SharedProjectPresentation: Sendable {
    public static let indicatorSystemImage = "person.2"

    public static func accessibilityLabel(locale: Locale = .autoupdatingCurrent) -> String {
        TodoshiL10n.tr("project.sharedA11y", locale: locale)
    }

    public static func memberRoleLabel(
        _ role: ProjectMemberRole,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch role {
        case .owner:
            return TodoshiL10n.tr("project.members.owner", locale: locale)
        case .member:
            return TodoshiL10n.tr("project.members.member", locale: locale)
        }
    }
}

public enum SharedProjectBootstrapInputValidation: Sendable {
    public static let titleMaxLength = 100
    public static let descriptionMaxLength = 2000

    public enum Issue: Error, Sendable, Equatable {
        case invalidProjectID
        case emptyTitle
        case titleTooLong
        case descriptionTooLong
        case invalidColor
    }

    public static func validate(
        projectID: String,
        title: String,
        description: String?,
        color: String?
    ) -> Result<(UUID, String, String, String), Issue> {
        guard let uuid = UUID(uuidString: projectID) else {
            return .failure(.invalidProjectID)
        }
        let trimmedTitle = FieldValidation.trimmed(title)
        guard !trimmedTitle.isEmpty else { return .failure(.emptyTitle) }
        guard trimmedTitle.count <= titleMaxLength else { return .failure(.titleTooLong) }

        let trimmedDescription = FieldValidation.trimmed(description ?? "")
        guard trimmedDescription.count <= descriptionMaxLength else {
            return .failure(.descriptionTooLong)
        }

        let sanitizedColor: String
        if let color {
            let upper = color.uppercased()
            guard ProjectColorCatalog.swatches.contains(where: { $0.hex.uppercased() == upper }) else {
                return .failure(.invalidColor)
            }
            sanitizedColor = ProjectColorCatalog.sanitized(color)
        } else {
            sanitizedColor = ProjectColorCatalog.defaultHex
        }

        return .success((uuid, trimmedTitle, trimmedDescription, sanitizedColor))
    }
}
