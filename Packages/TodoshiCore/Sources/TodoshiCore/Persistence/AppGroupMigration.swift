import Foundation

/// One-time migration from the legacy Nexus App Group container and preference namespaces.
public enum AppGroupMigration: Sendable {
    private static let migrationCompletedKey = "todoshi.migration.appGroup.completed"

    public static func migrateIfNeeded() {
        guard let suite = UserDefaults(suiteName: AppGroupConstants.suiteName) else { return }
        guard suite.bool(forKey: migrationCompletedKey) == false else {
            AppLanguageStore.migrateIfNeeded(in: suite)
            return
        }

        migrateStoreIfNeeded()
        migrateSharedPreferencesIfNeeded(from: suite)
        migrateStandardPreferencesIfNeeded()
        AppLanguageStore.migrateIfNeeded(in: suite)

        suite.set(true, forKey: migrationCompletedKey)
    }

    private static func migrateStoreIfNeeded() {
        guard let destination = AppGroupConstants.storeURL else { return }
        guard FileManager.default.fileExists(atPath: destination.path) == false else { return }
        guard let source = AppGroupConstants.legacyStoreURL,
              FileManager.default.fileExists(atPath: source.path) else { return }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.copyItem(at: source, to: destination)
            for suffix in ["-shm", "-wal"] {
                let legacySidecar = URL(fileURLWithPath: source.path + suffix)
                let destinationSidecar = URL(fileURLWithPath: destination.path + suffix)
                if FileManager.default.fileExists(atPath: legacySidecar.path) {
                    try? FileManager.default.copyItem(at: legacySidecar, to: destinationSidecar)
                }
            }
        } catch {
            // Preserve local-only launch; production container may fall back to app support store.
        }
    }

    private static func migrateSharedPreferencesIfNeeded(from destinationSuite: UserDefaults) {
        guard let legacySuite = UserDefaults(suiteName: AppGroupConstants.legacySuiteName) else { return }

        let keyMappings: [(legacy: String, current: String)] = [
            ("nexus.widget.project.override.", "todoshi.widget.project.override."),
            ("nexus.quickAdd.lastProjectID", "todoshi.quickAdd.lastProjectID"),
            ("nexus.quickAdd.showsOptionalFields", "todoshi.quickAdd.showsOptionalFields"),
            ("nexus.calendar.mode", "todoshi.calendar.mode"),
            ("nexus.calendar.showCompleted", "todoshi.calendar.showCompleted"),
            ("nexus.search.recentTerms", "todoshi.search.recentTerms"),
            ("nexus.search.includeArchived", "todoshi.search.includeArchived"),
            ("nexus.dailySummary.enabled", "todoshi.dailySummary.enabled"),
            ("nexus.dailySummary.hour", "todoshi.dailySummary.hour"),
            ("nexus.dailySummary.minute", "todoshi.dailySummary.minute"),
            ("nexus.projectTaskDisplayMode", "todoshi.projectTaskDisplayMode")
        ]

        for key in legacySuite.dictionaryRepresentation().keys {
            if key.hasPrefix("nexus.widget.project.override."),
               let value = legacySuite.string(forKey: key) {
                let suffix = key.replacingOccurrences(of: "nexus.widget.project.override.", with: "")
                let newKey = "todoshi.widget.project.override." + suffix
                if destinationSuite.string(forKey: newKey) == nil {
                    destinationSuite.set(value, forKey: newKey)
                }
                continue
            }

            if let mapping = keyMappings.first(where: { $0.legacy == key }),
               destinationSuite.object(forKey: mapping.current) == nil,
               let value = legacySuite.object(forKey: key) {
                destinationSuite.set(value, forKey: mapping.current)
            }
        }
    }

    private static func migrateStandardPreferencesIfNeeded() {
        let defaults = UserDefaults.standard
        let keyMappings: [(legacy: String, current: String)] = [
            ("nexus.dailySummary.enabled", DailySummaryStore.enabledKey),
            ("nexus.dailySummary.hour", DailySummaryStore.hourKey),
            ("nexus.dailySummary.minute", DailySummaryStore.minuteKey)
        ]
        for mapping in keyMappings {
            guard defaults.object(forKey: mapping.current) == nil,
                  let value = defaults.object(forKey: mapping.legacy) else { continue }
            defaults.set(value, forKey: mapping.current)
        }
    }
}
