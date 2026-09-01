# cmux placement preset

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: terminal-checkout · `app` grouped execution 및 setup window
- 시작 커밋: `e5b1b9b` (`docs: measure the cmux RPC placement contract for batch fan-out (#77)`)
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/cmux-placement-preset-review` (`worktree-cmux-placement-preset-review`) · 메인 체크아웃: `/Users/choongjaelee/Codes/terminal-checkout` (`main`, 무변경) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-cmux-placement-preset-work` (`cmux-placement-preset-work`)
- 현재: R1 반영 완료 · 항목 1 cleared · 항목 2 cleared · 항목 3 cleared · 항목 4 cleared · 항목 4′ verified · 항목 5 verified
- 최근 검증자 판정: "항목 4 차단 (a)(b) 막힘 확인 — cmux+items[]만 grouped 훅, admission 선확보·전량 반납, deadline seam, per-item timeline·경로 기록이 테스트로 고정. 잔여 없음." (드라이버, R1) · 원문 없음

이 파일은 **실행한 계획과 실행할 계획의 기록**이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실. 코드 수정 과정을 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다. 결정이나 질문이 특정 동작에 걸리면 한 절과 `파일:행`으로 끝낸다. 이 템플릿에 없는 소절을 만들지 않는다 — 테스트 설계는 테스트 파일이 말한다.

## 배경 — 확인한 원천

문제를 파악하며 확인한 영구 소스만 — Slack 스레드·이슈·PR·설계 문서처럼 세션이 끝나도 남는 것. 스크래치패드 경로는 여기 두지 않는다. 원천의 내용과 이 루프의 결정이 어긋나면 결정 원장의 `사용자` 행이 우선한다 — 원천을 읽었으면 원장에서 사용자가 결정·수정·취소한 것을 이어서 확인해라.

- [이슈 #71](https://github.com/dazebug/terminal-checkout/issues/71) — 확장은 what만 보내고 앱이 where를 결정하며, `items[]`는 하나의 원자적 요청이고 검증 실패는 fail-closed여야 한다.
- [이슈 #69](https://github.com/dazebug/terminal-checkout/issues/69) — cmux placement의 identity level·identity mode·arrangement, 앱 로컬 저장, layout fan-out 및 1023 UTF-8 바이트 경계를 정의한다.
- [이슈 #68](https://github.com/dazebug/terminal-checkout/issues/68) — `window_id`, layout 트리, focused-leaf 응답, depth-first `pane.index`, `operation_id`, N≤8 geometry, tty/readiness, 1023/1024 바이트 동작을 실측한다.
- [`docs/context/cmux-integration.md`](../context/cmux-integration.md) — cmux RPC만 사용하는 소켓·retry·channel 계약과 Placement contract matrix를 정본으로 둔다.
- [`docs/context/testing.md`](../context/testing.md) — 순수 파서·소스 감사 경계, AppKit run-loop settle, 테스트 토글 판정 원칙을 정한다.
- [`CLAUDE.md`](../../CLAUDE.md) — TCC 실행 분리, cmux socket pinning, command gate, Claude 입력 전달, 새 실행 경로 체크리스트 의무를 정한다.
- [`README.md`](../../README.md) — `cd app && swift test`와 `node --test`를 포함한 Development 게이트의 정본이다.
- [`docs/new-terminal-checklist.md`](../new-terminal-checklist.md) — 이미 batch fan-out와 stable/NIGHTLY cmux 수동 검증을 보유하며, 이번 placement 실행 경로의 항목을 추가할 대상이다.

## 목표

cmux stable/NIGHTLY 선택 시 앱 소유 머신 로컬 preset이 workspace identity와 always-new/fixed-name mode, tab/pane/workspace arrangement를 결정한다.

기본 arrangement는 pane per item이며, N≤8은 측정된 layout fan-out을 사용하고 N=9∼25는 측정 범위를 넘는 pane geometry를 피하여 같은 grouped 실행의 tab-per-item으로 폴백한다.

`items[]`는 먼저 전부 검증한 뒤 cmux에서는 하나의 grouped 실행으로 배치하고, 안전한 leaf command·oversize guarded send·surface 순서를 각각 측정 계약에 맞게 적용한다.

cmux 외 터미널의 현재 N-tab loop와 Claude per-session 전달은 유지하고, setup window의 placement section은 cmux와 cmux NIGHTLY에서만 보이며 preset은 `storage.sync`에 들어가지 않는다.

## 완료의 정의

- 반드시 재현해 막아야 할 실패: 현재 batch N개가 `runInCmux`를 N회 호출해 N개의 독립 workspace를 만들지만, 목표 preset은 한 grouped request 안에서 workspace identity/arrangement로 N개 item을 배치하고 source order 결과를 반환한다; found fixed-name workspace의 pane-per-item N≤8은 U4의 균형 split이어야 하며, pane N=9 이상이나 leaf command 1024 UTF-8 바이트 이상을 미측정 layout 또는 잘린 inline command로 처리해서는 안 된다.
- acceptance oracle: 실패 테스트를 먼저 추가해 red를 확인한 뒤 `cd app && swift test`의 driver 결과와 cmux hands-on matrix가 배치·identity·layout·retry·Claude 전달 불변식을 모두 통과하고, `node --test`가 exit 0이며 실행 테스트 수를 함께 확인한다; 구현자 sandbox에서는 Swift와 cmux 결과를 실행·판정하지 않는다.
- 코퍼스 범위: `extension/defaults.js`의 13 shipped preset과 `buildListBatchRequest`가 만드는 실제 `items[]` shape를 기준으로 N∈{1,2,3,4,5,8,9,25}, source-order variables, stable/NIGHTLY, workspace identity 1 level×2 mode, arrangement 3종, UTF-8 command 1023/1024/1025-byte 경계를 갖는 driver corpus를 사용하며 저장 fixture는 만들지 않는다.
- 원자성·부분 실패·롤백 경계: content validation은 side effect 전에 전체 item을 검사하고 하나라도 실패하면 launch 0건으로 per-item not-launched 결과를 낸다; placement side effect 뒤에는 이미 만들어진 surface/workspace를 rollback하지 않으며 ordered per-item failure를 반환한다; `workspace.create`는 동일 operation ID로만 transport uncertainty를 재시도하고 live workspace 재응답은 at-most-once로 취급하며 `already_completed`는 terminal이다; unkeyed 또는 post-forward가 불확실한 non-idempotent RPC는 fail-closed하고 command/Claude CR를 재전송하지 않는다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

이 루프가 막는 실패를 일으킬 수 있는 행위자(사람·프로세스·시스템)와 그 능력을 열거한다. **발견을 배정하려면 어느 행위자가 그 결함에 닿는지 이름을 대야 한다** — 모델 밖 행위자가 필요한 발견은 기본이 잔여(원장 기록, 배정 없음)다. 행위자를 새로 들이는 것은 범위 변경이라 사용자 승인이 필요하다. 해당 없으면(순수 로직 루프) N/A + 근거.

- Chrome extension/relay: `items[]`와 item variables/claude inputs를 보낼 수 있지만 placement를 지정하거나 앱의 로컬 preset을 바꿀 수 없다.
- 앱 사용자: setup window에서 local preset을 바꾸고 cmux의 active window/workspace를 닫거나 이름을 충돌시킬 수 있다.
- HostServer/execQueue/TerminalRunner: batch를 preflight하고 cmux RPC 및 per-session Claude delivery를 연결하는 local process다.
- cmux CLI/server stable·NIGHTLY: pinned socket의 접근 거부·소켓 교체·RPC rejection·응답 유실·live/closed operation ID 상태를 일으킬 수 있다.

## 비목표 — 건드리지 않는다

- `#70` send-time picker: placement를 요청 시 선택하는 UI와 protocol은 후속 범위다.
- `#72` relay-window: relay가 window를 소유하거나 전달하는 변경은 하지 않는다.
- `#76` `Path exists at` retry 분류: 이번 placement 구현에서 세 번째 retry 형태를 추가하거나 분류하지 않는다.
- `#78`·`#79`: option help와 구세대 앱 문구는 갱신하지 않는다.
- `extension/`: 기존 `items[]` payload와 preset/page/storage 동작은 확인만 하고 placement field나 `storage.sync` 변경을 넣지 않는다.
- cmux 설정 파일: 앱은 기존 socket control mode 설정을 읽어 추론하거나 쓰지 않으며 setup action의 현재 비파괴 동작을 바꾸지 않는다.
- non-cmux execution: iTerm2·WezTerm·Warp의 N-tab loop, 각 terminal의 기존 permission/input route, 기존 response shape를 placement 때문에 바꾸지 않는다.
- relay framing, native host name, app bundle ID, TCC 책임 프로세스 분리 및 새 터미널 지원은 범위에 넣지 않는다.

## 불변 원칙

0라운드 이후 이 절과 「완료의 정의」에 항목을 **더하는 것은 범위 변경이다** — 결정 원장의 `사용자` 행 없이 추가하지 않는다(드라이버·검증자 발의는 비용 추정과 함께 사용자 승인 후). 드라이버가 스스로 쓴 기준을 스스로 집행하는 것이 일감 자가 생산의 뿌리다.

- extension은 what(`items[]`, command, variables, claude inputs)만 보내고 app은 where를 고른다; request에 placement를 추가하지 않는다.
- 하나의 `items[]` request는 먼저 전체 validation을 끝낸 뒤 실행하며, batch는 N개의 socket request로 쪼개지지 않는다. legacy 단일 요청은 기존 경로를 유지한다.
- preset은 `cmuxPlacement` 접두의 개별 raw-string `UserDefaults` key를 사용하는 app-local state다. Core의 단일 parser가 unknown 값을 fresh default로 폴백하고 UI는 즉시 저장한다. `storage.sync`, extension defaults, cmux settings file, live cmux state를 저장 원천으로 사용하지 않는다.
- identity level은 workspace만이고 mode는 always-new 또는 fixed-name이다. workspace-per-item arrangement는 workspace identity와 결합하지 않으며 그 arrangement의 컨테이너는 항상 현재 window다. implicit current target 대신 확인된 workspace ID와 matrix가 허용한 RPC만 사용한다.
- pane-per-item은 default arrangement다. layout geometry는 실측된 N≤8까지만 주장하고, N>8은 layout을 확장하지 않고 같은 grouped request의 tab-per-item으로 폴백한다.
- layout은 두 자식 branch와 leaf `pane.surfaces[].command`로만 만든다. leaf inline command는 1023 UTF-8 bytes 이하만 허용하며, 1024 이상은 leaf에서 생략하고 해당 surface를 기존 guarded `surface.send_text` 경로로 보낸다.
- found fixed-name workspace의 pane-per-item은 layout create가 아니라 `pane.index` 0 pane의 첫 surface를 결정론적 root로 삼아 target 지정 `surface.split`을 재귀 실행한다. 깊이 d의 방향은 짝수=right, 홀수=down이고 root가 이미 절반 폭이므로 depth 1부터 down이며, 원 surface `ceil(n/2)`개와 split 응답 새 surface `floor(n/2)`개가 각각 재귀 leaf를 담당한다. item↔surface order는 응답에서 수집한 `surface_id` 순서가 정본이고, found+pane N>8은 tab-per-item으로 폴백한다.
- `workspace.create`에는 title·cwd·focus·window_id·layout·operation_id만 계약에 따라 넣고 top-level `name`·`command`에는 의존하지 않는다. create 응답의 `surface_id`는 focused leaf뿐이므로 `pane.list`/`surface.list`를 열거하고 depth-first `pane.index`로 source order를 복원한다.
- 동일 grouped create의 retry에는 stable operation ID를 사용한다. live repeat은 같은 workspace ID를 반환하는 at-most-once이고, 닫힌 뒤 `already_completed`는 자동 복구·새 workspace 생성으로 해석하지 않는다. 키를 보내는 승격에서 `CmuxControl.swift`의 기존 non-idempotent 주석을 갱신한다.
- cmux control path는 `cmuxRPC` 하나이며 channel별 live socket pinning, pointer 재해석, no preflight ping, access denied 즉시 실패, 기존 typed retry classification을 유지한다. `Path exists at`은 이번 루프에서 retry 가능으로 승격하지 않는다.
- `surface.send_text` 전송 gate는 payload가 `darwinCanonicalLineLimit` 이내면 raw mode를 기다리지 않고, 초과하면 raw mode deadline을 기다린 뒤 거부한다. writer가 accepted라고 보고한 것만으로 command submission이나 readiness를 추정하지 않는다.
- `tty`는 command submission 뒤의 진단 값이지 focus/readiness 신호가 아니다. queued output과 shell warm-up은 기존 cmux readiness/command gate를 재사용한다.
- Claude 입력은 item별 surface UUID handle로 기존 `deliverClaudeInputs`/`submitClaudeInputs` pipeline을 재사용한다. cmux는 pane proof가 필요 없고 background tab 전달을 계속하며, type→reflection→CR·clear·no-retype-after-CR 규칙과 모든 `send(_:io:)` gate를 우회하지 않는다.
- grouped command 응답은 Claude delivery 완료를 기다리지 않는다. 입력이 있는 item은 기존 admission/concurrency limit과 per-session timeline을 그대로 적용한다.
- placement route(layout create / found split / tab 폴백 / N>8 폴백)는 item timeline step과 `checkoutLog`에 기록하고 response contract는 변경하지 않는다.
- non-cmux는 기존 순차 N-tab launch와 per-item result를 계속 사용한다. placement section과 placement storage는 `Settings.terminal.cmuxChannel != nil`일 때만 활성화한다.
- setup window는 기존 `Theme.swift` palette와 refillable-section/redraw/run-loop settle 규칙을 재사용하고, 새 user-facing text는 다섯 app locale catalogue에 모두 둔다.
- 기능 추가로 생기는 모든 command/placement/identity/long-payload/background-delivery 경로는 `docs/new-terminal-checklist.md`에 수동 oracle을 추가한다. 구현자가 `swift test` 또는 cmux socket 실패를 regression으로 반올림하지 않는다.

## 배치 점검 (0라운드)

모드: ultrafast

(`default` 또는 `ultrafast`. 이 줄이 적힌 뒤로는 스킬 인자가 아니라 이 값이 모드를 정한다 — 스킬의 점검 블록이 이 줄을 읽는다.)

이 표의 실측 주체는 드라이버다 — 구현자가 채우는 행은 「에이전트 첫 보고」뿐이고, 자기 샌드박스의 실패로 드라이버 실측 값을 덮어쓰지 않는다(샌드박스 제약은 리포 오버레이 「ultrafast 모드 — 구현자 샌드박스 실측」에 적는다).

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | ignored — 드라이버가 기준 트리에서 `git check-ignore -q .claude/worktrees/probe` → exit 0. clone에는 `.claude/worktrees/`가 없어 구현자 측정은 무관 |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 설정 key는 `.claude/drive-agent-loop.md`에서 확인되지 않음; 첫 보고와 기준 트리 모두 `e5b1b9b`를 가리킴 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-cmux-placement-preset-work` · `cmux-placement-preset-work` · `e5b1b9b` |
| 리포 오버레이 `.claude/drive-agent-loop.md` — 있으면 경로, 없으면 이번 초안과 함께 작성 | 있음 — `/Users/choongjaelee/Codes/terminal-checkout-cmux-placement-preset-work/.claude/drive-agent-loop.md` |
| cmux 패널 (점검 블록 `cmux:` 신호가 켜졌을 때만, 아니면 N/A) — `cmux markdown open <작업 트리 계획 파일 절대경로>` → pane id. 계획 파일 첫 승격 전에 채운다 | pane:228 · surface:243 (드라이버 실행 2026-09-01) |
| 트리마다 의존성 동기화 (기준·작업) | 불필요 — SPM 의존성은 `swift test`가 해소하고 extension은 무의존(런타임 의존성 없음) |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 없음 — overlay에 local asset env 없음 |
| 증분 리뷰 소요(분) — 첫 세 번 | N/A — 승격·증분 리뷰 없음 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `items[]`를 전체 preflight 후 grouped executor로 넘기는 Core 계약과 cmux placement plan을 만든다; workspace identity/arrangement 조합 검증, pane default, N>8 tab fallback, depth-first leaf order를 순수 값으로 고정한다. | Core 계약·순수 계획 | (a) `handleBatchRequest`가 현재 `run`을 item마다 호출함 (b) 앱 소유 placement 상태와 grouped hook이 없음 | `app/Sources/Core/Request.swift`, 신규 `app/Sources/Core/CmuxPlacement.swift`, `app/Tests/CoreTests/BatchProtocolTests.swift`, 신규 `app/Tests/CoreTests/CmuxPlacementTests.swift` | — | cleared | 재실행: `cd app && swift test` → Executed 602 tests, 0 failures (드라이버, 기준선 587) · `node --test` → 252/252 · F1(found-split item 순서)의 red는 발견 시점 조합(depth-first 기대값 × 응답순 구현)으로 실관찰 — 토글 재실행 생략(순열 불일치가 논리 확정) | — |
| 2 | cmux 전용 app-local preset 저장과 setup window section을 추가한다; workspace identity/mode/name 및 arrangement control을 cmux stable/NIGHTLY에서만 노출하고 fresh default `workspace × always-new × pane-per-item`, 다섯 locale, 기존 Theme/refill/redraw contract를 맞춘다. | App 설정·UI | (a) placement preset의 `UserDefaults` 소스가 없음 (b) 현재 cmux section은 socket status/config만 제공함 | `app/Sources/App/Settings.swift`, `app/Sources/App/SetupWindowController.swift`, `app/Sources/App/Theme.swift` 확인·필요 시 최소 수정, `app/Sources/App/Resources/{en,ko,ja,zh-Hans,zh-Hant}.lproj/Localizable.strings`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Tests/AppTests/SetupWindowRedrawTests.swift`, `app/Tests/AppTests/LocalizationCatalogTests.swift`, 신규 `app/Tests/AppTests/CmuxPlacementSetupTests.swift` | 1 | cleared | 추가 테스트 9개: `testPlacementSettingsRoundTripRawStrings`, `testPlacementSettingsPassNonStringValuesAsText`, `testPlacementControlsAppearOnlyForCmuxChannels`, `testPlacementControlsUseFreshDefaults`, `testPlacementRadioChangesSaveImmediately`, `testPlacementNameUsesBaseDirectoryEditingSaveTiming`, `testPlacementInterpretationLabelUsesCoreParseResult`, `testPlacementControlsReachASettledLayout`, `testPlacementNameFieldReparentsAndKeepsAnUnstoredDraftAcrossRedraw`; `plutil -lint` → 다섯 `Localizable.strings` 모두 OK; 변경 파일: `app/Sources/App/Settings.swift`, `app/Sources/App/SetupWindowController.swift`, `app/Sources/App/Resources/{en,ko,ja,zh-Hans,zh-Hant}.lproj/Localizable.strings`, `app/Tests/AppTests/CmuxPlacementSetupTests.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Tests/AppTests/SetupWindowRedrawTests.swift`; `node --test` → exit 0, 252/252; `cd app && swift test`·`swift build`는 드라이버 게이트라 이 환경에서 미실행; F9 원인 대조: `git show c16e78f:app/Tests/AppTests/SetupWindowRedrawTests.swift`의 세 fixture와 재부모화 후 검색(`:156-159,168-169,189-192,221-224`)이 첫 editable 필드를 사용했고, `SetupWindowController.swift:658-662`가 terminal 카드를 baseDir보다 먼저 추가하며 `:904-930,991-1002,1020-1079`가 placement 이름 필드를 그 트리에 넣고 `:1473`에서 뒤늦게 cmuxSection을 숨겨 disabled 필드가 먼저 선택될 수 있음을 확정함; 현재 fixture는 `control.baseDirectoryEdited` role(`SetupWindowRedrawTests.swift:156-159,168-169,189-192,221-224`)로 특정함; F10: `SetupWindowController.swift:523-530`의 language rebuild 구간을 `isRebuildingForLanguageChange`로 표시하고 `:1372-1377`의 placement end-edit action을 그 구간에서 무시해 `drawnCmuxPlacementName` draft를 보존하며 일반 Enter/포커스 이탈 저장은 유지함; `rg -n 'NSTextField\(string:|isEditable|sendsActionOnEndEditing' app/Sources/App/SetupWindowController.swift`로 editable 컨트롤이 `baseDirField`(`:344`, `:771`)와 `cmuxPlacementNameField`(`:316`, `:1051`) 둘뿐임을 소탕함; production의 Core parser 호출은 `SetupWindowController`의 해석 라벨 갱신 한 곳이고 Settings는 raw 문자열만 전달함; 재실행: `cd app && swift test` → Executed 622 tests, 0 failures (드라이버, 직전 613) · F10 red 실관찰(리빌드 draft 저장 1 failure → 수정 후 green) · 로케일 5종 키 패리티는 기존 게이트 통과에 포함 | — |
| 3 | placement plan에 따라 cmux grouped executor와 RPC call sequence를 구현한다; N≤8 layout, found fixed-name pane의 target 지정 균형 `surface.split`, N>8 및 found+pane N>8 tab fallback, workspace identity/current-window placement, 1023-byte inline 및 guarded oversize send, enumeration/order, operation ID를 stable/NIGHTLY 양쪽에 적용한다. | Core 실행·cmux RPC | (a) `runInCmux`가 item마다 unaddressed workspace 하나만 만듦 (b) layout/leaf enumeration/order 복원이 없음 (c) `operation_id` 없는 retry 계약임 (d) found fixed-name 경로의 균형 split 시퀀스·응답 수집 매핑이 없음 | `app/Sources/Core/CmuxControl.swift`, `app/Sources/Core/TerminalRunner.swift`, 신규 `app/Sources/Core/CmuxGroupedExecution.swift`, 신규 `app/Tests/CoreTests/CmuxGroupedExecutionTests.swift` | cleared | 추가 테스트 11개: `testLayoutJSONUsesMeasuredBinaryShapeAndOmitsSubmitFromLeafCommands`, `testLayoutJSONLeavesCommandOutForGuardedSurfaceSend`, `testWorkspaceListMatchingRequiresCustomTitleAndChoosesLowestIndex`, `testAlreadyCompletedCreateFailureIsTerminalAndNeverAuthorizesLaunchRetry`, `testLayoutExecutionEnumeratesByPaneIndexAndGuardsOnlyOversizeItems`, `testFoundPaneExecutionUsesExplicitSplitTargetsAndMeasuredItemOrder`, `testFoundPaneFailureUsesConservativeAllItemFailureWithoutRollback`, `testCreatedTabsAddressEverySurfaceCreateToTheEnumeratedPane`, `testFoundTabsUseTheFirstPaneAndCreateOneSurfacePerItem`, `testWorkspacePerItemCreatesIndependentCurrentWindowWorkspaces`, `testCreateRecoveryReusesTheSameOperationParametersAfterMeasuredReachabilityFailure`; `node --test` → exit 0, 252/252; `cd app && swift test`·`swift build`·cmux hands-on은 샌드박스 제약으로 미실행; found split 실패는 응답 귀속 미측정으로 전 item failure 보수 처리; F3∼F5: `workspace.list`·`pane.list`·`surface.list` 항목 키를 실측 `id`로 파싱(`workspace_id`/`pane_id`/`surface_id` 아님); F6: `cmuxCreateWorkspaceWithRecovery`는 launch 후 nil socket pointer도 재시도함; F8: `workspace.create`의 `operation_id`는 UUID 형식만 허용되므로 plan은 `batchOperationID`·`itemOperationIDs`를 UUID로 받고 wire에는 `uuidString`을 사용함; 근거: 드라이버 실측 2026-09-01; 재실행: `cd app && swift test` → Executed 613 tests, 0 failures (드라이버, 직전 602) · 드라이버 실서버 실측 2026-09-01: layout+title+operation_id 조합 수용, keyed 반복 = 같은 workspace_id(at-most-once), operation_id는 UUID 강제(비UUID는 invalid_params), list 계열 항목 키는 `id` · F3∼F8 수정 반영 | — |
| 4 | HostServer가 cmux일 때만 preset-aware grouped executor를 호출하고, 기존 전체 validation·ordered per-item response·timeline·비동기 Claude delivery를 유지한다; layout create/found split/tab/N>8 폴백 경로 선택은 per-item timeline과 `checkoutLog`에 기록하고 응답 계약은 바꾸지 않으며, cmux 외에는 현재 serial N-tab loop를 그대로 둔다. | HostServer 통합·응답 | (a) `HostServer`가 모든 batch item을 같은 per-item launch closure로 순차 실행함 (b) grouped handles와 local preset을 전달하지 않음 | `app/Sources/App/HostServer.swift`, `app/Sources/Core/CmuxGroupedExecution.swift`, `app/Tests/AppTests/HostProtocolTests.swift`, `app/Tests/CoreTests/CmuxGroupedExecutionTests.swift`, `app/Tests/CoreTests/BatchProtocolTests.swift` | 1, 2, 3 | cleared | 재실행: `cd app && swift test` → Executed 629 tests, 0 failures (드라이버, 직전 622) · `node --test` → 252/252 exit 0 (드라이버) · F11 인자 순서·F12 병합 규칙 기대값 교정 반영 | — |
| 4′ | 항목 4의 layout surface 열거와 found root 조회를 실측 workspace-wide `surface.list` 계약에 맞추고, item↔surface 매핑을 pane 소유 정보로 재구성한다. | HostServer 통합·응답 개정 | (a) `surface.list`의 무시되는 `pane_id`를 pane마다 보내 workspace 전체 응답을 반복 수집함 (b) 항목별 owning `pane_id`를 읽지 않아 `index_in_pane`가 다른 pane 그룹에서 중복되고 응답이 전 item 실패함 | `app/Sources/Core/CmuxGroupedExecution.swift`, `app/Sources/Core/CmuxControl.swift`, `app/Tests/CoreTests/CmuxGroupedExecutionTests.swift`, `docs/context/cmux-integration.md` | 3, 4 | verified | 재실행: `cd app && swift test` → 630 tests 0 failures (드라이버, 직전 629) · 실기기 E2E A/B/C PASS (드라이버 2026-09-01, 수정 전 A는 3/3 실패 — red 실관찰) · surface.list pane_id 무시 실측 반영 | — |
| 5 | placement와 grouped execution의 비측정 경계·fallback·retry/partial failure·manual corpus를 영구 문서와 새-terminal checklist에 기록하고, extension no-change 및 source-audit 범위를 닫는다. | 문서·수동 검증 | 이번 경로의 pane N>8, fixed workspace identity, grouped command bytes, result/order 수동 oracle이 checklist에 없음 | `docs/new-terminal-checklist.md`, `docs/context/cmux-integration.md`, 필요 시 `CLAUDE.md`의 새 비자명 제약만 최소 갱신, `docs/context/testing.md` 확인 | 3, 4 | verified | 드라이버 문서 검수 통과 — 9-method 갱신·placement 결정 항목·매트릭스 3행·수동 oracle·CLAUDE.md 최소 갱신 확인 | — |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶이고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다. 승격 칸에는 커밋 해시를 적는다
- `의존`: 다른 항목의 계약(시그니처·불변식·생성물·호출 순서)을 전제하면 그 번호를 적는다. 그 항목에 정정(A′)이 오면 이 항목의 근거를 다시 낸 뒤에야 최종 리뷰에 들어간다
- `확정 결함`: 설계 리뷰·판정에서 이 항목으로 확정된 결함이 여럿이면 처방 산문과 분리해 `(a) … (b) …`로 열거한다 (하나뿐이면 — 항목 문장이 곧 결함이다). 배정문은 이 라벨을 인용한다 — 「이번 배정은 (a)(b), (c)는 후속」. 열거가 검증자 스레드·스크래치패드에만 있으면 세션과 함께 사라지고, 명세에 열거가 없으면 배정 전 자기 대조를 성실히 해도 빠진 결함이 보이지 않는다(실사고)
- 판정이 항목을 다시 열면 행을 고치지 말고 개정 항목으로 잇는다 — 같은 항목의 개정은 prime(`6′`), 형제 부류나 prime 소진 뒤는 letter(`6a`), 식별자는 재사용하지 않는다(append-only 표가 모호해진다). **선행 행의 상태는 그 승격에 대한 마지막 판정이지 종결이 아니다 — 부류의 종결은 체인 끝 항목의 상태가 나타낸다.** 이 규약 없이 표를 처음 읽으면(cold review·재개 브리핑) 개정된 행들이 미해결로 보인다
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`
- `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다. `verified`(드라이버 근거 대조)·`cleared`(증분 리뷰에서 범위 내 확인)·`agreed`(최종 리뷰 또는 cold review)·`dropped`(중단 결정)는 드라이버의 결정이고, 드라이버가 문구를 지정하면 에이전트가 그대로 적는다
- 근거 칸에는 **재실행 가능한 것**만: 명령과 결과 줄, 테스트 이름과 수를 낸 스크립트 경로. "확인했다"도, "이 함수가 이걸 읽어서 저렇게 한다"는 메커니즘 설명도 근거가 아니다 — 1행이 기준이다

## 결정 원장

append-only — **첫 승격 이후부터**다(첫 승격 전의 R0 초안은 아직 인용된 판정이 없으므로 재작성해도 된다). 결정의 이유, 기각한 반박과 근거, 잔여 불확실성 — 코드 서술은 여기에도 넣지 않는다. 기존 행을 고치지 않고 새 행을 더한다. `유형`은 결정 주체(`사용자`/`드라이버`)다. **행을 적는 손은 구현자여도 행의 발행은 드라이버다** — 두 유형 모두 드라이버가 문구를 지정한 것만 적고, 구현자는 스스로 행을 추가하지 않는다(구현자 발의는 「열린 질문」에 적어 처분을 기다린다). `claimed`가 상태의 구현자 상한인 것과 같은 축이다. **`사용자` 행은 배경 원천·검증자 권고와 어긋나도 우선하고, 새 `사용자` 행으로만 뒤집힌다** — 배경 소스에 적힌 내용을 사용자가 이 루프에서 결정·수정·취소한 것이 여기 남는다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| U1 | 사용자 | pane geometry의 실측 범위가 N≤8이고 batch cap은 25인데 pane default가 열려 있음 | arrangement 기본값은 pane per item으로 고정한다; N≤8은 layout fan-out, N=9∼25는 같은 grouped 실행에서 tab-per-item으로 폴백하여 미측정 pane을 만들지 않는다. over-8을 거부하거나 미측정 split을 시도하지 않는 이유는 cap 범위 안에서 측정된 tab 경로가 있고 visible truncation보다 안전한 보수 경로이기 때문이다. | 사용자 결정 2026-09-01 · 이슈 #69 · 이슈 #68 item 9의 N≤8 geometry와 batch cap 25 | found fixed-name pane의 split은 U4로 고정하고 placement 경로 선택은 D3으로 기록한다 |
| U2 | 사용자 | window identity를 유지하면 이름 기반 fixed-name 계약을 만들 수 없음 | identity는 **workspace 수준만** — always-new / fixed-name. window identity level은 v1에서 제외한다(`#70`의 send-time picker와 함께 재검토). 이번 request에는 placement field를 넣지 않고, workspace-per-item arrangement는 workspace identity와 결합하지 않는다(그 arrangement의 컨테이너는 항상 현재 window이다). | 사용자 결정 2026-09-01 (window identity 제외 선택) · 드라이버 실측 2026-09-01: `window.create`는 `title`을 무시하고 응답이 `window_id`/`window_ref`뿐이며, `window.list` 필드는 id·index·key·ref·selected_workspace_id/ref·visible·workspace_count가 전부라 find-by-name의 대상 이름 표면이 없다 | cmux가 window 이름 표면을 얻으면 재검토 |
| U3 | 사용자 | `storage.sync`에 placement를 넣으면 머신별 live cmux window/workspace와 계정 동기화 상태가 섞임 | preset은 app-owned machine-local `UserDefaults`에 두고 setup window의 cmux 전용 section에서만 편집한다; extension storage와 cmux settings file은 저장 원천에서 제외한다. | 사용자 결정 2026-09-01 · `app/Sources/Core/BaseDirectory.swift` 선례 · `CLAUDE.md` base-directory/app ownership rule | D2에서 key, parser, 저장 UX를 처분한다 |
| U4 | 사용자 | found fixed-name workspace에는 layout을 적용할 수 없어(create 전용) pane-per-item의 pane 생성 수단이 문제 | found 케이스는 **target 지정 균형 `surface.split`**으로 pane을 유지한다. 대상은 found workspace의 `pane.index` 0 pane의 첫 surface(결정론적 루트 — activeness 추정 금지)다. 재귀 규칙은 현재 surface를 깊이 d에서 d 짝수=right/홀수=down으로 분할하고(found 루트는 이미 절반 폭이므로 depth 1=down부터), 원 surface가 `ceil(n/2)`개·응답의 새 surface가 `floor(n/2)`개 leaf를 재귀 담당한다. item↔surface 매핑은 split 응답의 `surface_id`를 순서대로 수집한 것이 정본이다(layout 경로의 `pane.list` 열거와 달리 응답이 직접 준다). found+pane도 N>8이면 tab-per-item으로 폴백한다(U1과 동일 규칙). | 사용자 결정 2026-09-01 · 드라이버 실측 2026-09-01 N∈{3,5,8} + issue #68 item 5의 N=4: 기존 pane(1160×1382pt)은 전 케이스 불변, 대상 서브트리는 균형 분할(N=8에서 8×580×345.5pt 완전 균등, N=3에서 580×691 둘+1160×691 하나), `pane.index`도 전 케이스에서 leaf 순서와 일치(주 매핑은 응답 수집) | N∈{2,6,7}의 균형 순서는 동일 재귀 규칙의 미실측 지점(같은 조각의 조합) |
| D1 | 드라이버 | Q1: fresh default와 fixed-name 파싱·매칭이 분산될 위험 | fresh 기본 = workspace × always-new × pane-per-item. fixed-name의 빈 이름은 **단일 파싱 지점에서 always-new로 해석**한다(`Terminal(storedValue:)` 선례 — 소비자 분산 방지, `Terminal.swift:10-14`). 매칭은 `has_custom_title == true`인 workspace의 `custom_title`과 저장 이름의 Swift `==`(canonical equivalence가 NFC/NFD 흡수), 다중 매치는 `index` 최소. 조회는 무주소 `workspace.list`(현재 window 범위) — 전 window 검색은 하지 않는다(unaddressed create와 같은 현재-window 축). | 드라이버 실측 2026-09-01: `workspace.list` 응답에 `custom_title`/`has_custom_title`/`index`가 있고 `window_id` 주소 지정을 받으며 무주소 호출은 현재 window 것을 반환 | 없음 — Q1 처분 완료 |
| D2 | 드라이버 | Q3: preset 저장·해석·적용 시점이 여러 소비자에 흩어질 위험 | 저장은 개별 `UserDefaults` 키(raw string, `cmuxPlacement` 접두), 해석은 Core의 **단일 파싱 지점**이 unknown 값을 기본값으로 폴백(`Terminal` 선례). UI는 terminal 라디오와 같은 즉시 저장 — explicit apply 없음. | `Terminal.swift:10-14`의 단일 파싱 지점 규칙 · `Settings.swift:20-55`의 baseDirectory/terminal 저장 패턴 | 없음 — Q3 처분 완료 |
| D3 | 드라이버 | Q4: placement 경로가 response 밖에서 사라질 위험 | placement 경로 선택(layout create / found split / tab 폴백 / N>8 폴백)은 per-item timeline의 step과 `checkoutLog`로 명시 기록하고 응답 계약은 바꾸지 않는다. | `HostServer.swift:200-217`의 timeline 계약 | 없음 — Q4 처분 완료 |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점 전체. 미검사 항목을 비워 두지 않는 것이 이 표의 목적이다. 세 열뿐이다 — 셋째 열은 코드로 알 수 없는 이유 한 절이거나 `파일:행`이다. 판정이 안전이고 그런 이유가 없는 대상은 한 행에 나열해 합친다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `app/Sources/Core/Request.swift` · `BatchProtocolTests.swift` | 처리됨(항목 1·4; legacy fallback 유지) | `Request.swift:250-366` — 전체 validation 뒤 optional grouped hook이 검증된 순서의 `[ResolvedRequest]`를 한 번 받고, 없으면 기존 per-item `run`을 사용함; `testBatchGroupedHookResultCountMismatchFailsEveryItem`가 결과 수 불일치에서 모든 item을 closed로 만드는 기존 response branch를 고정함 |
| `app/Sources/Core/CmuxPlacement.swift` · `CmuxPlacementTests.swift` | 처리됨(항목 1) | `CmuxPlacement.swift:1-563` — workspace-only preset parser와 measured layout/found-split/tab-fallback/workspace-per-item plan value가 실행부 없이 고정됨 |
| `app/Sources/Core/CmuxControl.swift` · grouped execution parameter builders | 처리됨(항목 3) | `CmuxControl.swift:3-11,268-275,362-402` — 새 RPC 이름과 명시 target parameter를 한 곳에서 만들고, legacy `cmuxWorkspaceCreateParameters()`는 `focus:true` shape를 유지함; keyed `operation_id` retry 주석은 #68 item 11·13 계약을 반영함 |
| `app/Sources/Core/CmuxGroupedExecution.swift` · `workspace.list` | 처리됨(항목 3) | target 없음(D1의 현재-window 계약); response `workspaces[]`와 각 항목 `id`·`index`·`custom_title`·`has_custom_title`; 근거: 드라이버 실측 2026-09-01 (배정문 인용) |
| `app/Sources/Core/CmuxGroupedExecution.swift` · `workspace.create` | 처리됨(항목 3) | target 없음(U2의 current-window 계약); params `focus`·`layout`(`direction`·`children`·leaf `pane`/`surfaces`/`type`/optional `command`)·`operation_id`·optional `title`; response에서 `workspace_id`·focused-leaf `surface_id`를 읽음; 근거: issue #68 item 7·12·13 및 드라이버 실측 2026-09-01 (배정문 인용) |
| `app/Sources/Core/CmuxGroupedExecution.swift` · `pane.list` | 처리됨(항목 3) | target `workspace_id`를 명시하고 response `panes[]` 각 항목의 `id`·`index`를 읽음; `pane_id`는 읽거나 보내지 않음; `workspace_id` target은 실측 없음 — 드라이버 실측 요청; response 항목 근거: 드라이버 실측 2026-09-01 (배정문 인용) |
| `app/Sources/Core/CmuxGroupedExecution.swift` · `surface.list` | 처리됨(항목 3·4′) | target은 `workspace_id`만 명시하고 무시되는 `pane_id`는 보내지 않음; response `surfaces[]` 각 항목의 `id`·`index_in_pane`·owning `pane_id`를 읽어 pane별 grouping/order를 만듦; 근거: 드라이버 실측 2026-09-01 (배정문 인용) |
| `app/Sources/Core/CmuxGroupedExecution.swift` · `surface.split` | 처리됨(항목 3) | target `surface_id`와 `direction`을 매 호출 명시(U4); response 최상위 `surface_id`를 읽음; `workspace_id`·무주소 fallback은 사용하지 않으며 split retry 없음; 근거: issue #68 item 2·5 및 드라이버 실측 2026-09-01 (배정문 인용) |
| `app/Sources/Core/CmuxGroupedExecution.swift` · `surface.create` | 처리됨(항목 3) | target `workspace_id`·`pane_id`를 매 호출 명시; response 최상위 `surface_id`를 읽고 `pane_id`·`workspace_id`는 소비하지 않음; create retry 없음; 근거: issue #68 item 2·8 및 드라이버 실측 2026-09-01 (배정문 인용) |
| `app/Sources/Core/CmuxGroupedExecution.swift` · `surface.send_text` | 처리됨(항목 3·4) | target `surface_id`와 `text`를 매 호출 명시; response의 optional `queued`를 읽음; 기존 send gate 뒤에만 보내고 retry 없음; `deadlineExceeded`를 item 전 확인해 budget 이후 item은 `CommandError.badRequest`로 닫음; 근거: issue #68 item 6 |
| `app/Sources/Core/TerminalRunner.swift` · `debug.terminals` gate / `cmuxRPC` door | 처리됨(항목 3) | grouped `shellGate`가 기존 `cmuxAwaitShellReading`을 재사용하며 `debug.terminals`에 빈 params를 보내고 response `terminals[]`의 `surface_id`·`tty`를 읽음; `TerminalRunner.swift:393-414,489-520,567-613`의 pinned `cmuxRPC` context와 issue #68 item 6 근거를 유지하며 tty는 readiness 신호가 아님 |
| `app/Sources/Core/TerminalRunner.swift` · legacy `runInCmux` | 안전·시그니처 불변(항목 3) | `TerminalRunner.swift:616-692` — placement 판단은 새 plan executor에만 있고 legacy 단일 create/send 흐름의 public signature는 유지됨 |
| `app/Sources/Core/ClaudeInjector.swift` · `BatchDeliveryTests.swift` | 안전·재사용(항목 3) | `ClaudeInjector.swift:4-25,976-1045` — surface UUID handle과 기존 delivery pipeline을 유지해야 하며 새 입력 알고리즘은 범위 밖 |
| `app/Sources/App/Settings.swift` | 처리됨(항목 2) | `Settings.swift:58-77` — 세 개의 `cmuxPlacement` raw key만 `UserDefaults`와 연결하고 비문자열은 `String(describing:)`로 Core parser에 전달함; placement 해석·기본값·검증은 없음 |
| `app/Sources/App/SetupWindowController.swift` · `app/Sources/App/Theme.swift` · App layout/redraw tests | 처리됨(항목 2) | `SetupWindowController.swift:997-1098,1338-1377,1472-1553` — cmuxSection 안에만 controls를 만들고, radio tag의 raw binding 외에는 Core parser를 해석 라벨 갱신 한 곳에서만 호출함; 기존 Theme palette와 refillable/redraw/settle 경로를 재사용함. F9 이후 redraw fixture는 `control.baseDirectoryEdited` role로 baseDir 필드를 특정하고, placement field의 동일한 reparent/draft 계약은 `testPlacementNameFieldReparentsAndKeepsAnUnstoredDraftAcrossRedraw`로 고정함; F10은 language rebuild 중 `cmuxPlacementNameEdited` end-edit action만 차단하고 `capturePlace`/`restore`의 stored-field reparent 경로는 유지함 |
| 다섯 `app/Sources/App/Resources/*/Localizable.strings` | 처리됨(항목 2) | `app.section.cmux.placement.*`·`app.cmux.placement.*` 키를 다섯 catalogue에 동일하게 추가했고 `plutil -lint`가 다섯 파일을 모두 OK로 반환함 |
| `app/Sources/App/HostServer.swift` · `HostProtocolTests.swift` · `app/Sources/Core/CmuxGroupedExecution.swift` · 관련 Core tests | 처리됨(항목 4) | `HostServer.swift:211-307,316-418` — `terminal.cmuxChannel`과 `json["items"]`일 때만 local raw preset→Core parser→UUID plan→주입 가능한 grouped executor를 선택하고, per-item labeled timeline·placement/성공/실패 step 및 `checkoutLog`를 남김; Core deadline seam은 request-arrival monotonic budget을 소비하고, `HostProtocolTests`가 cmux admission·timeline·non-cmux·legacy 경계를 고정함 |
| `extension/defaults.js` · relay/native host | 안전·변경 없음 | `buildListBatchRequest`가 이미 top-level `command`+`items[]`를 만든다; placement는 app-owned이고 extension은 이번 범위 밖 |
| `docs/new-terminal-checklist.md` | 처리됨(항목 5) | `docs/new-terminal-checklist.md:87-106,150-168`에 placement 기본값·N>8 fallback·fixed-name found/not-found·layout byte/order·background input·deadline·setup·stable/NIGHTLY oracle을 추가함; N∈{2,6,7} found-split 순서·N=25 대량 tab·다중 window `workspace.list` 범위는 미측정 경계로 남김 |
| `docs/context/cmux-integration.md` · `docs/context/testing.md` | 처리됨(항목 5) | cmux 문서에 9개 app-issued RPC와 layout/found-split/UUID/deadline 결정을 추가하고, placement matrix 서문을 현재 동작으로 갱신함; source-audit와 driver-only gate 범위는 유지하며 N∈{2,6,7}, N=25, 다중 window `workspace.list`는 원장 잔여와 일치하게 미측정으로 표시함 |
| `CLAUDE.md` cmux bullets | 처리됨(항목 5) | 기존 cmux socket/retry bullet에 UUID `operation_id`, list 항목 `id`와 top-level create `surface_id`의 구별, layout leaf 1023 UTF-8-byte ceiling만 연결하고 상세 결정은 `docs/context/cmux-integration.md`에 둠 |
| `README.md` Development · `app/Package.swift` · `install.sh` · `app/e2e.sh` | 안전·비목표 | Development commands는 이미 정본이고 이번 변경은 새 terminal/channel이 아니며 e2e는 실제 terminal을 열지 않는다는 기존 경계가 있음 |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 차단·수정·실측 줄은 에이전트가, 판정 줄은 드라이버가 지정한 문구를 적는다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — <계획 커밋 해시> · 승격 <커밋 후 기입> · 리뷰 완료 · 왕복 1 · 원문 없음

- 반박: window fixed-name은 이름 표면 부재로 불성립(드라이버 실측); found fixed-name + pane-per-item의 pane 생성 수단 미정; 배치 점검 표 3행이 구현자 샌드박스 관측으로 채워짐; 기준 트리 표기 오기.
- 처리: U2 재작성(window identity 제외) · U4 추가(found는 target 지정 균형 split) · D1∼D3 추가(Q1·Q3·Q4 처분) · 점검 표를 드라이버 실측으로 정정 · Q1∼Q4 삭제.
- 실측: `node --test` exit 0, 252/252 (구현자) · 드라이버: window.create title 무시·window.list 이름 필드 0건 · 균형 split N∈{3,5,8} 기하 계약 성립·기존 pane 불변 · `workspace.list`의 custom_title/window_id 주소 확인.
- 판정: "이 계획으로 시작하는 데 합의한다 — window identity 제외와 found-split 계약 반영을 전제로." (드라이버, R0)

### R1

#### 리뷰 1 — 증분 · 5cd0065 · 리뷰 완료 · 왕복 1 · 원문 없음

- 차단: 항목 1의 확정 결함 (a)(b) 차단 여부와 새 grouped/placement 표면의 우회를 검토함.
- 수정: runBatch hook과 placement plan이 테스트로 고정되었고, 결과 수 불일치 브랜치 테스트는 후속 항목 4 큐로 남김.
- 실측: 드라이버 게이트가 clone에서 swift test 602 tests, 0 failures를 확인함(기준선 587); node --test는 252/252임.
- 판정: "항목 1 차단 (a)(b) 막힘 확인 — runBatch hook과 placement plan이 테스트로 고정, 새 표면 우회 없음. 잔여: runBatch 결과 수 불일치 브랜치의 테스트는 그 브랜치를 소비하는 항목 4에서." (드라이버, R1)

#### 리뷰 2 — 증분 · c16e78f · 리뷰 완료 · 왕복 1 · 원문 없음

- 차단: 항목 3 확정 결함 (a)∼(d)와 grouped 실행 전 경로의 새 표면 우회 여부를 대조함.
- 수정: grouped 실행 전 경로를 테스트 11건과 드라이버 실서버 실측으로 고정하고, enumeratedSurfaceIDs의 leafItemOrder 의존은 잔여 비차단으로 남김.
- 실측: 드라이버 게이트가 clone에서 swift test 613 tests, 0 failures를 확인하고 layout+title+operation_id·keyed 반복·UUID operation_id·list 항목 `id`를 실서버에서 확인함.
- 판정: "항목 3 차단 (a)∼(d) 막힘 확인 — grouped 실행 전 경로가 테스트 11건과 드라이버 실서버 실측으로 고정, 새 표면의 실효 우회 없음. 잔여(비차단): enumeratedSurfaceIDs는 leafItemOrder가 identity라는 현 plan 생성기 계약에 기댄다." (드라이버, R1)

#### 리뷰 3 — 증분 · 78d62fe · 리뷰 완료 · 왕복 1 · 원문 없음

- 차단: 항목 2 확정 결함 (a)(b)와 F10 draft 저장 회귀를 대조함.
- 수정: raw 3키·Core 단일 파서·즉시 저장·5로케일을 유지하고, role 기반 redraw fixture와 rebuild 중 placement end-edit 차단을 반영함.
- 실측: 드라이버 게이트가 clone에서 swift test 622 tests, 0 failures를 확인함(직전 613); F10 red 1 failure 후 수정 green을 확인하고 5종 로케일 키 패리티를 통과시킴.
- 판정: "항목 2 차단 (a)(b) 막힘 확인 — 저장은 raw 3키·해석은 Core 단일 지점·즉시 저장·5로케일이 테스트 9건으로 고정, F10의 draft 저장 결함은 red 실관찰 후 수정. 잔여(비차단): identity raw 리터럴(\"always-new\"/\"fixed-name\")이 App에 문자열로 존재 — 드리프트 시 parse가 always-new로 폴백하는 안전 방향." (드라이버, R1)

#### 리뷰 4 — 증분 · 84e1fee · 리뷰 완료 · 왕복 1 · 원문 없음

- 차단: 항목 4 확정 결함 (a)(b)와 grouped 통합 경계를 대조함.
- 수정: cmux+items[] grouped hook, admission 선확보·전량 반납, deadline seam, per-item timeline·경로 기록을 테스트로 고정함.
- 실측: 드라이버 게이트가 clone에서 swift test 629 tests, 0 failures를 확인하고 F11 인자 순서·F12 병합 규칙 기대값 교정을 반영함; node --test는 252/252임.
- 판정: "항목 4 차단 (a)(b) 막힘 확인 — cmux+items[]만 grouped 훅, admission 선확보·전량 반납, deadline seam, per-item timeline·경로 기록이 테스트로 고정. 잔여 없음." (드라이버, R1)

## 열린 질문

없음 — Q1∼Q4는 U4와 D1∼D3으로 처분되었다.

원 요구 충족 후 발견된 마이너·에지케이스 방어 후보는 여기 적립한다(즉시 배정 금지) — 사용자 대화로 포함/이슈/기록 중 처분이 정해지면 그 결과를 원장에 남기고 지운다.
