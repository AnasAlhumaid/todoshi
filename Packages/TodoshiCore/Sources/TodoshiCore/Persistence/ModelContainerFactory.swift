import Foundation
import SwiftData

public enum ModelContainerFactory {
    public enum StoreKind: Sendable {
        /// Production-like App Group store (shared with widgets once configured).
        case appGroup
        /// Explicit file URL (tests that need disk).
        case file(URL)
        /// Ephemeral store for unit tests and previews.
        case inMemory
    }

    public static func makeContainer(kind: StoreKind) throws -> ModelContainer {
        let schema = NexusSchema.makeSchema()

        switch kind {
        case .appGroup:
            guard let storeURL = AppGroupConstants.storeURL else {
                throw ModelContainerError.appGroupUnavailable
            }
            let configuration = ModelConfiguration(
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            return try openAppGroupStore(schema: schema, configuration: configuration, storeURL: storeURL)
        case .file(let url):
            let configuration = ModelConfiguration(
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: NexusSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        case .inMemory:
            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            return try ModelContainer(
                for: schema,
                migrationPlan: NexusSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        }
    }

    /// Opens the App Group store; may reset only when `StoreResetPolicy` allows.
    private static func openAppGroupStore(
        schema: Schema,
        configuration: ModelConfiguration,
        storeURL: URL
    ) throws -> ModelContainer {
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: NexusSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            guard StoreResetPolicy.allowsDestructiveAppGroupReset else {
                throw ModelContainerError.appGroupOpenFailed(underlying: String(describing: error))
            }
            destroyStoreFiles(at: storeURL)
            return try ModelContainer(
                for: schema,
                migrationPlan: NexusSchemaMigrationPlan.self,
                configurations: [configuration]
            )
        }
    }

    private static func destroyStoreFiles(at storeURL: URL) {
        try? FileManager.default.removeItem(at: storeURL)
        let related = [
            storeURL.appendingPathExtension("shm"),
            storeURL.appendingPathExtension("wal"),
            URL(fileURLWithPath: storeURL.path + "-shm"),
            URL(fileURLWithPath: storeURL.path + "-wal")
        ]
        for url in related {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Production container: prefers App Group, falls back to default application support store
    /// when the group container is unavailable (e.g. simulator without entitlements applied).
    public static func makeProductionContainer() throws -> ModelContainer {
        if AppGroupConstants.storeURL != nil {
            do {
                return try makeContainer(kind: .appGroup)
            } catch let error as ModelContainerError {
                switch error {
                case .appGroupOpenFailed:
                    throw error
                case .appGroupUnavailable:
                    break
                }
            } catch {
                // DEBUG reset success path variants: fall back to local application support.
            }
        }

        let schema = NexusSchema.makeSchema()
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: NexusSchemaMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

public enum ModelContainerError: Error, Equatable {
    case appGroupUnavailable
    case appGroupOpenFailed(underlying: String)
}
