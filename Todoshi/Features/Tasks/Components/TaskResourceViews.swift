import SwiftUI
import QuickLook
import NexusCore

struct TaskResourceEditorView: View {
    let kind: TaskResourceKind
    var initial: TaskResourceDraft?
    var onSave: (TaskResourceDraft) -> Void
    var onCancel: () -> Void

    @State private var title: String = ""
    @State private var bodyText: String = ""
    @State private var urlString: String = ""
    @State private var language: String = "Swift"
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Title (optional)", text: $title)
            }

            switch kind {
            case .link:
                Section {
                    TextField("URL", text: $urlString)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                } footer: {
                    Text(TaskResourceStrings.storedLocally)
                }
            case .codeSnippet:
                Section {
                    Picker(NexusL10n.tr("resource.language"), selection: $language) {
                        ForEach(TaskResourceValidation.curatedLanguages(), id: \.self) { lang in
                            Text(lang).tag(lang)
                        }
                    }
                    TextField(NexusL10n.tr("resource.codeField"), text: $bodyText, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(8...24)
                        // Code stays LTR for readability in Arabic/RTL UI.
                        .environment(\.layoutDirection, .leftToRight)
                } footer: {
                    Text(TaskResourceStrings.neverExecutesCode)
                }
            case .terminalCommand:
                Section {
                    TextField(NexusL10n.tr("resource.commandField"), text: $bodyText, axis: .vertical)
                        .font(.body.monospaced())
                        .lineLimit(4...16)
                        .environment(\.layoutDirection, .leftToRight)
                } footer: {
                    Text(TaskResourceStrings.commandsNotExecuted)
                }
            case .text:
                Section {
                    TextField(NexusL10n.tr("resource.textField"), text: $bodyText, axis: .vertical)
                        .lineLimit(4...16)
                }
            default:
                EmptyView()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }
        }
        .navigationTitle(kind.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(NexusL10n.tr("common.cancel"), action: onCancel)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(NexusL10n.tr("common.save")) { commit() }
                    .fontWeight(.semibold)
            }
        }
        .onAppear {
            if let initial {
                title = initial.title
                bodyText = initial.body
                urlString = initial.externalURLString
                language = initial.languageIdentifier ?? "Swift"
            }
        }
    }

    private func commit() {
        errorMessage = nil
        var draft = initial ?? TaskResourceDraft(kind: kind)
        draft.kind = kind
        draft.title = title
        switch kind {
        case .link:
            draft.externalURLString = urlString
            draft.body = ""
        case .codeSnippet:
            draft.body = bodyText
            draft.languageIdentifier = language
            draft.externalURLString = ""
        case .terminalCommand, .text:
            draft.body = bodyText
            draft.externalURLString = ""
        default:
            break
        }
        if let issue = draft.validationIssue {
            errorMessage = TaskResourceValidation.message(for: issue)
            return
        }
        onSave(draft)
    }
}

struct TaskResourceRowView: View {
    let resource: TaskResource
    let fileStore: TaskResourceFileStore
    var onCopy: () -> Void
    var onOpen: () -> Void
    var onShare: () -> Void
    var onDelete: () -> Void
    var onEdit: () -> Void

    private var available: Bool {
        guard let path = resource.relativeFilePath else { return true }
        return fileStore.fileExists(at: path)
    }

    private var editActionTitle: String {
        switch resource.kind {
        case .codeSnippet: return NexusL10n.tr("resource.editCode")
        case .terminalCommand: return NexusL10n.tr("resource.editCommand")
        case .text: return NexusL10n.tr("resource.editText")
        case .link: return NexusL10n.tr("resource.editLink")
        default: return NexusL10n.tr("common.edit")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: NexusSpacing.sm) {
                Image(systemName: resource.kind.systemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TaskResourceValidation.displayTitle(for: resource))
                        .font(.body.weight(.medium))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if let preview = contentPreview, resource.kind != .codeSnippet, resource.kind != .terminalCommand {
                Text(preview)
                    .font(NexusTypography.metadata)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if !available {
                Text(TaskResourceStrings.fileUnavailable)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive, action: onDelete) {
                Label(TaskResourceStrings.deleteResource, systemImage: "trash")
            }
        }
        .contextMenu {
            if resource.kind == .link || resource.kind.isTextBacked {
                Button(TaskResourceStrings.copy, action: onCopy)
            }
            if resource.kind == .link || resource.kind.isFileBacked {
                Button(TaskResourceStrings.open, action: onOpen)
            }
            if resource.kind.isFileBacked {
                Button(TaskResourceStrings.preview, action: onOpen)
                Button(TaskResourceStrings.share, action: onShare)
            }
            if resource.kind.isTextBacked || resource.kind == .link {
                Button(TaskResourceStrings.share, action: onShare)
                Button(editActionTitle, action: onEdit)
            }
            Button(TaskResourceStrings.deleteResource, role: .destructive, action: onDelete)
        }
    }

    private var subtitle: String {
        var parts = [resource.kind.displayName]
        if resource.kind == .codeSnippet, let lang = resource.languageIdentifier, !lang.isEmpty {
            parts.append(lang)
        }
        if let size = resource.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        if resource.kind == .link, let host = resource.externalURLString.flatMap(URL.init(string:))?.host {
            parts.append(host)
        }
        if let name = resource.originalFileName, resource.kind.isFileBacked {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }

    private var contentPreview: String? {
        switch resource.kind {
        case .codeSnippet, .terminalCommand, .text:
            guard let body = resource.body, !body.isEmpty else { return nil }
            return body
        default:
            return nil
        }
    }

    private var accessibilityLabel: String {
        var parts = [
            TaskResourceValidation.displayTitle(for: resource),
            resource.kind.displayName,
            available ? "available" : TaskResourceStrings.fileUnavailable
        ]
        if let size = resource.fileSize {
            parts.append(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
        }
        return parts.joined(separator: ", ")
    }
}

struct QuickLookPreview: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(url: url)
    }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> any QLPreviewItem {
            url as NSURL
        }
    }
}
