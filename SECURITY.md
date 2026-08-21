# Security Policy

## Reporting

Use GitHub's private [Report a vulnerability](https://github.com/dazebug/terminal-checkout/security/advisories/new) form. Please don't publish exploit details in a public issue.

Only the current source on `main` is maintained, on a best-effort basis — there are no supported release branches and no response-time guarantee.

## Trust model

- **Command templates are trusted user configuration.** Buttons deliberately run arbitrary shell commands the user configured. Variable values coming from GitHub pages are validated against a strict character whitelist (alphanumeric plus `-_./`) before substitution.
- **Same-uid processes are trusted.** The app's unix socket (mode 0600 + peer verification) and, on Warp, the injection helper's socket intentionally accept any process running as the same user. Same-uid access is not considered a boundary violation; the helper's exposure is narrowed by lifetime instead — it is killed the moment delivery ends.
- **What counts as a violation:** cross-uid access, command injection from untrusted page content getting past the whitelist, or bypassing the tty safety gates that keep injected input from reaching the wrong process.

Details: the engineering constraints in [CLAUDE.md](CLAUDE.md) and the Warp trust-boundary preamble in [`app/Sources/WarpHelper/main.swift`](app/Sources/WarpHelper/main.swift).
