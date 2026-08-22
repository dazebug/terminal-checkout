import Foundation

/// The session handle `runInTerminal` returns — what claude input will later be typed into.
public enum TerminalSessionHandle {
    case iterm(sessionID: String, tty: String)
    case wezterm(paneID: String, cliPath: String, socketPath: String?)
    /// Warp has neither a CLI nor AppleScript that can address a pane, so the socket of the injection helper running inside the pane is the only channel. Even the tty is learned by asking that helper (`ClaudeInjector.warpHelperTTY`).
    case warp(helperSocket: String)
    /// No delivery path (the WezTerm fallback launch, a Warp helper that could not be prepared, and so on).
    case none

    /// Can a screen read be asserted to belong to this session? iTerm2 and WezTerm read exactly that screen by session or pane id, whereas Warp only ever reads "the focused pane" — so only that one needs a pane proof.
    var screenNeedsPaneProof: Bool {
        if case .warp = self { return true }
        return false
    }
}

/// The foreground process names that count as claude. The npm distribution shows up as comm=node and a native install as comm=claude (confirmed). `bun` is headroom for environments that run it on the bun runtime.
private let claudeProcessNames: Set<String> = ["claude", "node", "bun"]

/// The key that submits an input. Why it has to be CR rather than LF is in `submitClaudeInputs`.
let claudeSubmitKey = "\r"
/// The **sequence** that empties the input box: Ctrl+U (0x15) followed by Backspace (0x7F). Erasing the marker, clearing before an input, and the end-of-delivery cleanup all use this one constant, so changing it here applies everywhere.
/// iTerm2 receives AppleScript rather than bytes, but that script is derived from this constant too (`appleScriptCharacters(of:)`) — while 21 and 127 were written out separately, this sentence was false, and changing the constant silently left iTerm2 on the old sequence.
///
/// **Why the Backspace is there — measured (2.1.238, pty).** Ctrl+U does not leave claude's `!` shell mode: sending it on `!text` erases the text and **leaves the `!`**. On screen that looks like an empty input box and even passes the disappearance check, while the plain text typed afterwards was **submitted and executed as a shell command** (`command not found: tcq3hello`). One Backspace after the Ctrl+U removes that `!`, and the plain text after it is submitted as an ordinary message (same measurement). Sending several Backspaces to an already-empty box had no side effect.
///
/// **The order matters**: on a box that still holds text, Backspace erases only its last character, so it must come **after** Ctrl+U has emptied it.
///
/// Only `!` was measured. The `/` and `#` prefixes are one character too and should be erased by the same sequence, but that is inference, not measurement.
let claudeClearInputKey = "\u{15}\u{7F}"

/// Returns the PID of the claude that is in the foreground process group (stat contains `+`), out of `ps -t <tty> -o pid=,stat=,comm=` output. nil when there is none. With the shell sitting at its prompt the shell itself is `+`, so the answer is nil — and this gate is the only defence against the mistyping where input goes into the shell and Enter runs it immediately.
/// A PID is returned rather than a yes/no because the re-wait between inputs has to confirm the session's identity: going by the name and raw mode alone, a claude that came up on the same tty after the original died reads as the same session, and the remaining inputs get submitted into an unrelated one. Restarting claude on the same tty confirmed it — comm (`claude`) and raw mode (true) were identical across the two sessions and only the PID differed, so the PID is the only signal that can tell a session swap apart.
public func claudeForegroundPID(psOutput: String) -> Int? {
    for line in psOutput.split(separator: "\n") {
        // "pid stat comm…" — comm may be a full path containing spaces, so only the first two gaps are split on
        let parts = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
        guard parts.count == 3, let pid = Int(parts[0]), parts[1].contains("+") else { continue }
        // The last piece produced by maxSplits keeps the separating whitespace — without trimming it every name comparison is off. ps right-aligns the pid so it carries leading spaces too, but split already filters those
        var name = (parts[2].trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() } // the login-shell spelling (-zsh)
        if claudeProcessNames.contains(name) { return pid }
    }
    return nil
}

/// Decides from `stty -f <tty> -a` output whether the tty is in raw mode.
/// nil means "cannot tell" (stty failed, or the output format changed) — which lets the caller carry on with the ps gate alone.
/// `-icanon` contains `icanon` as a substring, so the comparison has to be token by token.
public func ttyIsRawMode(sttyOutput: String) -> Bool? {
    let tokens = sttyOutput.split(whereSeparator: { $0.isWhitespace })
    if tokens.contains("-icanon") { return true }
    if tokens.contains("icanon") { return false }
    return nil
}

/// The claude's PID when it is in a state to accept input, otherwise nil. The foreground being claude is not enough on its own: right after the shell execs claude the tty is still canonical (icanon+echo), so typing is echoed by the kernel rather than by claude. `screenReflectsNewInput` mistakes that echo for the screen reflecting the input, and a CR sent too early is lost when claude switches to raw mode and redraws — the first input is never submitted and hangs in the input box as text. A 1-second poll usually steps over this canonical window (0.1∼1s after the exec) and happens to work, but a slow claude start loses the first input — polling tightly enough to aim at the canonical window lost the first of three inputs 100% of the time (measured on WezTerm).
/// In raw mode the kernel echo is off, so text on screen after this gate has passed was drawn by claude itself — which is what finally lets the reflection check mean **claude rendered those bytes**, and only where the screen is known to be our pane. Whether claude *received* the message is a different question, and one nothing outside the TUI can answer (`InputBoxOwnership`).
/// The returned PID is used to check that later inputs go to the same session.
/// Neither signal can be used alone: zsh's zle also leaves the tty in raw mode while the shell waits at its prompt (measured), so going by raw mode alone types straight into the shell. Treating the ps check as redundant and removing it brings back the very shell mistyping this exists to prevent.
public func acceptingClaudePID(psOutput: String, sttyOutput: String) -> Int? {
    guard let pid = claudeForegroundPID(psOutput: psOutput) else { return nil }
    // When it cannot be told, carry on with the ps gate alone — an unreadable stty is not a reason to abandon delivery entirely
    guard ttyIsRawMode(sttyOutput: sttyOutput) ?? true else { return nil }
    return pid
}

/// Finds a pane's tty path in `wezterm cli list --format json` output.
public func wezTermTTYName(listJSON: Data, paneID: String) -> String? {
    guard let list = (try? JSONSerialization.jsonObject(with: listJSON)) as? [[String: Any]],
          let paneNumber = Int(paneID) else { return nil }
    for pane in list where (pane["pane_id"] as? Int) == paneNumber {
        return pane["tty_name"] as? String
    }
    return nil
}

/// The random value used for the pane proof. It can only enter our own tty, so seeing it newly appear on screen is evidence that the screen is our pane. It is alphanumeric so it means nothing special to claude's input box (`/`, `!` and `@` trigger modes and completion), and long enough not to collide by accident.
public func paneProofToken() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return "tc" + String((0..<10).map { _ in alphabet.randomElement()! })
}

/// The probe used to confirm the screen reflects an input. A long input is truncated or folded somewhere on screen, so only its front is used.
///
/// **Are the first 24 characters enough — measured (2.1.238, pty).** Even a single 4,000-character line put into the input box makes the composer grow vertically and show all of it, with the first 24 characters staying on screen. A merged `!` line (∼300 characters for the shipped presets) is far shorter than that. So there is no reason to move the probe to a later slice or to lower the merge cap.
public func claudeInputProbe(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(trimmed.prefix(24))
}

/// Decides whether the typed input appeared on screen **this time round**. The probe has to be visible one more time than in the screen taken immediately before typing (`before`) for it to count as reflected.
///
/// Why "is it on screen" is not enough: on Warp the screen read through Accessibility belongs to the focused pane, with no guarantee it is ours. If another pane happens to show the same text, a plain substring match passes even before we type, and the CR that follows submits — leaving our input unsubmitted while whatever the user was typing in that pane goes in instead.
/// A nil `before` (a failed screen read) is a failed check — treating what could not be sampled as "it was not there" leaves exactly the same hole open.
///
/// All whitespace is removed before comparing because the claude TUI does not draw the input verbatim: shell mode (`!`) inserts a space after the `!`, as in "! gh …", and a long input wraps at the terminal width (both measured). Compared whole, such inputs would fail the reflection check forever and hang in the input box.
/// It counts occurrences rather than presence so that scheduling the same input twice still submits the second one while the first is still in the transcript.
public func screenReflectsNewInput(before: String?, after: String, input: String) -> Bool {
    guard let before else { return false }
    let probe = claudeInputProbe(input).filter { !$0.isWhitespace }
    // An empty probe matches any screen at all and would approve a submission that should not happen
    guard !probe.isEmpty else { return false }
    return probeCount(probe, in: after) > probeCount(probe, in: before)
}

private func probeCount(_ probe: String, in screen: String) -> Int {
    var count = 0
    var rest = Substring(screen.filter { !$0.isWhitespace })
    while let found = rest.range(of: probe) {
        count += 1
        rest = rest[found.upperBound...]
    }
    return count
}

/// Session I/O — in reality osascript and wezterm cli calls, split out as closures so the delivery order and the failure-recovery verdicts can be exercised without any processes.
public struct ClaudeSessionIO {
    /// Sends keystrokes without appending a newline. false means "this call failed" and nothing more — it does not mean the session is over, which is confirmSession's verdict to make.
    public var sendKeys: (String) -> Bool
    /// The current screen text. nil on a failed read.
    public var screenText: () -> String?
    /// True when the claude originally prepared reaches a state to accept input within the given time (this one waits).
    public var confirmSession: (TimeInterval) -> Bool
    /// Gate ③, **immediately before bytes go out**: is it still that first claude (this one does not wait)?
    /// Only `send(_:io:)` calls it, and every send goes through `send` — checking at each send site separately guarantees a missed site.
    public var sessionIsUnchanged: () -> Bool
    /// Is there still a way to confirm through the screen (on Warp: the Accessibility permission)? When false **nothing new is typed** — what is typed without confirmation can neither be submitted nor taken back. The cleanup that undoes what was already typed (`clearAbandonedInput`) deliberately does not look at this condition: blocking it too would leave our automatic input in the box, to be run by an Enter the user presses later.
    public var canConfirmScreen: () -> Bool
    /// True for terminals where `screenText` cannot be asserted to be our session's screen.
    /// iTerm2 and WezTerm read exactly that pane by pane or session id, so they are false. Warp only ever reads "the focused pane" through Accessibility, so it is true — and then every input runs the pane proof first.
    public var screenNeedsPaneProof: Bool
    /// The wait — removed in tests so the loops run immediately.
    public var wait: (TimeInterval) -> Void

    public init(
        sendKeys: @escaping (String) -> Bool,
        screenText: @escaping () -> String?,
        confirmSession: @escaping (TimeInterval) -> Bool,
        sessionIsUnchanged: @escaping () -> Bool = { true },
        canConfirmScreen: @escaping () -> Bool = { true },
        screenNeedsPaneProof: Bool = false,
        wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.sendKeys = sendKeys
        self.screenText = screenText
        self.confirmSession = confirmSession
        self.sessionIsUnchanged = sessionIsUnchanged
        self.canConfirmScreen = canConfirmScreen
        self.screenNeedsPaneProof = screenNeedsPaneProof
        self.wait = wait
    }
}

/// The kind of bytes going out. There is one door but the requirements differ — moving the check **outside** the door guarantees a missed site (that is exactly how body typing once leaked past the gate), so the kind is carried through the door and split inside it.
enum SendKind {
    /// Something newly typed (the marker, the body, the CR, a retype after clearing). It requires a way to confirm through the screen
    case typing
    /// Undoing what was already typed (the cleanup Ctrl+U). It has to go out regardless of whether the screen can be confirmed — blocking it too leaves our text in the box, to be run by an Enter the user presses
    case cleanup
}

/// **The only door bytes go out through.** The gate is checked here and nowhere else — the marker, the input-box clear, body typing, the CR and the cleanup all pass through this function, so a new send path cannot leak around the gate.
///
/// Gate ③ (session identity) applies to **every** kind. The screen-confirmation means (`canConfirmScreen`) applies to `.typing` only — looking once at the start of an attempt lets the marker, the body and the CR keep going out when the permission is revoked during the pane proof or a wait afterwards (which is what happened).
///
/// The window between the check and the send (a `ps` + `stty` round trip ≈ 9ms) cannot be removed on this path — if the session changes inside it, one byte enters the new session. But the CR passes the same gate, so **nothing is executed**, and the fragment left in the input box is erased by that session's user.
private func send(_ keys: String, io: ClaudeSessionIO, kind: SendKind = .typing) -> Bool {
    if kind == .typing, !io.canConfirmScreen() { return false }
    guard io.sessionIsUnchanged() else { return false }
    return io.sendKeys(keys)
}

/// Erases the fragment of ours that may be left in the input box when delivery ended midway. It goes through the same door, so nothing goes out once the session has changed.
///
/// With `weSentSomething` false it does nothing — if we never managed to send a single byte, what is in the input box is **the draft the user was typing**, and erasing that with Ctrl+U would be us causing the very damage we set out to prevent.
///
/// One failure is not a reason to give up — terminal CLI calls really do fail every so often (the same measurement is what justifies the retype retries), and residue is left silently when they do. Sending Ctrl+U several times gives the same result.
@discardableResult
func clearAbandonedInput(io: ClaudeSessionIO, weSentSomething: Bool, attempts: Int = 3) -> Bool {
    guard weSentSomething else { return false }
    for _ in 0..<attempts where send(claudeClearInputKey, io: io, kind: .cleanup) { return true }
    return false
}

/// **Might a fragment of ours be in claude's input box right now** — the state that decides whether a cleanup (Ctrl+U) is sent.
///
/// The two questions are **never mixed** (round 7):
///  - **(i) did claude receive the message** — not proven. It cannot be established from outside the TUI, and it is not a safety property either. That is why the log says "sent" rather than "delivered".
///  - **(ii) is the input box empty** — **this is a safety property.** Where the next bytes land, and whether a cleanup is sent, both depend on it. When it is unknown, "empty" is not assumed.
///
/// This type deals only with (ii):
///  - Bytes may already be in even when a send comes back as a failure (the helper can inject part of a write and then error). So it is raised by the **attempt**, not the result — otherwise the remaining fragment cannot be erased.
///  - **A CR does not lower it.** Writing a CR to the tty and the TUI processing it as a submission are different things, and if it was not processed the body is still sitting in the box. Lowering it here is how residue got appended to the next input and submitted as one line (reviewer reproduction: `"/review!git status"`).
///  - Only **evidence** lowers it: the screen showed our marker disappear after a clear (Ctrl+U), or the screen showed that ours is not there. Writing the Ctrl+U is not itself evidence — see `recordSendAttempt`.
struct InputBoxOwnership {
    private(set) var mayHoldOurs = false

    /// We **attempted** to put bytes out. Neither the result nor the kind is looked at: the bytes of a send that returned failure may already be in (the helper can inject part of a write and then error), and a CR or Ctrl+U having been written does not mean the TUI processed it. Only an observation lowers it (`recordInputBoxIsFreeOfOurs`).
    mutating func recordSendAttempt() {
        mayHoldOurs = true
    }

    /// The screen showed that **our input is nowhere** — so the input box is not holding it.
    mutating func recordInputBoxIsFreeOfOurs() { mayHoldOurs = false }
}

/// Sends the inputs to a prepared claude session in order and returns **how many got as far as a CR** — it does not count whether claude turned them into messages (that cannot be confirmed from outside, and round 6 removed it from the requirements). That is why the log says "sent" rather than "delivered".
/// Every input goes out as [type without a newline → confirm the screen reflects it → submit with CR]: LF (\n) is not recognised as a submission, and even past the gates there are moments when the TUI has not drawn the input yet (both measured on WezTerm). While the first input is being processed, the rest queue up in claude's input box.
/// Session identity is confirmed before every input — if the original session died in the meantime and a new claude came up on the same tty, the remaining inputs belong to an unrelated session, and a `!…` input would even run a shell command.
///
/// A session that gets typed input never also carries an argv opening message
/// (`prepareRequest` merges all inputs or none), so there is no startup submission racing us for
/// the input box. That invariant is what lets this function trust "the CR went out" — with both
/// routes in one session it did **not**: the argv submission clears the box and a wiped input was
/// recorded as delivered. What remains of that lesson is `inputBoxAfterSubmit`.
@discardableResult
public func submitClaudeInputs(
    _ inputs: [String], io: ClaudeSessionIO,
    betweenInputTimeout: TimeInterval = 15, retryConfirmTimeout: TimeInterval = 2,
    timeline: DeliveryTimeline? = nil
) -> Int {
    // Counting the bytes that go out is how "might a fragment of ours be in the input box" is tracked.
    // The tracking lives inside this function because **there are several failure exits** (a failed session check between inputs, exhausted retries). With the cleanup outside, only one of them would reach it
    var ownership = InputBoxOwnership()
    var tracked = io
    tracked.sendKeys = { keys in
        let sent = io.sendKeys(keys)
        ownership.recordSendAttempt()
        return sent
    }

    var sent = 0
    delivery: for (index, input) in inputs.enumerated() {
        // The fixed 0.4s wait between inputs was removed — the next input's marker experiment **observes** "what state is the input box in right now", which is both faster and stronger than sleeping and then assuming. If the marker has not appeared yet, that experiment waits until its own deadline
        guard tracked.confirmSession(betweenInputTimeout) else {
            checkoutLog("the claude session originally prepared is not in a state to accept input, so \(inputs.count - index) remaining input(s) were not sent")
            break
        }
        let outcome = typeAndSubmit(
            input, io: tracked, retryConfirmTimeout: retryConfirmTimeout,
            // Lowered by observation only — a successful write is not evidence
            boxObservedEmpty: { ownership.recordInputBoxIsFreeOfOurs() },
            timeline: timeline, label: "input \(index + 1)/\(inputs.count)"
        )
        switch outcome {
        case .sentAndBoxIsFreeOfOurs:
            sent += 1
            ownership.recordInputBoxIsFreeOfOurs()
        case .sentButBoxUnknown:
            sent += 1
        case .leftInTheInputBox:
            // Typing the next input now would append the two into one submitted line — that is the real damage of carrying on. The residue is erased by the cleanup below (ownership is not lowered by a CR)
            checkoutLog("the CR went out but the input is still sitting in the input box — \(inputs.count - index - 1) remaining input(s) were not sent")
            break delivery
        case .gaveUp:
            checkoutLog("failed to send claude input — stopping with \(inputs.count - index) remaining")
            break delivery
        }
    }
    // **The other half of the rule**: after the last input there is no "clear before the next input", so it is cleared here. The bytes are already in our tty even though we could not confirm it on screen (injection is independent of focus), and leaving them means an Enter the user presses later submits them (with `!…`, it even runs a shell command). It goes out on a delivery that ended normally too, because (i) and (ii) are never mixed — a CR having been written is not evidence that the input box is empty.
    // **The price** (accepted, issue #16): a draft the user started typing during or just after delivery may be erased. The loss on the other side is our `!` line staying in the box and being **executed** by the user's Enter, so the two are not symmetric. Leaving it in place would require proving "the input box is empty", which is (ii), and our signals cannot establish it
    if clearAbandonedInput(io: tracked, weSentSomething: ownership.mayHoldOurs) {
        checkoutLog("erased the fragment of ours that may have been left in claude's input box")
    } else if ownership.mayHoldOurs {
        checkoutLog("failed to clean up claude's input box — a fragment of our input may remain (pressing Enter submits it as is)")
    }
    return sent
}

/// Type → confirm the screen reflects it → submit. Even past the gates there are moments when the claude TUI has not drawn the input yet, so when no reflection is visible the input box is cleared and the text retyped. Submitting without that confirmation can submit an empty line or truncated text, so no CR goes out before it.
/// This is after the raw-mode gate, so the kernel echo is off and the text on screen was drawn by claude.
///
/// A failed terminal CLI call is treated as the same retry as an unreflected screen. That call really does fail every so often — in an incident where only #1 of 3 inputs was delivered, the app log held a single line 7 seconds after #1 was submitted, and the only path that ends leaving one line is this call failing (a session gate that did not pass logs after waiting 15 seconds). Which call failed was never narrowed down.
/// Session identity is re-confirmed before retyping though — the failure may have been "the session died", and retyping without checking would pour the input into a claude newly started on that tty.
///
/// **Retries exist only up to the CR.** Once a CR has gone out even once, that input is never typed again — the send call may have reported failure while the bytes went in, and retyping then submits the same message twice (with a `!` input, the user's command runs twice). Every failure past this boundary ends as "stop delivery and report", and whatever fragment is left in the input box is erased by the caller's cleanup.
private func typeAndSubmit(
    _ text: String, io: ClaudeSessionIO, retryConfirmTimeout: TimeInterval,
    boxObservedEmpty: () -> Void = {},
    timeline: DeliveryTimeline? = nil, label: String = ""
) -> SubmitOutcome {
    // Attempts, not the deadline, are what wait out "the user has not looked at the tab yet":
    // 12 × the ~2s appearance window is ~25s of patience for a slow watcher, while a marker
    // claude swallowed at startup is abandoned after ~2s instead of blocking the whole budget
    // (see the appearance deadline in `proveOurPaneAndEmptyBox`)
    let maxAttempts = 12
    for attempt in 1...maxAttempts {
        guard io.canConfirmScreen() else {
            checkoutLog("the means of confirming the screen is gone, so nothing more is typed — the remaining fragment gets cleaned up")
            return .gaveUp
        }
        if attempt > 1 {
            guard io.confirmSession(retryConfirmTimeout) else { return .gaveUp }
        }
        // **One marker buys three things** (see `proveOurPaneAndEmptyBox`): ① proof that the screen being read is our pane ② attribution that the place our typing appears is the **input box** ③ confirmation that the TUI actually **processed** that Ctrl+U
        guard proveOurPaneAndEmptyBox(io: io, attempt: attempt, of: maxAttempts) else { continue }
        // The gap on this line is the one the app does not control: on Warp the proof only passes
        // while the user is looking at that tab, so a large number here is the answer "you were
        // on another tab", not a bug to fix
        timeline?.step("\(label) pane proof passed (attempt \(attempt)/\(maxAttempts))")
        // At this point the input box has been **observed** empty — an observation, not a successful write
        boxObservedEmpty()
        guard let baseline = io.screenText().map({ probeCount(of: text, in: $0) }) else {
            checkoutLog("screen read failed — retrying (\(attempt)/\(maxAttempts))")
            continue
        }
        // The body is typed **exactly once**. While the experiment used the body, the moment that trial typing appeared on screen the user could press Enter, the command would run, and — not knowing that — we would retype and send a CR, so **the `!` command ran twice** (reviewer reproduction). With the marker taking the hit instead, what gets submitted is one inert line, and the fact that the user's Enter is not counted stays true without doing any damage
        guard send(text, io: io) else {
            checkoutLog("failed to send the typing — retrying (\(attempt)/\(maxAttempts))")
            continue
        }
        var reflected: String?
        var failure = "the input is not reflected on screen"
        // Same read-cost compensation as `poll` — a 137ms Warp read on top of a full interval
        // sleep stretched this "2 second" window to ~3.8s of wall clock. The wait comes before
        // the read here, so it is the **previous** iteration's read that gets subtracted
        var lastReadCost: TimeInterval = 0
        for attempt in 0..<13 { // 0.15s × 13 ≈ 2s, the same deadline as before
            if attempt > 0 { io.wait(max(0, screenPollInterval - lastReadCost)) }
            let readStarted = Date()
            guard let screen = io.screenText() else {
                failure = "screen read failed"
                break
            }
            lastReadCost = Date().timeIntervalSince(readStarted)
            // **At least** one more, not exactly one more: claude may draw our line a second time
            // (the hint-line behaviour the attribution experiment exists for), and demanding an
            // exact count made the button do nothing at all — five typings, no CR, no message
            // (reviewer reproduction). Only the *disappearance* check needs an exact count, where
            // "some of it is still there" has to fail
            if probeCount(of: text, in: screen) >= baseline + 1 {
                reflected = screen
                break
            }
        }
        if let reflected {
            timeline?.step("\(label) body reflection confirmed")
            guard submitConfirmedInput(io: io, retryConfirmTimeout: retryConfirmTimeout) else {
                // **A CR that went out may have landed even when the call reports failure** — the
                // helper can inject part of a write and then error. So this input is never typed
                // again: retyping is the only move that can submit the same message twice, and
                // with a `!` input that runs the user's command twice. Resending the CR is fine
                // (a CR into an empty box does nothing, measured) and `submitConfirmedInput`
                // already did that; once those are exhausted, delivery stops here
                checkoutLog("failed to send the submission (CR) — an input whose CR already went out is never retyped, so delivery stops")
                return .gaveUp
            }
            // The "total" printed on this line for the first input is the number the user actually feels — from the button click to the first submission
            timeline?.step("\(label) submission (CR) sent")
            switch inputBoxAfterSubmit(io: io, whenTyped: reflected, text: text) {
            case .stillHoldsOurInput:
                timeline?.step("\(label) post-check: the input is still in the input box")
                return .leftInTheInputBox
            case .ourInputIsGone:
                timeline?.step("\(label) post-check: nothing of ours in the input box")
                // The box is not holding ours. Whether claude took the message or the transcript
                // merely scrolled it out of view is question (i), which we do not ask
                return .sentAndBoxIsFreeOfOurs
            case .unknown:
                timeline?.step("\(label) post-check: the input box state is unknown")
                return .sentButBoxUnknown
            }
        }
        checkoutLog("\(failure) — retrying (\(attempt)/\(maxAttempts))")
    }
    return .gaveUp
}

/// The result of handling one input. The axis the cases split on is **(ii) is the input box empty**, not (i) did claude receive it — the latter is never checked.
private enum SubmitOutcome {
    /// The CR was written and the screen showed **our input is nowhere** — nothing of ours is in the input box
    case sentAndBoxIsFreeOfOurs
    /// The CR was written but the input box's state could not be seen (unreadable, not our pane, uninterpretable).
    /// The clear before the next input and the final cleanup cover this state
    case sentButBoxUnknown
    /// The screen showed "our text is still in the input box" — the residue is certain
    case leftInTheInputBox
    /// The CR never went out
    case gaveUp
}

/// What the screen says about the **input box** right after the CR.
///
/// **This is not a submission check, on purpose (round 6).** Nothing outside the TUI can prove a
/// message exists — two rounds of trying produced a check that was wrong in both directions, and
/// the property was never a safety property anyway. What this feature has to guarantee is that our
/// bytes do not leak into another session (the three gates and the pane proof), that nothing is
/// submitted twice (a CR-ed input is never retyped) and that we leave no residue behind. Only the
/// last one needs the screen, and it needs one operational answer: **may the next input be typed?**
/// If our text is still in the box, typing the next one appends to it and both go in as a single
/// mangled line — that is the whole damage carrying on can do.
///
/// The region compared is **from our input to the end of the screen**, i.e. everything the box can
/// occupy. A change above it — a spinner, streaming output, a clock — says nothing about the box,
/// and treating it as if it did is what made a whole-screen comparison report a stuck input as
/// submitted (reviewer reproduction). Three samples, because the TUI may not have redrawn yet
/// right after the CR, and the answer is taken from the last readable one.
enum InputBoxAfterSubmit: Equatable {
    /// Our input is still exactly where we typed it. The one state that changes what we do:
    /// delivery stops and the residue is handed to the single cleanup point
    case stillHoldsOurInput
    /// Our input is nowhere on screen, so the box is not holding it. Submitted, or scrolled out of
    /// view — indistinguishable, and nothing downstream depends on the difference
    case ourInputIsGone
    /// Unreadable, not our pane (Warp reads whichever pane has focus), or a change we cannot
    /// interpret. Carry on: not knowing is not a failure
    case unknown
}

/// How long the box may look frozen before we believe it. **Not measured for a CR redraw** — the
/// only adjacent measurement in this repository is claude's first-message render, 2.06∼3.41s
/// (`docs/new-terminal-checklist.md`), so anything shorter is a guess. Being generous is the safe
/// direction here: the safety of the next input rests on the clear we send **before typing**, not
/// on this look, so a slow answer costs nothing, while a hasty "it is stuck" drops the inputs that
/// were still to come (reviewer reproduction R3).
private let inputBoxLookDeadline: TimeInterval = 3.6

func inputBoxAfterSubmit(
    io: ClaudeSessionIO, whenTyped: String, text: String
) -> InputBoxAfterSubmit {
    // Warp's screen is whichever pane has focus, so "unchanged" there is not about our box. The
    // pane proof is only valid up to the moment the body is typed, and re-proving here would mean
    // typing bytes into a box a submission may have just emptied
    guard !io.screenNeedsPaneProof else { return .unknown }
    let probe = claudeInputProbe(text).filter { !$0.isWhitespace }
    guard !probe.isEmpty else { return .unknown }
    // **The probe has to identify our copy, and only ours.** claude draws hint lines, a permission
    // indicator and a context meter *below* the box, and `screenTail` takes the last occurrence —
    // so a probe that also appears down there pins the tail forever and a submission that went
    // through reads as "still in the box" (reproduced: input `y` against "bypass permissions on",
    // and `/review` against a "try /review" hint; both dropped every later input). When the probe
    // is not unique we cannot tell the copies apart, so we do not judge
    guard probeOccurrences(of: probe, in: whenTyped) == 1,
          let typedTail = screenTail(from: probe, in: whenTyped) else { return .unknown }
    var last = InputBoxAfterSubmit.unknown
    _ = poll(io: io, within: inputBoxLookDeadline) {
        // A read we could not make says nothing. It used to end the look, which threw away what
        // the earlier reads had already established (reviewer reproduction R5)
        guard let screen = io.screenText() else { return false }
        guard let tail = screenTail(from: probe, in: screen) else {
            last = .ourInputIsGone
            return false
        }
        if tail != typedTail {
            last = .unknown
            return true // it moved — there is nothing more to look at
        }
        last = .stillHoldsOurInput
        return false
    }
    return last
}

/// Types a throwaway marker, waits for it to appear, **clears the box and waits for it to go
/// away**. One experiment, three answers, and the canonical version of what used to be two
/// half-overlapping mechanisms (the Warp pane proof and round 8's body experiment):
///
///  1. **The screen is our pane.** A random marker can only reach the tty we injected it into, so
///     seeing it appear rules out reading someone else's pane — the Warp requirement, now applied
///     everywhere because the other two answers need it anyway.
///  2. **What appears is in the input box.** Seeing our text on screen does not say where it is;
///     claude draws the same string in hint lines below the box. Text that **disappears when the
///     box is cleared** was in the box — the only attribution obtainable from outside.
///  3. **The TUI processed our Ctrl+U.** AppleScript and the wezterm CLI report that the terminal
///     accepted the write, never that claude acted on it; the disappearance is the only evidence.
///
/// **Why a marker and not the body** (round 9, the regression this replaces): the experiment types
/// something and leaves it on screen for a moment. If the user presses Enter right then — on Warp
/// they are watching that tab by design — *they* submit whatever is in the box. With the body in
/// there, a `!` line runs, and the app, which can only count the CRs it sent itself, clears and
/// retypes and submits: the user's command runs **twice**. With a marker, that stray Enter submits
/// one inert line and the body is still typed exactly once.
///
/// The marker is alphanumeric for the same reason `paneProofToken` always was: `/`, `!` and `@`
/// mean something to the input box.
private func proveOurPaneAndEmptyBox(io: ClaudeSessionIO, attempt: Int, of maxAttempts: Int) -> Bool {
    guard let before = io.screenText() else {
        checkoutLog("screen read failed — retrying (\(attempt)/\(maxAttempts))")
        return false
    }
    let marker = paneProofToken()
    guard send(marker, io: io) else {
        checkoutLog("failed to send the marker — retrying (\(attempt)/\(maxAttempts))")
        return false
    }
    // The deadline is generous because most failures are "the user is looking at another tab for a moment", a state that resolves by waiting (measured on Warp). In exchange it **reads first** — already drawn means an immediate pass
    // 2s, not longer: both field timelines show the same shape — a marker typed right after raw
    // mode gets swallowed by claude's initialisation and will NEVER appear, so every extra second
    // here is spent waiting on a dead marker (5s cost the first message ~4s in both runs). The
    // patience for "the user is not looking at the tab yet" lives in the attempt count, not in
    // this deadline — a fresh marker every ~2s answers faster in both cases
    let appeared = poll(io: io, within: 2.0) {
        guard let after = io.screenText() else { return false }
        return screenReflectsNewInput(before: before, after: after, input: marker)
    }
    guard appeared else {
        checkoutLog("the screen being read is not our pane — retrying (\(attempt)/\(maxAttempts))")
        return false
    }
    guard send(claudeClearInputKey, io: io) else {
        checkoutLog("failed to clear the input box — retrying (\(attempt)/\(maxAttempts))")
        return false
    }
    let baseline = probeCount(of: marker, in: before)
    guard waitUntilProbeCount(baseline, of: marker, io: io) else {
        // The marker did not disappear — either what we saw was not the input box, or the TUI did not process the Ctrl+U. Both mean the same thing: do not send a CR
        checkoutLog("could not confirm the marker being erased from the input box — retrying (\(attempt)/\(maxAttempts))")
        return false
    }
    return true
}

/// How long to leave between two screen reads while waiting for something.
///
/// Bounded below by what one read costs — spend less and the polling is mostly reader startup.
/// Measured on this machine, 20 calls each: **osascript 59ms** (iTerm2's screen read), **wezterm
/// cli 14ms**, **ps+stty 9ms** (the session gate). Warp's Accessibility read could not be measured
/// without launching Warp, so it is assumed no cheaper than osascript. 0.15s keeps every known
/// reader under half the interval.
let screenPollInterval: TimeInterval = 0.15

/// Waits for `ready`, **reading before it sleeps**.
///
/// The old shape slept a fixed interval before every read, so a screen that was already drawn
/// still cost the full interval — and there are four such waits per input (marker appears, marker
/// gone, body reflected, post-CR look), which was 1.7s of pure sleeping on the happy path.
/// Deadlines are unchanged or longer; only the sampling moved. Nothing was dropped from what gets
/// checked: the same reads, the same conditions, just asked sooner.
private func poll(io: ClaudeSessionIO, within deadline: TimeInterval, _ ready: () -> Bool) -> Bool {
    // Counted rather than clock-driven so the fake, whose `wait` is a no-op, still terminates.
    // The sleep is **shortened by what the read itself cost**. Reads are not free — a Warp
    // Accessibility read measures 134∼143ms in the field, close to the interval itself — and
    // sleeping the full interval on top of that made every deadline here take nearly twice its
    // stated wall clock, because the attempt count assumes an iteration costs one interval.
    // With the compensation it does, whichever terminal is reading
    let attempts = max(1, Int((deadline / screenPollInterval).rounded()))
    for attempt in 0..<attempts {
        let readStarted = Date()
        if ready() { return true }
        if attempt < attempts - 1 {
            io.wait(max(0, screenPollInterval - Date().timeIntervalSince(readStarted)))
        }
    }
    return false
}

private func waitUntilProbeCount(
    _ wanted: Int, of text: String, io: ClaudeSessionIO, within deadline: TimeInterval = 2.0
) -> Bool {
    poll(io: io, within: deadline) {
        guard let screen = io.screenText() else { return false }
        return probeCount(of: text, in: screen) == wanted
    }
}

/// How many times the input's probe appears on the screen, whitespace removed on both sides —
/// the TUI reflows and pads what it draws (`screenReflectsNewInput` normalises the same way).
func probeCount(of input: String, in screen: String) -> Int {
    probeCount(claudeInputProbe(input).filter { !$0.isWhitespace }, in: screen)
}

private func probeOccurrences(of probe: String, in screen: String) -> Int {
    probeCount(probe, in: screen)
}

/// The screen from the **last** occurrence of the probe to the end, whitespace removed. The last
/// occurrence is the input box's copy — the transcript is above it — and whitespace is dropped for
/// the same reason `screenReflectsNewInput` drops it: the TUI reflows and pads what it draws.
private func screenTail(from probe: String, in screen: String) -> String? {
    let squeezed = screen.filter { !$0.isWhitespace }
    guard let found = squeezed.range(of: probe, options: .backwards) else { return nil }
    return String(squeezed[found.lowerBound...])
}

/// Submits an input already confirmed on screen, with a CR. When the send fails it resends the CR rather than retyping — a reported failure may in fact have gone through, and retyping then submits the same input twice. A CR into an empty input box does nothing (measured), so resending after it has already been submitted is harmless.
/// Session identity is confirmed every time, **including before the first CR**. Even immediately after confirming the screen reflection, if the original claude ended in the meantime and the shell on that tty — or a newly started claude — receives that CR, it submits and runs whatever the user was typing. There was a time when "we just confirmed the reflection, so it is safe" was assumed, but there is a polling-interval-sized gap between the screen check and the CR as well — the cost is one `ps` + `stty` round trip.
private func submitConfirmedInput(io: ClaudeSessionIO, retryConfirmTimeout: TimeInterval) -> Bool {
    for attempt in 1...3 {
        if attempt > 1 { io.wait(0.4) }
        guard io.confirmSession(retryConfirmTimeout) else { return false }
        if send(claudeSubmitKey, io: io) { return true }
    }
    return false
}

/// Waits until the claude in the spawned session can accept input, then delivers the inputs.
/// The wait condition is [foreground process = claude] + [the tty is in raw mode] — going by the process alone passes through the canonical window right after the shell's exec and loses the first input (see `acceptingClaudePID`).
/// The PID of the claude originally prepared is pinned, so later inputs can only go to that same session.
/// If claude is not ready within the timeout, nothing is sent and it gives up (logging only).
/// The startup wait (2 minutes by default) and the per-input retries are all blocking, so the whole thing can take minutes — it has to be called on a background queue rather than the request-handling one.
public func deliverClaudeInputs(
    _ inputs: [String], to handle: TerminalSessionHandle,
    pollInterval: TimeInterval = 1.0, timeout: TimeInterval = 120,
    betweenInputTimeout: TimeInterval = 15,
    timeline: DeliveryTimeline? = nil
) {
    guard !inputs.isEmpty else { return }
    // The Warp helper must not become a process left drifting in the pane — it is terminated on whichever path this ends
    defer {
        if case .warp(let socket) = handle { _ = warpHelperRequest(.bye, socket: socket) }
    }

    let ttyPath: String?
    switch handle {
    case .iterm(_, let tty):
        ttyPath = tty
    case .wezterm(let paneID, let cliPath, let socketPath):
        ttyPath = wezTermQueryTTY(cliPath: cliPath, socketPath: socketPath, paneID: paneID)
    case .warp(let socket):
        // Without reading the screen there is no way to confirm claude received the input, and a CR sent without that confirmation submits an empty line while input claude discarded is recorded as "delivered" (measured).
        // So on Warp the Accessibility permission is a **hard requirement** for buttons that schedule claude input — it has nothing to do with running the command itself, and the log records that difference
        guard accessibilityIsTrusted() else {
            checkoutLog(
                "without the Accessibility permission, \(inputs.count) claude input(s) are not delivered on Warp"
                    + " (the command still runs in the new tab) — grant it in the app settings window"
            )
            return
        }
        ttyPath = warpHelperTTY(socket: socket)
        // Waiting for the helper can stretch to 20 seconds — the "+" on this line is how much of that was actually spent
        timeline?.step(ttyPath == nil ? "failed waiting for the Warp injection helper" : "Warp injection helper ready")
    case .none:
        checkoutLog("cannot deliver claude input — no session handle")
        return
    }
    guard let ttyPath, ttyPath.hasPrefix("/dev/") else {
        checkoutLog("cannot deliver claude input — the session tty is unknown")
        return
    }
    let ttyName = String(ttyPath.dropFirst("/dev/".count))

    guard let claudePID = waitUntilClaudeAcceptsInput(
        ttyName: ttyName, ttyPath: ttyPath, pollInterval: pollInterval, timeout: timeout
    ) else {
        timeline?.step("timed out waiting for claude to start")
        checkoutLog("claude did not reach a state to accept input within \(Int(timeout))s, so \(inputs.count) input(s) were not sent")
        return
    }
    // The "+" on this line is the time taken by cd + the shell rc + claude booting — up to the foreground process becoming claude and the tty switching to raw mode. It is a stretch the app cannot shorten, so a large number here has its cause outside
    timeline?.step("claude ready (pid \(claudePID))")

    let io = ClaudeSessionIO(
        sendKeys: { keys in sendKeys(keys, to: handle, expectedPID: claudePID) },
        screenText: { screenText(of: handle) },
        confirmSession: { limit in
            waitUntilClaudeAcceptsInput(
                ttyName: ttyName, ttyPath: ttyPath,
                pollInterval: pollInterval, timeout: limit, expecting: claudePID
            ) != nil
        },
        // The check immediately before sending does not wait — it measures once and only asks whether it is still that claude
        sessionIsUnchanged: {
            probeAcceptingClaudePID(ttyName: ttyName, ttyPath: ttyPath) == claudePID
        },
        // A revoked permission makes screen confirmation impossible — nothing new is typed then, only the cleanup
        canConfirmScreen: { handle.screenNeedsPaneProof ? accessibilityIsTrusted() : true },
        // True for Warp alone — what Accessibility reads is "the focused pane", with no guarantee it is ours
        screenNeedsPaneProof: handle.screenNeedsPaneProof
    )
    let sent = submitClaudeInputs(
        inputs, io: io, betweenInputTimeout: betweenInputTimeout, timeline: timeline
    )
    timeline?.step("delivery finished — sent \(sent) of \(inputs.count) input(s)")
    checkoutLog("claude(pid \(claudePID)): sent \(sent) of \(inputs.count) input(s) (receipt is not confirmed)")
    // Cleaning up whatever fragment is left in the input box is done by `submitClaudeInputs` at the single failure-exit point — the cleanup condition is "we did not finish", not the permission. Only the diagnosis is left here: the most common reason delivery stalls on Warp is a revoked permission, and without the log saying what to grant the user cannot know. This wording can name the permission only because Warp is currently the one terminal where `canConfirmScreen` can go false (`screenNeedsPaneProof`) — if a terminal joins whose means of confirmation is not a permission, the wording has to split with it
    if sent < inputs.count, !io.canConfirmScreen() {
        checkoutLog("the means of confirming the screen disappeared mid-delivery — grant the Accessibility permission in the app settings window")
    }
}

private func probeAcceptingClaudePID(ttyName: String, ttyPath: String) -> Int? {
    guard let ps = try? runProcess(
        "/bin/ps", ["-t", ttyName, "-o", "pid=,stat=,comm="], timeout: 5
    ) else {
        return nil
    }
    // A failed stty is passed on as empty output and treated as "cannot tell" (carrying on with the ps gate alone)
    let stty = (try? runProcess("/bin/stty", ["-f", ttyPath, "-a"], timeout: 5))
        .flatMap { $0.status == 0 ? $0.stdout : nil } ?? ""
    return acceptingClaudePID(psOutput: ps.stdout, sttyOutput: stty)
}

/// Waits until claude can accept input and returns its PID. nil on timeout.
/// With `expecting` given, only that PID is accepted — the point being to keep the remaining inputs from pouring into a claude that came up on the same tty after the original session died. Once a new session has taken the place, the condition is never satisfied, so it waits out the timeout and ends as nil (sending nothing).
/// How long the fast phase of the startup poll lasts, and how often it looks.
///
/// claude reaches raw mode 0.1∼0.19s after the shell execs it (measured), so a 1s tick threw away
/// most of a second before the first input every single time. One probe is `ps` + `stty` ≈ 9ms
/// (measured, 20 calls each), so 0.15s is ~6% duty — cheap enough to keep up for the first ten
/// seconds, which covers a normal start with room to spare. After that the tab is either slow
/// (a big repository, a first-run trust prompt) or never coming, and the old 1s tick is right.
private let claudeStartupFastPhase: TimeInterval = 10
private let claudeStartupFastInterval: TimeInterval = 0.15

private func waitUntilClaudeAcceptsInput(
    ttyName: String, ttyPath: String, pollInterval: TimeInterval, timeout: TimeInterval,
    expecting: Int? = nil
) -> Int? {
    let started = Date()
    let deadline = started.addingTimeInterval(timeout)
    while true {
        if let pid = probeAcceptingClaudePID(ttyName: ttyName, ttyPath: ttyPath),
           expecting == nil || pid == expecting {
            return pid
        }
        if Date() >= deadline { return nil }
        let fast = Date().timeIntervalSince(started) < claudeStartupFastPhase
        Thread.sleep(forTimeInterval: fast ? min(claudeStartupFastInterval, pollInterval) : pollInterval)
    }
}

private func wezTermQueryTTY(cliPath: String, socketPath: String?, paneID: String) -> String? {
    let env = wezTermEnvironment(socketPath: socketPath)
    guard let result = try? runProcess(cliPath, ["cli", "list", "--format", "json"], env: env, timeout: 5),
          result.status == 0 else { return nil }
    return wezTermTTYName(listJSON: Data(result.stdout.utf8), paneID: paneID)
}

/// Sends keystrokes as they are, without appending a newline (`claudeSubmitKey` and `claudeClearInputKey` included).
private func sendKeys(_ text: String, to handle: TerminalSessionHandle, expectedPID: Int) -> Bool {
    switch handle {
    case .iterm(let sessionID, _):
        // Control characters cannot go into an AppleScript string literal, so these branch to dedicated scripts
        let script: String
        switch text {
        case claudeSubmitKey:
            script = iTermWriteToSessionScript(sessionID: sessionID, text: "", submit: true)
        case claudeClearInputKey: script = iTermClearInputScript(sessionID: sessionID)
        default: script = iTermWriteToSessionScript(sessionID: sessionID, text: text, submit: false)
        }
        guard let result = try? runProcess("/usr/bin/osascript", ["-e", script], timeout: 10),
              result.status == 0 else { return false }
        if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "gone" {
            checkoutLog("the iTerm session closed — claude input delivery stops")
            return false
        }
        return true
    case .wezterm(let paneID, let cliPath, let socketPath):
        let result = try? runProcess(
            cliPath, ["cli", "send-text", "--pane-id", paneID, "--no-paste"],
            input: text, env: wezTermEnvironment(socketPath: socketPath), timeout: 5
        )
        return result?.status == 0
    case .warp(let socket):
        // The helper puts bytes straight into our pane's tty input queue (TIOCSTI) — independent of focus, and unable to leak into another pane or another app. That is why synthetic keystrokes are not used.
        // The expected PID rides along so the helper can also check "the process that will read this tty right now" — we can only look before sending, and who reads what was put in the queue is decided only there
        let answer = warpHelperRequest(
            .inject(expectedPID: Int32(expectedPID), bytes: Data(text.utf8)), socket: socket
        )
        guard case .ok? = answer else {
            // The reason matters in the field: the first send after claude reaches raw mode
            // failed once in a measured run and cost that delivery 8 seconds, and without this
            // line the log could not say whether the helper refused (reader-gate mismatch),
            // died, or never answered
            checkoutLog("the Warp helper refused or failed the send — response: \(answer.map(String.init(describing:)) ?? "none")")
            return false
        }
        return true
    case .none:
        return false
    }
}

/// The session's current screen text, used to confirm typing was reflected. nil on a failed read or a vanished session.
private func screenText(of handle: TerminalSessionHandle) -> String? {
    switch handle {
    case .iterm(let sessionID, _):
        guard let result = try? runProcess(
            "/usr/bin/osascript", ["-e", iTermSessionContentsScript(sessionID: sessionID)],
            timeout: 10
        ), result.status == 0 else { return nil }
        let text = result.stdout
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "gone" ? nil : text
    case .wezterm(let paneID, let cliPath, let socketPath):
        guard let result = try? runProcess(
            cliPath, ["cli", "get-text", "--pane-id", paneID],
            env: wezTermEnvironment(socketPath: socketPath), timeout: 5
        ), result.status == 0 else { return nil }
        return result.stdout
    case .warp:
        // What Accessibility reads is "the focused pane in Warp", with no guarantee it is ours.
        // It is nevertheless safe because input does not travel this path (see `warpScreenText`) — reading someone else's pane makes the pane proof and the reflection check fail, which sends us back to a retry, and if it fails for good nothing is submitted
        return warpScreenText()
    case .none:
        return nil
    }
}

/// Waits for the helper to open its socket and report its own tty. It takes time for the pane to open and the shell to run the helper (measured around 0.7s), so this polls. nil if it never comes up — the command is already running, so only the claude input is given up.
private func warpHelperTTY(socket: String, timeout: TimeInterval = 20) -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if case .ok(let tty)? = warpHelperRequest(.tty, socket: socket), tty.hasPrefix("/dev/") {
            return tty
        }
        if Date() >= deadline {
            checkoutLog("the Warp injection helper did not come up within \(Int(timeout))s — giving up on claude input")
            return nil
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
}
