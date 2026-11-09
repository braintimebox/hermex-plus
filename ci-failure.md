# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42571532114
Commit: 27da232f7a1b5188838e7abff3edf8e6a691b3d0

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotActivity.swift:211:21: error: argument 'rowID' must precede argument 'displayKind'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotActivity.swift:276:115: error: missing argument for parameter 'id' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:228:17: error: cannot find 'SendChoiceCard' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:239:16: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:316:38: error: extra arguments at positions #12, #22 in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:335:25: error: cannot find 'ComposerRecall' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:396:33: error: extra argument 'supportsVoiceNotes' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:441:20: error: cannot call value of non-function type 'Binding<Subject>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:441:20: error: value of type 'ComposerVoiceInputController' has no dynamic member 'scheduleToggle' using key path from root type 'ComposerVoiceInputController'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatComposerView.swift:441:9: error: referencing subscript 'subscript(dynamicMember:)' requires wrapper 'Binding<ComposerVoiceInputController>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatView.swift:441:26: error: type 'ChatScrollPolicy' has no member 'showsScrollToBottomButton'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatView.swift:73:21: error: the compiler is unable to type-check this expression in reasonable time; try breaking up the expression into distinct sub-expressions
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotChatView.swift:76:29: error: 'LoadOlderMessagesButton' is inaccessible due to 'private' protection level
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotConversation.swift:499:44: error: cannot convert value of type '_' to expected argument type 'String'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotConversation.swift:502:10: error: missing argument for parameter 'apiClient' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotPendingRequest.swift:113:9: error: cannot find 'ApprovalScope' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotPendingRequest.swift:115:20: error: cannot infer contextual base in reference to member 'hermes'
```
