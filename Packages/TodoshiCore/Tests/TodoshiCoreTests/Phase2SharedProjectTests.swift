import Foundation
import Testing
import TodoshiCore

@Suite("Phase 2 Shared Project Bootstrap")
struct Phase2SharedProjectTests {
    @Test("ProjectSharingMode Codable/raw mapping")
    func sharingModeCodable() throws {
        for mode in ProjectSharingMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(ProjectSharingMode.self, from: data)
            #expect(decoded == mode)
            #expect(ProjectSharingMode(rawValue: mode.rawValue) == mode)
        }
    }

    @Test("Existing projects default to personal")
    func existingDefaultsPersonal() throws {
        let project = Project(name: "Local")
        #expect(project.sharingMode == .personal)
        #expect(project.remoteProjectID == nil)
        #expect(project.sharedAt == nil)
        #expect(project.isShared == false)
        #expect(
            SharedProjectLocalStatePolicy.isValidSharedMetadata(
                sharingMode: project.sharingMode,
                remoteProjectID: project.remoteProjectID,
                sharedAt: project.sharedAt,
                projectID: project.id
            )
        )
    }

    @Test("Nil sharingModeRaw maps to personal")
    func nilRawIsPersonal() {
        let project = Project(name: "Legacy")
        project.sharingModeRaw = nil
        #expect(project.sharingMode == .personal)
        #expect(project.isShared == false)
    }

    @Test("Remote ID equals local UUID policy")
    func remoteIDEqualsLocalUUID() {
        let id = UUID()
        #expect(SharedProjectRemoteIDPolicy.documentID(for: id) == id.uuidString)
        #expect(SharedProjectRemoteIDPolicy.matchesLocalProject(remoteID: id.uuidString, projectID: id))
        #expect(!SharedProjectRemoteIDPolicy.matchesLocalProject(remoteID: UUID().uuidString, projectID: id))
    }

    @Test("Shared metadata validation")
    func sharedMetadataValidation() {
        let id = UUID()
        let personal = SharedProjectLocalStatePolicy.personalDefault()
        #expect(
            SharedProjectLocalStatePolicy.isValidSharedMetadata(
                sharingMode: personal.sharingMode,
                remoteProjectID: personal.remoteProjectID,
                sharedAt: personal.sharedAt,
                projectID: id
            )
        )

        let shared = SharedProjectLocalStatePolicy.afterSuccessfulRemoteBootstrap(projectID: id)
        #expect(shared.sharingMode == .shared)
        #expect(shared.remoteProjectID == id.uuidString)
        #expect(shared.sharedAt != nil)
        #expect(
            SharedProjectLocalStatePolicy.isValidSharedMetadata(
                sharingMode: shared.sharingMode,
                remoteProjectID: shared.remoteProjectID,
                sharedAt: shared.sharedAt,
                projectID: id
            )
        )

        #expect(
            !SharedProjectLocalStatePolicy.isValidSharedMetadata(
                sharingMode: .shared,
                remoteProjectID: UUID().uuidString,
                sharedAt: .now,
                projectID: id
            )
        )
        #expect(
            !SharedProjectLocalStatePolicy.isValidSharedMetadata(
                sharingMode: .shared,
                remoteProjectID: id.uuidString,
                sharedAt: nil,
                projectID: id
            )
        )
    }

    @Test("Bootstrap local-state transition only after remote success")
    func localTransitionPolicy() {
        let id = UUID()
        let before = SharedProjectLocalStatePolicy.personalDefault()
        #expect(before.sharingMode == .personal)

        let after = SharedProjectLocalStatePolicy.afterSuccessfulRemoteBootstrap(projectID: id)
        #expect(after.sharingMode == .shared)
        #expect(after.remoteProjectID == SharedProjectRemoteIDPolicy.documentID(for: id))
    }

    @Test("Remote success / local failure recovery policy")
    func recoveryPolicy() {
        #expect(SharedProjectRecoveryPolicy.shouldDeleteRemoteOnLocalSaveFailure == false)
        #expect(
            SharedProjectRecoveryPolicy.shouldRetryBootstrap(
                localSharingMode: .personal,
                remoteBootstrapSucceeded: true
            )
        )
        #expect(
            !SharedProjectRecoveryPolicy.shouldRetryBootstrap(
                localSharingMode: .shared,
                remoteBootstrapSucceeded: true
            )
        )
    }

    @Test("Shared indicator accessibility")
    func sharedIndicatorA11y() {
        #expect(SharedProjectPresentation.indicatorSystemImage == "person.2")
        let en = SharedProjectPresentation.accessibilityLabel(locale: Locale(identifier: "en"))
        let ar = SharedProjectPresentation.accessibilityLabel(locale: Locale(identifier: "ar"))
        #expect(en == "Shared project")
        #expect(ar == "مشروع مشترك")
    }

    @Test("Owner role presentation")
    func ownerRoleLabel() {
        #expect(
            SharedProjectPresentation.memberRoleLabel(.owner, locale: Locale(identifier: "en"))
                == "Owner"
        )
        #expect(
            SharedProjectPresentation.memberRoleLabel(.owner, locale: Locale(identifier: "ar"))
                == "المالك"
        )
    }

    @Test("Bootstrap input validation")
    func inputValidation() {
        let id = UUID().uuidString
        let ok = SharedProjectBootstrapInputValidation.validate(
            projectID: id,
            title: "  Roadmap  ",
            description: " notes ",
            color: "#5b8def"
        )
        guard case .success(let values) = ok else {
            Issue.record("Expected success")
            return
        }
        #expect(values.0.uuidString == id)
        #expect(values.1 == "Roadmap")
        #expect(values.2 == "notes")
        #expect(values.3 == "#5B8DEF")

        #expect(
            {
                if case .failure(.invalidProjectID) = SharedProjectBootstrapInputValidation.validate(
                    projectID: "bad",
                    title: "X",
                    description: nil,
                    color: nil
                ) { return true }
                return false
            }()
        )
        #expect(
            {
                if case .failure(.emptyTitle) = SharedProjectBootstrapInputValidation.validate(
                    projectID: id,
                    title: "   ",
                    description: nil,
                    color: nil
                ) { return true }
                return false
            }()
        )
        #expect(
            {
                if case .failure(.invalidColor) = SharedProjectBootstrapInputValidation.validate(
                    projectID: id,
                    title: "X",
                    description: nil,
                    color: "#FFFFFF"
                ) { return true }
                return false
            }()
        )
    }

    @Test("Share conversion enabled via Firestore-only owner bootstrap")
    func shareConversionEnabled() {
        #expect(SharedProjectBootstrapPolicy.isShareConversionEnabled == true)
        #expect(SharedProjectBootstrapPolicy.requiredTrustedBackend.contains("Firestore"))
        #expect(!SharedProjectBootstrapPolicy.requiredTrustedBackend.contains("Cloud Function"))
    }

    @MainActor
    @Test("Home summary carries shared flag")
    func homeSharedFlag() {
        let personal = Project(name: "P")
        let shared = Project(
            name: "S",
            sharingMode: .shared,
            remoteProjectID: nil,
            sharedAt: .now,
            collaborationOwnerUID: "uid-home"
        )
        // Fix metadata for valid shared project
        shared.remoteProjectID = shared.id.uuidString

        let summaries = HomeMapping.projectSummaries(
            from: [personal, shared],
            collaborationUID: "uid-home"
        )
        #expect(summaries.first(where: { $0.id == personal.id })?.isShared == false)
        #expect(summaries.first(where: { $0.id == shared.id })?.isShared == true)
    }

    @Test("Schema current version is V8")
    func schemaV6() {
        #expect(TodoshiSchema.currentVersion == TodoshiSchemaV9.versionIdentifier)
    }

    @Test("Member DTO carries displayName snapshot")
    func memberDTODisplayName() throws {
        let dto = FirebaseProjectMemberDTO(
            userId: "uid-1",
            role: .owner,
            displayName: "Anas",
            joinedAt: .now
        )
        let data = try JSONEncoder().encode(dto)
        let decoded = try JSONDecoder().decode(FirebaseProjectMemberDTO.self, from: data)
        #expect(decoded.displayName == "Anas")
        #expect(decoded.role == .owner)
    }
}
