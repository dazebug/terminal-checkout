# Git Hooks

`pre-commit`: when a commit stages an addition, deletion, or rename of `CLAUDE.md`, create or remove the `AGENTS.md → CLAUDE.md` symlink in that directory and stage it with the commit. A commit that does not touch any `CLAUDE.md` is left alone. Full sync (tracked and untracked-but-not-ignored files only; ignored paths and nested worktrees are skipped): `.githooks/sync-agents-symlink.sh --all`.

`sync-agents-symlink.sh` is vendored verbatim from the `agents-md` plugin (watcha-claude-plugins, 1.1.1), Korean comments included — update it through the plugin (`/agents-md:setup-agents-md`), not by editing it here.

## Enable

```bash
git config core.hooksPath .githooks
```
