import Foundation
import FirebaseCore
import TodoshiCore

enum FirebaseBootstrap {
    /// Authoritative configured state — true only after `FirebaseApp.configure()` succeeds.
    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    /// Device Debug never auto-enables emulators. Only set true for explicit emulator launches.
    #if DEBUG
    private(set) static var usingAuthEmulator = false
    private(set) static var usingFirestoreEmulator = false
    #endif

    /// Configures Firebase once when the real `GoogleService-Info.plist` is bundled with the app.
    /// Safe to call at launch; no-op when the plist is absent or Firebase is already configured.
    static func configureIfAvailable() {
        guard FirebaseApp.app() == nil else {
            #if DEBUG
            logFirebaseConfig()
            #endif
            return
        }

        guard FirebaseConfiguration.hasPlistInBundle else {
            #if DEBUG
            TodoshiDiagnostics.note("[Firebase] configuration file not found in app bundle")
            #endif
            return
        }

        #if DEBUG
        TodoshiDiagnostics.note("[Firebase] configuration file found")
        #endif

        FirebaseApp.configure()

        #if DEBUG
        if FirebaseApp.app() != nil {
            TodoshiDiagnostics.note("[Firebase] FirebaseApp configured successfully")
        }
        logFirebaseConfig()
        #endif
    }

    #if DEBUG
    private static func logFirebaseConfig() {
        let projectID = FirebaseApp.app()?.options.projectID ?? "nil"
        TodoshiDiagnostics.note("[FirebaseConfig] projectID=\(projectID)")
        TodoshiDiagnostics.note("[FirebaseConfig] usingAuthEmulator=\(usingAuthEmulator)")
        TodoshiDiagnostics.note("[FirebaseConfig] usingFirestoreEmulator=\(usingFirestoreEmulator)")
    }
    #endif
}
