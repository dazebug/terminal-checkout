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
    /// tty 입력 큐에 아직 읽히지 않은 바이트 수 (FIONREAD)
    case pending
    /// 그 바이트들을 tty 입력 큐에 넣는다
    case inject(Data)
    /// 전달이 끝났으니 종료해라 — 헬퍼가 pane에 남아 떠도는 것을 막는 정상 경로다
    case bye
}

public enum WarpHelperResponse: Equatable {
    case ok(String)
    case err(String)
}

public func encodeWarpHelperRequest(_ request: WarpHelperRequest) -> String {
    switch request {
    case .tty: return "tty"
    case .pending: return "pending"
    case .bye: return "bye"
    case .inject(let bytes): return "inject " + bytes.base64EncodedString()
    }
}

/// 헬퍼가 받은 줄을 요청으로 읽는다. 해석되지 않으면 nil — 헬퍼는 그때 `err`로 답한다.
public func parseWarpHelperRequest(_ line: String) -> WarpHelperRequest? {
    let text = trimmingLineEnding(line)
    switch text {
    case "tty": return .tty
    case "pending": return .pending
    case "bye": return .bye
    default: break
    }
    // 빈 payload(`inject `)도 유효한 요청이라 빈 조각을 버리면 안 된다
    let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false)
    guard parts.count == 2, parts[0] == "inject",
          let bytes = Data(base64Encoded: String(parts[1]))
    else { return nil }
    return .inject(bytes)
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
        let tailStart = data.lastIndex(of: 0x0A).map { data.index(after: $0) } ?? data.startIndex
        if data.distance(from: tailStart, to: data.endIndex) > limit {
            isOverflowed = true
            data.removeAll()
        }
    }

    public mutating func nextLine() -> String? {
        guard !isOverflowed, let newline = data.firstIndex(of: 0x0A) else { return nil }
        let line = data[data.startIndex..<newline]
        data = Data(data[data.index(after: newline)...])
        return String(decoding: line, as: UTF8.self)
    }
}
