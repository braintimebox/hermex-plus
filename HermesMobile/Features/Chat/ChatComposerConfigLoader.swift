import Foundation

struct ChatComposerConfigState: Equatable, Sendable {
    var currentWorkspace: String?
    var currentModel: String?
    var currentModelProvider: String?
    var currentProfile: String?
    var selectedProfileName: String?
    var selectedReasoningEffort: String?
    /// Model-aware effort vocabulary (`supported_efforts`); `nil` on older
    /// servers → composer falls back to the full static list (issue #18).
    var supportedReasoningEfforts: [String]?
    /// `supports_reasoning_effort`; `false` hides the effort control, `nil`
    /// (older servers) keeps it visible.
    var supportsReasoningEffort: Bool?
    var modelCatalogGroups: [ModelCatalogGroup]
    var agentCommands: [AgentCommand]
    var workspaceRoots: [WorkspaceRoot]
    var workspaceSuggestions: [String]
    var profileOptions: [ProfileSummary]
    var isSingleProfileMode: Bool

    init(
        currentWorkspace: String? = nil,
        currentModel: String? = nil,
        currentModelProvider: String? = nil,
        currentProfile: String? = nil,
        selectedProfileName: String? = nil,
        selectedReasoningEffort: String? = nil,
        supportedReasoningEfforts: [String]? = nil,
        supportsReasoningEffort: Bool? = nil,
        modelCatalogGroups: [ModelCatalogGroup] = [],
        agentCommands: [AgentCommand] = [],
        workspaceRoots: [WorkspaceRoot] = [],
        workspaceSuggestions: [String] = [],
        profileOptions: [ProfileSummary] = [],
        isSingleProfileMode: Bool = false
    ) {
        self.currentWorkspace = currentWorkspace
        self.currentModel = currentModel
        self.currentModelProvider = currentModelProvider
        self.currentProfile = currentProfile
        self.selectedProfileName = selectedProfileName
        self.selectedReasoningEffort = selectedReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.supportsReasoningEffort = supportsReasoningEffort
        self.modelCatalogGroups = modelCatalogGroups
        self.agentCommands = agentCommands
        self.workspaceRoots = workspaceRoots
        self.workspaceSuggestions = workspaceSuggestions
        self.profileOptions = profileOptions
        self.isSingleProfileMode = isSingleProfileMode
    }
}

struct ChatComposerConfigLoadResult: Sendable {
    let state: ChatComposerConfigState
    let configurationError: Error?
}

struct ChatComposerConfigLoader {
    private let client: APIClient
    /// In-memory cache survives background/foreground transitions (iOS keeps the process alive).
    /// TTL = 24 hours because models, profiles, and workspaces rarely change.
    private static var memoryCache: (state: ChatComposerConfigState, timestamp: Date)?
    private static let cacheTTL: TimeInterval = 86_400

    init(client: APIClient) {
        self.client = client
    }

    func loadConfiguration(from initialState: ChatComposerConfigState) async -> ChatComposerConfigLoadResult {
        // Return cached state if fresh. iOS keeps the process alive across
        // background/foreground transitions, so this cache typically survives all day.
        if let (cachedState, ts) = Self.memoryCache,
           ts.timeIntervalSinceNow > -Self.cacheTTL,
           !cachedState.modelCatalogGroups.isEmpty {
            var result = cachedState
            result.currentProfile = initialState.currentProfile
            result.currentWorkspace = initialState.currentWorkspace
            result.currentModel = initialState.currentModel
            result.currentModelProvider = initialState.currentModelProvider
            return ChatComposerConfigLoadResult(state: result, configurationError: nil)
        }
        var state = initialState
        var configurationError: Error?

        do {
            let profilesResponse = try await client.profiles()
            state.profileOptions = profilesResponse.profiles ?? []
            state.isSingleProfileMode = profilesResponse.singleProfileMode ?? false
            state.selectedProfileName = Self.nonEmpty(state.currentProfile)
                ?? Self.nonEmpty(profilesResponse.active)
                ?? profilesResponse.effectiveDefaultProfileName

            if let sessionProfile = Self.nonEmpty(state.currentProfile),
               Self.nonEmpty(profilesResponse.active) != sessionProfile {
                let switchResponse = try await client.switchProfile(name: sessionProfile)
                state.profileOptions = switchResponse.profiles ?? state.profileOptions
                state.selectedProfileName = Self.nonEmpty(switchResponse.active) ?? sessionProfile
                state.currentProfile = state.selectedProfileName

                if state.currentWorkspace == nil {
                    state.currentWorkspace = Self.nonEmpty(switchResponse.defaultWorkspace)
                }

                if state.currentModel == nil {
                    state.currentModel = Self.nonEmpty(switchResponse.defaultModel)
                }
            }

            let selectedProfile = Self.profileSummary(
                matching: state.selectedProfileName,
                in: state.profileOptions
            )
            if state.currentModel == nil {
                state.currentModel = Self.nonEmpty(selectedProfile?.model)
            }

            // Fetch models + workspaces in parallel (independent calls)
            async let modelsTask = client.models()
            async let workspacesTask = client.workspaces()

            let modelsResponse = try await modelsTask
            state.modelCatalogGroups = modelsResponse.catalogGroups
            if state.currentModel == nil {
                state.currentModel = modelsResponse.defaultModel
            }
            if Self.nonEmpty(state.currentModelProvider) == nil {
                state.currentModelProvider = Self.nonEmpty(selectedProfile?.provider)
                    ?? Self.uniqueProvider(for: state.currentModel, in: state.modelCatalogGroups)
            }

            // Fetch reasoning (depends on model) + workspaces result in parallel
            async let reasoningTask = client.reasoning(
                model: Self.nonEmpty(state.currentModel),
                provider: Self.nonEmpty(state.currentModelProvider)
            )
            let workspaceResponse = try await workspacesTask

            let reasoningResponse = try await reasoningTask
            state.selectedReasoningEffort = reasoningResponse.effectiveEffort
            state.supportedReasoningEfforts = reasoningResponse.normalizedSupportedEfforts
            state.supportsReasoningEffort = reasoningResponse.supportsReasoningEffort

            state.workspaceRoots = workspaceResponse.workspaces ?? []
            if state.currentWorkspace == nil {
                state.currentWorkspace = workspaceResponse.last ?? state.workspaceRoots.compactMap(\.path).first
            }
            state.workspaceSuggestions = state.workspaceRoots.compactMap(\.path)
        } catch {
            configurationError = error
        }

        do {
            state.agentCommands = (try await client.commands()).commands ?? []
        } catch {
            state.agentCommands = []
        }

        let result = ChatComposerConfigLoadResult(
            state: state,
            configurationError: configurationError
        )
        if configurationError == nil {
            updateCache(state)
        }
        return result
    }

    private func updateCache(_ state: ChatComposerConfigState) {
        Self.memoryCache = (state, Date())
    }

    private static func profileSummary(
        matching profileName: String?,
        in profileOptions: [ProfileSummary]
    ) -> ProfileSummary? {
        guard let profileName = nonEmpty(profileName) else { return nil }
        return profileOptions.first { $0.normalizedName == profileName }
    }

    private static func uniqueProvider(
        for modelID: String?,
        in groups: [ModelCatalogGroup]
    ) -> String? {
        guard let modelID = nonEmpty(modelID) else { return nil }
        let providers = Set(
            groups
                .flatMap(\.slashAutocompleteModels)
                .filter { $0.id == modelID }
                .compactMap { nonEmpty($0.providerID) }
        )
        return providers.count == 1 ? providers.first : nil
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == false ? trimmed : nil
    }
}
