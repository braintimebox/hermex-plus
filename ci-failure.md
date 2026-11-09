# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42691987379
Commit: 6b8fb071ed2bd46d1bcd97c5abf2ca70d56525c3

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:179:25: error: referencing subscript 'subscript(dynamicMember:)' requires wrapper 'Binding<ComposerVoiceInputController>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:179:36: error: cannot call value of non-function type 'Binding<Subject>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:179:36: error: value of type 'ComposerVoiceInputController' has no dynamic member 'suspend' using key path from root type 'ComposerVoiceInputController'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:260:38: error: referencing subscript 'subscript(dynamicMember:)' requires wrapper 'Binding<ComposerVoiceInputController>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:260:49: error: cannot call value of non-function type 'Binding<Subject>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:260:49: error: value of type 'ComposerVoiceInputController' has no dynamic member 'suspend' using key path from root type 'ComposerVoiceInputController'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatView.swift:142:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
```
