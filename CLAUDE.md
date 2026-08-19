# CLAUDE.md

**문서 원칙**: 코드·`README.md`로 알 수 없고, 도구·하니스·모델이 대신 보장하지도 않는 것(규약·설계 판단·실측 함정)만 적는다. 구조·목록·절차는 소스가 따로 있으므로 나열하지 않는다 — 짧은 것은 의도된 생략이다. 내용을 추가할 때도 같은 기준을 따를 것.

GitHub PR·이슈·저장소 페이지에서 터미널(iTerm2/WezTerm)로 명령을 실행하는 Chrome 확장 프로그램 + 맥 앱. 설치·사용법·변수 표·트러블슈팅은 `README.md`에 있고, 빌드·테스트 명령은 그 "개발" 절에 있다.

```bash
./install.sh                         # 빌드 + ~/Applications 설치 + 실행 (sudo 불필요, 멱등, 비대화식)
git config core.hooksPath .githooks  # CLAUDE.md → AGENTS.md symlink 훅 활성화 (클론 후 1회)
```

## 아키텍처 — TCC가 이 구조를 강제한다

```
Chrome → relay(stdio↔socket 중계만) → unix socket → 앱(렌더링·검증·터미널 실행)
```

- macOS TCC는 권한을 responsible process에 귀속시킨다. Chrome의 자식 프로세스가 osascript를 실행하면 권한이 **Chrome**에 붙는다. 그래서 relay에는 실행 로직을 두면 안 되고, 실제 실행은 `open`(LaunchServices)으로 떠서 스스로 responsible process가 된 앱이 담당한다. 이 분리를 무너뜨리는 리팩터링 금지
- unix socket 경로는 104바이트 제한이 있어 짧아야 한다 — 테스트에서 `TERMINAL_CHECKOUT_SOCKET`으로 오버라이드할 때도 마찬가지다
- Native Messaging host 이름(`com.dazebug.terminal_checkout`)과 앱 번들 ID(`com.dazebug.terminal-checkout`)는 다른 네임스페이스다 — host 이름에는 하이픈을 쓸 수 없어 표기가 갈린 것이므로 섞지 않는다

## 개발 시 참고사항

- 터미널 선택은 앱이 단일 소스로 관리한다 — 확장이 터미널을 지정할 수단은 두지 않는다. 저장값 `iterm`은 확장 이름과 무관하게 iTerm2를 가리키는 식별자이므로 바꾸지 않는다
- 터미널을 새로 지원할 때 손댈 지점과 실측 검사 목록은 `docs/new-terminal-checklist.md`에 있다 — 분기가 Core·App·설정 창에 흩어져 있는데 단위 테스트도 `app/e2e.sh`도 터미널을 실제로 열지 않아, 빠뜨린 갈래는 실사용에서만 드러난다
- 확장 설치 완료 판정은 폴더 준비가 아니라 소켓 요청 수신 기록이다 — 폴더가 준비돼도 Chrome이 실제로 로드했는지는 알 수 없기 때문
- 변수 값 검증은 문자 단위 화이트리스트다. 파이썬 시절 정규식의 `$`가 끝 개행 하나를 허용하던 구멍까지 막은 것이므로 정규식으로 되돌리지 말 것
- `{base}`(PR이 머지될 브랜치)는 `{main}`과 달리 오버라이드·기본값 폴백을 거치지 않는다. 감지 실패 시 아예 전달하지 않아 앱이 거절하게 둔다 — 엉뚱한 브랜치에 머지·리베이스하는 것보다 실패가 낫기 때문
- claude 입력 전달(`Core/ClaudeInjector.swift`)의 게이트 세 겹은 우회 금지다: ①포그라운드 프로세스가 claude, ②tty가 raw mode, ③처음 준비된 claude와 같은 PID. ①이 없으면 셸에 Enter까지 오입력되고, ②가 없으면 exec 직후 canonical 구간에서 커널 에코를 claude의 화면 반영으로 오판해 첫 입력을 잃고, ③이 없으면 원래 세션이 죽은 뒤 같은 tty에 새로 뜬 claude로 남은 입력이 흘러든다 — `!…` 셸 모드 입력이면 의도치 않은 명령까지 실행된다 (모두 실측). 재시도·재전송처럼 입력을 보내는 경로를 새로 만들 때도 그 앞에서 ③을 다시 태운다 — 복구 경로가 게이트 밖으로 새기 쉽다
- claude 입력은 [개행 없는 타이핑 → 화면 반영 확인 → CR(`\r`) 제출] 순서다 — LF(`\n`)는 제출로 인식되지 않고(실측), 게이트를 통과한 뒤에도 TUI가 입력을 아직 그리지 못하는 순간이 있어 반영을 확인하기 전에는 CR을 보내지 않는다. "텍스트+개행 한 번에 전송"으로 단순화하면 안 된다
- 기본값·프리셋·표시 판정은 `extension/defaults.js`가 단일 출처다 — content script·service worker·옵션 페이지가 모두 이 파일을 먼저 로드한다. 옵션 페이지 CSS 토큰은 앱 `Theme.swift` 팔레트의 미러라, 한쪽 색을 바꾸면 다른 쪽도 바꾼다
- 옵션 페이지에서 storage 쓰기는 [저장] 버튼 하나로만 일어난다 — 가져오기도 storage에 직접 쓰지 않고 편집 상태만 채운다
- 이슈 버튼은 상태 배지(Open/Closed) 줄에 붙인다 — 제목(h1) 안에 넣으면 제목 길이에 따라 다음 줄로 밀리고, 모듈 CSS 클래스명에는 빌드 해시가 붙어 선택자로 쓸 수 없다(그래서 배지를 감싼 flex 조상을 찾아 append한다)
- 드래그 순서 변경을 브라우저 자동화로 검증할 때, CDP 합성 입력은 `dragstart`∼`dragend`까지만 재현하고 네이티브 `drop`을 완결하지 못하므로(실측) 드롭 이후 로직은 합성 `DragEvent`로 확인한다
- 도구 확인(`Core/ToolChecker.swift`)은 반드시 로그인 셸을 인터랙티브(`-i`)로 띄워서 한다 — `z`는 zoxide가 rc에서 정의하는 셸 함수라 실행 파일 탐색으로는 찾을 수 없고, GUI 앱의 PATH·SHELL은 로그인 셸과 다르다
- GUI 앱은 PATH가 `/usr/bin:/bin` 수준이라 wezterm CLI는 `/opt/homebrew/bin` 등 명시적 후보를 탐색해야 한다
- 새 탭은 사용자가 보고 있던 창에 만든다 — `wezterm cli spawn`은 `--window-id`가 없으면 `WEZTERM_PANE`으로 창을 정하는데 GUI 앱에는 그 변수가 없어 mux의 첫 창(= 가장 오래된 창)에 탭이 생긴다(실측). 창을 못 찾았을 때와 지정한 창이 그 사이 닫혔을 때의 폴백까지가 한 세트다(`Core/TerminalRunner.swift`) — 중간에서 포기하면 `wezterm start` fallback이 새 창을 띄워 고치려던 증상이 되살아난다. iTerm2의 `current window`는 이미 최근 활성 창이라 같은 처리가 필요 없다
- 확장 ID는 manifest `key`로 고정된다 — ID가 컴퓨터마다 같아야 `storage.sync` 설정이 같은 계정의 Chrome끼리 동기화되기 때문. 개인키(`~/Library/Application Support/TerminalCheckout/extension-key.pem`)는 리포 밖이며 unpacked 로드에는 manifest의 공개키만 있으면 된다. `allowed_origins`에 함께 등록된 경로 기반 옛 ID는 전환기용이다
- 확장 변경을 반영하려면 chrome://extensions에서 새로고침해야 하되, key 추가처럼 **ID가 바뀌는 변경은 새로고침이 아니라 제거 후 재로드**여야 한다
- Chrome Web Store 전환 시 `Installer.allowedExtensionIDs`에 store ID를 추가한다. CWS 업로드 zip에는 manifest `key` 필드를 넣을 수 없다 — key 없는 zip을 먼저 올려 store ID를 예약하는 것이 공식 절차다
