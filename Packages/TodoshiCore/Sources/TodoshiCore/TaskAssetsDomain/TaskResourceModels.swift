import Foundation

public enum TaskResourceImportState: Hashable, Sendable {
    case none
    /// File staged for save; delete on form cancel.
    case staged
    case persisted
}

/// Value-type draft — never holds live `TaskResource` models.
public struct TaskResourceDraft: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var persistedResourceID: UUID?
    public var kind: TaskResourceKind
    public var title: String
    public var body: String
    public var externalURLString: String
    public var relativeFilePath: String?
    public var originalFileName: String?
    public var mimeType: String?
    public var fileSize: Int64?
    public var languageIdentifier: String?
    public var position: Double
    public var importState: TaskResourceImportState

    public init(
        id: UUID = UUID(),
        persistedResourceID: UUID? = nil,
        kind: TaskResourceKind,
        title: String = "",
        body: String = "",
        externalURLString: String = "",
        relativeFilePath: String? = nil,
        originalFileName: String? = nil,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        languageIdentifier: String? = nil,
        position: Double = FractionalPosition.initial(),
        importState: TaskResourceImportState = .none
    ) {
        self.id = id
        self.persistedResourceID = persistedResourceID
        self.kind = kind
        self.title = title
        self.body = body
        self.externalURLString = externalURLString
        self.relativeFilePath = relativeFilePath
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.languageIdentifier = languageIdentifier
        self.position = position
        self.importState = importState
    }

    public init(resource: TaskResource) {
        self.id = resource.id
        self.persistedResourceID = resource.id
        self.kind = resource.kind
        self.title = resource.title
        self.body = resource.body ?? ""
        self.externalURLString = resource.externalURLString ?? ""
        self.relativeFilePath = resource.relativeFilePath
        self.originalFileName = resource.originalFileName
        self.mimeType = resource.mimeType
        self.fileSize = resource.fileSize
        self.languageIdentifier = resource.languageIdentifier
        self.position = resource.position
        self.importState = .persisted
    }

    public var validationIssue: TaskResourceValidation.Issue? {
        switch kind {
        case .link:
            return TaskResourceValidation.issueForLink(title: title, urlString: externalURLString)
        case .codeSnippet, .terminalCommand, .text:
            return TaskResourceValidation.issueForTextBody(title: title, body: body)
        case .file, .image, .pdf:
            return TaskResourceValidation.issueForImportedFile(
                title: title,
                relativePath: relativeFilePath,
                fileSize: fileSize
            )
        }
    }

    public var isValid: Bool {
        validationIssue == nil
    }

    public var displayTitle: String {
        let trimmed = TaskResourceValidation.trimTitle(title)
        if !trimmed.isEmpty { return trimmed }
        if let name = originalFileName, !name.isEmpty { return name }
        if let url = URL(string: externalURLString.trimmingCharacters(in: .whitespacesAndNewlines)),
           let host = url.host {
            return host
        }
        return kind.displayName
    }
}

public enum TaskResourceDraftBuilder: Sendable {
    public static func drafts(from resources: [TaskResource]) -> [TaskResourceDraft] {
        resources
            .sorted {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.createdAt < $1.createdAt
            }
            .map(TaskResourceDraft.init(resource:))
    }

    public static func ordered(_ drafts: [TaskResourceDraft]) -> [TaskResourceDraft] {
        drafts.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    public static func nextPosition(after drafts: [TaskResourceDraft]) -> Double {
        if let last = drafts.map(\.position).max() {
            return FractionalPosition.after(last)
        }
        return FractionalPosition.initial()
    }

    /// Drops invalid drafts; reassigns ascending positions.
    public static func preparedForSave(_ drafts: [TaskResourceDraft]) throws -> [TaskResourceDraft] {
        var prepared: [TaskResourceDraft] = []
        for draft in drafts {
            if let issue = draft.validationIssue {
                throw RepositoryValidationError.resourceInvalid(issue)
            }
            prepared.append(draft)
        }
        let positions = FractionalPosition.normalizedPositions(count: prepared.count)
        for index in prepared.indices {
            prepared[index].position = positions[index]
        }
        return prepared
    }
}

/// Staged paths for cleanup after cancel.
public enum TaskResourceDraftCleanup {
    public static func stagedRelativePaths(in drafts: [TaskResourceDraft]) -> [String] {
        drafts.compactMap { draft in
            guard draft.importState == .staged, let path = draft.relativeFilePath else { return nil }
            return path
        }
    }
}
