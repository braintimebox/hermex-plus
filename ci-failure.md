# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42492418366
Commit: 871c29fe00df6f0f0676fbd2d184cc57d76d3059

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotArtifactMessageView.swift:168:91: error: extra trailing closure passed in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotArtifactMessageView.swift:93:38: error: cannot convert value of type 'KeyPath<EnvironmentValues, Value>' to expected argument type 'WritableKeyPath<EnvironmentValues, Bool>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotArtifactMessageView.swift:93:38: error: value of type 'EnvironmentValues' has no member 'allowsStreamedTextAnimation'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatControlViews.swift:17:51: error: extra argument 'allowsEffortChanges' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatControlViews.swift:71:35: error: extra argument 'allowsCustomPath' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotDeepLink.swift:115:43: error: value of type 'ServerAccount' has no member 'kind'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotDeepLink.swift:115:52: error: cannot infer contextual base in reference to member 'hermes'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotDelegatedWorkView.swift:347:10: error: value of type 'NavigationStack<NavigationPath, some View>' has no member 'transcriptLinks'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotFilePathSearch.swift:27:77: error: 'nil' is not compatible with closure result type 'ComposerFilePathSearch.Match'
```
