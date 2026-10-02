# claude-input-cap

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: terminal-checkout의 Chrome extension 및 macOS app
- 시작 커밋: 4c3c722
- 기준 트리: /Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/claude-input-cap-review (worktree-claude-input-cap-review · 4c3c722) · 작업 트리: /Users/choongjaelee/Codes/terminal-checkout-claude-input-cap-work (claude-input-cap-work)
- 현재: R1 · 마지막 승격 d0690ac · 리뷰 중 없음 · 게이트 그린 (node 323 · check-locales · swift 132 — 항목 3 뒤 Swift는 드라이버가 종결 전에 다시 돈다)
- 최근 검증자 판정: R0 처리 반영으로 시작하는 데 합의한다 · 원문 /private/tmp/claude-input-cap-loop/r1-assign.md

이 파일은 **실행한 계획과 실행할 계획의 기록**이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실. 코드 수정 과정을 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다. 결정이나 질문이 특정 동작에 걸리면 한 절과 `파일:행`으로 끝낸다. 이 템플릿에 없는 소절을 만들지 않는다 — 테스트 설계는 테스트 파일이 말한다.

## 배경 — 확인한 원천

- [PR #90](https://github.com/dazebug/terminal-checkout/pull/90) — 저장 입력과 한 마디를 합쳐 클릭당 다섯 입력으로 제한한 원래 선택
- [docs/context/claude-input-delivery.md](../context/claude-input-delivery.md) — 한 마디의 자격, 전달 경로, 목록 표시, 결과 계약
- [docs/context/index.md](../context/index.md) — context 결정 문서의 정본 목록
- [README.md](../../README.md), [README.ko.md](../../README.ko.md), [README.zh-Hant.md](../../README.zh-Hant.md), [README.ja.md](../../README.ja.md) — 저장 입력과 한 마디의 사용자 설명
- [docs/new-terminal-checklist.md](../new-terminal-checklist.md) — 터미널별 한 마디 수동 확인 항목
- [docs/context/options-page-reordering.md](../context/options-page-reordering.md), [docs/context/testing.md](../context/testing.md) — 입력 행의 상한 참조와 red 토글 원칙

## 목표

- 저장 입력은 버튼당 최대 10개이고, 한 마디는 별도 한 칸이다. 각 세션이 받는 클릭 payload는 최대 11개이며 목록 배치의 합계에는 상한이 없다.
- Claude를 시작하는 유효 버튼은 저장 입력 개수와 관계없이 한 마디를 받을 수 있으며, content script와 worker는 같은 판정 함수를 쓴다.
- 사용자 제공 issue-list 버튼 값으로 한 마디 자격과 worker 요청의 입력 순서를 확인한다.
- 문서와 Warp helper 수명 설명이 새 상한과 현재 입력당 재시도 근거를 반영한다.

## 완료의 정의

- 반드시 재현해 막아야 할 실패: 사용자 제공 issueListButtons 버튼의 저장 입력 5개에서 buttonTakesClaudeNote가 false여서 ▾가 그려지지 않는다. 수정 전 red는 tests/claude-note.test.js의 해당 버튼 fixture에 대해 buttonTakesClaudeNote(...) === true를 요구하는 assertion이다. 기존 5개 클릭 상한으로 판정을 되돌리면 같은 assertion이 다시 실패해야 한다.
- acceptance oracle: 저장 reader가 입력 10개를 받아들이고 11개 버튼 전체를 건너뛰며, 실제 5개 입력 값과 경계값 10개에서 한 마디 자격이 true이고, worker가 저장 입력 뒤에 한 마디를 한 번 붙인 최대 11개 세션 payload를 native host에 보낸다. node --test --test-reporter=tap, node tools/check-locales.js 및 승인 후 issue-list 수동 확인을 기록한다.
- 코퍼스 범위: 사용자 제공 issueListButtons 값 1개와 저장 입력 5개를 테스트·소탕의 고정 fixture로 사용한다. 문자열을 정규화하거나 바꾸지 않는다. 새 10/11 경계 테스트에만 별도 경계 입력을 추가한다.
    {"claudeInputs":["!gh issue view {number}","!gh issue view {number} --comments","!gh api repos/{owner}/{repo}/issues/{number}/timeline --jq '[.[]|select(.event==\"cross-referenced\")|.source.issue.number]'","/rename {repo} Issue#{number}","이 이슈는 여전히 존재하는 이슈인가요?"],"command":"{cd} && claude --model opus","face":"📋","label":"이슈 분류"}
- 원자성·부분 실패·롤백 경계: 파일 수정 자체는 로컬이다. list batch는 하나의 요청으로 fan-out되고 일부 항목 결과를 가질 수 있으며 자동 재전송은 없다 (docs/context/claude-input-delivery.md:263-272, tests/worker-note.test.js:218-230). 이 루프는 그 재시도 계약을 바꾸지 않는다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

- GitHub issue-list에서 사용자 저장 버튼을 누르는 사람: 저장 입력이 5개인 claude 버튼에서 한 마디를 열려고 한다 (extension/content.js:504-523, extension/defaults.js:972-979).
- 옵션 사용자 또는 import 파일: 6∼10개 입력을 저장하거나, 긴 입력으로 issueListButtons 설정 키의 크기 제한에 닿는다 (extension/options.js:376, 1305-1314, extension/migrations.js:688-708).
- 다른 기기 또는 재로드 전 구버전 확장: storage.sync의 6개 이상 입력 버튼을 구버전 reader가 건너뛰고, 옵션에서 다음 저장 시 제거할 수 있다 (extension/defaults.js:801-819, extension/options.js:638-669, extension/migrations.js:189-192).
- 같은 uid의 로컬 프로세스: 현재 HostServer uid 경계 안에서 직접 요청을 보내거나 Warp helper 소켓에 입력을 넣을 수 있다. 이 경계는 기존과 같다 (app/Sources/App/HostServer.swift:190-205, app/Sources/WarpHelper/main.swift:32-36).
- 같은 uid 요청을 받는 앱 경로: Request.swift는 claude_inputs 배열 원소 수를 제한하지 않고 batch 항목은 최대 25개다. 프레이밍은 별도 16 MiB 상한을 둔다 (app/Sources/Core/Request.swift:27-29, 84-95, app/Sources/Core/Framing.swift:6, 19-27).

## 비목표 — 건드리지 않는다

- /Users/choongjaelee/Codes/terminal-checkout 및 /Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/claude-input-cap-review: 기준 조회만 하며 쓰지 않는다.
- 한 마디의 4,096 UTF-8 byte 제한과 변수·제어 문자 검증: extension/defaults.js:981-983, 1028-1038의 계약을 바꾸지 않는다.
- 앱의 입력 전달 프로토콜·터미널별 경로·프레임 상한: Core/ClaudeInputPlan.swift:343-347, 760-782, Core/Framing.swift:6, 19-27의 동작을 바꾸지 않는다.
- 앱 `claude_inputs` 원소 수 상한: 개수 상한은 확장 편집기의 한계지 안전 경계가 아니다 — 앱의 경계는 같은 uid다 (app/Sources/App/HostServer.swift:190-205, app/Sources/WarpHelper/main.swift 서두).
- 목록 batch의 최대 항목 수 25와 공통 입력 목록을 각 선택 세션에 전달하는 동작: Request.swift:27-29, 97-140, HostServer.swift:403-415의 계약을 바꾸지 않는다. 입력 상한 11은 세션(payload)당이고 batch 전체 합계 상한은 없다.
- Warp helper의 uid 신뢰 경계와 per-injection 8 KiB 상한: app/Sources/WarpHelper/main.swift:20-27의 계약을 바꾸지 않는다.

## 불변 원칙

- 저장 값 판정은 adoptStoredButtons 하나에서 유지한다. 옵션 import, content script, worker가 서로 다른 상한 판단을 만들지 않는다 (extension/defaults.js:801-819, 1235-1244; extension/migrations.js:688-708).
- content script와 worker는 buttonTakesClaudeNote라는 같은 함수로 한 마디 자격을 판단한다 (extension/content.js:790-795; extension/background.js:334-339).
- `MAX_CLAUDE_INPUTS`는 편집기·reader·import가 쓰는 버튼당 저장 상한이고 값은 10이다. 한 마디는 저장 칸을 쓰지 않으므로 `buttonTakesClaudeNote`는 정규화된 저장 입력 수가 `MAX_CLAUDE_INPUTS` 이하인지 확인한다. reader를 거친 버튼에서는 이 조건이 늘 참이고, reader를 거치지 않은 입력을 받는 호출자에 대한 fail-closed 가드로 남긴다. 한 세션의 클릭 입력은 최대 `MAX_CLAUDE_INPUTS + 1`이고 별도 상수는 두지 않는다 (extension/options.js:376, 1307; extension/defaults.js:814, 978, 1049-1063; docs/context/options-page-reordering.md:13).
- 사용자 제공 코퍼스는 그대로 사용한다. 테스트는 실제 5개 값의 판정 red와 저장 10/11 경계를 각각 고정한다.
- Warp의 per-input 순서와 확인 게이트, helper 종료 경로를 바꾸지 않는다 (app/Sources/Core/ClaudeInjector.swift:331-384, 387-486; app/Sources/WarpHelper/main.swift:49-52).
- 새 실행 경로가 생기는 경우의 수동 확인은 docs/new-terminal-checklist.md에 기록한다 (CLAUDE.md:46).

## 배치 점검 (0라운드)

모드: ultrafast

이 표의 실측은 드라이버가 채운다. 구현자 행만 R0 첫 보고에서 채운다.

| 점검 | 결과 |
|:--|:--|
| git check-ignore -q .claude/worktrees/probe → ignored | ignored (드라이버, 기준 트리) |
| 설정 worktree.baseRef: "head" — 에이전트 첫 보고의 git log --oneline -2가 기준 HEAD를 보이는가 | N/A — 작업 트리는 전용 clone. 첫 보고의 log가 기준 HEAD 4c3c722 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | /Users/choongjaelee/Codes/terminal-checkout-claude-input-cap-work · claude-input-cap-work · 4c3c722 |
| 리포 오버레이 .claude/drive-agent-loop.md — 기준 트리 경로 또는 드라이버 작성 · 커밋하지 않음 | `.claude/drive-agent-loop.md`는 리포에 커밋된 파일이라 점검 블록이 NOT ignored로 보고 — 이 루프는 수정하지 않는다 |
| cmux 패널 — cmux 신호가 켜졌을 때만 | surface:163 · pane:106 |
| 트리마다 의존성 동기화 (기준·작업) | N/A — 외부 의존성 없음 (app/Package.swift는 로컬 타깃만, node --test 무의존) |
| git 밖 로컬 자산 env (이름=절대경로) | 없음 |
| 증분 리뷰 소요(분) — 첫 세 번 | |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | 저장 입력 상한 `MAX_CLAUDE_INPUTS`를 10으로 올리고, 저장 입력 수와 무관하게 Claude 버튼에 한 마디 자격을 준다 | 확장 정책·worker/content 계약 | (a) `buttonTakesClaudeNote`가 저장+한 마디 ≤ 5를 요구해 실제 5개 버튼에 캐럿이 없다 (b) 저장 상한 `MAX_CLAUDE_INPUTS` 5 — 편집기·reader·import가 6개 이상을 거부 (c) worker 거절 문구 `CLAUDE_NOTE_NOT_TAKEN_ERROR`가 “no room for another input”을 말한다 (d) `content.js` 분할 버튼 머리 주석이 “room for one more input”을 말한다 | extension/defaults.js, extension/options.js, extension/background.js, extension/content.js, tests/claude-note.test.js, tests/buttons.test.js, tests/worker-note.test.js, tests/migration.test.js, tests/fixtures/saved-issue-list-buttons.json | — | cleared | red: `/opt/homebrew/bin/node --test --test-reporter=tap --test-name-pattern='issue-list button and both saved-input boundaries|saved issue-list button reaches the worker|saved-input cap accepts ten' tests/claude-note.test.js tests/worker-note.test.js tests/buttons.test.js` → exit 1, 세 새 테스트 실패. green: `/opt/homebrew/bin/node --test --test-reporter=tap` → exit 0, 323 passed; `/opt/homebrew/bin/node /Users/choongjaelee/Codes/terminal-checkout-claude-input-cap-work/tools/check-locales.js` → exit 0, all 5 live catalogues match. Toggle: `git -C /Users/choongjaelee/Codes/terminal-checkout-claude-input-cap-work apply -R /Users/choongjaelee/Codes/terminal-checkout-claude-input-cap-work/.git/toggle.patch` 후 full node gate exit 1 (319 passed, 4 failed: 세 새 테스트와 `only normalized saved inputs count against the button cap`); patch 재적용 exit 0, full node gate exit 0, 323 passed. `git diff --check` exit 0. 재실행(드라이버): clone node --test exit 0 · 323, check-locales exit 0; 스크래치 사본에 옛 defaults.js → exit 1 · 4 fail, worker 실패 사유 'takes no claude note' | |
| 2 | 사용자 문서·context 결정·issue-list 수동 확인을 새 정책에 맞춘다 | 제품 문서·체크리스트 | (a) README 네 언어의 “최대 5개” (b) README 네 언어의 “입력을 하나 더 넣을 여유(클릭당 다섯)” (c) `docs/context/claude-input-delivery.md`의 상한 문단과 결정 근거·기각 대안 (d) `docs/new-terminal-checklist.md`의 “다섯 입력 버튼에는 캐럿 없음”·“여유 없는 버튼” 항목 (e) 구버전 확장 잔여의 결정 기록 | README.md, README.ko.md, README.zh-Hant.md, README.ja.md, docs/context/index.md, docs/context/claude-input-delivery.md, docs/new-terminal-checklist.md | 1 | todo | | |
| 3 | Warp helper 수명 가정을 입력 11개 기준으로 고친다 | 수명 예산 설명 | (a) `maxLifetime` 주석의 “5 inputs” 전제 | app/Sources/WarpHelper/main.swift | 1 | cleared | 주석 갱신 근거: 12×2+2+2+3.6=31.6초/입력, 120+11×31.6=467.6초; `betweenInputTimeout` 15초를 입력마다 더하면 120+11×46.6=632.6초로 900초 안이다 (ClaudeInjector.swift:333, 399-403, 438-455, 529-555, 601-629, 970-973; `maxLifetime` 900 유지). node --test --test-reporter=tap exit 0 · 323. Swift 게이트는 드라이버 실행. 재실행(드라이버): diff는 `///` 줄뿐 — 코드 변경 없음 | |

- 항목 하나는 승격 하나의 크기다. 항목 2와 3은 항목 1의 승인된 계약을 사용한다. 판정으로 범위를 넓혀야 하면 새 항목을 만들고 사용자 결정을 기다린다.
- `tests/claude-note.test.js` red는 실제 5개 issueListButtons 값에서 `buttonTakesClaudeNote`가 false인 현재 동작을 true 기대와 비교했다. defaults.js 변경을 토글하면 이 assertion이 재실패했다. `tests/buttons.test.js`의 고정 10개 허용·11개 거부와 `tests/worker-note.test.js`의 진입점 payload 경계도 토글에서 실패했다. 기존 코드에서 통과하는 source-audit/context-sources 테스트를 새 근거 없이 늘리지 않았다.

## 결정 원장

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | 저장 입력이 5개인 버튼에 캐럿이 없다(PR #90 규칙: 저장 + 한 마디 ≤ 5) | 저장 상한 5→10, 한 마디는 그 위 별도 한 칸(클릭당 최대 11) | 2026-10-02 사용자 선택 | — |
| D2 | 드라이버 | 열린 질문 1: 저장 상한과 클릭당 상한에 이름을 따로 둘지 | 기각 — `MAX_CLAUDE_INPUTS`는 편집기·reader·import 모두에서 “버튼당 저장 상한”이고, 둘을 섞은 곳은 `buttonTakesClaudeNote` 하나뿐이다. 클릭당 상한은 `MAX_CLAUDE_INPUTS + 1`로 유도해 선언부에 적고, 판정은 정규화 저장 수 ≤ `MAX_CLAUDE_INPUTS` | extension/options.js:376, 1307 · extension/defaults.js:814, 978 · docs/context/options-page-reordering.md:13이 이 이름을 인용 · R0 | — |
| D3 | 드라이버 | 열린 질문 2: 클릭당 11이 세션당인지 배치 합계인지 | 세션(payload)당. 배치 합계는 상한이 아니다 — 변경 전 클릭당 5도 세션당이었다 | extension/defaults.js:557-565 · app/Sources/Core/Request.swift:97-140 · R0 | — |
| D4 | 드라이버 | 열린 질문 3: 구버전 확장(상한 5)이 입력 6개 이상 버튼을 건너뛰고, 그 옵션 페이지의 Save가 그 버튼을 지운다 | 잔여 — 막는 장치를 만들지 않는다. 구버전 reader는 자르지 않고 건너뛰며, 옵션 페이지는 저장 전에 “Saving will remove them — use Export first”를 보인다. 저장된 version은 명시적 검토로만 움직이므로(CLAUDE.md) version으로 막는 것은 이 변경에 비해 과하다. 결정 기록은 항목 2가 docs/context에 남기고, PR 본문에 “모든 기기를 갱신한 뒤 6개 이상 저장”을 적는다 | extension/defaults.js:801-819, 1235-1244 · extension/_locales/en/messages.json:188-189 · R0 | 키의 버튼이 전부 건너뛰어지면 구버전은 기본 버튼을 그린다(`readStoredButtons`) — 저장값과 다른 명령이 콘솔 경고만으로 실행된다 |
| D5 | 드라이버 | 열린 질문 4: 앱 Core에서도 11개 초과를 거부할지 | 기각 — 비목표. 개수는 편집 한계이고, 앱의 경계는 같은 uid(app/Sources/WarpHelper/main.swift 서두)이며 전달 시간은 Warp helper의 자체 수명 상한이 묶는다 | app/Sources/Core/Request.swift:84-95 · R0 | — |
| D6 | 드라이버 | 열린 질문 5: 900초가 입력 11개에서도 충분한가 | 유지 — 120 + 11 × 31.6 ≈ 468초, 약 1.9배. 주석의 “5 inputs” 전제만 클릭당 최대(`MAX_CLAUDE_INPUTS + 1`)로 갱신 | app/Sources/WarpHelper/main.swift:49-52 · app/Sources/Core/ClaudeInjector.swift:399-403, 438-455, 529-555, 601-629 · R0 | 세션 확인 대기(입력 사이 최대 15초)를 매 입력 다 쓰면 120 + 11 × 46.6 ≈ 633초 — 900초 안이지만 두 배는 아니다 |
| D7 | 드라이버 | 열린 질문 6: `settingsTooLarge` 문구가 “가장 긴 명령을 줄여라”만 말해, 입력이 원인일 때 안내가 좁다 | 범위 밖 — 기록만. 입력 10개는 한 키가 6,144B에 닿을 가능성을 키운다. 후속 이슈 여부는 종결 때 사용자에게 묻는다 | extension/_locales/en/messages.json:185-186 · extension/defaults.js:741 · 사용자 실제 issueListButtons 키 392B · R0 | 트리거: 입력이 대부분인 키가 6,144B를 넘는 저장 |
| D8 | 드라이버 | 열린 질문: migration.test.js의 adoptStoredSettings 상한 테스트가 adoptStoredButtons 경계 테스트와 중복인가 | 유지 — 설정 단위 reader가 키별 건너뜀 수(skippedByKey)를 보고하는 계약을 고정해 고도가 다르다. 이번 수정은 상한이 바뀐 뒤에도 참이도록 MAX_CLAUDE_INPUTS + 1로 바꾼 것뿐이다 | tests/migration.test.js:1144-1149 · R1 | — |

## 전수 소탕 표

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 파일:행 |
|:--|:--|:--|
| MAX_CLAUDE_INPUTS 선언·저장 reader·payload 판정 | 구현 완료 (항목 1) | extension/defaults.js:321-323, 801-819, 892-897, 974-980, 1049-1063, 1237-1244 |
| 옵션 편집기·import·저장 경고·구버전 reader | 구현 완료 (항목 1), 구버전 처분 잔여 (D4) | extension/options.js:376, 593-669, 1305-1314; extension/migrations.js:176, 189-192, 688-708; extension/defaults.js:801-819, 1237-1244 |
| content script와 worker의 버튼 판정 및 batch payload | 구현 완료 (항목 1), batch 입력은 세션당 (D3) | extension/content.js:94-101, 775-795; extension/background.js:139-145, 182-183, 334-339, 501-542; extension/defaults.js:557-565 |
| 앱 입력 개수·batch·프레임 예산 | 개수 상한은 비목표 (D5); batch는 세션당 (D3) | app/Sources/Core/Request.swift:27-29, 84-95, 97-140; app/Sources/Core/Framing.swift:6, 19-27; app/Sources/App/HostServer.swift:199-205, 403-415 |
| Warp helper per-input 수명 가정과 per-request size budget | 구멍 (항목 3); oversized-settings 안내 범위 밖 잔여 (D7) | app/Sources/WarpHelper/main.swift:20-27, 49-52, 122-127; app/Sources/Core/ClaudeInjector.swift:399-403, 438-455, 970-1024; app/Sources/Core/WarpHelperProtocol.swift:67-72 |
| 네 README의 저장 입력·한 마디 설명 | 구멍 (항목 2) | README.md:153, 192; README.ko.md:154, 193; README.zh-Hant.md:154, 193; README.ja.md:154, 193 |
| context 및 수동 체크리스트 | 구멍 (항목 2) | docs/context/index.md; docs/context/claude-input-delivery.md:228-284; docs/context/options-page-reordering.md:13 (상수 이름 유지); docs/new-terminal-checklist.md:147-185; CLAUDE.md:46 |
| 로케일 카탈로그 5개 | 상한 숫자 없음; oversized-settings 안내 범위 밖 잔여 (D7) | extension/_locales/en/messages.json:185-198, 222-229; extension/_locales/ko/messages.json:185-198, 222-229; extension/_locales/zh_CN/messages.json:185-198, 222-229; extension/_locales/zh_TW/messages.json:185-198, 222-229; extension/_locales/ja/messages.json:185-198, 222-229; 모두 ext_error_skipConsequence와 ext_error_settingsTooLarge를 보유 |
| predicate·reader·worker·import adapter 테스트 | 구현 완료 (항목 1) | tests/claude-note.test.js:102-137; tests/buttons.test.js:528-549; tests/worker-note.test.js:87-135, 169-178; tests/migration.test.js:1144-1149 |
| source lint와 context 출처 검사 | 안전 | tests/source-audit.test.js:250-270은 typed source-read 계약, tests/context-sources.test.js:34-36은 context metadata의 PR 출처만 다룬다 |
| test-design 지침 | 안전 | docs/context/testing.md:3, 120-134, 136-167 |
| 과거 settings migration plan | 안전 · 역사 기록 유지 | docs/plans/settings-migration.md:412, 643, 659의 상한 5는 당시 결정 기록 |
| sync per-item size·저장 실패 화면 | 범위 밖 잔여 (D7) | extension/defaults.js:731-746; extension/migrations.js:478-485, 542-561; extension/options.js:772-786; tests/buttons.test.js:789-796; tests/migration.test.js:1244-1252 |

## 라운드 로그

### R0

#### 설계 리뷰 — 드라이버 · 미커밋 초안 · 리뷰 13:15∼13:20 · 왕복 0 · 원문 /private/tmp/claude-input-cap-loop/r1-assign.md

- 반박: R0-1 상한 이름 분리 제안 · R0-2 배치 11의 단위 · R0-3 구버전 확장 · R0-4 앱 개수 상한 · R0-5 Warp 수명 900초 · R0-6 저장 크기 안내 · R0-7 형식과 확정 결함 열거
- 처리: R0-1 기각(D2) · R0-2 반영(D3, 목표) · R0-3 잔여(D4, 항목 2) · R0-4 기각(D5, 비목표) · R0-5 반영(D6, 항목 3) · R0-6 범위 밖(D7) · R0-7 반영
- 실측: node --test --test-reporter=tap exit 0 · 320 · tools/check-locales.js exit 0 · swift test (드라이버, 기준 트리 4c3c722) exit 0 · XCTest 132
- 판정: R0 처리 반영으로 시작하는 데 합의한다

### R1

#### 리뷰 1 — 증분 · 항목 1 커밋 · 드라이버 · 리뷰 13:38∼13:50 · 왕복 0 · 원문 /private/tmp/claude-input-cap-loop/r2-assign.md

- 차단: 없음
- 수정: 항목 1 (배정 13:20 · 완료 13:37), 커밋 전 다듬기 — 실제 저장값 fixture 한 곳, 중복 경계 assertion 제거
- 실측: node --test exit 0 · 323 · check-locales exit 0 · 옛 defaults.js 토글 exit 1 · 4 fail
- 판정: 막혔다. 우회 없음 — reader를 거친 버튼은 저장 수가 늘 상한 이하라 가드에 닿지 않고, 저장 입력 11개 버튼은 reader가 건너뛴다 → 항목 1 cleared

#### 리뷰 2 — 증분 · 항목 3 커밋 · 드라이버 · 리뷰 13:47∼13:50 · 왕복 0 · 원문 /private/tmp/claude-input-cap-loop/r3-assign.md

- 차단: 산식의 120이 이름 없이 쓰였다
- 수정: 항목 3 (배정 13:40 · 완료 13:46), 120을 claude 시작 대기로 이름 붙임
- 실측: diff는 `///` 줄뿐 · node --test exit 0 · 323
- 판정: 막혔다. 우회 없음 → 항목 3 cleared

## 열린 질문

없음
