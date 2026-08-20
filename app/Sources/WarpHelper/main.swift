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
/// 큐가 빌 때까지 기다리는 상한. claude가 바쁘면 소비가 늦는데, 여기서 무한정 기다리면
/// 전달 스레드가 통째로 묶인다 — 시간을 넘기면 `err`로 돌려주고 앱의 재시도에 맡긴다.
private let injectDrainTimeout: TimeInterval = 10
/// 한 요청으로 받아 주는 최대 바이트. claude 입력은 한 줄이라 이보다 훨씬 짧다 —
/// 상한이 없으면 보내는 쪽이 수십만 번의 ioctl을 시킬 수 있다.
private let injectMaxBytes = 8 * 1024
/// 수신 버퍼 상한. base64는 원본의 4/3이라 위 상한의 두 배면 넉넉하다.
private let requestLineLimit = 16 * 1024

// 위협 모델: 이 소켓은 같은 uid의 **아무 프로세스나** 그 pane의 claude에 입력을 넣을 수 있게
// 한다. 같은 uid에게 비밀을 숨길 자리가 없어서(argv·환경변수·0600 파일을 모두 읽고, 소켓
// 경로는 Tab Config와 pane 화면에 그대로 보인다) 인증으로는 좁힐 수 없다. 그래서 좁히는
// 축은 **수명**이다 — 전달이 끝나면 `bye`로 즉시 죽고, 그러지 못한 경우에만 아래 상한이 돈다.
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

/// 큐 여유만큼 나눠 넣는다. 통째로 거절하면 512바이트가 넘는 claude 프롬프트가 항상
/// 실패하는데, 그 길이는 사용자가 직접 쓰는 입력에서 드물지 않다.
/// 바이트 단위로 잘라도 되는 이유는 tty 입력 큐가 바이트 스트림이기 때문이다 — 멀티바이트
/// 문자가 조각나 들어가도 순서대로 이어지면 claude가 온전히 받는다(한글 입력으로 실측).
private func inject(_ bytes: Data, into ttyFD: Int32) -> WarpHelperResponse {
    guard !bytes.isEmpty else { return .ok("0") }
    guard bytes.count <= injectMaxBytes else {
        return .err("payload too large (\(bytes.count) > \(injectMaxBytes))")
    }
    let all = [UInt8](bytes)
    var sent = 0
    let deadline = Date().addingTimeInterval(injectDrainTimeout)
    while sent < all.count {
        guard let pending = ttyPendingBytes(ttyFD) else { return .err(lastErrnoName()) }
        let chunk = warpInjectChunkSize(pending: pending, remaining: all.count - sent, limit: injectQueueLimit)
        guard chunk > 0 else {
            // claude가 아직 읽어 가지 않았다. 여기서 더 넣으면 커널이 조용히 버린다
            guard Date() < deadline else {
                return .err("input queue still full after \(Int(injectDrainTimeout))s (\(pending) pending)")
            }
            usleep(50_000)
            continue
        }
        for index in sent..<(sent + chunk) {
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
    return .ok(String(sent))
}

/// 연결 하나를 끝까지 처리한다. `bye`를 받았으면 true(헬퍼 종료).
private func serve(client: Int32, ttyFD: Int32, ttyPath: String) -> Bool {
    var tv = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var buffer = LineBuffer(limit: requestLineLimit)
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        while let line = buffer.nextLine() {
            var finished = false
            let response: WarpHelperResponse
            switch parseWarpHelperRequest(line) {
            case .tty:
                response = .ok(ttyPath)
            case .inject(let bytes):
                response = inject(bytes, into: ttyFD)
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

let startedAt = Date()
var lastActivity = Date()
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
                finished = serve(client: client, ttyFD: ttyFD, ttyPath: ttyPath)
                lastActivity = Date()
            }
            close(client)
        }
    } else if ready < 0 && errno != EINTR {
        checkoutLog("Warp 주입 헬퍼 poll 실패: \(lastErrnoName())")
        break
    }
    // pane이 닫혔는지 확인한다. `tcgetpgrp`이 성공하는지만 보면 부족하다 — tty 번호는
    // 재사용되므로(실측), 우리 pane이 닫힌 뒤 같은 번호를 새 세션이 차지하면 그대로 살아남아
    // 남의 세션 tty에 붙은 헬퍼가 된다. 세션 id까지 비교해야 그 갈래가 죽는다
    if !finished && tcgetsid(ttyFD) != getsid(0) { break }
    if !finished && Date().timeIntervalSince(lastActivity) > idleTimeout { break }
    if !finished && Date().timeIntervalSince(startedAt) > maxLifetime { break }
}

if let path = socketPathForSignal { unlinkIfSocket(path) }
close(server)
close(ttyFD)
exit(0)
