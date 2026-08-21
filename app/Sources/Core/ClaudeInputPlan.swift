import Foundation

// 예약된 claude 입력을 두 갈래로 나눈다: **병합 접두사**는 claude를 띄우는 명령의 argv에 실어
// 첫 메시지 하나로 보내고, **꼬리**만 기존 주입 경로(`ClaudeInjector`)로 보낸다.
//
// 왜: 주입은 화면을 읽어 확인해야 하므로 Warp에서 손쉬운 사용 권한이 필수이고, pane 증명·반영
// 확인·재시도가 붙어 느리고 깨지기 쉽다. argv는 그 전부가 필요 없다 — claude가 뜰 때 프롬프트를
// 이미 들고 있기 때문이다. 배포 프리셋의 claude 입력은 전부 `!`라 꼬리가 공집합이 되고, 그러면
// 헬퍼도 권한도 필요 없어진다.
//
// 대가: 입력 N개가 메시지 1개로 합쳐져 응답도 1회가 된다. 이것은 사용자가 선택한 의미 변화다
// (`!` 하나하나가 오늘도 응답을 유발한다 — 트랜스크립트 실측).

// MARK: - 경계 판정

/// 입력 하나의 부류. 경계 판정에만 쓴다.
private enum ClaudeInputKind {
    /// `!`로 시작 — claude의 셸 모드. 선실행해 출력을 프롬프트에 싣는다
    case shellCommand
    /// `/`로 시작 — 슬래시 명령
    case slashCommand
    /// 그 밖의 자유 텍스트
    case interactive

    init(_ input: String) {
        if input.hasPrefix("!") {
            self = .shellCommand
        } else if input.hasPrefix("/") {
            self = .slashCommand
        } else {
            self = .interactive
        }
    }
}

/// 입력을 병합 접두사와 주입 꼬리로 가른 결과. `prefix + tail`은 항상 원본이다.
public struct ClaudeInputPlan: Equatable {
    /// claude argv의 첫 메시지 하나로 합칠 입력들 (순서 보존)
    public let prefix: [String]
    /// 기존 주입 경로로 보낼 입력들
    public let tail: [String]
}

/// 병합할 수 있는 **최대 접두사**를 찾는다. 경계는 둘뿐이다:
///
/// ① **슬래시 명령** — 단독 메시지라야 명령으로 해석된다. 선두의 `/`만 슬래시 디스패처로 가고,
///    배너가 앞에 붙으면 불활성 텍스트가 된다(`claude -p "/help"` → 명령으로 인식,
///    `claude -p $'banner\n/help\n…'` → 일반 텍스트로 처리, 둘 다 실측). 그래서 슬래시 명령을
///    병합에 넣으면 뜻이 조용히 사라진다.
/// ② **대화형 입력 뒤에 오는 `!`** — 그 명령의 출력은 **다음** 지시문이 볼 컨텍스트로 의도된
///    것이다. 첫 메시지로 끌어올리면 앞 지시문이 보는 맥락이 달라진다.
///
/// 그 밖의 전환(명령형→명령형, 대화형→대화형, 명령형→대화형)은 모두 병합한다.
public func claudeInputPlan(_ inputs: [String]) -> ClaudeInputPlan {
    var sawInteractive = false
    for (index, input) in inputs.enumerated() {
        func split() -> ClaudeInputPlan {
            ClaudeInputPlan(prefix: Array(inputs[..<index]), tail: Array(inputs[index...]))
        }
        switch ClaudeInputKind(input) {
        case .slashCommand: return split()
        case .shellCommand where sawInteractive: return split()
        case .shellCommand: continue
        case .interactive: sawInteractive = true
        }
    }
    return ClaudeInputPlan(prefix: inputs, tail: [])
}

// MARK: - 명령 꼬리에 프롬프트를 붙일 수 있는가

let claudeExecutableName = "claude"

/// 최상위(따옴표 밖) 명령 구분자 뒤의 마지막 조각. 파이프 뒤이거나 따옴표가 닫히지 않았으면 nil.
///
/// `||`는 or이지 파이프가 아니므로 구분자 덩어리를 통째로 보고 가른다 — 한 글자씩 보면
/// `a || claude`가 파이프로 오판된다.
private func lastSimpleCommandSegment(in command: String) -> String? {
    let chars = Array(command)
    let separators: Set<Character> = ["&", "|", ";", "\n", "(", "{"]
    var index = 0
    var segmentStart = 0
    var inSingle = false, inDouble = false
    var lastSeparatorWasPipe = false

    while index < chars.count {
        let character = chars[index]
        if inSingle {
            if character == "'" { inSingle = false }
            index += 1
            continue
        }
        if inDouble {
            if character == "\\" {
                index += 2
                continue
            }
            if character == "\"" { inDouble = false }
            index += 1
            continue
        }
        switch character {
        case "'":
            inSingle = true
            index += 1
        case "\"":
            inDouble = true
            index += 1
        case "\\":
            index += 2
        case let separator where separators.contains(separator):
            var run = ""
            while index < chars.count, separators.contains(chars[index]) {
                run.append(chars[index])
                index += 1
            }
            segmentStart = index
            lastSeparatorWasPipe = run.contains("|") && run != "||"
        default:
            index += 1
        }
    }
    if inSingle || inDouble { return nil } // 따옴표가 닫히지 않았다 — 판정 불가
    if lastSeparatorWasPipe { return nil } // 파이프로 받은 claude는 TUI가 성립하지 않는다
    return String(chars[segmentStart...])
}

/// 명령의 **마지막 simple command**가 인자 없는 `claude` 호출인가. 참이면 끝에 positional
/// 프롬프트 하나를 덧붙여도 claude가 그것을 첫 메시지로 받는다.
///
/// 덧붙이는 것은 인자 하나뿐이라 제어 흐름을 만들 수 없다 — 그래서 오판의 최악은 "프롬프트가
/// 조용히 누락"이고, 그때는 전부 주입 폴백(오늘의 동작)으로 간다. 판정이 애매한 모양은 모두
/// 거짓으로 보낸다: 주석 뒤에 붙이면 추가분까지 주석이 되고, 파이프·리다이렉트는 덧붙인 인자의
/// 의미를 바꾸며, **플래그가 하나라도 있으면 그 플래그가 우리 인자를 값으로 먹을 수 있다**
/// (실측: `claude -p --resume "Reply with exactly: OK"` → `Provided value "Reply with exactly:
/// OK" is not a UUID` — 프롬프트가 `--resume`의 값으로 삼켜졌다). 어떤 플래그가 값을 먹는지는
/// claude의 플래그 표를 알아야 하는데 그 표는 버전마다 바뀌므로, 플래그가 보이면 판정을 접는다.
public func commandAcceptsAppendedClaudePrompt(_ command: String) -> Bool {
    guard let segment = lastSimpleCommandSegment(in: command) else { return false }
    return segment.split(whereSeparator: \.isWhitespace) == [claudeExecutableName[...]]
}

// MARK: - 프롬프트 조립 스크립트

/// 선실행과 조립을 맡는 셸. claude의 `!`도 자기 Bash 도구에서 도므로 사용자 대화형 셸(zsh 등)이
/// 아니라 `sh`가 오히려 현행 의미론에 가깝다 — 대신 zoxide의 `z` 같은 셸 함수는 여기서도
/// 쓸 수 없다(claude의 `!`에서도 마찬가지다).
let claudePromptShell = "/bin/sh"

/// argv 예산에서 뺄 여유분. ARG_MAX는 argv와 환경변수의 **합**에 걸리고, 우리 명령줄·다른 인자·
/// 환경 증가분이 그 안에 함께 들어간다. 실측 기준(ARG_MAX 1,048,576 / env 6,193바이트)에서
/// 64KiB는 넉넉하다.
public let claudeArgvBudgetSlack = 65536

let claudePromptScriptPrefix = "tc-prompt-"
let claudePromptContextPrefix = "tc-context-"

/// 한도를 넘었을 때 argv에 싣는 지시. 절단하지 않는다 — 전체 컨텍스트를 파일로 남기고 claude가
/// 읽게 한다. 기본 권한 모드에서는 Read 승인 프롬프트가 한 번 뜰 수 있다(희귀 엣지, 수용).
let claudeContextPointerInstruction =
    "The context for this task was too large to pass on the command line, "
    + "so it was written to a file. Read this file in full before doing anything else:"

/// 스크립트가 사라진 뒤에 명령이 실행됐을 때(회수 스윕과 겹친 경우) argv가 빈 문자열이 되는 것을
/// 막는다 — 빈 프롬프트는 claude에 빈 메시지를 제출시킬 수 있다.
let claudePromptLostInstruction =
    "Terminal Checkout: the prepared context was lost before claude started. "
    + "Ask the user what they wanted to do."

/// `!` 입력이 프롬프트에 남길 출처 표시. 출력만 있으면 claude가 무엇을 실행한 결과인지 모른다.
func claudePromptBanner(for input: String) -> String { "==== \(input) ====" }

/// **argv 첫 메시지가 화면에 렌더됐음을 밖에서 확인하기 위한 표식 — 변환기와 꼬리 게이트의 단일 정본.**
///
/// 왜 필요한가(실측, claude 2.1.238, bare pty, 시점당 3회 전건 일치): **argv 제출이 입력창을
/// 비운다.** argv 메시지가 렌더되기 전에 타이핑한 바이트는 입력창에 들어갔다가 그 clear에
/// 지워진다(유실 3/3). 그런데 raw 모드 전환은 0.1∼0.19초, argv 렌더는 2.06∼3.41초로 65%
/// 흔들려 **[포그라운드=claude + raw 모드]는 이 시점을 전혀 가리지 못하고, 시간 기반 대기도
/// 성립하지 않는다.** 밖에서 얻을 수 있는 신호는 화면에 렌더된 메시지 자체뿐이다.
///
/// 배너와 같은 모양인 것은 메시지에 새 시각 요소를 더하지 않기 위해서다. 다만 **기존 첫 배너에
/// 얹지 않고 독립된 첫 줄로 둔다** — 첫 입력이 `!`가 아니면 배너 자체가 없어 마커가 조용히
/// 사라지고, 그러면 게이트가 영영 통과하지 못해 꼬리가 통째로 버려진다.
///
/// 토큰이 요청 고유이므로 Warp에서는 이 문자열의 존재 확인이 그 순간의 pane 증명을 겸한다.
/// 명령줄 에코에 남는 스크립트 경로(`tc-prompt-<token>.sh`)와 겹치지 않도록 게이트는 줄 전체를 본다.
public func claudeArgvRenderMarker(token: String) -> String {
    "==== terminal-checkout tc-\(token) ===="
}

/// pane 안에서 첫 메시지를 조립하는 스크립트 텍스트.
///
/// **이 스크립트에는 사용자 텍스트가 문법으로 들어가는 자리가 없다.** 배너와 대화형 입력은
/// 앱이 단일 인용해 `printf`의 **인자**로 넣고, `!` 본문도 단일 인용해 `sh -c`에 넘긴다 —
/// 본문에 문법 오류가 있어도 그 `sh -c` 안에 갇히고 스크립트 전체가 파싱 실패하지 않는다.
/// 절단은 하지 않는다(사용자 결정). 한도 초과는 파일 포인터로 우회한다.
///
/// 조립이 claude 호출 시점에 도는 것이 핵심이다 — `z {repo} && … && cd ../worktree && claude`에서
/// `!gh`가 볼 cwd는 마지막 `cd` 뒤이고, 앱은 그 경로를 모른다.
///
/// `marker`는 꼬리 주입이 있을 때만 준다(`claudeArgvRenderMarker`). 컨텍스트 블록 **밖**에서
/// stdout으로 직접 내보내므로 한도 초과로 본문이 파일에 남는 갈래에서도 argv에 실린다 —
/// 실리지 않으면 게이트가 통과하지 못해 꼬리가 버려진다.
public func claudePromptScriptBody(
    prefix: [String], contextPath: String, marker: String? = nil,
    argvSlack: Int = claudeArgvBudgetSlack
) -> String {
    var lines = [
        "#!/bin/sh",
        "# \(appDisplayName)이 자동 생성합니다 — claude 첫 메시지를 조립합니다.",
        "TC_CTX=\(shellSingleQuoted(contextPath))",
        "{",
    ]
    for input in prefix {
        if input.hasPrefix("!") {
            let body = String(input.dropFirst()).trimmingCharacters(in: .whitespaces)
            lines.append("printf '%s\\n' \(shellSingleQuoted(claudePromptBanner(for: input)))")
            // 앞 명령이 실패해도 뒤 명령은 돈다 — `&&`로 이으면 첫 실패가 나머지를 삼킨다.
            // `2>&1`은 실패 출력도 `!`와 같이 프롬프트에 남기기 위한 것이다
            lines.append("\(claudePromptShell) -c \(shellSingleQuoted(body)) 2>&1")
        } else {
            lines.append("printf '%s\\n' \(shellSingleQuoted(input))")
        }
        lines.append("printf '\\n'") // 블록 경계 — 붙여 쓰면 입력들이 한 덩어리로 읽힌다
    }
    lines += [
        "} > \"$TC_CTX\"",
        // 리다이렉트가 실패해도 셸은 다음 줄로 넘어간다(실측) — 그대로 두면 `cat`이 아무것도
        // 못 내놓고 **빈 문자열이 claude의 첫 메시지로 제출된다.** 실패로 끝내 부착 쪽의
        // `|| printf <claudePromptLostInstruction>`가 대신 말하게 한다. 접두사가 비어 있지
        // 않으면 블록은 최소 한 바이트를 쓰므로, 0바이트는 언제나 사고다
        "[ -s \"$TC_CTX\" ] || exit 1",
    ]
    if let marker {
        // 메시지의 **첫 줄**이다 — TUI가 긴 메시지를 접어도 앞부분이 가장 오래 보인다
        lines.append("printf '%s\\n' \(shellSingleQuoted(marker))")
    }
    lines += [
        // 산술 치환을 거쳐 정수로 만든다 — `wc`는 앞에 공백을 붙이고 `test -le`는 그것을 싫어한다
        "TC_SIZE=$(( $(wc -c < \"$TC_CTX\") + 0 ))",
        "TC_BUDGET=$(( $(getconf ARG_MAX) - $(env | wc -c) - \(argvSlack) ))",
        "if [ \"$TC_SIZE\" -le \"$TC_BUDGET\" ]; then",
        "cat \"$TC_CTX\"",
        "command rm -f -- \"$TC_CTX\"",
        "else",
        "printf '%s\\n%s\\n' \(shellSingleQuoted(claudeContextPointerInstruction)) \"$TC_CTX\"",
        "fi",
        "",
    ]
    return lines.joined(separator: "\n")
}

/// 명령 끝에 프롬프트 치환을 덧붙인다. 스크립트는 자기 일을 마친 뒤 **같은 치환 안에서** 지워진다
/// (spawn-claude와 같은 방식) — 체인이 claude에 닿지 못하면 치환이 아예 돌지 않으므로, 나중에 뜬
/// claude가 옛 프롬프트를 집는 창이 생기지 않는다.
public func appendedPromptCommand(_ command: String, scriptPath: String) -> String {
    let quoted = shellSingleQuoted(scriptPath)
    let trimmed = command.replacingOccurrences(
        of: "[ \t]+$", with: "", options: .regularExpression
    )
    return trimmed + " \"$(\(claudePromptShell) \(quoted)"
        + " || printf '%s' \(shellSingleQuoted(claudePromptLostInstruction));"
        + " command rm -f -- \(quoted))\""
}

// MARK: - 요청 준비

/// 실행 직전까지 준비된 요청.
public struct PreparedRequest {
    /// 터미널에 보낼 최종 명령 (병합 접두사가 argv로 붙어 있을 수 있다)
    public let command: String
    /// 주입 경로로 보낼 입력들. **비어 있으면 Warp 헬퍼도 손쉬운 사용 권한도 필요 없다**
    public let claudeInputs: [String]
    /// 명령이 터미널에 닿지 못했을 때 지워야 하는 파일들
    public let temporaryPaths: [String]
    /// 꼬리를 치기 전에 화면에서 찾아야 하는 문자열(`claudeArgvRenderMarker`). **꼬리가 있을
    /// 때만** 있다 — 꼬리가 없으면 볼 사람이 없고, 프리셋의 첫 메시지에 줄 하나를 얹는 대가만
    /// 남는다. nil이면 게이트도 없다(argv가 없는 순수 주입 폴백이 그렇다).
    public let argvRenderMarker: String?

    public func discardTemporaryFiles() {
        for path in temporaryPaths { unlink(path) }
    }
}

/// 회수해도 되는 이름인가 — 우리 접두사 + 16진 토큰 + 정해진 확장자.
func claudePromptFileIsOurs(name: String) -> Bool {
    for (prefix, suffix) in [(claudePromptScriptPrefix, ".sh"), (claudePromptContextPrefix, ".txt")] {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { continue }
        let token = name.dropFirst(prefix.count).dropLast(suffix.count)
        return !token.isEmpty && token.allSatisfy(\.isHexDigit)
    }
    return false
}

/// 요청마다 다른 16진 토큰. 헬퍼 소켓·Tab Config와 같은 생성기를 쓴다 — 요청 고유 문자열이
/// 필요한 자리가 늘어도 뽑는 곳은 하나다.
func claudePromptToken() -> String { warpHelperToken() }

/// 새로 만드는 경우에만 쓴다(`O_EXCL`) — 토큰이 겹쳤다면 그것은 남의 파일일 수도 있으므로
/// 덮어쓰지 않는다. 0600은 스크립트에 사용자 설정의 `!` 본문과 지시문이 담기기 때문이다.
/// 조립 결과(PR·이슈 본문)가 담기는 컨텍스트 파일은 pane의 셸이 자기 umask로 만들지만,
/// 임시 디렉토리 자체가 `drwx------`라 다른 사용자는 들어오지 못한다(같은 uid는 이 리포의
/// 선언된 신뢰 경계 안이다 — `SECURITY.md`).
private func writeNewPrivateFile(path: String, contents: String) -> Bool {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { return false }
    defer { close(descriptor) }
    guard writeAll(fd: descriptor, data: Data(contents.utf8)) else {
        unlink(path)
        return false
    }
    return true
}

/// 정상 경로는 스스로 치운다(스크립트는 치환 안에서, 컨텍스트는 예산 이내면 `cat` 직후).
/// 남는 것은 두 갈래다: 탭이 끝내 열리지 않아 치환이 돌지 못한 스크립트, 그리고 **한도 초과로
/// 일부러 남긴 컨텍스트**. 후자는 claude가 세션 중에 읽어야 하므로 나이를 넉넉히 본다.
func reclaimStaleClaudePromptFiles(
    in directory: String = NSTemporaryDirectory(), olderThan age: TimeInterval = 6 * 3600
) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where claudePromptFileIsOurs(name: name) {
        let path = (directory as NSString).appendingPathComponent(name)
        var info = stat()
        // 심볼릭 링크를 따라가지 않는다 — 따라가면 링크가 가리키는 남의 파일을 지운다
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else { continue }
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        guard Date().timeIntervalSince(modified) > age else { continue }
        unlink(path)
    }
}

/// 요청을 실행 가능한 형태로 바꾼다. 병합할 접두사가 있고 명령 꼬리에 붙일 수 있으면 argv로
/// 싣고 꼬리만 주입에 남긴다. 어느 조건이든 어긋나면 **전부 주입**(오늘의 동작)으로 되돌린다 —
/// 변환에 확신이 없을 때 기본값은 폴백이다.
///
/// 던지지 않는다: 이 변환은 요청을 실패시킬 수 없다. 임시 파일을 쓰지 못하면 거절이 아니라
/// 폴백이다 — 여기서 던지면 오늘 잘 돌던 요청이 디스크 사정으로 실패하게 된다.
public func prepareRequest(_ resolved: ResolvedRequest) -> PreparedRequest {
    func injectEverything() -> PreparedRequest {
        PreparedRequest(
            command: resolved.command, claudeInputs: resolved.claudeInputs,
            temporaryPaths: [], argvRenderMarker: nil
        )
    }

    let plan = claudeInputPlan(resolved.claudeInputs)
    guard !plan.prefix.isEmpty, commandAcceptsAppendedClaudePrompt(resolved.command) else {
        return injectEverything()
    }
    // 앱이 죽어 남은 이전 실행의 찌꺼기부터 회수한다 (나이로 가르므로 살아 있는 것은 건드리지 않는다)
    reclaimStaleClaudePromptFiles()

    let token = claudePromptToken()
    let scriptPath = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("\(claudePromptScriptPrefix)\(token).sh")
    let contextPath = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("\(claudePromptContextPrefix)\(token).txt")
    // 꼬리를 칠 때만 마커를 싣는다 — 칠 것이 없으면 화면을 볼 일도 없다
    let marker = plan.tail.isEmpty ? nil : claudeArgvRenderMarker(token: token)
    let body = claudePromptScriptBody(prefix: plan.prefix, contextPath: contextPath, marker: marker)
    guard writeNewPrivateFile(path: scriptPath, contents: body) else {
        checkoutLog("프롬프트 조립 스크립트를 쓰지 못해 claude 입력 \(resolved.claudeInputs.count)개를 주입 경로로 보낸다")
        return injectEverything()
    }
    return PreparedRequest(
        command: appendedPromptCommand(resolved.command, scriptPath: scriptPath),
        claudeInputs: plan.tail,
        temporaryPaths: [scriptPath],
        argvRenderMarker: marker
    )
}
