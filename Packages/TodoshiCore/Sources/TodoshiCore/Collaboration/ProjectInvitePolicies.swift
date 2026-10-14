import Foundation
import Security

/// Cryptographically secure invite token (≈43 chars URL-safe Base64, 256-bit entropy).
public enum ProjectInviteTokenGenerator: Sendable {
    public static let byteCount = 32
    public static let minimumLength = 40
    public static let maximumLength = 64

    public static func generate() -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        return Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    public static func isValidFormat(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumLength, trimmed.count <= maximumLength else {
            return false
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}

public enum ProjectInviteLifetimePolicy: Sendable {
    /// MVP invite lifetime.
    public static let lifetimeDays = 7
    public static let lifetime: TimeInterval = TimeInterval(lifetimeDays * 24 * 60 * 60)

    public static func expiresAt(from createdAt: Date = .now) -> Date {
        createdAt.addingTimeInterval(lifetime)
    }
}

public enum ProjectInviteURLBuilder: Sendable {
    /// Development deep link. Architecture can later switch host to https://todoshi.app without changing the domain model.
    public static func url(token: String) -> URL? {
        guard ProjectInviteTokenGenerator.isValidFormat(token) else { return nil }
        var components = URLComponents()
        components.scheme = TodoshiDeepLink.scheme
        components.host = "invite"
        components.path = "/\(token.trimmingCharacters(in: .whitespacesAndNewlines))"
        return components.url
    }

    public static func shareMessage(url: URL, locale: Locale = .autoupdatingCurrent) -> String {
        TodoshiL10n.format("project.invite.shareMessage", locale: locale, url.absoluteString)
    }
}

public enum ProjectInviteStatus: String, Sendable, Equatable {
    case valid
    case expired
    case accepted
    case revoked
    case invalid
}

public enum ProjectInviteStatusPolicy: Sendable {
    public static func status(
        acceptedBy: String?,
        revokedAt: Date?,
        expiresAt: Date?,
        now: Date = .now
    ) -> ProjectInviteStatus {
        if acceptedBy != nil { return .accepted }
        if revokedAt != nil { return .revoked }
        guard let expiresAt else { return .invalid }
        if expiresAt <= now { return .expired }
        return .valid
    }

    public static func userMessage(
        for status: ProjectInviteStatus,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        switch status {
        case .valid:
            return ""
        case .expired:
            return TodoshiL10n.tr("project.invite.expired", locale: locale)
        case .accepted:
            return TodoshiL10n.tr("project.invite.alreadyUsed", locale: locale)
        case .revoked:
            return TodoshiL10n.tr("project.invite.revoked", locale: locale)
        case .invalid:
            return TodoshiL10n.tr("project.invite.invalid", locale: locale)
        }
    }
}

/// Local shell for a joined shared project (no tasks until Phase 4).
public struct JoinedSharedProjectShell: Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let description: String
    public let colorHex: String
    public let remoteProjectID: String
    public let sharedAt: Date
    public let projectType: ProjectType

    public init(
        id: UUID,
        title: String,
        description: String,
        colorHex: String,
        remoteProjectID: String,
        sharedAt: Date = .now,
        projectType: ProjectType = .tasks
    ) {
        self.id = id
        self.title = title
        self.description = description
        self.colorHex = colorHex
        self.remoteProjectID = remoteProjectID
        self.sharedAt = sharedAt
        self.projectType = projectType
    }
}

public enum JoinedSharedProjectShellPolicy: Sendable {
    public static func make(
        projectID: UUID,
        title: String,
        description: String,
        color: String,
        projectType: ProjectType = .tasks,
        at date: Date = .now
    ) -> JoinedSharedProjectShell {
        JoinedSharedProjectShell(
            id: projectID,
            title: FieldValidation.trimmed(title),
            description: FieldValidation.trimmed(description),
            colorHex: ProjectColorCatalog.sanitized(color),
            remoteProjectID: SharedProjectRemoteIDPolicy.documentID(for: projectID),
            sharedAt: date,
            projectType: projectType
        )
    }

    public static func shouldCreateLocalShell(
        existingLocalSharingMode: ProjectSharingMode?,
        existingRemoteProjectID: String?,
        projectID: UUID
    ) -> Bool {
        // Duplicate avoidance: same UUID already present as shared with matching remote ID.
        if existingLocalSharingMode == .shared,
           SharedProjectRemoteIDPolicy.matchesLocalProject(
            remoteID: existingRemoteProjectID,
            projectID: projectID
           ) {
            return false
        }
        return true
    }
}

public enum ProjectInvitePresentation: Sendable {
    public static func canInviteMembers(role: ProjectMemberRole?) -> Bool {
        role == .owner
    }

    public static let temporaryNoTaskSyncNoticeKey = "project.invite.joinedNoTaskSync"
}
