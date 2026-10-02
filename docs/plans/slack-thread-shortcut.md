# slack-thread-shortcut

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: `terminal-checkout` / `app`
- 시작 커밋: `21382f5101555401a3a71263cad2441b9e37981b`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/slack-thread-review` (`worktree-slack-thread-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-slack-thread-work` (`slack-thread`)
- 현재: R1 · 마지막 승격 7d77777 · 리뷰 중 없음 · 게이트 그린(드라이버, clone)
- 최근 검증자 판정: 없음 (R0 계획 초안) · 원문 없음

이 파일은 실행한 계획과 실행할 계획의 기록이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실을 기록한다. 코드 수정 과정은 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다. 결정이나 질문이 특정 동작에 걸리면 한 절과 `파일:행`으로 끝낸다. 템플릿에 없는 소절을 만들지 않는다 — 테스트 설계는 테스트 파일이 말한다.

## 배경 — 확인한 원천

문제를 파악하며 확인한 영구 소스만 — 세션이 끝나도 남는 것. 사용자가 제공한 실측은 출처가 세션 입력임을 밝히고, 실측되지 않은 것은 열린 질문에 둔다.

- `CLAUDE.md` — 실행은 앱 소유여야 하며, Claude 입력 전달과 NFD 및 AppKit 레이아웃의 실측된 경계를 지켜야 한다
- `docs/context/index.md` · `docs/context/claude-input-delivery.md` · `docs/context/subprocess-execution.md` · `docs/context/localization.md` · `docs/context/testing.md` · `docs/context/setup-window-placement.md` · `docs/context/signing-and-permissions.md` · `docs/context/repository-entry.md` — 기존 설계의 이유, 입력 전달의 한계, 다국어 UI·테스트의 근거
- [Slack Help — Manage apps in an Enterprise organization](https://slack.com/help/articles/360000281563-Manage-apps-in-an-Enterprise-organization) — 설치된 앱은 기본적으로 워크스페이스 전원이 쓰고, 사용자별 제한은 Enterprise 전용
- [Slack docs — Using Socket Mode](https://docs.slack.dev/apis/events-api/using-socket-mode) — 연결이 여러 개면 payload는 그중 아무 연결로나 전달됨
- [Apple — Run a shortcut while working on your Mac](https://support.apple.com/en-asia/guide/shortcuts-mac/apd163eb9f95/mac) — 키보드 단축키는 단축어 상세에서 사용자가 지정
- [Apple — Run shortcuts from the command line](https://support.apple.com/guide/shortcuts-mac/run-shortcuts-from-the-command-line-apd455c82f02/mac) — `shortcuts run`과 `shortcuts sign` 사용법
- 사용자 배정 (2026-10-02) — 트리거·URL 스킴·설정 소유권·단축어 설치 방식·비목표 및 위협 모델
- 드라이버 실측 (2026-10-02) — `shortcuts sign --mode people-who-know-me` 성공, 산출물의 `AEA1` 매직, 사용자 hotkey 지정 경로, `/usr/bin/shortcuts help`의 `run`·`list`·`view`·`sign` 하위 명령과 삭제 명령 부재; Darwin 27.0.0 AppKit 프로브에서 cold URL `open`/`open -g`는 `launchIsDefault=0`, URL callback은 didFinish보다 먼저 오고 그 안의 event는 `GURL/GURL`, willFinish의 `currentAppleEvent`는 nil; 일반 `open`과 relay식 `open -g -b … --args --background`는 `launchIsDefault=1` 및 `aevt/oapp`, 이미 실행 중인 앱은 URL callback만 받음. 가져온 단축어 이름은 파일명(확장자 제외)이고 현재 `shortcuts run`은 exit 0으로 끝나도 빈 `url` 값을 앱에 보냄. URL 런치 실측은 설치 위치인 `∼/Applications`에서 한정하며 `/tmp` 번들은 `kLSApplicationNotFoundErr`로 URL을 받지 못함

## 목표

`terminal-checkout://slack-thread?url=<퍼센트 인코딩된 Slack 메시지 링크>` 한 건을 받으면, 앱이 URL과 앱 설정을 검증해 설정된 작업 폴더에서 `claude`를 시작한다.
작업 폴더와 지시문은 앱 로컬 설정에서만 읽으며 입력 하나를 `<링크>` 또는 `<링크> <지시문>` 순으로 만든다 (지시문이 비면 링크만 전달한다).
요청은 기존 `prepareRequest`와 `runInTerminal` 경로, terminal 및 tab activation 설정을 그대로 이용하고 항상 Claude argv 경로를 탄다.
설정 창은 작업 폴더·지시문·단축어 상태·키보드 단축키 안내를 제공하고, 앱이 생성해 서명한 단축어는 단축어 앱의 가져오기 흐름으로 연다.

## 완료의 정의

- 반드시 막아야 할 실패:
  - 바깥 URL에서 `url` 외의 쿼리 키, `url`의 중복, scheme·host·path 불일치를 거부해 URL로 명령·폴더·지시문을 바꾸지 못하게 한다.
  - 허용하지 않은 Slack 도메인·permalink 경로·ID·query·percent escape를 거부하고, 검증한 메시지 링크 한 건만 입력에 넣는다.
  - 작업 폴더가 비었거나 `normalizedBaseDirectory` 검증을 통과하지 못하면 터미널을 열지 않는다. 공백이 든 경로는 거부하고 UI가 이유를 보인다. 지시문은 비어도 허용하되 LF·CR·C0·DEL은 거부한다.
  - 조립된 `cd <검증된 작업 폴더> && claude`가 `commandAcceptsAppendedClaudePrompt`를 통과하지 않거나 `prepareRequest`가 typed input을 남기면 입력 타이핑으로 폴백하지 않고 세션을 열기 전에 가시 오류로 실패한다.
  - URL 런치 성공이 자동으로 설정 창을 띄우거나, URL 거부·실행 실패가 조용히 사라지거나, 실패를 성공처럼 보이는 결과를 허용하지 않는다.
  - 단축어 서명·열기·설치 상태 확인 실패를 `설치됨`으로 표시하지 않고 설정 UI에 실패 이유를 보인다. 단축어 가져오기 창을 열었다는 사실만으로 가져오기 완료나 단축키 설정 완료를 주장하지 않는다.
- acceptance oracle: Core 테스트가 합성 Slack URL과 외곽 URL의 수락·거부 경계, 양끝 ASCII 공백·탭·CR·LF 제거, 512 UTF-8 byte 상한, 원본 링크 보존, `thread_ts` 형식, `cid` 불일치 허용, 공유 URL 상수 및 `<링크> <지시문>` 입력 조립을 증명한다. `normalizedBaseDirectory` 형식의 대표 작업 폴더로 `cd <폴더> && claude`가 append scanner를 통과하고 `prepareRequest`가 입력을 `appendedPromptCommand`에 넣어 typed input을 남기지 않는 Core 테스트를 둔다; 거부·shell admission 불가 때 typed fallback이 되지 않고 실패하는 것도 고정한다. 앱 테스트는 `Info.plist`의 `CFBundleURLSchemes`와 Core URL scheme 상수의 일치, 런치 종류별 자동 표시, 오류 훅을 확인한다. 드라이버는 앱을 `∼/Applications`에 설치한 뒤 cold URL·실행 중 URL·성공 무창·오류 창을 실기기에서 확인하고 생성한 shortcut을 가져와 `shortcuts run`이 인코딩된 Slack link 전체를 정확히 한 URL로 여는지 확인한다; `/tmp`에서 LaunchServices URL 수신을 시험하지 않는다.
- 코퍼스 범위: 리포에는 실사용 작업 폴더·지시문·Slack 워크스페이스명·채널 ID를 넣지 않는다. 픽스처는 `example.slack.com`과 합성 C/G/D ID·타임스탬프만 쓴다. 실제 값은 로컬 driver 확인에만 쓰고 계획·테스트에 복사하지 않는다.
- 원자성·부분 실패·롤백 경계: 유효한 URL 이벤트 하나는 terminal session 하나를 요청한다. 같은 URL을 다시 열면 새 요청·새 session이며 URL에 operation ID가 없어 의도적 재실행과 재시도를 구별하지 않는다. 실행 결과가 모호하면 전체 URL 요청을 자동 재시도하지 않고 실패를 표시한다. 이미 열린 terminal tab은 롤백하지 않으며, 앱은 command send 완료만으로 Claude 수신을 보장한다고 말하지 않는다. Slack 경로에는 비동기 typing 단계와 typed delivery partial failure가 없다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

이 루프가 막는 실패를 일으킬 수 있는 행위자와 능력은 다음과 같다. Slack 스레드 작성자의 본문은 Claude가 사용자 MCP로 읽는 비신뢰 입력이며, prompt injection은 GitHub 이슈 본문과 같은 별도 위험으로 범위 밖이다.

- 사용자: Slack 데스크톱에서 링크를 복사하고 앱의 작업 폴더·지시문을 설정해 단축키를 실행한다. 같은 링크를 의도적으로 다시 실행할 수 있다.
- 사용자의 브라우저에서 열린 임의 웹페이지: 사용자가 외부 앱 열기를 승인하면 원하는 URL 내용을 넣어 scheme을 열 수 있다. 수신 앱은 호출 앱을 신뢰하지 않는다.
- 같은 macOS uid의 로컬 프로세스: 사용자 확인 없이 URL을 열 수 있고 앱의 uid 제한 unix socket에도 이미 접근할 수 있다.
- Slack 스레드 작성자: 스레드 내용과 링크된 본문을 조절할 수 있다. 앱은 Slack API를 호출하지 않으며 작성자 입력을 정화하거나 지시문으로 승격하지 않는다.

## 비목표 — 건드리지 않는다

- `extension/` 및 GitHub 버튼 경로: 트리거는 Slack 데스크톱 앱의 링크 복사와 단축어이며 확장 콘텐츠 스크립트는 데스크톱 앱을 보지 못한다.
- Slack API·Socket Mode 앱·OAuth·앱별 MCP 설정: 스레드는 사용자의 Claude Slack MCP가 읽고 Terminal Checkout은 링크만 전달한다.
- 단축키 자동 지정 및 `∼/Library/Shortcuts/Shortcuts.sqlite` 읽기·쓰기: 사용자는 단축어 앱 상세에서 직접 지정하고 DB 조작은 하지 않는다.
- 제거 때 가져온 단축어 삭제: `shortcuts help`에 삭제 하위 명령이 없다. 사용자 단축어 라이브러리는 편집하지 않는다.
- iOS/iPadOS, 다른 메신저, GitHub 버튼의 이름·위치·실행 경로 변경.
- Slack 본문 prompt injection 방어: Claude 및 MCP 측의 신뢰 정책으로 다룬다.
- 작업 폴더·지시문·키보드 조합·실제 Slack workspace/channel 식별자를 코드 기본값, 픽스처, 계획, 번역 또는 README에 기록.

## 불변 원칙

R0 이후 이 절과 「완료의 정의」에 항목을 더하는 것은 범위 변경이다 — 결정 원장의 `사용자` 행 없이 추가하지 않는다. 드라이버·검증자 발의는 비용 추정과 함께 사용자 승인 후 반영한다.

- URL 규칙의 단일 원천은 Core의 `SlackThreadURLContract`다. scheme·host·outer query key 상수는 parser와 shortcut 생성기가 공유하고 `Info.plist`의 `CFBundleURLSchemes`가 scheme 상수와 같은지 테스트한다. 바깥 URL은 정확히 `terminal-checkout://slack-thread`이고 query에는 정확히 `url` 키 하나만 있어야 하며 중복·다른 키·scheme·host·path 불일치는 거부한다.
- Slack permalink는 `https`만 받는다. host는 `<label>.slack.com` 또는 `<label>.enterprise.slack.com`이고 label은 소문자로 비교하는 `[a-z0-9-]{1,63}`다. path는 `/archives/<ID>/p<16자리>`이며 `ID`는 `[CGD][A-Z0-9]{8,10}`다. query는 `thread_ts` (10자리.6자리)와 `cid` (같은 ID 문법)만 각각 최대 한 번 허용하고 둘의 채널 ID가 달라도 수락한다. userinfo·port·fragment·디코딩된 링크 안의 `%` escape·다른 query key는 거부한다.
- outer `url` 값을 한 번 percent-decode한 뒤 양끝의 ASCII space·tab·CR·LF만 제거하고 그 링크가 512 UTF-8 byte 이하여야 한다. 그 trim된 원본 링크 문자열을 reserialize하지 않고 Claude 입력의 첫 토큰으로 보존한다.
- Slack 작업 폴더는 별도 앱 로컬 설정 키에서만 읽고 `normalizedBaseDirectory` 단일 검증을 재사용한다. 설정 누락·빈 값·존재하지 않는 경로·디렉터리가 아닌 경로는 실행 전에 거부한다. 기존 허용 목록이 거부하는 공백 경로는 지원하지 않고 UI에서 이유를 보인다; 지원하려면 `{cd}` 조립까지 포함한 별도 안전 설계가 필요하다. `repoEntryCommand`의 zoxide·clone 동작은 쓰지 않고 정확히 `cd <검증된 작업 폴더> && claude`를 조립한다.
- 지시문과 링크를 한 공백으로 결합해 단일 plain-text input `<링크>` 또는 `<링크> <지시문>`으로 전달하고 빈 지시문은 허용한다. 링크가 `https://`로 시작해 첫 문자가 항상 `h`이므로 `!`·`/`·`#` 입력창 모드 부류를 원천 제거한다. 지시문의 LF·CR·C0·DEL 검증은 기존 Claude 입력 경계와 공유하는 Core 함수를 쓰며 빈 값은 이 검증에서 허용한다. 링크와 지시문은 command template·폴더·터미널 설정으로 해석하지 않는다.
- Slack 명령은 앱이 조립한다. `commandAcceptsAppendedClaudePrompt`가 `cd <검증된 폴더> && claude`를 받는지 representative normalized path로 테스트한다. `prepareRequest` 결과는 언제나 `appendedPromptCommand` 경로여야 하며 `claudeInputs`가 남거나 scanner·shell admission이 거부하면 terminal 실행 전에 사용자 오류로 fail closed 한다; typing 경로는 fallback으로 쓰지 않는다.
- 요청은 `prepareRequest`와 `runInTerminal`의 기존 경로를 쓰고 `HostServer`의 직렬 `execQueue`, 선택된 terminal, `Settings.tabActivation`을 공유한다. Slack 전용 terminal launch queue나 별도 command executor를 만들지 않는다.
- Relay는 계속 stdio↔socket 전달만 맡고 AppleScript·명령 실행은 앱 안에 둔다. TCC 책임 프로세스 경계를 깨지 않는다.
- 런치 때의 자동 설정 창 표시는 `applicationDidFinishLaunching` 알림의 `userInfo[NSApplication.launchIsDefaultUserInfoKey]`가 true이고 `--background`가 아닐 때만 한다; URL 런치는 자동으로 창을 띄우지 않는다. URL 거부·실행 실패의 명시 표시는 런치 종류와 무관하게 기존 `ClaudeInputGuidance.present`와 같은 훅 패턴으로 설정 창을 열어 Slack 절에 오류 줄을 보이고 로그도 남긴다. 이 실패 표시를 위해 별도 알림·경고창 경로를 만들지 않는다. 성공한 URL 요청은 창을 띄우지 않는다.
- `application(_:open:)` URL callback은 `applicationDidFinishLaunching`보다 먼저 올 수 있으므로 앱 서비스 초기화 뒤까지 보류한 다음 한 번만 실행 큐에 넣는다. URL 이벤트에는 호출자에게 결과를 돌려줄 채널이 없다. 파싱·설정·append admission·터미널 실행 실패는 위의 Slack 오류 표시로 보인다. 성공은 Claude가 텍스트를 수신했다는 증거가 아니다.
- shortcut 이름은 ASCII 상수 `Terminal Checkout Slack Thread`이며 `Terminal Checkout Slack Thread.shortcut`의 basename과 일치하고 로컬라이즈하지 않는다. Foundation이 비ASCII argv를 NFD로 재인코딩하므로 `shortcuts sign --input/--output`의 파일명·이름 argv도 ASCII로 유지한다. 설치 상태는 `/usr/bin/shortcuts list` 출력에서 해당 이름과 정확히 일치하는 줄로만 판별한다; 실행 실패나 출력 파싱 불가는 `알 수 없음`이며 설치됨이 아니다. hotkey 지정 상태는 앱이 알 수 없으므로 사용자 안내만 한다.
- 사용자 지시문과 Slack 링크를 Foundation `Process.arguments`/environment의 raw Unicode carrier로 쓰지 않는다. 이 한 입력은 기존 `appendedPromptCommand` 및 terminal-specific NFD 보존 운반 경로를 통과한다.
- 앱 설정 및 생성 단축어는 private 폴더·지시문·Slack 링크를 Chrome `storage.sync`나 shortcut file에 넣지 않는다. shortcut action은 클립보드 링크 하나를 URL로 여는 것만 한다.
- Slack 설정 절의 긴 문자열은 `SetupWindowLayoutTests`가 `supportedLocales`의 다섯 앱 로케일에서 실제 표시 주체와 고정점 규칙으로 확인한다; `layoutSubtreeIfNeeded()`로 실창 레이아웃을 대신하지 않는다.
- 앱 카탈로그 다섯 언어 (`en`, `ja`, `ko`, `zh-Hans`, `zh-Hant`)에 같은 키 집합을 두고 README 네 언어 (`en`, `ko`, `ja`, `zh-Hant`)에 같은 사용 계약을 기술한다.

## 배치 점검 (0라운드)

모드: ultrafast

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | 메인 리포 `.git/info/exclude:7`로 ignored — clone에는 worktree를 만들지 않아 해당 없음 |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | N/A — ultrafast 전용 clone (`git clone --local`, 브랜치 `slack-thread`) |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-slack-thread-work` · `slack-thread` · `21382f5101555401a3a71263cad2441b9e37981b` |
| 리포 오버레이 `.claude/drive-agent-loop.md` — 기준 트리의 경로(메인 것을 복사했으면 그렇게), 없으면 드라이버가 골격으로 작성. 커밋하지 않는다 — `오버레이 무시: ignored` 확인 | `.claude/drive-agent-loop.md`는 이 리포의 git 추적 파일 (`#65`·`#77`에서 커밋) — 이번 루프는 수정하지 않는다 |
| cmux 패널 (점검 블록 `cmux:` 신호가 켜졌을 때만, 아니면 N/A) — `cmux markdown open <작업 트리 계획 파일 절대경로>` → pane id. 계획 파일 첫 승격 전에 채운다 | pane:328 (surface:414) |
| 트리마다 의존성 동기화 (기준·작업) | 외부 의존성 없음 — SwiftPM 의존 없음, `node --test`는 무의존 (README Development) |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 기준 오버레이 `Local asset env: None`; 확인 완료 |
| 증분 리뷰 소요(분) — 첫 세 번 | 아직 리뷰 없음 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | strict outer URL과 확정 Slack permalink를 파싱하고, 앱 설정으로 작업 명령과 link-first 평문 입력 하나를 조립한다 | Core 입력 계약 | — (새 경로) | `app/Sources/Core/SlackThreadURLContract.swift` (신규) · `app/Sources/Core/SlackThreadRequest.swift` (신규) · `app/Sources/Core/Request.swift` · `app/Sources/Core/BaseDirectory.swift` · `app/Sources/Core/ClaudeInputPlan.swift` · `app/Tests/CoreTests/SlackThreadRequestTests.swift` (신규) | — | cleared | `cd app && swift test --filter SlackThreadRequestTests` → `sandbox-exec: sandbox_apply: Operation not permitted` (게이트 미실행); `git diff --check` → exit 0; 12 tests: `testURLContractConstantsDescribeTheSharedShortcutURL`, `testAcceptsDriverShortcutURLAndQuerylessPermalinkPreservingOriginalLink`, `testAcceptsEnterpriseHostIDsAndTrimmedOriginalLink`, `testRejectsMalformedOuterURLs`, `testRejectsInvalidSlackLinks`, `testRejectsSlackLinkOver512UTF8BytesBeforeValidation`, `testHostLabelBoundaryAllows63AndRejects64Characters`, `testRejectsUnknownOuterQueryKeys`, `testBuildsLinkFirstCommandFromSettingsAndAllowsEmptyInstruction`, `testRejectsInvalidInstructionsAndInvalidDirectories`, `testFileManagerDefaultAcceptsAnExistingTemporaryDirectory`, `testPreparedSlackRequestUsesArgvOnlyAndFailsClosed`; `.git/toggle-host-label-boundary.patch` · `.git/toggle-outer-unknown-key.patch` · `.git/toggle-argv-fail-closed.patch`; 재실행(드라이버): `cd app && swift test` → exit 0, CoreTests 545 실행·1 skip·0 실패, AppTests 132 실행·0 실패; 토글 5종(host label 63자 상한·바깥 알 수 없는 키·argv fail-closed·호스트 앞 점 경계·`%` 거부) 각각 SlackThreadRequestTests의 이름 있는 테스트 실패(exit 1), 작업 상태 복원 확인 | 0962de1 |
| 2 | 고정 ASCII 이름의 Shortcuts plist를 생성·서명·열고 설치 상태를 판별한다 | 앱 Shortcuts 연동 | — (새 경로) | `app/Sources/Core/ShortcutWorkflow.swift` (신규) · `app/Tests/CoreTests/ShortcutWorkflowTests.swift` (신규) · `app/Sources/App/ShortcutInstaller.swift` (신규) · `app/Tests/AppTests/ShortcutInstallerTests.swift` (신규) | 1 | cleared | `cd app && swift test --filter ShortcutWorkflowTests` → `sandbox-exec: sandbox_apply: Operation not permitted` (manifest compile에서 차단, 테스트 미실행); `swiftc -frontend -parse app/Sources/Core/ShortcutWorkflow.swift app/Sources/App/ShortcutInstaller.swift app/Tests/CoreTests/ShortcutWorkflowTests.swift app/Tests/AppTests/ShortcutInstallerTests.swift` → exit 0; `git diff --check` → exit 0; Core 6 tests: `testActionOrderAndOutputConnections`, `testURLencodeUsesTextTokenStringForClipboardAttachment`, `testURLActionUsesSharedPrefixAndCalculatedUTF16AttachmentRange`, `testWorkflowMetadataIsExactAndContainsNoUserSettings`, `testWorkflowDataIsDeterministic`, `testWorkflowURLPrefixComesFromSharedContract`; App 9 tests: `testInstallationStatusMatchesOnlyAnExactOutputLine`, `testInstallationStatusIsUnknownWhenListCommandFailsOrThrows`, `testInstallationStatusIsUnknownForMalformedListOutput`, `testInstallSignsFixedASCIIShortcutWithExpectedArguments`, `testInstallRejectsMissingNewSignatureAfterRemovingPreviousFile`, `testInstallLaunchesShortcutsAndWaitsBeforeOpening`, `testInstallWaitsForAnExistingLaunchToFinishBeforeOpening`, `testInstallOpensDirectlyWhenShortcutsIsAlreadyRunning`, `testInstallFailsWhenShortcutsDoesNotStartBeforeTimeout`; `.git/toggle-urlencode-serialization.patch` · `.git/toggle-shortcut-list-exact-line.patch` · `.git/toggle-shortcuts-launch-before-open.patch`; 재실행(드라이버): `cd app && swift test` → exit 0, CoreTests 551·1 skip·0 실패, AppTests 141·0 실패; 생성 plist가 실측 통과 plist와 UUID 값 외 구조 동일(드라이버 대조 스크립트); 토글 3종(urlencode 텍스트 토큰·목록 정확 일치·실행 완료 후 열기) 각각 이름 있는 테스트 실패, 상태 복원 | |
| 3 | 앱 로컬 Slack 설정 절, 오류 줄, 단축어 상태·단축키 안내를 다섯 언어로 제공한다 | 설정 UI·로컬라이제이션 | — (새 설정) | `app/Sources/Core/SlackThreadRequest.swift` · `app/Tests/CoreTests/SlackThreadRequestTests.swift` · `app/Sources/App/Settings.swift` · `app/Sources/App/SetupWindowController.swift` · `app/Sources/App/ShortcutInstaller.swift` · `app/Sources/App/Localization.swift` · `app/Sources/App/Resources/en.lproj/Localizable.strings` · `app/Sources/App/Resources/ja.lproj/Localizable.strings` · `app/Sources/App/Resources/ko.lproj/Localizable.strings` · `app/Sources/App/Resources/zh-Hans.lproj/Localizable.strings` · `app/Sources/App/Resources/zh-Hant.lproj/Localizable.strings` · `app/Tests/AppTests/SetupWindowLayoutTests.swift` · `app/Tests/AppTests/LocalizationCatalogTests.swift` · `app/Tests/AppTests/SlackThreadSettingsTests.swift` (신규) · `app/Tests/AppTests/CmuxPlacementSetupTests.swift` · `app/Tests/AppTests/LocaleRestartTests.swift` · `app/Tests/AppTests/SetupWindowRedrawTests.swift` | 1, 2 | cleared | `cd app && CLANG_MODULE_CACHE_PATH=../.git/tc-clang-cache swift build --build-tests --disable-sandbox --scratch-path ../.git/tc-swift-build --cache-path ../.git/tc-swift-cache --config-path ../.git/tc-swift-config --security-path ../.git/tc-swift-security` → exit 0; `cd app && CLANG_MODULE_CACHE_PATH=../.git/tc-clang-cache swift test --disable-sandbox --scratch-path ../.git/tc-swift-build --cache-path ../.git/tc-swift-cache --config-path ../.git/tc-swift-config --security-path ../.git/tc-swift-security --filter SlackThreadRequestTests` → exit 0, Core 13; 같은 명령의 `--filter SlackThreadSettingsTests` → exit 0, App 5; `--filter testSlackThreadCardFitsInEveryLocale` → exit 0, App 1; `--filter LocalizationCatalogTests` → exit 0, App 8; 추가 테스트 8개: `testLiveSettingsValidatorMatchesRequestResolution`, `testSlackSettingsAreStoredAsRawAppLocalStrings`, `testSettingsAndURLRequestUseTheSameCoreValidator`, `testRequestAndInstallerFailuresHaveLocalizedMessagesInEveryLocale`, `testShortcutButtonReflectsQueriedStatusNotInstallSuccess`, `testSuccessfulInstallShowsAddShortcutGuidanceUntilStatusIsInstalled`, `testSlackFieldsSaveRawTextAndShowValidationWhileEditing`, `testSlackThreadCardFitsInEveryLocale`; 토글 `.git/toggle-slack-settings-validator.patch`의 역적용은 `testSettingsAndURLRequestUseTheSameCoreValidator` 실패(exit 1), `.git/toggle-slack-installed-status.patch`의 역적용은 `testShortcutButtonReflectsQueriedStatusNotInstallSuccess` 실패(exit 1); 두 패치 재적용 후 `git diff --check` → exit 0 재실행(드라이버): `cd app && swift test` → exit 0, CoreTests 552·1 skip·0 실패, AppTests 148·0 실패; 토글(검증 단일 원천·설치 상태 규칙) red·상태 복원(드라이버), 단축어 추가 안내 토글 red(구현자 샌드박스 `--disable-sandbox`) | |
| 4 | URL event를 didFinish 초기화 순서에 안전하게 연결하고 기존 직렬 launch 경로, launch 자동 표시 규칙, 명시 실패 훅을 구현한다 | 앱 URL 수신·실행 | — (새 경로) | `app/Sources/App/AppDelegate.swift` · `app/Sources/App/HostServer.swift` · `app/Tests/AppTests/SlackThreadURLHandlingTests.swift` (신규) | 1, 3 | todo | | |
| 5 | URL scheme 번들 등록과 LaunchServices 설치 수명을 검증한다 | 앱 번들·설치 수명 | — (새 경로) | `app/Info.plist` · `install.sh` · `uninstall.sh` · `app/Tests/AppTests/URLSchemeRegistrationTests.swift` (신규) | 1, 4 | todo | | |
| 6 | 사용법·보안·제약을 README 네 언어와 terminal 수동 점검표에 반영한다 | 제품 문서·수동 점검 | — (새 기능) | `README.md` · `README.ko.md` · `README.ja.md` · `README.zh-Hant.md` · `docs/new-terminal-checklist.md` | 1∼5 | todo | | |
| 7 | 선택·거부 이유와 런타임 불변식을 why 문서 및 agent 안내에 남긴다 | 설계 맥락·프로젝트 규칙 | — (새 기능) | `docs/context/slack-thread-shortcut.md` (신규) · `docs/context/index.md` · `CLAUDE.md` | 1∼6 | todo | | |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶이고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다. 승격 칸에는 커밋 해시를 적는다.
- `의존`: 다른 항목의 계약(시그니처·불변식·생성물·호출 순서)을 전제하면 그 번호를 적는다. 그 항목에 정정이 오면 이 항목의 근거를 다시 낸 뒤에 최종 리뷰에 들어간다.
- `확정 결함`: 설계 리뷰·판정에서 결함이 확정되면 처방 산문과 분리해 `(a) … (b) …`로 적는다. 배정문은 라벨을 인용한다. 이 계획은 새 기능이므로 현재 확정 결함은 없다.
- 판정이 항목을 다시 열면 행을 고치지 말고 개정 항목으로 잇는다 — 같은 항목 개정은 prime (`6′`), 형제 부류나 prime 소진 뒤는 letter (`6a`), 식별자는 재사용하지 않는다.
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`다. `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다.
- 근거 칸에는 재실행 가능한 것만 적는다. 계획 작성 중에는 게이트를 실행하지 않았으므로 비워 둔다.

## 결정 원장

R0에서는 이번 배정에서 사용자가 확정한 결정과 드라이버가 지정한 실측 결정을 함께 적는다. 첫 승격 뒤에는 append-only이며 드라이버가 지정한 문구만 새 행으로 기록한다. 구현자는 스스로 드라이버 결정을 추가하지 않는다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | Slack 메시지 동작을 별도 메시징 앱 또는 브라우저 확장에 둘 후보 | 트리거는 Slack 데스크톱에서 링크 복사 후 사용자가 단축어의 키보드 단축키 실행. Slack 앱 방식과 `app.slack.com` 콘텐츠 스크립트 방식은 기각 | 사용자 배정: Slack workspace 앱은 기본적으로 구성원 모두가 쓰며 사용자별 제한은 Enterprise 전용; Socket Mode 여러 연결은 사용자별 경계를 주지 않음 | 없음 — 안쪽 permalink 허용 문법은 D9에서 확정 |
| D2 | 사용자 | 단축어에서 앱까지의 실행 통로 | `terminal-checkout://` URL scheme을 선택. 단축어의 셸 스크립트 실행 권한을 요구하지 않는 대신 웹페이지와 다른 앱이 같은 URL을 열 수 있음을 수용 | 사용자 배정; 브라우저의 외부 앱 확인 뒤 임의 페이지가 URL 내용을 고를 수 있고 같은 uid 프로세스는 app socket에도 닿는다는 위협 모델 승인 | 브라우저 확인 UX는 브라우저별이며 신뢰 판정으로 쓰지 않음 |
| D3 | 사용자 | 설치 산출물과 단축키의 소유권 | 앱의 `[설치하기]`가 공유 가능한 단축어 파일을 `people-who-know-me`로 서명해 연다. 사용자가 단축어 앱에서 단축키를 지정하며 DB를 조작하지 않는다 | 사용자 배정; `shortcuts sign` 측정에서 서명 성공과 `AEA1` magic 확인. Apple 단축키 안내 및 driver import 측정 | action 연결이 clipboard link를 비워 보내는 원인을 찾고 list 출력 계약을 확인해야 함 |
| D4 | 사용자 | 기계·사용자별 설정이 여러 기기나 공유 파일에 섞일 위험 | 작업 폴더와 지시문은 앱 로컬 설정이고 기본값은 비어 있다. 개인 경로·지시문·키보드 조합 및 실제 Slack workspace/channel 값은 공개 리포에 기록하지 않는다 | 사용자 배정 | 빈 지시문 허용; 작업 폴더와 기본값의 UI 테스트 필요 |
| D5 | 드라이버 | 콜드 URL 런치에서 일반 실행 설정 창이 나타날 위험 | URL 콜드 런치 구분은 didFinishLaunching의 `launchIsDefault`로 한다 — willFinishLaunching의 `currentAppleEvent`는 nil로 실측돼 기각 | 드라이버 프로브 실측 2026-10-02, Darwin 27.0.0: cold URL `open`/`open -g`는 `launchIsDefault=0`, URL callback이 didFinish보다 먼저 오고 callback 안은 `GURL/GURL`, willFinish `currentAppleEvent=nil`; 일반 `open`과 relay식 `open -g -b … --args --background`는 `launchIsDefault=1`·`aevt/oapp`, running app URL open은 callback만 옴 | 없음 — 제품 확인은 설치 앱에서 acceptance oracle로 수행 |
| D6 | 드라이버 | 지시문 첫 글자가 Claude 입력창 모드를 바꾸는 위험 | 링크를 입력 맨 앞에 둔다 — 지시문 첫 글자가 claude 입력창 모드를 바꾸는 부류를 원천 제거, 빈 지시문 허용 | 드라이버 R0 지시, 2026-10-02; `https://` permalink가 입력 첫 문자 `h`를 보장 | 없음 |
| D7 | 드라이버 | argv admission 불가 시 기존 request가 typing으로 폴백하는 위험 | Slack 경로는 argv 경로만 쓰고 타이핑 폴백을 금지한다 — 조립한 명령이 append scanner를 통과함을 테스트로 고정, 실패 시 fail closed | 드라이버 R0 지시, 2026-10-02; 검증 대상은 `commandAcceptsAppendedClaudePrompt` 및 `prepareRequest` 결과 | 실제 normalized folder 모양의 scanner 결과를 Core 테스트로 고정 |
| D8 | 드라이버 | 안쪽 query의 `&`·`=`·`?`가 바깥 URL query 구조로 새는 위험 | 바깥 URL은 `url` 키 하나만 엄격 파싱한다; 단축어 인코딩이 이 문자를 인코딩하지 않으면 parser가 아니라 단축어 생성기를 고친다 | 드라이버 R0 지시, 2026-10-02; import + `shortcuts run`으로 merge 전 확인 요구 | 현재 실행한 후보는 URL을 열지만 링크 값이 비어 있어 encoding 성공은 미확인 |
| D9 | 드라이버 | 위장된 호스트·경로·query가 Slack link로 승인되는 위험 | 호스트·label·path·ID·query의 Slack permalink 문법은 불변 원칙에 적은 strict allowlist이며, `cid`와 path ID 불일치는 거부 조건이 아니다 | 드라이버 R0 지시, 2026-10-02 | 없음 — parser tests가 확정 계약을 고정 |
| D10 | 드라이버 | 공백 포함 작업 폴더를 셸에서 안전하지 않게 조립할 위험 | 작업 폴더는 `normalizedBaseDirectory` 단일 검증을 재사용하고 공백 경로는 지원하지 않는다 — 지원하려면 `{cd}` 조립까지 포함한 별도 설계가 필요 | 드라이버 R0 지시, 2026-10-02; 기존 허용 목록과 조립 경계 | 없음 |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점을 계획 대상으로 전부 열거한다. 구현 뒤 각 판정은 테스트·수동 실측으로 갱신한다. 코드만으로 판정할 수 없는 이유를 셋째 칸에 적는다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| outer URL scheme·host·path·`url` query cardinality와 unknown/duplicate key | Core 테스트 추가 · 게이트 미실행 | `SlackThreadRequestTests.testRejectsMalformedOuterURLs` · `testRejectsUnknownOuterQueryKeys`; `.git/toggle-outer-unknown-key.patch` |
| inner Slack host·label·path·ID·`thread_ts`·`cid`·trim·percent escape·512-byte cap | Core 테스트 추가 · 게이트 미실행 | `SlackThreadRequestTests.testAcceptsDriverShortcutURLAndQuerylessPermalinkPreservingOriginalLink` · `testAcceptsEnterpriseHostIDsAndTrimmedOriginalLink` · `testRejectsInvalidSlackLinks` · `testRejectsSlackLinkOver512UTF8BytesBeforeValidation` · `testHostLabelBoundaryAllows63AndRejects64Characters`; `.git/toggle-host-label-boundary.patch` |
| 설정 작업 폴더·빈 설정·경로 유형·공백 | 공용 Core 검증과 즉시 UI 판정 추가 · 필터 테스트 실행 · 드라이버 게이트 미실행 | `SlackThreadRequestTests.testLiveSettingsValidatorMatchesRequestResolution` · `SlackThreadSettingsTests.testSlackFieldsSaveRawTextAndShowValidationWhileEditing` · `testSlackSettingsAreStoredAsRawAppLocalStrings` |
| instruction control validation·empty value·input classification | 입력창 분류 원천 제거 (R0-2) · 공용 검증 유지 · 필터 테스트 실행 | `SlackThreadRequestTests.testBuildsLinkFirstCommandFromSettingsAndAllowsEmptyInstruction` · `testRejectsInvalidInstructionsAndInvalidDirectories` · `testLiveSettingsValidatorMatchesRequestResolution` |
| command append scanner·`prepareRequest` route | Core 테스트 추가 · 게이트 미실행 | `SlackThreadRequestTests.testPreparedSlackRequestUsesArgvOnlyAndFailsClosed`; `.git/toggle-argv-fail-closed.patch` |
| URL path의 launch serial·terminal·tab activation | 계획 구멍 (항목 4) | `HostServer.execQueue` 및 현재 app 설정을 주입한 URL handler 테스트 필요 |
| URL cold launch 자동 창 표시·실패 명시 창 표시 | 실측 (R0-1) · 요구 확정 (R0-8) | installed app probe 결과: willFinish event nil, URL open callback 먼저, `launchIsDefault` false; 실패 표시는 별도 hook |
| typed delivery 결과 및 실패 UI | 범위 밖 (R0-3) | 이 경로는 `appendedPromptCommand` argv 방식만 사용하고 타이핑하지 않는다 |
| iTerm2·WezTerm·Warp·cmux stable/nightly 및 background 설정 | 미검사 (항목 4, 6) | 단위 테스트와 `app/e2e.sh`는 실제 터미널을 열지 않음. `docs/new-terminal-checklist.md`에 driver 실기기 확인 필요 |
| shortcut plist action 연결·query 인코딩·sign·import·run | 드라이버 실측 및 구조 테스트 추가 · 게이트 미실행 | `WFTextTokenString` urlencode 입력을 포함한 4-action graph를 import하고 `shortcuts run`으로 정확한 링크 전달; `ShortcutWorkflowTests.testURLencodeUsesTextTokenStringForClipboardAttachment` · `testURLActionUsesSharedPrefixAndCalculatedUTF16AttachmentRange`; `.git/toggle-urlencode-serialization.patch` |
| shortcut 설치 상태·고정 이름·hotkey 설정 상태 | 드라이버 실측 및 격리 테스트 추가 · 설정 창 조회는 비동기 · 드라이버 게이트 미실행 | `shortcuts list`는 이름 한 줄씩 출력; `ShortcutInstallerTests.testInstallationStatusMatchesOnlyAnExactOutputLine` · `testInstallationStatusIsUnknownWhenListCommandFailsOrThrows` · `testInstallationStatusIsUnknownForMalformedListOutput` · `testInstallLaunchesShortcutsAndWaitsBeforeOpening` · `SlackThreadSettingsTests.testShortcutButtonReflectsQueriedStatusNotInstallSuccess`; 사용자가 hotkey를 직접 지정하고 상태로 표시하지 않음 |
| `Info.plist` 등록·`install.sh`·`uninstall.sh`의 LaunchServices lifecycle | 계획 구멍 (항목 5) | `CFBundleURLSchemes` 상수 일치 테스트 및 installed location cold open 필요; `/tmp` 번들은 URL을 받지 못함 |
| 설정 창 Slack 절·catalogue key·다섯 앱 locale | 구현 및 필터 테스트 추가 · 드라이버 게이트 미실행 | `SetupWindowLayoutTests.testSlackThreadCardFitsInEveryLocale` · `LocalizationCatalogTests` 8 tests · `SlackThreadSettingsTests.testRequestAndInstallerFailuresHaveLocalizedMessagesInEveryLocale` · `.git/toggle-slack-settings-validator.patch` · `.git/toggle-slack-installed-status.patch` |
| README 네 언어·terminal checklist·why index 일관성 | 계획 구멍 (항목 6, 7) | README는 사용법, `CLAUDE.md`는 불변 원칙, `docs/context/`는 이유만 맡도록 정리 |
| shortcut 삭제 정책 | 안전 경계 (항목 5) | `shortcuts help`에 delete 명령 없음; 사용자 shortcut library는 편집하지 않음 |
| Slack thread 작성자 prompt injection | 범위 밖 | MCP가 읽는 원격 텍스트이며 GitHub issue 본문과 같은 모델 입력 위험; 앱이 읽거나 filter하지 않음 |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰마다 대상 커밋과 계측, 차단·수정·실측·판정을 적는다. 보고서 원문은 스크래치패드 경로로 가리킨다. R0은 설계 리뷰다.

### R0

#### 설계 리뷰 — 미승격 · 원문 없음

- 반박: 드라이버 R0 반박 12건 — URL 런치 구분 실측, 입력 순서(링크 먼저), argv 경로 보장, URL 계약 단일 원천, ASCII 단축어 이름, 엄격 파싱 유지, 안쪽 링크 규칙, 실패 표시, 배경 출처, 배치 점검, 소탕 표, 공백 경로
- 처리: 전부 반영(D5∼) — 항목 4에서 ClaudeInjector 변경 제외
- 실측: 드라이버 프로브: URL 콜드 런치 launchIsDefault=0·willFinish currentAppleEvent=nil, 일반·relay 런치 launchIsDefault=1, /tmp 번들은 URL 미수신
- 판정: "반박 반영 조건으로 이 계획으로 시작하는 데 합의한다"

### R1

#### 리뷰 1 — 증분 · 항목 1 커밋 · 배정 18:48 · 완료 19:09 · 리뷰 19:03∼19:14 · 왕복 1

- 차단: 512바이트 상한 테스트 픽스처가 462바이트(게이트 실패 2건, 테스트 결함) · Slack 작업 폴더를 base directory로 부름(기존 base directory 설정과 혼동) · argv 성공 테스트가 기계의 로그인 셸에 의존
- 수정: 세 건 모두 커밋 전에 반영 — 픽스처 확대, workDirectory 계열로 개명, loginShell 명시
- 실측: 게이트 exit 0(CoreTests 545·1 skip·0 실패, AppTests 132) · 토글 5종 red · 상태 복원
- 판정: 항목 1 범위 내 확인 — 새 표면(바깥 쿼리 파서·안쪽 링크 문법·argv fail-closed)에서 우회 없음 → 항목 1 `cleared`

#### 리뷰 2 — 증분 · 항목 2 커밋 · 배정 19:15 · 완료 19:33 · 리뷰 19:20∼19:40 · 왕복 3

- 차단: 빌드 실패 2회(`parseListOutput` 암시적 반환 누락, 테스트의 `Any` 비교) · 단축어 이름이 내부 식별자 모양 · 프로세스 존재만으로 런치 완료 판정 · 이전 서명 파일을 다시 열 수 있음
- 수정: 모두 커밋 전 반영 — `return`, `XCTUnwrap` 비교, 이름 `Terminal Checkout Slack Thread`, `isFinishedLaunching` 대기(폴링마다 새 조회), 서명 전 이전 파일 삭제
- 실측: 게이트 exit 0(CoreTests 551·AppTests 141) · 생성 plist 구조 = 실측 통과 plist · 토글 3종 red · 구현자 샌드박스 컴파일 확인 경로 확보(`swift build --build-tests --disable-sandbox`, 캐시는 `.git/` 아래)
- 판정: 항목 2 범위 내 확인 — 새 표면(plist 생성기·서명·열기 순서·상태 조회)에서 우회 없음

#### 리뷰 3 — 증분 · 항목 3 커밋 · 배정 19:45 · 완료 20:09 · 리뷰 20:01∼20:14 · 왕복 2

- 차단: 설치 직후 다음 행동 안내 없음 · `slackLocalized` 새 호출 형태로 카탈로그 정규식 확장 · Core 폴더 검사 기본값 중복 · 되돌린 카탈로그 테스트에 주석·빈 줄 잔재
- 수정: 단축어 추가 안내(상태가 설치됨이 되면 사라짐), 오류 매핑을 `localized(…)`로, 기본 검사 함수 하나로, 카탈로그 테스트 HEAD로 원복
- 실측: 게이트 exit 0(CoreTests 552·AppTests 148) · 토글 3종 red · 다섯 로케일 키 패리티는 기존 카탈로그 테스트
- 판정: 항목 3 범위 내 확인 — 새 표면(설정 창 Slack 절·실시간 검증·설치 상태 표시)에서 우회 없음 → 항목 3 `cleared`

## 열린 질문

- 이미 `Terminal Checkout Slack Thread` 이름의 단축어가 보관함에 있을 때 생성한 `.shortcut`을 열면 가져오기 화면이 어떤 선택지를 보이는가? 드라이버가 실제 가져오기로 확인한다 (항목 2).
