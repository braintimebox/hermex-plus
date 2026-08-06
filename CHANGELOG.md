# Changelog

## 1.1.0 — 2026-08-06

### Data Channels — Apple Health

- `HermesMobile/Features/DataChannels/AppleHealthProvider.swift`: HealthKit singleton. 35+ metrics across Activity, Body, Heart, Vitals, Sleep, Nutrition, Environment. `[TRACKER]` prefix triggers focus-tracker skill. Uses `startBackground` for fire-and-forget delivery.
- `HermesMobile/Features/DataChannels/DataChannelsSettings.swift`: `UserDefaults` keys.
- `HermesMobile/Resources/HermesMobile.entitlements`: `com.apple.developer.healthkit`.
- `HermesMobile/Resources/Info.plist`: `NSHealthShareUsageDescription` + `fetch` background mode for auto-sync.
- `HermesMobile/Features/DataChannels/HealthBackgroundTask.swift`: BGTaskScheduler auto-sync every 1-4h. Works with any Hermes server that has `focus-tracker` skill.
- `HermesMobile/HermesMobileApp.swift`: register BGTask at app launch.
- `HermesMobile/Features/Settings/SettingsView.swift`: «Data Channels» card: Apple Health toggle + «Sync Now». Persistent session + server URL storage for background tasks.
- `README.md`: setup instructions for any fork user.

## 1.0.0 — 2026-08-05

Forked from [Hermex](https://github.com/uzairansaruzi/hermex) `master`. Three surgical changes applied:

### App name → "Hermes Plus"
- `HermesMobile.xcodeproj/project.pbxproj`: `APP_DISPLAY_NAME = "Hermes Plus"`
- `HermesMobile/Features/SessionList/SessionListView.swift`: `HermesHeaderLogo` — original graphic "Hermes" logo + "Plus" text label in `HStack`
- `HermesMobile/Features/Onboarding/OnboardingWelcomePage.swift`: accessibility label updated

### Swipe gestures removed
- `HermesMobile/Features/SessionList/SessionListComponents.swift`: `.swipeActions(edge: .leading)` and `.swipeActions(edge: .trailing)` removed
- Helper functions `sessionLeadingSwipeActions` / `sessionTrailingSwipeActions` deleted
- All session actions (pin, archive, delete) remain available via long-press `.contextMenu`

### Unsigned IPA CI
- `.github/workflows/build-ipa.yml`: GitHub Actions workflow with `macos-26` runner (Xcode 26 beta for `Glass` API)
- `xcodebuild build` (not `archive`) to avoid extension signing issues
- `.app` → Payload → `.ipa` → uploaded as artifact (30-day retention)

### Documentation
- `README.md`: fork notice, diff table, IPA download instructions
- `CHANGELOG.md`: this file
