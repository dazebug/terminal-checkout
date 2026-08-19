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
        XCTAssertTrue(screenShowsInput(
            "╭────────╮\n! gh issue view 1404\n╰────────╯\n  ! for shell mode",
            input: "!gh issue view 1404"
        ))
    }

    // 긴 입력은 터미널 폭에서 줄바꿈된다 — 프로브 길이 안에서 끊겨도 매칭돼야 한다
    func testScreenMatchesWrappedInput() {
        XCTAssertTrue(screenShowsInput(
            "> !gh api repos/frograms/remy-\nworker/issues/1404/timeline",
            input: "!gh api repos/frograms/remy-worker/issues/1404/timeline"
        ))
    }

    func testScreenWithoutInputDoesNotMatch() {
        XCTAssertFalse(screenShowsInput("> \n  ? for shortcuts", input: "!gh issue view 1404"))
    }

    // 공백뿐인 입력은 프로브가 비어 아무 화면에나 매칭된다 — 제출을 승인해선 안 된다
    func testEmptyInputNeverMatches() {
        XCTAssertFalse(screenShowsInput("아무 화면", input: "   "))
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
    /// 입력창에 이미 남아 있는 텍스트 (클리어 실패 상황을 만들 때 쓴다)
    var presetBox = "" { didSet { box = presetBox } }
    private(set) var sendCallCount = 0
    private var screenCalls = 0
    private var box = ""

    var io: ClaudeSessionIO {
        ClaudeSessionIO(
            sendKeys: { [unowned self] keys in
                sendCallCount += 1
                if failSendAt.contains(sendCallCount) { return false }
                keystrokes.append(keys)
                switch keys {
                case "\r": submitted.append(box); box = ""
                case "\u{15}": box = ""
                default: box += keys
                }
                return true
            },
            screenText: { [unowned self] in
                screenCalls += 1
                if failScreenAt.contains(screenCalls) { return nil }
                return "❯ " + box
            },
            confirmSession: { [unowned self] _ in sessionAlive },
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
        XCTAssertEqual(session.keystrokes, [inputs[0], "\r"])
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
        XCTAssertTrue(session.keystrokes.isEmpty) // 재시도 타이핑이 나가면 안 된다
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
            confirmSession: { _ in confirms += 1; return confirms == 1 },
            wait: { _ in }
        )
        XCTAssertEqual(submitClaudeInputs([inputs[0]], io: io), 0)
        XCTAssertEqual(session.sendCallCount, 2) // 타이핑 1 + CR 1 — 재전송을 더 시도하면 안 된다
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
