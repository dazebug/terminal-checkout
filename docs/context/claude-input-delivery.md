# Claude input delivery

How a button's scheduled `claude_inputs` — and the one-line note a click can add after them — reach the Claude Code session the button just started. The mechanisms, the measurements behind them, and the invariants live in `CLAUDE.md`; this file holds the forks — what was chosen over what, and why.

## `!` inputs are typed into claude's shell mode, never pre-run and pasted

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #36 (`da37339`); measured in a pty against claude 2.1.238
**Revisit when:** claude gains a documented way to enter shell mode from argv, or the `!` prefix stops meaning shell mode

An input starting with `!` is typed into the running TUI so that claude's own shell mode executes it. For a while the app did the opposite: it ran those lines in the pane's shell ahead of time and handed claude the captured output as its opening message, assembled by a generated script through a temporary context file.

**Reason:** the two are not equivalent, even when the text ends up looking the same. Executing it in the session leaves the command in that session's own history as a command; pasting its output leaves a wall of text whose provenance claude has to infer from a banner convention we invented. The paste route was faster, and it was still rejected: what the feature is for is putting *claude* in front of the command, not putting the command's stdout in front of claude.

**Rejected alternative — carry the `!` line in argv instead of typing it.** This would have kept the speed of the paste route without the paste. Measured, it does not exist: `claude -- '!echo x'` does **not** enter shell mode. The line arrives as an ordinary message and the model then decides to run it through its Bash tool — which can stop at a permission prompt, is a judgement rather than a shell fact, and spends a turn. The official CLI reference documents no flag or prefix for it either.

**Implementation consideration — keeping pre-execution behind a switch.** Written down as a rejected alternative once, and demoted here because it never was one: `git log -S`, the commit body of PR #36 and that PR's comments carry no proposal, no branch, and no reproduction for it (searched round 10). What is true is the reason it was not built — a second delivery path is a second path every later change has to be correct in — and that is a design consideration rather than a road anyone took.

**Consequence, accepted:** every shipped preset that schedules claude input is `!`-only, so all of them are typed. On Warp that makes the Accessibility permission a hard requirement for those four buttons, where the paste route had needed nothing.

## A leading `!` is sent in its own write before a long input

**Type:** decision
**Status:** active
**Evidence:** Claude Code 2.1.287 in cmux 0.64.25 on 2026-10-02: a 424-character merged line doubled its leading `!` in 6 of 8 one-write attempts, while sending `!` first and the rest immediately produced 0 of 8; a 24-character input doubled in 0 of 20 one-write attempts. A live delivery of the issue-list button's inputs to Claude in a 38×20 cmux pane sent all four typed inputs (424, 45, 21 and 105 characters) in 9.4 seconds; the first marker was retried once during startup, the Korean note arrived, `/rename` took effect, and no doubled `!!` or `no such file` error appeared.
**Source:** `typeAndSubmit` in `app/Sources/Core/ClaudeInjector.swift`; `testLeadingBangIsSentSeparatelyFromTheLongInputBody` in `app/Tests/CoreTests/CoreTests.swift`; a live delivery of the issue-list button's inputs to Claude in a 38×20 cmux pane
**Revisit when:** Claude Code changes shell-mode entry or how it handles a long typed chunk

A typed input that starts with `!` sends the prefix in one write and the rest immediately after it in a second. Both writes use the existing session gate, and reflection still checks the complete input.

**Reason:** the measured screen showed the shell-mode prompt and a second, literal `!` at the start of the typed command (`! !/bin/echo …`). The shell received `!/bin/echo …` and failed with `no such file or directory: !/bin/echo`. Treating the long write as a paste is an inference from the measurements, not an isolated cause.

**Rejected alternative — send the whole long input in one write.** This was the measured failure path, with doubled `!` in 6 of 8 attempts.

**Rejected alternative — wait for the shell-mode prompt before sending the rest.** Waiting produced 0 of 8 doubled prefixes, the same result as sending the two writes immediately, and added a screen-read dependency.

**Cost, accepted:** a leading-`!` input takes one additional write; the carrier boundary on iTerm2, WezTerm and Warp has not been measured.

## Consecutive `!` inputs merge into one typed line, joined with `;`

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #36; `claudeTypedInputs` and `claudeBodyJoinsSafely` in `app/Sources/Core/ClaudeInputPlan.swift`
**Revisit when:** the delivery cycle stops being the dominant cost, or claude's shell mode starts sharing state across submissions

What survives of the abandoned optimisation is cycles, not routes. A run of consecutive `!` inputs is typed as a single line, each command behind its own banner, so three inputs cost one type/submit cycle and one model turn instead of three.

**Reason:** each type/submit cycle pays for the marker experiment, the reflection check and the post-CR look; the inputs themselves are cheap by comparison. Merging removes the repeated overhead without changing what runs.

**Rejected alternative — join with `&&`.** Separate `!` submissions never stopped each other when one failed, so `&&` would make the merged line behave differently from the same inputs typed apart. `;` preserves the original behaviour.

**Rejected alternative — merge unconditionally.** Joining is not free, and the gate is what makes the merge honest rather than an assumption. Measured in zsh, bash and dash: an unquoted `#` anywhere comments out every later banner and body and the line still exits 0; a body ending in `&` or `<`/`>`, or a malformed separator sequence like `|||`, is a parse error that kills the whole line; a body that runs `cd` or `export` changes what the commands after it do, because separate submissions share no shell state while a merged line does. Any body that cannot be proven safe to join sends its whole run back to being typed one input at a time — slower, and exactly what the user wrote.

## The gate makes no judgement about where a character sits

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #36; reviewer reproductions, measured in zsh, bash and dash
**Revisit when:** someone proposes teaching the gate to parse the user's shell

`claudeBodyJoinsSafely` is a whitelist walk. An unquoted `#` or `=` folds the run wherever it appears — including where it is provably literal.

**Reason:** the opposite posture was tried twice and lost twice. A rule that tried to prove a given `#` was a literal read `!echo one;# note` as text; merged, that line prints `one`, exits 0, and the next input disappears with no error anywhere. The second attempt at position judgement lost the same way one review round later. Over-folding costs one type/submit cycle; under-folding loses a command silently, and silence is the failure this whole area exists to remove.

**Rejected alternative — parse the shell properly.** Refused twice. A real parser is a large, permanently-maintained surface whose failure mode is the same silent loss, only harder to reason about.

## argv carries the opening message only when every input is plain text

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #36; measured on claude 2.1.238 (32 runs)
**Revisit when:** claude stops clearing the input box when it submits an argv message

A list holding exactly one plain-text input rides in argv, which skips the typing dance entirely. Anything else is typed.

**Reason:** plain text is just a message, so argv is exactly right for it.

**Rejected alternative — argv for the leading plain-text inputs, typing for the rest.** Measured and removed: submitting the argv message clears the input box, and it renders 2.06–3.41s after start while "claude accepts input" is true from 0.1s. Anything typed in that window is wiped (3/3). No gate over that race survived review.

**Rejected alternative — join several plain-text inputs with newlines into one argv message.** The newline is the problem, not the joining: the command reaches the terminal by being typed, and a newline there runs it early. Carrying it would need shell-specific quoting and a fresh way to be wrong about the pane's shell.

## Delivery proves the input box by experiment, not by reading the screen

**Type:** decision
**Type:** workaround
**Status:** active
**Evidence:** confirmed
**Source:** PR #36; two independent reviewers reached the same reproduction
**Revisit when:** a terminal gains a way to read a specific pane's input box directly

Before each input, the app types a throwaway marker, watches it appear, clears the box, and watches it disappear. Only then is the body typed, once, and submitted.

**Reason:** seeing our text on screen does not mean it is in the input box — claude draws the same string in hint lines below the box, so a screen that gains one of those while the typing was dropped is indistinguishable from a render, and the CR that follows submits whatever the box really holds. Text that *disappears when the box is cleared* was in the box: that is the only attribution obtainable from outside the TUI, and the same observation is the only evidence that the TUI processed the clear at all — a terminal reporting that it accepted a write says nothing about what claude did with it.

**Rejected alternative — run the experiment on the body itself.** Shipped briefly and reverted. The trial typing sits on screen for a moment; a user pressing Enter right then submits it, and the app, which can only count the CRs it sent itself, then clears, retypes and submits — running a `!` command twice. A marker makes that stray Enter submit one inert line instead.

**Rejected alternative — trust the write.** Rejected for the clear for the same reason it was rejected for the CR: an accepted write is not a processed keystroke.

## Reflection checks the tail first and accepts the head only at the window's end

**Type:** decision
**Status:** active
**Evidence:** Claude Code 2.1.287 in cmux 0.64.25 on 2026-10-02 showed only the last five composer lines in 38×20 and 76×20 panes: for the 424-character merged line the head fragment stayed at 0→0 while the tail rose 0→2. A 2,000-character paste appeared as `[Pasted text #N]` with the head rising 0→1 and the tail staying at 0→0, though the cause of folding was not isolated. A live delivery of the issue-list button's inputs to Claude in a 38×20 cmux pane sent four typed inputs in 9.4 seconds; the first marker was retried once during startup, the Korean note arrived and `/rename` took effect.
**Source:** `claudeInputProbe`, `screenReflectsNewInput` and `inputBoxAfterSubmit` in `app/Sources/Core/ClaudeInjector.swift`; `testShortPaneTailReflectionSubmitsThe424CharacterMergedInputOnce` and `testCollapsedInputUsesHeadReflectionOnlyAfterTheWindowExpires` in `app/Tests/CoreTests/CoreTests.swift`; a live delivery of the issue-list button's inputs to Claude in a 38×20 cmux pane
**Revisit when:** Claude Code changes its composer scrolling or pasted-text rendering

The reflection check accepts a newly visible increase in the final 24 non-whitespace characters immediately. If that tail never increases but the first 24 characters do, it accepts the head only after the reflection window ends. The fragment that passes is also the one used for the post-submit input-box check; if it is not unique on that screen, the result remains unknown.

**Reason:** in a short pane, the composer shows only the last lines of a long input and scrolls its head off screen, while a long paste can fold into a placeholder that exposes the head but hides the tail. The tail gives an end-of-input signal when visible; waiting through the full window before using the head covers the measured folded form without sending CR early.

**Rejected alternative — parse the composer border or cursor position.** Those are Claude screen details that can change between versions; the measured fragments work without reading that structure.

**Cost, accepted:** a head-only folded input waits for the full reflection window, and the measurement did not identify which length, timing or box state triggers folding.

## The input box is cleared by counted visual lines, then Backspace

**Type:** decision
**Status:** active
**Evidence:** measured in a pty with Claude Code 2.1.238: Ctrl+U cleared text but left the `!` shell-mode prefix, and one Backspace removed it. Measured in cmux 0.64.25 with Claude Code 2.1.287 on 2026-10-02: one Ctrl+U removed one visual line; writes of 64 or 128 Ctrl+U bytes were each dropped whole in two trials, while bursts of at most eight were processed. A live delivery of the issue-list button's inputs to Claude in a 38×20 cmux pane sent 4 of 4 typed inputs in 9.4 seconds.
**Source:** `claudeClearBatches`, `InputBoxOwnership` and `clearAbandonedInput` in `app/Sources/Core/ClaudeInjector.swift`; `testRetryClearsWrappedRemainderBeforeRetypingInputAgain`, `testAbandonedWrappedInputIsFullyClearedAfterRetriesExhausted` and `testRetryClears120KoreanCharactersByCellWidthBeforeSubmittingOnce` in `app/Tests/CoreTests/CoreTests.swift`; `testItem10CmuxClearInputIsTwoSendTextCallsCtrlUThenBackspace` in `app/Tests/CoreTests/CmuxTests.swift`
**Revisit when:** Claude Code changes how Ctrl+U clears wrapped or collapsed input, or a terminal changes how it groups writes

The app estimates how many terminal cells its own writes may occupy since the input box was last observed free, then uses the tty width to choose the Ctrl+U count. It sends the keys in writes of at most eight and sends one Backspace last; cmux sends that Backspace separately.

**Reason:** Ctrl+U removes only the current visual line, leaving earlier wrapped lines; a retry could then append a new body behind an old one and submit both. Ctrl+U alone does not leave Claude's `!` shell mode: the box looks empty while the prefix remains, and the next plain input is run as a shell command (`command not found: …`). One Backspace removes that prefix, and additional Backspace on an empty box does nothing. The order matters: on a box that still holds text, Backspace would only take its last character.

**Rejected alternative — clear until the screen stops changing.** Screen output can continue while the clear is being processed, so no stable point identifies an empty input box. Esc did not clear it.

**Rejected alternative — put every Ctrl+U in one write.** Claude Code 2.1.287 dropped writes of 64 and 128 whole; the small burst size avoids those measured drops.

**Cost, accepted:** a user draft longer than the count of our possible input may remain, the same residual class as issue #16.

**Known limit:** only `!` was measured for the shell-mode prefix. `/` and `#` are also one character and should be covered by the same sequence, but that is inference, not measurement.

## cmux sends Ctrl+U bursts as text and Backspace in a separate call

**Type:** incident
**Type:** decision
**Status:** active
**Evidence:** cmux 0.64.22 and Claude Code 2.1.246: `surface.send_key` did not send Ctrl+U as Claude expected and a combined Ctrl+U plus Backspace write did not preserve their order. Claude Code 2.1.287 in cmux 0.64.25 on 2026-10-02 processed Ctrl+U bursts of eight bytes per `surface.send_text` call.
**Source:** PR #60; `cmuxSendOperations` in `app/Sources/Core/ClaudeInjector.swift`; `testItem10CmuxClearInputIsTwoSendTextCallsCtrlUThenBackspace` in `app/Tests/CoreTests/CmuxTests.swift`
**Revisit when:** cmux changes key encoding or the ordering of bytes and key events sent through `surface.send_text`

cmux exposes `surface.send_key`, and it is unusable under Claude's kitty keyboard protocol. The current clear sends each burst of up to eight Ctrl+U bytes as one `surface.send_text` call, then sends Backspace (`0x7F`) in a separate call; `send_key` remains absent from the app's method list.

**What happened:** on an installed build, claude received the message `tctqr20ckbi!echo tc-r1j-input-ok` — the throwaway marker glued to the body, submitted as one line — while the app's own log recorded a clean success. It only surfaced by reading the transcript.

**Cause, measured:** claude turns on the kitty keyboard protocol (flag 1, `CSI > 1 u`) and modifyOtherKeys 2. `send_key` runs libghostty's key encoder, which under that protocol encodes `ctrl+u` as a CSI-u sequence that claude does not act on — so the marker stayed in the box — while `send_key backspace` still deleted exactly one character. Eleven of the marker's twelve characters remained, and the erase check (below) passed them as gone.

**The earlier measurement did not transfer, and that is the lesson.** An earlier round had confirmed `^U` arriving correctly by running `cat -v` in a raw shell — with the protocol *off*, because nothing had turned it on. A clear key has to be measured inside a running claude TUI, not in the shell next to it; `docs/new-terminal-checklist.md` carries that as an item now.

**Rejected alternative — put Backspace in the Ctrl+U burst.** Measured: `0x15 0x7F` in one `send_text` cleared text but left the shell-mode `!`; cmux converts `0x7F` (and `0x08`, `0x09`) into a key event, and a key event is not guaranteed to stay ordered behind text buffered in the same call. Two consecutive calls are ordered; only that much is established. A burst of up to eight Ctrl+U bytes is handled as one write, and Backspace stays separate.

**Rejected alternative — keep `send_key` because cmux uses it itself.** cmux does drive its own agent input box that way, which reads as authority until you notice the box in question is not running a program that has switched the keyboard protocol.

## "The marker is gone" is checked over every 6-character window, not the whole string

**Type:** decision
**Status:** superseded by the next entry — the question it asks is kept, the window size is not
**Evidence:** confirmed
**Source:** PR #60; the defect above

The erase check counted occurrences of each 6-character window of the 12-character alphanumeric marker and required every one of them back at its pre-typing baseline.

**Reason:** counting the whole 12-character string asks "is the marker intact", and the answer is no as soon as one character is missing — which is exactly the state the incident above produced. A window check asks the question that matters: is any fragment of it still on screen. Six characters was the smallest fragment an alphanumeric marker could be counted by without matching ordinary text.

**Rejected alternative — check the prefix only.** It assumes the remnant is eaten from the end, which is true of Backspace and of nothing else.

**Scope:** this is the marker experiment's disappearance poll. Judging the body after CR is a separate contract with its own tail comparison.

## The marker is three Runic letters, and the erase check counts single characters

**Type:** decision
**Status:** active
**Evidence:** confirmed for claude's input box (Claude Code 2.1.283 in a pty); the terminals' own send and read paths are a `docs/new-terminal-checklist.md` item
**Source:** maintainer request to shorten the marker, and the Codex review that raised dialog key bindings
**Revisit when:** claude's screen starts drawing Runic, or a supported terminal cannot round-trip it

`paneProofToken` draws three letters from U+16A0–U+16EA, and `screenShowsMarkerErased` requires every single character of the marker back at its pre-typing count.

**Reason:** the six-character window existed only because alphanumerics occur everywhere, so a fragment had to be long to mean anything. Nothing claude draws is Runic — its frame, spinner, prompt and hints are box drawing, dingbats, `❯` and ASCII — so one rune left on screen already means "part of our marker is still there", and the marker can be as short as the uniqueness it needs: 75 letters give 421,875 markers, enough that an earlier attempt's marker cannot pass for this one. Measured in claude's input box: `ᚠᛉᛟ` drew as `❯ ᚠᛉᛟ` one cell each, Ctrl+U then Backspace removed all three, and one Backspace alone left `ᚠᛉ`, which the per-character check rejects. Being non-ASCII, the marker also means nothing to the input box (`/`, `!`, `@`) or to a dialog whose keys are digits or `y`/`n` — the old alphabet carried both.

**Rejected alternative — an invisible marker (zero-width characters).** A terminal need not store them in its grid, so the screen read cannot see them, and one left behind would ride invisibly into the user's next message.

**Rejected alternative — Nerd Font or braille characters.** Prompts and statuslines draw private-use icons, and CLI spinners draw braille, so neither is absent from the screen the check reads.

**Accepted cost:** an earlier marker still visible in the baseline that shares a letter with this one and disappears in the same clear makes the check fail once and retry.

## Polling reads first and subtracts what the read cost

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** three timed field runs on Warp; first message 11.6s → 10.5s → 6.8s
**Revisit when:** a terminal's screen read gets much cheaper or much more expensive than ~140ms

Every wait in the delivery loop reads before it sleeps, and the sleep is shortened by what the read itself just cost.

**Reason:** the attempt counts assume one iteration costs one interval. A Warp Accessibility read measures 134–143ms against a 0.15s interval, so sleeping a full interval on top made every deadline take nearly twice its stated wall clock. The first shape also slept before its first read, so a screen that was already drawn still cost a full interval — four times per input.

**Rejected alternative — shorten the deadlines instead.** The deadlines are what wait out "the user has not looked at the tab yet", which on Warp is a design constraint rather than a delay to remove. The waiting moved into the attempt count instead: more attempts, each shorter, so a marker claude's initialisation swallowed is abandoned in ~2s rather than holding the budget for 5.

## An unreadable `stty` used to open gate ②

**Type:** decision
**Status:** superseded
**Evidence:** confirmed
**Source:** PR #3, which introduced both the gate and the fallback; superseded by PR #41
**Revisit when:** never on its own — it is here so the replacement is read as an expiry rather than as a discovery

The commit that added gate ② also added a way past it: when `stty` could not be read, the check was treated as undecidable and delivery continued on the `ps` check alone. The commit body says so twice — "stty를 읽지 못하면 판정 불가로 보고 기존처럼 ps만으로 진행한다", and "iTerm2 경로는 미검증이나, stty 조회 실패 시 ps만으로 폴백하므로 회귀 위험은 없다". A test named `testAcceptsInputFallsBackToForegroundWhenSttyUnavailable` then pinned it, so the fallback was the documented behaviour rather than an oversight.

**It was a regression-safety argument, not a measurement.** At the moment the gate was introduced, the argument was that a new check must not take away delivery that already worked. That is a claim about the change, not about what an unreadable `stty` means — which is what the next entry measures.

## Gate ② stays closed when raw mode cannot be decided

**Type:** decision
**Status:** active
**Evidence:** confirmed for the case measured — one pty, three states, plus three unreadable ttys
**Source:** PR #41; `app/Sources/Core/ClaudeInjector.swift:52` and `:73`
**Revisit when:** a terminal appears where `stty` cannot be read while the tty is genuinely usable

`ttyIsRawMode(...) ?? true` became `== true`: an undecidable raw-mode check no longer opens the gate.

**Reason, measured — and the measurement is small.** One pty on macOS 26.4.1, asked in three states: canonical answered `icanon`, raw answered `-icanon`, and canonical again answered `icanon` (13 lines of output each time). The cases that produced nothing were a tty path with no device, a pty whose ends had both been closed, and a file that is not a terminal, and in every one of those `ps -t` is empty too, so the first gate has already refused. That supports **"every live pty we measured answered", not "a live pty always answers"** — the earlier wording here claimed the second, which is the overclaim class this loop keeps finding in other people's sentences. A previous evidence line also read "13 lines, 650 characters" as *thirteen ptys*; it was the size of one pty's output, and one careful reader has already drawn the wrong number from it. What is left for "could not read `stty`" to mean is "the tty we are about to type into cannot be read", which is precisely the state gate ② exists to stop: without it, the kernel echo in the canonical window right after `exec` gets mistaken for claude rendering the input, and the first input is lost.

**Cost, not hidden.** If `stty` is unreadable for good, polling now runs to its deadline and the log does not say why.

**Rejected alternative — widen it into three states** the way the foreground check was widened. "Not raw" and "could not tell" take the same action here, and nothing today distinguishes them in what it says either, so a third state would be a shape with no consumer.

## The foreground check has three states, and `unknown` is not `different`

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #41; `WarpForeground` in `app/Sources/Core/WarpHelperProtocol.swift:83-91`, its `diagnosis` at `:98`, `app/Sources/WarpHelper/main.swift:110`
**Revisit when:** a caller appears that needs to act differently on `.different` and `.unknown`, rather than only to say something different

A single `Bool` gave "another process group was observed" and "the lookup failed" the same value, and the diagnostic built on it then said something false — `.drainedByOther` names a reader that nothing had identified.

**The safety truth table is unchanged.** `.different` and `.unknown` both refuse, and only `.expected` succeeds. What the split changed is what the code *says*, not what it *does*.

**Rejected alternative — wording discipline**, where every false path is only allowed to claim "could not confirm". That holds exactly as long as the next caller remembers it. A three-state enum makes the compiler ask instead, and the old `Bool` function was deleted rather than left beside it, because leaving it leaves the collapsing path open.

**Closed with it, same class.** `tcgetsid` and `getsid` both return `-1` on failure, so two failures compared equal and read as "still our tty" while holding an fd the helper could not identify. And a watch decision written as `pending <= 0` turned a negative — that is, malformed — queue count into successful delivery; it is `== 0` now, and a malformed count falls through to the fail-closed branches.

## Non-ASCII text changes normalization when it crosses `Process.arguments`

**Type:** constraint
**Status:** superseded — the delivery paths no longer cross this boundary (PR #41, commit `682b6c7`); the platform behaviour it describes is unchanged
**Evidence:** confirmed (measured)
**Source:** PR #41; `ProcessArgumentBoundaryTests` in `app/Tests/CoreTests/CoreTests.swift`
**Revisit when:** a delivery path has to put a value that is not a path into `Process.arguments` or the environment again

Measured by reading codepoints with AppleScript's `id of`: text handed to `osascript -e` arrives **decomposed** (NFD — `4361 4453 4527 4352 4456`), while the same text read from a script file or from stdin arrives **composed** (NFC — `49444 44228`). So a claude message a user wrote in Korean or Japanese reached the iTerm2 path in a different form from the one they typed, and where the input was a `!` one the decomposed bytes reached the shell.

**The first probe was wrong, and that is worth recording.** AppleScript's `count of characters` counts grapheme clusters, so it answered `2` for both forms and measured nothing at all. The generalization drawn from it — that this is a rule about non-ASCII in shell and path strings generally — was too broad as well.

**And the correction was too narrow.** "The WezTerm fallback carries ASCII today" was wrong: a single plain-text input is appended to the command, which then holds the user's sentence, so the fallback carried it on the first click of anyone who had not started WezTerm. `Process.environment` was later measured to decompose exactly like `Process.arguments`, which widened the boundary again. Both corrections came from following the value rather than from re-reading the rule.

**What was done about it is a *decision* and lives in `localization.md`** ("The bytes a user typed are carried, not normalized"): the carriers changed — one stdin door for every AppleScript run, and an ASCII-only argument for the WezTerm fallback — rather than the app normalizing anything.

**Unmeasured.** What iTerm2 itself received. The measurement now reaches one step further than the interpreter's codepoints — those decomposed bytes were confirmed to leave AppleScript *as bytes*, through `do shell script` and through AppleScript's own UTF-8 writer — but the last hop, `write text` putting them on the tty, needs iTerm2 running.

## A click-time note is one more claude input, and only plain text

**Type:** decision
**Status:** active
**Evidence:** confirmed — the scope is a maintainer decision; the premise of the first-character rule is measured; on a live page (the real scripts injected into github.com's main world, `chrome` stubbed, trusted keys) Enter on `!ls` showed the refusal and sent nothing
**Source:** PR #90; `claudeNoteVerdict` in `extension/defaults.js`; `testEveryLeadingScalarTheTrimStripsIsASeparatorOrOther` in `app/Tests/CoreTests/CoreTests.swift`; `tests/claude-note.test.js` (`no first character the app could strip or read as a directive gets through`)
**Revisit when:** the app changes its trim, the order of its render and trim, or what a leading `!`, `/` or `#` means

A ▾ caret beside a button that starts claude opens a one-line box, and what is typed there becomes the last element of that click's `claude_inputs` — no new protocol field, no app change. It is refused unless it is plain text on one line: once ordinary spaces come off its ends it may not start with `!`, `/`, `#` or any character of Unicode categories Z or C, it may hold no line break or control character, and it is at most 4096 UTF-8 bytes, the budget the app gives a merged `!` line. One function, `claudeNoteVerdict`, decides all of it: the content script asks it so the popover can say why, and the worker asks it again because only the worker's answer is authority.

**Reason:** the note is a message, and the app reads a leading `!`, `/` or `#` as a shell command or an input-box directive. Checking the first character is only sound if the app cannot change it afterwards. The app renders, refuses C0, DEL and line breaks, and then trims `.whitespacesAndNewlines` — a trim that strips scalars JavaScript's `trim()` and `\p{Z}` both keep, U+0085 and U+200B among them (measured). Every non-C0 scalar it strips is in category Z or C (measured through the real `resolveRequest`, and pinned by the Swift test above), so refusing Z and C at the front leaves the app classifying the very character checked here.

**Rejected alternative — allow `!`, `/` and `#` notes.** Declined by the maintainer: a note is plain text.

**Rejected alternative — `trim()` or `\p{Z}` for the front.** Both miss U+0085 and U+200B, so a note starting with one of them before `!x` would pass the check and still reach the app's classification as `!x`.

## A click-time note has a slot above the button's stored inputs

**Type:** decision
**Status:** active
**Evidence:** confirmed — the 2026-10-02 report found no caret on an issue-list button with five stored inputs; its saved value is preserved in `tests/fixtures/saved-issue-list-buttons.json` and exercised by `the saved issue-list button with five claude inputs takes a note` (`tests/claude-note.test.js`) and `a note on the saved issue-list button reaches the worker in its own slot` (`tests/worker-note.test.js`). The stored-input cap of 10 is the user's decision.
**Source:** PR #99; `buttonTakesClaudeNote` and `MAX_CLAUDE_INPUTS` in `extension/defaults.js`; the two tests above; `maxLifetime` in `app/Sources/WarpHelper/main.swift`
**Revisit when:** the app begins enforcing a `claude_inputs` count limit, the Warp helper lifetime cap changes, or the storage format can block outdated readers

A button stores up to 10 claude inputs. A click-time note uses a separate slot and follows them, so each session request can carry up to 11 inputs. A button whose command contains the word `claude` gets a ▾ caret regardless of its stored-input count. The content script and worker use the same predicate, `buttonTakesClaudeNote`.

**Reason:** the previous rule counted the note against the button's stored-input cap, so a full button lost its caret. A note belongs to one click and is not saved with the button; it is appended for delivery.

**Rejected alternative — count the note toward the stored-input cap.** That was the previous rule and hides the caret when the button is full.

**Rejected alternative — raise only the combined cap by one.** The note would still share the saved-input budget, moving the same cutoff one input higher.

**Rejected alternative — a count cap in the app too.** The count is a limit of the extension's editor, not a safety boundary: the app's boundary stays the same macOS uid.

**Cost, accepted:** An older extension still has a stored-input cap of five. On another device, or in Chrome before it reloads the updated extension, it skips buttons with six or more saved inputs. If every button under a storage key is skipped, `readStoredButtons` draws the defaults; those can run commands different from the stored ones, with only a console warning, and the options page warns that saving will remove the skipped buttons. Update every device before saving six or more inputs. No version gate is added: the stored version marks the settings generation the user explicitly reviewed and moves only through an explicit review action, so using it as an extension compatibility switch would overload that contract.

## A note carries no variables: any closed brace span is refused

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured through the real `resolveRequest`: a 493-byte note rendered to 8201 bytes, in a batch one item rendered to 4096 bytes and the next to 4097, and `{이거}` was read as a variable name and refused)
**Source:** PR #90; `variableRegex` and `renderCommand` in `app/Sources/Core/CommandRenderer.swift`; `claudeNoteVerdict` in `extension/defaults.js`; `tests/claude-note.test.js` (`any closed brace span is refused, whatever is inside it`)
**Revisit when:** the app's renderer gains an escape, or stops rendering claude inputs as templates

The app renders every claude input as a template, the note included, so `{repo}` typed into a note becomes the repository's name and a Korean `{이거}` is refused as an unknown variable. The popover and the worker therefore refuse a note in which any `{` has a `}` after it. With no placeholder left, rendering cannot grow the note, so the 4096-byte check bounds its UTF-8 size before the app's trim, and the bound is the same for every item of a batch. That trim can only shorten it: a one-byte note with a trailing no-break space arrived as 1 byte instead of 3, and with a trailing zero-width space as 1 instead of 4 (measured).

**Rejected alternative — render the variables the page provides and refuse the rest** (the first decision). A note's size and its fate then depended on the page kind and on each batch item, which is what the measurements above showed.

**Rejected alternative — refuse only what the app's pattern `\{(\w+)\}` matches.** The app's `\w` is ICU's and takes Korean names; JavaScript's does not reproduce it, and a mirror that disagrees lets a placeholder through. Every match of that pattern is a closed span with no `}` inside, so refusing every closed span is a superset that needs no model of `\w`.

**Rejected alternative — support literal braces.** The renderer has no escape — `{{repo}}` and `\{repo}` still render — and adding one is an app change this work kept out of scope.

**Cost, accepted:** `{}`, `{ a }` and `{"a":1}` are refused too, with a localized reason.

## ✅ on the page means the terminal opened, not that claude received anything

**Type:** decision
**Status:** active
**Evidence:** confirmed; on a live page (the real scripts injected into github.com's main world, `chrome` stubbed with the app's answers written by hand) a batch of one selected row, answered as failed, showed ❌ with that row's ✕ badge and kept the note, and a failed single request kept it too. A batch mixing ✓ and ✕ was not seen there: its mapping to one badge of each is pinned by `tests/list-pages.test.js` (`listBatchResultView maps ordered item results without crossing button identities`), and the worker's answer for it by `tests/worker-note.test.js` (`a batch the app ran in part arrives as the app's own result, keyed in the order the worker read`)
**Source:** PR #90; `serve(fd:)` in `app/Sources/App/HostServer.swift`; `handleBatchRequest` in `app/Sources/Core/Request.swift`
**Revisit when:** the app answers a request only after delivery, or keeps the session handle to report on it later

The app answers as soon as the tab exists and delivers claude input afterwards, on another queue. A button's ✅ — and a popover closing on success — therefore means only that the app accepted the command and opened the terminal; a delivery that fails later is in the app's log and nowhere on the page. A batch can run some of its items and then answer `success:false`, and the page shows that as a failure with a badge on each row.

**Rejected alternative — send again automatically after a failure.** A batch that failed part-way has already run the items that succeeded, and a repeat would run them a second time; a single request whose answer was lost may already have opened its session. Sending again stays a person's decision.

## Whether a note is typed or rides in argv is the app's decision, and nothing promises it

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured: a button storing one input made of U+200B, a zero-width space, plus the note `hello` reached the app as the single input `hello`, an argv candidate, although the extension saw two inputs)
**Source:** PR #90; `executionPayload` and `buttonTakesClaudeNote` in `extension/defaults.js`
**Revisit when:** the extension and the app come to share one normalization of stored inputs

The note joins the stored inputs, and the app chooses the route by the rules above, after its own trim. The extension trims ordinary spaces only while the app's trim is wider, so the extension cannot know which list the app will see; the README and the popover state no route. What the extension does own is the per-button stored-input cap, `MAX_CLAUDE_INPUTS`; a note uses one slot above it, so one request carries at most `MAX_CLAUDE_INPUTS + 1` claude inputs.

**Rejected alternative — state the route per button** ("an input-less button hands the note over in argv"). The measurement above is a counterexample, and keeping such a sentence true would take a second copy of the app's trim in the extension.

## A note goes to the page its popover opened on, and a draft stays with that page

**Type:** decision
**Status:** active
**Evidence:** confirmed; on a live page (the real scripts injected into github.com's main world, `chrome` stubbed) a draft typed on PR 86 was back when that button's popover was opened on PR 86 again, after a move to PR 87 had closed it
**Source:** PR #90; `openNotePopover` and `submitNote` in `extension/content.js`; `tests/claude-note.test.js` (`a note is for the page its popover opened on, read once, and judged before anything is sent (lint)`)
**Revisit when:** the popover starts following the page instead of closing when the page moves

The popover reads the page when it opens, and the note is sent for that page — the person wrote it about what they were looking at. If the tab has moved by the time the worker checks, the final gate refuses the request (`PAGE_CHANGED_ERROR`) rather than attaching the note to another PR. The text is read once, at send, and judged before anything leaves. What a closed or failed popover leaves typed is kept in memory under the identity of the page it was opened for, so reopening that button on that page brings it back and another page does not.

**Rejected alternative — read the page when the note is sent.** A page that moved while the note was being written would receive a note about the page before it.

## A split button's run is held by page and button, never by the node on screen

**Type:** decision
**Status:** active
**Evidence:** confirmed. Before the fix, reproduced in a browser: a button drawn on PR 86 survived a move to PR 87 that nothing saw; its body was pressed and the header rebuilt while the request was out, the rebuilt button was free, and a second press sent the same request again. After it, on a live page (the real scripts injected into github.com's main world, `chrome` stubbed, trusted clicks and keys): two Enters sent one message and body and caret stayed busy until the answer; a refused press's reason left the tooltip when a note was sent during its ❌, did not come back when the refused run's timer fired, and the note's run sent exactly one message
**Source:** PR #90; `splitButtonRun` and `createSplitButtonRuns` in `extension/defaults.js`; `runSplitButton` and `paintSplitButton` in `extension/content.js`; `tests/claude-note.test.js` (`a drawing that outlived a page change holds and shows the run of the page it now sends for`, `a run refused before it sent keeps its reason for its own marker only: not for the next run, whatever the old timer does`)
**Revisit when:** buttons gain a persistent id in the stored schema

Every way into a button — its body, its caret, the popover's send button, Enter — goes through one run function, which holds the run before its first await under the identity of the page the request is for plus the button's kind, index and fingerprint. A drawing keeps no identity of its own: it is painted from the run of the page on screen now, and everything it shows comes from that run — the face, whether it can be pressed, the caret, and the tooltip a refused list selection puts up. A list page's identity has no query in it, so filtering or paginating the same list leaves a batch in flight holding its button.

**Rejected alternative — hold the DOM node.** GitHub rebuilds headers while a request is out; the new node was free and sent again.

**Rejected alternative — hold the page the button was drawn on.** A button that outlived a move nothing saw held A while sending B, which is how the rebuilt button came back free.

**The same rule closed a second defect.** A refused selection's reason used to be written into the button's tooltip and put back by the refused run's timer, which stands down once a later run has started — so the reason stayed on the next run's ⏳ and outcome. The reason now lives in the run beside its phase, and the paint draws the tooltip from it.

## The popover lists the stored inputs a note follows from the list that is sent

**Type:** decision
**Status:** active
**Evidence:** confirmed; on a live page (the real scripts injected into github.com's main world, `chrome` stubbed) `pr.review`'s popover listed its two `!` templates above the note in their order, the message sent carried the same inputs in its fingerprint, and four long inputs wrapped inside the popover's width while the list scrolled on its own
**Source:** PR #90; `claudeInputsBeforeNote` in `extension/defaults.js`; `noteBeforeList` in `extension/content.js`; `tests/claude-note.test.js` (`a popover lists the inputs a note follows exactly as the click sends them, and the fingerprint vouches for that list`)
**Revisit when:** the popover has to show inputs the fingerprint does not cover

Above the note's box the popover lists the button's stored inputs in the order they are sent and as stored, with `{branch}` and the rest still unfilled — they are filled in at the click (a maintainer request). The list is `executionPayload(button).claudeInputs`, the normalization a click goes through, made from the same stored button at the same moment as the drawing's fingerprint. If storage changes after the drawing, the worker's fingerprint check refuses the click, so the list is exactly the templates the request carries in front of the note.

**That is where the promise stops.** The app renders and trims each input afterwards and can drop one that trims to nothing: a button storing an input made only of U+200B and then `!echo A` lists two entries and sends two, and the app keeps one. The extension does not copy the app's normalization to predict that, for the same reason it does not predict the note's route above.

**Rejected alternative — a separate copy of the inputs, normalized for display.** A second normalization is a list that can disagree with the one sent, and the popover would then vouch for something the fingerprint does not.

## Residuals kept rather than closed

**Type:** constraint
**Status:** active
**Evidence:** confirmed
**Source:** PR #36; issue #16

- **A draft typed during delivery mixes with ours.** Measured: a stray character landing in front of a `!` line costs it shell mode, and the line is submitted as an ordinary message instead. Detecting it would mean proving "the box starts with our text and nothing else", which is the screen-reading class this design abandoned. The contract is documented instead: don't type in that tab during delivery.
- **A command name assembled out of quotes** (`'cd' sub`) walks past the state-word scan. Reading inside quotes would break the shipped presets' own `--jq '…'`.
- **A zsh builtin with an unquoted glob matching nothing** aborts the rest of a merged line. Folding on glob characters would fold every ordinary `gh … *`.
