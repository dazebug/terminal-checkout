import XCTest
@testable import Core

// MARK: - Command rendering (variable substitution + command-injection defence)

final class RenderTests: XCTestCase {
    func testRenderBasic() throws {
        let cmd = try renderCommand(
            template: "z {repo} && git fetch origin && git checkout {branch}",
            variables: ["repo": "remy", "branch": "fix/login"]
        )
        XCTAssertEqual(cmd, "z remy && git fetch origin && git checkout fix/login")
    }

    func testRenderAllVariables() throws {
        let cmd = try renderCommand(
            template: "{repo} {branch} {base} {main} {branch_underbar} {number} {owner}",
            variables: [
                "repo": "r", "branch": "a/b", "base": "release/2", "main": "develop",
                "branch_underbar": "a_b", "number": "1402", "owner": "frograms",
            ]
        )
        XCTAssertEqual(cmd, "r a/b release/2 develop a_b 1402 frograms")
    }

    // {base} is the branch this PR will actually be merged into — it can differ from {main}, which goes through the per-repository override and the global default, so the two have to substitute different values
    func testRenderBaseIsIndependentOfMain() throws {
        let cmd = try renderCommand(
            template: "git merge --ff-only origin/{base} && echo {main}",
            variables: ["base": "release/2", "main": "main"]
        )
        XCTAssertEqual(cmd, "git merge --ff-only origin/release/2 && echo main")
    }

    // The gh commands in the issue and PR presets put {owner}/{repo}/{number} straight into a URL path
    func testRenderGitHubAPIPath() throws {
        let cmd = try renderCommand(
            template: "gh api repos/{owner}/{repo}/issues/{number}/timeline",
            variables: ["owner": "frograms", "repo": "remy-worker", "number": "1402"]
        )
        XCTAssertEqual(cmd, "gh api repos/frograms/remy-worker/issues/1402/timeline")
    }

    func testAcceptsAllowedCharacters() throws {
        _ = try renderCommand(template: "z {repo}", variables: ["repo": "my-repo_1.2/x"])
    }

    func testRejectsInvalidCharactersInValue() {
        for bad in ["a;rm -rf /", "a b", "한글", "", "a$b", "a`b`", "a\"b", "a&&b|c", "a\nb"] {
            XCTAssertThrowsError(
                try renderCommand(template: "z {repo}", variables: ["repo": bad]),
                "value should be rejected: \(bad)"
            )
        }
    }

    func testRejectsUnknownVariableName() {
        XCTAssertThrowsError(
            try renderCommand(template: "z {repo}", variables: ["repo": "r", "evil": "x"])
        )
    }

    func testRejectsUnprovidedTemplateVariable() {
        XCTAssertThrowsError(
            try renderCommand(template: "git checkout {main}", variables: ["repo": "r"])
        )
    }

    // A bash grouping { …; } is not a variable pattern ({word}), so it has to pass through untouched
    // (the default checkout preset uses { } grouping for its worktree fallback)
    func testBashGroupingBracesPassThrough() throws {
        let cmd = try renderCommand(
            template: "z {repo} && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }",
            variables: ["repo": "remy", "branch": "ci/x", "branch_underbar": "ci_x"]
        )
        XCTAssertEqual(cmd, "z remy && { git checkout ci/x || cd ../remy-ci_x; }")
    }
}

// MARK: - Base directory normalization
// The fallback for issue #30: on a cold zoxide DB `z {repo}` exits non-zero and the whole chain
// dies with nothing to see. The value reaches the shell unquoted, so it takes the **same**
// character verdict as a command variable.

final class BaseDirectoryTests: XCTestCase {
    func testAbsolutePathPassesThrough() throws {
        XCTAssertEqual(try normalizedBaseDirectory("/Users/x/Codes"), "/Users/x/Codes")
    }

    // Adding `~` to the allowed characters would let it flow into the shell verbatim — expand it
    // here instead of widening the whitelist
    func testTildeIsExpandedSoItNeverReachesTheShell() throws {
        XCTAssertEqual(try normalizedBaseDirectory("~/Codes"), NSHomeDirectory() + "/Codes")
        XCTAssertEqual(try normalizedBaseDirectory("~"), NSHomeDirectory())
    }

    func testTrailingSlashesAreStripped() throws {
        XCTAssertEqual(try normalizedBaseDirectory("/Users/x/Codes/"), "/Users/x/Codes")
        XCTAssertEqual(try normalizedBaseDirectory("/Users/x/Codes///"), "/Users/x/Codes")
    }

    // Pasting into a text field easily drags surrounding spaces along
    func testSurroundingWhitespaceIsTrimmed() throws {
        XCTAssertEqual(try normalizedBaseDirectory("  /Users/x/Codes  "), "/Users/x/Codes")
    }

    // An empty value is not an error but "not configured" — staying on the old behavior with no
    // fallback is a legitimate state
    func testEmptyMeansNotConfigured() throws {
        XCTAssertNil(try normalizedBaseDirectory(""))
        XCTAssertNil(try normalizedBaseDirectory("   "))
    }

    func testRelativePathIsRejected() {
        for bad in ["Codes", "./Codes", "../Codes", "Users/x"] {
            XCTAssertThrowsError(try normalizedBaseDirectory(bad), "should be rejected: \(bad)")
        }
    }

    // The same whitelist as command variables — a path with spaces, quotes, or substitution
    // characters would be split apart or executed by the shell
    func testPathCharactersOutsideTheWhitelistAreRejected() {
        for bad in ["/Users/x/My Codes", "/Users/x/Codes; rm -rf /", "/Users/x/$HOME",
                    "/Users/x/`whoami`", "/Users/x/코드", "/Users/x/Codes\n"] {
            XCTAssertThrowsError(try normalizedBaseDirectory(bad), "should be rejected: \(bad)")
        }
    }

    func testRootStaysRoot() throws {
        XCTAssertEqual(try normalizedBaseDirectory("/"), "/")
    }
}

// MARK: - Repository entry clause assembly (the value of {cd})

final class RepoEntryCommandTests: XCTestCase {
    private let base = "/Users/x/Codes"

    // For a user with no base directory the command must be **byte-identical** to before this
    // change
    func testWithoutBaseDirectoryTheEntryIsExactlyTodaysFirstClause() throws {
        XCTAssertEqual(
            try repoEntryCommand(repo: "remy", owner: "frograms", baseDirectory: ""),
            "z remy"
        )
    }

    // The cd clause is gated on the directory actually being a repository. A bare `cd` returning 0
    // would read as "found it" for an empty or unrelated directory too, and the rest of the preset
    // chain (`git fetch`, `git checkout`) would then run somewhere the user never asked for.
    func testBaseDirectoryAddsCdThenCloneFallback() throws {
        XCTAssertEqual(
            try repoEntryCommand(repo: "remy", owner: "frograms", baseDirectory: base),
            "{ z remy || "
                + "{ git -C /Users/x/Codes/remy rev-parse --git-dir >/dev/null && cd /Users/x/Codes/remy; } || "
                + "{ gh repo clone frograms/remy /Users/x/Codes/remy && cd /Users/x/Codes/remy; }; }"
        )
    }

    // Without an owner there is no clone address — drop the clause and chain z→cd only
    func testWithoutOwnerTheCloneClauseIsOmitted() throws {
        let cmd = try repoEntryCommand(repo: "remy", owner: nil, baseDirectory: base)
        XCTAssertEqual(
            cmd,
            "{ z remy || "
                + "{ git -C /Users/x/Codes/remy rev-parse --git-dir >/dev/null && cd /Users/x/Codes/remy; }; }"
        )
        XCTAssertFalse(cmd.contains("clone"))
    }

    func testEmptyOwnerCountsAsAbsent() throws {
        XCTAssertEqual(
            try repoEntryCommand(repo: "remy", owner: "", baseDirectory: base),
            "{ z remy || "
                + "{ git -C /Users/x/Codes/remy rev-parse --git-dir >/dev/null && cd /Users/x/Codes/remy; }; }"
        )
    }

    // ( … ) is a subshell, so a cd inside it does not stick in the current shell — grouping is
    // { …; } and nothing else
    func testGroupingNeverUsesASubshell() throws {
        for owner in ["frograms", ""] {
            let cmd = try repoEntryCommand(repo: "remy", owner: owner, baseDirectory: base)
            XCTAssertFalse(cmd.contains("("), "subshell grouping leaked in: \(cmd)")
            XCTAssertFalse(cmd.contains(")"), "subshell grouping leaked in: \(cmd)")
        }
    }

    // The base directory must not override a jump z made successfully — z is always the first
    // clause
    func testZComesFirst() throws {
        XCTAssertTrue(
            try repoEntryCommand(repo: "remy", owner: "frograms", baseDirectory: base)
                .hasPrefix("{ z remy || ")
        )
    }

    // The reason for the fallback has to stay readable on screen — suppressing stderr would take
    // real failures down with it.
    // The repository guard discards `git rev-parse`'s *stdout* (on success it prints the .git path,
    // which is pure noise), so "contains /dev/null" stopped telling the two apart. The check is
    // narrowed to stderr redirection itself, which is what decision 7 is actually about: `fatal:
    // not a git repository` and `cannot change to` have to reach the screen and explain the fallback.
    func testStderrIsNotSuppressed() throws {
        let cmd = try repoEntryCommand(repo: "remy", owner: "frograms", baseDirectory: base)
        XCTAssertFalse(cmd.contains("2>"), cmd)  // 2>/dev/null, 2>&1, 2>>…
        XCTAssertFalse(cmd.contains("&>"), cmd)  // the both-streams form
    }

    // A corrupted stored value (a hand-edited plist, say) is not silently ignored — the button
    // fails and carries the reason
    func testInvalidBaseDirectoryThrows() {
        XCTAssertThrowsError(try repoEntryCommand(repo: "remy", owner: "f", baseDirectory: "Codes"))
        XCTAssertThrowsError(
            try repoEntryCommand(repo: "remy", owner: "f", baseDirectory: "/Users/x/My Codes")
        )
    }

    // Every ingredient of the fragment is a validated value — the assembly site checks again
    func testUnsanitizedRepoOrOwnerThrows() {
        XCTAssertThrowsError(try repoEntryCommand(repo: "a;rm -rf /", owner: "f", baseDirectory: base))
        XCTAssertThrowsError(try repoEntryCommand(repo: "remy", owner: "a b", baseDirectory: base))
        XCTAssertThrowsError(try repoEntryCommand(repo: "", owner: "f", baseDirectory: base))
    }

    func testRootBaseDirectoryDoesNotDoubleTheSlash() throws {
        XCTAssertEqual(
            try repoEntryCommand(repo: "remy", owner: nil, baseDirectory: "/"),
            "{ z remy || { git -C /remy rev-parse --git-dir >/dev/null && cd /remy; }; }"
        )
    }
}

// MARK: - Request resolution (the command_template shape)

final class RequestTests: XCTestCase {
    func testTemplateRequest() throws {
        let req: [String: Any] = [
            "command_template": "z {repo} && git checkout {branch}",
            "variables": ["repo": "remy", "branch": "fix/x"],
        ]
        XCTAssertEqual(try resolveRequest(req).command, "z remy && git checkout fix/x")
    }

    // Which terminal to use is the app's setting to decide — a terminal field riding along in the request is never resolved
    func testTerminalFieldIsIgnored() throws {
        let req: [String: Any] = [
            "command_template": "z {repo}",
            "variables": ["repo": "remy"],
            "terminal": "wezterm",
        ]
        XCTAssertEqual(try resolveRequest(req).command, "z remy")
    }

    func testRequestWithoutTemplateIsRejected() {
        XCTAssertThrowsError(try resolveRequest([:]))
        XCTAssertThrowsError(try resolveRequest(["unrelated": 1]))
        XCTAssertThrowsError(try resolveRequest(["repo": "remy", "branch": "fix/x"]))
        XCTAssertThrowsError(try resolveRequest(["command_template": ""]))
    }

    // claude_inputs: the inputs to type into the session once claude is running. They use the same variable syntax as the command.
    func testClaudeInputsParsedAndRendered() throws {
        let req: [String: Any] = [
            "command_template": "z {repo} && claude",
            "variables": ["repo": "remy", "branch": "fix/x"],
            "claude_inputs": ["/review", "PR {branch} 변경사항을 요약해줘"],
        ]
        let r = try resolveRequest(req)
        XCTAssertEqual(r.claudeInputs, ["/review", "PR fix/x 변경사항을 요약해줘"])
    }

    func testClaudeInputsAbsentDefaultsToEmpty() throws {
        let r = try resolveRequest([
            "command_template": "z {repo}", "variables": ["repo": "remy"],
        ])
        XCTAssertEqual(r.claudeInputs, [])
    }

    func testClaudeInputsTrimmedAndEmptyDropped() throws {
        let r = try resolveRequest([
            "command_template": "z {repo}", "variables": ["repo": "remy"],
            "claude_inputs": ["  /review  ", "", "   "],
        ])
        XCTAssertEqual(r.claudeInputs, ["/review"])
    }

    func testClaudeInputsRejectNonStringElement() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "z {repo}", "variables": ["repo": "remy"],
            "claude_inputs": [1],
        ]))
    }

    func testClaudeInputsRejectNonArray() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "z {repo}", "variables": ["repo": "remy"],
            "claude_inputs": "/review",
        ]))
    }

    // A variable inside an input gets the same validation as one in the command — an unknown variable is an error
    func testClaudeInputsUnknownVariableThrows() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "z {repo}", "variables": ["repo": "remy"],
            "claude_inputs": ["checkout {nope} please"],
        ]))
    }

    /// **Reproduction (reviewer P2-6)**: command substitution drops NUL silently — `"pre\0post"`
    /// was submitted as `prepost`. The injection path cannot put that byte into a tty either.
    /// Since neither route can deliver it faithfully, **reject the request** instead of quietly
    /// altering it
    func testNULInInputsIsRejected() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "z {repo} && claude", "variables": ["repo": "remy"],
            "claude_inputs": ["pre\u{0}post"],
        ]))
    }

    func testNULInTheCommandIsRejected() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "z {repo}\u{0} && claude", "variables": ["repo": "remy"],
        ]))
    }

    // MARK: {cd} — the shell fragment the app assembles and fills in

    // For a user with no base directory the command must be byte-identical to before this change
    func testCDWithoutBaseDirectoryRendersTodaysCommand() throws {
        let req: [String: Any] = [
            "command_template": "{cd} && git fetch origin && git checkout {branch}",
            "variables": ["repo": "remy", "owner": "frograms", "branch": "fix/x"],
        ]
        XCTAssertEqual(
            try resolveRequest(req).command,
            "z remy && git fetch origin && git checkout fix/x"
        )
    }

    func testCDWithBaseDirectoryRendersTheFallbackChain() throws {
        let req: [String: Any] = [
            "command_template": "{cd} && git fetch origin",
            "variables": ["repo": "remy", "owner": "frograms"],
        ]
        XCTAssertEqual(
            try resolveRequest(req, baseDirectory: "/Users/x/Codes").command,
            "{ z remy || "
                + "{ git -C /Users/x/Codes/remy rev-parse --git-dir >/dev/null && cd /Users/x/Codes/remy; } || "
                + "{ gh repo clone frograms/remy /Users/x/Codes/remy && cd /Users/x/Codes/remy; }; }"
                + " && git fetch origin"
        )
    }

    // The app is the single source for the base directory — a value the extension sends under the
    // same name is rejected, not merged. (Allowing the merge would open a hole through which the
    // extension could run an arbitrary shell fragment.)
    func testCDCannotComeFromTheExtension() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "{cd}", "variables": ["cd": "rm -rf /"],
        ])) { error in
            XCTAssertEqual(errorMessage(error), "Unknown variable: {cd}")
        }
    }

    // Assembling the fragment needs repo — when it is missing, the reason reported is the thing
    // that is actually absent, not {cd}
    func testCDWithoutRepoIsRejected() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "{cd}", "variables": ["owner": "frograms"],
        ])) { error in
            XCTAssertEqual(errorMessage(error), "Variable {repo} not provided")
        }
    }

    // A command that doesn't use {cd} is unchanged even with a base directory configured
    func testBaseDirectoryDoesNotTouchCommandsWithoutCD() throws {
        let req: [String: Any] = ["command_template": "z {repo}", "variables": ["repo": "remy"]]
        XCTAssertEqual(try resolveRequest(req, baseDirectory: "/Users/x/Codes").command, "z remy")
    }

    // Keeps the contract (README) that variables work identically in commands and claude inputs
    func testCDIsSubstitutedInClaudeInputsToo() throws {
        let r = try resolveRequest([
            "command_template": "{cd} && claude", "variables": ["repo": "remy"],
            "claude_inputs": ["!{cd} && git status"],
        ], baseDirectory: "")
        XCTAssertEqual(r.claudeInputs, ["!z remy && git status"])
    }

    // A corrupted stored value is not silently ignored — the button fails and carries the reason
    func testInvalidStoredBaseDirectoryIsReported() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "{cd}", "variables": ["repo": "remy"],
        ], baseDirectory: "~/My Codes")) { error in
            XCTAssertTrue(
                errorMessage(error).contains("Invalid characters in base directory"),
                errorMessage(error)
            )
        }
    }

    // The fragment is made of characters sanitizeValue cannot pass (spaces, braces) — running the
    // app-assembled value through the request-variable check would kill every button
    func testAssembledFragmentIsNotRunThroughTheValueWhitelist() throws {
        let cmd = try resolveRequest([
            "command_template": "{cd}", "variables": ["repo": "remy", "owner": "frograms"],
        ], baseDirectory: "/Users/x/Codes").command
        XCTAssertTrue(cmd.contains(" || "), cmd)
        XCTAssertTrue(cmd.hasPrefix("{ z remy"), cmd)
    }
}

// MARK: - The request handler (the success/failure JSON response shape)

final class HandlerTests: XCTestCase {
    func testHandleRequestSuccess() {
        var ran: ResolvedRequest?
        let resp = handleRequest(
            json: [
                "command_template": "z {repo}",
                "variables": ["repo": "remy"],
                "claude_inputs": ["/review"],
            ],
            run: { ran = $0 }
        )
        XCTAssertEqual(resp["success"] as? Bool, true)
        XCTAssertEqual(ran?.command, "z remy")
        XCTAssertEqual(ran?.claudeInputs, ["/review"])
    }

    func testHandleRequestRenderError() {
        var didRun = false
        let resp = handleRequest(
            json: ["command_template": "z {repo}", "variables": ["repo": "a;b"]],
            run: { _ in didRun = true }
        )
        XCTAssertEqual(resp["success"] as? Bool, false)
        XCTAssertFalse(didRun)
        XCTAssertTrue((resp["error"] as? String ?? "").contains("Invalid characters"))
    }

    func testHandleRequestRunError() {
        struct Boom: Error, CustomStringConvertible { var description: String { "boom" } }
        let resp = handleRequest(
            json: ["command_template": "z {repo}", "variables": ["repo": "remy"]],
            run: { _ in throw Boom() }
        )
        XCTAssertEqual(resp["success"] as? Bool, false)
        XCTAssertEqual(resp["error"] as? String, "boom")
    }
}

// MARK: - claude input delivery (the foreground gate verdict — the crux of preventing shell mistyping)

final class ClaudeInjectorTests: XCTestCase {
    // Against `ps -t <tty> -o pid=,stat=,comm=` output. A foreground process group carries `+` in stat.
    // The reason a PID comes back rather than just the name is so the re-wait between inputs can confirm it is the same session (see testForegroundPIDDistinguishesReplacedSession).
    func testForegroundClaudeDetected() {
        XCTAssertEqual(claudeForegroundPID(psOutput: "100 Ss   -zsh\n200 S+   claude"), 200)
    }

    func testForegroundNodeWithFullPathDetected() {
        XCTAssertEqual(
            claudeForegroundPID(psOutput: "100 Ss   -zsh\n201 S+   /opt/homebrew/bin/node"), 201)
    }

    func testShellAtPromptIsNotClaude() {
        // While waiting at the prompt the shell itself is the foreground (+) — typing then makes the shell run it
        XCTAssertNil(claudeForegroundPID(psOutput: "100 Ss+  -zsh"))
        XCTAssertNil(claudeForegroundPID(psOutput: "100 Ss+  zsh"))
        XCTAssertNil(claudeForegroundPID(psOutput: "100 Ss+  /bin/zsh"))
    }

    func testOtherForegroundProcessIsNotClaude() {
        XCTAssertNil(claudeForegroundPID(psOutput: "100 Ss   -zsh\n300 S+   git"))
    }

    func testBackgroundClaudeIsNotEnough() {
        XCTAssertNil(claudeForegroundPID(psOutput: "200 S    claude\n100 Ss+  -zsh"))
    }

    func testPathWithSpacesUsesExactBasename() {
        // An unrelated process such as "Claude Helper (Renderer)" must not be mistaken for claude
        XCTAssertNil(claudeForegroundPID(
            psOutput: "400 S+   /Applications/Claude.app/Contents/MacOS/Claude Helper (Renderer)"))
    }

    func testEmptyOutputIsNotClaude() {
        XCTAssertNil(claudeForegroundPID(psOutput: ""))
    }

    /// In `ps -o pid=,stat=,comm=` the pid is right-aligned so it carries leading spaces, and several alignment spaces come before comm as well (measured: `" 3719 S+   node"`). Without trimming them every name comparison is off and claude is never found.
    func testRealPSColumnSpacingIsTolerated() {
        XCTAssertEqual(claudeForegroundPID(psOutput: " 3719 S+   node"), 3719)
        XCTAssertEqual(
            claudeForegroundPID(psOutput: "34782 Ss   -zsh\n 3719 S+   claude"), 3719)
        XCTAssertEqual(
            claudeForegroundPID(psOutput: "  100 Ss   -zsh\n95539 R+   /opt/homebrew/bin/node"),
            95539)
    }

    func testMalformedPIDColumnIsSkipped() {
        // When the pid field is not a number (a header, say) that line is skipped
        XCTAssertNil(claudeForegroundPID(psOutput: "PID STAT COMM\nxxx S+   claude"))
    }

    /// Regression guard for the session-swap defence: when the original claude dies and a new one comes up on the same tty, the name and raw mode are satisfied identically, so the PID is the only thing that can tell the two sessions apart.
    /// Failing to tell them apart submits the remaining claude_inputs into an unrelated new session, and with a `!…` shell-mode input it even runs an unintended command.
    func testForegroundPIDDistinguishesReplacedSession() {
        let first = claudeForegroundPID(psOutput: "100 Ss   -zsh\n95539 R+   claude")
        let replaced = claudeForegroundPID(psOutput: "100 Ss   -zsh\n95610 R+   claude")
        XCTAssertEqual(first, 95539)
        XCTAssertEqual(replaced, 95610)
        XCTAssertNotEqual(first, replaced)
    }

    // MARK: the tty raw-mode verdict — it separates out the window where the foreground is claude but input still cannot be accepted.
    // Right after the shell execs claude the tty is canonical (icanon+echo), so typing then is echoed by the kernel rather than by claude. Mistaking that echo for the screen reflecting the input loses the CR (measured).

    /// Real `stty -f /dev/ttysNNN -a` output (while claude is running = raw mode)
    private static let sttyRawOutput = """
    speed 9600 baud; 89 rows; 338 columns;
    lflags: -icanon -isig -iexten -echo echoe -echok echoke -echonl echoctl
    \t-echoprt -altwerase -noflsh -tostop -flusho -pendin -nokerninfo
    \t-extproc
    iflags: -istrip -icrnl -inlcr -igncr -ixon -ixoff ixany imaxbel -iutf8
    """

    /// Real `stty` output (right after claude is exec'd = canonical, the window where the kernel echoes)
    private static let sttyCanonicalOutput = """
    speed 9600 baud; 89 rows; 338 columns;
    lflags: icanon isig iexten echo echoe echok echoke -echonl echoctl
    \t-echoprt -altwerase -noflsh -tostop -flusho pendin -nokerninfo
    iflags: -istrip icrnl -inlcr -igncr ixon -ixoff ixany imaxbel -iutf8
    """

    func testRawModeDetected() {
        XCTAssertEqual(ttyIsRawMode(sttyOutput: Self.sttyRawOutput), true)
    }

    func testCanonicalModeDetected() {
        // Typing here puts the kernel echo on screen and lets the reflection check pass falsely
        XCTAssertEqual(ttyIsRawMode(sttyOutput: Self.sttyCanonicalOutput), false)
    }

    func testRawFlagIsNotMatchedAsSubstring() {
        // "-icanon" contains "icanon" as a substring — the split has to be token by token or raw gets mistaken for canonical
        XCTAssertEqual(ttyIsRawMode(sttyOutput: "lflags: -icanon -echo"), true)
        XCTAssertEqual(ttyIsRawMode(sttyOutput: "lflags: icanon echo"), false)
    }

    func testUndecidableSttyOutputIsNil() {
        // nil when it cannot be told because stty failed or its format changed — the caller then carries on with the ps gate alone
        XCTAssertNil(ttyIsRawMode(sttyOutput: ""))
        XCTAssertNil(ttyIsRawMode(sttyOutput: "stty: /dev/ttys999: No such file or directory"))
    }

    // MARK: the can-accept-input verdict = foreground claude + raw mode

    func testAcceptsInputRequiresBothSignals() {
        let claudeFg = "100 Ss   -zsh\n200 S+   claude"
        let shellFg = "100 Ss+  -zsh"
        XCTAssertEqual(acceptingClaudePID(psOutput: claudeFg, sttyOutput: Self.sttyRawOutput), 200)
        // claude is up but the tty is still canonical — sending now loses the CR
        XCTAssertNil(acceptingClaudePID(psOutput: claudeFg, sttyOutput: Self.sttyCanonicalOutput))
        // A shell prompt is raw because of zle, but the foreground is not claude
        XCTAssertNil(acceptingClaudePID(psOutput: shellFg, sttyOutput: Self.sttyRawOutput))
    }

    /// **An unreadable stty does not open the gate** (round 7 review). It used to: the verdict was
    /// `ttyIsRawMode(...) ?? true`, so "cannot tell" was treated as "raw" and delivery proceeded on
    /// the ps gate alone — the one thing `CLAUDE.md` says gate ② exists to prevent, since in the
    /// canonical window right after the exec the kernel echo is mistaken for claude rendering and
    /// the first input is lost.
    ///
    /// The fallback was deliberate when it was written (`20d7617`): the raw-mode check was new, and
    /// falling back to the previous ps-only behaviour meant it could not regress anyone. That is a
    /// migration argument, and it expired. Measured since: a **live tty always reports the token** —
    /// `icanon` in canonical mode, `-icanon` in raw — and stty only fails to produce one when the
    /// tty is gone or is not a terminal, in which case `ps -t` finds nothing either and the first
    /// guard has already refused. So the branch is not "an environment where stty does not work";
    /// it is "the tty we are about to type into cannot be read", which is not a state to type in.
    func testAnUnreadableSttyDoesNotOpenTheGate() {
        XCTAssertNil(
            acceptingClaudePID(psOutput: "200 S+   claude", sttyOutput: ""),
            "a claude in the foreground is not enough — gate ② has to have been passed, not skipped"
        )
        XCTAssertNil(acceptingClaudePID(psOutput: "100 Ss+  -zsh", sttyOutput: ""))
        // Output that exists but says nothing about the line discipline is the same "cannot tell"
        XCTAssertNil(acceptingClaudePID(psOutput: "200 S+   claude", sttyOutput: "speed 9600 baud;"))
        // And the two states that *are* readable keep answering as before
        XCTAssertEqual(
            acceptingClaudePID(psOutput: "200 S+   claude", sttyOutput: Self.sttyRawOutput), 200
        )
        XCTAssertNil(acceptingClaudePID(psOutput: "200 S+   claude", sttyOutput: Self.sttyCanonicalOutput))
    }

    // Finds a pane's tty in `wezterm cli list --format json`
    func testWezTermTTYParsing() throws {
        let json = Data("""
        [{"window_id":0,"tab_id":0,"pane_id":3,"tty_name":"/dev/ttys011","title":"zsh"},
         {"window_id":0,"tab_id":1,"pane_id":7,"tty_name":"/dev/ttys012","title":"zsh"}]
        """.utf8)
        XCTAssertEqual(wezTermTTYName(listJSON: json, paneID: "7"), "/dev/ttys012")
    }

    func testWezTermTTYMissingPane() {
        let json = Data(#"[{"pane_id":3,"tty_name":"/dev/ttys011"}]"#.utf8)
        XCTAssertNil(wezTermTTYName(listJSON: json, paneID: "99"))
        XCTAssertNil(wezTermTTYName(listJSON: Data("broken".utf8), paneID: "3"))
    }

    // The probe for confirming the screen reflects an input: a long input wraps at the screen width and breaks a whole-string match, so only its front is used
    func testClaudeInputProbeShortInputUsedWhole() {
        XCTAssertEqual(claudeInputProbe("/help"), "/help")
    }

    func testClaudeInputProbeLongInputTruncated() {
        let long = String(repeating: "a", count: 60)
        let probe = claudeInputProbe(long)
        XCTAssertEqual(probe.count, 24)
        XCTAssertTrue(long.hasPrefix(probe))
    }

    func testClaudeInputProbeTrimsWhitespace() {
        XCTAssertEqual(claudeInputProbe("  /help  "), "/help")
    }

    // claude draws a shell-mode input with a space after the `!`, as in "! gh ...".
    // Missing that makes the reflection check fail forever, so the input is never submitted and hangs in the input box (measured)
    func testScreenMatchesShellModeRendering() {
        XCTAssertTrue(screenReflectsNewInput(
            before: "╭────────╮\n╰────────╯\n  ! for shell mode",
            after: "╭────────╮\n! gh issue view 1404\n╰────────╯\n  ! for shell mode",
            input: "!gh issue view 1404"
        ))
    }

    // A long input wraps at the terminal width — it has to match even when the break falls inside the probe's length
    func testScreenMatchesWrappedInput() {
        XCTAssertTrue(screenReflectsNewInput(
            before: "> ",
            after: "> !gh api repos/frograms/remy-\nworker/issues/1404/timeline",
            input: "!gh api repos/frograms/remy-worker/issues/1404/timeline"
        ))
    }

    func testScreenWithoutInputDoesNotMatch() {
        XCTAssertFalse(screenReflectsNewInput(before: "> ", after: "> \n  ? for shortcuts", input: "!gh issue view 1404"))
    }

    // A whitespace-only input has an empty probe that matches any screen at all — it must not approve a submission
    func testEmptyInputNeverMatches() {
        XCTAssertFalse(screenReflectsNewInput(before: "", after: "any screen", input: "   "))
    }
}

// MARK: - Control-key bytes
// Both the delivery path and the tests below **reference** `claudeSubmitKey` and `claudeClearInputKey` — if the constants themselves were wrong (a CR turning into an LF, say) those tests would go green along with them and stop being oracles. So the literal bytes are pinned in this one place: claude recognises only CR (0x0D) as a submission (measured), and clearing the input box is Ctrl+U (0x15).

final class ClaudeControlKeyTests: XCTestCase {
    func testControlKeysAreTheExpectedBytes() {
        XCTAssertEqual(Array(claudeSubmitKey.utf8), [0x0D])
        // Ctrl+U **and** a Backspace, in that order: Ctrl+U alone leaves claude's `!` shell mode
        // behind (measured), and Backspace is what removes the prefix. The order matters — on a
        // box that still holds text, Backspace would only take its last character
        XCTAssertEqual(Array(claudeClearInputKey.utf8), [0x15, 0x7F])
    }
}

// MARK: - Terminal identifiers
// An oracle that pins the rawValues as literals — renaming a case changes the stored value with it, and an existing user's terminal choice is then silently ignored. The stored value "iterm" is an identifier that denotes iTerm2 regardless of the product's name, so it does not change. A constant referring to itself cannot keep this contract, which is why the check is by literal only.

final class TerminalIdentifierTests: XCTestCase {
    func testRawValuesAreTheStoredIdentifiers() {
        XCTAssertEqual(Terminal.iterm.rawValue, "iterm")
        XCTAssertEqual(Terminal.wezterm.rawValue, "wezterm")
        XCTAssertEqual(Terminal.warp.rawValue, "warp")
        // Oracle completeness: a new case has to gain a literal line in the list above too
        XCTAssertEqual(Terminal.allCases.count, 3)
    }

    func testStoredValueParsingFallsBackToITerm() {
        XCTAssertEqual(Terminal(storedValue: "iterm"), .iterm)
        XCTAssertEqual(Terminal(storedValue: "wezterm"), .wezterm)
        XCTAssertEqual(Terminal(storedValue: "warp"), .warp)
        // An unknown stored value (an identifier left by another version, a hand-edited plist) falls back to iTerm2 — the contract that gathers the fallback into the single parsing point so it cannot diverge per consumer
        XCTAssertEqual(Terminal(storedValue: "kitty"), .iterm)
        XCTAssertEqual(Terminal(storedValue: ""), .iterm)
    }
}

// MARK: - claude input preconditions (a known-undeliverable input rejects the request)
// Opening the tab and giving up only on the input answers success, so the button shows ✅ and the
// user is left with a claude session that has no context. **The argv track narrowed the
// condition**: what the judgement looks at is not "were claude inputs scheduled" but "is there a
// **tail** left after merging" (`PreparedRequest.claudeInputs`). Only what is knowable **before**
// any side effect belongs here — a failure after the tab exists has nothing to undo, so it is
// logged instead.

final class ClaudeInputPreconditionTests: XCTestCase {
    override func tearDown() {
        ClaudeInputGuidance.present = nil         // The hook is global, so it must not leak between tests
        super.tearDown()
    }

    /// iTerm2 and WezTerm read exactly their own screen by session or pane id, so they need no
    /// extra permission. (iTerm2's Automation permission is needed to run the command at all —
    /// without it osascript fails and the request is already rejected.)
    func testITermIsNeverBlockedBeforeLaunch() {
        XCTAssertNil(claudeInputBlocker(
            terminal: .iterm, injectsClaudeInput: true,
            accessibilityTrusted: false, injectionHelperReady: false
        ))
    }

    /// WezTerm is not "never undeliverable" — it is "not decidable **here**". Whether a pane can
    /// be addressed is only known once the mux has been asked, which is inside `runInWezTerm`
    func testWezTermIsNotDecidedBeforeLaunch() {
        XCTAssertNil(claudeInputBlocker(
            terminal: .wezterm, injectsClaudeInput: true,
            accessibilityTrusted: false, injectionHelperReady: false
        ))
    }

    /// **Round 4**: with no mux to spawn into, `runInWezTerm` starts a fresh process, and a pane
    /// in it cannot be addressed — `send-text`/`get-text` both need a mux pane id, so a scheduled
    /// input is dropped **after** the command has already run and the answer was `{success:true}`.
    /// Nothing has been spawned at that point, so it is a rejection like any other, raised at the
    /// fallback boundary through the same door
    func testWezTermFallbackWithScheduledInputIsRejectedBeforeSpawning() throws {
        var seen: [ClaudeInputBlocker] = []
        ClaudeInputGuidance.present = { seen.append($0) }

        let rejection = try XCTUnwrap(wezTermFallbackRejection(injectsClaudeInput: true))
        guard case TerminalError.claudeInputNotDeliverable(let blocker) = rejection else {
            return XCTFail("this has to be the dedicated rejection case: \(rejection)")
        }
        XCTAssertEqual(blocker, .wezTermSessionUnavailable)
        // …and the setup window stays where it is: it has no WezTerm control on it, so taking
        // focus away from Chrome to show it would explain nothing (`setupWindowCanHelp`)
        XCTAssertEqual(seen, [])
    }

    /// A button with nothing to type keeps the fallback — starting WezTerm for someone who does
    /// not have it running is the whole point of that branch
    func testWezTermFallbackWithoutScheduledInputStillRuns() {
        XCTAssertNil(wezTermFallbackRejection(injectsClaudeInput: false))
    }

    /// Regression: a Warp button with **no tail** still runs without the permission, exactly as
    /// it does today. Every shipped preset is in that case — this gate must not take back what
    /// the argv track won.
    func testWarpWithoutATailIsNotBlocked() {
        XCTAssertNil(claudeInputBlocker(
            terminal: .warp, injectsClaudeInput: false,
            accessibilityTrusted: false, injectionHelperReady: false
        ))
    }

    func testWarpWithoutAccessibilityIsBlockedBeforeAnyTabOpens() {
        XCTAssertEqual(
            claudeInputBlocker(
                terminal: .warp, injectsClaudeInput: true,
                accessibilityTrusted: false, injectionHelperReady: true
            ),
            .warpAccessibility
        )
    }

    func testWarpWithoutInjectionHelperIsBlocked() {
        XCTAssertEqual(
            claudeInputBlocker(
                terminal: .warp, injectsClaudeInput: true,
                accessibilityTrusted: true, injectionHelperReady: false
            ),
            .warpHelperUnavailable
        )
    }

    func testWarpWithEverythingReadyIsNotBlocked() {
        XCTAssertNil(claudeInputBlocker(
            terminal: .warp, injectsClaudeInput: true,
            accessibilityTrusted: true, injectionHelperReady: true
        ))
    }

    /// With both missing, name the permission — that is what the user has to do first, whereas
    /// the helper wording sends them to reinstall (which fixes nothing if it is a permission).
    func testAccessibilityIsReportedBeforeHelperWhenBothAreMissing() {
        XCTAssertEqual(
            claudeInputBlocker(
                terminal: .warp, injectsClaudeInput: true,
                accessibilityTrusted: false, injectionHelperReady: false
            ),
            .warpAccessibility
        )
    }

    /// This judgement runs inside the execQueue that holds up the Chrome response — a TCC or
    /// filesystem lookup on a request that cannot be blocked is button latency for nothing. So
    /// state is only queried for Warp with a tail.
    func testStateIsNotQueriedWhenTheAnswerCannotDependOnIt() {
        var queries = 0
        func probe() -> Bool {
            queries += 1
            return true
        }
        _ = claudeInputBlocker(
            terminal: .warp, injectsClaudeInput: false,
            accessibilityTrusted: probe(), injectionHelperReady: probe()
        )
        _ = claudeInputBlocker(
            terminal: .iterm, injectsClaudeInput: true,
            accessibilityTrusted: probe(), injectionHelperReady: probe()
        )
        _ = claudeInputBlocker(
            terminal: .wezterm, injectsClaudeInput: true,
            accessibilityTrusted: probe(), injectionHelperReady: probe()
        )
        XCTAssertEqual(queries, 0)
        // With the permission it goes on to the helper (2 lookups); without it, it stops there (1)
        _ = claudeInputBlocker(
            terminal: .warp, injectsClaudeInput: true,
            accessibilityTrusted: probe(), injectionHelperReady: probe()
        )
        XCTAssertEqual(queries, 2)
    }

    /// Each reason implies a different next action, so the wording has to differ — sharing one
    /// would send a user who needs to grant a permission off to reinstall.
    func testEachBlockerTellsADifferentNextAction() {
        let messages = ClaudeInputBlocker.allCases.map(\.message)
        XCTAssertFalse(messages.contains(where: \.isEmpty))
        XCTAssertEqual(Set(messages).count, messages.count, "\(messages)")
    }

    /// The setup window is only brought forward for reasons it can actually do something about.
    /// Stealing focus from Chrome to show a window with no WezTerm control on it is noise, and the
    /// hook used to ignore the reason entirely
    func testOnlyBlockersTheSetupWindowCanActOnBringItForward() {
        XCTAssertTrue(ClaudeInputBlocker.warpAccessibility.setupWindowCanHelp)
        XCTAssertTrue(ClaudeInputBlocker.warpHelperUnavailable.setupWindowCanHelp)
        XCTAssertFalse(ClaudeInputBlocker.wezTermSessionUnavailable.setupWindowCanHelp)
    }

    // MARK: The last check before the side effect (round 4, TOCTOU)

    /// **Round 4**: what `runInTerminal` checked can be gone by the time the Tab Config is
    /// written — the permission revoked, the helper removed by a reinstall. That branch used to
    /// log and run the command with no helper, which answers `{success:true}` with the input
    /// dropped: the exact symptom this loop exists to remove. Checked again as late as possible,
    /// it rejects
    func testWarpInjectionSetupRejectsWhenThePermissionWentAwayAfterTheEarlierCheck() {
        XCTAssertThrowsError(try warpInjectionSetup(
            token: "a1b2c3d4", injectsClaudeInput: true,
            accessibilityTrusted: false,
            helperExecutable: { "/x/helper" }, socketPath: { _ in "/tmp/tcw.sock" }
        )) { error in
            guard case TerminalError.claudeInputNotDeliverable(.warpAccessibility) = error else {
                return XCTFail("a lost permission has to be the dedicated rejection: \(error)")
            }
        }
    }

    func testWarpInjectionSetupRejectsWhenTheHelperWentAway() {
        XCTAssertThrowsError(try warpInjectionSetup(
            token: "a1b2c3d4", injectsClaudeInput: true,
            accessibilityTrusted: true,
            helperExecutable: { nil }, socketPath: { _ in "/tmp/tcw.sock" }
        )) { error in
            guard case TerminalError.claudeInputNotDeliverable(.warpHelperUnavailable) = error else {
                return XCTFail("a missing helper has to be the dedicated rejection: \(error)")
            }
        }
        XCTAssertThrowsError(try warpInjectionSetup(
            token: "a1b2c3d4", injectsClaudeInput: true,
            accessibilityTrusted: true,
            helperExecutable: { "/x/helper" }, socketPath: { _ in nil }
        ))
    }

    /// A button with nothing to type never touches any of this — no permission, no helper line
    func testWarpInjectionSetupIsSkippedEntirelyWithoutScheduledInput() throws {
        var probed = false
        XCTAssertNil(try warpInjectionSetup(
            token: "a1b2c3d4", injectsClaudeInput: false,
            accessibilityTrusted: { probed = true; return false }(),
            helperExecutable: { probed = true; return nil }, socketPath: { _ in nil }
        ))
        XCTAssertFalse(probed)
    }

    func testWarpInjectionSetupReturnsTheHelperLineAndItsSocket() throws {
        let setup = try XCTUnwrap(try warpInjectionSetup(
            token: "a1b2c3d4", injectsClaudeInput: true,
            accessibilityTrusted: true,
            helperExecutable: { "/x/warp helper" }, socketPath: { "/tmp/tcw-\($0).sock" }
        ))
        XCTAssertEqual(setup.socket, "/tmp/tcw-a1b2c3d4.sock")
        XCTAssertEqual(
            setup.line, warpHelperCommand(executable: "/x/warp helper", socketPath: setup.socket)
        )
    }

    /// Rejection and explanation go through one door — the contract that keeps any new rejection
    /// site from becoming "a ❌ with the reason nowhere".
    func testRejectionNotifiesTheGuidanceHookWithTheSameBlocker() {
        var seen: [ClaudeInputBlocker] = []
        ClaudeInputGuidance.present = { seen.append($0) }

        let error = claudeInputRejection(.warpHelperUnavailable)

        XCTAssertEqual(seen, [.warpHelperUnavailable])
        guard case .claudeInputNotDeliverable(let blocker) = error else {
            return XCTFail("an undeliverable rejection has to be the dedicated case — it must not be identified by its string")
        }
        XCTAssertEqual(blocker, .warpHelperUnavailable)
    }

    /// The headless server (`--headless-server`) installs no hook — the rejection still has to go out, carrying **the blocker's own wording** rather than a copy of it: the equality below is against `ClaudeInputBlocker.warpAccessibility.message`, so a literal spelled out at the throw site fails here
    func testRejectionWithoutAHookStillThrows() {
        ClaudeInputGuidance.present = nil
        XCTAssertEqual(
            errorMessage(claudeInputRejection(.warpAccessibility)),
            ClaudeInputBlocker.warpAccessibility.message
        )
    }

    /// **Wiring**: the judgement has to be the first line of `runInTerminal` for the rejection to
    /// beat the tab. A correct decision function with no wiring leaves the reproduced defect
    /// exactly as it was (the prefix runs and the answer is `{success:true}`). On a machine where
    /// the permission is granted this call would really open a Warp tab, so it skips there — the
    /// rule that agents and CI do not launch Warp comes first.
    func testRunInTerminalRejectsBeforeOpeningAnyTab() throws {
        try XCTSkipIf(
            accessibilityIsTrusted(),
            "the Accessibility permission is granted here — this path really would open a Warp tab"
        )
        // The reservation is what says this run injects, so the case has to hold one — and it gives
        // it back, because a slot left in the register refuses every restart after this case
        let admission = try XCTUnwrap(ClaudeDelivery.admit())
        defer { admission.end() }
        XCTAssertThrowsError(
            try runInTerminal(command: "claude", terminal: .warp, claudeInput: admission)
        ) { error in
            guard case TerminalError.claudeInputNotDeliverable(let blocker) = error else {
                return XCTFail("the dedicated rejection has to come before any tab is opened: \(error)")
            }
            XCTAssertEqual(blocker, .warpAccessibility)
        }
    }

    // The regression that a missing tail must **not** be rejected is covered as a pure function
    // by `testWarpWithoutATailIsNotBlocked`. Checking it through `runInTerminal` instead passes
    // the judgement, falls through to `runInWarp` and **really opens a Warp tab** (done once by
    // mistake in this round) — the passing branch has side effects, so unit tests stay off it.

    /// The shape in which the rejection reaches the extension — it only turns the button into a ❌
    /// on `{success:false}` (content.js `runButtonCommand`), so if this response shape breaks the
    /// failure goes quiet again.
    func testHandleRequestReportsClaudeInputRejectionAsFailure() {
        let resp = handleRequest(
            json: [
                "command_template": "z {repo} && claude",
                "variables": ["repo": "remy"],
                "claude_inputs": ["!gh pr view 1"],
            ],
            run: { _ in throw TerminalError.claudeInputNotDeliverable(.warpAccessibility) }
        )
        XCTAssertEqual(resp["success"] as? Bool, false)
        XCTAssertEqual(resp["error"] as? String, ClaudeInputBlocker.warpAccessibility.message)
    }
}

// MARK: - claude input boundary
// The split is still computed as prefix/tail, but since round 4 only **one bit of it is used**:
// an empty tail means the whole list merges into claude's opening message, and anything else
// means the whole list is typed (`prepareRequest`). The split itself is what the boundary rule
// defines, and it is what the property test can pin — no input lost or duplicated on the way to
// that answer. There are only two boundaries: (1) a line the input box reads specially — a slash
// command or a `#` memory line, which are only read that way as a whole message (put a banner in
// front and it becomes inert text); (2) a `!` that follows an interactive input, whose output was
// meant as context for the *next* instruction, so hoisting it into the opening message changes
// what the earlier one sees. Every other transition merges — the user chose the change in meaning
// from N responses to one.

final class ClaudeInputPlanTests: XCTestCase {
    /// **The rule this round is built on (user decision).** A `!` input has to reach claude's own
    /// shell mode, so it is **typed**, never pre-run and pasted: measured on 2.1.238, `claude --
    /// '!echo x'` arrives as an ordinary message and claude then runs it through its Bash tool —
    /// which can stop for a permission prompt, is a model judgement rather than a shell fact, and
    /// costs a turn. What the merge buys instead is **cycles**: a run of `!` inputs becomes one
    /// typed line joined with `;`, so three inputs are one type/submit cycle rather than three.
    func testARunOfShellInputsBecomesOneTypedLine() {
        let typed = claudeTypedInputs(["!gh pr view 42", "!gh pr diff 42", "!git status"])
        XCTAssertEqual(typed.count, 1, "a run of consecutive ! inputs was not merged into one cycle")
        XCTAssertEqual(
            typed.first,
            "!/bin/echo '==== !gh pr view 42 ===='; gh pr view 42;"
                + " /bin/echo '==== !gh pr diff 42 ===='; gh pr diff 42;"
                + " /bin/echo '==== !git status ===='; git status"
        )
    }

    /// `;` and not `&&`: each `!` used to run on its own, so a failure never stopped the next one.
    /// Keeping that is what makes the merge equivalent to what the user had (their correction)
    func testTheRunIsJoinedWithSemicolonsSoAFailureDoesNotStopTheRest() {
        let typed = claudeTypedInputs(["!false", "!echo after"])
        XCTAssertEqual(typed.count, 1)
        XCTAssertFalse(try XCTUnwrap(typed.first).contains("&&"))
        XCTAssertTrue(
            try XCTUnwrap(typed.first).contains("; /bin/echo '==== !echo after ===='; echo after")
        )
    }

    /// A lone `!` keeps its own shape — the banners exist to tell merged outputs apart, and with
    /// one command claude's shell mode already shows what ran
    func testASingleShellInputIsTypedAsItWas() {
        XCTAssertEqual(claudeTypedInputs(["!gh issue view 1"]), ["!gh issue view 1"])
    }

    /// A run ends at the first input that is not a `!`, and everything keeps its order
    func testRunsAreBrokenByOtherInputsAndOrderIsKept() {
        XCTAssertEqual(
            claudeTypedInputs(["!a", "!b", "summarise the design", "/review", "!c", "!d"]),
            [
                "!/bin/echo '==== !a ===='; a; /bin/echo '==== !b ===='; b",
                "summarise the design",
                "/review",
                "!/bin/echo '==== !c ===='; c; /bin/echo '==== !d ===='; d",
            ]
        )
    }

    /// Nothing may be lost or reordered on the way into the merged line — the property that
    /// mattered when the split was prefix/tail, restated for the new shape
    func testEveryInputSurvivesTheConversionInOrder() {
        let alphabet = ["!a", "!b", "plain", "/slash", "# memo", "!c"]
        for _ in 0..<400 {
            let inputs = (0..<Int.random(in: 0...6)).map { _ in alphabet.randomElement()! }
            let joined = claudeTypedInputs(inputs).joined(separator: "\n")
            var cursor = joined.startIndex
            for input in inputs {
                // the body of a `!` input appears with its `!` either kept (lone) or turned into
                // a banner + body (merged), so look for the text after the `!`
                let needle = input.hasPrefix("!") ? String(input.dropFirst()) : input
                guard let found = joined.range(of: needle, range: cursor..<joined.endIndex) else {
                    return XCTFail("\(inputs) → \(joined): \(input) was lost")
                }
                cursor = found.lowerBound         // Preserves order (the same input can repeat, so only the lower bound advances)
            }
        }
    }

    /// **Reproduction (round 11, Codex — blocking).** Joining bodies with `; ` is only sound if
    /// each body *ends* where it looks like it ends. Three shapes break that, and all three are a
    /// preset edit away (`# note` on a `gh` line, `npm run watch &`, a heredoc):
    ///
    ///  1. an unquoted `#` comments out the rest of the **merged line**, banners included
    ///  2. a trailing `&` produces `… &; …`, a syntax error that kills the whole line
    ///  3. `<<` swallows what follows as heredoc content
    ///
    /// Delivery is asynchronous, so the button still shows success. The fix is not a shell parser:
    /// a run merges only when **every** body is provably safe to join, and otherwise each input is
    /// typed on its own — slower, and exactly what it says.
    func testARunIsTypedSeparatelyWhenJoiningWouldChangeMeaning() {
        for run in [
            ["!printf '%s\n' one # note", "!printf '%s\n' two"],
            ["!sleep 0.01 &", "!printf '%s\n' two"],
            ["!cat <<EOF\nheredoc\nEOF", "!printf '%s\n' two"],
            ["!echo 'unterminated", "!printf '%s\n' two"],
            ["!echo one \\", "!printf '%s\n' two"],
            // …and three more the independent reviewer measured, all of which abort the whole
            // line rather than just their own command:
            ["!echo a;", "!printf '%s\n' two"],        // `…;; …` is a parse error
            ["!", "!printf '%s\n' two"],               // an empty body gives `; ;`
            ["!   ", "!printf '%s\n' two"],            // the request trims this one to `!`
            ["!echo ====", "!printf '%s\n' two"],      // zsh expands a word starting with `=`
        ] {
            XCTAssertEqual(claudeTypedInputs(run), run, "\(run) was merged")
        }
    }

    /// …and the shipped presets — plain `gh` invocations — must still merge, or the round-10 win
    /// is gone
    func testTheShippedPresetRunsStillMerge() {
        for run in [
            ["!gh pr view 42 --comments", "!gh pr diff 42"],
            [
                "!gh issue view 42", "!gh issue view 42 --comments",
                "!gh api repos/o/r/issues/42/timeline --jq '[.[]|select(.event==\"cross-referenced\")]'",
            ],
        ] {
            XCTAssertEqual(claudeTypedInputs(run).count, 1, "\(run) was not merged")
        }
    }

    /// **Measured (Q2b)**: separate `!` submissions do **not** share shell state — `!export X=1`
    /// then `!echo $X` prints nothing, because each `!` is a fresh eval. Merging them with `;`
    /// does share it, and that is a real difference in what runs: `["!cd sub", "!rm -rf build"]`
    /// deletes `./build` when typed separately and `sub/build` when merged. Deleting the wrong
    /// directory is the failure class this loop treats as blocking, so a body that changes shell
    /// state is not merged — it costs a cycle, and the shipped presets (read-only `gh`) never hit it
    func testABodyThatChangesShellStateIsNotMerged() {
        for run in [
            ["!cd sub", "!rm -rf build"],
            ["!export TOKEN=x", "!gh pr view 1"],
            ["!TOKEN=x gh pr view 1", "!gh pr diff 1"],
            ["!git fetch && cd ../worktree", "!gh pr diff 1"],
            ["!source .env", "!gh pr view 1"],
        ] {
            XCTAssertEqual(claudeTypedInputs(run), run, "\(run) was merged")
        }
        // …and the read-only shapes the presets actually use still merge
        XCTAssertEqual(claudeTypedInputs(["!gh pr view 1", "!gh pr diff 1"]).count, 1)
    }

    /// The merged line runs in **claude's** `!` shell, which is zsh-family (measured: a missing
    /// command reports `(eval):1: command not found`). A word starting with `=` is harmless in bash
    /// and an expansion error in zsh that takes the whole line with it, which is exactly the
    /// difference merging must not create — so the gate rejects it for every shell
    func testAWordThatOnlyZshWouldExpandStopsTheMerge() {
        XCTAssertFalse(claudeBodyJoinsSafely("echo ===="))
        XCTAssertFalse(claudeBodyJoinsSafely("=ls"))
        XCTAssertTrue(claudeBodyJoinsSafely("gh pr view 42 --jq '.title=\"x\"'"))
    }

    /// **Reproduction (round 13, Codex — blocking).** The gate used to call a `#` a comment only
    /// when a **space** came before it, so a `#` right after a separator was read as literal text
    /// and the run merged. It is a comment there too, and it swallows the rest of the merged line —
    /// banners and every later body included. Measured, all three shells, `echo one;# note; echo two`
    /// prints `one` and **exits 0**: the second input disappears with no error anywhere, and the
    /// button still reports success because delivery is asynchronous.
    ///
    /// `&&` and `|` are the same position: zsh takes `echo one&&# note` as `one` alone (exit 0),
    /// bash and dash as a syntax error that runs nothing at all.
    func testAnOperatorBeforeAHashIsNotProofThatItIsLiteral() {
        for run in [
            ["!echo one;# note", "!echo two"],
            ["!echo one&&# note", "!echo two"],
            ["!echo one|# note", "!echo two"],
            ["!echo one; # note", "!echo two"], // the round-11 shape, still folded
        ] {
            XCTAssertEqual(claudeTypedInputs(run), run, "\(run) was merged")
        }
    }

    /// The same guard was the only thing standing behind `=`, and it misread that position for the
    /// same reason: `echo one;=tcnosuchcmd` puts the word at a command position, where zsh expands
    /// it and **aborts the rest of the line** (measured: `one` prints, `two` never does)
    func testAnOperatorBeforeAnEqualsIsNotProofThatItIsLiteralEither() {
        XCTAssertEqual(
            claudeTypedInputs(["!echo one;=tcnosuchcmd", "!echo two"]),
            ["!echo one;=tcnosuchcmd", "!echo two"]
        )
    }

    /// **The gate now makes no judgement about position at all**, and that is the point: a rule of
    /// the form "this `#` is provably not a comment" has produced two silent-loss defects, and the
    /// gate is a whitelist, so the answer is to stop proving. The price is over-folding, which
    /// costs a type/submit cycle and never correctness — pinned here so it stays visible.
    func testTheGateFoldsEveryUnquotedHashAndEqualsIncludingLiteralOnes() {
        XCTAssertFalse(claudeBodyJoinsSafely("echo a#b"))        // literal in every shell, folded
        XCTAssertFalse(claudeBodyJoinsSafely("gh pr list --state=open")) // legal, folded
        // …and quoting still merges, which is what keeps the shipped presets on the fast path
        XCTAssertTrue(claudeBodyJoinsSafely("gh api x --jq '[.[]|select(.event==\"y\")]'"))
        XCTAssertTrue(claudeBodyJoinsSafely("echo '#not a comment'"))
        // A backslash-escaped one is data too — and measured to be disarmed: zsh reports a plain
        // `command not found` for `\=tcnosuchcmd` instead of expanding it
        XCTAssertTrue(claudeBodyJoinsSafely("echo a\\#b"))
    }

    /// The trailing-operator rule had no mirror and an incomplete list. Both edges of a body are
    /// spliced onto `; `, so an operator on either side is a parse error that runs **nothing** on
    /// the whole line (measured in zsh, bash and dash; zsh alone tolerates a leading `;`, and the
    /// gate is conservative across shells for the same reason the `=` rule is)
    func testABodyThatDoesNotStartOrEndWhereItLooksLikeItDoesIsNotMerged() {
        for run in [
            ["!echo one >", "!echo two"],   // `… >; …` — parse error
            ["!echo one <", "!echo two"],
            ["!;echo hi", "!echo two"],     // `…; ;echo hi` — parse error in bash and dash
            ["!|cat", "!echo two"],
            ["!&& echo hi", "!echo two"],
            ["!& echo hi", "!echo two"],
        ] {
            XCTAssertEqual(claudeTypedInputs(run), run, "\(run) was merged")
        }
    }

    /// **Reproduction (PR #36 review, Codex).** The separator cases consumed `;` and `|` one
    /// character at a time, so a malformed separator *sequence* — an empty command between two
    /// separators — passed the gate: `["!echo one ||| echo two", "!echo later"]` merged, the whole
    /// line died as a parse error in zsh, bash AND dash (measured), and `later` never ran, while
    /// separate submissions run it. Separators are now read as tokens: `|`, `||`, `&&` and a
    /// single `;` are valid only after a command word; anything else folds the run.
    func testMalformedSeparatorSequencesDoNotMerge() {
        for body in [
            "echo one ||| echo two", "echo one ||; echo two", "echo one |; echo two",
            "echo one ;; echo two", "echo one ; ; echo two", "echo one ;| echo two",
            "echo one && ; echo two", "echo one ; && echo two", "echo one | | echo two",
        ] {
            XCTAssertFalse(claudeBodyJoinsSafely(body), "\(body) was judged safe to join")
        }
        // …and every valid separator shape still merges — the gate must not fold real pipes
        for body in [
            "echo one | wc -l", "echo one || echo two", "gh pr view 1 && gh pr diff 1",
            "echo one; echo two", "gh api x --jq '.[]|.n'", "echo 'a ||| b'",
        ] {
            XCTAssertTrue(claudeBodyJoinsSafely(body), "\(body) was folded")
        }
    }

    /// **Reproduction (round 13, independent reviewer — 162 merged/separate runs in bash and zsh,
    /// 47 divergences).** Two families were missing from the state-word list:
    ///  - `exit` and `return` end the eval. Merged, `…; exit 0; …` prints nothing after itself and
    ///    **exits 0** (measured, zsh and bash for `exit`, zsh for `return`), so every later body
    ///    disappears with no error — the same silence as the `#` case
    ///  - words with no partner on the list: `setopt` had no `unsetopt`, `hash` no `unhash`, and
    ///    the name-binding family (`enable`/`disable`, `unfunction`, `autoload`, `zmodload`) and
    ///    the emulation switch (`emulate`) were absent altogether
    ///
    /// The list is not a claim of completeness — it is the second line, behind "anything the scan
    /// cannot read folds" — but a *missing partner* is a hole with no argument behind it.
    func testWordsThatEndTheLineOrRebindNamesAreNotMerged() {
        for body in [
            "exit 0", "return 0",
            "unsetopt nomatch", "unhash gh", "unfunction gh", "emulate sh",
            "disable echo", "enable -n echo", "zmodload zsh/pcre", "autoload -Uz compinit",
            "let x", "integer n", "float f", "read answer",
        ] {
            XCTAssertFalse(claudeBodyJoinsSafely(body), body)
        }
        // …and the shipped shapes are untouched
        XCTAssertTrue(claudeBodyJoinsSafely("gh pr diff 42"))
    }

    /// **Reproduction (round 14, independent reviewer).** The two scanners in this file disagreed
    /// about the same words: the append scanner folds `if`/`for`/`while`/`until`/`select` as
    /// "grammar we do not model", while the join gate waved them through. Both halves of that
    /// grammar bite on a merged line, and both were measured:
    ///  - the grammar the scan cannot see belongs to the **whole line**, not to one body:
    ///    `for i in 1 2 do echo x; done` (one `;` missing) is a parse error in zsh and bash, and
    ///    neither the body before it nor the one after it runs
    ///  - a *well-formed* compound still leaks: `for i in 1 2; do :; done` leaves `i=2` behind
    ///    (measured, both shells), and later bodies on the merged line read it, while separate `!`
    ///    submissions never could — item 117's class, reached through a word the gate did not fold
    ///
    /// So the keyword set lives in one constant that both scanners read.
    func testCompoundCommandKeywordsFoldInBothScanners() {
        for keyword in shellCompoundCommandKeywords {
            XCTAssertFalse(claudeBodyJoinsSafely("echo x \(keyword) y"), keyword)
            XCTAssertFalse(commandAcceptsAppendedClaudePrompt("\(keyword) && claude"), keyword)
        }
        XCTAssertEqual(
            claudeTypedInputs(["!for i in 1 2 do echo x; done", "!gh pr diff 1"]),
            ["!for i in 1 2 do echo x; done", "!gh pr diff 1"]
        )
        // …and the shipped preset run still merges — its `select` sits inside the `--jq` quotes,
        // which the scan skips whole
        XCTAssertEqual(
            claudeTypedInputs([
                "!gh issue view 42",
                "!gh api repos/o/r/issues/42/timeline --jq '[.[]|select(.event==\"x\")]'",
            ]).count,
            1
        )
    }

    /// A state-changing word does not stop being one because an operator or a backslash is stuck to
    /// it. `cd>/dev/null` really changes directory (measured: `cd /tmp; cd>/dev/null; pwd` prints
    /// `$HOME`), and so does `\c\d /usr` — both are the wrong-directory class of item 117, reached
    /// through a word the scan was splitting in the wrong place
    func testAStateChangingWordIsSeenThroughARedirectionOrAnEscape() {
        XCTAssertFalse(claudeBodyJoinsSafely("cd>/dev/null"))
        XCTAssertFalse(claudeBodyJoinsSafely("cd</dev/null"))
        XCTAssertFalse(claudeBodyJoinsSafely("\\c\\d sub"))
        XCTAssertEqual(
            claudeTypedInputs(["!cd>/dev/null", "!rm -rf build"]),
            ["!cd>/dev/null", "!rm -rf build"]
        )
    }

    /// The merged line reaches Warp as **one** injection payload, and the helper refuses anything
    /// over 8 KiB. Merging is the optimisation, so it is what gives way: a run that would exceed
    /// the ceiling is typed input by input — not a promise that each of them is short, since a single
    /// input has no limit of its own, only that the merge stops adding to it. Nothing is truncated
    func testARunTooLongToInjectInOnePieceIsTypedSeparately() {
        let long = "!gh api " + String(repeating: "x", count: 2500)
        XCTAssertEqual(claudeTypedInputs([long, long]), [long, long])
    }

    /// The banner cannot be hijacked by the body before it. `echo` is a shell builtin a body could
    /// redefine (`echo() { :; }`), and the merged line runs the bodies **before** the later
    /// banners — so the banner calls it by absolute path, which no function or alias can take over
    func testTheBannerCannotBeRedefinedByABody() {
        let merged = try? XCTUnwrap(claudeTypedInputs(["!echo one", "!echo two"]).first)
        XCTAssertEqual(merged?.contains("/bin/echo '==== !echo one ===='"), true, merged ?? "nil")
        XCTAssertEqual(merged?.contains("; echo '===="), false, merged ?? "nil")
    }

    /// Why the gate exists, shown in a real shell: the line we would have produced for the comment
    /// case runs only the first command, and the second never happens
    func testTheUnsafeJoinReallyLosesTheSecondCommandInARealShell() throws {
        let joined = "printf '%s\n' one # note; /bin/echo '==== two ===='; printf '%s\n' two"
        let result = try runProcess("/bin/sh", ["-c", joined], timeout: 10)
        XCTAssertEqual(result.stdout, "one\n", "the reproduction does not hold: \(result.stdout)")
    }

    /// The same, for the three shapes round 13 adds. None of them merely loses its own command:
    /// the rest of the merged line — later banners and bodies included — is either swallowed by a
    /// comment or never parses
    func testTheJoinsAddedInRoundThirteenAlsoRunNothingAfterThem() throws {
        for (label, joined) in [
            ("hash after a separator",
             "/bin/echo one;# note; /bin/echo '==== two ===='; /bin/echo two"),
            ("body ending in a redirection",
             "/bin/echo one >; /bin/echo '==== two ===='; /bin/echo two"),
            ("body starting with a separator",
             "/bin/echo one; ;/bin/echo hi; /bin/echo '==== two ===='; /bin/echo two"),
        ] {
            let result = try runProcess("/bin/sh", ["-c", joined], timeout: 10)
            XCTAssertFalse(
                result.stdout.contains("two"), "\(label): the reproduction does not hold — \(result.stdout)"
            )
        }
    }

    /// Plain text is just a message, so the whole list rides in argv when that is all there is —

    /// and only then (see the plan's dissent: mixing argv with typing in one session brings back
    /// the measured startup-clear race that round 4 removed)
    func testAllPlainTextBecomesTheOpeningMessage() {
        XCTAssertEqual(claudeArgvOpeningMessage(["summarise the design"]), "summarise the design")
        // **Exactly one.** Joining several with blank lines produced a message the newline guard
        // in `prepareRequest` then rejected, so two plain inputs could never ride argv — the join
        // was dead code pretending to be a feature (round 11, Codex). Several plain inputs are
        // typed, which is visible and needs no shell-specific quoting of newlines
        XCTAssertNil(claudeArgvOpeningMessage(["summarise the design", "then add tests"]))
        XCTAssertNil(claudeArgvOpeningMessage(["summarise the design", "!git status"]))
        XCTAssertNil(claudeArgvOpeningMessage(["!git status"]))
        XCTAssertNil(claudeArgvOpeningMessage(["/review"]))
        XCTAssertNil(claudeArgvOpeningMessage([]))
    }
}

final class ClaudeCommandTailTests: XCTestCase {
    func testTrailingClaudeMatches() {
        XCTAssertTrue(commandAcceptsAppendedClaudePrompt("claude"))
        XCTAssertTrue(commandAcceptsAppendedClaudePrompt("z remy && claude"))
        XCTAssertTrue(commandAcceptsAppendedClaudePrompt("z remy && claude  "))
        XCTAssertTrue(commandAcceptsAppendedClaudePrompt(
            "z r && git fetch origin && { git checkout b || cd ../r-b; } && claude"
        ))
    }

    /// One flag is enough to fall back, because some flags optionally take a value — measured:
    /// `claude -p --resume "Reply with exactly: OK"` → `--resume ... Provided value
    /// "Reply with exactly: OK" is not a UUID`. The appended prompt was swallowed as the **value**
    /// of `--resume`. The app has no table of claude's flags and that table changes between
    /// versions, so there is no way to tell which flags eat the next argument → fall back.
    func testAnyFlagAfterClaudeDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("z r && claude --resume"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude -c"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude --model=sonnet --resume"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude --model sonnet"))
    }

    func testClaudeNotAtACommandPositionDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("git commit -m claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("z claude-code"))
    }

    func testQuotedClaudeDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo 'claude'"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo \"claude\""))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo '&& claude'"))
    }

    func testPipeOrRedirectDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("cat f | claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude > out.txt"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude 2>&1"))
    }

    func testCommandContinuingAfterClaudeDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude && echo done"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude; echo done"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude &"))
    }

    /// Appending after a comment comments out the addition too — a silent loss, so fall back
    func testCommentedClaudeDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("z r && claude # later"))
    }

    // The next five are all **reproductions from the external reviewer**. A token heuristic only
    // looks at the last segment, and even when that segment looks like `claude` the syntax before
    // it changes the meaning entirely — these are what disproved "the worst a misjudgement can do
    // is lose the prompt silently" (comment = loss, heredoc = breakage, function definition =
    // **unintended execution**).

    /// Reproduction: a comment mid-command swallows the rest. The last token is `claude` but it
    /// never runs
    func testCommentEarlierInTheCommandDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo ready # && claude"))
    }

    /// Reproduction: the final `claude` is a heredoc **terminator**. Appending an argument changes
    /// the terminator, and the shell either hangs waiting for input or fails
    func testHeredocDelimiterThatLooksLikeClaudeDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("cat <<claude\nstuff\nclaude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("cat <<'EOF'\nx\nEOF\nclaude"))
    }

    /// Reproduction (the worst one): a shell function defined earlier captures the name `claude`,
    /// and the **plain-text input we appended is executed as a shell command.** Not a silent loss
    /// — arbitrary execution
    func testFunctionDefinitionCapturingTheNameDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude() { /bin/sh -c \"$1\"; }\nclaude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude() ( /bin/sh -c \"$1\" )\nclaude"))
    }

    // The next block is **round 4**: both external reviewers, independently, got a plain-text
    // input executed as a shell command through the *keyword* form of a function definition,
    // which has no `(` for a "word followed by `(`" rule to see. Enumerating definition syntaxes
    // is what let that through, so the judgement moved up to command-position words.

    /// Reproduction (both reviewers created a sentinel file with these): bash/zsh `function name`
    /// needs no parentheses, and zsh even accepts a brace-only body
    func testKeywordFunctionDefinitionDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("function claude { eval \"$@\"; }; claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt(
            "function claude { shift; /bin/sh -c \"$1\"; }; claude"
        ))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("function claude { echo hi }; claude"))
    }

    /// Reproduction: `{ }` has to stay allowed (a shipped preset uses it), so a definition can be
    /// **hidden inside the group**. Judging every command position catches it wherever it sits
    func testFunctionDefinitionHiddenInsideAGroupDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt(
            "{ function claude { eval \"$@\"; }; } && claude"
        ))
    }

    /// Everything that can bind the name `claude` to something else has to run as a **builtin or
    /// keyword in this same shell**, so it is visible in command position
    func testNameRebindingBuiltinsFold() {
        for command in [
            "alias claude='sh -c' && claude",
            "unalias claude; claude",
            "eval 'alias claude=sh' && claude",
            "source ./evil.sh && claude",
            ". ./evil.sh && claude",
            "hash -p /tmp/evil claude && claude",
            "autoload -Uz claude && claude",
            "trap 'alias claude=sh' DEBUG && claude",
            "enable -f ./evil.so claude && claude",
            "PATH=/tmp/evil:/usr/bin && claude",
            "export PATH=/tmp/evil:/usr/bin; claude",
            "declare -x PATH=/tmp/evil; claude",
        ] {
            XCTAssertFalse(commandAcceptsAppendedClaudePrompt(command), command)
        }
    }

    /// A command modifier keeps the rebinding in **this** shell instead of a child, so it can
    /// carry one of the words above behind it
    func testCommandModifiersThatKeepRebindingInThisShellFold() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("builtin eval 'alias claude=sh' && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("command eval x && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("time eval x && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("! eval x && claude"))
    }

    /// Quoting does not stop a builtin (`'eval' x` runs eval) and an expansion hides the name
    /// entirely — a command name we cannot read as plain text folds
    func testCommandNameWeCannotReadAsTextFolds() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("'eval' 'alias claude=sh' && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("\"eval\" x && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("$RUNNER build && claude"))
    }

    /// Compound commands are grammar this scanner does not model (it models one flat chain of
    /// simple commands). It folds rather than guess — `then`, `do` and friends open command
    /// positions that a flat segment scan does not see
    func testCompoundCommandsFold() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("if true; then function claude { :; }; fi; claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("for f in a b; do echo x; done && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("while true; do break; done && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("case x in y) echo z;; esac && claude"))
    }

    /// **Reproduction (round 5, both reviewers, sentinel confirmed)**: reading only the *first*
    /// word of a segment as the command position is wrong. A redirection (`> /dev/null eval …`)
    /// and a zsh precommand modifier (`noglob`, `nocorrect`, `-`) both sit in front of the command
    /// name, so the scanner read `/dev/null` / `noglob` as the command and never saw the `eval`
    /// behind it — a plain-text claude input then ran as a shell command
    func testWordsInFrontOfTheCommandNameCannotHideARebinding() {
        for command in [
            "> /dev/null eval 'claude() { shift; /bin/sh -c \"$1\"; }' && claude",
            "noglob eval 'claude() { :; }' && claude",
            "nocorrect eval 'claude() { :; }' && claude",
            "- eval 'claude() { :; }' && claude",
            "2>/dev/null eval x && claude",
        ] {
            XCTAssertFalse(commandAcceptsAppendedClaudePrompt(command), command)
        }
    }

    /// A word we cannot read is not safe just because something precedes it — that something may
    /// be a modifier, which is exactly what we stopped trying to enumerate
    func testAWordWeCannotReadFoldsWhereverItSits() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("noglob 'eval' 'claude() { :; }' && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("$RUNNER eval x && claude"))
    }

    /// zsh's `zmodload` is bash's `enable` — the pair was asymmetric. It is also the only way to
    /// make `claude` a **builtin**, and `command` does not bypass builtins (it bypasses functions
    /// and aliases), so this is the one rebinding the structural half cannot answer
    func testModuleLoadingFolds() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("zmodload zsh/parameter && claude"))
    }

    /// An assignment with a subscript is still an assignment — zsh's `functions[claude]=…` rebinds
    /// the name, and the name check used to stop at the first `[`
    func testSubscriptedAssignmentCountsAsAnAssignment() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("functions[claude]=x && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("PATH[1]=/tmp && claude"))
    }

    /// The price of not looking for the command position: an ordinary **argument** spelled like one
    /// of those words folds too. That is the safe direction — the request falls back to typing,
    /// which is what it did before the merge existed — and the shipped presets are unaffected
    /// (`testGroupsAndSubshellsInShippedPresetsStillMatch`)
    func testAFoldWordUsedAsAnArgumentAlsoFolds() {
        // The common shapes that lose the merge, pinned so the cost stays visible. On Warp without
        // the Accessibility permission these are not merely slower: everything then has to be
        // typed, and a button that cannot be delivered is refused (README "Known limits")
        for command in [
            "git add . && claude",
            "echo function && claude",
            "export FOO=1 && claude",
            "ANTHROPIC_MODEL=opus claude",
            "source ~/.nvm/nvm.sh && claude",
            "direnv exec . claude",
        ] {
            XCTAssertFalse(commandAcceptsAppendedClaudePrompt(command), command)
        }
        XCTAssertTrue(commandAcceptsAppendedClaudePrompt("git add -A && claude"))
    }

    /// Whitespace that is not a space or a tab is not a word separator to the shell: `claude\r`
    /// is a **different command name** and fails with "command not found" once we append to it
    func testExoticWhitespaceAfterClaudeDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("z r && claude\r"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("z r && claude\u{00A0}"))
    }

    /// Appending after a backgrounding `&` makes the argument **the next command**
    func testBackgroundOperatorDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("sleep 1 & claude"))
    }

    /// Command substitution, backticks, line continuations and newlines all change the structure
    /// the judgement reads — any one of them folds it
    func testSubstitutionsAndLineContinuationsDoNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo $(date) && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo `date` && claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo a \\\n&& claude"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("echo a\nclaude"))
    }

    /// Regression: the groups and subshells in the shipped presets are **not function
    /// definitions** — folding on those would cost `Start Work on Issue` (a preset that has claude
    /// inputs) its argv track
    func testGroupsAndSubshellsInShippedPresetsStillMatch() {
        XCTAssertTrue(commandAcceptsAppendedClaudePrompt(
            "z r && git fetch origin && { git checkout b || cd ../r-b; } && claude"
        ))
        XCTAssertTrue(commandAcceptsAppendedClaudePrompt(
            "z r && git fetch origin && ([ -d ../r-issue-1 ] || git worktree add -f ../r-issue-1"
                + " -b issue-1 origin/main) && cd ../r-issue-1 && claude"
        ))
    }

    /// With a positional prompt already there, ours would be a second one and the meaning splits
    func testExistingPositionalPromptDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude 'do it'"))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("claude fix-it"))
    }

    func testEmptyOrTrailingSeparatorDoesNotMatch() {
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt(""))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("z r && "))
        XCTAssertFalse(commandAcceptsAppendedClaudePrompt("z r && claude;"))
    }
}

// MARK: - Does the appended command survive each terminal's quoting?
// Conversion and appending are Core work that happens **before** the terminal branch, so all three
// terminals receive the same string. It carries the user's own text in single quotes, and iTerm2
// embeds it in an AppleScript literal while Warp embeds it in a TOML basic string — break it here
// and the tab either never opens or runs a truncated command.

final class AppendedPromptPerTerminalTests: XCTestCase {
    private let command = appendedPromptCommand(
        "z remy && claude", message: "설계 정리해줘 — it's \"quoted\" $HOME `now`"
    )

    /// Asks osascript whether it really parses as an AppleScript literal — with no
    /// `tell application` it touches no terminal and needs no permission.
    ///
    /// It goes through `runAppleScript` because that is the carrier the shipped path uses, and the
    /// second assertion is on **bytes**: `XCTAssertEqual` on the strings passes for NFC and NFD
    /// alike, so on the old carrier the string check below was green while the Korean in this very
    /// command was being decomposed.
    func testAppleScriptLiteralParsesBackToTheSameCommand() throws {
        let result = try runAppleScript("return \"\(escapeForAppleScript(command))\"", timeout: 30)
        XCTAssertEqual(result.status, 0, result.stderr)
        let out = result.stdout.trimmingCharacters(in: .newlines)
        XCTAssertEqual(out, command)
        XCTAssertEqual(Array(out.utf8), Array(command.utf8), "the literal came back re-encoded")
    }

    /// Every `"` inside a TOML basic string has to be escaped — one leaking is enough for Warp to
    /// fail parsing the file, and then no tab opens
    func testTOMLEscapesEveryQuoteInTheAppendedCommand() {
        let toml = warpTabConfigTOML(commands: [command])
        XCTAssertTrue(toml.contains("commands = [\"\(escapeForTOMLBasicString(command))\"]"), toml)
        var previous: Character = " "
        for character in escapeForTOMLBasicString(command) {
            if character == "\"" { XCTAssertEqual(previous, "\\", "an unescaped quote") }
            previous = character
        }
    }

    /// WezTerm passes the command as process arguments or stdin rather than as a shell string, so
    /// there is no re-quoting to check. What matters instead is that it stays on one line:
    /// `send-text` treats a newline as a submission (which is also why a message containing one
    /// never gets appended — `prepareRequest`)
    func testAppendedCommandStaysOnASingleLine() {
        XCTAssertFalse(command.contains("\n"), command)
    }

    /// The message is the user's text and it is **never evaluated**: single-quoted, with the
    /// quotes inside escaped the only way a POSIX shell allows
    func testTheMessageIsSingleQuotedSoTheShellNeverEvaluatesIt() throws {
        let hostile = "don't; touch /tmp/tc-should-not-exist $(id) `id`"
        let line = appendedPromptCommand("printf '%s'", message: hostile)
        let result = try runProcess("/bin/sh", ["-c", line], timeout: 10)
        // `printf '%s'` reapplies its format per argument, so the two arrive back to back
        XCTAssertEqual(result.stdout, "--" + hostile, "the body was evaluated by the shell")
        XCTAssertFalse(FileManager.default.fileExists(atPath: "/tmp/tc-should-not-exist"))
    }
}

// MARK: - Request preparation (the new rules applied to a real request)

final class PreparedRequestTests: XCTestCase {
    /// Regression: a request with no claude inputs has its command changed by **not one byte**
    func testRequestWithoutClaudeInputsIsUntouched() {
        let prepared = prepareRequest(ResolvedRequest(command: "z remy && claude", claudeInputs: []))
        XCTAssertEqual(prepared.command, "z remy && claude")
        XCTAssertEqual(prepared.claudeInputs, [])
    }

    /// **The shipped presets are all `!`, so they are all typed now** — one cycle for the whole
    /// run, and the command is left exactly as the user wrote it. This is the round-10 reversal:
    /// those buttons need the Warp Accessibility permission again
    func testShippedPresetInputsAreTypedAsOneMergedLine() {
        let prepared = prepareRequest(ResolvedRequest(
            command: "z remy && claude",
            claudeInputs: ["!gh pr view 42 --comments", "!gh pr diff 42"]
        ))
        XCTAssertEqual(prepared.command, "z remy && claude", "the command changed")
        XCTAssertEqual(prepared.claudeInputs.count, 1)
        XCTAssertEqual(
            prepared.claudeInputs.first,
            "!/bin/echo '==== !gh pr view 42 --comments ===='; gh pr view 42 --comments;"
                + " /bin/echo '==== !gh pr diff 42 ===='; gh pr diff 42"
        )
    }

    /// Plain text, and nothing else, rides in argv — no substitution, no temp file
    func testAllPlainTextRidesInArgv() {
        let prepared = prepareRequest(ResolvedRequest(
            command: "z remy && claude", claudeInputs: ["설계 정리해줘"]
        ))
        XCTAssertEqual(prepared.command, "z remy && command claude -- '설계 정리해줘'")
        XCTAssertEqual(prepared.claudeInputs, [])
    }

    /// **Never both in one session** (the plan's dissent): the argv message's own submission
    /// clears the input box seconds after claude starts, and anything typed before that render is
    /// wiped (measured). A list that mixes plain text with anything else is typed in full
    func testAMixedListIsTypedInFullRatherThanSplitBetweenArgvAndTyping() {
        let prepared = prepareRequest(ResolvedRequest(
            command: "z remy && claude", claudeInputs: ["summarise the design", "!git status"]
        ))
        XCTAssertEqual(prepared.command, "z remy && claude")
        XCTAssertEqual(prepared.claudeInputs, ["summarise the design", "!git status"])
    }

    /// A newline in the message would end the command line early — iTerm2 writes it with
    /// `write text`, WezTerm with `send-text`, and both read a newline as "run it now"
    func testAMessageWithANewlineIsTypedInsteadOfAppended() {
        let inputs = ["first line\nsecond line"]
        let prepared = prepareRequest(ResolvedRequest(command: "z remy && claude", claudeInputs: inputs))
        XCTAssertEqual(prepared.command, "z remy && claude")
        XCTAssertEqual(prepared.claudeInputs, inputs)
    }

    /// A command that cannot take the append types instead — today's behaviour
    func testUnappendableCommandFallsBackToTyping() {
        let inputs = ["summarise the design"]
        let prepared = prepareRequest(ResolvedRequest(command: "z remy", claudeInputs: inputs))
        XCTAssertEqual(prepared.command, "z remy")
        XCTAssertEqual(prepared.claudeInputs, inputs)
    }

    /// **Round 6 (independent reviewer)**: with `claude` installed only as a function or an alias,
    /// `command claude` would fail with "command not found" while the setup window still shows ✅
    func testMergingNeedsAClaudeExecutableNotJustAWrapper() {
        let inputs = ["summarise the design"]
        let prepared = prepareRequest(
            ResolvedRequest(command: "z remy && claude", claudeInputs: inputs),
            claudeIsExecutable: false
        )
        XCTAssertEqual(prepared.command, "z remy && claude")
        XCTAssertEqual(prepared.claudeInputs, inputs)
    }

    /// csh and tcsh: the appended text is a parse error that takes the whole line with it, so the
    /// login shell has to be POSIX-family before anything is appended
    func testANonPOSIXLoginShellFallsBackToTyping() {
        let inputs = ["summarise the design"]
        let prepared = prepareRequest(
            ResolvedRequest(command: "z remy && claude", claudeInputs: inputs),
            loginShell: "/bin/tcsh"
        )
        XCTAssertEqual(prepared.command, "z remy && claude")
        XCTAssertEqual(prepared.claudeInputs, inputs)
    }

    /// The sweep that clears what **older builds** left in the temp directory runs for every
    /// request, not only the ones that would have created something
    func testEveryRequestReclaimsWhatOlderBuildsLeftBehind() throws {
        let directory = NSTemporaryDirectory() + claudePromptDirectoryPrefix + "ffffffff"
        try? FileManager.default.removeItem(atPath: directory)
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        try "old".write(
            toFile: directory + "/" + legacyContextFileName, atomically: true, encoding: .utf8
        )
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-7 * 3600)], ofItemAtPath: directory
        )
        _ = prepareRequest(ResolvedRequest(command: "z remy", claudeInputs: []))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory))
    }
}

/// What an **older build** wrote into each request's directory. The app has no constant for it
/// any more — nothing creates these files since round 10 — but the sweep still has to recognise
/// and clear what those installations left behind.
private let legacyContextFileName = "context.txt"

final class ClaudePromptReclaimTests: XCTestCase {
    private var root = ""

    override func setUpWithError() throws {
        root = NSTemporaryDirectory() + "tc-reclaim-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(atPath: root)
    }

    @discardableResult
    private func makeDirectory(
        _ name: String, ageHours: Double, files: [String] = [legacyContextFileName]
    ) throws -> String {
        let path = root + "/" + name
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        for file in files { try "x".write(toFile: path + "/" + file, atomically: true, encoding: .utf8) }
        let old = Date().addingTimeInterval(-ageHours * 3600)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: path)
        return path
    }

    func testStaleLeftoverDirectoryIsReclaimed() throws {
        let path = try makeDirectory("tc-prompt-a1b2c3d4", ageHours: 7)
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    func testFreshDirectoryIsLeftAlone() throws {
        let path = try makeDirectory("tc-prompt-a1b2c3d5", ageHours: 1)
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    /// **Reproduction (round 5, Codex)**: age alone cannot tell "has not been used yet" from "died
    /// unused". With `sleep 21601 && claude` the script is still waiting to run six hours later,
    /// and another request's sweep reclaimed it — the command then started claude with the
    /// lost-context notice. The script's own presence is the observation: it deletes itself as it
    /// runs, so **still there** means nothing has consumed it
    func testAScriptThatHasNotRunYetSurvivesTheShortAge() throws {
        let path = try makeDirectory(
            "tc-prompt-b1b2c3d4", ageHours: 7,
            files: [claudePromptScriptName, legacyContextFileName]
        )
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    /// It is still reclaimed eventually — a tab that never opened must not leak forever
    func testAScriptThatNeverRanIsReclaimedEventually() throws {
        let path = try makeDirectory(
            "tc-prompt-b1b2c3d5", ageHours: 24 * 8, files: [claudePromptScriptName]
        )
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// A context handed to claude because it was over budget has to survive past six hours — the
    /// session reads it then. Deleting it leaves claude unable to find the file it was told to read
    func testContextHandedToClaudeSurvivesTheShortAge()
        throws {
        let path = try makeDirectory(
            "tc-prompt-a1b2c3d6", ageHours: 30,
            files: [legacyContextFileName, claudePromptHandoffName]
        )
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    func testContextHandedToClaudeIsReclaimedEventually() throws {
        let path = try makeDirectory(
            "tc-prompt-a1b2c3d7", ageHours: 24 * 8,
            files: [legacyContextFileName, claudePromptHandoffName]
        )
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path))
    }

    /// Upper-case hex is not a name we write (`%08x`) and not a name `uninstall.sh` matches. Both
    /// sides have to agree on which names are ours — reclaiming one we never wrote is deleting
    /// somebody else's directory
    func testUpperCaseHexIsNotOneOfOurNames() throws {
        let path = try makeDirectory("tc-prompt-ABCDEF01", ageHours: 100)
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    /// **Reproduction (round 7, Codex)**: `Character.isNumber` is Unicode-wide, so a token of
    /// Arabic-Indic digits passed as "hex" and the sweep would have deleted a directory we never
    /// wrote. Ours are ASCII `[0-9a-f]`, because that is what `%08x` and `uninstall.sh` produce
    func testUnicodeDigitsAreNotHexAndNotOurNames() throws {
        // Measured (`Character` predicates): `١` is `isNumber` but not `isHexDigit` — that is the
        // one the old `isNumber ||` test let through — while the fullwidth `０` and `ｆ` **are**
        // `isHexDigit`, which is why the ASCII test is the one doing the work now
        for name in ["tc-prompt-١٢٣٤abcd", "tc-prompt-０１２３abcd"] {
            let path = try makeDirectory(name, ageHours: 100)
            reclaimStaleClaudePromptDirectories(in: root)
            XCTAssertTrue(FileManager.default.fileExists(atPath: path), name)
        }
        // The same class, same fix, in the helper socket names
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-０１２３abcd.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-١٢٣٤abcd.sock"))
        XCTAssertTrue(warpHelperSocketFileIsOurs(name: "tcw-a1b2c3d4.sock"))
    }

    /// **Reproduction (round 7, Codex)**: the re-check before removal compared whole seconds, so a
    /// pane that started consuming the directory inside the same second was missed. Every form of
    /// consumption bumps the directory's mtime — the comparison has to see sub-second changes
    func testADirectoryConsumedWithinTheSameSecondIsLeftAlone() throws {
        let path = try makeDirectory("tc-prompt-c0ffee01", ageHours: 7)
        var sampled = stat()
        XCTAssertEqual(lstat(path, &sampled), 0)
        let sameSecond = Date(timeIntervalSince1970: TimeInterval(sampled.st_mtimespec.tv_sec))
            .addingTimeInterval(0.4)
        reclaimStaleClaudePromptDirectories(in: root, justBeforeRemoving: { consumed in
            try? FileManager.default.setAttributes(
                [.modificationDate: sameSecond], ofItemAtPath: consumed
            )
        })
        XCTAssertTrue(FileManager.default.fileExists(atPath: path))
    }

    /// Someone else's entries are never touched, whatever their age, and symlinks are never
    /// followed — following one would delete the whole directory it points at
    func testForeignEntriesAndSymlinksAreNeverTouched() throws {
        let foreign = try makeDirectory("important-a1b2c3d4", ageHours: 100)
        let victim = try makeDirectory("victim", ageHours: 100)
        let link = root + "/tc-prompt-deadbeef"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: victim)
        reclaimStaleClaudePromptDirectories(in: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: foreign))
        XCTAssertTrue(FileManager.default.fileExists(atPath: victim))
    }
}

// MARK: - Delivery order and failure recovery
// The delivery loop calls osascript and the wezterm cli, but the order, the retries and the stop verdicts have to be verifiable without any processes — ClaudeSessionIO swaps out exactly those calls.

/// A stand-in for a claude session. It mirrors whatever is typed into the input box (box) onto the screen, and on receiving a CR it treats that as a submission and empties the box.
private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Delivery stage instrumentation (round 15)
// A successful delivery used to log one line, at the end. When a real run took 86 seconds between
// the tab opening and the first submission, nothing in the log could say where they went — helper
// wait, claude startup, or the user not looking at the tab. These pin the shape of the stopwatch
// and the fact that the delivery loop actually drives it.

final class DeliveryTimelineTests: XCTestCase {
    /// Every step reports **both** numbers: the gap from the previous step (which stage was slow)
    /// and the total since the request arrived (the metric this round exists for — button press to
    /// the first CR).
    func testEachStepReportsTheGapFromThePreviousStepAndTheTotal() {
        var clock = Date(timeIntervalSince1970: 1_000)
        var lines: [String] = []
        let timeline = DeliveryTimeline(now: { clock }, emit: { lines.append($0) })
        timeline.step("request received")
        clock = clock.addingTimeInterval(3.2)
        timeline.step("Warp tab created")
        clock = clock.addingTimeInterval(86)
        timeline.step("claude ready")
        XCTAssertEqual(lines, [
            "request received (+0.0s, total 0.0s)",
            "Warp tab created (+3.2s, total 3.2s)",
            "claude ready (+86.0s, total 89.2s)",
        ])
    }

    /// The stopwatch is only worth anything if the delivery loop drives it. One input has to log
    /// its pane proof, its reflection check and its submission — that split is what tells a slow
    /// claude apart from a user who is looking at another tab.
    func testTheDeliveryLoopLogsEveryStepOfAnInput() {
        let session = FakeClaudeSession()
        var lines: [String] = []
        // A frozen clock, so this pins the **shape** of the output rather than its timings
        let timeline = DeliveryTimeline(
            now: { Date(timeIntervalSince1970: 0) }, emit: { lines.append($0) }
        )
        XCTAssertEqual(submitClaudeInputs(["!gh pr diff 1"], io: session.io, timeline: timeline), 1)
        XCTAssertEqual(lines, [
            "input 1/1 pane proof passed (attempt 1/12) (+0.0s, total 0.0s)",
            "input 1/1 body reflection confirmed (+0.0s, total 0.0s)",
            // The "total" on this line is the number the user is complaining about: press to submit
            "input 1/1 submission (CR) sent (+0.0s, total 0.0s)",
            "input 1/1 post-check: the input box state is unknown (+0.0s, total 0.0s)",
        ])
    }

    /// The attempt counter is the whole point of the pane-proof line: on Warp the proof only
    /// passes while the user is looking at that tab, so "passed (attempt 3/5)" with a large gap is the
    /// evidence for telling them so, rather than a defect to chase
    func testThePaneProofLineCarriesHowManyAttemptsItTook() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        session.failScreenAt = [1]         // The first attempt's screen read fails → it passes on the second
        var lines: [String] = []
        let timeline = DeliveryTimeline(
            now: { Date(timeIntervalSince1970: 0) }, emit: { lines.append($0) }
        )
        _ = submitClaudeInputs(["!gh pr diff 1"], io: session.io, timeline: timeline)
        XCTAssertTrue(
            lines.contains { $0.hasPrefix("input 1/1 pane proof passed (attempt 2/12)") }, "\(lines)"
        )
    }

    /// No timeline, no lines — the tests above are the only callers that pass one, and every other
    /// test in this file must keep running against an unchanged loop.
    func testWithoutATimelineNothingIsEmitted() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs(["!gh pr diff 1"], io: session.io), 1)
        XCTAssertEqual(session.submitted, ["!gh pr diff 1"])
    }
}

private final class FakeClaudeSession {
    private(set) var keystrokes: [String] = []
    private(set) var submitted: [String] = []
    var sessionAlive = true
    /// Fails the nth sendKeys call (1-based) — the situation where the terminal CLI fails once
    var failSendAt: Set<Int> = []
    /// Fails the nth screenText call (1-based)
    var failScreenAt: Set<Int> = []
    /// claude discards the text the nth sendKeys sent (1-based) — the moment where the TUI has not drawn the input box yet. The send succeeds and only the screen fails to show it
    var dropTypingAt: Set<Int> = []
    /// Text already sitting in the input box (used to build the failed-clear situation)
    var presetBox = "" { didSet { box = presetBox } }
    /// Text already on screen (used to build the situation where another pane is being read)
    var screenPrefix = ""
    /// What the claude TUI draws **below** the input box — hint lines, the permission indicator, the context %, a clock.
    /// Without these the region `screenTail` looks at (from our input to the end of the screen) is not represented, so a defect like "a probe that also appears in the bottom chrome pins the tail forever" is invisible in the fake (independent reviewer's point)
    var bottomChrome = "? for shortcuts"
    /// Something below the box that changes on every read — a context meter, a clock. Then the
    /// tail differs every time and the look can never say "stuck" (reviewer's R6), which is why
    /// the safety of the next input cannot rest on that look
    var tickingChrome = false
    /// Text that newly appears from the nth `screenText` call onwards
    var screenGains: [Int: String] = [:]
    /// What was already on screen when the first byte went out — pins "what did it see before typing"
    private(set) var screenPrefixAtFirstSend: String?
    /// A submitted message stays on screen, in the transcript — that is what claude does, and it
    /// is what `inputBoxAfterSubmit` reads. Turning this on models **the input box losing our text
    /// instead of submitting it**: the CR goes out and nothing appears anywhere
    var dropSubmittedFromScreen = false
    /// The CR is reported as sent and **nothing happens**: the input box keeps our text and the
    /// transcript never gets it (round 5 reproduction — a TUI that has not consumed the CR)
    var submitDoesNothing = false
    /// The same for Ctrl+U: the write is accepted, the TUI never acts on it. An AppleScript or a
    /// CLI call returning success means the terminal took the bytes, not that claude processed
    /// them (round 8, both reviewers)
    var clearDoesNothing = false
    /// **Measured (2.1.238, pty)**: Ctrl+U on a `!…` line clears the text but **leaves the `!`**,
    /// so the box stays in shell mode and looks empty. Whatever is typed next is submitted as a
    /// shell command. One Backspace after the Ctrl+U removes the prefix (also measured)
    var clearLeavesModePrefix = true
    /// **The user presses Enter** right after our nth send lands (1-based). On Warp they are
    /// looking at that tab by design, so this is not exotic: whatever is in the box at that moment
    /// is submitted by them, not by us (round 9)
    var userPressesEnterAfterSend: Int?
    /// The nth `sendKeys` reports failure **although the bytes went in** (1-based). The helper
    /// injecting part of a write and then erroring looks exactly like this from here, and it is
    /// the only shape in which a resend can duplicate a message
    var deliverButReportFailureAt: Set<Int> = []
    /// A terminal whose screen reads are not pane-accurate (Warp)
    var screenNeedsPaneProof = false
    /// The situation where the screen being read is not our pane — our typing never shows up on it
    var screenIsForeign = false
    /// Text that other pane gains later (Codex's reproduction: the count increases)
    var foreignScreenGains: [String] = []
    /// Every synthetic wait, and the order of reads/waits/sends. The delivery loop's speed is a
    /// property worth pinning: a poll that sleeps **before** its first read pays a full interval
    /// for a screen that is already drawn (round 10)
    private(set) var waits: [TimeInterval] = []
    private(set) var events: [String] = []
    private(set) var sendCallCount = 0
    /// How many times the gate was checked immediately before bytes went out
    private(set) var gateChecks = 0
    private var screenCalls = 0
    private var box = ""
    private var history = ""
    private var foreignScreen = "another pane's screen"

    var io: ClaudeSessionIO {
        ClaudeSessionIO(
            sendKeys: { [unowned self] keys in
                sendCallCount += 1
                events.append("send")
                if screenPrefixAtFirstSend == nil { screenPrefixAtFirstSend = screenPrefix }
                if failSendAt.contains(sendCallCount) { return false }
                let reported = !deliverButReportFailureAt.contains(sendCallCount)
                keystrokes.append(keys)
                if keys == claudeSubmitKey {
                    // A CR into an **empty** box does nothing (measured) — modelling it as an
                    // empty submission would hide the duplicate a resend can cause
                    if !box.isEmpty, !submitDoesNothing {
                        submitted.append(box)
                        if !dropSubmittedFromScreen { history += box + " " }
                        box = ""
                    }
                } else if dropTypingAt.contains(sendCallCount) {
                    // claude drew nothing for this send
                } else {
                    // Byte by byte, the way a terminal sees it — so a change that drops the
                    // Backspace from the clear sequence shows up here rather than passing
                    for character in keys {
                        switch character {
                        case "\u{15}" where !clearDoesNothing:
                            box = clearLeavesModePrefix && box.hasPrefix("!") ? "!" : ""
                        case "\u{15}":
                            break // the write was accepted, the TUI ignored it
                        case "\u{7f}":
                            if !box.isEmpty, !clearDoesNothing { box.removeLast() }
                        default:
                            box.append(character)
                        }
                    }
                    if foreignScreenGains.contains(keys) { foreignScreen += " " + keys }
                }
                if sendCallCount == userPressesEnterAfterSend, !box.isEmpty {
                    submitted.append(box)         // An Enter the user pressed — not our CR
                    history += box + " "
                    box = ""
                }
                return reported
            },
            screenText: { [unowned self] in
                screenCalls += 1
                events.append("read")
                if let gained = screenGains[screenCalls] { screenPrefix += " " + gained }
                if failScreenAt.contains(screenCalls) { return nil }
                if screenIsForeign { return foreignScreen }
                let ticker = tickingChrome ? " \(screenCalls)% context left" : ""
                return screenPrefix + " " + history + "❯ " + box + "\n" + bottomChrome + ticker
            },
            confirmSession: { [unowned self] _ in sessionAlive },
            sessionIsUnchanged: { [unowned self] in
                gateChecks += 1
                return sessionAlive
            },
            screenNeedsPaneProof: screenNeedsPaneProof,
            wait: { [unowned self] seconds in
                waits.append(seconds)
                events.append("wait")
            }
        )
    }
}

// MARK: - The two delivery routes are never mixed in one session
// Measured (claude 2.1.238, bare pty, 3 runs per timepoint all agreeing, 32 runs under
// 32 runs, 3 per timepoint, all agreeing): **submitting the argv message clears the input box.**
// Bytes typed before it renders land in the box and are wiped by that clear (T1 at 0.06s and T2
// right after the first frame both lost 3/3), while raw mode — the readiness signal — is reached
// at 0.1–0.19s, seconds too early to protect anything.
//
// Round 3 tried to gate the typing on a per-request marker appearing on screen. Two independent
// reviewers broke it: a zsh with `set -x` prints the fully substituted argv, marker included,
// right before the exec, and it can print it more than once — so no count over that marker is a
// condition **only claude** can satisfy, and the production loop recorded a wiped input as
// delivered. Round 4 removes the combination instead of the gate: a request either merges
// everything into argv or types everything (`prepareRequest`). These tests pin that, and pin the
// one thing kept from the lesson — a submission is only counted once it is seen to have survived.

final class ClaudeSubmissionSurvivalTests: XCTestCase {
    private let inputs = ["/review"]

    /// **The check is best-effort (round 6, user's decision).** Nothing outside the TUI can prove
    /// a message exists, and chasing that proof produced a check that was wrong in both directions
    /// twice. What the loop needs from the screen is one operational answer — may the next input
    /// be typed? — so only a screen that **still shows our input where we typed it** stops
    /// delivery. "Gone from the screen" is one of the things a scrolled transcript looks like, and
    /// nothing bad follows from carrying on: the box does not hold our text, so the next input
    /// cannot be appended to it
    func testAnInputThatLeftTheScreenDoesNotStopDelivery() {
        let session = FakeClaudeSession()
        session.dropSubmittedFromScreen = true
        XCTAssertEqual(submitClaudeInputs(["/review", "/second"], io: session.io), 2)
    }

    /// …and it is still never retyped. Retyping is the one move that could submit the same message
    /// twice, and that invariant does not depend on any reading of the screen
    func testAnInputThatLeftTheScreenIsNotRetyped() {
        let session = FakeClaudeSession()
        session.dropSubmittedFromScreen = true
        _ = submitClaudeInputs(["/review", "/second"], io: session.io)
        XCTAssertEqual(session.keystrokes.filter { $0 == "/review" }.count, 1)
    }

    /// A screen we cannot read says nothing. Unknown is not evidence of a wipe — and calling it
    /// one would stop delivery, which drops every input after this one
    func testAnUnreadableScreenAfterTheCarriageReturnIsNotTreatedAsAWipe() {
        let session = FakeClaudeSession()
        session.dropSubmittedFromScreen = true
        // 1: pre-typing snapshot · 2: reflection · 3–7: the whole post-CR window
        session.failScreenAt = [3, 4, 5, 6, 7]
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 1)
    }

    /// The normal path is unchanged — a message that reached the transcript counts once
    func testASubmittedInputStaysOnScreenAndCounts() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 1)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// **Reproduction (round 5, Codex)**: the CR is reported as sent, the TUI has not acted on it,
    /// and the text is **still in the input box**. The old check re-read the screen against the
    /// *pre-typing* snapshot — the question the reflection check had already answered yes — so it
    /// counted a message that does not exist.
    ///
    /// **Round 6 (independent reviewer, the blocking one)**: stopping is not enough. Our text is
    /// provably still in the box, so the single cleanup point has to fire — otherwise the next
    /// Enter the **user** presses submits it, and a `!` input runs their shell command
    func testAnInputStillSittingInTheInputBoxIsNotCountedAsDelivered() {
        let session = FakeClaudeSession()
        session.submitDoesNothing = true
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 0)
        XCTAssertEqual(session.submitted, [])
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey, "the residue was not erased")
    }

    /// The reviewer's own reproduction, in the shape they ran it: the TUI stops acting on
    /// submissions **after the first one**, the writes keep reporting success, and the second
    /// input is left sitting in the box
    func testAnInputTheTUIStoppedActingOnIsClearedRatherThanLeftForTheUsersEnter() {
        let session = FakeClaudeSession()
        let base = session.io
        var io = base
        io.sendKeys = { keys in
            if keys == claudeSubmitKey, !session.submitted.isEmpty { session.submitDoesNothing = true }
            return base.sendKeys(keys)
        }
        XCTAssertEqual(submitClaudeInputs(["/review", "!git status"], io: io), 1)
        XCTAssertEqual(session.submitted, ["/review"])
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey, "`!git status` was left in the input box")
    }

    /// **Reproduction (round 5, Codex P1-a)**: a change somewhere else on the screen — a spinner,
    /// streaming output — is not evidence about the input box. Only the region from our input to
    /// the end of the screen is
    func testAnUnrelatedScreenChangeDoesNotMakeAStuckInputLookSubmitted() {
        let session = FakeClaudeSession()
        session.submitDoesNothing = true
        session.screenGains = [4: "spinner"] // arrives during the post-CR look, above our input
        XCTAssertEqual(submitClaudeInputs(["/review", "!git status"], io: session.io), 0)
        XCTAssertFalse(
            session.keystrokes.contains("!git status"),
            "typing on would append the two inputs into one submitted line"
        )
    }

    /// **Reproduction (round 7, Codex — the blocking one).** Two questions had been squashed into
    /// one: *(i) did claude receive it* (not proven, by decision) and *(ii) is the input box empty
    /// before we type the next thing* (a safety property). Treating "unknown" as "empty" merged our
    /// leftover with the next input: the first CR is written but the box keeps `/review`, the
    /// post-CR look cannot read the screen, and the next input is typed straight onto it —
    /// `"/review!git status"` goes in as one line
    func testResidueIsClearedBeforeTheNextInputIsTyped() {
        let session = FakeClaudeSession()
        session.submitDoesNothing = true // the first CR writes but the TUI does not act on it
        // …and something below the box ticks (context meter, clock), so the tail differs on every
        // read and the look can never answer "stuck" — the common case, not a corner (R6)
        session.tickingChrome = true
        let base = session.io
        var io = base
        io.sendKeys = { keys in
            let result = base.sendKeys(keys)
            if keys == claudeSubmitKey { session.submitDoesNothing = false } // only the first
            return result
        }
        _ = submitClaudeInputs(["/review", "!git status"], io: io)
        XCTAssertEqual(session.submitted, ["!git status"], "the residue and the next input were merged into one line")
    }

    /// The same property where the screen can never answer: on Warp the post-CR look is skipped
    /// entirely, so **even a single input** must not be left in the box for the user's next Enter
    /// (with a `!` input that Enter runs their shell command)
    func testWarpDeliveryDoesNotLeaveOurInputInTheBox() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        session.submitDoesNothing = true
        _ = submitClaudeInputs(["!git status"], io: session.io)
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey)
    }

    /// …and the rule is **one rule**, not a per-branch judgement: delivery ends with the box
    /// cleared whenever we cannot see that it is free of ours — including the path where
    /// everything looked fine. The cost (a draft the user started during delivery is erased) is
    /// accepted deliberately; the alternative is our `!` line waiting for their Enter
    func testDeliveryEndsWithTheBoxCleared() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 1)
        XCTAssertEqual(session.submitted, inputs)
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey)
    }

    /// **Reproduction (round 7, independent reviewer — F1, deterministic).** `screenTail` takes the
    /// **last** occurrence of the probe, and claude draws things *below* the input box: hint lines,
    /// a permission mode indicator, a context meter. If the probe also appears down there, that
    /// occurrence wins, the tail never moves, and a submission that went through is read as "still
    /// in the box" — delivery stops and the rest of the inputs are dropped. A one-character input
    /// hits it immediately (`y` is in "bypass permissions on")
    func testAProbeThatAlsoAppearsBelowTheBoxIsNotJudged() {
        let session = FakeClaudeSession()
        session.bottomChrome = "? for shortcuts · ⏵⏵ bypass permissions on"
        XCTAssertEqual(submitClaudeInputs(["y", "!git status"], io: session.io), 2)
        XCTAssertEqual(session.submitted, ["y", "!git status"])
    }

    /// The same with a whole slash command echoed in the chrome (`try /review`)
    func testAProbeEchoedInAHintLineIsNotJudged() {
        let session = FakeClaudeSession()
        session.bottomChrome = "try /review for a code review"
        XCTAssertEqual(submitClaudeInputs(["/review", "!git status"], io: session.io), 2)
        XCTAssertEqual(session.submitted, ["/review", "!git status"])
    }

    /// **Reproduction (round 7, independent reviewer — R5)**: one failed read in the middle of the
    /// look wiped out what the earlier reads had already established. A read we could not make says
    /// nothing; it must not turn "the box is still holding it" into "carry on"
    func testAFailedReadDoesNotEraseWhatTheEarlierReadsShowed() {
        let session = FakeClaudeSession()
        session.submitDoesNothing = true
        session.failScreenAt = [4] // 1: snapshot · 2: reflection · 3,4,5…: the post-CR look
        _ = submitClaudeInputs(["/review", "!git status"], io: session.io)
        XCTAssertFalse(session.keystrokes.contains("!git status"), "it kept typing even after seeing the input stuck there")
    }

    /// **Reproduction (round 8, Codex — the blocking one).** The reflection check accepted the
    /// probe appearing **anywhere**, and the CR follows it immediately. claude draws hint lines
    /// that can contain the very text we typed, so a screen that gains one of those while our
    /// typing was dropped looks exactly like a render — and the CR then submits whatever the box
    /// really holds, which can be something the user typed. Round 7 put the uniqueness rule only
    /// *after* the CR; the judgement before an irreversible byte has to be the stricter one
    func testTextAppearingSomewhereElseIsNotMistakenForOurRender() {
        let session = FakeClaudeSession()
        session.dropTypingAt = Set(1...100)      // claude never draws what we type
        session.screenGains = [2: "try /review"] // …and a hint containing it shows up meanwhile
        XCTAssertEqual(submitClaudeInputs(["/review"], io: session.io), 0)
        XCTAssertFalse(session.keystrokes.contains(claudeSubmitKey), "a CR went out without confirmation")
    }

    /// The normal path still goes through: what we type really is in the box, so clearing it makes
    /// the text disappear — that is the experiment that tells the two apart
    func testTextThatDisappearsWhenTheBoxIsClearedIsOurs() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs(["/review"], io: session.io), 1)
        XCTAssertEqual(session.submitted, ["/review"])
    }

    /// **Speed, as a pinned property (round 10).** Every poll in the delivery loop used to sleep
    /// **before** its first read, so a screen that was already drawn still cost a full interval —
    /// four of those per input. The rule now: read first, then retry on a short interval, with the
    /// same (or a longer) deadline. Evidence is not traded away for it; only the sampling changes.
    ///
    /// Pinned two ways: no wait may directly follow a send (the next thing is always a read), and
    /// the total synthetic wait for one happy-path input stays small. Measured on this fake:
    /// **1.70s before, 0.00s after** — the happy path now answers on its first read every time.
    func testTheHappyPathDoesNotSleepBeforeReading() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs(["!git status"], io: session.io), 1)
        for (index, event) in session.events.enumerated() where event == "send" {
            guard let next = session.events[safe: index + 1] else { continue }         // the cleanup at the end
            XCTAssertEqual(next, "read", "a wait came after the send instead of a read: \(session.events)")
        }
        XCTAssertLessThanOrEqual(session.waits.reduce(0, +), 0.5, "\(session.waits)")
    }

    /// **Reproduction (round 12, driver's pty measurement — blocking).** Ctrl+U does **not** leave
    /// claude's `!` shell mode: it clears the text and leaves the `!` behind, so the box looks
    /// empty on screen (the disappearance check passes) while still being in shell mode. The next
    /// input typed into it is submitted as a **shell command** — measured directly:
    /// `command not found: tcq3hello`. CLAUDE.md carried this as "unmeasured, the circumstantial
    /// evidence points the safe way"; the evidence pointed the wrong way.
    ///
    /// The real path is not exotic: an earlier `!` input whose CR did not take leaves `!text` in
    /// the box, the next cycle's marker experiment clears it down to `!`, and a plain-text body
    /// then goes in as `!body`.
    func testAPlainInputIsNeverSubmittedIntoLeftoverShellMode() {
        let session = FakeClaudeSession()
        session.presetBox = "!gh pr view 1"         // left over because the previous input's CR did not take
        _ = submitClaudeInputs(["summarize the diff"], io: session.io)
        XCTAssertEqual(
            session.submitted, ["summarize the diff"],
            "plain text was typed into an input box still holding a `!` and submitted as a shell command"
        )
    }

    /// **Reproduction (round 9, Codex — the blocking one, a regression round 8 introduced).**
    /// The attribution experiment used to type **the body**. If the user presses Enter while that
    /// trial typing is on screen — on Warp they are looking at the tab by design — their Enter
    /// runs the command, and the app, which only counts the CRs **it** sent, clears, retypes and
    /// submits: `!git status` runs twice. Up to round 7 our CR landed in an empty box and did
    /// nothing. The experiment now uses a throwaway marker, so a stray Enter submits that instead
    /// and the command is typed exactly once
    func testAUserPressingEnterDuringTheExperimentCannotRunTheCommandTwice() {
        let session = FakeClaudeSession()
        session.userPressesEnterAfterSend = 1 // the first thing we type is the experiment's
        _ = submitClaudeInputs(["!git status"], io: session.io)
        XCTAssertEqual(
            session.submitted.filter { $0 == "!git status" }.count, 1,
            "the command ran twice — once from the user's Enter and once from our CR"
        )
    }

    /// **Reproduction (round 9, independent reviewer).** The appearance check demanded *exactly*
    /// one more copy of our text on screen. If claude draws it a second time — the same hint-line
    /// behaviour this repository documents elsewhere — the count is `baseline + 2`, the check never
    /// matches, and the button does nothing at all: five typings, no CR, no message. Appearance
    /// needs "at least one more"; only the **disappearance** check needs an exact count
    func testAnInputTheScreenDrawsTwiceIsStillSubmitted() {
        let session = FakeClaudeSession()
        let base = session.io
        var io = base
        io.sendKeys = { keys in
            let sent = base.sendKeys(keys)
            // claude draws our line a second time somewhere else the moment we type it
            if keys == "/review" { session.screenPrefix += " /review" }
            return sent
        }
        XCTAssertEqual(submitClaudeInputs(["/review"], io: io), 1)
        XCTAssertEqual(session.submitted, ["/review"])
    }

    /// **Reproduction (round 9, Codex P2)**: the trial text reached the tty and only the *screen
    /// read* failed, so the clear was never sent and the next attempt typed on top of it. With a
    /// marker the leftover is harmless, and the next attempt's clear takes it — what must not
    /// happen is the body going in twice
    func testAFailedReadDuringTheExperimentDoesNotDoubleTheBody() {
        let session = FakeClaudeSession()
        session.failScreenAt = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] // the whole first attempt
        _ = submitClaudeInputs(["!git status"], io: session.io)
        XCTAssertEqual(session.submitted, ["!git status"])
        XCTAssertEqual(session.keystrokes.filter { $0 == "!git status" }.count, 1)
    }

    /// **Reproduction (round 8, both reviewers)**: a Ctrl+U whose **write** succeeded is not a
    /// Ctrl+U the TUI processed — AppleScript and the CLI answer for the terminal, not for claude.
    /// Lowering ownership on the write left the box holding our markers with no cleanup at all
    func testAWrittenClearThatTheTUIIgnoredStillLeavesUsHoldingTheBox() {
        let session = FakeClaudeSession()
        session.clearDoesNothing = true         // the write succeeds, the TUI does not process it
        _ = submitClaudeInputs(["!git status"], io: session.io)
        // The marker never disappears, so no attempt gets as far as the body and a cleanup goes out at the end — back when a written Ctrl+U was believed to have been processed, this cleanup was skipped entirely
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey)
        XCTAssertTrue(session.submitted.isEmpty)
        XCTAssertFalse(session.keystrokes.contains("!git status"), "the body was typed without confirmation")
    }

    /// Cleanup is one Ctrl+U through the same gate, and the terminal CLI does fail one call now and
    /// then — a single attempt with no retry and no record leaves our text in the box silently
    func testCleanupIsRetriedWhenTheSendFails() {
        let session = FakeClaudeSession()
        session.submitDoesNothing = true
        // 1: the experiment's typing · 2: the experiment's clear · 3: the body · 4: the CR · 5–7: the cleanup attempts on the way out
        session.failSendAt = [5, 6]
        _ = submitClaudeInputs(inputs, io: session.io)
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey)
        XCTAssertEqual(session.sendCallCount, 7)
    }

    /// …and it is not retyped either, for the same reason a wiped one is not
    func testAnInputStillSittingInTheInputBoxIsNotRetyped() {
        let session = FakeClaudeSession()
        session.submitDoesNothing = true
        _ = submitClaudeInputs(["/review", "/second"], io: session.io)
        XCTAssertEqual(session.keystrokes.filter { $0 == "/review" }.count, 1)
    }

    /// **Reproduction (round 5, independent reviewer)**: on Warp the screen read after the CR is
    /// **whatever pane has focus**, so switching tabs returns someone else's text — not nil. Read
    /// as "our input is gone" it reported a delivered input as lost and dropped every input after
    /// it. Where the screen cannot be attributed to our pane, absence means *unknown*
    func testAForeignScreenAfterTheCarriageReturnDoesNotStopDelivery() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        let base = session.io
        var io = base
        io.screenText = {
            session.keystrokes.contains(claudeSubmitKey) ? "another pane's screen" : base.screenText()
        }
        XCTAssertEqual(submitClaudeInputs(inputs, io: io), 1)
        XCTAssertEqual(session.submitted, inputs)
    }
}

final class ClaudeInputDeliveryTests: XCTestCase {
    private let inputs = ["!gh issue view 1415", "!gh issue view 1415 --comments", "/gh-drive-pr-review"]

    func testAllInputsSubmittedInOrder() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// A submission happens only after the screen is confirmed to reflect the input — a CR going out ahead of any typing submits an empty line.
    /// The Ctrl+U before and after is round 7's rule (ii): empty before typing, and empty on the way out
    func testSubmitsOnlyAfterScreenShowsTypedText() {
        let session = FakeClaudeSession()
        _ = submitClaudeInputs([inputs[0]], io: session.io)
        // Round 9's cycle: type a **marker** → clear it (confirming it disappears) → type the body **once** → CR, and empty once more as delivery ends. The marker is random, so it is pinned by shape
        XCTAssertEqual(session.keystrokes.count, 5)
        XCTAssertTrue(session.keystrokes[0].hasPrefix("tc"), session.keystrokes[0])
        XCTAssertEqual(
            Array(session.keystrokes.dropFirst()),
            [claudeClearInputKey, inputs[0], claudeSubmitKey, claudeClearInputKey]
        )
    }

    /// Regression guard (measured): right after input #1 was submitted, one wezterm cli call failed and the remaining 2 inputs were thrown away wholesale. A failed terminal CLI call does not mean "the session is over", only that this call failed — so it has to recover by retyping and keep sending the rest.
    func testTransientSendFailureDoesNotDropRemainingInputs() {
        let session = FakeClaudeSession()
        session.failSendAt = [5]         // after #1's marker, clear and body = #1's CR
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// A failed screen read is the same — it only means the reflection could not be confirmed, so it recovers by retyping
    func testTransientScreenReadFailureDoesNotDropRemainingInputs() {
        let session = FakeClaudeSession()
        session.failScreenAt = [2]         // #1's reflection-check read
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// Retrying does not hold the remaining inputs forever — if it keeps failing it stops at that input
    func testPersistentFailureStopsAtThatInput() {
        let session = FakeClaudeSession()
        session.failSendAt = Set(6...100)         // #1 passes (marker, clear, body, CR) and it fails from #2's marker onwards
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]])
    }

    /// When the session has changed (the original claude died and a new one came up on the same tty) the remaining inputs are not sent — with a `!…` input a shell command would run in an unrelated session
    func testReplacedSessionStopsDelivery() {
        let session = FakeClaudeSession()
        _ = submitClaudeInputs([inputs[0]], io: session.io)
        session.sessionAlive = false
        let after = session.keystrokes.count
        XCTAssertEqual(submitClaudeInputs([inputs[1]], io: session.io), 0)
        XCTAssertEqual(session.keystrokes.count, after)
    }

    /// A retry must not skip the session check itself — the session can change between the first typing and the retry, and typing into that second claude is the same mistyping
    func testRetryReconfirmsSessionBeforeRetyping() {
        let session = FakeClaudeSession()
        session.failSendAt = [1]         // the first typing fails → it enters a retry
        var confirms = 0
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            // The between-inputs gate passed, but the check immediately before the retry finds the session changed
            confirmSession: { _ in confirms += 1; return confirms == 1 },
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
        // No retry typing may go out. The first typing failed as a send, but its bytes may already be in, so a single Ctrl+U follows to erase them on the way out
        XCTAssertFalse(session.keystrokes.contains(inputs[0]), "retry typing went out: \(session.keystrokes)")
        XCTAssertEqual(session.keystrokes, [claudeClearInputKey])
    }

    /// When clearing the input box (Ctrl+U) failed, nothing is typed — typing after text that may still be there gets an input with something stuck on the front submitted while the screen check passes
    func testFailedClearDoesNotTypeOverLeftovers() {
        let session = FakeClaudeSession()
        session.presetBox = "leftover"
        session.failSendAt = [1, 2]         // #1's typing fails → #2's clear fails too
        _ = submitClaudeInputs([inputs[0]], io: session.io)
        XCTAssertEqual(session.submitted, [inputs[0]])
    }

    /// Resending the CR has to sit inside the session-identity gate too — if the original claude ended after the first CR failed, the CR lands on the shell of that tty or on a new claude and submits and runs whatever the user was typing
    func testCarriageReturnResendStopsWhenSessionChanged() {
        let session = FakeClaudeSession()
        session.failSendAt = [4] // marker, clear and body succeed; the first CR fails
        var confirms = 0
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            // The between-inputs gate and the first CR gate both pass, and the session changes immediately before the resend
            confirmSession: { _ in confirms += 1; return confirms <= 2 },
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        // marker 1 + clear 1 + body 1 + CR 1 + cleanup after giving up 1 — there must be no CR resend
        XCTAssertEqual(session.sendCallCount, 5)
        XCTAssertEqual(
            Array(session.keystrokes.dropFirst()),
            [claudeClearInputKey, inputs[0], claudeClearInputKey]
        )
    }

    /// When sending the submission (CR) fails it resends the CR rather than retyping — a reported failure may in fact have gone through, and retyping then submits the same input twice
    func testFailedSubmitResendsCarriageReturnWithoutRetyping() {
        let session = FakeClaudeSession()
        session.failSendAt = [4] // marker, clear and body succeed; #4 = the CR fails
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]])
        // The body is typed once (the experiment uses the marker). Not typing again after a CR is the invariant to hold here
        XCTAssertEqual(session.keystrokes.filter { $0 == inputs[0] }.count, 1)
    }

    /// **Reproduction (round 5, Codex)**: a CR whose call reported failure may still have landed —
    /// the helper can inject part of a write and then error. Retrying the CR is fine (a CR into an
    /// empty box does nothing), but the outer loop used to give up on the resends, clear the box
    /// and **retype**, submitting the same message twice. With a `!` input that runs the user's
    /// command twice
    func testAnInputWhoseCarriageReturnMayHaveLandedIsNeverRetyped() {
        let session = FakeClaudeSession()
        // 1: the marker · 2: its clear · 3: the body · 4–6: the three CR attempts, each landing
        // but reporting failure
        session.deliverButReportFailureAt = [4, 5, 6]
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertEqual(session.submitted, [inputs[0]]) // it did go through — exactly once
        XCTAssertEqual(session.keystrokes.filter { $0 == inputs[0] }.count, 1)
    }

    /// Regression guard (measured on Warp): right after claude comes up there is a moment where gates ① and ② pass but the TUI has not drawn the first input yet. The screen reads fine and only the input is missing, so it recovers by retyping
    func testUnreflectedInputRetypesUntilScreenShowsIt() {
        let session = FakeClaudeSession()
        session.dropTypingAt = [3] // the marker and clear pass, and claude discards the **body**
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]]) // the real input was submitted, not an empty line
        // the discarded body 1 + the next attempt's body 1
        XCTAssertEqual(session.keystrokes.filter { $0 == inputs[0] }.count, 2)
    }

    /// When the screen can never be read, nothing is submitted. There was a time the "tty input queue is empty" signal (`FIONREAD`=0) stood in for it, but that only means claude called `read()`, not that it drew the input box — so an empty CR was sent on top of input claude had discarded and it was recorded as "delivered"
    func testUnreadableScreenNeverSubmits() {
        let session = FakeClaudeSession()
        session.failScreenAt = Set(1...100)
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
    }

    /// When the screen reads but our input never appears (another pane is being read) nothing is submitted — submitting an empty line here runs whatever the user was typing in that pane
    func testScreenThatNeverShowsInputNeverSubmits() {
        let session = FakeClaudeSession()
        session.dropTypingAt = Set(1...100)
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
    }

    /// Regression guard (reviewer reproduction, P2): injection enters **our tty regardless of focus**, so "we could not confirm it on screen" does not mean "it is not in the input box". If the reflection check finally fails while the body is already in, ending without erasing that fragment lets an Enter the user presses later submit it (in `!…` shell mode it even runs a command).
    /// The same holds while the permission is alive, so the cleanup condition is not "the permission was lost" but **"we did not finish and a fragment of ours may remain"**.
    func testUnconfirmedTypingIsClearedWhenDeliveryGivesUp() {
        let session = FakeClaudeSession()
        session.dropTypingAt = Set(1...100) // the bytes went in but never show up on screen
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
        XCTAssertEqual(
            session.keystrokes.last, claudeClearInputKey,
            "it gave up and ended without erasing the fragment of ours left in the input box: \(session.keystrokes)"
        )
    }

    /// Regression guard (P0-2): there is no guarantee the screen read through Accessibility is our pane. If another pane happens to show the same text, a plain substring match passes even before we type, and the CR that follows leaves our input unsubmitted while whatever the user was typing goes in instead.
    /// Taking a snapshot before typing and demanding "one more occurrence than before" kills that branch
    func testTextAlreadyOnScreenBeforeTypingIsNotReflection() {
        let session = FakeClaudeSession()
        session.screenPrefix = inputs[0] // another pane already shows the same text
        session.dropTypingAt = Set(1...100) // our input never actually appears
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
    }

    /// Regression guard (P0-1): if a probe that was absent before typing appears **in another pane** afterwards, the count increases too — comparing counts only removes the false positive from pre-existing text; it says nothing about where the screen came from.
    /// The screen check only holds once a random value that can enter our tty alone has been seen to appear on that screen.
    /// Both branches live in one test so that the flag actually splitting the verdict is pinned as well
    func testPaneProofIsWhatBlocksAForeignScreen() {
        func run(paneProof: Bool) -> (submitted: Int, lines: [String]) {
            let session = FakeClaudeSession()
            session.screenIsForeign = true
            session.foreignScreenGains = [inputs[0]]
            session.screenNeedsPaneProof = paneProof
            let count = submitClaudeInputs([inputs[0]], io: session.io)
            return (count, session.submitted)
        }
        // Since round 8, someone else's screen cannot approve a submission even without the pane proof — the attribution experiment asks "does what we typed disappear once we clear it", and on someone else's screen it does not.
        // The proof is nevertheless kept because the experiment is made of **our own text** and so cannot rule out a coincidental match (a random marker can)
        XCTAssertEqual(run(paneProof: false).lines, [])
        XCTAssertEqual(run(paneProof: false).submitted, 0)
        // With the proof demanded, the random value never appears on that screen, so nothing is submitted
        XCTAssertEqual(run(paneProof: true).submitted, 0)
        XCTAssertTrue(run(paneProof: true).lines.isEmpty)
    }

    /// With the pane proof on, the normal path still runs to the end — a hardening must not block delivery
    func testPaneProofDoesNotBlockTheNormalPath() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// If the random value used for the proof were submitted along with the input, claude would receive the wrong thing — the marker is always erased before typing
    func testPaneProofTokenNeverReachesSubmission() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]])
    }

    /// Regression guard (P0-1): once the session has changed, not just the CR but **the marker, the Ctrl+U and the body typing** must not go out either. They pollute the input box of the new shell or the newly started claude, and the Ctrl+U erases the draft the user was typing there. "It does not execute, so it is fine" is not the answer
    func testNoBytesLeaveAfterTheSessionChanged() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            confirmSession: { _ in true }, // the between-inputs gate has passed
            sessionIsUnchanged: { false }, // but by the moment bytes go out it has already changed
            screenNeedsPaneProof: true,
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.keystrokes.isEmpty, "bytes leaked out: \(session.keystrokes)")
    }

    /// Regression guard (P0-2): when the screen can no longer be confirmed (the permission was revoked) **typing anything new** has to stop, but the cleanup that undoes what was already typed still has to go out. Blocking the cleanup under the same condition leaves the automatic input in the box, to be run by an Enter the user presses later
    func testLostScreenAccessStopsTypingButNotCleanup() {
        let session = FakeClaudeSession()
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            confirmSession: { _ in true },
            sessionIsUnchanged: { true },
            screenConfirmation: { .warpAccessibility }, // the permission disappeared mid-delivery
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.keystrokes.isEmpty, "typed while it could not be confirmed: \(session.keystrokes)")
        XCTAssertTrue(clearAbandonedInput(io: io, weSentSomething: true), "the cleanup was blocked")
        XCTAssertEqual(session.keystrokes, [claudeClearInputKey])
    }

    /// Regression guard (P1-2): the permission has to be checked before every send, not only at the **start** of an attempt. If it is revoked during the pane proof or a one-second wait, the marker, the body and the CR keep going out afterwards
    func testPermissionLostMidAttemptStopsFurtherSends() {
        let session = FakeClaudeSession()
        var sends = 0
        let io = ClaudeSessionIO(
            sendKeys: { sends += 1; return session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            confirmSession: { _ in true },
            sessionIsUnchanged: { true },
            screenConfirmation: { sends < 1 ? nil : .warpAccessibility }, // the permission disappears right after the first send
            screenNeedsPaneProof: true,
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        // Typing anything new stops at the one marker. What goes out after it is only the cleanup that **erases the marker already typed** — blocking that too leaves the marker in the input box for the user to submit
        XCTAssertEqual(session.keystrokes.count, 2, "typed anew after the permission was gone: \(session.keystrokes)")
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey)
    }

    /// Regression guard (P1-3): if we never sent a single byte, no cleanup happens either — that Ctrl+U would erase nothing but the draft the user was typing
    func testCleanupDoesNothingWhenWeNeverSentAnything() {
        let session = FakeClaudeSession()
        XCTAssertFalse(clearAbandonedInput(io: session.io, weSentSomething: false))
        XCTAssertTrue(session.keystrokes.isEmpty)
        XCTAssertTrue(clearAbandonedInput(io: session.io, weSentSomething: true))
        XCTAssertEqual(session.keystrokes, [claudeClearInputKey])
    }

    /// Regression guard: "might a fragment of ours be in the input box" is raised by the **attempt** and lowered by **observation**.
    /// Raising it by the result misses the leftover when the helper injected part of a write and then failed (a false negative), and leaving it true forever after one success erases the user's draft when the next input never even started (a false positive).
    func testInputBoxOwnershipRisesOnAttemptAndFallsOnSubmit() {
        // This exercises the very type `deliverClaudeInputs` uses — keeping a copy of the rule here would go green while the copy is right and the real one has drifted
        var ownership = InputBoxOwnership()
        XCTAssertFalse(ownership.mayHoldOurs, "before anything is sent there is no fragment of ours to erase")
        ownership.recordSendAttempt() // even a failed send may already have put bytes in
        XCTAssertTrue(ownership.mayHoldOurs, "the fragment left after a failed send would become impossible to erase")
        // A CR or Ctrl+U having been **written** is not evidence the TUI processed it — a success from AppleScript or the CLI only means the terminal accepted the bytes. So no send lowers this
        ownership.recordSendAttempt()
        XCTAssertTrue(ownership.mayHoldOurs, "a written Ctrl+U was believed to have been processed")
        // And **a CR does not lower it** (round 7): writing a CR to the tty and the TUI processing it as a submission are different things, and if it was not processed the body is still in the box. Treating "unknown" as "empty" is how residue got appended to the next input as one line. Only **evidence** lowers it — the screen showed our marker disappear after a clear, or the screen showed that ours is not there
        ownership.recordSendAttempt()
        XCTAssertTrue(ownership.mayHoldOurs, "writing a CR is not evidence that the input box is empty")
        ownership.recordInputBoxIsFreeOfOurs()
        XCTAssertFalse(ownership.mayHoldOurs)
    }

    /// The answer and its reason are one value (round 6 review). They used to be two — a `Bool`
    /// for "can the screen be confirmed" and, at the diagnosis, a permission named from the outside
    /// on the grounds that Warp is currently the only terminal whose confirmation can fail. That
    /// held today and would have gone on naming a permission for a terminal that had none, so the
    /// reason now travels with the answer and nothing can disagree with it.
    func testTheScreenConfirmationAnswerCarriesItsOwnReason() {
        let confirmable = ClaudeSessionIO(sendKeys: { _ in true }, screenText: { "" }, confirmSession: { _ in true })
        XCTAssertTrue(confirmable.canConfirmScreen())
        XCTAssertNil(confirmable.screenConfirmation())

        let blocked = ClaudeSessionIO(
            sendKeys: { _ in true }, screenText: { "" }, confirmSession: { _ in true },
            screenConfirmation: { .warpAccessibility }
        )
        XCTAssertFalse(blocked.canConfirmScreen())
        XCTAssertEqual(blocked.screenConfirmation(), .warpAccessibility)
        // The sentence the log shows comes from the blocker itself, so it cannot name a permission
        // for a reason that is not one
        XCTAssertTrue(blocked.screenConfirmation()?.message.contains("Accessibility") == true)
    }

    /// The cleanup Ctrl+U after delivery ended midway has to pass the same gate — if this site bypassed it, the cleanup would erase somebody else's session's input box
    func testAbandonedInputCleanupIsGatedToo() {
        let session = FakeClaudeSession()
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            confirmSession: { _ in true },
            sessionIsUnchanged: { false },
            wait: { _ in }
        )
        XCTAssertFalse(clearAbandonedInput(io: io, weSentSomething: true))
        XCTAssertTrue(session.keystrokes.isEmpty)
    }

    /// Every site that emits bytes goes through the one gate — checking at each site separately is how the next missed site appears. What is asserted is the general property (gate checks == sends), not a fixed list: this run happens to make five sends, and any additional send executed by this scenario is covered without editing this test. A send on a path this scenario never takes — a failure branch, another input shape, another terminal's route — is not covered by this equality and needs its own case
    func testEverySendPassesTheSameGate() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.gateChecks, session.sendCallCount)
        // marker · clear · body · CR · the cleanup on the way out
        XCTAssertEqual(session.sendCallCount, 5)
    }

    /// Regression guard (P0-2): the first CR has to pass the session check too. Even immediately after confirming the screen reflection, claude can die in between and the shell or a new claude can take that tty, and the CR then submits and runs whatever the user was typing
    func testFirstCarriageReturnAlsoRequiresSessionConfirmation() {
        let session = FakeClaudeSession()
        var confirms = 0
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            // Only the between-inputs gate passes, and the session changes after it
            confirmSession: { _ in confirms += 1; return confirms == 1 },
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
        // Only the typing went out and the CR was blocked. That typing stays in the input box, so it is erased on the way out
        XCTAssertEqual(
            Array(session.keystrokes.dropFirst()),
            [claudeClearInputKey, inputs[0], claudeClearInputKey]
        )
    }

    /// With the same input scheduled twice, the second is still submitted while the first is on screen (in the transcript) — because the count is "how many times is it visible", not "was it there at all"
    func testRepeatedInputIsStillSubmittedWhileTheEarlierOneStaysOnScreen() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs([inputs[0], inputs[0]], io: session.io), 2)
        XCTAssertEqual(session.submitted, [inputs[0], inputs[0]])
    }
}

// MARK: - The screen-reflection verdict (before/after typing)
// The Warp screen read through Accessibility belongs to the focused pane, with no guarantee it is ours.
// The only way to tell "text that was already there" from "what we just typed" is a comparison against the screen taken before typing.

final class ScreenReflectionTests: XCTestCase {
    private let input = "!gh issue view 1415"

    func testNewlyAppearedInputIsReflection() {
        XCTAssertTrue(screenReflectsNewInput(before: "❯ ", after: "❯ " + input, input: input))
    }

    /// A snapshot that could not be taken (a failed screen read) is a failed check — treating what could not be sampled as "it was not there" lets pre-existing text pass as a reflection
    func testMissingBeforeSnapshotIsNotReflection() {
        XCTAssertFalse(screenReflectsNewInput(before: nil, after: "❯ " + input, input: input))
    }

    func testTextThatWasAlreadyThereIsNotReflection() {
        let screen = "another pane: " + input
        XCTAssertFalse(screenReflectsNewInput(before: screen, after: screen, input: input))
    }

    /// Even with the same text still in the transcript, one more occurrence counts as a reflection
    func testOneMoreOccurrenceIsReflection() {
        XCTAssertTrue(screenReflectsNewInput(
            before: input + " ❯ ", after: input + " ❯ " + input, input: input
        ))
    }

    /// When the screen scrolls and pushes the old occurrence out, the count does not grow — that path goes to a retype
    func testUnchangedOccurrenceCountIsNotReflection() {
        XCTAssertFalse(screenReflectsNewInput(
            before: input + " old line", after: "new line " + input, input: input
        ))
    }
}

// MARK: - Tool checking (whether z/gh/claude can actually be called in the user's shell)

final class ToolCheckTests: XCTestCase {
    func testScriptAsksEachToolAndMarksCompletion() {
        let script = toolCheckScript(["z", "gh"])
        XCTAssertTrue(script.contains("command -v z 2>/dev/null) && echo TC_OK:z"))
        XCTAssertTrue(script.contains("command -v gh 2>/dev/null) && echo TC_OK:gh"))
        // Without the completion marker, "the tool is missing" and "the shell itself failed" cannot be told apart
        XCTAssertTrue(script.hasSuffix("echo TC_DONE"))
    }

    func testParsesFoundAndMissingTools() throws {
        let output = "TC_OK:z\nTC_OK:claude\nTC_DONE\n"
        let result = try XCTUnwrap(parseToolCheck(output: output, tools: ["z", "gh", "claude"]))
        XCTAssertEqual(result, ["z": true, "gh": false, "claude": true])
    }

    // The marker has to be found even when shell integration (iTerm2 and friends) prepends escape sequences to the first line
    func testIgnoresShellIntegrationPrefix() throws {
        let output = "\u{1B}]1337;ShellIntegrationVersion=14;shell=zsh\u{07}TC_OK:z\nTC_DONE"
        let result = try XCTUnwrap(parseToolCheck(output: output, tools: ["z"]))
        XCTAssertEqual(result["z"], true)
    }

    // If "TC_OK:zoxide" leaked through as a match for "z", z would be judged present while it is missing
    func testToolNamePrefixDoesNotLeak() throws {
        let result = try XCTUnwrap(parseToolCheck(output: "TC_OK:zoxide\nTC_DONE", tools: ["z", "zoxide"]))
        XCTAssertEqual(result, ["z": false, "zoxide": true])
    }

    // No completion marker means the check failed (nil) — it must not be concluded that everything is missing
    func testMissingDoneMarkerMeansUnknown() {
        XCTAssertNil(parseToolCheck(output: "TC_OK:z", tools: ["z"]))
        XCTAssertNil(parseToolCheck(output: "", tools: ["z"]))
    }

    func testLoginShellIsAbsolutePath() {
        XCTAssertTrue(loginShellPath().hasPrefix("/"))
    }

    /// **Round 9 decision.** The check asks the form the terminals actually open — an interactive
    /// **login** shell (WezTerm spawns the shell with a `-` argv0 by design; iTerm2's default
    /// profile command is "Login shell"; Warp uses the login shell). Round 8 asked both forms and
    /// unioned them, which answers a different question ("is it in *some* rc") and told the merge
    /// that a claude only reachable from `.bashrc` was runnable — the pane then failed with
    /// `command not found` (reviewer reproduction).
    ///
    /// Measured (rc files planted in an empty HOME): `bash -l -i -c` reads `.bash_profile`,
    /// `bash -i -c` reads `.bashrc`, `zsh -l -i -c` reads all three of zsh's. So for a bash user
    /// whose tools live only in `.bashrc`, "missing" is the **correct** answer: their tab does not
    /// read that file either, which is also why their `z …` command would fail there.
    func testToolCheckAsksTheShellFormTheTerminalsOpen() throws {
        let home = NSTemporaryDirectory() + "tc-home-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: home) }
        try "tcfunc() { :; }\n".write(toFile: home + "/.bashrc", atomically: true, encoding: .utf8)
        try "tcprofile() { :; }\n"
            .write(toFile: home + "/.bash_profile", atomically: true, encoding: .utf8)

        let result = try XCTUnwrap(checkTools(
            ["tcfunc", "tcprofile"], shell: "/bin/bash",
            environment: ["HOME": home, "PATH": "/usr/bin:/bin"]
        ))
        XCTAssertEqual(result.available["tcprofile"], true, "a tool in a file the login shell reads was not seen")
        XCTAssertEqual(
            result.available["tcfunc"], false,
            "answering that a tool in an rc the tab never reads is present turns the merge on and fails in the pane"
        )
    }

    /// The fallback exists only for shells that reject `-l` (dash has no such flag). A first
    /// candidate that *answers* — even with "not found" — is the answer
    func testTheSecondShellFormIsOnlyAFallbackForShellsThatRejectTheFirst() {
        let candidates = toolCheckShellArgumentCandidates("SCRIPT")
        XCTAssertEqual(candidates.first, ["-l", "-i", "-c", "SCRIPT"])
        XCTAssertEqual(candidates.last, ["-i", "-c", "SCRIPT"])
    }

    /// **Round 8 (Codex P2)**: a relative `PATH` entry resolves against the working directory, and
    /// the pane's is whatever the command `cd`s into — so a file found from `/` is not a file
    /// `command claude` will find there. Any relative entry disqualifies the answer
    /// **Reproduction (round 9, independent reviewer).** The guard was written as
    /// `for d in $PATH`, and **zsh does not word-split an unquoted parameter** — so in the shell
    /// this machine actually logs in with, the loop ran once over the whole string and the guard
    /// did nothing. The test hid it by running the script through `/bin/sh` on purpose, which is
    /// the same shape of mistake round 2 made with the xtrace oracle: green, and proving nothing.
    /// So the guard is asked in **every shell the tool check may run in**
    func testTheRelativePathGuardAnswersTheSameInEveryShellWeMayAsk() throws {
        for shell in ["/bin/sh", "/bin/bash", "/bin/zsh", "/bin/dash"]
        where FileManager.default.isExecutableFile(atPath: shell) {
            let relative = try runProcess(
                shell, ["-c", toolCheckScript(["ls"])],
                env: ["PATH": "bin:/usr/bin:/bin"], timeout: 10
            )
            XCTAssertEqual(
                try XCTUnwrap(parseToolExecutables(output: relative.stdout, tools: ["ls"])),
                ["ls": false], shell
            )
            let absolute = try runProcess(
                shell, ["-c", toolCheckScript(["ls"])],
                env: ["PATH": "/usr/bin:/bin"], timeout: 10
            )
            XCTAssertEqual(
                try XCTUnwrap(parseToolExecutables(output: absolute.stdout, tools: ["ls"])),
                ["ls": true], shell
            )
        }
    }

    func testARelativePathEntryIsNotAcceptedAsAnExecutable() throws {
        // Codex's shape exactly: with `bin` on PATH, asking from `/` finds `/bin/ls` and answers
        // "executable" — but in the pane, after the command has `cd`ed somewhere else, `bin/ls`
        // is not there. The relative entry is what makes the answer meaningless, so it is refused
        let result = try runProcess(
            "/bin/sh", ["-c", toolCheckScript(["ls"])],
            env: ["PATH": "bin:/usr/bin:/bin"], timeout: 10
        )
        XCTAssertEqual(
            try XCTUnwrap(parseToolCheck(output: result.stdout, tools: ["ls"])), ["ls": true]
        )
        XCTAssertEqual(
            try XCTUnwrap(parseToolExecutables(output: result.stdout, tools: ["ls"])),
            ["ls": false]
        )
    }

    /// `command -v` answers for **functions and aliases** too, so "the user can type claude" and
    /// "the merge can launch claude" are different facts: the merged command runs `command claude`,
    /// which skips exactly those. Measured (both zsh and bash): with `zzclaude(){ :; }` defined,
    /// `command -v zzclaude` prints `zzclaude` while `command zzclaude` is "command not found"
    func testScriptAlsoAsksWhetherTheNameResolvesToAFile() {
        XCTAssertTrue(toolCheckScript(["claude"]).contains("TC_EXE:claude"))
    }

    func testAWrapperIsAvailableButNotExecutable() throws {
        let output = "TC_OK:z\nTC_OK:claude\nTC_EXE:claude\nTC_DONE\n"
        XCTAssertEqual(
            try XCTUnwrap(parseToolCheck(output: output, tools: ["z", "claude"])),
            ["z": true, "claude": true]
        )
        XCTAssertEqual(
            try XCTUnwrap(parseToolExecutables(output: output, tools: ["z", "claude"])),
            ["z": false, "claude": true]
        )
    }

    /// The classification has to come out of a **real shell**, not out of our reading of one.
    ///
    /// Three cases, all measured before they were coded (round 7, Codex's reproduction):
    ///  - `tcfunc` — a function with no file behind it. `command claude` would fail, so no merge
    ///  - `tcwrapped` — a function **wrapping a real file**. `command -v` answers `tcwrapped`, but
    ///    `command tcwrapped` runs the file, which is exactly what the merged command does. The old
    ///    probe said "not executable" here and refused to merge, contradicting the documented
    ///    "the merge bypasses your wrapper"
    ///  - `tcnoexec` — a file on PATH **without the executable bit**. bash and dash hand back its
    ///    absolute path from `command -v` (measured), so a `/*` test alone called it executable and
    ///    the merged `command claude` then failed
    func testExecutableProbeSeesPastWrappersAndRejectsUnrunnableFiles() throws {
        let directory = NSTemporaryDirectory() + "tc-toolcheck-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        for name in ["tcreal", "tcwrapped", "tcnoexec"] {
            try "#!/bin/sh\nexit 0\n".write(toFile: directory + "/" + name, atomically: true, encoding: .utf8)
        }
        for name in ["tcreal", "tcwrapped"] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: directory + "/" + name
            )
        }

        let tools = ["tcfunc", "tcreal", "tcwrapped", "tcnoexec"]
        let result = try runProcess(
            "/bin/sh",
            ["-c", "tcfunc() { :; }\ntcwrapped() { command tcwrapped; }\n" + toolCheckScript(tools)],
            env: ["PATH": directory + ":/usr/bin:/bin"], timeout: 10
        )
        XCTAssertEqual(
            try XCTUnwrap(parseToolExecutables(output: result.stdout, tools: tools)),
            ["tcfunc": false, "tcreal": true, "tcwrapped": true, "tcnoexec": false]
        )
        // The `-x` guard is what covers the shells that answer with a path for a file they could
        // not run (measured: bash and dash do, /bin/sh and zsh do not), so it must not be dropped
        XCTAssertTrue(toolCheckScript(["claude"]).contains("[ -x "), toolCheckScript(["claude"]))
    }
    // "Without z every button fails" holds only until a base directory is configured. Keeping it
    // an error afterwards leaves a red line in the setup window of a perfectly fine environment
    func testZIsCriticalOnlyWhileNoBaseDirectoryIsConfigured() {
        XCTAssertTrue(toolIsCritical("z", baseDirectoryConfigured: false))
        XCTAssertFalse(toolIsCritical("z", baseDirectoryConfigured: true))
    }

    // gh and claude are used by some presets only, so either way they are warnings
    // (gh also appears in the clone clause once a base directory is set, but the z and cd
    // fallbacks survive without it)
    func testOtherToolsAreNeverCritical() {
        for tool in ["gh", "claude"] {
            XCTAssertFalse(toolIsCritical(tool, baseDirectoryConfigured: false), tool)
            XCTAssertFalse(toolIsCritical(tool, baseDirectoryConfigured: true), tool)
        }
    }
}

// MARK: - AppleScript escaping

final class AppleScriptTests: XCTestCase {
    /// iTerm2 is the one terminal that does not receive `claudeClearInputKey` as bytes — it goes
    /// through AppleScript, so the sequence has to be spelled out there too. Both characters, in
    /// one `write text` (a newline between them would submit), Ctrl+U first: alone it leaves
    /// claude's `!` shell mode behind and the next plain input runs as a shell command (measured)
    func testTheClearScriptSendsBothCharactersOfTheClearSequence() {
        let script = iTermClearInputScript(sessionID: "s")
        XCTAssertTrue(
            script.contains("write text ((character id 21) & (character id 127)) newline NO"),
            script
        )
    }

    /// **Drift (round 13, independent reviewer).** "One constant, every site" was false for iTerm2:
    /// the script transcribed 21 and 127 instead of reading `claudeClearInputKey`, so changing the
    /// constant would have moved every terminal *except* iTerm2 — silently. The expectation here is
    /// recomputed from the constant, so the two can no longer disagree
    func testTheClearScriptIsDerivedFromTheClearKeyAndCannotDriftFromIt() {
        let expected = claudeClearInputKey.unicodeScalars
            .map { "(character id \($0.value))" }
            .joined(separator: " & ")
        XCTAssertTrue(
            iTermClearInputScript(sessionID: "s").contains("write text (\(expected)) newline NO"),
            iTermClearInputScript(sessionID: "s")
        )
    }

    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(escapeForAppleScript(#"say "hi" \ now"#), #"say \"hi\" \\ now"#)
    }

    func testEscapeNewline() {
        XCTAssertEqual(escapeForAppleScript("a\nb"), #"a\nb"#)
    }

    func testITermScriptEmbedsEscapedCommand() {
        let script = iTermScript(for: #"echo "hi""#)
        XCTAssertTrue(script.contains(#"write text "echo \"hi\"""#))
        // Targeting has to be by bundle ID rather than by name ("iTerm2") — so it keeps working when the app file is called iTerm.app, or when a copy (iTerm Rosetta.app and the like) has confused LaunchServices' name resolution (this is what avoids -1728)
        XCTAssertTrue(script.contains(#"tell application id "com.googlecode.iterm2""#))
        XCTAssertFalse(script.contains(#"tell application "iTerm2""#))
    }

    // For claude input delivery the spawn script has to return a session handle (id|tty)
    func testITermScriptReturnsSessionHandle() {
        let script = iTermScript(for: "echo hi")
        XCTAssertTrue(script.contains(#"(id of s) & "|" & (tty of s)"#))
    }

    // Typing mode: the text alone goes in, with no newline — the submission is sent separately once the screen is confirmed to reflect it
    func testITermWriteToSessionScriptTypingSuppressesNewline() {
        let script = iTermWriteToSessionScript(sessionID: "ABC-123", text: #"say "hi""#, submit: false)
        XCTAssertTrue(script.contains(#"tell application id "com.googlecode.iterm2""#))
        XCTAssertTrue(script.contains(#"if (id of s) is "ABC-123" then"#))
        XCTAssertTrue(script.contains(#"write text "say \"hi\"" newline NO"#))
        // When the session is gone (the tab closed) it returns "gone" so the caller stops the delivery
        XCTAssertTrue(script.contains(#"return "gone""#))
    }

    // Submission mode: only the newline is sent (an empty write text = Enter)
    func testITermWriteToSessionScriptSubmitSendsNewlineOnly() {
        let script = iTermWriteToSessionScript(sessionID: "ABC-123", text: "", submit: true)
        XCTAssertTrue(script.contains(#"write text """#))
        XCTAssertFalse(script.contains("newline NO"))
    }

    func testITermWriteToSessionScriptEscapesSessionID() {
        let script = iTermWriteToSessionScript(sessionID: #"x"y"#, text: "t", submit: false)
        XCTAssertTrue(script.contains(#"if (id of s) is "x\"y" then"#))
    }

    // The script for confirming the screen reflects an input: it returns the session's current screen text
    func testITermSessionContentsScript() {
        let script = iTermSessionContentsScript(sessionID: "ABC-123")
        XCTAssertTrue(script.contains(#"if (id of s) is "ABC-123" then"#))
        XCTAssertTrue(script.contains("return contents of s"))
        XCTAssertTrue(script.contains(#"return "gone""#))
    }
}

// MARK: - Extension ID (unpacked extension: the first 32 hex of SHA-256(absolute path) → a-p)

final class ExtensionIDTests: XCTestCase {
    func testKnownVectors() {
        // The vector is the value computed by the previous Python implementation in install.sh
        XCTAssertEqual(extensionID(forPath: "/Users/test/extension"), "ommholjeknmifgidochbhocolnejiema")
        XCTAssertEqual(extensionID(forPath: "/tmp/e"), "cinkehcaekebplmoijecmdfmflcnboch")
    }

    func testIDIsStable() {
        XCTAssertEqual(extensionID(forPath: "/tmp/e"), extensionID(forPath: "/tmp/e"))
    }

    // With a manifest "key" (a base64 DER public key) present, Chrome builds the ID from that key rather than from the path — only what gets hashed differs; the mapping rule is the same as the path form
    func testKeyBasedIDKnownVector() {
        // base64 "aGVsbG8=" → "hello"; the expected value was computed independently with Python hashlib
        XCTAssertEqual(extensionID(fromManifestKey: "aGVsbG8="), "cmpcenlkfplakdaocgoidlckmfljocjo")
    }

    func testKeyBasedIDRejectsInvalidBase64() {
        XCTAssertNil(extensionID(fromManifestKey: "!!!not-base64!!!"))
        XCTAssertNil(extensionID(fromManifestKey: ""))
    }
}

// MARK: - Native Host manifest JSON

final class ManifestTests: XCTestCase {
    func testManifestJSON() throws {
        let relayPath = "/Applications/Terminal Checkout.app/Contents/MacOS/terminal-checkout-relay"
        let data = nativeHostManifestJSON(relayPath: relayPath, extensionIDs: ["abcdefgh"])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["name"] as? String, "com.dazebug.terminal_checkout")
        XCTAssertEqual(obj["type"] as? String, "stdio")
        XCTAssertEqual(obj["path"] as? String, relayPath)
        XCTAssertEqual(obj["allowed_origins"] as? [String], ["chrome-extension://abcdefgh/"])
    }

    // Ready for the Web Store move: it supports listing the store ID alongside the development one
    func testManifestJSONMultipleOrigins() throws {
        let data = nativeHostManifestJSON(relayPath: "/x", extensionIDs: ["aaa", "bbb"])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            obj["allowed_origins"] as? [String],
            ["chrome-extension://aaa/", "chrome-extension://bbb/"]
        )
    }
}

// MARK: - Native Messaging framing (a 4-byte LE length + JSON)

final class FramingTests: XCTestCase {
    func testFrameMessage() {
        let framed = frameMessage(Data(#"{"a":1}"#.utf8))
        XCTAssertEqual(framed.prefix(4), Data([7, 0, 0, 0]))
        XCTAssertEqual(framed.count, 11)
    }

    func testReadFramedFromPipe() throws {
        let pipe = Pipe()
        pipe.fileHandleForWriting.write(frameMessage(Data("hello".utf8)))
        pipe.fileHandleForWriting.write(frameMessage(Data("world!".utf8)))
        pipe.fileHandleForWriting.closeFile()
        let fd = pipe.fileHandleForReading.fileDescriptor
        XCTAssertEqual(readFramedMessage(fromFD: fd), Data("hello".utf8))
        XCTAssertEqual(readFramedMessage(fromFD: fd), Data("world!".utf8))
        XCTAssertNil(readFramedMessage(fromFD: fd)) // EOF
    }
}

// MARK: - Path constants

final class PathsTests: XCTestCase {
    func testSocketPathEnvOverride() {
        setenv("TERMINAL_CHECKOUT_SOCKET", "/tmp/tc-test.sock", 1)
        defer { unsetenv("TERMINAL_CHECKOUT_SOCKET") }
        XCTAssertEqual(defaultSocketPath(), "/tmp/tc-test.sock")
    }

    func testSocketPathDefault() {
        unsetenv("TERMINAL_CHECKOUT_SOCKET")
        XCTAssertTrue(defaultSocketPath().hasSuffix("/Library/Application Support/TerminalCheckout/host.sock"))
    }
}

// MARK: - Choosing the window a WezTerm tab is created in

final class WezTermWindowTests: XCTestCase {
    // The measured shape of `wezterm cli list-clients --format json`
    private let clientsJSON = Data("""
    [{"username":"u","hostname":"h","pid":96467,
      "connection_elapsed":{"secs":546209,"nanos":0},
      "idle_time":{"secs":9,"nanos":557978000},
      "workspace":"default","focused_pane_id":146}]
    """.utf8)

    // `wezterm cli list --format json` at the same moment (3 windows, at least one tab each)
    private let listJSON = Data("""
    [{"window_id":4,"tab_id":82,"pane_id":147,"tty_name":"/dev/ttys003"},
     {"window_id":3,"tab_id":81,"pane_id":146,"tty_name":"/dev/ttys000"},
     {"window_id":0,"tab_id":4,"pane_id":5,"tty_name":"/dev/ttys001"}]
    """.utf8)

    func testFocusedWindowIDFromClientsAndList() {
        XCTAssertEqual(wezTermFocusedWindowID(clientsJSON: clientsJSON, listJSON: listJSON), "3")
    }

    // With several clients, the most recently active one (the shortest idle_time) is the window the user is looking at
    func testMostRecentlyActiveClientWins() {
        let clients = Data("""
        [{"pid":1,"idle_time":{"secs":300,"nanos":0},"focused_pane_id":5},
         {"pid":2,"idle_time":{"secs":2,"nanos":500000000},"focused_pane_id":147}]
        """.utf8)
        XCTAssertEqual(wezTermFocusedWindowID(clientsJSON: clients, listJSON: listJSON), "4")
    }

    // A client with no focused_pane_id (a mux connection attached without a window) has to be dropped from the candidates
    func testClientWithoutFocusedPaneIgnored() {
        let clients = Data("""
        [{"pid":1,"idle_time":{"secs":0,"nanos":0}},
         {"pid":2,"idle_time":{"secs":90,"nanos":0},"focused_pane_id":5}]
        """.utf8)
        XCTAssertEqual(wezTermFocusedWindowID(clientsJSON: clients, listJSON: listJSON), "0")
    }

    // When the focused pane is not in the list (it closed a moment ago) no window is named — rather than pick the wrong window and spill a tab into it, the choice is left to wezterm's default
    func testUnknownFocusedPaneYieldsNil() {
        let clients = Data(#"[{"idle_time":{"secs":0,"nanos":0},"focused_pane_id":999}]"#.utf8)
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: clients, listJSON: listJSON))
    }

    func testBrokenOrEmptyJSONYieldsNil() {
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: Data("nope".utf8), listJSON: listJSON))
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: clientsJSON, listJSON: Data("nope".utf8)))
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: Data("[]".utf8), listJSON: listJSON))
    }

    // With a window identified, that window is aimed at first, and on failure it is tried once more without one — if the window found closes just before the spawn, wezterm fails with "window_id N not found" (measured), and giving up there lets the `wezterm start` fallback open a new window, resurrecting the very symptom this fixes
    func testSpawnAttemptsRetryWithoutWindowID() {
        XCTAssertEqual(
            wezTermSpawnAttempts(windowID: "3"),
            [["cli", "spawn", "--window-id", "3"], ["cli", "spawn"]]
        )
    }

    // With no window found there is only one attempt — there is no reason to run the same command twice
    func testSpawnAttemptsSingleWhenWindowUnknown() {
        XCTAssertEqual(wezTermSpawnAttempts(windowID: nil), [["cli", "spawn"]])
    }
}

// MARK: - Warp: the Tab Config TOML
// A Tab Config file is the only way to open a new tab in Warp and run a command in it — no AppleScript support, warpctrl disabled by default on Stable, and no CLI that sends text to a pane (measured).

final class WarpTabConfigTests: XCTestCase {
    func testTOMLRunsCommandInSingleTerminalPane() {
        let toml = warpTabConfigTOML(commands: ["z remy && claude"])
        XCTAssertTrue(toml.contains(#"name = "Terminal Checkout""#), toml)
        XCTAssertTrue(toml.contains(#"type = "terminal""#), toml)
        XCTAssertTrue(toml.contains(#"commands = ["z remy && claude"]"#), toml)
    }

    /// Only a button with claude input scheduled starts the helper first. With the order reversed, the helper would not come up until claude had already ended
    func testTOMLRunsHelperBeforeUserCommand() {
        let toml = warpTabConfigTOML(commands: ["'/tmp/helper' '/tmp/x.sock'", "z remy && claude"])
        XCTAssertTrue(
            toml.contains(##"commands = ["'/tmp/helper' '/tmp/x.sock'", "z remy && claude"]"##), toml
        )
    }

    // No directory key — like iTerm2 and WezTerm the pane starts in the default cwd and the
    // command's entry clause (`{cd}`) does the moving. Pinning a cwd here would make the behavior
    // differ per terminal
    func testTOMLDoesNotPinDirectory() {
        XCTAssertFalse(warpTabConfigTOML(commands: ["z remy"]).contains("directory"))
    }

    // `{{name}}` is Warp's parameter template syntax, so declaring [params.*] pops a modal on open — we use no parameters, so we declare none
    func testTOMLDeclaresNoParameters() {
        XCTAssertFalse(warpTabConfigTOML(commands: ["z remy"]).contains("[params"))
    }

    // Measured: an undeclared `{{zzz}}` is passed to the shell as-is, with no substitution and no modal (`printf '%s' 'X{{zzz}}Y'` → the file contains `X{{zzz}}Y`). So it needs no defence of its own
    func testTOMLLeavesWarpTemplateBracesLiteral() {
        let toml = warpTabConfigTOML(commands: ["awk '{{print}}'"])
        XCTAssertTrue(toml.contains(##"commands = ["awk '{{print}}'"]"##), toml)
    }

    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(escapeForTOMLBasicString(#"say "hi" \ now"#), #"say \"hi\" \\ now"#)
    }

    // A TOML basic string cannot carry control characters literally — without escaping, Warp fails to parse the file and the tab does not open at all
    func testEscapeControlCharacters() {
        XCTAssertEqual(escapeForTOMLBasicString("a\nb\tc\rd"), #"a\nb\tc\rd"#)
        XCTAssertEqual(escapeForTOMLBasicString("a\u{01}b"), #"a\u0001b"#)
    }

    func testEscapedCommandStaysOnOneLineInTOML() {
        let toml = warpTabConfigTOML(commands: ["echo \"a\"\nrm -rf /"])
        XCTAssertTrue(toml.contains(#"commands = ["echo \"a\"\nrm -rf /"]"#), toml)
    }

    /// Every request uses a different name — a fixed one silently overwrites a user Tab Config of the same name, and since Warp has not read the file even after `open` returns, consecutive requests swap each other's commands (measured 0.5∼0.7s until the pane appears)
    func testTabConfigNameCarriesTokenSoRunsDoNotCollide() {
        let stem = warpTabConfigStem(token: "deadbeef")
        XCTAssertEqual(stem, "terminal-checkout-deadbeef")
        XCTAssertTrue(warpTabConfigPath(stem: stem).hasSuffix("/.warp/tab_configs/\(stem).toml"))
        XCTAssertEqual(warpTabConfigURL(stem: stem), "warp://tab_config/\(stem)")
    }

    /// Reclaiming may only touch files we created — a user's Tab Config must not be deleted
    func testOnlyOurGeneratedFileIsRecognisedAsOurs() {
        XCTAssertTrue(warpTabConfigIsOurs(contents: warpTabConfigTOML(commands: ["z remy"])))
        XCTAssertFalse(warpTabConfigIsOurs(contents: "name = \"my workspace\"\n"))
        XCTAssertFalse(warpTabConfigIsOurs(contents: ""))
    }

    /// The name is filtered once as well — only **exactly the name we write** (the prefix plus 8 lower-case hex) is a reclaim target. Casting wider deletes files we did not create (round 8, Codex P2): the creation rule and the reclaim rule have to be one source of truth
    func testOnlyOurNamingIsSweptFromTheDirectory() {
        XCTAssertTrue(warpTabConfigFileIsOurs(name: "terminal-checkout-deadbeef.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-myfile.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "my-workspace.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-deadbeef.txt"))
        // Shapes we never write
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-DEADBEEF.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-０１２３abcd.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-abc.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-deadbeefdeadbeef.toml"))
    }

    /// The socket name shares that source of truth — treating an under-length name like `tcw-a.sock` as ours would make another program's socket, belonging to the same user, a reclaim target
    func testOnlyOurSocketNamingIsReclaimable() {
        XCTAssertTrue(warpHelperSocketFileIsOurs(name: "tcw-a1b2c3d4.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-a.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-user.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-A1B2C3D4.sock"))
    }

    /// A fixed-name file left by an early build of this branch is a reclaim target too — but only when its contents are ours
    func testLegacyFixedNameIsSweptOnlyWhenContentsAreOurs() {
        XCTAssertTrue(warpTabConfigFileIsOurs(name: "terminal-checkout.toml"))
    }
}

// MARK: - Warp: the helper launch command and socket path
// The helper has to come up inside the pane — TIOCSTI is allowed only on the calling process's controlling terminal (BSD `isctty`), so an app outside the session cannot put bytes into the pane's tty.

final class WarpHelperLaunchTests: XCTestCase {
    /// The app bundle path contains a space (`Terminal Checkout.app`) — without quoting, the shell splits it into two words and the helper never starts
    func testHelperCommandQuotesPathsWithSpaces() {
        XCTAssertEqual(
            warpHelperCommand(
                executable: "/Users/me/Applications/Terminal Checkout.app/Contents/MacOS/tc-warp-helper",
                socketPath: "/tmp/tcw-ab12.sock"
            ),
            "'/Users/me/Applications/Terminal Checkout.app/Contents/MacOS/tc-warp-helper' '/tmp/tcw-ab12.sock'"
        )
    }

    func testSingleQuoteInPathIsEscaped() {
        XCTAssertEqual(shellSingleQuoted("it's"), #"'it'\''s'"#)
    }

    func testEmptyStringQuotesToEmptyWord() {
        XCTAssertEqual(shellSingleQuoted(""), "''")
    }

    /// A socket path past sun_path's 104-byte limit makes bind fail — the first candidate directory that fits is chosen
    func testSocketPathPicksFirstDirectoryThatFits() {
        let path = warpHelperSocketPath(
            token: "ab12cd34", directories: [String(repeating: "x", count: 120), "/tmp"]
        )
        XCTAssertEqual(path, "/tmp/tcw-ab12cd34.sock")
    }

    func testSocketPathNilWhenNoCandidateFits() {
        XCTAssertNil(
            warpHelperSocketPath(token: "ab12cd34", directories: [String(repeating: "x", count: 120)])
        )
    }

    /// A different token per run is what keeps it from attaching to a dead socket left by an earlier run
    func testSocketNameCarriesToken() {
        XCTAssertEqual(
            warpHelperSocketPath(token: "deadbeef", directories: ["/tmp"]),
            "/tmp/tcw-deadbeef.sock"
        )
    }

    /// Reclaiming applies to our socket names alone — another program's socket must not be deleted
    func testOnlyOurSocketNamesAreReclaimed() {
        XCTAssertTrue(warpHelperSocketFileIsOurs(name: "tcw-deadbeef.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-mysocket.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "other.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-deadbeef.txt"))
    }

    func testTokenIsHexAndVariesBetweenRuns() {
        let tokens = (0..<50).map { _ in warpHelperToken() }
        XCTAssertTrue(tokens.allSatisfy { $0.count == 8 && $0.allSatisfy(\.isHexDigit) }, "\(tokens[0])")
        XCTAssertGreaterThan(Set(tokens).count, 40)
    }
}

// MARK: - Warp: the helper socket protocol
// Requests and responses are line-based ASCII. The bytes to inject ride as base64 — control characters such as CR and Ctrl+U cannot travel raw in a line-based protocol.

final class WarpHelperProtocolTests: XCTestCase {
    private func roundTrip(_ request: WarpHelperRequest) -> WarpHelperRequest? {
        parseWarpHelperRequest(encodeWarpHelperRequest(request))
    }

    func testRequestsRoundTrip() {
        XCTAssertEqual(roundTrip(.tty), .tty)
        XCTAssertEqual(roundTrip(.bye), .bye)
    }

    /// The submission (CR) and the input-box clear (Ctrl+U) have to ride unchanged — one altered byte and claude does not submit the input.
    ///
    /// The list is wider than those two on purpose, and the extra entries are not decoration: the multibyte one is this suite's only check that a payload survives the base64 round trip byte for byte (the helper cuts writes on byte boundaries, so a mangled encoding would surface as a split character), and the empty one is the shape `inject` answers before any of that
    func testInjectCarriesControlBytesUnchanged() {
        for text in ["!gh issue view 1", claudeSubmitKey, claudeClearInputKey, "한글 입력", ""] {
            let request = WarpHelperRequest.inject(expectedPID: 4242, bytes: Data(text.utf8))
            XCTAssertEqual(roundTrip(request), request, text.debugDescription)
        }
    }

    /// An injection request carries "who is expected to read this" along with it — the helper compares that against the foreground at that moment and does not inject when they disagree
    func testInjectCarriesTheExpectedReader() {
        XCTAssertEqual(
            parseWarpHelperRequest(encodeWarpHelperRequest(.inject(expectedPID: 91, bytes: Data("x".utf8)))),
            .inject(expectedPID: 91, bytes: Data("x".utf8))
        )
        XCTAssertNil(parseWarpHelperRequest("inject notapid eA=="))
        XCTAssertNil(parseWarpHelperRequest("inject 91"))
        // Anything at or below 0 is refused — `getpgid(0)` is the caller's group, so in the abnormal situation where the helper is the foreground it would pass as "the expected reader matches"
        XCTAssertNil(parseWarpHelperRequest("inject 0 eA=="))
        XCTAssertNil(parseWarpHelperRequest("inject -1 eA=="))
    }

    func testEncodedRequestIsASingleLine() {
        let line = encodeWarpHelperRequest(.inject(expectedPID: 7, bytes: Data("a\nb".utf8)))
        XCTAssertFalse(line.contains("\n"))
    }

    func testUnknownRequestIsRejected() {
        XCTAssertNil(parseWarpHelperRequest("quit"))
        XCTAssertNil(parseWarpHelperRequest(""))
        XCTAssertNil(parseWarpHelperRequest("inject"))
    }

    func testInjectWithBadBase64IsRejected() {
        XCTAssertNil(parseWarpHelperRequest("inject 91 !!!not-base64!!!"))
    }

    func testResponsesRoundTrip() {
        XCTAssertEqual(
            parseWarpHelperResponse(encodeWarpHelperResponse(.ok("/dev/ttys026"))), .ok("/dev/ttys026")
        )
        XCTAssertEqual(parseWarpHelperResponse(encodeWarpHelperResponse(.ok(""))), .ok(""))
        XCTAssertEqual(parseWarpHelperResponse(encodeWarpHelperResponse(.err("ENXIO"))), .err("ENXIO"))
    }

    /// Reading a line without the prefix as a success reports a failure as a success
    func testResponseWithoutPrefixIsRejected() {
        XCTAssertNil(parseWarpHelperResponse("/dev/ttys026"))
        XCTAssertNil(parseWarpHelperResponse(""))
    }
}

// MARK: - What happens to non-ASCII text on its way through Process.arguments

/// **Measured, and it is a boundary rather than a bug of ours**: Foundation hands `Process`
/// arguments to the child re-encoded as NFD on Darwin. Text we hold as NFC — which is what a user
/// types and what a Swift literal in this repository is — arrives decomposed on the other side.
///
/// It is pinned here because it is invisible everywhere else. Swift's `==` compares strings by
/// canonical equivalence, so the two forms are *equal* in every assertion that does not look at
/// bytes; the first thing this boundary broke was a test of ours that compared a Korean pattern
/// against file bytes with `grep` and silently stopped matching (round 5).
///
/// Where it used to reach a user: `runInITerm` put the claude message inside an AppleScript handed
/// to `osascript -e`, and the WezTerm fallback put the command in argv the same way. Both now avoid
/// the boundary rather than survive it (`AppleScriptCarrierTests`, `WezTermFallbackCarrierTests`);
/// this class only pins what the platform does, so a change in **that** fails here rather than out
/// there. It is also why the two carrier classes measure bytes and not strings.
final class ProcessArgumentBoundaryTests: XCTestCase {
    private let composed = "설계"

    /// Comparison is on **bytes**. `XCTAssertEqual` on the strings passes either way, which is
    /// exactly why the boundary went unnoticed for as long as it did.
    func testANonASCIIArgumentReachesTheChildDecomposed() throws {
        let result = try runProcess(
            "/bin/bash", ["-c", #"printf '%s' "$1""#, "probe", composed], timeout: 10
        )
        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(
            Array(result.stdout.utf8),
            Array(composed.decomposedStringWithCanonicalMapping.utf8),
            "the child no longer sees NFD — the boundary changed and everything built on it needs rereading"
        )
        XCTAssertNotEqual(Array(result.stdout.utf8), Array(composed.utf8))
        XCTAssertEqual(result.stdout, composed, "the two forms stay canonically equal, which is what hides this")
    }

    /// The same for a path, which is the shape the Warp helper's socket and executable travel in.
    /// Nothing in the repository writes a non-ASCII path today; what makes it reachable is the
    /// user's `TMPDIR` or a bundle sitting under a folder they named themselves.
    func testANonASCIIPathArgumentIsDecomposedToo() throws {
        let path = "/tmp/터미널/tcw-deadbeef.sock"
        let result = try runProcess("/bin/bash", ["-c", #"printf '%s' "$1""#, "probe", path], timeout: 10)
        XCTAssertEqual(
            Array(result.stdout.utf8), Array(path.decomposedStringWithCanonicalMapping.utf8)
        )
    }

    /// The way out, measured alongside: bytes read from a **file** are not touched. Round 5's
    /// uninstall sweep test moved to running the script from a file for this reason.
    func testTextReadFromAFileKeepsItsBytes() throws {
        let path = NSTemporaryDirectory() + "tc-argv-\(UInt32.random(in: .min ... .max)).txt"
        try composed.write(toFile: path, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: path) }
        let result = try runProcess("/bin/cat", [path], timeout: 10)
        XCTAssertEqual(Array(result.stdout.utf8), Array(composed.utf8))
    }
}

// MARK: - The carriers that were changing the user's bytes

/// Every `.swift` file under `app/Sources`, keyed by its path relative to the repository root.
/// Located from `#filePath` for the same reason `repoFileContents` is — the CWD depends on how the
/// test was invoked, and in a worktree the wrong checkout would be read.
private func appSourceFiles() throws -> [(path: String, text: String)] {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // app
    let sources = root.appendingPathComponent("Sources")
    guard let walk = FileManager.default.enumerator(atPath: sources.path) else {
        throw CocoaError(.fileReadNoSuchFile)
    }
    var found: [(String, String)] = []
    for case let name as String in walk where name.hasSuffix(".swift") {
        found.append((name, try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)))
    }
    // An empty walk would make every gate below pass without reading anything
    guard !found.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
    return found
}

/// **Where the boundary above reaches a user, and what was done about it.**
///
/// `ProcessArgumentBoundaryTests` pins the platform fact — Foundation re-encodes argv to NFD. The
/// iTerm2 branch is where a user meets it: the command and every claude input are embedded in an
/// AppleScript that used to be handed over as `osascript -e <script>`, so a message written in
/// Korean, Japanese or Chinese arrived decomposed, and a `!` input carrying it arrived decomposed
/// **at the shell** — which is exactly how round 5's own `grep` silently stopped matching.
///
/// The repair is the **carrier**, not a normalisation of our own. Normalising to NFC would change
/// what a user who typed NFD wrote, and this feature's promise is the bytes they wrote. Measured
/// three ways for `설계` (NFC `C124 ACC4`, NFD `1109 1165 11AF 1100 1168`): `-e` gives the
/// interpreter the NFD code points and those NFD bytes leave AppleScript again through both
/// `do shell script` and its own UTF-8 writer; `osascript -` and a script file both give `C124 ACC4`.
/// `Process.environment` was measured at the same time and decomposes **just like argv**, so it is
/// not an escape hatch for anything.
///
/// **The limit of what is measured here**: the last hop, iTerm2's `write text` putting those bytes
/// on the tty, needs iTerm2 running and is not measured — the AppleScript string's own bytes are as
/// far as this gets. It is one step further than round 6, which stopped at the interpreter's code
/// points.
final class AppleScriptCarrierTests: XCTestCase {
    private let message = "설계 정리해줘"

    /// AppleScript writes its own string out as UTF-8. That is the closest observable stand-in for
    /// what `write text` hands the terminal, and it touches no terminal and needs no permission.
    func testAScriptLiteralKeepsTheBytesTheUserWrote() throws {
        let sink = NSTemporaryDirectory() + "tc-as-\(UInt32.random(in: .min ... .max)).bin"
        defer { try? FileManager.default.removeItem(atPath: sink) }
        let script = """
        set f to open for access POSIX file "\(sink)" with write permission
        write "\(escapeForAppleScript(message))" to f as «class utf8»
        close access f
        """
        let result = try runAppleScript(script, timeout: 30)
        XCTAssertEqual(result.status, 0, result.stderr)
        let written = try Data(contentsOf: URL(fileURLWithPath: sink))
        XCTAssertEqual(
            Array(written), Array(message.utf8),
            "the AppleScript carrier changed the bytes (decomposed: "
                + "\(Array(written) == Array(message.decomposedStringWithCanonicalMapping.utf8)))"
        )
    }

    /// **The door has to be the only one.** Fixing one send site and missing another is the defect
    /// this repository has already paid for once (body typing leaked past the session gate), so the
    /// rule is enforced by counting rather than by discipline: the osascript path appears in exactly
    /// one file. What this cannot see is a *new* carrier of some other kind — it answers "did an
    /// AppleScript call go back to argv", not "is every process boundary byte-exact".
    func testEveryAppleScriptRunGoesThroughTheOneDoor() throws {
        let door = "Core/AppleScriptSupport.swift"
        var sites: [String] = []
        for (path, text) in try appSourceFiles() where text.contains("\"/usr/bin/osascript\"") {
            sites.append(path)
        }
        XCTAssertEqual(sites, [door], "an AppleScript call outside \(door)")
    }

    /// **The literal above is evadable by spelling, so the token is banned as well.**
    ///
    /// Measured: a second call site written `let tool = "/usr/bin/" + "osascript"` passed the check
    /// above — the scope was right (it walks every source) and the predicate was narrower than the
    /// property, because a computed path is not the literal it searches for.
    ///
    /// **This cannot be made exact and is not claimed to be.** What a computed string turns out to
    /// be is undecidable from the text, and `"osas" + "cript"` defeats any spelling of this rule. So
    /// the rule is deliberately blunt: outside the door, the seven characters may not appear in code
    /// at all. Getting past it now takes a name assembled from pieces that never spell it — which is
    /// an act of intent, not the accident this is here to catch.
    ///
    /// **Comments are exempt**, and that is not laziness: six files explain *why* AppleScript is
    /// confined to one door, and a rule that punished the explanation would be deleted the first
    /// time someone documented this properly. Code is where the process gets launched.
    func testNoSourceOutsideTheDoorEvenNamesTheInterpreter() throws {
        let door = "Core/AppleScriptSupport.swift"
        var offenders: [String] = []
        for (path, text) in try appSourceFiles() where !path.hasSuffix(door) {
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.trimmingCharacters(in: .whitespaces)
                guard !code.hasPrefix("//") else { continue }
                if code.contains("osascript") { offenders.append("\(path):\(number + 1)") }
            }
        }
        XCTAssertEqual(
            offenders, [],
            "a source outside \(door) names the AppleScript interpreter in code — every run goes through runAppleScript"
        )
    }

    /// The door must not grow an argv form again — `-e` is the spelling that decomposes.
    func testTheDoorDeliversTheScriptOnStdin() throws {
        let text = try appSourceFiles().first { $0.path.hasSuffix("Core/AppleScriptSupport.swift") }?.text
        XCTAssertNotNil(text)
        XCTAssertTrue(text?.contains(#"["-"], input: script"#) == true)
        XCTAssertFalse(text?.contains(#""-e""#) == true, "the door is back on the argv form")
    }
}

/// The WezTerm fallback is the same class and it is **reachable**: a request whose claude input is a
/// single plain-text message has that message appended to the command (`appendedPromptCommand`) and
/// comes back with `claudeInputs` empty, so `injectsClaudeInput` is false, so
/// `wezTermFallbackRejection` lets the fallback run — with the user's sentence inside the command.
/// It is the no-mux path, which is every first click before WezTerm has ever been started.
///
/// It has no stdin and no file to ride on, and the environment decomposes too, so the argument is
/// made **ASCII** instead: an argument that is already ASCII cannot be changed by a re-encoding
/// between NFC and NFD, and bash puts the bytes back.
final class WezTermFallbackCarrierTests: XCTestCase {
    private let message = "설계 — it's \"quoted\" $HOME `now`"

    func testTheFallbackPutsNoNonASCIIIntoArgv() {
        let command = "z remy && command claude -- \(shellSingleQuoted(message))"
        for argument in wezTermFallbackArguments(command: command) {
            XCTAssertTrue(
                argument.allSatisfy(\.isASCII),
                "a non-ASCII argument is re-encoded to NFD before the child sees it: \(argument)"
            )
        }
    }

    /// End to end through the real boundary: the exact two arguments `/bin/bash` is handed, run by
    /// `/bin/bash`. Only WezTerm's own forwarding of argv is left out, and that is unchanged.
    /// `exec bash` at the end reads EOF from the null stdin and exits, so this terminates.
    func testTheFallbackScriptRunsTheCommandsExactBytes() throws {
        let sink = NSTemporaryDirectory() + "tc-wez-\(UInt32.random(in: .min ... .max)).bin"
        defer { try? FileManager.default.removeItem(atPath: sink) }
        let command = "printf %s \(shellSingleQuoted(message)) > \(sink)"
        let arguments = wezTermFallbackArguments(command: command)
        XCTAssertEqual(Array(arguments.prefix(3)), ["start", "--", "/bin/bash"])
        let result = try runProcess("/bin/bash", Array(arguments.suffix(2)), timeout: 20)
        XCTAssertEqual(result.status, 0, result.stderr)
        let written = try Data(contentsOf: URL(fileURLWithPath: sink))
        XCTAssertEqual(
            Array(written), Array(message.utf8),
            "the fallback changed the command's bytes (decomposed: "
                + "\(Array(written) == Array(message.decomposedStringWithCanonicalMapping.utf8)))"
        )
    }

    /// An all-ASCII command has to stay readable — in `ps`, and in the pane the user is looking at.
    /// A blanket byte-by-byte escape would pass the test above and turn every command into hex.
    func testAnASCIICommandStaysReadable() {
        let arguments = wezTermFallbackArguments(command: "z remy && claude")
        XCTAssertTrue(
            arguments.last?.contains("z remy && claude") == true,
            arguments.last ?? "no script argument"
        )
    }
}

// MARK: - Warp: the foreground verdict immediately before injecting
// TIOCSTI only checks whether it is the caller's session; **it does not decide who reads those bytes**. If claude dies and the shell becomes the foreground, the shell reads the CR left in the queue and runs the user's draft.
// Measured: the claude pid the app picks is sometimes not the process group leader (3 of 13 panes) — which is why the comparison is against `getpgid(pid)` rather than the pid.

final class WarpForegroundTests: XCTestCase {
    func testForegroundMatchesExpectedGroup() {
        XCTAssertEqual(warpForeground(foregroundPGID: 4242, expectedPGID: 4242), .expected)
    }

    func testDifferentGroupIsBlocked() {
        XCTAssertEqual(warpForeground(foregroundPGID: 4242, expectedPGID: 99), .different)
    }
}

/// **"Could not be told" is its own answer** (round 6 review). The verdict used to be a `Bool`, so
/// a failed `tcgetpgrp` or `getpgid` — which returns -1 — came back as the same value as "somebody
/// else is attached". Refusing to inject in both cases is right and has not changed; reporting both
/// as a different reader was a claim nobody had established, and no wording could fix it while the
/// two shared one value.
///
/// This is the last gate in front of `TIOCSTI`, which only enqueues and does not decide who reads
/// (`CLAUDE.md`), so the distinction is not cosmetic: it is the difference between "the shell took
/// our CR" and "we could not look".
final class WarpForegroundUnknownTests: XCTestCase {
    /// Every shape a failed lookup takes. -1 is what the syscalls return; 0 is not a process group
    /// either, and letting it through would compare two zeroes into `.expected`.
    func testAFailedLookupIsUnknownAndNotDifferent() {
        for (foreground, expected) in [(-1, -1), (4242, -1), (-1, 4242), (0, 0), (4242, 0)] {
            XCTAssertEqual(
                warpForeground(foregroundPGID: Int32(foreground), expectedPGID: Int32(expected)),
                .unknown, "\(foreground)/\(expected)"
            )
        }
    }

    /// Fail-closed is unchanged: both non-expected states refuse in exactly the same way. What
    /// changed is that the caller can still tell them apart when it writes down what happened.
    func testUnknownRefusesLikeDifferentButIsNotTheSameValue() {
        XCTAssertNotEqual(WarpForeground.unknown, .different)
        for foreground in [WarpForeground.different, .unknown] {
            XCTAssertNotEqual(
                warpInjectWatchDecision(pending: 0, foreground: foreground, budgetExpired: false),
                .delivered, "\(foreground)"
            )
            XCTAssertEqual(
                warpInjectWatchDecision(pending: 4, foreground: foreground, budgetExpired: false),
                .readerUnconfirmed(pending: 4), "\(foreground)"
            )
        }
    }

    /// The success path is the one place the answer has to be `.expected` exactly — an unknown
    /// foreground reaching `.delivered` is the failure this whole gate exists to prevent.
    func testOnlyAConfirmedForegroundCanDeliver() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 0, foreground: .expected, budgetExpired: false),
            .delivered
        )
    }
}

/// The two remaining places a safety check reduced an unreadable answer to a safe-looking one
/// (round 7 review). Both are the shape gate ②'s `?? true` had: the fold is invisible because the
/// type has nowhere to keep "could not tell".
final class WarpUnknownFoldTests: XCTestCase {
    /// `tcgetsid` and `getsid` both answer **-1 on failure**, so a raw `==` compared two failures as
    /// equal and the helper concluded the tty was still its own — while holding an fd it could not
    /// identify. Requiring both to be positive is the whole fix.
    func testTwoFailedSessionLookupsAreNotAMatch() {
        XCTAssertTrue(warpTTYSessionIsOurs(ttySID: 4242, ourSID: 4242))
        XCTAssertFalse(warpTTYSessionIsOurs(ttySID: 4242, ourSID: 99))
        XCTAssertFalse(warpTTYSessionIsOurs(ttySID: -1, ourSID: -1), "two failed lookups read as a match")
        XCTAssertFalse(warpTTYSessionIsOurs(ttySID: 0, ourSID: 0))
        XCTAssertFalse(warpTTYSessionIsOurs(ttySID: -1, ourSID: 4242))
        XCTAssertFalse(warpTTYSessionIsOurs(ttySID: 4242, ourSID: -1))
    }

    /// A negative pending count is a malformed answer, not an empty queue. `pending <= 0` reported
    /// it as delivery — success derived from a number that means nothing.
    func testANegativeQueueCountIsNotDelivery() {
        for pending in [-1, -512] {
            XCTAssertNotEqual(
                warpInjectWatchDecision(pending: pending, foreground: .expected, budgetExpired: false),
                .delivered, "\(pending)"
            )
            XCTAssertNotEqual(
                warpInjectWatchDecision(pending: pending, foreground: .unknown, budgetExpired: false),
                .delivered, "\(pending)"
            )
        }
        // Zero is still delivery when the foreground is confirmed — the fix narrows nothing else
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 0, foreground: .expected, budgetExpired: false), .delivered
        )
    }

    /// The diagnosis comes from the value rather than from a ternary that had to be right about
    /// which states could reach it: `.expected` used to be worded "could not be read".
    func testEveryForegroundStateWordsItself() {
        XCTAssertEqual(WarpForeground.expected.diagnosis, "the foreground is the reader we aimed at")
        XCTAssertEqual(WarpForeground.different.diagnosis, "the foreground was a different process group")
        XCTAssertEqual(WarpForeground.unknown.diagnosis, "the foreground could not be read")
        XCTAssertEqual(Set([WarpForeground.expected, .different, .unknown].map(\.diagnosis)).count, 3)
    }
}

// MARK: - Warp: the helper stop verdict
// The caps and the tty identity are gathered into one function — if the waiting loop and the request-handling path used different criteria, someone holding the connection open and requesting continuously would bypass the caps entirely.

final class WarpHelperBudgetTests: XCTestCase {
    /// If the helper spent longer on one request than the app waits for a response, the previous request's injection would keep running while the app gives up and retries, and those bytes would mix with the retry's and with the user's input.
    /// Keeping the two numbers separate is how they drift apart again, so the second is derived from the first in one place
    func testHelperFinishesWellBeforeTheAppGivesUp() {
        XCTAssertLessThan(warpHelperWorkBudget, warpHelperRequestTimeout)
        XCTAssertLessThanOrEqual(warpHelperWorkBudget * 2, warpHelperRequestTimeout)
    }
}

final class WarpHelperStopTests: XCTestCase {
    private func reason(
        tty: Bool = true, idle: TimeInterval = 0, alive: TimeInterval = 0
    ) -> WarpHelperStop? {
        warpHelperStopReason(
            ttySessionMatches: tty, idleSeconds: idle, aliveSeconds: alive,
            idleLimit: 180, lifetimeLimit: 900
        )
    }

    func testKeepsRunningWithinEveryLimit() {
        XCTAssertNil(reason(idle: 179, alive: 899))
    }

    /// tty numbers get reused — once our pane closes and a new session takes the same number, the remaining injection goes into somebody else's tty. This is checked before anything else
    func testTTYSessionChangeStopsEverything() {
        XCTAssertEqual(reason(tty: false), .ttySessionChanged)
        XCTAssertEqual(reason(tty: false, idle: 0, alive: 0), .ttySessionChanged)
    }

    func testIdleAndLifetimeLimits() {
        XCTAssertEqual(reason(idle: 181), .idle)
        XCTAssertEqual(reason(alive: 901), .lifetime)
    }
}

// MARK: - Warp: splitting an injection
// The tty input queue has a cap (TTYHOG) and the kernel silently drops whatever overflows it. So a claude input over 512 bytes does not fail wholesale: it is written in pieces sized to the queue's headroom, waiting for consumption in between.

final class WarpInjectChunkTests: XCTestCase {
    /// Regression guard (P0-1): nothing is written while **even one byte** remains in the queue. Continuing just because there is room leaves the previous piece's tail in the queue while the next piles on, and once claude reads only the first 24 characters and draws them, the screen check passes — then, when claude ends, **the shell reads and runs** the remaining tail
    func testChunkOnlyGoesIntoAnEmptyQueue() {
        XCTAssertEqual(warpInjectChunkSize(pending: 1, remaining: 1000, limit: 512), 0)
        XCTAssertEqual(warpInjectChunkSize(pending: 100, remaining: 1000, limit: 512), 0)
        XCTAssertEqual(warpInjectChunkSize(pending: 512, remaining: 10, limit: 512), 0)
    }

    func testEmptyQueueTakesAFullChunk() {
        XCTAssertEqual(warpInjectChunkSize(pending: 0, remaining: 1000, limit: 512), 512)
        XCTAssertEqual(warpInjectChunkSize(pending: 0, remaining: 30, limit: 512), 30)
    }
}

// MARK: - Warp: watching whether the injected bytes get read
// Delivery only counts once the queue is seen to drain after the write. The `FIONREAD` consulted here is the **negative** signal "not read yet" alone, and it **says nothing about whose** the remaining bytes are — it is a single total, so ours cannot be separated from the keys the user just typed. That is why the verdict ends at one sample and takes no history as an argument: the moment it does, the branch that "infers the origin from a change in the total" comes back.

final class WarpInjectWatchTests: XCTestCase {
    /// Regression guard (reviewer reproduction ①): the old verdict compared against the previous sample and read "the queue grew, so the user's keys got mixed in", but **the first sample has nothing to compare against** and so could never establish that anything was mixed in whatever its value. If the user typed one character after claude had read all of our bytes and the foreground changed at that moment, that character was taken for ours and the whole queue was discarded (`tcflush`) — a misjudgement that silently erases the user's keys.
    func testFirstSampleNeverJustifiesDiscardingTheQueue() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 1, foreground: .different, budgetExpired: false),
            .readerUnconfirmed(pending: 1)
        )
    }

    /// Regression guard (reviewer reproduction ②): past the first sample it is no different. If the user types 4 bytes while claude reads 5, the queue **shrinks** from 10 to 9 — a monotonic decrease is no evidence that "what remains is our bytes". At any sample the conclusion is the same: discard nothing and report only the failure.
    func testMonotonicDecreaseIsNotProofOfOwnership() {
        for pending in [10, 9] {
            XCTAssertEqual(
                warpInjectWatchDecision(pending: pending, foreground: .different, budgetExpired: false),
                .readerUnconfirmed(pending: pending)
            )
        }
    }

    /// Success is **only the case where our reader is what emptied the queue**
    func testDeliveredOnlyWhenOurReaderEmptiedTheQueue() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 0, foreground: .expected, budgetExpired: false), .delivered
        )
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 0, foreground: .expected, budgetExpired: true), .delivered
        )
    }

    /// The queue drained while the foreground was not confirmed to be ours — the usual way there is claude ending in between and the shell inheriting the queue, and since which of them consumed the bytes is not observable, the verdict has to be failure either way. Answering success makes the app put a CR on top, and the user's next Enter runs that line.
    ///
    /// **Both non-expected states reach it**, which is the fail-closed rule: an unreadable
    /// foreground is not evidence of a different reader, and it is not evidence of ours either
    func testEmptyQueueWithoutAConfirmedReaderIsFailure() {
        for foreground in [WarpForeground.different, .unknown] {
            XCTAssertEqual(
                warpInjectWatchDecision(pending: 0, foreground: foreground, budgetExpired: false),
                .drainedWithoutConfirmedReader, "\(foreground)"
            )
        }
    }

    /// While our reader is unchanged it waits for as long as the budget lasts
    func testWaitsWhileOurReaderStillHasBytes() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 7, foreground: .expected, budgetExpired: false), .keepWaiting
        )
    }

    /// Not read within the budget is a failure (fail-closed) — answering success puts a CR on top of the tail left in the queue
    func testBudgetExpiryFailsClosed() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 7, foreground: .expected, budgetExpired: true),
            .queueNotEmptyAtDeadline(pending: 7)
        )
    }

    /// The branch where the reader is not confirmed reaches the same conclusion regardless of the budget — the remaining bytes are not discarded
    func testAnUnconfirmedReaderOutranksTheBudget() {
        for foreground in [WarpForeground.different, .unknown] {
            XCTAssertEqual(
                warpInjectWatchDecision(pending: 3, foreground: foreground, budgetExpired: true),
                .readerUnconfirmed(pending: 3), "\(foreground)"
            )
        }
    }
}


// MARK: - Warp: the line-oriented receive buffer
// A socket read() does not respect line boundaries — two lines can arrive at once, and one line can arrive split.

final class LineBufferTests: XCTestCase {
    func testYieldsCompleteLinesAndKeepsThePartialTail() {
        var buffer = LineBuffer()
        buffer.append(Data("tty\nb".utf8))
        XCTAssertEqual(buffer.nextLine(), "tty")
        XCTAssertNil(buffer.nextLine())
        buffer.append(Data("ye\n".utf8))
        XCTAssertEqual(buffer.nextLine(), "bye")
        XCTAssertNil(buffer.nextLine())
    }

    func testYieldsTwoLinesArrivingTogether() {
        var buffer = LineBuffer()
        buffer.append(Data("tty\nbye\n".utf8))
        XCTAssertEqual(buffer.nextLine(), "tty")
        XCTAssertEqual(buffer.nextLine(), "bye")
        XCTAssertNil(buffer.nextLine())
    }

    /// A peer that never sends a newline is not given unbounded memory
    func testOverlongTailIsRejected() {
        var buffer = LineBuffer(limit: 16)
        buffer.append(Data(String(repeating: "x", count: 17).utf8))
        XCTAssertTrue(buffer.isOverflowed)
        XCTAssertNil(buffer.nextLine())
    }

    /// Regression guard (P0-4): an over-cap line that arrives **together with its final newline** passes straight through a tail-only check — the same cap applies to completed lines
    func testOverlongCompletedLineIsRejected() {
        var buffer = LineBuffer(limit: 16)
        buffer.append(Data((String(repeating: "x", count: 20) + "\n").utf8))
        XCTAssertTrue(buffer.isOverflowed)
        XCTAssertNil(buffer.nextLine())
    }

    func testLinesWithinTheLimitStillPassWhenManyArriveAtOnce() {
        var buffer = LineBuffer(limit: 16)
        buffer.append(Data("tty\nbye\ntty\n".utf8))
        XCTAssertFalse(buffer.isOverflowed)
        XCTAssertEqual(buffer.nextLine(), "tty")
        XCTAssertEqual(buffer.nextLine(), "bye")
        XCTAssertEqual(buffer.nextLine(), "tty")
    }
}

// MARK: - Warp: the process tree
// The pane's shell is a direct child of Warp's `terminal-server`, and the GUI process is that one's parent (measured).
// The GUI pid is what identifies the target process when the screen is read through Accessibility.

final class WarpProcessTests: XCTestCase {
    private let exePath = "/Applications/Warp.app/Contents/MacOS/stable"

    /// The measured shape of `ps -axo pid=,ppid=,command=`
    private let psOutput = """
        1     0 /sbin/launchd
    17699     1 /Applications/Warp.app/Contents/MacOS/stable
    17700 17699 /Applications/Warp.app/Contents/MacOS/stable terminal-server --parent-pid=17699
    17710 17700 -zsh -g --no_rcs
    96467     1 /Applications/WezTerm.app/Contents/MacOS/wezterm-gui
    """

    func testGUIPIDIsParentOfTerminalServer() {
        XCTAssertEqual(warpGUIPIDs(psOutput: psOutput, executablePath: exePath), [17699])
    }

    /// Mistaking the argument-less GUI process itself for terminal-server would name the GUI's parent (launchd) as Warp
    func testGUIProcessItselfIsNotTerminalServer() {
        XCTAssertFalse(warpGUIPIDs(psOutput: psOutput, executablePath: exePath).contains(1))
    }

    /// Looking at a Warp installed somewhere else catches nothing
    func testDifferentExecutablePathMatchesNothing() {
        XCTAssertEqual(
            warpGUIPIDs(
                psOutput: psOutput,
                executablePath: "/Users/me/Applications/Warp.app/Contents/MacOS/stable"
            ),
            []
        )
    }

    /// Launching Warp twice yields two terminal-servers — both stay as candidates
    func testTwoWarpInstancesYieldTwoGUIPIDs() {
        let ps = psOutput
            + "\n30000 29999 /Applications/Warp.app/Contents/MacOS/stable terminal-server --parent-pid=29999"
        XCTAssertEqual(warpGUIPIDs(psOutput: ps, executablePath: exePath), [17699, 29999])
    }
}

// MARK: - Warp: the handles that need a pane proof
// Whether a screen read can be asserted to belong to that session differs per terminal. Getting this verdict wrong makes iTerm2 and WezTerm pay an unnecessary proof cost, or lets Warp submit without one.

final class PaneProofRoutingTests: XCTestCase {
    func testOnlyWarpNeedsPaneProof() {
        XCTAssertTrue(TerminalSessionHandle.warp(helperSocket: "/tmp/x.sock").screenNeedsPaneProof)
        XCTAssertFalse(TerminalSessionHandle.iterm(sessionID: "s", tty: "/dev/ttys001").screenNeedsPaneProof)
        XCTAssertFalse(
            TerminalSessionHandle.wezterm(paneID: "1", cliPath: "/x", socketPath: nil).screenNeedsPaneProof
        )
        XCTAssertFalse(TerminalSessionHandle.none.screenNeedsPaneProof)
    }

    /// The marker has to be something only our run can produce, and it must mean nothing special to claude's input box
    func testPaneProofTokenIsPlainAndUnique() {
        let tokens = (0..<50).map { _ in paneProofToken() }
        // Alphanumerics only — `/`, `!` and `@` trigger modes and completion in claude's input box
        XCTAssertTrue(tokens.allSatisfy { token in token.allSatisfy { $0.isLetter || $0.isNumber } })
        // Long enough that the same value cannot appear in another pane by chance, and different on every run
        XCTAssertTrue(tokens.allSatisfy { $0.count == 12 })
        XCTAssertGreaterThan(Set(tokens).count, 45)
    }
}

// MARK: - Warp: reclaiming (what an abnormal exit leaves behind)
// The normal paths clean up after themselves (the helper on `bye`, on the pane closing and on signals; `runInWarp` once the tab has opened).
// Only SIGKILL and an app crash skip those, so the next run sweeps up — on the condition that it **never touches anything alive**: deleting the wrong thing removes the channel of a session mid-delivery.

final class WarpReclaimTests: XCTestCase {
    private var directory = ""

    override func setUp() {
        super.setUp()
        directory = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("tc-reclaim-\(UInt32.random(in: .min ... .max))")
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: directory)
        super.tearDown()
    }

    @discardableResult
    private func write(_ name: String, _ contents: String = "", ageSeconds: TimeInterval) -> String {
        let path = (directory as NSString).appendingPathComponent(name)
        FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
        try? FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-ageSeconds)], ofItemAtPath: path
        )
        return path
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    private func listeningSocket(at path: String) throws -> Int32 {
        var address = try XCTUnwrap(makeUnixSockaddr(path))
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bound, 0)
        XCTAssertEqual(listen(fd, 1), 0)
        return fd
    }

    /// A socket whose owner died = the file survives with nobody listening (a helper that ended on SIGKILL)
    func testDeadHelperSocketIsRemoved() throws {
        let path = (directory as NSString).appendingPathComponent("tcw-deadbeef.sock")
        close(try listeningSocket(at: path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: path
        )
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertFalse(exists(path))
    }

    /// Deleting a live helper's socket cuts off that session's delivery entirely
    func testLiveHelperSocketIsKept() throws {
        let path = (directory as NSString).appendingPathComponent("tcw-cafebabe.sock")
        let fd = try listeningSocket(at: path)
        defer { close(fd) }
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: path
        )
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(path))
    }

    /// Connections are refused between `bind` and `listen` — deleting a freshly created file removes the socket of a helper caught in that window
    func testFreshHelperSocketIsKept() {
        let path = write("tcw-facefeed.sock", ageSeconds: 1)
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(path))
    }

    /// Regression guard (P0-3): deleting by name alone removes a **regular file** of the same name (Codex's reproduction)
    func testRegularFileWithOurSocketNameIsNotRemoved() {
        let path = write("tcw-deadbeef.sock", "a user's file", ageSeconds: 3000)
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(path))
    }

    /// Following a symbolic link to delete removes whatever file of somebody else's the link points at
    func testSymlinkWithOurSocketNameIsNotRemoved() throws {
        let target = write("someone-elses-file.txt", "something precious", ageSeconds: 3000)
        let link = (directory as NSString).appendingPathComponent("tcw-cafed00d.sock")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(target))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link))
    }

    /// The scheduled deletion 20 seconds later must not go by path alone either — the user may have put their own file at that path in the meantime
    func testScheduledTabConfigRemovalRechecksTheHeader() {
        let ours = write("terminal-checkout-deadbeef.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 0)
        removeWarpTabConfigIfOurs(path: ours)
        XCTAssertFalse(exists(ours))

        let theirs = write("terminal-checkout-cafebabe.toml", "name = \"mine\"\n", ageSeconds: 0)
        removeWarpTabConfigIfOurs(path: theirs)
        XCTAssertTrue(exists(theirs))
    }

    /// Regression guard (P0-3): when a symbolic link bearing our name points at a file carrying our header, a path-based verdict **deletes the link itself**. The socket side was covered by `lstat` and this one had been missed
    func testSymlinkWithOurTabConfigNameIsNotRemoved() throws {
        let target = write("someone-elses-file.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 600)
        let link = (directory as NSString).appendingPathComponent("terminal-checkout-deadbeef.toml")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        removeWarpTabConfigIfOurs(path: link)
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertNotNil(try? FileManager.default.attributesOfItem(atPath: link), "the link was deleted")
        XCTAssertTrue(exists(target))
    }

    func testForeignSocketIsNeverTouched() {
        let path = write("other.sock", ageSeconds: 3000)
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(path))
    }

    func testStaleTabConfigIsRemoved() {
        let path = write(
            "terminal-checkout-deadbeef.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 600
        )
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertFalse(exists(path))
    }

    /// Deleting another request's file while it is opening right now means that tab never opens
    func testFreshTabConfigIsKept() {
        let path = write(
            "terminal-checkout-deadbeef.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 5
        )
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertTrue(exists(path))
    }

    /// A user file whose name collides is filtered out by its contents — somebody else's Tab Config must not be deleted
    func testUserFileWithOurNamingIsKept() {
        let path = write("terminal-checkout-deadbeef.toml", "name = \"my workspace\"\n", ageSeconds: 600)
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertTrue(exists(path))
    }

    /// A file written with the **legacy header** is still reclaimed. Every other fixture here uses
    /// `warpTabConfigTOML`, which writes today's token, so without this one the whole reclaim path
    /// would only ever be exercised against the new marker — and the files actually at risk are the
    /// ones already on disk carrying the old one.
    func testTabConfigWrittenByAnOlderBuildIsStillRemoved() {
        let legacy = warpTabConfigLegacyHeader + " — 탭이 열리면 지웁니다.\nname = \"Terminal Checkout\"\n"
        let path = write("terminal-checkout-deadbeef.toml", legacy, ageSeconds: 600)
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertFalse(exists(path), "a Tab Config from an older build was left behind")
    }

    /// The same for the scheduled single-file delete, which reaches the verdict through an fd.
    func testRemoveByPathAlsoAcceptsTheLegacyHeader() {
        let legacy = warpTabConfigLegacyHeader + "\nname = \"Terminal Checkout\"\n"
        let path = write("terminal-checkout-cafebabe.toml", legacy, ageSeconds: 0)
        removeWarpTabConfigIfOurs(path: path)
        XCTAssertFalse(exists(path), "the scheduled delete stopped recognising an older build's file")
    }

    /// A fixed-name file left by an early build of this branch is reclaimed too, when its contents are ours
    func testLegacyFixedNameTabConfigIsRemoved() {
        let path = write(
            "terminal-checkout.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 600
        )
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertFalse(exists(path))
    }
}

// MARK: - uninstall.sh ↔ Swift constant synchronisation
// The uninstall script deletes what is left with **the same verdict** the app uses (for a socket: our prefix plus an actual socket; for a Tab Config: our prefix plus our header). Those strings are duplicated in the script, so changing only one side makes the deletion target drift silently — change the prefix and our files stay on the user's machine forever; change the header and the script deletes nothing. This test turns that divergence red.
//
// **The limit**: it only checks whether the string is in the file. So if someone editing uninstall.sh leaves the string in a comment or in dead code, this guard still passes — it does not look at the shell syntax.

/// Reads a repository-root file **relative to the source location** — the CWD a test runs in depends on how it was invoked, whereas `#filePath` is the absolute path at compile time and so points at that checkout's copy even in a worktree.
/// If it cannot be found it throws and **fails**: passing it off as a skip disables the guard silently.
private func repoFileContents(_ name: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath) // <root>/app/Tests/CoreTests/CoreTests.swift
        .deletingLastPathComponent() // CoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // app
        .deletingLastPathComponent() // the repository root
    return try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
}

/// The Tab Config marker is a **permanent machine protocol** (D38): a language-neutral token that
/// will not change again, plus a human-readable line below it that may.
///
/// Both headers have to be recognised, and for different reasons. The new one is what we write now.
/// The old one is Korean and sits in files already on users' disks — if `warpTabConfigIsOurs` stopped
/// matching it, the app would never reclaim them and `uninstall.sh` would never delete them.
final class WarpTabConfigMarkerTests: XCTestCase {
    func testTheHeaderTokenCarriesNoNaturalLanguage() {
        // The whole point of the change: a marker that can never need translating again.
        XCTAssertTrue(
            warpTabConfigHeader.unicodeScalars.allSatisfy { $0.isASCII },
            "the marker has to stay language-neutral: \(warpTabConfigHeader)"
        )
    }

    func testContentFromAnOlderBuildIsStillOurs() {
        // A file written before the token change, verbatim as it appeared on disk.
        let old = warpTabConfigLegacyHeader + " — 탭이 열리면 지웁니다.\nname = \"Terminal Checkout\"\n"
        XCTAssertTrue(warpTabConfigIsOurs(contents: old), "an older build's file stopped being reclaimable")
    }

    func testContentWeWriteNowIsOurs() {
        XCTAssertTrue(warpTabConfigIsOurs(contents: warpTabConfigTOML(commands: ["z remy"])))
    }

    func testSomebodyElsesFileIsNotOurs() {
        XCTAssertFalse(warpTabConfigIsOurs(contents: "name = \"my workspace\"\n"))
    }

    /// **A near miss is not ours** (P0, round 5 review). The verdict used `hasPrefix` for both
    /// headers, so anything whose first line *starts with* the token — `…/v1` followed by a `0`,
    /// which is the shape the next format version would take, or a user's own line that happens to
    /// open with it — was reclaimed and deleted. We created that exposure ourselves: separating the
    /// explanation onto its own line made an exact match possible and the prefix match stayed.
    ///
    /// The legacy header keeps its prefix match, and that is not an oversight: earlier builds wrote
    /// the explanation on the *same* line, so there is no exact string on disk to match.
    func testAFirstLineThatMerelyStartsWithTheTokenIsNotOurs() {
        XCTAssertFalse(warpTabConfigIsOurs(contents: warpTabConfigHeader + "0\nname = \"theirs\"\n"))
        XCTAssertFalse(warpTabConfigIsOurs(contents: warpTabConfigHeader + "-draft\n"))
        XCTAssertFalse(warpTabConfigIsOurs(contents: warpTabConfigHeader + " and then some\n"))
        // The token on a line of its own stays ours, with or without the trailing newline
        XCTAssertTrue(warpTabConfigIsOurs(contents: warpTabConfigHeader))
        XCTAssertTrue(warpTabConfigIsOurs(contents: warpTabConfigHeader + "\n"))
        XCTAssertTrue(warpTabConfigIsOurs(contents: warpTabConfigLegacyHeader + " — 탭이 열리면 지웁니다.\n"))
    }

    /// The human-readable explanation lives on its **own** line, so translating it later can never
    /// touch the token the reclaim verdict matches on.
    func testTheExplanationIsOnItsOwnLine() {
        let toml = warpTabConfigTOML(commands: ["z remy"])
        let first = toml.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)[0]
        XCTAssertEqual(String(first), warpTabConfigHeader, "the first line has to be the token alone")
    }
}

final class UninstallScriptSyncTests: XCTestCase {
    func testUninstallScriptSweepsWithTheSameConstants() throws {
        let script = try repoFileContents("uninstall.sh")
        // What has to appear verbatim in the script. The `--serve` flag is deliberately absent — it is private to the WarpHelper target and cannot be seen from here, the damage from a divergence is only a missed pkill, and the helper dies on its own from the idle and lifetime caps
        let expected = [
            warpHelperSocketPrefix + "*.sock",
            warpTabConfigPrefix + "*.toml",
            warpTabConfigHeader,
            // The old header stays a reclaim target: files written before the token change are
            // still on users' disks, and dropping it from either side (here or `warpTabConfigIsOurs`)
            // orphans them permanently
            warpTabConfigLegacyHeader,
            warpTabConfigLegacyStem + ".toml",
            warpHelperExecutableName,
            // Round 4: uninstall swept the helper sockets but left the prompt directories, which
            // are the ones holding **content** — PR and issue bodies, and `!` output
            claudePromptDirectoryPrefix + "*",
            // Round 5: a directory carrying the hand-off marker is one a **running** claude
            // session was told to read. Uninstalling must not pull that file out from under it,
            // so those are reported instead of deleted
            claudePromptHandoffName,
            // Round 8: the socket sweep matched `tcw-*.sock` with no name check at all, so a
            // same-user socket like `/tmp/tcw-user.sock` was in range. The pattern below is the
            // one the app writes — prefix plus 8 lower-case hex
            "^tcw-[0-9a-f]{8}\\.sock$",
        ]
        for needle in expected {
            XCTAssertTrue(
                script.contains(needle),
                "uninstall.sh does not handle \(needle.debugDescription) — only the Swift constant changed"
            )
        }
    }
}

/// What `UninstallScriptSyncTests` cannot see: it asks whether a string appears in the script, and
/// a string appears in a predicate whose **boundary** is wrong just as well as in one whose is
/// right — the prefix match that deleted a user's file passed that check for as long as it existed.
/// So this runs the sweep against real files and looks at what is left.
///
/// **Only the Tab Config block is run, never the whole script.** The rest of `uninstall.sh` kills a
/// running TerminalCheckout and any live Warp injection helper, and sweeps `/tmp/tcw-*.sock` and
/// `/tmp/tc-prompt-*` through hardcoded paths that no environment variable redirects — running that
/// from a test would delete the files of whoever is using the app on this machine, mid-delivery.
/// The block is lifted out of the shipped script verbatim, so the bytes under test are the shipped
/// bytes; when it can no longer be found the test fails rather than passing on a script it never
/// read. `set -euo pipefail` is put back because the script runs under it, and the block's
/// if-statement shape was chosen for that reason.
final class UninstallScriptSweepTests: XCTestCase {
    private var home = ""
    private var tabConfigs = ""

    override func setUp() {
        super.setUp()
        home = (NSTemporaryDirectory() as NSString)
            .appendingPathComponent("tc-uninstall-\(UInt32.random(in: .min ... .max))")
        tabConfigs = (home as NSString).appendingPathComponent(".warp/tab_configs")
        try? FileManager.default.createDirectory(
            atPath: tabConfigs, withIntermediateDirectories: true
        )
    }

    override func tearDown() {
        try? FileManager.default.removeItem(atPath: home)
        super.tearDown()
    }

    private func tabConfigSweep(_ script: String) -> String? {
        guard let start = script.range(of: #"for toml in "$HOME"/.warp/tab_configs/"#),
              let end = script.range(of: "\ndone\n", range: start.upperBound..<script.endIndex)
        else { return nil }
        return String(script[start.lowerBound..<end.upperBound])
    }

    @discardableResult
    private func write(_ name: String, _ contents: String) -> String {
        let path = (tabConfigs as NSString).appendingPathComponent(name)
        FileManager.default.createFile(atPath: path, contents: Data(contents.utf8))
        return path
    }

    private func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

    func testTheSweepDeletesOnlyFilesCarryingOurMarker() throws {
        let script = try repoFileContents("uninstall.sh")
        let block = try XCTUnwrap(
            tabConfigSweep(script),
            "the Tab Config sweep is no longer where this test reads it from — uninstall.sh changed shape"
        )

        let ours = write("terminal-checkout-deadbeef.toml", warpTabConfigTOML(commands: ["z remy"]))
        let legacyName = write("terminal-checkout.toml", warpTabConfigTOML(commands: ["z remy"]))
        let legacyHeader = write(
            "terminal-checkout-cafebabe.toml",
            warpTabConfigLegacyHeader + " — 탭이 열리면 지웁니다.\nname = \"Terminal Checkout\"\n"
        )
        // The P0: one character past our token, which is what `…/v2` or a user's own line looks like
        let nearMiss = write("terminal-checkout-0badcafe.toml", warpTabConfigHeader + "0\nname = \"theirs\"\n")
        let theirs = write("terminal-checkout-feedface.toml", "name = \"my workspace\"\n")
        let otherName = write("my-workspace.toml", warpTabConfigTOML(commands: ["z remy"]))
        // A link wearing our name: following it would delete somebody else's file, so the script
        // checks `-L` before it checks the header
        let linkTarget = write("their-config.toml", warpTabConfigTOML(commands: ["z remy"]))
        let link = (tabConfigs as NSString).appendingPathComponent("terminal-checkout-beefbeef.toml")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: linkTarget)

        // The block goes to a **file**, not to `bash -c`. Measured: an argument passed through
        // `Process.arguments` comes out NFD on Darwin, and the legacy header in it is Korean — so
        // `-c` handed grep a pattern that no longer matched the NFC bytes on disk, and the legacy
        // file survived a sweep that in a real shell deletes it. The test would have been
        // reporting its own encoding, not the script's behaviour
        let runner = (home as NSString).appendingPathComponent("sweep.sh")
        try ("set -euo pipefail\n" + block).write(toFile: runner, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [runner]
        process.environment = ["HOME": home, "PATH": "/usr/bin:/bin"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)

        XCTAssertFalse(exists(ours), "a Tab Config we wrote was left behind")
        XCTAssertFalse(exists(legacyName), "the fixed name early builds used was left behind")
        XCTAssertFalse(exists(legacyHeader), "a Tab Config from an older build was left behind")
        XCTAssertTrue(exists(nearMiss), "a file that only starts with our token was deleted")
        XCTAssertTrue(exists(theirs), "a user's file with a colliding name was deleted")
        XCTAssertTrue(exists(otherName), "a file outside our naming was deleted")
        XCTAssertTrue(exists(linkTarget), "a user's file was deleted through a symlink wearing our name")
        XCTAssertTrue(exists(link), "the symlink itself was deleted")
    }
}

// MARK: - extension/defaults.js ↔ Swift: names the app fills in
// The name of an app-provided variable exists twice: `repoEntryVariable` here and `APP_VARIABLES`
// in `extension/defaults.js`. Neither side can catch the other drifting at runtime, and the damage
// is total either way: rename the name on one side alone and every preset dies with a
// "Variable {…} not provided" rejection (`renderCommand` never passes an unresolved placeholder
// through) — visible, but shipped. This test turns that drift into a red before it ships.
//
// **Limit**: it reads the array literal out of the file's text. Computing `APP_VARIABLES` at
// runtime, or spelling it across several statements, would slip past this guard.

final class AppVariableSyncTests: XCTestCase {
    /// Pulls the element names out of `const APP_VARIABLES = ['cd'];`. Returns nil when the
    /// declaration is missing or no longer a plain array literal — the caller fails, rather than
    /// comparing against an empty set and passing for the wrong reason.
    private func appVariablesFromDefaults(_ source: String) -> Set<String>? {
        guard let range = source.range(of: #"APP_VARIABLES\s*=\s*\[([^\]]*)\]"#, options: .regularExpression)
        else { return nil }
        let body = source[range].drop { $0 != "[" }.dropFirst().dropLast()
        let names = body
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \t\n'\"")) }
            .filter { !$0.isEmpty }
        return Set(names)
    }

    func testAppProvidedVariableNamesMatchTheExtension() throws {
        let defaults = try repoFileContents("extension/defaults.js")
        let fromJS = try XCTUnwrap(
            appVariablesFromDefaults(defaults),
            "APP_VARIABLES is gone from extension/defaults.js, or is no longer an array literal"
        )
        XCTAssertEqual(
            fromJS, [repoEntryVariable],
            "the app-provided variable names have drifted: JS has \(fromJS.sorted()), "
                + "Swift has [\(repoEntryVariable)]"
        )
    }

    /// The parser has to be able to fail — otherwise the test above passes on a file it never read
    /// correctly. These are the shapes that must not be mistaken for a match.
    func testParserRejectsWhatItCannotRead() {
        XCTAssertNil(appVariablesFromDefaults("const OTHER = ['cd'];"))
        XCTAssertNil(appVariablesFromDefaults("// APP_VARIABLES was here"))
        XCTAssertEqual(appVariablesFromDefaults("const APP_VARIABLES = ['cd', 'zz'];"), ["cd", "zz"])
        XCTAssertEqual(appVariablesFromDefaults("const APP_VARIABLES = [];"), [])
    }
}

// MARK: - Locale resolution (which of the five bundled catalogs the app renders in)

/// Everything the verdict depends on is passed in — the stored preference, the system's language
/// order, and the tags the bundle actually carries. None of it is read from the host machine here,
/// and that is what makes these assertions mean the same thing on a ko-KR laptop and on an `en` CI
/// runner. Measured (D7): a `Bundle(url:)` lookup resolves through the host language, so an oracle
/// that touched the bundle would be answering a different question on each machine.
final class LocaleResolutionTests: XCTestCase {
    /// What the app ships a catalog for, spelled out instead of read from `supportedLocales` —
    /// changing the constant has to fail here rather than quietly redefine what the rest of these
    /// tests are asserting.
    private let bundled = ["en", "ko", "ja", "zh-Hans", "zh-Hant"]

    /// The three tags in the R0 measurement that no bundle carries: they can only be answered by
    /// dropping the region (`en-GB`) or by reading the script the region implies (`zh-HK`,
    /// `zh-MO`). The first loop is what makes the name true — if one of them were ever bundled,
    /// the equalities below would still pass while proving nothing.
    func testAutoMatchesOnlyThroughRegionFallback() {
        for tag in ["zh-HK", "zh-MO", "en-GB"] {
            XCTAssertFalse(bundled.contains(tag), "\(tag) is bundled — an exact match would answer first")
        }
        XCTAssertEqual(resolveLocale(preference: "auto", systemPreferred: ["zh-HK"], available: bundled), "zh-Hant")
        XCTAssertEqual(resolveLocale(preference: "auto", systemPreferred: ["zh-MO"], available: bundled), "zh-Hant")
        XCTAssertEqual(resolveLocale(preference: "auto", systemPreferred: ["en-GB"], available: bundled), "en")
        // An absent preference is the same path as the stored `auto`, not a third one
        XCTAssertEqual(resolveLocale(preference: nil, systemPreferred: ["zh-HK"], available: bundled), "zh-Hant")
    }

    /// The system list here would answer `ko`. An explicit choice we cannot honour must not fall
    /// through to it: the user asked for a language, and answering with a third one they never
    /// named would be a guess. What is left is the fallback the project chose, `en`.
    func testUnsupportedExplicitLocaleFallsBackToEnglish() {
        let system = ["ko-KR", "ja-JP"]
        XCTAssertEqual(resolveLocale(preference: nil, systemPreferred: system, available: bundled), "ko")
        for tag in ["fr", "pt-BR", "de-DE", "xx", "und"] {
            XCTAssertEqual(resolveLocale(preference: tag, systemPreferred: system, available: bundled), "en", tag)
        }
    }

    /// A stored value that is not a string at all, and a string that names nothing, are both
    /// answered without consulting the system list — the assertion is the gap between `ko` (what
    /// the auto path answers for this system order) and `en`. Folding them into `auto` would make
    /// a corrupt byte indistinguishable from a user who asked to follow the system, and the fold
    /// is silent: nothing on screen would say the stored choice was dropped.
    ///
    /// The type list is what `UserDefaults.object(forKey:)` can hand back after a hand-edited
    /// plist or a future build that wrote another type. `auto` is our own token, not a language
    /// tag, so it is matched exactly — `AUTO` and `auto ` are not it.
    func testCorruptStoredPreferenceIsNotTrusted() {
        let system = ["ko-KR"]
        XCTAssertEqual(resolveLocale(preference: nil, systemPreferred: system, available: bundled), "ko")

        let corrupt: [Any] = [
            42, 3.5, true, ["ko"], ["locale": "ko"], Data(), Date(timeIntervalSince1970: 0),
            "", " ko ", "auto ", "AUTO", "-", "1234", "-ko", "-zh-Hant",
        ]
        for value in corrupt {
            XCTAssertEqual(
                resolveLocale(preference: value, systemPreferred: system, available: bundled), "en",
                "\(type(of: value)) \(value) reached the auto path"
            )
        }
    }

    /// A tag is a tag only when **every** subtag is one (P0, round 5 review).
    ///
    /// Reading the first component alone answered Korean for `ko--KR`: the walk stopped at the
    /// first `-`, found `ko`, and never looked at what followed. The round before had added
    /// `omittingEmptySubsequences: false`, which closed the **leading**-empty shape and nothing
    /// else — so the comment claiming that a value we cannot account for does not get to name a
    /// language was true of one shape rather than of the rule. The system list needs the same
    /// check: an `auto` list that opens with `ko--KR` must skip that entry, not honour it.
    func testEverySubtagIsCheckedNotJustTheFirst() {
        // This system order answers `ko`, so anything that leaks shows up as Korean
        let system = ["ko-KR"]
        let malformed = [
            "ko-", "ko--KR", "zh--Hant", "zh__Hant", "ko-💩", "zh-Hant foo", "ko-KR-",
            "zh-abcdefghi", "ko-KR ", "-ko",
        ]
        for tag in malformed {
            XCTAssertEqual(
                resolveLocale(preference: tag, systemPreferred: system, available: bundled), "en", tag
            )
        }
        XCTAssertEqual(
            resolveLocale(preference: "auto", systemPreferred: ["ko--KR", "ja-JP"], available: bundled),
            "ja"
        )
        // The exact match used to run before the check, so a malformed entry in `available`
        // answered for itself
        XCTAssertEqual(
            resolveLocale(preference: "ko--KR", systemPreferred: [], available: ["ko--KR", "en"]), "en"
        )
        // Still a tag: one underscore is the ICU spelling of the same thing
        XCTAssertEqual(resolveLocale(preference: "zh_Hant", systemPreferred: [], available: bundled), "zh-Hant")
    }

    /// The output is a member of the list it was given, by identity — never the caller's input
    /// echoed back, and never a tag assembled here. That is what lets the caller turn it straight
    /// into `<tag>.lproj`; a resolver that returned `en` when `en` is not in the bundle would name
    /// a directory that does not exist.
    ///
    /// **Membership is all this one says.** Which member is the right one for a given input is what
    /// the measured-table, system-order and explicit-choice tests answer — the name used to promise
    /// that too, and a name that promises more than the assertions deliver is the same defect as a
    /// comment that does (round 5 review).
    ///
    /// The shape check is the other half: a tag ends up in a filesystem path and, if it ever
    /// leaks into a command, in a shell word. All five pass the same character whitelist a
    /// request variable does, and none of them carries `/` or `.`, which that whitelist allows.
    func testEveryResolutionIsAMemberOfTheAvailableTags() {
        XCTAssertEqual(supportedLocales, bundled)
        for tag in supportedLocales {
            XCTAssertEqual(try? sanitizeValue(tag), tag)
            XCTAssertTrue(tag.allSatisfy { $0.isASCII && ($0.isLetter || $0 == "-") }, tag)
        }

        let availabilities = [bundled, ["en"], ["ja", "ko"], ["zh-Hans"], ["zh-Hant", "en"]]
        let preferences: [Any?] = [nil, "auto", "ko", "zh-Hant", "zh-HK", "fr", "", 7, ["x"]]
        let systems = [[], ["ko-KR"], ["zh-HK", "en"], ["pt-BR"], ["fr", "ja"], ["zh"]]
        for available in availabilities {
            for preference in preferences {
                for system in systems {
                    let resolved = resolveLocale(
                        preference: preference, systemPreferred: system, available: available
                    )
                    XCTAssertTrue(
                        available.contains(resolved),
                        "\(resolved) is not one of \(available) (preference \(preference ?? "nil"), system \(system))"
                    )
                }
            }
        }
    }

    /// The R0 measurement (D12), taken against five real `.lproj` bundles: this is what macOS
    /// itself answered for these tags. The rules in `Localization.swift` were derived from this
    /// table, not the other way round, so the table is the oracle and stays spelled out.
    ///
    /// `pt-BR` is the row that is not a fallback at all — nothing we ship speaks it, so what
    /// answered there was the bundle itself (D2 measured that the development region decides that
    /// answer; that the probe's region was `en` is inference from the value). We reach the same
    /// tag by our own last resort: the road differs, the answer is the one that was measured.
    func testTheMeasuredSystemFallbackTableHolds() {
        let measured = [
            ("zh-HK", "zh-Hant"), ("zh-Hant-HK", "zh-Hant"), ("zh-MO", "zh-Hant"),
            ("zh-TW", "zh-Hant"), ("zh", "zh-Hans"), ("zh-SG", "zh-Hans"),
            ("en-GB", "en"), ("pt-BR", "en"),
        ]
        for (tag, expected) in measured {
            XCTAssertEqual(
                resolveLocale(preference: "auto", systemPreferred: [tag], available: bundled),
                expected, tag
            )
        }
    }

    /// The user's order decides, not ours. Walking `available` instead and asking "is any of
    /// these in the system list" reads the same and answers `ko` for a list that starts with
    /// Japanese — the first two lines are the same set in two orders precisely to catch that.
    func testAutoFollowsTheSystemOrderNotOurOwn() {
        XCTAssertEqual(resolveLocale(preference: "auto", systemPreferred: ["ja-JP", "ko-KR"], available: bundled), "ja")
        XCTAssertEqual(resolveLocale(preference: "auto", systemPreferred: ["ko-KR", "ja-JP"], available: bundled), "ko")
        // A language we ship nothing for is skipped, not read as the end of the list
        XCTAssertEqual(resolveLocale(preference: "auto", systemPreferred: ["pt-BR", "fr", "ko-KR"], available: bundled), "ko")
        XCTAssertEqual(resolveLocale(preference: "auto", systemPreferred: [], available: bundled), "en")
    }

    /// An explicit choice is honoured whatever the system says, and it is matched by the same
    /// function the system list goes through: `zh-HK` names Traditional Chinese wherever it was
    /// read from. Two matchers would be two verdicts, and only one of them would get fixed.
    func testAnExplicitChoiceOverridesTheSystemList() {
        for tag in bundled {
            XCTAssertEqual(
                resolveLocale(preference: tag, systemPreferred: ["ko-KR", "ja-JP"], available: bundled),
                tag
            )
        }
        XCTAssertEqual(resolveLocale(preference: "zh-HK", systemPreferred: ["ko-KR"], available: bundled), "zh-Hant")
        XCTAssertEqual(resolveLocale(preference: "ko-KR", systemPreferred: ["ja-JP"], available: bundled), "ko")
        XCTAssertEqual(resolveLocale(preference: "zh_TW", systemPreferred: ["ko-KR"], available: bundled), "zh-Hant")
    }

    /// `epoch` counts revisions of the **resolved** locale, not of the preference (D48). The
    /// preference stays `auto` for the whole of the last block below while the language changes
    /// underneath it — counting preference edits there would leave the extension on the old
    /// language forever, because its rule is to accept a same-install snapshot only when the
    /// epoch is strictly greater (D32).
    ///
    /// Republishing an unchanged locale returns the snapshot untouched: every launch resolves and
    /// publishes, and if that moved the number, the extension would redraw on every launch and no
    /// epoch would ever mean anything.
    func testTheEpochAdvancesOnlyWhenTheResolvedLocaleChanges() {
        let first = localeSnapshotToPublish(resolved: "ko", lastPublished: nil)
        XCTAssertEqual(first, LocaleSnapshot(tag: "ko", epoch: 0))
        XCTAssertEqual(localeSnapshotToPublish(resolved: "ko", lastPublished: first), first)

        let second = localeSnapshotToPublish(resolved: "ja", lastPublished: first)
        XCTAssertEqual(second, LocaleSnapshot(tag: "ja", epoch: 1))

        // Returning to a tag published before is a new revision, not the old number again
        XCTAssertEqual(
            localeSnapshotToPublish(resolved: "ko", lastPublished: second),
            LocaleSnapshot(tag: "ko", epoch: 2)
        )

        let beforeChange = resolveLocale(preference: "auto", systemPreferred: ["ko-KR"], available: bundled)
        let afterChange = resolveLocale(preference: "auto", systemPreferred: ["ja-JP"], available: bundled)
        let published = localeSnapshotToPublish(resolved: beforeChange, lastPublished: nil)
        XCTAssertEqual(
            localeSnapshotToPublish(resolved: afterChange, lastPublished: published),
            LocaleSnapshot(tag: "ja", epoch: 1)
        )
    }
}
