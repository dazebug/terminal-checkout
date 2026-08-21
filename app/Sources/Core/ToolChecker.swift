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
    let checks = tools.flatMap { tool in
        [
            "TC_PATH=$(command -v \(tool) 2>/dev/null) && echo TC_OK:\(tool)",
            "TC_EXE_PATH=$(cd / && /bin/sh -c 'command -v \(tool)' 2>/dev/null)",
            "case \"$TC_EXE_PATH\" in /*) [ -x \"$TC_EXE_PATH\" ] && echo TC_EXE:\(tool) ;; esac",
        ]
    }
    return (checks + ["echo TC_DONE"]).joined(separator: "\n")
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

/// 셸을 어떻게 띄워 물어볼 것인가. **로그인(-l) + 인터랙티브(-i)** 가 첫 후보다:
///  - `-i`가 없으면 rc를 읽지 않아 `z` 같은 셸 함수도, rc가 덧붙인 PATH도 보이지 않는다
///  - `-l`이 없으면 **프로필을 읽지 않는다** — Homebrew `shellenv`가 들어가는 곳이 정확히
///    `.zprofile`/`.bash_profile`이라, 그 사용자는 터미널 탭에서는 멀쩡히 도는 `claude`를
///    "실행 파일 없음"으로 판정받는다(독립 검증자 지적). 터미널 탭이 실제로 로그인 셸이다
///  - `-l`은 보편적이지 않다(dash에는 없다). 그래서 실패하면 `-i -c`로 한 번 더 묻는다
public func toolCheckShellArgumentCandidates(_ script: String) -> [[String]] {
    [["-l", "-i", "-c", script], ["-i", "-c", script]]
}

/// 로그인 셸에게 물어 확인한다. 느리므로(프로필·rc 로드) 백그라운드에서 부른다.
/// **로그인 셸이 pane 셸과 다를 수 있다**는 한계는 병합 판정 전반과 같다
/// (`shellCanRunAppendedPrompt` 주석) — 여기서 본 rc가 그 pane의 rc가 아닐 수 있다.
public func checkTools(
    _ tools: [String] = checkedTools, timeout: TimeInterval = 20
) -> ToolCheckResult? {
    let script = toolCheckScript(tools)
    for arguments in toolCheckShellArgumentCandidates(script) {
        guard let result = try? runProcess(loginShellPath(), arguments, timeout: timeout),
              let available = parseToolCheck(output: result.stdout, tools: tools),
              let executable = parseToolExecutables(output: result.stdout, tools: tools) else {
            continue // 이 형태로는 셸이 뜨지 않았다(완료 마커 없음) — 다음 후보로
        }
        return ToolCheckResult(available: available, executable: executable)
    }
    return nil
}
