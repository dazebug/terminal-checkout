import ApplicationServices
import Foundation

// MARK: - Tab Config
// Warp에 새 탭을 열고 명령을 실행시키는 수단은 이것뿐이다: AppleScript를 지원하지 않고
// (번들에 .sdef 없음, Info.plist에 NSAppleScriptEnabled 없음), warpctrl은 Stable에서 기본
// 비활성이며, pane에 텍스트를 보내는 CLI(`wezterm cli send-text` 같은 것)도 없다 — 모두 실측.

/// 요청마다 다른 이름을 쓴다. 고정 이름은 두 가지를 동시에 깨뜨렸다:
/// ① 같은 이름의 사용자 Tab Config가 있으면 말없이 덮어쓴다
/// ② `open`이 돌아온 뒤에도 Warp는 파일을 조금 뒤에 읽는다(pane 등장까지 실측 0.5∼0.7초) —
///    그 사이 다음 요청이 덮어쓰면 두 탭 중 하나에 남의 명령이 뜬다
/// 이름을 나누면 두 문제가 파일 하나당 하나의 요청이라는 성질로 함께 사라진다. 대신 `+` 메뉴에
/// 파일이 쌓이지 않도록 실행이 끝나면 지우고(`runInWarp`), 앱이 그 전에 죽어 남은 것은
/// 다음 실행이 회수한다(`reclaimStaleWarpTabConfigs`).
public let warpTabConfigPrefix = "terminal-checkout-"

/// 이 브랜치 초기 빌드가 쓰던 고정 이름 — 회수 대상으로만 남긴다
let warpTabConfigLegacyStem = "terminal-checkout"

/// 생성 파일임을 알아보는 표시. 사용자 파일을 지우지 않기 위한 마지막 확인이다.
public let warpTabConfigHeader = "# Terminal Checkout이 자동 생성합니다"

public func warpTabConfigStem(token: String) -> String { warpTabConfigPrefix + token }

/// Stable 채널만 본다 — Preview 등 다른 채널은 이 디렉토리부터 `~/.warp-<channel>`로 갈린다.
public func warpTabConfigDirectory() -> String {
    (NSHomeDirectory() as NSString).appendingPathComponent(".warp/tab_configs")
}

public func warpTabConfigPath(stem: String) -> String {
    (warpTabConfigDirectory() as NSString).appendingPathComponent("\(stem).toml")
}

public func warpTabConfigURL(stem: String) -> String { "warp://tab_config/\(stem)" }

/// 회수해도 되는 파일 이름인가 — 우리 접두사 + 16진 토큰, 또는 옛 고정 이름.
public func warpTabConfigFileIsOurs(name: String) -> Bool {
    guard name.hasSuffix(".toml") else { return false }
    let stem = String(name.dropLast(".toml".count))
    if stem == warpTabConfigLegacyStem { return true }
    guard stem.hasPrefix(warpTabConfigPrefix) else { return false }
    let token = stem.dropFirst(warpTabConfigPrefix.count)
    return !token.isEmpty && token.allSatisfy(\.isHexDigit)
}

/// 내용까지 확인한다 — 이름이 우연히 겹친 사용자 파일을 지우면 안 된다.
public func warpTabConfigIsOurs(contents: String) -> Bool {
    contents.hasPrefix(warpTabConfigHeader)
}

/// TOML basic string 이스케이프. 제어문자는 리터럴로 담을 수 없어 반드시 escape sequence로
/// 바꿔야 한다 — 하나라도 새면 Warp가 파일 파싱에 실패해 탭이 아예 열리지 않는다.
public func escapeForTOMLBasicString(_ text: String) -> String {
    var out = ""
    for scalar in text.unicodeScalars {
        switch scalar {
        case "\\": out += #"\\"#
        case "\"": out += #"\""#
        case "\u{08}": out += #"\b"#
        case "\u{09}": out += #"\t"#
        case "\u{0A}": out += #"\n"#
        case "\u{0C}": out += #"\f"#
        case "\u{0D}": out += #"\r"#
        default:
            if scalar.value < 0x20 || scalar.value == 0x7F {
                out += String(format: #"\u%04X"#, scalar.value)
            } else {
                out.unicodeScalars.append(scalar)
            }
        }
    }
    return out
}

/// 명령들을 차례로 실행하는 단일 pane Tab Config.
/// `directory`를 두지 않는 것은 iTerm2·WezTerm과 맞추기 위해서다 — 기본 cwd에서 시작하고
/// 이동은 명령의 `z {repo}`가 한다.
/// `[params.*]`도 두지 않는다. 파라미터를 선언하면 열 때 채워 넣는 모달이 떠 명령이
/// 사용자 응답 전까지 실행되지 않는다. 선언하지 않으면 명령 속 `{{...}}`는 치환도 모달도 없이
/// 셸에 그대로 전달된다(실측) — 그래서 `{{`를 따로 방어하지 않는다.
public func warpTabConfigTOML(commands: [String]) -> String {
    let list = commands.map { "\"\(escapeForTOMLBasicString($0))\"" }.joined(separator: ", ")
    return """
    \(warpTabConfigHeader) — 탭이 열리면 지웁니다.
    name = "\(appDisplayName)"

    [[panes]]
    id = "main"
    type = "terminal"
    commands = [\(list)]

    """
}

// MARK: - 주입 헬퍼 기동

/// 앱 번들 안에서 relay와 나란히 놓이는 실행 파일 이름 (`app/build.sh`가 복사한다).
let warpHelperExecutableName = "terminal-checkout-warp-helper"

/// 헬퍼 실행 파일 경로. 앱에서는 `Contents/MacOS/` 안, 테스트·CLI에서는 실행 파일 옆이다.
/// 못 찾으면 nil — 그때는 명령만 실행하고 claude 입력을 포기한다.
func warpHelperExecutablePath() -> String? {
    guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else { return nil }
    let path = directory.appendingPathComponent(warpHelperExecutableName).path
    return FileManager.default.isExecutableFile(atPath: path) ? path : nil
}

/// 셸 단어 하나로 만든다. 앱 번들 경로에는 공백이 있어(`Terminal Checkout.app`)
/// 인용하지 않으면 셸이 두 단어로 갈라 헬퍼가 뜨지 않는다.
public func shellSingleQuoted(_ text: String) -> String {
    "'" + text.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

public func warpHelperCommand(executable: String, socketPath: String) -> String {
    "\(shellSingleQuoted(executable)) \(shellSingleQuoted(socketPath))"
}

/// 실행마다 새로 뽑는다 — 고정 이름이면 이전 실행이 남긴 죽은 소켓 파일에 붙거나,
/// 아직 살아 있는 이전 헬퍼(다른 pane)에 입력을 보내게 된다.
public func warpHelperToken() -> String {
    String(format: "%08x", UInt32.random(in: .min ... .max))
}

/// 회수해도 되는 소켓 파일 이름인가 — 우리 접두사 + 16진 토큰.
public func warpHelperSocketFileIsOurs(name: String) -> Bool {
    guard name.hasPrefix(warpHelperSocketPrefix), name.hasSuffix(".sock") else { return false }
    let token = name.dropFirst(warpHelperSocketPrefix.count).dropLast(".sock".count)
    return !token.isEmpty && token.allSatisfy(\.isHexDigit)
}

public let warpHelperSocketPrefix = "tcw-"

/// 후보 디렉토리 중 sun_path 104바이트에 들어가는 첫 경로. 하나도 안 들어가면 nil.
public func warpHelperSocketPath(token: String, directories: [String]) -> String? {
    for directory in directories {
        let path = (directory as NSString).appendingPathComponent("\(warpHelperSocketPrefix)\(token).sock")
        if makeUnixSockaddr(path) != nil { return path }
    }
    return nil
}

/// 임시 디렉토리를 쓰는 이유는 경로가 짧아 sun_path 104바이트 제한에 여유가 있어서다.
/// 남은 파일을 OS가 치워 주리라고 기대하지 않는다 — 헬퍼가 SIGKILL로 끝나면 `unlink`가 돌지
/// 못하므로, 다음 실행이 죽은 소켓을 직접 회수한다(`reclaimDeadWarpHelperSockets`).
public func warpHelperSocketPath(token: String) -> String? {
    warpHelperSocketPath(token: token, directories: [NSTemporaryDirectory(), "/tmp"])
}

// MARK: - 설치 감지와 프로세스 트리

/// Warp 앱 번들. LaunchServices 조회(AppKit)를 Core에 들이지 않으려고 표준 위치만 본다 —
/// 앱과 Core가 같은 함수를 쓰게 해서 "설정에는 설치됨, 실행은 못 찾음"이 생기지 않게 한다.
public func findWarpAppBundle() -> String? {
    let candidates = [
        "/Applications/Warp.app",
        (NSHomeDirectory() as NSString).appendingPathComponent("Applications/Warp.app"),
    ]
    return candidates.first { FileManager.default.fileExists(atPath: $0) }
}

/// Warp 실행 파일의 절대 경로. ps의 command 열과 정확히 맞아야 GUI 프로세스를 특정할 수 있어
/// 실행 파일 이름은 번들 Info.plist에서 읽는다 (Stable은 `stable`).
public func findWarpExecutable() -> String? {
    guard let bundle = findWarpAppBundle() else { return nil }
    let infoPath = (bundle as NSString).appendingPathComponent("Contents/Info.plist")
    guard let name = NSDictionary(contentsOfFile: infoPath)?["CFBundleExecutable"] as? String
    else { return nil }
    let executable = (bundle as NSString).appendingPathComponent("Contents/MacOS/\(name)")
    return FileManager.default.isExecutableFile(atPath: executable) ? executable : nil
}

/// `ps -axo pid=,ppid=,command=` 출력에서 Warp GUI 프로세스의 pid를 골라낸다.
/// GUI 프로세스는 `terminal-server`의 부모다(실측: `stable terminal-server --parent-pid=<gui>`).
/// GUI 자신은 인자 없이 뜨므로 인자로 갈라야 한다 — 인자를 보지 않으면 GUI의 부모(launchd)를
/// Warp로 지목하게 된다.
public func warpGUIPIDs(psOutput: String, executablePath: String) -> [Int] {
    var pids: [Int] = []
    for line in psOutput.split(separator: "\n") {
        // "pid ppid command…" — command에는 공백이 들어가므로 앞 두 칸만 가른다
        let parts = line.split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
        guard parts.count == 3, let ppid = Int(parts[1]) else { continue }
        let command = parts[2].trimmingCharacters(in: .whitespaces)
        guard command.hasPrefix(executablePath + " ") else { continue }
        let args = command.dropFirst(executablePath.count + 1).split(whereSeparator: { $0.isWhitespace })
        if args.first == "terminal-server", !pids.contains(ppid) { pids.append(ppid) }
    }
    return pids
}

/// 지금 떠 있는 Warp GUI 프로세스들.
func currentWarpGUIPIDs() -> [Int] {
    guard let executable = findWarpExecutable(),
          let ps = try? runProcess("/bin/ps", ["-axo", "pid=,ppid=,command="], timeout: 5),
          ps.status == 0
    else { return [] }
    return warpGUIPIDs(psOutput: ps.stdout, executablePath: executable)
}

// MARK: - 접근성 (화면 읽기)
// 입력 전달 자체는 접근성과 무관하다 — 헬퍼가 우리 tty에만 바이트를 넣기 때문이다.
// 접근성은 "claude가 그 입력을 입력창에 그렸는가"를 확인하는 데만 쓰는 best-effort 신호다.

/// 접근성 권한 상태 — 프롬프트를 띄우지 않고 조회만 한다.
public func accessibilityIsTrusted() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: false] as CFDictionary)
}

/// 접근성 권한 프롬프트를 띄운다 (이미 허용됐으면 그대로 true).
/// 자동화 권한과 달리 이 프롬프트는 그 자리에서 허용시켜 주지 않고 시스템 설정으로 안내만
/// 하므로, 결과는 `accessibilityIsTrusted()` 재조회로 확인해야 한다.
@discardableResult
public func requestAccessibilityPrompt() -> Bool {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
}

/// Warp의 포커스된 pane 화면 텍스트. 권한이 없거나 Warp가 없으면 nil.
///
/// 읽히는 것은 "그 창에서 포커스된 pane"이라 우리 pane이라는 보장이 없다 — Warp 창의 AX
/// 자식은 `AXTextArea` 하나 + 창 버튼 셋뿐이고 탭 바도 pane 식별자도 없으며, 탭을 바꿔도
/// 같은 AX 요소가 재사용된다(실측). 그래도 안전한 이유는 **입력이 이 경로로 가지 않기**
/// 때문이다: 타이핑·제출은 헬퍼가 우리 tty에만 넣으므로, 다른 pane을 읽어 생기는 최악은
/// "반영 확인이 어긋나 재시도" 또는 "확인을 tty 큐 신호로 대신함"이다.
public func warpScreenText() -> String? {
    guard accessibilityIsTrusted() else { return nil }
    // 창 하나를 읽을 때마다 ps를 다시 부른다 — 반영 확인은 0.4초 간격 다섯 번이라
    // 비용이 드러나지 않고, 캐시를 두면 Warp 재시작 뒤 죽은 pid를 붙들게 된다
    for pid in currentWarpGUIPIDs() {
        if let text = warpFocusedPaneText(pid: pid_t(pid)) { return text }
    }
    return nil
}

/// 주어진 Warp 프로세스의 포커스된 창에서 pane 화면 텍스트를 읽는다.
private func warpFocusedPaneText(pid: pid_t) -> String? {
    let app = AXUIElementCreateApplication(pid)
    guard let window = axElement(app, kAXFocusedWindowAttribute as String)
        ?? axElement(app, kAXMainWindowAttribute as String)
    else { return nil }
    return firstTextAreaValue(in: window, depth: 3)
}

private func axElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
          let raw = value, CFGetTypeID(raw) == AXUIElementGetTypeID()
    else { return nil }
    return (raw as! AXUIElement) // swiftlint:disable:this force_cast
}

private func axString(_ element: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value as? String
}

private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success
    else { return [] }
    return (value as? [AXUIElement]) ?? []
}

private func firstTextAreaValue(in element: AXUIElement, depth: Int) -> String? {
    guard depth > 0 else { return nil }
    for child in axChildren(element) {
        if axString(child, kAXRoleAttribute as String) == (kAXTextAreaRole as String),
           let value = axString(child, kAXValueAttribute as String) {
            return value
        }
        if let nested = firstTextAreaValue(in: child, depth: depth - 1) { return nested }
    }
    return nil
}

// MARK: - 회수
// 정상 경로는 스스로 치운다: 헬퍼는 `bye`·pane 종료·잡을 수 있는 시그널에서 소켓을 지우고,
// `runInWarp`은 탭이 열린 뒤 Tab Config를 지운다. 건너뛰는 것은 SIGKILL·전원 차단·앱 크래시다.
// 그 몫을 다음 실행이 훑어 되찾는다 — **살아 있는 것을 건드리지 않는 것**이 조건이다.

/// 주인이 죽은 헬퍼 소켓 파일을 지운다. 연결되면 살아 있는 헬퍼이므로 그대로 둔다.
/// 갓 만들어진 파일을 건너뛰는 이유는 `bind`와 `listen` 사이의 짧은 순간에 연결이 거절되기
/// 때문이다 — 그 창에서 지우면 살아 있는 헬퍼의 소켓을 없애 전달이 통째로 사라진다.
func reclaimDeadWarpHelperSockets(
    in directories: [String] = [NSTemporaryDirectory(), "/tmp"], youngerThan grace: TimeInterval = 60
) {
    for directory in Set(directories) {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { continue }
        for name in names where warpHelperSocketFileIsOurs(name: name) {
            let path = (directory as NSString).appendingPathComponent(name)
            guard let modified = fileModificationDate(path),
                  Date().timeIntervalSince(modified) > grace else { continue }
            if let fd = connectToUnixSocket(path: path) {
                close(fd)
                continue
            }
            unlink(path)
        }
    }
}

/// 앱이 자기 Tab Config를 지우기 전에 죽으면 파일이 남아 Warp `+` 메뉴에 쌓인다.
/// 나이를 보는 이유는 지금 막 열리고 있는 다른 요청의 파일을 지우지 않기 위해서고,
/// 내용까지 보는 이유는 이름이 겹친 사용자 파일을 지우지 않기 위해서다.
func reclaimStaleWarpTabConfigs(
    in directory: String = warpTabConfigDirectory(), olderThan age: TimeInterval = 300
) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where warpTabConfigFileIsOurs(name: name) {
        let path = (directory as NSString).appendingPathComponent(name)
        guard let modified = fileModificationDate(path),
              Date().timeIntervalSince(modified) > age,
              let contents = try? String(contentsOfFile: path, encoding: .utf8),
              warpTabConfigIsOurs(contents: contents)
        else { continue }
        try? FileManager.default.removeItem(atPath: path)
    }
}

private func fileModificationDate(_ path: String) -> Date? {
    (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
}

// MARK: - 헬퍼 소켓 클라이언트

/// 요청 하나를 보내고 응답 한 줄을 받는다. 연결·전송·해석 중 하나라도 실패하면 nil이다 —
/// 호출자는 이것을 "이번 호출이 실패했다"로만 다뤄야 한다(세션이 끝났다는 뜻이 아니다).
func warpHelperRequest(
    _ request: WarpHelperRequest, socket path: String, timeout: TimeInterval = 5
) -> WarpHelperResponse? {
    guard let fd = connectToUnixSocket(path: path) else { return nil }
    defer { close(fd) }

    // 헬퍼가 응답하지 않을 때 전달 스레드가 영영 매달리지 않게 한다
    var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    guard writeAll(fd: fd, data: Data((encodeWarpHelperRequest(request) + "\n").utf8)) else { return nil }

    var buffer = LineBuffer()
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
        if let line = buffer.nextLine() { return parseWarpHelperResponse(line) }
        let n = read(fd, &chunk, chunk.count)
        if n > 0 {
            buffer.append(Data(chunk[0..<n]))
            if buffer.isOverflowed { return nil }
        } else if n < 0 && errno == EINTR {
            continue
        } else {
            return nil
        }
    }
}
