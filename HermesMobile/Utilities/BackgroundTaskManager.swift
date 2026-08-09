import Foundation
import BackgroundTasks

/// Registers a periodic background refresh for Hermes Plus.
/// iOS decides the exact timing — we request ~4 hours, system grants based on
/// battery, usage patterns, and network availability.
///
/// Impact: ~0.5% battery per day (5 seconds of radio every 4 hours).
enum BackgroundTaskManager {
    static let refreshIdentifier = "com.uzairansar.hermesmobile.refresh"

    /// Call once during app init. Must be called BEFORE the app finishes launching.
    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else { return }
            handleRefresh(refreshTask)
        }
    }

    /// Call from `sceneDidEnterBackground` or `.onChange(of: scenePhase)`.
    static func scheduleNext() {
        let request = BGAppRefreshTaskRequest(identifier: refreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("[HermesPlus] BGTaskScheduler: \(error.localizedDescription)")
        }
    }

    private static func handleRefresh(_ task: BGAppRefreshTask) {
        scheduleNext()
        task.expirationHandler = { task.setTaskCompleted(success: false) }

        // The refresh itself is minimal: mark the timestamp so that on next
        // foreground launch, the app knows to refresh its caches aggressively.
        // Actual network work is deferred to foreground (where there's no 30s limit).
        UserDefaults.standard.set(Date(), forKey: "hermes_last_bg_refresh_ts")
        task.setTaskCompleted(success: true)
    }
}
