# Knowledge capture

Why this repository keeps a `docs/context/` at all, and how the tooling around it is installed.

**Note on sources:** an entry cites ledger ids and `file:line` while the work it describes is still on a branch, and PR numbers once that work is merged — this repository squash-merges, so a branch hash recorded before the merge stops resolving afterwards. A hash may ride along for precision, but never alone, and `tests/context-sources.test.js` fails a `Source` or `Status` line that carries one without a PR number. That gate exists because this note alone did not hold: nine lines across four entries cited hashes that are not ancestors of main, while the one hash that is — `da37339` — is a squash commit rather than a branch one.

## The skill is vendored into the repository

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** `skills-lock.json`; `.agents/skills/keep-the-why/`
**Revisit when:** the skill gains a release cadence that makes manual updates a burden, or a shared marketplace copy exists

The Keep the Why skill is committed here — the 16 source files under `.agents/skills/keep-the-why/`, the `.claude/skills/keep-the-why` symlink that points at them, and `skills-lock.json`.

**Reason:** this repository branches through git worktrees, and skill discovery is bound to the directory a session started in rather than its current one. An installed-but-uncommitted skill therefore does not exist in a fresh worktree, and a lock-only install assumes someone re-runs the installer in each one. Committing it means every worktree has it the moment it is created. A cloner gets the discipline along with the `context/` it is meant to maintain.

**Rejected alternative — install globally in `~/.claude/skills/`.** Solves the worktree problem just as well and keeps a third-party MIT skill out of a public repository. Rejected for consistency with the other repository adopting this convention, and because a cloner would then read `context/` without the rules for maintaining it.

**Rejected alternative — lock file only, no vendored copy.** Reproducible and small, but it is the shape the worktree finding argues against: each new worktree starts without the skill until someone reinstalls.

**Rejected alternative — republish through the internal marketplace.** Adds a fork to maintain and a licence-attribution question, for a skill nobody here needs to modify.

**Note on the lock:** `ref` is `latest`, an upstream moving tag, so `npx skills update` pulls new releases. That also means the lock does not pin a version — `computedHash` is the only actual fixed point recorded here.

## Personal preferences live outside the repository

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Source:** `CLAUDE.md` import line; Claude Code memory documentation
**Revisit when:** this repository stops using worktrees, or Claude Code changes how local instruction files resolve

Per-developer settings are imported from `~/.claude/local/{owner}-{repo}.md` rather than kept in a gitignored file at the repository root.

**Reason:** `CLAUDE.local.md` is Claude Code's documented local-instructions file and would be the obvious choice, but a gitignored file only exists in the worktree that created it. Branching through worktrees means it would be missing — and its setup wizard would re-run — in every new one. The home directory is the same file for all of them. Naming the file after `{owner}-{repo}` rather than after the tool avoids collisions between same-named repositories and keeps one file per project as more tools want a place to store preferences.

**Rejected alternative — `CLAUDE.local.md` at the repository root.** The documented default, and wrong here for the reason above. Claude Code's own documentation recommends the home-directory import for exactly this case.

**Cost, accepted:** an import that resolves outside the working directory triggers a one-time approval dialog per project. Declining it disables the import silently thereafter.

## No session-start hook

**Type:** decision
**Status:** active
**Evidence:** confirmed
**Revisit when:** `context/` is observably going stale because the skill is not being reached for

`CLAUDE.md` points at `docs/context/` in prose and carries the config block; nothing fires on session start.

**Reason:** `CLAUDE.md` is already loaded at the start of every session, so a hook that injects a reminder is doing the same job a second time. The skill's own setup notes that no cross-tool recommendation for stronger activation has been established yet.

**Caveat worth knowing:** block-level HTML comments in `CLAUDE.md` are stripped before the file is injected into context, so the `<!-- keep-the-why:config -->` delimiters are invisible to the automatically loaded copy — only to a tool that opens the file directly. That is why the pointer next to the block is prose rather than living inside the comment.
