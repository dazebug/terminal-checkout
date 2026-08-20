import Core
import Darwin
import Foundation

// Warp pane 주입 헬퍼.
//
// Warp에는 pane에 텍스트를 보내는 수단이 없다 — AppleScript 미지원, warpctrl은 Stable에서
// 기본 비활성, `wezterm cli send-text` 같은 CLI도 없다(모두 실측). 남은 경로는 pane의 tty
// 입력 큐에 바이트를 직접 넣는 `TIOCSTI`인데, BSD 커널은 비root에게 **호출 프로세스의 제어
// 터미널**로만 이것을 허용한다(`isctty`). 그래서 앱이 아니라 pane 안에서 도는 이 프로세스가
// 주입을 맡고, 앱은 유닉스 소켓의 클라이언트가 된다.
//
// 절대 하지 않는 것 두 가지:
//   - tty에서 읽지 않는다 — 사용자가 그 pane에 친 키를 훔치게 된다
//   - tty에 쓰지 않는다 — claude가 그리는 화면을 망친다
// 로그는 os_log로만 남긴다(`checkoutLog`).

/// `_IOW('t', 114, char)` — tty 입력 큐에 바이트 하나를 밀어 넣는다.
/// `_IOR('f', 127, int)` — 아직 읽히지 않은 바이트 수.
/// 둘 다 C 매크로라 Swift로 넘어오지 않아 값을 직접 적는다.
private let requestTIOCSTI: UInt = 0x8001_7472
private let requestFIONREAD: UInt = 0x4004_667F

/// 한 번에 큐에 넣어 두는 최대 바이트. tty 입력 큐 상한(TTYHOG, 기본 1024)보다 넉넉히 낮게
/// 잡아 두고, 넘치는 분량은 소비를 기다렸다 이어 넣는다.
private let injectQueueLimit = 512
/// 한 요청으로 받아 주는 최대 바이트. claude 입력은 한 줄이라 이보다 훨씬 짧다 —
/// 상한이 없으면 보내는 쪽이 수십만 번의 ioctl을 시킬 수 있다.
private let injectMaxBytes = 8 * 1024
/// 수신 버퍼 상한. base64는 원본의 4/3이라 위 상한의 두 배면 넉넉하다.
private let requestLineLimit = 16 * 1024
/// 조각을 밀어 넣는 도중 포그라운드를 다시 보는 간격(바이트). 확인 없이 도는 구간이
/// "claude가 끝났을 때 셸로 새는 최대 바이트"라 짧을수록 좋지만, `tcgetpgrp`+`getpgid`가
/// 바이트마다 두 번씩 도는 것도 낭비다 — 한 줄 입력에서 유출이 한눈에 들어오는 크기로 잡는다.
private let foregroundRecheckStride = 16

// ─────────────────────────────────────────────────────────────────────────────
// 신뢰 경계 선언 (이 기능 전체에 적용된다)
//
// **경계는 uid다.** 같은 uid로 도는 프로세스는 신뢰하고, 다른 uid는 막는다. 이유는 두 가지다:
// macOS 자신이 이 부류(유닉스 소켓·사용자 홈의 파일)에 uid를 경계로 쓰고, 같은 uid 안에서는
// 숨길 자리가 없다 — argv·환경변수·0600 파일을 모두 읽을 수 있고, 이 소켓 경로는 Tab Config
// 파일과 pane 화면에 그대로 보인다. 그래서 `getpeereid`의 uid 비교는 **인증이 아니라 경계
// 확인**이다.
//
// 이 경계 안에서 가능한 것(막지 않는다):
//  1. 살아 있는 헬퍼 소켓에 임의의 `inject` — 같은 uid 프로세스는 그 pane의 claude에 원하는
//     바이트를 넣을 수 있다. 좁히는 축은 수명뿐이다: 전달이 끝나면 `bye`로 즉시 죽고,
//     그러지 못하면 유휴 180초·수명 900초에 걸린다
//  2. 경로 기반 `unlink`의 TOCTOU — 소켓 회수·Tab Config 회수·예약 삭제·`uninstall.sh`.
//     `lstat`/`fstat`과 inode 재확인으로 창을 마이크로초로 줄였지만, macOS에 `funlinkat`이
//     없어 마지막 한 걸음은 경로다. 우리 난수 이름을 미리 알아야 끼워 넣을 수 있다
//  3. 헤더를 확인한 뒤 내용을 바꿔치기 — 판정은 fd로 하지만 삭제는 경로다(2와 같은 창)
//  4. 헬퍼 소켓 경로에 파일을 미리 놓아 `bind`를 실패시키기(전달만 무산되는 DoS)
//
// 경계와 **무관한** 잔여(악의가 없어도 남는 것)는 따로다 — 섞지 않는다:
//  - pane 증명이 본문 타이핑 시점까지만 유효한 창 (`proveOurPane` 주석)
//  - 큐에 넣은 CR을 셸이 먼저 읽어 가는 경합 (`watchUntilRead` 주석)
//  - Tab Config 20초 예약 삭제가 "Warp가 읽었다"를 보장하지 못하는 것 (`runInWarp` 주석)
// ─────────────────────────────────────────────────────────────────────────────
//
/// `bye`가 오지 못한 경우의 유휴 상한. 정상 전달에서 가장 긴 침묵은 앱이 claude 기동을
/// 기다리는 구간(`deliverClaudeInputs`의 기본 120초)이라 그보다 여유만 두면 된다.
private let idleTimeout: TimeInterval = 180
/// 전체 수명 상한. 최악의 정상 전달(기동 대기 120초 + 입력 5개 × 재시도)이 400초 안쪽이라
/// 그 두 배 남짓으로 잡는다 — 여기에 걸린다는 것은 이미 비정상이다.
private let maxLifetime: TimeInterval = 900

private let serveFlag = "--serve"

/// 시그널 핸들러는 async-signal-safe한 것만 부를 수 있다 — Swift 문자열을 만들 수 없으므로
/// 경로를 C 문자열로 미리 떠 둔다. `lstat`·`unlink`는 둘 다 안전 목록에 있다.
private var socketPathForSignal: UnsafeMutablePointer<CChar>?

/// 우리 소켓일 때만 지운다. 경로만 보고 지우면, 그 사이 누가 같은 경로에 놓은 파일을
/// 없앤다 — 정상 경로에서는 겹칠 일이 없지만 삭제는 되돌릴 수 없다.
private func unlinkIfSocket(_ path: UnsafePointer<CChar>) {
    var info = stat()
    guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFSOCK else { return }
    unlink(path)
}

/// SIGTERM(앱 재설치·`pkill`)·SIGINT·SIGHUP에서 소켓 파일을 지우고 나간다.
/// SIGKILL은 잡을 수 없으므로 그 몫은 앱이 다음 실행에서 회수한다
/// (`reclaimDeadWarpHelperSockets`).
private func installSocketCleanupOnSignals(path: String) {
    socketPathForSignal = strdup(path)
    for number in [SIGTERM, SIGINT, SIGHUP] {
        signal(number) { _ in
            if let path = socketPathForSignal { unlinkIfSocket(path) }
            _exit(0)
        }
    }
}

private func fail(_ message: String) -> Never {
    checkoutLog("Warp 주입 헬퍼 종료: \(message)")
    exit(1)
}

private func lastErrnoName() -> String { String(cString: strerror(errno)) }

/// tty 입력 큐에 남은 바이트 수. 조회 실패면 nil.
private func ttyPendingBytes(_ fd: Int32) -> Int? {
    var pending: Int32 = 0
    let result = withUnsafeMutablePointer(to: &pending) {
        ioctl(fd, requestFIONREAD, UnsafeMutableRawPointer($0))
    }
    return result == 0 ? Int(pending) : nil
}

/// 헬퍼가 사는 동안의 상태. 정지 판정을 여기 하나로 모아 **대기 루프와 요청 처리 경로가
/// 같은 기준**을 쓰게 한다 — 상한 검사가 대기 루프에만 있으면 연결을 물고 계속 요청하는
/// 쪽이 유휴·수명 상한을 통째로 우회한다.
private final class HelperState {
    let ttyFD: Int32
    let ttyPath: String
    private let startedAt = Date()
    private var lastActivity = Date()

    init(ttyFD: Int32, ttyPath: String) {
        self.ttyFD = ttyFD
        self.ttyPath = ttyPath
    }

    func touch() { lastActivity = Date() }

    func stopReason() -> WarpHelperStop? {
        warpHelperStopReason(
            // tty 번호는 재사용된다 — pane이 닫힌 뒤 같은 번호를 새 세션이 차지하면
            // 세션 id가 달라진다. 이 비교가 "남의 tty에 붙은 헬퍼"를 막는 유일한 신호다
            ttySessionMatches: tcgetsid(ttyFD) == getsid(0),
            idleSeconds: Date().timeIntervalSince(lastActivity),
            aliveSeconds: Date().timeIntervalSince(startedAt),
            idleLimit: idleTimeout,
            lifetimeLimit: maxLifetime
        )
    }
}

/// 큐 여유만큼 나눠 넣는다. 통째로 거절하면 512바이트가 넘는 claude 프롬프트가 항상
/// 실패하는데, 그 길이는 사용자가 직접 쓰는 입력에서 드물지 않다.
/// 바이트 단위로 잘라도 되는 이유는 tty 입력 큐가 바이트 스트림이기 때문이다 — 멀티바이트
/// 문자가 조각나 들어가도 순서대로 이어지면 claude가 온전히 받는다(한글 입력으로 실측).
private func inject(_ bytes: Data, expectedPID: Int32, state: HelperState) -> WarpHelperResponse {
    let ttyFD = state.ttyFD
    guard !bytes.isEmpty else { return .ok("0") }
    guard bytes.count <= injectMaxBytes else {
        return .err("payload too large (\(bytes.count) > \(injectMaxBytes))")
    }
    let all = [UInt8](bytes)
    var sent = 0
    // 이 요청에 쓸 수 있는 시간 전부 — 큐가 비기를 기다리는 것과 읽히는지 지켜보는 것을
    // 합쳐 앱의 응답 대기보다 확실히 짧아야 한다(`warpHelperWorkBudget` 참고)
    let deadline = Date().addingTimeInterval(warpHelperWorkBudget)
    while sent < all.count {
        // 조각마다 다시 본다. 분할 주입은 큐가 빌 때까지 예산만큼 기다리는데, 그 사이
        // 우리 pane이 닫히고 같은 tty 번호를 새 세션이 차지하면 남은 조각이 남의 tty로 들어간다
        if let stop = state.stopReason() { return .err(stop.description) }
        // 넣기 직전에 "지금 이 tty를 읽을 프로세스"를 확인한다. 앱의 게이트는 요청을 보내기
        // 전의 상태만 보므로, 그 사이 claude가 끝났으면 우리 바이트를 셸이 읽는다.
        // syscall 두 번이라 `ps` 왕복보다 싸고, 주입과 같은 프로세스라 창이 마이크로초다
        guard warpForegroundIsExpected(
            foregroundPGID: tcgetpgrp(ttyFD), expectedPGID: getpgid(expectedPID)
        ) else {
            return .err("foreground is not the expected reader")
        }
        guard let pending = ttyPendingBytes(ttyFD) else { return .err(lastErrnoName()) }
        let chunk = warpInjectChunkSize(pending: pending, remaining: all.count - sent, limit: injectQueueLimit)
        guard chunk > 0 else {
            // claude가 아직 읽어 가지 않았다. 여기서 더 넣으면 커널이 조용히 버린다
            guard Date() < deadline else {
                return .err("input queue not drained in time (\(pending) pending)")
            }
            usleep(50_000)
            continue
        }
        for index in sent..<(sent + chunk) {
            // 조각 전체를 한 번의 확인으로 밀어 넣으면, 그 사이 claude가 끝났을 때 남은
            // 바이트가 통째로 셸로 간다. 512바이트 조각이면 확인 없이 도는 구간이 그만큼
            // 길어지므로 중간에도 다시 본다 — 유출 상한을 이 간격으로 묶는다
            if index > sent, (index - sent) % foregroundRecheckStride == 0 {
                guard warpForegroundIsExpected(
                    foregroundPGID: tcgetpgrp(ttyFD), expectedPGID: getpgid(expectedPID)
                ) else {
                    return .err("foreground changed after \(index - sent) bytes")
                }
            }
            var value = CChar(bitPattern: all[index])
            let result = withUnsafeMutablePointer(to: &value) {
                ioctl(ttyFD, requestTIOCSTI, UnsafeMutableRawPointer($0))
            }
            // 중간에 실패하면 앞부분만 들어간 상태다 — 몇 바이트까지 갔는지 함께 알린다.
            // 앱은 재시도 전에 Ctrl+U로 입력창을 비우므로 남은 조각은 정리된다
            guard result == 0 else { return .err("\(lastErrnoName()) after \(index)") }
        }
        sent += chunk
    }
    return watchUntilRead(expectedPID: expectedPID, state: state, injected: sent, deadline: deadline)
}

/// 넣은 바이트가 읽힐 때까지 잠깐 지켜본다. 아직 큐에 남아 있는데 포그라운드가 우리가 겨눈
/// claude에서 벗어났으면 `tcflush`로 입력 큐를 버린다.
///
/// **이것은 창을 닫지 못한다 — 좁힐 뿐이다.** 실측: 포그라운드가 죽는 순간 셸이 이미
/// `read()`에 걸려 있으면 우리 폴링(5ms)보다 먼저 읽어 간다(프로브에서 `SHELL_READ=b'\r'`).
/// 그래도 두는 이유는 **셸이 아직 읽지 않은 경우에만 동작**하기 때문이다 — 그 경우가 바로
/// 아직 막을 수 있는 경우다. 큐에 우리 본문이 남아 있다가 셸의 줄 버퍼에 들어가면 사용자가
/// 나중에 누른 Enter가 그것을 셸 명령으로 실행한다(`!…`로 시작하는 입력이면 특히 나쁘다).
/// 사용자가 그 순간 친 키가 함께 버려질 수 있지만, 버려지는 상황은 "셸이 아직 아무것도 읽지
/// 않은" 순간이라 잃는 것은 방금 친 몇 글자다.
///
/// **시간 안에 안 읽혔으면 실패다(fail-closed).** 한때 "포그라운드는 그대로니 claude가 느린
/// 것"이라며 성공으로 돌려줬는데, 그러면 큐에 남은 tail을 앱이 모른 채 CR을 얹는다 —
/// 앱의 화면 확인은 앞 24자만 보므로 claude가 앞부분만 읽어도 통과한다. 그 뒤 claude가
/// 끝나면 셸이 [tail + CR]을 읽어 **명령으로 실행한다.** 성공은 큐가 빈 것을 본 경우뿐이다.
///
/// `tcflush`는 **우리 바이트만 남아 있을 때만** 한다. 큐에 우리가 넣은 것보다 많이 들어 있으면
/// 사용자가 그 사이 친 키가 섞인 것이라, 버리면 우리가 막으려던 피해(사용자 입력 손실)를
/// 우리가 일으킨다. 그때는 버리지 않고 실패만 알린다.
///
/// 여기서 보는 `FIONREAD`는 "아직 안 읽혔다"는 **부정** 신호다. 라운드 1에서 없앤 것은
/// "읽혔으니 claude가 그렸을 것"이라는 **긍정** 추론이고, 그쪽은 되살리지 않는다 —
/// 전달 성공 판정은 여전히 화면 반영 확인이 한다. 이것은 그 앞에 얹는 필요조건이다.
private func watchUntilRead(
    expectedPID: Int32, state: HelperState, injected: Int, deadline: Date
) -> WarpHelperResponse {
    // 넣은 직후부터 큐는 **줄기만 해야 한다**. 한 번이라도 늘면 그 사이 사용자가 친 키가
    // 섞인 것이다 — `FIONREAD`는 총량만 주므로 출처를 가릴 다른 방법이 없다.
    // 총량 비교(`pending <= injected`)로는 못 가른다: 우리 42바이트가 모두 소비된 뒤
    // 사용자가 한 글자를 치면 `1 <= 42`라 사용자 것을 버리게 된다(검증자 재현).
    var lowWaterMark = Int.max
    var sawForeignBytes = false
    while true {
        guard let pending = ttyPendingBytes(state.ttyFD) else { return .err(lastErrnoName()) }
        if pending > lowWaterMark { sawForeignBytes = true }
        lowWaterMark = min(lowWaterMark, pending)

        let readerIsOurs = warpForegroundIsExpected(
            foregroundPGID: tcgetpgrp(state.ttyFD), expectedPGID: getpgid(expectedPID)
        )
        if pending == 0 {
            // 큐는 비었지만 **누가 가져갔는지**를 함께 봐야 한다. 그 사이 claude가 끝나
            // 포그라운드가 셸이면 우리 tail을 셸이 읽어 간 것이다 — 성공으로 답하면 앱이
            // 그 위에 CR을 얹고, 사용자의 다음 Enter가 그 줄을 실행한다
            guard readerIsOurs else {
                checkoutLog("Warp 주입 헬퍼: 큐는 비었으나 겨눈 claude가 아닌 쪽이 읽어 감")
                return .err("queue drained by a different reader")
            }
            return .ok(String(injected))
        }
        if !readerIsOurs {
            guard !sawForeignBytes else {
                checkoutLog("Warp 주입 헬퍼: 겨눈 claude가 사라졌으나 큐(\(pending)바이트)에 사용자 입력이 섞여 버리지 않음")
                return .err("expected reader gone; queue holds user input")
            }
            tcflush(state.ttyFD, TCIFLUSH)
            checkoutLog("Warp 주입 헬퍼: 겨눈 claude가 사라져 읽히지 않은 우리 입력 \(pending)바이트를 버림")
            return .err("expected reader gone; input queue flushed")
        }
        guard Date() < deadline else {
            return .err("injected bytes not read in time (\(pending) pending)")
        }
        usleep(5_000)
    }
}

/// 연결 하나를 끝까지 처리한다. `bye`를 받았거나 상한에 걸렸으면 true(헬퍼 종료).
private func serve(client: Int32, state: HelperState) -> Bool {
    var tv = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var buffer = LineBuffer(limit: requestLineLimit)
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        while let line = buffer.nextLine() {
            var finished = false
            let response: WarpHelperResponse
            // 요청마다 상한과 tty 동일성을 먼저 본다 — 연결을 물고 있는 쪽이 대기 루프의
            // 검사를 건너뛰게 두면 상한이 없는 것과 같다
            if let stop = state.stopReason() {
                _ = writeAll(fd: client, data: Data((encodeWarpHelperResponse(.err(stop.description)) + "\n").utf8))
                checkoutLog("Warp 주입 헬퍼 종료: \(stop.description)")
                return true
            }
            state.touch()
            switch parseWarpHelperRequest(line) {
            case .tty:
                response = .ok(state.ttyPath)
            case .inject(let expectedPID, let bytes):
                response = inject(bytes, expectedPID: expectedPID, state: state)
            case .bye:
                response = .ok("")
                finished = true
            case nil:
                response = .err("unknown request")
            }
            let payload = Data((encodeWarpHelperResponse(response) + "\n").utf8)
            guard writeAll(fd: client, data: payload) else { return finished }
            if finished { return true }
        }
        if buffer.isOverflowed { return false }
        let n = read(client, &chunk, chunk.count)
        if n > 0 {
            buffer.append(Data(chunk[0..<n]))
        } else if n < 0 && errno == EINTR {
            continue
        } else {
            return false
        }
    }
}

/// 셸이 물려준 표준 입출력에서 pane tty의 이름을 읽는다.
/// 자식이 `/dev/tty`를 여는 방법은 쓸 수 없다 — fd는 맞지만 `ttyname()`이 `/dev/tty`를
/// 돌려주고(실측), 앱의 게이트는 `ps -t ttysNNN`·`stty -f /dev/ttysNNN`이라 실제 이름이 필요하다.
private func resolvePaneTTYName() -> String? {
    for fd in Int32(0)...2 {
        guard isatty(fd) == 1, let raw = ttyname(fd) else { continue }
        let name = String(cString: raw)
        if name.hasPrefix("/dev/"), name != "/dev/tty" { return name }
    }
    return nil
}

// MARK: - 기동

let arguments = CommandLine.arguments

if arguments.count == 2 && arguments[1] != serveFlag {
    // 부모 모드: 자식을 띄우고 즉시 빠진다 — 셸의 다음 명령(claude)이 바로 이어져야 하므로
    // 포그라운드에 남아 있으면 안 된다. `setsid`는 하지 않는다: 세션을 벗어나면 그 tty가
    // 제어 터미널이 아니게 되어 TIOCSTI 권한을 잃는다
    guard let ttyName = resolvePaneTTYName() else {
        fail("pane tty 이름을 알 수 없음 — 표준 입출력이 터미널이 아니다")
    }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? arguments[0])
    child.arguments = [serveFlag, arguments[1], ttyName]
    // pane tty를 실수로도 만지지 못하게 표준 입출력을 끊는다. 제어 터미널은 fd가 아니라
    // 세션에 딸린 것이라 이렇게 끊어도 자식의 TIOCSTI 권한은 그대로다(실측)
    child.standardInput = FileHandle.nullDevice
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    do {
        try child.run()
    } catch {
        fail("자식 프로세스를 띄우지 못함: \(errorMessage(error))")
    }
    exit(0)
}

guard arguments.count == 4, arguments[1] == serveFlag else {
    FileHandle.standardError.write(Data("usage: \(arguments.first ?? "helper") <socket-path>\n".utf8))
    exit(2)
}
let socketPath = arguments[2]
let ttyPath = arguments[3]

// 우리는 백그라운드 프로세스 그룹에 있다(포그라운드는 claude다). SIGTTOU를 무시하지 않으면
// TIOCSTI가 통째로 막힌다 — 실측: 부모가 빠져 orphaned가 된 프로세스 그룹에서는 EIO,
// orphaned가 아니면 SIGTTOU가 날아와 EINTR. 무시로 두면 두 경우 모두 성공한다.
signal(SIGTTOU, SIG_IGN)
// 앱이 응답을 받기 전에 연결을 끊으면 write에서 SIGPIPE로 죽는다
signal(SIGPIPE, SIG_IGN)

let ttyFD = open(ttyPath, O_RDWR | O_NOCTTY)
guard ttyFD >= 0 else { fail("\(ttyPath)를 열 수 없음 (\(lastErrnoName()))") }
// 이름과 fd가 같은 터미널을 가리키는지가 아니라, 그것이 **우리 세션의 제어 터미널**인지를
// 확인한다 — 아니면 앱에 남의 tty를 알려 주게 되고, 게이트가 엉뚱한 세션을 보고 통과한다.
// 세션의 제어 터미널은 하나뿐이라 이 비교로 충분하다
guard tcgetsid(ttyFD) == getsid(0) else {
    fail("\(ttyPath)는 이 세션의 제어 터미널이 아님")
}

umask(0o077)
// 이미 있는 파일을 지우고 bind한다. 소켓이 아닌 것은 우리가 만든 것이 아니므로 손대지 않는다 —
// 앱이 난수 토큰으로 경로를 뽑으니 정상 경로에서는 겹치지 않지만, 겹쳤다면 그건 남의 파일이다
socketPath.withCString { unlinkIfSocket($0) }
guard var address = makeUnixSockaddr(socketPath) else { fail("소켓 경로가 너무 김: \(socketPath)") }
let server = socket(AF_UNIX, SOCK_STREAM, 0)
guard server >= 0 else { fail("socket(): \(lastErrnoName())") }
let bound = withUnsafePointer(to: &address) {
    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bound == 0, listen(server, 4) == 0 else { fail("bind/listen: \(lastErrnoName())") }
chmod(socketPath, 0o600)
installSocketCleanupOnSignals(path: socketPath)

private let state = HelperState(ttyFD: ttyFD, ttyPath: ttyPath)
var finished = false

while !finished {
    var descriptor = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
    let ready = poll(&descriptor, 1, 2000)
    if ready > 0 {
        let client = accept(server, nil, nil)
        if client >= 0 {
            // 같은 사용자 프로세스만 허용 (앱 소켓과 같은 기준). uid만 보는 것이 여기서는
            // 충분한 신뢰 경계다 — 같은 uid의 프로세스는 이미 이 사용자의 파일을 고치고
            // 앱 번들을 갈아 끼우고 claude가 붙은 pane에 무엇이든 할 수 있어서, 호출자를
            // 특정 바이너리로 좁혀도 실제로 막히는 것이 없다. 다른 사용자는 소켓 파일
            // 퍼미션(0600)에서 먼저 걸린다. 경로의 난수 토큰은 비밀이 아니라 실행끼리
            // 섞이지 않게 하는 이름표다 (Tab Config에 그대로 적혀 pane에도 보인다)
            var uid: uid_t = 0
            var gid: gid_t = 0
            if getpeereid(client, &uid, &gid) == 0, uid == getuid() {
                finished = serve(client: client, state: state)
                state.touch()
            }
            close(client)
        }
    } else if ready < 0 && errno != EINTR {
        checkoutLog("Warp 주입 헬퍼 poll 실패: \(lastErrnoName())")
        break
    }
    // 요청이 없는 동안에도 같은 판정으로 본다 (요청 경로는 `serve`가 본다)
    if !finished, let stop = state.stopReason() {
        checkoutLog("Warp 주입 헬퍼 종료: \(stop.description)")
        break
    }
}

if let path = socketPathForSignal { unlinkIfSocket(path) }
close(server)
close(ttyFD)
exit(0)
