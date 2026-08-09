import SwiftUI

struct ForwardMessageSheet: View {
    let content: (text: String, author: String, sessionTitle: String)?
    let onForward: (String, String, String, String) -> Void  // text, author, fromTitle, toSessionId
    let onDismiss: () -> Void
    let client: APIClient

    @State private var sessions: [SessionSummary] = []
    @State private var isLoading = false

    var body: some View {
        SessionPickerForForward(
            sessions: sessions.map {
                SessionListItem(id: $0.id ?? $0.sessionId, displayTitle: $0.title ?? "Chat", lastMessagePreview: nil)
            }
        ) { session in
            guard let content else { return }
            onForward(content.text, content.author, content.sessionTitle, session.id)
        }
        .task {
            isLoading = true
            defer { isLoading = false }
            do {
                let response = try await client.sessions()
                sessions = response.sessions ?? []
            } catch {
                sessions = []
            }
        }
    }
}
