import Foundation

/// Checks whether the tools a command template calls can actually be called in the user's shell.
/// Why ask the shell rather than search the filesystem: `z` is a shell function zoxide defines in an rc file, so there is no executable at any path, and a GUI app's PATH differs from the login shell's anyway.

/// What is checked by default. `z` is the first word of the default command template, so without it every button fails; `gh` and `claude` are used only by the issue preset and by claude input respectively.
public let checkedTools = ["z", "gh", "claude"]

/// Whether missing this tool means "every button fails" — how the setup window splits error (red)
/// from warning (yellow).
///
/// Only `z` depends on whether a base directory is configured. With one, `{cd}`'s fallback
/// (`cd` → `clone`) covers a failing `z` (`BaseDirectory.swift`), so "every button fails" stops
/// being true. `gh` also appears in the clone clause once a base directory is set, but the z and
/// cd branches survive without it, so it stays a warning.
public func toolIsCritical(_ tool: String, baseDirectoryConfigured: Bool) -> Bool {
    tool == "z" && !baseDirectoryConfigured
}

/// The user's login shell. A GUI app's SHELL environment variable is whatever launchd handed down and cannot be trusted, so this reads the account record directly.
public func loginShellPath() -> String {
    if let entry = getpwuid(getuid()) {
        let shell = String(cString: entry.pointee.pw_shell)
        if shell.hasPrefix("/") { return shell }
    }
    return "/bin/zsh"
}

/// The shell script that makes the shell answer two questions per tool, one marker line each.
/// `tools` receives code constants only — putting user input in here would be shell injection.
///
/// `TC_OK` means "typing that name calls something" and **includes functions and aliases** (`z` is exactly that case). `TC_EXE` means **`command <name>` has an actual file to run**. Why they are separate: the merge path invokes `command claude`, and `command` skips functions and aliases, so on an install like `alias claude='npx …'` `TC_OK` is true while the merged command dies with command not found.
///
/// Why `TC_EXE` is asked of a **child `/bin/sh`** (measured):
///  - In the login shell, `command -v` returns just the name when a function or alias shadows it. But if that is a **wrapper around a real file**, `command claude` runs that file — a case where merging is fine. A child shell, which reads no rc, answers with the file itself.
///  - Why `[ -x ]` is needed: bash's and dash's `command -v` return an absolute path even for a file **without the executable bit** (zsh and /bin/sh do not). Going by the shape of the path alone, the merge would fail afterwards.
///  - Why it is asked from `cd /`: if PATH holds a **relative** entry, the resolution depends on the cwd. The pane's cwd (after the command has `cd`ed) is unknowable, so if it does not resolve from `/` we do not merge.
public func toolCheckScript(_ tools: [String]) -> String {
    // A relative `PATH` entry (or an empty one, which means the working directory) resolves
    // against a cwd we cannot know — the pane's, after the command has `cd`ed. One of those and
    // the executable answer is worthless, so it disqualifies the whole answer.
    //
    // **A trailing colon is not caught, on purpose** (measured; the split produces no trailing
    // empty element):
    //
    //     PATH=/usr/bin:/bin   -> TC_REL=[]      PATH=:/usr/bin      -> TC_REL=[rel]
    //     PATH=/usr/bin::/bin  -> TC_REL=[rel]   PATH=/usr/bin:rel   -> TC_REL=[rel]
    //     PATH=/usr/bin:/bin:  -> TC_REL=[]      PATH=.              -> TC_REL=[rel]
    //
    // Why it is left: a trailing colon puts the working directory **last**, and an earlier
    // absolute entry always wins — measured from both `/` and another cwd, the same absolute hit
    // comes back. So the cwd entry can only decide the answer for a name that exists in *no*
    // absolute entry, which for `claude` means a file at the filesystem root.
    //
    // One leg of that argument does **not** hold:
    // "asked from `/`, a cwd hit answers with a relative path and the `/*` gate filters it" is
    // false for the shell we ask — `/bin/sh` (bash 3.2 here) absolutises it (`/./claude`), while
    // bash, zsh and dash return `./claude` or `claude`. So the residual is real: with `/claude`
    // present and `claude` nowhere on the absolute PATH, we would answer "executable" and the pane
    // would fail. The mirror case is a pane whose `z` command enters a repository that happens to
    // contain an executable `./claude`, so the check and the run resolve **different files** —
    // it needs a PATH ending in `:` *and* that file, and it does not hold otherwise.
    // Both failures are visible `command not found` or a wrong-but-user-owned program (a lost
    // input, not a misdelivered one), whereas treating every trailing colon as relative would
    // silently cost the merge — and on Warp without the permission, the whole request — to
    // everyone whose PATH merely ends in a stray `:`. The rarer, visible failure is the one we keep
    // Split with `${}` rather than word splitting: **zsh does not split an unquoted parameter**,
    // so `for d in $PATH` looped once over the whole string and this guard did nothing in the
    // shell most macOS users log in with. Measured, all four shells and six PATHs, before/after:
    //
    //     `for d in $PATH`   sh/bash/dash agree · **zsh answers [] for every PATH, including `.`**
    //     `${p%%:*}` loop    sh, bash, zsh, dash all agree, and the table below is unchanged
    //
    // The patterns carry a leading `(`: inside `$( )`, bash 3.2 — which is `/bin/sh` on macOS —
    // mis-parses a bare `pattern)` in a `case` and dies with a syntax error (measured)
    let relative = "TC_REL=$(p=\"$PATH\"; while [ -n \"$p\" ]; do e=${p%%:*};"
        + " case \"$e\" in (/*) : ;; (*) printf rel; break ;; esac;"
        + " case \"$p\" in (*:*) p=${p#*:} ;; (*) p= ;; esac; done)"
    let checks = tools.flatMap { tool in
        [
            "TC_PATH=$(command -v \(tool) 2>/dev/null) && echo TC_OK:\(tool)",
            "TC_EXE_PATH=$(cd / && /bin/sh -c 'command -v \(tool)' 2>/dev/null)",
            "case \"$TC_EXE_PATH\" in /*) [ -z \"$TC_REL\" ] && [ -x \"$TC_EXE_PATH\" ]"
                + " && echo TC_EXE:\(tool) ;; esac",
        ]
    }
    return ([relative] + checks + ["echo TC_DONE"]).joined(separator: "\n")
}

/// Turns the marker output into a per-tool result. When the script did not run to the end (no completion marker) the answer is nil — treating a dead shell the same as a missing tool is how a perfectly fine environment gets a warning.
public func parseToolCheck(output: String, tools: [String]) -> [String: Bool]? {
    parseToolMarker("TC_OK:", output: output, tools: tools)
}

/// Reads only "does it resolve to an executable" out of the same output — a different fact from the setup window's ✅ (can it be called), so it is answered separately.
public func parseToolExecutables(output: String, tools: [String]) -> [String: Bool]? {
    parseToolMarker("TC_EXE:", output: output, tools: tools)
}

private func parseToolMarker(_ prefix: String, output: String, tools: [String]) -> [String: Bool]? {
    var found = Set<String>()
    var completed = false
    for rawLine in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasSuffix("TC_DONE") { completed = true }
        // Shell integration (iTerm2 and friends) prepends escape sequences to the first line, so the search discards whatever comes before the marker
        guard let marker = line.range(of: prefix, options: .backwards) else { continue }
        found.insert(String(line[marker.upperBound...]))
    }
    guard completed else { return nil }
    return Dictionary(uniqueKeysWithValues: tools.map { ($0, found.contains($0)) })
}

/// The two halves of a tool check. `available` is the setup window's ✅ (can that name be called), `executable` is the fact the merge path needs (does that name resolve to an executable file).
public struct ToolCheckResult: Equatable {
    public let available: [String: Bool]
    public let executable: [String: Bool]
}

/// How the shell is launched to be asked — **the one shape a tab actually opens** (login + interactive).
///
/// The justification is the default of all three terminals we support: WezTerm prefixes argv0 with `-` and launches a **login shell** (its "Launching Programs" documentation, and discussion #4544 which explains why), iTerm2's default profile command is "Login shell", and Warp launches the user's login shell too. The shell inside a tab is an interactive login shell, so that is how we ask.
///
/// Measured (by planting rc files in an empty HOME): `bash -l -i -c` → `.bash_profile`, `bash -i -c` → `.bashrc`, `zsh -l -i -c` → `.zshenv .zprofile .zshrc` (so zsh is a superset and does not distinguish them).
///
/// **Use the exact shell form, not a union of startup files.** A union answers "present if it is in
/// any rc", not "does this name run in that pane". It can enable merging for a command that the
/// login shell cannot run, while a non-login pane remains a known limitation shown on the tools card.
///
/// The second candidate is only a fallback for a shell that does not know `-l` (dash) — it is used **only when the first candidate produced no answer at all**. The first candidate answering "the tool is missing" is an answer, so the fallback does not run.
public func toolCheckShellArgumentCandidates(_ script: String) -> [[String]] {
    [["-l", "-i", "-c", script], ["-i", "-c", script]]
}

/// Asks the login shell. This is slow (it loads profiles and rc files), so call it in the background.
/// The limitation that **the login shell may not be the pane's shell** is the same one the whole merge verdict carries (see the `shellCanRunAppendedPrompt` comment) — the rc read here may not be that pane's rc.
public func checkTools(
    _ tools: [String] = checkedTools, timeout: TimeInterval = 20,
    shell: String = loginShellPath(), environment: [String: String]? = nil
) -> ToolCheckResult? {
    let script = toolCheckScript(tools)
    for arguments in toolCheckShellArgumentCandidates(script) {
        guard let result = try? runProcess(shell, arguments, env: environment, timeout: timeout),
              let available = parseToolCheck(output: result.stdout, tools: tools),
              let executable = parseToolExecutables(output: result.stdout, tools: tools) else {
            continue // the shell gave no answer in this shape (no completion marker) — try the next candidate
        }
        return ToolCheckResult(available: available, executable: executable)
    }
    return nil
}
