import Foundation

public protocol CollaborationBackend: Sendable {
    var isConfigured: Bool { get }

    func currentSession() async throws -> CollaborationSession?
}

/// Default backend used when Firebase is unavailable. Personal/local features continue unchanged.
public struct LocalOnlyCollaborationBackend: CollaborationBackend {
    public init() {}

    public var isConfigured: Bool { false }

    public func currentSession() async throws -> CollaborationSession? {
        nil
    }
}
