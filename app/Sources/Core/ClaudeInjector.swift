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

/// `ps -t <tty> -o stat=,comm=` 출력에서 포그라운드 프로세스 그룹(stat에 `+`)에
/// claude가 있는지 판정한다. 셸이 프롬프트에 있으면 셸 자신이 `+`라서 false가 된다 —
/// 이 게이트가 "셸에 타이핑되어 Enter까지 즉시 실행"되는 오입력을 막는 유일한 방어선이다.
public func hasClaudeForeground(psOutput: String) -> Bool {
    for line in psOutput.split(separator: "\n") {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let space = trimmed.firstIndex(where: { $0.isWhitespace }) else { continue }
        guard trimmed[..<space].contains("+") else { continue }
        // comm은 이름만("claude")일 수도, 공백 포함 풀 경로일 수도 있다 → 나머지 전체가 comm
        let comm = trimmed[space...].trimmingCharacters(in: .whitespaces)
        var name = (comm as NSString).lastPathComponent
        if name.hasPrefix("-") { name.removeFirst() } // 로그인 셸 표기(-zsh)
        if claudeProcessNames.contains(name) { return true }
    }
    return false
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

/// 스폰된 세션의 포그라운드가 claude가 될 때까지 기다렸다가 입력을 순서대로 전달한다.
/// 각 입력은 [개행 없이 타이핑 → 화면 반영 확인 → CR로 제출] 순서로 보낸다:
/// claude TUI는 초기화 중 도착한 입력을 버리고, LF(\n)는 제출로 인식하지 않기 때문
/// (둘 다 WezTerm 실측). 첫 입력을 처리하는 동안 나머지는 claude 입력창에 큐잉된다.
/// 타임아웃 내에 claude가 안 뜨면 아무것도 보내지 않고 포기한다(로그만).
/// 최대 2분을 도는 블로킹 루프이므로 요청 처리 큐가 아닌 백그라운드 큐에서 불러야 한다.
public func deliverClaudeInputs(
    _ inputs: [String], to handle: TerminalSessionHandle,
    pollInterval: TimeInterval = 1.0, timeout: TimeInterval = 120
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

    let deadline = Date().addingTimeInterval(timeout)
    while !claudeIsForeground(ttyName: ttyName) {
        if Date() >= deadline {
            NSLog("Terminal Checkout: \(Int(timeout))초 내에 claude가 뜨지 않아 입력 \(inputs.count)개를 보내지 않음")
            return
        }
        Thread.sleep(forTimeInterval: pollInterval)
    }

    for (index, input) in inputs.enumerated() {
        if index > 0 { Thread.sleep(forTimeInterval: 0.4) }
        // 전송 직전 재확인 — 그 사이 claude가 종료했으면 텍스트가 셸에 들어가므로 중단
        guard claudeIsForeground(ttyName: ttyName) else {
            NSLog("Terminal Checkout: claude가 전면에서 사라져 남은 입력 \(inputs.count - index)개를 보내지 않음")
            return
        }
        guard typeAndSubmit(input, to: handle) else {
            NSLog("Terminal Checkout: claude 입력 전송 실패 — 남은 \(inputs.count - index)개 중단")
            return
        }
    }
}

/// 타이핑 → 화면 반영 확인 → 제출. 반영이 안 보이면(TUI가 아직 입력을 버리는 중)
/// 입력창을 비우고 재타이핑한다. 반영 확인 없이 제출하면 빈 줄만 제출되거나
/// 잘린 텍스트가 제출될 수 있으므로 확인 전에는 절대 CR을 보내지 않는다.
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

private func claudeIsForeground(ttyName: String) -> Bool {
    guard let result = try? runProcess("/bin/ps", ["-t", ttyName, "-o", "stat=,comm="], timeout: 5) else {
        return false
    }
    return hasClaudeForeground(psOutput: result.stdout)
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
