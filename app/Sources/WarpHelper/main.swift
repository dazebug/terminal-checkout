import Core
import Darwin
import Foundation

// The Warp pane injection helper.
//
// Warp has no way to send text to a pane — no AppleScript support, warpctrl disabled by default on Stable, and no CLI like `wezterm cli send-text` (all measured). What is left is `TIOCSTI`, which puts bytes straight into the pane's tty input queue, and for a non-root caller the BSD kernel allows that only on **the calling process's controlling terminal** (`isctty`). So the injection is done by this process running inside the pane rather than by the app, and the app becomes a client of its unix socket.
//
// Two things this never does:
//   - it never reads from the tty — that would steal the keys the user typed into that pane
//   - it never writes to the tty — that would wreck the screen claude is drawing
// Logging goes to os_log alone (`checkoutLog`).

/// `_IOW('t', 114, char)` — pushes one byte into the tty input queue.
/// `_IOR('f', 127, int)` — how many bytes have not been read yet.
/// Both are C macros and do not come through to Swift, so the values are written out here.
private let requestTIOCSTI: UInt = 0x8001_7472
private let requestFIONREAD: UInt = 0x4004_667F

/// The maximum bytes left in the queue at once. It sits comfortably below the tty input queue's cap (TTYHOG, 1024 by default), and the surplus waits for consumption before continuing.
private let injectQueueLimit = 512
/// The maximum bytes accepted in one request. A claude input is a single line and far shorter than this — without a cap the sender could make us issue hundreds of thousands of ioctls.
private let injectMaxBytes = 8 * 1024
/// The receive buffer cap. base64 is 4/3 of the original, so twice the cap above is ample.
private let requestLineLimit = 16 * 1024
/// How often (in bytes) the foreground is re-checked while a chunk is being pushed in. The stretch that runs without a check is "the most bytes that can leak to the shell when claude has ended", so shorter is better, but running `tcgetpgrp`+`getpgid` twice per byte is waste too — this is sized so that a leak in a one-line input is visible at a glance.
private let foregroundRecheckStride = 16

// ─────────────────────────────────────────────────────────────────────────────
// Trust boundary declaration (this applies to the whole feature)
//
// **The boundary is the uid.** Processes running as the same uid are treated as inside the boundary; other uids are refused. There are two reasons: macOS itself uses the uid as the boundary for this class of thing (unix sockets, files in the user's home), and within one uid there is nowhere to hide — argv, environment variables and 0600 files are all readable, and this socket path is written plainly in the Tab Config file and visible on the pane's screen. So the uid comparison in `getpeereid` is **a boundary check, not authentication**.
//
// What is possible inside this boundary (and is not prevented):
//  1. An arbitrary `inject` into a live helper socket — a same-uid process can put whatever bytes it likes into that pane's claude. The only axis left to narrow is lifetime: the helper dies immediately on `bye` when delivery ends, and failing that it is caught by the 180-second idle cap and the 900-second lifetime cap.
//  2. The TOCTOU in path-based `unlink` — socket reclaim, Tab Config reclaim, the scheduled deletion, and `uninstall.sh`. `lstat`/`fstat` plus an inode re-check narrowed the window to microseconds, but macOS has no `funlinkat`, so the last step is by path. Slipping into it requires knowing our random name in advance.
//  3. Swapping the contents after the header has been checked — the verdict is reached through an fd but the deletion is by path (the same window as 2).
//  4. Placing a file at the helper socket path in advance to make `bind` fail (a DoS that only defeats delivery).
//
// The residuals that have **nothing to do with** the boundary (the ones that remain even with no malice) are kept separate — the two are never mixed:
//  - the window in which the pane proof is valid only up to the moment the body is typed (see the `proveOurPane` comment)
//  - the race where the shell reads a queued CR first, and — when the claude we aimed at is gone — **our unread bytes lingering as residue in the shell's line buffer**; this is not prevented by discarding them (see the `watchUntilRead` comment)
//  - the fact that the Tab Config's 20-second scheduled deletion cannot guarantee "Warp has read it" (see the `runInWarp` comment)
//  - the user typing into the same pane during delivery, which mixes into the input box and is submitted together (issue #16). At the queue level this looks normal — claude reads immediately, so the queue keeps draining. The Accessibility API only hands over the whole screen and not the input box's contents separately, so "only ours is in there" cannot be proven.
// ─────────────────────────────────────────────────────────────────────────────
//
/// The idle cap for when `bye` never arrives. The longest silence in a normal delivery is the stretch where the app waits for claude to start (120 seconds by default in `deliverClaudeInputs`), so this only needs headroom over that.
private let idleTimeout: TimeInterval = 180
/// The overall lifetime cap. The worst normal delivery (a 120-second startup wait plus 5 inputs with retries) stays inside 400 seconds, so this is set at roughly twice that — being caught here already means something is abnormal.
private let maxLifetime: TimeInterval = 900

private let serveFlag = "--serve"

/// A signal handler may only call async-signal-safe functions — it cannot build a Swift string, so the path is captured as a C string in advance. `lstat` and `unlink` are both on the safe list.
private var socketPathForSignal: UnsafeMutablePointer<CChar>?

/// Deletes only when the object at the path we expected is a socket. That is **inferred** ownership, not proven: a same-uid process can put a socket of its own there, and residual 2 in the preamble is exactly that. Going by the path alone would also remove a regular file somebody put there in the meantime — collisions do not happen on the normal path, but a deletion cannot be undone.
private func unlinkIfSocket(_ path: UnsafePointer<CChar>) {
    var info = stat()
    guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return }
    unlink(path)
}

/// On SIGTERM (an app reinstall, `pkill`), SIGINT and SIGHUP, the socket file is deleted before exiting.
/// SIGKILL cannot be caught, so that share is reclaimed by the app on its next run (`reclaimDeadWarpHelperSockets`).
private func installSocketCleanupOnSignals(path: String) {
    socketPathForSignal = strdup(path)
    for number in [SIGTERM, SIGINT, SIGHUP] {
        signal(number) { _ in
            if let path = socketPathForSignal { unlinkIfSocket(path) }
            _exit(0)
        }
    }
}

private func fail(_ message: String) -> Never {
    checkoutLog("Warp injection helper exiting: \(message)")
    exit(1)
}

private func lastErrnoName() -> String { String(cString: strerror(errno)) }

/// How many bytes remain in the tty input queue. nil on a failed query.
private func ttyPendingBytes(_ fd: Int32) -> Int? {
    var pending: Int32 = 0
    let result = withUnsafeMutablePointer(to: &pending) {
        ioctl(fd, requestFIONREAD, UnsafeMutableRawPointer($0))
    }
    return result == 0 ? Int(pending) : nil
}

/// The helper's state while it lives. The stop verdict is gathered here in one place so **the waiting loop and the request-handling path use the same criterion** — with the cap checked only in the waiting loop, someone holding the connection open and requesting continuously bypasses the idle and lifetime caps entirely.
private final class HelperState {
    let ttyFD: Int32
    let ttyPath: String
    private let startedAt = Date()
    private var lastActivity = Date()

    init(ttyFD: Int32, ttyPath: String) {
        self.ttyFD = ttyFD
        self.ttyPath = ttyPath
    }

    func touch() { lastActivity = Date() }

    func stopReason() -> WarpHelperStop? {
        warpHelperStopReason(
            // tty numbers get reused — once the pane closes and a new session takes the same number, the session id differs. This comparison is the only signal that keeps a helper from being attached to somebody else's tty
            ttySessionMatches: tcgetsid(ttyFD) == getsid(0),
            idleSeconds: Date().timeIntervalSince(lastActivity),
            aliveSeconds: Date().timeIntervalSince(startedAt),
            idleLimit: idleTimeout,
            lifetimeLimit: maxLifetime
        )
    }
}

/// Writes in pieces sized to the queue's headroom. Rejecting outright would make every claude prompt longer than 512 bytes fail, and that length is not rare in input the user writes themselves.
/// Cutting on byte boundaries is fine because the tty input queue is a byte stream — a multi-byte character split across pieces still arrives whole for claude as long as the order is kept (measured with Korean input).
private func inject(_ bytes: Data, expectedPID: Int32, state: HelperState) -> WarpHelperResponse {
    let ttyFD = state.ttyFD
    guard !bytes.isEmpty else { return .ok("0") }
    guard bytes.count <= injectMaxBytes else {
        return .err("payload too large (\(bytes.count) > \(injectMaxBytes))")
    }
    let all = [UInt8](bytes)
    var sent = 0
    // All the time available to this request — waiting for the queue to drain and watching whether it gets read, together, have to stay comfortably shorter than the app's response wait (see `warpHelperWorkBudget`)
    let deadline = Date().addingTimeInterval(warpHelperWorkBudget)
    while sent < all.count {
        // Re-checked for every piece. A split injection waits out its budget for the queue to drain, and if our pane closes in that time and a new session takes the same tty number, the remaining pieces go into somebody else's tty
        if let stop = state.stopReason() { return .err(stop.description) }
        // Immediately before writing, "the process that will read this tty right now" is checked. The app's gate only sees the state before the request was sent, so if claude ended in between, the shell reads our bytes.
        // It is two syscalls, cheaper than a `ps` round trip, and it runs in the same process as the injection, so the window is microseconds
        guard warpForegroundIsExpected(
            foregroundPGID: tcgetpgrp(ttyFD), expectedPGID: getpgid(expectedPID)
        ) else {
            return .err("foreground is not the expected reader")
        }
        guard let pending = ttyPendingBytes(ttyFD) else { return .err(lastErrnoName()) }
        let chunk = warpInjectChunkSize(pending: pending, remaining: all.count - sent, limit: injectQueueLimit)
        guard chunk > 0 else {
            // claude has not read it yet. Writing more here means the kernel silently drops it
            guard Date() < deadline else {
                return .err("input queue not drained in time (\(pending) pending)")
            }
            usleep(50_000)
            continue
        }
        for index in sent..<(sent + chunk) {
            // Pushing a whole piece in on one check sends every remaining byte to the shell if claude ends midway. With a 512-byte piece the stretch running without a check is that long, so it is re-checked partway through — this interval is what bounds the leak
            if index > sent, (index - sent) % foregroundRecheckStride == 0 {
                guard warpForegroundIsExpected(
                    foregroundPGID: tcgetpgrp(ttyFD), expectedPGID: getpgid(expectedPID)
                ) else {
                    // Same check as the one before the write, and the same wording: a lookup that fails is "not the expected reader", not "changed"
                    return .err("foreground is not the expected reader after \(index - sent) bytes")
                }
            }
            var value = CChar(bitPattern: all[index])
            let result = withUnsafeMutablePointer(to: &value) {
                ioctl(ttyFD, requestTIOCSTI, UnsafeMutableRawPointer($0))
            }
            // A failure partway leaves only the front in — the count of how far it got is reported along with it.
            // The app clears the input box with Ctrl+U before retrying, so the leftover piece gets cleaned up
            guard result == 0 else { return .err("\(lastErrnoName()) after \(index)") }
        }
        sent += chunk
    }
    return watchUntilRead(expectedPID: expectedPID, state: state, injected: sent, deadline: deadline)
}

/// Watches briefly until the written bytes get read. The verdict is `warpInjectWatchDecision`'s; this function only takes samples and carries out its conclusion.
///
/// **Unread bytes are never discarded.** There used to be a `tcflush` that emptied the queue when the foreground moved off our claude, but "what remains is our bytes" cannot be proven with `FIONREAD` (an unattributed total), so there was a branch that erased the keys the user had just typed (two reproductions are in the `warpInjectWatchDecision` comment). So instead of strengthening the proof, the discarding was removed — **the trade-off**: the window in which our bytes linger as residue in the shell's line buffer widens again (with an input that starts with `!…`, an Enter the user presses later can run it). This side is still better because residue is **visible** and the user can erase it, whereas a wrong `tcflush` removes the user's keys **silently**.
///
/// **Not read in time is a failure (fail-closed).** There was a time this returned success on the grounds that "the foreground is unchanged, so claude is just slow", but then the app puts a CR on top of a tail still in the queue without knowing — the app's screen check looks only at the first 24 characters, so it passes even when claude read only the front. Once claude then ends, the shell reads [tail + CR] and **runs it as a command.** Success is only the case where the queue was seen empty.
///
/// The `FIONREAD` consulted here is the **negative** signal "not read yet". What was discarded is the **positive** inference "it was read, so claude must have drawn it", and that one is not revived — the delivery-success verdict is still made by the screen reflection check. This is a necessary condition placed in front of it.
private func watchUntilRead(
    expectedPID: Int32, state: HelperState, injected: Int, deadline: Date
) -> WarpHelperResponse {
    while true {
        guard let pending = ttyPendingBytes(state.ttyFD) else { return .err(lastErrnoName()) }
        // **Whose the remaining bytes are is never asked** — there is no way to ask.
        // Not passing any history into the verdict is what keeps that inference from coming back
        switch warpInjectWatchDecision(
            pending: pending,
            readerIsOurs: warpForegroundIsExpected(
                foregroundPGID: tcgetpgrp(state.ttyFD), expectedPGID: getpgid(expectedPID)
            ),
            budgetExpired: Date() >= deadline
        ) {
        case .delivered:
            return .ok(String(injected))
        case .drainedByOther:
            // Two observations, one sample: the queue is empty, and the foreground is not ours. Which of them read the bytes is not observable — `FIONREAD` is an unattributed total, and our claude reading and then exiting produces this same sample. The verdict is failure either way, and the log says what was seen rather than who took it
            checkoutLog("Warp injection helper: the queue drained while the foreground was not the claude we aimed at — which of them read the bytes is not observable here")
            return .err("queue drained with the foreground not ours")
        case .readerGone(let pending):
            // Nothing is discarded. The remaining bytes may end up as residue in the shell's line buffer, but emptying the queue to prevent that would silently take the keys the user just typed as well
            // "not ours" and not "gone": a failed `tcgetpgrp`/`getpgid` lookup yields -1 and lands here too (see `warpForegroundIsExpected`)
            checkoutLog("Warp injection helper: the foreground is no longer the claude we aimed at — reporting failure rather than discarding \(pending) unread byte(s)")
            return .err("foreground is not the expected reader; \(pending) bytes unread")
        case .notReadInTime(let pending):
            return .err("injected bytes not read in time (\(pending) pending)")
        case .keepWaiting:
            usleep(5_000)
        }
    }
}

/// Handles one connection to the end. true when `bye` arrived or a cap was hit (the helper exits).
private func serve(client: Int32, state: HelperState) -> Bool {
    var tv = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var buffer = LineBuffer(limit: requestLineLimit)
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        while let line = buffer.nextLine() {
            var finished = false
            let response: WarpHelperResponse
            // The caps and the tty identity are checked before every request — letting whoever holds the connection skip the waiting loop's check is the same as having no caps at all
            if let stop = state.stopReason() {
                _ = writeAll(fd: client, data: Data((encodeWarpHelperResponse(.err(stop.description)) + "\n").utf8))
                checkoutLog("Warp injection helper exiting: \(stop.description)")
                return true
            }
            state.touch()
            switch parseWarpHelperRequest(line) {
            case .tty:
                response = .ok(state.ttyPath)
            case .inject(let expectedPID, let bytes):
                response = inject(bytes, expectedPID: expectedPID, state: state)
            case .bye:
                response = .ok("")
                finished = true
            case nil:
                response = .err("unknown request")
            }
            let payload = Data((encodeWarpHelperResponse(response) + "\n").utf8)
            guard writeAll(fd: client, data: payload) else { return finished }
            if finished { return true }
        }
        if buffer.isOverflowed { return false }
        let n = read(client, &chunk, chunk.count)
        if n > 0 {
            buffer.append(Data(chunk[0..<n]))
        } else if n < 0 && errno == EINTR {
            continue
        } else {
            return false
        }
    }
}

/// Reads the pane tty's name from the stdio the shell handed down.
/// Having the child open `/dev/tty` does not work — the fd is right but `ttyname()` returns `/dev/tty` (measured), and the app's gates are `ps -t ttysNNN` and `stty -f /dev/ttysNNN`, which need the real name.
private func resolvePaneTTYName() -> String? {
    for fd in Int32(0)...2 {
        guard isatty(fd) == 1, let raw = ttyname(fd) else { continue }
        let name = String(cString: raw)
        if name.hasPrefix("/dev/"), name != "/dev/tty" { return name }
    }
    return nil
}

// MARK: - Startup

let arguments = CommandLine.arguments

if arguments.count == 2 && arguments[1] != serveFlag {
    // Parent mode: launch the child and get out immediately — the shell's next command (claude) has to follow right away, so this must not stay in the foreground. `setsid` is **not** called: leaving the session means that tty is no longer the controlling terminal, which loses the TIOCSTI permission
    guard let ttyName = resolvePaneTTYName() else {
        fail("the pane tty name is unknown — stdio is not a terminal")
    }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? arguments[0])
    child.arguments = [serveFlag, arguments[1], ttyName]
    // stdio is severed so the pane tty cannot be touched even by accident. The controlling terminal belongs to the session rather than to an fd, so severing it this way leaves the child's TIOCSTI permission intact (measured)
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    do {
        try child.run()
    } catch {
        fail("could not launch the child process: \(errorMessage(error))")
    }
    exit(0)
}

guard arguments.count == 4, arguments[1] == serveFlag else {
    FileHandle.standardError.write(Data("usage: \(arguments.first ?? "helper") <socket-path>\n".utf8))
    exit(2)
}
let socketPath = arguments[2]
let ttyPath = arguments[3]

// We are in a background process group (the foreground is claude). Without ignoring SIGTTOU, TIOCSTI is blocked entirely — measured: in a process group orphaned by the parent leaving it is EIO, and when not orphaned a SIGTTOU arrives and it is EINTR. Ignoring it makes both cases succeed.
signal(SIGTTOU, SIG_IGN)
// If the app closes the connection before receiving the response, the write kills us with SIGPIPE
signal(SIGPIPE, SIG_IGN)

let ttyFD = open(ttyPath, O_RDWR | O_NOCTTY)
guard ttyFD >= 0 else { fail("could not open \(ttyPath) (\(lastErrnoName()))") }
// What is checked is not whether the name and the fd point at the same terminal, but whether it is **our session's controlling terminal** — otherwise we would report somebody else's tty to the app and its gates would pass while looking at the wrong session.
// A session has exactly one controlling terminal, so this comparison suffices
guard tcgetsid(ttyFD) == getsid(0) else {
    fail("\(ttyPath) is not this session's controlling terminal")
}

umask(0o077)
// Deletes an existing file and binds. Anything that is not a socket was not made by us and is left alone — the app draws the path with a random token so collisions do not happen on the normal path, but if one did, that file is somebody else's
socketPath.withCString { unlinkIfSocket($0) }
guard var address = makeUnixSockaddr(socketPath) else { fail("the socket path is too long: \(socketPath)") }
let server = socket(AF_UNIX, SOCK_STREAM, 0)
guard server >= 0 else { fail("socket(): \(lastErrnoName())") }
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bound == 0, listen(server, 4) == 0 else { fail("bind/listen: \(lastErrnoName())") }
chmod(socketPath, 0o600)
installSocketCleanupOnSignals(path: socketPath)

private let state = HelperState(ttyFD: ttyFD, ttyPath: ttyPath)
var finished = false

while !finished {
    var descriptor = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
    let ready = poll(&descriptor, 1, 2000)
    if ready > 0 {
        let client = accept(server, nil, nil)
        if client >= 0 {
            // Only same-user processes are allowed (the same criterion as the app's socket). Looking at the uid alone is a sufficient trust boundary here — a process of the same uid can already edit this user's files, swap the app bundle, and do anything at all to the pane claude is attached to, so narrowing the caller to a specific binary would prevent nothing in practice. Other users are stopped earlier by the socket file's permissions (0600). The random token in the path is not a secret but a name tag that keeps runs from mixing (it is written plainly in the Tab Config and visible on the pane too)
            var uid: uid_t = 0
            var gid: gid_t = 0
            if getpeereid(client, &uid, &gid) == 0, uid == getuid() {
                finished = serve(client: client, state: state)
                state.touch()
            }
            close(client)
        }
    } else if ready < 0 && errno != EINTR {
        checkoutLog("Warp injection helper poll failed: \(lastErrnoName())")
        break
    }
    // The same verdict is applied while there are no requests too (the request path is `serve`'s to check)
    if !finished, let stop = state.stopReason() {
        checkoutLog("Warp injection helper exiting: \(stop.description)")
        break
    }
}

if let path = socketPathForSignal { unlinkIfSocket(path) }
close(server)
close(ttyFD)
exit(0)
