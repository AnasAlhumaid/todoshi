import Foundation
import SwiftData

@Model
public final class TaskResource {
    @Attribute(.unique) public var id: UUID
    public var kindRaw: String
    public var title: String
    public var body: String?
    public var externalURLString: String?
    public var relativeFilePath: String?
    public var originalFileName: String?
    public var mimeType: String?
    public var fileSize: Int64?
    public var languageIdentifier: String?
    public var position: Double
    public var createdAt: Date
    public var updatedAt: Date

    public var task: TaskItem?

    public var kind: TaskResourceKind {
        get { TaskResourceKind.parse(kindRaw) ?? .file }
        set { kindRaw = newValue.rawValue }
    }

    public init(
        id: UUID = UUID(),
        kind: TaskResourceKind,
        title: String = "",
        body: String? = nil,
        externalURLString: String? = nil,
        relativeFilePath: String? = nil,
        originalFileName: String? = nil,
        mimeType: String? = nil,
        fileSize: Int64? = nil,
        languageIdentifier: String? = nil,
        position: Double = FractionalPosition.initial(),
        createdAt: Date = .now,
        updatedAt: Date = .now,
        task: TaskItem? = nil
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.title = title
        self.body = body
        self.externalURLString = externalURLString
        self.relativeFilePath = relativeFilePath
        self.originalFileName = originalFileName
        self.mimeType = mimeType
        self.fileSize = fileSize
        self.languageIdentifier = languageIdentifier
        self.position = position
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.task = task
    }
}
