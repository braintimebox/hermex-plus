import SwiftUI

/// Full-screen reader for a response the user chose "Select Text" on.
///
/// Lives in our own file rather than inside `ChatMessageActions.swift`, which
/// upstream also owns: the 1.6.0 merge replaced that file and took both of
/// these declarations with it, while `ChatView` kept calling them.

struct SelectableResponseText: Identifiable, Equatable {
    let id: String
    let text: String

    init(context: MessageActionContext) {
        id = context.messageID
        text = context.copyText
    }
}

struct SelectableResponseTextView: View {
    let selection: SelectableResponseText

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SelectableTextView(text: selection.text)
                .accessibilityIdentifier("selectable-response-text")
                .background(Color(.systemBackground))
                .navigationTitle("Select Text")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
}
