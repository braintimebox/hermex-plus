import BackgroundTasks
import Foundation

/// Manages BGAppRefreshTask for Data Channels auto-sync.
/// iOS wakes the app periodically (1-4h intervals), runs sync, schedules next task.
enum HealthBackgroundTask {
    static let identifier = "com.hermesplus.health-sync"

    /// Call once at app launch.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task {
                await handleRefresh(task: task as! BGAppRefreshTask)
            }
        }
    }

    /// Schedule next background sync. Call after each successful sync (foreground or background).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // iOS decides exact timing; 1 hour minimum suggested
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Silently fail — iOS may refuse scheduling under certain conditions
        }
    }

    private static func handleRefresh(task: BGAppRefreshTask) async {
        // Schedule next before work — if we crash, next one still fires
        schedule()

        task.expirationHandler = {}

        let provider = AppleHealthProvider.shared
        guard provider.isAuthorized else {
            task.setTaskCompleted(success: true)
            return
        }

        do {
            guard let message = try await provider.syncToday() else {
                task.setTaskCompleted(success: true)
                return
            }

            guard let serverURL = storedServerURL() else {
                task.setTaskCompleted(success: false)
                return
            }

            let sessionID = UserDefaults.standard.string(forKey: DataChannelsSettings.dataChannelsSessionIDKey) ?? ""

            let client = APIClient(baseURL: serverURL)

            // Create session if needed
            var sid = sessionID
            if sid.isEmpty {
                let session = try await client.createSession(
                    workspace: nil, model: nil, modelProvider: nil, profile: nil
                )
                guard let newID = session.session?.sessionId else {
                    task.setTaskCompleted(success: false)
                    return
                }
                sid = newID
                UserDefaults.standard.set(sid, forKey: DataChannelsSettings.dataChannelsSessionIDKey)
            }

            // Fire-and-forget to agent
            _ = try await client.startBackground(sessionID: sid, prompt: message)
            task.setTaskCompleted(success: true)
        } catch {
            task.setTaskCompleted(success: false)
        }
    }

    private static func storedServerURL() -> URL? {
        // AuthManager stores servers; we need the active one.
        // For simplicity, store the server URL in UserDefaults when the user
        // connects — AuthManager already persists accounts.
        // We read the first server from the catalog (user typically has one).
        guard let rawURL = UserDefaults.standard.string(forKey: "dataChannels.serverURL"),
              let url = URL(string: rawURL) else {
            // Fallback: try to read from AuthManager's persistent store
            return nil
        }
        return url
    }
}
