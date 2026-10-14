import Foundation

/// Canonical collaboration display-name rules. Identity is always Firebase UID — never email or display name.
public enum CollaborationDisplayNamePolicy: Sendable {
  public static let membershipMaximumLength = 80

  public static func normalized(_ raw: String?) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// Normalizes Apple `fullName` from the first authorization only.
  public static func fromAppleFullName(_ components: PersonNameComponents?) -> String? {
    guard let components else { return nil }
    let formatter = PersonNameComponentsFormatter()
    formatter.style = .default
    return normalized(formatter.string(from: components))
  }

  public static func hasValidCollaborationName(_ name: String?) -> Bool {
    normalized(name) != nil
  }

  /// Collaboration-facing snapshot. Email is never used as a display name.
  public static func collaborationSnapshot(preferred: String?, uid: String) -> String {
    if let name = normalized(preferred) { return name }
    return TaskAssignmentPresentation.memberDisplayName(nil)
  }
}

public enum ProfileDisplayNameCompletionPolicy: Sendable {
  public static func needsCompletion(profileName: String?, authName: String?) -> Bool {
    !CollaborationDisplayNamePolicy.hasValidCollaborationName(profileName)
      && !CollaborationDisplayNamePolicy.hasValidCollaborationName(authName)
  }
}

public enum MemberDisplayNamePropagationPolicy: Sendable {
  public struct MembershipSnapshot: Sendable, Equatable {
    public let projectRemoteID: String
    public let memberUID: String
    public let membershipDisplayName: String?

    public init(projectRemoteID: String, memberUID: String, membershipDisplayName: String?) {
      self.projectRemoteID = projectRemoteID
      self.memberUID = memberUID
      self.membershipDisplayName = membershipDisplayName
    }
  }

  /// Whether the caller's own membership snapshot should be updated to match the profile name.
  public static func shouldUpdate(profileName: String?, membershipName: String?) -> Bool {
    guard let profile = CollaborationDisplayNamePolicy.normalized(profileName) else { return false }
    let membership = CollaborationDisplayNamePolicy.normalized(membershipName)
    return membership != profile
  }

  public static func projectIDsNeedingUpdate(
    viewerUID: String,
    profileName: String,
    memberships: [MembershipSnapshot]
  ) -> [String] {
    memberships.compactMap { item in
      guard item.memberUID == viewerUID else { return nil }
      guard shouldUpdate(profileName: profileName, membershipName: item.membershipDisplayName) else {
        return nil
      }
      return item.projectRemoteID
    }
  }
}

public enum CommentAuthorPresentation: Sendable {
  /// Active membership name wins; otherwise fall back to the stored comment snapshot.
  public static func displayName(
    authorUID: String,
    storedName: String,
    members: [AssignmentCandidate]
  ) -> String {
    if let member = members.first(where: { $0.uid == authorUID }),
       let current = CollaborationDisplayNamePolicy.normalized(member.displayName) {
      return current
    }
    if let stored = CollaborationDisplayNamePolicy.normalized(storedName) {
      return stored
    }
    return TaskAssignmentPresentation.memberDisplayName(nil)
  }

  public static func initials(
    authorUID: String,
    storedName: String,
    members: [AssignmentCandidate]
  ) -> String {
    TaskCommentInitialsPolicy.initials(
      from: displayName(authorUID: authorUID, storedName: storedName, members: members),
      fallbackUID: authorUID
    )
  }
}
