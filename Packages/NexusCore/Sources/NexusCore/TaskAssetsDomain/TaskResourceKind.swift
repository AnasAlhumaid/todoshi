import Foundation

/// Supported resource kinds attached to a `TaskItem`.
public enum TaskResourceKind: String, Codable, CaseIterable, Sendable {
    case link
    case file
    case image
    case pdf
    case codeSnippet
    case terminalCommand
    case text

    public var systemImage: String {
        switch self {
        case .link: return "link"
        case .file: return "doc"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        case .codeSnippet: return "chevron.left.forwardslash.chevron.right"
        case .terminalCommand: return "terminal"
        case .text: return "note.text"
        }
    }

    public var displayName: String {
        displayName(locale: .autoupdatingCurrent)
    }

    public func displayName(locale: Locale) -> String {
        switch self {
        case .link: return NexusL10n.tr("resource.link", locale: locale)
        case .file: return NexusL10n.tr("resource.file", locale: locale)
        case .image: return NexusL10n.tr("resource.image", locale: locale)
        case .pdf: return NexusL10n.tr("resource.pdf", locale: locale)
        case .codeSnippet: return NexusL10n.tr("resource.code", locale: locale)
        case .terminalCommand: return NexusL10n.tr("resource.command", locale: locale)
        case .text: return NexusL10n.tr("resource.text", locale: locale)
        }
    }

    public var isFileBacked: Bool {
        switch self {
        case .file, .image, .pdf: return true
        case .link, .codeSnippet, .terminalCommand, .text: return false
        }
    }

    public var isTextBacked: Bool {
        switch self {
        case .codeSnippet, .terminalCommand, .text: return true
        default: return false
        }
    }

    /// Fails safe to optional when unknown raw values appear.
    public static func parse(_ raw: String) -> TaskResourceKind? {
        TaskResourceKind(rawValue: raw)
    }
}
