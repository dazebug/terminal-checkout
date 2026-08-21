import Foundation

/// The base directory — the top-level folder the user clones repositories into.
///
/// Command templates open by moving into the repository. When that clause is a bare `z {repo}` and
/// zoxide's DB has never recorded the repository, it exits non-zero with `zoxide: no match found`
/// and the whole `&&` chain dies (issue #30). The app cannot observe a failure inside the user's
/// shell, so the button still reports success. Hence a fallback rather than detection: if `z`
/// fails, `cd` into the base directory, and if the repository isn't there either, clone it.
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

    // Strip trailing slashes so composing `<base>/<repo>` never yields `//` (root stays root)
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
/// With no base directory configured this is `z <repo>`, **byte-identical** to what the presets
/// used to spell out. That equivalence is why the app assembles the clause instead of the presets
/// carrying a path variable: a path variable would leave every button of an unconfigured user
/// failing with `Variable {basedir} not provided`.
///
/// Configured, it chains `z` → `cd` → `clone`. `z` coming first is a rule: the base directory must
/// not override a jump `z` made successfully. Measured, a cold DB exits 1 and a missing `z` exits
/// 127, so this one branch covers both.
///
/// Grouping is `{ …; }` only — `( … )` is a subshell, and `cd` inside one does not stick in the
/// current shell. stderr is not suppressed either: the two fallback lines explain what happened,
/// and hiding them would hide real failures (permissions, and so on) along with them.
///
/// Every ingredient is a validated value — even though callers have validated already, the
/// assembly site checks again. The result of this function is the only thing exempt from
/// `sanitizeValue`, and re-checking the ingredients right here is what earns that exemption.
public func repoEntryCommand(repo: String, owner: String?, baseDirectory: String) throws -> String {
    let repo = try sanitizeValue(repo)
    let jump = "z \(repo)"
    guard let base = try normalizedBaseDirectory(baseDirectory) else { return jump }

    let dir = base == "/" ? "/\(repo)" : "\(base)/\(repo)"
    var clauses = [jump, "cd \(dir)"]
    // Without an owner there is no clone address — drop the clause and chain z→cd only.
    // `gh` defers protocol (SSH/HTTPS) and auth to the user's gh config, which covers private
    // repositories too.
    if let owner, !owner.isEmpty {
        let cloneOwner = try sanitizeValue(owner)
        clauses.append("{ gh repo clone \(cloneOwner)/\(repo) \(dir) && cd \(dir); }")
    }
    return "{ \(clauses.joined(separator: " || ")); }"
}
