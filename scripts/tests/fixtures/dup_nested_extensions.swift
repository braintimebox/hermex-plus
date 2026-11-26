import Foundation

/// Negative control for the second half of the same defect: two extensions of
/// *different* nested types share a leading component (`Container`), and before the
/// dotted-name fix the gate attributed every member to that shared prefix and called
/// them duplicates. `HermesCall.ProfileChanges` / `.NewProfile` / `.RoomCreation` are
/// exactly this shape, and touching `HermesCall.swift` for attachments produced four
/// blockers.
enum Container {
    struct First {
        var name: String
    }

    struct Second {
        var name: String
    }
}

extension Container.First {
    var isReady: Bool { !name.isEmpty }
}

extension Container.Second {
    var isReady: Bool { !name.isEmpty }
}
