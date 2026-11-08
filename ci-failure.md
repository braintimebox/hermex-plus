# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/42493784732
Commit: 65eae953ca22a63d60b11451e4bdce3bcda89487

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Chat/ChatAttachmentPreviewView.swift:145:9: error: switch must be exhaustive
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Chat/ChatAttachmentPreviewView.swift:243:13: error: switch must be exhaustive
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Chat/ChatAttachmentPreviewView.swift:314:9: error: switch must be exhaustive
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Chat/MessageBubbleView.swift:337:18: error: generic parameter 'V' could not be inferred
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Chat/MessageBubbleView.swift:337:30: error: cannot convert value of type 'KeyPath<EnvironmentValues, Value>' to expected argument type 'WritableKeyPath<EnvironmentValues, V>'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Chat/MessageBubbleView.swift:337:30: error: value of type 'EnvironmentValues' has no member 'markdownTableEdgeFadeColor'
```
