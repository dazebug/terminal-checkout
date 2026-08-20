import Foundation

/// runInTerminal이 돌려주는 세션 핸들 — claude 입력을 나중에 타이핑할 대상.
public enum TerminalSessionHandle {
    case iterm(sessionID: String, tty: String)
    case wezterm(paneID: String, cliPath: String, socketPath: String?)
    /// Warp는 pane을 지목할 CLI도 AppleScript도 없어, pane 안에서 도는 주입 헬퍼의 소켓이
    /// 유일한 통로다. tty도 그 헬퍼에게 물어서 안다(`ClaudeInjector.warpHelperTTY`).
    case warp(helperSocket: String)
    /// 전달 경로 없음 (WezTerm fallback 기동, Warp 헬퍼를 준비하지 못함 등)
    case none

    /// 화면 조회가 이 세션의 것이라고 단정할 수 있는가. iTerm2·WezTerm은 세션·pane id로
    /// 그 화면만 읽지만 Warp는 "포커스된 pane"만 읽힌다 — 그쪽만 pane 증명이 필요하다.
    var screenNeedsPaneProof: Bool {
        if case .warp = self { return true }
        return false
    }
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
/// 커널이 에코한다. 그 에코를 `screenReflectsNewInput`이 화면 반영으로 오판해 CR을 너무 일찍 보내면,
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

/// pane 증명용 난수. 우리 tty로만 들어가므로, 이것이 화면에 새로 뜨면 그 화면이 우리
/// pane이라는 증거가 된다. claude 입력창에서 특별한 뜻을 갖지 않도록 영숫자만 쓰고
/// (`/`·`!`·`@`는 모드·자동완성을 건드린다), 우연히 겹치지 않을 만큼 길게 뽑는다.
public func paneProofToken() -> String {
    let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")
    return "tc" + String((0..<10).map { _ in alphabet.randomElement()! })
}

/// 화면 반영 확인용 프로브. 긴 입력은 화면에서 어딘가 잘리거나 접히므로 앞부분만 쓴다.
public func claudeInputProbe(_ input: String) -> String {
    let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
    return String(trimmed.prefix(24))
}

/// 타이핑한 입력이 **이번에 새로** 화면에 떴는지 판정한다. 타이핑 직전 화면(`before`)보다
/// 프로브가 한 번 더 보여야 반영으로 인정한다.
///
/// "화면에 있나"만 보면 안 되는 이유: Warp에서 접근성으로 읽는 화면은 포커스된 pane의
/// 것이라 우리 pane이라는 보장이 없다. 다른 pane에 우연히 같은 텍스트가 떠 있으면 단순
/// 부분 문자열 일치는 타이핑 전부터 통과하고, 그대로 CR이 나가면 우리 입력은 제출되지 않은
/// 채 그 순간 사용자가 그 pane에 치고 있던 것이 제출된다.
/// `before`가 nil(화면 조회 실패)이면 확인 실패다 — 못 찍은 것을 "없었다"로 다루면 같은 구멍이
/// 그대로 남는다.
///
/// 공백을 모두 지우고 비교하는 이유는 claude TUI가 입력을 글자 그대로 그리지 않기 때문이다:
/// shell mode(`!`)는 "! gh …"처럼 `!` 뒤에 공백을 끼우고, 긴 입력은 터미널 폭에서 줄바꿈된다
/// (둘 다 실측). 통짜로 비교하면 이런 입력은 영영 반영 확인에 실패해 입력창에 매달린다.
/// 있음/없음이 아니라 개수로 세는 이유는 같은 입력을 두 번 예약했을 때 앞의 것이 대화 기록에
/// 남아 있어도 뒤의 것을 제출할 수 있어야 하기 때문이다.
public func screenReflectsNewInput(before: String?, after: String, input: String) -> Bool {
    guard let before else { return false }
    let probe = claudeInputProbe(input).filter { !$0.isWhitespace }
    // 빈 프로브는 어떤 화면에나 매칭돼 엉뚱한 제출을 승인하게 된다
    guard !probe.isEmpty else { return false }
    return probeCount(probe, in: after) > probeCount(probe, in: before)
}

private func probeCount(_ probe: String, in screen: String) -> Int {
    var count = 0
    var rest = Substring(screen.filter { !$0.isWhitespace })
    while let found = rest.range(of: probe) {
        count += 1
        rest = rest[found.upperBound...]
    }
    return count
}

/// 세션 입출력 — 실제로는 osascript·wezterm cli 호출이지만, 전달 순서와 실패 복구 판정을
/// 프로세스 없이 검증할 수 있도록 클로저로 분리한다.
public struct ClaudeSessionIO {
    /// 키 입력을 개행 추가 없이 보낸다. false는 "이번 호출이 실패했다"는 뜻일 뿐
    /// 세션이 끝났다는 뜻이 아니다 — 그 판정은 confirmSession이 한다.
    public var sendKeys: (String) -> Bool
    /// 현재 화면 텍스트. 조회 실패면 nil.
    public var screenText: () -> String?
    /// 주어진 시간 안에 처음 준비된 그 claude가 입력을 받을 상태가 되면 true (기다린다).
    public var confirmSession: (TimeInterval) -> Bool
    /// **바이트를 내보내기 직전** 게이트 ③: 지금도 처음 그 claude인가 (기다리지 않는다).
    /// `send(_:io:)`만 이것을 부르고, 모든 전송은 `send`를 지난다 — 전송 자리마다 따로
    /// 확인하면 반드시 빠뜨리는 자리가 생긴다.
    public var sessionIsUnchanged: () -> Bool
    /// 화면으로 확인할 수단이 아직 있는가(Warp: 손쉬운 사용 권한). false면 **새로 치지 않는다** —
    /// 확인 없이 친 것은 제출도 회수도 못 하기 때문이다. 반대로 이미 친 것을 되돌리는
    /// 정리(`clearAbandonedInput`)는 이 조건을 보지 않는다: 정리를 같이 막으면 자동 입력이
    /// 입력창에 남아 사용자가 나중에 Enter를 눌렀을 때 실행된다.
    public var canConfirmScreen: () -> Bool
    /// `screenText`가 우리 세션의 화면이라고 단정할 수 없는 터미널은 true.
    /// iTerm2·WezTerm은 pane/세션 id로 그 pane만 읽으므로 false다. Warp는 접근성으로
    /// "포커스된 pane"만 읽히므로 true — 그때는 입력마다 pane 증명을 먼저 태운다.
    public var screenNeedsPaneProof: Bool
    /// 대기 — 테스트에서 없애 루프를 즉시 돌린다.
    public var wait: (TimeInterval) -> Void

    public init(
        sendKeys: @escaping (String) -> Bool,
        screenText: @escaping () -> String?,
        confirmSession: @escaping (TimeInterval) -> Bool,
        sessionIsUnchanged: @escaping () -> Bool = { true },
        canConfirmScreen: @escaping () -> Bool = { true },
        screenNeedsPaneProof: Bool = false,
        wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
    ) {
        self.sendKeys = sendKeys
        self.screenText = screenText
        self.confirmSession = confirmSession
        self.sessionIsUnchanged = sessionIsUnchanged
        self.canConfirmScreen = canConfirmScreen
        self.screenNeedsPaneProof = screenNeedsPaneProof
        self.wait = wait
    }
}

/// 나가는 바이트의 종류. 문은 하나지만 요구 조건이 다르다 — 검사를 문 **밖으로** 빼면
/// 반드시 빠뜨리는 자리가 생기므로(실제로 그렇게 새어 본문 타이핑이 게이트를 건너뛰었다),
/// 종류를 문에 달아 안에서 가른다.
enum SendKind {
    /// 새로 치는 것(표식·본문·CR·클리어 후 재타이핑). 화면으로 확인할 수단이 있어야 한다
    case typing
    /// 이미 친 것을 되돌리는 것(정리용 Ctrl+U). 화면 확인 수단과 무관하게 나가야 한다 —
    /// 같이 막으면 우리 텍스트가 입력창에 남아 사용자가 누른 Enter로 실행된다
    case cleanup
}

/// **바이트가 나가는 유일한 문.** 여기서만 게이트를 확인한다 — 표식·입력창 클리어·본문
/// 타이핑·CR·정리가 모두 이 함수를 지나므로, 새 전송 경로를 추가해도 게이트 밖으로 샐 수 없다.
///
/// 게이트 ③(세션 동일성)은 **모든** 종류에 건다. 화면 확인 수단(`canConfirmScreen`)은
/// `.typing`에만 건다 — 시도 시작에 한 번만 보면 그 뒤 pane 증명이나 대기 중에 권한이
/// 회수됐을 때 표식·본문·CR이 계속 나간다(실제로 그랬다).
///
/// 확인과 전송 사이의 창(`ps`·`stty` 왕복 ≈ 9ms)은 경로상 없앨 수 없다 — 그 사이 세션이
/// 바뀌면 바이트 하나가 새 세션에 들어간다. 다만 CR도 같은 게이트를 지나므로 **실행되지는
/// 않고**, 입력창에 남은 조각은 그 세션의 사용자가 지운다.
private func send(_ keys: String, io: ClaudeSessionIO, kind: SendKind = .typing) -> Bool {
    if kind == .typing, !io.canConfirmScreen() { return false }
    guard io.sessionIsUnchanged() else { return false }
    return io.sendKeys(keys)
}

/// 전달이 중간에 끝났을 때 입력창에 남았을 우리 조각을 지운다. 같은 문을 지나므로
/// 세션이 바뀐 뒤에는 아무것도 나가지 않는다.
///
/// `weSentSomething`이 false면 아무것도 하지 않는다 — 우리가 한 바이트도 보내지 못했다면
/// 입력창에 있는 것은 **사용자가 치던 초안**뿐이고, 그걸 Ctrl+U로 지우는 것은 우리가 고치려던
/// 피해를 우리가 일으키는 것이다.
@discardableResult
func clearAbandonedInput(io: ClaudeSessionIO, weSentSomething: Bool) -> Bool {
    guard weSentSomething else { return false }
    return send("\u{15}", io: io, kind: .cleanup)
}

/// 준비된 claude 세션에 입력을 순서대로 제출하고, 제출에 성공한 개수를 돌려준다.
/// 각 입력은 [개행 없이 타이핑 → 화면 반영 확인 → CR로 제출] 순서로 보낸다:
/// LF(\n)는 제출로 인식되지 않고, 게이트를 통과한 뒤에도 TUI가 입력을 아직 그리지 못하는
/// 순간이 있기 때문이다 (둘 다 WezTerm 실측). 첫 입력을 처리하는 동안 나머지는 claude
/// 입력창에 큐잉된다.
/// 입력마다 세션 동일성을 먼저 확인한다 — 그 사이 원래 세션이 죽고 같은 tty에 새 claude가
/// 떴다면 남은 입력은 무관한 세션의 것이고, `!…` 입력이면 셸 명령까지 실행된다.
@discardableResult
public func submitClaudeInputs(
    _ inputs: [String], io: ClaudeSessionIO,
    betweenInputTimeout: TimeInterval = 15, retryConfirmTimeout: TimeInterval = 2
) -> Int {
    var submitted = 0
    for (index, input) in inputs.enumerated() {
        if index > 0 { io.wait(0.4) }
        guard io.confirmSession(betweenInputTimeout) else {
            checkoutLog("처음 준비된 claude 세션이 입력을 받을 상태가 아니라 남은 입력 \(inputs.count - index)개를 보내지 않음")
            return submitted
        }
        guard typeAndSubmit(input, io: io, retryConfirmTimeout: retryConfirmTimeout) else {
            checkoutLog("claude 입력 전송 실패 — 남은 \(inputs.count - index)개 중단")
            return submitted
        }
        submitted += 1
    }
    return submitted
}

/// 타이핑 → 화면 반영 확인 → 제출. 게이트를 통과했어도 claude TUI가 아직 입력을 그리지
/// 못하는 순간이 있어, 반영이 안 보이면 입력창을 비우고 재타이핑한다. 반영 확인 없이
/// 제출하면 빈 줄만 제출되거나 잘린 텍스트가 제출될 수 있으므로 확인 전에는 CR을 보내지 않는다.
/// raw mode 게이트를 통과한 뒤라 커널 에코는 꺼져 있고, 화면의 텍스트는 claude가 그린 것이다.
///
/// 터미널 CLI 호출 실패도 화면 미반영과 같은 재시도로 다룬다. 이 호출은 실제로 한 번씩
/// 실패한다 — 입력 3개 중 #1만 전달되고 끝난 사고에서 앱 로그는 #1 제출 7초 뒤의 한 줄이
/// 전부였고, 한 줄만 남기고 끝나는 경로는 이 호출 실패뿐이었다 (세션 게이트 미통과라면
/// 15초를 기다린 뒤 찍힌다). 어느 호출이 실패했는지까지는 좁히지 못했다.
/// 다만 재타이핑 전에는 세션 동일성을 다시 확인한다 — 실패가 "세션이 죽었다"였을 수도 있어,
/// 확인 없이 다시 치면 그 tty에 새로 뜬 claude에 입력이 흘러든다.
private func typeAndSubmit(
    _ text: String, io: ClaudeSessionIO, retryConfirmTimeout: TimeInterval
) -> Bool {
    let maxAttempts = 5
    for attempt in 1...maxAttempts {
        guard io.canConfirmScreen() else {
            checkoutLog("화면을 확인할 수단이 사라져 더 치지 않음 — 남은 조각은 정리한다")
            return false
        }
        if attempt > 1 {
            guard io.confirmSession(retryConfirmTimeout) else { return false }
        }
        // 읽히는 화면이 우리 pane인지 먼저 증명한다. 실패는 대개 "사용자가 다른 탭·앱을
        // 보고 있다"이므로 오류가 아니라 대기다 — 다음 시도에서 다시 본다
        var proved = true
        if io.screenNeedsPaneProof {
            proved = proveOurPane(io: io)
            if !proved {
                checkoutLog("읽히는 화면이 우리 pane이 아님 — 재시도 (\(attempt)/\(maxAttempts))")
            }
        }
        // 입력창을 비운다. pane 증명을 했으면 표식이 남아 있고, 재시도면 이전 조각이 남아
        // 있다 — 남은 것 뒤에 이어 치면 화면 확인은 통과한 채로 앞이 붙은 입력이 제출된다.
        // 증명이 실패했을 때도 반드시 지운다: 표식을 남기면 사용자가 그것을 제출하게 된다
        if io.screenNeedsPaneProof || attempt > 1 {
            guard send("\u{15}", io: io) else {
                checkoutLog("입력창 클리어 실패 — 재시도 (\(attempt)/\(maxAttempts))")
                io.wait(1.0)
                continue
            }
            io.wait(1.0)
        }
        guard proved else { continue }
        // 타이핑 직전 화면을 찍어 둔다 — "이미 떠 있던 텍스트"와 "우리가 방금 친 것"을
        // 가르는 유일한 수단이다(`screenReflectsNewInput`)
        let before = io.screenText()
        guard send(text, io: io) else {
            checkoutLog("타이핑 전송 실패 — 재시도 (\(attempt)/\(maxAttempts))")
            continue
        }

        var reflected = false
        var failure = "입력이 화면에 반영되지 않음"
        for _ in 0..<5 {
            io.wait(0.4)
            guard let screen = io.screenText() else {
                failure = "화면 조회 실패"
                break
            }
            if screenReflectsNewInput(before: before, after: screen, input: text) {
                reflected = true
                break
            }
        }
        if reflected {
            if submitConfirmedInput(io: io, retryConfirmTimeout: retryConfirmTimeout) { return true }
            failure = "제출(CR) 전송 실패"
        }
        checkoutLog("\(failure) — 재시도 (\(attempt)/\(maxAttempts))")
    }
    return false
}

/// 읽히는 화면이 우리 pane인지 증명한다. 우리 tty에만 들어가는 난수를 하나 넣고 그것이
/// 화면에 **새로** 뜨는지 본다 — 뜨면 지금 읽히는 화면이 우리 pane이다. 다른 pane에 같은
/// 난수가 같은 순간 나타날 확률은 무시할 수 있다.
/// 표식은 여기서 지우지 않는다 — 성공·실패 경로가 갈리면 정리를 빠뜨리므로 호출자가
/// 한 자리에서 Ctrl+U로 지운다.
/// 폴링이 반영 확인보다 넉넉한 이유는 실패의 대부분이 "사용자가 잠깐 다른 탭을 보는 중"이고,
/// 그건 기다리면 풀리는 상태이기 때문이다.
///
/// **증명은 본문 타이핑 시점까지만 유효하다.** 증명 뒤 [Ctrl+U → 1초 → 타이핑 → 반영 확인]
/// 사이에 사용자가 탭을 옮기면, 본문 반영 확인은 다시 남의 화면을 읽게 된다. 그 창을 없애려면
/// CR 직전에 증명을 다시 태워야 하는데, 그때 입력창에는 본문이 들어 있어 표식을 덧붙이면
/// 제출에 섞인다. 표식을 본문 뒤에 붙였다 지우는 안도 검토했지만, **지웠음을 확인하는 화면
/// 읽기가 다시 같은 문제를 갖는다** — 남의 화면에서는 표식도 안 보이므로 "지워졌다"가 거짓
/// 양성이 되고, 그러면 `본문+표식`이 그대로 제출된다. 유실보다 나쁜 결과라 택하지 않았다.
///
/// 남는 창의 크기와 피해: 창은 위 구간(대략 1∼3초, 폴링 간격 0.4초). 그 안에서 피해가
/// 생기려면 ①사용자가 정확히 그때 탭을 옮기고 ②그 pane이 우리 프로브(입력 앞 24자)를
/// **새로** 얻고 ③claude가 우리 본문을 그리지 못하고 버려야 한다 — 셋이 모두 겹쳐야 한다.
/// 그때의 결과는 **빈 CR 한 번**이다: 바이트는 CR을 포함해 전부 우리 tty로만 가므로
/// (`sendKeys`의 `.warp` 갈래 → 헬퍼 TIOCSTI, 합성 키 입력·AX 쓰기 경로는 코드에 없다)
/// 남의 pane 내용이 제출될 수는 없고, 우리 pane의 입력창이 비어 있어 아무 일도 일어나지
/// 않는다. 앱 로그에는 전달된 것으로 남으므로 그 한 건이 유실된다.
private func proveOurPane(io: ClaudeSessionIO) -> Bool {
    guard let before = io.screenText() else { return false }
    let token = paneProofToken()
    guard send(token, io: io) else { return false }
    for _ in 0..<10 {
        io.wait(0.5)
        guard let after = io.screenText() else { continue }
        if screenReflectsNewInput(before: before, after: after, input: token) { return true }
    }
    return false
}

/// 화면에 뜬 것이 확인된 입력을 CR로 제출한다. 전송이 실패하면 재타이핑이 아니라 CR만 다시
/// 보낸다 — 실패로 보고됐어도 실제로는 전달됐을 수 있고, 그때 재타이핑하면 같은 입력이 두 번
/// 제출된다. 빈 입력창에 들어간 CR은 아무 일도 일으키지 않으므로(실측) 이미 제출된 뒤의
/// 재전송은 무해하다.
/// **첫 CR을 포함해** 매번 세션 동일성을 확인한다. 화면 반영을 확인한 직후라도 그 사이
/// 원래 claude가 끝나 같은 tty의 셸이나 새로 뜬 claude가 그 CR을 받으면, 사용자가 치고
/// 있던 것을 제출·실행시킨다. "반영 확인 직후라 안전하다"고 보던 때가 있었지만 화면 확인과
/// CR 사이에도 폴링 간격만큼의 틈이 있다 — 비용은 `ps`+`stty` 왕복 한 번이다.
private func submitConfirmedInput(io: ClaudeSessionIO, retryConfirmTimeout: TimeInterval) -> Bool {
    for attempt in 1...3 {
        if attempt > 1 { io.wait(0.4) }
        guard io.confirmSession(retryConfirmTimeout) else { return false }
        if send("\r", io: io) { return true }
    }
    return false
}

/// 스폰된 세션의 claude가 입력을 받을 수 있게 될 때까지 기다렸다가 입력을 전달한다.
/// 대기 조건은 [포그라운드 프로세스 = claude] + [tty가 raw mode]다 — 프로세스만 보면 셸이
/// exec한 직후의 canonical 구간을 통과해 첫 입력을 잃는다(`acceptingClaudePID` 참고).
/// 처음 준비된 claude의 PID를 고정해, 이후 입력이 같은 세션에만 가도록 한다.
/// 타임아웃 내에 claude가 준비되지 않으면 아무것도 보내지 않고 포기한다(로그만).
/// 기동 대기(기본 2분)와 입력별 재시도가 모두 블로킹이라 전체로는 수 분이 걸릴 수 있다 —
/// 요청 처리 큐가 아닌 백그라운드 큐에서 불러야 한다.
public func deliverClaudeInputs(
    _ inputs: [String], to handle: TerminalSessionHandle,
    pollInterval: TimeInterval = 1.0, timeout: TimeInterval = 120,
    betweenInputTimeout: TimeInterval = 15
) {
    guard !inputs.isEmpty else { return }
    // Warp 헬퍼는 pane에 남아 떠도는 프로세스가 되면 안 된다 — 어느 경로로 끝나든 종료시킨다
    defer {
        if case .warp(let socket) = handle { _ = warpHelperRequest(.bye, socket: socket) }
    }

    let ttyPath: String?
    switch handle {
    case .iterm(_, let tty):
        ttyPath = tty
    case .wezterm(let paneID, let cliPath, let socketPath):
        ttyPath = wezTermQueryTTY(cliPath: cliPath, socketPath: socketPath, paneID: paneID)
    case .warp(let socket):
        // 화면을 읽지 못하면 claude가 입력을 받았는지 확인할 방법이 없고, 확인 없이 CR을
        // 보내면 claude가 버린 입력이 "전달됨"으로 기록된 채 빈 줄이 제출된다(실측).
        // 그래서 Warp에서 손쉬운 사용 권한은 claude 입력을 예약한 버튼의 **필수 조건**이다 —
        // 명령 실행 자체와는 무관하므로 그 차이를 로그에 남긴다
        guard accessibilityIsTrusted() else {
            checkoutLog(
                "손쉬운 사용 권한이 없어 Warp에서 claude 입력 \(inputs.count)개를 전달하지 않음"
                    + " (명령은 새 탭에서 실행됨) — 앱 설정 창에서 허용하세요"
            )
            return
        }
        ttyPath = warpHelperTTY(socket: socket)
    case .none:
        checkoutLog("claude 입력 전달 불가 — 세션 핸들 없음")
        return
    }
    guard let ttyPath, ttyPath.hasPrefix("/dev/") else {
        checkoutLog("claude 입력 전달 불가 — 세션 tty를 알 수 없음")
        return
    }
    let ttyName = String(ttyPath.dropFirst("/dev/".count))

    guard let claudePID = waitUntilClaudeAcceptsInput(
        ttyName: ttyName, ttyPath: ttyPath, pollInterval: pollInterval, timeout: timeout
    ) else {
        checkoutLog("\(Int(timeout))초 내에 claude가 입력을 받을 상태가 되지 않아 입력 \(inputs.count)개를 보내지 않음")
        return
    }

    // 우리가 실제로 바이트를 내보냈는지 — 정리(Ctrl+U)를 보낼지 가르는 조건이다.
    // 한 바이트도 못 보냈다면 입력창에 있는 것은 사용자 초안뿐이라 지우면 안 된다
    var weSentSomething = false
    let io = ClaudeSessionIO(
        sendKeys: {
            let sent = sendKeys($0, to: handle, expectedPID: claudePID)
            if sent { weSentSomething = true }
            return sent
        },
        screenText: { screenText(of: handle) },
        confirmSession: { limit in
            waitUntilClaudeAcceptsInput(
                ttyName: ttyName, ttyPath: ttyPath,
                pollInterval: pollInterval, timeout: limit, expecting: claudePID
            ) != nil
        },
        // 전송 직전 확인은 기다리지 않는다 — 한 번 재서 지금도 그 claude인지만 본다
        sessionIsUnchanged: {
            probeAcceptingClaudePID(ttyName: ttyName, ttyPath: ttyPath) == claudePID
        },
        // 권한이 회수되면 화면 확인이 불가능해진다 — 그때는 새로 치지 않고 정리만 한다
        canConfirmScreen: { handle.screenNeedsPaneProof ? accessibilityIsTrusted() : true },
        // Warp만 true — 접근성으로 읽히는 것은 "포커스된 pane"이라 우리 것이라는 보장이 없다
        screenNeedsPaneProof: handle.screenNeedsPaneProof
    )
    let submitted = submitClaudeInputs(inputs, io: io, betweenInputTimeout: betweenInputTimeout)
    checkoutLog("claude(pid \(claudePID)) 입력 \(inputs.count)개 중 \(submitted)개 전달")
    // 전달 도중 권한이 회수되면 화면 확인이 멈춰 CR은 막히지만, 그때까지 친 텍스트는 입력창에
    // 남는다. 우리 tty로만 가는 Ctrl+U를 한 번 보내 그 조각을 지우고 끝낸다
    if case .warp = handle, !accessibilityIsTrusted() {
        // 정리도 같은 문을 지난다 — 세션이 바뀐 뒤라면 남의 입력창을 지우게 된다.
        // 우리가 아무것도 못 보냈으면 지울 우리 조각도 없다(사용자 초안만 지우게 된다)
        if clearAbandonedInput(io: io, weSentSomething: weSentSomething) {
            checkoutLog("전달 도중 손쉬운 사용 권한이 사라짐 — claude 입력창을 비우고 중단")
        } else {
            checkoutLog("손쉬운 사용 권한이 없어 전달하지 못함 — 우리가 보낸 것이 없어 입력창은 건드리지 않음")
        }
    }
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
private func sendKeys(_ text: String, to handle: TerminalSessionHandle, expectedPID: Int) -> Bool {
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
            checkoutLog("iTerm 세션이 닫혀 claude 입력 전달 중단")
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
    case .warp(let socket):
        // 헬퍼가 우리 pane의 tty 입력 큐에 바이트를 직접 넣는다(TIOCSTI) — 포커스와 무관하고
        // 다른 pane·다른 앱으로 샐 수 없다. 합성 키 입력을 쓰지 않는 이유가 이것이다.
        // 기대 PID를 함께 보내 헬퍼가 "지금 이 tty를 읽을 프로세스"까지 확인하게 한다 —
        // 우리는 보내기 전만 볼 수 있고, 큐에 넣은 뒤 누가 읽는지는 거기서만 정해진다
        guard case .ok? = warpHelperRequest(
            .inject(expectedPID: Int32(expectedPID), bytes: Data(text.utf8)), socket: socket
        ) else { return false }
        return true
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
    case .warp:
        // 접근성으로 읽히는 것은 "Warp에서 포커스된 pane"이라 우리 pane이라는 보장이 없다.
        // 그래도 안전한 이유는 입력이 이 경로로 가지 않기 때문이다(`warpScreenText` 참고) —
        // 다른 pane을 읽으면 반영 확인이 실패하고, 그때는 tty 큐 신호로 넘어간다
        return warpScreenText()
    case .none:
        return nil
    }
}

/// 헬퍼가 소켓을 열고 자기 tty를 알려 줄 때까지 기다린다. pane이 열리고 셸이 헬퍼를
/// 실행하기까지 시간이 걸리므로(실측 0.7초 근방) 폴링한다. 끝내 못 뜨면 nil —
/// 명령은 이미 돌고 있으니 claude 입력만 포기한다.
private func warpHelperTTY(socket: String, timeout: TimeInterval = 20) -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while true {
        if case .ok(let tty)? = warpHelperRequest(.tty, socket: socket), tty.hasPrefix("/dev/") {
            return tty
        }
        if Date() >= deadline {
            checkoutLog("Warp 주입 헬퍼가 \(Int(timeout))초 안에 뜨지 않음 — claude 입력 포기")
            return nil
        }
        Thread.sleep(forTimeInterval: 0.2)
    }
}
