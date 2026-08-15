# CLAUDE.md

GitHub PR·저장소 페이지에서 터미널(iTerm2/WezTerm)로 브랜치 checkout하는 Chrome 확장 프로그램. `extension/`(Manifest V3) + `native-host/`(Native Messaging, Python 표준 라이브러리만 사용) 구성.

## 주요 명령어

```bash
./install.sh                         # 설치 (sudo 불필요, 멱등, 완전 비대화식)
./install.sh --id EXT_ID             # manifest에 key를 넣어 고정 ID를 쓰는 경우
./uninstall.sh
git config core.hooksPath .githooks  # CLAUDE.md → AGENTS.md symlink 훅 활성화 (클론 후 1회)
```

Extension ID는 기본적으로 `extension/` 절대경로의 SHA-256으로 자동 계산된다.

## 개발 시 참고사항

- Native Messaging host 이름(`com.dazebug.terminal_checkout`)은 소문자 영숫자·`_`·`.`만 허용된다. 하이픈을 넣으면 Chrome이 host를 인식하지 못한다
- 설정값 `terminal`의 `iterm`/`wezterm`, DOM id `terminal-iterm`은 터미널 앱 식별자다. 확장 이름이 Terminal Checkout이어도 이 값들은 iTerm2를 가리키므로 바꾸지 않는다
- command template 시스템: `{repo}`, `{branch}`, `{main}`, `{branch_underbar}` 변수를 Native Host에서 치환
- main 브랜치 결정 순서: 리포별 오버라이드 → PR 페이지 base branch → 글로벌 기본값
- iTerm2는 AppleScript로, WezTerm은 `wezterm cli spawn`(실패 시 `wezterm start` fallback)으로 제어
- 입력값 검증: `^[a-zA-Z0-9\-_./]+$` 정규식으로 command injection 방지
- 아이콘 버튼은 `span.head-ref` 바깥(clipboard-copy wrapper 뒤)에 삽입
