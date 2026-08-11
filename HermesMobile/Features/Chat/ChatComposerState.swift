import Foundation
import Observation

/// Composer state extracted from ChatViewModel — holds model selection,
/// slash-command suggestions, workspace paths, profiles, and reasoning effort.
///
/// Separated so streaming message updates don't invalidate composer UI.
@Observable
final class ChatComposerState {
    var quotedMessage: (messageId: String, author: String, text: String)? = nil

    // Model & catalog
    var modelCatalogGroups: [ModelCatalogGroup] = []
    var isLoadingComposerConfiguration = false
    var isUpdatingComposerConfiguration = false
    var composerConfigurationErrorMessage: String?

    // Profiles
    var profileOptions: [ProfileSummary] = []
    var isSingleProfileMode = false
    var selectedProfileName: String?

    // Reasoning effort
    var selectedReasoningEffort: String?
    var supportedReasoningEfforts: [String]?
    var supportsReasoningEffort: Bool?

    // Workspace
    var workspaceRoots: [WorkspaceRoot] = []
    var workspaceSuggestions: [String] = []

    // Slash commands & personality
    var agentCommands: [AgentCommand] = []
    var personalitySuggestions: [String] = ["none"]
    var skillSlashSuggestions: [SkillSlashSuggestion] = []

    var showsReasoningEffortControl: Bool {
        ReasoningEffortOption.showsEffortControl(
            supportsReasoningEffort: supportsReasoningEffort,
            supportedEfforts: supportedReasoningEfforts
        )
    }
}
