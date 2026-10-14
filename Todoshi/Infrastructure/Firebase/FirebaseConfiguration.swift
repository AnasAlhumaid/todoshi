import Foundation

enum FirebaseConfiguration {
    /// Whether `GoogleService-Info.plist` is present in the main app bundle at runtime.
    static var hasPlistInBundle: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }
}
