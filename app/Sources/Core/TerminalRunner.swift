import Foundation

public enum TerminalError: Error, CustomStringConvertible {
    case appleScriptFailed(String)
    case wezTermNotFound
    case warpNotFound
    case warpTabConfigFailed(String)
    case timeout(String)
    /// An undeliverable input we already know about **before** creating a tab. Identified by
    /// type, not by string — it reaches the extension as an `error` string, but inside the app
    /// this value is what tells the reasons apart
    case claudeInputNotDeliverable(ClaudeInputBlocker)

    public var description: String {
        switch self {
        case .appleScriptFailed(let message): return "AppleScript error: \(message)"
        case .wezTermNotFound: return "WezTerm not found. Install WezTerm or check your PATH."
        case .warpNotFound: return "Warp not found. Install Warp in /Applications or ~/Applications."
        case .warpTabConfigFailed(let message): return "Warp tab config error: \(message)"
        case .timeout(let what): return "Timed out: \(what)"
        case .claudeInputNotDeliverable(let blocker): return blocker.message
        }
    }
}

// MARK: - claude input preconditions (what we know is undeliverable before opening a tab)

/// Why scheduled input cannot be delivered. Only reasons knowable **before any side effect**
/// belong here — whichever point in the run establishes them.
public enum ClaudeInputBlocker: Equatable, CaseIterable {
    /// The screen cannot be read on Warp — no way to confirm claude received the input
    case warpAccessibility
    /// The in-pane injection helper could not be prepared (missing from the bundle, or the
    /// socket path exceeds the 104-byte limit)
    case warpHelperUnavailable
    /// WezTerm has no mux to spawn into, so the run would fall back to a fresh process whose
    /// pane cannot be addressed — `send-text` and `get-text` both need a mux pane id
    case wezTermSessionUnavailable

    /// Is the setup window the place to fix this? It holds the Accessibility card and the install
    /// state, so it answers the two Warp reasons. It has no WezTerm control on it — bringing it
    /// forward for "start WezTerm first" takes focus away from Chrome and shows nothing to do.
    public var setupWindowCanHelp: Bool {
        switch self {
        case .warpAccessibility, .warpHelperUnavailable: return true
        case .wezTermSessionUnavailable: return false
        }
    }

    /// Each reason implies a **different next action**. One shared wording would send a user who
    /// needs to grant a permission off to reinstall instead
    public var message: String {
        switch self {
        case .warpAccessibility:
            return "Warp에 claude 입력을 넣으려면 손쉬운 사용 권한이 필요합니다 —"
                + " Terminal Checkout 설정 창에서 허용하세요."
        case .warpHelperUnavailable:
            return "Warp 주입 헬퍼를 준비하지 못했습니다 — ./install.sh로 다시 설치하세요."
        // Two ways to land here — no mux at all, and a mux whose spawn attempts all failed — so
        // the wording covers both rather than asserting the first
        case .wezTermSessionUnavailable:
            return "WezTerm에서 claude 입력을 넣을 pane을 잡지 못했습니다 —"
                + " WezTerm 창이 떠 있는지 확인한 뒤 다시 누르세요."
        }
    }
}

/// Must this run be rejected **before it is even attempted**? `injectsClaudeInput` is not "were
/// claude inputs scheduled" but **"will anything be typed into the session"**
/// (`PreparedRequest.claudeInputs`) — every shipped preset merges completely and never reaches this.
///
/// The state probes are `@autoclosure` because this runs inside the execQueue that holds up the
/// Chrome response: when the answer cannot depend on state (nothing to type, not Warp) no TCC or
/// filesystem lookup happens at all.
///
/// The switch has no `default`, so adding a terminal turns into a compile error right here. That
/// is a prompt to decide, **not a proof that every reason is knowable this early**: WezTerm
/// returns nil here and still rejects later, because whether a pane can be addressed is only
/// known once the mux has been asked (`wezTermFallbackRejection`). A new terminal has to be
/// walked through `docs/new-terminal-checklist.md`, not just through this switch.
public func claudeInputBlocker(
    terminal: Terminal, injectsClaudeInput: Bool,
    accessibilityTrusted: @autoclosure () -> Bool,
    injectionHelperReady: @autoclosure () -> Bool
) -> ClaudeInputBlocker? {
    guard injectsClaudeInput else { return nil }
    switch terminal {
    // iTerm2 and WezTerm read exactly their own screen by session or pane id, so they need no
    // extra permission. (iTerm2's Automation permission is a precondition of running the command
    // at all — without it osascript fails and the request is already rejected.) WezTerm's own
    // blocker cannot be evaluated yet — see `wezTermFallbackRejection`
    case .iterm, .wezterm: return nil
    case .warp:
        guard accessibilityTrusted() else { return .warpAccessibility }
        guard injectionHelperReady() else { return .warpHelperUnavailable }
        return nil
    }
}

/// The rejection to raise instead of taking the WezTerm fallback, or nil to take it.
///
/// The fallback starts a **new WezTerm process**: no mux, so no pane id, so `.none` for a session
/// handle and nothing to type into. That used to be a log line while the response said
/// `{success:true}`. It is raised at the fallback boundary rather than in `claudeInputBlocker`
/// because that is the first moment it is known.
///
/// "Before any side effect" is exact for the common way in — no mux found, and asking the mux
/// neither spawns nor writes. The other way in is a mux that answered but whose spawn attempts all
/// failed; a `wezterm cli spawn` that timed out **may** have opened a tab whose id we never read.
/// Not measured, and it does not change the decision (rejecting is still better than running with
/// the input dropped), but the claim is narrower than the branch.
func wezTermFallbackRejection(injectsClaudeInput: Bool) -> TerminalError? {
    guard injectsClaudeInput else { return nil }
    return claudeInputRejection(.wezTermSessionUnavailable)
}

/// The helper line to put in front of the user's command in the Tab Config, plus the socket the
/// app will talk to it on. Nil when nothing will be typed into the session.
///
/// **This is the last check before the side effect, and that is the point.** `runInTerminal`
/// already asked `claudeInputBlocker`, but between that answer and the Tab Config being written
/// the permission can be revoked or a reinstall can replace the bundle. The old code logged
/// "권한이 없어 헬퍼를 띄우지 않음 — 명령만 실행한다" and carried on, which is a `{success:true}`
/// with the input silently dropped. It is separated from `runInWarp` so the decision can be
/// exercised without launching Warp — the passing branch of `runInWarp` has side effects, so unit
/// tests stay off it.
func warpInjectionSetup(
    token: String, injectsClaudeInput: Bool,
    accessibilityTrusted: @autoclosure () -> Bool = accessibilityIsTrusted(),
    helperExecutable: () -> String? = warpHelperExecutablePath,
    socketPath: (String) -> String? = warpHelperSocketPath(token:)
) throws -> (line: String, socket: String)? {
    guard injectsClaudeInput else { return nil }
    guard accessibilityTrusted() else { throw claudeInputRejection(.warpAccessibility) }
    guard let executable = helperExecutable(), let socket = socketPath(token) else {
        throw claudeInputRejection(.warpHelperUnavailable)
    }
    return (warpHelperCommand(executable: executable, socketPath: socket), socket)
}

/// Hook that brings forward a window explaining the rejection. The App target installs it;
/// `--headless-server` has no `AppDelegate`, so it stays nil and e2e never opens a window.
public enum ClaudeInputGuidance {
    public static var present: ((ClaudeInputBlocker) -> Void)?
}

/// Puts rejection and explanation through **one door**, so that however many rejection sites
/// appear, none of them can become "a ❌ with the reason nowhere" — the extension only sends the
/// `error` string to the console (issue #29).
public func claudeInputRejection(_ blocker: ClaudeInputBlocker) -> TerminalError {
    if blocker.setupWindowCanHelp { ClaudeInputGuidance.present?(blocker) }
    return .claudeInputNotDeliverable(blocker)
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

/// `injectsClaudeInput`은 이 실행에 예약된 claude 입력이 있는지다. Warp만 이 값을 본다 —
/// 입력을 넣으려면 pane 안에 주입 헬퍼를 함께 띄워야 하는데, 입력이 없는 버튼에까지 띄우면
/// 사용자에게 보이는 명령 블록이 하나 늘고 쓸모없는 프로세스가 남는다.
@discardableResult
public func runInTerminal(
    command: String, terminal: Terminal, injectsClaudeInput: Bool = false
) throws -> TerminalSessionHandle {
    // An undeliverable input known **before** any side effect rejects the whole request. Opening
    // the tab and dropping the tail answers `{success:true}`, so the button shows ✅ and the user
    // is left with a claude session that has no context
    if let blocker = claudeInputBlocker(
        terminal: terminal, injectsClaudeInput: injectsClaudeInput,
        accessibilityTrusted: accessibilityIsTrusted(),
        injectionHelperReady: warpInjectionHelperIsReady()
    ) {
        throw claudeInputRejection(blocker)
    }
    switch terminal {
    case .iterm: return try runInITerm(command)
    case .wezterm: return try runInWezTerm(command, injectsClaudeInput: injectsClaudeInput)
    case .warp: return try runInWarp(command, injectsClaudeInput: injectsClaudeInput)
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

/// Warp에서 새 탭을 열고 명령 실행.
/// Warp는 AppleScript도 pane 제어 CLI도 없어 Tab Config 파일 + `warp://tab_config/<stem>`
/// URL이 유일한 수단이다(실측). `open`은 LaunchServices를 거치므로 Warp가 꺼져 있으면
/// 새로 띄우고, 떠 있으면 활성 창에 탭을 더한다.
///
/// claude 입력이 예약돼 있으면 명령 앞에 주입 헬퍼를 한 줄 더 실행시킨다. 헬퍼가 자기 tty를
/// 알려 주므로 여기서 pane을 찾아 헤맬 필요가 없다 — 이 함수는 Chrome 응답을 막는
/// execQueue 안에서 도는데, 헬퍼가 뜨기를 기다리는 일은 백그라운드 전달 스레드
/// (`deliverClaudeInputs`)에서 하면 되기 때문이다.
///
/// Tab Config 파일 이름에는 요청마다 다른 토큰이 붙는다(`warpTabConfigStem`) — 고정 이름은
/// 사용자 파일을 덮어쓰고, `open`이 돌아온 뒤에도 Warp가 파일을 읽기 전이라 연속 요청이
/// 서로의 명령을 갈아 끼운다. 그 대신 우리 파일은 탭이 열릴 시간을 준 뒤 지운다.
@discardableResult
public func runInWarp(_ command: String, injectsClaudeInput: Bool = false) throws -> TerminalSessionHandle {
    guard findWarpAppBundle() != nil else { throw TerminalError.warpNotFound }

    // 앱이 죽어 남은 이전 실행의 찌꺼기부터 회수한다 (살아 있는 것은 건드리지 않는다)
    reclaimStaleWarpTabConfigs()
    reclaimDeadWarpHelperSockets()

    let token = warpHelperToken()
    // 사전조건을 부수효과 **직전**에 한 번 더 본다 — `runInTerminal`의 판정과 여기 사이에
    // 권한이 회수되거나 재설치가 번들을 갈아 끼울 수 있고, 그때 예전 코드는 로그만 남기고
    // 명령을 실행해 `{success:true}`로 답했다(입력은 조용히 증발). 여기서 던지면 탭도 열리지
    // 않는다 — 아직 아무것도 만들지 않았다
    let injection = try warpInjectionSetup(token: token, injectsClaudeInput: injectsClaudeInput)
    let socketPath = injection?.socket
    let commands = [injection?.line, command].compactMap { $0 }

    let stem = warpTabConfigStem(token: token)
    let path = warpTabConfigPath(stem: stem)
    do {
        try FileManager.default.createDirectory(
            atPath: warpTabConfigDirectory(), withIntermediateDirectories: true
        )
        // 토큰이 겹칠 일은 없지만, 겹쳤다면 그것은 사용자 파일일 수도 있다 — 덮어쓰지 않는다.
        // `O_CREAT|O_EXCL`로 만들어 "있는지 보고 쓴다"의 창을 없앤다: 검사와 생성이 한 syscall이다
        try writeNewFile(path: path, contents: warpTabConfigTOML(commands: commands))
    } catch let error as TerminalError {
        throw error
    } catch {
        throw TerminalError.warpTabConfigFailed(errorMessage(error))
    }
    // 회수 예약은 파일을 쓰자마자 건다 — `open`이 던지는 갈래에서도 파일이 남지 않아야 한다.
    // Warp는 `open`이 돌아온 뒤에 파일을 읽으므로(pane 등장까지 실측 0.5∼0.7초) 곧바로
    // 지우면 안 된다
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + warpTabConfigLifetime) {
        removeWarpTabConfigIfOurs(path: path)
    }

    let result = try runProcess("/usr/bin/open", [warpTabConfigURL(stem: stem)], timeout: 15)
    guard result.status == 0 else {
        throw TerminalError.warpTabConfigFailed(
            result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    guard let socketPath else { return .none }
    return .warp(helperSocket: socketPath)
}

/// 새로 만드는 경우에만 쓴다. 이미 있으면 `EEXIST`로 실패한다 — 먼저 존재를 확인하고
/// 쓰는 방식은 그 사이 사용자 파일이 놓이면 덮어쓴다.
private func writeNewFile(path: String, contents: String) throws {
    let fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
    guard fd >= 0 else {
        throw TerminalError.warpTabConfigFailed("파일을 새로 만들지 못했습니다(\(String(cString: strerror(errno)))): \(path)")
    }
    defer { close(fd) }
    guard writeAll(fd: fd, data: Data(contents.utf8)) else {
        unlink(path)
        throw TerminalError.warpTabConfigFailed("파일을 쓰지 못했습니다: \(path)")
    }
}

/// Warp가 Tab Config를 읽고 pane을 띄우기까지 기다려 주는 시간. 실측 0.5∼0.7초의 여유분이며,
/// 이보다 짧으면 탭이 열리지 않고 길면 `+` 메뉴에 우리 파일이 오래 남는다.
/// **이 시간은 "Warp가 읽었다"를 보장하지 않는다** — 그것을 알려 주는 신호가 없어서 시간에
/// 기대는 것이고, 시스템이 크게 밀리면 탭이 열리지 않을 수 있다. 그때의 결과는 "탭이 안
/// 열린다"뿐이라(데이터 손실 없음) 여유를 30배로 잡고 남겨 둔다. 이건 신뢰 경계와 무관한
/// 타이밍 가정이다.
let warpTabConfigLifetime: TimeInterval = 20

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

/// wezterm CLI를 부를 환경 — GUI 앱의 환경에 우리가 고른 mux 소켓을 얹는다.
/// 창 조회·spawn·send-text·get-text가 **같은 소켓**을 봐야 하므로 만드는 자리를 하나로 둔다.
func wezTermEnvironment(socketPath: String?) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    if let socketPath { env["WEZTERM_UNIX_SOCKET"] = socketPath }
    return env
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

    // idle_time이 없는 client는 최하위로 밀어 아래 선택에서 마지막 후보가 되게 한다
    func idleSeconds(_ client: [String: Any]) -> Double {
        guard let idle = client["idle_time"] as? [String: Any] else { return .greatestFiniteMagnitude }
        let secs = (idle["secs"] as? Double) ?? 0
        let nanos = (idle["nanos"] as? Double) ?? 0
        return secs + nanos / 1_000_000_000
    }
    // client가 여럿이면 가장 최근에 활동한 쪽을 사용자가 보고 있는 창으로 본다 — 실측한 것은
    // gui 하나만 붙은 경우뿐이라 이 선택 규칙은 아직 확인하지 못한 전제다. 어긋나도 결과는
    // "보고 있지 않은 창에 탭"이고 spawn 자체는 성공한다(이 변경 전과 같은 수준).
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

/// mux에 물어 포커스된 창 id를 얻는다 (조회 실패 시 nil → wezterm 기본 창 선택).
/// 이 조회는 Chrome 응답을 막는 execQueue 안에서 돈다(`HostServer`) — 지금은 두 번 합쳐
/// 20∼40ms(실측)라 버튼 반응에 드러나지 않지만, 조회를 늘리면 그만큼 응답이 늦어진다.
public func findWezTermFocusedWindow(cli: String, env: [String: String]) -> String? {
    guard let clients = try? runProcess(cli, ["cli", "list-clients", "--format", "json"], env: env, timeout: 5),
          clients.status == 0,
          let list = try? runProcess(cli, ["cli", "list", "--format", "json"], env: env, timeout: 5),
          list.status == 0
    else { return nil }
    return wezTermFocusedWindowID(clientsJSON: Data(clients.stdout.utf8), listJSON: Data(list.stdout.utf8))
}

/// WezTerm에서 지금 보고 있는 창에 새 탭을 열고 명령 실행 (spawn 실패 시 새 프로세스 fallback).
/// `injectsClaudeInput`이면 그 fallback으로는 갈 수 없다 — pane을 지목할 수 없어 입력이
/// 사라지기 때문이다(`wezTermFallbackRejection`).
@discardableResult
public func runInWezTerm(
    _ command: String, injectsClaudeInput: Bool = false
) throws -> TerminalSessionHandle {
    guard let cli = findWezTermCLI() else { throw TerminalError.wezTermNotFound }

    if let sock = findWezTermSocket() {
        let env = wezTermEnvironment(socketPath: sock)
        let windowID = findWezTermFocusedWindow(cli: cli, env: env)
        for args in wezTermSpawnAttempts(windowID: windowID) {
            guard let spawn = try? runProcess(cli, args, env: env, timeout: 5), spawn.status == 0 else {
                checkoutLog("wezterm \(args.joined(separator: " ")) 실패")
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
    // 종료를 기다리지 않으며, pane을 특정할 수 없어 핸들도 없다 — 그래서 타이핑할 입력이
    // 예약돼 있으면 여기로 갈 수 없다. 아직 spawn 전이라 되돌릴 부수효과가 없다
    if let rejection = wezTermFallbackRejection(injectsClaudeInput: injectsClaudeInput) {
        throw rejection
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: cli)
    process.arguments = ["start", "--", "/bin/bash", "-ic", "\(command); exec bash"]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    process.standardInput = FileHandle.nullDevice
    try process.run()
    return .none
}
