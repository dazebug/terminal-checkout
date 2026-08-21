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

/// 명령 끝에 프롬프트 인자 하나를 덧붙여도 되는가 — **화이트리스트 문법 스캐너**.
///
/// 예전 판정은 "마지막 조각의 토큰이 `claude`인가"만 봤고, 근거는 "오판의 최악은 조용한
/// 누락"이었다. **그 근거는 거짓임이 재현으로 증명됐다**(외부 검증자):
///  - `echo ready # && claude` → 마지막 토큰은 `claude`지만 전부 주석이다(조용한 누락)
///  - `cat <<claude` … `claude` → 그 `claude`는 heredoc **종료 표식**이다. 인자를 붙이면
///    표식이 달라져 셸이 입력을 기다리며 멈춘다(파손)
///  - `claude() { /bin/sh -c "$1"; }` ⏎ `claude` → 앞에서 정의된 **함수**가 이름을 가로채,
///    우리가 붙인 평문 입력이 셸 명령으로 **실행된다**(임의 실행)
///
/// 그래서 마지막 조각만 보지 않고 명령 전체를 훑어, **허용 목록에 없는 문법이 인용 밖에
/// 하나라도 보이면 접는다**(→ 전부 주입 폴백 = 오늘의 동작). 허용하는 것은
/// `&&`·`||`·`;`·`|`로 이어진 simple command 열과 그룹(`{ }`)·서브셸(`( )`)뿐이고,
/// 그 위에서 **마지막 simple command가 정확히 `claude` 한 토큰**이라야 참이다.
///
/// 플래그도 접는 이유는 따로 있다(실측): `claude -p --resume "Reply with exactly: OK"` →
/// `Provided value … is not a UUID` — 값을 선택적으로 먹는 플래그가 우리 인자를 삼킨다.
/// 어떤 플래그가 값을 먹는지는 claude의 플래그 표를 알아야 하고 그 표는 버전마다 바뀐다.
///
/// **막지 못하는 것**(스캐너가 볼 수 없는 자리): 사용자 rc가 정의한 `claude` 함수·별칭.
/// 명령 텍스트에 그 정의가 없으므로 판정할 방법이 없다 — `docs/new-terminal-checklist.md`의
/// 소탕 표에 잔여로 적었다.
public func commandAcceptsAppendedClaudePrompt(_ command: String) -> Bool {
    let chars = Array(command)
    // 그룹·서브셸의 여닫이는 명령 열을 가르는 자리이기도 하다 — 마지막 조각을 찾는 데 쓴다
    let separators: Set<Character> = ["&", "|", ";", "(", ")", "{", "}"]
    var index = 0
    var segmentStart = 0
    var lastSeparatorWasPipe = false
    var previous: Character?          // 직전 문자(공백 포함) — 주석 판정용
    var previousMeaningful: Character? // 직전 비공백 문자 — 함수 정의 판정용

    /// 단어의 첫 글자 자리인가. `#`는 여기서만 주석이다(`echo a#b`의 `#`는 리터럴)
    func atWordStart() -> Bool {
        guard let previous else { return true }
        return previous.isWhitespace || separators.contains(previous)
    }

    while index < chars.count {
        let character = chars[index]
        if character == "'" {
            // 작은따옴표 안에는 이스케이프가 없다 — 다음 `'`까지 통째로 데이터다
            var scan = index + 1
            while scan < chars.count, chars[scan] != "'" { scan += 1 }
            guard scan < chars.count else { return false } // 닫히지 않은 인용 = 판정 불가
            index = scan + 1
            previous = "'"
            previousMeaningful = "'"
            continue
        }
        if character == "\"" {
            var scan = index + 1
            while scan < chars.count {
                let inner = chars[scan]
                if inner == "\\" {
                    scan += 2
                    continue
                }
                // 큰따옴표 안에서도 치환은 살아 있다
                if inner == "`" { return false }
                if inner == "$", scan + 1 < chars.count, chars[scan + 1] == "(" { return false }
                if inner == "\"" { break }
                scan += 1
            }
            guard scan < chars.count else { return false }
            index = scan + 1
            previous = "\""
            previousMeaningful = "\""
            continue
        }
        switch character {
        case "\\", "\n", "`":
            return false // 줄이음·개행(명령이 하나 더 있다)·백틱 치환
        case "#" where atWordStart():
            return false // 주석 — 뒤에 붙이는 것이 전부 삼켜진다
        case "$" where index + 1 < chars.count && chars[index + 1] == "(":
            return false // 명령 치환
        case "<" where index + 1 < chars.count && chars[index + 1] == "<":
            return false // heredoc — 마지막 토큰이 종료 표식일 수 있다
        case "(" where !(previousMeaningful.map(separators.contains) ?? true):
            return false // 단어 바로 뒤의 `(` = 함수 정의. 명령 위치의 `(`는 서브셸이라 허용
        default:
            break
        }
        guard separators.contains(character) else {
            index += 1
            previous = character
            if !character.isWhitespace { previousMeaningful = character }
            continue
        }
        var run = ""
        while index < chars.count, separators.contains(chars[index]) {
            run.append(chars[index])
            index += 1
        }
        // `&`는 정확히 둘일 때만 and다. 하나면 백그라운드이고, 그 뒤에 붙인 인자는
        // **다음 명령**이 되어 실행된다
        var scan = run.startIndex
        while scan < run.endIndex {
            guard run[scan] == "&" else {
                scan = run.index(after: scan)
                continue
            }
            var count = 0
            while scan < run.endIndex, run[scan] == "&" {
                count += 1
                scan = run.index(after: scan)
            }
            if count != 2 { return false }
        }
        // `||`는 or이지 파이프가 아니다 — 덩어리 끝을 보고 가른다
        lastSeparatorWasPipe = run.hasSuffix("|") && !run.hasSuffix("||")
        segmentStart = index
        previous = run.last
        previousMeaningful = run.last
    }
    if lastSeparatorWasPipe { return false } // 파이프로 받은 claude는 TUI가 성립하지 않는다
    let segment = String(chars[segmentStart...])
    let tokens = segment.split(whereSeparator: \.isWhitespace).map(String.init)
    return tokens == [claudeExecutableName]
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

/// 스크립트가 부르는 유틸리티의 **절대 경로**. PATH를 타면 사용자가 통제하는 디렉토리의
/// 동명 프로그램이 돈다 — 재현: 명령이 `PATH="$PWD/bin:$PATH" && claude`이고 저장소에
/// `bin/getconf`가 있으면, claude 입력이 평문 하나여도 그 프로그램이 실행됐다.
/// 절대 경로는 PATH뿐 아니라 **셸 함수·별칭**도 지나친다(이름에 `/`가 들어갈 수 없다).
enum ShellUtility {
    static let getconf = "/usr/bin/getconf"
    static let env = "/usr/bin/env"
    static let wc = "/usr/bin/wc"
    static let tr = "/usr/bin/tr"
    static let cat = "/bin/cat"
    static let printf = "/usr/bin/printf"
    static let rm = "/bin/rm"
}

/// 요청 하나가 쓰는 것은 **디렉토리 하나**다. 임시 디렉토리에 파일 두 개를 흩어 놓으면 이름이
/// 예측 가능해 남이 미리 링크를 놓을 수 있고(재현됨), 회수도 파일 단위라 "이 컨텍스트가 아직
/// 필요한가"를 알 수 없다. 디렉토리는 `mkdir`로 원자적으로 잡는다 — 이미 있으면 실패한다.
let claudePromptDirectoryPrefix = "tc-prompt-"
let claudePromptTokenLength = 8
let claudePromptScriptName = "prompt.sh"
let claudePromptContextName = "context.txt"
/// 한도 초과 갈래가 남기는 표식. 이 파일이 있으면 컨텍스트를 claude가 세션 중에 읽는다는 뜻이라
/// 회수 스윕이 훨씬 길게 봐준다
let claudePromptHandoffName = "handed-to-claude"

/// 환경 항목 하나가 argv 예산에서 차지하는 바이트(포인터 + 정렬 여유). `env | wc -c`는 문자열만
/// 세므로 이것을 더 빼지 않으면 항목이 많은 환경에서 execve가 E2BIG로 실패한다(재현됨).
public let claudeArgvEnvEntryOverhead = 32

func claudePromptHandoffPath(forContext contextPath: String) -> String {
    ((contextPath as NSString).deletingLastPathComponent as NSString)
        .appendingPathComponent(claudePromptHandoffName)
}

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
/// 토큰이 요청 고유이므로 Warp에서는 이 문자열 확인이 그 순간의 pane 증명을 겸한다. 명령줄
/// 에코에 남는 스크립트 경로(`tc-prompt-<token>/prompt.sh`)와 겹치지 않도록 줄 전체를 본다.
///
/// **짧아야 한다**: 게이트는 `screenReflectsNewInput`를 그대로 쓰고, 그 함수는 앞
/// `claudeInputProbe`(24자)만 비교한다 — 토큰이 24자 밖으로 밀려나면 요청 고유성이 사라진다.
public func claudeArgvRenderMarker(token: String) -> String { "==== tc-\(token) ====" }

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
    let printf = ShellUtility.printf
    var lines = [
        "#!/bin/sh",
        "# \(appDisplayName)이 자동 생성합니다 — claude 첫 메시지를 조립합니다.",
        "# 우리가 부르는 유틸리티는 전부 절대 경로다. PATH를 타면 사용자 저장소의 `bin/getconf`",
        "# 같은 것이 돈다(재현됨) — 평문 입력 하나로 임의 프로그램이 실행되는 경로였다. 대신",
        "# PATH 자체는 건드리지 않는다: `!` 본문(사용자 명령)이 gh 등을 찾아야 한다.",
        "TC_CTX=\(shellSingleQuoted(contextPath))",
        // 생성이 `O_EXCL`이 되어 **심볼릭 링크를 따라가지 않는다** — 링크가 놓여 있으면 열리지
        // 않고 실패한다(재현: 맨 `>`는 링크가 가리키는 사용자 파일을 덮어썼다)
        "set -C",
        "{",
    ]
    for input in prefix {
        if input.hasPrefix("!") {
            let body = String(input.dropFirst()).trimmingCharacters(in: .whitespaces)
            lines.append("\(printf) '%s\\n' \(shellSingleQuoted(claudePromptBanner(for: input)))")
            // 앞 명령이 실패해도 뒤 명령은 돈다 — `&&`로 이으면 첫 실패가 나머지를 삼킨다.
            // `2>&1`은 실패 출력도 `!`와 같이 프롬프트에 남기기 위한 것이다
            lines.append("\(claudePromptShell) -c \(shellSingleQuoted(body)) 2>&1")
        } else {
            lines.append("\(printf) '%s\\n' \(shellSingleQuoted(input))")
        }
        lines.append("\(printf) '\\n'") // 블록 경계 — 붙여 쓰면 입력들이 한 덩어리로 읽힌다
    }
    lines += [
        "} > \"$TC_CTX\" || exit 1",
        "set +C",
        // 두 겹으로 막는다: `set -C`가 못 막는 셸이 있어도 링크면 여기서 멈춘다. `-s`를 먼저
        // 보면 링크가 가리키는 **남의 파일**이 비어 있지 않다는 이유로 통과해 그 내용이
        // 프롬프트로 나간다. 그리고 리다이렉트가 실패해도 셸은 다음 줄로 넘어가므로(실측),
        // 0바이트를 그냥 두면 **빈 문자열이 claude의 첫 메시지로 제출된다** — 실패로 끝내
        // 부착 쪽의 `|| printf <claudePromptLostInstruction>`가 대신 말하게 한다
        "if [ -L \"$TC_CTX\" ] || [ ! -f \"$TC_CTX\" ] || [ ! -s \"$TC_CTX\" ]; then exit 1; fi",
    ]
    if let marker {
        // 메시지의 **첫 줄**이다 — TUI가 긴 메시지를 접어도 앞부분이 가장 오래 보인다
        lines.append("\(printf) '%s\\n' \(shellSingleQuoted(marker))")
    }
    lines += [
        // 산술 치환을 거쳐 정수로 만든다 — `wc`는 앞에 공백을 붙이고 `test -le`는 그것을 싫어한다
        "TC_SIZE=$(( $(\(ShellUtility.wc) -c < \"$TC_CTX\") + 0 ))",
        // NUL을 뺀 크기. 다르면 NUL이 있다는 뜻이고, NUL은 명령 치환에서 조용히 사라진다
        // (`pre<NUL>post` → `prepost`, 재현됨) — 왜곡해 보내느니 파일로 넘긴다
        "TC_CLEAN=$(( $(\(ShellUtility.tr) -d '\\000' < \"$TC_CTX\" | \(ShellUtility.wc) -c) + 0 ))",
        // ARG_MAX는 문자열 바이트만이 아니라 **포인터 배열과 정렬**까지 포함한다. 문자열만 빼면
        // 항목이 많은 환경(재현: 9,000개·81,000바이트)에서 execve가 E2BIG로 실패한다
        "TC_ENV_BYTES=$(( $(\(ShellUtility.env) | \(ShellUtility.wc) -c) + 0 ))",
        "TC_ENV_COUNT=$(( $(\(ShellUtility.env) | \(ShellUtility.wc) -l) + 0 ))",
        "TC_BUDGET=$(( $(\(ShellUtility.getconf) ARG_MAX) - TC_ENV_BYTES"
            + " - TC_ENV_COUNT * \(claudeArgvEnvEntryOverhead) - \(argvSlack) ))",
        "if [ \"$TC_SIZE\" -le \"$TC_BUDGET\" ] && [ \"$TC_SIZE\" -eq \"$TC_CLEAN\" ]; then",
        // **지우지 않는다.** 예산 판정을 통과하고도 execve가 실패할 수 있고, 그때 이미 지웠다면
        // 조립한 내용이 통째로 사라진다. 회수 스윕이 나이를 보고 치운다
        "\(ShellUtility.cat) \"$TC_CTX\"",
        "else",
        "\(printf) '%s\\n%s\\n' \(shellSingleQuoted(claudeContextPointerInstruction)) \"$TC_CTX\"",
        // 이 갈래의 컨텍스트는 claude가 **세션 중에** 읽는다 — 회수 스윕이 짧은 나이로 지우면
        // 세션이 "읽으라던 파일이 없다"를 만난다. 표식을 남겨 스윕이 길게 봐주게 한다
        ": > \(shellSingleQuoted(claudePromptHandoffPath(forContext: contextPath)))",
        "fi",
        "",
    ]
    return lines.joined(separator: "\n")
}

/// 명령 끝에 프롬프트 치환을 덧붙인다. 스크립트는 자기 일을 마친 뒤 **같은 치환 안에서** 지워진다
/// (spawn-claude와 같은 방식) — 체인이 claude에 닿지 못하면 치환이 아예 돌지 않으므로, 나중에 뜬
/// claude가 옛 프롬프트를 집는 창이 생기지 않는다.
/// 이 문자열은 **사용자의 대화형 셸**이 평가한다 — 우리 스크립트보다 더 통제 밖이다. 그래서
/// `printf`·`rm`도 절대 경로로 부른다: `command rm`은 함수·별칭만 지나칠 뿐 PATH는 그대로 탄다.
/// 컨텍스트 파일은 여기서 지우지 않는다(회수 스윕의 몫) — 지우는 것은 스크립트 하나다.
///
/// **`--`를 먼저 넣는다.** 실측(claude 2.1.238, 조합당 2회 전건 일치): 값을 먹는 플래그가
/// 뒤 인자를 프롬프트 대신 자기 값으로 가져간다 — `claude -p --resume <SID> 'P'`뿐 아니라
/// **가변인자 플래그도** 그렇다(`claude -p --allowed-tools Bash 'P'` → 프롬프트가 삼켜져
/// exit 1). "값이 이미 붙어 있으면 안전하다"는 추론이 거짓이라는 뜻이다. `--`를 넣으면 그
/// 부류가 전부 막힌다(`--allowed-tools Bash -- 'P'` 전달됨). 지금은 bare `claude`에만 붙이니
/// 무해하고, 프롬프트가 `-`로 시작하게 되는 날(파일 포인터 문구·배너 변경)도 이것이 닫는다.
///
/// `--`가 **못 막는 것**: 명령에 이미 positional 프롬프트가 있으면 우리 것이 두 번째가 되어
/// **exit 0·stderr 없이 조용히 버려진다**(`claude -p 'first' 'second'` → first만 기록).
/// 그래서 판정은 여전히 "마지막 simple command가 bare `claude`"로 좁혀 둔다.
public func appendedPromptCommand(_ command: String, scriptPath: String) -> String {
    let quoted = shellSingleQuoted(scriptPath)
    let trimmed = command.replacingOccurrences(
        of: "[ \t]+$", with: "", options: .regularExpression
    )
    return trimmed + " -- \"$(\(claudePromptShell) \(quoted)"
        + " || \(ShellUtility.printf) '%s' \(shellSingleQuoted(claudePromptLostInstruction));"
        + " \(ShellUtility.rm) -f -- \(quoted))\""
}

// MARK: - 요청 준비

/// 실행 직전까지 준비된 요청.
public struct PreparedRequest {
    /// 터미널에 보낼 최종 명령 (병합 접두사가 argv로 붙어 있을 수 있다)
    public let command: String
    /// 주입 경로로 보낼 입력들. **비어 있으면 Warp 헬퍼도 손쉬운 사용 권한도 필요 없다**
    public let claudeInputs: [String]
    /// 이 요청만 쓰는 디렉토리. 명령이 터미널에 닿지 못했으면 통째로 지운다
    public let temporaryDirectory: String?
    /// 꼬리를 치기 전에 화면에서 찾아야 하는 문자열(`claudeArgvRenderMarker`). **꼬리가 있을
    /// 때만** 있다 — 꼬리가 없으면 볼 사람이 없고, 프리셋의 첫 메시지에 줄 하나를 얹는 대가만
    /// 남는다. nil이면 게이트도 없다(argv가 없는 순수 주입 폴백이 그렇다).
    public let argvRenderMarker: String?

    /// 조립 스크립트의 경로. 디렉토리가 없으면(폴백) nil이다
    public var scriptPath: String? {
        temporaryDirectory.map { ($0 as NSString).appendingPathComponent(claudePromptScriptName) }
    }

    public func discardTemporaryFiles() {
        guard let temporaryDirectory else { return }
        try? FileManager.default.removeItem(atPath: temporaryDirectory)
    }
}

/// 회수해도 되는 이름인가 — 우리 접두사 + **정확히 8자** 16진 토큰. 길이를 보지 않으면
/// `tc-prompt-a` 같은 남의 디렉토리도 우리 것이 된다.
func claudePromptDirectoryIsOurs(name: String) -> Bool {
    guard name.hasPrefix(claudePromptDirectoryPrefix) else { return false }
    let token = name.dropFirst(claudePromptDirectoryPrefix.count)
    return token.count == claudePromptTokenLength && token.allSatisfy(\.isHexDigit)
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

/// 스크립트는 치환 안에서 자기를 지우지만 **컨텍스트는 아무도 지우지 않는다** — 지우고 나서
/// execve가 실패하면 조립한 내용이 통째로 사라지기 때문이다(그 실패는 실제로 재현됐다).
/// 그래서 회수는 여기 한 곳이고, 나이를 두 가지로 본다:
///  - 보통은 짧게(기본 6시간). 스크립트가 돌았든(내용은 이미 argv로 갔다) 탭이 끝내 열리지
///    않았든, 그 시점엔 아무도 그 디렉토리를 필요로 하지 않는다
///  - **인계 표식이 있으면 길게**(기본 7일). 한도 초과 갈래에서 claude는 그 파일을 세션 중에
///    읽는다 — 다른 요청의 스윕이 6시간 뒤 지우면 "읽으라던 파일이 없다"가 된다
func reclaimStaleClaudePromptDirectories(
    in directory: String = NSTemporaryDirectory(),
    leftoverAge: TimeInterval = 6 * 3600, handedOffAge: TimeInterval = 7 * 24 * 3600
) {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
    for name in names where claudePromptDirectoryIsOurs(name: name) {
        let path = (directory as NSString).appendingPathComponent(name)
        var info = stat()
        // 심볼릭 링크를 따라가지 않는다 — 따라가면 링크가 가리키는 남의 디렉토리를 통째로 지운다
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else { continue }
        let handoff = (path as NSString).appendingPathComponent(claudePromptHandoffName)
        var handoffInfo = stat()
        let age = lstat(handoff, &handoffInfo) == 0 ? handedOffAge : leftoverAge
        let modified = Date(timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec))
        guard Date().timeIntervalSince(modified) > age else { continue }
        try? FileManager.default.removeItem(atPath: path)
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
            temporaryDirectory: nil, argvRenderMarker: nil
        )
    }

    let plan = claudeInputPlan(resolved.claudeInputs)
    guard !plan.prefix.isEmpty, commandAcceptsAppendedClaudePrompt(resolved.command) else {
        return injectEverything()
    }
    // 앱이 죽어 남은 이전 실행의 찌꺼기부터 회수한다 (나이로 가르므로 살아 있는 것은 건드리지 않는다)
    reclaimStaleClaudePromptDirectories()

    let token = claudePromptToken()
    let directory = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("\(claudePromptDirectoryPrefix)\(token)")
    // `withIntermediateDirectories: false`라 이미 있으면 던진다 — 원자적으로 잡는다는 뜻이고,
    // 남이 그 이름으로 놓아 둔 링크·디렉토리를 우리 것으로 쓰는 일이 없다
    guard (try? FileManager.default.createDirectory(
        atPath: directory, withIntermediateDirectories: false,
        attributes: [.posixPermissions: 0o700]
    )) != nil else {
        checkoutLog("프롬프트 작업 디렉토리를 만들지 못해 claude 입력 \(resolved.claudeInputs.count)개를 주입 경로로 보낸다")
        return injectEverything()
    }
    let scriptPath = (directory as NSString).appendingPathComponent(claudePromptScriptName)
    let contextPath = (directory as NSString).appendingPathComponent(claudePromptContextName)
    // 꼬리를 칠 때만 마커를 싣는다 — 칠 것이 없으면 화면을 볼 일도 없다
    let marker = plan.tail.isEmpty ? nil : claudeArgvRenderMarker(token: token)
    let body = claudePromptScriptBody(prefix: plan.prefix, contextPath: contextPath, marker: marker)
    guard writeNewPrivateFile(path: scriptPath, contents: body) else {
        checkoutLog("프롬프트 조립 스크립트를 쓰지 못해 claude 입력 \(resolved.claudeInputs.count)개를 주입 경로로 보낸다")
        try? FileManager.default.removeItem(atPath: directory)
        return injectEverything()
    }
    return PreparedRequest(
        command: appendedPromptCommand(resolved.command, scriptPath: scriptPath),
        claudeInputs: plan.tail,
        temporaryDirectory: directory,
        argvRenderMarker: marker
    )
}
