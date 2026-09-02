import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
import NexusCore

/// Form draft resources section (mutations persist only on Save).
struct TaskFormResourcesSection: View {
    @Bindable var viewModel: TaskFormViewModel
    @State private var editorKind: TaskResourceKind?
    @State private var editingDraft: TaskResourceDraft?
    @State private var showImporter = false
    @State private var importerContentTypes: [UTType] = [.item]
    @State private var preferredImportKind: TaskResourceKind?

    var body: some View {
        Section {
            if viewModel.draft.resources.isEmpty {
                Text(TaskResourceStrings.noResources)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(viewModel.draft.resources) { resource in
                    HStack {
                        Image(systemName: resource.kind.systemImage)
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(resource.displayTitle)
                            Text(resource.kind.displayName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if resource.kind.isTextBacked || resource.kind == .link {
                            editingDraft = resource
                            editorKind = resource.kind
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            viewModel.deleteResourceDraft(id: resource.id)
                        } label: {
                            Label(TaskResourceStrings.deleteResource, systemImage: "trash")
                        }
                    }
                }
                .onMove { viewModel.moveResourceDrafts(from: $0, to: $1) }
            }

            Menu {
                Button(TaskResourceStrings.addLink) {
                    editingDraft = nil
                    editorKind = .link
                }
                Button(TaskResourceStrings.addCodeSnippet) {
                    editingDraft = nil
                    editorKind = .codeSnippet
                }
                Button(TaskResourceStrings.addCommand) {
                    editingDraft = nil
                    editorKind = .terminalCommand
                }
                Button(TaskResourceStrings.addText) {
                    editingDraft = nil
                    editorKind = .text
                }
                Button(TaskResourceStrings.addImage) {
                    preferredImportKind = .image
                    importerContentTypes = [.image]
                    showImporter = true
                }
                Button(TaskResourceStrings.addPDF) {
                    preferredImportKind = .pdf
                    importerContentTypes = [.pdf]
                    showImporter = true
                }
                Button(TaskResourceStrings.addFile) {
                    preferredImportKind = nil
                    importerContentTypes = [.item]
                    showImporter = true
                }
            } label: {
                Label(NexusL10n.tr("resource.add"), systemImage: "plus.circle")
            }
        } header: {
            Text(TaskResourceStrings.resources)
        } footer: {
            Text(TaskResourceStrings.storedLocally)
                .font(.footnote)
        }
        .environment(\.editMode, .constant(.active))
        .sheet(item: Binding(
            get: { editorKind.map { EditorPresentation(kind: $0, draft: editingDraft) } },
            set: { if $0 == nil { editorKind = nil; editingDraft = nil } }
        )) { presentation in
            NavigationStack {
                TaskResourceEditorView(
                    kind: presentation.kind,
                    initial: presentation.draft,
                    onSave: { draft in
                        if presentation.draft != nil {
                            viewModel.updateResourceDraft(draft)
                        } else {
                            viewModel.addResourceDraft(draft)
                        }
                        editorKind = nil
                        editingDraft = nil
                    },
                    onCancel: {
                        editorKind = nil
                        editingDraft = nil
                    }
                )
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importerContentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    try viewModel.importFile(from: url, preferredKind: preferredImportKind)
                } catch TaskResourceStorageError.fileTooLarge {
                    viewModel.errorMessage = TaskResourceStrings.fileTooLarge
                } catch TaskResourceStorageError.emptyFile {
                    viewModel.errorMessage = TaskResourceStrings.emptyFile
                } catch {
                    viewModel.errorMessage = TaskResourceStrings.unsupportedFile
                }
            case .failure:
                break
            }
            preferredImportKind = nil
        }
    }
}

private struct EditorPresentation: Identifiable {
    let kind: TaskResourceKind
    let draft: TaskResourceDraft?
    var id: String { "\(kind.rawValue)-\(draft?.id.uuidString ?? "new")" }
}

/// Detail resources with immediate repository persistence.
struct TaskDetailResourcesSection: View {
    let taskID: UUID
    let resources: [TaskResource]
    var onError: (String) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var editorKind: TaskResourceKind?
    @State private var editingResource: TaskResource?
    @State private var showImporter = false
    @State private var importerTypes: [UTType] = [.item]
    @State private var preferredKind: TaskResourceKind?
    @State private var previewURL: URL?
    @State private var shareItems: [Any] = []
    @State private var showShare = false
    @State private var confirmDelete: TaskResource?
    @State private var isReordering = false

    private let fileStore = TaskResourceFileStore.shared

    private var ordered: [TaskResource] {
        resources.sorted {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.createdAt < $1.createdAt
        }
    }

    var body: some View {
        Section {
            if ordered.isEmpty {
                Text(TaskResourceStrings.noResources)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(ordered, id: \.id) { resource in
                    TaskResourceRowView(
                        resource: resource,
                        fileStore: fileStore,
                        onCopy: { copy(resource) },
                        onOpen: { open(resource) },
                        onShare: { share(resource) },
                        onDelete: { confirmDelete = resource },
                        onEdit: {
                            editingResource = resource
                            editorKind = resource.kind
                        }
                    )
                }
                .onMove { source, destination in
                    reorder(from: source, to: destination)
                }
            }

            Menu {
                Button(TaskResourceStrings.addLink) { editorKind = .link; editingResource = nil }
                Button(TaskResourceStrings.addCodeSnippet) { editorKind = .codeSnippet; editingResource = nil }
                Button(TaskResourceStrings.addCommand) { editorKind = .terminalCommand; editingResource = nil }
                Button(TaskResourceStrings.addText) { editorKind = .text; editingResource = nil }
                Button(TaskResourceStrings.addImage) {
                    preferredKind = .image
                    importerTypes = [.image]
                    showImporter = true
                }
                Button(TaskResourceStrings.addPDF) {
                    preferredKind = .pdf
                    importerTypes = [.pdf]
                    showImporter = true
                }
                Button(TaskResourceStrings.addFile) {
                    preferredKind = nil
                    importerTypes = [.item]
                    showImporter = true
                }
            } label: {
                Label(NexusL10n.tr("resource.add"), systemImage: "plus.circle")
            }
        } header: {
            HStack {
                Text(TaskResourceStrings.resources)
                Spacer()
                if ordered.count > 1 {
                    Button(isReordering ? NexusL10n.tr("common.done") : NexusL10n.tr("checklist.reorder")) {
                        isReordering.toggle()
                    }
                    .font(.caption.weight(.semibold))
                }
            }
        } footer: {
            Text(TaskResourceStrings.storedLocally)
        }
        .environment(\.editMode, .constant(isReordering ? .active : .inactive))
        .sheet(item: Binding(
            get: {
                editorKind.map { EditorPresentation(
                    kind: $0,
                    draft: editingResource.map(TaskResourceDraft.init(resource:))
                ) }
            },
            set: { if $0 == nil { editorKind = nil; editingResource = nil } }
        )) { presentation in
            NavigationStack {
                TaskResourceEditorView(
                    kind: presentation.kind,
                    initial: presentation.draft,
                    onSave: { draft in
                        saveEditor(draft: draft, existing: editingResource)
                        editorKind = nil
                        editingResource = nil
                    },
                    onCancel: {
                        editorKind = nil
                        editingResource = nil
                    }
                )
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: importerTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    importFile(url)
                }
            case .failure:
                break
            }
        }
        .sheet(isPresented: Binding(
            get: { previewURL != nil },
            set: { if !$0 { previewURL = nil } }
        )) {
            if let previewURL {
                QuickLookPreview(url: previewURL)
                    .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showShare) {
            ActivityView(items: shareItems)
        }
        .alert(TaskResourceStrings.deleteResource, isPresented: Binding(
            get: { confirmDelete != nil },
            set: { if !$0 { confirmDelete = nil } }
        )) {
            Button(TaskResourceStrings.deleteResource, role: .destructive) {
                if let confirmDelete {
                    delete(confirmDelete)
                }
            }
            Button(NexusL10n.tr("common.cancel"), role: .cancel) {}
        }
    }

    private func saveEditor(draft: TaskResourceDraft, existing: TaskResource?) {
        let repo = TaskResourceRepository(context: modelContext, fileStore: fileStore)
        do {
            if let existing {
                try repo.updateResource(
                    resourceID: existing.id,
                    title: draft.title,
                    body: draft.body,
                    externalURL: URL(string: draft.externalURLString),
                    languageIdentifier: draft.languageIdentifier
                )
            } else if draft.kind == .link, let url = URL(string: draft.externalURLString.trimmingCharacters(in: .whitespacesAndNewlines)) {
                _ = try repo.createLink(taskID: taskID, title: draft.title, url: url)
            } else if draft.kind.isTextBacked {
                _ = try repo.createTextResource(
                    taskID: taskID,
                    kind: draft.kind,
                    title: draft.title,
                    body: draft.body,
                    languageIdentifier: draft.languageIdentifier
                )
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch RepositoryValidationError.resourceInvalid(let issue) {
            onError(TaskResourceValidation.message(for: issue))
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func importFile(_ url: URL) {
        let repo = TaskResourceRepository(context: modelContext, fileStore: fileStore)
        let resourceID = UUID()
        do {
            let imported = try fileStore.importFile(from: url, taskID: taskID, resourceID: resourceID)
            _ = try repo.createImportedFile(
                taskID: taskID,
                resourceID: resourceID,
                importedFile: imported,
                kind: preferredKind ?? imported.inferredKind
            )
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch TaskResourceStorageError.fileTooLarge {
            onError(TaskResourceStrings.fileTooLarge)
        } catch TaskResourceStorageError.emptyFile {
            onError(TaskResourceStrings.emptyFile)
        } catch {
            onError(TaskResourceStrings.unsupportedFile)
        }
        preferredKind = nil
    }

    private func delete(_ resource: TaskResource) {
        do {
            _ = try TaskResourceRepository(context: modelContext, fileStore: fileStore)
                .deleteResource(resourceID: resource.id)
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }

    private func copy(_ resource: TaskResource) {
        if resource.kind == .link {
            UIPasteboard.general.string = resource.externalURLString
        } else if let body = resource.body {
            UIPasteboard.general.string = body
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func open(_ resource: TaskResource) {
        if resource.kind == .link, let string = resource.externalURLString, let url = URL(string: string) {
            UIApplication.shared.open(url)
            return
        }
        guard let path = resource.relativeFilePath,
              fileStore.fileExists(at: path),
              let url = try? fileStore.fileURL(for: path) else {
            onError(TaskResourceStrings.fileUnavailable)
            return
        }
        previewURL = url
    }

    private func share(_ resource: TaskResource) {
        if resource.kind == .link, let string = resource.externalURLString, let url = URL(string: string) {
            shareItems = [url]
            showShare = true
            return
        }
        if let body = resource.body, resource.kind.isTextBacked {
            shareItems = [body]
            showShare = true
            return
        }
        guard let path = resource.relativeFilePath,
              let url = try? fileStore.fileURL(for: path),
              fileStore.fileExists(at: path) else {
            onError(TaskResourceStrings.fileUnavailable)
            return
        }
        shareItems = [url]
        showShare = true
    }

    private func reorder(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        var ids = ordered.map(\.id)
        let moved = ids[from]
        ids.move(fromOffsets: source, toOffset: destination)
        guard let newIndex = ids.firstIndex(of: moved) else { return }
        let before = newIndex + 1 < ids.count ? ids[newIndex + 1] : nil
        do {
            _ = try TaskResourceRepository(context: modelContext, fileStore: fileStore)
                .moveResource(resourceID: moved, before: before)
        } catch {
            onError(UserFacingError.message(for: error))
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
