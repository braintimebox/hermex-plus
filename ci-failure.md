# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42517069543
Commit: 58f234c4f4d9ff3144e58a4079b043ac727c2d36

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/ChatStreamCoordinatorTests.swift:2413:21: error: type 'CoordinatorSpyLiveActivityManager' does not conform to protocol 'AgentLiveActivityManaging'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/ChatViewModelSendTests.swift:10026:21: error: type 'SpyChatLiveActivityManager' does not conform to protocol 'AgentLiveActivityManaging'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/LiveActivityTests.swift:1218:21: error: type 'SpyAgentLiveActivityManager' does not conform to protocol 'AgentLiveActivityManaging'
```
