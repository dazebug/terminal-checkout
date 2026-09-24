# Repository entry — how `{cd}` finds the repository

## `{cd}` enters the zoxide folder named exactly `{repo}`, never `z {repo}`

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured — zoxide 0.10.0 against an isolated database in zsh 5.9 and bash 3.2; `filter_by_keywords`, `Stream::new` and `query_list` read at v0.10.0 and on main)
**Source:** user decision, 2026-09-24, after a button meant for the main checkout landed in a worktree; `zoxideExactJump` in `app/Sources/Core/BaseDirectory.swift`; `RepoEntryRuntimeTests` in `app/Tests/CoreTests/CoreTests.swift`
**Revisit when:** zoxide gains an anchored or exact query, or the presets stop creating `{repo}-<branch>` worktrees next to the checkout

`z {repo}` reached worktrees by two separate routes, both reproduced on an isolated database with a checkout `foo` and a worktree `foo-feature_x`:

- **Frecency.** The score is rank times a recency weight — ×4 within the hour, ×2 within the day, ×0.5 within the week, ×0.25 after that — so a worktree someone just worked in outranks the checkout (88 against 48 in the reproduction), and `z foo` goes there.
- **The current directory is excluded.** The `z` function queries with `--exclude "$PWD"`, so from inside `foo` it landed in `foo-feature_x` while `foo` scored ten times higher (40 against 4). A tab that opens in the checkout's directory therefore never stays in it.

zoxide cannot be asked for an exact match. Its last keyword is found with `rfind` anywhere inside the path's last component, with no way to anchor the end, and neither a flag nor an environment variable changes that. The spellings that look like anchors are something else: `z foo/` is a relative path, `z foo /` means a subdirectory of a `foo` match, an unquoted trailing space is dropped by the shell, and a quoted one is searched for literally (`zoxide: no match found`).

So `{cd}` asks `zoxide query --list -- {repo}` — every match, highest score first, existing folders only, and without `--exclude`, so already standing in the checkout counts — and takes the first line whose last component is `{repo}`, ignoring case as zoxide does. Two measured shell facts shape the clause:

- `cd ""` **succeeds** in zsh 5.9 and bash 3.2 (bash 5.3 refuses with `null directory`). Feeding the lookup straight to `cd -- "$(…)"` would leave the rest of the chain running wherever the tab opened, so the result goes through a variable and `&&`.
- `zoxide query --list` prints nothing and exits 0 when nothing matches. The clause prints `zoxide has not recorded a directory named {repo}` itself; without a base directory that line is the only thing on screen explaining why the chain stopped.

**z.sh is dropped (user decision).** The clause runs the `zoxide` executable, and the setup window's tool check moved from `z` to `zoxide` with it. z.sh mostly did not have this problem: it prefers the shortest match when that match is a prefix of all the others, rank notwithstanding (`common` in `z.sh`). Keeping it would have meant a runtime `command -v zoxide` branch in every typed command, about 60 characters more on every command, where cmux layout leaf commands are capped at 1023 bytes. That was offered and declined.

**Consequences, accepted:** a clone kept under a folder name other than the repository's is no longer found by the jump — the base directory catches it, or renaming the folder does. The variable `tc_dir` stays set in the user's shell after the jump.

**Rejected alternative — normalize whatever `z` finds to its main worktree** (`git rev-parse --git-common-dir`, then its parent). It works with any `z`, but in a bare-repository layout the common directory's parent is not a checkout, and when `z` lands in a different repository that merely contains the name, the result is that repository's checkout with nothing on screen saying so.

**Rejected alternative — check the basename after `z` and fail on a mismatch.** It refuses the wrong folder but never reaches the right one when no base directory is set.

**Rejected alternative — the app looks the folder up and sends `cd <path>`.** A login-shell spawn per click, and a path containing a space fails the value whitelist.

**Rejected alternative — name the presets' worktrees so they do not contain `{repo}`.** It moves every existing user's worktrees and still leaves any other folder whose name contains the repository's.

## The appended-prompt scanner judges `{cd}` as the one word it stands for

**Type:** decision
**Status:** active
**Evidence:** confirmed (measured — with the scanner judging the real command, `testTheEntryClauseDoesNotCostAClaudeButtonItsArgvPrompt` and `testTheAppendedPromptReachesClaudeInTheRepositoryFolder` failed, exit status 1 over 2 executed tests; with the stand-in they pass)
**Source:** the same change; `commandJudgedForAppendedPrompt` on `ResolvedRequest` in `app/Sources/Core/Request.swift`, and its use in `prepareRequest` in `app/Sources/Core/ClaudeInputPlan.swift`
**Revisit when:** the scanner starts modeling command substitution, or the app assembles a second fragment

The exact jump needs a command substitution, quotes, an assignment and `command`, and each of those folds `commandAcceptsAppendedClaudePrompt`. Judging the real text would have moved every `{cd} && claude` button's single plain-text input from claude's argv to typing — which on Warp also puts it behind the Accessibility permission.

That scanner exists to judge syntax the **user** wrote. The fragment is built only by `repoEntryCommand` from validated values, defines no function or alias, touches no `PATH`, and is one closed `{ …; }` group, so `resolveRequestItem` renders the template a second time with each app fragment standing in as its own name (`{cd}` becomes `cd`) and the scanner judges that. The append itself still edits the real command, whose tail is the same. The exemption is earned the way the whitelist exemption is — by construction at the one assembly site — and it is pinned by a runtime test that runs the prepared command in zsh, bash, sh and dash and sees claude receive exactly the message, in the repository folder.

**Rejected alternative — a fragment the scanner accepts.** Not available: nothing hands a lookup's output to `cd` in the current shell without a substitution (a pipeline into `read` runs in a subshell in bash).

**Rejected alternative — teach the scanner the fragment's shape.** It would accept that text wherever it appears, including typed by hand, and judge by appearance rather than by who assembled it.
