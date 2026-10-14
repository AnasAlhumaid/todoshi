import Foundation
import FirebaseFirestore
import TodoshiCore

struct ProjectMemberRow: Identifiable, Sendable, Equatable {
    var id: String { userId }
    let userId: String
    let role: ProjectMemberRole
    let displayName: String?
    let joinedAt: Date?
    /// Nil means legacy membership — treat as full via `resolvedAccessLevel`.
    let accessLevel: ProjectMemberAccessLevel?

    var resolvedAccessLevel: ProjectMemberAccessLevel {
        if role == .owner { return .full }
        return accessLevel ?? ProjectMemberAccessLevel.legacyDefault
    }

    /// Membership facts the Core assignment policies reason about.
    var assignmentCandidate: AssignmentCandidate {
        AssignmentCandidate(
            uid: userId,
            role: role,
            accessLevel: accessLevel,
            displayName: displayName
        )
    }
}

extension Array where Element == ProjectMemberRow {
    var assignmentCandidates: [AssignmentCandidate] { map(\.assignmentCandidate) }

    /// Membership display names keyed by UID, for assignee presentation without `/users/{uid}` reads.
    var assigneeDisplayNames: [String: String] {
        reduce(into: [:]) { partial, member in
            partial[member.userId] = TaskAssignmentPresentation.memberDisplayName(member.displayName)
        }
    }
}

/// Reads membership snapshots from `projects/{id}/members`. Does not query `users/{other}`.
final class SharedProjectMembersService: @unchecked Sendable {
    static let shared = SharedProjectMembersService()

    private let db: Firestore
    private let lock = NSLock()
    private var listeners: [UUID: ListenerRegistration] = [:]

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    func fetchMembers(projectID: UUID) async throws -> [ProjectMemberRow] {
        guard isConfigured else {
            throw CollaborationError.notConfigured
        }

        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        do {
            let snapshot = try await db
                .collection("projects")
                .document(remoteID)
                .collection("members")
                .getDocuments()
            return Self.mapMembers(snapshot.documents)
        } catch {
            throw CollaborationError.membersLoadFailed
        }
    }

    /// Realtime membership updates while the Members screen is open. Call `stopListening` on disappear.
    @discardableResult
    func startListening(
        projectID: UUID,
        onChange: @escaping @Sendable ([ProjectMemberRow]) -> Void,
        onError: @escaping @Sendable (Error) -> Void
    ) -> UUID {
        let token = UUID()
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        let registration = db
            .collection("projects")
            .document(remoteID)
            .collection("members")
            .addSnapshotListener { snapshot, error in
                if let error {
                    onError(error)
                    return
                }
                guard let snapshot else {
                    onError(CollaborationError.membersLoadFailed)
                    return
                }
                onChange(Self.mapMembers(snapshot.documents))
            }
        lock.lock()
        listeners[token] = registration
        lock.unlock()
        return token
    }

    func stopListening(_ token: UUID?) {
        guard let token else { return }
        lock.lock()
        let registration = listeners.removeValue(forKey: token)
        lock.unlock()
        registration?.remove()
    }

    func currentUserRole(projectID: UUID, userID: String) async throws -> ProjectMemberRole? {
        let members = try await fetchMembers(projectID: projectID)
        return members.first(where: { $0.userId == userID })?.role
    }

    func currentUserMembership(projectID: UUID, userID: String) async throws -> ProjectMemberRow? {
        let members = try await fetchMembers(projectID: projectID)
        return members.first(where: { $0.userId == userID })
    }

    /// Owner-only: updates another member's `accessLevel` (rules reject non-owner and self-escalation paths).
    func updateAccessLevel(
        projectID: UUID,
        memberUID: String,
        accessLevel: ProjectMemberAccessLevel
    ) async throws {
        guard isConfigured else {
            throw CollaborationError.notConfigured
        }
        guard FirebaseIdentifierPolicy.isValidFirebaseUserID(memberUID) else {
            throw CollaborationError.membersLoadFailed
        }
        let remoteID = SharedProjectRemoteIDPolicy.documentID(for: projectID)
        do {
            try await db
                .collection("projects")
                .document(remoteID)
                .collection("members")
                .document(memberUID)
                .updateData(["accessLevel": accessLevel.rawValue])
        } catch {
            let ns = error as NSError
            if ns.domain == FirestoreErrorDomain,
               ns.code == FirestoreErrorCode.permissionDenied.rawValue {
                throw CollaborationError.taskEditPermissionDenied
            }
            throw CollaborationError.membersLoadFailed
        }
    }

    private static func mapMembers(_ documents: [QueryDocumentSnapshot]) -> [ProjectMemberRow] {
        documents.compactMap { doc in
            let data = doc.data()
            let userId = (data["userId"] as? String) ?? doc.documentID
            guard FirebaseIdentifierPolicy.isValidFirebaseUserID(userId) else { return nil }
            let roleRaw = data["role"] as? String ?? ProjectMemberRole.member.rawValue
            let role = ProjectMemberRole(rawValue: roleRaw) ?? .member
            let displayName = data["displayName"] as? String
            let joinedAt = (data["joinedAt"] as? Timestamp)?.dateValue()
            let accessRaw = data["accessLevel"] as? String
            let accessLevel: ProjectMemberAccessLevel? =
                accessRaw.flatMap { ProjectMemberAccessLevel(rawValue: $0) }
            return ProjectMemberRow(
                userId: userId,
                role: role,
                displayName: displayName,
                joinedAt: joinedAt,
                accessLevel: accessLevel
            )
        }
        .sorted { lhs, rhs in
            if lhs.role != rhs.role {
                return lhs.role == .owner
            }
            let left = lhs.displayName ?? ""
            let right = rhs.displayName ?? ""
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}
