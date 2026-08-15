import Foundation
import UIKit
import MachO
import Darwin

/// Tracks the currently-running heavy main-thread operation so a freeze can be
/// attributed to it. Cheap: a locked (label, startTime) pair. Instrument the
/// known-expensive main-thread paths (CacheStore writes, big fetches) with
/// begin/end — when a freeze fires, the snapshot tells us what was in flight.
enum HeavyOperationTracker {
    private static let lock = NSLock()
    private static var currentLabel: String?
    private static var currentStart: Date?

    static func begin(_ label: String) {
        lock.lock()
        currentLabel = label
        currentStart = Date()
        lock.unlock()
    }

    static func end() {
        lock.lock()
        currentLabel = nil
        currentStart = nil
        lock.unlock()
    }

    /// "Label (123ms)" while an operation is in flight, else nil.
    static func snapshot() -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let label = currentLabel, let start = currentStart else { return nil }
        return "\(label) (\(Int(Date().timeIntervalSince(start) * 1000))ms)"
    }
}

/// Physical memory footprint of the app (bytes). nil when the syscall fails.
enum MemoryFootprint {
    static func currentBytes() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &info) { ptr in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), intPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return nil }
        return info.phys_footprint
    }
}

/// Captures the main thread's instruction pointer + return address directly via
/// Mach `thread_get_state`, symbolicated with `dladdr`.
///
/// This runs on the *watchdog's background queue*, not the main thread, so it
/// reads the main thread's register state while that thread is blocked — unlike
/// `Thread.callStackSymbols`, which is static/current-thread-only and can never
/// see the main thread from a background queue. A main-queue capture loop would
/// snapshot its own frames and was the reason every freeze report showed the
/// watchdog itself with an empty `heavyOp`.
enum MainThreadStackCapture {
    /// One-line "blocked at Foo.bar +0x12 (return: Baz.qux)" summary, or a
    /// human-readable failure reason. Never throws, never crashes — the freeze
    /// report must always get *some* text.
    static func capture() -> String {
        let mainThread = pthread_mach_thread_np(pthread_main_np())

        #if arch(arm64)
        var state = arm_thread_state64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<arm_thread_state64_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &state) { ptr in
            ptr.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { natPtr in
                thread_get_state(mainThread, ARM_THREAD_STATE64, natPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return "thread_get_state failed (\(kr))"
        }
        let pc = state.__pc
        let lr = state.__lr
        let fp = state.__fp
        #else
        var state = x86_thread_state64_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<x86_thread_state64_t>.size / MemoryLayout<natural_t>.size
        )
        let kr = withUnsafeMutablePointer(to: &state) { ptr in
            ptr.withMemoryRebound(to: natural_t.self, capacity: Int(count)) { natPtr in
                thread_get_state(mainThread, x86_THREAD_STATE64, natPtr, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return "thread_get_state failed (\(kr))"
        }
        let pc = state.__rip
        let lr = state.__rbp
        let fp = state.__rbp
        #endif

        var parts: [String] = []
        if pc != 0, let sym = symbolize(pc) {
            parts.append("blocked at \(sym)")
        }
        if lr != 0, lr != pc, let sym = symbolize(lr) {
            parts.append("return: \(sym)")
        }
        if fp != 0, fp != pc, fp != lr, let sym = symbolize(fp) {
            parts.append("fp: \(sym)")
        }
        if parts.isEmpty {
            return String(format: "pc=0x%llx lr=0x%llx fp=0x%llx", pc, lr, fp)
        }
        return parts.joined(separator: " | ")
    }

    /// Resolve an instruction address to "SymbolName +0xNN" via `dladdr`.
    private static func symbolize(_ address: UInt64) -> String? {
        guard let raw = UnsafeRawPointer(bitPattern: UInt(address)) else { return nil }
        var info = Dl_info()
        guard dladdr(raw, &info) != 0 else { return nil }
        let name = info.dli_sname.map { String(cString: $0) } ?? "?"
        if let saddr = info.dli_saddr {
            let base = UInt64(UInt(bitPattern: saddr))
            guard address >= base else { return name }
            let offset = address - base
            return offset == 0 ? name : "\(name) +0x\(String(offset, radix: 16))"
        }
        return name
    }
}

/// Detects main-thread hangs in the app.
///
/// A background timer pings the main queue every `pingInterval` seconds. If the
/// main queue stops acknowledging within `hangThreshold`, the main thread is
/// blocked — a `freeze` event is logged from the *background* queue (the main
/// queue is stuck, so the network call must not originate there). When the main
/// queue recovers, a `recovered` event is logged.
///
/// Freeze events carry:
///   - `stack`: the main thread's symbolicated stack (where it is stuck)
///   - `memoryMB`: physical footprint at freeze time (Jetsam proximity)
///   - `heavyOp`: which instrumented heavy operation was in flight (if any)
/// Sub-hang stalls (1-3s, below the hard threshold) are reported as rate-limited
/// `stutter` events so slow-but-not-dead UI is still visible in diagnostics.
///
/// Used as the client-side freeze detector for the 24/7 diagnostics channel:
/// HermexLogger ships the events to the server, where a watchdog notifies the
/// agent within a minute.
final class MainThreadWatchdog {
    static let shared = MainThreadWatchdog()

    private let pingInterval: TimeInterval = 1.0
    private let hangThreshold: TimeInterval = 3.0
    private let stutterThreshold: TimeInterval = 1.0
    private let stutterRateLimit: TimeInterval = 30.0

    private let lock = NSLock()
    private var lastPong = Date()
    private var isFrozen = false
    private var timer: DispatchSourceTimer?
    private var currentScreen: String?
    private var lastStutterReport = Date(timeIntervalSince1970: 0)

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
            // Capture WHERE the main thread is stuck from THIS (background)
            // watchdog queue. `Thread.callStackSymbols` is static/current-thread
            // only, so a main-queue loop would capture *itself* (the bug that
            // made every freeze report show the watchdog's own frames and an
            // empty heavyOp). The Mach `thread_get_state` path below reads the
            // main thread's instruction pointer directly.
            let memoryMB = MemoryFootprint.currentBytes().map { Int64($0 / 1_048_576) } ?? -1
            let heavyOp = HeavyOperationTracker.snapshot() ?? ""
            let mainStack = MainThreadStackCapture.capture()
            HermexLogger.shared.log(
                type: "freeze",
                durationMs: elapsed * 1000,
                screen: screen,
                message: "main thread blocked \(Int(elapsed))s",
                extras: [
                    "stack": mainStack,
                    "memoryMB": memoryMB,
                    "heavyOp": heavyOp,
                ]
            )
        } else if elapsed >= stutterThreshold && !wasFrozen {
            // Sub-hang main-thread stall (1-3s): report rate-limited so a
            // stream of micro-hangs doesn't spam the log.
            lock.lock()
            let shouldReport = now.timeIntervalSince(lastStutterReport) >= stutterRateLimit
            if shouldReport { lastStutterReport = now }
            lock.unlock()
            if shouldReport {
                HermexLogger.shared.log(
                    type: "stutter",
                    durationMs: elapsed * 1000,
                    screen: screen,
                    message: "main thread stalled \(Int(elapsed))s"
                )
            }
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

/// Measures real frame times via CADisplayLink and reports sustained jank —
/// UI lag that never hard-blocks the main thread (e.g. heavy streaming
/// renders, the "interface lags while the agent thinks" case). A 2s window
/// with average frame time above ~33ms (sub-30 FPS) or a single frame above
/// 50ms logs a `jank` event, rate-limited to one per 30s.
final class FrameTimeMonitor: NSObject {
    static let shared = FrameTimeMonitor()

    private var displayLink: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCount = 0
    private var frameMsSum = 0.0
    private var frameMsMax = 0.0
    private var windowStart = Date()
    private var lastReport = Date(timeIntervalSince1970: 0)
    private let windowDuration: TimeInterval = 2.0
    private let jankAvgThresholdMs: Double = 33.0
    private let jankMaxThresholdMs: Double = 50.0
    private let reportRateLimit: TimeInterval = 30.0

    private override init() {}

    /// Start the display link on the main run loop. Idempotent.
    func start() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frameTick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func frameTick(_ link: CADisplayLink) {
        // CADisplayLink pauses in the background; when we resume, the first
        // timestamp is stale. Drop it and start the window fresh.
        guard UIApplication.shared.applicationState == .active else {
            lastTimestamp = 0
            return
        }
        if lastTimestamp == 0 {
            lastTimestamp = link.timestamp
            return
        }

        let frameMs = (link.timestamp - lastTimestamp) * 1000
        lastTimestamp = link.timestamp
        frameCount += 1
        frameMsSum += frameMs
        frameMsMax = max(frameMsMax, frameMs)

        guard Date().timeIntervalSince(windowStart) >= windowDuration else { return }

        let avgMs = frameCount > 0 ? frameMsSum / Double(frameCount) : 0
        let avgFps = frameCount > 0 ? 1000.0 / avgMs : 0
        let maxMs = frameMsMax

        // Reset the window before reporting (reporting is non-blocking).
        frameCount = 0
        frameMsSum = 0
        frameMsMax = 0
        windowStart = Date()

        guard avgMs > jankAvgThresholdMs || maxMs > jankMaxThresholdMs else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReport) >= reportRateLimit else { return }
        lastReport = now
        HermexLogger.shared.log(
            type: "jank",
            durationMs: avgMs,
            message: String(format: "UI jank avg %.0fms (%.0f fps) max %.0fms", avgMs, avgFps, maxMs),
            extras: ["maxFrameMs": maxMs]
        )
    }
}
