import Foundation
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Security
import TodoshiCore

/// Transactional Todoshi ID provisioning against Firestore uniqueness claims.
final class TodoshiIdentityService: Sendable {
    static let shared = TodoshiIdentityService()

    private let db: Firestore
    private let maxAttempts = 12

    init(db: Firestore = Firestore.firestore()) {
        self.db = db
    }

    var isConfigured: Bool {
        FirebaseBootstrap.isConfigured
    }

    func ensureProvisioned(uid: String) async throws -> String {
        guard isConfigured else {
            throw CollaborationError.notConfigured
        }
        guard let authUID = Auth.auth().currentUser?.uid, authUID == uid else {
            throw CollaborationError.notAuthenticated
        }

        logFirebaseProjectIfNeeded()
        logPhase("ensure started")

        if let existing = try await loadCanonicalTodoshiID(uid: uid, preferServer: true) {
            TodoshiIdentityCache.store(existing, for: uid)
            logPhase("canonical identity loaded")
            return existing
        }

        for attempt in 1 ... maxAttempts {
            let candidate = try generateCandidate()
            logPhase("transaction started")
            do {
                if let resolved = try await provisionTransaction(uid: uid, candidate: candidate) {
                    TodoshiIdentityCache.store(resolved, for: uid)
                    logPhase("transaction succeeded")
                    if let canonical = try await loadCanonicalTodoshiID(uid: uid, preferServer: true) {
                        TodoshiIdentityCache.store(canonical, for: uid)
                        logPhase("canonical identity loaded")
                        return canonical
                    }
                    return resolved
                }
                logPhase("transaction retry attempt=\(attempt)")
            } catch {
                logProvisionFailure(error, phase: "transaction")
                throw error
            }
        }

        let exhausted = NSError(
            domain: FirestoreErrorPolicy.errorDomain,
            code: FirestoreErrorPolicy.failedPreconditionCode
        )
        logProvisionFailure(exhausted, phase: "exhausted-retries")
        throw CollaborationError.identityProvisioningFailed
    }

    private func loadCanonicalTodoshiID(uid: String, preferServer: Bool) async throws -> String? {
        let ref = db.collection("users").document(uid)
        let snapshot: DocumentSnapshot
        if preferServer {
            snapshot = try await ref.getDocument(source: .server)
        } else {
            snapshot = try await ref.getDocument()
        }
        return TodoshiIdentityProvisioningPolicy.normalized(snapshot.data()?["todoshiId"] as? String)
    }

    private func generateCandidate() throws -> String {
        var bytes = [UInt8](repeating: 0, count: TodoshiIDPolicy.randomByteCount)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw CollaborationError.identityProvisioningFailed
        }
        return TodoshiIDPolicy.generate(randomBytes: bytes)
    }

    private func provisionTransaction(uid: String, candidate: String) async throws -> String? {
        let resolved = try await db.runTransaction { transaction, errorPointer -> Any? in
            do {
                let userRef = self.db.collection("users").document(uid)
                let claimRef = self.db.collection("todoshiIds").document(candidate)
                let publicRef = self.db.collection("publicIdentities").document(uid)

                // Firestore requires every read to complete before any write in a transaction.
                let userSnapshot = try transaction.getDocument(userRef)
                let claimSnapshot = try transaction.getDocument(claimRef)
                let publicSnapshot = try transaction.getDocument(publicRef)

                let decision = TodoshiIdentityProvisioningPolicy.decide(
                    existingUserTodoshiId: userSnapshot.data()?["todoshiId"] as? String,
                    candidate: candidate,
                    claimExists: claimSnapshot.exists,
                    claimUID: claimSnapshot.data()?["uid"] as? String,
                    actingUID: uid
                )

                switch decision {
                case .useExisting(let existing):
                    return existing
                case .retryCollision:
                    return nil
                case .commitCandidate(let id):
                    transaction.setData(
                        [
                            "todoshiId": id,
                            "updatedAt": FieldValue.serverTimestamp(),
                        ],
                        forDocument: userRef,
                        merge: true
                    )

                    if !claimSnapshot.exists {
                        transaction.setData(
                            [
                                "uid": uid,
                                "createdAt": FieldValue.serverTimestamp(),
                            ],
                            forDocument: claimRef
                        )
                    }

                    if !publicSnapshot.exists {
                        transaction.setData(
                            [
                                "userId": uid,
                                "todoshiId": id,
                                "createdAt": FieldValue.serverTimestamp(),
                            ],
                            forDocument: publicRef
                        )
                    }

                    return id
                }
            } catch {
                errorPointer?.pointee = error as NSError
                return nil
            }
        }
        return resolved as? String
    }

    private func logFirebaseProjectIfNeeded() {
        #if DEBUG
        let projectID = FirebaseApp.app()?.options.projectID ?? "unknown"
        TodoshiDiagnostics.note("[TodoshiID] firebase project configured projectId=\(projectID)")
        #endif
    }

    private func logPhase(_ phase: String) {
        #if DEBUG
        TodoshiDiagnostics.note("[TodoshiID] \(phase)")
        #endif
    }

    #if DEBUG
    private func logProvisionFailure(_ error: Error, phase: String) {
        let info = FirestoreErrorPolicy.debugInfo(for: error)
        TodoshiDiagnostics.note("[TodoshiID] provision failed")
        TodoshiDiagnostics.note("phase=\(phase)")
        TodoshiDiagnostics.note("domain=\(info.domain)")
        TodoshiDiagnostics.note("code=\(info.code)")
        TodoshiDiagnostics.note("classification=\(info.classification.rawValue)")
    }
    #else
    private func logProvisionFailure(_ error: Error, phase: String) {}
    #endif
}
