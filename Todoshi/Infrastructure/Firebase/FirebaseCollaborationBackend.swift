import Foundation
import FirebaseAuth
import TodoshiCore

final class FirebaseCollaborationBackend: CollaborationBackend, @unchecked Sendable {
    static let shared = FirebaseCollaborationBackend()

    private init() {}

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    func currentSession() async throws -> CollaborationSession? {
        guard isConfigured else {
            throw CollaborationError.notConfigured
        }
        return await MainActor.run {
            FirebaseAuthService.shared.currentSession()
        }
    }
}
