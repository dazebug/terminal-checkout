# Terminal Checkout

GitHub PR·저장소 페이지에서 클릭 한 번으로 터미널(iTerm2 / WezTerm)에서 해당 브랜치를 checkout하는 Chrome 확장 프로그램입니다.

## 요구 사항

- macOS
- Chrome 브라우저
- iTerm2 또는 WezTerm
- Python 3
- [zoxide](https://github.com/ajeetdsouza/zoxide) 또는 [z.sh](https://github.com/rupa/z) (디렉토리 점프 도구)

## 설치

### 0. zoxide 설치 (이미 설치되어 있다면 건너뛰기)

```bash
brew install zoxide
```

`~/.zshrc`에 다음 줄 추가:
```bash
eval "$(zoxide init zsh)"
```

적용:
```bash
source ~/.zshrc
```

> zoxide는 자주 방문하는 디렉토리를 학습해서 `z 폴더명`으로 빠르게 이동할 수 있게 해주는 도구입니다.
> 사용하기 전에 해당 디렉토리를 한 번 이상 `cd`로 방문해야 합니다.

### 1. Native Host 설치

```bash
git clone https://github.com/dazebug/terminal-checkout.git
cd terminal-checkout
./install.sh
```

`install.sh`는 비대화식이며 sudo가 필요 없습니다. 확장 프로그램 ID는 `extension/` 폴더의 절대 경로로부터 자동 계산되므로 별도 입력이 필요 없습니다.

> 확장 프로그램에 고정 ID(manifest `key`)를 쓰는 경우에는 `./install.sh --id EXTENSION_ID`로 직접 지정합니다.

### 2. Chrome 확장 프로그램 로드

1. Chrome에서 `chrome://extensions` 열기 (첫 설치 시 `install.sh`가 자동으로 열어줍니다)
2. 우측 상단 **개발자 모드** 켜기
3. **압축해제된 확장 프로그램을 로드합니다** 클릭
4. `terminal-checkout/extension` 폴더 선택

저장소를 다른 경로로 옮겼다면 `./install.sh`를 다시 실행하세요 (멱등하게 동작합니다).

## 사용법

### PR 페이지

PR 헤더의 브랜치 이름 옆에 나타나는 아이콘 버튼을 클릭하면 설정된 명령이 터미널 새 탭에서 실행됩니다. 확장 아이콘을 클릭하면 첫 번째 버튼이 실행됩니다.

기본 명령:
```bash
z {repo} && git fetch origin && git checkout {branch}
```

### 저장소 페이지

헤더의 **Open in iTerm / Open in WezTerm** 버튼을 클릭하면 해당 저장소 디렉토리로 이동한 새 탭이 열립니다.

## 설정

확장 프로그램 옵션 페이지(`chrome://extensions` → Terminal Checkout → 세부정보 → 확장 프로그램 옵션)에서 설정합니다.

- **Terminal**: 명령을 실행할 터미널 앱 (iTerm2 / WezTerm)
- **Command Buttons**: PR 페이지에 표시할 버튼 (최대 3개). Emoji가 버튼 모양, Label이 툴팁입니다.
- **Default Main Branch**: PR 페이지에서 base branch 감지가 안 될 때 쓸 기본값
- **Per-Repo Main Branch Override**: 특정 리포의 main 브랜치 지정 (base branch 감지보다 우선)

Command에서 쓸 수 있는 변수:

| 변수 | 값 |
|:---|:---|
| `{repo}` | 저장소 이름 |
| `{branch}` | PR의 head 브랜치 |
| `{main}` | main 브랜치 (리포별 오버라이드 → PR 페이지 감지 → 글로벌 기본값 순으로 결정) |
| `{branch_underbar}` | `{branch}`의 `/`를 `_`로 치환한 값 (worktree 디렉토리명 등에 사용) |

## 삭제

```bash
./uninstall.sh
```

Chrome 확장 프로그램은 `chrome://extensions`에서 직접 삭제하세요.

## 동작 원리

```
┌──────────────────┐     ┌───────────────────┐     ┌──────────────────┐
│  Chrome 확장     │────▶│   Native Host     │────▶│  iTerm2/WezTerm  │
│  (JavaScript)    │     │   (Python)        │     │                  │
└──────────────────┘     └───────────────────┘     └──────────────────┘
```

1. **Chrome 확장**: PR 페이지에서 repo명·브랜치명·base 브랜치 추출
2. **Native Messaging**: Chrome이 로컬 Python 스크립트에 command template과 변수 전달
3. **Native Host**: 변수를 치환해 최종 명령 생성 후 터미널에 전달 (iTerm2는 AppleScript, WezTerm은 `wezterm cli`)
4. **터미널**: 새 탭에서 명령 실행

## 보안

- Native Host는 특정 확장 프로그램 ID에서만 호출 가능 (화이트리스트)
- 변수 값은 `^[a-zA-Z0-9\-_./]+$` 검증을 거쳐 command injection 방지
- GitHub 도메인에서만 동작

## 트러블슈팅

### "Native host has exited" 오류

`./install.sh`를 다시 실행하세요. 설치 스크립트가 python3 절대경로로 래퍼를 다시 만들고 셀프 테스트까지 수행합니다.

수동 확인:
```bash
printf '\x02\x00\x00\x00{}' | ./native-host/run.sh
```

### z 명령이 동작하지 않음

터미널 설정에서 로그인 쉘을 사용하도록 되어 있는지 확인하세요.
zoxide/z가 쉘 설정 파일(`.zshrc`, `.bashrc`)에 제대로 설정되어 있어야 합니다.

### 버튼이 보이지 않음

GitHub UI 업데이트로 버튼 위치가 변경될 수 있습니다.
확장 아이콘 클릭은 항상 동작합니다.
