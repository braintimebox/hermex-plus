import Foundation
import Observation

/// Drives the Decisions screen: collects a state plus questions, calls the alpha
/// endpoint, and keeps the last answer. No decisions model is ever offered to the
/// chat picker — they cannot serve chat completions.
@MainActor
@Observable
final class DecisionsViewModel {
    struct EditableQuestion: Identifiable, Equatable {
        let id = UUID()
        var kind: DecisionQuestion.Kind = .noul
        var instructions = ""
        /// Comma-separated options for `.choice`.
        var choices = ""
        /// Comma-separated ordered levels for `.score`.
        var levels = ""

        func build() -> DecisionQuestion? {
            let text = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let split = { (raw: String) in
                raw.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            }
            return DecisionQuestion(type: kind, instructions: text, choices: split(choices), levels: split(levels))
        }
    }

    var apiKey: String = ""
    var model: String = "typesafe/jev-1.14"
    var state: String = ""
    var questions: [EditableQuestion] = [EditableQuestion()]
    var models: [DecisionModelInfo] = []
    var result: DecisionResponse?
    var errorMessage: String?
    var isRunning = false

    private let client: DecisionsClient
    private let keychain: KeychainStoring

    init(client: DecisionsClient = DecisionsClient(), keychain: KeychainStoring = KeychainStore()) {
        self.client = client
        self.keychain = keychain
    }

    var canRun: Bool {
        !state.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !buildQuestions().isEmpty
            && !isRunning
    }

    func loadSavedKey() {
        guard apiKey.isEmpty, let saved = try? keychain.load(.decisionsAPIKey) else { return }
        apiKey = saved
    }

    func saveKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? keychain.save(trimmed, forKey: .decisionsAPIKey)
    }

    func loadModels() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        do {
            let fetched = try await client.availableModels(apiKey: key)
            models = fetched.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
            if let first = models.first, !models.contains(where: { $0.id == model }) {
                model = first.id
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func run() async {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let built = buildQuestions()
        guard !key.isEmpty else {
            errorMessage = DecisionsClient.ClientError.missingKey.errorDescription
            return
        }
        guard !built.isEmpty else { return }

        isRunning = true
        errorMessage = nil
        defer { isRunning = false }

        let request = DecisionRequest(model: model, state: state, questions: built)
        do {
            result = try await client.decide(request, apiKey: key)
            saveKey()
        } catch {
            result = nil
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Question keys are positional (`q1`, `q2`, …) so answers map back to rows.
    private func buildQuestions() -> [String: DecisionQuestion] {
        var built: [String: DecisionQuestion] = [:]
        for (index, editable) in questions.enumerated() {
            guard let question = editable.build() else { continue }
            built["q\(index + 1)"] = question
        }
        return built
    }
}
