# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42570312417
Commit: a5d9976aed9dd2f2a78821dc76f3d5dafad3e77c

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:100:116: error: extra argument 'onResolveHeldMessage' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:100:75: error: missing argument for parameter 'isFocused' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:22:116: error: extra argument 'onResolveHeldMessage' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:22:75: error: missing argument for parameter 'isFocused' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:253:29: error: value of type 'BotConversation' has no member 'mayDecline'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:44:116: error: extra argument 'onResolveHeldMessage' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:44:75: error: missing argument for parameter 'isFocused' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:465:82: error: missing argument for parameter 'transcriptMediaCacheNamespace' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:65:116: error: extra argument 'onResolveHeldMessage' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotChatPresentationTests.swift:65:75: error: missing argument for parameter 'isFocused' in call
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:126:90: error: contextual closure type '(URLRequest) -> any BotSocket' expects 1 argument, but 2 were used in closure body
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:131:29: error: value of type 'BotConnection' has no member 'untestedVersionNote'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:142:90: error: contextual closure type '(URLRequest) -> any BotSocket' expects 1 argument, but 2 were used in closure body
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:32:90: error: contextual closure type '(URLRequest) -> any BotSocket' expects 1 argument, but 2 were used in closure body
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:33:32: error: value of type 'URLRequest' has no member 'scheme'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:45:13: error: type 'Any' cannot conform to 'Equatable'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:47:80: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:71:90: error: contextual closure type '(URLRequest) -> any BotSocket' expects 1 argument, but 2 were used in closure body
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:73:101: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:73:67: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:75:106: error: type 'Any' has no member 'bool'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:75:72: error: type 'Any' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:94:90: error: contextual closure type '(URLRequest) -> any BotSocket' expects 1 argument, but 2 were used in closure body
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:97:44: error: value of type 'BotPromptMode' has no member 'method'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotClientTests.swift:97:57: error: value of type 'BotPromptMode' has no member 'params'
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
```
