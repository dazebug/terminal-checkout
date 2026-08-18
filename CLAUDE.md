# CLAUDE.md

GitHub PR·이슈·저장소 페이지에서 터미널(iTerm2/WezTerm)로 명령을 실행하는 Chrome 확장 프로그램 + 맥 앱. `extension/`(Manifest V3) + `app/`(Swift 패키지 → Terminal Checkout.app: relay + 소켓 서버 + 설정 UI) 구성.

## 주요 명령어

```bash
./install.sh                         # 빌드 + ~/Applications 설치 + 실행 (sudo 불필요, 멱등, 비대화식)
./uninstall.sh
app/build.sh                         # 번들만 빌드 → app/build/Terminal Checkout.app
cd app && swift test                 # Core 단위 테스트
node --test                          # 확장(JS) 순수 함수 단위 테스트 (리포 루트, 의존성 없음)
app/e2e.sh                           # relay↔소켓↔서버 왕복 회귀 테스트 (빌드 후 실행)
git config core.hooksPath .githooks  # CLAUDE.md → AGENTS.md symlink 훅 활성화 (클론 후 1회)
```

## 아키텍처 — TCC가 이 구조를 강제한다

```
Chrome → relay(번들 내 terminal-checkout-relay, stdio↔socket 중계만) → unix socket → 앱(렌더링·검증·터미널 실행)
```

- macOS TCC는 권한을 responsible process에 귀속시킨다. Chrome의 자식 프로세스가 osascript를 실행하면 권한이 **Chrome**에 붙는다. 그래서 relay에는 실행 로직을 두면 안 되고, 실제 실행은 `open`(LaunchServices)으로 떠서 스스로 responsible process가 된 앱이 담당한다. 이 분리를 무너뜨리는 리팩터링 금지
- relay는 소켓 연결 실패 시 `open -g -b com.dazebug.terminal-checkout --args --background`로 앱을 띄우고 재시도한다 (앱 상주 불필요)
- 소켓: `~/Library/Application Support/TerminalCheckout/host.sock`. 테스트용 오버라이드 `TERMINAL_CHECKOUT_SOCKET`. unix socket 경로는 104바이트 제한이 있어 짧아야 한다
- 프레이밍은 Chrome Native Messaging과 동일한 4바이트 LE 길이 + JSON을 소켓에서도 그대로 쓴다

## 개발 시 참고사항

- Native Messaging host 이름(`com.dazebug.terminal_checkout`)은 소문자 영숫자·`_`·`.`만 허용된다(하이픈 금지). 앱 번들 ID(`com.dazebug.terminal-checkout`)는 하이픈을 쓴다 — 서로 다른 네임스페이스이며 섞지 않는다
- 터미널 선택은 앱이 단일 소스로 관리한다(UserDefaults `terminal`: `iterm`/`wezterm`). 소켓 요청은 `{command_template, variables, claude_inputs?}` 하나뿐이며, 확장이 터미널을 지정할 수단은 없다. `iterm` 값은 확장 이름과 무관하게 iTerm2를 가리키는 식별자이므로 바꾸지 않는다. iTerm2 권한 블록은 iTerm2 선택 + 권한 미허용 시에만 표시된다
- 설정 창은 상태 기반 노출: 완료된 설정 항목의 카드는 숨고 헤더 파이프라인 스트립의 점으로만 남는다. 확장 설치 완료 판정은 폴더 준비가 아니라 소켓 요청 수신 기록(UserDefaults `lastRequestAt`, `Settings.recordRequestEvidence`)이다 — 폴더 준비만으로는 Chrome 로드 여부를 알 수 없기 때문. 창이 열려 있으면 요청 도착 시 Notification으로 실시간 갱신된다
- command template 시스템: `{repo}`, `{owner}`, `{number}`, `{branch}`, `{base}`, `{main}`, `{branch_underbar}` 변수를 앱(`Core/CommandRenderer.swift`)에서 치환. 값 검증은 영숫자·`-_./` 화이트리스트 문자 검사 (파이썬 시절 정규식 `$`가 끝 개행을 허용하던 구멍까지 막은 것 — 정규식으로 되돌리지 말 것). 이슈 페이지는 PR 브랜치가 없어 `{branch}` 계열과 `{base}`를 주지 않으므로, 템플릿이 쓰면 앱이 not provided로 거절한다
- `{base}`(PR이 머지될 브랜치)와 `{main}`은 다른 변수다: `{main}`은 오버라이드·기본값 폴백을 거치지만 `{base}`는 PR 페이지에서 감지한 base ref를 그대로 쓰고, 감지 실패 시 아예 전달하지 않아 거절되게 한다 — 엉뚱한 브랜치에 머지·리베이스하는 것보다 실패가 낫기 때문
- claude 입력(`claude_inputs`): command가 띄운 claude 세션에 순서대로 타이핑할 자유 텍스트(버튼당 최대 5개, 같은 변수 치환). 앱이 세션 tty의 포그라운드 프로세스가 claude/node/bun임을 `ps`로 확인한 뒤에만 전송한다(`Core/ClaudeInjector.swift`) — 이 게이트를 없애면 셸에 Enter 포함 오입력되어 즉시 실행되므로 우회 금지. 각 입력은 [개행 없는 타이핑 → 화면 반영 확인 → CR(\r) 제출] 순서다 — claude TUI는 초기화 중 도착한 입력을 버리고 LF(\n)를 제출로 인식하지 않으므로(둘 다 실측) 이 시퀀스를 "텍스트+\n 한 번에 전송"으로 단순화하면 안 된다. 반영 확인은 공백을 지우고 비교한다(`screenShowsInput`) — claude는 shell mode 입력을 `! gh …`로 공백을 끼워 그리고 긴 입력은 줄바꿈해서, 통짜 비교로는 영영 확인에 실패해 입력이 매달린다(실측). 전달 감시는 execQueue 밖 백그라운드에서 돈다(Chrome 응답을 막지 않기 위해). WezTerm fallback(`wezterm start`) 경로는 pane을 특정할 수 없어 전달 생략
- 버튼 표시는 `face` 키(이모지 여러 개·짧은 텍스트 허용), `emoji`는 구버전 저장값 호환 읽기 전용. 기본값·프리셋·표시 판정은 `extension/defaults.js`가 단일 출처이고 content script·service worker·옵션 페이지가 모두 이 파일을 먼저 로드한다. 옵션 페이지 CSS 토큰은 앱 `Theme.swift` 팔레트의 미러
- 버튼 순서 변경(드래그·↑↓)과 복제는 옵션 페이지 전용이지만, 배열 조작은 순수 함수 `moveButton`·`duplicateButton`으로 `defaults.js`에 있다(`tests/buttons.test.js`가 검증). 드래그는 손잡이(`.drag-handle`)를 누르고 있는 동안에만 카드에 `draggable`을 건다 — 카드에 상시로 걸면 안쪽 입력에서 텍스트를 끌어 고를 수 없다. 드롭하면 곧바로 다시 그리느라 원래 카드가 사라져 `dragend`가 오지 않으므로 뒷정리는 `drop`에서 끝낸다
- 버튼 설정은 페이지별로 분리된다: PR은 storage `buttons`, 이슈는 `issueButtons`. 이슈 버튼은 상태 배지(Open/Closed) 줄에 붙는다 — 제목(h1) 안에 넣으면 제목 길이에 따라 다음 줄로 밀리므로, 배지를 감싼 flex 조상을 찾아 append한다(모듈 CSS 클래스명은 빌드 해시가 붙어 못 쓴다)
- 옵션 페이지 백업(내보내기/가져오기): 계정 없이 옮기거나 파일로 백업하는 통로(확장 ID가 key로 고정되어 같은 계정 Chrome끼리는 `storage.sync`가 자동 동기화된다). 가져오기는 storage에 직접 쓰지 않고 편집 상태만 채운다 — 저장은 저장 버튼 하나로만 일어난다는 이 페이지의 원칙을 지키기 위함이고, 검증은 DOM·chrome API를 모르는 순수 함수 `parseImportedSettings`에 모여 있다
- main 브랜치 결정 순서: 리포별 오버라이드 → PR 페이지 base branch → 글로벌 기본값 (`extension/background.js`)
- 앱 실행 시 `z`/`gh`/`claude`가 로그인 셸에서 불리는지 확인해 설정 창에 없는 것만 표시한다(`Core/ToolChecker.swift`). 확인은 반드시 로그인 셸을 인터랙티브(`-i`)로 띄워서 한다 — `z`는 zoxide가 rc에서 정의하는 셸 함수라 실행 파일 탐색으로는 찾을 수 없고, GUI 앱의 PATH·SHELL은 로그인 셸과 다르다
- iTerm2는 osascript(앱의 자식 프로세스 → 권한이 앱에 귀속), WezTerm은 `wezterm cli spawn`(실패 시 `wezterm start` fallback — mux가 없어 붙을 창도 없으니 이 경로만 새 창이다). GUI 앱은 PATH가 `/usr/bin:/bin` 수준이라 wezterm CLI는 `/opt/homebrew/bin` 등 명시적 후보를 탐색한다
- 새 탭은 사용자가 보고 있던 창에 만든다: `wezterm cli spawn`은 `--window-id`가 없으면 `WEZTERM_PANE`으로 창을 정하는데 GUI 앱에는 그 변수가 없어 mux의 첫 창(= 가장 오래된 창)에 탭이 생긴다(실측) — `cli list-clients`의 `focused_pane_id`가 속한 창을 찾아 `--window-id`로 명시한다(`Core/TerminalRunner.swift`). 조회가 실패하거나 그 pane이 이미 닫혔으면 창을 지정하지 않는다 — 엉뚱한 창에 탭을 흘리는 것보다 wezterm 기본 선택이 낫다. 지정한 창이 spawn 직전에 닫혔으면 wezterm이 `window_id N not found`로 실패하므로(실측) 창 지정 없이 한 번 더 시도한다 — 여기서 포기하면 `wezterm start` fallback이 새 창을 띄워 고치려던 증상이 되살아난다. iTerm2의 `current window`는 이미 최근 활성 창이라 같은 처리가 필요 없다
- 확장 ID는 manifest `key`(base64 DER 공개키)의 SHA-256 앞 32 hex를 a-p로 매핑해 고정된다(`Core/ExtensionID.swift`; key가 없으면 경로 해시 폴백) — ID가 컴퓨터마다 같아야 `storage.sync` 설정이 같은 계정의 Chrome끼리 동기화되기 때문. `allowed_origins`에는 전환기용으로 경로 기반 옛 ID도 함께 등록된다. 개인키(`~/Library/Application Support/TerminalCheckout/extension-key.pem`)는 리포 밖이며 unpacked 로드에는 manifest의 공개키만 있으면 된다. 확장 폴더는 App Support 고정 경로 단일 위치이며, 앱 실행 시 번들 확장과 사본을 내용 비교해 다르면 자동 재복사한다(수동 복사·재설치 버튼 없음). 반영에는 chrome://extensions에서 확장 새로고침이 필요하되, key 추가처럼 ID가 바뀌는 변경은 새로고침이 아니라 제거 후 재로드가 필요하다
- `allowed_origins`는 배열이다. Chrome Web Store 전환 시 `Installer.allowedExtensionIDs`에 store ID만 추가하면 된다 (CWS 업로드 zip에는 manifest `key` 필드 금지 — key 없는 zip을 먼저 올려 store ID를 예약하는 것이 공식 절차). unpacked 확장은 Chrome 133+부터 개발자 모드가 켜져 있어야 활성 유지된다
- ad-hoc 서명이므로 재빌드하면 자동화 권한을 다시 물을 수 있다 (정상 동작)
- 아이콘 버튼은 `span.head-ref` 바깥(clipboard-copy wrapper 뒤)에 삽입
