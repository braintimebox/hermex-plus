# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42574786221
Commit: 3e49fdbbc06a42f5fc489bd38fb0ed27c1a4e9f7

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:21:48: error: type 'BotConnection' has no member 'testedHermesVersion'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:27:33: error: value of type 'BotConnection' has no member 'untestedVersionNote'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:28:50: error: type 'BotConnection' has no member 'testedHermesVersion'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:29:33: error: value of type 'BotConnection' has no member 'untestedVersionNote'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:31:24: error: generic parameter 'T' could not be inferred
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:31:45: error: value of type 'BotConnection' has no member 'untestedVersionNote'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:32:78: error: type 'BotConnection' has no member 'testedHermesVersion'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConnectionVersionTests.swift:39:33: error: value of type 'BotConnection' has no member 'untestedVersionNote'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:156:31: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:159:28: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:179:31: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:185:28: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:198:30: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:198:75: error: value of type 'BotPromptOutcome' has no member 'receipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:203:28: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:211:30: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:211:75: error: value of type 'BotPromptOutcome' has no member 'receipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:215:28: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:46:34: error: value of type 'BotConversation' has no member 'promptReceipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:46:92: error: value of type 'BotPromptOutcome' has no member 'receipt'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:47:58: error: value of type 'BotPromptMode' has no member 'method'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:49:42: error: cannot convert value of type 'T?' to expected argument type 'T'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:49:59: error: type 'Equatable' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:50:42: error: cannot convert value of type 'T?' to expected argument type 'T'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:50:53: error: type 'Equatable' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:51:72: error: type 'Equatable' has no member 'bool'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:53:61: error: value of type 'BotPromptMode' has no member 'method'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:64:38: error: value of type 'BotPromptMode' has no member 'method'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:113:27: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:115:27: error: cannot infer contextual base in reference to member 'object'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:115:50: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:115:75: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:116:46: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:118:38: error: type 'Equatable' has no member 'credential'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:122:28: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:123:33: error: value of type 'BotCredentialRequest.Kind' has no member 'respondMethod'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:126:55: error: value of type 'BotCredentialRequest.Kind' has no member 'valueKey'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:127:57: error: value of type 'BotCredentialRequest.Kind' has no member 'valueKey'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:133:22: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:133:86: error: cannot infer contextual base in reference to member 'object'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:134:22: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:135:59: error: cannot infer contextual base in reference to member 'object'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:135:82: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:140:48: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:141:50: error: cannot infer contextual base in reference to member 'object'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:141:73: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:151:87: error: type 'BotDesktopTaskRequest.Kind' has no member 'mcpSetup'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:156:17: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:157:54: error: cannot infer contextual base in reference to member 'object'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:157:77: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:158:18: error: type 'Equatable' has no member 'desktopTask'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:160:28: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:166:67: error: cannot convert value of type 'KeyPath<Root, Value>' to expected argument type 'Predicate<BotDesktopTaskRequest.Kind>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:166:67: error: cannot infer key path type from context; consider explicitly specifying a root type
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:166:94: error: type 'Array<BotDesktopTaskRequest.Kind>.ArrayLiteralElement' (aka 'BotDesktopTaskRequest.Kind') has no member 'mcpSetup'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:167:67: error: cannot convert value of type 'KeyPath<Root, Value>' to expected argument type 'Predicate<BotDesktopTaskRequest.Kind>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:167:67: error: cannot infer key path type from context; consider explicitly specifying a root type
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:167:86: error: type 'Array<BotDesktopTaskRequest.Kind>.ArrayLiteralElement' (aka 'BotDesktopTaskRequest.Kind') has no member 'mcpSetup'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:168:51: error: type 'BotDesktopTaskRequest.Kind' has no member 'mcpSetup'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:170:24: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:170:88: error: cannot infer contextual base in reference to member 'object'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:171:25: error: type 'Equatable' has no member 'desktopTask'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:171:83: error: 'nil' is not compatible with expected argument type 'String'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:175:22: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:175:89: error: cannot infer contextual base in reference to member 'null'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:176:22: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:176:84: error: cannot infer contextual base in reference to member 'null'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:177:22: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:179:22: error: cannot find 'BotStreamRequest' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:180:59: error: cannot infer contextual base in reference to member 'object'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:180:82: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:460:28: error: value of type 'BotConversation' has no member 'streamRequest'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:491:28: error: value of type 'BotConversation' has no member 'streamRequest'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:564:28: error: value of type 'BotConversation' has no member 'streamRequest'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:684:30: error: value of type 'BotConversation' has no member 'streamRequest'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:685:25: error: type 'Equatable' has no member 'desktopTask'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:713:29: error: value of type 'BotConversation' has no member 'mayDecline'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:715:21: error: value of type 'BotConversation' has no member 'declineDesktopTask'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:720:28: error: value of type 'BotConversation' has no member 'streamRequest'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:733:30: error: value of type 'BotConversation' has no member 'mayDecline'
```
