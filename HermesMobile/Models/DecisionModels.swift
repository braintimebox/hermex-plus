import Foundation

/// Request and response shapes for OpenRouter's Decisions API (alpha).
///
/// Shape verified against a live call on 2026-10-19: `POST
/// https://openrouter.ai/api/alpha/decisions` with `{model, state, questions}`
/// answered 200 with `{model, answers, usage, id, provider}`. Question types and
/// the `criteria` payload follow OpenRouter's published Jev documentation
/// (`choice` → object of option → description, `score` → ordered array).
///
/// A decisions model is NOT a chat model: `/chat/completions` rejects one with
/// "is a decisions model and cannot be used with the chat/completions endpoint",
/// which is why this lives in its own screen and never in the model picker.
struct DecisionRequest: Encodable, Equatable {
    let model: String
    let state: String
    let questions: [String: DecisionQuestion]
}

struct DecisionQuestion: Encodable, Equatable {
    enum Kind: String, Encodable, CaseIterable, Identifiable {
        case noul
        case choice
        case score

        var id: String { rawValue }

        var title: String {
            switch self {
            case .noul: return String(localized: "Yes / no")
            case .choice: return String(localized: "Pick one")
            case .score: return String(localized: "Score")
            }
        }
    }

    let type: Kind
    let instructions: String
    /// `criteria` keys for `.choice`.
    let choices: [String]
    /// Ordered `criteria` levels for `.score`.
    let levels: [String]

    init(type: Kind, instructions: String, choices: [String] = [], levels: [String] = []) {
        self.type = type
        self.instructions = instructions
        self.choices = choices
        self.levels = levels
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case instructions
        case criteria
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(instructions, forKey: .instructions)
        switch type {
        case .noul:
            break
        case .choice:
            guard !choices.isEmpty else { break }
            var criteria = container.nestedContainer(keyedBy: DynamicCodingKey.self, forKey: .criteria)
            for choice in choices {
                try criteria.encodeNil(forKey: DynamicCodingKey(choice))
            }
        case .score:
            guard !levels.isEmpty else { break }
            try container.encode(levels, forKey: .criteria)
        }
    }
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

struct DecisionResponse: Decodable, Equatable {
    let model: String?
    let id: String?
    let provider: String?
    let answers: [String: DecisionAnswer]
    let usage: DecisionUsage?
}

struct DecisionAnswer: Decodable, Equatable {
    let type: String
    let noul: Double?
    let choice: String?
    let score: Double?
    let probabilities: [String: Double]?
    let confidence: Double?
    /// Only for `.score`: level index → human label, as the API returns it.
    /// Captured live on 2026-10-20: `{"0":"Cosmetic","1":"…","2":"Blocking"}`.
    let legend: [String: String]?

    /// One line per answer, shaped for a dense results list.
    var summary: String {
        switch type {
        case "noul":
            guard let noul else { return "—" }
            return "\(Int((noul * 100).rounded()))%"
        case "choice":
            guard let choice else { return "—" }
            if let confidence { return "\(choice) · \(Int((confidence * 100).rounded()))%" }
            return choice
        case "score":
            guard let score else { return "—" }
            // `score` is the expected level index (0-based), not a percentage:
            // 0.83 over three levels means "between level 0 and 1, closest to 1".
            if let label = legendLabel(for: score) {
                return "\(label) · \(String(format: "%.2f", score))"
            }
            return String(format: "%.2f", score)
        default:
            return type
        }
    }

    private func legendLabel(for score: Double) -> String? {
        guard let legend, !legend.isEmpty else { return nil }
        let keys = legend.keys.compactMap { Int($0) }.sorted()
        guard let nearest = keys.min(by: { abs(Double($0) - score) < abs(Double($1) - score) }) else {
            return nil
        }
        return legend[String(nearest)]
    }
}

struct DecisionUsage: Decodable, Equatable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cost: Double?

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cost
    }
}

/// One entry of `GET /api/v1/models?output_modalities=decisions` (27 entries on
/// 2026-10-19).
struct DecisionModelInfo: Decodable, Identifiable, Equatable {
    let id: String
    let name: String?

    var displayName: String { name ?? id }
}

struct DecisionModelsEnvelope: Decodable {
    let data: [DecisionModelInfo]
}
