import Foundation

/// Controls whether an unreadable on-disk App Group store may be deleted and recreated.
///
/// - DEBUG: allowed (pre-release ergonomics when the schema changes).
/// - RELEASE: never allowed — failures surface so user data is not silently wiped.
public enum StoreResetPolicy: Sendable {
    public static var allowsDestructiveAppGroupReset: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}
