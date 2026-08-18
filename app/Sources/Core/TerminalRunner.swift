import Foundation

public enum TerminalError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case wezTermNotFound
    case timeout(String)

    public var description: String {
        switch self {
        case .appleScriptFailed(let message): return "AppleScript error: \(message)"
        case .wezTermNotFound: return "WezTerm not found. Install WezTerm or check your PATH."
        case .timeout(let what): return "Timed out: \(what)"
        }
    }
}

/// 서브프로세스 실행 헬퍼 (타임아웃 + stdin 주입 + 파이프 데드락 방지)
@discardableResult
public func runProcess(
    _ path: String, _ args: [String],
    input: String? = nil,
    env: [String: String]? = nil,
    timeout: TimeInterval = 10
) throws -> (status: Int32, stdout: String, stderr: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    if let env { process.environment = env }

    let outPipe = Pipe(), errPipe = Pipe()
    process.standardOutput = outPipe
    process.standardError = errPipe
    let inPipe = Pipe()
    if input != nil { process.standardInput = inPipe } else { process.standardInput = FileHandle.nullDevice }

    try process.run()

    if let input {
        inPipe.fileHandleForWriting.write(Data(input.utf8))
        inPipe.fileHandleForWriting.closeFile()
    }

    // 종료를 기다리기 전에 파이프를 비워야 출력이 큰 경우에도 막히지 않는다
    let group = DispatchGroup()
    var outData = Data(), errData = Data()
    DispatchQueue.global().async(group: group) {
        outData = outPipe.fileHandleForReading.readDataToEndOfFile()
    }
    DispatchQueue.global().async(group: group) {
        errData = errPipe.fileHandleForReading.readDataToEndOfFile()
    }

    let exited = DispatchSemaphore(value: 0)
    DispatchQueue.global().async {
        process.waitUntilExit()
        exited.signal()
    }
    if exited.wait(timeout: .now() + timeout) == .timedOut {
        process.terminate()
        _ = exited.wait(timeout: .now() + 2)
        group.wait()
        throw TerminalError.timeout("\(path) \(args.joined(separator: " "))")
    }
    group.wait()

    return (
        process.terminationStatus,
        String(data: outData, encoding: .utf8) ?? "",
        String(data: errData, encoding: .utf8) ?? ""
    )
}

@discardableResult
public func runInTerminal(command: String, terminal: String) throws -> TerminalSessionHandle {
    if terminal == "wezterm" {
        return try runInWezTerm(command)
    } else {
        return try runInITerm(command)
    }
}

/// iTerm2에서 새 탭 열고 명령 실행.
/// osascript는 이 앱의 자식 프로세스이므로 TCC 자동화 권한이 이 앱에 귀속된다.
@discardableResult
public func runInITerm(_ command: String) throws -> TerminalSessionHandle {
    // 타임아웃 여유: 최초 실행 시 자동화 권한 프롬프트가 뜨면 사용자가 응답할 때까지 블록된다
    let result = try runProcess("/usr/bin/osascript", ["-e", iTermScript(for: command)], timeout: 180)
    guard result.status == 0 else {
        throw TerminalError.appleScriptFailed(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    // 스크립트가 돌려준 "세션id|tty" — 형태가 어긋나면 실행은 성공으로 두고 핸들만 포기한다
    let parts = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(separator: "|", maxSplits: 1)
    guard parts.count == 2, !parts[0].isEmpty, parts[1].hasPrefix("/dev/") else { return .none }
    return .iterm(sessionID: String(parts[0]), tty: String(parts[1]))
}

/// WezTerm CLI 경로 탐색: PATH → Homebrew/앱 번들 fallback
/// (앱은 GUI 프로세스라 PATH가 /usr/bin:/bin 수준으로 제한되므로 명시적 후보가 필수)
public func findWezTermCLI() -> String? {
    var candidates: [String] = []
    if let raw = getenv("PATH") {
        for dir in String(cString: raw).split(separator: ":") {
            candidates.append("\(dir)/wezterm")
        }
    }
    candidates.append(contentsOf: [
        "/opt/homebrew/bin/wezterm",
        "/usr/local/bin/wezterm",
        "/Applications/WezTerm.app/Contents/MacOS/wezterm",
    ])
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// 실행 중인 WezTerm GUI 프로세스의 소켓 찾기 (최신 우선, PID 매칭)
public func findWezTermSocket() -> String? {
    let sockDir = (NSHomeDirectory() as NSString).appendingPathComponent(".local/share/wezterm")
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: sockDir) else { return nil }

    let runningPIDs: Set<String>
    if let result = try? runProcess("/usr/bin/pgrep", ["-x", "wezterm-gui"], timeout: 3), result.status == 0 {
        runningPIDs = Set(result.stdout.split(whereSeparator: \.isWhitespace).map(String.init))
    } else {
        runningPIDs = []
    }

    func mtime(_ path: String) -> Date {
        (try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date).flatMap { $0 } ?? .distantPast
    }
    let sockets = entries.filter { $0.hasPrefix("gui-sock-") }
        .map { (sockDir as NSString).appendingPathComponent($0) }
        .sorted { mtime($0) > mtime($1) }

    for sock in sockets {
        if let pid = sock.split(separator: "-").last, runningPIDs.contains(String(pid)) {
            return sock
        }
    }
    return sockets.first
}

/// `wezterm cli spawn` 시도 순서. 창을 특정했으면 그 창을 먼저 노리고, 실패하면 창 지정 없이
/// 한 번 더 시도한다 — 찾은 창이 spawn 직전에 닫히면 wezterm은 "window_id N not found"로
/// 실패하는데(실측), 거기서 포기하면 `wezterm start` fallback이 새 창을 띄워 고치려던 증상이
/// 그대로 되살아난다. 창을 못 찾았으면 시도는 한 번뿐이다.
public func wezTermSpawnAttempts(windowID: String?) -> [[String]] {
    let base = ["cli", "spawn"]
    guard let windowID else { return [base] }
    return [base + ["--window-id", windowID], base]
}

/// 지금 포커스된 pane이 속한 창 id를 mux 응답(list-clients + list)에서 찾는다.
/// `wezterm cli spawn`은 --window-id가 없으면 WEZTERM_PANE 환경변수의 pane으로 창을 정하는데,
/// GUI 앱에는 그 변수가 없어 mux의 첫 창(= 가장 오래된 창)에 탭이 생긴다 — 사용자가 보던 창이
/// 아닌 딴 창이 앞으로 튀어나온다(실측). 그래서 포커스된 창을 직접 찾아 지정한다.
public func wezTermFocusedWindowID(clientsJSON: Data, listJSON: Data) -> String? {
    guard let clients = (try? JSONSerialization.jsonObject(with: clientsJSON)) as? [[String: Any]],
          let list = (try? JSONSerialization.jsonObject(with: listJSON)) as? [[String: Any]]
    else { return nil }

    // client가 여럿이면 가장 최근에 활동한 쪽이 사용자가 보고 있는 창이다
    func idleSeconds(_ client: [String: Any]) -> Double {
        guard let idle = client["idle_time"] as? [String: Any] else { return .greatestFiniteMagnitude }
        let secs = (idle["secs"] as? Double) ?? 0
        let nanos = (idle["nanos"] as? Double) ?? 0
        return secs + nanos / 1_000_000_000
    }
    let focused = clients
        .compactMap { client -> (pane: Int, idle: Double)? in
            guard let pane = client["focused_pane_id"] as? Int else { return nil }
            return (pane, idleSeconds(client))
        }
        .min { $0.idle < $1.idle }
    guard let paneID = focused?.pane else { return nil }

    for pane in list where (pane["pane_id"] as? Int) == paneID {
        guard let windowID = pane["window_id"] as? Int else { return nil }
        return String(windowID)
    }
    return nil // 포커스된 pane이 이미 닫혔다 — 엉뚱한 창을 고르지 않는다
}

/// mux에 물어 포커스된 창 id를 얻는다 (조회 실패 시 nil → wezterm 기본 창 선택)
public func findWezTermFocusedWindow(cli: String, env: [String: String]) -> String? {
    guard let clients = try? runProcess(cli, ["cli", "list-clients", "--format", "json"], env: env, timeout: 5),
          clients.status == 0,
          let list = try? runProcess(cli, ["cli", "list", "--format", "json"], env: env, timeout: 5),
          list.status == 0
    else { return nil }
    return wezTermFocusedWindowID(clientsJSON: Data(clients.stdout.utf8), listJSON: Data(list.stdout.utf8))
}

/// WezTerm에서 지금 보고 있는 창에 새 탭을 열고 명령 실행 (spawn 실패 시 새 프로세스 fallback)
@discardableResult
public func runInWezTerm(_ command: String) throws -> TerminalSessionHandle {
    guard let cli = findWezTermCLI() else { throw TerminalError.wezTermNotFound }

    if let sock = findWezTermSocket() {
        var env = ProcessInfo.processInfo.environment
        env["WEZTERM_UNIX_SOCKET"] = sock
        let windowID = findWezTermFocusedWindow(cli: cli, env: env)
        for args in wezTermSpawnAttempts(windowID: windowID) {
            guard let spawn = try? runProcess(cli, args, env: env, timeout: 5), spawn.status == 0 else {
                NSLog("Terminal Checkout: wezterm \(args.joined(separator: " ")) 실패")
                continue
            }
            let paneID = spawn.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            _ = try? runProcess(
                cli, ["cli", "send-text", "--pane-id", paneID, "--no-paste"],
                input: command + "\n", env: env, timeout: 5
            )
            _ = try? runProcess("/usr/bin/open", ["-a", "WezTerm"], timeout: 5)
            return .wezterm(paneID: paneID, cliPath: cli, socketPath: sock)
        }
    }

    // fallback: 새 WezTerm 프로세스 = 새 창 (mux가 없으면 붙을 창도 없다).
    // 종료를 기다리지 않으며, pane을 특정할 수 없어 핸들도 없다
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cli)
    process.arguments = ["start", "--", "/bin/bash", "-ic", "\(command); exec bash"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    return .none
}
