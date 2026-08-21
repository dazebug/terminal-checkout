import Foundation

// Splits the scheduled claude inputs in two: the **merged prefix** rides along in the argv of the
// command that starts claude, as a single opening message, and only the **tail** goes through the
// existing injection path (`ClaudeInjector`).
//
// Why: injection has to read the screen to confirm delivery, which makes the Accessibility
// permission mandatory on Warp and drags in pane proofs, reflection checks and retries — slow and
// fragile. argv needs none of it, because claude already holds the prompt when it starts. Every
// claude input in the shipped presets is a `!` line, so the tail comes out empty and neither the
// helper nor the permission is needed at all.
//
// The cost: N inputs become one message and therefore one response. The user chose that change in
// meaning (each `!` already triggers a response today — measured in session transcripts).

// MARK: - Boundary

/// What one input is. Used only to find the boundary.
private enum ClaudeInputKind {
    /// Starts with `!` — claude's shell mode. Run ahead of time so its output joins the prompt
    case shellCommand
    /// Starts with `/` — a slash command
    case slashCommand
    /// Anything else: free text
    case interactive

    init(_ input: String) {
        if input.hasPrefix("!") {
            self = .shellCommand
        } else if input.hasPrefix("/") {
            self = .slashCommand
        } else {
            self = .interactive
        }
    }
}

/// The inputs split into a merged prefix and an injected tail. `prefix + tail` is always the input.
public struct ClaudeInputPlan: Equatable {
    /// Inputs folded into the single opening message in claude's argv (order preserved)
    public let prefix: [String]
    /// Inputs left for the existing injection path
    public let tail: [String]
}

/// Finds the **longest prefix** that can be merged. There are only two boundaries:
///
/// 1. **A slash command** — it is only read as a command when it is the whole message. Only a
///    leading `/` reaches the slash dispatcher; put a banner in front and it becomes inert text
///    (`claude -p "/help"` → recognised as a command, `claude -p $'banner\n/help\n…'` → handled as
///    ordinary text; both measured). Merging one would silently discard what it meant.
/// 2. **A `!` that follows an interactive input** — its output was meant as context for the
///    instruction *after* it. Hoisting it into the opening message changes what the earlier
///    instruction sees.
///
/// Every other transition (command→command, text→text, command→text) merges.
public func claudeInputPlan(_ inputs: [String]) -> ClaudeInputPlan {
    var sawInteractive = false
    for (index, input) in inputs.enumerated() {
        func split() -> ClaudeInputPlan {
            ClaudeInputPlan(prefix: Array(inputs[..<index]), tail: Array(inputs[index...]))
        }
        switch ClaudeInputKind(input) {
        case .slashCommand: return split()
        case .shellCommand where sawInteractive: return split()
        case .shellCommand: continue
        case .interactive: sawInteractive = true
        }
    }
    return ClaudeInputPlan(prefix: inputs, tail: [])
}

// MARK: - Can a prompt be appended to the command?

let claudeExecutableName = "claude"

/// Whether one prompt argument can be appended to the command — a **whitelist syntax scanner**.
///
/// The previous rule looked only at "is the last segment's token `claude`", justified by "the
/// worst a misjudgement can do is drop the prompt silently". **Reproductions proved that false**
/// (external reviewer):
///  - `echo ready # && claude` → the last token is `claude`, but all of it is a comment (silent loss)
///  - `cat <<claude` … `claude` → that `claude` is the heredoc **terminator**. Appending an
///    argument changes the terminator and the shell hangs waiting for input (breakage)
///  - `claude() { /bin/sh -c "$1"; }` ⏎ `claude` → a **function** defined earlier captures the
///    name, and the plain-text input we appended is **executed as a shell command** (arbitrary
///    execution)
///
/// So the whole command is scanned instead of just its tail, and **anything outside quotes that
/// is not on the whitelist folds the judgement** (→ inject everything, i.e. today's behaviour).
/// What is allowed is a run of simple commands joined by `&&`, `||`, `;` or `|`, plus groups
/// (`{ }`) and subshells (`( )`); on top of that the **last simple command must be exactly the
/// single token `claude`**.
///
/// Flags fold for a separate, measured reason: `claude -p --resume "Reply with exactly: OK"` →
/// `Provided value … is not a UUID`. A flag that optionally takes a value swallows our argument,
/// and knowing which flags do that needs claude's flag table, which changes between versions.
///
/// **What this cannot catch**: a `claude` function or alias defined in the user's shell rc. The
/// definition is not in the command text, so there is nothing to judge — recorded as a residual
/// in the sweep table of `docs/new-terminal-checklist.md`.
public func commandAcceptsAppendedClaudePrompt(_ command: String) -> Bool {
    let chars = Array(command)
    // A group's or subshell's brackets also separate commands, so they help find the last segment
    let separators: Set<Character> = ["&", "|", ";", "(", ")", "{", "}"]
    var index = 0
    var segmentStart = 0
    var lastSeparatorWasPipe = false
    var previous: Character?          // previous character, spaces included — for comments
    var previousMeaningful: Character? // previous non-space character — for function definitions

    /// Are we at the first character of a word? `#` only starts a comment here (`echo a#b` is literal)
    func atWordStart() -> Bool {
        guard let previous else { return true }
        return previous.isWhitespace || separators.contains(previous)
    }

    while index < chars.count {
        let character = chars[index]
        if character == "'" {
            // No escapes inside single quotes — everything up to the next `'` is data
            var scan = index + 1
            while scan < chars.count, chars[scan] != "'" { scan += 1 }
            guard scan < chars.count else { return false } // unterminated quote: cannot judge
            index = scan + 1
            previous = "'"
            previousMeaningful = "'"
            continue
        }
        if character == "\"" {
            var scan = index + 1
            while scan < chars.count {
                let inner = chars[scan]
                if inner == "\\" {
                    scan += 2
                    continue
                }
                // Substitutions are still live inside double quotes
                if inner == "`" { return false }
                if inner == "$", scan + 1 < chars.count, chars[scan + 1] == "(" { return false }
                if inner == "\"" { break }
                scan += 1
            }
            guard scan < chars.count else { return false }
            index = scan + 1
            previous = "\""
            previousMeaningful = "\""
            continue
        }
        switch character {
        case "\\", "\n", "`":
            return false // line continuation, newline (another command follows), backtick
        case "#" where atWordStart():
            return false // comment — everything we append is swallowed by it
        case "$" where index + 1 < chars.count && chars[index + 1] == "(":
            return false // command substitution
        case "<" where index + 1 < chars.count && chars[index + 1] == "<":
            return false // heredoc — the last token may be its terminator
        case "(" where !(previousMeaningful.map(separators.contains) ?? true):
            return false // `(` right after a word is a function definition; at a command
            // position it is a subshell, which is allowed
        default:
            break
        }
        guard separators.contains(character) else {
            index += 1
            previous = character
            if !character.isWhitespace { previousMeaningful = character }
            continue
        }
        var run = ""
        while index < chars.count, separators.contains(chars[index]) {
            run.append(chars[index])
            index += 1
        }
        // `&` is "and" only in pairs. A single one backgrounds, and the argument we append
        // after it becomes **the next command** and runs
        var scan = run.startIndex
        while scan < run.endIndex {
            guard run[scan] == "&" else {
                scan = run.index(after: scan)
                continue
            }
            var count = 0
            while scan < run.endIndex, run[scan] == "&" {
                count += 1
                scan = run.index(after: scan)
            }
            if count != 2 { return false }
        }
        // `||` is or, not a pipe — decide from the end of the run
        lastSeparatorWasPipe = run.hasSuffix("|") && !run.hasSuffix("||")
        segmentStart = index
        previous = run.last
        previousMeaningful = run.last
    }
    if lastSeparatorWasPipe { return false } // claude on the receiving end of a pipe has no TUI
    let segment = String(chars[segmentStart...])
    let tokens = segment.split(whereSeparator: \.isWhitespace).map(String.init)
    return tokens == [claudeExecutableName]
}

// MARK: - Prompt assembly script

/// The shell that pre-runs the `!` bodies and assembles the message. claude's own `!` runs in its
/// Bash tool, so `sh` is closer to today's semantics than the user's interactive shell (zsh and
/// friends) would be — with the same consequence that shell functions like zoxide's `z` are
/// unavailable here, exactly as they are unavailable to claude's `!`.
let claudePromptShell = "/bin/sh"

/// Slack subtracted from the argv budget. ARG_MAX covers argv **and** the environment together,
/// and our own command line, the other arguments and any growth in the environment all live in
/// there too. Against the measured baseline (ARG_MAX 1,048,576 / env 6,193 bytes) 64 KiB is ample.
public let claudeArgvBudgetSlack = 65536

/// **Absolute paths** for the utilities the script calls. Going through PATH runs whatever
/// same-named program sits in a directory the user controls — reproduced: with the command
/// `PATH="$PWD/bin:$PATH" && claude` and a `bin/getconf` in the repository, that program ran even
/// though the claude input was a single line of plain text. An absolute path also bypasses shell
/// **functions and aliases**, whose names cannot contain `/`.
enum ShellUtility {
    static let getconf = "/usr/bin/getconf"
    static let env = "/usr/bin/env"
    static let wc = "/usr/bin/wc"
    static let tr = "/usr/bin/tr"
    static let cat = "/bin/cat"
    static let printf = "/usr/bin/printf"
    static let rm = "/bin/rm"
}

/// One request owns **one directory**. Scattering two files across the temp directory makes their
/// names predictable enough for someone to pre-place a symlink (reproduced), and reclaiming
/// per-file leaves no way to ask "is this context still needed". The directory is claimed
/// atomically with `mkdir`, which fails if it already exists.
let claudePromptDirectoryPrefix = "tc-prompt-"
let claudePromptTokenLength = 8
let claudePromptScriptName = "prompt.sh"
let claudePromptContextName = "context.txt"
/// Left behind by the over-budget branch. Its presence means claude was told to read the context
/// during the session, so the reclaim sweep gives that directory a much longer grace period
let claudePromptHandoffName = "handed-to-claude"

/// Bytes one environment entry costs in the argv budget (pointer plus alignment slack).
/// `env | wc -c` counts only the strings, so without subtracting this as well `execve` fails with
/// E2BIG in an environment with many entries (reproduced).
public let claudeArgvEnvEntryOverhead = 32

func claudePromptHandoffPath(forContext contextPath: String) -> String {
    ((contextPath as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent(claudePromptHandoffName)
}

/// What goes into argv when the assembled message is over budget. Nothing is truncated — the whole
/// context stays in a file and claude is told to read it. In the default permission mode that may
/// cost one Read approval prompt (a rare edge, accepted).
let claudeContextPointerInstruction =
    "The context for this task was too large to pass on the command line, "
    + "so it was written to a file. Read this file in full before doing anything else:"

/// Keeps argv from being an empty string when the command runs after the script is already gone
/// (a race with the reclaim sweep) — an empty prompt can submit an empty message to claude.
let claudePromptLostInstruction =
    "Terminal Checkout: the prepared context was lost before claude started. "
    + "Ask the user what they wanted to do."

/// Attribution a `!` input leaves in the prompt. With only the output, claude cannot tell which
/// command produced it.
func claudePromptBanner(for input: String) -> String { "==== \(input) ====" }

/// **The marker that lets us confirm from outside that the argv message has rendered — the single
/// source of truth shared by the converter and the tail gate.**
///
/// Why it is needed (measured on claude 2.1.238, bare pty, 3 runs per timepoint, all agreeing):
/// **submitting the argv message clears the input box.** Bytes typed before that message renders
/// land in the box and are wiped by that clear (lost 3/3). And the switch to raw mode happens at
/// 0.1–0.19s while the render lands at 2.06–3.41s with 65% jitter, so **[foreground = claude +
/// raw mode] does not mark this moment at all, and neither does waiting a fixed time.** The only
/// signal available from outside is the rendered message itself.
///
/// It is shaped like a banner so the message gains no new visual element. It is deliberately its
/// **own first line rather than an addition to the first banner**: when the first input is not a
/// `!` there is no banner to attach to, the marker would silently vanish, the gate would never
/// pass, and the whole tail would be dropped.
///
/// The token is unique per request, so on Warp checking for this string doubles as proof that the
/// pane on screen is ours. The gate matches the whole line so the script path echoed on the
/// command line (`tc-prompt-<token>/prompt.sh`) cannot be mistaken for it.
///
/// **It has to be short**: the gate reuses `screenReflectsNewInput`, which compares only the
/// leading `claudeInputProbe` (24 characters) — a token pushed past that loses its uniqueness.
public func claudeArgvRenderMarker(token: String) -> String { "==== tc-\(token) ====" }

/// The text of the script that assembles the opening message inside the pane.
///
/// **Nowhere in this script does user text become syntax.** Banners and interactive inputs are
/// single-quoted by the app and passed as **arguments** to `printf`; a `!` body is single-quoted
/// too and handed to `sh -c`, so a syntax error in it stays trapped inside that `sh -c` instead of
/// failing to parse the whole script. Nothing is truncated (the user's decision); going over
/// budget is routed around with a file pointer.
///
/// Assembly running at the moment claude is invoked is the whole point — in
/// `z {repo} && … && cd ../worktree && claude` the cwd `!gh` sees is the one after the last `cd`,
/// and the app does not know that path.
///
/// `marker` is supplied only when there is a tail to inject (`claudeArgvRenderMarker`). It is
/// written to stdout **outside** the context block, so it rides in argv even on the over-budget
/// branch where the body stays in a file — without it the gate never passes and the tail is lost.
public func claudePromptScriptBody(
    prefix: [String], contextPath: String, marker: String? = nil,
    argvSlack: Int = claudeArgvBudgetSlack
) -> String {
    let printf = ShellUtility.printf
    var lines = [
        "#!/bin/sh",
        "# Generated by \(appDisplayName) — assembles claude's opening message.",
        "# Every utility we call is an absolute path. Going through PATH runs whatever the user's",
        "# repository has at e.g. bin/getconf (reproduced) — one line of plain text was enough to",
        "# execute an arbitrary program. PATH itself is left alone: the ! bodies need to find gh.",
        "TC_CTX=\(shellSingleQuoted(contextPath))",
        // Makes the create an `O_EXCL` open, which **does not follow a symlink** — if one has
        // been planted the open fails instead (reproduced: a bare `>` overwrote the user file the
        // link pointed at)
        "set -C",
        "{",
    ]
    for input in prefix {
        if input.hasPrefix("!") {
            let body = String(input.dropFirst()).trimmingCharacters(in: .whitespaces)
            lines.append("\(printf) '%s\\n' \(shellSingleQuoted(claudePromptBanner(for: input)))")
            // A failing command does not stop the next one — joining with `&&` would let the
            // first failure swallow the rest. `2>&1` keeps failure output in the prompt, the way
            // `!` does
            lines.append("\(claudePromptShell) -c \(shellSingleQuoted(body)) 2>&1")
        } else {
            lines.append("\(printf) '%s\\n' \(shellSingleQuoted(input))")
        }
        lines.append("\(printf) '\\n'") // block separator: run together, the inputs read as one lump
    }
    lines += [
        "} > \"$TC_CTX\" || exit 1",
        "set +C",
        // Two layers: even in a shell where `set -C` does not stop it, a symlink stops here.
        // Testing `-s` first would pass on the grounds that **someone else's file** behind the
        // link is non-empty, and that content would go out as the prompt. And since a failed
        // redirect still lets the shell continue to the next line (measured), leaving 0 bytes
        // alone would **submit an empty string as claude's opening message** — failing instead
        // lets the `|| printf <claudePromptLostInstruction>` on the append side speak
        "if [ -L \"$TC_CTX\" ] || [ ! -f \"$TC_CTX\" ] || [ ! -s \"$TC_CTX\" ]; then exit 1; fi",
    ]
    if let marker {
        // The **first line** of the message — if the TUI folds a long one, the head survives longest
        lines.append("\(printf) '%s\\n' \(shellSingleQuoted(marker))")
    }
    lines += [
        // Through arithmetic expansion to get a plain integer — `wc` pads with spaces and
        // `test -le` dislikes that
        "TC_SIZE=$(( $(\(ShellUtility.wc) -c < \"$TC_CTX\") + 0 ))",
        // Size with NULs removed. A difference means NULs are present, and command substitution
        // drops those silently (`pre<NUL>post` → `prepost`, reproduced) — hand the file over
        // rather than send something distorted
        "TC_CLEAN=$(( $(\(ShellUtility.tr) -d '\\000' < \"$TC_CTX\" | \(ShellUtility.wc) -c) + 0 ))",
        // ARG_MAX covers the **pointer array and alignment** too, not just the string bytes.
        // Subtracting only the strings makes `execve` fail with E2BIG in a large environment
        // (reproduced: 9,000 entries / 81,000 bytes)
        "TC_ENV_BYTES=$(( $(\(ShellUtility.env) | \(ShellUtility.wc) -c) + 0 ))",
        "TC_ENV_COUNT=$(( $(\(ShellUtility.env) | \(ShellUtility.wc) -l) + 0 ))",
        "TC_BUDGET=$(( $(\(ShellUtility.getconf) ARG_MAX) - TC_ENV_BYTES"
            + " - TC_ENV_COUNT * \(claudeArgvEnvEntryOverhead) - \(argvSlack) ))",
        "if [ \"$TC_SIZE\" -le \"$TC_BUDGET\" ] && [ \"$TC_SIZE\" -eq \"$TC_CLEAN\" ]; then",
        // **Not deleted.** `execve` can still fail after the budget check passes, and if we had
        // already deleted it the assembled content would be gone for good. The reclaim sweep
        // clears it by age instead
        "\(ShellUtility.cat) \"$TC_CTX\"",
        "else",
        "\(printf) '%s\\n%s\\n' \(shellSingleQuoted(claudeContextPointerInstruction)) \"$TC_CTX\"",
        // On this branch claude reads the context **during the session** — if the sweep removed
        // it on the short age the session would find the file it was told to read missing. The
        // marker makes the sweep wait much longer
        ": > \(shellSingleQuoted(claudePromptHandoffPath(forContext: contextPath)))",
        "fi",
        "",
    ]
    return lines.joined(separator: "\n")
}

/// Appends the prompt substitution to the command. The script deletes itself once its work is
/// done, **inside the same substitution** (the way spawn-claude does it) — if the chain never
/// reaches claude the substitution never runs at all, so there is no window in which a later
/// claude picks up a stale prompt.
///
/// This string is evaluated by the **user's interactive shell**, further outside our control than
/// our own script, so `printf` and `rm` are called by absolute path too: `command rm` only
/// bypasses functions and aliases, it still goes through PATH. The context file is not deleted
/// here (that is the reclaim sweep's job) — only the script is.
///
/// **`--` comes first.** Measured (claude 2.1.238, 2 runs per combination, all agreeing): a flag
/// that takes a value claims the following argument as its own instead of leaving it as the
/// prompt — and so do **variadic flags** (`claude -p --allowed-tools Bash 'P'` → the prompt is
/// swallowed and it exits 1), which means "a flag that already has its value is safe" is false.
/// `--` closes that whole class (`--allowed-tools Bash -- 'P'` is delivered). Today it is
/// harmless because only a bare `claude` is ever appended to, and it also covers the day the
/// prompt starts with `-` (a reworded file pointer or banner).
///
/// What `--` **cannot** fix: if the command already has a positional prompt, ours becomes the
/// second one and is **discarded silently, exit 0 and no stderr** (`claude -p 'first' 'second'`
/// records only first). That is why the judgement stays narrowed to "the last simple command is a
/// bare `claude`".
public func appendedPromptCommand(_ command: String, scriptPath: String) -> String {
    let quoted = shellSingleQuoted(scriptPath)
    let trimmed = command.replacingOccurrences(
        of: "[ \t]+$", with: "", options: .regularExpression
    )
    return trimmed + " -- \"$(\(claudePromptShell) \(quoted)"
        + " || \(ShellUtility.printf) '%s' \(shellSingleQuoted(claudePromptLostInstruction));"
        + " \(ShellUtility.rm) -f -- \(quoted))\""
}

// MARK: - Request preparation

/// A request prepared up to the moment of execution.
public struct PreparedRequest {
    /// The final command for the terminal (the merged prefix may be appended to its argv)
    public let command: String
    /// Inputs for the injection path. **Empty means neither the Warp helper nor the
    /// Accessibility permission is needed**
    public let claudeInputs: [String]
    /// The directory this request alone owns. Removed whole if the command never reached the terminal
    public let temporaryDirectory: String?
    /// The string to look for on screen before typing the tail (`claudeArgvRenderMarker`).
    /// Present **only when there is a tail** — with no tail nobody would be watching, and all
    /// that would be left is one extra line in a preset's opening message. Nil means no gate,
    /// which is the case for the pure-injection fallback where there is no argv at all.
    public let argvRenderMarker: String?

    /// Path of the assembly script. Nil when there is no directory (the fallback)
    public var scriptPath: String? {
        temporaryDirectory.map { ($0 as NSString).appendingPathComponent(claudePromptScriptName) }
    }

    public func discardTemporaryFiles() {
        guard let temporaryDirectory else { return }
        try? FileManager.default.removeItem(atPath: temporaryDirectory)
    }
}

/// Is this a name we may reclaim — our prefix plus an **exactly 8 character** hex token? Without
/// the length check someone else's `tc-prompt-a` would count as ours.
func claudePromptDirectoryIsOurs(name: String) -> Bool {
    guard name.hasPrefix(claudePromptDirectoryPrefix) else { return false }
    let token = name.dropFirst(claudePromptDirectoryPrefix.count)
    return token.count == claudePromptTokenLength && token.allSatisfy(\.isHexDigit)
}

/// A different hex token per request, from the same generator the helper socket and the Tab
/// Config use — however many places need a request-unique string, they all draw from one.
func claudePromptToken() -> String { warpHelperToken() }

/// Creates only (`O_EXCL`) — a colliding token might be someone else's file, so it is never
/// overwritten. 0600 because the script carries the `!` bodies and instructions from the user's
/// settings. The context file, which holds the assembled result (PR and issue bodies), is created
/// by the pane's shell under its own umask, but the temp directory itself is `drwx------` so no
/// other user can walk in — and the same uid is inside this repository's declared trust boundary
/// (`SECURITY.md`).
private func writeNewPrivateFile(path: String, contents: String) -> Bool {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    guard writeAll(fd: descriptor, data: Data(contents.utf8)) else {
        unlink(path)
        return false
    }
    return true
}

/// The script deletes itself inside the substitution, but **nobody deletes the context** —
/// deleting it and then having `execve` fail would lose the assembled content entirely, and that
/// failure has actually been reproduced. So reclaiming happens here alone, on two different ages:
///  - Normally short (6 hours by default). Whether the script ran (the content already went out
///    in argv) or the tab never opened at all, by then nobody needs that directory
///  - **Long when the hand-off marker is there** (7 days by default). On the over-budget branch
///    claude reads that file during the session — another request's sweep removing it after six
///    hours would leave the session unable to find the file it was told to read
func reclaimStaleClaudePromptDirectories(
    in directory: String = NSTemporaryDirectory(),
    leftoverAge: TimeInterval = 6 * 3600, handedOffAge: TimeInterval = 7 * 24 * 3600
) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where claudePromptDirectoryIsOurs(name: name) {
        let path = (directory as NSString).appendingPathComponent(name)
        var info = stat()
        // Never follow a symlink — following one would delete the whole directory it points at
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
        let handoff = (path as NSString).appendingPathComponent(claudePromptHandoffName)
        var handoffInfo = stat()
        let age = lstat(handoff, &handoffInfo) == 0 ? handedOffAge : leftoverAge
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        guard Date().timeIntervalSince(modified) > age else { continue }
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Turns a request into the form that will actually run. When there is a prefix to merge and the
/// command can take the append, the prefix goes into argv and only the tail is left for injection.
/// If either condition fails it falls back to **injecting everything** (today's behaviour) — with
/// no confidence in the conversion, the fallback is the default.
///
/// It does not throw: this conversion cannot fail a request. Not being able to write the temp
/// files is a fallback, not a rejection — throwing here would make a request that works today
/// fail because of the state of the disk.
public func prepareRequest(_ resolved: ResolvedRequest) -> PreparedRequest {
    func injectEverything() -> PreparedRequest {
        PreparedRequest(
            command: resolved.command, claudeInputs: resolved.claudeInputs,
            temporaryDirectory: nil, argvRenderMarker: nil
        )
    }

    let plan = claudeInputPlan(resolved.claudeInputs)
    guard !plan.prefix.isEmpty, commandAcceptsAppendedClaudePrompt(resolved.command) else {
        return injectEverything()
    }
    // Reclaim leftovers from earlier runs the app died in the middle of (age decides, so nothing
    // still in use is touched)
    reclaimStaleClaudePromptDirectories()

    let token = claudePromptToken()
    let directory = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("\(claudePromptDirectoryPrefix)\(token)")
    // `withIntermediateDirectories: false` throws if it already exists — that is what makes the
    // claim atomic, and it means a link or directory someone else left under that name is never
    // adopted as ours
    guard (try? FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )) != nil else {
        checkoutLog("프롬프트 작업 디렉토리를 만들지 못해 claude 입력 \(resolved.claudeInputs.count)개를 주입 경로로 보낸다")
        return injectEverything()
    }
    let scriptPath = (directory as NSString).appendingPathComponent(claudePromptScriptName)
    let contextPath = (directory as NSString).appendingPathComponent(claudePromptContextName)
    // The marker rides along only when there is a tail to type — with nothing to type there is
    // no reason to watch the screen
    let marker = plan.tail.isEmpty ? nil : claudeArgvRenderMarker(token: token)
    let body = claudePromptScriptBody(prefix: plan.prefix, contextPath: contextPath, marker: marker)
    guard writeNewPrivateFile(path: scriptPath, contents: body) else {
        checkoutLog("프롬프트 조립 스크립트를 쓰지 못해 claude 입력 \(resolved.claudeInputs.count)개를 주입 경로로 보낸다")
        try? FileManager.default.removeItem(atPath: directory)
        return injectEverything()
    }
    return PreparedRequest(
        command: appendedPromptCommand(resolved.command, scriptPath: scriptPath),
        claudeInputs: plan.tail,
        temporaryDirectory: directory,
        argvRenderMarker: marker
    )
}
