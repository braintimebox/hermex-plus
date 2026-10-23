import Foundation

/// The compact Nous Portal list the picker shows by default.
///
/// Why a static list: the portal advertises 427 models and the picker's port of
/// entry is a phone screen, not a directory. The list below is the portal's own
/// curated selection intersected with what the endpoint actually served on
/// 2026-10-19 (56 of 57 — `stealth/space-bunny-alpha` is gone from the catalog),
/// plus the free models that answered a real chat completion with text.
///
/// Deliberately absent:
/// - `:batch` and `:US` variants (same model, different endpoint family);
/// - `poolside/laguna-xs-2.1:free`, `stepfun/step-3.7-flash:free` — 200 OK but
///   only reasoning tokens, empty `content`;
/// - `meituan/longcat-2.0:free` — 404 "This model is no longer free";
/// - `meituan/longcat-2.5-preview:free` — timed out; not proven broken, not shown.
///
/// Nothing is deleted: every model outside this set stays reachable through the
/// group's overflow ("show all") list, and the server catalog is untouched.
enum NousCompactCatalog {
    static let providerID = "nous"

    static let modelIDs: Set<String> = [
        "anthropic/claude-fable-5.1",
        "anthropic/claude-fable-5",
        "anthropic/claude-opus-5.5",
        "anthropic/claude-opus-5",
        "anthropic/claude-opus-4.8",
        "anthropic/claude-sonnet-5.5",
        "anthropic/claude-sonnet-5",
        "anthropic/claude-haiku-5.5",
        "anthropic/claude-haiku-4.5",
        "openai/gpt-6-astra",
        "openai/gpt-6-astra-fast",
        "openai/gpt-6-astra-flex",
        "openai/gpt-6-astra-pro",
        "openai/gpt-6-astra-pro-fast",
        "openai/gpt-6-astra-pro-flex",
        "openai/gpt-6.1-sol",
        "openai/gpt-6.1-sol-pro",
        "openai/gpt-6-sol",
        "openai/gpt-6-sol-pro",
        "openai/gpt-6-luna",
        "openai/gpt-6-luna-pro",
        "openai/gpt-5.5",
        "openai/gpt-5.5-pro",
        "openai/gpt-5.4-mini",
        "google/gemini-4-argon",
        "google/gemini-3.1-pro-preview",
        "google/gemini-3.8-flash",
        "google/gemini-3.7-flash",
        "x-ai/grok-4.7",
        "x-ai/grok-4.6",
        "deepseek/deepseek-v4-pro",
        "deepseek/deepseek-v4-pro-0813",
        "deepseek/deepseek-v4.1-flash",
        "deepseek/deepseek-v4.1-flash-1017",
        "deepseek/deepseek-v4-flash-0731",
        "qwen/qwen3.8-max-0902",
        "qwen/qwen3.8-flash",
        "moonshotai/kimi-k3",
        "minimax/minimax-m3",
        "z-ai/glm-5.3",
        "z-ai/glm-5.3-flash",
        "z-ai/glm-5.3-flashx",
        "z-ai/glm-5.2",
        "xiaomi/mimo-v2.6-pro",
        "xiaomi/mimo-v2.6-flash",
        "xiaomi/mimo-v2.6-pro-ultraspeed",
        "xiaomi/mimo-v2.5-pro",
        "tencent/hy4-preview",
        "tencent/hy3",
        "stepfun/step-3.7-flash",
        "nvidia/nemotron-3-super-120b-a12b",
        "meta/muse-spark-1.2",
        "meta/muse-spark-1.3",
        "sakana/fugu-ultra",
        "upstage/solar-pro4",
        "upstage/solar-mini4",
        "poolside/laguna-s-2.1:free",
        "upstage/solar-mini4:free",
        "reflection/beam-1.0-501b-a23b:free",
    ]

    /// Collapses the base Nous group to the compact list while keeping every
    /// other model in the overflow bucket, so the picker never hides a model
    /// the server is willing to serve.
    ///
    /// Derived slices ("Nous Portal · Free", "· Latest") are left alone: they
    /// are category views, not the provider catalog, and compacting them would
    /// empty the FREE and LATEST sections.
    static func compact(_ group: ModelCatalogGroup) -> ModelCatalogGroup {
        guard group.providerID == providerID, !group.name.contains("·") else { return group }
        let all = group.allModels
        let primary = all.filter { isCompact($0.id) }
        let overflow = all.filter { !isCompact($0.id) }
        guard primary.count != all.count else { return group }
        return ModelCatalogGroup(
            id: group.id,
            name: group.name,
            providerID: group.providerID,
            models: primary,
            extraModels: overflow
        )
    }

    /// Server ids may carry the `@provider:` prefix the picker adds for
    /// cross-provider models, so compare the bare id.
    static func isCompact(_ modelID: String) -> Bool {
        modelIDs.contains(modelID) || modelIDs.contains(modelID.bareModelID)
    }
}
