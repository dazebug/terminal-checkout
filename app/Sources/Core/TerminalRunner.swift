import Darwin
import Foundation

public enum TerminalError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case wezTermNotFound
    case warpNotFound
    case warpTabConfigFailed(String)
    case cmuxNotFound
    case cmuxSocketDenied
    case cmuxRPCFailed(String)
    case cmuxNotReachable(String)
    case timeout(String)
    /// The app is leaving, so no new delivery may be started. Transient by nature — which is why it
    /// is not a `ClaudeInputBlocker`: those name a state the user has to go and fix.
    ///
    /// **Both ways of leaving arrive here**, and the name and the sentence say so. The value is
    /// shared by language restart and termination, so neither path is described as the other.
    case goingAway
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
        case .cmuxNotFound: return "cmux not found. Install cmux or check your PATH."
        case .cmuxSocketDenied: return "cmux socket access denied."
        case .cmuxRPCFailed(let message): return "cmux RPC error: \(message)"
        case .cmuxNotReachable(let message): return "cmux not reachable: \(message)"
        case .timeout(let what): return "Timed out: \(what)"
        case .goingAway:
            return "Terminal Checkout is quitting or restarting — press the button again in a moment."
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
/// (`PreparedRequest.claudeInputs`). **Every shipped preset reaches this**: their
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
    case .cmux, .cmuxNightly: return nil
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
    let processID = process.processIdentifier
    // Keep timeout cleanup from leaving a descendant with the pipes open. Foundation exposes only
    // the process id: its public API has no child-side posix_spawn attribute hook. On Darwin 25.4.0,
    // a /bin/sh child returned by Process.run() had already execed before the parent could call
    // setpgid: 20/20 attempts returned EACCES. In practice isolatedProcessGroup is therefore
    // effectively always false; the three kill(-pid, ...) branches are best effort when this race
    // happens to be won, not the source of the timeout bound. The bound comes from closing the
    // pipe readers, and the measured sleep descendant can remain (pgrep rose from 1 to 2), so
    // this is not full process-tree cleanup. WezTerm's GUI fallback uses a raw Process, and
    // open -b/-a delegates to LaunchServices, so no current runProcess caller launches a
    // long-lived GUI child inside this group; revisit that assumption before keeping this branch
    // if that changes. A child-side group setup is not available through the public Foundation API.
    let isolatedProcessGroup = Darwin.setpgid(processID, processID) == 0

    if let input {
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        inPipe.fileHandleForWriting.closeFile()
    }

    // The pipes have to be drained before waiting for exit, or a large output blocks
    let group = DispatchGroup()
    var outData = Data(), errData = Data()
    let bufferLock = NSLock()
    DispatchQueue.global().async(group: group) {
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        bufferLock.lock()
        outData = data
        bufferLock.unlock()
    }
    DispatchQueue.global().async(group: group) {
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        bufferLock.lock()
        errData = data
        bufferLock.unlock()
    }

    let exited = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        process.waitUntilExit()
        exited.signal()
    }
    if exited.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        if isolatedProcessGroup { _ = Darwin.kill(-processID, SIGTERM) }

        let termGrace: TimeInterval = 2
        if exited.wait(timeout: .now() + termGrace) == .timedOut {
            // SIGTERM is a cooperative request. A child that ignores it (or a shell that traps it)
            // gets SIGKILL after the grace period, and the group is killed so it cannot keep our
            // pipe readers alive through an unrelated descendant.
            if isolatedProcessGroup { _ = Darwin.kill(-processID, SIGKILL) }
            _ = Darwin.kill(processID, SIGKILL)
            _ = exited.wait(timeout: .now() + 2)
        }

        // A killed process can still have a descendant holding stdout/stderr. Never wait forever
        // for that drain: close the readers after the bounded post-kill wait and give the drain a
        // short final chance to unwind before reporting the timeout.
        if group.wait(timeout: .now() + 1) == .timedOut {
            if isolatedProcessGroup { _ = Darwin.kill(-processID, SIGKILL) }
            outPipe.fileHandleForReading.closeFile()
            errPipe.fileHandleForReading.closeFile()
            if group.wait(timeout: .now() + 0.25) == .timedOut {
                checkoutLog(
                    "process output drain still exceeded the final 0.25s bound after timeout; "
                        + "captured buffers remain partial"
                )
            }
        }
        throw TerminalError.timeout("\(path) \(args.joined(separator: " "))")
    }
    // A normally exited parent can leave a background child holding a pipe open. Do not let that
    // descendant turn a successful command into an unbounded wait: one second is long enough for
    // ordinary pipe EOF after the parent exits, while the bounded final wait keeps this shared
    // helper from stalling the HostServer queue. The bytes collected so far are returned and the
    // partial drain is logged rather than silently discarded.
    let normalDrainTimeout: TimeInterval = 1
    if group.wait(timeout: .now() + normalDrainTimeout) == .timedOut {
        checkoutLog(
            "process \(path) exited but output drain exceeded \(normalDrainTimeout)s; "
                + "returning partial output"
        )
        outPipe.fileHandleForReading.closeFile()
        errPipe.fileHandleForReading.closeFile()
        // The race between the final wait and the readers is not reproduced deterministically in
        // a test; both readers and this caller use bufferLock so the timeout still has defined data.
        if group.wait(timeout: .now() + 0.25) == .timedOut {
            checkoutLog(
                "process output drain still exceeded the final 0.25s bound; "
                    + "returning captured partial output"
            )
        }
    }

    bufferLock.lock()
    let capturedOutData = outData
    let capturedErrData = errData
    bufferLock.unlock()

    // Lossy decoding preserves a valid prefix when J3's forced pipe close cuts a multibyte
    // sequence. The old optional decoder returned an empty string for that same invalid byte;
    // log the invalid original instead of changing it silently.
    func decoded(_ data: Data, stream: String) -> String {
        if String(data: data, encoding: .utf8) == nil {
            checkoutLog(
                "process output contained invalid UTF-8 on \(stream); using lossy decoding"
            )
        }
        return String(decoding: data, as: UTF8.self)
    }

    return (
        process.terminationStatus,
        decoded(capturedOutData, stream: "stdout"),
        decoded(capturedErrData, stream: "stderr")
    )
}

/// `claudeInput` is the slot this run reserved for its delivery, and its presence is what says input is scheduled. Only Warp goes further with it — injecting requires launching the injection helper inside the pane as well, and doing that for buttons with no input adds one more command block the user can see and leaves a useless process behind.
///
/// It replaced a `Bool`: the boolean and the reservation were two values saying the same thing, kept in step by the one call site that set both, and only a reservation can be checked against the gate that says whether a helper may still be created. Nothing outside `ClaudeInjector.swift` can make one, so "this run injects" is now the same fact as "this run has been admitted".
@discardableResult
public func runInTerminal(
    command: String, terminal: Terminal, claudeInput: ClaudeDelivery.Admission? = nil
) throws -> TerminalSessionHandle {
    let injectsClaudeInput = claudeInput != nil
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
    case .warp: return try runInWarp(command, claudeInput: claudeInput)
    case .cmux: return try runInCmux(command, channel: .stable)
    case .cmuxNightly: return try runInCmux(command, channel: .nightly)
    }
}

private let cmuxReadinessWaitTimeout: TimeInterval = 10
private let cmuxReadinessPollInterval: TimeInterval = 0.1

/// Keep launch and readiness diagnostics ahead of the generic timeout so a missing bundle or the
/// last server error survives the bounded poll.
func cmuxReadinessTimeoutDescription(
    launchExitStatus: Int32?, lastError: TerminalError?
) -> String {
    var details: [String] = []
    if let launchExitStatus {
        details.append("cmux launch exited with status " + String(launchExitStatus))
    }
    if let lastError {
        details.append("last readiness error: " + errorMessage(lastError))
    }
    guard !details.isEmpty else { return "cmux readiness" }
    return details.joined(separator: "; ") + "; cmux readiness"
}

/// After launching, a successful `debug.terminals` RPC is the server-side readiness proof. A
/// denied response is surfaced immediately. A `.noLiveSocket` pin is not queried: another
/// channel's response cannot prove that the selected channel is ready. The normal first
/// `workspace.create` success path never calls this poll, preserving the two-RPC budget. The
/// channel's socket pin is re-resolved on every attempt, and only `.discover` uses unpinned
/// discovery while no channel has a live pointer.
private func waitForCmuxReadiness(
    cliPath: String, channel: CmuxChannel, launchExitStatus: Int32?,
    initialError: TerminalError? = nil
) throws {
    let deadline = Date().addingTimeInterval(cmuxReadinessWaitTimeout)
    var lastError: TerminalError?
    if let initialError, case .cmuxSocketDenied = initialError {
        lastError = nil
    } else {
        lastError = initialError
    }
    while true {
        let remaining = deadline.timeIntervalSinceNow
        guard remaining > 0 else {
            throw TerminalError.timeout(
                cmuxReadinessTimeoutDescription(
                    launchExitStatus: launchExitStatus, lastError: lastError
                )
            )
        }
        let socketPin = currentCmuxSocketPin(channel: channel)
        if case .noLiveSocket = socketPin {
            // Keep waiting for the selected channel's pointer; an unpinned response could come
            // from the other channel and would falsely declare the launch ready.
        } else {
            let socketPath: String?
            switch socketPin {
            case .pinned(let path): socketPath = path
            case .discover: socketPath = nil
            case .noLiveSocket: socketPath = nil
            }
            do {
                _ = try cmuxRPC(
                    cli: cliPath, method: cmuxDebugTerminalsMethod,
                    timeout: min(3, remaining),
                    socketPath: socketPath
                )
                return
            } catch let error as TerminalError {
                switch cmuxReadinessOutcome(from: error) {
                case .ready:
                    return
                case .denied:
                    throw TerminalError.cmuxSocketDenied
                case .notReady:
                    lastError = error
                }
            } catch {
                // An untyped process failure is not a readiness proof, but keep its reason for the
                // bounded timeout rather than replacing it with a generic sentence.
                lastError = .cmuxRPCFailed(errorMessage(error))
            }
        }
        let sleepFor = min(cmuxReadinessPollInterval, deadline.timeIntervalSinceNow)
        guard sleepFor > 0 else {
            throw TerminalError.timeout(
                cmuxReadinessTimeoutDescription(
                    launchExitStatus: launchExitStatus, lastError: lastError
                )
            )
        }
        Thread.sleep(forTimeInterval: sleepFor)
    }
}

private func currentCmuxSocketPin(channel: CmuxChannel) -> CmuxSocketPin {
    cmuxSocketPin(channel: channel) { cmuxChannelSocketPath(channel: $0) }
}

private func cmuxPinnedSocketPathOrThrow(channel: CmuxChannel) throws -> String {
    let socketPin = currentCmuxSocketPin(channel: channel)
    guard case .pinned(let socketPath) = socketPin else {
        let pointerPaths = cmuxSocketPointerPaths(channel: channel).joined(separator: " or ")
        let channelName = channel == .nightly ? "NIGHTLY" : "stable"
        throw TerminalError.cmuxRPCFailed(
            "cmux \(channelName) has no live socket pointer (checked \(pointerPaths)); "
                + "refusing unpinned \(cmuxWorkspaceCreateMethod)"
        )
    }
    return socketPath
}

private func launchCmuxAndWait(cliPath: String, channel: CmuxChannel) throws {
    // Passing no target after the bundle id is deliberate: an argument would disable cmux
    // session restoration by turning this into an explicit launch.
    var launchExitStatus: Int32?
    var launchError: TerminalError?
    do {
        launchExitStatus = try runProcess(
            "/usr/bin/open", ["-b", channel.bundleID], timeout: 15
        ).status
    } catch let error as TerminalError {
        launchError = error
    } catch {
        launchError = .cmuxRPCFailed(errorMessage(error))
    }
    try waitForCmuxReadiness(
        cliPath: cliPath,
        channel: channel,
        launchExitStatus: launchExitStatus,
        initialError: launchError
    )
}

/// How long the command send waits for the pane's shell to start reading (raw mode). A zsh with
/// shell integration reaches its prompt well inside this on the measured machine (the tty itself
/// appears at ~1.4s); the deadline exists for shells that never enter raw mode, where the
/// canonical-limit gate falls back by payload size.
private let cmuxShellReadingWaitTimeout: TimeInterval = 10
private let cmuxShellReadingPollInterval: TimeInterval = 0.1

/// `cmuxTTYName` returns a complete `/dev/...` path; stty receives it unchanged.
func cmuxRawModeProbeArguments(ttyPath: String) -> [String] {
    ["-f", ttyPath, "-a"]
}

/// Polls until the surface's tty exists and is in raw mode, then answers the send gate. Sending
/// earlier lands the bytes in a canonical-mode line buffer that keeps exactly
/// `darwinCanonicalLineLimit` bytes of an unread line and silently discards the rest, CR
/// included (measured) — the command then sits truncated and unsubmitted while every layer
/// reports success, and the kernel's own echo paints it once more ahead of the prompt.
func cmuxAwaitShellReading(
    cliPath: String, socketPath: String?, surfaceID: String, payloadByteCount: Int
) -> CmuxCommandGate {
    let deadline = Date().addingTimeInterval(cmuxShellReadingWaitTimeout)
    var ttyPath: String?
    while true {
        if ttyPath == nil {
            let response = try? cmuxRPC(
                cli: cliPath, method: cmuxDebugTerminalsMethod, params: [:], timeout: 5,
                socketPath: socketPath
            )
            if let response, let data = try? JSONSerialization.data(withJSONObject: response) {
                ttyPath = cmuxTTYName(debugTerminalsJSON: data, surfaceID: surfaceID)
            }
        }
        var rawMode: Bool?
        if let ttyPath,
           let stty = try? runProcess(
               "/bin/stty", cmuxRawModeProbeArguments(ttyPath: ttyPath), timeout: 5
           ) {
            // A failed stty stays nil — "cannot tell", which the gate treats as not raw, the same
            // rule as the claude session gate.
            rawMode = ttyIsRawMode(sttyOutput: stty.stdout + stty.stderr)
        }
        let gate = cmuxCommandSendGate(
            rawModeObserved: rawMode,
            deadlineExpired: Date() >= deadline,
            payloadByteCount: payloadByteCount
        )
        if gate != .waitLonger { return gate }
        Thread.sleep(forTimeInterval: cmuxShellReadingPollInterval)
    }
}

/// Opens a workspace in cmux and starts the command on its returned surface. cmux chooses the
/// user's last active window; the command itself owns cwd through its assembled `{cd}` clause.
@discardableResult
public func runInCmux(
    _ command: String, channel: CmuxChannel = .stable
) throws -> TerminalSessionHandle {
    guard let cliPath = findCmuxCLI(channel: channel) else { throw TerminalError.cmuxNotFound }
    var socketPath: String?
    var launchAttempted = false
    switch currentCmuxSocketPin(channel: channel) {
    case .pinned(let path):
        socketPath = path
    case .discover:
        socketPath = nil
    case .noLiveSocket:
        launchAttempted = true
        try launchCmuxAndWait(cliPath: cliPath, channel: channel)
        socketPath = try cmuxPinnedSocketPathOrThrow(channel: channel)
    }

    // The execution path deliberately does not ping first: workspace.create is the authoritative
    // diagnosis for the request, and a normal run stays at D7's two RPCs. A first denial is final;
    // only another first failure gets one launch and one workspace retry, never a second workspace
    // creation after a successful first response.
    let workspace: [String: Any]
    do {
        workspace = try cmuxRPC(
            cli: cliPath, method: cmuxWorkspaceCreateMethod,
            params: cmuxWorkspaceCreateParameters(),
            socketPath: socketPath
        )
    } catch let firstFailure as TerminalError {
        switch cmuxRecoveryAction(afterFirstFailure: firstFailure, launchAttempted: launchAttempted) {
        case .rethrow:
            throw firstFailure
        case .launchAndRetry:
            try launchCmuxAndWait(cliPath: cliPath, channel: channel)
            // The restarted server wrote a fresh socket pointer; the pre-launch resolution may
            // still name the socket it left behind.
            socketPath = cmuxChannelSocketPath(channel: channel)
            workspace = try cmuxRPC(
                cli: cliPath, method: cmuxWorkspaceCreateMethod,
                params: cmuxWorkspaceCreateParameters(),
                socketPath: socketPath
            )
        }
    } catch {
        throw error
    }
    guard let identifiers = cmuxWorkspaceIdentifiers(from: workspace) else {
        throw TerminalError.cmuxRPCFailed(
            "\(cmuxWorkspaceCreateMethod): response missing workspace_id or surface_id"
        )
    }

    let payload = command + claudeSubmitKey
    switch cmuxAwaitShellReading(
        cliPath: cliPath, socketPath: socketPath,
        surfaceID: identifiers.surfaceID, payloadByteCount: payload.utf8.count
    ) {
    case .send:
        break
    case .waitLonger:
        // Keep this future-proof if the polling helper ever returns early: waiting is not proof
        // that the tty is raw, so apply the same bounded fallback as a deadline expiry.
        if payload.utf8.count <= darwinCanonicalLineLimit {
            checkoutLog(
                "cmux pane did not confirm raw mode; sending "
                    + "\(payload.utf8.count) bytes inside the canonical line limit"
            )
        } else {
            throw TerminalError.cmuxRPCFailed(
                "\(cmuxSurfaceSendTextMethod): the pane's shell did not confirm raw mode, and "
                    + "\(payload.utf8.count) bytes exceed the canonical line buffer "
                    + "(\(darwinCanonicalLineLimit) bytes) — the tail would be silently dropped, "
                    + "so nothing was sent"
            )
        }
    case .sendDespiteCanonical:
        checkoutLog(
            "cmux pane never reported raw mode within \(Int(cmuxShellReadingWaitTimeout))s; "
                + "sending \(payload.utf8.count) bytes inside the canonical line limit"
        )
    case .refuseTooLong:
        throw TerminalError.cmuxRPCFailed(
            "\(cmuxSurfaceSendTextMethod): the pane's shell did not start reading within "
                + "\(Int(cmuxShellReadingWaitTimeout))s, and \(payload.utf8.count) bytes exceed "
                + "the canonical line buffer (\(darwinCanonicalLineLimit) bytes) — the tail would "
                + "be silently dropped, so nothing was sent"
        )
    }

    let sendResponse = try cmuxRPC(
        cli: cliPath, method: cmuxSurfaceSendTextMethod,
        params: cmuxSurfaceSendTextParameters(
            surfaceID: identifiers.surfaceID, text: payload
        ),
        socketPath: socketPath
    )
    if sendResponse["queued"] as? Bool == true {
        checkoutLog("cmux \(cmuxSurfaceSendTextMethod) queued=true")
    }
    return .cmux(
        surfaceID: identifiers.surfaceID,
        workspaceID: identifiers.workspaceID,
        cliPath: cliPath,
        socketPath: socketPath
    )
}

/// Opens a new tab in iTerm2 and runs the command.
/// osascript is a child process of this app, so the TCC automation permission is attributed to this app.
@discardableResult
public func runInITerm(_ command: String) throws -> TerminalSessionHandle {
    // Generous timeout: on the first run the automation permission prompt appears and blocks until the user answers
    let result = try runAppleScript(iTermScript(for: command), timeout: 180)
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
///
/// **The helper's address is written into the register before the file is**. This is the only place a Warp injection helper is brought into existence, and the address it will answer on is known one line earlier — so recording it here, through the same lock that closes the admission gate, is what makes "a helper exists outside the register" unreachable rather than merely unlikely. A refusal means the app is going away and nothing is created: no Tab Config, no `open`, no tab.
@discardableResult
public func runInWarp(
    _ command: String, claudeInput: ClaudeDelivery.Admission? = nil
) throws -> TerminalSessionHandle {
    guard findWarpAppBundle() != nil else { throw TerminalError.warpNotFound }

    // Reclaim leftovers from an earlier run the app died during (live ones are left alone)
    reclaimStaleWarpTabConfigs()
    reclaimDeadWarpHelperSockets()

    let token = warpHelperToken()
    // The precondition is checked once more **immediately before** the side effect — between `runInTerminal`'s verdict and this point the permission can be revoked or a reinstall can swap the bundle, and the old code then merely logged, ran the command and answered `{success:true}` (with the input silently evaporating). Throwing here means no tab is opened either — nothing has been created yet
    let injection = try warpInjectionSetup(token: token, injectsClaudeInput: claudeInput != nil)
    let socketPath = injection?.socket
    let commands = [injection?.line, command].compactMap { $0 }
    // What follows is what creates: the Tab Config, and then the tab that runs the helper. So the
    // register learns where that helper will answer **before** either exists — and if the gate has
    // closed since this request was admitted, this is where the run stops instead
    if let claudeInput {
        // `warpInjectionSetup` throws rather than answering nil for a run that injects, so the
        // address is in hand here. The impossible pairing lands on the rejection that names it
        // instead of skipping the record, which is how "no address" would become "launched
        // unregistered"
        guard let socketPath else { throw claudeInputRejection(.warpHelperUnavailable) }
        // The file the app will link from if it has to take this address back. Made **here**, with
        // the register entry, because making it at termination would put an allocation into the one
        // moment that must not fail — which is the sliver `mkdir` left.
        //
        // **And the request is refused when it cannot be made.** Without the pin there is nothing to
        // link from, so the address could not be taken back and a late helper would answer with
        // nothing left to dismiss it — the failure this guard prevents. Refusing costs the
        // user this delivery; not refusing costs them a helper the app cannot reach
        guard createWarpHelperPin(forAdvertised: socketPath) else {
            throw claudeInputRejection(.warpHelperUnavailable)
        }
        // **Before `record`, and cleaned up if `record` throws.** The order is not swappable: a
        // registered address whose pin does not exist yet is an address a departure cannot take back,
        // which is this item's defect in a new window. So the pin goes first and the failing path is
        // the one that tidies — nothing has been launched at that point and nothing can claim
        do {
            try claudeInput.record(.warp(helperSocket: socketPath))
        } catch {
            removeWarpHelperPin(forAdvertised: socketPath)
            throw error
        }
    }

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

/// Spells text as a **bash ANSI-C literal** (`$'…'`) that is itself pure ASCII.
///
/// The reason is one boundary: Foundation re-encodes `Process.arguments` to NFD
/// (`ProcessArgumentBoundaryTests`), and an argument that is **already ASCII cannot be changed by
/// that re-encoding**. So the bytes are spelled out on our side and bash puts them back. Measured
/// on `/bin/bash` 3.2.57 (the system bash this launches by absolute path) for a byte followed by a
/// hex digit, a newline, a tab, a quote, a backslash and Korean/Japanese/Chinese text — `\xHH`
/// takes at most two hex digits, so `설계1` survives.
///
/// `$'…'` is bash syntax and not POSIX; the only caller hands `wezterm start` the absolute path
/// `/bin/bash`, so the interpreter is not the user's login shell and cannot be something else.
///
/// Printable ASCII passes through unescaped, which is not decoration: an all-ASCII command has to
/// stay readable in `ps` and in the pane the user is looking at. Only `'` (it would close the
/// literal), `\` (it would start an escape) and everything outside printable ASCII are spelled out.
func bashANSICQuoted(_ text: String) -> String {
    var literal = "$'"
    for byte in Data(text.utf8) {
        if byte >= 0x20, byte < 0x7F, byte != UInt8(ascii: "'"), byte != UInt8(ascii: "\\") {
            literal.unicodeScalars.append(UnicodeScalar(byte))
        } else {
            literal += String(format: "\\x%02x", byte)
        }
    }
    return literal + "'"
}

/// The argv for the WezTerm fallback launch — a new process, so there is no mux pane to write to and
/// the command has nowhere to ride but argv.
///
/// **This is the same normalisation boundary as the iTerm2 one and it is reachable.** A request
/// whose claude input is a single plain-text message has that message appended to the command
/// (`appendedPromptCommand`) and comes back with `claudeInputs` empty, so `injectsClaudeInput` is
/// false and `wezTermFallbackRejection` lets the fallback run — carrying the user's sentence. This
/// is the no-mux path, i.e. every first click before WezTerm has ever been started.
///
/// The two carriers that work elsewhere are both unavailable here: the mux path writes the command
/// to `send-text` on **stdin**, and Warp writes it to a **file**, but a fresh `wezterm start` has
/// neither. The environment is no way out either — measured, `Process.environment` decomposes just
/// like argv. What is left is to make the argument ASCII, which `bashANSICQuoted` does, and `eval`
/// is what turns the literal back into a command line (in command position a `$'…'` would be read
/// as a program name).
///
/// `eval` **replaces** the outer parse rather than adding one, so the command text is parsed exactly
/// once either way. Compared against the interpolation it replaces, `echo a!b`, a quoted `!`, and a
/// `cd … && …` chain came out identical in exit status, stdout and stderr — four cases, which is
/// what was checked and not a claim about every command.
func wezTermFallbackArguments(command: String) -> [String] {
    ["start", "--", "/bin/bash", "-ic", "eval \(bashANSICQuoted(command)); exec bash"]
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
    // It does not wait for exit, and since the pane cannot be identified there is no handle either — which is why a run with input to type cannot come here. There is no **fallback-process** side effect to undo at this point; a spawn attempt above that timed out may already have opened a tab we cannot identify, and that one is not undone either
    if let rejection = wezTermFallbackRejection(injectsClaudeInput: injectsClaudeInput) {
        throw rejection
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cli)
    process.arguments = wezTermFallbackArguments(command: command)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    return .none
}
