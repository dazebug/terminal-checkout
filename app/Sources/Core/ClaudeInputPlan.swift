import Foundation

// Decides how the scheduled claude inputs reach claude. **All of them ride along in the argv of
// the command that starts claude, as one opening message, or all of them are typed into the
// session by `ClaudeInjector` — never a mix** (see `prepareRequest`).
//
// Why argv: injection has to read the screen to confirm delivery, which makes the Accessibility
// permission mandatory on Warp and drags in pane proofs, reflection checks and retries — slow and
// fragile. argv needs none of it, because claude already holds the prompt when it starts. Every
// claude input in the shipped presets is a `!` line and all of them merge, so neither the helper
// nor the permission is needed at all.
//
// The cost: N inputs become one message and therefore one response. The user chose that change in
// meaning (each `!` already triggers a response today — measured in session transcripts).

// MARK: - Boundary

/// What one input is. Used only to find the boundary.
private enum ClaudeInputKind {
    /// Starts with `!` — claude's shell mode. Run ahead of time so its output joins the prompt
    case shellCommand
    /// A line the **input box** reads specially: `/` dispatches a slash command, `#` files the
    /// line into memory. Neither meaning exists in argv, where the text is just text
    case inputBoxDirective
    /// Anything else: free text
    case interactive

    init(_ input: String) {
        if input.hasPrefix("!") {
            self = .shellCommand
        } else if input.hasPrefix("/") || input.hasPrefix("#") {
            self = .inputBoxDirective
        } else {
            self = .interactive
        }
    }
}

/// The inputs split at the first boundary. `prefix + tail` is always the input.
///
/// **An empty `tail` is what "this configuration can be merged" means** — `prepareRequest` merges
/// only then. The split is still computed as a split (rather than a single Bool) because the
/// boundary rule is what defines mergeability, and because it is the thing worth pinning with a
/// property test: no input may be lost or duplicated on the way to that answer.
public struct ClaudeInputPlan: Equatable {
    /// Inputs before the first boundary (order preserved)
    public let prefix: [String]
    /// The first boundary onwards. Non-empty means **nothing merges** and everything is typed
    public let tail: [String]
}

/// Finds the **longest prefix** that could be merged. There are only two boundaries:
///
/// 1. **A line the input box reads specially** — a slash command or a `#` memory line. Both only
///    mean what they mean when they are the whole message, typed into the box. Only a leading `/`
///    reaches the slash dispatcher; put a banner in front and it becomes inert text
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
        case .inputBoxDirective: return split()
        case .shellCommand where sawInteractive: return split()
        case .shellCommand: continue
        case .interactive: sawInteractive = true
        }
    }
    return ClaudeInputPlan(prefix: inputs, tail: [])
}

// MARK: - Can a prompt be appended to the command?

let claudeExecutableName = "claude"

/// A word the scanner read outside quotes. `opaque` means the text cannot be compared: it held a
/// quote or an expansion. That matters **only in command position** — `'eval' x` still runs the
/// `eval` builtin and `$RUNNER x` runs whatever the variable holds, so a command name we cannot
/// read is a command name we cannot clear.
private struct ShellWord {
    var text = ""
    var opaque = false
}

/// Words that make us give up on appending, read **wherever they appear**.
///
/// This list is the *second* layer, and it is not claimed to be complete. The first layer is
/// structural: the append invokes `command claude`, which runs the executable past any function or
/// alias (`appendedPromptCommand`), so the wrapper class this list used to be the only defence
/// against cannot receive our prompt at all. What is left for the list is the shell being able to
/// rebind `command` itself, plus grammar we do not model.
///
/// Why every word and not just the first. Reading only the first word of a segment was wrong: a
/// **redirection** (`> /dev/null eval …`) and a **precommand modifier** (zsh's `noglob`,
/// `nocorrect`, `-`) both sit in front of the command name, and both were used to hide an `eval`
/// (reproduced by two independent reviewers, sentinel confirmed). Neither list is closed across
/// shells, so instead of locating the command position we require **every** word to be one that
/// would be safe there. Wherever the command position turns out to be, that word has been checked.
/// The price is over-folding on arguments spelled like these words (`git add .`) or on words we
/// cannot read (`-m 'msg'`), which costs the merge and nothing else — the request falls back to
/// typing, which is what it did before this track existed.
///
/// The named groups:
///
///  - **Definition and rebinding**: `function` (the keyword form has no `(` — this is what both
///    reviewers used), `alias`/`unalias`, `hash` (rewrites the lookup table), `autoload`
///    (zsh/ksh: declares a function loaded from `fpath`), `enable` (bash: loads builtins).
///  - **Evaluating text we cannot see**: `eval`, `source`, `.`, `trap` (its handler runs later in
///    this shell, `DEBUG` before every command).
///  - **PATH**: `export`/`declare`/`typeset`/`local`/`readonly`, and any word shaped like an
///    assignment (`PATH=…`). A different PATH is a different `claude`.
///  - **Command modifiers** that keep the above in this shell rather than a child: `command`,
///    `builtin`, `exec`, `time`, `!`. (`env`, `nohup`, `xargs` fork, so they cannot rebind.)
///  - **Compound-command keywords**: `if`/`then`/`fi`/`for`/`while`/`case`/… . These are not
///    rebinding — they open command positions that a flat segment scan does not model, so a
///    definition could hide behind one. We fold on grammar we do not model rather than guess.
///
/// **What is still not caught** — all of it needs runtime knowledge of the user's shell and
/// filesystem, and none of it can put our prompt text through a shell:
///  - Anything that changes **PATH** by a route that is not an assignment word: `printf -v PATH`,
///    `read PATH < file`, or a PATH exported from the rc. Then `claude` resolves to a different
///    program — a different program receiving the prompt as its argument, not the shell executing
///    our text. `cp x ~/bin/claude && claude` is the same class; telling it from any other `cp`
///    would need the PATH and the filesystem.
///  - A **`command` function or alias** in the rc, which would capture the invocation this list's
///    structural partner relies on. It is not in the command text, so nothing here can see it.
/// Both are recorded as residuals in `README.md` and `docs/new-terminal-checklist.md`.
private let commandPositionWordsThatFold: Set<String> = [
    "function", "alias", "unalias", "hash", "autoload", "enable", "zmodload",
    "eval", "source", ".", "trap",
    "export", "declare", "typeset", "local", "readonly",
    "command", "builtin", "exec", "time", "!",
    "if", "then", "elif", "else", "fi",
    "for", "while", "until", "do", "done", "in",
    "case", "esac", "select", "coproc",
]

/// `NAME=` / `NAME+=` / `NAME[index]=` — a variable assignment. `PATH=…` alone changes which
/// `claude` runs, `PROMPT_COMMAND=…`/`BASH_ENV=…` run text later in this shell, and zsh's
/// `functions[claude]=…` rebinds a function through a **subscripted** assignment, which the name
/// check used to miss because it stopped at the `[`.
private func looksLikeAnAssignment(_ word: String) -> Bool {
    guard let equals = word.firstIndex(of: "=") else { return false }
    var name = word[word.startIndex..<equals]
    if name.hasSuffix("+") { name = name.dropLast() }
    // What is inside the brackets does not matter — the name in front of them is assigned to
    if name.hasSuffix("]"), let bracket = name.firstIndex(of: "[") {
        name = name[name.startIndex..<bracket]
    }
    guard let first = name.first, first.isLetter || first == "_" else { return false }
    return name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
}

/// Whether one prompt argument can be appended to the command — a **whitelist syntax scanner**.
///
/// The previous rule looked only at "is the last segment's token `claude`", justified by "the
/// worst a misjudgement can do is drop the prompt silently". **Reproductions proved that false**
/// (external reviewers):
///  - `echo ready # && claude` → the last token is `claude`, but all of it is a comment (silent loss)
///  - `cat <<claude` … `claude` → that `claude` is the heredoc **terminator**. Appending an
///    argument changes the terminator and the shell hangs waiting for input (breakage)
///  - `claude() { /bin/sh -c "$1"; }` ⏎ `claude` → a **function** defined earlier captures the
///    name, and the plain-text input we appended is **executed as a shell command** (arbitrary
///    execution)
///  - `function claude { eval "$@"; }; claude` — the same thing with **no parentheses at all**,
///    which is why the judgement is not a list of definition syntaxes but a list of
///    command-position words (`commandPositionWordsThatFold`)
///
/// So the whole command is scanned instead of just its tail, and **anything outside quotes that
/// is not on the whitelist folds the judgement** (→ inject everything, i.e. today's behaviour).
/// What is allowed is a run of simple commands joined by `&&`, `||`, `;` or `|`, plus groups
/// (`{ }`) and subshells (`( )`); each of their command-position words has to be an ordinary,
/// readable name, and the **last simple command must be exactly the single word `claude`**.
///
/// Flags fold for a separate, measured reason: `claude -p --resume "Reply with exactly: OK"` →
/// `Provided value … is not a UUID`. A flag that optionally takes a value swallows our argument,
/// and knowing which flags do that needs claude's flag table, which changes between versions.
public func commandAcceptsAppendedClaudePrompt(_ command: String) -> Bool {
    let chars = Array(command)
    // A group's or subshell's brackets also separate commands, so they help find the last segment
    let separators: Set<Character> = ["&", "|", ";", "(", ")", "{", "}"]
    var index = 0
    var lastSeparatorWasPipe = false
    var previous: Character?          // previous character, spaces included — for comments
    var previousMeaningful: Character? // previous non-space character — for function definitions
    var word: ShellWord?
    var segment: [ShellWord] = []
    var segments: [[ShellWord]] = []

    /// Are we at the first character of a word? `#` only starts a comment here (`echo a#b` is literal)
    func atWordStart() -> Bool {
        guard let previous else { return true }
        return previous.isWhitespace || separators.contains(previous)
    }
    func endWord() {
        if let word { segment.append(word) }
        word = nil
    }
    func endSegment() {
        endWord()
        segments.append(segment)
        segment = []
    }
    func extend(_ character: Character? = nil, opaque: Bool = false) {
        var current = word ?? ShellWord()
        if let character { current.text.append(character) }
        current.opaque = current.opaque || opaque
        word = current
    }

    while index < chars.count {
        let character = chars[index]
        if character == "'" {
            // No escapes inside single quotes — everything up to the next `'` is data
            var scan = index + 1
            while scan < chars.count, chars[scan] != "'" { scan += 1 }
            guard scan < chars.count else { return false } // unterminated quote: cannot judge
            extend(opaque: true)
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
            extend(opaque: true)
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
        if !separators.contains(character) {
            // Only a space or a tab separates words. Every other whitespace is part of the name:
            // `claude\r` is a **different command** and fails with "command not found" once we
            // have appended to it, and a non-breaking space is not a separator either
            switch character {
            case " ", "\t": endWord()
            case _ where character.isWhitespace: return false
            case "$": extend(character, opaque: true) // `$VAR` — the name is not in the text
            default: extend(character)
            }
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
        endSegment()
        previous = run.last
        previousMeaningful = run.last
    }
    endSegment()

    if lastSeparatorWasPipe { return false } // claude on the receiving end of a pipe has no TUI
    // **Every word is judged as if it were the command name.** Reading only the first word meant
    // deciding where the command position is, and redirections and precommand modifiers move it
    // (`commandPositionWordsThatFold`)
    for word in segments.joined() {
        if word.opaque { return false }
        if commandPositionWordsThatFold.contains(word.text) { return false }
        if looksLikeAnAssignment(word.text) { return false }
    }
    guard let last = segments.last, last.count == 1, !last[0].opaque else { return false }
    return last[0].text == claudeExecutableName
}

// MARK: - Prompt assembly script

/// The shell that pre-runs the `!` bodies and assembles the message. claude's own `!` runs in its
/// Bash tool, so `sh` is closer to today's semantics than the user's interactive shell (zsh and
/// friends) would be — with the same consequence that shell functions like zoxide's `z` are
/// unavailable here, exactly as they are unavailable to claude's `!`.
let claudePromptShell = "/bin/sh"

/// Shells that can run the appended text. **csh and tcsh have no `$( )`**: the append is a parse
/// error there and the shell throws away the whole line, so even the part in front of `&&` — the
/// user's actual command — never runs (measured: `/bin/tcsh -c 'echo START; echo -- "$(/bin/echo
/// hi)"'` prints no START). Merging must not be able to break a command that works today.
///
/// Unknown names type instead of merging, the same fallback everything else uses. fish is left out
/// on purpose: `{ }` grouping and `[ … ]` differ enough there that the shipped presets do not run
/// in it at all.
let posixFamilyShellNames: Set<String> = [
    "sh", "bash", "zsh", "dash", "ksh", "ksh93", "mksh", "ash", "yash",
]

/// Judged from the **account's login shell**, which is the best signal the app has: the pane's
/// shell is chosen by the terminal and can differ (WezTerm's fallback runs `/bin/bash` outright).
/// Being wrong in the safe direction costs a merge; being wrong the other way would cost the
/// command, which is why an unrecognised shell does not merge.
public func shellCanRunAppendedPrompt(_ shellPath: String) -> Bool {
    posixFamilyShellNames.contains((shellPath as NSString).lastPathComponent)
}

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
public func claudePromptScriptBody(
    prefix: [String], contextPath: String,
    argvSlack: Int = claudeArgvBudgetSlack
) -> String {
    let printf = ShellUtility.printf
    let handoff = claudePromptHandoffPath(forContext: contextPath)
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
        // **`set -C` stays on for the whole script.** It used to be switched off right here, and
        // the hand-off marker written further down was a bare `>` again — which followed a
        // planted symlink and truncated the file behind it (reproduced). Nothing below needs
        // clobbering: every other redirect is a read
        //
        // Two layers: even in a shell where `set -C` does not stop it, a symlink stops here.
        // Testing `-s` first would pass on the grounds that **someone else's file** behind the
        // link is non-empty, and that content would go out as the prompt. And since a failed
        // redirect still lets the shell continue to the next line (measured), leaving 0 bytes
        // alone would **submit an empty string as claude's opening message** — failing instead
        // lets the `|| printf <claudePromptLostInstruction>` on the append side speak
        "if [ -L \"$TC_CTX\" ] || [ ! -f \"$TC_CTX\" ] || [ ! -s \"$TC_CTX\" ]; then exit 1; fi",
    ]
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
        // marker makes the sweep wait much longer.
        //
        // The same two layers as the context file, for the same reason: this used to be a bare
        // `>` after `set +C` and it **followed a planted symlink and truncated the file behind
        // it** (reproduced). `-L` first, and the redirect itself is `O_EXCL` because `set -C` is
        // still on. `|| :` because failing to leave a marker must not fail the script — the
        // pointer text is already on stdout, and swallowing the status here keeps the append
        // side's `|| printf <lost>` from firing on top of a prompt that is perfectly fine
        "if [ ! -L \(shellSingleQuoted(handoff)) ]; then : > \(shellSingleQuoted(handoff))"
            + " 2>/dev/null || :; fi",
        "fi",
        "",
    ]
    return lines.joined(separator: "\n")
}

/// Rewrites a trailing `claude` into `command claude`, or nil when the command does not end in
/// that word.
///
/// **This is the structural half of "our prompt is never executed as shell code".** A `claude`
/// **function or alias** — the shape both reviewers used to get a plain-text input executed, and
/// the shape that is invisible to any scanner when it comes from the user's rc — receives our
/// prompt as `$1` and can do what it likes with it. `command` is POSIX for "skip functions and
/// aliases, run the executable", and the name after it is not in alias-expansion position either.
/// So instead of detecting wrappers we stop handing them the prompt.
///
/// The cost, accepted deliberately: someone who wraps `claude` on purpose (extra flags, an env
/// var) loses that wrapper **on the merge path only** — commands with no claude input, and the
/// typed route, are untouched, and naming the wrapper anything else keeps it. The alternative was
/// to keep feeding wrappers and rely on spotting the dangerous ones, which is the blacklist this
/// round removed. What it does not cover: `command` itself rebound in the rc, and a PATH that
/// resolves `claude` to another program.
private func invokingClaudeDirectly(_ trimmed: String) -> String? {
    guard trimmed.hasSuffix(claudeExecutableName) else { return nil }
    let head = String(trimmed.dropLast(claudeExecutableName.count))
    // Only when `claude` is a whole word — a stand-in like `myclaude` must not be cut in half
    if let last = head.last, !(last == " " || last == "\t" || "&|;({".contains(last)) { return nil }
    return head + "command " + claudeExecutableName
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
    // `prepareRequest` only ever passes a command whose last word is a bare `claude`
    // (`commandAcceptsAppendedClaudePrompt`); anything else keeps its own last word, so a
    // stand-in used in a test still runs and simply does not get the wrapper bypass
    let invocation = invokingClaudeDirectly(trimmed) ?? trimmed
    return invocation + " -- \"$(\(claudePromptShell) \(quoted)"
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
    // Lower case only. The app formats tokens with `%08x` and `uninstall.sh` matches
    // `[0-9a-f]{8}` — a name neither of them writes is somebody else's directory
    return token.count == claudePromptTokenLength
        && token.allSatisfy { $0.isNumber || ("a"..."f").contains($0) }
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
/// failure has actually been reproduced. So reclaiming happens here alone, and it asks whether the
/// directory has been **used up** rather than only how old it is:
///  - `prompt.sh` gone ⇒ the substitution ran, the content is already in claude's argv. Nobody
///    needs the directory after that, so the short age (6 hours by default) applies
///  - `prompt.sh` still there ⇒ **nothing has consumed it**. Age cannot tell "has not run yet"
///    from "died unused", and it got the first one wrong: with `sleep 21601 && claude` the script
///    was still waiting six hours later and another request's sweep took it, so the command
///    finally started claude with the lost-context notice (reproduced). Unconsumed directories get
///    the long age, which costs almost nothing — until the script runs, the directory holds only
///    the script; the assembled context is written by the script itself
///  - **Hand-off marker present** ⇒ the over-budget branch told claude to read that file *during*
///    the session, so it has to outlive the six hours as well
func reclaimStaleClaudePromptDirectories(
    in directory: String = NSTemporaryDirectory(),
    consumedAge: TimeInterval = 6 * 3600, unfinishedAge: TimeInterval = 7 * 24 * 3600
) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where claudePromptDirectoryIsOurs(name: name) {
        let path = (directory as NSString).appendingPathComponent(name)
        var info = stat()
        // Never follow a symlink — following one would delete the whole directory it points at
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
        func contains(_ file: String) -> Bool {
            var entry = stat()
            return lstat((path as NSString).appendingPathComponent(file), &entry) == 0
        }
        let unfinished = contains(claudePromptScriptName) || contains(claudePromptHandoffName)
        let age = unfinished ? unfinishedAge : consumedAge
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        guard Date().timeIntervalSince(modified) > age else { continue }
        // Look once more immediately before removing. Between the listing above and this line a
        // pane can start consuming the directory, and **every way of consuming it changes the
        // directory's own mtime**: creating `context.txt`, dropping the hand-off marker, the
        // script deleting itself. So an unchanged mtime is a cheap "nothing has happened since I
        // looked", and it narrows the window from the whole sweep to one syscall. It cannot be
        // closed from here — the consumer is a shell we do not control
        var current = stat()
        guard lstat(path, &current) == 0,
              current.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec else { continue }
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Claims the request's own directory, `drwx------`, with **one `mkdir(2)`**. `FileManager`'s
/// `attributes:` is a `mkdir` followed by a `chmod`, so only the name is atomic and the directory
/// exists at the process umask for the moment in between. Harmless while `$TMPDIR` is itself
/// 0700, but the script and the assembled context live here and the guarantee should not lean on
/// that. umask can only take bits away, never add them, so this is never *wider* than 0700 —
/// which is the property that matters (`testRequestGetsItsOwnFreshDirectory` pins the exact mode
/// for the ordinary umasks; an owner-masking umask would break far more than this).
private func claimPrivateDirectory(_ path: String) -> Bool {
    mkdir(path, 0o700) == 0
}

/// Turns a request into the form that will actually run. Either **every** scheduled input merges
/// into claude's opening message (argv), or **none** does and they are all typed — today's
/// behaviour. There is no third state.
///
/// **Why not merge the longest prefix and type the rest** (round 4). Doing both in one session
/// means racing claude's own startup: submitting the argv message clears the input box, so a tail
/// typed before that message renders is wiped (measured), and the only signals available from
/// outside are ones the user's shell can forge — a zsh with `set -x` prints the substituted argv,
/// including any marker we put in it, right before the exec, and it can print it more than once.
/// Two independent reviewers drove the production path into recording a wiped input as delivered.
/// A gate cannot be made sound without either typing bytes before we know claude owns the input
/// box (a new hazard: those keystrokes reach the trust dialog) or reading claude's internal
/// session files. Removing the combination removes the race, and it costs nothing that exists
/// today: a mixed configuration simply behaves the way it did before the argv track existed.
/// (Design candidates and their failure modes are recorded in the plan file.)
///
/// It does not throw: this conversion cannot fail a request. Not being able to write the temp
/// files is a fallback, not a rejection — throwing here would make a request that works today
/// fail because of the state of the disk.
///
/// That fallback does reach a rejection **on Warp without the Accessibility permission**, because
/// everything then has to be typed and the precondition gate refuses to open a tab it cannot
/// deliver into. Kept deliberately: the alternative is running the command with the context
/// silently missing, which is the symptom this whole route exists to remove. The user sees ❌ and
/// the log line above says the cause was the temp file, not the permission.
public func prepareRequest(
    _ resolved: ResolvedRequest, loginShell: String = loginShellPath(),
    claudeIsExecutable: Bool = true
) -> PreparedRequest {
    func injectEverything() -> PreparedRequest {
        PreparedRequest(
            command: resolved.command, claudeInputs: resolved.claudeInputs,
            temporaryDirectory: nil
        )
    }
    // Reclaim leftovers from earlier runs the app died in the middle of (age decides, so nothing
    // still in use is touched). **Before the guard, not after**: the sweep used to run only for
    // requests that were about to merge, so a user who never sends another mergeable request kept
    // `context.txt` — PR and issue bodies, and `!` output — forever. Every request sweeps now
    reclaimStaleClaudePromptDirectories()

    let plan = claudeInputPlan(resolved.claudeInputs)
    guard !plan.prefix.isEmpty, plan.tail.isEmpty, claudeIsExecutable,
          commandAcceptsAppendedClaudePrompt(resolved.command),
          shellCanRunAppendedPrompt(loginShell) else {
        return injectEverything()
    }

    let token = claudePromptToken()
    let directory = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("\(claudePromptDirectoryPrefix)\(token)")
    // `mkdir` fails if the name is taken — that is what makes the claim atomic, and it means a
    // link or directory someone else left under that name is never adopted as ours
    guard claimPrivateDirectory(directory) else {
        checkoutLog("프롬프트 작업 디렉토리를 만들지 못해 claude 입력 \(resolved.claudeInputs.count)개를 주입 경로로 보낸다")
        return injectEverything()
    }
    let scriptPath = (directory as NSString).appendingPathComponent(claudePromptScriptName)
    let contextPath = (directory as NSString).appendingPathComponent(claudePromptContextName)
    let body = claudePromptScriptBody(prefix: plan.prefix, contextPath: contextPath)
    guard writeNewPrivateFile(path: scriptPath, contents: body) else {
        checkoutLog("프롬프트 조립 스크립트를 쓰지 못해 claude 입력 \(resolved.claudeInputs.count)개를 주입 경로로 보낸다")
        try? FileManager.default.removeItem(atPath: directory)
        return injectEverything()
    }
    return PreparedRequest(
        command: appendedPromptCommand(resolved.command, scriptPath: scriptPath),
        claudeInputs: [],
        temporaryDirectory: directory
    )
}
