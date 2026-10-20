import Foundation

/// Thin client for OpenRouter's Decisions API (alpha).
///
/// This is the one place in the app that talks to OpenRouter directly instead of
/// the user's Hermes server, because the server exposes no decisions endpoint and
/// decisions models cannot be routed through `/chat/completions`. The key is
/// optional and user-supplied; without it the screen stays read-only.
struct DecisionsClient: Sendable {
    static let decisionsURL = URL(string: "https://openrouter.ai/api/alpha/decisions")!
    static let modelsURL = URL(string: "https://openrouter.ai/api/v1/models?output_modalities=decisions")!

    enum ClientError: LocalizedError, Equatable {
        case missingKey
        case unauthorized
        case insufficientCredits
        case rateLimited
        case emptyAnswers
        case http(Int, String)
        case decoding

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return String(localized: "Add an OpenRouter API key first.")
            case .unauthorized:
                return String(localized: "OpenRouter rejected the key (401).")
            case .insufficientCredits:
                return String(localized: "OpenRouter reports no credits for this key (402).")
            case .rateLimited:
                return String(localized: "Rate limited by OpenRouter (429). Try again shortly.")
            case .emptyAnswers:
                return String(localized: "The model answered nothing.")
            case .http(let status, let message):
                return "HTTP \(status): \(message)"
            case .decoding:
                return String(localized: "Unexpected response shape.")
            }
        }
    }

    var session: URLSession = .shared

    func decide(_ request: DecisionRequest, apiKey: String) async throws -> DecisionResponse {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ClientError.missingKey
        }
        var urlRequest = URLRequest(url: Self.decisionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        try Self.validate(response, data: data)

        guard let decoded = try? JSONDecoder().decode(DecisionResponse.self, from: data) else {
            throw ClientError.decoding
        }
        guard !decoded.answers.isEmpty else { throw ClientError.emptyAnswers }
        return decoded
    }

    func availableModels(apiKey: String) async throws -> [DecisionModelInfo] {
        var urlRequest = URLRequest(url: Self.modelsURL)
        if !apiKey.isEmpty {
            urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: urlRequest)
        try Self.validate(response, data: data)
        guard let envelope = try? JSONDecoder().decode(DecisionModelsEnvelope.self, from: data) else {
            throw ClientError.decoding
        }
        return envelope.data
    }

    private static func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401: throw ClientError.unauthorized
            case 402: throw ClientError.insufficientCredits
            case 429: throw ClientError.rateLimited
            default:
                throw ClientError.http(http.statusCode, Self.errorMessage(from: data))
            }
        }
    }

    /// OpenRouter wraps failures as `{"error":{"message":…,"code":…}}`; fall back
    /// to the raw prefix so an unexpected body still says something.
    static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable {
            struct Inner: Decodable { let message: String? }
            let error: Inner?
        }
        if let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
           let message = envelope.error?.message {
            return message
        }
        return String(decoding: data.prefix(200), as: UTF8.self)
    }
}
