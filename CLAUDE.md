# CLAUDE.md

GitHub PR·저장소 페이지에서 터미널(iTerm2/WezTerm)로 브랜치 checkout하는 Chrome 확장 프로그램 + 맥 앱. `extension/`(Manifest V3) + `app/`(Swift 패키지 → Terminal Checkout.app: relay + 소켓 서버 + 설정 UI) 구성.

## 주요 명령어

```bash
./install.sh                         # 빌드 + ~/Applications 설치 + 실행 (sudo 불필요, 멱등, 비대화식)
./uninstall.sh
app/build.sh                         # 번들만 빌드 → app/build/Terminal Checkout.app
cd app && swift test                 # Core 단위 테스트
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
- 터미널 선택은 앱이 단일 소스로 관리한다(UserDefaults `terminal`: `iterm`/`wezterm`). 확장이 보내는 `terminal` 필드는 서버가 무시한다(Core의 파싱은 하위 호환용으로 유지). `iterm` 값은 확장 이름과 무관하게 iTerm2를 가리키는 식별자이므로 바꾸지 않는다. iTerm2 권한 섹션은 iTerm2 선택 시에만 표시된다
- command template 시스템: `{repo}`, `{branch}`, `{main}`, `{branch_underbar}` 변수를 앱(`Core/CommandRenderer.swift`)에서 치환. 값 검증은 영숫자·`-_./` 화이트리스트 문자 검사 (파이썬 시절 정규식 `$`가 끝 개행을 허용하던 구멍까지 막은 것 — 정규식으로 되돌리지 말 것)
- main 브랜치 결정 순서: 리포별 오버라이드 → PR 페이지 base branch → 글로벌 기본값 (`extension/background.js`)
- iTerm2는 osascript(앱의 자식 프로세스 → 권한이 앱에 귀속), WezTerm은 `wezterm cli spawn`(실패 시 `wezterm start` fallback). GUI 앱은 PATH가 `/usr/bin:/bin` 수준이라 wezterm CLI는 `/opt/homebrew/bin` 등 명시적 후보를 탐색한다
- 확장 ID는 로드된 폴더 절대경로의 SHA-256 앞 32 hex를 a-p로 매핑해 계산(`Core/ExtensionID.swift`). 확장 폴더는 App Support 고정 경로 단일 위치이며, 앱 실행 시 번들 확장과 사본을 내용 비교해 다르면 자동 재복사한다(수동 복사·재설치 버튼 없음). 반영에는 chrome://extensions에서 확장 새로고침이 필요하다
- `allowed_origins`는 배열이다. Chrome Web Store 전환 시 `Installer.allowedExtensionIDs`에 store ID만 추가하면 된다 (CWS 업로드 zip에는 manifest `key` 필드 금지 — key 없는 zip을 먼저 올려 store ID를 예약하는 것이 공식 절차). unpacked 확장은 Chrome 133+부터 개발자 모드가 켜져 있어야 활성 유지된다
- ad-hoc 서명이므로 재빌드하면 자동화 권한을 다시 물을 수 있다 (정상 동작)
- 아이콘 버튼은 `span.head-ref` 바깥(clipboard-copy wrapper 뒤)에 삽입
