import Foundation
import SwiftUI

/// What the app tried to connect to, and what came back.
///
/// Until now a failed sign-in left one sentence under the password and nothing else:
/// the details went to `os_log`, which cannot be read on a phone without a Mac. That
/// is why "Reconnect did nothing" and "the password is wrong" could not be told apart
/// — from the outside they look the same, because both end with the same screen.
///
/// This is a ring buffer in memory, not a log file: it is a diagnostic for the session
/// the user is in, and it must not grow, survive a reinstall, or hold a password. The
/// address and the reason are enough to say which host refused what.
@MainActor
@Observable
final class ConnectionLog {
    struct Entry: Identifiable, Equatable {
        enum Kind: String, Equatable {
            case attempt = "Try"
            case connected = "Connected"
            case refused = "Refused"
            case reconnected = "Reconnected"
            case signedOut = "Signed out"
        }

        let id = UUID()
        let at: Date
        let kind: Kind
        let address: String
        let detail: String

        /// One line for the list, and for pasting into a message when asking for help.
        var line: String {
            let stamp = Entry.formatter.string(from: at)
            return "\(stamp)  \(kind.rawValue)  \(address)  \(detail)"
        }

        static let formatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss"
            return formatter
        }()
    }

    static let shared = ConnectionLog()

    /// Fifty is enough to cover one troubleshooting session and small enough that the
    /// screen opens instantly.
    static let limit = 50

    private(set) var entries: [Entry] = []

    init() {}

    /// Newest first: the thing that just failed is the thing being read.
    func record(_ kind: Entry.Kind, address: String, detail: String, at: Date = Date()) {
        entries.insert(Entry(at: at, kind: kind, address: address, detail: detail), at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    func clear() { entries.removeAll() }

    /// The whole buffer as text, for "copy" in the screen.
    var transcript: String {
        entries.map(\.line).joined(separator: "\n")
    }
}

#if DEBUG
extension ConnectionLog {
    /// Tests need a buffer that is not the app's, and a way to fill it.
    static func makeForTesting() -> ConnectionLog { ConnectionLog() }
}
#endif

/// The log, on screen: what was tried, what came back, and a way to send it on.
struct ConnectionLogView: View {
    private let log = ConnectionLog.shared

    var body: some View {
        List {
            if log.entries.isEmpty {
                ContentUnavailableView(
                    "Nothing yet",
                    systemImage: "list.bullet.rectangle",
                    description: Text("Connection attempts appear here as they happen.")
                )
            }
            ForEach(log.entries) { entry in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(entry.kind.rawValue).font(.caption.bold())
                            .foregroundStyle(colour(for: entry.kind))
                        Spacer(minLength: 8)
                        Text(ConnectionLog.Entry.formatter.string(from: entry.at))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(entry.address).font(.footnote).lineLimit(1).truncationMode(.middle)
                    Text(entry.detail).font(.footnote).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Connection log")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Copy all", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = log.transcript
                    }
                    .disabled(log.entries.isEmpty)
                    Button("Clear", systemImage: "trash", role: .destructive) { log.clear() }
                        .disabled(log.entries.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
    }

    private func colour(for kind: ConnectionLog.Entry.Kind) -> Color {
        switch kind {
        case .connected, .reconnected: .green
        case .refused, .signedOut: .red
        case .attempt: .secondary
        }
    }
}
