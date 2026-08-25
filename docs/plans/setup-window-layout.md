# setup-window-layout

- 대상: `app` SwiftPM 패키지와 설정 창 테스트
- 시작 커밋: `a13fa48`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/setup-window-layout-review` (`worktree-setup-window-layout-review`, `a13fa48`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-setup-window-layout-work` (`setup-window-layout-work`, `a13fa48`)
- 현재: R1 · 마지막 승격 R1 재현 커밋 · 리뷰 중 없음 · 게이트 red(의도된 재현: 481 / 1 skipped / 2 failures, 전부 신규 케이스)
- 최근 검증자 판정: "이 계획으로 시작하는 데 합의한다. 단 R1 첫 배정은 항목 1∼3의 재현·계측뿐이고, 항목 4의 수정 배정은 red를 본 뒤에만 나간다." · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/4ffc53dd-bc2a-45a7-9448-a47a2106d5f6/scratchpad/R0-review1.md`

## 배경 — 확인한 원천

- [이슈 #34](https://github.com/dazebug/terminal-checkout/issues/34) — 권한 부여 또는 재설치 후 재부여 때 설정 창의 빈 띠와 상단 클리핑이 발생하며, 사용자 관측상 권한 전이가 트리거다.
- [PR #36](https://github.com/dazebug/terminal-checkout/pull/36) — headless 가용 높이 681pt에서 콘텐츠 721.5pt, iTerm2 선택 시 830.5pt인 수치와 스크롤 인수 분기를 제시한다.
- [8fccab5](https://github.com/dazebug/terminal-checkout/commit/8fccab5) — 창 크기 계산을 `FittedContentStackView.layout()`으로 옮기고, 가시성 토글 뒤 정착·측정과 visible-frame clamp를 한 곳에 둔 선행 수정이다.
- [9460d5a](https://github.com/dazebug/terminal-checkout/commit/9460d5a6fb7cca66fe799b35b967f179a67ca069) — 이슈 본문이 지목한 빌드이며, 설정 창의 접근성 안내 문구와 상태 길이가 현재 레이아웃 입력에 포함된다.
- `CLAUDE.md` — 설정 창은 문서 스택이 측정의 단일 소유자이고, 비뒤집힌 documentView의 좌표·권한 상태·레이아웃 순서를 보존해야 한다는 프로젝트 규약이다.
- `docs/context/testing.md` — `visibleFrameOverride` setter가 소유 레이아웃을 dirty하게 해야 하며, 테스트가 한 방향 oracle만 가지면 환경에 따라 계속 초록일 수 있다는 D322·D323의 근거다.
- `docs/context/signing-and-permissions.md` — ad-hoc 재서명이 Accessibility TCC 상태를 무효화할 수 있어 설치 중 재부여 경로도 기기 검증 범위에 들어간다.

## 목표

Accessibility가 false에서 true로 바뀌는 동안 설정 창이 열려 있어도, `refresh()`가 숨긴 콘텐츠와 창·스크롤 document의 크기가 같은 정착된 레이아웃을 사용한다.
콘텐츠가 화면에 들어오면 창 높이뿐 아니라 document와 viewport의 배치도 일치하고, 들어오지 않으면 창만 visible frame으로 clamp되며 document는 줄어들거나 겹치지 않는다.
레이아웃을 고정점까지 반복한 뒤 한 번 더 돌려도 창 크기·document 배치·스크롤 위치가 변하지 않으며, 권한 전이·재설치 후 재부여·터미널 선택·도구·소켓·언어·상태 라벨 변화를 같은 불변식으로 검증한다.

## 완료의 정의

- 반드시 재현해 막아야 끝인 실패: Accessibility를 허용하지 않은 Warp 설정 창을 정착시킨 뒤 권한을 허용하고 System Settings에서 돌아와 key가 되게 하는 입력, 그리고 창이 열린 상태에서 `./install.sh` 후 같은 재부여를 하는 입력 → 창 높이는 이전의 큰 값에 남고 짧아진 비뒤집힌 document가 아래에 놓이는 빈 띠 또는 새 콘텐츠의 상단 클리핑.
- acceptance oracle: 드라이버 환경에서 먼저 최소 provider seam만 연결한 현재 트리에 반복 settle·계측을 적용해 red가 되는지 확인한다. red가 없으면 수정으로 진행하지 않고 그 사실과 실기기와 다른 경계를 보고한다. red가 확인된 뒤에만 green을 요구하며, 콘텐츠가 화면에 들어오는 경우 `contentHeight(window) == rootStack.fittingSize.height`와 `rootStack.frame.height == rootStack.fittingSize.height`가 각각 0.5pt 이내이고, `scroll.documentVisibleRect.maxY == document.frame.maxY` 및 `card.header`가 viewport 안에 있어야 한다. 짧은 document에서는 document frame과 documentVisibleRect의 양 끝이 일치해 viewport에 빈 영역이 없어야 한다. 콘텐츠가 화면에 들어오지 않는 경우 `contentHeight(window) == visible.height`가 1pt 이내이고 document는 clip보다 커야 한다. settle을 고정점까지 반복한 뒤 한 번 더 실행해 창 크기·document frame·documentVisibleRect·scroll origin이 tolerance 안에서 바뀌지 않아야 하며, 언어 변경의 scroll anchor·focus·selection과 모든 status label의 wrap 계약도 함께 green이어야 한다.
- 기기 acceptance 1 (R1 재현 red 직후 한 번 실행): `tccutil reset Accessibility com.dazebug.terminal-checkout` → 앱 실행 → 설정 창이 정상인지 확인 → [Request Accessibility Permission] → System Settings에서 Terminal Checkout 허용 → 설정 창으로 복귀 → 빈 띠·상단 클리핑 없이 계속 정상인지 확인한다.
- 기기 acceptance 2: 창이 열린 설치 위에 `./install.sh` 실행 → ad-hoc 재서명으로 권한이 reset된 것을 확인 → Warp claude 입력용 Accessibility를 다시 허용 → 설정 창으로 복귀 → 같은 레이아웃 불변식이 계속 성립하는지 확인한다. 두 결과는 종결 시 PR 본문으로 승계한다.
- 코퍼스 범위: `SetupWindowController.swift`의 직접 `isHidden` 대입을 세는 `rg -n "\\.isHidden\\s*=" app/Sources/App/SetupWindowController.swift | wc -l` → 18, raw `refresh()` match를 세는 `rg -n "refresh\\(\\)" app/Sources/App/SetupWindowController.swift | wc -l` → 23(주석·정의 포함)을 근거로 삼고, 실제 값의 출처는 전수 소탕 표로 열거한다. 여기에 `supportedLocales`가 제공하는 5개 앱 언어와 `SetupWindowLayoutTests.swift:83∼115`의 각 측정 경로를 포함한다.
- 원자성·부분 실패·롤백 경계: N/A — UI 상태를 다시 읽어 같은 결과를 만드는 레이아웃이며 외부 명령을 이 항목에서 실행하지 않는다. `window.setContentSize`와 scroll restore는 반복 가능한 상태 갱신이어야 하고, 테스트용 Accessibility provider는 각 테스트의 `defer` 또는 tearDown에서 실제 provider로 복구한다. 실제 TCC 변경은 기기 acceptance에서만 수행하며 실패 시 코드 green으로 간주하지 않는다.

## 비목표 — 건드리지 않는다

- `app/Sources/Core/WarpControl.swift`의 실제 TCC API와 Warp 입력 전달 — 설정 창이 읽는 상태의 seam만 두고 권한 의미나 입력 게이트는 바꾸지 않는다.
- `install.sh`의 cdhash 비교·TCC reset과 터미널 실행·Chrome relay·socket protocol — 재설치 경로는 재현 입력과 수동 acceptance로만 다룬다.
- `capturePlace`·`restore`의 언어 변경 계약을 숫자 offset이나 flipped document 가정으로 단순화하는 변경 — anchor role, UTF-16 selection, 비뒤집힌 `maxY` 계산을 유지한다.
- 레이아웃 문제와 무관한 카탈로그 문구·옵션 저장·확장 기능 — 상태 라벨 길이를 재현하는 데 필요한 기존 리소스 외에는 번역을 바꾸지 않는다.

## 불변 원칙

가시성 토글 또는 intrinsic-size 변경 → constraint/layout pass 정착 → `fittingSize` 측정 → 창 크기·visible-frame 보정의 순서를 `FittedContentStackView`의 단일 경로로 유지한다.
`setContentSize`가 layout 안에서 재진입을 만들더라도 잘못된 고정점에서 멈추지 않게 한다. test settle은 한 번의 `layoutSubtreeIfNeeded()`에 의존하지 않고, 창 크기·fittingSize·document frame·documentVisibleRect·scroll origin snapshot이 변하지 않을 때까지 반복하되 이름 있는 상한 N회에 도달하면 실패한다.
각 pass의 `layout()` 호출 수와 `fittingSize`, clamp target, window content height, document frame, documentVisibleRect, scroll origin을 test-only 계측으로 기록한다. 계측은 원인 확인 뒤 제거하거나 테스트 계약으로 남길지를 결정하며, 계측 없이 수정 방향을 고르지 않는다.
`visibleFrameOverride` setter는 첫 layout 이후 대입되어도 소유 스택에 layout을 예약해야 하며, 테스트 호출자가 별도의 `needsLayout`을 기억해야 하는 계약으로 되돌리지 않는다.
`lastRequestedSize`의 early return은 현재 document와 새 `fittingSize`가 반영된 target을 버리는 근거가 될 수 없다. 콘텐츠가 화면에 들어올 때 창이 콘텐츠보다 큰 상태를 허용하지 않고, 화면보다 큰 콘텐츠는 stack을 squeeze하지 않은 채 scroll view가 인수한다.
비뒤집힌 documentView에서 viewport 상단은 `documentVisibleRect.maxY`로 계산하고, 짧은 document가 clip 아래에 놓이거나 긴 document의 첫 카드가 원점에서 잘리는 증상을 같은 창·document 높이 불변식으로 막는다.
높이 equality와 배치 equality는 별도 oracle이다. document가 clip보다 짧을 때의 빈 위쪽 영역, document가 clip보다 길 때 top position에서 header가 잘리는 경우를 각각 독립적으로 실패시킨다.
`visibleFrameOverride` 경로만으로 실제 화면 선택을 증명하지 않는다. `window.screen`과 `NSScreen.main`을 선택하는 분기를 이름 있는 함수로 분리해 unit test에 닿게 할지, 분리하지 않는다면 다중 디스플레이 기기 sweep으로 닫을지를 R1 계측 뒤 결정한다. 사용자의 디스플레이 구성은 Mac Pro + 외장 2대(가로 1, 세로 1)로 확인됐다. 세로 디스플레이의 `visibleFrame.height`가 가로와 크게 다르므로, 다중 디스플레이에서 실제 화면 선택과 clamp를 대조한다.
`refresh()`는 상태 라벨·카드와 섹션의 현재 값을 다시 쓰되 ordinary refresh에서 view tree를 재생성하지 않는다. `rebuildForLanguageChange()`는 `capturePlace` → build → refresh → layout 정착 → `restore` 순서와 scroll anchor·포커스·UTF-16 selection 복원을 유지한다.
상태 라벨은 `makeStatusLabel(font:)`의 비단일행·wrap·`maximumNumberOfLines == 0`·`preferredMaxLayoutWidth == setupTextWidth` 계약을 유지한다. 텍스트 길이만 바뀌는 권한 상태와 tool/socket 결과도 같은 레이아웃 oracle의 대상이다.
테스트는 live `accessibilityIsTrusted()`나 실제 System Settings 권한을 뒤집지 않는다. 앱 계층에만 주입 가능한 provider를 만들고, 테스트가 끝나면 실제 동작으로 되돌린다. provider가 만든 red는 실제 TCC UI를 대신하는 것이 아니라 `refresh()`의 상태 전이와 레이아웃 경계를 검증한다. R1의 provider seam과 반복 settle/계측은 재현을 위한 최소 변경이며, red 확인 전에는 production layout fix를 배정하지 않는다.

## 배치 점검 (0라운드)

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | N/A — 이번 작업 트리는 worktree gate가 아니라 별도 clone이다. 공유 기준 트리에서 `info/exclude`로 ignored인 사실은 드라이버가 확인했다. |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | N/A — 별도 clone에서는 worktree.baseRef 계약을 적용하지 않는다. 작업 트리 HEAD는 `a13fa48`이고 기준 트리 HEAD도 `a13fa48`이다. |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-setup-window-layout-work` · `setup-window-layout-work` · `a13fa48` |
| 트리마다 `uv sync` (기준·작업) | N/A — Python/uv 프로젝트가 아니라 SwiftPM 패키지다. |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | `HOME`, `CLAUDE_CODE_EXECPATH`, `CLAUDE_CODE_MESSAGING_SOCKET` 등은 읽혔지만 이 계획의 입력으로 사용하지 않았다. 외부 자산 의존 없음. |
| 증분 리뷰 소요(분) — 첫 세 번 | 미실시 — R0 설계 리뷰 전 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | R1에서 최소 Accessibility provider seam과 false→true 권한 전이 재현 fixture만 추가한다 | R1 재현·test seam | (a) `PermissionChecker.isAccessibilityGranted`가 `accessibilityIsTrusted()`를 직접 호출해 기존 테스트가 전이를 만들지 못함 | `app/Sources/App/PermissionChecker.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift` | — | claimed | 재실행: `cd <clone> && swift test --package-path app --filter SetupWindowLayoutTests` → `testAccessibilityGrantRefreshConvergesWithFittedPlacement`가 provider false→true 전이를 만들고 `accessibilitySection.isHidden` 전후를 단언; 481 tests / 1 skipped / 2 failures (전부 이 케이스) | |
| 2 | R1에서 `settle`을 고정점 반복으로 바꾸고 `layout()` 재진입·pass별 fitting 값을 계측한다 | R1 수렴 계측 | (a) 현재 `settle(_:)`은 `layoutSubtreeIfNeeded()`를 한 번만 호출함 (b) layout 재진입과 pass별 target 변화가 기록되지 않음 | `app/Sources/App/SetupWindowController.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Tests/AppTests/SetupWindowRedrawTests.swift` | 1의 권한 전이 입력 | claimed | 재실행: 같은 명령 → 고정점 settle(상한 20) 도입 후 기존 6 케이스 전원 통과, 신규 케이스만 red. TRACE: granted pass=1 fitting=747.0 target=747.0 applied=747.0, repeat layoutPasses=0 | |
| 3 | R1에서 `8fccab5`의 선행 계약과 override 밖의 `window.screen`·`NSScreen.main` 선택 분기를 Mac Pro + 외장 2대(가로 1, 세로 1)에서 대조한다 | 선행 수정·화면 선택 | — | `app/Sources/App/SetupWindowController.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Tests/AppTests/SetupWindowRedrawTests.swift`, `8fccab5` | 1∼2의 재현 계측 | claimed | `git show 8fccab5` 대조 결과 한 줄: visibility 변경 → layout 정착 → fitting 측정과 visible-frame clamp/moveInside를 `FittedContentStackView.layout()`에 모았지만 이번 권한 전이의 배치·수렴은 당시 계약에서 검증하지 않았다. 화면 선택 분기 한 줄: `window.screen`·`NSScreen.main`은 override 밖에서 여전히 미검증이다 | |
| 4 | R1 red 이후에만 잘못된 fixed point의 원천을 수정하고 높이·배치·수렴·scroll restore oracle을 닫는다 | 근본 레이아웃 수정 | (a) 높이만 보는 oracle은 빈 띠를 통과시킴 (b) 두 증상의 최초 원인이 측정 순서·early return·화면 선택·document 배치 중 무엇인지 아직 미확정 | `app/Sources/App/SetupWindowController.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Tests/AppTests/SetupWindowRedrawTests.swift` | 1∼3에서 red 확인 | todo | 이슈 #34 두 증상; `SetupWindowController.swift:15∼67`, `299∼353`; R1 pass trace와 placement assertion | |
| 5 | 4가 green인 뒤 두 재설치·재부여 경로를 실제 화면에서 검증하고 PR 본문 gate로 승계한다 | 기기 TCC·다중 디스플레이 acceptance | — | `install.sh`, `app/Sources/App/PermissionChecker.swift`, `docs/context/signing-and-permissions.md` | 4의 green | todo | 이슈 #34 재현 절차 두 가지; `docs/context/signing-and-permissions.md:3∼20` | |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶이고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다. 승격 칸에는 커밋 해시를 적는다.
- `의존`: 2와 3은 1의 권한 전이를 전제로 한다. 4는 1∼3을 적용한 현재 tree에서 red가 확인된 뒤에만 시작한다. 5는 4의 자동 gate가 green인 뒤에만 수행한다.
- R1 첫 배정은 1∼3의 재현·계측뿐이다. provider seam은 red를 만들기 위한 최소 변경이고, 반복 settle과 pass trace는 관찰 장치다. R1에서 red가 없으면 그 사실과 실기기와 다른 경계를 보고하고 멈추며, 4의 production layout fix는 배정하지 않는다.
- `확정 결함`: 레이아웃 최초 원인인 (a) 조기 `fittingSize` 측정, (b) `lastRequestedSize` early return, (c) non-flipped document 배치는 아직 확정하지 않는다. 표에는 현재 코드와 사용자 관측으로 확정된 테스트 공백·높이 불일치만 적고, R0 실측 후 결함 문구를 개정한다.
- 판정이 항목을 다시 열면 행을 고치지 말고 개정 항목으로 잇는다 — 같은 항목의 개정은 prime(`6′`), 형제 부류나 prime 소진 뒤는 letter(`6a`), 식별자는 재사용하지 않는다. 선행 행의 상태는 그 승격에 대한 마지막 판정이지 종결이 아니다.
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`.
- `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다. `verified`·`cleared`·`agreed`·`dropped`는 드라이버의 결정이다.
- 근거 칸에는 재실행 가능한 명령과 결과 줄, 테스트 이름과 수, 수치를 낸 파일 경로만 적는다. 이번 게이트의 환경 실패는 회귀 red가 아니다.

## 결정 원장

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 드라이버 | 이번 배정은 구현 계획 초안까지이며 코드 수정·테스트 수정·커밋을 금지한다 | 계획 파일만 작성하고 멈춘다 | 사용자 배정문; 작업 트리 `git status --short --branch`가 `## setup-window-layout-work`만 출력 | 드라이버가 후속 구현 승격을 정하지 않음 |
| D2 | 드라이버 | 완료는 권한 false→true 전이를 포함해야 하며 기존 초록 테스트가 현실과 다른 이유를 밝혀야 한다 | live TCC를 테스트에서 뒤집지 않고 provider seam을 항목 1로 둔다 | `PermissionChecker.swift:49∼61`; `SetupWindowLayoutTests.swift:203∼214` | seam의 최종 이름과 주입 위치는 구현 리뷰에서 결정 |
| D3 | 드라이버 | 빈 띠와 상단 클리핑은 한 부류의 양면인지 확인해야 한다 | 창 content height와 document fitting height의 양방향 equality/clamp를 공통 oracle로 삼고, non-flipped 위치를 별도 관찰한다 | `SetupWindowController.swift:15∼56`, `315∼353`; 이슈 #34 관측 | 최초 원인이 측정 순서·early return·scroll 배치 중 무엇인지는 red 전까지 open |
| D4 | 드라이버 | `fittingSize` 조기 측정, `lastRequestedSize` early return, documentView 배치가 원인일 수 있다 | 읽기 가설으로만 유지하고 구현 결론으로 승격하지 않는다 | 사용자 배정문의 읽기 전용 가설; 선행 수정 [8fccab5](https://github.com/dazebug/terminal-checkout/commit/8fccab5) | headless 테스트가 환경 실패해 이번 라운드에는 동적 수치가 없음 |
| D5 | 드라이버 | 이 환경의 게이트 실패는 구현 회귀로 반올림하면 안 된다 | 두 실행을 `환경 실패·판정 보류`로 기록하고 driver 환경에서 재실행한다 | `swift test --package-path app` → exit 1, clang ModuleCache `Operation not permitted`; cache env 재시도 → exit 1, `sandbox-exec: sandbox_apply: Operation not permitted` | Xcode/SwiftPM 실행 가능한 검증 환경에서 테스트 수와 red→green 필요 |
| D6 | 드라이버 | 높이 equality만으로는 짧은 document가 clip 아래에 놓이는 빈 띠와 top card clipping을 잡지 못한다 | `documentVisibleRect.maxY`·document `frame.maxY`, `card.header`의 viewport 포함, short-document의 양끝 일치를 별도 placement oracle로 둔다 | 이슈 #34의 배치 증상; `SetupWindowController.swift:322∼330`; 반박 1 | 실제 AppKit 좌표 tolerance와 header의 초기 top staging은 driver 환경에서 측정 |
| D7 | 드라이버 | `setContentSize`가 `layout()` 안에서 재진입하고 `lastRequestedSize`가 fixed point를 고정한다면 빈 띠·클리핑은 같은 부류일 수 있다 | R1에서 settle을 bounded fixed-point loop로 만들고 pass별 layout/fitting/target/frame trace를 낸다. red 전에는 수정 방향을 고르지 않는다 | `SetupWindowController.swift:47∼56`; `SetupWindowLayoutTests.swift:56∼58`; 반박 2 | 실제 재진입 횟수와 pass별 수치 미측정 |
| D8 | 드라이버 | override 밖의 `window.screen`·`NSScreen.main` 선택은 다른 앱에서 돌아오는 다중 디스플레이 경로에서 미검증이다 | R1 계측 뒤 화면 선택을 이름 있는 함수로 분리해 단위 테스트에 닿게 할지 결정하고, 어느 경우에도 소탕 표와 device display sweep을 남긴다 | `SetupWindowController.swift:50∼52`; 반박 3 | 실제 `window.screen` 선택과 screen별 clamp 수치는 미측정이며, 디스플레이 구성은 D15에서 확인했다 |
| D9 | 드라이버 | `8fccab5`의 visibility→settle→measure 계약이 이번 권한 text/hidden 전이·재진입·placement를 덮었는지는 확인되지 않았다 | `git show 8fccab5`로 선행 계약과 이번 입력의 틈을 먼저 대조하고, 같은 자리에 수동 resize를 추가하는 point fix는 red 후에만 검토한다 | `8fccab5`; `SetupWindowController.swift:15∼56`; 반박 4 | 선행 계약의 실제 누락 축은 R1 trace 전 open |
| D10 | 드라이버 | R1에서 red가 없으면 항목 4의 수정 근거가 없다 | R1 첫 배정은 재현·계측만 하고, red가 없으면 실기기와 테스트 모델의 차이를 보고한 뒤 멈춘다 | 작업 항목 1∼3; 반박 5 | red를 만들 최소 provider seam의 최종 shape 미결정 |
| D11 | 사용자 | 실제 사용자가 본 권한 부여와 재설치 후 재부여 두 경로가 종결 조건이다 | 지정된 두 기기 절차를 완료의 정의에 고정하고, 결과를 PR 본문으로 승계한다 | 이슈 #34 코멘트 2·4; 반박 6 | 첫 기기 재현의 실행 시점은 D14에서 R1 재현 red 직후 한 번으로 확정 |
| D12 | 드라이버 | clone에서의 worktree ignore/baseRef 점검은 기준 worktree 사실과 섞이면 오해를 만든다 | 이 계획의 두 배치 점검 행은 N/A로 두고, 기준 트리의 shared `info/exclude` 확인은 드라이버 사실로만 기록한다 | 반박 7; 기준 트리 `git check-ignore` 결과 | spark 변형의 실제 checkout 형태가 바뀌면 점검 문구 재검토 |
| D13 | 드라이버 | raw `rg` match와 value-flow inventory를 같은 수치로 쓰면 재현 근거가 흔들린다 | 계획에는 `rg -n "refresh\\(\\)" ... | wc -l` → 23(주석·정의 포함)을 쓰고, 실제 값의 흐름은 전수 표에서 열거한다 | 반박 8; `SetupWindowController.swift`의 raw match 명령 | 주석·정의 제외의 별도 call-site count는 R1에서 필요할 때만 추가 |
| D14 | 사용자 | 기기 재현(`tccutil reset` → 부여 → 창 확인)의 실행 시점은 R1 재현 red 직후 한 번이다 | 테스트 모델이 현실과 어긋났는지를 수정 방향을 고르기 전에 확인하도록, 해당 기기 재현을 R1 red 직후 한 번 실행한다 | 사용자 답변; D11; 완료의 정의 기기 acceptance 1 | red 직후의 실제 TCC 상태와 테스트 red의 모양이 얼마나 대응하는지는 기기 실행에서 확인 |
| D15 | 사용자 | 디스플레이 구성은 Mac Pro + 외장 2대(가로 1, 세로 1)다. 세로 디스플레이는 `visibleFrame.height`가 가로와 크게 다르므로 D8의 화면 선택 분기는 실재 위험이다 | 항목 3의 선행 계약 대조에 `window.screen`·`NSScreen.main`의 다중 디스플레이 선택과 screen별 clamp를 명시한다 | 사용자 답변; 항목 3; D8 | 실제 창이 어느 화면에 속하고 System Settings 왕복 뒤 선택이 어떻게 바뀌는지는 R1/device sweep에서 측정 |
| D16 | 드라이버 | 반박 1이 실측으로 확정됐다. 같은 recipe의 비뒤집힌 `NSStackView` documentView는 짧은 콘텐츠에서 높이 oracle만으로 빈 띠를 통과시킨다 | `swift clipgeom.swift`의 기하를 placement oracle의 실측 근거로 채택한다. 콘텐츠 320pt·창 800pt에서 `stack.frame = (0, 480, 560, 320)`, `clip.bounds = (0, 480, 600, 800)`이 되어 `topAnchor` 제약이 document를 위로 붙이지 않고 clip bounds origin을 옮기며, 뷰포트 위 480pt가 빈다. 콘텐츠 920pt·창 400pt에서는 `stack.frame = (0, -520, …)`, `clip.bounds = (0, 0, 600, 400)`으로 document 상단이 보인다. 따라서 D6의 placement oracle은 실측 근거를 얻었고, 이 기하만으로는 상단 클리핑을 설명할 수 없으므로 D7의 단일 부류 해석과 실제 다중 패스 거동은 R1에서 계속 검증한다 | `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/4ffc53dd-bc2a-45a7-9448-a47a2106d5f6/scratchpad/clipgeom.swift`; `swift clipgeom.swift`; 드라이버 실측; D6·D7 | 스크립트는 run loop 없이 `layoutSubtreeIfNeeded()`로만 정착시켜 실제 앱의 다중 패스 거동은 재현하지 않는다 |
| D17 | 드라이버 | clone의 커밋 identity가 회사 계정으로 나갔다 | 이 clone의 `user.name`·`user.email`을 dazebug로 고정하고 `git reset --soft HEAD~1` 후 새 커밋으로 재발행한다. amend는 사용하지 않는다 | 기존 `858f708` author `tim-watcha <tim@watcha.com>`; 현재 `git config user.email` → `1300067+dazebug@users.noreply.github.com`; 기준 트리 `git config user.email`도 후자; 드라이버가 clone config를 교정함 | 이후 라운드의 커밋 author를 매 승격마다 드라이버가 확인한다 |
| D18 | 드라이버 | 고정 강제 레이아웃 복제에서 높이 equality와 2-pass 수렴은 모든 hidden 전이에서 유지됐지만, 축소 때만 document 위에 빈 띠가 남는다 | D6의 `visible.maxY == document.frame.maxY`를 축소 빈 띠의 placement oracle로 유지한다. `visible.minY == document.frame.minY`는 document가 clip보다 짧거나 같은 경우에만 단언하고, document가 더 긴 scroll 상태에서는 검사하지 않는다. 이 모형에서는 `lastRequestedSize` early return·layout 재진입 발산을 원인으로 채택하지 않는다 | `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/4ffc53dd-bc2a-45a7-9448-a47a2106d5f6/scratchpad/fittedloop.swift`; `swift fittedloop.swift`; 초기 622/622/18pt, hidden 494/494/32pt, visible 622/622/0pt, 반복 전이 동일; settle 2회, 재진입 없음, early return 없음 | run loop 없는 복제이므로 실제 앱의 다중 패스와 권한 전이 경계는 미측정이며, D4·D7 가설은 실제 앱에서 완전히 닫히지 않는다 |
| D19 | 드라이버 | R1 red 확정. Accessibility 허용 전이 뒤 신규 placement oracle이 두 방향으로 실패한다 | 전체 게이트가 exit 1인 의도된 재현 red로 남긴다. denied에서 granted로 줄어든 뒤 clip bounds origin이 32.0에 남은 상태를 항목 4의 production 수정 전제와 항목 5의 기기 검증 입력으로 승격한다 | `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/4ffc53dd-bc2a-45a7-9448-a47a2106d5f6/tasks/b2sapk19c.output`; `swift test --package-path app` exit 1; `XCTAssertEqualWithAccuracy` 두 실패: `779.0`은 `747.0` ±`0.5` (`accessibility-granted: the viewport top extends above the document`), `32.0`은 `0.0` ±`0.5` (`accessibility-granted: the viewport has a blank region below the document`); `SETUP_LAYOUT_SNAPSHOT[accessibility-denied] contentSize=(600.0, 902.0) fittingSize=(600.0, 902.0) rootFrame=(0.0, 0.0, 600.0, 902.0) contentBounds=(0.0, 0.0, 600.0, 902.0) documentVisibleRect=(0.0, 0.0, 600.0, 902.0) rootMaxY=902.0`; `SETUP_LAYOUT_SNAPSHOT[accessibility-granted] contentSize=(600.0, 747.0) fittingSize=(600.0, 747.0) rootFrame=(0.0, 0.0, 600.0, 747.0) contentBounds=(0.0, 32.0, 600.0, 747.0) documentVisibleRect=(0.0, 32.0, 600.0, 747.0) rootMaxY=747.0`; `SETUP_LAYOUT_SNAPSHOT[accessibility-granted-repeat] contentSize=(600.0, 747.0) fittingSize=(600.0, 747.0) rootFrame=(0.0, 0.0, 600.0, 747.0) contentBounds=(0.0, 32.0, 600.0, 747.0) documentVisibleRect=(0.0, 32.0, 600.0, 747.0) rootMaxY=747.0`; `SETUP_LAYOUT_TRACE[accessibility-denied] layoutPasses=1`, `pass=1 fittingHeight=902.0 targetHeight=902.0 lastRequestedHeight=902.0 appliedContentHeight=902.0 requested=false`; `SETUP_LAYOUT_TRACE[accessibility-granted] layoutPasses=1`, `pass=1 fittingHeight=747.0 targetHeight=747.0 lastRequestedHeight=747.0 appliedContentHeight=747.0 requested=true`; `SETUP_LAYOUT_TRACE[accessibility-granted-repeat] layoutPasses=0`; 전체 481 tests / 1 skipped / 2 failures | 테스트 빈 띠 32.0pt가 사용자 실측 250pt·55%와 다른 이유는 D21로 남긴다 |
| D20 | 드라이버 | D4(a) `fittingSize` 조기 측정과 D4(b) `lastRequestedSize` early return, D7의 되먹임 루프가 이 입력의 크기 축 원인이라는 가설 | 이 입력의 크기 축에서는 세 가설을 기각한다. layout은 한 pass이고 재진입이 없으며 `fitting == target == applied == 747.0`, 두 번째 settle은 `layoutPasses=0`이다. 결함 축을 clip bounds origin의 보존으로 좁힌다 | D19 원문 trace; granted snapshot `contentSize=(600.0, 747.0)`, `fittingSize=(600.0, 747.0)`, `contentBounds=(0.0, 32.0, 600.0, 747.0)`, `documentVisibleRect=(0.0, 32.0, 600.0, 747.0)` | 이 결론은 현재 테스트 모델의 크기 축에 한정하며, 실제 기기의 250pt·55% 모양과 화면 선택 분기는 아직 닫히지 않았다 |
| D21 | 드라이버 | 테스트에서 재현된 빈 띠 32pt와 사용자 보고 250pt·창의 55% 사이에 크기 차이가 있다 | 부류는 재현했으나 크기는 재현하지 못했다. 원인과 수치를 항목 5 기기 검증 전까지 열린 상태로 둔다 | D19의 `contentBounds.origin.y=32.0`; 이슈 #34 코멘트 1의 사용자 실측 약 55% 빈 영역·코멘트 본문의 약 250pt | 다중 디스플레이 화면 선택, 실제 창 크기, run loop와 설치·권한 왕복이 차이를 만드는지는 기기 acceptance에서 확인한다 |
| D22 | 드라이버 | 테스트가 헤더를 찾기 위해 production `NSView` 확장의 가시성을 넓히는 것은 불필요한 경계 변경이다 | `private extension NSView`를 유지하고 `card.header`는 `rootStack.arrangedSubviews`에서 직접 찾는다. 자손 탐색을 공유 API로 만들지 않는다 | `SetupWindowController.swift:1502`; `buildContent()`의 카드 목록에서 `card.header`가 root stack의 직접 arranged subview임; R1 리뷰 1 지적 | 헤더 식별자와 arranged-subview 순서는 현재 `buildContent()` 계약에 의존하며 이번 배정에서 변경하지 않는다 |

## 전수 소탕 표

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| 초기 `SetupWindowController` 생성: `buildContent()`의 guide·install feedback·test result 기본 hidden → `updateTerminalControls()` → 첫 `refresh()` → `layoutSubtreeIfNeeded()` | 계획 대상(항목 2) | `SetupWindowController.swift:191∼226`, `467∼485`, `727∼745`; 첫 측정은 hidden state·status wrapping·screen clamp가 모두 섞인다. |
| `manifest` → `chromeCard.isHidden` | 계획 대상(항목 2) | `SetupWindowController.swift:991∼1002`; manifest 완료/미완료가 card height를 바꾸므로 window height와 함께 settle되어야 한다. |
| `lastRequestAt`·extension state → `extensionCard.isHidden`, `utilityRow.isHidden` | 계획 대상(항목 2·3) | `SetupWindowController.swift:1004∼1015`; socket evidence가 card를 줄이고 utility row를 되살리는 양방향이다. |
| `Settings.toolAvailability == nil` 또는 missing tools/wrapper advice → `toolsCard.isHidden`와 `toolsList` 재구성 | 계획 대상(항목 2) | `SetupWindowController.swift:1117∼1141`; list removal/addition은 hidden 토글이 아니라도 intrinsic height를 바꾼다. |
| `Settings.terminal`과 iTerm automation 상태 → `permissionSection.isHidden` | 계획 대상(항목 2) | `SetupWindowController.swift:1029∼1050`; `select(terminal:)`의 iterm↔wezterm↔warp가 section을 늘리고 줄인다. |
| `PermissionChecker.isAccessibilityGranted` → `accessibilitySection.isHidden` | 재현 seam 필요(항목 1·2) | `SetupWindowController.swift:1025`, `1051`; `PermissionChecker.swift:49∼61`은 실제 TCC를 직접 읽어 false→true 전이를 현재 테스트가 만들 수 없다. |
| `select(terminal:)` → radio/note text → `refresh()` | 계획 대상(항목 2) | `SetupWindowController.swift:949∼974`; terminal card의 text와 permission section이 동시에 변하므로 status label wrap과 hidden layout을 함께 본다. |
| `windowDidBecomeKey` → `refresh()`; System Settings에서 돌아온 Accessibility 상태의 실제 관측 지점 | 재현 핵심(항목 1·2·4) | `SetupWindowController.swift:235∼237`, `1348∼1354`; Accessibility 요청 자체에는 completion callback이 없고, key 복귀가 상태 재조회 경계다. |
| `.terminalCheckoutRequestHandled` → extension evidence/card, `.terminalCheckoutToolsChecked` → tools card | 계획 대상(항목 2) | observer는 `SetupWindowController.swift:216∼222`, 발생원은 `Settings.swift:67∼71`, `96∼107`; 두 알림 모두 창 생성 뒤 비동기로 도착한다. |
| `languageChanged` → Settings notification·explicit `refresh()` → `rebuildForLanguageChange()` | 보존 필수(항목 3) | `SetupWindowController.swift:581∼585`, `272∼283`; `capturePlace`와 `restore`가 status reflow 뒤에 실행되어야 하고 ordinary refresh와 중복 재생성하지 않아야 한다. |
| `registerManifest`, `installInChrome`, `reshowInstall` → guide/feedback hidden 변경 및 `refresh()` | 계획 대상(항목 2) | `SetupWindowController.swift:1235∼1264`, `1320∼1328`; 직접 label visibility를 바꾼 직후 refresh가 다시 상태를 덮는다. |
| `baseDirectoryEdited` → invalid status label text 또는 valid `refresh()` | 계획 대상(항목 2) | `SetupWindowController.swift:1278∼1300`; invalid path는 refresh 없이 wrapping label만 바꾸므로 Fitted stack이 text intrinsic change도 잡아야 한다. |
| `requestPermission` completion → permission status·`refresh()` | 계획 대상(항목 2) | `SetupWindowController.swift:1330∼1341`; iTerm callback은 Accessibility와 다른 비동기 경로지만 permissionSection의 크기 변화를 공유한다. |
| `requestAccessibility()` 즉시 `refresh()`와 key 복귀 refresh | 재현 핵심(항목 1·2) | `SetupWindowController.swift:1348∼1354`; prompt 호출 시 grant가 확정되지 않으므로 즉시 refresh는 old state일 수 있고, 실제 전이는 다음 key 이벤트에서 온다. |
| `testTerminal` 시작/완료 → `testResultLabel.isHidden`·status text·`refresh()` | 계획 대상(항목 2) | `SetupWindowController.swift:1360∼1382`; async 완료가 label을 보이게 하고 text를 바꾸므로 권한 경로와 무관한 intrinsic-size 회귀도 같은 oracle로 닫는다. |
| `windowWillClose` → guide/feedback/test result hidden | 안전(닫히는 창) | `SetupWindowController.swift:240∼247`; 창을 닫는 중이라 크기 oracle 대상은 아니지만, 다음 open에서 `forceShowInstall`과 hidden 초기값이 첫 측정을 오염시키지 않는지 확인한다. |
| `visibleFrameOverride` 대입 → stack layout 예약 | 보존 필수 | `SetupWindowController.swift:39∼45`; `SetupWindowLayoutTests.swift:64∼74`, `180∼201`; setter가 plain stored property가 되면 test display가 inert해진다(D322·D323). |
| `visibleFrameOverride ?? window.screen ?? NSScreen.main` → clamp height와 `moveInside` | 미검증 분기(항목 3·5) | `SetupWindowController.swift:50∼56`; 현재 모든 자동 테스트가 override를 사용해 `window.screen`·`NSScreen.main`을 지나지 않는다. System Settings 왕복·다중 디스플레이에서 어느 화면을 선택하는지 driver가 확인해야 한다. |
| `settle(_:)` 한 번 호출 → 실제 `layout()` 재진입 고정점 | R1 재현·계측(항목 2) | `SetupWindowLayoutTests.swift:56∼58`; `SetupWindowRedrawTests.swift:62∼75`; pass 수·fittingSize·target·window/document frame·documentVisibleRect·scroll origin을 N회까지 기록하고, 무수렴은 red로 남긴다. |
| `8fccab5`의 visibility→settle→measure·clamp·scroll 계약 → 권한 text/hidden 전이 | 선행 계약 공백 대조(항목 3) | `git show 8fccab5`; 이번 입력은 `select(terminal:)`가 아니라 `windowDidBecomeKey` 뒤 `refresh()`이며, upper-height·placement·convergence·override 밖 화면 선택이 당시 테스트에 포함됐는지는 먼저 대조한다. |
| `lastRequestedSize` early return과 `FittedContentStackView.layout()`의 measurement boundary | 원인 미확정(항목 2) | `SetupWindowController.swift:47∼56`; `super.layout()` 뒤의 fitting value가 실제 정착값인지와 동일 target 반환이 새 window size를 합법적으로 건너뛰는지는 동적 red가 필요하다. |
| `capturePlace`/`restore`의 비뒤집힌 document top 및 hidden anchor fallback | 보존 필수(항목 3) | `SetupWindowController.swift:299∼371`; `SetupWindowRedrawTests.swift:224∼338`; 짧은 document의 빈 띠와 긴 document의 상단 클리핑이 restore 자체의 실패인지 높이 mismatch의 결과인지 분리해야 한다. |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — 계획 초안 · 리뷰 드라이버 직접 · 왕복 1 · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/4ffc53dd-bc2a-45a7-9448-a47a2106d5f6/scratchpad/R0-review1.md`

- 반박: ① acceptance oracle이 높이만 봐서 보고된 배치 증상을 재현하지 못한다 ② `layout()` 안의 `setContentSize` 재진입에 대한 수렴 oracle이 없고 `settle`이 `layoutSubtreeIfNeeded()`를 한 번만 부른다 ③ 화면 선택 분기가 seam 밖이라 어떤 테스트도 지나지 않는다 ④ 선행 수정 `8fccab5`가 왜 못 막았는지를 규명하는 항목이 없다 ⑤ 재현 red 전에 수정 항목이 배정되는 순서다 ⑥ 완료의 정의에 사용자가 본 화면(기기 절차)이 고정돼 있지 않다 ⑦ 배치 점검 표가 clone 기준이라 오해를 만들고 커밋 링크 해시가 39자로 깨졌다 ⑧ `refresh()` 수치가 세는 명령 없이 적혀 실측(23)과 다르다
- 처리: 전부 반영 — 항목을 재현(1∼3) → 수정(4) → 기기(5) 순서로 재편, 배치·수렴 oracle 추가, 화면 분기와 `8fccab5` 대조를 항목 3으로 신설, 기기 절차 2건을 완료의 정의에 고정 (D6∼D13). 기각 없음
- 실측: 드라이버 baseline `swift test --package-path app` → 481 tests / 1 skipped / 0 failures / exit 0, `node --test` → 216 pass / 0 fail (기준 트리 `a13fa48`). 반박 1의 기하학은 `clipgeom.swift` 실측으로 확정 (D16). 구현자 샌드박스에서는 게이트가 중첩 `sandbox-exec`로 돌지 않는다 — 앞으로 게이트는 드라이버가 clone에서 돌린다 (D5)
- 판정: "이 계획으로 시작하는 데 합의한다. 단 R1 첫 배정은 항목 1∼3의 재현·계측뿐이고, 항목 4의 수정 배정은 red를 본 뒤에만 나간다."

### R1

#### 리뷰 1 — 증분 · R1 재현 커밋 · 리뷰 드라이버 직접 · 왕복 2 · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/4ffc53dd-bc2a-45a7-9448-a47a2106d5f6/scratchpad/R1-fix1.md`

- 차단: 1차 제출이 컴파일되지 않았다 — `String(CGFloat)` 이니셜라이저 없음, `firstDescendant(role:)`가 다른 테스트 파일의 `fileprivate`. 그리고 `FittedContentLayoutPass`가 `FittedContentStackView`의 설계 주석과 클래스 선언 사이에 들어가 `8fccab5`의 근거 원문이 엉뚱한 타입의 문서가 됐다
- 수정: 컴파일 에러 2건, 주석 재부착 원복, `visible.minY` 단언에 "콘텐츠가 뷰포트에 들어올 때만" 전제 게이트, production 가시성 확대 원복 (D22)
- 실측: 전체 게이트 exit 1 — 481 tests / 1 skipped / 2 failures, 둘 다 신규 케이스. 빈 띠 32.0pt, 드라이버 독립 복제 `fittedloop.swift`의 32.0과 일치
- 판정: 재현 확인. D4(a)(b)·D7 크기 축 기각, 결함 축은 clip bounds origin (D19·D20). 크기 차이는 미해명으로 남긴다 (D21)

## 열린 질문

- 항목 1의 provider seam을 `PermissionChecker`의 closure로 둘지 별도 상태 함수로 둘지, 실제 TCC 호출을 production default로 보존하는 최종 이름은 무엇인가.
- 항목 1 seam을 연결한 뒤 현재 tree에서 false→true test가 실제로 red가 되는가. red가 되지 않으면 `FittedContentStackView.layout()`의 pass 경계를 관찰할 수 있는 최소한의 test-only instrumentation seam이 추가로 필요하다.
- red가 발생할 때 최초 원인이 (a) `fittingSize`가 nested wrap/hidden 정착 전 값인 경우, (b) 같은 target의 `lastRequestedSize` early return인 경우, (c) non-flipped clip의 document placement인 경우 중 어느 것인가. 세 경우의 수정과 테스트 범위가 다르므로 실측 전에는 결정하지 않는다.
- 권한 provider 전이와 실제 System Settings 복귀가 동일한 `windowDidBecomeKey` 경계를 통과하는지, 재설치 후 cdhash reset이 완료되기 전의 중간 상태가 별도 수동 시나리오를 요구하는지는 기기 acceptance에서 확인해야 한다.
