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
    /// The raw byte count one file may have.
    static let bytes = 15_000_000
    /// The base64 length that raw byte count produces.
    static var encodedCharacters: Int { ((bytes + 2) / 3) * 4 }
    /// Files one message may carry (`MAX_ATTACHMENTS_PER_MESSAGE`).
    static let filesPerMessage = 8
    /// Bytes one message may carry in total (`MAX_MESSAGE_ATTACHMENT_BYTES`).
    static let messageBytes = 25_000_000
}

/// Why a file did not become an upload. Every case can be said to the user.
enum RoomAttachmentFailure: LocalizedError, Equatable {
    case empty(name: String)
    case tooLarge(name: String, bytes: Int, limit: Int)
    case unreadable(name: String)
    case tooManyFiles(name: String, limit: Int)
    case exceedsMessageBudget(name: String, bytes: Int, remaining: Int)

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
        case let .tooManyFiles(name, limit):
            String(
                localized: """
                \(name) would be file \(limit + 1); a room message carries at most \(limit).
                """
            )
        case let .exceedsMessageBudget(name, bytes, remaining):
            String(
                localized: """
                \(name) is \(Self.describe(bytes)) and only \(Self.describe(remaining)) of this                 message's \(Self.describe(RoomAttachmentLimit.messageBytes)) is left.
                """
            )
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
    /// What this upload costs against the message budget.
    let byteCount: Int
    /// The bytes themselves. Kept because scheduling copies the file into our own
    /// container — the picker's URL is not ours and does not survive a relaunch.
    let data: Data

    /// Where the file came from, for showing its name and origin in the picker. Never
    /// persisted: a picker URL belongs to another app and does not survive a relaunch.
    var sourceURL: URL?

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
        self.byteCount = data.count
        self.data = data
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
        self.sourceURL = url
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

/// What one message's files may add up to, checked before anything is uploaded.
///
/// The per-file limit is not the only one: `session_rules/hosted_attachments.py:16-18`
/// allows eight files and 25 000 000 bytes per message. Validating only the file
/// lets two 15 MB files upload successfully and then makes `groups.send` refuse the
/// message — after both bytes crossed the tunnel, and after the user watched two
/// progress bars finish.
///
/// The gateway cannot be asked to undo that: there is no delete verb for uploads
/// (`groups.discard` is about a member's execution, not bytes). An abandoned upload
/// does carry an expiry and is pruned, so it does not hold quota forever — but the
/// only reliable fix is to refuse *before* the first upload, which is what this
/// budget is for.
struct RoomAttachmentBudget: Equatable {
    private(set) var uploads: [RoomAttachmentUpload] = []

    var byteCount: Int { uploads.reduce(0) { $0 + $1.byteCount } }
    var remainingBytes: Int { max(0, RoomAttachmentLimit.messageBytes - byteCount) }
    var remainingFiles: Int { max(0, RoomAttachmentLimit.filesPerMessage - uploads.count) }
    var isEmpty: Bool { uploads.isEmpty }

    /// The line the picker shows under the selection: what is left, in the same
    /// units the refusal uses, so the number in the message is never a surprise.
    var remainingSummary: String {
        String(
            localized: "\(Self.describe(byteCount)) of \(Self.describe(RoomAttachmentLimit.messageBytes)) used · \(remainingFiles) file(s) left"
        )
    }

    static func describe(_ bytes: Int) -> String { RoomAttachmentFailure.describe(bytes) }

    /// The refusal this file would earn, or nil when it fits whole.
    func refusal(adding name: String, bytes: Int) -> RoomAttachmentFailure? {
        if uploads.count + 1 > RoomAttachmentLimit.filesPerMessage {
            return .tooManyFiles(name: name, limit: RoomAttachmentLimit.filesPerMessage)
        }
        if bytes <= 0 { return .empty(name: name) }
        if bytes > RoomAttachmentLimit.bytes {
            return .tooLarge(name: name, bytes: bytes, limit: RoomAttachmentLimit.bytes)
        }
        if bytes > remainingBytes {
            return .exceedsMessageBudget(name: name, bytes: bytes, remaining: remainingBytes)
        }
        return nil
    }

    /// Adds a picked file, or throws the refusal that names what is left.
    mutating func add(contentsOf url: URL) throws {
        let name = url.lastPathComponent
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            data = try handle.read(upToCount: RoomAttachmentLimit.bytes + 1) ?? Data()
        } catch {
            throw RoomAttachmentFailure.unreadable(name: name)
        }
        if let refusal = refusal(adding: name, bytes: data.isEmpty ? 0 : data.count) {
            throw refusal
        }
        uploads.append(try RoomAttachmentUpload(data: data, name: name, mime: RoomAttachmentUpload.mime(for: url)))
    }

    mutating func removeAll() { uploads.removeAll() }
}
