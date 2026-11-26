import Foundation

/// Positive control for the dotted-name fix: the exemption must be about *different*
/// types, not about the dot. Two extensions of the same nested type declaring the same
/// member are still a duplicate — whichever implementation wins depends on declaration
/// order, which is the ambiguity the gate exists to catch.
enum SampleContainer {
    struct Nested {
        var name: String
    }
}

extension SampleContainer.Nested {
    var isReady: Bool { true }
}

extension SampleContainer.Nested {
    var isReady: Bool { false }
}
