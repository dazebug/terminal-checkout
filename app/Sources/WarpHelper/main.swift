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

/// tty 입력 큐에는 상한(TTYHOG)이 있고 넘치면 커널이 조용히 버린다 — 앱이 "전달됐다"로
/// 오판하지 않도록 여유 있게 잡아 두고, 넘칠 것 같으면 거절해 재시도로 돌린다.
private let injectQueueLimit = 512

/// 앱이 `bye`를 못 보내고 끝나는 경우(claude가 뜨지 않아 포기 등)에 대비한 자동 종료.
/// claude 기동 대기가 최대 120초라 그보다 넉넉해야 한다.
private let idleTimeout: TimeInterval = 300
private let maxLifetime: TimeInterval = 3600

private let serveFlag = "--serve"

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

private func inject(_ bytes: Data, into ttyFD: Int32) -> WarpHelperResponse {
    guard !bytes.isEmpty else { return .ok("0") }
    guard let pending = ttyPendingBytes(ttyFD) else { return .err(lastErrnoName()) }
    guard pending + bytes.count <= injectQueueLimit else {
        return .err("input queue full (\(pending) pending)")
    }
    for (index, byte) in bytes.enumerated() {
        var value = CChar(bitPattern: byte)
        let result = withUnsafeMutablePointer(to: &value) {
            ioctl(ttyFD, requestTIOCSTI, UnsafeMutableRawPointer($0))
        }
        // 중간에 실패하면 앞부분만 들어간 상태다 — 몇 바이트까지 갔는지 함께 알린다.
        // 앱은 재시도 전에 Ctrl+U로 입력창을 비우므로 남은 조각은 정리된다
        guard result == 0 else { return .err("\(lastErrnoName()) after \(index)") }
    }
    return .ok(String(bytes.count))
}

/// 연결 하나를 끝까지 처리한다. `bye`를 받았으면 true(헬퍼 종료).
private func serve(client: Int32, ttyFD: Int32, ttyPath: String) -> Bool {
    var tv = timeval(tv_sec: 10, tv_usec: 0)
    setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    var buffer = LineBuffer()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        while let line = buffer.nextLine() {
            var finished = false
            let response: WarpHelperResponse
            switch parseWarpHelperRequest(line) {
            case .tty:
                response = .ok(ttyPath)
            case .pending:
                response = ttyPendingBytes(ttyFD).map { .ok(String($0)) } ?? .err(lastErrnoName())
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
unlink(socketPath)
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

let startedAt = Date()
var lastActivity = Date()
var finished = false

while !finished {
    var descriptor = pollfd(fd: server, events: Int16(POLLIN), revents: 0)
    let ready = poll(&descriptor, 1, 2000)
    if ready > 0 {
        let client = accept(server, nil, nil)
        if client >= 0 {
            // 같은 사용자 프로세스만 허용 (앱 소켓과 같은 기준)
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
    // pane이 닫히면 pty가 회수돼 이 조회가 실패한다 — 떠도는 프로세스로 남지 않는다
    if !finished && tcgetpgrp(ttyFD) < 0 { break }
    if !finished && Date().timeIntervalSince(lastActivity) > idleTimeout { break }
    if !finished && Date().timeIntervalSince(startedAt) > maxLifetime { break }
}

unlink(socketPath)
close(server)
close(ttyFD)
exit(0)
