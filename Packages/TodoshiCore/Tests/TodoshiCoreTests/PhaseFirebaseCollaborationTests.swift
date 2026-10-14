import Foundation
import Testing
@testable import TodoshiCore

struct PhaseFirebaseCollaborationTests {
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    @Test("ProjectMemberRole Codable round-trip")
    func projectMemberRoleRoundTrip() throws {
        for role in ProjectMemberRole.allCases {
            let data = try encoder.encode(role)
            let decoded = try decoder.decode(ProjectMemberRole.self, from: data)
            #expect(decoded == role)
        }
    }

    @Test("Firebase UID remains String and is not modeled as UUID")
    func firebaseUIDIsString() {
        let uid = "firebase-uid-abc123"
        let user = CollaborationUser(id: uid, displayName: "Anas", email: "user@example.com")
        #expect(user.id == uid)
        #expect(FirebaseIdentifierPolicy.isValidFirebaseUserID(uid))
        #expect(UUID(uuidString: uid) == nil)
    }

    @Test("UUID project and task identifiers round-trip for Firestore document IDs")
    func uuidDocumentIDs() {
        let projectID = UUID()
        let taskID = UUID()
        #expect(FirebaseIdentifierPolicy.firestoreDocumentID(for: projectID) == projectID.uuidString)
        #expect(FirebaseIdentifierPolicy.firestoreDocumentID(for: taskID) == taskID.uuidString)
    }

    @Test("Collaboration configuration reports local-only when Firebase is unavailable")
    func localOnlyWhenUnavailable() {
        #expect(CollaborationConfigurationPolicy.status(isFirebaseConfigured: false) == .configuredLocalOnly)
        #expect(CollaborationConfigurationPolicy.localOnlyGuarantee)
        #expect(CollaborationArchitecturePolicy.sourceOfTruth(isShared: false) == "SwiftData")
    }

    @Test("Personal vs shared architecture policy")
    func architecturePolicy() {
        #expect(CollaborationArchitecturePolicy.sourceOfTruth(isShared: true) == "Firestore")
        #expect(CollaborationArchitecturePolicy.sourceOfTruth(isShared: false) == "SwiftData")
    }

    @Test("Invite DTO uses bearer token as document ID; no raw token field")
    func inviteBearerDocumentModel() throws {
        let invite = FirebaseProjectInviteDTO(
            projectId: UUID().uuidString,
            createdBy: "owner-uid",
            role: .member,
            projectTitle: "Shared",
            inviterDisplayName: "Anas",
            createdAt: Date(timeIntervalSince1970: 1_699_000_000),
            expiresAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let json = try encoder.encode(invite)
        let object = try JSONSerialization.jsonObject(with: json) as? [String: Any]
        #expect(object?.keys.contains("token") == false)
        #expect(object?.keys.contains("tokenHash") == false)
        #expect(object?["createdBy"] as? String == "owner-uid")
        #expect(FirebaseInviteSecurityPolicy.bearerTokenIsDocumentID == true)
        #expect(FirebaseInviteSecurityPolicy.collectionName == "projectInvites")
    }

    @Test("Firebase DTO encoding/decoding")
    func dtoRoundTrip() throws {
        let projectID = UUID()
        let ownerID = "firebase-owner-123"
        let project = FirebaseProjectDTO(
            id: projectID,
            ownerId: ownerID,
            title: "Shared",
            description: "Notes",
            color: "#5B8DEF",
            position: 1000,
            memberIds: [ownerID],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let projectData = try encoder.encode(project)
        let decodedProject = try decoder.decode(FirebaseProjectDTO.self, from: projectData)
        #expect(decodedProject == project)

        let task = FirebaseTaskDTO(
            id: UUID(),
            projectId: projectID,
            title: "Task",
            statusRaw: TaskStatus.todo.rawValue,
            priorityRaw: TaskPriority.none.rawValue,
            position: 1000,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let taskData = try encoder.encode(task)
        let decodedTask = try decoder.decode(FirebaseTaskDTO.self, from: taskData)
        #expect(decodedTask == task)
    }

    @Test("Local-only collaboration backend handles unconfigured state safely")
    func localOnlyBackend() async throws {
        let backend = LocalOnlyCollaborationBackend()
        #expect(backend.isConfigured == false)
        #expect(try await backend.currentSession() == nil)
    }

    @Test("Membership document is the sole authorization authority")
    func membershipAuthorityPolicy() {
        #expect(CollaborationMembershipPolicy.membershipDocumentIsAuthority == true)
        #expect(CollaborationMembershipPolicy.memberIdsGrantsAuthorization == false)
    }

    @Test("memberIds is a discovery field only, not an authorization proof")
    func memberIdsDiscoveryOnly() {
        #expect(CollaborationMembershipPolicy.memberIdsQueryPattern.contains("arrayContains"))
        #expect(CollaborationMembershipPolicy.membershipDocumentPathPattern.contains("/members/"))
        #expect(CollaborationMembershipPolicy.divergenceFailureBehavior.contains("Membership document"))
    }
}
