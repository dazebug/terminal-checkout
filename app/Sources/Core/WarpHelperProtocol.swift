import Foundation

// Warp pane 안에서 도는 주입 헬퍼와 앱 사이의 프로토콜.
//
// 왜 pane 안에 프로세스가 필요한가: BSD 커널은 비root의 `TIOCSTI`를 호출 프로세스의 제어
// 터미널로만 허용한다(`isctty`). 앱은 pane의 세션 밖이라 pane tty에 바이트를 넣을 수 없다.
// 그래서 Tab Config가 여는 pane에서 헬퍼를 먼저 띄우고, 앱은 그 소켓의 클라이언트가 된다.
//
// 줄 단위 ASCII 프로토콜이다. 주입할 바이트만 base64로 싣는다 — 제출(CR)과 입력창
// 클리어(Ctrl+U)가 제어문자라 줄 기반 프로토콜에 날것으로 실을 수 없기 때문이다.

public enum WarpHelperRequest: Equatable {
    /// 헬퍼가 붙어 있는 pane의 tty 경로. 앱은 이 값으로 게이트 ①②③을 태운다
    case tty
    /// 그 바이트들을 tty 입력 큐에 넣는다. `expectedPID`는 **그 바이트를 읽을 것으로 기대하는**
    /// 프로세스다 — 헬퍼가 주입 직전에 포그라운드와 맞춰 보고 어긋나면 넣지 않는다.
    /// 요청마다 싣는 이유는 상태로 두면 "설정해 두고 잊는" 갈래가 생기기 때문이다.
    case inject(expectedPID: Int32, bytes: Data)
    /// 전달이 끝났으니 종료해라 — 헬퍼가 pane에 남아 떠도는 것을 막는 정상 경로다
    case bye
}

/// tty 입력 큐에는 상한(TTYHOG)이 있고 넘치면 커널이 조용히 버린다. 그래서 한 번에 넣는 양을
/// 제한하고, 넘치는 만큼은 소비를 기다렸다 이어 넣는다 — 상한을 넘는 입력을 통째로 거절하면
/// 512바이트가 넘는 claude 프롬프트가 항상 실패한다.
/// 바이트 단위로 자르는 것은 안전하다: tty 입력 큐는 바이트 스트림이라 멀티바이트 문자가
/// 조각나 들어가도 순서대로 이어지면 claude가 온전히 받는다(한글 입력으로 실측).
///
/// **큐에 한 바이트라도 남아 있으면 넣지 않는다.** 여유가 있다고 이어 넣으면 앞 조각의 tail이
/// 큐에 남은 채 다음이 쌓이는데, claude가 앞부분만 읽어 화면에 그리면 앱의 반영 확인은
/// 통과한다(프로브는 앞 24자만 본다 — `claudeInputProbe`). 그 뒤 claude가 끝나면 큐에 남은
/// tail을 **셸이 읽어 명령으로 실행한다.** 우리가 만든 바이트가 사용자의 셸에서 실행되는
/// 갈래가 여기였다. 빈 큐에만 넣으면 조각마다 claude가 읽은 것을 확인하고 다음으로 넘어간다.
public func warpInjectChunkSize(pending: Int, remaining: Int, limit: Int) -> Int {
    guard pending == 0 else { return 0 }
    return max(0, min(remaining, limit))
}

/// 헬퍼가 요청 **하나**에 쓰는 시간의 상한 — 큐가 비기를 기다리고, 넣은 바이트가 읽히는지
/// 지켜보는 전부가 이 안에 들어간다.
public let warpHelperWorkBudget: TimeInterval = 2

/// 앱이 응답을 기다리는 시간. 헬퍼의 예산보다 **확실히 길어야 한다** — 앱이 먼저 포기하고
/// 재시도하는 동안 이전 요청의 주입이 계속 돌면, 그 바이트가 재시도분·사용자 입력과 섞인다.
/// 두 값을 따로 적으면 한쪽만 고쳐져 다시 갈리므로 한 곳에서 유도한다.
public let warpHelperRequestTimeout: TimeInterval = warpHelperWorkBudget * 3

/// 지금 이 tty의 입력을 읽을 프로세스가 우리가 겨눈 claude인가.
///
/// `TIOCSTI`는 호출자의 controlling session인지만 보고 **큐에 넣은 바이트를 누가 읽을지는
/// 정하지 않는다**. claude가 죽어 셸이 포그라운드가 되면 남은 CR을 셸이 읽어 사용자가 치던
/// 초안을 실행한다 — 그래서 "보내기 전"만 보는 앱 쪽 게이트로는 부족하고, 주입과 같은
/// 프로세스에서 포그라운드를 확인해야 창이 좁아진다.
///
/// pid가 아니라 **프로세스 그룹**으로 비교한다: 앱이 고르는 claude pid가 그룹 리더가 아닌
/// 경우가 있다(사용자의 claude pane 13개 중 3개에서 `pid != pgid` 실측).
/// 조회가 실패하면 -1이므로 "알 수 없으면 넣지 않는다"가 된다.
public func warpForegroundIsExpected(foregroundPGID: Int32, expectedPGID: Int32) -> Bool {
    foregroundPGID > 0 && expectedPGID > 0 && foregroundPGID == expectedPGID
}

/// 헬퍼가 더 살아 있으면 안 되는 이유. 대기 루프와 **요청 처리 경로**가 같은 판정을 쓴다 —
/// 상한 검사가 대기 루프에만 있으면, 연결을 물고 계속 요청하는 쪽이 유휴·수명 상한을
/// 통째로 우회한다.
public enum WarpHelperStop: Equatable {
    /// tty가 우리 세션의 제어 터미널이 아니게 됐다 (pane이 닫히고 번호가 재사용됐다)
    case ttySessionChanged
    case idle
    case lifetime

    public var description: String {
        switch self {
        case .ttySessionChanged: return "tty session changed"
        case .idle: return "idle timeout"
        case .lifetime: return "lifetime limit"
        }
    }
}

/// tty 동일성을 먼저 본다 — 상한에 여유가 있어도 남의 tty에는 한 바이트도 넣으면 안 된다.
public func warpHelperStopReason(
    ttySessionMatches: Bool,
    idleSeconds: TimeInterval,
    aliveSeconds: TimeInterval,
    idleLimit: TimeInterval,
    lifetimeLimit: TimeInterval
) -> WarpHelperStop? {
    if !ttySessionMatches { return .ttySessionChanged }
    if idleSeconds > idleLimit { return .idle }
    if aliveSeconds > lifetimeLimit { return .lifetime }
    return nil
}

public enum WarpHelperResponse: Equatable {
    case ok(String)
    case err(String)
}

public func encodeWarpHelperRequest(_ request: WarpHelperRequest) -> String {
    switch request {
    case .tty: return "tty"
    case .bye: return "bye"
    case .inject(let pid, let bytes): return "inject \(pid) " + bytes.base64EncodedString()
    }
}

/// 헬퍼가 받은 줄을 요청으로 읽는다. 해석되지 않으면 nil — 헬퍼는 그때 `err`로 답한다.
public func parseWarpHelperRequest(_ line: String) -> WarpHelperRequest? {
    let text = trimmingLineEnding(line)
    switch text {
    case "tty": return .tty
    case "bye": return .bye
    default: break
    }
    // 빈 payload(`inject <pid> `)도 유효한 요청이라 빈 조각을 버리면 안 된다
    let parts = text.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
    // pid는 양수만 받는다 — `getpgid(0)`은 "호출자의 그룹"이라, 헬퍼 자신이 포그라운드인
    // 비정상 상황에서 0이 "기대 독자가 맞다"로 통과해 버린다. fail-closed로 둔다
    guard parts.count == 3, parts[0] == "inject",
          let pid = Int32(parts[1]), pid > 0,
          let bytes = Data(base64Encoded: String(parts[2]))
    else { return nil }
    return .inject(expectedPID: pid, bytes: bytes)
}

public func encodeWarpHelperResponse(_ response: WarpHelperResponse) -> String {
    switch response {
    case .ok(let detail): return detail.isEmpty ? "ok" : "ok " + detail
    case .err(let reason): return reason.isEmpty ? "err" : "err " + reason
    }
}

/// 접두사 없는 줄은 nil이다 — 그것을 성공으로 읽으면 헬퍼의 실패가 앱에는 성공으로 보인다.
public func parseWarpHelperResponse(_ line: String) -> WarpHelperResponse? {
    let text = trimmingLineEnding(line)
    if text == "ok" { return .ok("") }
    if text == "err" { return .err("") }
    let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2 else { return nil }
    switch parts[0] {
    case "ok": return .ok(String(parts[1]))
    case "err": return .err(String(parts[1]))
    default: return nil
    }
}

private func trimmingLineEnding(_ line: String) -> String {
    var text = line
    while let last = text.last, last == "\n" || last == "\r" { text.removeLast() }
    return text
}

/// 소켓 read()는 줄 경계를 지켜 주지 않는다 — 한 번에 여러 줄이 오기도, 한 줄이 쪼개져
/// 오기도 한다. 받은 조각을 모아 완성된 줄만 꺼내 준다.
public struct LineBuffer {
    /// 줄바꿈 없이 계속 보내는 상대에게 메모리를 무한정 내주지 않기 위한 상한.
    /// 주입 payload는 base64라 원본의 4/3 크기다
    public static let defaultLimit = 256 * 1024

    private var data = Data()
    private let limit: Int
    /// 상한을 넘긴 뒤에는 아무것도 돌려주지 않는다 — 호출자가 연결을 끊게 한다
    public private(set) var isOverflowed = false

    public init(limit: Int = LineBuffer.defaultLimit) {
        self.limit = limit
    }

    public mutating func append(_ chunk: Data) {
        guard !isOverflowed else { return }
        data.append(chunk)
        // 완성된 줄과 아직 줄바꿈이 오지 않은 꼬리에 **같은** 상한을 건다. 꼬리만 보면
        // 상한을 넘긴 줄이 마지막 줄바꿈과 함께 도착할 때 그대로 통과한다
        var start = data.startIndex
        while let newline = data[start...].firstIndex(of: 0x0A) {
            if data.distance(from: start, to: newline) > limit { return overflow() }
            start = data.index(after: newline)
        }
        if data.distance(from: start, to: data.endIndex) > limit { return overflow() }
    }

    private mutating func overflow() {
        isOverflowed = true
        data.removeAll()
    }

    public mutating func nextLine() -> String? {
        guard !isOverflowed, let newline = data.firstIndex(of: 0x0A) else { return nil }
        let line = data[data.startIndex..<newline]
        data = Data(data[data.index(after: newline)...])
        return String(decoding: line, as: UTF8.self)
    }
}
