import Core
import Foundation

/// relay의 요청을 받아 터미널에서 실행하는 unix socket 서버.
final class HostServer {
    enum ServerError: Error, CustomStringConvertible {
        case alreadyRunning
        case socketFailed(String)

        var description: String {
            switch self {
            case .alreadyRunning: return "다른 Terminal Checkout 인스턴스가 이미 실행 중입니다."
            case .socketFailed(let reason): return "소켓 생성 실패: \(reason)"
            }
        }
    }

    private let socketPath: String
    private var serverFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "terminal-checkout.accept")
    private let execQueue = DispatchQueue(label: "terminal-checkout.exec") // 터미널 실행 직렬화

    init(socketPath: String) {
        self.socketPath = socketPath
    }

    func start() throws {
        let dir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        // 기존 소켓: 연결되면 살아있는 인스턴스, 아니면 stale → 제거 후 재사용
        if FileManager.default.fileExists(atPath: socketPath) {
            if let fd = connectToUnixSocket(path: socketPath) {
                close(fd)
                throw ServerError.alreadyRunning
            }
            unlink(socketPath)
        }

        guard var addr = makeUnixSockaddr(socketPath) else {
            throw ServerError.socketFailed("경로가 너무 깁니다: \(socketPath)")
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ServerError.socketFailed(String(cString: strerror(errno))) }

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bound == 0, listen(fd, 8) == 0 else {
            let reason = String(cString: strerror(errno))
            close(fd)
            throw ServerError.socketFailed(reason)
        }
        chmod(socketPath, 0o600)
        serverFD = fd
        acceptQueue.async { [weak self] in self?.acceptLoop(serverFD: fd) }
    }

    func stop() {
        if serverFD >= 0 {
            close(serverFD)
            serverFD = -1
        }
        unlink(socketPath)
    }

    private func acceptLoop(serverFD: Int32) {
        while true {
            let fd = accept(serverFD, nil, nil)
            if fd < 0 {
                if errno == EINTR { continue }
                break // 서버 소켓이 닫힘
            }
            // 같은 사용자 프로세스만 허용
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd)
                continue
            }
            DispatchQueue.global().async { [weak self] in self?.serve(fd: fd) }
        }
    }

    private func serve(fd: Int32) {
        defer { close(fd) }
        while let data = readFramedMessage(fromFD: fd) {
            // 실행 결과와 무관하게 요청 도착 자체가 Chrome→relay→소켓 경로의 증거다
            Settings.recordRequestEvidence()
            let json = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
            let response = execQueue.sync {
                handleRequest(json: json) { resolved in
                    // 예약된 claude 입력은 전부 claude의 argv로 병합되거나 전부 주입 경로로
                    // 간다(`prepareRequest`) — 섞이지 않는다. 병합된 쪽은 주입할 것이 없어
                    // Warp 헬퍼도 손쉬운 사용 권한도 필요 없어진다
                    let prepared = prepareRequest(
                        resolved, claudeIsExecutable: Settings.claudeIsExecutable
                    )
                    do {
                        // 터미널 선택은 앱 설정이 단일 소스 — 요청의 terminal 필드는 무시한다
                        let handle = try runInTerminal(
                            command: prepared.command, terminal: Settings.terminal,
                            injectsClaudeInput: !prepared.claudeInputs.isEmpty
                        )
                        if !prepared.claudeInputs.isEmpty {
                            // 전달 감시는 claude 기동 대기와 입력별 재시도가 모두 블로킹이라
                            // 수 분이 걸릴 수 있다 — 직렬 execQueue와 Chrome 응답을 막지 않도록
                            // 응답은 스폰 즉시 돌려주고 감시는 밖에서 돈다
                            DispatchQueue.global(qos: .utility).async {
                                deliverClaudeInputs(prepared.claudeInputs, to: handle)
                            }
                        }
                    } catch {
                        // 명령이 터미널에 닿지 못했으면 그 스크립트를 실행할 셸이 없다 —
                        // 남겨 두면 회수 스윕이 돌 때까지 임시 디렉토리에 쌓인다
                        prepared.discardTemporaryFiles()
                        throw error
                    }
                }
            }
            let payload = (try? JSONSerialization.data(withJSONObject: response))
                ?? Data(#"{"success":false,"error":"internal error"}"#.utf8)
            if !writeFramedMessage(payload, toFD: fd) { break }
        }
    }
}
