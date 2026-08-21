import XCTest
@testable import Core

// MARK: - 명령 렌더링 (변수 치환 + command injection 방지)

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

    // {base}는 이 PR이 실제로 머지될 브랜치다 — 리포 오버라이드·글로벌 기본값을 거치는
    // {main}과 달라질 수 있으므로 서로 다른 값으로 치환돼야 한다
    func testRenderBaseIsIndependentOfMain() throws {
        let cmd = try renderCommand(
            template: "git merge --ff-only origin/{base} && echo {main}",
            variables: ["base": "release/2", "main": "main"]
        )
        XCTAssertEqual(cmd, "git merge --ff-only origin/release/2 && echo main")
    }

    // 이슈/PR 프리셋의 gh 명령은 {owner}/{repo}/{number}를 그대로 URL 경로에 넣는다
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

    // bash 그룹핑 { …; }는 변수 패턴({word})이 아니므로 그대로 통과해야 한다
    // (기본 checkout 프리셋이 워크트리 fallback에 { } 그룹핑을 사용)
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

// MARK: - 요청 해석 (command_template 포맷)

final class RequestTests: XCTestCase {
    func testTemplateRequest() throws {
        let req: [String: Any] = [
            "command_template": "z {repo} && git checkout {branch}",
            "variables": ["repo": "remy", "branch": "fix/x"],
        ]
        XCTAssertEqual(try resolveRequest(req).command, "z remy && git checkout fix/x")
    }

    // 어느 터미널을 쓸지는 앱 설정이 정한다 — 요청에 섞여 오는 terminal 필드는 해석하지 않는다
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

    // claude_inputs: claude 실행 후 세션에 타이핑할 입력들. command와 같은 변수 문법을 쓴다.
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

    // 입력 속 변수도 command와 같은 검증을 거친다 — 미지의 변수는 에러
    func testClaudeInputsUnknownVariableThrows() {
        XCTAssertThrowsError(try resolveRequest([
            "command_template": "z {repo}", "variables": ["repo": "remy"],
            "claude_inputs": ["checkout {nope} please"],
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

// MARK: - 요청 핸들러 (성공/실패 JSON 응답 형태)

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

// MARK: - Claude 입력 전달 (포그라운드 게이트 판정 — 셸 오입력 방지의 핵심)

final class ClaudeInjectorTests: XCTestCase {
    // ps -t <tty> -o pid=,stat=,comm= 출력 기준. 포그라운드 프로세스 그룹은 stat에 `+`가 붙는다.
    // 이름만이 아니라 PID 를 돌려주는 이유는 입력 사이 재대기에서 같은 세션인지 확인하기
    // 위해서다 (testForegroundPIDDistinguishesReplacedSession 참고).
    func testForegroundClaudeDetected() {
        XCTAssertEqual(claudeForegroundPID(psOutput: "100 Ss   -zsh\n200 S+   claude"), 200)
    }

    func testForegroundNodeWithFullPathDetected() {
        XCTAssertEqual(
            claudeForegroundPID(psOutput: "100 Ss   -zsh\n201 S+   /opt/homebrew/bin/node"), 201)
    }

    func testShellAtPromptIsNotClaude() {
        // 프롬프트 대기 중에는 셸 자신이 포그라운드(+)다 — 이때 타이핑하면 셸이 실행해버린다
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
        // "Claude Helper (Renderer)" 같은 무관한 프로세스가 claude로 오인되면 안 된다
        XCTAssertNil(claudeForegroundPID(
            psOutput: "400 S+   /Applications/Claude.app/Contents/MacOS/Claude Helper (Renderer)"))
    }

    func testEmptyOutputIsNotClaude() {
        XCTAssertNil(claudeForegroundPID(psOutput: ""))
    }

    /// `ps -o pid=,stat=,comm=` 의 pid 는 우측 정렬이라 선행 공백이 붙고, comm 앞에도
    /// 칸 맞춤 공백이 여러 개 온다 (실측: `" 3719 S+   node"`). 이 공백을 떼지 않으면
    /// 이름 비교가 전부 어긋나 claude 를 영영 못 찾는다.
    func testRealPSColumnSpacingIsTolerated() {
        XCTAssertEqual(claudeForegroundPID(psOutput: " 3719 S+   node"), 3719)
        XCTAssertEqual(
            claudeForegroundPID(psOutput: "34782 Ss   -zsh\n 3719 S+   claude"), 3719)
        XCTAssertEqual(
            claudeForegroundPID(psOutput: "  100 Ss   -zsh\n95539 R+   /opt/homebrew/bin/node"),
            95539)
    }

    func testMalformedPIDColumnIsSkipped() {
        // pid 자리가 숫자가 아니면(헤더 등) 그 줄은 건너뛴다
        XCTAssertNil(claudeForegroundPID(psOutput: "PID STAT COMM\nxxx S+   claude"))
    }

    /// 세션 교체 방어의 회귀 방지: 원래 claude 가 죽고 같은 tty 에 새 claude 가 떠도
    /// 이름·raw mode 는 똑같이 만족하므로, PID 로만 두 세션을 구별할 수 있다.
    /// 구별하지 못하면 남은 claude_inputs 가 무관한 새 세션에 제출되고,
    /// 입력이 `!…` 셸 모드면 의도하지 않은 명령까지 실행된다.
    func testForegroundPIDDistinguishesReplacedSession() {
        let first = claudeForegroundPID(psOutput: "100 Ss   -zsh\n95539 R+   claude")
        let replaced = claudeForegroundPID(psOutput: "100 Ss   -zsh\n95610 R+   claude")
        XCTAssertEqual(first, 95539)
        XCTAssertEqual(replaced, 95610)
        XCTAssertNotEqual(first, replaced)
    }

    // MARK: tty raw mode 판정 — 포그라운드가 claude여도 아직 입력을 받을 수 없는 구간을 가른다.
    // 셸이 claude를 exec한 직후 tty는 canonical(icanon+echo)이라, 이때 타이핑하면
    // claude가 아니라 커널이 에코한다. 그 에코를 화면 반영으로 오판하면 CR이 유실된다 (실측).

    /// 실제 `stty -f /dev/ttysNNN -a` 출력 (claude 실행 중 = raw mode)
    private static let sttyRawOutput = """
    speed 9600 baud; 89 rows; 338 columns;
    lflags: -icanon -isig -iexten -echo echoe -echok echoke -echonl echoctl
    \t-echoprt -altwerase -noflsh -tostop -flusho -pendin -nokerninfo
    \t-extproc
    iflags: -istrip -icrnl -inlcr -igncr -ixon -ixoff ixany imaxbel -iutf8
    """

    /// 실제 `stty` 출력 (claude exec 직후 = canonical, 커널이 에코하는 구간)
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
        // 여기서 타이핑하면 커널 에코가 화면에 떠 반영 확인을 거짓 통과시킨다
        XCTAssertEqual(ttyIsRawMode(sttyOutput: Self.sttyCanonicalOutput), false)
    }

    func testRawFlagIsNotMatchedAsSubstring() {
        // "-icanon"은 "icanon"을 부분 문자열로 포함한다 — 토큰 단위로 갈라야 raw를
        // canonical로 오판하지 않는다
        XCTAssertEqual(ttyIsRawMode(sttyOutput: "lflags: -icanon -echo"), true)
        XCTAssertEqual(ttyIsRawMode(sttyOutput: "lflags: icanon echo"), false)
    }

    func testUndecidableSttyOutputIsNil() {
        // stty 실패·형식 변경으로 판정할 수 없으면 nil — 호출자가 ps 게이트만으로 진행한다
        XCTAssertNil(ttyIsRawMode(sttyOutput: ""))
        XCTAssertNil(ttyIsRawMode(sttyOutput: "stty: /dev/ttys999: No such file or directory"))
    }

    // MARK: 입력 접수 가능 판정 = 포그라운드 claude + raw mode

    func testAcceptsInputRequiresBothSignals() {
        let claudeFg = "100 Ss   -zsh\n200 S+   claude"
        let shellFg = "100 Ss+  -zsh"
        XCTAssertEqual(acceptingClaudePID(psOutput: claudeFg, sttyOutput: Self.sttyRawOutput), 200)
        // claude는 떴지만 아직 canonical — 지금 보내면 CR이 유실된다
        XCTAssertNil(acceptingClaudePID(psOutput: claudeFg, sttyOutput: Self.sttyCanonicalOutput))
        // 셸 프롬프트는 zle 때문에 raw지만 포그라운드가 claude가 아니다
        XCTAssertNil(acceptingClaudePID(psOutput: shellFg, sttyOutput: Self.sttyRawOutput))
    }

    func testAcceptsInputFallsBackToForegroundWhenSttyUnavailable() {
        // stty를 못 읽는 환경에서 전달이 아예 끊기지 않도록 ps 게이트만으로 통과시킨다
        XCTAssertEqual(acceptingClaudePID(psOutput: "200 S+   claude", sttyOutput: ""), 200)
        XCTAssertNil(acceptingClaudePID(psOutput: "100 Ss+  -zsh", sttyOutput: ""))
    }

    // wezterm cli list --format json에서 pane의 tty를 찾는다
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

    // 화면 반영 확인용 프로브: 긴 입력은 화면 폭에서 줄바꿈돼 통짜 매칭이 깨지므로
    // 앞부분만 잘라 쓴다
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

    // claude는 shell mode 입력을 "! gh ..."처럼 `!` 뒤에 공백을 끼워 그린다.
    // 이걸 놓치면 반영 확인이 영영 실패해 입력이 제출되지 않고 입력창에 매달린다 (실측)
    func testScreenMatchesShellModeRendering() {
        XCTAssertTrue(screenReflectsNewInput(
            before: "╭────────╮\n╰────────╯\n  ! for shell mode",
            after: "╭────────╮\n! gh issue view 1404\n╰────────╯\n  ! for shell mode",
            input: "!gh issue view 1404"
        ))
    }

    // 긴 입력은 터미널 폭에서 줄바꿈된다 — 프로브 길이 안에서 끊겨도 매칭돼야 한다
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

    // 공백뿐인 입력은 프로브가 비어 아무 화면에나 매칭된다 — 제출을 승인해선 안 된다
    func testEmptyInputNeverMatches() {
        XCTAssertFalse(screenReflectsNewInput(before: "", after: "아무 화면", input: "   "))
    }
}

// MARK: - 제어키 바이트
// 전달 경로도, 아래 테스트들도 `claudeSubmitKey`·`claudeClearInputKey`를 **참조**한다 — 상수 자체가
// 틀리면(CR이 LF로 바뀌는 등) 그 테스트들은 함께 초록이 되어 오라클이 되지 못한다. 그래서 이
// 한 자리에서만 리터럴 바이트로 고정한다: claude는 CR(0x0D)만 제출로 인식하고(실측), 입력창
// 클리어는 Ctrl+U(0x15)다.

final class ClaudeControlKeyTests: XCTestCase {
    func testControlKeysAreTheExpectedBytes() {
        XCTAssertEqual(Array(claudeSubmitKey.utf8), [0x0D])
        XCTAssertEqual(Array(claudeClearInputKey.utf8), [0x15])
    }
}

// MARK: - 터미널 식별자
// rawValue를 리터럴로 고정하는 oracle — 케이스 이름을 바꾸면 저장값이 함께 바뀌어 기존 사용자의
// 터미널 선택이 조용히 무시된다. 저장값 "iterm"은 확장 이름과 무관하게 iTerm2를 가리키는
// 식별자이므로 바꾸지 않는다. 상수 자기참조로는 이 계약을 지킬 수 없어 리터럴로만 검증한다.

final class TerminalIdentifierTests: XCTestCase {
    func testRawValuesAreTheStoredIdentifiers() {
        XCTAssertEqual(Terminal.iterm.rawValue, "iterm")
        XCTAssertEqual(Terminal.wezterm.rawValue, "wezterm")
        XCTAssertEqual(Terminal.warp.rawValue, "warp")
        // oracle 완결성: 케이스가 늘면 위 목록에도 리터럴 한 줄이 있어야 한다
        XCTAssertEqual(Terminal.allCases.count, 3)
    }

    func testStoredValueParsingFallsBackToITerm() {
        XCTAssertEqual(Terminal(storedValue: "iterm"), .iterm)
        XCTAssertEqual(Terminal(storedValue: "wezterm"), .wezterm)
        XCTAssertEqual(Terminal(storedValue: "warp"), .warp)
        // 알 수 없는 저장값(다른 버전이 남긴 식별자, 손으로 고친 plist)은 iTerm2 폴백 —
        // 폴백이 소비 지점마다 갈리지 않게 파싱 한 곳에 모은 계약
        XCTAssertEqual(Terminal(storedValue: "kitty"), .iterm)
        XCTAssertEqual(Terminal(storedValue: ""), .iterm)
    }
}

// MARK: - 입력 전달 순서와 실패 복구
// 전달 루프는 osascript·wezterm cli를 부르지만, 순서·재시도·중단 판정은 프로세스 없이
// 검증할 수 있어야 한다 — ClaudeSessionIO로 그 호출만 갈아 끼운다.

/// claude 세션 흉내. 입력창(box)에 타이핑된 것을 화면에 그대로 비추고, CR을 받으면
/// 제출로 처리해 입력창을 비운다.
private final class FakeClaudeSession {
    private(set) var keystrokes: [String] = []
    private(set) var submitted: [String] = []
    var sessionAlive = true
    /// n번째 sendKeys 호출을 실패시킨다 (1-based) — 터미널 CLI가 한 번 실패하는 상황
    var failSendAt: Set<Int> = []
    /// n번째 screenText 호출을 실패시킨다 (1-based)
    var failScreenAt: Set<Int> = []
    /// n번째 sendKeys가 보낸 텍스트를 claude가 버린다 (1-based) — TUI가 아직 입력창을
    /// 그리지 못하는 순간. 전송은 성공하고 화면에만 뜨지 않는다
    var dropTypingAt: Set<Int> = []
    /// 입력창에 이미 남아 있는 텍스트 (클리어 실패 상황을 만들 때 쓴다)
    var presetBox = "" { didSet { box = presetBox } }
    /// 화면에 이미 떠 있는 텍스트 (다른 pane을 읽고 있는 상황을 만들 때 쓴다)
    var screenPrefix = ""
    /// 제출한 입력이 화면(대화 기록)에 남게 한다
    var keepSubmittedOnScreen = false
    /// 화면 읽기가 pane 단위로 정확하지 않은 터미널(Warp)
    var screenNeedsPaneProof = false
    /// 읽히는 화면이 우리 pane이 아닌 상황 — 우리 타이핑은 화면에 비치지 않는다
    var screenIsForeign = false
    /// 그 남의 pane이 뒤늦게 얻는 텍스트 (Codex 재현: 개수가 증가한다)
    var foreignScreenGains: [String] = []
    private(set) var sendCallCount = 0
    /// 바이트를 내보내기 직전 게이트가 몇 번 확인됐는지
    private(set) var gateChecks = 0
    private var screenCalls = 0
    private var box = ""
    private var history = ""
    private var foreignScreen = "다른 pane 화면"

    var io: ClaudeSessionIO {
        ClaudeSessionIO(
            sendKeys: { [unowned self] keys in
                sendCallCount += 1
                if failSendAt.contains(sendCallCount) { return false }
                keystrokes.append(keys)
                switch keys {
                case claudeSubmitKey:
                    submitted.append(box)
                    if keepSubmittedOnScreen { history += box + " " }
                    box = ""
                case claudeClearInputKey: box = ""
                default:
                    if !dropTypingAt.contains(sendCallCount) { box += keys }
                    if foreignScreenGains.contains(keys) { foreignScreen += " " + keys }
                }
                return true
            },
            screenText: { [unowned self] in
                screenCalls += 1
                if failScreenAt.contains(screenCalls) { return nil }
                if screenIsForeign { return foreignScreen }
                return screenPrefix + " " + history + "❯ " + box
            },
            confirmSession: { [unowned self] _ in sessionAlive },
            sessionIsUnchanged: { [unowned self] in
                gateChecks += 1
                return sessionAlive
            },
            screenNeedsPaneProof: screenNeedsPaneProof,
            wait: { _ in }
        )
    }
}

final class ClaudeInputDeliveryTests: XCTestCase {
    private let inputs = ["!gh issue view 1415", "!gh issue view 1415 --comments", "/gh-drive-pr-review"]

    func testAllInputsSubmittedInOrder() {
        let session = FakeClaudeSession()
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// 제출은 화면 반영을 확인한 뒤에만 한다 — 타이핑 없이 CR이 먼저 나가면 빈 줄이 제출된다
    func testSubmitsOnlyAfterScreenShowsTypedText() {
        let session = FakeClaudeSession()
        _ = submitClaudeInputs([inputs[0]], io: session.io)
        XCTAssertEqual(session.keystrokes, [inputs[0], claudeSubmitKey])
    }

    /// 회귀 방지(실측): 입력 #1 제출 직후 wezterm cli 호출 한 번이 실패해 남은 입력 2개가
    /// 통째로 버려졌다. 터미널 CLI 호출 실패는 "세션이 끝났다"가 아니라 그 호출만 실패한
    /// 것이므로, 재타이핑으로 복구하고 남은 입력을 계속 보내야 한다.
    func testTransientSendFailureDoesNotDropRemainingInputs() {
        let session = FakeClaudeSession()
        session.failSendAt = [3] // #1 타이핑·CR 다음 = #2의 첫 타이핑
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// 화면 조회 실패도 마찬가지다 — 반영을 확인하지 못했을 뿐이라 재타이핑으로 복구한다
    func testTransientScreenReadFailureDoesNotDropRemainingInputs() {
        let session = FakeClaudeSession()
        session.failScreenAt = [2]
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// 재시도는 남은 입력을 무한정 붙들지 않는다 — 계속 실패하면 그 입력에서 멈춘다
    func testPersistentFailureStopsAtThatInput() {
        let session = FakeClaudeSession()
        session.failSendAt = Set(3...100)
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]])
    }

    /// 세션이 바뀌었으면(원래 claude가 죽고 같은 tty에 새 claude가 떴으면) 남은 입력을
    /// 보내지 않는다 — `!…` 입력이면 무관한 세션에서 셸 명령이 실행된다
    func testReplacedSessionStopsDelivery() {
        let session = FakeClaudeSession()
        _ = submitClaudeInputs([inputs[0]], io: session.io)
        session.sessionAlive = false
        let after = session.keystrokes.count
        XCTAssertEqual(submitClaudeInputs([inputs[1]], io: session.io), 0)
        XCTAssertEqual(session.keystrokes.count, after)
    }

    /// 재시도 자체가 세션 확인을 건너뛰면 안 된다 — 첫 타이핑과 재시도 사이에 세션이
    /// 바뀔 수 있고, 그 사이 두 번째 claude에 타이핑하면 같은 오입력이 된다
    func testRetryReconfirmsSessionBeforeRetyping() {
        let session = FakeClaudeSession()
        session.failSendAt = [1] // 첫 타이핑 실패 → 재시도 진입
        var confirms = 0
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            // 입력 사이 게이트는 통과했지만 재시도 직전 확인에서 세션이 바뀐 상황
            confirmSession: { _ in confirms += 1; return confirms == 1 },
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
        // 재시도 타이핑이 나가면 안 된다. 첫 타이핑은 전송 자체가 실패했지만 바이트는 이미
        // 들어갔을 수 있어, 포기하면서 지우는 Ctrl+U 하나만 뒤따른다
        XCTAssertFalse(session.keystrokes.contains(inputs[0]), "재시도 타이핑: \(session.keystrokes)")
        XCTAssertEqual(session.keystrokes, [claudeClearInputKey])
    }

    /// 입력창 클리어(Ctrl+U)가 실패했으면 타이핑하지 않는다 — 남아 있을지 모르는 텍스트
    /// 뒤에 이어 치면 화면 확인은 통과한 채로 앞이 붙은 입력이 제출된다
    func testFailedClearDoesNotTypeOverLeftovers() {
        let session = FakeClaudeSession()
        session.presetBox = "잔여텍스트"
        session.failSendAt = [1, 2] // #1 타이핑 실패 → #2 클리어도 실패
        _ = submitClaudeInputs([inputs[0]], io: session.io)
        XCTAssertEqual(session.submitted, [inputs[0]])
    }

    /// CR 재전송도 세션 동일성 게이트 안에 있어야 한다 — 첫 CR이 실패한 뒤 원래 claude가
    /// 끝났다면, 같은 tty의 셸이나 새 claude에 CR이 들어가 사용자가 치던 것을 제출·실행시킨다
    func testCarriageReturnResendStopsWhenSessionChanged() {
        let session = FakeClaudeSession()
        session.failSendAt = [2] // 타이핑은 성공, 첫 CR 실패
        var confirms = 0
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            // 입력 사이 게이트와 첫 CR 게이트는 통과하고, 재전송 직전에 세션이 바뀐 상황
            confirmSession: { _ in confirms += 1; return confirms <= 2 },
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        // 타이핑 1 + CR 1 + 포기 후 정리 1 — CR 재전송을 더 시도하면 안 된다
        XCTAssertEqual(session.sendCallCount, 3)
        XCTAssertEqual(session.keystrokes, [inputs[0], claudeClearInputKey])
    }

    /// 제출(CR) 전송이 실패하면 재타이핑이 아니라 CR만 다시 보낸다 — 실패로 보고됐어도
    /// 실제로는 전달됐을 수 있고, 그때 재타이핑하면 같은 입력이 두 번 제출된다
    func testFailedSubmitResendsCarriageReturnWithoutRetyping() {
        let session = FakeClaudeSession()
        session.failSendAt = [2] // #1 타이핑 성공, #2 = CR 실패
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]])
        XCTAssertEqual(session.keystrokes.filter { $0 == inputs[0] }.count, 1)
    }

    /// 회귀 방지(Warp 실측): claude가 뜬 직후 게이트 ①②를 통과하고도 TUI가 첫 입력을
    /// 아직 그리지 못하는 순간이 있다. 화면은 읽히는데 입력만 안 보이므로 재타이핑으로 복구한다
    func testUnreflectedInputRetypesUntilScreenShowsIt() {
        let session = FakeClaudeSession()
        session.dropTypingAt = [1] // 첫 타이핑을 claude가 버린다
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]]) // 빈 줄이 아니라 실제 입력이 제출됐다
        XCTAssertEqual(session.keystrokes.filter { $0 == inputs[0] }.count, 2)
    }

    /// 화면을 끝내 읽지 못하면 아무것도 제출하지 않는다. tty 입력 큐가 비었다는
    /// 신호(`FIONREAD`=0)로 대신하던 때가 있었는데, 그것은 claude가 `read()`했다는 뜻일 뿐
    /// 입력창에 그렸다는 뜻이 아니라서 claude가 버린 입력에 빈 CR을 보내고 "전달됨"으로 기록했다
    func testUnreadableScreenNeverSubmits() {
        let session = FakeClaudeSession()
        session.failScreenAt = Set(1...100)
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
    }

    /// 화면은 읽히는데 우리 입력이 영영 뜨지 않으면(다른 pane을 읽고 있다) 제출하지 않는다 —
    /// 여기서 빈 줄을 제출하면 사용자가 그 pane에 치고 있던 것이 실행된다
    func testScreenThatNeverShowsInputNeverSubmits() {
        let session = FakeClaudeSession()
        session.dropTypingAt = Set(1...100)
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
    }

    /// 회귀 방지(검증자 재현 P2): 주입은 **포커스와 무관하게 우리 tty로** 들어가므로
    /// "화면에서 확인하지 못했다"가 "입력창에 없다"를 뜻하지 않는다. 본문이 이미 들어간 채로
    /// 반영 확인이 끝내 실패하면, 그 조각을 지우지 않고 끝낼 경우 사용자가 나중에 누른 Enter가
    /// 그것을 제출한다(`!…` 셸 모드면 명령까지 실행된다).
    /// 권한이 살아 있어도 마찬가지라 정리 조건은 "권한 상실"이 아니라 **"다 끝내지 못했고 우리
    /// 조각이 남아 있을 수 있음"**이어야 한다.
    func testUnconfirmedTypingIsClearedWhenDeliveryGivesUp() {
        let session = FakeClaudeSession()
        session.dropTypingAt = Set(1...100) // 바이트는 들어갔는데 화면에는 영영 안 뜬다
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
        XCTAssertEqual(
            session.keystrokes.last, claudeClearInputKey,
            "포기하고 끝내면서 입력창에 남은 우리 조각을 지우지 않았다: \(session.keystrokes)"
        )
    }

    /// 회귀 방지(P0-2): 접근성으로 읽는 화면이 우리 pane이라는 보장은 없다. 다른 pane에 우연히
    /// 같은 텍스트가 떠 있으면 단순 부분 문자열 일치는 타이핑 전부터 통과하고, 그대로 CR이
    /// 나가면 우리 입력은 제출되지 않은 채 그 순간 사용자가 치던 것이 제출된다.
    /// 타이핑 전 화면을 먼저 찍어 "전보다 한 번 더 보인다"를 요구하면 이 갈래가 죽는다
    func testTextAlreadyOnScreenBeforeTypingIsNotReflection() {
        let session = FakeClaudeSession()
        session.screenPrefix = inputs[0] // 다른 pane에 같은 텍스트가 이미 떠 있다
        session.dropTypingAt = Set(1...100) // 우리 입력은 실제로 뜨지 않는다
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
    }

    /// 회귀 방지(P0-1): 타이핑 전에는 없던 프로브가 타이핑 후 **다른 pane에** 나타나면 개수도
    /// 증가한다 — 개수 비교는 과거 텍스트 오탐만 없앨 뿐 화면의 출처를 보증하지 않는다.
    /// 우리 tty에만 들어가는 난수가 그 화면에 뜨는 것을 먼저 확인해야 화면 확인이 성립한다.
    /// 두 갈래를 한 테스트에 둔 이유는 이 플래그가 실제로 판정을 가르는지까지 고정하기 위해서다
    func testPaneProofIsWhatBlocksAForeignScreen() {
        func run(paneProof: Bool) -> (submitted: Int, lines: [String]) {
            let session = FakeClaudeSession()
            session.screenIsForeign = true
            session.foreignScreenGains = [inputs[0]]
            session.screenNeedsPaneProof = paneProof
            let count = submitClaudeInputs([inputs[0]], io: session.io)
            return (count, session.submitted)
        }
        // pane 증명이 없으면 남의 화면이 그대로 제출을 승인한다 (Codex가 재현한 공격)
        XCTAssertEqual(run(paneProof: false).submitted, 1)
        // 증명을 요구하면 난수가 그 화면에 뜨지 않으므로 아무것도 제출되지 않는다
        XCTAssertEqual(run(paneProof: true).submitted, 0)
        XCTAssertTrue(run(paneProof: true).lines.isEmpty)
    }

    /// pane 증명을 켜도 정상 경로는 그대로 끝까지 간다 — 강화가 전달을 막으면 안 된다
    func testPaneProofDoesNotBlockTheNormalPath() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        XCTAssertEqual(submitClaudeInputs(inputs, io: session.io), 3)
        XCTAssertEqual(session.submitted, inputs)
    }

    /// 증명에 쓴 난수가 입력과 함께 제출되면 claude가 엉뚱한 것을 받는다 —
    /// 표식은 반드시 지우고 나서 친다
    func testPaneProofTokenNeverReachesSubmission() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.submitted, [inputs[0]])
    }

    /// 회귀 방지(P0-1): 세션이 바뀐 뒤에는 CR뿐 아니라 **표식·Ctrl+U·본문 타이핑도** 나가면
    /// 안 된다. 그것이 새 셸이나 새로 뜬 claude의 입력창을 오염시키고, Ctrl+U는 그쪽에서
    /// 사용자가 치던 초안을 지운다. "실행은 안 되니 괜찮다"가 아니다
    func testNoBytesLeaveAfterTheSessionChanged() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            confirmSession: { _ in true }, // 입력 사이 게이트는 통과한 상태
            sessionIsUnchanged: { false }, // 그러나 바이트를 내보내는 순간에는 이미 바뀌었다
            screenNeedsPaneProof: true,
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.keystrokes.isEmpty, "새어 나간 바이트: \(session.keystrokes)")
    }

    /// 회귀 방지(P0-2): 화면을 더 확인할 수 없게 되면(권한 회수) **새로 치는 것은** 멈춰야
    /// 하지만, 이미 친 것을 되돌리는 정리는 나가야 한다. 정리까지 같은 조건으로 막으면
    /// 자동 입력이 입력창에 남아 사용자가 나중에 Enter를 눌렀을 때 실행된다
    func testLostScreenAccessStopsTypingButNotCleanup() {
        let session = FakeClaudeSession()
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            confirmSession: { _ in true },
            sessionIsUnchanged: { true },
            canConfirmScreen: { false }, // 전달 도중 권한이 사라졌다
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.keystrokes.isEmpty, "확인할 수 없는데 친 것: \(session.keystrokes)")
        XCTAssertTrue(clearAbandonedInput(io: io, weSentSomething: true), "정리가 막혔다")
        XCTAssertEqual(session.keystrokes, [claudeClearInputKey])
    }

    /// 회귀 방지(P1-2): 권한은 시도 **시작**에만이 아니라 매 전송 앞에서 확인해야 한다.
    /// pane 증명이나 1초 대기 중에 회수되면 그 뒤 표식·본문·CR이 계속 나간다
    func testPermissionLostMidAttemptStopsFurtherSends() {
        let session = FakeClaudeSession()
        var sends = 0
        let io = ClaudeSessionIO(
            sendKeys: { sends += 1; return session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            confirmSession: { _ in true },
            sessionIsUnchanged: { true },
            canConfirmScreen: { sends < 1 }, // 첫 전송 직후 권한이 사라진다
            screenNeedsPaneProof: true,
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        // 새로 치는 것은 표식 하나에서 멈춘다. 그 뒤에 나가는 것은 **이미 친 표식을 지우는**
        // 정리뿐이다 — 정리까지 막으면 표식이 입력창에 남아 사용자가 그것을 제출하게 된다
        XCTAssertEqual(session.keystrokes.count, 2, "권한이 사라진 뒤에도 새로 친 것: \(session.keystrokes)")
        XCTAssertEqual(session.keystrokes.last, claudeClearInputKey)
    }

    /// 회귀 방지(P1-3): 우리가 한 바이트도 보내지 않았으면 정리도 하지 않는다 —
    /// 그 Ctrl+U는 사용자가 치고 있던 초안만 지운다
    func testCleanupDoesNothingWhenWeNeverSentAnything() {
        let session = FakeClaudeSession()
        XCTAssertFalse(clearAbandonedInput(io: session.io, weSentSomething: false))
        XCTAssertTrue(session.keystrokes.isEmpty)
        XCTAssertTrue(clearAbandonedInput(io: session.io, weSentSomething: true))
        XCTAssertEqual(session.keystrokes, [claudeClearInputKey])
    }

    /// 회귀 방지: "우리 조각이 입력창에 남아 있는가"는 **시도**로 세우고 **CR·클리어로 내린다**.
    /// 결과로 세우면 헬퍼가 일부만 넣고 실패했을 때 남은 조각을 못 지우고(미탐),
    /// 한 번 성공한 뒤 계속 참으로 두면 다음 입력을 시작도 못 했을 때 사용자 초안을 지운다(오탐).
    func testInputBoxOwnershipRisesOnAttemptAndFallsOnSubmit() {
        // `deliverClaudeInputs`가 쓰는 그 타입을 검증한다 — 규칙 사본을 여기 두면
        // 사본만 맞고 실물이 어긋나도 초록이 된다
        var ownership = InputBoxOwnership()
        XCTAssertFalse(ownership.mayHoldOurs, "아무것도 보내기 전에는 지울 우리 조각이 없다")
        ownership.recordSend(keys: "!gh pr view", sent: false) // 전송은 실패했지만 바이트는 이미 들어갔을 수 있다
        XCTAssertTrue(ownership.mayHoldOurs, "실패한 전송 뒤 남은 조각을 못 지우게 된다")
        ownership.recordSend(keys: claudeSubmitKey, sent: true)
        XCTAssertFalse(ownership.mayHoldOurs, "제출로 입력창이 비었는데 정리를 보내면 사용자 초안을 지운다")
        ownership.recordSend(keys: claudeSubmitKey, sent: false) // 제출 실패 — 본문은 입력창에 그대로 남아 있다
        XCTAssertTrue(ownership.mayHoldOurs)
        // 클리어 갈래도 같다: 성공한 Ctrl+U는 입력창을 비우므로 내려가고, 실패면 남는다
        ownership.recordSend(keys: claudeClearInputKey, sent: true)
        XCTAssertFalse(ownership.mayHoldOurs)
        ownership.recordSend(keys: claudeClearInputKey, sent: false)
        XCTAssertTrue(ownership.mayHoldOurs)
    }

    /// 전달이 중간에 끝난 뒤의 정리용 Ctrl+U도 같은 게이트를 지나야 한다 —
    /// 이 자리가 게이트를 우회하면 정리가 남의 세션 입력창을 지운다
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

    /// 바이트를 내보내는 자리는 전부 하나의 게이트를 지난다 — 자리마다 따로 확인하면
    /// 다음에 또 빠진 자리가 생긴다. 표식·Ctrl+U·본문·CR 네 번 모두 확인돼야 한다
    func testEverySendPassesTheSameGate() {
        let session = FakeClaudeSession()
        session.screenNeedsPaneProof = true
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: session.io), 1)
        XCTAssertEqual(session.gateChecks, session.sendCallCount)
        XCTAssertEqual(session.sendCallCount, 4) // 표식 · Ctrl+U · 본문 · CR
    }

    /// 회귀 방지(P0-2): 첫 CR도 세션 확인을 통과해야 한다. 화면 반영을 확인한 직후라도 그
    /// 사이 claude가 죽고 셸이나 새 claude가 같은 tty를 차지할 수 있고, 그 CR은 사용자가
    /// 치고 있던 것을 제출·실행시킨다
    func testFirstCarriageReturnAlsoRequiresSessionConfirmation() {
        let session = FakeClaudeSession()
        var confirms = 0
        let io = ClaudeSessionIO(
            sendKeys: { session.io.sendKeys($0) },
            screenText: { session.io.screenText() },
            // 입력 사이 게이트만 통과하고, 그 뒤 세션이 바뀐 상황
            confirmSession: { _ in confirms += 1; return confirms == 1 },
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertTrue(session.submitted.isEmpty)
        // 타이핑만 나가고 CR은 막혔다. 그 타이핑은 입력창에 남으므로 포기하면서 지운다
        XCTAssertEqual(session.keystrokes, [inputs[0], claudeClearInputKey])
    }

    /// 같은 입력을 두 번 예약했을 때, 앞의 것이 화면(대화 기록)에 남아 있어도 뒤의 것이
    /// 제출된다 — "있었나/없었나"가 아니라 "몇 번 보이나"로 세기 때문이다
    func testRepeatedInputIsStillSubmittedWhileTheEarlierOneStaysOnScreen() {
        let session = FakeClaudeSession()
        session.keepSubmittedOnScreen = true
        XCTAssertEqual(submitClaudeInputs([inputs[0], inputs[0]], io: session.io), 2)
        XCTAssertEqual(session.submitted, [inputs[0], inputs[0]])
    }
}

// MARK: - 화면 반영 판정 (타이핑 전/후 비교)
// 접근성으로 읽는 Warp 화면은 포커스된 pane의 것이라 우리 pane이라는 보장이 없다.
// "이미 떠 있던 텍스트"와 "우리가 방금 친 것"을 가르는 수단은 타이핑 전 화면과의 비교뿐이다.

final class ScreenReflectionTests: XCTestCase {
    private let input = "!gh issue view 1415"

    func testNewlyAppearedInputIsReflection() {
        XCTAssertTrue(screenReflectsNewInput(before: "❯ ", after: "❯ " + input, input: input))
    }

    /// 스냅샷을 못 찍었으면(화면 조회 실패) 확인 실패다 — 못 찍은 것을 "없었다"로 다루면
    /// 이미 떠 있던 텍스트가 그대로 반영으로 통과한다
    func testMissingBeforeSnapshotIsNotReflection() {
        XCTAssertFalse(screenReflectsNewInput(before: nil, after: "❯ " + input, input: input))
    }

    func testTextThatWasAlreadyThereIsNotReflection() {
        let screen = "다른 pane: " + input
        XCTAssertFalse(screenReflectsNewInput(before: screen, after: screen, input: input))
    }

    /// 대화 기록에 같은 텍스트가 남아 있어도 하나 더 늘면 반영이다
    func testOneMoreOccurrenceIsReflection() {
        XCTAssertTrue(screenReflectsNewInput(
            before: input + " ❯ ", after: input + " ❯ " + input, input: input
        ))
    }

    /// 화면이 스크롤되어 옛 항목이 밀려나면 개수가 늘지 않는다 — 그때는 재타이핑으로 간다
    func testUnchangedOccurrenceCountIsNotReflection() {
        XCTAssertFalse(screenReflectsNewInput(
            before: input + " 옛 줄", after: "새 줄 " + input, input: input
        ))
    }
}

// MARK: - 도구 확인 (z/gh/claude가 사용자 셸에서 실제로 불릴 수 있는지)

final class ToolCheckTests: XCTestCase {
    func testScriptAsksEachToolAndMarksCompletion() {
        let script = toolCheckScript(["z", "gh"])
        XCTAssertTrue(script.contains("command -v z >/dev/null 2>&1 && echo TC_OK:z"))
        XCTAssertTrue(script.contains("command -v gh >/dev/null 2>&1 && echo TC_OK:gh"))
        // 완료 마커가 없으면 "도구 없음"과 "셸 자체가 실패"를 구분할 수 없다
        XCTAssertTrue(script.hasSuffix("echo TC_DONE"))
    }

    func testParsesFoundAndMissingTools() throws {
        let output = "TC_OK:z\nTC_OK:claude\nTC_DONE\n"
        let result = try XCTUnwrap(parseToolCheck(output: output, tools: ["z", "gh", "claude"]))
        XCTAssertEqual(result, ["z": true, "gh": false, "claude": true])
    }

    // 셸 통합(iTerm2 등)이 첫 줄 앞에 escape sequence를 붙여도 마커를 찾아내야 한다
    func testIgnoresShellIntegrationPrefix() throws {
        let output = "\u{1B}]1337;ShellIntegrationVersion=14;shell=zsh\u{07}TC_OK:z\nTC_DONE"
        let result = try XCTUnwrap(parseToolCheck(output: output, tools: ["z"]))
        XCTAssertEqual(result["z"], true)
    }

    // "TC_OK:zoxide"가 "z"의 매칭으로 새면 z 없이도 있다고 오판한다
    func testToolNamePrefixDoesNotLeak() throws {
        let result = try XCTUnwrap(parseToolCheck(output: "TC_OK:zoxide\nTC_DONE", tools: ["z", "zoxide"]))
        XCTAssertEqual(result, ["z": false, "zoxide": true])
    }

    // 완료 마커가 없으면 확인 실패(nil) — 전부 "없음"으로 단정하면 안 된다
    func testMissingDoneMarkerMeansUnknown() {
        XCTAssertNil(parseToolCheck(output: "TC_OK:z", tools: ["z"]))
        XCTAssertNil(parseToolCheck(output: "", tools: ["z"]))
    }

    func testLoginShellIsAbsolutePath() {
        XCTAssertTrue(loginShellPath().hasPrefix("/"))
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

// MARK: - AppleScript 이스케이프

final class AppleScriptTests: XCTestCase {
    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(escapeForAppleScript(#"say "hi" \ now"#), #"say \"hi\" \\ now"#)
    }

    func testEscapeNewline() {
        XCTAssertEqual(escapeForAppleScript("a\nb"), #"a\nb"#)
    }

    func testITermScriptEmbedsEscapedCommand() {
        let script = iTermScript(for: #"echo "hi""#)
        XCTAssertTrue(script.contains(#"write text "echo \"hi\"""#))
        // 이름("iTerm2")이 아닌 번들 ID로 타게팅해야 한다 — 앱 파일명이 iTerm.app이거나
        // 복사본(iTerm Rosetta.app 등)으로 LaunchServices 이름 해석이 꼬여도 동작하도록 (-1728 방지)
        XCTAssertTrue(script.contains(#"tell application id "com.googlecode.iterm2""#))
        XCTAssertFalse(script.contains(#"tell application "iTerm2""#))
    }

    // claude 입력 전달을 위해 spawn 스크립트가 세션 핸들(id|tty)을 돌려줘야 한다
    func testITermScriptReturnsSessionHandle() {
        let script = iTermScript(for: "echo hi")
        XCTAssertTrue(script.contains(#"(id of s) & "|" & (tty of s)"#))
    }

    // 타이핑 모드: 개행 없이 텍스트만 넣는다 — 제출은 화면 반영 확인 후 별도로 보낸다
    func testITermWriteToSessionScriptTypingSuppressesNewline() {
        let script = iTermWriteToSessionScript(sessionID: "ABC-123", text: #"say "hi""#, submit: false)
        XCTAssertTrue(script.contains(#"tell application id "com.googlecode.iterm2""#))
        XCTAssertTrue(script.contains(#"if (id of s) is "ABC-123" then"#))
        XCTAssertTrue(script.contains(#"write text "say \"hi\"" newline NO"#))
        // 세션이 사라졌으면(탭 닫힘) "gone"을 돌려줘 호출자가 전달을 중단하게 한다
        XCTAssertTrue(script.contains(#"return "gone""#))
    }

    // 제출 모드: 개행만 보낸다 (빈 write text = Enter)
    func testITermWriteToSessionScriptSubmitSendsNewlineOnly() {
        let script = iTermWriteToSessionScript(sessionID: "ABC-123", text: "", submit: true)
        XCTAssertTrue(script.contains(#"write text """#))
        XCTAssertFalse(script.contains("newline NO"))
    }

    func testITermWriteToSessionScriptEscapesSessionID() {
        let script = iTermWriteToSessionScript(sessionID: #"x"y"#, text: "t", submit: false)
        XCTAssertTrue(script.contains(#"if (id of s) is "x\"y" then"#))
    }

    // 화면 반영 확인용 스크립트: 세션의 현재 화면 텍스트를 돌려준다
    func testITermSessionContentsScript() {
        let script = iTermSessionContentsScript(sessionID: "ABC-123")
        XCTAssertTrue(script.contains(#"if (id of s) is "ABC-123" then"#))
        XCTAssertTrue(script.contains("return contents of s"))
        XCTAssertTrue(script.contains(#"return "gone""#))
    }
}

// MARK: - Extension ID (unpacked 확장: SHA-256(절대경로) 앞 32 hex → a-p)

final class ExtensionIDTests: XCTestCase {
    func testKnownVectors() {
        // 벡터는 기존 install.sh의 파이썬 구현으로 계산한 값
        XCTAssertEqual(extensionID(forPath: "/Users/test/extension"), "ommholjeknmifgidochbhocolnejiema")
        XCTAssertEqual(extensionID(forPath: "/tmp/e"), "cinkehcaekebplmoijecmdfmflcnboch")
    }

    func testIDIsStable() {
        XCTAssertEqual(extensionID(forPath: "/tmp/e"), extensionID(forPath: "/tmp/e"))
    }

    // manifest "key"(base64 DER 공개키)가 있으면 Chrome은 경로 대신 그 키에서 ID를 만든다 —
    // 해시 대상만 다르고 매핑 규칙은 경로 방식과 같다
    func testKeyBasedIDKnownVector() {
        // base64 "aGVsbG8=" → "hello", 기대값은 파이썬 hashlib로 독립 계산
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

    // Web Store 전환 대비: store ID + 개발용 ID 병기 지원
    func testManifestJSONMultipleOrigins() throws {
        let data = nativeHostManifestJSON(relayPath: "/x", extensionIDs: ["aaa", "bbb"])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(
            obj["allowed_origins"] as? [String],
            ["chrome-extension://aaa/", "chrome-extension://bbb/"]
        )
    }
}

// MARK: - Native Messaging 프레이밍 (4바이트 LE 길이 + JSON)

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

// MARK: - 경로 상수

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

// MARK: - WezTerm 탭을 만들 창 고르기

final class WezTermWindowTests: XCTestCase {
    // wezterm cli list-clients --format json 실측 형태
    private let clientsJSON = Data("""
    [{"username":"u","hostname":"h","pid":96467,
      "connection_elapsed":{"secs":546209,"nanos":0},
      "idle_time":{"secs":9,"nanos":557978000},
      "workspace":"default","focused_pane_id":146}]
    """.utf8)

    // 같은 순간의 wezterm cli list --format json (창 3개, 창마다 탭 1개 이상)
    private let listJSON = Data("""
    [{"window_id":4,"tab_id":82,"pane_id":147,"tty_name":"/dev/ttys003"},
     {"window_id":3,"tab_id":81,"pane_id":146,"tty_name":"/dev/ttys000"},
     {"window_id":0,"tab_id":4,"pane_id":5,"tty_name":"/dev/ttys001"}]
    """.utf8)

    func testFocusedWindowIDFromClientsAndList() {
        XCTAssertEqual(wezTermFocusedWindowID(clientsJSON: clientsJSON, listJSON: listJSON), "3")
    }

    // client가 여럿이면 가장 최근에 활동한(idle_time이 짧은) 쪽이 사용자가 보고 있는 창이다
    func testMostRecentlyActiveClientWins() {
        let clients = Data("""
        [{"pid":1,"idle_time":{"secs":300,"nanos":0},"focused_pane_id":5},
         {"pid":2,"idle_time":{"secs":2,"nanos":500000000},"focused_pane_id":147}]
        """.utf8)
        XCTAssertEqual(wezTermFocusedWindowID(clientsJSON: clients, listJSON: listJSON), "4")
    }

    // focused_pane_id가 없는 client(창 없이 붙은 mux 연결)는 후보에서 빼야 한다
    func testClientWithoutFocusedPaneIgnored() {
        let clients = Data("""
        [{"pid":1,"idle_time":{"secs":0,"nanos":0}},
         {"pid":2,"idle_time":{"secs":90,"nanos":0},"focused_pane_id":5}]
        """.utf8)
        XCTAssertEqual(wezTermFocusedWindowID(clientsJSON: clients, listJSON: listJSON), "0")
    }

    // 포커스된 pane이 목록에 없으면(직전에 닫힘) 창을 지정하지 않는다 —
    // 엉뚱한 창을 골라 탭을 흘리는 대신 wezterm 기본 선택에 맡긴다
    func testUnknownFocusedPaneYieldsNil() {
        let clients = Data(#"[{"idle_time":{"secs":0,"nanos":0},"focused_pane_id":999}]"#.utf8)
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: clients, listJSON: listJSON))
    }

    func testBrokenOrEmptyJSONYieldsNil() {
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: Data("nope".utf8), listJSON: listJSON))
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: clientsJSON, listJSON: Data("nope".utf8)))
        XCTAssertNil(wezTermFocusedWindowID(clientsJSON: Data("[]".utf8), listJSON: listJSON))
    }

    // 창을 특정했으면 그 창을 먼저 노리고, 실패하면 창 지정 없이 한 번 더 시도한다 —
    // 찾은 창이 spawn 직전에 닫히면 wezterm은 "window_id N not found"로 실패하고(실측),
    // 거기서 포기하면 `wezterm start` fallback이 새 창을 띄워 고치려던 증상이 되살아난다
    func testSpawnAttemptsRetryWithoutWindowID() {
        XCTAssertEqual(
            wezTermSpawnAttempts(windowID: "3"),
            [["cli", "spawn", "--window-id", "3"], ["cli", "spawn"]]
        )
    }

    // 창을 못 찾았으면 시도는 한 번뿐이다 — 같은 명령을 두 번 돌릴 이유가 없다
    func testSpawnAttemptsSingleWhenWindowUnknown() {
        XCTAssertEqual(wezTermSpawnAttempts(windowID: nil), [["cli", "spawn"]])
    }
}

// MARK: - Warp: Tab Config TOML
// Warp에 새 탭을 열고 명령을 실행시키는 수단은 Tab Config 파일뿐이다 —
// AppleScript 미지원, warpctrl은 Stable 기본 비활성, pane에 텍스트를 보내는 CLI도 없다(실측).

final class WarpTabConfigTests: XCTestCase {
    func testTOMLRunsCommandInSingleTerminalPane() {
        let toml = warpTabConfigTOML(commands: ["z remy && claude"])
        XCTAssertTrue(toml.contains(#"name = "Terminal Checkout""#), toml)
        XCTAssertTrue(toml.contains(#"type = "terminal""#), toml)
        XCTAssertTrue(toml.contains(#"commands = ["z remy && claude"]"#), toml)
    }

    /// claude 입력을 예약한 버튼만 헬퍼를 먼저 띄운다. 순서가 뒤집히면 헬퍼는 claude가
    /// 끝난 뒤에야 뜬다
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

    // `{{name}}`은 Warp의 파라미터 템플릿 문법이라 [params.*]를 선언하면 열 때 모달이 뜬다 —
    // 우리는 파라미터를 쓰지 않으므로 선언도 하지 않는다
    func testTOMLDeclaresNoParameters() {
        XCTAssertFalse(warpTabConfigTOML(commands: ["z remy"]).contains("[params"))
    }

    // 실측: 선언되지 않은 `{{zzz}}`는 치환도 모달도 없이 셸에 그대로 전달된다
    // (`printf '%s' 'X{{zzz}}Y'` → 파일 내용 `X{{zzz}}Y`). 그래서 따로 방어하지 않는다
    func testTOMLLeavesWarpTemplateBracesLiteral() {
        let toml = warpTabConfigTOML(commands: ["awk '{{print}}'"])
        XCTAssertTrue(toml.contains(##"commands = ["awk '{{print}}'"]"##), toml)
    }

    func testEscapeQuotesAndBackslashes() {
        XCTAssertEqual(escapeForTOMLBasicString(#"say "hi" \ now"#), #"say \"hi\" \\ now"#)
    }

    // TOML basic string은 제어문자를 리터럴로 담을 수 없다 — 이스케이프하지 않으면
    // Warp가 파일 파싱에 실패해 탭이 아예 열리지 않는다
    func testEscapeControlCharacters() {
        XCTAssertEqual(escapeForTOMLBasicString("a\nb\tc\rd"), #"a\nb\tc\rd"#)
        XCTAssertEqual(escapeForTOMLBasicString("a\u{01}b"), #"a\u0001b"#)
    }

    func testEscapedCommandStaysOnOneLineInTOML() {
        let toml = warpTabConfigTOML(commands: ["echo \"a\"\nrm -rf /"])
        XCTAssertTrue(toml.contains(#"commands = ["echo \"a\"\nrm -rf /"]"#), toml)
    }

    /// 요청마다 다른 이름을 쓴다 — 고정 이름은 같은 이름의 사용자 Tab Config를 말없이
    /// 덮어쓰고, `open`이 돌아온 뒤에도 Warp가 파일을 읽기 전이라 연속 요청이 서로의 명령을
    /// 갈아 끼운다(pane 등장까지 실측 0.5∼0.7초)
    func testTabConfigNameCarriesTokenSoRunsDoNotCollide() {
        let stem = warpTabConfigStem(token: "deadbeef")
        XCTAssertEqual(stem, "terminal-checkout-deadbeef")
        XCTAssertTrue(warpTabConfigPath(stem: stem).hasSuffix("/.warp/tab_configs/\(stem).toml"))
        XCTAssertEqual(warpTabConfigURL(stem: stem), "warp://tab_config/\(stem)")
    }

    /// 회수는 우리가 만든 파일에만 해야 한다 — 사용자 Tab Config를 지우면 안 된다
    func testOnlyOurGeneratedFileIsRecognisedAsOurs() {
        XCTAssertTrue(warpTabConfigIsOurs(contents: warpTabConfigTOML(commands: ["z remy"])))
        XCTAssertFalse(warpTabConfigIsOurs(contents: "name = \"내 작업 공간\"\n"))
        XCTAssertFalse(warpTabConfigIsOurs(contents: ""))
    }

    /// 이름으로도 한 번 거른다 — 우리 접두사 + 16진 토큰 형태만 회수 대상이다
    func testOnlyOurNamingIsSweptFromTheDirectory() {
        XCTAssertTrue(warpTabConfigFileIsOurs(name: "terminal-checkout-deadbeef.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-내파일.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "my-workspace.toml"))
        XCTAssertFalse(warpTabConfigFileIsOurs(name: "terminal-checkout-deadbeef.txt"))
    }

    /// 브랜치 초기 빌드가 남긴 고정 이름 파일도 회수 대상이다 — 다만 내용이 우리 것일 때만
    func testLegacyFixedNameIsSweptOnlyWhenContentsAreOurs() {
        XCTAssertTrue(warpTabConfigFileIsOurs(name: "terminal-checkout.toml"))
    }
}

// MARK: - Warp: 헬퍼 기동 명령과 소켓 경로
// 헬퍼는 pane 안에서 떠야 한다 — TIOCSTI는 호출 프로세스의 제어 터미널에만 허용되므로
// (BSD `isctty`) 세션 밖의 앱은 pane tty에 바이트를 넣을 수 없다.

final class WarpHelperLaunchTests: XCTestCase {
    /// 앱 번들 경로에는 공백이 있다(`Terminal Checkout.app`) — 인용하지 않으면 셸이
    /// 두 단어로 갈라 헬퍼가 뜨지 않는다
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

    /// 소켓 경로는 sun_path 104바이트 제한을 넘으면 bind가 실패한다 —
    /// 후보 중 들어가는 첫 디렉토리를 고른다
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

    /// 실행마다 다른 토큰을 써야 이전 실행이 남긴 죽은 소켓에 붙지 않는다
    func testSocketNameCarriesToken() {
        XCTAssertEqual(
            warpHelperSocketPath(token: "deadbeef", directories: ["/tmp"]),
            "/tmp/tcw-deadbeef.sock"
        )
    }

    /// 회수는 우리 소켓 이름에만 한다 — 다른 프로그램의 소켓을 지우면 안 된다
    func testOnlyOurSocketNamesAreReclaimed() {
        XCTAssertTrue(warpHelperSocketFileIsOurs(name: "tcw-deadbeef.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-내소켓.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "other.sock"))
        XCTAssertFalse(warpHelperSocketFileIsOurs(name: "tcw-deadbeef.txt"))
    }

    func testTokenIsHexAndVariesBetweenRuns() {
        let tokens = (0..<50).map { _ in warpHelperToken() }
        XCTAssertTrue(tokens.allSatisfy { $0.count == 8 && $0.allSatisfy(\.isHexDigit) }, "\(tokens[0])")
        XCTAssertGreaterThan(Set(tokens).count, 40)
    }
}

// MARK: - Warp: 헬퍼 소켓 프로토콜
// 요청·응답은 줄 단위 ASCII다. 주입할 바이트는 base64로 싣는다 — CR·Ctrl+U 같은
// 제어문자를 줄 기반 프로토콜에 날것으로 실을 수 없기 때문이다.

final class WarpHelperProtocolTests: XCTestCase {
    private func roundTrip(_ request: WarpHelperRequest) -> WarpHelperRequest? {
        parseWarpHelperRequest(encodeWarpHelperRequest(request))
    }

    func testRequestsRoundTrip() {
        XCTAssertEqual(roundTrip(.tty), .tty)
        XCTAssertEqual(roundTrip(.bye), .bye)
    }

    /// 제출(CR)과 입력창 클리어(Ctrl+U)가 그대로 실려야 한다 — 한 바이트라도 바뀌면
    /// claude가 입력을 제출하지 않는다
    func testInjectCarriesControlBytesUnchanged() {
        for text in ["!gh issue view 1", claudeSubmitKey, claudeClearInputKey, "한글 입력", ""] {
            let request = WarpHelperRequest.inject(expectedPID: 4242, bytes: Data(text.utf8))
            XCTAssertEqual(roundTrip(request), request, text.debugDescription)
        }
    }

    /// 주입 요청은 "누가 읽을 것을 기대하는지"를 함께 나른다 — 헬퍼가 그 순간의 포그라운드와
    /// 맞춰 보고 어긋나면 넣지 않는다
    func testInjectCarriesTheExpectedReader() {
        XCTAssertEqual(
            parseWarpHelperRequest(encodeWarpHelperRequest(.inject(expectedPID: 91, bytes: Data("x".utf8)))),
            .inject(expectedPID: 91, bytes: Data("x".utf8))
        )
        XCTAssertNil(parseWarpHelperRequest("inject notapid eA=="))
        XCTAssertNil(parseWarpHelperRequest("inject 91"))
        // 0 이하는 거부한다 — `getpgid(0)`은 호출자 그룹이라, 헬퍼가 포그라운드인 비정상
        // 상황에서 "기대 독자가 맞다"로 통과해 버린다
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

    /// 접두사가 없는 줄을 성공으로 읽으면 실패가 성공으로 보고된다
    func testResponseWithoutPrefixIsRejected() {
        XCTAssertNil(parseWarpHelperResponse("/dev/ttys026"))
        XCTAssertNil(parseWarpHelperResponse(""))
    }
}

// MARK: - Warp: 주입 직전 포그라운드 판정
// TIOCSTI는 호출자의 세션인지만 보고 **누가 그 바이트를 읽을지는 정하지 않는다**. claude가
// 죽어 셸이 포그라운드가 되면 큐에 남은 CR을 셸이 읽어 사용자 초안을 실행한다.
// 실측: 앱이 고르는 claude pid가 프로세스 그룹 리더가 아닌 경우가 있다(13개 pane 중 3개) —
// 그래서 pid가 아니라 `getpgid(pid)`와 비교해야 한다.

final class WarpForegroundTests: XCTestCase {
    func testForegroundMatchesExpectedGroup() {
        XCTAssertTrue(warpForegroundIsExpected(foregroundPGID: 4242, expectedPGID: 4242))
    }

    func testDifferentGroupIsBlocked() {
        XCTAssertFalse(warpForegroundIsExpected(foregroundPGID: 4242, expectedPGID: 99))
    }

    /// `tcgetpgrp`·`getpgid`가 실패하면 -1이다 — 알 수 없을 때는 넣지 않는다
    func testUnknownGroupIsBlocked() {
        XCTAssertFalse(warpForegroundIsExpected(foregroundPGID: -1, expectedPGID: -1))
        XCTAssertFalse(warpForegroundIsExpected(foregroundPGID: 4242, expectedPGID: -1))
        XCTAssertFalse(warpForegroundIsExpected(foregroundPGID: 0, expectedPGID: 0))
    }
}

// MARK: - Warp: 헬퍼 정지 판정
// 상한과 tty 동일성을 한 함수로 모은다 — 대기 루프와 요청 처리 경로가 서로 다른 기준을 쓰면
// 연결을 물고 계속 요청하는 쪽이 상한을 통째로 우회한다.

final class WarpHelperBudgetTests: XCTestCase {
    /// 헬퍼가 한 요청에 쓰는 시간이 앱의 응답 대기보다 길면, 앱이 먼저 포기하고 재시도하는
    /// 동안 이전 요청의 주입이 계속 돌아 재시도분·사용자 입력과 섞인다.
    /// 두 값을 따로 두면 다시 갈리므로 한 곳에서 유도한다
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

    /// tty 번호는 재사용된다 — 우리 pane이 닫힌 뒤 같은 번호를 새 세션이 차지하면
    /// 남은 주입이 남의 tty로 들어간다. 다른 무엇보다 먼저 본다
    func testTTYSessionChangeStopsEverything() {
        XCTAssertEqual(reason(tty: false), .ttySessionChanged)
        XCTAssertEqual(reason(tty: false, idle: 0, alive: 0), .ttySessionChanged)
    }

    func testIdleAndLifetimeLimits() {
        XCTAssertEqual(reason(idle: 181), .idle)
        XCTAssertEqual(reason(alive: 901), .lifetime)
    }
}

// MARK: - Warp: 주입 분할
// tty 입력 큐에는 상한(TTYHOG)이 있고 넘치면 커널이 조용히 버린다. 512바이트를 넘는
// claude 입력이 통째로 실패하지 않도록, 큐 여유만큼 나눠 넣고 소비를 기다렸다 이어 넣는다.

final class WarpInjectChunkTests: XCTestCase {
    /// 회귀 방지(P0-1): 큐에 **한 바이트라도** 남아 있으면 넣지 않는다. 여유가 있다고 이어
    /// 넣으면 앞 조각의 tail이 큐에 남은 채로 다음이 쌓이고, claude가 앞 24자만 읽어 화면에
    /// 그리면 화면 확인은 통과한다 — 그 뒤 claude가 끝나면 남은 tail을 **셸이 읽어 실행한다**
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

// MARK: - Warp: 주입한 바이트가 읽히는지 지켜보기
// 넣은 뒤 큐가 비는 것을 확인해야 전달로 인정한다. 여기서 보는 `FIONREAD`는 "아직 안 읽혔다"는
// **부정** 신호일 뿐이고, 남은 바이트가 **누구 것인지는 말해 주지 않는다** — 총량 하나뿐이라
// 우리 것과 사용자가 방금 친 키를 가를 수 없다. 그래서 판정은 표본 하나로 끝나고, 이력을
// 인자로 받지 않는다: 받는 순간 "총량 변화로 출처를 추론"하는 갈래가 되살아난다.

final class WarpInjectWatchTests: XCTestCase {
    /// 회귀 방지(검증자 재현 ①): 옛 판정은 직전 표본과 비교해 "큐가 늘었으면 사용자 키가 섞였다"로
    /// 봤는데, **첫 표본은 비교 대상이 없어** 어떤 값이어도 섞였다고 세우지 못했다. claude가 우리
    /// 바이트를 모두 읽은 뒤 사용자가 한 글자를 치고 그 순간 포그라운드가 바뀌면, 그 한 글자를
    /// 우리 것으로 보고 큐를 통째로 버렸다(`tcflush`) — 사용자 키를 조용히 지우는 오판이다.
    func testFirstSampleNeverJustifiesDiscardingTheQueue() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 1, readerIsOurs: false, budgetExpired: false),
            .readerGone(pending: 1)
        )
    }

    /// 회귀 방지(검증자 재현 ②): 첫 표본을 넘겨도 마찬가지다. claude가 5바이트를 읽는 사이
    /// 사용자가 4바이트를 치면 큐는 10 → 9로 **줄어든다** — 단조 감소는 "남은 것이 우리 바이트"의
    /// 증거가 못 된다. 어느 표본에서도 결론은 같다: 버리지 않고 실패만 알린다.
    func testMonotonicDecreaseIsNotProofOfOwnership() {
        for pending in [10, 9] {
            XCTAssertEqual(
                warpInjectWatchDecision(pending: pending, readerIsOurs: false, budgetExpired: false),
                .readerGone(pending: pending)
            )
        }
    }

    /// 성공은 **큐가 빈 것을 우리 독자가 만든 경우뿐**이다
    func testDeliveredOnlyWhenOurReaderEmptiedTheQueue() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 0, readerIsOurs: true, budgetExpired: false), .delivered
        )
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 0, readerIsOurs: true, budgetExpired: true), .delivered
        )
    }

    /// 큐는 비었지만 그 사이 claude가 끝나 셸이 가져갔으면 실패다 — 성공으로 답하면 앱이 그 위에
    /// CR을 얹고, 사용자의 다음 Enter가 그 줄을 실행한다
    func testEmptyQueueDrainedByAnotherReaderIsFailure() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 0, readerIsOurs: false, budgetExpired: false),
            .drainedByOther
        )
    }

    /// 우리 독자가 그대로면 예산이 남는 동안 기다린다
    func testWaitsWhileOurReaderStillHasBytes() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 7, readerIsOurs: true, budgetExpired: false), .keepWaiting
        )
    }

    /// 예산 안에 안 읽혔으면 실패다(fail-closed) — 성공으로 답하면 큐에 남은 tail 위로 CR이 얹힌다
    func testBudgetExpiryFailsClosed() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 7, readerIsOurs: true, budgetExpired: true),
            .notReadInTime(pending: 7)
        )
    }

    /// 독자가 사라진 갈래는 예산과 무관하게 같은 결론이다 — 남은 바이트를 버리지 않는다
    func testReaderGoneOutranksBudget() {
        XCTAssertEqual(
            warpInjectWatchDecision(pending: 3, readerIsOurs: false, budgetExpired: true),
            .readerGone(pending: 3)
        )
    }
}


// MARK: - Warp: 줄 단위 수신 버퍼
// 소켓 read()는 줄 경계를 지켜 주지 않는다 — 한 번에 두 줄이 오기도, 한 줄이 쪼개져 오기도 한다.

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

    /// 줄바꿈 없이 계속 보내는 상대에게 메모리를 무한정 내주지 않는다
    func testOverlongTailIsRejected() {
        var buffer = LineBuffer(limit: 16)
        buffer.append(Data(String(repeating: "x", count: 17).utf8))
        XCTAssertTrue(buffer.isOverflowed)
        XCTAssertNil(buffer.nextLine())
    }

    /// 회귀 방지(P0-4): 상한을 넘긴 줄이 **마지막 줄바꿈과 함께** 들어오면 꼬리 검사만으로는
    /// 그대로 통과한다 — 완성된 줄에도 같은 상한을 건다
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

// MARK: - Warp: 프로세스 트리
// pane 셸은 Warp `terminal-server`의 직속 자식이고, GUI 프로세스는 그 부모다(실측).
// GUI pid는 접근성으로 화면을 읽을 때 대상 프로세스를 특정하는 데 쓴다.

final class WarpProcessTests: XCTestCase {
    private let exePath = "/Applications/Warp.app/Contents/MacOS/stable"

    /// `ps -axo pid=,ppid=,command=` 실측 형태
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

    /// 인자 없는 GUI 프로세스 자체를 terminal-server로 오인하면 GUI의 부모(launchd)를
    /// Warp로 지목하게 된다
    func testGUIProcessItselfIsNotTerminalServer() {
        XCTAssertFalse(warpGUIPIDs(psOutput: psOutput, executablePath: exePath).contains(1))
    }

    /// 다른 경로에 설치된 Warp를 보고 있으면 아무것도 잡히지 않는다
    func testDifferentExecutablePathMatchesNothing() {
        XCTAssertEqual(
            warpGUIPIDs(
                psOutput: psOutput,
                executablePath: "/Users/me/Applications/Warp.app/Contents/MacOS/stable"
            ),
            []
        )
    }

    /// Warp를 두 번 띄우면 terminal-server도 둘이다 — 둘 다 후보로 남긴다
    func testTwoWarpInstancesYieldTwoGUIPIDs() {
        let ps = psOutput
            + "\n30000 29999 /Applications/Warp.app/Contents/MacOS/stable terminal-server --parent-pid=29999"
        XCTAssertEqual(warpGUIPIDs(psOutput: ps, executablePath: exePath), [17699, 29999])
    }
}

// MARK: - Warp: pane 증명이 필요한 핸들
// 화면 조회가 그 세션의 것이라고 단정할 수 있는지는 터미널마다 다르다. 이 판정이 어긋나면
// iTerm2·WezTerm이 불필요한 증명 비용을 물거나, Warp가 증명 없이 제출한다.

final class PaneProofRoutingTests: XCTestCase {
    func testOnlyWarpNeedsPaneProof() {
        XCTAssertTrue(TerminalSessionHandle.warp(helperSocket: "/tmp/x.sock").screenNeedsPaneProof)
        XCTAssertFalse(TerminalSessionHandle.iterm(sessionID: "s", tty: "/dev/ttys001").screenNeedsPaneProof)
        XCTAssertFalse(
            TerminalSessionHandle.wezterm(paneID: "1", cliPath: "/x", socketPath: nil).screenNeedsPaneProof
        )
        XCTAssertFalse(TerminalSessionHandle.none.screenNeedsPaneProof)
    }

    /// 표식은 우리 실행에서만 나올 수 있어야 하고, claude 입력창에서 특별한 뜻을 가지면 안 된다
    func testPaneProofTokenIsPlainAndUnique() {
        let tokens = (0..<50).map { _ in paneProofToken() }
        // 영숫자만 — `/`·`!`·`@`는 claude 입력창에서 모드·자동완성을 건드린다
        XCTAssertTrue(tokens.allSatisfy { token in token.allSatisfy { $0.isLetter || $0.isNumber } })
        // 우연히 다른 pane에 같은 것이 뜰 수 없을 만큼 길고, 실행마다 달라야 한다
        XCTAssertTrue(tokens.allSatisfy { $0.count == 12 })
        XCTAssertGreaterThan(Set(tokens).count, 45)
    }
}

// MARK: - Warp: 회수 (비정상 종료가 남긴 것)
// 정상 경로는 스스로 치운다(헬퍼는 `bye`·pane 종료·시그널에서, `runInWarp`은 탭이 열린 뒤).
// SIGKILL·앱 크래시만 그 경로를 건너뛰므로 다음 실행이 훑는데, **살아 있는 것을 건드리지
// 않는 것**이 조건이다 — 잘못 지우면 전달 중인 세션의 통로가 사라진다.

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

    /// 주인이 죽은 소켓 = 파일은 남았는데 아무도 듣지 않는 상태 (SIGKILL로 끝난 헬퍼)
    func testDeadHelperSocketIsRemoved() throws {
        let path = (directory as NSString).appendingPathComponent("tcw-deadbeef.sock")
        close(try listeningSocket(at: path))
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-300)], ofItemAtPath: path
        )
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertFalse(exists(path))
    }

    /// 살아 있는 헬퍼의 소켓을 지우면 그 세션의 전달이 통째로 끊긴다
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

    /// `bind`와 `listen` 사이에는 연결이 거절된다 — 갓 만들어진 파일을 지우면 그 창에 걸린
    /// 헬퍼의 소켓을 없애게 된다
    func testFreshHelperSocketIsKept() {
        let path = write("tcw-facefeed.sock", ageSeconds: 1)
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(path))
    }

    /// 회귀 방지(P0-3): 이름만 보고 지우면 같은 이름의 **일반 파일**이 사라진다 (Codex 재현)
    func testRegularFileWithOurSocketNameIsNotRemoved() {
        let path = write("tcw-deadbeef.sock", "사용자 파일", ageSeconds: 3000)
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(path))
    }

    /// 심볼릭 링크를 따라가 지우면 링크가 가리키는 남의 파일이 사라진다
    func testSymlinkWithOurSocketNameIsNotRemoved() throws {
        let target = write("남의파일.txt", "소중한 것", ageSeconds: 3000)
        let link = (directory as NSString).appendingPathComponent("tcw-cafed00d.sock")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        reclaimDeadWarpHelperSockets(in: [directory])
        XCTAssertTrue(exists(target))
        XCTAssertTrue(FileManager.default.fileExists(atPath: link))
    }

    /// 20초 뒤 예약 삭제도 경로만 보고 지우면 안 된다 — 그 사이 사용자가 같은 경로에
    /// 자기 파일을 놓았을 수 있다
    func testScheduledTabConfigRemovalRechecksTheHeader() {
        let ours = write("terminal-checkout-deadbeef.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 0)
        removeWarpTabConfigIfOurs(path: ours)
        XCTAssertFalse(exists(ours))

        let theirs = write("terminal-checkout-cafebabe.toml", "name = \"내 것\"\n", ageSeconds: 0)
        removeWarpTabConfigIfOurs(path: theirs)
        XCTAssertTrue(exists(theirs))
    }

    /// 회귀 방지(P0-3): 우리 이름의 심볼릭 링크가 우리 헤더를 가진 파일을 가리키면
    /// 경로 기반 판정은 **링크 자체를 지운다**. 소켓 쪽은 `lstat`으로 막았는데 여기가 빠졌었다
    func testSymlinkWithOurTabConfigNameIsNotRemoved() throws {
        let target = write("남의파일.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 600)
        let link = (directory as NSString).appendingPathComponent("terminal-checkout-deadbeef.toml")
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)
        removeWarpTabConfigIfOurs(path: link)
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertNotNil(try? FileManager.default.attributesOfItem(atPath: link), "링크가 지워졌다")
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

    /// 지금 막 열리고 있는 다른 요청의 파일을 지우면 그 탭이 열리지 않는다
    func testFreshTabConfigIsKept() {
        let path = write(
            "terminal-checkout-deadbeef.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 5
        )
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertTrue(exists(path))
    }

    /// 이름이 겹친 사용자 파일은 내용에서 걸러진다 — 남의 Tab Config를 지우면 안 된다
    func testUserFileWithOurNamingIsKept() {
        let path = write("terminal-checkout-deadbeef.toml", "name = \"내 작업 공간\"\n", ageSeconds: 600)
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertTrue(exists(path))
    }

    /// 브랜치 초기 빌드가 남긴 고정 이름 파일도 내용이 우리 것이면 회수한다
    func testLegacyFixedNameTabConfigIsRemoved() {
        let path = write(
            "terminal-checkout.toml", warpTabConfigTOML(commands: ["z remy"]), ageSeconds: 600
        )
        reclaimStaleWarpTabConfigs(in: directory)
        XCTAssertFalse(exists(path))
    }
}

// MARK: - uninstall.sh ↔ Swift 상수 동기화
// 삭제 스크립트는 앱과 **같은 판정**으로 남은 파일을 지운다(소켓은 우리 접두사 + 실제 소켓,
// Tab Config는 우리 접두사 + 우리 헤더). 그 문자열이 스크립트에 복제돼 있어, 한쪽만 바뀌면
// 삭제 대상이 조용히 어긋난다 — 접두사를 바꾸면 사용자 머신에 우리 파일이 영구히 남고,
// 헤더를 바꾸면 스크립트가 아무것도 못 지운다. 이 테스트가 그 갈림을 red로 만든다.
//
// **한계**: 문자열이 파일에 있는지만 본다. 그래서 uninstall.sh를 고칠 때 문자열을 주석이나 죽은
// 코드에만 남기면 이 가드는 통과한다 — 셸 구문까지 보지는 않는다.

/// 리포 루트 파일을 **소스 위치 기준**으로 읽는다 — 테스트 실행 CWD는 호출 방식에 따라
/// 달라지지만 `#filePath`는 컴파일 시점의 절대 경로라 worktree에서도 그 사본을 가리킨다.
/// 못 찾으면 던져서 **실패**한다: 스킵으로 넘기면 가드가 조용히 무력화된다.
private func repoFileContents(_ name: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath) // <루트>/app/Tests/CoreTests/CoreTests.swift
        .deletingLastPathComponent() // CoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // app
        .deletingLastPathComponent() // 리포 루트
    return try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
}

final class UninstallScriptSyncTests: XCTestCase {
    func testUninstallScriptSweepsWithTheSameConstants() throws {
        let script = try repoFileContents("uninstall.sh")
        // 스크립트에 그대로 나타나야 하는 것들. `--serve` 플래그는 일부러 빠져 있다 —
        // WarpHelper 타깃 private이라 여기서 볼 수 없고, 어긋났을 때 피해는 pkill 미스뿐이며
        // 헬퍼는 유휴·수명 상한으로 스스로 죽는다
        let expected = [
            warpHelperSocketPrefix + "*.sock",
            warpTabConfigPrefix + "*.toml",
            warpTabConfigHeader,
            warpTabConfigLegacyStem + ".toml",
            warpHelperExecutableName,
        ]
        for needle in expected {
            XCTAssertTrue(
                script.contains(needle),
                "uninstall.sh가 \(needle.debugDescription)을 다루지 않는다 — Swift 상수만 바뀌었다"
            )
        }
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
