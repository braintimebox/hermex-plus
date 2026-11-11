# Compile failure

Run: https://github.com/braintimebox/hermex-plus/actions/runs/43024286646
Commit: e17399881e21471b740c865ccba81dd20e7221ea

```
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotActivity.swift:183:41: error: cannot convert value of type '[String : BotJSON]?' to expected argument type '[String : JSONValue]?'
/Users/runner/work/hermex-plus/hermex-plus/HermesMobile/Features/Bots/BotActivity.swift:225:41: error: cannot assign value of type '(String, [String], Double?, Int?, [String : JSONValue]?, String?)' to type '(id: String, parts: [String], timestamp: Double?, rowID: Int?, displayMetadata: [String : BotJSON]?, displayKind: String?)?'
```
