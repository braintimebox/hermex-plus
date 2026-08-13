import Foundation
import UIKit

/// Detects main-thread hangs in the app.
///
/// A background timer pings the main queue every `pingInterval` seconds. If the
/// main queue stops acknowledging within `hangThreshold`, the main thread is
/// blocked — a `freeze` event is logged from the *background* queue (the main
/// queue is stuck, so the network call must not originate there). When the main
/// queue recovers, a `recovered` event is logged.
///
/// Used as the client-side freeze detector for the 24/7 diagnostics channel:
/// HermexLogger ships the events to the server, where a watchdog notifies the
/// agent within a minute.
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    private let pingInterval: TimeInterval = 1.0
    private let hangThreshold: TimeInterval = 3.0

    private let lock = NSLock()
    private var lastPong = Date()
    private var isFrozen = false
    private var timer: DispatchSourceTimer?
    private var currentScreen: String?

    private init() {}

    /// Start the watchdog. Idempotent — calling twice is a no-op.
    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard timer == nil else { return }

        let queue = DispatchQueue(label: "hermex.watchdog", qos: .utility)
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now(), repeating: pingInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    /// Optional context for the next freeze event (e.g. the active screen).
    func setScreen(_ screen: String?) {
        lock.lock()
        currentScreen = screen
        lock.unlock()
    }

    private func tick() {
        let now = Date()

        // The main queue legitimately does not run while the app is suspended
        // or in the background — counting that as a freeze produces false
        // multi-minute "main thread blocked" reports every time the phone is
        // locked or the app backgrounded (real case: 491s/729s "freezes" that
        // were simply suspension time; the watchdog's timer fires on resume and
        // measures the whole pause as a block). Only report when the app is
        // active. Mirrors HermexLogger's foreground flag (UIApplication read
        // from this background queue is already done there, line 58).
        guard UIApplication.shared.applicationState == .active else {
            lock.lock()
            lastPong = now
            lock.unlock()
            return
        }

        lock.lock()
        let elapsed = now.timeIntervalSince(lastPong)
        let wasFrozen = isFrozen
        let screen = currentScreen
        lock.unlock()

        if elapsed > hangThreshold && !wasFrozen {
            lock.lock()
            isFrozen = true
            lock.unlock()
            HermexLogger.shared.log(
                type: "freeze",
                durationMs: elapsed * 1000,
                screen: screen,
                message: "main thread blocked \(Int(elapsed))s"
            )
        }

        // Ping the main queue. The pong only runs if the main thread is free.
        DispatchQueue.main.async { [weak self] in self?.pong() }
    }

    private func pong() {
        lock.lock()
        let wasFrozen = isFrozen
        isFrozen = false
        lastPong = Date()
        lock.unlock()

        if wasFrozen {
            HermexLogger.shared.log(type: "recovered", message: "main thread recovered")
        }
    }
}
