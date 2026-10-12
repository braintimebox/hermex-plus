import Foundation

/// Owns the workspace file tree for one session: lists directories from the server as the
/// user opens them, remembers which folders are open per server and workspace, and warms
/// file previews on press-down so the next screen has its content ready.
@MainActor
@Observable
final class FileBrowserViewModel {
    private let session: SessionSummary
    private let apiClient: APIClient
    private let expansionStore: FileTreeExpansionStore

    private(set) var tree = FileTree()
    private(set) var expandedPaths: Set<String> = []
    /// Directory path → generation of the listing that owns its spinner.
    private(set) var loadingPaths: [String: Int] = [:]
    /// Directory path → message for listings that failed; tapping the row retries.
    private(set) var failedPaths: [String: String] = [:]
    private(set) var selectedPath: String?
    /// HERMEX-FORK: the folder the user is actually looking at. Derived from the
    /// last directory that was listed, not from `expandedPaths` — that is a Set,
    /// so it has no order and `.last` would name a different folder on each
    /// read. Empty string is the workspace root.
    private(set) var currentDirectoryPath = "" 
    private(set) var isLoadingRoot = false
    private(set) var errorMessage: String?
    private(set) var lastError: Error?

    private var hasLoadedInitialRoot = false
    private var hasRestoredExpansion = false
    /// Per-directory generation counters so a stale listing never overwrites a newer one.
    private var loadGenerations: [String: Int] = [:]
    /// At most one prefetch is in flight: a newer press-down replaces the previous one, and
    /// opening a file takes its task out so the next visit fetches fresh content.
    private var prefetches: [String: Task<FileResponse, Error>] = [:]

    init(session: SessionSummary, server: URL, apiClient: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.session = session
        self.apiClient = apiClient ?? APIClient(baseURL: server)
        expansionStore = FileTreeExpansionStore(server: server, workspace: session.workspace, defaults: defaults)
    }

    // MARK: - Reading

    func visibleNodes(matching searchQuery: String) -> [VisibleFileTreeNode] {
        tree.visibleNodes(expanded: expandedPaths, searchQuery: searchQuery)
    }

    func isExpanded(_ path: String) -> Bool {
        expandedPaths.contains(path)
    }

    func isLoading(_ path: String) -> Bool {
        loadingPaths[path] != nil
    }

    func loadFailure(for path: String) -> String? {
        failedPaths[path]
    }

    /// Nil until the directory has been listed.
    func childCount(of path: String) -> Int? {
        tree.children(of: path)?.count
    }

    /// Hands the most recent failure to the caller once, so a recovered folder or a plain
    /// collapse never re-reports an error that already surfaced.
    func takeLastError() -> Error? {
        defer { lastError = nil }
        return lastError
    }

    // MARK: - Loading

    func loadInitialRootIfNeeded() async {
        guard !hasLoadedInitialRoot else { return }
        hasLoadedInitialRoot = true
        await loadRoot(reloadingOpenDirectories: false)
    }

    /// Pull-to-refresh: re-lists the root and every open directory, keeping expansion.
    func refresh() async {
        await loadRoot(reloadingOpenDirectories: true)
    }

    // MARK: - Manual file management

    // HERMEX-FORK: the server has served /api/file/{delete,create,rename,move,
    // create-dir} since long before this app knew about them; the browser was
    // read-only only because nothing called them.
    /// Every mutation ends the same way: the server is the source of truth for
    /// what is on disk, so the affected directory is re-listed rather than the
    /// tree being patched locally. A local optimisation would drift the moment
    /// a concurrent write or a failed rename happened.
    private func runFileMutation(_ operation: () async throws -> FileMutationResponse, reloading path: String) async {
        do {
            let response = try await operation()
            if let response, response.ok == false {
                lastError = FileMutationRejection(serverMessage: response.error)
            }
        } catch {
            lastError = error
        }
        await loadDirectory(path)
    }

    /// Removes a file or folder. The caller confirms first — this is the one
    /// operation here that cannot be undone from the app.
    func deleteEntry(at path: String) async {
        guard let sessionID = session.sessionId else { return }
        await runFileMutation(
            { try await self.apiClient.deleteFile(sessionID: sessionID, path: path) },
            reloading: parentDirectory(of: path)
        )
    }

    /// Creates an empty file at `path`, which must include the new name.
    func createFile(at path: String) async {
        guard let sessionID = session.sessionId else { return }
        await runFileMutation(
            { try await self.apiClient.createFile(sessionID: sessionID, path: path) },
            reloading: parentDirectory(of: path)
        )
    }

    /// Creates a folder at `path`, which must include the new name.
    func createDirectory(at path: String) async {
        guard let sessionID = session.sessionId else { return }
        await runFileMutation(
            { try await self.apiClient.createDirectory(sessionID: sessionID, path: path) },
            reloading: parentDirectory(of: path)
        )
    }

    /// Renames in place: the server takes the new name, not a full path.
    func renameEntry(at path: String, to newName: String) async {
        guard let sessionID = session.sessionId else { return }
        await runFileMutation(
            { try await self.apiClient.renameFile(sessionID: sessionID, path: path, newName: newName) },
            reloading: parentDirectory(of: path)
        )
    }

    /// Moves an entry into another directory of the same workspace.
    func moveEntry(at path: String, toDirectory destDir: String) async {
        guard let sessionID = session.sessionId else { return }
        await runFileMutation(
            { try await self.apiClient.moveFile(sessionID: sessionID, path: path, destDir: destDir) },
            reloading: parentDirectory(of: path)
        )
    }

    /// The directory a mutation should refresh: the entry's own parent, since
    /// that is where the row appears and disappears.
    private func parentDirectory(of path: String) -> String {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard let lastSlash = trimmed.lastIndex(of: "/") else { return "" }
        return String(trimmed[..<lastSlash])
    }

    func retryRoot() async {
        await loadRoot(reloadingOpenDirectories: false)
    }

    /// Opens or closes a directory. Opening lists it on first use; tapping a failed listing retries.
    func toggleDirectory(_ path: String) async {
        if expandedPaths.contains(path), failedPaths[path] == nil {
            setExpanded(expandedPaths.subtracting([path]))
            return
        }

        setExpanded(expandedPaths.union([path]))
        if !tree.isLoaded(path) || failedPaths[path] != nil {
            await loadDirectory(path)
        }
    }

    /// Marks a file as the current one and opens every folder above it, listing any that
    /// have not been fetched yet, so the row is on screen when the tree is shown again.
    func select(path: String) async {
        selectedPath = path
        let ancestors = FileTree.ancestorPaths(of: path)
        if !ancestors.allSatisfy(expandedPaths.contains) {
            setExpanded(expandedPaths.union(ancestors))
        }
        for ancestor in ancestors where !tree.isLoaded(ancestor) {
            await loadDirectory(ancestor)
        }
    }

    private func loadRoot(reloadingOpenDirectories: Bool) async {
        guard let sessionID = session.sessionId else {
            errorMessage = String(localized: "Session ID is missing.")
            return
        }

        let generation = bumpGeneration(for: FileTree.rootPath)
        isLoadingRoot = true
        errorMessage = nil
        lastError = nil

        do {
            let response = try await apiClient.directoryList(sessionID: sessionID, path: FileTree.rootPath)
            guard generation == loadGenerations[FileTree.rootPath] else { return }
            commitListing(response.entries ?? [], of: FileTree.rootPath)
            if !hasRestoredExpansion {
                hasRestoredExpansion = true
                expandedPaths = expansionStore.load() ?? FileTree.defaultExpandedPaths
            }
            isLoadingRoot = false
            await loadOpenDescendants(of: FileTree.rootPath, reloadingLoaded: reloadingOpenDirectories)
        } catch {
            guard generation == loadGenerations[FileTree.rootPath] else { return }
            if !Self.isCancellationError(error) {
                lastError = error
                errorMessage = error.localizedDescription
            }
            isLoadingRoot = false
        }
    }

    /// Lists every expanded directory under `directory` whose parents are also open, in
    /// parallel, then recurses into them. Unloaded directories are fetched; loaded ones only
    /// when `reloadingLoaded` is set.
    private func loadOpenDescendants(of directory: String, reloadingLoaded: Bool) async {
        guard let nodes = tree.children(of: directory) else { return }
        let open = nodes.filter { $0.isDirectory && expandedPaths.contains($0.path) }
        guard !open.isEmpty else { return }

        await withTaskGroup(of: Void.self) { group in
            for node in open {
                group.addTask { @MainActor in
                    if reloadingLoaded || !self.tree.isLoaded(node.path) {
                        await self.loadDirectory(node.path)
                    }
                    await self.loadOpenDescendants(of: node.path, reloadingLoaded: reloadingLoaded)
                }
            }
        }
    }

    private func loadDirectory(_ path: String) async {
        guard let sessionID = session.sessionId else { return }

        let generation = bumpGeneration(for: path)
        loadingPaths[path] = generation
        failedPaths[path] = nil
        lastError = nil
        // Clear the spinner on every exit, but only if a newer listing has not taken it over.
        defer {
            if loadingPaths[path] == generation {
                loadingPaths[path] = nil
            }
        }

        do {
            let response = try await apiClient.directoryList(sessionID: sessionID, path: path)
            guard generation == loadGenerations[path] else { return }
            // A root refresh that finished meanwhile may have dropped this directory; an
            // orphaned listing would be shown as current if the folder ever came back.
            if tree.node(at: path)?.isDirectory == true {
                commitListing(response.entries ?? [], of: path)
                // HERMEX-FORK: only a listing that actually landed becomes the
                // current folder — a failed or dropped one must not own where a
                // new file is written.
                currentDirectoryPath = path
            }
        } catch {
            guard generation == loadGenerations[path] else { return }
            if !Self.isCancellationError(error) {
                lastError = error
                failedPaths[path] = error.localizedDescription
            }
        }
    }

    /// Stores a listing and invalidates in-flight requests for every folder the listing
    /// dropped (and any cached listing beneath it), so a folder that is removed and recreated
    /// cannot resurface a response that was requested before it disappeared.
    private func commitListing(_ entries: [WorkspaceEntry], of directory: String) {
        let previousFolders = Set((tree.children(of: directory) ?? []).filter(\.isDirectory).map(\.path))
        let previousKeys = Set(tree.children.keys)
        tree.setChildren(entries, of: directory)
        let currentFolders = Set((tree.children(of: directory) ?? []).filter(\.isDirectory).map(\.path))
        let stale = previousFolders.subtracting(currentFolders).union(previousKeys.subtracting(tree.children.keys))
        for path in stale {
            _ = bumpGeneration(for: path)
        }
    }

    private func bumpGeneration(for path: String) -> Int {
        let next = (loadGenerations[path] ?? 0) + 1
        loadGenerations[path] = next
        return next
    }

    private func setExpanded(_ paths: Set<String>) {
        expandedPaths = paths
        expansionStore.save(paths)
    }

    // MARK: - Prefetch

    /// Starts fetching a text file's content while the finger is still down on its row.
    func prefetchFile(at path: String) {
        guard prefetches[path] == nil,
              let sessionID = session.sessionId,
              FilePreviewViewModel.loadsTextPreview(forPath: path) else { return }

        cancelPrefetches()
        let apiClient = apiClient
        prefetches[path] = Task {
            try await apiClient.file(sessionID: sessionID, path: path)
        }
    }

    /// Called when a file opens: hands over that file's prefetch, if any, and cancels every
    /// other one. The task leaves the table so reopening the file fetches it again.
    func takePrefetch(for path: String) -> Task<FileResponse, Error>? {
        let task = prefetches.removeValue(forKey: path)
        cancelPrefetches()
        return task
    }

    func prefetchedFile(at path: String) -> Task<FileResponse, Error>? {
        prefetches[path]
    }

    func cancelPrefetches() {
        prefetches.values.forEach { $0.cancel() }
        prefetches.removeAll()
    }

    private static func isCancellationError(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        let underlying: Error
        if case APIError.network(let wrapped) = error {
            underlying = wrapped
        } else {
            underlying = error
        }

        guard let urlError = underlying as? URLError else { return false }
        return urlError.code == .cancelled
    }
}

/// Remembers which folders are open, keyed by server and workspace so one server's layout
/// never shows up under another. A missing record means "use the default expansion".
struct FileTreeExpansionStore {
    private let defaults: UserDefaults
    private let key: String

    init(server: URL, workspace: String?, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        key = Self.key(server: server, workspace: workspace)
    }

    static func key(server: URL, workspace: String?) -> String {
        "fileTree.expanded|\(server.absoluteString)|\(workspace ?? "")"
    }

    func load() -> Set<String>? {
        guard let paths = defaults.stringArray(forKey: key) else { return nil }
        return Set(paths)
    }

    func save(_ paths: Set<String>) {
        defaults.set(Array(paths).sorted(), forKey: key)
    }
}
