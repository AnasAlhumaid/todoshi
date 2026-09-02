import Foundation
import UniformTypeIdentifiers

/// Pure path and size policy for managed task resource files.
public enum TaskResourceFilePath: Sendable {
    public static let maxFileBytes: Int64 = 25 * 1024 * 1024
    public static let resourcesDirectoryName = "Resources"

    /// Relative path: `<taskUUID>/<resourceUUID>.<ext>`
    public static func relativePath(
        taskID: UUID,
        resourceID: UUID,
        fileExtension: String
    ) -> String {
        let ext = sanitizeExtension(fileExtension)
        if ext.isEmpty {
            return "\(taskID.uuidString)/\(resourceID.uuidString)"
        }
        return "\(taskID.uuidString)/\(resourceID.uuidString).\(ext)"
    }

    public static func sanitizeExtension(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
            .lowercased()
        let allowed = CharacterSet.alphanumerics
        let filtered = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        return String(filtered.prefix(16))
    }

    public static func sanitizeDisplayFileName(_ raw: String) -> String {
        let base = (raw as NSString).lastPathComponent
        let cleaned = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "file" }
        return String(cleaned.prefix(200))
    }

    public static func resolveFileURL(root: URL, relative: String) throws -> URL {
        let raw = relative.trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty
            || raw.hasPrefix("/")
            || raw.hasPrefix("~")
            || raw.contains("..")
            || raw.contains(":")
            || raw.contains("\\") {
            throw TaskResourceStorageError.pathTraversal
        }
        let normalized = raw.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalized.isEmpty {
            throw TaskResourceStorageError.pathTraversal
        }
        let resolved = root.appendingPathComponent(normalized, isDirectory: false).standardizedFileURL
        let rootStandard = root.standardizedFileURL
        let rootPath = rootStandard.path
        let resolvedPath = resolved.path
        guard resolvedPath == rootPath || resolvedPath.hasPrefix(rootPath + "/") else {
            throw TaskResourceStorageError.pathTraversal
        }
        return resolved
    }

    public static func defaultApplicationSupportRoot() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport
            .appendingPathComponent("Nexus", isDirectory: true)
            .appendingPathComponent(resourcesDirectoryName, isDirectory: true)
    }
}

public enum TaskResourceStorageError: Error, Equatable, Sendable {
    case pathTraversal
    case fileTooLarge
    case emptyFile
    case copyFailed
    case missingSource
    case managedRootUnavailable
}

public struct ImportedTaskFile: Hashable, Sendable {
    public let relativePath: String
    public let originalFileName: String
    public let mimeType: String?
    public let fileSize: Int64
    public let inferredKind: TaskResourceKind

    public init(
        relativePath: String,
        originalFileName: String,
        mimeType: String?,
        fileSize: Int64,
        inferredKind: TaskResourceKind
    ) {
        self.relativePath = relativePath
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.inferredKind = inferredKind
    }
}

public protocol TaskResourceFileStoring: Sendable {
    func importFile(
        from sourceURL: URL,
        taskID: UUID,
        resourceID: UUID
    ) throws -> ImportedTaskFile

    func fileURL(for relativePath: String) throws -> URL
    func deleteFile(at relativePath: String) throws
    func deleteAllFiles(for taskID: UUID) throws
    func fileExists(at relativePath: String) -> Bool
    func deleteIfExists(at relativePath: String)
    func listManagedRelativePaths() throws -> [String]
    func rehomeTaskDirectory(from sourceTaskID: UUID, to destTaskID: UUID) throws
}

/// Resolves the active file store (overridable in tests; shared Application Support in production).
public enum TaskResourceFileAccess {
    nonisolated(unsafe) public static var current: any TaskResourceFileStoring = TaskResourceFileStore.shared

    public static func resetToShared() {
        current = TaskResourceFileStore.shared
    }
}

/// File store with injectable root (Application Support production; temp dirs in tests).
public final class TaskResourceFileStore: TaskResourceFileStoring, @unchecked Sendable {
    public let rootURL: URL
    private let fileManager: FileManager

    public static let shared: TaskResourceFileStore = {
        let root = (try? TaskResourceFilePath.defaultApplicationSupportRoot())
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("NexusResources", isDirectory: true)
        return TaskResourceFileStore(rootURL: root)
    }()

    public init(rootURL: URL, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.fileManager = fileManager
    }

    public func ensureRootExists() throws {
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    public func importFile(
        from sourceURL: URL,
        taskID: UUID,
        resourceID: UUID
    ) throws -> ImportedTaskFile {
        try ensureRootExists()

        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if accessed { sourceURL.stopAccessingSecurityScopedResource() }
        }

        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw TaskResourceStorageError.missingSource
        }

        let values = try sourceURL.resourceValues(forKeys: [
            .fileSizeKey,
            .contentTypeKey,
            .nameKey
        ])
        let size = Int64(values.fileSize ?? 0)
        if size <= 0 {
            throw TaskResourceStorageError.emptyFile
        }
        if size > TaskResourceFilePath.maxFileBytes {
            throw TaskResourceStorageError.fileTooLarge
        }

        let originalName = TaskResourceFilePath.sanitizeDisplayFileName(
            values.name ?? sourceURL.lastPathComponent
        )
        let ext = TaskResourceFilePath.sanitizeExtension(sourceURL.pathExtension)
        let relative = TaskResourceFilePath.relativePath(
            taskID: taskID,
            resourceID: resourceID,
            fileExtension: ext
        )
        let destination = try TaskResourceFilePath.resolveFileURL(root: rootURL, relative: relative)
        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } catch {
            throw TaskResourceStorageError.copyFailed
        }

        let mime = values.contentType?.preferredMIMEType
            ?? mimeType(forExtension: ext)
        let kind = Self.inferredKind(mimeType: mime, fileExtension: ext)

        return ImportedTaskFile(
            relativePath: relative,
            originalFileName: originalName,
            mimeType: mime,
            fileSize: size,
            inferredKind: kind
        )
    }

    public func fileURL(for relativePath: String) throws -> URL {
        try TaskResourceFilePath.resolveFileURL(root: rootURL, relative: relativePath)
    }

    public func deleteFile(at relativePath: String) throws {
        let url = try fileURL(for: relativePath)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        // Remove empty task directory when possible
        let parent = url.deletingLastPathComponent()
        if let contents = try? fileManager.contentsOfDirectory(atPath: parent.path), contents.isEmpty {
            try? fileManager.removeItem(at: parent)
        }
    }

    public func deleteIfExists(at relativePath: String) {
        try? deleteFile(at: relativePath)
    }

    public func deleteAllFiles(for taskID: UUID) throws {
        let dir = rootURL.appendingPathComponent(taskID.uuidString, isDirectory: true)
        if fileManager.fileExists(atPath: dir.path) {
            try fileManager.removeItem(at: dir)
        }
    }

    /// Moves an entire task file folder after the owning task id is known.
    public func rehomeTaskDirectory(from sourceTaskID: UUID, to destTaskID: UUID) throws {
        guard sourceTaskID != destTaskID else { return }
        try ensureRootExists()
        let source = rootURL.appendingPathComponent(sourceTaskID.uuidString, isDirectory: true)
        let dest = rootURL.appendingPathComponent(destTaskID.uuidString, isDirectory: true)
        guard fileManager.fileExists(atPath: source.path) else { return }
        if fileManager.fileExists(atPath: dest.path) {
            // Merge files into dest
            let files = try fileManager.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
            try fileManager.createDirectory(at: dest, withIntermediateDirectories: true)
            for file in files {
                let target = dest.appendingPathComponent(file.lastPathComponent)
                if fileManager.fileExists(atPath: target.path) {
                    try fileManager.removeItem(at: target)
                }
                try fileManager.moveItem(at: file, to: target)
            }
            try? fileManager.removeItem(at: source)
        } else {
            try fileManager.moveItem(at: source, to: dest)
        }
    }

    public static func rehomeRelativePath(_ path: String, from sourceTaskID: UUID, to destTaskID: UUID) -> String {
        let prefix = sourceTaskID.uuidString + "/"
        if path.hasPrefix(prefix) {
            return destTaskID.uuidString + "/" + String(path.dropFirst(prefix.count))
        }
        return path
    }

    public func fileExists(at relativePath: String) -> Bool {
        guard let url = try? fileURL(for: relativePath) else { return false }
        return fileManager.fileExists(atPath: url.path)
    }

    public func listManagedRelativePaths() throws -> [String] {
        try ensureRootExists()
        guard fileManager.fileExists(atPath: rootURL.path) else { return [] }
        var results: [String] = []
        let taskDirs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for taskDir in taskDirs {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: taskDir.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            let files = try fileManager.contentsOfDirectory(
                at: taskDir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for file in files {
                results.append("\(taskDir.lastPathComponent)/\(file.lastPathComponent)")
            }
        }
        return results
    }

    public static func inferredKind(mimeType: String?, fileExtension: String) -> TaskResourceKind {
        let mime = (mimeType ?? "").lowercased()
        let ext = fileExtension.lowercased()
        if mime.hasPrefix("image/") || ["png", "jpg", "jpeg", "gif", "heic", "webp", "tiff"].contains(ext) {
            return .image
        }
        if mime == "application/pdf" || ext == "pdf" {
            return .pdf
        }
        return .file
    }

    private func mimeType(forExtension ext: String) -> String? {
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "heic": return "image/heic"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        case "json": return "application/json"
        default: return nil
        }
    }
}
