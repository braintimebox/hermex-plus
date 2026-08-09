import SwiftUI
import SwiftData
import BackgroundTasks

struct HermexSceneActions {
    let canCreateNewChat: Bool
    let createNewChat: () -> Void
    let searchSessions: () -> Void
}

private struct HermexSceneActionsKey: FocusedValueKey {
    typealias Value = HermexSceneActions
}

extension FocusedValues {
    var hermexSceneActions: HermexSceneActions? {
        get { self[HermexSceneActionsKey.self] }
        set { self[HermexSceneActionsKey.self] = newValue }
    }
}

struct HermexCommands: Commands {
    @FocusedValue(\.hermexSceneActions) private var actions

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Chat") {
                actions?.createNewChat()
            }
            .keyboardShortcut("n", modifiers: .command)
            .disabled(actions?.canCreateNewChat != true)
        }

        CommandGroup(after: .newItem) {
            Button("Search Sessions") {
                actions?.searchSessions()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(actions == nil)
        }
    }
}

@main
struct HermesMobileApp: App {
    @State private var authManager = AuthManager()
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BackgroundTaskManager.register()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            // Launch argument hook so the Streaming Lab can be opened without
            // UI navigation (agent-driven simulator diagnosis, issue #234):
            // `xcrun simctl launch <udid> com.uzairansar.hermesmobile --streaming-lab`
            if ProcessInfo.processInfo.arguments.contains("--streaming-lab") {
                NavigationStack {
                    StreamingLabView()
                }
            } else {
                ContentView(authManager: authManager)
                    .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            }
            #else
            ContentView(authManager: authManager)
                .preferredColorScheme(AppTheme.storedValue(appThemeRawValue).colorScheme)
            #endif
        }
        .modelContainer(for: [CachedSession.self, CachedMessage.self, SavedMessage.self, PendingScheduledMessage.self])
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundTaskManager.scheduleNext()
            }
        }
        .backgroundTask(.appRefresh(BackgroundTaskManager.refreshIdentifier)) {
            await handleBackgroundRefresh()
        }
        .commands {
            HermexCommands()
            SidebarCommands()
        }
    }
}

// MARK: - Background Refresh

private func handleBackgroundRefresh() async {
    UserDefaults.standard.set(Date(), forKey: "hermes_last_bg_refresh_ts")
    BackgroundTaskManager.scheduleNext()
}
