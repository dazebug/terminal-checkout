# setup-window

- 절차 정본: `drive-agent-loop` 스킬과 이 계획 파일
- 대상: `app/Sources/App/` 의 macOS 설정 창
- 시작 커밋: `416ce06`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/setup-window-review` (`worktree-setup-window-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-setup-window-work` (`setup-window-work`)
- 현재: R0 승인 · 마지막 승격 없음 · 리뷰 중 없음 · 게이트: node green, Swift 기준선 green(416ce06)
- 최근 검증자 판정: R0 계획 승인 · 반박 전부 반영 · 2026-10-03

이 파일은 실행한 계획과 실행할 계획의 기록이다. R0 설계 계획이 승인되었으며 앱·확장 코드 변경은 없다.

## 배경 — 확인한 원천

- [CLAUDE.md](../../CLAUDE.md) — TCC 실행 경계, 요청 기록의 의미, cmux·Warp 상태 해석, 설정 소유권, AppKit 테스트 규칙, 도구 검사 계약.
- [setup-window-placement.md](../context/setup-window-placement.md) — 다음 main-queue turn에서 창 크기를 적용하는 이유와 화면 중심·클램프·언어 재구축 계약.
- [localization.md](../context/localization.md) — 다섯 앱 카탈로그와 로케일 변경 뒤 재시작이 필요한 AppKit 언어 경계.
- [cmux-integration.md](../context/cmux-integration.md) — cmux socket control mode 거부는 실행 중이 아닌 상태가 아니며 `automation` 외 `password`·`allowAll`도 통과한다는 근거와 그룹 배치 결과 계약.
- [tab-activation.md](../context/tab-activation.md) — 배경 탭 선택의 터미널별 동작과 Warp에서 선택을 저장하면서 비활성화하는 이유.
- [slack-thread-shortcut.md](../context/slack-thread-shortcut.md) — Slack 요청 입력 경계, 단축키, Slack MCP, 실패 처리와 로그인 항목의 소유.
- [signing-and-permissions.md](../context/signing-and-permissions.md) — 재설치 뒤 Warp 손쉬운 사용 권한이 다시 필요할 수 있는 조건.
- [testing.md](../context/testing.md) — AppKit 고정점 settle, 강제 layout 금지, 테스트 창을 닫지 않는 규칙과 직렬 실행 근거.
- [README.md](../../README.md) — 사용자 안내의 정본, 현재 설정 창 문구를 인용하는 설치·문제 해결 절.
- [docs/new-terminal-checklist.md](../new-terminal-checklist.md) — 새 터미널 검증에서 현재 설정 창 라디오·파이프라인 설명·버튼 이름을 참조하는 지점.
- [Apple `NSWindow.ToolbarStyle`](https://developer.apple.com/documentation/appkit/nswindow/toolbarstyle-swift.enum?changes=_6) — `.preference` 가 설정 창에 쓰는 기본 툴바 형식이라는 API 설명.
- [Apple `NSToolbarItemGroup.SelectionMode`](https://developer.apple.com/documentation/appkit/nstoolbaritemgroup/selectionmode-swift.enum) — 툴바 항목 중 하나만 선택하는 모드를 제공한다는 API 설명.

## 목표

설정 창을 720pt 폭의 General · GitHub · Slack 툴바형 창으로 바꾸고 선택된 한 항목의 내용에 맞춰 높이를 재측정한다. 각 항목은 동작 결과를 설명하는 접근성 설명을 가진 그림과 관련 설정을 보여 준다. 평소에는 설명 카드를 감추고 오류·경고 또는 창을 연 사유가 있을 때 원인·조치·영향·동작을 상단 공통 영역에 순서대로 표시한다. 다섯 앱 로케일, 저장값 보존, 기존 터미널·TCC·요청 기록 계약을 함께 검증하고 README와 설치 문서의 인용 문구를 갱신한다.

## 완료의 정의

- 반드시 재현해 막아야 끝인 실패: Warp의 claude 입력 거절 또는 Slack 요청 실패로 창이 열렸는데 원인이 사라져 일반 안내만 보이거나, cmux socket 거부가 “실행 중 아님”으로 표시되거나, 확장 요청 기록이 명령 성공으로 오해되는 입력에서 오해를 바로잡는 문제 블록이 없으면 실패다.
- acceptance oracle: 새 순수 모델 테스트에서 문제 순서와 Core 실효 배치 결과를 고정하고, AppKit 테스트는 다섯 로케일·세 항목·높이 전환·공통 상단 영역·언어 재구축의 불변식을 고정한다. 드라이버가 `cd app && swift test` 를 직렬 실행하고, `node --test` 및 `node tools/check-locales.js` 의 종료 코드와 실행 수를 기록한다. AppKit 레이아웃은 shared `settle` 의 run-loop 고정점으로만 확인하고 장치에서 툴바의 최종 프레임·화면 클램프를 확인한다.
- 코퍼스 범위: 실코퍼스는 해당 없음 — 제품 동작 행렬은 `supportedLocales` 의 다섯 앱 카탈로그와 목업에서 합의된 상태(처음 설치, 기록된 요청, cmux 거부, Warp 거절 사유, 도구 부족, 잘못된 저장소 폴더, Slack 실패, 재시작 막힘·실패, 그룹 배치 선택)로 고정한다.
- 원자성·부분 실패·롤백 경계: 새 다중 쓰기나 설치 프로토콜은 없다. 폼 입력은 기존 설정 소유자와 저장 시점을 유지하고, 창 재구축·상태 갱신은 테스트 터미널 실행·설치·재시작을 재실행하지 않는다. 마지막 요청 시각은 표시·안내 닫기에서 지우지 않는다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

- 사용자: 터미널 설치·삭제, TCC 권한 변경, 설정 편집, 언어 변경, 가이드 열기, Slack 단축키 지정, 창을 연 채 터미널·프로세스 상태를 변경한다.
- Chrome 확장과 Native Host: 프레임을 전달하거나 전달하지 않는다. 호스트는 프레임을 파싱하기 전에 요청 기록을 남길 수 있다.
- 앱 소켓·선택한 터미널·cmux: 연결 가능, 거부, 미실행, 미설치, 확인 실패를 각각 보고한다. cmux가 거부를 반환해도 설정 창에서 실행 여부를 추론할 수 없다.
- 로그인 셸 도구 검사와 설치 상태 조회: `gh`, `claude`, `zoxide` 및 실행 가능 여부가 창 생성 뒤 비동기로 달라질 수 있다.
- Slack 단축키 요청·로그인 항목: 요청이 실패하거나 등록 상태가 승인 대기·실패로 바뀌어 Slack 항목의 문제 표시를 바꾼다.
- 언어 재구축 알림과 AppKit: 새 로케일 문자열은 즉시 그릴 수 있지만 AppKit이 읽는 시스템 UI 언어는 재시작까지 바뀌지 않는다.

## 비목표 — 건드리지 않는다

- `extension/` 의 버튼 옵션·페이지 분류·저장·마이그레이션은 범위 밖이다. 확장 변경은 앱 아이콘 파생 PNG와 manifest 아이콘 필드만 다루며 manifest `key` 와 확장 ID를 유지한다.
- `Core/` 의 명령 렌더링·터미널 실행·cmux 배치 해석·Claude 입력 전달: 새 그림과 적용 문장은 기존 Core 결과를 읽는다.
- Native Host 프로토콜·Chrome 설치 ID·요청 기록 시점·앱 소켓 처리: 준비된 확장 폴더와 요청 도착을 같은 상태로 합치지 않는다.
- TCC 요청·권한 부여·코드 서명·Warp helper 신뢰 경계·cmux 설정 파일 쓰기: 설정 창은 기존 액션을 호출하고 상태를 표시한다.
- `Settings` 의 소유권·기본값·기존 키 의미: 저장소 기본 폴더와 Slack 입력은 앱 로컬이고, 확장 버튼은 `storage.sync` 의 소유다.
- 이슈·PR 생성 및 `docs/context/` 의 기존 판단 재서술: 이미 코드나 정본 문서에서 알 수 있는 구조·절차는 복제하지 않는다.

## 불변 원칙

TCC 실행 경계는 Chrome → relay(전달만) → 앱(검증·실행)으로 유지한다. 화면에 보이는 “확장 요청을 받았습니다”는 호스트에 프레임이 도착했다는 기록일 뿐, 파싱·명령 실행 성공을 뜻하지 않는다. 문제 없는 상태를 “정상”이라고 이름 붙이지 않는다. cmux 상태는 `PermissionChecker` 가 반환한 typed status로 표시하고 설정 파일을 읽어 상태를 추론하지 않는다. 접근 거부는 즉시 별도 오류로 보이며 “cmux가 실행 중이 아님”으로 바꾸지 않고, `automation`은 권장일 뿐 `password`·`allowAll`도 유효하다. 도구 상태는 기존 로그인 셸 `-i` 검사를 사용한다. Warp 손쉬운 사용 권한은 타이핑이 필요한 Claude 입력에만 적용한다. 프리셋 개수는 문구에 넣지 않는다. 확장 manifest의 `key` 와 그로부터 정해지는 Chrome 확장 ID는 바꾸지 않는다.

문제 판정·순서와 그림 입력은 AppKit 밖에서 테스트할 수 있는 값 모델로 둔다. 모든 창 열기 사유는 각각 문제 블록 하나로 만들고 도착 순서만 모델 입력으로 전달한다. 그림은 새 `NSView` 의 `draw(_:)` 와 레이어 배경으로 그리는 정적 벡터다. 터미널, 실행 후 화면, 배치 단위, identity, workspace 이름에서 순수 함수로 `SetupWindowPreviewModel` 을 만들고, cmux 값은 Core의 `CmuxPlacementPreset.parse`·`effectiveIdentityMode` 가 해석한 실효 결과를 읽는다. 모델 테스트는 named workspace의 원래 pane/tab 보존 및 workspace-per-item에서 identity가 always-new가 되는 결과를 Core와 대조한다. 그림에는 VoiceOver 설명 또는 동등한 텍스트 설명을 둔다.

macOS 설정 창처럼 보여야 한다는 요구에는 아이콘과 현지화된 이름을 같이 표시하는 `NSToolbar` 와 `NSWindow.ToolbarStyle.preference` 의 `NSToolbarItemGroup.SelectionMode.selectOne` 그룹을 쓴다. 창은 `.fullSizeContentView` 와 투명 타이틀바를 버리고 보통의 타이틀 있는 창을 쓰며 제목은 현재 항목 이름이다. 콘텐츠는 툴바 아래에서 시작하므로 기존 38pt 위 여백과 자동 inset 비활성화는 새 콘텐츠 영역에 맞춰 다시 정한다. 툴바는 `FittedContentStackView` 의 문서 높이에 포함하지 않고, 선택 항목 하나의 pane만 측정해 창 높이를 갱신한다. `NSWindow` 프레임 폭은 720pt로 고정하고 화면 선택·가운데 배치·화면 경계 클램프는 동일한 가시 영역 기준을 쓴다. placeholder와 첫 measured size만 가운데 배치하고, 이후 pane 크기 변경은 재중앙 배치하지 않고 같은 visible rect 안으로만 되돌린다. 언어 재구축은 창 수명 동안의 첫 측정 여부를 초기화하지 않는다. #34의 지연 크기 적용과 한 레이아웃 주기당 한 화면 결정은 유지한다.

일반 항목 맨 위에 앱 아이콘(32∼36pt)·“Terminal Checkout”·`CFBundleShortVersionString` 을 한 줄로 보이고 버전의 기존 하단 표시는 없앤다. General 툴바 항목은 톱니 대신 `NSApp.applicationIconImage`, GitHub·Slack은 SF Symbols를 쓴다. 그림의 프롬프트 글리프는 아이콘 초록과 가장 가까운 후보인 `Theme.ok` 를 실제 아이콘 색과 비교해 최종 하나로 정한다. 언어 변경 재구축은 `SetupWindowPlace` 에 저장한 선택 pane identifier, 현재 포커스의 action-derived role, UTF-16 선택 범위, 해당 pane 스크롤 기준점, 편집 초안과 컨트롤러 소유 `LanguageNoteState` 의 변경·막힘·실패 상태를 보존한다. 재시작 안내는 사용자가 언어를 바꾼 뒤에만 나타난다. 선택 pane은 UserDefaults에 저장하지 않는다. 역할은 액션 선택자에서 파생하며 배열 인덱스를 식별자로 쓰지 않는다. 라디오가 팝업·세그먼트로 바뀌어 역할이 달라지는 컨트롤은 테스트에서 의도적으로 갱신하고, 같은 액션 선택자를 쓰는 컨트롤 둘은 번역되지 않는 qualifier로 구분한다.

`refresh()` 는 창 활성화와 소켓 요청마다 상태를 갱신한다. 새 구조에서도 갱신은 상태·보임만 바꾸고 뷰를 다시 만들지 않는다. 저장소 폴더·workspace 이름·Slack 입력의 초안 보존은 기존 `drawn…` 추적 의미 그대로 유지한다. 다시 만들기는 포커스와 사용자가 편집 중인 초안을 빼앗으므로 3∼6번 테스트가 갱신과 초안 보존을 고정한다.

레이아웃은 AppKit이 돌린다. `SetupWindowTestSupport.settle` 에서 `layoutSubtreeIfNeeded()` 를 호출하지 않고, 테스트에서 `NSWindow` 를 닫지 않으며, AppKit 테스트 게이트는 한 번에 하나만 실행한다. 기본 창 크기는 placeholder일 수 있으므로 다음 main-queue 턴 이후 고정점에서 측정하고, 창 크기·클립·문서 높이·화면 배치를 각각 확인한다. 구현 테스트는 새 실패 케이스를 먼저 추가해 red를 확인한 뒤 구현해 green을 확인한다.

계획 번호와 결정 원장 식별자는 코드·주석·커밋 본문에 넣지 않는다. 아래 작업은 각각 한 번의 승격을 목표로 한다. `SetupWindowController.swift` 는 5번에서 기존 Slack 녹화 UI·상태 처리를 옮길 때 한 번, 6번에서 root composition을 교체할 때 다시 편집한다. 다른 pane은 새 파일에서 독립 구현·검증하고, 각 승격은 빌드와 해당 테스트가 green인 상태로 끝난다.

## 배치 점검 (0라운드)

모드: ultrafast

드라이버가 확인한 시작 환경과 게이트 기준선을 적었다.

| 점검 | 결과 |
|:--|:--|
| `.claude/worktrees/` 무시 | 메인 리포 기준 `.git/info/exclude` 에서 ignored. clone의 exit 1은 clone exclude 기본값 때문이며 이 루프와 무관 |
| `worktree.baseRef` | 해당 없음 — ultrafast 모드는 전용 clone 사용 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-setup-window-work` · `setup-window-work` · `416ce06` |
| 리포 오버레이 `.claude/drive-agent-loop.md` | 커밋된 파일을 그대로 사용; 기준 트리와 clone 내용이 동일 |
| cmux 패널 | surface:664 · pane:555 (드라이버가 6177731 승격 뒤 열었다) |
| 트리마다 의존성 동기화 (기준·작업) | Swift 기준선 `416ce06`: 드라이버가 clone에서 `cd app && swift test` 실행, exit 0; CoreTests 560 실행(1 skipped), AppTests 155 실행, 실패 0. Node `node --test`: exit 0, 324/324; `node tools/check-locales.js`: exit 0 |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) | 없음 |
| 증분 리뷰 소요(분) — 첫 세 번 | 미실시 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | 문제·입구 사유·그림을 AppKit 없이 계산하는 순수 프레젠테이션 모델을 만든다 | 순수 상태·미리보기 모델 | `ClaudeInputGuidance.present` 가 `.warpAccessibility` 와 `.warpHelperUnavailable` 을 버리고 현재 시각 창 열기만 한다; 배치 미리보기는 별도 검증 가능한 결과값이 없다 | `app/Sources/App/SetupWindowPresentation.swift` (신규); `app/Tests/AppTests/SetupWindowPresentationTests.swift` (신규) | — | claimed | `cd /Users/choongjaelee/Codes/terminal-checkout-setup-window-work/app && CLANG_MODULE_CACHE_PATH=/Users/choongjaelee/Codes/terminal-checkout-setup-window-work/.git/tc-clang-cache swift build --build-tests --disable-sandbox --scratch-path /Users/choongjaelee/Codes/terminal-checkout-setup-window-work/.git/tc-swift-build --cache-path /Users/choongjaelee/Codes/terminal-checkout-setup-window-work/.git/tc-swift-cache --config-path /Users/choongjaelee/Codes/terminal-checkout-setup-window-work/.git/tc-swift-config --security-path /Users/choongjaelee/Codes/terminal-checkout-setup-window-work/.git/tc-swift-security` → exit 0, `Build complete! (14.81초)`; 새 테스트 15개: `testOpeningReasonsComeFirstAndNewestReasonComesFirst`, `testResolvedClaudeOpeningReasonIsRemoved`, `testErrorsPrecedeWarningsAfterOpeningReasons`, `testCmuxAccessDeniedAndNotRunningRemainDifferentProblems`, `testMissingExtensionFolderIsAProblemOnlyAfterARequestWasRecorded`, `testFirstInstallChecklistDependsOnRequestEvidenceOrReopenAction`, `testZoxideIsCriticalOnlyWithoutConfiguredBaseDirectory`, `testWorkspacePerItemIgnoresStoredNamedWorkspaceIdentity`, `testNamedWorkspaceWithEmptyNameUsesNewWorkspace`, `testNamedWorkspacePreviewPreservesTheExistingPaneAndTab`, `testWarpKeepsTheTerminalInFrontEvenWhenStoredChoiceIsBackground`, `testNonCmuxGitHubPreviewUsesOneNewTabPerExampleRow`, `testSlackPreviewUsesSymbolicFolderAndSlackLinkThenInstruction`, `testSuccessfulSlackRequestClearsOpeningFailureAndToolbarDot`, `testClaudeExecutableWarningIdentifiesSlackImpact` | — |
| 2 | 툴바 아래 공통 문제·설치 안내 패널을 독립 뷰로 만든다. 문제는 제목·원인/고치는 법·영향·동작 버튼을 상태 점으로 표시하고, 창 연 이유·오류·경고 순으로 배치한다. 처음 설치 checklist는 Native Host·Chrome 설치·첫 GitHub 요청이고, 설치 버튼 뒤 네 단계 안내를 펼치며 재방문은 [안내 닫기]로 닫는다. 마지막 요청 기록은 지우지 않고 요청 뒤 확장 폴더가 사라진 경우도 문제로 표시한다. 이 pane의 새 문자열 키만 다섯 로케일에 추가하고 기존 키는 건드리지 않는다; en·ko는 목업 문구, ja·zh-Hans·zh-Hant는 번역한다 | 공통 안내 뷰 | 기존 안내는 카드·파이프라인에 붙어 선택 pane 위 공통 영역으로 렌더되지 않는다 | `app/Sources/App/SetupWindowSharedPanel.swift` (신규); `app/Tests/AppTests/SetupWindowSharedPanelTests.swift` (신규); `app/Sources/App/Resources/{en,ko,ja,zh-Hans,zh-Hant}.lproj/Localizable.strings`; `app/Tests/AppTests/LocalizationCatalogTests.swift`, `app/Tests/AppTests/CatalogueOwnershipTests.swift` | 1 | todo | `rg -n -e 'func buildContent' -e 'manifestState' -e 'extensionState' app/Sources/App/SetupWindowController.swift app/Sources/App/Installer.swift` → `buildContent:674`, `manifestState:87`, `extensionState:172` | — |
| 3 | General pane을 만든다: 앱 아이콘(32∼36pt)·“Terminal Checkout”·번들 버전을 한 줄로 두고 그 아래 상태 줄, 연결 상세, 다섯 터미널 팝업과 미설치 비활성 상태, 터미널 테스트, 실행 후 화면 세그먼트 [터미널로 이동 \| 지금 화면 유지], 힌트, 언어, GitHub 버튼 편집, 안내 다시 보기와 적용 그림을 둔다. Warp에서는 세그먼트를 비활성화하고 이동 상태를 보이며 저장값을 보존하고, 터미널을 바꾸면 해당 터미널의 저장 선택을 복원한다. 언어 변경 뒤에만 재시작 안내를 보이고 막힘·실패 안내를 보존하며, GitHub 편집 진입점은 요청 기록 뒤에만 연다. General 툴바 항목은 `NSApp.applicationIconImage`, GitHub·Slack 항목은 SF Symbols를 쓴다. 그림 글리프는 아이콘 초록과 가장 가까운 후보인 `Theme.ok` 를 실측 비교해 하나로 정한다. 이 pane의 새 키만 다섯 로케일에 추가하고 기존 키는 건드리지 않는다; en·ko는 목업 문구, ja·zh-Hans·zh-Hant는 번역한다 | General pane | 현재 설정은 일반·연결·도구 카드로 흩어져 있고 버튼명이 목표와 다르다. 버전은 새 헤더가 아닌 하단 보조 정보에 놓여 있다 | `app/Sources/App/SetupWindowGeneralPane.swift` (신규); `app/Tests/AppTests/SetupWindowGeneralPaneTests.swift` (신규); `app/Sources/App/Resources/{en,ko,ja,zh-Hans,zh-Hant}.lproj/Localizable.strings`; `app/Tests/AppTests/LocalizationCatalogTests.swift`, `app/Tests/AppTests/CatalogueOwnershipTests.swift` | 1 | todo | `rg -n -e 'app.terminal.openInBackground' -e 'app.button.runInTerminal' -e 'app.button.openOptionsPage' -e 'CFBundleShortVersionString' app/Sources/App/SetupWindowController.swift` → `1034`, `1235`, `1250`, version lookup | — |
| 4 | GitHub pane을 만든다: 기본 폴더 입력·폴더 선택, “PR·이슈 목록에서 여러 개를 실행할 때” 섹션, cmux의 pane/tab/workspace와 새로 만들기·이름 찾기, workspace 단위에서 identity 비활성화 및 저장값 보존, Core 결과 문장과 세 행 미리보기를 둔다. 기본 폴더 상태는 입력·저장값 오류, 아직 없는 폴더, 값과 zoxide가 모두 없는 경우에만 보인다. 도움말 문단·저장소 탐색 순서·이전 버전 버튼 안내는 두지 않고, 비-cmux 문장은 행마다 새 탭으로 표현한다. 자기 pane의 새 문자열 키만 다섯 로케일에 추가하고 기존 키는 건드리지 않는다; en·ko는 목업 문구, ja·zh-Hans·zh-Hant는 번역한다 | GitHub pane | 기본 폴더는 정상일 때도 긴 도움말·이전 버튼 안내를 표시하고, cmux 배치 UI는 현재 세로 카드다 | `app/Sources/App/SetupWindowGitHubPane.swift` (신규); `app/Tests/AppTests/SetupWindowGitHubPaneTests.swift` (신규); 기존 `app/Tests/AppTests/CmuxPlacementSetupTests.swift` 갱신; `app/Sources/App/Resources/{en,ko,ja,zh-Hans,zh-Hant}.lproj/Localizable.strings`; `app/Tests/AppTests/LocalizationCatalogTests.swift`, `app/Tests/AppTests/CatalogueOwnershipTests.swift` | 1 | todo | `rg -n -e 'app.card.baseDir.help' -e 'legacyNote' -e 'cmuxPlacementArrangement' app/Sources/App/SetupWindowController.swift` → `baseDir.help:825`, `legacyNote:834`, `arrangement:1169` | — |
| 5 | Slack pane에 작업 폴더·검증되는 Claude 지시문·단축키 녹화/지우기·수식키 필요 경고·등록 실패·로그인할 때 앱 열기와 상태·“단축키는 앱이 실행 중일 때만 동작합니다.” 힌트·그림을 둔다. Slack 요청 실패는 공통 문제 영역에 두고 Slack 툴바 항목에 빨간 점을 보인다. 그림은 해당 폴더에서 `claude '<Slack 링크> <지시문>'` 을 실행하고 Slack MCP가 필요하다고 설명한다. PR #107의 녹화 UI와 상태 처리를 새로 만들지 않고 `SetupWindowController.swift` 에서 옮긴다. `SlackThreadHotKey.swift` 와 `LoginItem.swift` 는 바꾸지 않고, 현재 UI와 설정 검증은 `validateSlackThreadSettings` 같은 한 함수를 공유한다. 문자열은 자기 pane의 새 키만 다섯 로케일에 추가하고 기존 키는 건드리지 않는다; en·ko는 목업 문구, ja·zh-Hans·zh-Hant는 번역한다 | Slack pane | Slack 실패는 현재 Slack 카드 아래 인라인 상태이고 공통 문제 순서와 툴바 표시가 없다. #107 녹화·로그인 UI는 컨트롤러에 있다 | `app/Sources/App/SetupWindowSlackPane.swift` (신규), `app/Sources/App/SetupWindowController.swift` (기존 녹화 UI·상태 처리 이동); `app/Tests/AppTests/SetupWindowSlackPaneTests.swift` (신규), `app/Tests/AppTests/SlackThreadSettingsTests.swift` 갱신; `app/Sources/App/Resources/{en,ko,ja,zh-Hans,zh-Hant}.lproj/Localizable.strings`; `app/Tests/AppTests/LocalizationCatalogTests.swift`, `app/Tests/AppTests/CatalogueOwnershipTests.swift` | 1 | todo | `rg -n -e 'app.card.slack.title' -e 'presentSlackThreadRequestFailure' -e 'slackRequestFailure' app/Sources/App/SetupWindowController.swift` → `card:882`, `failure label:273`, `present:1852` | — |
| 6 | pane을 preference `NSToolbar` 로 조립하고 720pt 폭·항목별 높이·보통 타이틀바·창 제목·pane 선택·AppDelegate 입구 사유 전달을 통합한다. 기존 카드·파이프라인·깜빡이는 커서를 제거하고 이전 UI 전용 로케일 키만 삭제한다. 통합으로 깨지는 기존 테스트만 갱신한다 | B2 창 통합 | controller가 한 카드 순서와 600pt 기준을 측정하고, 기존 root는 새 pane들을 조립하지 않는다. 제목바·콘텐츠 inset·첫 크기·창 사유 lifecycle은 현재 계약과 다르다 | `app/Sources/App/SetupWindowController.swift`, `app/Sources/App/AppDelegate.swift`, `app/Sources/App/Theme.swift`, `app/Sources/App/Localization.swift` (구 키 설명 주석 갱신), `app/Sources/App/Resources/{en,ko,ja,zh-Hans,zh-Hant}.lproj/Localizable.strings`; `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Tests/AppTests/SetupWindowRedrawTests.swift`, `app/Tests/AppTests/LocalizationCatalogTests.swift`, `app/Tests/AppTests/CatalogueOwnershipTests.swift`, `app/Tests/AppTests/CmuxLocalizationTests.swift` | 2–5 | todo | `rg -n -e 'FittedContentStackView' -e 'SetupWindowPlace' -e 'func role\(' -e 'func capturePlace' -e 'func restore' app/Sources/App/SetupWindowController.swift` → `FittedContentStackView:48`, `SetupWindowPlace:586`, `role:1319` | — |
| 7 | stale 설정 창 UI 이름·설명을 README·설치 출력·점검표·개발/배경 문서에서 정리하고 README의 Warp 프리셋 개수 4는 유지한다. 결정·실험 근거는 고치지 않고 실제 UI 이름만 갱신한다 | 문서 동기화 | 문서에 이전 버튼명·체크박스·파이프라인 카드가 남아 있고 새 터미널 점검표는 제거할 pipeline-node 화면을 요구한다 | `README.md`, `install.sh`, `docs/new-terminal-checklist.md`, `CLAUDE.md` (옛 UI 이름 검색·필요한 이름만 갱신), `docs/context/tab-activation.md` (체크박스 용어만 UI 이름에 맞춤); `docs/context/*.md` 중 옛 설정 창 UI 이름이 검색되는 곳만 같은 제한으로 갱신 | 6 | todo | `rg -n -e 'Run Test' -e 'Run in Terminal' -e 'Open Extension Options Page' -e 'Keep the current screen when you press a button' -e 'pipeline nodes' -e 'checkbox' -e 'card' README.md install.sh docs/new-terminal-checklist.md CLAUDE.md docs/context` | — |
| 8 | Chrome 확장 아이콘을 앱 아이콘에서 만든 16·32·48·128 PNG로 지정한다. 16·32는 어두운 타일이 캔버스를 거의 채우게 자르고, 48·128은 Chrome 권장 여백을 둔다. manifest `icons` 와 `action.default_icon` 을 채운다 | 확장 정적 자산 | `extension/manifest.json` 의 action이 비어 있고 아이콘 필드가 없다 | `extension/icons/` (신규 PNG); `extension/manifest.json`; `tests/i18n.test.js`; `app/Tests/AppTests/ExtensionCopyTests.swift`; `app/AppIcon.icns`, `docs/assets/icon.png` (원본 확인) | 1 | todo | `tests/i18n.test.js` 는 네 manifest 아이콘 경로와 PNG 파일 존재를 검증하고 `key` 불변을 고정한다. `ExtensionCopyTests.swift` 는 recursive install copy에 새 자산이 포함되는지 고정한다. `app/build.sh` 는 `cp -R ../extension` 으로 복사하며 파일 목록을 쓰지 않아 수정 대상 아님 | — |

- 6번은 더 나누지 않는다. toolbar만 먼저 연결하거나 pane을 하나씩 root에 올리면 미완성 항목과 기존 카드가 함께 보이거나 다른 항목이 비고, 옛 키를 지울 수 있는 시점도 호출부를 한 번에 전환한 뒤이므로 매 승격에서 완전한 창과 green 테스트를 보장할 이음매가 없다. 조립·기존 UI 제거·입구 사유 전달은 같은 root 교체로 끝낸다.
- 2∼5번은 pane 구현과 그 pane의 새 키를 같은 승격에 넣고 기존 키를 수정하지 않는다. 각 승격에서 다섯 앱 카탈로그와 `LocalizationCatalogTests`·`CatalogueOwnershipTests` 가 green인 상태를 확인한다. Item 2의 문제 문구는 창 연 이유, 오류, 경고 순서를 지키며, cmux 거부·Warp 조건·Slack 링크 열기 실패의 설명도 각각 원인을 단정하지 않는 문구로 추가한다.
- D8의 다섯 로케일 UI 문구 교정도 새 pane 키에 넣는다: 2번은 Warp 손쉬운 사용 조건만과 cmux socket control mode의 허용 범위, 3번은 `claude` 가 실행 파일이 아닐 때 Slack 링크도 열 수 없다는 경고, 4번은 “PR·이슈 목록에서 여러 개를 실행할 때”, 5번은 Slack 요청 그림의 Slack MCP 설명을 다룬다. 정상 상태 안내나 프리셋 개수는 추가하지 않는다.
- 카탈로그 계획은 새 키 `app.setup.*` 를 2∼5번의 pane 소유로 추가하고, 기존 UI 키는 번역 값을 바꾸지 않은 채 6번에서 삭제하는 것이다. 변경 키는 없다. 삭제할 사용 전용 키는 `app.pipeline.*`, `app.card.*`, `app.section.cmux.*`, `app.section.accessibility.help`, `app.tools.claudeWrapper.advice`, `app.status.extension.connected`, `app.status.extension.waiting`, `app.button.openOptionsPage`, `app.button.runInTerminal`, `app.terminal.openInBackground` 및 note처럼 기존 SetupWindow 전용 호출이 끝나는 키다. 정확한 미사용 집합은 새 호출부 전환 후 다섯 카탈로그·`LocalizationCatalogTests`·`CatalogueOwnershipTests` 에서 확인한다.
- 6번의 로케일 파일 변경은 옛 UI가 쓰던 키 삭제로 한정한다. 제거 후보는 `app.pipeline.*`, `app.card.chrome.title`, `app.card.extension.title`, `app.card.extension.help`, `app.card.baseDir.help`, `app.card.baseDir.legacyNote`, `app.card.slack.help`, `app.card.tools.title`, `app.card.tools.help`, `app.card.test.title` 및 새 호출부가 없는 나머지 card 전용 키다. 호출부를 새 키로 옮긴 뒤 실제 사용 집합을 확인하고 다섯 카탈로그에서 동일하게 제거한다. 새 키 추가와 문구 교정은 2∼5번에 둔다.
- 기존 테스트: `SetupWindowLayoutTests` 는 600pt·card-order·pipeline 단언을 720pt, pane별 fit, 공통 상단 영역, 보통 타이틀바로 바꾼다. `SetupWindowRedrawTests` 는 pane 선택, action-derived role·UTF-16 범위, 스크롤 기준점, 편집 초안 및 막힘·실패 보존과 refresh 때 뷰 재생성이 없는 것을 고정한다. `CmuxPlacementSetupTests` 는 pane 이동에 맞춰 업데이트되어 Core 실효 배치와 그림 모델을 대조한다. `SlackThreadSettingsTests` 는 기존 #107 동작과 단일 검증 함수를 Slack pane에 고정한다. 카탈로그 테스트는 매 pane 승격의 새 키 완전성 및 통합 때 옛 키 삭제를 고정한다. 새 순수 테스트는 창 연 사유 전체 표시·최신 순서, 오류 후 경고, cmux 거부와 미실행 구분, 확장 폴더 사라짐, request evidence 보존, workspace identity override를 고정한다. `SetupWindowTestSupport.settle` 에서 강제 layout하지 않고 테스트 창을 닫지 않으며 AppKit 게이트는 하나씩 직렬 실행한다.

## 결정 원장

사용자 행은 2026-10-03 이 세션에서 지정한 결정을 기록하고, 드라이버 행은 설계 리뷰에서 추가로 닫은 결정을 기록한다. 구현 선택과 실측할 사실은 작업 항목과 열린 질문에 둔다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | 여러 설정이 동시에 보여 창이 길고 상태 안내가 특정 카드에 묶임 | General · GitHub · Slack 세 항목의 macOS 설정 창 툴바, 한 항목만 표시, 720pt 폭·항목별 높이; 문제·설치 안내는 툴바 아래에서 공통 표시 | 사용자 결정 1, 2026-10-03 | 툴바 높이·콘텐츠 영역·클램프 실측은 열린 질문 1 |
| D2 | 사용자 | 파이프라인이 성공 여부로 오해되고 Chrome 요청이 명령 성공으로 보일 수 있음 | 일반 항목에 “확장 요청을 받았습니다”와 상대 시각, 연결 상세 팝오버(Chrome 확장 요청 도착·Native Host·앱 소켓·터미널·도구); pipeline 줄과 깜빡이는 커서를 제거 | 사용자 결정 2, 2026-10-03; 요청 기록 근거 `CLAUDE.md:42` | 팝오버 안 각 단계의 추가 기계 진단은 요구하지 않음 |
| D3 | 사용자 | 오류만 보여 창을 연 직접 원인과 조치·영향이 사라짐 | 창을 연 Claude 거절 사유 또는 Slack 실패를 먼저 표시하고 오류·경고 순으로 렌더; 색 가장자리 막대 없이 제목 앞 심각도 점, 원인·수정법·영향·동작 버튼 포함 | 사용자 결정 3, 2026-10-03; 현 blocker 전달부 `app/Sources/App/AppDelegate.swift:40` | 없음 — 지속·정렬은 D10에서 결정 |
| D4 | 사용자 | 처음 설치 뒤 무엇을 할지, 연결 뒤 폴더가 없어진 상태를 구별하지 못함 | Native Host·Chrome 설치·첫 GitHub 요청 checklist; Chrome 설치 버튼을 누르면 네 단계 조작을 펼침; 다시 연 안내는 `안내 닫기`; 가이드 조작이 request evidence를 지우지 않음; evidence 이후 폴더가 사라지면 문제 블록 | 사용자 결정 4, 2026-10-03; `Installer.extensionState` 와 `Settings.lastRequestAt` 의미는 `CLAUDE.md:42` | 없음 |
| D5 | 사용자 | 일반 설정은 terminal-specific 동작·권한 조건을 평소 설명 없이 알려야 함 | 다섯 터미널 선택과 미설치 비활성 표기·상태·Terminal Test; after-action 분절; Warp에서는 “터미널로 이동” 상태를 보이면서 분절을 비활성화하고 저장 선택은 보존, 다른 터미널을 선택하면 각자 저장된 선택 복원; 힌트·미리보기; 언어 재시작 안내는 선택 뒤에만; GitHub 편집은 Chrome 확장 요청 기록 뒤에만; 가이드 다시 보기 | 사용자 결정 5, 2026-10-03 | 없음 |
| D6 | 사용자 | 저장소 기본 폴더의 정상 안내가 과하고 cmux placement의 실제 효과가 모호함 | 저장소 찾는 순서·도움말 문단·이전 버전 버튼 안내는 두지 않는다. 기본 폴더·폴더 선택만 제공하고 상태는 저장되지 않은 잘못된 입력, 저장된 잘못된 값, clone 때 만들어질 아직 없는 폴더, 값과 zoxide가 모두 없을 때만 표시한다. cmux에서 pane/tab/workspace와 새로 만들기/이름 찾기, workspace-per-item에서 identity 비활성·저장값 보존; 표시 문장은 Core 결과, 비-cmux는 행마다 새 탭; 이름으로 찾은 workspace의 원래 pane/tab은 그대로 두는 세 행 그림 | 사용자 결정 6, 2026-10-03; `app/Sources/Core/CmuxPlacement.swift` | 없음 |
| D7 | 사용자 | Slack 설정과 요청 실패가 일반 화면의 문제 목록에 합쳐지지 않고, 적용 결과를 알기 어려움 | PR #107 기준으로 작업 폴더·검증 표시가 있는 Claude 지시문·단축키 녹화/지우기·수식키 필요 경고·등록 실패·로그인할 때 앱 열기와 상태·“단축키는 앱이 실행 중일 때만 동작합니다.” 힌트를 둔다. Slack 요청 실패는 카드 아래가 아닌 위쪽 공통 문제 영역에 보이고 Slack 툴바 항목에 빨간 점을 표시한다. 그림은 그 폴더에서 `claude '<Slack 링크> <지시문>'` 을 실행하며 Slack MCP 필요를 설명한다 | 사용자 결정 7, 2026-10-03; PR #107 | 녹화·로그인 코드는 기존 구현을 옮기며 D7은 그 UI·상태 범위를 지정 |
| D8 | 사용자 | Warp preset 수·cmux 모드·배치 단어·Claude 실행 파일 경고 문구가 부정확함 | 다섯 로케일 모두 조건 중심 Warp 안내, cmux `automation` 권장 및 다른 유효 모드, “PR·이슈 목록에서 여러 개를 실행할 때”, Slack 링크도 열 수 없다는 Claude 경고로 고친다 | 사용자 결정 8, 2026-10-03 | 없음 |
| D9 | 사용자 | 현재 컨트롤명이 새 기능과 다름 | `GitHub 버튼 편집…`, `터미널 테스트`, `실행 후 화면` 으로 이름을 바꾼다 | 사용자 결정 9, 2026-10-03 | 없음 |
| D10 | 드라이버 | 한 창 생명주기에 창을 연 이유가 겹칠 수 있음 | 창을 연 이유는 각각 문제 블록 하나로 모두 보이고 가장 최근에 도착한 것이 맨 위다. Slack 실패 블록은 다음 Slack 요청이 성공하면 사라진다. Claude 입력 거절 블록은 창이 닫히거나 원인이 풀리면(예: 손쉬운 사용 권한이 생김) 사라진다. 어느 이유도 앱 재시작을 넘어 저장하지 않는다 | R0 설계 리뷰, 2026-10-03 | 없음 |
| D11 | 드라이버 | 툴바가 있는 창을 열 때 첫 선택이 정해져 있지 않음 | Slack 실패로 열리면 Slack, Claude 입력 거절로 열리면 General, 그 밖에는 앱이 실행되는 동안 마지막으로 고른 항목(처음엔 General)을 선택한다. 선택은 UserDefaults에 저장하지 않는다. 언어 rebuild는 현재 항목을 유지한다 | R0 설계 리뷰, 2026-10-03 | 없음 |
| D12 | 드라이버 | 투명 타이틀바 아래 콘텐츠와 preference 툴바의 크기 계약이 모호함 | preference 툴바를 쓰므로 `.fullSizeContentView` 와 투명 타이틀바를 버리고 보통 타이틀 창으로 간다. 창 제목은 선택한 항목 이름이다. 콘텐츠는 툴바 아래에서 시작하므로 기존 38pt 위 여백과 자동 inset 비활성화 처리를 새 구조에 맞춰 정한다. #34의 지연 적용·한 레이아웃 주기 한 화면 결정·첫 측정 크기만 가운데 배치는 유지한다 | R0 설계 리뷰, 2026-10-03; #34 | 툴바 높이·콘텐츠 영역·클램프 실측은 열린 질문 1 |
| D13 | 사용자 | “아이콘 아이덴티티가 좀 더 포함되면 이쁘겠다” | 앱 아이콘(`app/AppIcon.icns`, `docs/assets/icon.png`; 어두운 둥근 타일 위 초록 `>_`)을 창에 더 드러낸다. General 툴바는 앱 아이콘, GitHub·Slack은 SF Symbols다. General 맨 위에 32∼36pt 아이콘·“Terminal Checkout”·`CFBundleShortVersionString` 을 한 줄로 두고 그 아래 상태 줄을 둔다. 버전은 이 헤더로 옮긴다. 그림의 프롬프트 글리프는 `Theme.ok` 가 아이콘 초록에 가장 가까운 후보이므로 두 색을 실측 비교해 하나로 정한다 | 사용자 추가 요청, 2026-10-03; 앱 아이콘 자산 | 실측 색 비교는 항목 3에서 완료 |
| D14 | 사용자 | “크롬 익스텐션 아이콘도 지정해줘” | `app/AppIcon.icns` 의 iconset(16∼1024px)에서 16·32·48·128 PNG를 만든다. 16·32는 타일이 캔버스를 거의 채우게 자르고 48·128은 Chrome 권장 여백을 둔다. `extension/manifest.json` 의 `icons` 와 `action.default_icon` 에 지정한다 | 사용자 추가 요청, 2026-10-03; 현 manifest `"action": {}` | 없음 |

## 전수 소탕 표

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| 창 연 이유·문제 우선순위·Slack 실패 표시 | 구멍(항목 1, 2, 6) | `app/Sources/App/AppDelegate.swift:40`; `app/Sources/App/SetupWindowController.swift:1852` |
| Chrome 요청 기록과 명령 성공, 설치 폴더 존재 | 안전성 보존 | `CLAUDE.md:42`; `app/Sources/App/Settings.swift` 의 `lastRequestAt`; `app/Sources/App/Installer.swift:87,172` |
| cmux 접근 거부와 실행 중 아님 | 안전성 보존 | `CLAUDE.md:60`; `docs/context/cmux-integration.md` D1 |
| Warp 손쉬운 사용 범위·프리셋 수 문구 | 구멍(항목 2, 3, 7) | `CLAUDE.md:45`; `app/Sources/App/Resources/en.lproj/Localizable.strings:84` |
| 기본 폴더 정상·오류 표기 | 구멍(항목 4, 6) | `app/Sources/App/SetupWindowController.swift:823,1724` |
| Core effective identity와 preview | 안전성 보존 | `app/Sources/Core/CmuxPlacement.swift` |
| Slack 링크·설정 소유·단축키 진입 | 안전성 보존 | `docs/context/slack-thread-shortcut.md`; `app/Sources/App/SetupWindowController.swift:1852` |
| 다섯 앱 카탈로그 키·중복·호출 근거 | 구멍(항목 2–6) | `app/Tests/AppTests/LocalizationCatalogTests.swift`; `app/Tests/AppTests/CatalogueOwnershipTests.swift` |
| 창 fit·언어 재구축·툴바 화면 배치 | 구멍(항목 6) | `app/Sources/App/SetupWindowController.swift:48,79,586,642`; `app/Tests/AppTests/SetupWindowTestSupport.swift` |
| README·install·terminal checklist·배경 문서의 UI 인용 | 구멍(항목 7) | `README.md:65,75,238,369,390`; `install.sh:176`; `docs/new-terminal-checklist.md:11,66`; `docs/context/tab-activation.md:13,21` |
| Chrome 확장 아이콘 manifest·복사 | 구멍(항목 8) | `extension/manifest.json` 의 빈 action; `tests/i18n.test.js`; `app/Tests/AppTests/ExtensionCopyTests.swift` |

## 라운드 로그

### R0

#### 설계 리뷰 — R0 승인 · 승격 없음 · 리뷰 완료

- 반박: R0-1∼R0-10 (드라이버 설계 리뷰), R0-11 (사용자 추가 요청 둘)
- 처리: 전부 반영 — 6번에서 문자열을 2∼5번으로 나눔, D7·D10·D11·D12·D13·D14 추가, 불변 원칙 셋 추가, 5번은 #107 코드 이전, 7번 소탕 범위 확대, 8번(확장 아이콘) 신설, 배치 점검 실측 기입
- 실측: `node --test` → exit 0, 324/324; `node tools/check-locales.js` → exit 0, `all 5 live catalogues carry the same names and argument bindings as en`; Swift 기준선 `416ce06` 은 드라이버가 clone에서 `cd app && swift test` 실행, exit 0, CoreTests 560 실행(1 skipped), AppTests 155 실행, 실패 0
- 판정: R0 계획 승인 — 1번부터 구현 시작

## 열린 질문

- D12의 일반 타이틀 창에서 preference 툴바 높이·콘텐츠 영역·클램프를 실측한다. #34의 지연 적용, 레이아웃 주기당 한 화면 결정, 첫 측정 크기만 가운데 배치하는 규칙 아래 실제 window frame·pane 높이·다중 화면 배치를 드라이버가 항목 6 승격 게이트에서 확인한다. 막는 항목: 6.
- preference 툴바의 표시명과 SF Symbols가 다섯 로케일에서 잘리고 겹치지 않는지, VoiceOver에서 항목명과 Slack 오류 상태가 한 번씩 구별되어 읽히는지 기기에서 확인한다. 막는 항목: 6.
