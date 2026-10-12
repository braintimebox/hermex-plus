import Foundation

extension APIClient {
    func workspaces() async throws -> WorkspacesResponse {
        try await send(endpoint: .workspaces, method: "GET")
    }

    func workspaceSuggestions(prefix: String) async throws -> WorkspaceSuggestionsResponse {
        try await send(endpoint: .workspaceSuggestions(prefix: prefix), method: "GET")
    }

    func addWorkspace(path: String, name: String? = nil, create: Bool? = nil) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceAdd,
            method: "POST",
            body: AddWorkspaceRequest(path: path, name: name, create: create)
        )
    }

    func removeWorkspace(path: String) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceRemove,
            method: "POST",
            body: RemoveWorkspaceRequest(path: path)
        )
    }

    func renameWorkspace(path: String, name: String) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceRename,
            method: "POST",
            body: RenameWorkspaceRequest(path: path, name: name)
        )
    }

    func reorderWorkspaces(paths: [String]) async throws -> WorkspaceMutationResponse {
        try await send(
            endpoint: .workspaceReorder,
            method: "POST",
            body: ReorderWorkspacesRequest(paths: paths)
        )
    }

    // MARK: - Manual file management

    // HERMEX-FORK: all five operations the server already offers for workspace
    // files — nothing here is new on the wire, only newly reachable from iOS.
    /// All five operations the server already offers for workspace files. They
    /// are POSTs with a JSON body; the server answers `{"ok": true, ...}` or an
    /// error status, and the caller refreshes the listing rather than optimising
    /// the tree locally — the server owns what is on disk.
    func deleteFile(sessionID: String, path: String) async throws -> FileMutationResponse {
        try await send(
            endpoint: .fileDelete(sessionID: sessionID, path: path),
            method: "POST",
            body: FileDeleteRequest(sessionID: sessionID, path: path)
        )
    }

    func createFile(sessionID: String, path: String, content: String = "") async throws -> FileMutationResponse {
        try await send(
            endpoint: .fileCreate(sessionID: sessionID, path: path, content: content),
            method: "POST",
            body: FileCreateRequest(sessionID: sessionID, path: path, content: content)
        )
    }

    func createDirectory(sessionID: String, path: String) async throws -> FileMutationResponse {
        try await send(
            endpoint: .fileCreateDir(sessionID: sessionID, path: path),
            method: "POST",
            body: FileCreateDirRequest(sessionID: sessionID, path: path)
        )
    }

    func renameFile(sessionID: String, path: String, newName: String) async throws -> FileMutationResponse {
        try await send(
            endpoint: .fileRename(sessionID: sessionID, path: path, newName: newName),
            method: "POST",
            body: FileRenameRequest(sessionID: sessionID, path: path, newName: newName)
        )
    }

    func moveFile(sessionID: String, path: String, destDir: String) async throws -> FileMutationResponse {
        try await send(
            endpoint: .fileMove(sessionID: sessionID, path: path, destDir: destDir),
            method: "POST",
            body: FileMoveRequest(sessionID: sessionID, path: path, destDir: destDir)
        )
    }

    func directoryList(sessionID: String, path: String? = nil) async throws -> DirectoryListResponse {
        try await send(
            endpoint: .directoryList(sessionID: sessionID, path: path),
            method: "GET"
        )
    }

    func file(sessionID: String, path: String) async throws -> FileResponse {
        try await send(endpoint: .file(sessionID: sessionID, path: path), method: "GET")
    }

    func rawFileData(sessionID: String, path: String) async throws -> Data {
        try await sendData(endpoint: .rawFile(sessionID: sessionID, path: path), method: "GET", encodedBody: nil, timeout: 180)
    }

    func mediaData(sessionID: String, path: String) async throws -> Data {
        try await sendData(endpoint: .media(sessionID: sessionID, path: path), method: "GET")
    }

    func remoteTranscriptMediaData(from url: URL) async throws -> Data {
        if Self.isSameOrigin(url, as: baseURL) {
            return try await downloadData(from: url, using: session, mapsUnauthorized: true)
        }

        return try await downloadData(from: url, using: publicMediaSession, mapsUnauthorized: false)
    }

    /// Stream a workspace file to a temp file on disk (large binaries). Uses the
    /// same endpoint contract as `rawFileData` but writes to disk instead of
    /// memory — so a multi-MB .ipa is not loaded into a single `Data`.
    func rawFileDownloadURL(sessionID: String, path: String) async throws -> URL {
        let url = Endpoint.rawFile(sessionID: sessionID, path: path).url(relativeTo: baseURL)
        return try await downloadFile(from: url, using: session)
    }
}

