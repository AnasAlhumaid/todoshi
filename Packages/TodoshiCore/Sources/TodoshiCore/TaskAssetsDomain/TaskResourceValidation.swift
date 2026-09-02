import Foundation

/// Pure validation for task resources (no filesystem or networking).
public enum TaskResourceValidation: Sendable {
    public static let maxTitleLength = 120
    public static let maxBodyLength = 100_000

    public enum Issue: Equatable, Sendable {
        case emptyContent
        case emptyBody
        case titleTooLong
        case bodyTooLong
        case invalidURL
        case unsupportedURLScheme
        case missingFilePath
        case emptyFile
        case fileTooLarge
    }

    public static let allowedURLSchemes: Set<String> = ["https", "http", "mailto"]

    public static func trimTitle(_ raw: String) -> String {
        SearchText.normalizeQuery(raw)
    }

    /// Preserve internal whitespace/newlines; only trim ends.
    public static func normalizeBody(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public static func issue(title: String) -> Issue? {
        if title.count > maxTitleLength { return .titleTooLong }
        return nil
    }

    public static func issueForLink(title: String, urlString: String) -> Issue? {
        if let t = issue(title: trimTitle(title)) { return t }
        return linkIssue(urlString: urlString)
    }

    public static func linkIssue(urlString: String) -> Issue? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyContent }
        let schemePart = trimmed.split(separator: ":", maxSplits: 1).first.map { String($0).lowercased() }
        if let schemePart, schemePart == "javascript" || schemePart == "data" || schemePart == "file" {
            return .unsupportedURLScheme
        }
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            return .invalidURL
        }
        if !allowedURLSchemes.contains(scheme) {
            return .unsupportedURLScheme
        }
        if scheme == "mailto" {
            return nil
        }
        guard url.host != nil else {
            return .invalidURL
        }
        return nil
    }

    public static func issueForTextBody(title: String, body: String) -> Issue? {
        if let t = issue(title: trimTitle(title)) { return t }
        let normalized = normalizeBody(body)
        if normalized.isEmpty { return .emptyBody }
        if normalized.count > maxBodyLength { return .bodyTooLong }
        return nil
    }

    public static func issueForImportedFile(
        title: String,
        relativePath: String?,
        fileSize: Int64?
    ) -> Issue? {
        if let t = issue(title: trimTitle(title)) { return t }
        guard let relativePath, !relativePath.isEmpty else { return .missingFilePath }
        // Ensure no traversal pattern is embedded before resolve.
        if relativePath.contains("..") || relativePath.hasPrefix("/") {
            return .missingFilePath
        }
        if let fileSize {
            if fileSize <= 0 { return .emptyFile }
            if fileSize > TaskResourceFilePath.maxFileBytes { return .fileTooLarge }
        }
        return nil
    }

    public static func issueForFileSize(_ size: Int64) -> Issue? {
        if size <= 0 { return .emptyFile }
        if size > TaskResourceFilePath.maxFileBytes { return .fileTooLarge }
        return nil
    }

    public static func message(for issue: Issue, locale: Locale = .autoupdatingCurrent) -> String {
        switch issue {
        case .emptyContent, .emptyBody:
            return NexusL10n.tr("resource.empty", locale: locale)
        case .titleTooLong:
            return NexusL10n.tr("resource.titleTooLong", locale: locale)
        case .bodyTooLong:
            return NexusL10n.tr("resource.bodyTooLong", locale: locale)
        case .invalidURL, .unsupportedURLScheme:
            return NexusL10n.tr("resource.unsupportedURL", locale: locale)
        case .missingFilePath:
            return NexusL10n.tr("resource.fileUnavailable", locale: locale)
        case .emptyFile:
            return NexusL10n.tr("resource.emptyFile", locale: locale)
        case .fileTooLarge:
            return NexusL10n.tr("resource.fileTooLarge", locale: locale)
        }
    }

    public static func displayTitle(for resource: TaskResource) -> String {
        let trimmed = trimTitle(resource.title)
        if !trimmed.isEmpty { return trimmed }
        if let name = resource.originalFileName, !name.isEmpty { return name }
        if let url = resource.externalURLString.flatMap(URL.init(string:)),
           let host = url.host, !host.isEmpty {
            return host
        }
        if let body = resource.body, !normalizeBody(body).isEmpty {
            let line = body.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true).first.map(String.init) ?? body
            return String(line.prefix(80))
        }
        return resource.kind.displayName
    }

    public static func curatedLanguages() -> [String] {
        [
            "Swift",
            "JavaScript",
            "TypeScript",
            "Python",
            "Kotlin",
            "SQL",
            "Shell",
            "JSON",
            "Plain Text"
        ]
    }
}
