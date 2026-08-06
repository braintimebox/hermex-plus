import BackgroundTasks
import Foundation
import os

/// Manages BGAppRefreshTask for Data Channels auto-sync.
/// iOS wakes the app periodically (1-4h intervals), runs sync, schedules next task.
enum HealthBackgroundTask {
    static let identifier = "com.hermesplus.health-sync"

    private static let log = Logger(subsystem: "com.hermesplus", category: "health-bg-task")

    /// Call once at app launch.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            Task {
                await handleRefresh(task: task as! BGAppRefreshTask)
            }
        }
        log.info("BGTask registered: \(identifier)")
    }

    /// Schedule next background sync. Call after each successful sync (foreground or background).
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        // iOS decides exact timing; 1 hour minimum suggested
        request.earliestBeginDate = Date(timeIntervalSinceNow: 3600)

        do {
            try BGTaskScheduler.shared.submit(request)
            log.debug("BGTask scheduled: earliestBeginDate +1h")
        } catch {
            log.error("BGTask schedule failed: \(error.localizedDescription)")
        }
    }

    private static func handleRefresh(task: BGAppRefreshTask) async {
        // Schedule next before work — if we crash, next one still fires
        schedule()

        task.expirationHandler = {
            log.warning("BGTask expired before completion")
        }

        let provider = AppleHealthProvider.shared
        guard provider.isAuthorized else {
            task.setTaskCompleted(success: true)
            return
        }

        do {
            guard let message = try await provider.syncToday() else {
                log.info("No health data — skipping BG sync")
                task.setTaskCompleted(success: true)
                return
            }

            // We need the active server URL. Use the stored session ID as a proxy —
            // the regular Settings→Sync flow persists a session. For BG, we need
            // a stored server base URL.
            // Fallback: read from UserDefaults (set when user enables Data Channels)
            guard let serverURL = storedServerURL() else {
                log.warning("No stored server URL — skipping BG sync")
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
            log.info("BG sync sent: \(provider.lastSyncDate?.description ?? "?")")
            task.setTaskCompleted(success: true)
        } catch {
            log.error("BG sync failed: \(error.localizedDescription)")
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
