# short-pane-delivery

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: terminal-checkout · app Claude input delivery 및 cmux grouped placement
- 시작 커밋: 21382f5
- 기준 트리: (worktree-short-pane-delivery-review · 21382f5) · 작업 트리: /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work (short-pane-delivery-work)
- 현재: R2 · 마지막 승격 bd302f6 · 리뷰 중 없음 · 게이트 Node 323 · Swift CoreTests 542 / AppTests 132
- 최근 검증자 판정: 미요청 · 원문 없음

이 파일은 **실행한 계획과 실행할 계획의 기록**이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실. 코드 수정 과정을 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다. 결정이나 질문이 특정 동작에 걸리면 한 절과 파일:행으로 끝낸다. 이 템플릿에 없는 소절을 만들지 않는다 — 테스트 설계는 테스트 파일이 말한다.

## 배경 — 확인한 원천

문제를 파악하며 확인한 영구 소스만 — Slack 스레드·이슈·PR·설계 문서처럼 세션이 끝나도 남는 것. 스크래치패드 경로는 여기 두지 않는다. 원천의 내용과 이 루프의 결정이 어긋나면 결정 원장의 사용자 행이 우선한다 — 원천을 읽었으면 원장에서 사용자가 결정·수정·취소한 것을 이어서 확인해라.

- [Issue #95](https://github.com/dazebug/terminal-checkout/issues/95) — 작은 pane에서 긴 typed Claude 입력이 화면 반사 확인을 통과하지 못해 제출되지 않는 문제. Directions는 끝 조각 probe 또는 앞·끝 조각 중 하나를 받는 방식을 제안하고, 2026-09-29 측정은 41×24 pane에서 8개 모두 실패했다고 기록한다.
- [PR #80](https://github.com/dazebug/terminal-checkout/pull/80) — cmux batch placement preset과 현재 grouped placement 경로의 이력.
- [PR #90](https://github.com/dazebug/terminal-checkout/pull/90) — 클릭 시 추가한 note도 기존 Claude input delivery로 합류하는 경로.
- [Issue #68](https://github.com/dazebug/terminal-checkout/issues/68) — cmux layout 생성, 표면 순서, 1∼8 pane geometry의 기존 측정 근거.
- [docs/context/claude-input-delivery.md](../context/claude-input-delivery.md) — 입력 probe, marker 실험, clear key, shell-mode merge의 현재 근거와 잔여.
- [docs/context/cmux-integration.md](../context/cmux-integration.md) — grouped placement, layout geometry, found-workspace split 및 RPC 계약.
- [docs/context/testing.md](../context/testing.md) — 테스트 대역의 한계, red toggle과 live oracle의 구분.

## 목표

- 반사 창에서는 끝 조각(공백 제외 마지막 24자)이 직전 화면보다 늘면 즉시 통과한다. 창이 끝날 때까지 끝 조각이 나타나지 않고 앞 조각만 늘었으면 통과한다; `inputBoxAfterSubmit`은 반사를 통과시킨 같은 조각을 쓰고 입력 화면에서 유일하지 않으면 `.unknown`을 반환한다 ( app/Sources/Core/ClaudeInjector.swift:216-243, 468-563, 644-678 ).
- 우리 입력이 차지할 수 있는 줄 수를 글자 수와 tty 열 수로 계산해 Ctrl+U를 K개 보낸 뒤 Backspace 하나를 보낸다. Claude composer 구조를 파싱하지 않는다; 우리 것이 아닌 사용자 초안이 K보다 길면 남을 수 있다 ( app/Sources/Core/ClaudeInjector.swift:336-382, 698-742, 1212-1222 ).
- `!`로 시작하는 입력은 `!`와 나머지를 두 번의 send로 보낸다. 대기나 shell-mode 화면 확인은 끼우지 않고, 본문 반사는 앞의 `!`를 포함한 전체 입력으로 한다 ( app/Sources/Core/ClaudeInjector.swift:511-563 ).
- cmux의 pane-per-item arrangement가 N=1∼25에서 layout-create와 fixed-name found-workspace 경로 모두 pane 배치를 유지한다.

## 완료의 정의

- 확정해 재현할 실패: M1은 38×20·76×20에서 앞 24자는 0→0, 끝 24자는 0→2라 현재 head-only 반사가 제출을 포기한다; M3의 319자·424자 입력은 Ctrl+U와 Backspace 한 쌍으로 앞 시각 줄이 남고, 반사 실패 뒤 재시도하면 잔여 위에 marker와 본문을 다시 쌓는다; M4의 424자 합친 줄은 한 번에 보내면 6/8 중복되고 `!`를 먼저 분리하면 0/8이다; N=9∼25 pane-per-item은 탭으로 바뀐다 ( app/Sources/Core/ClaudeInjector.swift:31-43, 216-243, 336-382, 468-563, 698-742; app/Sources/Core/CmuxPlacement.swift:89-90, 295-379, 383-435 ).
- acceptance oracle: M1 tail-only 화면은 반사를 통과하고, tail이 끝까지 보이지 않은 경우에는 반사 창 끝의 head 증가로 통과한다; M4는 leading `!`와 나머지를 두 send로 분리하고, M3는 K 기반 Ctrl+U와 Backspace가 이전 시도의 우리 잔여를 정리한다. M2 head-only 부분 화면을 실제 실패나 테스트 red로 취급하지 않는다. 테스트는 이슈 특성화와 이름으로 정한 전송·반사·소유량 계약만 고정한다; 드라이버는 cmux 0.64.22 및 Claude Code 2.1.287에서 필요한 입력 경로를 실측하고 `swift test --package-path app`을 실행한다; 확장 기준선은 `cd /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work && node --test --test-reporter=tap` exit 0, 323 tests다.
- 코퍼스 범위: 반사는 424자 합친 줄과 2,000자 plain note를; clear는 319자 줄, 424자 합친 줄, 재시도 중 남은 입력을; `!` 분리는 424자 합친 줄과 24자 단독 입력을; pane placement는 N∈{1,8,9,16,17,25}의 always-new 및 fixed-name found 경로를 다룬다.
- 원자성·부분 실패·롤백 경계: 세 입력 경로는 게이트 세 개, 모든 byte의 `send(_:io:)` 통과, CR 뒤 재타이핑 금지를 유지한다; layout create의 keyed retry와 found split의 부분 side effect·무rollback도 유지한다 ( app/Sources/Core/ClaudeInjector.swift:166-178, 328-334, 511-563, 806-815; app/Sources/Core/CmuxGroupedExecution.swift:511-579 ).

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

이 루프가 막는 실패를 일으킬 수 있는 행위자(사람·프로세스·시스템)와 그 능력을 열거한다. **발견을 배정하려면 어느 행위자가 그 결함에 닿는지 이름을 대야 한다** — 모델 밖 행위자가 필요한 발견은 기본이 잔여(원장 기록, 배정 없음)다. 행위자를 새로 들이는 것은 범위 변경이라 사용자 승인이 필요하다. 해당 없으면(순수 로직 루프) N/A + 근거.

- 사용자: pane 개수와 창 크기를 바꾸고, 길거나 줄바꿈된 Claude 입력(한글 등 두 칸 문자를 포함할 수 있음)을 보내며, 전달 도중 Enter를 누르거나 같은 tab에서 draft를 작성할 수 있다. `focus:false` workspace의 pane은 보이기 전까지 layout과 무관하게 106×39일 수 있다. 사용자가 쓴 draft가 계산한 K보다 길면 뒤쪽이 남을 수 있으며, 기존 #16과 같은 잔여다.
- Claude TUI: 버전별 composer 높이, 긴 입력의 [Pasted text #N] 접기, ! 진입 키 처리와 화면 출력이 달라질 수 있다.
- 터미널별 carrier: iTerm2 AppleScript, WezTerm CLI, Warp helper, cmux RPC가 같은 control sequence를 서로 다른 경로로 전달하고 screen reader도 서로 다른 단위를 반환한다.
- 같은 uid 프로세스: 기존 Warp helper socket boundary 안에서 pane input을 주입할 수 있다 ( app/Sources/WarpHelper/main.swift:1-12 ).

## 비목표 — 건드리지 않는다

- 세 Claude input gate, send(_:io:) 단일 byte 출구, TCC 프로세스 분리, no-retype-after-CR 계약: 이번 세 결함을 고칠 때 우회하지 않는다 ( app/Sources/Core/ClaudeInjector.swift:166-178, 328-334, 401-456, 806-815 ).
- claudeTypedInputs의 안전성 판단, shell 실행 의미, banner, 순서, ; 결합: 첫 ! 전달 단계를 제외하고 바꾸지 않는다 ( app/Sources/Core/ClaudeInputPlan.swift:280-325 ).
- batchItemLimit, extension payload, cmux workspace identity와 command byte limit: 이 루프는 pane placement 상한만 다룬다 ( app/Sources/Core/Request.swift:27-35, app/Sources/Core/CmuxPlacement.swift:89-90 ).
- 완료된 [docs/plans/cmux-placement-preset.md](cmux-placement-preset.md): PR #80 당시 결정을 기록한 역사 자료로 보존하고, 현재 계약은 context와 checklist에서 갱신한다.
- 메인 체크아웃, 기준 트리, extension 코드와 다른 terminal의 command-launch/placement 동작.

## 불변 원칙

0라운드 이후 이 절과 「완료의 정의」에 항목을 **더하는 것은 범위 변경이다** — 결정 원장의 사용자 행 없이 추가하지 않는다(드라이버·검증자 발의는 비용 추정과 함께 사용자 승인 후). 드라이버가 스스로 쓴 기준을 스스로 집행하는 것이 일감 자가 생산의 뿌리다.

- 세 gate와 모든 send-site session identity 재검사를 보존한다; probe, `!` prefix 분리, count-based clear를 포함한 각 byte는 `send(_:io:)` 단일 출구를 통한다 ( app/Sources/Core/ClaudeInjector.swift:328-334, 511-518, 698-742 ).
- 본문 반사는 before snapshot 대비 증가한 끝 조각을 우선하고, 반사 창이 끝날 때까지 끝 조각이 없으면 앞 조각 증가를 대체로 받는다; 반사를 통과시킨 같은 조각으로 post-CR 상태를 판정하고, 입력 화면에서 유일하지 않으면 `.unknown`이다 ( app/Sources/Core/ClaudeInjector.swift:216-243, 468-563, 644-678, 789-803 ).
- marker는 pane proof와 입력 위치 attribution에 계속 쓰지만 marker 글자 count나 composer 구조 파싱을 clear oracle로 쓰지 않는다. marker clear, 재시도 전 clear, delivery-end cleanup은 동일한 K 산정 규칙을 쓴다 ( app/Sources/Core/ClaudeInjector.swift:208-213, 336-357, 698-742 ).
- `InputBoxOwnership`은 마지막으로 우리 입력이 없다고 판정한 뒤 시도한 입력의 terminal-cell 상한을 marker 포함해 추적한다; send 실패도 일부 byte가 갔을 수 있으므로 전체 시도 상한에 포함한다. printable ASCII는 1칸, 그 밖의 비제어 Character는 2칸으로 센다. Ctrl+U·Backspace는 count에 더하지 않고, CR 뒤에도 입력창 부재 증거나 count clear 전까지 기존 count를 유지한다. 가능한 tty 열 수를 읽어 K를 산정하고, 못 읽으면 20열의 보수적 하한을 쓴다; 사용자 초안이 K보다 길면 남는 경우는 기존 #16 잔여와 같은 부류다 ( app/Sources/Core/ClaudeInjector.swift:102-130, 383-399, 411-468, 1223-1233 ).
- clear는 Ctrl+U를 K개 보낸 뒤 Backspace 하나다. cmux는 Ctrl+U를 최대 8개씩 `surface.send_text`에 나눠 보내고 Backspace는 별도 호출에 보낸다; 빈 입력창에서 추가 Ctrl+U가 무해하다는 관찰은 cmux의 C1이다. iTerm2, WezTerm, Warp의 쓰기 단위는 코드로 확인하고 hands-on checklist에 남기며, cmux 외 TUI 실측은 이 루프의 게이트가 아니다 ( app/Sources/Core/ClaudeInjector.swift:31-115, 328-357, 1352-1424; app/Sources/Core/AppleScriptSupport.swift:121-152 ).
- 입력이 `!`로 시작하면 첫 글자와 나머지를 별도 send로 연달아 보낸다. 셸 모드 전환을 확인하려고 기다리지 않는다; 두 send 각각 gate ③을 통과하며 화면 반사는 앞의 `!`를 포함한 전체 원문으로 한다 ( app/Sources/Core/ClaudeInjector.swift:511-563 ).
- 연속 `!` 입력의 merge 안전성, shell 의미, banner, 순서는 유지한다; 전송 경로만 leading `!`를 분리한다 ( app/Sources/Core/ClaudeInputPlan.swift:280-325 ).
- pane geometry 상한 25는 `batchItemLimit`과 값이 같더라도 별도 명시값으로 둔다; batch 상한 변경만으로 미측정 geometry 범위를 자동 확장하지 않는다 ( app/Sources/Core/Request.swift:27-35, app/Sources/Core/CmuxPlacement.swift:89-90 ).
- 계획 항목 번호와 원장 식별자는 코드·주석·패키지 문서·커밋 본문에 옮기지 않는다.

## 배치 점검 (0라운드)

모드: ultrafast

(default 또는 ultrafast. 이 줄이 적힌 뒤로는 스킬 인자가 아니라 이 값이 모드를 정한다 — 스킬의 점검 블록이 이 줄을 읽는다.)

이 표의 실측 주체는 드라이버다 — 구현자가 채우는 행은 「에이전트 첫 보고」뿐이고, 자기 샌드박스의 실패로 드라이버 실측 값을 덮어쓰지 않는다(샌드박스 제약은 리포 오버레이 「격리 안에서 도는·못 도는 게이트」에 드라이버가 적는다).

| 점검 | 결과 |
|:--|:--|
| git check-ignore -q .claude/worktrees/probe → ignored (아니면 .gitignore 또는 info/exclude에 .claude/worktrees/) | ignored (드라이버, 기준 트리) |
| 설정 worktree.baseRef: "head" — 에이전트 첫 보고의 git log --oneline -2가 기준 HEAD를 보이는가 | N/A — 작업 트리는 전용 clone, 첫 보고 log가 기준 HEAD 21382f5 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work · short-pane-delivery-work · 21382f5 |
| 리포 오버레이 .claude/drive-agent-loop.md — 기준 트리의 경로(메인 것을 복사했으면 그렇게), 없으면 드라이버가 골격으로 작성. 커밋하지 않는다 — 오버레이 무시: ignored 확인 | `.claude/drive-agent-loop.md`는 리포에 커밋된 파일 — 이 루프는 수정하지 않는다 |
| cmux 패널 (점검 블록 cmux: 신호가 켜졌을 때만, 아니면 N/A) — cmux markdown open <작업 트리 계획 파일 절대경로> → pane id. 계획 파일 첫 승격 전에 채운다 | surface:406 · pane:324 (드라이버, 이 세션 workspace에 focus 없이) |
| 트리마다 의존성 동기화 (기준·작업) | N/A — 외부 의존성 없음 |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 없음 |
| 증분 리뷰 소요(분) — 첫 세 번 | |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1a | 반사 확인을 tail-first, head-fallback으로 바꾸고 `inputBoxAfterSubmit`이 반사를 통과시킨 같은 조각을 쓰게 한다. | 입력 반사 | M1: 424자 합친 줄에서 38×20·76×20의 head24는 0→0이고 tail24는 0→2; 구 head-only probe는 입력을 놓친다 ( app/Sources/Core/ClaudeInjector.swift:216-243, 468-563, 644-678, 789-803 ). | app/Sources/Core/ClaudeInjector.swift, app/Sources/Core/ClaudeInputPlan.swift, app/Sources/Core/Request.swift, app/Sources/Core/WarpHelperProtocol.swift, app/Sources/WarpHelper/main.swift, app/Tests/CoreTests/CoreTests.swift | — | cleared | 재실행(드라이버): clone swift test → exit 1, 접힘 테스트 대역 결함(공백 포함 24자 렌더) · 토글(옛 ClaudeInjector) → 새 테스트 2개 실패(짧은 pane: 제출 0·waits 144, 접힘: waits 0); `node --test --test-reporter=tap` → exit 0·323 · 재실행(드라이버): clone swift test → exit 0, CoreTests 535(1 skipped), AppTests 132 · 토글 → 새 테스트 2개 실패 | — |
| 1b | `!`로 시작하는 입력을 `!` 한 글자와 나머지로 나눠 연속 전송한다; 셸 모드 화면 확인이나 대기는 넣지 않고 반사는 전체 입력으로 한다. | 입력 전송 | 424자 합친 줄은 한 번에 보내면 6/8 중복되고, `!`를 별도 send로 보낸 뒤 나머지를 즉시 보내면 0/8이다; 24자 단독 입력은 한 번 전송도 0/20이라 중복은 긴 덩어리에서 관찰됐다 ( app/Sources/Core/ClaudeInjector.swift:511-518; app/Tests/CoreTests/CoreTests.swift:2616-2637 ). | app/Sources/Core/ClaudeInjector.swift, app/Tests/CoreTests/CoreTests.swift | 1a | cleared | `testLeadingBangIsSentSeparatelyFromTheLongInputBody`와 FakeClaudeSession red model 추가; 단일 424자 write는 대역에서 `!!…`가 되고 split send는 원문 그대로 한 번 제출하도록 고정; `node --test --test-reporter=tap` → exit 0·323; Swift 게이트는 드라이버 실행 대기 · 재실행(드라이버): clone swift test → exit 1, 기존 테스트 1개가 단일 전송 기대값 — 고침 · 토글(1b 전 ClaudeInjector) → 새 테스트 red(`!!/bin/echo …` 제출) | — |
| 1c | composer 구조를 파싱하지 않고 `InputBoxOwnership`의 누적 칸 수 상한과 tty 열 수로 K를 산정해 Ctrl+U K개, Backspace 하나를 보내는 clear 경로를 만든다. marker clear, 재시도 전 clear, delivery-end cleanup이 한 함수를 쓴다. | 입력 비우기 | C1: 한 Ctrl+U는 시각 줄 하나만 지우며 Ctrl+U+Backspace 한 쌍은 319자·424자 입력의 앞 줄을 남긴다. 반사 실패 뒤 재시도는 그 잔여 위에 marker와 다음 본문을 쌓아 입력 병합·오제출로 이어질 수 있고, 포기 뒤 정리도 마지막 줄 외의 `!` 입력을 남겨 이후 Enter가 잘린 셸 명령을 실행할 수 있다. D7: 64·128 Ctrl+U 한 번 쓰기는 무시됐고, 한 쓰기당 최대 8개로 나눈다 ( app/Sources/Core/ClaudeInjector.swift:31-43, 85-130, 354-399, 411-468, 709-753, 1223-1233; measurements.md B2 ). | app/Sources/Core/ClaudeInjector.swift, app/Sources/Core/AppleScriptSupport.swift, app/Tests/CoreTests/CoreTests.swift, app/Tests/CoreTests/CmuxTests.swift | 1a·1b; retry reflection은 1a 정책 전제 | cleared | `testRetryClearsWrappedRemainderBeforeRetypingInputAgain`, `testAbandonedWrappedInputIsFullyClearedAfterRetriesExhausted` 추가; 424자 입력·38열 시각 줄 대역 사용. 기존 15개 delivery 테스트의 clear 쓰기 기대를 갱신하고 ownership·carrier 테스트를 확장했다. `node --test --test-reporter=tap` → exit 0·323. 로컬 Swift filter는 테스트 전에 `sandbox-exec: sandbox_apply: Operation not permitted`로 중단; 드라이버 clone Swift는 `AppleScriptSupport.swift:134`에서 public 기본 인자가 internal `claudeClearInputKey`를 참조해 compile error. 기본값을 제거하고 앱·테스트 호출부가 키를 명시하도록 고쳤다. 재실행(드라이버): clone swift test exit 0 · CoreTests 538 · AppTests 132 · 토글(옛 지우기) → 새 테스트 2개 red. 재실행(드라이버): clone swift test → exit 0, CoreTests 539(1 skipped), AppTests 132 · 토글 ① 예전 단일 clear → 줄바꿈 테스트 2개 red; ② cell count 대신 character count → 한글 120자 테스트 red | — |
| 1c′ | K를 글자 수가 아니라 terminal-cell 수 상한으로 센다. | 입력 비우기 | (a) 두 칸 글자를 한 칸으로 세어 K가 모자란다 — 한글 120자, 38열에서 두 줄 남음 | app/Sources/Core/ClaudeInjector.swift, app/Tests/CoreTests/CoreTests.swift | 1c | cleared | `testRetryClears120KoreanCharactersByCellWidthBeforeSubmittingOnce` 추가; 120개 한글 문자·38열에서 첫 본문 반사 읽기를 실패시켜 다음 시도의 본문만 한 번 제출하는지 확인한다. `InputBoxOwnership`은 printable ASCII를 1칸, 나머지 비제어 Character를 2칸으로 상한 계산하고, 대역은 같은 칸 규칙으로 시각 줄을 나눈다. Node exit 0·323; Swift 게이트는 드라이버 재실행 대기. 재실행(드라이버): clone swift test → exit 0, CoreTests 539(1 skipped), AppTests 132 · 토글 ① 예전 단일 clear → 줄바꿈 테스트 2개 red; ② cell count 대신 character count → 한글 120자 테스트 red | — |
| 2 | cmux pane-per-item 상한을 명시값 25로 올리고 balanced layout 및 fixed-name found split 경로가 모두 25 item을 표현하는지 고정한다. | cmux placement | N=9∼25는 명시적 8 cap 때문에 현재 탭 경로로 바뀐다; 고정 이름 workspace의 found split 계획도 8 cap이다 ( app/Sources/Core/CmuxPlacement.swift:90, 299, 315, 336, 397 ). | app/Sources/Core/CmuxPlacement.swift, app/Sources/Core/CmuxGroupedExecution.swift, app/Sources/App/HostServer.swift, app/Tests/CoreTests/CmuxPlacementTests.swift, app/Tests/CoreTests/CmuxGroupedExecutionTests.swift, app/Tests/AppTests/HostProtocolTests.swift | 1c·1c′ | cleared | `testAlwaysNewPanePlacementKeeps25ItemsInBalancedLayout`는 새 workspace의 leaf 25개·실제 DFS 0∼24 순서와 root horizontal split(첫 자식 13·둘째 12)을 고정한다. `testFoundPaneExecutionRoutesAll25ItemsInPlannedSurfaceOrder`는 found 경로의 split 24회와 25개 surface에 대한 command/result 순서를 고정한다. 기존 Core placement의 N>8 테스트를 N=9 pane 경로로 고쳐 쓰고, HostServer 테스트는 N=9의 계획이 pane fallback하지 않는 점과 실행 결과가 보고한 fallback 로그를 분리해 고정한다. 재실행(드라이버): swift test CoreTests 541(1 skipped) · AppTests 132(단독 0) · 토글(상한 8) → 새 테스트 2개 red · 라이브: 38×20 pane에 sent 4 of 4(9.4s) | — |
| 2′ | found split이 기존 첫 surface를 항목에 보내지 않는다: N+1 leaf 균형 split, leaf 0(기존 surface)은 그대로, 항목은 leaf 1∼N | cmux placement | 항목 0의 명령·Claude 입력이 기존 첫 surface로 가며, 재사용 workspace에서는 이전 배치의 claude에 전달된다 (D10) | app/Sources/Core/CmuxPlacement.swift, app/Tests/CoreTests/CmuxPlacementTests.swift, app/Tests/CoreTests/CmuxGroupedExecutionTests.swift | 2 | cleared | 새 통합 테스트 `testFoundPaneExecutionNeverSendsItemsToExistingRoot`가 N=1, 9, 25에서 기존 root 미전송·미반환, split N회, N개 고유 새 surface와 depth-first 응답 순서를 고정한다. 기존 5개 테스트 갱신: `testFoundPaneExecutionUsesExplicitSplitTargetsAndMeasuredItemOrder`, `testFoundPaneExecutionRoutesAll25ItemsInPlannedSurfaceOrder`, `testPanePlacementKeepsNineItemsInPanesForBothIdentityModes`, `testFoundPanePlanBalancesTheExistingRootAsUnassignedLeafZero`, `testFixedPanePlanCarriesFoundAndCreateBranches`. cold review 재현은 기존 코드에서 N=25 `foundSplit`, 첫 수신자가 existing Claude surface라 exit 1. 구현 전 로컬 red 확인 시도(`swift test --package-path /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work/app --filter CmuxGroupedExecutionTests/testFoundPaneExecutionLeavesExistingRootUntouchedForEveryItemCount`)는 manifest 검증 전에 `sandbox-exec: sandbox_apply: Operation not permitted`로 중단되어 새 테스트의 로컬 red/green은 확인하지 못했다. `node --test --test-reporter=tap` → exit 0·323; Swift 게이트는 드라이버 확인 필요. 재실행(드라이버): clone `swift test` exit 0, CoreTests 542(1 skipped)·AppTests 132 · 토글(옛 계획기) → 새 테스트 red(N=1·9·25) · 라이브 P2: 옛 계획 N=9 기존 surface 22바이트 수신, 새 계획 N=9·25 0바이트·surface 10·26 | — |
| 3 | 실측으로 확정된 입력 전달·pane placement 이유와 지원 체크리스트를 갱신한다; 새 carrier 측정 게이트는 추가하지 않는다. | 근거·체크리스트 | active context와 hands-on checklist가 first-24 probe, Ctrl+U clear, N>8 tab fallback을 현재 계약처럼 남긴다. | CLAUDE.md, docs/context/claude-input-delivery.md, docs/context/cmux-integration.md, docs/context/testing.md, docs/new-terminal-checklist.md | 1a·1b·1c·2 및 cmux 실측 | claimed | CLAUDE.md 반사·개수 기반 비우기·선행 `!` 기록; context 결정 3개 추가 및 cmux geometry/B1·Swift 병렬 게이트 근거 반영; 체크리스트 갱신. 드라이버 리뷰 1회: 사라진 사실 복원·범위 밖 편집 되돌림·없는 테스트 이름 교정. README 4개 검색 `rg -ni '(pane|panel|split|분할|패널|ペイン|窗格|分屏).{0,45}(8|８|eight|八|여덟)|(8|８|eight|八|여덟).{0,45}(pane|panel|split|분할|패널|ペイン|窗格|分屏)' /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work/README.md /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work/README.ko.md /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work/README.ja.md /Users/choongjaelee/Codes/terminal-checkout-short-pane-delivery-work/README.zh-Hant.md` → exit 1·0건; `node --test --test-reporter=tap` → exit 0·323; 보정 커밋: 2.1.238 문장·typed bytes·cmux 0.64.25 출처·체크리스트 기본 프리셋 복원 | — |
| 3′ | 2′의 결정·측정을 문서에 반영하고 pane proof 문장을 정정한다 (D11) | 근거·체크리스트 | found split 설명이 항목 0 = 기존 첫 surface를 전제하고, cmux가 pane proof를 생략한다고 잘못 쓴다 | CLAUDE.md, docs/context/cmux-integration.md, docs/new-terminal-checklist.md | 2′ | todo | P3 문장만 정정하며 코드 변경은 없다. `proveOurPaneAndEmptyBox`는 모든 입력에서 호출되고 `screenNeedsPaneProof`는 post-CR 상태 판정과 Warp 접근성 판단에서 읽힌다 ( app/Sources/Core/ClaudeInjector.swift:501-504, 658-662, 1172-1176 ). | — |

- 승격 순서: 1a → 1b → 1c → 1c′ → 2 → 3 → 2′ → 3′. 1a·1b·1c·1c′는 같은 `ClaudeInjector.swift`를 건드려 순서로 분리했고, 새 found-workspace 리뷰 작업은 2 뒤에 2′, 문서 반영은 3′로 둔다.
- 1a tests: `testShortPaneTailReflectionSubmitsThe424CharacterMergedInputOnce` feeds the M1 five-row tail-only screen through `submitClaudeInputs`; `testCollapsedInputUsesHeadReflectionOnlyAfterTheWindowExpires` models the M2 head-only folded-paste screen and pins deadline fallback. The existing long-probe test now checks both tail-primary and head-fallback candidates; `inputBoxAfterSubmit` uses the selected fragment and still returns `.unknown` when it is not unique.
- 1b red: `FakeClaudeSession`은 빈 box에 `!`로 시작하는 24자 초과 단일 write가 오면 shell-mode 전환 중 leading `!`가 글자로도 남는 `!!…`를 모델링한다. `testLeadingBangIsSentSeparatelyFromTheLongInputBody`는 424자 합친 줄을 `submitClaudeInputs`에 넣어 전송 call `!` → 나머지, 원문 그대로 한 번 제출, CR 한 번, 각 send의 gate ③, 대기 없는 경로를 고정한다. 24자 이하 입력의 중복은 구 코드에서 재현되지 않아 테스트하지 않는다 ( app/Sources/Core/ClaudeInjector.swift:511-518; app/Tests/CoreTests/CoreTests.swift:2369-2532, 2616-2637 ).
- 1c tests: `testRetryClearsWrappedRemainderBeforeRetypingInputAgain` feeds the measured 424-character input at 38 columns, fails the first body-reflection read, and requires one clean submission after the next marker experiment; `testAbandonedWrappedInputIsFullyClearedAfterRetriesExhausted` withholds long-body reflection, exhausts retries, and requires an empty input box. `FakeClaudeSession` clears only the last visual line for each Ctrl+U, even when several controls share a send.
- 1c′ test: `testRetryClears120KoreanCharactersByCellWidthBeforeSubmittingOnce` sends 120 Hangul characters into the 38-column fake pane, fails the first body-reflection read, then requires the next attempt to submit only the original body once; the width rule models ordinary terminal cells, not a Claude-specific measurement.
- 1c K: `InputBoxOwnership` counts attempted terminal-cell upper bounds since the last observed-empty input box, including marker and split `!`, and excludes control bytes and CR; only observation resets the count. Printable ASCII characters count as one cell, while every other non-control Character counts as two. `/bin/stty -f <tty> size` supplies columns through `ClaudeSessionIO.terminalColumns`, with 20 columns if the read fails. K = ceil(cellCountUpperBound / max(columns − 4, 8)) + 2; each write has at most eight Ctrl+U keys and the last batch carries one Backspace. The residual when a user's draft is longer than K remains in the #16 class.
- 1c carrier check is code-only: iTerm2 writes each clear batch in one AppleScript call, WezTerm passes each batch through one `send-text --no-paste` call, Warp sends one helper inject request per batch and waits for the input queue to empty before replying, and cmux uses one `surface.send_text` for each Ctrl+U burst with a separate Backspace call. The other three terminals' TUI behavior remains unmeasured; carry it as a hands-on checklist item, not a gate.
- 2 tests: `testAlwaysNewPanePlacementKeeps25ItemsInBalancedLayout` pins 25 leaves, actual DFS leaf indices, and the measured root horizontal split with 13 leaves in its first child; `testFoundPaneExecutionRoutesAll25ItemsInPlannedSurfaceOrder` pins 24 found-workspace splits and the command/result order across 25 surfaces. The former N>8 fallback test is rewritten to require N=9 pane placement for both identity modes. The live found split geometry still needs a visible workspace, so notify the user before opening it.
- 2의 25는 geometry policy의 명시값이다; `batchItemLimit`은 batch cardinality로 둔다. N=26은 batch precondition 전에 거부되어 이 루프의 pane oracle이 아니다.
- 3은 마지막에 current-state 문서만 갱신한다. `docs/plans/cmux-placement-preset.md`의 N>8 문구는 완료된 PR #80의 역사 기록으로 남긴다.

## 결정 원장

append-only — **첫 승격 이후부터**다(첫 승격 전의 R0 초안은 아직 인용된 판정이 없으므로 재작성해도 된다). 결정의 이유, 기각한 반박과 근거, 잔여 불확실성 — 코드 서술은 여기에도 넣지 않는다. 기존 행을 고치지 않고 새 행을 더한다. 유형은 결정 주체(사용자/드라이버)다. **행을 적는 손은 구현자여도 행의 발행은 드라이버다** — 두 유형 모두 드라이버가 문구를 지정한 것만 적고, 구현자는 스스로 행을 추가하지 않는다(구현자 발의는 「열린 질문」에 적어 처분을 기다린다). claimed가 상태의 구현자 상한인 것과 같은 축이다. **사용자 행은 배경 원천·검증자 권고와 어긋나도 우선하고, 새 사용자 행으로만 뒤집힌다** — 배경 소스에 적힌 내용을 사용자가 이 루프에서 결정·수정·취소한 것이 여기 남는다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | #95와 같은 입력 경로의 두 결함(M3 Ctrl+U, M4 ! 중복)도 함께 | 셋 다 이번 루프에서 고치고, 그 뒤 cmux pane 배치 상한을 8→25로 | 2026-10-02 사용자 선택 | — |
| D2 | 드라이버 | 열린 질문 1: 앞 조각만으로는 입력 전체가 그려졌다는 증거가 아니다 — composer 끝·접힘 신호를 확인해야 한다 | 기각 — 꼬리 우선, 머리는 대체: 반사 창 안에서 끝 조각(공백 제외 마지막 24자)이 직전 화면보다 늘면 즉시 통과, 창이 끝날 때까지 끝 조각이 안 나타나고 앞 조각만 늘었으면 그때 통과(긴 입력을 claude가 [Pasted text #N]로 접으면 앞만 보인다 — M2). 끝 조각이 보이면 입력 끝까지 그려진 것이다. composer 테두리·커서 같은 claude 화면 구조를 파싱하지 않는다. 앞만 보인 채 CR이 붙여넣기 처리 중에 들어가 제출되지 않는 경우는 inputBoxAfterSubmit이 입력창에 남았음으로 잡는다 | measurements.md M1·M2 · ClaudeInjector.swift typeAndSubmit·inputBoxAfterSubmit · R0 | 접힘이 어떤 조건(길이·타이밍·입력창 상태)에서 일어나는지 분리하지 못했다 |
| D3 | 드라이버 | 열린 질문 3: 셸 모드 전환을 화면으로 확인한 뒤 나머지를 보내야 한다 | 기각 — 대기·화면 확인 없이 두 번의 send로 충분하다(합친 줄 0/8, 단독 0/20). 두 send 모두 send(_:io:)를 지나 게이트 ③을 각각 다시 확인한다. 반사 확인은 지금처럼 입력 전체(앞의 ! 포함)로 한다 | measurements.md C2·D1 · R0 | 다른 터미널에서 두 send가 한 번의 읽기로 합쳐질 수 있는지(Warp helper는 빈 큐에만 쓴다 — 확인 필요) |
| D4 | 드라이버 | 열린 질문 2: 비웠는지를 composer 영역 파싱으로 확인해야 한다 | 기각 — 우리가 넣었을 수 있는 글자 수와 pane 폭으로 필요한 Ctrl+U 개수 K를 구해 한 번에 보내고(D2: 한 호출에 여러 개가 줄마다 처리된다), 그 뒤 Backspace 하나(셸 모드 ! 제거, cmux는 지금처럼 따로). 빈 입력창의 추가 Ctrl+U는 무해하다(C1). 마커 지우기·실패한 반사 뒤 재시도 전·전달 끝 정리 세 곳이 같은 함수를 쓴다. 우리 것이 아닌 사용자 초안이 K보다 길면 남는다 — 기존 잔여(#16)와 같은 부류로 문서화한다 | measurements.md C1·D2 · ClaudeInjector.swift proveOurPaneAndEmptyBox·clearAbandonedInput · R0 | K가 클 때(64 이상) 한 호출의 Ctrl+U 묶음이 붙여넣기로 처리되지 않는지 드라이버 측정 전 |
| D5 | 드라이버 | 항목 1을 한 승격으로 묶자는 초안 | 기각 — 셋은 결함·실패 모드·대역이 달라 따로 리뷰해야 우회가 보인다. 같은 파일을 만지는 것은 순서로 푼다 | R0 | — |
| D6 | 드라이버 | 네 터미널 모두에서 TUI 실측을 완료 조건으로 | 기각 — cmux 실측 + 나머지는 전달 방식 코드 확인과 체크리스트. 사용자 모르게 Warp를 띄우지 않는다 | R0 | iTerm2·WezTerm·Warp에서 K개 Ctrl+U 묶음·! 분리 전송이 같은 결과인지 미측정 |
| D7 | 드라이버 | D4 정정: K개 Ctrl+U를 한 호출로 보내면 64·128개 묶음이 통째로 무시된다(B2) | 한 번의 쓰기에 Ctrl+U를 8개 이하로 나눠 보낸다(8개 묶음은 매번 처리됐다). 나머지(누적 글자 수·열 수로 K 산정, 뒤에 Backspace 하나, 세 곳이 같은 함수)는 D4 그대로 | measurements.md B2 · R0 뒤 드라이버 실측 | 묶음이 무시되는 조건(크기·내용·타이밍)은 모른다 — 8이 모든 상황에서 안전하다는 증명은 없다, cmux 밖 터미널은 미측정 |
| D8 | 사용자 | 고정 이름 workspace가 이미 있을 때의 split 경로도 25로 올릴지(그 경로는 첫 pane을 쪼개므로 17개부터 약 10줄 — 계산치) | 둘 다 25 | 2026-10-02 사용자 선택 · found-split-probe.py(구조만 확인: split 24·pane 25) | 그 크기에서 claude 입력 전달은 미측정 |
| D9 | 드라이버 | 테스트 심사 — 이 루프의 새 테스트 8개와 고쳐 쓴 기존 테스트 | 새 테스트 8개 모두 유지(각각 토글 red: 1a 2·1b 1·1c 2·1c′ 1·2 2), 기대값만 갱신한 기존 테스트 유지. 삭제 후보로 올라온 testDeliveryEndsWithTheBoxCleared는 이 루프 전부터 있던 테스트라 범위 밖 — 유지 | r10 2단계 심사표(원문 /private/tmp/short-pane-loop/r10-response.md) | FakeClaudeSession의 화면·시각 줄 모델은 실제 TUI 렌더러를 증명하지 않는다 — 라이브 전달 1회(38×20, sent 4 of 4)가 그 공백을 메우는 유일한 실측 |
| D10 | 사용자 | cold review P1: found split이 기존 첫 surface를 항목 0에 쓴다 — 같은 workspace에 다시 보내면 이전 배치의 claude에 명령·예약 입력이 들어간다(8개 이하는 PR #80부터, 상한 25로 9∼25까지) | 고친다: 기존 첫 surface는 내용 그대로 한 leaf로 남기고 항목은 모두 새 split surface에(N+1 leaf, 모든 N). PR #80 U4의 "root가 항목 0을 맡는다"를 대체한다 | 2026-10-02 사용자 선택 · cold review 원문 /private/tmp/short-pane-loop/cold-response.md · 재현 /private/tmp/short-pane-independent-review.1TDz2w/root-probe.swift | found workspace의 첫 pane은 배치마다 한 몫씩 더 작아진다 |
| D11 | 사용자 | cold review P3: 문서가 "cmux는 nonce pane 증명을 생략"이라 쓰지만 모든 입력이 마커 실험을 거친다(이 PR 이전부터) | 이번 PR에서 해당 문장만 정정, 코드 변경 없음 | 2026-10-02 사용자 선택 | — |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점 전체. 미검사 항목을 비워 두지 않는 것이 이 표의 목적이다. 세 열뿐이다 — 셋째 열은 코드로 알 수 없는 이유 한 절이거나 파일:행이다. 판정이 안전이고 그런 이유가 없는 대상은 한 행에 나열해 합친다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 파일:행 |
|:--|:--|:--|
| `claudeInputProbe`·head fallback·`screenReflectsNewInput`·`probeCount(of:)` | tail 우선; head baseline은 저장하고 reflection window 끝에 fallback (1a) | app/Sources/Core/ClaudeInjector.swift:216-243, 468-563, 789-803 |
| `inputBoxAfterSubmit`의 selected candidate 재사용·유일성 | 반사를 통과시킨 조각을 받아 유일성을 확인 (1a) | app/Sources/Core/ClaudeInjector.swift:644-678, 793-803 |
| `screenTail`·`probeOccurrences`의 selected candidate 처리 | 선택된 조각만 전달받음 (1a) | app/Sources/Core/ClaudeInjector.swift:793-803 |
| marker appearance in `proveOurPaneAndEmptyBox` | 변경 없음: 3글자 marker는 head와 tail이 같다 (1a) | app/Sources/Core/ClaudeInjector.swift:208-213, 698-742, 778-784 |
| Warp helper의 reflection 설명 | 2.1.287 tail-only·folded-head 측정과 현재 정책으로 갱신 (1a) | app/Sources/Core/WarpHelperProtocol.swift:20-26; app/Sources/WarpHelper/main.swift:180-186 |
| merged-line cap 및 typed-input control-byte rationale | 현재 경계 probe 설명으로 갱신 (1a) | app/Sources/Core/ClaudeInputPlan.swift:59-65, 287-294; app/Sources/Core/Request.swift:207-220 |
| 본문이 `!`로 시작할 때 prefix와 remainder를 잇는 두 send | 각 send는 `send(_:io:)`를 다시 지나며 gate ③을 확인; 두 번째 실패도 기존 typing 실패와 같이 재시도 (1b) | app/Sources/Core/ClaudeInjector.swift:511-518 |
| marker·clear·delivery-end cleanup bytes | marker는 세 Runic 글자이고 clear/cleanup은 control keys라 긴 leading-`!` 단일 write가 생기지 않는다 | app/Sources/Core/ClaudeInjector.swift:31-43, 328-357, 698-742 |
| cmux의 두 body send | 각 `sendKeys` 호출의 `cmuxSendOperations`는 body text를 하나의 `surface.send_text` operation으로 만들고 두 호출은 순서대로 실행; C2는 대기 없이 나눈 두 send를 측정 | app/Sources/Core/ClaudeInjector.swift:63-83, 1384-1405; measurements.md C2 |
| iTerm2 carrier | 각 body send는 별도 AppleScript `write text … newline NO` 한 번으로 전달; 실제 TUI read 경계는 코드로 확정할 수 없어 미측정(D6) | app/Sources/Core/ClaudeInjector.swift:1352-1377; app/Sources/Core/AppleScriptSupport.swift:85-119 |
| WezTerm carrier | 각 body send는 별도 `wezterm cli send-text --no-paste` 호출로 전달; 실제 TUI read 경계는 코드로 확정할 수 없어 미측정(D6) | app/Sources/Core/ClaudeInjector.swift:1378-1383 |
| Warp helper carrier | 각 inject 요청은 queue-empty 확인까지 응답하지 않으므로 두 번째 send가 첫 `!`의 queue read보다 앞서 합쳐질 수 없다 | app/Sources/Core/ClaudeInjector.swift:1406-1424; app/Sources/WarpHelper/main.swift:123-175, 187-219 |
| `InputBoxOwnership`의 flag와 누적 칸 상한 | ASCII printable Character는 1칸, 나머지 비제어 Character는 2칸으로 세고 관찰 때만 flag와 count를 0으로 돌린다; 실패 send도 상한에 남는다 (1c′) | app/Sources/Core/ClaudeInjector.swift:102-130, 383-399, 411-468 |
| `FakeClaudeSession`의 시각 줄 wrapping | ASCII는 1칸, 나머지 비제어 Character는 2칸으로 pane cell width를 누적해 마지막 시각 줄을 지운다; 이는 일반 터미널 폭 동작이며 Claude 전용 측정이 아니다 | app/Tests/CoreTests/CoreTests.swift:2517-2549 |
| tty 열 수 조회와 K 계산·20열 fallback | `ClaudeSessionIO.terminalColumns`가 tty size를 읽고, 실패하면 fallback 후 K를 계산한다; Ctrl+U는 write당 최대 8개 | app/Sources/Core/ClaudeInjector.swift:85-115, 266-310, 1179-1182, 1228-1238 |
| marker clear, retry pre-clear | marker 실험이 관찰한 marker와 이전 소유량을 같은 K 경로로 지우고, 재시도도 같은 실험을 거친다 | app/Sources/Core/ClaudeInjector.swift:468-493, 698-742 |
| `clearAbandonedInput` delivery-end cleanup | `mayHoldOurs`일 때 현재 누적 칸 수 상한과 K로 정리한다 | app/Sources/Core/ClaudeInjector.swift:354-371, 439-468 |
| 공통 clear batching과 cmux Ctrl+U burst / Backspace 분리 | 모든 chunk는 `send(_:io:)`를 지나며, cmux는 마지막 burst와 Backspace를 별도 RPC로 나눈다 | app/Sources/Core/ClaudeInjector.swift:31-115, 328-357, 1384-1405; app/Tests/CoreTests/CmuxTests.swift:395-435 |
| iTerm2 clear carrier | `claudeClearParts`가 1∼8개의 Ctrl+U batch를 분류하고 각 batch의 scalar를 AppleScript 한 `write text`로 쓴다 | app/Sources/Core/ClaudeInjector.swift:85-100, 1361-1370; app/Sources/Core/AppleScriptSupport.swift:121-152 |
| WezTerm clear carrier | 각 batch가 별도 `wezterm cli send-text --no-paste` call의 stdin이 된다 | app/Sources/Core/ClaudeInjector.swift:1378-1383 |
| Warp helper clear carrier | 각 batch가 별도 inject request bytes가 되고 helper는 큐가 빌 때까지 응답하지 않는다 | app/Sources/Core/ClaudeInjector.swift:1406-1424; app/Sources/WarpHelper/main.swift:123-175, 187-219, 244-245 |
| cmux clear carrier | 각 Ctrl+U batch는 하나의 `surface.send_text` operation이고 Backspace는 별도 operation이다 | app/Sources/Core/ClaudeInjector.swift:63-83, 1384-1405; app/Tests/CoreTests/CmuxTests.swift:395-435 |
| `FakeClaudeSession` visual-line clear model | Ctrl+U 한 번이 마지막 시각 줄 하나를 지우도록 바뀌었다 | app/Tests/CoreTests/CoreTests.swift:2369-2532 |
| 사용자 draft가 K보다 긴 경우 | 잔여: K는 우리 전송 시도만 세므로 그보다 긴 사용자 draft는 남을 수 있다; #16과 같은 부류이며 이번 구현에서 제거하지 않는다 | app/Sources/Core/ClaudeInjector.swift:369-382, 448-456 |
| 1c에서 바꾼 public 선언의 접근 수준 | `iTermClearInputScript(sessionID:keys:)`는 public `String` 인자를 명시적으로 받는다; `ClaudeSessionIO.terminalColumns`와 initializer 인자는 public closure/value types이며, `submitClaudeInputs`·`deliverClaudeInputs`의 public signatures도 public types만 쓴다; 점검한 두 파일에 public `@inlinable` body는 없다 | app/Sources/Core/AppleScriptSupport.swift:134; app/Sources/Core/ClaudeInjector.swift:269-310, 401-405, 1082-1090 |
| pane limit, create/found preconditions and fallback selector | The explicit limit is 25, separate from the equal-valued batch limit; the >25 tab guard remains in case the batch limit grows before larger pane geometry is measured | app/Sources/Core/CmuxPlacement.swift:90, 299, 315, 336, 391, 399; app/Sources/Core/Request.swift:29, 112 |
| found-split executor and item result mapping | planner는 root를 DFS leaf 0에 두고 `itemSurfaceOrder`에서 제외한다; N개 split response만 N개 item route와 handle로 간다. `.root` fail-closed 분기는 추가하지 않았다 — 실행 경로는 planner 결과를 쓰며 planner가 root leaf를 검증하고 제외한다; public resolver의 일반 `.root` 매핑은 유지한다 | app/Sources/Core/CmuxPlacement.swift:330-381; app/Sources/Core/CmuxGroupedExecution.swift:203-218, 511-568 |
| found fixed-name tab-per-item | found workspace route chooses the requested pane, then creates one new surface per item; each item command and handle uses that returned surface, not the existing root | app/Sources/Core/CmuxGroupedExecution.swift:706-773 |
| always-new and fixed-name not-found pane-per-item | layout creation launches new surfaces; `enumeratedSurfaceIDs` pairs them with `leafItemOrder` before `itemResults` sends any guarded command | app/Sources/Core/CmuxGroupedExecution.swift:474-508, 489-500, 604-654 |
| workspace-per-item | creates a workspace for each source item and uses that create response surface for its command and returned handle | app/Sources/Core/CmuxGroupedExecution.swift:784-843 |
| splitOperations.count consumer | only sizes `responseSurfaceIDs` before iterating the plan; it now equals N. Updated split-count expectations are listed in placement route tests; documentation statement at cmux-integration.md:211 is deferred to 3′ | app/Sources/Core/CmuxGroupedExecution.swift:536-568; app/Tests/CoreTests/CmuxPlacementTests.swift:130, 199-229; app/Tests/CoreTests/CmuxGroupedExecutionTests.swift:293, 482-483 |
| results-to-Claude handle mapping | `itemResults` zips command index to ordered surface ID and returns that handle; HostServer indexes `execution.results` with the corresponding prepared item before `deliverClaudeInputs` | app/Sources/Core/CmuxGroupedExecution.swift:391-435, 557-568; app/Sources/App/HostServer.swift:389-416 |
| HostServer placement log | 로그는 `execution.path`와 fallback 상태만 기록하며 surface를 선택하지 않는다 | app/Sources/App/HostServer.swift:382-387 |
| extension pane cap duplication | No matching limit or pane-fallback selector exists in extension sources | rg `cmuxPanePlacementItemLimit` and pane fallback terms across `extension/` |
| placement route tests | 새 integration test 하나가 N=1, 9, 25 found pane 실행을 확인한다; 위의 기존 5개 found plan·execution 기대를 N split 및 root 제외로 갱신했다. `docs/context/cmux-integration.md:211`의 N=25 “24 balanced splits” 문구는 문서 항목 3′에서만 고친다 | app/Tests/CoreTests/CmuxPlacementTests.swift:110-235; app/Tests/CoreTests/CmuxGroupedExecutionTests.swift:217-496; docs/context/cmux-integration.md:211 |
| changed public placement declaration | public 함수 시그니처와 타입은 바뀌지 않았다; `cmuxFoundWorkspacePanePlan` 구현만 N+1 leaf를 만들도록 바뀌었다 | app/Sources/Core/CmuxPlacement.swift:335-381 |
| current-state placement and pane-proof documentation | 2′ 구현과 P3 문장 정정은 항목 3′에서만 문서화하며, N=25 found의 24-split 서술도 그때 갱신한다 | docs/context/cmux-integration.md:211, 229; CLAUDE.md:68-69; docs/new-terminal-checklist.md |
| completed PR #80 plan's N>8 statement | 역사 기록으로 유지 | docs/plans/cmux-placement-preset.md:1-6, 29, 70-80, 108-110 |
| Claude merge algorithm | 유지; plan output and shell equivalence do not change | app/Sources/Core/ClaudeInputPlan.swift:280-325 |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — 드라이버 · 미커밋 초안 · 리뷰 16:20∼16:45 · 왕복 0 · 원문 /private/tmp/short-pane-loop/r1-assign.md

- 반박: R0-1 반사 확인 설계 과잉 · R0-2 ! 전송 · R0-3 비우기 확인 방식 · R0-4 승격 단위 · R0-5 네 터미널 실측 · R0-6 상한·B1 · R0-7 원천 · R0-8 형식
- 처리: R0-1 기각(D2) · R0-2 기각(D3) · R0-3 기각(D4) · R0-4 반영(D5) · R0-5 기각(D6) · R0-6 반영(열린 질문 B1) · R0-7 반영 · R0-8 반영
- 실측: 드라이버 C1·C2·D1·D2·B1 (measurements.md) · node --test exit 0 · 323
- 판정: R0 처리 반영으로 시작하는 데 합의한다

### R1

#### 리뷰 1 — 증분 · 1a 커밋 · 드라이버 · 리뷰 17:05∼17:25 · 왕복 1 · 원문 /private/tmp/short-pane-loop/r3-assign.md

- 차단: 접힘 테스트 대역이 공백 포함 24자만 렌더해 새 코드에서 실패 · 읽기 실패 시 창을 계속 도는 무배정 동작 변경 · 근거 주석 삭제 · 측정 수치 다섯 곳 중복
- 수정: 항목 1a (배정 16:58 · 완료 17:16)
- 실측: swift test exit 0 · CoreTests 535 · AppTests 132 · node 323 · 토글 새 테스트 2개 red
- 판정: 막혔다. 우회 없음 → 항목 1a cleared

#### 리뷰 2 — 증분 · 1b 커밋 · 드라이버 · 리뷰 17:45∼17:55 · 왕복 0 · 원문 /private/tmp/short-pane-loop/r5-assign.md

- 차단: 기존 테스트 하나가 `!` 단일 전송 기대값
- 수정: 항목 1b (배정 17:25 · 완료 17:40)
- 실측: 토글 새 테스트 red · Swift는 1b 커밋에서 드라이버 재실행
- 판정: 막혔다. 우회 없음 → 항목 1b cleared

#### 리뷰 3 — 증분 · 1c·1c′ 커밋 · 드라이버 · 리뷰 18:20∼18:55 · 왕복 2 · 원문 /private/tmp/short-pane-loop/r6-assign.md, r7-assign.md

- 차단: public 함수 기본 인자가 internal 상수 참조(컴파일 실패) · K를 글자 수로 세어 두 칸 문자에서 모자람(한글 120자, 38열에서 두 줄 남음)
- 수정: 항목 1c (배정 17:50 · 완료 18:17), 1c′ (배정 18:35 · 완료 18:50)
- 실측: swift test exit 0 · CoreTests 539 · AppTests 132 · 토글 2종 red
- 판정: 막혔다. 우회 없음 → 항목 1c·1c′ cleared

#### 리뷰 4 — 증분 · 2 커밋 · 드라이버 · 리뷰 18:50∼19:00 · 왕복 0 · 원문 /private/tmp/short-pane-loop/r9-assign.md

- 차단: 없음
- 수정: 항목 2 (배정 18:47 · 완료 18:50)
- 실측: swift test CoreTests 541 · AppTests 132 · 토글 red · 라이브 sent 4 of 4
- 판정: 막혔다. 우회 없음 → 항목 2 cleared

#### 리뷰 5 — 증분 · 3 커밋(4b282b2 및 이번 커밋) · 드라이버 · 리뷰 19:20∼19:55 · 왕복 2 · 원문 /private/tmp/short-pane-loop/r10-assign.md, r11-assign.md

- 차단: 문서가 지운 측정 사실(Backspace 이유·`/`·`#` 추론·PR #60·2.1.238 '비어 보임'), 없는 테스트 이름 인용, 범위 밖 문구 수정, 오늘 측정의 출처·버전 오귀속(#69·0.64.22)
- 수정: 항목 3 (배정 19:22 · 완료 19:40), 항목 3 보정 (배정 19:55)
- 실측: 실제 실행기 25개 배치 — always-new layoutCreate 4.4s·found foundSplit 5.7s, 둘 다 25/25(measurements.md P1)
- 판정: 4b282b2는 위 차단 외 통과 — 보정 커밋 확인 후 항목 3 판정

### R2

#### cold review 1 — 최종 bd302f6 · read_codex 새 스레드 01a0fc47 · 20:02∼20:20 · 원문 /private/tmp/short-pane-loop/cold-response.md

- 판정: no — P1(B, 차단) found 경로 항목 0이 기존 첫 surface로, P3(B, 비차단) pane proof 문서
- 처분: 사용자 D10·D11 → 항목 2′·3′

#### 리뷰 6 — 증분 · 2′ · 드라이버 · 리뷰 20:40∼20:55 · 왕복 0 · 원문 /private/tmp/short-pane-loop/r12-assign.md, r13-assign.md

- 차단: 없음
- 수정: 항목 2′ (배정 20:25 · 완료 20:36)
- 실측: swift test 542/132 · 토글 red · 라이브 P2 전/후
- 판정: 막혔다. 우회 없음 → 항목 2′ cleared

## 열린 질문

4. **N=25 pane 경로와 live geometry.** 이미 주어진 cmux layout 관찰은 N=9∼16 전부 76 columns, N=17∼25 일부 38×20, N=25는 18개 38-column과 7개 76-column이며 25-leaf `workspace.create`를 한 번 받아들였다. 항목 2 구현 뒤 드라이버는 N=9,16,17,25의 always-new와 fixed-name found 경로를 stable 및 NIGHTLY에서 확인하고 surface 수·item 순서·geometry·부분 실패를 기록한다. pane 크기를 확인하려면 workspace가 보여야 하므로 실행 전에 사용자에게 알리고 화면에 연다. N=25 found route가 실패해도 상한 25를 임의로 낮추지 않고 사용자 판단 후보로 올린다.
   처분 — 드라이버 실측(2026-10-02, 실제 실행기 `runCmuxBatch`, 백그라운드): always-new N=25 `layoutCreate` 4.4s·found N=25 `foundSplit` 5.7s, 둘 다 25개 surface가 자기 항목 마커만 보임. found 화면 크기·NIGHTLY는 미측정 → 체크리스트. 원문 measurements.md P1
B1. **focus:false pane size.** `focus:false` workspace의 pane은 사용자가 보기 전까지 layout과 무관하게 cmux 기본 106×39이고, 1초 보여 줬다 되돌려도 106×39였다 — 이때 Claude composer의 높이와 줄바꿈은 layout 크기와 다르다. tail reflection과 K 기반 clear가 그 상태에서도 맞는지, tty 열 수 조회가 106을 반환해 K를 과소 산정하는지 확인한다. 드라이버 판단은 tty의 106열을 쓰면 문제가 없다는 것이지만 실측 전 질문으로 남긴다.

원 요구 충족 후 발견된 마이너·에지케이스 방어 후보는 여기 적립한다(즉시 배정 금지) — 사용자 대화로 포함/이슈/기록 중 처분이 정해지면 그 결과를 원장에 남기고 지운다.
