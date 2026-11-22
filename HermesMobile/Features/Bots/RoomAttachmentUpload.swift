import Foundation

/// The size a room attachment may have, taken from the gateway rather than guessed.
///
/// `groups.attachment.upload` carries the file inline as base64, and
/// `gateway/session_hosted_attachments.py:53-56` refuses anything whose *encoded*
/// length exceeds `((MAX_ATTACHMENT_BYTES + 2) / 3) * 4` before decoding it.
/// `MAX_ATTACHMENT_BYTES` is 15 000 000 (`session_rules/hosted_attachments.py:17`),
/// which is 20 000 000 base64 characters.
///
/// The client checks the same number, so an oversized file becomes a sentence in
/// the composer instead of a long round trip that ends in `invalid_params` — over a
/// tunnel that is the difference between an immediate "no" and a timeout.
enum RoomAttachmentLimit {
    /// The raw byte count the gateway accepts.
    static let bytes = 15_000_000
    /// The base64 length that raw byte count produces.
    static var encodedCharacters: Int { ((bytes + 2) / 3) * 4 }
}

/// Why a file did not become an upload. Every case can be said to the user.
enum RoomAttachmentFailure: LocalizedError, Equatable {
    case empty(name: String)
    case tooLarge(name: String, bytes: Int, limit: Int)
    case unreadable(name: String)

    var errorDescription: String? {
        switch self {
        case let .empty(name):
            String(localized: "\(name) is empty, so there is nothing to send.")
        case let .tooLarge(name, bytes, limit):
            String(
                localized: """
                \(name) is \(Self.describe(bytes)), and a room attachment can be at most \
                \(Self.describe(limit)).
                """
            )
        case let .unreadable(name):
            String(localized: "\(name) couldn't be read.")
        }
    }

    static func describe(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB]
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

/// The six fields `groups.attachment.upload` requires, filled from one file.
///
/// `kind` is not free-form: the gateway accepts `image`, `pdf` and `file`, and
/// rejects an image MIME type declared as `file` (`hosted_room_attachments.py:95-106`).
/// Deriving it from the MIME type here is what keeps that refusal unreachable.
struct RoomAttachmentUpload: Equatable {
    let uploadID: String
    let kind: String
    let name: String
    let mime: String
    let dataBase64: String

    /// The upload call's parameters, without `room_id`, which the connection adds.
    var params: [String: String] {
        [
            "upload_id": uploadID,
            "kind": kind,
            "name": name,
            "mime": mime,
            "data_base64": dataBase64,
        ]
    }

    init(data: Data, name: String, mime: String, uploadID: String = UUID().uuidString.lowercased()) throws {
        guard !data.isEmpty else { throw RoomAttachmentFailure.empty(name: name) }
        guard data.count <= RoomAttachmentLimit.bytes else {
            throw RoomAttachmentFailure.tooLarge(name: name, bytes: data.count, limit: RoomAttachmentLimit.bytes)
        }
        self.uploadID = uploadID
        self.kind = Self.kind(forMIME: mime)
        self.name = name
        self.mime = mime
        self.dataBase64 = data.base64EncodedString()
    }

    /// Reads a file the user picked, refusing it by size before the bytes are encoded.
    init(contentsOf url: URL) throws {
        let name = url.lastPathComponent
        let data: Data
        do {
            // A mapped read would fault on a file the share sheet handed us; a plain
            // read of a bounded size is what makes the refusal cheap for big videos.
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: RoomAttachmentLimit.bytes + 1) ?? Data()
        } catch {
            throw RoomAttachmentFailure.unreadable(name: name)
        }
        try self.init(data: data, name: name, mime: Self.mime(for: url))
    }

    static func kind(forMIME mime: String) -> String {
        let lowered = mime.lowercased()
        if lowered.hasPrefix("image/") { return "image" }
        if lowered == "application/pdf" { return "pdf" }
        return "file"
    }

    static func mime(for url: URL) -> String {
        // UTType is unavailable to tests that only exercise the payload, so the common
        // types are named here and everything else is an opaque file.
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic": return "image/heic"
        case "gif": return "image/gif"
        case "pdf": return "application/pdf"
        case "txt": return "text/plain"
        default: return "application/octet-stream"
        }
    }
}
