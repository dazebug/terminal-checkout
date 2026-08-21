import Foundation

// Decides how the scheduled claude inputs reach claude.
//
// **A `!` input is typed into claude's own shell mode — never pre-run and pasted.** The app used
// to run those lines in the pane's shell and hand claude the captured output as its opening
// message; that is gone (user decision, round 10). Measured on 2.1.238 in a pty: `claude --
// '!echo x'` does **not** enter shell mode. The line arrives as an ordinary message and claude
// then runs it through its Bash tool — which can stop for a permission prompt, is a model
// judgement rather than a shell fact, and spends a turn. Typing it means the command really runs
// in that session and stays in its history as a command.
//
// What is left to optimise is **cycles, not routes**: a run of consecutive `!` inputs is typed as
// one line joined with `;`, so three inputs cost one type/submit cycle instead of three. And a
// list that is nothing but plain text still rides in argv, because plain text is just a message.

// MARK: - What the inputs turn into

/// What one input is.
private enum ClaudeInputKind {
    /// Starts with `!` — claude's shell mode. Typed, and merged with its neighbours
    case shellCommand
    /// A line the **input box** reads specially: `/` dispatches a slash command, `#` files the
    /// line into memory. Neither meaning exists anywhere but the box, so it is typed alone
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

/// Attribution a merged `!` line prints before each command. With several outputs running
/// together, claude cannot otherwise tell which command produced what — and a lone `!` needs none,
/// because claude's shell mode already shows the command it ran.
func claudePromptBanner(for input: String) -> String { "==== \(input) ====" }

/// The banner is printed by **absolute path**. `echo` is a builtin the *previous* body on the
/// merged line could have redefined (`echo() { :; }`), and a function or an alias cannot take over
/// a name containing `/` — the same reasoning the pre-execution script used to apply to every
/// utility it called. `/bin/echo` exists on macOS and Linux; claude's shell mode runs there.
let claudeBannerCommand = "/bin/echo"

/// The largest merged line we will produce. The Warp helper refuses an injection payload over
/// 8 KiB in one request (`injectMaxBytes`), and merging is an optimisation, so it gives way well
/// before that: past this the run is typed input by input, each far below the limit. Nothing is
/// truncated either way.
///
/// The ceiling is **not** about the reflection probe: a 4,000-character line still shows its first
/// 24 characters in the composer, which grows vertically (measured, 2.1.238).
let claudeMergedLineLimit = 4096

/// Can this `!` body be joined to another with `; ` without changing what it means?
///
/// A **whitelist walk, not a shell parser** — parsing the user's shell is a road this repository
/// has refused twice. The body passes only if the scan reaches its end seeing nothing that could
/// reach past it. Everything below was reproduced or is the same class:
///  - `#` at a word start — comments out the rest of the **merged line**, later banners included
///  - a lone `&` — `… &; …` is a syntax error, so the whole line runs nothing
///  - `<<` / `<<-` — a heredoc eats what follows as its content
///  - a newline, a trailing backslash, an unterminated quote — the join splices two commands
///  - `(`, `)`, `{`, `}`, a backtick, `$(` — grammar this scan does not model, and a function
///    definition in one body would still be live when the next banner runs
///  - an empty body, or one ending in an operator (`;`, `|`, `&`, `\`) — the join yields `;;`
///    or `; ;`, a parse error, so **nothing on the line runs** (measured in bash and zsh)
///  - a word starting with `=` — bash shrugs, zsh expands it and aborts the line. claude's `!`
///    shell **is** zsh-family (measured: a missing command reports `(eval):1: command not found`),
///    so this one is not hypothetical
///  - a word that **changes shell state** (`cd`, `export`, `set`, `alias`, `source`, an assignment
///    …). Measured (Q2b): separate `!` submissions share no state — `!export X=1` then `!echo $X`
///    prints nothing, because each `!` is a fresh eval — while a merged line does share it. That
///    is a difference in what runs, not in speed: `["!cd sub", "!rm -rf build"]` removes `./build`
///    typed separately and `sub/build` merged. Deleting the wrong directory is the failure class
///    this project treats as blocking, so those runs are typed one at a time.
///    A quoted command name (`'cd' sub`) is not caught — the scan cannot read inside quotes, and
///    rejecting every quoted word would break the shipped presets' `--jq '…'`
///
/// Anything unrecognised is *rejected*, which costs speed and never correctness: that run is typed
/// one input at a time, exactly as it was before merging existed.
/// Words that make a body's meaning depend on — or leak into — the commands around it. Read
/// anywhere in the body, for the same reason the append scanner reads every word: this scan does
/// not model command positions, and over-folding only costs a cycle.
private let claudeStateChangingWords: Set<String> = [
    "cd", "pushd", "popd", "chdir",
    "export", "unset", "set", "setopt", "shopt", "declare", "typeset", "local", "readonly",
    "alias", "unalias", "hash", "trap", "umask", "ulimit",
    "source", ".", "eval", "exec",
]

func claudeBodyJoinsSafely(_ body: String) -> Bool {
    let trimmed = body.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty, let last = trimmed.last, !"&|;\\".contains(last) else { return false }
    let chars = Array(trimmed)
    var index = 0
    var previous: Character?
    var word = ""
    var wordIsOpaque = false
    var stateChanges = false

    func endWord() {
        defer { word = ""; wordIsOpaque = false }
        guard !wordIsOpaque, !word.isEmpty else { return }
        if claudeStateChangingWords.contains(word) || looksLikeAnAssignment(word) {
            stateChanges = true
        }
    }
    while index < chars.count {
        let character = chars[index]
        if character == "'" {
            var scan = index + 1
            while scan < chars.count, chars[scan] != "'" { scan += 1 }
            guard scan < chars.count else { return false } // unterminated
            index = scan + 1
            previous = "'"
            wordIsOpaque = true
            continue
        }
        if character == "\"" {
            var scan = index + 1
            while scan < chars.count {
                if chars[scan] == "\\" {
                    scan += 2
                    continue
                }
                if chars[scan] == "`" { return false }
                if chars[scan] == "$", scan + 1 < chars.count, chars[scan + 1] == "(" { return false }
                if chars[scan] == "\"" { break }
                scan += 1
            }
            guard scan < chars.count else { return false } // unterminated
            index = scan + 1
            previous = "\""
            wordIsOpaque = true
            continue
        }
        switch character {
        case "\n", "`", "(", ")", "{", "}":
            return false
        case "\\":
            guard index + 1 < chars.count else { return false }
            index += 2
            previous = "\\"
            continue
        case "#" where previous.map(\.isWhitespace) ?? true:
            return false
        case "$" where index + 1 < chars.count && chars[index + 1] == "(":
            return false
        case "=" where previous.map(\.isWhitespace) ?? true:
            return false // zsh expands a word starting with `=` and aborts the line
        case "<" where index + 1 < chars.count && chars[index + 1] == "<":
            return false
        case "&":
            var run = 0
            while index + run < chars.count, chars[index + run] == "&" { run += 1 }
            guard run == 2 else { return false } // `&&` joins; a single `&` backgrounds
            endWord() // `git fetch && cd ..` — the word after the operator is a command too
            index += run
            previous = "&"
            continue
        case ";", "|":
            endWord()
            index += 1
            previous = character
            continue
        default:
            break
        }
        if character.isWhitespace {
            endWord()
        } else {
            word.append(character)
        }
        index += 1
        previous = character
    }
    endWord()
    return !stateChanges
}

/// Everything that gets typed, in order, with **consecutive `!` inputs merged into one line**.
///
/// The merged shape is `!echo '<banner>'; body; echo '<banner>'; body`. Two things about it are
/// deliberate:
///  - **`;`, not `&&`.** Separate `!` inputs each ran on their own, so a failure never stopped the
///    next one; `;` is what keeps the merged line equivalent to what the user had.
///  - **The bodies are the user's own shell text**, single-quoted nowhere — that is what `!` means.
///    Only the banner, which is ours, is quoted (`shellSingleQuoted`), so nothing we add can be
///    read as syntax.
///
/// No length cap: this is typed into a TUI, so `ARG_MAX` does not apply, the reflection check
/// looks at a 24-character prefix, and truncating would silently change a command the user wrote.
public func claudeTypedInputs(_ inputs: [String]) -> [String] {
    var typed: [String] = []
    var run: [String] = []

    func flushRun() {
        defer { run = [] }
        guard !run.isEmpty else { return }
        guard run.count > 1 else { return typed.append(run[0]) }
        let bodies = run.map { String($0.dropFirst()).trimmingCharacters(in: .whitespaces) }
        // **Merge only what provably joins.** One body that reaches past its own end — a comment,
        // a trailing `&`, a heredoc — takes the whole merged line with it, and the button still
        // reports success because delivery is asynchronous (reproduced). When in doubt, type them
        // one at a time: slower, and exactly what the user wrote
        guard bodies.allSatisfy(claudeBodyJoinsSafely) else { return typed.append(contentsOf: run) }
        let parts = zip(run, bodies).flatMap { input, body in
            ["\(claudeBannerCommand) \(shellSingleQuoted(claudePromptBanner(for: input)))", body]
        }
        let merged = "!" + parts.joined(separator: "; ")
        guard merged.utf8.count <= claudeMergedLineLimit else { return typed.append(contentsOf: run) }
        typed.append(merged)
    }

    for input in inputs {
        switch ClaudeInputKind(input) {
        case .shellCommand:
            run.append(input)
        default:
            flushRun()
            typed.append(input)
        }
    }
    flushRun()
    return typed
}

/// The opening message for claude's argv, or nil when there is none.
///
/// **Exactly one** plain-text input, and nothing else in the list.
///
/// Two reasons, and they are different:
///  - *Nothing else in the list*: mixing argv with typing in one session is the combination round 4
///    removed on a measurement — submitting the argv message clears the input box, and it renders
///    2.06∼3.41s after start while "claude accepts input" is true from 0.1s, so anything typed in
///    between is wiped (3/3). No gate over that race survived review.
///  - *Exactly one*: several plain inputs used to be joined with blank lines, and the newline guard
///    in `prepareRequest` then rejected the result — so they could never ride argv anyway; the join
///    was dead code wearing a feature's clothes (round 11). Carrying a newline through would mean
///    shell-specific quoting (`$'…'` is not POSIX) and a new way to be wrong about the pane's
///    shell, to save typing on a shape the shipped presets do not have. They are typed instead.
public func claudeArgvOpeningMessage(_ inputs: [String]) -> String? {
    guard inputs.count == 1, let only = inputs.first,
          ClaudeInputKind(only) == .interactive else { return nil }
    return only
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

// MARK: - Where the append may go

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

/// **Legacy names.** Until round 10 a request owned a directory here: a script that pre-ran the
/// `!` inputs and the context file it assembled. Nothing creates those any more — `!` is typed
/// into claude's shell mode instead — but installations that ran the older build left directories
/// behind, so the sweep below (and `uninstall.sh`) still recognises and clears them.
let claudePromptDirectoryPrefix = "tc-prompt-"
let claudePromptTokenLength = 8
let claudePromptScriptName = "prompt.sh"
/// Marked a context an older build had told claude to read during the session, which is why such
/// a directory gets a much longer grace period from the sweep
let claudePromptHandoffName = "handed-to-claude"

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

/// Appends the opening message to the command as claude's first positional argument.
///
/// There is no command substitution and no temporary file any more: the message is plain text the
/// user wrote, so it goes in single-quoted and nothing in it is ever evaluated by the shell
/// (`shellSingleQuoted` escapes the quotes themselves). What survives from the earlier design is
/// the invocation: **`command claude`** so a wrapper of that name cannot receive the message, and
/// the **`--`** so no flag can swallow it (measured: variadic flags do).
public func appendedPromptCommand(_ command: String, message: String) -> String {
    let trimmed = command.replacingOccurrences(
        of: "[ \t]+$", with: "", options: .regularExpression
    )
    return (invokingClaudeDirectly(trimmed) ?? trimmed) + " -- " + shellSingleQuoted(message)
}

// MARK: - Request preparation

/// A request prepared up to the moment of execution.
public struct PreparedRequest {
    /// The final command for the terminal (an all-plain-text input list may be appended to it)
    public let command: String
    /// Inputs for the typing path, `!` runs already merged. **Empty means neither the Warp helper
    /// nor the Accessibility permission is needed** — which, since round 10, is only true for
    /// buttons whose inputs are all plain text or have none at all
    public let claudeInputs: [String]
}

/// Is this a name we may reclaim — our prefix plus an **exactly 8 character** hex token? Without
/// the length check someone else's `tc-prompt-a` would count as ours.
func claudePromptDirectoryIsOurs(name: String) -> Bool {
    guard name.hasPrefix(claudePromptDirectoryPrefix) else { return false }
    let token = name.dropFirst(claudePromptDirectoryPrefix.count)
    // **ASCII** lower-case hex only. The app formats tokens with `%08x` and `uninstall.sh` matches
    // `[0-9a-f]{8}`, so a name neither of them writes is somebody else's directory — and
    // `Character.isNumber`/`isHexDigit` are Unicode-wide, which let a token of Arabic-Indic digits
    // pass as hex (reproduced: `tc-prompt-١٢٣٤abcd` was reclaimable)
    return token.count == claudePromptTokenLength && token.allSatisfy(\.isASCIIHexLower)
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
///
/// `justBeforeRemoving` is a **test seam**: the race this narrows cannot be exercised from outside
/// the process, and a race with no test is a race that comes back.
func reclaimStaleClaudePromptDirectories(
    in directory: String = NSTemporaryDirectory(),
    consumedAge: TimeInterval = 6 * 3600, unfinishedAge: TimeInterval = 7 * 24 * 3600,
    justBeforeRemoving: (String) -> Void = { _ in }
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
        // looked", and it narrows the window from the whole sweep to one syscall.
        //
        // **Nanoseconds, not seconds** — a consumer that started inside the same second was
        // invisible to a `tv_sec` comparison (reproduced through `justBeforeRemoving`). The inode
        // is compared too: a directory replaced by another one is not the one we judged.
        // The window cannot be closed from here; the consumer is a shell we do not control
        justBeforeRemoving(path)
        var current = stat()
        guard lstat(path, &current) == 0,
              current.st_ino == info.st_ino,
              current.st_mtimespec.tv_sec == info.st_mtimespec.tv_sec,
              current.st_mtimespec.tv_nsec == info.st_mtimespec.tv_nsec else { continue }
        try? FileManager.default.removeItem(atPath: path)
    }
}

/// Turns a request into the form that will actually run: what the terminal is asked to execute,
/// and what will be typed into the session afterwards.
///
/// `!` inputs are always typed (see the top of this file). A list that is **nothing but plain
/// text** can instead ride in claude's argv, and then there is nothing left to type — the two are
/// never mixed, because the argv message's own submission clears the input box seconds after
/// claude starts and would wipe whatever we typed in the meantime (measured; round 4 removed the
/// combination and no gate over it survived review).
///
/// It does not throw: this conversion cannot fail a request.
public func prepareRequest(
    _ resolved: ResolvedRequest, loginShell: String = loginShellPath(),
    claudeIsExecutable: Bool = true
) -> PreparedRequest {
    // Clear out directories an **older build** left in the temp directory (it pre-ran `!` inputs
    // into files there). Nothing creates them now; this is the last thing that cleans them up
    reclaimStaleClaudePromptDirectories()

    let typed = claudeTypedInputs(resolved.claudeInputs)
    guard let message = claudeArgvOpeningMessage(resolved.claudeInputs), claudeIsExecutable,
          commandAcceptsAppendedClaudePrompt(resolved.command),
          shellCanRunAppendedPrompt(loginShell),
          // A newline would end the command line early: iTerm2 writes it with `write text` and
          // WezTerm with `send-text`, and both treat a newline as "run this now"
          !message.contains("\n") else {
        return PreparedRequest(command: resolved.command, claudeInputs: typed)
    }
    return PreparedRequest(
        command: appendedPromptCommand(resolved.command, message: message), claudeInputs: []
    )
}
