import SwiftUI

extension View {
    /// Marks a screen whose transcript links open through the environment's
    /// `openURL`.
    ///
    /// 1.9.0 routes these through `TranscriptLinkRouter`, which also chooses
    /// between an in-app browser and Safari. That policy was never ported here,
    /// so this keeps the system behaviour instead of faking a choice: a tap hands
    /// the URL to `openURL`, which opens it the way every other link in the app
    /// opens.
    func transcriptLinks() -> some View {
        environment(\.openURL, OpenURLAction { _ in .systemAction })
    }
}
