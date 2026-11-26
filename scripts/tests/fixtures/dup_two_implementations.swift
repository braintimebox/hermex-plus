import Foundation

/// Positive control for gate 9: two implementations of the same member in one
/// type are a real duplicate — whichever of them wins is decided by declaration
/// order, which is exactly the ambiguity the gate exists to catch. The gate must
/// keep reporting this after the protocol/extension exemption was added.
struct SampleDuplicateMembers {
    func sampleConfiguration() async throws -> String {
        "first"
    }

    func sampleConfiguration() async throws -> String {
        "second"
    }
}
