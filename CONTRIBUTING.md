# Contributing

Thanks for your interest in Terminal Checkout!

## Getting started

```bash
git clone https://github.com/dazebug/terminal-checkout.git
cd terminal-checkout
```

## Tests

```bash
cd app && swift test        # Core unit tests
node --test                 # extension (JS) tests — from the repo root
app/build.sh && app/e2e.sh  # build + relay ↔ socket ↔ server round-trip (headless)
```

All of the above run in CI on every pull request.

## Before you change code

- Read [`CLAUDE.md`](CLAUDE.md) first. It is the canonical engineering-constraints document for humans and AI agents alike (`AGENTS.md` is a symlink to it): architecture constraints and empirically measured pitfalls this project depends on — in particular the TCC responsible-process split and the claude-input injection gates, which must not be weakened. If you edit `CLAUDE.md` files, enable the symlink-sync hook with `git config core.hooksPath .githooks` (optional otherwise).
- Neither the unit tests nor e2e ever opens a real terminal, so changes to terminal-control paths need hands-on verification. Adding support for a new terminal? Follow [`docs/new-terminal-checklist.md`](docs/new-terminal-checklist.md), including its hands-on checklist.
- Parts of `app/` are still commented in Korean; an English pass is planned. New code, comments, and PRs should be in English.

## Pull requests

Keep PRs focused, and describe what you verified — which tests you ran and which hands-on checks you performed.
