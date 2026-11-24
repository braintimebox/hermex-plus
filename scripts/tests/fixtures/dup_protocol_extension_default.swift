import Foundation

/// Negative control for gate 9: a protocol requirement plus its default
/// implementation in the protocol's own extension is one contract, not two
/// declarations. Before the fix this shape reported every default as a duplicate,
/// which is why the fork's `KanbanDataClient` produced sixteen false blockers.
protocol SampleDataClient: Sendable {
    func sampleConfiguration() async throws -> String
    func sampleItems(_ request: String) async throws -> String
}

extension SampleDataClient {
    func sampleItems(_ request: String) async throws -> String {
        throw SampleUnsupportedClientMethod.items
    }
}

private enum SampleUnsupportedClientMethod: Error {
    case items
}
