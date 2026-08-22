# Claude input delivery

How a button's scheduled `claude_inputs` reach the Claude Code session the button just started. The mechanisms, the measurements behind them, and the invariants live in `CLAUDE.md`; this file holds the forks — what was chosen over what, and why.

## `!` inputs are typed into claude's shell mode, never pre-run and pasted

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** PR #36 (`da37339`); measured in a pty against claude 2.1.238
**Revisit when:** claude gains a documented way to enter shell mode from argv, or the `!` prefix stops meaning shell mode

An input starting with `!` is typed into the running TUI so that claude's own shell mode executes it. For a while the app did the opposite: it ran those lines in the pane's shell ahead of time and handed claude the captured output as its opening message, assembled by a generated script through a temporary context file.

**Reason:** the two are not equivalent, even when the text ends up looking the same. Executing it in the session leaves the command in that session's own history as a command; pasting its output leaves a wall of text whose provenance claude has to infer from a banner convention we invented. The paste route was faster, and it was still rejected: what the feature is for is putting *claude* in front of the command, not putting the command's stdout in front of claude.

**Rejected alternative — carry the `!` line in argv instead of typing it.** This would have kept the speed of the paste route without the paste. Measured, it does not exist: `claude -- '!echo x'` does **not** enter shell mode. The line arrives as an ordinary message and the model then decides to run it through its Bash tool — which can stop at a permission prompt, is a judgement rather than a shell fact, and spends a turn. The official CLI reference documents no flag or prefix for it either.

**Rejected alternative — keep pre-execution as an option.** Dropped rather than kept behind a switch: it doubles the delivery paths that every later change has to be correct in, and the whole hardening effort that followed was about removing paths, not adding them.

**Consequence, accepted:** every shipped preset that schedules claude input is `!`-only, so all of them are typed. On Warp that makes the Accessibility permission a hard requirement for those three buttons, where the paste route had needed nothing.

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

## The input box is cleared with Ctrl+U **then** Backspace

**Type:** workaround
**Status:** active
**Evidence:** confirmed
**Source:** measured in a pty on claude 2.1.238; only `!` was measured
**Revisit when:** claude changes how its `!` shell mode is entered or exited

**Reason:** Ctrl+U alone does not leave claude's `!` shell mode. It clears the text and leaves the `!`, so the box looks empty and the disappearance check passes — and the next plain input is submitted as a shell command (`command not found: …`). One Backspace removes the prefix; extra Backspaces on an empty box do nothing. The order matters: on a box that still holds text, Backspace alone would take only its last character.

**Known limit:** only `!` was measured. `/` and `#` are also one character and should be covered by the same sequence, but that is inference, not measurement.

## Polling reads first and subtracts what the read cost

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** three timed field runs on Warp; first message 11.6s → 10.5s → 6.8s
**Revisit when:** a terminal's screen read gets much cheaper or much more expensive than ~140ms

Every wait in the delivery loop reads before it sleeps, and the sleep is shortened by what the read itself just cost.

**Reason:** the attempt counts assume one iteration costs one interval. A Warp Accessibility read measures 134–143ms against a 0.15s interval, so sleeping a full interval on top made every deadline take nearly twice its stated wall clock. The first shape also slept before its first read, so a screen that was already drawn still cost a full interval — four times per input.

**Rejected alternative — shorten the deadlines instead.** The deadlines are what wait out "the user has not looked at the tab yet", which on Warp is a design constraint rather than a delay to remove. The waiting moved into the attempt count instead: more attempts, each shorter, so a marker claude's initialisation swallowed is abandoned in ~2s rather than holding the budget for 5.

## Residuals kept rather than closed

**Type:** constraint
**Status:** active
**Evidence:** confirmed
**Source:** PR #36; issue #16

- **A draft typed during delivery mixes with ours.** Measured: a stray character landing in front of a `!` line costs it shell mode, and the line is submitted as an ordinary message instead. Detecting it would mean proving "the box starts with our text and nothing else", which is the screen-reading class this design abandoned. The contract is documented instead: don't type in that tab during delivery.
- **A command name assembled out of quotes** (`'cd' sub`) walks past the state-word scan. Reading inside quotes would break the shipped presets' own `--jq '…'`.
- **A zsh builtin with an unquoted glob matching nothing** aborts the rest of a merged line. Folding on glob characters would fold every ordinary `gh … *`.
