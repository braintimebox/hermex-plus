import SwiftUI
import UniformTypeIdentifiers

/// The room's attach button and its picker.
///
/// The bot chat already has a picker, but it is built around `BotConversation` and the chat's
/// draft store (`BotAttachmentPickerView` takes a `BotConversation`, `BotAttachmentDraft`
/// holds a `ChatDraftKey`), so reusing it in a room would mean dragging the chat's draft
/// model in. This is the same interaction without that coupling: pick files, hand back URLs,
/// and let the composer own the budget.
struct RoomAttachmentPicker: ViewModifier {
    @Binding var isPresented: Bool
    let onPick: ([URL]) -> Void

    func body(content: Content) -> some View {
        content.fileImporter(
            isPresented: $isPresented,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                onPick(urls)
            case .failure(let error):
                // A cancelled picker is not an error worth showing; a real failure is.
                if (error as NSError).code != NSUserCancelledError {
                    onPick([])
                }
            }
        }
    }
}

extension View {
    func roomAttachmentPicker(isPresented: Binding<Bool>, onPick: @escaping ([URL]) -> Void) -> some View {
        modifier(RoomAttachmentPicker(isPresented: isPresented, onPick: onPick))
    }
}
