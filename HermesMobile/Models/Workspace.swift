import Foundation

struct WorkspacesResponse: Decodable, Equatable {
    let workspaces: [WorkspaceRoot]?
    let last: String?
}

struct WorkspaceSuggestionsResponse: Decodable, Equatable {
    let suggestions: [String]?
    let prefix: String?
}

struct WorkspaceRoot: Decodable, Equatable, Sendable {
    let path: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case path
        case name
    }

    init(from decoder: Decoder) throws {
        if let stringValue = try? decoder.singleValueContainer().decode(String.self) {
            path = stringValue
            name = nil
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        name = try container.decodeIfPresent(String.self, forKey: .name)
    }
}

/// Response shape shared by the four workspace-registry mutation routes
/// (`/api/workspaces/add|remove|rename|reorder`). Verified against upstream
/// `_handle_workspace_*` handlers: `{"ok": true, "workspaces": [...]}` on success.
/// These routes are undocumented (not on the official docs site), so every field
/// stays optional and callers must tolerate a missing `workspaces` echo.
struct WorkspaceMutationResponse: Decodable, Equatable {
    let ok: Bool?
    let workspaces: [WorkspaceRoot]?
    let error: String?
}

/// HERMEX-FORK: what the file-management routes answer. Every one of them
/// reports `ok`, and some add `error` in the body with a 200 status — the same
/// shape the workspace mutations use, so the same rejection path applies.
struct FileMutationResponse: Decodable, Equatable {
    let ok: Bool?
    let error: String?
}

/// Raised when a file route answers HTTP 200 but reports `ok: false` in the
/// body. Same reasoning as `WorkspaceMutationRejection`: a failure presented as
/// a success leaves the listing showing a file that was never written.
struct FileMutationRejection: LocalizedError, Equatable {
    let serverMessage: String?

    var errorDescription: String? {
        serverMessage?.isEmpty == false ? serverMessage : String(localized: "The server refused that change.")
    }
}

/// Surfaced when a mutation route answers with HTTP success but reports
/// `ok: false` in the body. Upstream signals failure via non-2xx today, but
/// these routes are undocumented, so an explicit body-level failure must not
/// be presented as a success. Reuses the phrasing (and localization keys) of
/// `APIError`'s 400 handling.
struct WorkspaceMutationRejection: LocalizedError, Equatable {
    let serverMessage: String?

    var errorDescription: String? {
        if let serverMessage, !serverMessage.isEmpty {
            return String(localized: "The server rejected the request: \(serverMessage)")
        }
        return String(localized: "The server rejected the request.")
    }
}

struct AddWorkspaceRequest: Encodable, Equatable {
    let path: String
    let name: String?
    let create: Bool?
}

struct RemoveWorkspaceRequest: Encodable, Equatable {
    let path: String
}

struct RenameWorkspaceRequest: Encodable, Equatable {
    let path: String
    let name: String
}

struct ReorderWorkspacesRequest: Encodable, Equatable {
    let paths: [String]
}

// HERMEX-FORK: request bodies for the manual file-management endpoints the
// server already serves (api/routes.py:15451-15472). Every one of them carries
// `session_id`, because the server resolves the workspace root through the
// session — there is no way to address a file without one.
struct FileDeleteRequest: Encodable, Equatable {
    let sessionID: String
    let path: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case path
    }
}

struct FileCreateRequest: Encodable, Equatable {
    let sessionID: String
    let path: String
    let content: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case path
        case content
    }
}

struct FileRenameRequest: Encodable, Equatable {
    let sessionID: String
    let path: String
    let newName: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case path
        case newName = "new_name"
    }
}

struct FileMoveRequest: Encodable, Equatable {
    let sessionID: String
    let path: String
    let destDir: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case path
        case destDir = "dest_dir"
    }
}

struct FileCreateDirRequest: Encodable, Equatable {
    let sessionID: String
    let path: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case path
    }
}

struct DirectoryListResponse: Decodable, Equatable {
    let entries: [WorkspaceEntry]?
    let path: String?
    let workspace: String?
    let error: String?
}

struct WorkspaceEntry: Decodable, Hashable, Identifiable {
    var id: String { path ?? name ?? UUID().uuidString }
    var isBrowsableDirectory: Bool {
        isDirectory == true || type == "dir"
    }

    let name: String?
    let path: String?
    let type: String?
    let size: Int?
    let modified: Double?
    let isDirectory: Bool?
    /// `target_outside_workspace` for a symlink: the server resolved it and the
    /// target is not under the workspace root. Absent for everything else, and
    /// on servers that predate the flag, so callers treat `nil` as "no claim".
    let targetOutsideWorkspace: Bool?

    init(
        name: String?,
        path: String?,
        type: String? = nil,
        size: Int? = nil,
        modified: Double? = nil,
        isDirectory: Bool? = nil,
        targetOutsideWorkspace: Bool? = nil
    ) {
        self.name = name
        self.path = path
        self.type = type
        self.size = size
        self.modified = modified
        self.isDirectory = isDirectory
        self.targetOutsideWorkspace = targetOutsideWorkspace
    }

    enum CodingKeys: String, CodingKey {
        case name
        case path
        case type
        case size
        case modified
        case isDirectory
        case isDir
        case targetOutsideWorkspace
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        type = try container.decodeIfPresent(String.self, forKey: .type)
        size = try container.decodeIfPresent(Int.self, forKey: .size)
        modified = try container.decodeIfPresent(Double.self, forKey: .modified)
        isDirectory = try container.decodeIfPresent(Bool.self, forKey: .isDirectory)
            ?? container.decodeIfPresent(Bool.self, forKey: .isDir)
        targetOutsideWorkspace = try container.decodeIfPresent(Bool.self, forKey: .targetOutsideWorkspace)
    }
}

struct FileResponse: Decodable, Equatable {
    let content: String?
    let path: String?
    let name: String?
    let language: String?
    let size: Int?
    let lines: Int?
    let error: String?
}
