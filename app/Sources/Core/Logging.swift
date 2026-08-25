import Foundation
import os

/// The diagnostic log the app and the relay share.
///
/// Why not NSLog: NSLog passes the message as an *argument* to os_log, and arguments are redacted by default in the unified log. So `log show` keeps only `<private>`, which tells you that something failed but never what — investigating an incident where claude input stopped halfway, there was a line in the log whose contents could not be read, and the path had to be narrowed down from the gaps between timestamps instead (measured).
///
/// To read it: `log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 1h`
private let checkoutLogger = Logger(subsystem: appBundleID, category: "app")

public func checkoutLog(_ message: String) {
    checkoutLogger.log("\(message, privacy: .public)")
}

/// One request's stopwatch, from the button press to the last input submitted.
///
/// **Why it exists**: a delivery that worked logged one line, at the end. A real run spent 86
/// seconds between opening the tab and submitting the first input, and nothing in the log could
/// say which stage they went to — the Warp helper's 20-second window, claude's own startup, or the
/// pane proof waiting for the user to look at that tab (which is not ours to fix, but is ours to
/// be able to say). Every stage now reports **the gap from the previous stage** (which one was
/// slow) and **the total** (the metric the user actually feels: press to first submission).
///
/// Instrumentation only — no step here changes what is sent or when. It is passed as an optional
/// so the delivery loop runs identically without one, which is how every existing test calls it.
public final class DeliveryTimeline: @unchecked Sendable {
    private let lock = NSLock()
    private let now: () -> Date
    private let emit: (String) -> Void
    private let started: Date
    private var previous: Date

    public init(now: @escaping () -> Date = Date.init, emit: @escaping (String) -> Void = checkoutLog) {
        self.now = now
        self.emit = emit
        let start = now()
        self.started = start
        self.previous = start
    }

    /// Logs one stage as `<message> (+1.2s, total 3.4s)`. Safe to call from either the request queue
    /// or the delivery queue — they never overlap today, and the lock keeps that from being a
    /// premise a future caller has to know about.
    public func step(_ message: String) {
        lock.lock()
        let instant = now()
        let sincePrevious = instant.timeIntervalSince(previous)
        let total = instant.timeIntervalSince(started)
        previous = instant
        lock.unlock()
        emit("\(message) (+\(seconds(sincePrevious))s, total \(seconds(total))s)")
    }

    private func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f", value)
    }
}
