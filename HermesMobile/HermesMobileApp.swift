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

private enum BGTask {
    static let refreshID = "com.uzairansar.hermesmobile.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { task in
            guard let t = task as? BGAppRefreshTask else { return }
            t.expirationHandler = { t.setTaskCompleted(success: false) }
            UserDefaults.standard.set(Date(), forKey: "hermes_last_bg_refresh_ts")
            t.setTaskCompleted(success: true)
            scheduleNext()
        }
    }

    static func scheduleNext() {
        let req = BGAppRefreshTaskRequest(identifier: refreshID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        try? BGTaskScheduler.shared.submit(req)
    }
}

@main
struct HermesMobileApp: App {
    @State private var authManager = AuthManager()
    @AppStorage(AppTheme.storageKey) private var appThemeRawValue = AppTheme.system.rawValue
    @Environment(\.scenePhase) private var scenePhase

    init() {
        BGTask.register()
        MainThreadWatchdog.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
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
            switch newPhase {
            case .active:
                HermexLogger.shared.log(type: "event", message: "scene active")
            case .background:
                HermexLogger.shared.log(type: "event", message: "scene background")
                BGTask.scheduleNext()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .backgroundTask(.appRefresh(BGTask.refreshID)) {
            UserDefaults.standard.set(Date(), forKey: "hermes_last_bg_refresh_ts")
            BGTask.scheduleNext()
        }
        .commands {
            HermexCommands()
            SidebarCommands()
        }
    }
}
