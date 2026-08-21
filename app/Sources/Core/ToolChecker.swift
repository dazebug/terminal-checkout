import Foundation

/// 명령 템플릿이 부르는 도구들이 사용자 셸에서 실제로 불릴 수 있는지 확인한다.
/// 파일시스템 탐색이 아니라 셸에게 묻는 이유: `z`는 zoxide가 rc에서 정의하는 셸 함수라
/// 어떤 경로에도 실행 파일이 없고, PATH도 GUI 앱과 로그인 셸이 서로 다르다.

/// 기본 확인 대상. z는 기본 명령 템플릿이 첫 단어로 쓰므로 없으면 모든 버튼이 실패하고,
/// gh/claude는 각각 이슈 프리셋과 claude 입력에서만 쓰인다.
public let checkedTools = ["z", "gh", "claude"]

/// 사용자의 로그인 셸. GUI 앱의 SHELL 환경변수는 launchd가 물려준 값이라 신뢰할 수 없어
/// 계정 레코드에서 직접 읽는다.
public func loginShellPath() -> String {
    if let entry = getpwuid(getuid()) {
        let shell = String(cString: entry.pointee.pw_shell)
        if shell.hasPrefix("/") { return shell }
    }
    return "/bin/zsh"
}

/// 도구별로 두 가지를 마커 한 줄씩으로 답하게 하는 셸 스크립트.
/// tools는 코드 상수만 넘긴다 — 사용자 입력을 그대로 넣으면 셸 주입이 된다.
///
/// `TC_OK`는 "그 이름을 치면 뭔가 불린다"이고 **함수·별칭도 포함한다**(`z`가 바로 그 경우다).
/// `TC_EXE`는 **`command <이름>`이 실제로 실행할 파일이 있는가**이다. 둘을 가르는 이유: 병합
/// 경로는 `command claude`로 부르고 `command`는 함수·별칭을 지나치므로, `alias claude='npx …'`
/// 같은 설치에서는 `TC_OK`가 참이어도 병합한 명령이 command not found로 죽는다.
///
/// `TC_EXE`를 **자식 `/bin/sh`에게** 묻는 이유(라운드 7, 전부 실측):
///  - 로그인 셸에서 `command -v`는 함수·별칭이 이름을 가리면 그 이름만 돌려준다. 그런데
///    **실제 파일을 감싼 래퍼**라면 `command claude`는 그 파일을 실행한다 — 병합해도 되는
///    경우다. rc를 읽지 않는 자식 셸은 그 파일을 그대로 답한다
///  - `[ -x ]`가 필요한 이유: bash·dash의 `command -v`는 **실행 권한이 없는** 파일에도 절대
///    경로를 돌려준다(zsh·/bin/sh는 돌려주지 않는다). 경로 모양만 보면 병합 후 실패한다
///  - `cd /`로 물어보는 이유: PATH에 **상대 경로** 항목이 있으면 해석 결과가 cwd에 따라 달라진다.
///    pane의 cwd(명령이 `cd`한 뒤)는 알 수 없으므로 `/`에서 풀리지 않으면 병합하지 않는다
public func toolCheckScript(_ tools: [String]) -> String {
    // A relative `PATH` entry (or an empty one, which means the working directory) resolves
    // against a cwd we cannot know — the pane's, after the command has `cd`ed. One of those and
    // the executable answer is worthless, so it disqualifies the whole answer.
    //
    // **A trailing colon is not caught, on purpose** (measured, `scratchpad/trailing-colon-probe.sh`;
    // field splitting produces no trailing null field):
    //
    //     PATH=/usr/bin:/bin   -> TC_REL=[]      PATH=:/usr/bin      -> TC_REL=[rel]
    //     PATH=/usr/bin::/bin  -> TC_REL=[rel]   PATH=/usr/bin:rel   -> TC_REL=[rel]
    //     PATH=/usr/bin:/bin:  -> TC_REL=[]      PATH=.              -> TC_REL=[rel]
    //
    // Why it is left: a trailing colon puts the working directory **last**, and an earlier
    // absolute entry always wins — measured from both `/` and another cwd, the same absolute hit
    // comes back. So the cwd entry can only decide the answer for a name that exists in *no*
    // absolute entry, which for `claude` means a file at the filesystem root.
    //
    // One leg of that argument does **not** hold, and saying so is the point of writing it down:
    // "asked from `/`, a cwd hit answers with a relative path and the `/*` gate filters it" is
    // false for the shell we ask — `/bin/sh` (bash 3.2 here) absolutises it (`/./claude`), while
    // bash, zsh and dash return `./claude` or `claude`. So the residual is real: with `/claude`
    // present and `claude` nowhere on the absolute PATH, we would answer "executable" and the pane
    // would fail. That failure is a visible `command not found` (a lost input, not a misdelivered
    // one), whereas treating every trailing colon as relative would silently cost the merge — and
    // on Warp without the permission, the whole request — to everyone whose PATH merely ends in a
    // stray `:`. The rarer, visible failure is the one we keep
    // The patterns carry a leading `(`: inside `$( )`, bash 3.2 — which is `/bin/sh` on macOS —
    // mis-parses a bare `pattern)` in a `case` and dies with a syntax error (measured)
    let relative = "TC_REL=$(IFS=:; for d in $PATH; do case \"$d\" in (/*) : ;; (*) printf rel;"
        + " break ;; esac; done)"
    let checks = tools.flatMap { tool in
        [
            "TC_PATH=$(command -v \(tool) 2>/dev/null) && echo TC_OK:\(tool)",
            "TC_EXE_PATH=$(cd / && /bin/sh -c 'command -v \(tool)' 2>/dev/null)",
            "case \"$TC_EXE_PATH\" in /*) [ -z \"$TC_REL\" ] && [ -x \"$TC_EXE_PATH\" ]"
                + " && echo TC_EXE:\(tool) ;; esac",
        ]
    }
    return ([relative] + checks + ["echo TC_DONE"]).joined(separator: "\n")
}

/// 마커 출력을 도구별 결과로 바꾼다. 스크립트가 끝까지 돌지 못했으면(완료 마커 없음)
/// nil — 셸이 죽은 것과 도구가 없는 것을 같게 다루면 멀쩡한 환경에 경고를 띄우게 된다.
public func parseToolCheck(output: String, tools: [String]) -> [String: Bool]? {
    parseToolMarker("TC_OK:", output: output, tools: tools)
}

/// 같은 출력에서 "실행 파일로 풀리는가"만 읽는다 — 설정 창의 ✅(부를 수 있는가)와는 다른 사실이라
/// 별도로 답한다.
public func parseToolExecutables(output: String, tools: [String]) -> [String: Bool]? {
    parseToolMarker("TC_EXE:", output: output, tools: tools)
}

private func parseToolMarker(_ prefix: String, output: String, tools: [String]) -> [String: Bool]? {
    var found = Set<String>()
    var completed = false
    for rawLine in output.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        if line.hasSuffix("TC_DONE") { completed = true }
        // 셸 통합(iTerm2 등)이 첫 줄 앞에 escape sequence를 붙이므로 앞부분은 버리고 찾는다
        guard let marker = line.range(of: prefix, options: .backwards) else { continue }
        found.insert(String(line[marker.upperBound...]))
    }
    guard completed else { return nil }
    return Dictionary(uniqueKeysWithValues: tools.map { ($0, found.contains($0)) })
}

/// 도구 확인 결과 두 갈래. `available`은 설정 창의 ✅(그 이름을 부를 수 있는가),
/// `executable`은 병합 경로가 필요로 하는 사실(그 이름이 실행 파일로 풀리는가)이다.
public struct ToolCheckResult: Equatable {
    public let available: [String: Bool]
    public let executable: [String: Bool]
}

/// 셸을 어떻게 띄워 물어볼 것인가 — **둘 다 물어보고 합집합을 쓴다.**
///
/// 실측(`scratchpad/rcfiles-probe.sh`): `bash -l -i -c`는 `.bash_profile`만 읽고 **`.bashrc`를
/// 읽지 않는다**. `bash -i -c`는 `.bashrc`를 읽는다. zsh는 `-l -i -c`가 `-i -c`의 상위집합이다
/// (`.zshenv .zprofile .zshrc`). 즉 어느 한 형태도 다른 쪽을 포함하지 못한다.
///
/// 라운드 7은 "로그인 형태를 먼저, 실패하면 폴백"으로 두었는데 로그인 형태는 **성공한다** —
/// 도구를 못 찾았을 뿐이다. 그래서 폴백이 영영 돌지 않았고, 도구가 `.bashrc`에만 있는 bash
/// 사용자는 설정 창에 `z` ❌가 뜨고 **모든 버튼의 병합이 조용히 꺼졌다**(독립 검증자 차단 항목).
/// 합집합이면 어느 rc에 있든 찾는다. 대가는 셸을 두 번 띄우는 시간(백그라운드)뿐이다.
public func toolCheckShellArgumentCandidates(_ script: String) -> [[String]] {
    [["-l", "-i", "-c", script], ["-i", "-c", script]]
}

/// 여러 형태로 물어본 답을 합친다 — 한 곳에서라도 보이면 있는 것이다. 전부 실패(빈 배열)면
/// nil: "없음"이 아니라 "모름"이고, 그때는 직전 결과를 그대로 둔다.
public func mergeToolChecks(_ results: [ToolCheckResult]) -> ToolCheckResult? {
    guard !results.isEmpty else { return nil }
    func union(_ pick: (ToolCheckResult) -> [String: Bool]) -> [String: Bool] {
        results.map(pick).reduce(into: [:]) { merged, answer in
            for (tool, found) in answer { merged[tool] = (merged[tool] ?? false) || found }
        }
    }
    return ToolCheckResult(available: union(\.available), executable: union(\.executable))
}

/// 로그인 셸에게 물어 확인한다. 느리므로(프로필·rc 로드) 백그라운드에서 부른다.
/// **로그인 셸이 pane 셸과 다를 수 있다**는 한계는 병합 판정 전반과 같다
/// (`shellCanRunAppendedPrompt` 주석) — 여기서 본 rc가 그 pane의 rc가 아닐 수 있다.
public func checkTools(
    _ tools: [String] = checkedTools, timeout: TimeInterval = 20,
    shell: String = loginShellPath(), environment: [String: String]? = nil
) -> ToolCheckResult? {
    let script = toolCheckScript(tools)
    let answers = toolCheckShellArgumentCandidates(script).compactMap { arguments in
        guard let result = try? runProcess(shell, arguments, env: environment, timeout: timeout),
              let available = parseToolCheck(output: result.stdout, tools: tools),
              let executable = parseToolExecutables(output: result.stdout, tools: tools) else {
            return ToolCheckResult?.none // 이 형태로는 셸이 답하지 않았다(완료 마커 없음)
        }
        return ToolCheckResult(available: available, executable: executable)
    }
    return mergeToolChecks(answers)
}
