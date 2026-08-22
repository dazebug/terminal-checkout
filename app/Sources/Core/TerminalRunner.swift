import Foundation

public enum TerminalError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case wezTermNotFound
    case warpNotFound
    case warpTabConfigFailed(String)
    case timeout(String)
    /// An undeliverable input we already know about **before** creating a tab. Identified by
    /// type, not by string — it reaches the extension as an `error` string, but inside the app
    /// this value is what tells the reasons apart
    case claudeInputNotDeliverable(ClaudeInputBlocker)

    public var description: String {
        switch self {
        case .appleScriptFailed(let message): return "AppleScript error: \(message)"
        case .wezTermNotFound: return "WezTerm not found. Install WezTerm or check your PATH."
        case .warpNotFound: return "Warp not found. Install Warp in /Applications or ~/Applications."
        case .warpTabConfigFailed(let message): return "Warp tab config error: \(message)"
        case .timeout(let what): return "Timed out: \(what)"
        case .claudeInputNotDeliverable(let blocker): return blocker.message
        }
    }
}

// MARK: - claude input preconditions (what we know is undeliverable before opening a tab)

/// Why scheduled input cannot be delivered. Only reasons knowable **before any side effect**
/// belong here — whichever point in the run establishes them.
public enum ClaudeInputBlocker: Equatable, CaseIterable {
    /// The screen cannot be read on Warp — no way to confirm claude received the input
    case warpAccessibility
    /// The in-pane injection helper could not be prepared (missing from the bundle, or the
    /// socket path exceeds the 104-byte limit)
    case warpHelperUnavailable
    /// WezTerm has no mux to spawn into, so the run would fall back to a fresh process whose
    /// pane cannot be addressed — `send-text` and `get-text` both need a mux pane id
    case wezTermSessionUnavailable

    /// Is the setup window the place to fix this? It holds the Accessibility card and the install
    /// state, so it answers the two Warp reasons. It has no WezTerm control on it — bringing it
    /// forward for "start WezTerm first" takes focus away from Chrome and shows nothing to do.
    public var setupWindowCanHelp: Bool {
        switch self {
        case .warpAccessibility, .warpHelperUnavailable: return true
        case .wezTermSessionUnavailable: return false
        }
    }

    /// Each reason implies a **different next action**. One shared wording would send a user who
    /// needs to grant a permission off to reinstall instead
    public var message: String {
        switch self {
        case .warpAccessibility:
            return "Injecting claude input on Warp needs the Accessibility permission —"
                + " grant it in the Terminal Checkout settings window."
        case .warpHelperUnavailable:
            return "The Warp injection helper could not be prepared — reinstall with ./install.sh."
        // Two ways to land here — no mux at all, and a mux whose spawn attempts all failed — so
        // the wording covers both rather than asserting the first
        case .wezTermSessionUnavailable:
            return "No WezTerm pane could be addressed for claude input —"
                + " make sure a WezTerm window is open and press again."
        }
    }
}

/// Must this run be rejected **before it is even attempted**? `injectsClaudeInput` is not "were
/// claude inputs scheduled" but **"will anything be typed into the session"**
/// (`PreparedRequest.claudeInputs`). **Every shipped preset reaches this** since round 10: their
/// inputs are all `!`, and a `!` only runs as a command when it is typed into claude's shell mode.
///
/// The state probes are `@autoclosure` because this runs inside the execQueue that holds up the
/// Chrome response: when the answer cannot depend on state (nothing to type, not Warp) no TCC or
/// filesystem lookup happens at all.
///
/// The switch has no `default`, so adding a terminal turns into a compile error right here. That
/// is a prompt to decide, **not a proof that every reason is knowable this early**: WezTerm
/// returns nil here and still rejects later, because whether a pane can be addressed is only
/// known once the mux has been asked (`wezTermFallbackRejection`). A new terminal has to be
/// walked through `docs/new-terminal-checklist.md`, not just through this switch.
public func claudeInputBlocker(
    terminal: Terminal, injectsClaudeInput: Bool,
    accessibilityTrusted: @autoclosure () -> Bool,
    injectionHelperReady: @autoclosure () -> Bool
) -> ClaudeInputBlocker? {
    guard injectsClaudeInput else { return nil }
    switch terminal {
    // iTerm2 and WezTerm read exactly their own screen by session or pane id, so they need no
    // extra permission. (iTerm2's Automation permission is a precondition of running the command
    // at all — without it osascript fails and the request is already rejected.) WezTerm's own
    // blocker cannot be evaluated yet — see `wezTermFallbackRejection`
    case .iterm, .wezterm: return nil
    case .warp:
        guard accessibilityTrusted() else { return .warpAccessibility }
        guard injectionHelperReady() else { return .warpHelperUnavailable }
        return nil
    }
}

/// The rejection to raise instead of taking the WezTerm fallback, or nil to take it.
///
/// The fallback starts a **new WezTerm process**: no mux, so no pane id, so `.none` for a session
/// handle and nothing to type into. That used to be a log line while the response said
/// `{success:true}`. It is raised at the fallback boundary rather than in `claudeInputBlocker`
/// because that is the first moment it is known.
///
/// "Before any side effect" is exact for the common way in — no mux found, and asking the mux
/// neither spawns nor writes. The other way in is a mux that answered but whose spawn attempts all
/// failed; a `wezterm cli spawn` that timed out **may** have opened a tab whose id we never read.
/// Not measured, and it does not change the decision (rejecting is still better than running with
/// the input dropped), but the claim is narrower than the branch.
func wezTermFallbackRejection(injectsClaudeInput: Bool) -> TerminalError? {
    guard injectsClaudeInput else { return nil }
    return claudeInputRejection(.wezTermSessionUnavailable)
}

/// The helper line to put in front of the user's command in the Tab Config, plus the socket the
/// app will talk to it on. Nil when nothing will be typed into the session.
///
/// **This is the last check before the side effect, and that is the point.** `runInTerminal`
/// already asked `claudeInputBlocker`, but between that answer and the Tab Config being written
/// the permission can be revoked or a reinstall can replace the bundle. The old code logged
/// "no permission, so the helper is not launched — only the command runs" and carried on, which is a `{success:true}`
/// with the input silently dropped. It is separated from `runInWarp` so the decision can be
/// exercised without launching Warp — the passing branch of `runInWarp` has side effects, so unit
/// tests stay off it.
func warpInjectionSetup(
    token: String, injectsClaudeInput: Bool,
    accessibilityTrusted: @autoclosure () -> Bool = accessibilityIsTrusted(),
    helperExecutable: () -> String? = warpHelperExecutablePath,
    socketPath: (String) -> String? = warpHelperSocketPath(token:)
) throws -> (line: String, socket: String)? {
    guard injectsClaudeInput else { return nil }
    guard accessibilityTrusted() else { throw claudeInputRejection(.warpAccessibility) }
    guard let executable = helperExecutable(), let socket = socketPath(token) else {
        throw claudeInputRejection(.warpHelperUnavailable)
    }
    return (warpHelperCommand(executable: executable, socketPath: socket), socket)
}

/// Hook that brings forward a window explaining the rejection. The App target installs it;
/// `--headless-server` has no `AppDelegate`, so it stays nil and e2e never opens a window.
public enum ClaudeInputGuidance {
    public static var present: ((ClaudeInputBlocker) -> Void)?
}

/// Puts rejection and explanation through **one door**, so that however many rejection sites
/// appear, none of them can become "a ❌ with the reason nowhere" — the extension only sends the
/// `error` string to the console (issue #29).
public func claudeInputRejection(_ blocker: ClaudeInputBlocker) -> TerminalError {
    if blocker.setupWindowCanHelp { ClaudeInputGuidance.present?(blocker) }
    return .claudeInputNotDeliverable(blocker)
}

/// Subprocess helper: a timeout, stdin injection, and pipe-deadlock avoidance.
@discardableResult
public func runProcess(
    _ path: String, _ args: [String],
    input: String? = nil,
    env: [String: String]? = nil,
    timeout: TimeInterval = 10
) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    if let env { process.environment = env }

    let outPipe = Pipe(), errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    let inPipe = Pipe()
    if input != nil { process.standardInput = inPipe } else { process.standardInput = FileHandle.nullDevice }

    try process.run()

    if let input {
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        inPipe.fileHandleForWriting.closeFile()
    }

    // The pipes have to be drained before waiting for exit, or a large output blocks
    let group = DispatchGroup()
    var outData = Data(), errData = Data()
    DispatchQueue.global().async(group: group) {
        outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    }
    DispatchQueue.global().async(group: group) {
        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    }

    let exited = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        process.waitUntilExit()
        exited.signal()
    }
    if exited.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        _ = exited.wait(timeout: .now() + 2)
        group.wait()
        throw TerminalError.timeout("\(path) \(args.joined(separator: " "))")
    }
    group.wait()

    return (
        process.terminationStatus,
        String(data: outData, encoding: .utf8) ?? "",
        String(data: errData, encoding: .utf8) ?? ""
    )
}

/// `injectsClaudeInput` says whether this run has claude input scheduled. Only Warp looks at it — injecting requires launching the injection helper inside the pane as well, and doing that for buttons with no input adds one more command block the user can see and leaves a useless process behind.
@discardableResult
public func runInTerminal(
    command: String, terminal: Terminal, injectsClaudeInput: Bool = false
) throws -> TerminalSessionHandle {
    // An undeliverable input known **before** any side effect rejects the whole request. Opening
    // the tab and dropping the tail answers `{success:true}`, so the button shows ✅ and the user
    // is left with a claude session that has no context
    if let blocker = claudeInputBlocker(
        terminal: terminal, injectsClaudeInput: injectsClaudeInput,
        accessibilityTrusted: accessibilityIsTrusted(),
        injectionHelperReady: warpInjectionHelperIsReady()
    ) {
        throw claudeInputRejection(blocker)
    }
    switch terminal {
    case .iterm: return try runInITerm(command)
    case .wezterm: return try runInWezTerm(command, injectsClaudeInput: injectsClaudeInput)
    case .warp: return try runInWarp(command, injectsClaudeInput: injectsClaudeInput)
    }
}

/// Opens a new tab in iTerm2 and runs the command.
/// osascript is a child process of this app, so the TCC automation permission is attributed to this app.
@discardableResult
public func runInITerm(_ command: String) throws -> TerminalSessionHandle {
    // Generous timeout: on the first run the automation permission prompt appears and blocks until the user answers
    let result = try runProcess("/usr/bin/osascript", ["-e", iTermScript(for: command)], timeout: 180)
    guard result.status == 0 else {
        throw TerminalError.appleScriptFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    // The "session id|tty" the script returned — on a malformed shape the run still counts as a success and only the handle is given up
    let parts = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "|", maxSplits: 1)
    guard parts.count == 2, !parts[0].isEmpty, parts[1].hasPrefix("/dev/") else { return .none }
    return .iterm(sessionID: String(parts[0]), tty: String(parts[1]))
}

/// Opens a new tab in Warp and runs the command.
/// Warp has neither AppleScript nor a pane-control CLI, so a Tab Config file plus a `warp://tab_config/<stem>` URL is the only way (measured). `open` goes through LaunchServices, so it launches Warp when it is not running and adds a tab to the active window when it is.
///
/// When claude input is scheduled, one more line runs ahead of the command to start the injection helper. The helper reports its own tty, so there is no hunting for the pane here — this function runs inside the execQueue that holds up the Chrome response, whereas waiting for the helper to come up can happen on the background delivery thread (`deliverClaudeInputs`).
///
/// The Tab Config file name carries a per-request token (`warpTabConfigStem`) — a fixed name overwrites the user's own file, and since Warp reads the file only after `open` has returned, consecutive requests swap each other's commands. In exchange, our file is deleted after giving the tab time to open.
@discardableResult
public func runInWarp(_ command: String, injectsClaudeInput: Bool = false) throws -> TerminalSessionHandle {
    guard findWarpAppBundle() != nil else { throw TerminalError.warpNotFound }

    // Reclaim leftovers from an earlier run the app died during (live ones are left alone)
    reclaimStaleWarpTabConfigs()
    reclaimDeadWarpHelperSockets()

    let token = warpHelperToken()
    // The precondition is checked once more **immediately before** the side effect — between `runInTerminal`'s verdict and this point the permission can be revoked or a reinstall can swap the bundle, and the old code then merely logged, ran the command and answered `{success:true}` (with the input silently evaporating). Throwing here means no tab is opened either — nothing has been created yet
    let injection = try warpInjectionSetup(token: token, injectsClaudeInput: injectsClaudeInput)
    let socketPath = injection?.socket
    let commands = [injection?.line, command].compactMap { $0 }

    let stem = warpTabConfigStem(token: token)
    let path = warpTabConfigPath(stem: stem)
    do {
        try FileManager.default.createDirectory(
            atPath: warpTabConfigDirectory(), withIntermediateDirectories: true
        )
        // Tokens will not collide, but if one did the existing file could be the user's — it is not overwritten.
        // Creating with `O_CREAT|O_EXCL` removes the "check then write" window: the check and the creation are one syscall
        try writeNewFile(path: path, contents: warpTabConfigTOML(commands: commands))
    } catch let error as TerminalError {
        throw error
    } catch {
        throw TerminalError.warpTabConfigFailed(errorMessage(error))
    }
    // The reclaim is scheduled the moment the file is written — the file must not survive even the branch where `open` throws.
    // Warp reads the file after `open` returns (measured 0.5∼0.7s until the pane appears), so it must not be deleted immediately
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + warpTabConfigLifetime) {
        removeWarpTabConfigIfOurs(path: path)
    }

    let result = try runProcess("/usr/bin/open", [warpTabConfigURL(stem: stem)], timeout: 15)
    guard result.status == 0 else {
        throw TerminalError.warpTabConfigFailed(
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    guard let socketPath else { return .none }
    return .warp(helperSocket: socketPath)
}

/// Only used for creating a new file. An existing one fails with `EEXIST` — checking for existence first and then writing overwrites a user file that lands in between.
private func writeNewFile(path: String, contents: String) throws {
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard fd >= 0 else {
        throw TerminalError.warpTabConfigFailed("could not create the file (\(String(cString: strerror(errno)))): \(path)")
    }
    defer { close(fd) }
    guard writeAll(fd: fd, data: Data(contents.utf8)) else {
        unlink(path)
        throw TerminalError.warpTabConfigFailed("could not write the file: \(path)")
    }
}

/// How long Warp is given to read the Tab Config and bring the pane up. It is headroom over the measured 0.5∼0.7s: shorter and the tab does not open, longer and our file lingers in the `+` menu.
/// **This interval does not guarantee "Warp has read it"** — there is no signal that would say so, which is why it leans on time, and a heavily loaded system may fail to open the tab. The outcome then is only "the tab does not open" (no data loss), so the headroom is set to 30x and left there. This is a timing assumption, unrelated to the trust boundary.
let warpTabConfigLifetime: TimeInterval = 20

/// Finds the WezTerm CLI: PATH first, then a Homebrew / app-bundle fallback.
/// (The app is a GUI process whose PATH is limited to roughly /usr/bin:/bin, so explicit candidates are mandatory.)
public func findWezTermCLI() -> String? {
    var candidates: [String] = []
    if let raw = getenv("PATH") {
        for dir in String(cString: raw).split(separator: ":") {
            candidates.append("\(dir)/wezterm")
        }
    }
    candidates.append(contentsOf: [
        "/opt/homebrew/bin/wezterm",
        "/usr/local/bin/wezterm",
        "/Applications/WezTerm.app/Contents/MacOS/wezterm",
    ])
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// The environment the wezterm CLI is called with — the GUI app's environment plus the mux socket we picked.
/// Window lookup, spawn, send-text and get-text all have to see the **same socket**, so it is built in exactly one place.
func wezTermEnvironment(socketPath: String?) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    if let socketPath { env["WEZTERM_UNIX_SOCKET"] = socketPath }
    return env
}

/// Finds the socket of a running WezTerm GUI process (newest first, matched by PID).
public func findWezTermSocket() -> String? {
    let sockDir = (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/wezterm")
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: sockDir) else { return nil }

    let runningPIDs: Set<String>
    if let result = try? runProcess("/usr/bin/pgrep", ["-x", "wezterm-gui"], timeout: 3), result.status == 0 {
        runningPIDs = Set(result.stdout.split(whereSeparator: \.isWhitespace).map(String.init))
    } else {
        runningPIDs = []
    }

    func mtime(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date).flatMap { $0 } ?? .distantPast
    }
    let sockets = entries.filter { $0.hasPrefix("gui-sock-") }
        .map { (sockDir as NSString).appendingPathComponent($0) }
        .sorted { mtime($0) > mtime($1) }

    for sock in sockets {
        if let pid = sock.split(separator: "-").last, runningPIDs.contains(String(pid)) {
            return sock
        }
    }
    return sockets.first
}

/// The order `wezterm cli spawn` is attempted in. With a window identified, that window is aimed at first, and on failure it is tried once more without one — if the window found closes just before the spawn, wezterm fails with "window_id N not found" (measured), and giving up there lets the `wezterm start` fallback open a new window, resurrecting the very symptom this fixes. With no window found there is only one attempt.
public func wezTermSpawnAttempts(windowID: String?) -> [[String]] {
    let base = ["cli", "spawn"]
    guard let windowID else { return [base] }
    return [base + ["--window-id", windowID], base]
}

/// Finds the id of the window holding the currently focused pane, out of the mux responses (list-clients + list).
/// Without --window-id, `wezterm cli spawn` picks the window from the pane in the WEZTERM_PANE environment variable, which a GUI app does not have — so the tab lands in the mux's first (= oldest) window and some other window than the one the user was looking at jumps to the front (measured). Hence the focused window is looked up and named explicitly.
public func wezTermFocusedWindowID(clientsJSON: Data, listJSON: Data) -> String? {
    guard let clients = (try? JSONSerialization.jsonObject(with: clientsJSON)) as? [[String: Any]],
          let list = (try? JSONSerialization.jsonObject(with: listJSON)) as? [[String: Any]]
    else { return nil }

    // A client without idle_time is pushed to the bottom so the selection below treats it as the last candidate
    func idleSeconds(_ client: [String: Any]) -> Double {
        guard let idle = client["idle_time"] as? [String: Any] else { return .greatestFiniteMagnitude }
        let secs = (idle["secs"] as? Double) ?? 0
        let nanos = (idle["nanos"] as? Double) ?? 0
        return secs + nanos / 1_000_000_000
    }
    // With several clients, the most recently active one is taken to be the window the user is looking at — what was actually measured is only the single-GUI case, so this selection rule is still an unverified premise. Being wrong yields "a tab in a window you were not looking at" and the spawn itself still succeeds (the same level as before this change).
    let focused = clients
        .compactMap { client -> (pane: Int, idle: Double)? in
            guard let pane = client["focused_pane_id"] as? Int else { return nil }
            return (pane, idleSeconds(client))
        }
        .min { $0.idle < $1.idle }
    guard let paneID = focused?.pane else { return nil }

    for pane in list where (pane["pane_id"] as? Int) == paneID {
        guard let windowID = pane["window_id"] as? Int else { return nil }
        return String(windowID)
    }
    return nil // the focused pane is already closed — do not pick the wrong window
}

/// Asks the mux for the focused window id (nil on a failed lookup → wezterm's default window choice).
/// This lookup runs inside the execQueue that holds up the Chrome response (`HostServer`) — today the two calls together take 20∼40ms (measured), which does not show in the button's responsiveness, but every lookup added delays the response by that much.
public func findWezTermFocusedWindow(cli: String, env: [String: String]) -> String? {
    guard let clients = try? runProcess(cli, ["cli", "list-clients", "--format", "json"], env: env, timeout: 5),
          clients.status == 0,
          let list = try? runProcess(cli, ["cli", "list", "--format", "json"], env: env, timeout: 5),
          list.status == 0
    else { return nil }
    return wezTermFocusedWindowID(clientsJSON: Data(clients.stdout.utf8), listJSON: Data(list.stdout.utf8))
}

/// Opens a new tab in the WezTerm window currently being looked at and runs the command (falling back to a new process when the spawn fails).
/// With `injectsClaudeInput` that fallback is not reachable — the pane cannot be addressed there, so the input would vanish (`wezTermFallbackRejection`).
@discardableResult
public func runInWezTerm(
    _ command: String, injectsClaudeInput: Bool = false
) throws -> TerminalSessionHandle {
    guard let cli = findWezTermCLI() else { throw TerminalError.wezTermNotFound }

    if let sock = findWezTermSocket() {
        let env = wezTermEnvironment(socketPath: sock)
        let windowID = findWezTermFocusedWindow(cli: cli, env: env)
        for args in wezTermSpawnAttempts(windowID: windowID) {
            guard let spawn = try? runProcess(cli, args, env: env, timeout: 5), spawn.status == 0 else {
                checkoutLog("wezterm \(args.joined(separator: " ")) failed")
                continue
            }
            let paneID = spawn.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try? runProcess(
                cli, ["cli", "send-text", "--pane-id", paneID, "--no-paste"],
                input: command + "\n", env: env, timeout: 5
            )
            _ = try? runProcess("/usr/bin/open", ["-a", "WezTerm"], timeout: 5)
            return .wezterm(paneID: paneID, cliPath: cli, socketPath: sock)
        }
    }

    // Fallback: a new WezTerm process = a new window (with no mux there is no window to attach to).
    // It does not wait for exit, and since the pane cannot be identified there is no handle either — which is why a run with input to type cannot come here. The fallback process has not been spawned yet, so there is no side effect to undo
    if let rejection = wezTermFallbackRejection(injectsClaudeInput: injectsClaudeInput) {
        throw rejection
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cli)
    process.arguments = ["start", "--", "/bin/bash", "-ic", "\(command); exec bash"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    return .none
}
