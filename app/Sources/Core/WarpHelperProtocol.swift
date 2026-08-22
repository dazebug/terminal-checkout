import Foundation

// The protocol between the app and the injection helper that runs inside a Warp pane.
//
// Why a process has to be inside the pane: for a non-root caller the BSD kernel allows `TIOCSTI` only on the calling process's controlling terminal (`isctty`). The app is outside the pane's session, so it cannot put bytes into the pane's tty.
// So the helper is launched first in the pane the Tab Config opens, and the app becomes a client of its socket.
//
// It is a line-based ASCII protocol. Only the bytes to inject ride as base64 — submission (CR) and clearing the input box (Ctrl+U) are control characters and cannot travel raw in a line-based protocol.

public enum WarpHelperRequest: Equatable {
    /// The tty path of the pane the helper is attached to. The app runs gates ①②③ against this value.
    case tty
    /// Put these bytes into the tty input queue. `expectedPID` is the process **expected to read those bytes** — immediately before injecting, the helper compares it against the foreground and does not inject when they disagree.
    /// It rides on every request because keeping it as state would create a "set it and forget it" branch.
    case inject(expectedPID: Int32, bytes: Data)
    /// Delivery is over, exit — the normal path that keeps the helper from lingering in the pane.
    case bye
}

/// The tty input queue has a cap (TTYHOG) and the kernel silently drops whatever overflows it. So the amount written at once is limited and the surplus waits for consumption before continuing — rejecting an over-cap input outright would make every claude prompt longer than 512 bytes fail.
/// Cutting on byte boundaries is safe: the tty input queue is a byte stream, so a multi-byte character split across chunks still arrives whole for claude as long as the order is kept (measured with Korean input).
///
/// **Nothing is written while even one byte is still in the queue.** Continuing just because there is room leaves the previous chunk's tail in the queue while the next piles on: claude reads only the front and draws it, so the app's reflection check passes (the probe looks at the first 24 characters only — `claudeInputProbe`). Then, once claude exits, **the shell reads the tail left in the queue and runs it as a command.** This was the branch by which bytes we produced got executed in the user's shell. Writing only into an empty queue means every chunk is confirmed read by claude before the next one goes.
public func warpInjectChunkSize(pending: Int, remaining: Int, limit: Int) -> Int {
    guard pending == 0 else { return 0 }
    return max(0, min(remaining, limit))
}

/// The verdict reached **from a single sample** while watching whether the injected bytes get read.
///
/// Taking no history as an argument is the whole point of this function. There used to be a comparison against the previous sample: "the queue grew, so the user's keys got mixed in", and if it had not grown the remaining bytes were treated as ours and discarded with `tcflush`. That inference breaks in two places (reproduced by the reviewer): the **first sample** has nothing to compare against, so it can never establish that anything was mixed in, and even afterwards, if the user types 4 bytes while claude reads 5, the total **shrinks** from 10 to 9 and produces the same misjudgement. `FIONREAD` is an unattributed total, so there was never a way to prove "what remains is our bytes" — which is why, instead of strengthening the proof, **the discarding was removed altogether.**
///
/// The price is that the window in which our bytes **linger as residue** in the shell's line buffer widens again. This side is still chosen because residue is something the user can see and erase, whereas a wrong `tcflush` **silently** deletes the keys they just typed.
public enum WarpInjectWatch: Equatable {
    /// The queue is empty and the foreground is still the reader we aimed at — the only success, and the closest to delivery this vantage point reaches. It does not say claude processed anything.
    case delivered
    /// Our reader is still reading.
    case keepWaiting
    /// The queue is empty and the foreground was **not confirmed** to be the reader we aimed at — either somebody else's group, or a lookup that failed. Which of them consumed the bytes is not observable from one sample, so the case says what was seen and not who took it.
    case drainedWithoutConfirmedReader
    /// Bytes remain in the queue and the foreground was not confirmed to be ours. Nothing is discarded, only the remaining count is reported.
    case readerUnconfirmed(pending: Int)
    /// The budget ran out with bytes still in the queue (fail-closed). It does **not** say our bytes are the ones left: `FIONREAD` is an unattributed total, and the user typing during the wait lands in it too.
    case queueNotEmptyAtDeadline(pending: Int)
}

/// Decides what to do next from the queue's remaining bytes, what the foreground is, and whether the budget is spent.
/// The empty queue is checked first because it is the only success condition, and the foreground check comes before the budget because once the reader is not confirmably ours there is no reason to keep waiting.
///
/// `.different` and `.unknown` produce the same verdict — that is the fail-closed rule, unchanged.
/// What changed is that they are no longer the same *value*: the caller still has both apart when
/// it writes down what happened.
public func warpInjectWatchDecision(
    pending: Int, foreground: WarpForeground, budgetExpired: Bool
) -> WarpInjectWatch {
    // `== 0` and not `<= 0`: a negative count is a malformed answer, not an empty queue, and
    // reading it as success would report delivery from a number that means nothing (round 7
    // review). It falls through to the branches below, which is the fail-closed direction.
    if pending == 0 { return foreground == .expected ? .delivered : .drainedWithoutConfirmedReader }
    if foreground != .expected { return .readerUnconfirmed(pending: pending) }
    return budgetExpired ? .queueNotEmptyAtDeadline(pending: pending) : .keepWaiting
}

/// The cap on the time the helper spends on **one** request — waiting for the queue to drain and watching whether the written bytes get read both have to fit inside it.
public let warpHelperWorkBudget: TimeInterval = 2

/// How long the app waits for a response. It has to be **comfortably longer** than the helper's budget — if the app gives up first and retries while the previous request's injection is still running, those bytes mix with the retry's and with the user's own typing.
/// Writing the two numbers separately is how one of them gets fixed and they drift apart again, so the second is derived from the first in one place.
public let warpHelperRequestTimeout: TimeInterval = warpHelperWorkBudget * 3

/// Is the process that will read this tty's input right now the claude we aimed at?
///
/// `TIOCSTI` only checks whether the caller shares the controlling session; **it does not decide who reads the bytes put into the queue**. If claude dies and the shell becomes the foreground, the shell reads the remaining CR and runs whatever draft the user was typing — which is why app-side gates that look only "before sending" are not enough, and why the window narrows only when the foreground is checked from the same process that injects.
///
/// **Three states and not two.** This used to answer `Bool`, and a failed `tcgetpgrp` or `getpgid`
/// lookup came back as `false` — the same value as "somebody else is attached". Both must refuse to
/// inject, so the *decision* was right, but everything downstream then reported a fact nobody had
/// established: an unreadable foreground was logged and replied to as a different reader. Wording
/// alone could not fix that, because a `Bool` has nowhere to keep the difference; a caller that
/// needs one verdict collapses the two itself, at a site the type no longer forces to think.
///
/// The comparison is by **process group** rather than pid: the claude pid the app picks is sometimes not the group leader (measured: `pid != pgid` in 3 of the user's 13 claude panes).
public enum WarpForeground: Equatable {
    /// The foreground process group is the one we aimed at.
    case expected
    /// Both lookups answered, and the foreground is somebody else's group.
    case different
    /// A lookup failed (`tcgetpgrp` or `getpgid` returned -1, or a pgid came back non-positive).
    /// **Not the same as `different`**: it is the absence of an answer, and it is fail-closed for
    /// the same reason — what cannot be told apart must not be injected into.
    case unknown

    /// How a diagnostic words this state. Exhaustive on purpose: the caller used to spell it as
    /// `foreground == .different ? … : …`, which maps `.expected` onto "could not be read" and was
    /// only correct because no reachable branch passed `.expected` to it. **A switch keeps that
    /// from being an argument about reachability** — adding a fourth state, or reaching this from a
    /// new site, becomes a compile error instead of a wrong sentence (round 7 review).
    public var diagnosis: String {
        switch self {
        case .expected: return "the foreground is the reader we aimed at"
        case .different: return "the foreground was a different process group"
        case .unknown: return "the foreground could not be read"
        }
    }
}

/// Is this tty still the one our session owns?
///
/// The raw comparison was `tcgetsid(ttyFD) == getsid(0)`, and both calls return **-1 on failure** —
/// so two failed lookups compared equal and the helper concluded the tty was still ours (round 7
/// review). Requiring both to be positive is what makes the failure fail-closed; the name says
/// "ours" rather than "changed" because an unreadable pair is not evidence of a change.
public func warpTTYSessionIsOurs(ttySID: pid_t, ourSID: pid_t) -> Bool {
    ttySID > 0 && ourSID > 0 && ttySID == ourSID
}

public func warpForeground(foregroundPGID: Int32, expectedPGID: Int32) -> WarpForeground {
    guard foregroundPGID > 0, expectedPGID > 0 else { return .unknown }
    return foregroundPGID == expectedPGID ? .expected : .different
}

/// Why the helper must not stay alive any longer. The waiting loop and the **request-handling path** use the same verdict — with the cap checked only in the waiting loop, someone holding the connection open and requesting continuously bypasses the idle and lifetime caps entirely.
public enum WarpHelperStop: Equatable {
    /// The tty is no longer our session's controlling terminal (the pane closed and its number was reused).
    case ttySessionChanged
    case idle
    case lifetime

    public var description: String {
        switch self {
        case .ttySessionChanged: return "tty session changed"
        case .idle: return "idle timeout"
        case .lifetime: return "lifetime limit"
        }
    }
}

/// The tty identity is checked first — even with budget to spare, not one byte may go into somebody else's tty.
public func warpHelperStopReason(
    ttySessionMatches: Bool,
    idleSeconds: TimeInterval,
    aliveSeconds: TimeInterval,
    idleLimit: TimeInterval,
    lifetimeLimit: TimeInterval
) -> WarpHelperStop? {
    if !ttySessionMatches { return .ttySessionChanged }
    if idleSeconds > idleLimit { return .idle }
    if aliveSeconds > lifetimeLimit { return .lifetime }
    return nil
}

public enum WarpHelperResponse: Equatable {
    case ok(String)
    case err(String)
}

public func encodeWarpHelperRequest(_ request: WarpHelperRequest) -> String {
    switch request {
    case .tty: return "tty"
    case .bye: return "bye"
    case .inject(let pid, let bytes): return "inject \(pid) " + bytes.base64EncodedString()
    }
}

/// Reads a line the helper received as a request. nil when it cannot be parsed — the helper answers `err` in that case.
public func parseWarpHelperRequest(_ line: String) -> WarpHelperRequest? {
    let text = trimmingLineEnding(line)
    switch text {
    case "tty": return .tty
    case "bye": return .bye
    default: break
    }
    // An empty payload (`inject <pid> `) is a valid request too, so empty pieces must not be dropped
    let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    // Only a positive pid is accepted — `getpgid(0)` means "the caller's group", so in the abnormal situation where the helper itself is the foreground, 0 would pass as "the expected reader matches". Keep it fail-closed
    guard parts.count == 3, parts[0] == "inject",
          let pid = Int32(parts[1]), pid > 0,
          let bytes = Data(base64Encoded: String(parts[2]))
    else { return nil }
    return .inject(expectedPID: pid, bytes: bytes)
}

public func encodeWarpHelperResponse(_ response: WarpHelperResponse) -> String {
    switch response {
    case .ok(let detail): return detail.isEmpty ? "ok" : "ok " + detail
    case .err(let reason): return reason.isEmpty ? "err" : "err " + reason
    }
}

/// A line without the prefix is nil — reading it as a success is how a helper failure looks like a success to the app.
public func parseWarpHelperResponse(_ line: String) -> WarpHelperResponse? {
    let text = trimmingLineEnding(line)
    if text == "ok" { return .ok("") }
    if text == "err" { return .err("") }
    let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    switch parts[0] {
    case "ok": return .ok(String(parts[1]))
    case "err": return .err(String(parts[1]))
    default: return nil
    }
}

private func trimmingLineEnding(_ line: String) -> String {
    var text = line
    while let last = text.last, last == "\n" || last == "\r" { text.removeLast() }
    return text
}

/// A socket read() does not respect line boundaries — several lines can arrive at once, and one line can arrive split. This accumulates the pieces and hands out only completed lines.
public struct LineBuffer {
    /// The cap that keeps a peer which never sends a newline from taking unbounded memory.
    /// An injection payload is base64, so it is 4/3 the size of the original
    public static let defaultLimit = 256 * 1024

    private var data = Data()
    private let limit: Int
    /// After the cap is exceeded nothing is handed back — that is how the caller learns to close the connection
    public private(set) var isOverflowed = false

    public init(limit: Int = LineBuffer.defaultLimit) {
        self.limit = limit
    }

    public mutating func append(_ chunk: Data) {
        guard !isOverflowed else { return }
        data.append(chunk)
        // The **same** cap applies to completed lines and to the tail whose newline has not arrived yet. Checking the tail alone lets an over-cap line through when it arrives together with its final newline
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 0x0A) {
            if data.distance(from: start, to: newline) > limit { return overflow() }
            start = data.index(after: newline)
        }
        if data.distance(from: start, to: data.endIndex) > limit { return overflow() }
    }

    private mutating func overflow() {
        isOverflowed = true
        data.removeAll()
    }

    public mutating func nextLine() -> String? {
        guard !isOverflowed, let newline = data.firstIndex(of: 0x0A) else { return nil }
        let line = data[data.startIndex..<newline]
        data = Data(data[data.index(after: newline)...])
        return String(decoding: line, as: UTF8.self)
    }
}
