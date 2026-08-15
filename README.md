# Terminal Checkout

GitHub PR·저장소 페이지에서 클릭 한 번으로 터미널(iTerm2 / WezTerm)에서 해당 브랜치를 checkout하는 Chrome 확장 프로그램 + 맥 앱입니다.

## 왜 앱인가?

macOS는 자동화(Apple Events) 권한을 "responsible process"에 귀속시킵니다. Chrome이 native host를 직접 띄워 터미널을 제어하면 권한 주체가 **Chrome**이 되어, Chrome 전체에 넓은 권한을 허용해야 했습니다.

Terminal Checkout.app 구조에서는:

- Chrome이 띄우는 relay는 아무 것도 실행하지 않고 앱에 전달만 합니다
- 실제 터미널 제어는 LaunchServices로 실행된 **Terminal Checkout.app**이 수행합니다
- 따라서 **"Terminal Checkout → iTerm2 제어" 권한 하나만** 허용하면 됩니다. Chrome이나 python3에는 아무 권한도 필요 없습니다.

```
┌──────────────┐   stdio    ┌──────────────┐  unix socket  ┌──────────────────────┐   AppleScript /   ┌──────────────────┐
│  Chrome 확장  │──────────▶│ relay (중계만) │──────────────▶│ Terminal Checkout.app │──────────────────▶│  iTerm2/WezTerm  │
│ (JavaScript) │            │  (앱 번들 내)  │               │  ← TCC 권한은 여기에만  │   wezterm cli     │                  │
└──────────────┘            └──────────────┘               └──────────────────────┘                   └──────────────────┘
```

relay는 앱이 꺼져 있으면 자동으로 백그라운드 실행하므로, 앱을 항상 켜둘 필요는 없습니다.

## 요구 사항

- macOS 13+
- Google Chrome
- iTerm2 또는 WezTerm
- Swift 툴체인 (Xcode 또는 Command Line Tools) — 빌드용
- [zoxide](https://github.com/ajeetdsouza/zoxide) 또는 [z.sh](https://github.com/rupa/z) (디렉토리 점프 도구)

## 설치

### 0. zoxide 설치 (이미 설치되어 있다면 건너뛰기)

```bash
brew install zoxide
```

`~/.zshrc`에 다음 줄 추가 후 `source ~/.zshrc`:
```bash
eval "$(zoxide init zsh)"
```

> zoxide는 자주 방문하는 디렉토리를 학습해서 `z 폴더명`으로 빠르게 이동할 수 있게 해주는 도구입니다.
> 사용하기 전에 해당 디렉토리를 한 번 이상 `cd`로 방문해야 합니다.

### 1. 앱 설치

```bash
git clone https://github.com/dazebug/terminal-checkout.git
cd terminal-checkout
./install.sh
```

`install.sh`는 앱을 빌드해 `~/Applications/Terminal Checkout.app`으로 설치하고 실행합니다. sudo 불필요, 비대화식, 멱등입니다.

### 2. 앱 설정 창에서 마무리

앱이 열리면 설정 창에서 순서대로 진행합니다. Native Host 등록과 확장 폴더 준비는 앱 실행 시 자동으로 끝나 있습니다. 설정 창은 상태 기반으로 표시됩니다 — **완료된 항목의 카드는 사라지고 상단 파이프라인 표시등(●)으로만 남습니다.**

1. **확장 프로그램** — [Chrome에 설치하기] 클릭 (폴더 경로가 클립보드에 복사되고 chrome://extensions가 열리며, 창에 ①→④ 안내가 나타납니다). 이어서:
   - 우측 상단 **개발자 모드** 켜기
   - 좌측 상단 **압축해제된 확장 프로그램을 로드합니다** 클릭
   - 파일 선택 창에서 **⇧⌘G → ⌘V(붙여넣기) → Enter → [선택]**
   - **개발자 모드는 켜둔 채로 유지하세요** — Chrome 133+부터 끄면 unpacked 확장이 비활성화됩니다
   - 이 항목은 GitHub PR 페이지에서 버튼을 처음 눌러 요청이 실제로 도착하면 완료 처리됩니다
2. **터미널** — 명령을 실행할 터미널(iTerm2 / WezTerm)을 선택합니다
3. **iTerm2 제어 권한** (iTerm2 선택 + 권한 미허용 시에만 표시) — [iTerm2 권한 요청] 클릭 → 프롬프트에서 허용 (권한은 이 앱에만 부여됩니다. WezTerm은 권한이 필요 없습니다)
4. **동작 테스트** — [터미널에서 실행] 클릭, 터미널 새 탭에서 echo가 실행되면 완료

설정이 모두 끝나면 창에는 터미널 선택·동작 테스트와 [확장 옵션 페이지 열기]·[설치 안내 다시 보기]만 남습니다.

> 향후 Chrome Web Store(unlisted) 배포로 전환하면 이 과정은 스토어 링크 클릭 한 번으로 줄어들 예정입니다.

앱은 보이지 않게 백그라운드로 동작합니다 — 메뉴 막대 아이콘이 없고, Dock에는 설정 창이 열려 있는 동안만 나타납니다. 설정 창을 다시 열려면 Spotlight(⌘Space)나 Launchpad에서 **Terminal Checkout**을 실행하세요. 앱이 꺼져 있어도 확장 버튼을 누르면 자동으로 실행되므로 항상 켜둘 필요가 없습니다.

## 사용법

### PR 페이지

PR 헤더의 브랜치 이름 옆에 나타나는 버튼을 클릭하면 설정된 명령이 터미널 새 탭에서 실행됩니다. 버튼의 표시는 이모지 하나든 여러 개(🌳🤖)든, 짧은 이름(리뷰, WT)이든 자유입니다. 확장 아이콘을 클릭하면 첫 번째 버튼이 실행됩니다.

기본 명령 (checkout 실패 시 — 예: 브랜치가 워크트리에 체크아웃된 경우 — 관례 경로 `../{repo}-{branch_underbar}`의 워크트리로 이동):
```bash
z {repo} && git fetch origin && { git checkout {branch} || cd ../{repo}-{branch_underbar}; }
```

### claude 입력

command가 `claude`를 실행한다면, 옵션 페이지에서 버튼마다 claude에게 보낼 입력을 최대 5개까지 예약할 수 있습니다 — 예: `/review` 다음 `PR {branch} 변경사항을 요약해줘`. 앱이 새 탭의 포그라운드 프로세스가 claude로 바뀐 것을 확인한 뒤에만 순서대로 타이핑하므로, claude가 뜨기 전 셸에 잘못 입력되는 일은 없습니다. 2분 내에 claude가 뜨지 않으면 조용히 보내지 않습니다.

알아둘 한계: 입력은 한 줄씩만 가능합니다. WezTerm이 꺼져 있어 새 프로세스로 뜬 경우(fallback)에는 전달되지 않습니다. 각 입력은 화면에 실제로 타이핑된 것을 확인한 뒤에만 제출되므로, 새 폴더에서 claude의 신뢰(trust) 프롬프트가 떠 있는 동안에는 전달이 보류됩니다 — 15초 안에 수락하면 이어서 전달되고, 그보다 오래 걸리면 그 입력부터 전송을 포기합니다.

### 저장소 페이지

헤더의 **Open in Terminal** 버튼을 클릭하면 해당 저장소 디렉토리로 이동한 새 탭이 열립니다.

## 설정

- **설치·터미널 선택·권한·확장 폴더**: Terminal Checkout.app 설정 창
- **버튼·명령·main 브랜치**: 확장 프로그램 옵션 페이지 (앱 설정 창의 [확장 옵션 페이지 열기] 또는 `chrome://extensions` → Terminal Checkout → 확장 프로그램 옵션)

Command에서 쓸 수 있는 변수:

| 변수 | 값 |
|:---|:---|
| `{repo}` | 저장소 이름 |
| `{branch}` | PR의 head 브랜치 |
| `{main}` | main 브랜치 (리포별 오버라이드 → PR 페이지 감지 → 글로벌 기본값 순으로 결정) |
| `{branch_underbar}` | `{branch}`의 `/`를 `_`로 치환한 값 (worktree 디렉토리명 등에 사용) |

변수는 command와 claude 입력 양쪽에서 동일하게 동작합니다.

## 개발

```bash
cd app && swift test   # Core 단위 테스트
app/build.sh           # 앱 번들 빌드 (app/build/Terminal Checkout.app)
app/e2e.sh             # relay ↔ 소켓 ↔ 서버 왕복 회귀 테스트 (빌드 후)
```

## 삭제

```bash
./uninstall.sh
```

Chrome 확장 프로그램은 `chrome://extensions`에서 직접 삭제하세요.

## 보안

- Native Host relay는 특정 확장 프로그램 ID에서만 호출 가능 (`allowed_origins` 화이트리스트)
- 변수 값은 영숫자·`-_./` 화이트리스트 검증을 거쳐 command injection 방지
- 앱 소켓은 같은 사용자(uid)의 프로세스만 접근 가능 (모드 0600 + peer 검증)
- GitHub 도메인에서만 동작

## 트러블슈팅

### "Native host has exited" 또는 확장에서 반응이 없음

앱 설정 창(Spotlight에서 Terminal Checkout 실행)을 여세요. 문제가 있으면 해당 카드가 자동으로 나타납니다 — Chrome 연결 카드가 보이면 [등록/업데이트]를 누르세요. 저장소를 옮겼거나 앱을 재설치한 경우 `./install.sh`를 다시 실행하면 됩니다.

### 권한을 거부해버렸을 때

앱 설정 창의 [시스템 설정 열기]로 이동해 **개인정보 보호 및 보안 → 자동화 → Terminal Checkout → iTerm2**를 켜세요.

### 재빌드 후 권한을 다시 물어봄

ad-hoc 서명을 사용하므로 앱을 다시 빌드하면 서명 정체성이 바뀌어 자동화 권한을 다시 요청할 수 있습니다. 한 번 허용하면 됩니다.

### z 명령이 동작하지 않음

터미널 설정에서 로그인 쉘을 사용하도록 되어 있는지, zoxide/z가 쉘 설정 파일(`.zshrc`, `.bashrc`)에 제대로 설정되어 있는지 확인하세요.

### 버튼이 보이지 않음

GitHub UI 업데이트로 버튼 위치가 변경될 수 있습니다. 확장 아이콘 클릭은 항상 동작합니다.
