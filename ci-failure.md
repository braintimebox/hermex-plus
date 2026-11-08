# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42505854207
Commit: fade45ff413af3571d3ef5d99282b34528a018a1

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotAvatarTests.swift:135:24: error: type 'BotAvatarFixtureWire' does not conform to protocol 'BotTransport'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/BotConversationTests.swift:720:24: error: type 'BotFixtureWire' does not conform to protocol 'BotTransport'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/ChatAttachmentCoordinatorTests.swift:521:15: error: type 'RecordingAttachmentStore' does not conform to protocol 'ChatDraftAttachmentStoring'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/ChatDraftStoreTests.swift:1173:15: error: type 'RecordingChatDraftAttachmentStore' does not conform to protocol 'ChatDraftAttachmentStoring'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/ChatStreamCoordinatorTests.swift:2413:21: error: type 'CoordinatorSpyLiveActivityManager' does not conform to protocol 'AgentLiveActivityManaging'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/ChatViewModelSendTests.swift:10026:21: error: type 'SpyChatLiveActivityManager' does not conform to protocol 'AgentLiveActivityManaging'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/ChatViewModelSendTests.swift:10088:15: error: type 'RecordingSendDraftAttachmentStore' does not conform to protocol 'ChatDraftAttachmentStoring'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobileTests/LiveActivityTests.swift:1218:21: error: type 'SpyAgentLiveActivityManager' does not conform to protocol 'AgentLiveActivityManaging'
```
