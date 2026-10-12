import SwiftUI

/// The workspace file tree: folders open in place, search keeps matches with their parents,
/// and a file row pushes its preview.
struct FileBrowserView: View {
    let onAPIError: (Error) -> Void

    private let session: SessionSummary
    private let server: URL
    @State private var viewModel: FileBrowserViewModel
    @State private var searchText = ""
    @State private var openedFile: FileTreeNode?
    // HERMEX-FORK: manual file management state. Rename and delete both need
    // confirmation, and neither can be done from the row itself.
    @State private var renamingEntry: FileTreeNode?
    @State private var renameDraft = ""
    @State private var deletingEntry: FileTreeNode?
    @State private var newEntryIsDirectory = false
    @State private var newEntryName = ""
    @State private var showingNewEntryAlert = false
    /// The warm fetch handed over when `openedFile` was tapped; consumed by that preview only.
    @State private var openedFilePrefetch: Task<FileResponse, Error>?

    init(session: SessionSummary, server: URL, onAPIError: @escaping (Error) -> Void) {
        self.session = session
        self.server = server
        self.onAPIError = onAPIError
        _viewModel = State(initialValue: FileBrowserViewModel(session: session, server: server))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar

            content
                .adaptiveReadableScrollContent(maxWidth: AdaptiveReadableContentWidth.workspace)
        }
        .navigationTitle("Files")
        .navigationBarTitleDisplayMode(.inline)
        // HERMEX-FORK: creating a file or a folder was only ever possible from
        // the web UI. Both land in the current folder, named in a prompt.
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    Button {
                        newEntryIsDirectory = false
                        newEntryName = ""
                        showingNewEntryAlert = true
                    } label: {
                        Label(String(localized: "New File"), systemImage: "doc.badge.plus")
                    }
                    Button {
                        newEntryIsDirectory = true
                        newEntryName = ""
                        showingNewEntryAlert = true
                    } label: {
                        Label(String(localized: "New Folder"), systemImage: "folder.badge.plus")
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(String(localized: "New file or folder"))
            }
        }
        .alert(
            newEntryIsDirectory
                ? String(localized: "New Folder")
                : String(localized: "New File"),
            isPresented: $showingNewEntryAlert
        ) {
            TextField(String(localized: "Name"), text: $newEntryName)
            Button(String(localized: "Create")) { createEntry() }
            Button(String(localized: "Cancel"), role: .cancel) {}
        }
        .navigationDestination(item: $openedFile) { node in
            FilePreviewView(
                session: session,
                server: server,
                entry: node.entry,
                prefetchedFile: openedFilePrefetch,
                onAPIError: onAPIError
            )
        }
        .task {
            await viewModel.loadInitialRootIfNeeded()
            handleLastError()
        }
        // HERMEX-FORK: rename takes the new name only — the server resolves the
        // full path from the current one, so a move and a rename cannot be
        // confused on the wire.
        // The field lives inside the actions closure: SwiftUI's alert has no
        // `prompt:` variant, and a text field there is what makes the keyboard
        // come up with the dialog.
        .alert(String(localized: "Rename"), isPresented: renameAlertBinding) {
            TextField(String(localized: "New name"), text: $renameDraft)
            Button(String(localized: "Rename")) {
                commitRename()
            }
            Button(String(localized: "Cancel"), role: .cancel) { renamingEntry = nil }
        } message: {
            if let entry = renamingEntry {
                Text(String(localized: "Renaming \(entry.name)."))
            }
        }
        // Deleting a folder deletes what is inside it, and the server has no
        // undo — so the confirmation names the entry rather than asking a
        // generic "are you sure".
        .alert(String(localized: "Delete"), isPresented: deleteAlertBinding, presenting: deletingEntry) { entry in
            Button(String(localized: "Delete"), role: .destructive) {
                Task {
                    await viewModel.deleteEntry(at: entry.path)
                    handleLastError()
                }
            }
            Button(String(localized: "Cancel"), role: .cancel) { deletingEntry = nil }
        } message: { entry in
            Text(String(localized: "\(entry.name) will be removed from the workspace. This cannot be undone."))
        }
    }

    /// The folder the user is looking at: a creation lands here rather than at
    /// the root, because a file made in the wrong place is a file that is lost.
    /// The ViewModel owns it — `expandedPaths` is a Set and has no order, so
    /// reading "the last open folder" from it would be arbitrary.
    private var currentDirectoryPath: String {
        viewModel.currentDirectoryPath
    }

    private func createEntry() {
        let name = newEntryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let base = currentDirectoryPath
        let path = base.isEmpty ? name : "\(base)/\(name)"

        Task {
            if newEntryIsDirectory {
                await viewModel.createDirectory(at: path)
            } else {
                await viewModel.createFile(at: path)
            }
            handleLastError()
        }
    }

    private var renameAlertBinding: Binding<Bool> {
        Binding(
            get: { renamingEntry != nil },
            set: { if !$0 { renamingEntry = nil } }
        )
    }

    /// Runs the pending rename. Split out because the alert's action closure
    /// cannot see the entry it was presenting — SwiftUI dismisses the binding
    /// before the button's work runs, so the entry is read here while it is
    /// still set.
    private func commitRename() {
        guard let entry = renamingEntry else { return }
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != entry.name else { return }
        renamingEntry = nil
        Task {
            await viewModel.renameEntry(at: entry.path, to: trimmed)
            handleLastError()
        }
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(
            get: { deletingEntry != nil },
            set: { if !$0 { deletingEntry = nil } }
        )
    }

    @ViewBuilder
    private var content: some View {
        let visibleNodes = viewModel.visibleNodes(matching: searchText)

        if viewModel.isLoadingRoot && !viewModel.tree.isRootLoaded {
            ProgressView("Loading files...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage, !viewModel.tree.isRootLoaded {
            ContentUnavailableView {
                Label("Could Not Load Files", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") {
                    Task {
                        await viewModel.retryRoot()
                        handleLastError()
                    }
                }
            }
        } else if visibleNodes.isEmpty {
            ContentUnavailableView {
                Label(searchText.isEmpty ? "No Files" : "No Matches", systemImage: searchText.isEmpty ? "folder" : "magnifyingglass")
            } description: {
                if !searchText.isEmpty {
                    Text("Try a different file name or path.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            List(visibleNodes) { item in
                FileTreeRowView(
                    item: item,
                    isExpanded: viewModel.isExpanded(item.node.path),
                    isLoading: viewModel.isLoading(item.node.path),
                    isSelected: item.node.path == viewModel.selectedPath,
                    hasLoadFailure: viewModel.loadFailure(for: item.node.path) != nil,
                    childCount: viewModel.childCount(of: item.node.path),
                    onPressDown: { viewModel.prefetchFile(at: item.node.path) },
                    onTap: { open(item.node) },
                    onRename: {
                        renameDraft = item.node.name
                        renamingEntry = item.node
                    },
                    onDelete: { deletingEntry = item.node }
                )
                .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .refreshable {
                await viewModel.refresh()
                handleLastError()
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if viewModel.isLoadingRoot {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading files...")
                    }
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                } else if let errorMessage = viewModel.errorMessage {
                    HStack(spacing: 12) {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        Spacer(minLength: 0)

                        Button("Try Again") {
                            Task {
                                await viewModel.retryRoot()
                                handleLastError()
                            }
                        }
                        .font(.footnote.weight(.semibold))
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                }
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Search files", text: $searchText)
                .font(.subheadline)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear file search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .background(Color(.tertiarySystemFill).opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private func open(_ node: FileTreeNode) {
        if node.isDirectory {
            Task {
                await viewModel.toggleDirectory(node.path)
                handleLastError()
            }
            return
        }

        openedFilePrefetch = viewModel.takePrefetch(for: node.path)
        openedFile = node
        Task { await viewModel.select(path: node.path) }
    }

    private func handleLastError() {
        if let error = viewModel.takeLastError() {
            onAPIError(error)
        }
    }
}

/// One tree row: 42 pt tall, indented 18 pt per level, chevron for folders, child count once
/// the folder has been listed. Press-down warms the file preview before the tap lands.
private struct FileTreeRowView: View {
    let item: VisibleFileTreeNode
    let isExpanded: Bool
    let isLoading: Bool
    let isSelected: Bool
    let hasLoadFailure: Bool
    let childCount: Int?
    let onPressDown: () -> Void
    let onTap: () -> Void
    // HERMEX-FORK: manual file management. The server has served these routes
    // all along; the browser was read-only because nothing wired them up.
    var onRename: () -> Void = {}
    var onDelete: () -> Void = {}

    private var node: FileTreeNode { item.node }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                if node.isDirectory {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.forward")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .frame(width: 12)
                } else {
                    Color.clear.frame(width: 12, height: 1)
                }

                icon
                    .frame(width: 22)

                Text(node.name)
                    .font(.subheadline.weight(isSelected ? .semibold : .medium))
                    .foregroundStyle(isSelected || node.isDirectory ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 8)

                trailingAccessory
            }
            .padding(.leading, 8 + CGFloat(item.depth) * 18)
            .padding(.trailing, 12)
            .frame(minHeight: 42)
            .contentShape(Rectangle())
        }
        .buttonStyle(FileTreeRowButtonStyle(isSelected: isSelected, onPressChanged: { isPressed in
            if isPressed, !node.isDirectory {
                onPressDown()
            }
        }))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        // HERMEX-FORK: manual file management. The server has served
        // /api/file/{delete,rename} all along; nothing in the client called them,
        // so the browser was read-only by omission rather than by design.
        .contextMenu {
            Button {
                onRename()
            } label: {
                Label(String(localized: "Rename"), systemImage: "pencil")
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label(String(localized: "Delete"), systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var trailingAccessory: some View {
        if node.isDirectory {
            if isLoading {
                ProgressView()
                    .controlSize(.mini)
            } else if hasLoadFailure {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let childCount {
                Text(childCount, format: .number)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
    }

    /// Folders and symlinks are quiet grey symbols; a file shows the glyph for its type.
    /// Everything sits at 17 pt so the column lines up.
    @ViewBuilder
    private var icon: some View {
        if node.isDirectory || node.isSymlink {
            Image(systemName: node.isSymlink ? "link" : "folder")
                .font(.system(size: 17))
                .foregroundStyle(Color(uiColor: .systemGray))
        } else {
            FileIcon.resolve(node.name).image
                .resizable()
                .scaledToFit()
                .frame(width: 17, height: 17)
        }
    }

    private var accessibilityLabel: String {
        let kind: String
        if node.isSymlink {
            kind = String(localized: "Link")
        } else {
            kind = node.isDirectory ? String(localized: "Folder") : String(localized: "File")
        }
        return String(localized: "\(kind), \(node.name)")
    }

    private var accessibilityValue: String {
        guard node.isDirectory else { return "" }
        if hasLoadFailure { return String(localized: "Could Not Load Files") }
        return isExpanded ? String(localized: "Expanded") : String(localized: "Collapsed")
    }
}

/// Highlights the row while pressed and reports press changes so the row can prefetch.
private struct FileTreeRowButtonStyle: ButtonStyle {
    let isSelected: Bool
    let onPressChanged: (Bool) -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(background(isPressed: configuration.isPressed))
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                onPressChanged(isPressed)
            }
    }

    private func background(isPressed: Bool) -> Color {
        if isPressed { return Color(.tertiarySystemFill) }
        return isSelected ? Color(.secondarySystemFill) : .clear
    }
}
