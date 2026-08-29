# cmux-send-gate

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: `/Users/choongjaelee/Codes/terminal-checkout-cmux-send-gate-work`
- 시작 커밋: `0a9e142`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/cmux-send-gate-review` (`worktree-cmux-send-gate-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-cmux-send-gate-work` (`cmux-send-gate-work`)
- 현재: cold yes — 종결 절차(계획 파일 삭제 → 머지 → PR) 진행
- 최근 검증자 판정: cold 재판정 yes · 차단 0건 · 원문 /Users/choongjaelee/.claude/scratchpads/cmux-send-gate-loop/cold2-out.json

이 파일은 실행한 계획과 실행할 계획의 기록이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실을 기록한다. 코드 수정 과정을 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다.

## 배경 — 확인한 원천

- [PR #64](https://github.com/dazebug/terminal-checkout/pull/64) — 1024바이트를 초과하는 cmux payload가 canonical line에서 잘리는 결함과 raw-mode 대기 게이트가 도입된 변경이다.
- [`CmuxControl.swift`](../../app/Sources/Core/CmuxControl.swift) — `darwinCanonicalLineLimit`, `CmuxCommandGate`, `cmuxCommandSendGate`의 현재 판정 순서와 case 집합이 있다.
- [`TerminalRunner.swift`](../../app/Sources/Core/TerminalRunner.swift) — `cmuxAwaitShellReading`의 폴링 경계와 `runInCmux`의 gate별 로그·전송 분기가 있다.
- [`CmuxTests.swift`](../../app/Tests/CoreTests/CmuxTests.swift) — 기존 raw-mode 및 deadline 경계 테스트가 있으며, 작은 payload의 새 즉시 반환 기대값으로 갱신할 대상이다.
- [`cmux-integration.md`](../context/cmux-integration.md) — “The send waits for raw mode” 결정의 이유·기각 대안·결과를 보존하는 정본이다.
- [`CLAUDE.md`](../../CLAUDE.md) — cmux command text가 raw mode 뒤에만 전송된다고 현재 서술하는 운영 제약이다.
- [`README.md` Development](../../README.md#development) — `cd app && swift test`와 `node --test`의 검사 명령 정본이다.

## 목표

- raw mode가 관측되면 payload 크기와 무관하게 `cmuxCommandSendGate`가 즉시 `.send`를 반환한다.
- raw mode가 관측되지 않았어도 `payloadByteCount <= darwinCanonicalLineLimit`이면 deadline 전 폴링 없이 `.sendDespiteCanonical`을 반환하고, 호출부는 이 경로를 구분해 로그한다.
- 한도를 초과한 payload만 기존대로 raw mode 관측 전에는 `.waitLonger`, deadline 만료 후에는 `.refuseTooLong`이 된다.
- 게이트 경계 테스트를 TDD로 갱신하고, 결정 문서와 `CLAUDE.md`의 raw-mode 서술을 새 동작과 일치시킨다.

## 완료의 정의

- 반드시 재현해 막아야 하는 실패: `cmuxCommandSendGate(rawModeObserved: false, deadlineExpired: false, payloadByteCount: darwinCanonicalLineLimit)`가 현재 `.waitLonger`를 반환해 작은 payload도 폴링에 들어가는 대신 `.sendDespiteCanonical`을 즉시 반환해야 하며, `cmuxCommandSendGate(rawModeObserved: nil, deadlineExpired: false, payloadByteCount: darwinCanonicalLineLimit)`도 현재 `.waitLonger`에서 `.sendDespiteCanonical`으로 바뀌어야 한다. 두 입력을 red 테스트로 고정한다.
- acceptance oracle: 먼저 새 작은-payload 기대 테스트를 추가한 `cd app && swift test`가 non-zero로 red인지 확인하고, 구현 뒤 같은 명령이 exit status 0인지 확인한다. 최종 `cd app && swift test`와 `node --test`의 성공·실패는 출력 검색이 아니라 exit status로 판정하며, 실행된 테스트 수를 별도로 기록한다.
- 코퍼스 범위: `app/Tests/CoreTests/CmuxTests.swift`의 canonical-limit 게이트에 대해 raw `{true, false, nil}`, payload `{darwinCanonicalLineLimit, darwinCanonicalLineLimit + 1}`, deadline `{false, true}`의 경계와 기존 raw send·oversize refuse 기대를 포함한다.
- 원자성·부분 실패·롤백 경계: 게이트 함수는 순수 판정이므로 자체 롤백은 N/A다. `runInCmux`는 게이트가 끝난 뒤에만 `surface.send_text`를 호출하고 `.refuseTooLong`의 기존 동작(이미 만든 workspace 뒤 visible failure와 빈 tab 하나)을 유지하며, 재시도·추가 workspace 생성은 범위에 넣지 않는다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

이 루프가 막는 실패를 일으킬 수 있는 행위자는 cmux shell integration과 그 위의 앱 실행 경로다. 새로운 외부 행위자는 도입하지 않는다.

- cmux shell integration 또는 shell 초기화: `debug.terminals`의 tty 보고와 raw-mode 전환을 늦춰 `rawModeObserved`가 deadline 전까지 false 또는 nil로 남길 수 있다.
- Chrome에서 버튼을 누른 사용자와 앱의 `runInCmux`: 작은 payload를 기존 gate에 전달해 불필요한 폴링 지연과 해당 로그를 발생시키는 실제 소비 경로다.

## 비목표 — 건드리지 않는다

- `darwinCanonicalLineLimit`의 값과 Darwin canonical-mode 측정: 1024바이트 및 CR 포함 경계를 재측정하거나 바꾸지 않는다.
- 한도를 초과한 payload의 안전성 동작: raw mode 전 대기, deadline 후 `.refuseTooLong`, 전송 전 visible failure를 바꾸지 않는다.
- workspace 생성·socket pinning·cmux RPC method·tty discovery·`surface.send_text` payload 조립과 cmux 이외의 terminal 경로: 이번 게이트의 판정 순서와 호출부 로그에 필요한 범위만 읽는다.
- 새 실측, 새 로그 수집기, 실제 cmux pane 수동 검증, extension 변경: 이미 제공된 Darwin 측정과 기존 테스트·게이트만 사용한다.
- 이번 R0: 코드·기존 문서·계획 파일 외의 파일을 수정하거나 커밋하지 않는다. 계획 종결 때 계획 파일을 삭제하는 일은 항목 3에서만 수행한다.

## 불변 원칙

- gate 판정 순서는 고정한다: `rawModeObserved == true`이면 먼저 `.send`; 그 밖에 payload가 `darwinCanonicalLineLimit` 이하이면 deadline 값과 무관하게 `.sendDespiteCanonical`; 그 밖에 deadline 전이면 `.waitLonger`; deadline 후이면 `.refuseTooLong`이다.
- `.send`는 raw mode 관측 경로만 뜻하고 로그 없이 유지한다. `.sendDespiteCanonical`은 nonraw 상태에서 canonical limit 안에 들어 즉시 보내는 경로로 재사용하며, `runInCmux`에서 “기다리지 않고 한도 안에서 보낸다”는 상황을 별도 로그로 남긴다.
- `payloadByteCount`는 `runInCmux`가 넘기는 command와 CR을 합친 payload의 UTF-8 바이트 수다. 문자 수, command body만의 길이, 임의의 새 한도를 사용하지 않는다.
- `cmuxAwaitShellReading`은 gate가 `.waitLonger`일 때만 계속 폴링한다. 작은 payload의 반환값이 `.sendDespiteCanonical`이어야 하며 helper 자체에 별도 sleep 우회를 넣지 않는다.
- 기존 raw-mode true 전송과 oversize 대기·거부, `.refuseTooLong` 오류 문구의 안전한 의미를 회귀시키지 않는다. `.waitLonger`의 방어적 호출부 분기는 gate의 반환 계약을 소비하는 지점으로 함께 심사한다.
- TDD 순서를 지킨다: `CmuxTests.swift`에 현재 구현을 실패시키는 작은-payload 테스트를 먼저 추가하고 `cd app && swift test`의 exit status로 red를 확인한 다음 Core와 호출부를 수정해 green을 확인한다. 출력의 TAP 또는 `fail` 문자열로 판정하지 않는다.
- Swift gate의 실측은 드라이버가 담당한다. 구현자 샌드박스에서 발생한 환경 실패를 구현 회귀나 green으로 반올림하지 않으며, 최종 gate의 실행 테스트 수와 exit status를 원문 그대로 기록한다.
- `docs/context/cmux-integration.md`는 keep-the-why 형식의 active/confirmed 결정과 기각 대안을 유지하면서 이번 원인과 consequence를 갱신하고, `CLAUDE.md`는 코드·문서 주석을 영어로 유지한다. 이 계획 문서만 한국어로 쓴다.
- 파일 범위는 항목 1의 세 파일, 항목 2의 두 문서, 종결 시 항목 3의 계획 파일로 제한한다. amend commit은 하지 않는다.

## 배치 점검 (0라운드)

모드: ultrafast

이 표의 실측 주체는 드라이버다 — 구현자가 채우는 행은 「에이전트 첫 보고」뿐이고, 자기 샌드박스의 실패로 드라이버 실측 값을 덮어쓰지 않는다.

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored | ignored — 드라이버 실측(스킬 점검 블록). 규칙은 메인 리포 `.git/info/exclude`에 있어 워크트리(기준 트리)는 공유하고 clone에는 복사되지 않는다; clone은 `.claude/worktrees/`를 만들지 않으므로 무관 |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 설정됨 — Claude Code 사용자 설정(`~/.claude/settings.json`)이지 git config가 아니다(clone의 `git config` exit 1은 그래서다). 기준 트리가 로컬 HEAD `0a9e142`에서 분기했고 첫 보고 HEAD도 `0a9e142`로 일치 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-cmux-send-gate-work` · `cmux-send-gate-work` · `0a9e142` |
| 리포 오버레이 `.claude/drive-agent-loop.md` | 이번 R0 초안과 함께 작성됨 |
| cmux 패널 | `cmux markdown open <작업 트리 계획 파일>` → OK surface:22 pane:18 |
| 트리마다 의존성 동기화 (기준·작업) | 해당 없음 — `app/Package.swift`에 외부 dependency가 없고 `Package.resolved`가 없다. |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) | 해당 없음 |
| 증분 리뷰 소요(분) — 첫 세 번 | R0 초안 단계라 해당 없음 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | 게이트 재정렬 + 호출부 로그 + TDD red→green | 게이트 판정·호출부 | (a) raw mode가 아직 관측되지 않은 한도 이내 payload가 deadline 전에도 `.waitLonger`가 되어 불필요하게 10초 폴링한다. (b) `runInCmux`의 `.sendDespiteCanonical` 로그 문구가 'never reported raw mode within 10s'라고 대기를 주장한다 — 새 동작(즉시 전송)에서는 거짓 로그가 된다. 대기 주장 없는 문구로 교체(예: sending N bytes inside the canonical line limit without waiting for raw mode). | `app/Sources/Core/CmuxControl.swift` · `app/Sources/Core/TerminalRunner.swift` · `app/Tests/CoreTests/CmuxTests.swift` | — | agreed | red 재실행(드라이버): cd app && swift test → exit 1, 557 tests, failures 2 (CmuxTests.swift:549·556, waitLonger ≠ sendDespiteCanonical)<br>green 재실행(드라이버): cd app && swift test → exit 0, 557 tests, 0 failures<br>토글(드라이버, 기준 트리): git apply -R(86df7cc의 CmuxControl 훅) → swift test exit 1·557 tests·failures 2(CmuxTests.swift:549·556 동일 2건) → git apply 재적용 → porcelain clean. 소탕 재확인: rg로 producer 1(cmuxCommandSendGate)·polling consumer 1(cmuxAwaitShellReading)·switch 1(runInCmux)만 존재 | — |
| 1a | raw-mode probe 낡은 대기 서술 소탕 | 게이트 판정·호출부(낡은 서술 소탕) | `cmuxRawModeProbeArguments` 주석이 모든 명령이 deadline까지 기다린다고 잘못 주장한다. | `app/Sources/Core/TerminalRunner.swift` | 1 | agreed | rg -n 'every command wait' app/Sources → 0건(수정 후)<br>전체 상태 확인 판정: 위 리뷰 4 판정 줄 | — |
| 2 | 결정 문서와 운영 서술을 새 gate case 의미에 맞게 갱신 | 문서·결정 기록 | 현재 “raw mode 뒤에만 전송” 및 “deadline까지 기다린다”는 서술이 한도 이내 즉시 전송을 누락한다. | `docs/context/cmux-integration.md` · `CLAUDE.md` | 항목 1의 `.sendDespiteCanonical` 의미 확정 | agreed | rg 재확인: 두 문구가 새 서술로 대체됨, `rg -n "sent only after|waits for raw mode" CLAUDE.md docs/context/cmux-integration.md` 결과 줄: `CLAUDE.md:61`, `docs/context/cmux-integration.md:27`, `docs/context/cmux-integration.md:35`<br>green 재실행(드라이버, 문서 변경 후): cd app && swift test → exit 0, 557 tests, 0 failures<br>드라이버 리뷰 2: 두 문서의 새 서술이 게이트 구현과 일치함을 diff·rg로 확인 | — |
| 3 | 종결: 테스트 심사 + 계획 파일 삭제 | 종결 | — | `app/Tests/CoreTests/CmuxTests.swift` · `docs/plans/cmux-send-gate.md` | 항목 1·2·4·5 | todo | 종결 재실행: `cd app && swift test`와 `node --test`; 각 exit status와 실행 테스트 수를 기록한 뒤 이 계획 파일만 삭제한다. | — |
| 4 | cold-1: cmux 입력 tty 창 30s 복원 | 입력 경로 시간 창 | cold 차단 1 (B) | `app/Sources/Core/ClaudeInjector.swift` · `docs/context/cmux-integration.md` | 1 | agreed | 근거: rg -n "cmuxTTYWaitTimeout" → 30, 주석·Consequence 갱신<br>전체 상태 확인 판정: 위 리뷰 4 판정 줄 | — |
| 5 | cold-2: `.waitLonger` 분기 판정 복제 제거 | 게이트 판정·호출부 | cold 차단 2 | `app/Sources/Core/TerminalRunner.swift` | 1 | agreed | 근거: rg -n "darwinCanonicalLineLimit" app/Sources/Core/TerminalRunner.swift → runInCmux switch 안 0건<br>전체 상태 확인 판정: 위 리뷰 4 판정 줄 | — |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다.
- `의존`은 항목의 계약을 전제할 때만 적는다. 항목 2는 항목 1에서 확정한 `.sendDespiteCanonical`의 새 의미를 문서에 반영해야 한다.
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`다.
- `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다. `verified`·`cleared`·`agreed`·`dropped`는 드라이버 판정이다.
- 근거는 재실행 가능한 명령·결과 줄·테스트 이름·수치로만 보강한다. 아직 실행하지 않은 red·green 결과를 미리 적지 않는다.

## 결정 원장

append-only — 첫 승격 이후부터다. 이 R0 초안에는 아직 인용된 판정이 없으므로 아래 행은 이번 배정에서 확정된 사용자·드라이버 결정을 기록한다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | 한도 이내 payload까지 raw-mode deadline을 기다리면 shell integration 지연이 안전성을 높이지 않고 지연만 만든다. | raw mode true이면 `.send`; 그 밖에 `payloadByteCount <= darwinCanonicalLineLimit`이면 즉시 `.sendDespiteCanonical`; 한도 초과만 deadline 전 `.waitLonger`, 만료 후 `.refuseTooLong`으로 판정 순서를 고정한다. | 배정문 2026-08-30 03:31 실측(총 24.7초 중 gate 10.4초, 317바이트 payload); PR #64 / `0a9e142`; `app/Sources/Core/CmuxControl.swift:237-242` | 없음 |
| D2 | 드라이버 | 즉시 전송을 `.send`로 합치면 raw 관측 전송과 canonical-safe 전송의 로그가 합쳐진다. | 기존 `.sendDespiteCanonical` case를 별도 즉시 전송 case로 재사용한다. `.send`는 로그 없이 유지하고, `runInCmux`는 `.sendDespiteCanonical`에서 대기하지 않고 한도 안에서 보냈음을 로그한다. | 배정문 driver 의견; `app/Sources/Core/CmuxControl.swift:224-242`; `app/Sources/Core/TerminalRunner.swift:577-603` | 정확한 영어 로그 문구는 기존 `checkoutLog` 어휘를 따르는 구현 세부다. |
| D3 | 사용자 | 기존 결정 문서와 운영 규칙은 raw mode 대기를 모든 payload에 적용하는 것으로 읽힌다. | `docs/context/cmux-integration.md`의 해당 결정 항목과 `CLAUDE.md`의 cmux 문장을 새 판정 순서·case 의미·oversize 안전성에 맞춰 갱신하고, keep-the-why의 기각 대안과 accepted consequence를 유지한다. | 배정문 결정; `docs/context/cmux-integration.md:27-47`; `CLAUDE.md:61` | 항목 1의 case 의미가 문서 갱신 전에 확정되어야 한다. |
| D4 | 드라이버 | 종결 전 테스트 심사 — 이 루프의 테스트 diff 4함수 심사 | 전부 유지, 삭제 0건: `testCommandSendGateSendsWithinCanonicalLimitWithoutWaiting`=(i) 토글 red 실증(557/2), `testCommandSendGateSendsImmediatelyWhenRawModeIsObserved`·`testCommandSendGateWaitsOnlyForOversizedPayloadBeforeDeadline`·기존 `testCommandSendGateFallsBackBySizeAtTheDeadline`=(ii) 불변 원칙이 이름으로 부르는 계약(raw 즉시 send·초과만 대기·deadline 폴백) 고정, 경계당 대역 0 | 토글 로그 /Users/choongjaelee/.claude/scratchpads/cmux-send-gate-loop/toggle-red.log · 리뷰 2 | 없음 |
| D5 | 드라이버 | 한도 이내 payload도 `cmuxAwaitShellReading` 첫 반복의 관측 1회(debug.terminals RPC + 조건부 stty)는 수행한다 | 수용 — 폴링(sleep) 없음, 관측 1회는 수십 ms급이고 사전 short-circuit은 판정 로직을 게이트 밖에 복제한다(판정은 단일 함수 원칙) | `app/Sources/Core/TerminalRunner.swift:489-521` · 리뷰 2 | cmux 서버가 debug.terminals에 수 초간 무응답이면 그만큼 늦는다 — 직전 workspace.create가 성공한 서버라 실측상 무시 가능 |
| D6 | 드라이버 | cold 차단 1: 게이트 10s 제거가 claude 입력 tty 창을 30→20s로 줄였다(정적 확정) | cmuxTTYWaitTimeout 20→30으로 창을 명시 복원 — 새 테스트 없음(private 상수 핀은 진입점 검증이 아니고, 창의 정본은 주석·결정 문서) | HostServer.swift:197·ClaudeInjector.swift:1116 · cold 리뷰 | shell integration 없는 pane은 포기 로그까지 30s(백그라운드) |
| D7 | 드라이버 | cold 차단 2: 도달 불가 분기의 판정 복제 | 분기 본문을 내부 불일치 throw로 교체 — 3-case enum 신설은 기각(churn > 이득, 판정 주체는 불변) | TerminalRunner.swift:585 · cold 리뷰 | 없음 |

## 전수 소탕 표

게이트 판정을 소비하거나 그 의미를 고정하는 모든 지점을 확인했다. 추가 소비 지점은 현재 검색에서 발견되지 않았다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `cmuxCommandSendGate` 호출자 `cmuxAwaitShellReading` | 항목 1 대상 | `app/Sources/Core/TerminalRunner.swift:487-517`; `.waitLonger`일 때만 polling loop가 계속된다. |
| `CmuxCommandGate` case를 switch하는 `runInCmux` | 항목 1 대상 | `app/Sources/Core/TerminalRunner.swift:577-610`; `.send`는 무로그, 비raw safe-send와 oversize 처리는 별도 로그·실패 경계를 갖는다. |
| 결정 문서 서술 | 항목 2 완료 | `docs/context/cmux-integration.md:27-47`; 제목·본문·Reason·기각 대안·Consequence를 새 raw-mode 대기 경계와 2026-08-30 실측에 맞춰 갱신했다. |
| 운영 서술 | 항목 2 완료 | `CLAUDE.md:61`; 한도 이내 즉시 전송과 한도 초과의 raw-mode 대기·deadline 거부를 한 논리 줄로 갱신했다. |
| 그 밖의 `cmuxCommandSendGate`·`CmuxCommandGate` 참조 | 안전 | `rg -n "cmuxCommandSendGate|CmuxCommandGate|sendDespiteCanonical|waitLonger|refuseTooLong" app docs CLAUDE.md` 결과 위 네 지점 외에는 테스트와 정의만 있다. |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. R0 설계 리뷰에서 반박 5건을 모두 계획에 반영했고, R1 증분·최종 리뷰와 R2 cold 리뷰·재판정의 차단과 해소를 기록했다.

### R0

#### 설계 리뷰 — 미커밋 계획 초안 · 승격 없음 · 리뷰 완료 · 왕복 미기록

- 반박: R0-1 — 계획 헤더의 기준 트리가 작업 트리와 같은 경로로 적혀 있어 기준 트리와 작업 트리 경로·브랜치를 분리해 갱신했다.
- 반박: R0-2 — 배치 점검 표의 `git check-ignore`, `worktree.baseRef`, `cmux 패널` 행이 구현자 실측이어서 드라이버 실측 값으로 교체했다.
- 반박: R0-3 — 결정 원장 D2의 case 선택 주체가 사용자로 기록되어 드라이버로 정정했다.
- 반박: R0-4 — 항목 1에 `.sendDespiteCanonical`의 낡은 10초 대기 주장 로그를 확정 결함 (b)로 추가하고 대기 없는 문구로 교체하도록 명시했으며 `.waitLonger` 방어 분기는 건드리지 않도록 했다.
- 반박: R0-5 — 완료의 정의에 `rawModeObserved: nil`의 deadline 전 한도 경계를 추가하고 false·nil 두 입력을 red 테스트로 고정했다.
- 처리: 전부 반영(계획 수정)
- 실측: 구현 전이며 `cd app && swift test`는 구현자 샌드박스에서 실행하지 않는다. Swift gate는 드라이버가 담당한다.
- 판정: 드라이버 판정: 이 계획으로 시작하는 데 합의한다 — 반박 5건 반영 확인 후
- 원문: `/Users/choongjaelee/.claude/scratchpads/cmux-send-gate-loop/r0b-prompt.md`

### R1

#### 리뷰 1 — 증분 · 86df7cc · 승격 04:16 · 리뷰 04:16∼04:21 · 왕복 0 · 원문 없음(드라이버 직접)

- 차단: 없음
- 수정: 없음 (항목 1은 이 리뷰의 대상 승격분)
- 실측: 토글 red 557/2 재현·재적용 clean · green 557/0 · 소비 지점 3곳 소탕 일치
- 판정: "드라이버 판정(증분 ①②): 항목 1 차단 확인 — 게이트 재정렬이 red 2건을 막고, 새 표면의 우회 소비 지점 없음." → 항목 1 `cleared`

#### 리뷰 2 — 최종 · 86df7cc..9c4f272 · 승격 04:22 · 리뷰 04:22∼04:30 · 왕복 0 · 원문 없음(드라이버 직접)

- 차단: 없음 — 냉독·소탕(rg "deadline|wait")에서 낡은 주석 1건(TerminalRunner.swift:476)만 발견, 항목 1a로 배정
- 수정: 항목 1a (이 커밋에 포함)
- 실측: swift 557/0 (exit 0) · node 222/0 (exit 0) · 토글 red 557/2 재현 후 clean 복원 · 소비 지점 3곳 일치
- 판정: "드라이버 판정(최종 ③④): 원 요구 항목 1·2 차단 확인, 잔여 최고 심각도 결함 없음 — 합의한다(yes). 종결 관문은 cold review." → 항목 1a `cleared` 예정, 항목 1·2 `agreed`

### R2

#### 리뷰 3 — cold · 519b551 · 승격 04:31 · 리뷰 04:31∼04:44 · 왕복 1 · 원문 /Users/choongjaelee/.claude/scratchpads/cmux-send-gate-loop/cold-out.json

- 차단: ① 작은 payload 즉시 반환이 예약 claude 입력의 tty 탐색 창을 10s 축소(B — shell integration이 20s 넘게 늦는 pane에서 입력 소실, Chrome은 이미 성공 응답) ② `runInCmux` `.waitLonger` 분기가 게이트 판정을 크기 비교로 복제(불변식 위반, 도달 불가)
- 수정: 항목 4(cmuxTTYWaitTimeout 30s + Consequence 문장) · 항목 5(분기 본문을 내부 불일치 throw로)
- 실측: 드라이버 정적 확정 — HostServer.swift:197(전달은 runInCmux 반환 후 시작)·ClaudeInjector.swift:1116(20s)·TerminalRunner.swift:585(크기 재비교)
- 판정: "이 구현에 합의하는가: no" (cold 스레드 01a04f01-b0fd-7382-934f-6e2d860b6d66) → 항목 4·5 배정

#### 리뷰 4 — cold 재판정 · 5ce2c46 · 승격 04:48 · 리뷰 04:48∼04:57 · 왕복 1 · 원문 /Users/choongjaelee/.claude/scratchpads/cmux-send-gate-loop/cold2-out.json

- 차단: 없음 — 차단 2건 모두 닫힘 확인(30s 창 복원·판정 소유권 게이트 단독), 새 throw의 소비처 영향 없음(HostServer defer가 admission 반환)
- 수정: 비차단 주석 1건(ClaudeInjector.swift:1141 "100 lines in 20 seconds" → 150/30s) — 이 커밋
- 실측: swift 557/0 (exit 0) · node 222/222 (직전 실측 유효, extension 무변경)
- 판정: "재판정: 이 구현에 합의하는가: yes. … (A) 차단 또는 비차단 코드 결함 없음. (B, 비차단 주석 결함) ClaudeInjector.swift:1141 …" (cold 스레드 01a04f01-b0fd-7382-934f-6e2d860b6d66)

## 열린 질문

- 기능 설계·파일 범위에 남은 질문은 없음. `git check-ignore` exit 1과 `worktree.baseRef` 미설정은 배치 환경 점검 결과로 기록했으며, 기능 항목의 진행을 막지 않으므로 드라이버가 loop setup에서 별도 처분한다.
