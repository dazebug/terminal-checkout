# Git Hook for AGENTS symlink

Before each commit, this repository creates or removes an `AGENTS.md` symlink in every folder, based on whether that folder has a `CLAUDE.md`.

- Folder with a `CLAUDE.md`: create (or keep) an `AGENTS.md` in that folder
- Folder without a `CLAUDE.md`: delete the existing `AGENTS.md` symlink

To enable it locally, run:

```bash
git config core.hooksPath .githooks
```
