# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42595918006
Commit: a0e76b5bed83ec153916688dd0344edbac0c26a1

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:46:58: error: value of type 'BotPromptMode' has no member 'method'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:48:42: error: cannot convert value of type 'T?' to expected argument type 'T'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:48:59: error: type 'Equatable' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:49:42: error: cannot convert value of type 'T?' to expected argument type 'T'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:49:53: error: type 'Equatable' has no member 'string'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:50:72: error: type 'Equatable' has no member 'bool'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:52:61: error: value of type 'BotPromptMode' has no member 'method'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:63:38: error: value of type 'BotPromptMode' has no member 'method'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:113:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:114:37: error: type 'Equatable' has no member 'needsAttention'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:120:29: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:120:53: error: cannot infer contextual base in reference to member 'session'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:134:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:135:29: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:135:53: error: cannot infer contextual base in reference to member 'once'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:138:48: error: type 'Equatable' has no member 'connected'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:146:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:147:29: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:147:53: error: cannot infer contextual base in reference to member 'always'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:155:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:156:23: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:159:47: error: cannot infer contextual base in reference to member 'once'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:169:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:170:24: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:174:48: error: cannot infer contextual base in reference to member 'once'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:184:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:186:29: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:186:53: error: cannot infer contextual base in reference to member 'deny'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:188:48: error: type 'Equatable' has no member 'disconnected'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:206:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:208:29: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:208:53: error: cannot infer contextual base in reference to member 'once'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:210:48: error: type 'Equatable' has no member 'connected'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:219:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:232:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:233:29: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:233:53: error: cannot infer contextual base in reference to member 'once'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:247:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:250:36: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:271:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:272:36: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:289:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:290:36: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:308:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:309:36: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:313:34: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:330:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:331:36: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:349:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:350:36: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:365:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:366:34: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:377:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:388:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:398:38: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:409:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:414:36: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:425:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:430:38: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:432:48: error: type 'Equatable' has no member 'connected'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:442:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:447:38: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:449:48: error: type 'Equatable' has no member 'disconnected'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:457:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:462:21: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:480:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:495:20: error: cannot find 'make' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:495:44: error: cannot find 'connection' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:496:21: error: cannot find 'make' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:496:46: error: cannot find 'connection' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:500:28: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:500:51: error: cannot infer contextual base in reference to member 'deny'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:510:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:511:21: error: cannot find 'action' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:514:45: error: cannot infer contextual base in reference to member 'once'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:526:27: error: cannot find 'blocked' in scope
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotPendingRequestTests.swift:529:37: error: type 'Equatable' has no member 'needsAttention'
```
