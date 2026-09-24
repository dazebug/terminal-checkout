import Foundation

/// The base directory — the top-level folder the user clones repositories into.
///
/// Command templates open by moving into the repository. When zoxide has never recorded the
/// repository, that jump exits non-zero and the whole `&&` chain dies (issue #30). The app cannot
/// observe a failure inside the user's shell, so the button still reports success. Hence a fallback
/// rather than detection: if the jump fails, `cd` into the base directory, and if the repository
/// isn't there either, clone it.
///
/// The app owns this value; the extension gets no way to specify it. Paths differ per machine
/// while extension settings ride `storage.sync` across an account — synced, the value would be
/// silently wrong on the other machine.

/// The name of the variable the entry clause fills in. The extension-side source of truth for the
/// same name is `APP_VARIABLES` in `extension/defaults.js`.
public let repoEntryVariable = "cd"

/// Validates and normalizes the stored string. An empty value is not an error but **not
/// configured** (nil) — staying on the old behavior with no fallback is a legitimate state.
///
/// `~` is expanded here. Adding `~` to the allowed characters would let it flow into the shell
/// verbatim, and widening the whitelist for it would split the verdict from the one command
/// variables get. Only surrounding spaces are trimmed, **not newlines** — that is the hole the
/// Python-era regex's `$` left open, and it is not getting reopened here.
public func normalizedBaseDirectory(_ raw: String) throws -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return nil }

    let expanded = (trimmed as NSString).expandingTildeInPath
    guard expanded.hasPrefix("/") else {
        throw CommandError.invalidBaseDirectory(.notAbsolute, trimmed)
    }

    // Strip trailing slashes so the `<base>/<repo>` join never adds a `//` (root stays root). A
    // `//` the user typed *inside* the path survives — the kernel collapses it, and this owns the join
    var path = expanded
    while path.count > 1, path.hasSuffix("/") { path.removeLast() }

    // The value reaches the shell unquoted — it takes the same verdict as a command variable
    guard (try? sanitizeValue(path)) != nil else {
        throw CommandError.invalidBaseDirectory(.invalidCharacters, trimmed)
    }
    return path
}

/// The value of `{cd}` — the clause a command opens with to move into the repository.
///
/// With no base directory configured this is the zoxide jump alone (`zoxideExactJump`). The app
/// assembles the clause instead of the presets carrying a path variable because a path variable
/// would leave every button of an unconfigured user failing with `Variable {basedir} not provided`.
///
/// Configured, it chains jump → `cd` (guarded) → `clone`. The jump coming first is a rule: the base
/// directory must not override a jump zoxide made successfully. The jump exits non-zero both when
/// zoxide has no folder of that exact name and when zoxide is missing (measured), so this one
/// branch covers both.
///
/// The middle clause asks git whether the directory **is a repository** before entering it. Plain
/// `cd` returns 0 for any directory that exists — an empty one, a scratch folder, someone else's
/// checkout — and treating that as "the repository is here" skips the clone and leaves the rest of
/// the preset chain (`git fetch`, `git checkout`) running somewhere the user never asked for
/// (measured: with an empty `<base>/<repo>`, an unguarded chain ends up sitting in it).
///
/// Grouping is `{ …; }` only — `( … )` is a subshell, and `cd` inside one does not stick in the
/// current shell (the jump's one `$( … )` only looks the folder up; its `cd` runs outside it). **stderr is never redirected**: `fatal: not a git repository` and `cannot change
/// to` are what explain the fallback on screen, and hiding them would hide real failures
/// (permissions, and so on) along with them. The `>/dev/null` on the guard is stdout only — the
/// `.git` path git prints on success, which is noise nobody asked for.
///
/// Every ingredient is a validated value — even though callers have validated already, the
/// assembly site checks again. The result of this function is the only thing exempt from
/// `sanitizeValue`, and re-checking the ingredients right here is what earns that exemption.
public func repoEntryCommand(repo: String, owner: String?, baseDirectory: String) throws -> String {
    let repo = try sanitizeValue(repo)
    let jump = zoxideExactJump(repo: repo)
    guard let base = try normalizedBaseDirectory(baseDirectory) else { return jump }

    let dir = base == "/" ? "/\(repo)" : "\(base)/\(repo)"
    var clauses = [jump, "{ git -C \(dir) rev-parse --git-dir >/dev/null && cd \(dir); }"]
    // Without an owner there is no clone address — drop the clause and chain jump→cd only.
    // `gh` defers protocol (SSH/HTTPS) and auth to the user's gh config, which covers private
    // repositories too.
    if let owner, !owner.isEmpty {
        let cloneOwner = try sanitizeValue(owner)
        clauses.append("{ gh repo clone \(cloneOwner)/\(repo) \(dir) && cd \(dir); }")
    }
    return "{ \(clauses.joined(separator: " || ")); }"
}

/// Moves into the folder zoxide has recorded under **exactly** the repository's name — the
/// highest-scoring one when there are several — and fails, saying so, when there is none.
///
/// Never `z <repo>`: zoxide cannot anchor a match to the end of a folder name, so `z` also lands in
/// the `<repo>-<branch>` worktrees the presets create (the measured routes are in
/// `docs/context/repository-entry.md`).
///
/// - `zoxide query --list` prints every match, highest score first, skipping folders that no
///   longer exist. Do not add `--exclude`: standing in the repository has to count as a match.
/// - The match ignores case, as zoxide's does. `.` is the one whitelisted character grep reads as a
///   wildcard, so it is escaped; `command grep` keeps a `grep --color=always` alias from painting
///   escape codes into the path.
/// - Do not collapse this to `cd -- "$(…)"` — `cd ""` succeeds in zsh 5.9 and bash 3.2 (measured),
///   and the chain would run wherever the tab opened.
/// - `zoxide query --list` prints nothing and exits 0 on no match (measured), so the clause prints
///   the only line that explains a stopped chain. It is ASCII because it is typed into a shell.
///
/// `tc_dir` stays set in the user's shell. The appended-prompt scanner never sees this syntax
/// (`ResolvedRequest.commandJudgedForAppendedPrompt`), so keep the fragment one closed group.
private func zoxideExactJump(repo: String) -> String {
    let pattern = repo.replacingOccurrences(of: ".", with: "\\.")
    return "{ tc_dir=$(zoxide query --list -- \(repo) | command grep -i -m1 '/\(pattern)$'"
        + " || { echo 'zoxide has not recorded a directory named \(repo)' >&2; false; })"
        + " && cd -- \"$tc_dir\"; }"
}
