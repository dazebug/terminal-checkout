import Foundation

/// runInTerminal이 돌려주는 세션 핸들 — claude 입력을 나중에 타이핑할 대상.
public enum TerminalSessionHandle {
    case iterm(sessionID: String, tty: String)
    case wezterm(paneID: String, cliPath: String, socketPath: String?)
    /// 전달 경로 없음 (WezTerm fallback 기동 등, pane을 특정할 수 없는 경우)
    case none
}

/// claude로 판정할 포그라운드 프로세스 이름. npm 배포는 comm=node로, 네이티브 설치는
/// comm=claude로 뜨는 것을 확인했다. bun은 bun 런타임으로 실행하는 환경 대비 여유분.
private let claudeProcessNames: Set<String> = ["claude", "node", "bun"]

/// `ps -t <tty> -o pid=,stat=,comm=` 출력에서 포그라운드 프로세스 그룹(stat에 `+`)인
/// claude의 PID를 돌려준다. 없으면 nil. 셸이 프롬프트에 있으면 셸 자신이 `+`라서 nil이 된다 —
/// 이 게이트가 "셸에 타이핑되어 Enter까지 즉시 실행"되는 오입력을 막는 유일한 방어선이다.
/// 있음/없음이 아니라 PID를 돌려주는 이유는 입력 사이 재대기에서 세션의 동일성을 확인해야
/// 하기 때문이다: 이름과 raw mode만 보면 원래 claude가 죽은 뒤 같은 tty에 새로 뜬 claude를
/// 같은 세션으로 오인해, 남은 입력을 무관한 세션에 제출한다. 같은 tty에서 claude를 재시작해
/// 확인한 결과 comm(`claude`)과 raw mode(참)는 두 세션이 동일했고 PID만 달랐다 — 세션 교체를
/// 가려낼 수 있는 신호는 PID뿐이다.
public func claudeForegroundPID(psOutput: String) -> Int? {
    for line in psOutput.split(separator: "\n") {
        // "pid stat comm…" — comm은 공백 포함 풀 경로일 수 있으므로 앞 두 칸만 가른다
        let parts = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
        guard parts.count == 3, let pid = Int(parts[0]), parts[1].contains("+") else { continue }
        // maxSplits에 걸린 마지막 조각에는 구분자 공백이 남는다 — 떼지 않으면 이름 비교가
        // 전부 어긋난다. ps의 pid는 우측 정렬이라 앞 공백도 붙지만 그쪽은 split이 걸러 준다
        var name = (parts[2].trimmingCharacters(in: .whitespaces) as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() } // 로그인 셸 표기(-zsh)
        if claudeProcessNames.contains(name) { return pid }
    }
    return nil
}

/// `stty -f <tty> -a` 출력에서 tty가 raw mode인지 판정한다.
/// nil은 "판정 불가"(stty 실패·출력 형식 변경) — 호출자가 ps 게이트만으로 진행하게 한다.
/// `-icanon`은 `icanon`을 부분 문자열로 포함하므로 반드시 토큰 단위로 갈라야 한다.
public func ttyIsRawMode(sttyOutput: String) -> Bool? {
    let tokens = sttyOutput.split(whereSeparator: { $0.isWhitespace })
    if tokens.contains("-icanon") { return true }
    if tokens.contains("icanon") { return false }
    return nil
}

/// 입력을 받을 수 있는 상태면 그 claude의 PID, 아니면 nil. 포그라운드가 claude인 것만으로는 부족하다:
/// 셸이 claude를 exec한 직후 tty는 아직 canonical(icanon+echo)이라 타이핑을 claude가 아니라
/// 커널이 에코한다. 그 에코를 `screenShowsInput`이 화면 반영으로 오판해 CR을 너무 일찍 보내면,
/// claude가 raw mode로 전환하며 화면을 다시 그릴 때 CR만 유실되어 첫 입력이 제출되지 않고
/// 입력창에 텍스트로 매달린다. 1초 폴링은 이 canonical 구간(exec 후 0.1∼1초)을 대개 지나쳐
/// 우연히 동작하지만, claude 기동이 느리면 첫 입력을 잃는다 — 폴링을 촘촘히 해 canonical
/// 구간을 겨냥하면 입력 3개 중 첫 개가 100% 유실되는 것을 확인했다(WezTerm 실측).
/// raw mode에서는 커널 에코가 꺼지므로, 이 게이트를 통과한 뒤 화면에 보이는 텍스트는
/// claude가 직접 그린 것이다 — 반영 확인이 비로소 claude의 수신을 뜻하게 된다.
/// 돌려준 PID는 이후 입력들이 같은 세션에 가는지 확인하는 데 쓴다.
/// 두 신호는 어느 쪽도 혼자 쓸 수 없다: 셸이 프롬프트에서 대기할 때도 zsh의 zle이 tty를
/// raw mode로 두므로(실측), raw mode만 보면 셸에 그대로 타이핑한다. ps 확인을 중복으로 보고
/// 걷어내면 이 스킬이 막으려던 셸 오입력이 되살아난다.
public func acceptingClaudePID(psOutput: String, sttyOutput: String) -> Int? {
    guard let pid = claudeForegroundPID(psOutput: psOutput) else { return nil }
    // 판정 불가면 ps 게이트만으로 진행한다 — stty를 못 읽는다고 전달을 통째로 포기하지 않는다
    guard ttyIsRawMode(sttyOutput: sttyOutput) ?? true else { return nil }
    return pid
}

/// `wezterm cli list --format json` 출력에서 pane의 tty 경로를 찾는다.
public func wezTermTTYName(listJSON: Data, paneID: String) -> String? {
    guard let list = (try? JSONSerialization.jsonObject(with: listJSON)) as? [[String: Any]],
          let paneNumber = Int(paneID) else { return nil }
    for pane in list where (pane["pane_id"] as? Int) == paneNumber {
        return pane["tty_name"] as? String
    }
    return nil
}

/// 화면 반영 확인용 프로브. 긴 입력은 화면에서 어딘가 잘리거나 접히므로 앞부분만 쓴다.
public func claudeInputProbe(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(trimmed.prefix(24))
}

/// 타이핑한 입력이 화면에 떴는지 판정한다. 공백을 모두 지우고 비교하는 이유는 claude TUI가
/// 입력을 글자 그대로 그리지 않기 때문이다: shell mode(`!`)는 "! gh …"처럼 `!` 뒤에 공백을
/// 끼우고, 긴 입력은 터미널 폭에서 줄바꿈된다 (둘 다 실측). 통짜로 비교하면 이런 입력은
/// 영영 반영 확인에 실패해 제출되지 못하고 입력창에 매달린다.
public func screenShowsInput(_ screen: String, input: String) -> Bool {
    let probe = claudeInputProbe(input).filter { !$0.isWhitespace }
    // 빈 프로브는 어떤 화면에나 매칭돼 엉뚱한 제출을 승인하게 된다
    guard !probe.isEmpty else { return false }
    return screen.filter { !$0.isWhitespace }.contains(probe)
}

/// 스폰된 세션의 claude가 입력을 받을 수 있게 될 때까지 기다렸다가 입력을 순서대로 전달한다.
/// 대기 조건은 [포그라운드 프로세스 = claude] + [tty가 raw mode]다 — 프로세스만 보면 셸이
/// exec한 직후의 canonical 구간을 통과해 첫 입력을 잃는다(`acceptingClaudePID` 참고).
/// 처음 준비된 claude의 PID를 고정해, 이후 입력이 같은 세션에만 가도록 한다.
/// 각 입력은 [개행 없이 타이핑 → 화면 반영 확인 → CR로 제출] 순서로 보낸다:
/// claude TUI는 초기화 중 도착한 입력을 온전히 받지 못하고, LF(\n)는 제출로 인식하지 않기 때문
/// (둘 다 WezTerm 실측). 첫 입력을 처리하는 동안 나머지는 claude 입력창에 큐잉된다.
/// 타임아웃 내에 claude가 준비되지 않으면 아무것도 보내지 않고 포기한다(로그만).
/// 최대 2분을 도는 블로킹 루프이므로 요청 처리 큐가 아닌 백그라운드 큐에서 불러야 한다.
public func deliverClaudeInputs(
    _ inputs: [String], to handle: TerminalSessionHandle,
    pollInterval: TimeInterval = 1.0, timeout: TimeInterval = 120,
    betweenInputTimeout: TimeInterval = 15
) {
    guard !inputs.isEmpty else { return }

    let ttyPath: String?
    switch handle {
    case .iterm(_, let tty):
        ttyPath = tty
    case .wezterm(let paneID, let cliPath, let socketPath):
        ttyPath = wezTermQueryTTY(cliPath: cliPath, socketPath: socketPath, paneID: paneID)
    case .none:
        NSLog("Terminal Checkout: claude 입력 전달 불가 — 세션 핸들 없음")
        return
    }
    guard let ttyPath, ttyPath.hasPrefix("/dev/") else {
        NSLog("Terminal Checkout: claude 입력 전달 불가 — 세션 tty를 알 수 없음")
        return
    }
    let ttyName = String(ttyPath.dropFirst("/dev/".count))

    guard let claudePID = waitUntilClaudeAcceptsInput(
        ttyName: ttyName, ttyPath: ttyPath, pollInterval: pollInterval, timeout: timeout
    ) else {
        NSLog("Terminal Checkout: \(Int(timeout))초 내에 claude가 입력을 받을 상태가 되지 않아 입력 \(inputs.count)개를 보내지 않음")
        return
    }

    for (index, input) in inputs.enumerated() {
        if index > 0 { Thread.sleep(forTimeInterval: 0.4) }
        // 전송 직전 재확인 — 그 사이 claude가 종료했으면 텍스트가 셸에 들어가므로 중단한다.
        // claude가 잠시 입력을 받지 못하는 상태일 수도 있어 즉시 포기하지 않고 짧게 기다리되,
        // 처음 준비된 그 PID만 인정한다 — 그 사이 사용자가 같은 pane에 새 claude를 띄웠다면
        // 남은 입력은 무관한 세션의 것이고, `!…` 입력이면 의도치 않은 셸 명령까지 실행된다
        guard waitUntilClaudeAcceptsInput(
            ttyName: ttyName, ttyPath: ttyPath,
            pollInterval: pollInterval, timeout: betweenInputTimeout, expecting: claudePID
        ) != nil else {
            NSLog("Terminal Checkout: 처음 준비된 claude 세션(pid \(claudePID))이 입력을 받을 상태가 아니라 남은 입력 \(inputs.count - index)개를 보내지 않음")
            return
        }
        guard typeAndSubmit(input, to: handle) else {
            NSLog("Terminal Checkout: claude 입력 전송 실패 — 남은 \(inputs.count - index)개 중단")
            return
        }
    }
}

/// 타이핑 → 화면 반영 확인 → 제출. 게이트를 통과했어도 claude TUI가 아직 입력을 그리지
/// 못하는 순간이 있어, 반영이 안 보이면 입력창을 비우고 재타이핑한다. 반영 확인 없이
/// 제출하면 빈 줄만 제출되거나 잘린 텍스트가 제출될 수 있으므로 확인 전에는 CR을 보내지 않는다.
/// raw mode 게이트를 통과한 뒤라 커널 에코는 꺼져 있고, 화면의 텍스트는 claude가 그린 것이다.
private func typeAndSubmit(_ text: String, to handle: TerminalSessionHandle) -> Bool {
    let maxAttempts = 5
    for attempt in 1...maxAttempts {
        if attempt > 1 {
            // Ctrl+U: 입력창 클리어 — 부분적으로 들어간 텍스트가 재타이핑과 섞이지 않게 한다
            guard sendKeys("\u{15}", to: handle) else { return false }
            Thread.sleep(forTimeInterval: 1.0)
        }
        guard sendKeys(text, to: handle) else { return false }

        for _ in 0..<5 {
            Thread.sleep(forTimeInterval: 0.4)
            guard let screen = screenText(of: handle) else { return false }
            if screenShowsInput(screen, input: text) {
                return sendKeys("\r", to: handle)
            }
        }
        NSLog("Terminal Checkout: 입력이 화면에 반영되지 않아 재시도 (\(attempt)/\(maxAttempts))")
    }
    return false
}

private func probeAcceptingClaudePID(ttyName: String, ttyPath: String) -> Int? {
    guard let ps = try? runProcess(
        "/bin/ps", ["-t", ttyName, "-o", "pid=,stat=,comm="], timeout: 5
    ) else {
        return nil
    }
    // stty 실패는 빈 출력으로 넘겨 "판정 불가"로 다룬다 (ps 게이트만으로 진행)
    let stty = (try? runProcess("/bin/stty", ["-f", ttyPath, "-a"], timeout: 5))
        .flatMap { $0.status == 0 ? $0.stdout : nil } ?? ""
    return acceptingClaudePID(psOutput: ps.stdout, sttyOutput: stty)
}

/// claude가 입력을 받을 수 있게 될 때까지 기다렸다가 그 PID를 돌려준다. 타임아웃이면 nil.
/// `expecting`을 주면 그 PID일 때만 인정한다 — 원래 세션이 죽은 뒤 같은 tty에 새로 뜬
/// claude에 남은 입력을 흘리지 않기 위해서다. 새 세션이 자리를 차지했으면 영영 만족하지
/// 않으므로 타임아웃까지 기다렸다 nil로 끝난다(입력은 보내지 않는다).
private func waitUntilClaudeAcceptsInput(
    ttyName: String, ttyPath: String, pollInterval: TimeInterval, timeout: TimeInterval,
    expecting: Int? = nil
) -> Int? {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if let pid = probeAcceptingClaudePID(ttyName: ttyName, ttyPath: ttyPath),
           expecting == nil || pid == expecting {
            return pid
        }
        if Date() >= deadline { return nil }
        Thread.sleep(forTimeInterval: pollInterval)
    }
}

private func wezTermQueryTTY(cliPath: String, socketPath: String?, paneID: String) -> String? {
    var env = ProcessInfo.processInfo.environment
    if let socketPath { env["WEZTERM_UNIX_SOCKET"] = socketPath }
    guard let result = try? runProcess(cliPath, ["cli", "list", "--format", "json"], env: env, timeout: 5),
          result.status == 0 else { return nil }
    return wezTermTTYName(listJSON: Data(result.stdout.utf8), paneID: paneID)
}

/// 키 입력을 개행 추가 없이 그대로 보낸다. "\r"는 제출, "\u{15}"(Ctrl+U)는 입력창 클리어.
private func sendKeys(_ text: String, to handle: TerminalSessionHandle) -> Bool {
    switch handle {
    case .iterm(let sessionID, _):
        // 제어문자는 AppleScript 문자열 리터럴에 넣을 수 없어 전용 스크립트로 분기한다
        let script: String
        switch text {
        case "\r": script = iTermWriteToSessionScript(sessionID: sessionID, text: "", submit: true)
        case "\u{15}": script = iTermClearInputScript(sessionID: sessionID)
        default: script = iTermWriteToSessionScript(sessionID: sessionID, text: text, submit: false)
        }
        guard let result = try? runProcess("/usr/bin/osascript", ["-e", script], timeout: 10),
              result.status == 0 else { return false }
        if result.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "gone" {
            NSLog("Terminal Checkout: 세션이 닫혀 claude 입력 전달 중단")
            return false
        }
        return true
    case .wezterm(let paneID, let cliPath, let socketPath):
        var env = ProcessInfo.processInfo.environment
        if let socketPath { env["WEZTERM_UNIX_SOCKET"] = socketPath }
        let result = try? runProcess(
            cliPath, ["cli", "send-text", "--pane-id", paneID, "--no-paste"],
            input: text, env: env, timeout: 5
        )
        return result?.status == 0
    case .none:
        return false
    }
}

/// 세션의 현재 화면 텍스트 — 타이핑 반영 확인용. 조회 실패나 세션 소멸이면 nil.
private func screenText(of handle: TerminalSessionHandle) -> String? {
    switch handle {
    case .iterm(let sessionID, _):
        guard let result = try? runProcess(
            "/usr/bin/osascript", ["-e", iTermSessionContentsScript(sessionID: sessionID)],
            timeout: 10
        ), result.status == 0 else { return nil }
        let text = result.stdout
        return text.trimmingCharacters(in: .whitespacesAndNewlines) == "gone" ? nil : text
    case .wezterm(let paneID, let cliPath, let socketPath):
        var env = ProcessInfo.processInfo.environment
        if let socketPath { env["WEZTERM_UNIX_SOCKET"] = socketPath }
        guard let result = try? runProcess(
            cliPath, ["cli", "get-text", "--pane-id", paneID], env: env, timeout: 5
        ), result.status == 0 else { return nil }
        return result.stdout
    case .none:
        return nil
    }
}
