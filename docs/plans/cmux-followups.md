# cmux-followups

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: `/Users/choongjaelee/Codes/terminal-checkout-cmux-followups-work`
- 시작 커밋: `e2e9c43fa842a1571ee76706048766b82cc0afa9`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/cmux-followups-review` (`worktree-cmux-followups-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-cmux-followups-work` (`cmux-followups-work`)
- 현재: R1 · 마지막 승격 40eb4f2 · 리뷰 중 없음 · A cleared, B cleared, C·D·E verified (네 게이트는 드라이버가 실행함)
- 최근 검증자 판정: "E가 핀 nil 경로를 닫아 채널 동일성이 성립 — 증분 리뷰 재판정" · 원문 `/tmp/cmux-spark.qH3zbk/`

이 파일은 **실행한 계획과 실행할 계획의 기록**이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실. 코드 수정 과정을 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다. 결정이나 질문이 특정 동작에 걸리면 한 절과 `파일:행`으로 끝낸다. 이 템플릿에 없는 소절을 만들지 않는다 — 테스트 설계는 테스트 파일이 말한다.

## 배경 — 확인한 원천

문제를 파악하며 확인한 영구 소스만 — Slack 스레드·이슈·PR·설계 문서처럼 세션이 끝나도 남는 것. 스크래치패드 경로는 여기 두지 않는다. 원천의 내용과 이 루프의 결정이 어긋나면 결정 원장의 `사용자` 행이 우선한다 — 원천을 읽었으면 원장에서 사용자가 결정·수정·취소한 것을 이어서 확인해라.

- [기준 커밋 `e2e9c43`](../../commit/e2e9c43) — 1024바이트 명령 전송 게이트와 cmux 채널·포인터 plumbing의 red 테스트 및 Core 구현을 포함하고, App의 NIGHTLY 배선은 아직 컴파일되지 않는 baseline이다.
- [`CLAUDE.md`](../../CLAUDE.md) — cmux는 `rpc`만 사용하고, TCC·소켓·raw mode·설정 파일 비쓰기·새 터미널 소탕 원칙을 따른다.
- [`docs/new-terminal-checklist.md`](../new-terminal-checklist.md) — Core·App·설치 스크립트·README·로케일 및 실기기 검증에 흩어진 터미널 touch point의 정본이다.
- [`docs/context/cmux-integration.md`](../context/cmux-integration.md) — cmux socket-control, RPC, 재시도, workspace, tty, surface read의 설계 이유와 기각한 대안을 보존한다.
- 드라이버 확정 측정 — Darwin 25.4.0 pty 프로브에서 canonical mode tty는 읽히지 않은 줄을 정확히 1024바이트만 보관하고 초과분과 CR을 조용히 버리며 쓰는 쪽은 전량 accepted였다. 1023B+CR은 온전히 생존했고, 실사고는 ∼1400B 명령이 1024B로 잘려 미제출된 것과 커널 echo가 프롬프트 앞에 한 번 더 그려진 것이다.
- 드라이버 확정 측정 — `workspace.create`에는 `window_id?`·`cwd?`·`title?`·`focus`만 있고 command 파라미터가 없으며, cmux의 `new-workspace --command`도 `unescapeSendText`를 통과하는 타이핑 경로다.
- 드라이버 확정 측정 — stable은 `com.cmuxterm.app` 및 `/Applications/cmux.app`, NIGHTLY는 `com.cmuxterm.app.nightly` 및 `/Applications/cmux NIGHTLY.app`이며 버전은 각각 `0.64.22`와 `0.64.22-nightly.3302761607201`이다. 번들 CLI는 각 번들의 `Contents/Resources/bin/cmux`다.
- 드라이버 확정 측정 — stable 포인터는 `$HOME/.local/state/cmux/last-socket-path`, NIGHTLY 포인터는 `$HOME/.local/state/cmux/nightly-last-socket-path`이고 socket basename은 재시작·버전에 따라 바뀐다. 두 CLI 모두 네 채널 파일명을 내장하며, 양 서버가 떠 있을 때 unpinned NIGHTLY CLI가 stable 서버에서 PONG을 받을 수 있고 `CMUX_SOCKET_PATH` pin은 양쪽에서 존중된다.
- 드라이버 확정 측정 — 두 채널은 `$HOME/.config/cmux/cmux.json`을 공유하고 automation 도움 동작도 공용이다. 앱은 이 파일을 쓰지 않고 열기와 복사만 제공한다.

## 목표

cmux가 shell을 읽기 전에도 명령 payload를 전량 보존하고 제출하도록 하며, 읽기 시작하지 않은 채 canonical limit을 넘는 경우에는 tail을 버리는 대신 눈에 보이는 실패를 반환한다.
stable cmux의 기존 동작은 대기 추가 외에는 유지하고, `cmux NIGHTLY`를 다섯 번째 선택지로 설치 감지·선택·실행·상태 표시까지 완성한다.
각 채널의 CLI, socket pointer, `CMUX_SOCKET_PATH` 흐름이 한 요청 전체에서 섞이지 않게 하고, 모든 cmux RPC 호출 지점과 다섯 Terminal 분기를 전수 대조한다.
README·CLAUDE.md·검사목록·context·설치 preflight·확장 설명이 이 계약과 NIGHTLY를 반영하고, 종결 단계에서 드라이버의 네 게이트와 양채널 실기기 검증을 통과한다.

## 완료의 정의

- 반드시 재현해 막아야 하는 실패: `workspace.create` 직후 canonical mode이고 shell이 아직 읽지 않는 cmux pane에 1024바이트를 넘는 `command+CR`을 보내면 writer는 성공해도 정확히 1024바이트 뒤의 tail과 CR이 폐기되어 명령이 잘린 채 미제출된다. 수정 후에는 raw mode가 관측될 때만 전 payload를 보내고, deadline에 raw mode가 아니면 payload가 1024바이트 이하일 때만 제한적 전송하며 초과 payload는 `surface.send_text`와 CR 전에 가시적으로 거부한다.
- acceptance oracle: 드라이버가 `cd app && swift test`, `node --test`, `./app/build.sh`, `./app/e2e.sh`를 실행하고 각 원문 결과를 보존한다. 구현자는 이 네 게이트를 실행하지 않으며, 테스트 reporter 출력 grep이나 샌드박스 실패를 green 또는 회귀로 해석하지 않는다. 드라이버는 stable/NIGHTLY 양채널에서 ∼1024B 초과 명령, NIGHTLY workspace 생성, claude typed input을 실기기로 확인한다.
- 코퍼스 범위: `app/Sources/Core/CmuxControl.swift`, `app/Sources/Core/TerminalRunner.swift`, `app/Sources/Core/ClaudeInjector.swift`, `app/Sources/App/{PermissionChecker.swift,Settings.swift,SetupWindowController.swift}`, `app/Tests/**`, `install.sh`, `README.md`, `CLAUDE.md`, `docs/new-terminal-checklist.md`, `docs/context/cmux-integration.md`, `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`; `cmuxRPC` 호출 전체, `Terminal`의 5개 case 전체, 2개 cmux channel 전체가 식별자다.
- 원자성·부분 실패·롤백 경계: `workspace.create`는 비멱등이므로 연결 단계에 도달하지 않았다고 타입으로 확인된 첫 실패에만 채널별 cmux launch와 한 번의 retry를 허용하고, server-side effect 가능성이 있는 실패는 재시도하지 않는다. workspace가 만들어진 뒤 canonical 초과로 거부하면 `surface.send_text`는 호출하지 않으며 workspace rollback은 범위가 아니다. NIGHTLY 실패를 stable로 fallback하지 않는다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

이 루프가 막는 실패를 일으킬 수 있는 행위자(사람·프로세스·시스템)와 그 능력을 열거한다. **발견을 배정하려면 어느 행위자가 그 결함에 닿는지 이름을 대야 한다** — 모델 밖 행위자가 필요한 발견은 기본이 잔여(원장 기록, 배정 없음)다. 행위자를 새로 들이는 것은 범위 변경이라 사용자 승인이 필요하다. 해당 없으면(순수 로직 루프) N/A + 근거.

- 버튼을 누르는 사용자: stable 또는 NIGHTLY 중 어느 채널이든 선택하고, shell이 느리거나 아직 canonical mode인 새 workspace에 1024바이트 초과 command를 보낼 수 있다.
- stable/NIGHTLY cmux 서버 및 각 번들의 CLI: 두 서버가 동시에 실행되어 unpinned discovery를 교차 채널로 해석할 수 있고, 재시작으로 pointer target basename을 바꿀 수 있다.
- 같은 uid의 다른 프로세스: 기존 cmux automation socket 신뢰 경계 안에서 socket에 접근할 수 있다. 이 경계를 좁히는 것은 범위가 아니다.
- shell 초기화 프로세스: shell integration이 늦거나 없고, ZLE 없는 shell처럼 raw mode가 끝내 관측되지 않는 상태를 만들 수 있다.

## 비목표 — 건드리지 않는다

- `extension`의 terminal 선택·명령 계획·preset semantics: 터미널 선택의 단일 source of truth는 App이며, 확장은 terminal 값을 지정하지 않는다.
- `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`의 `extDescription`: 비목표 — NIGHTLY는 cmux 제품의 채널이지 다섯 번째 제품이 아니라 한 줄 제품 나열은 그대로 둔다(사용자 문구 churn 회피, 드라이버 결정 D8).
- `$HOME/.config/cmux/cmux.json` 쓰기와 `cmux settings automation` 위임: setup action은 기존 파일 또는 폴더를 열고 automation fragment를 clipboard에 복사하기만 한다.
- `TerminalSessionHandle.cmux`의 `workspaceID` 제거와 `cmuxWorkspaceIdentifiers`의 두 식별자 요구 완화: 이슈 #62로 이연된 소유자 결정이며 이번 루프에서 바꾸지 않는다.
- cmux RPC 대신 `cmux send`·`--command`·`new-workspace --command`를 통한 payload 전달: newline과 backslash를 재작성하는 타이핑 경로를 선택하지 않는다.
- cmux에 대한 새 TCC·Accessibility permission과 stable 사용자의 대기 외 동작 변경: NIGHTLY는 stable로 fallback하지 않고 자기 bundle과 pointer를 사용한다.
- `cmux NIGHTLY` 라디오 label의 locale key 추가: 제품명 자체인 `cmux NIGHTLY`는 iTerm2·WezTerm·Warp·cmux와 같은 고유 제품명이라 비지역화한다.

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

0라운드 이후 이 절과 「완료의 정의」에 항목을 **더하는 것은 범위 변경이다** — 결정 원장의 `사용자` 행 없이 추가하지 않는다(드라이버·검증자 발의는 비용 추정과 함께 사용자 승인 후). 드라이버가 스스로 쓴 기준을 스스로 집행하는 것이 일감 자가 생산의 뿌리다.

- cmux `surface.send_text`에 도달하는 command payload는 입력의 UTF-8 바이트 순서를 보존해야 하며, `command+CR`은 1024바이트 canonical 경계를 넘을 때 잘리거나 부분 제출되어서는 안 된다.
- shell이 raw mode로 읽는 것이 확인되기 전에는 command 또는 CR을 보내지 않는다. timeout fallback은 `payloadByteCount <= darwinCanonicalLineLimit`인 경우에만 허용하고, 초과 시에는 아무 send도 하지 않고 가시적 실패를 반환한다.
- channel identity는 결정론적이다. channel pointer가 존재하고 target socket이 살아 있으면 `workspace.create`, readiness, `debug.terminals`, `surface.send_text`, `surface.read_text`, setup `ping`을 포함한 모든 cmux RPC가 그 target을 `CMUX_SOCKET_PATH`로 pin한다. pointer target은 매 재시도에 다시 읽으며 stable과 NIGHTLY 사이 fallback을 하지 않는다.
- 앱은 cmux settings file을 만들거나 수정하지 않는다. automation fragment의 copy/open은 상태를 바꾸지 않는 도움 동작이다.
- stable만 설치된 사용자의 기존 command 실행과 cmux input delivery semantics는 raw-mode 대기가 추가되는 것 외에 바꾸지 않는다. cmux의 control path는 계속 `rpc` 네 method뿐이다.
- `.cmux` session handle은 `surfaceID`와 `workspaceID`를 모두 보존하고, `Terminal`은 `cmux`와 `cmux-nightly`를 distinct rawValue로 유지한다. NIGHTLY는 `com.cmuxterm.app.nightly`와 `cmux NIGHTLY.app` 및 NIGHTLY pointer만 사용한다.
- 다섯 terminal을 추가하는 모든 default-less switch, radio의 양방향 mapping, cmuxSection의 selected-channel status, install preflight와 사용자 문구를 함께 점검한다. label `cmux NIGHTLY`는 제품명 그대로 둔다.
- 네 게이트의 실행·판정 권한은 드라이버에 있다. 구현자는 `cd app && swift test`, `node --test`, `./app/build.sh`, `./app/e2e.sh`를 실행하지 않고, 환경 실패 원문을 구현 회귀로 반올림하지 않는다.

<재개하는 에이전트가 이 절만 읽고도 경계를 아는 것이 목표다. SKILL.md의 「라운드마다 지키는 것」 중 이 작업에 걸리는 것 + 이 작업 고유의 규칙(재사용해야 할 단일 함수 이름, 바이트가 불변이어야 할 산출물 경로, 실코퍼스 위치 등)>

## 배치 점검 (0라운드)

모드: ultrafast

(`default` 또는 `ultrafast`. 이 줄이 적힌 뒤로는 스킬 인자가 아니라 이 값이 모드를 정한다 — 스킬의 점검 블록이 이 줄을 읽는다.)

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | not-ignored 확인; 0라운드의 두 파일 범위를 지키기 위해 이 라운드에는 수정하지 않음 |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | `git config --get worktree.baseRef` 출력 없음; 기준 HEAD `e2e9c43`를 직접 기록 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-cmux-followups-work` · `cmux-followups-work` · `e2e9c43fa842a1571ee76706048766b82cc0afa9` |
| 리포 오버레이 `.claude/drive-agent-loop.md` — 있으면 경로, 없으면 이번 초안과 함께 작성 | 이번 초안과 함께 작성 |
| 트리마다 의존성 동기화 (기준·작업) | 기준/작업이 같은 단일 worktree라 별도 동기화 없음; 게이트는 드라이버 소유 |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 해당 없음; 드라이버 스크래치패드는 `/tmp/cmux-spark.qH3zbk/` |
| 증분 리뷰 소요(분) — 첫 세 번 | 미요청 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| A | 1024바이트 초과 cmux command를 안전하게 보내는 raw-mode/canonical-limit 게이트를 baseline 검증과 함께 마무리 | 명령 전송 게이트 | — | `app/Sources/Core/CmuxControl.swift`, `app/Sources/Core/TerminalRunner.swift`, `app/Tests/CoreTests/CmuxTests.swift` | — | cleared | 증분 리뷰(드라이버, 40eb4f2): 낡은 대역 제거로 컴파일 복구 — 차단 없음 | 40eb4f2 |
| B | cmux NIGHTLY를 App의 다섯 번째 terminal 선택지로 배선하고 baseline의 App 컴파일 미완료를 복구 | NIGHTLY App 배선 | (a) `SetupWindowController`에 NIGHTLY를 추가한 뒤 permission/status/pipeline switch가 exhaustive하지 않음 (b) NIGHTLY radio와 양방향 선택 mapping이 부분 배선임 | `app/Sources/App/PermissionChecker.swift`, `app/Sources/App/Settings.swift`, `app/Sources/App/SetupWindowController.swift`, `app/Sources/Core/Terminal.swift`, `app/Tests/AppTests/CmuxDetectionTests.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Tests/CoreTests/CoreTests.swift` | A (B→A; 같은 channel contract와 실행 handle을 전제) | cleared | 재실행(드라이버, 40eb4f2): swift test 553(1 skip)·node --test 222·app/build.sh·app/e2e.sh 9/9 → 0 실패; 증분 리뷰에서 핀 nil 경로의 채널 혼선 발견 → 항목 E로 승계, E 종료 후 재판정; E가 핀 nil 경로를 닫아 채널 동일성이 성립 — 증분 리뷰 재판정 | 40eb4f2 |
| C | command gate와 두 cmux channel을 사용자 문서·설치 preflight·context의 이유로 일치시키고 fixed socket 판단을 supersede로 기록 | 문서·운영 계약 | (a) README·CLAUDE.md·checklist·설치 preflight가 네 terminal만 말함 (b) 고정 socket/default discovery 설명이 channel pointer 사실과 충돌함 | `README.md`, `CLAUDE.md`, `docs/new-terminal-checklist.md`, `docs/context/cmux-integration.md`, `install.sh` | A·B (C→A·B) | verified | `CLAUDE.md`, `README.md`, `docs/new-terminal-checklist.md`, `docs/context/cmux-integration.md` 반영; `install.sh` NIGHTLY preflight는 40eb4f2에 반영; `git diff --check` 통과; `extension/_locales/**` 미변경으로 extDescription 5개 locale은 D8 불변; 재실행(드라이버, C·D·E 미커밋 트리): swift test 555(1 skip)·node --test 222·app/build.sh·app/e2e.sh → 0 실패 | |
| D | 모든 cmux RPC의 socketPath pin, 모든 Terminal switch, radio 양방향, `cmuxSection`과 `refresh()`의 channel 분기를 전수 소탕 | 전수 소탕 | (a) unpinned CLI discovery는 살아 있는 반대 channel 서버로 갈 수 있음 (b) stable-only status/UI branch가 NIGHTLY 선택에서 잘못된 상태를 그릴 수 있음 | `app/Sources/Core/CmuxControl.swift`, `app/Sources/Core/TerminalRunner.swift`, `app/Sources/Core/ClaudeInjector.swift`, `app/Sources/Core/Terminal.swift`, `app/Sources/App/PermissionChecker.swift`, `app/Sources/App/Settings.swift`, `app/Sources/App/SetupWindowController.swift`, `app/Tests/CoreTests/CoreTests.swift`, `app/Tests/CoreTests/CmuxTests.swift`, `app/Tests/AppTests/CmuxDetectionTests.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift` | A·B | verified | `rg -n 'cmuxRPC\\(' app/Sources --glob '*.swift'`에서 정의 1·호출 8을 확인하고 호출마다 `socketPath:` 전달; `SetupWindowController.swift`의 D1 명시적 channel switch와 refresh·pipeline·radio·install 흐름 정적 대조; `Settings.terminal.cmuxChannel ?? .stable` 미검출; 소탕 표 전 행 재판정; 재실행(드라이버, C·D·E 미커밋 트리): swift test 555(1 skip)·node --test 222·app/build.sh·app/e2e.sh → 0 실패 | |
| E | 포인터가 해석되지 않을 때 cmux 채널 동일성을 보존하고 state·`/tmp` 후보를 순서대로 해석 | 채널 동일성 | (a) nil socket이 unpinned CLI discovery로 번역되어 다른 채널 서버에 닿음 (b) state 포인터만 읽어 `/tmp`의 유효한 후보를 놓침 | `app/Sources/Core/CmuxControl.swift`, `app/Sources/Core/TerminalRunner.swift`, `app/Sources/App/PermissionChecker.swift`, `app/Tests/CoreTests/CmuxTests.swift` | B | verified | `CmuxTests.testCmuxSocketPinDistinguishesPinnedDiscoverAndNoLiveSocket`, `CmuxTests.testCmuxSocketPointerCandidatesPreferStateThenTmpAndRequireALiveTarget` 추가; pin·state→`/tmp` 후보 해석과 세 소비 지점 반영; red 실행은 샌드박스의 Swift manifest/ModuleCache 권한 거부로 테스트 컴파일 전 중단; 재실행(드라이버, C·D·E 미커밋 트리): swift test 555(1 skip)·node --test 222·app/build.sh·app/e2e.sh → 0 실패 | |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶이고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다. 승격 칸에는 커밋 해시를 적는다
- `의존`: 다른 항목의 계약(시그니처·불변식·생성물·호출 순서)을 전제하면 그 번호를 적는다. 그 항목에 정정(A′)이 오면 이 항목의 근거를 다시 낸 뒤에야 최종 리뷰에 들어간다
- `확정 결함`: 설계 리뷰·판정에서 이 항목으로 확정된 결함이 여럿이면 처방 산문과 분리해 `(a) … (b) …`로 열거한다 (하나뿐이면 — 항목 문장이 곧 결함이다). 배정문은 이 라벨을 인용한다 — 「이번 배정은 (a)(b), (c)는 후속」. 열거가 검증자 스레드·스크래치패드에만 있으면 세션과 함께 사라지고, 명세에 열거가 없으면 배정 전 자기 대조를 성실히 해도 빠진 결함이 보이지 않는다(실사고)
- 판정이 항목을 다시 열면 행을 고치지 말고 개정 항목으로 잇는다 — 같은 항목의 개정은 prime(`6′`), 형제 부류나 prime 소진 뒤는 letter(`6a`), 식별자는 재사용하지 않는다(append-only 표가 모호해진다). **선행 행의 상태는 그 승격에 대한 마지막 판정이지 종결이 아니다 — 부류의 종결은 체인 끝 항목의 상태가 나타낸다.** 이 규약 없이 표를 처음 읽으면(cold review·재개 브리핑) 개정된 행들이 미해결로 보인다
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`
- `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다. `verified`(드라이버 근거 대조)·`cleared`(증분 리뷰에서 범위 내 확인)·`agreed`(최종 리뷰 또는 cold review)·`dropped`(중단 결정)는 드라이버의 결정이고, 드라이버가 문구를 지정하면 에이전트가 그대로 적는다
- 근거 칸에는 **재실행 가능한 것**만: 명령과 결과 줄, 테스트 이름과 수, 수치를 낸 스크립트 경로. "확인했다"도, "이 함수가 이걸 읽어서 저렇게 한다"는 메커니즘 설명도 근거가 아니다 — 1행이 기준이다

## 결정 원장

append-only. 결정의 이유, 기각한 반박과 근거, 잔여 불확실성 — 코드 서술은 여기에도 넣지 않는다. 기존 행을 고치지 않고 새 행을 더한다. `유형`은 결정 주체(`사용자`/`드라이버`)다. **`사용자` 행은 배경 원천·검증자 권고와 어긋나도 우선하고, 새 `사용자` 행으로만 뒤집힌다** — 배경 소스에 적힌 내용을 사용자가 이 루프에서 결정·수정·취소한 것이 여기 남는다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | 두 사용자 요구와 종착지 범위가 명시됨 | ∼1024B cmux command truncation 수정과 cmux NIGHTLY 다섯 번째 선택지를 모두 종결하고, 종결 후 PR → automerge → 설치까지 진행한다 | 현재 사용자 요청 | 최종 PR·automerge·설치 결과는 종결 단계에서 드라이버가 확인 |
| D2 | 사용자 | 이 라운드가 구현 라운드로 오인될 위험 | 0라운드는 계획 초안과 `.claude/drive-agent-loop.md`만 작성하고 구현·테스트 실행·커밋 없이 보고 후 정지한다 | 현재 사용자 요청 | 다음 라운드의 배정·승격 시각은 미정 |
| D3 | 드라이버 | 구현자 샌드박스의 Swift 실패를 gate 판정으로 쓰면 안 됨 | `cd app && swift test`, `node --test`, `./app/build.sh`, `./app/e2e.sh` 네 게이트는 모두 드라이버가 실행하고 원문으로 보고한다 | 현재 사용자 요청; 직전 루프의 Swift sandbox 불가 실측 | 네 게이트의 실제 결과는 아직 없음 |
| D4 | 드라이버 | canonical tty가 writer 성공을 전량 수신 증거처럼 보이게 함 | raw mode 전송 대기, deadline의 1024B 이하 제한적 fallback, 초과 payload의 pre-send visible refusal을 계약으로 둔다 | Darwin 25.4.0 pty probe: 1024B 보관, 초과·CR 폐기, 1023B+CR 생존; `e2e9c43` | shell별 raw-mode 전환 시간과 양채널 실기기 결과는 남아 있음 |
| D5 | 드라이버 | unpinned cmux CLI가 stable/NIGHTLY 서버를 교차 선택함 | channel별 bundle CLI와 channel pointer target을 사용하고, 살아 있는 pointer가 있으면 모든 RPC와 ping을 `CMUX_SOCKET_PATH`로 pin한다 | cmux `0.64.22`·`0.64.22-nightly.3302761607201`; pointer path·cross-channel PONG 측정; `e2e9c43` | pointer가 없는 구버전 layout에서 CLI discovery를 허용할지의 기존 compatibility는 코드 계약 안에서만 재확인 |
| D6 | 사용자 | NIGHTLY wiring 중 기존 소유자·제품명 계약이 흔들릴 위험 | `.cmux`의 `workspaceID`와 parser의 `workspace_id`·`surface_id` 요구를 유지하고, label `cmux NIGHTLY`는 비지역화한다 | 현재 사용자 요청; 이슈 #62 이연 결정; 기존 `Terminal`/localization 테스트 경계 | NIGHTLY UI의 실제 layout은 driver 실기기에서 확인 |
| D7 | 드라이버 | 설정 파일 자동 수정은 권한·소유권·성공 판정을 넓힘 | 앱은 shared `cmux.json`을 쓰지 않고 fragment copy와 file/folder open만 한다 | [`docs/context/cmux-integration.md`](../context/cmux-integration.md)와 기존 `CmuxConfigHelp` 계약 | cmux가 향후 외부 automation 설정 API를 제공할 때만 revisit |
| D8 | 드라이버 | NIGHTLY를 확장 설명에 나열할지 | extDescription 5개 locale은 불변 — NIGHTLY는 cmux의 채널이지 별도 제품이 아니다 | R0 설계 리뷰 | 스토어 문구 정책이 바뀌면 revisit |
| D9 | 드라이버 | A만 따로 승격하면 게이트 불가 | A·B는 한 승격으로 묶는다 — App이 컴파일되기 전에는 swift test 자체가 돌지 않아 A의 green을 독립적으로 낼 수 없다 | R0 설계 리뷰 | 없음 |
| D10 | 드라이버 | 제거된 Core 심볼을 참조하는 낡은 테스트가 남아 컴파일을 막음 | 고정 이름 socket 대역은 삭제하고 포인터 해석 대역으로 대체한다 | swift test 컴파일 오류 CmuxTests.swift:40,43; 대체 대역 testCmuxResolvedSocketPathRequiresALivePointerTarget | 없음 |
| D11 | 드라이버 | 채널 포인터가 해석되지 않을 때 무엇을 하는가 | 다른 채널이 살아 있으면 탐색 금지(noLiveSocket), 아무 채널도 살아 있지 않으면 기존 탐색 유지 — 채널 하나만 쓰는 사용자의 동작을 바이트 그대로 두면서 교차만 막는다 | 증분 리뷰 40eb4f2; TerminalRunner.swift:363 주석·PermissionChecker.cmuxSocketStatus | 탐색에 의존하는 cmux 버전이 실재하는지는 미측정 — 그래서 .discover를 남긴다. cmux가 채널 식별 RPC를 제공하면 재판정 |
| D12 | 드라이버 | 채널 포인터의 위치 | 채널당 후보 두 곳(state 디렉터리 → /tmp)을 순서대로 읽어 타깃이 존재하는 첫 번째를 핀한다 | 실측: 두 채널 모두 ∼/.local/state/cmux/*last-socket-path 와 /tmp/cmux[-nightly]-last-socket-path 에 같은 내용이 동시에 존재; CLI strings에 dev·staging 포함 여덟 이름 | 두 곳이 서로 다른 값을 가리키는 상황은 미측정 |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점 전체. 미검사 항목을 비워 두지 않는 것이 이 표의 목적이다. 세 열뿐이다 — 셋째 열은 코드로 알 수 없는 이유 한 절이거나 `파일:행`이다. 판정이 안전이고 그런 이유가 없는 대상은 한 행에 나열한다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `cmuxCommandSendGate`·`cmuxAwaitShellReading`·`runInCmux`의 command+CR | 안전 | `app/Sources/Core/CmuxControl.swift:220-240`, `app/Sources/Core/TerminalRunner.swift:480-610`; raw-mode 대기와 1024B deadline 계약을 코드가 보유하고 A·B 드라이버 게이트가 green임 |
| `cmuxRPC` 정의 및 호출 전체 | 안전 | `app/Sources/Core/CmuxControl.swift`, `app/Sources/Core/ClaudeInjector.swift`, `app/Sources/Core/TerminalRunner.swift`; production 호출 전체가 pin 판정 뒤 channel `socketPath`를 전달하고 `noLiveSocket`이면 RPC 자체를 생략함 |
| `CmuxChannel` bundle·CLI 후보·pointer·env | 안전 | `app/Sources/Core/CmuxControl.swift:45-201`, `app/Tests/CoreTests/CmuxTests.swift`; stable/NIGHTLY의 state→`/tmp` 후보·첫 live target·pin·환경 병합을 channel별 테스트가 고정함 |
| `Terminal` enum·rawValue·cmux channel mapping·session handle | 안전 | `app/Sources/Core/Terminal.swift`, `app/Sources/Core/ClaudeInjector.swift`, `app/Tests/CoreTests/CoreTests.swift`; `.cmux`의 `workspaceID`와 parser 두 식별자를 유지함 |
| `SetupWindowController`의 세 Terminal switch 및 permission/pipeline branch | 안전 | `app/Sources/App/SetupWindowController.swift:1217-1247,1262-1358,1467-1532`; cmux와 NIGHTLY가 각 exhaustive switch에서 동일 로직과 직접 channel mapping을 가짐 |
| `terminalChanged`·`updateTerminalControls`의 radio 양방향 | 안전 | `app/Sources/App/SetupWindowController.swift:1217-1247`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`; 다섯 radio의 양방향 mapping을 유지함 |
| `cmuxSection.isHidden`·`refresh()`의 status channel 분기·pipeline detail | 안전 | `app/Sources/App/SetupWindowController.swift:1262-1362,1467-1532`; 두 channel의 section 표시와 선택 channel status를 직접 분기함 |
| install preflight cmux candidate 및 no-terminal message | 안전 | `install.sh:34-86`; stable과 NIGHTLY bundle 후보 및 no-terminal 안내가 channel 계약과 일치함 |
| README·CLAUDE.md·new-terminal checklist | 안전 | 이번 C1∼C4에서 channel, raw-mode gate, shared settings, NIGHTLY 실기기 항목을 반영함 |
| `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`의 `extDescription` | 안전·불변 — D8 | NIGHTLY는 cmux 제품의 채널이지 다섯 번째 제품이 아니라 한 줄 제품 나열은 그대로 둔다(사용자 문구 churn 회피, 드라이버 결정 D8) |
| `docs/context/cmux-integration.md`의 socket discovery rationale | 안전 | C5에서 channel pointer 결정과 fixed `cmux.sock` 대안의 supersede 관계를 keep-the-why 형식으로 기록함 |
| `CmuxConfigHelp` 및 shared cmux settings file | 안전·불변 | `app/Sources/App/CmuxConfigHelp.swift`; D7에 따라 copy/open만 유지하고 쓰기 API를 추가하지 않음 |
| extension의 terminal selection and request schema | 비목표 | App이 terminal 선택의 source of truth이며 extension은 terminal rawValue를 받거나 보내지 않음 |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 차단·수정·실측 줄은 에이전트가, 판정 줄은 드라이버가 지정한 문구를 적는다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — 계획 커밋 전 · 승격 없음 · 리뷰 시각 미기록 · 왕복 1 · 원문 `/tmp/cmux-spark.qH3zbk/`

- 반박: 기준 트리 오기(r1) · C가 확장 locale 문구까지 범위에 넣음(r2) · A 단독 승격의 게이트 불가분성
- 처리: r1·r2 반영, A·B 단일 승격은 D9로 원장 기록
- 실측: 드라이버 baseline의 Darwin canonical 1024B 측정과 stable/NIGHTLY pointer·cross-channel PONG 측정을 계획 근거로 기록함
- 판정: "계획 합의 — r1·r2 반영 조건부. A·B는 게이트 불가분으로 한 승격."

### R1

#### 리뷰 1 — 증분 · a1b2c3d · 승격 14:02 · 리뷰 14:03∼14:15 · 왕복 1 · 원문 `<스크래치패드>/R1-review1.md`

- 차단: `max_items=0` → 빈 행 대신 전체 노출 (재현: `{"max_items": 0}`)
- 수정: 항목 1, `HomeRow.clamp` 재사용 (배정 13:20 · 완료 13:58)
- 실측: 게이트 214 green · 실코퍼스 1,427건 거부 0 · 산출물 sha256 불변
- 판정: "항목 1 차단 확인. 우회 없음." → 항목 1 `cleared`

#### 리뷰 2 — 증분 · 커밋 전 · 드라이버 게이트 보고

- 차단: A 점검 보고가 컴파일을 확인하지 않아 낡은 대역 1건이 남았다 (재현: `swift test --package-path app` → `cannot find 'cmuxSocketPath' in scope`)
- 수정: 항목 A′, 낡은 대역 삭제 + 제거·변경 심볼 전수 훑기
- 판정: "A 단독으로는 green을 낼 수 없다 — D9대로 A·B 단일 승격, 게이트 재실행 후 판정."

#### 리뷰 3 — 증분 · 40eb4f2 · 드라이버

- 실측: 게이트 swift 555(1 skip)·node 222·build·e2e 통과
- 차단: 채널 포인터 nil이면 세 지점이 핀 없이 탐색으로 떨어져, 선택한 채널이 꺼져 있고 다른 채널이 켜져 있을 때 남의 서버에 워크스페이스가 생기고 설정 창은 거짓 초록을 그린다 (`TerminalRunner.swift:363`·`:476`, `PermissionChecker.cmuxSocketStatus`)
- 수정: 항목 E, `cmuxSocketPin` 3상태로 판정을 모으고 소비 지점 셋을 태운다
- 판정: "A는 차단 없음(cleared). B는 채널 동일성이 핀 있을 때만 성립 — E 종료 후 재판정."
- 분류: B(평범한 환경 — NIGHTLY를 깔고 아직 안 띄운 상태)

## 열린 질문

- R0 계획 합의와 A∼D 배정·승격 판정 — 드라이버가 결정하며 A∼D 전체를 막는다.
- stable/NIGHTLY 양채널의 ∼1024B 초과 command, NIGHTLY 탭 생성, claude typed input 실기기 결과 — 종결 단계 드라이버 검증이 필요하다.
