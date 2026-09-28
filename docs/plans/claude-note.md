# claude-note

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: terminal-checkout — `extension/`·`tests/`·`tools/check-locales.js`·`README.md`·`CLAUDE.md`·`docs/` (Swift는 `app/Tests/`만)
- 시작 커밋: `3aa6c98` (`fix: the PR buttons find the header's branch links by document order, not by screen position (#86)`)
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/claude-note-review` (`worktree-claude-note-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/agent-a7397a9d0ed8f049e` (`worktree-agent-a7397a9d0ed8f049e`)
- 현재: R0 · 마지막 승격 없음 · 리뷰 중 없음 · 게이트 그린(기준선 — 아래 수치)
  - 기준선(작업 트리 `3aa6c98`, 구현자 실행): `node --test` exit 0 · 258/258 · `cd app && swift test` exit 0 · CoreTests 517(skipped 1) + AppTests 130 · `node tools/check-locales.js` exit 0
- 최근 검증자 판정: 미요청

이 파일은 **실행한 계획과 실행할 계획의 기록**이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실. 코드 수정 과정을 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다. 결정이나 질문이 특정 동작에 걸리면 한 절과 `파일:행`으로 끝낸다. 이 템플릿에 없는 소절을 만들지 않는다 — 테스트 설계는 테스트 파일이 말한다.

## 배경 — 확인한 원천

문제를 파악하며 확인한 영구 소스만 — Slack 스레드·이슈·PR·설계 문서처럼 세션이 끝나도 남는 것. 스크래치패드 경로는 여기 두지 않는다. 원천의 내용과 이 루프의 결정이 어긋나면 결정 원장의 `사용자` 행이 우선한다 — 원천을 읽었으면 원장에서 사용자가 결정·수정·취소한 것을 이어서 확인해라.

- 요청 원문 — 이 루프의 대화에서 나왔고 영구 링크는 없다: 「크롬 버튼 옆에 아이콘을 추가하고 그걸 누르면 뭔가 열리면서, 해당버튼이 클로드를 여는 버튼이면 클로드에게 전달할 한 마디를 추가하고 전송하는 기능」
- [이슈 #16](https://github.com/dazebug/terminal-checkout/issues/16) — typed 전달 중 같은 탭에서 사용자가 친 글자가 우리 입력과 섞여 함께 제출된다(열림, 구조적 수정 없음) — 노트가 `!` 프리셋에 붙으면 이 잔여를 그대로 진다.
- [이슈 #21](https://github.com/dazebug/terminal-checkout/issues/21) — 페이지 스크립트의 합성 클릭이 명령을 실행하던 결함(이슈는 열려 있으나 `onUserClick`으로 막혀 있다 — `defaults.js:337-360`) — 아이콘·전송·Enter가 같은 가드를 타야 하는 근거.
- [이슈 #29](https://github.com/dazebug/terminal-checkout/issues/29) — 버튼 실패의 이유가 페이지에 안 보인다(열림) — 팝오버가 오류 원문을 그리지 않는 경계의 출처.
- [`docs/context/claude-input-delivery.md`](../context/claude-input-delivery.md) — 평문 입력 하나만 argv, 섞이면 전부 typed인 이유와 `!`를 claude 셸 모드에 타이핑하는 결정.
- [`docs/context/localization.md`](../context/localization.md) — 확장 언어는 Chrome이 정하고, 사용자가 친 바이트는 정규화하지 않고 싣는다.
- [`docs/context/testing.md`](../context/testing.md) — 소스 lint와 런타임 오라클의 구분, 확장 페이지에 DOM 하네스가 없다는 것, 문자열 목록이 아니라 계약으로 거는 게이트.
- [`docs/context/github-page-reading.md`](../context/github-page-reading.md) — 헤더 버튼의 앵커(배너 랜드마크·브랜치 링크) — 아이콘이 붙는 자리.

## 목표

- claude를 띄우는 버튼에만 ▾ 캐럿이 붙는다 — 그 버튼과 이어진 분할 버튼의 오른쪽 조각이다(D4·D5); 판정은 `defaults.js`의 한 함수이고 그리기(content)·검증(worker)·options 경고가 공유한다; 13개 프리셋 중 8개가 해당한다(전수 소탕 표).
- 캐럿을 누르면 한 줄 입력 팝오버가 열리고, 보내면 그 버튼의 명령이 실행되며 노트는 그 요청 `claude_inputs`의 마지막 원소가 된다 — 노트뿐이면 앱의 argv 조건(`ClaudeInputPlan.swift:760-783`)을, 저장된 입력이 있으면 typed 경로를 그대로 탄다. 앱 프로덕션 코드는 바뀌지 않는다.
- 앱에 도달하는 노트는 평문 한 줄이다: 앱이 셸 명령·입력 상자 지시로 분류할 수 있는 값, 개행·제어문자, 상한 초과, 페이지 종류가 주지 않는 변수는 워커가 `{success:false}`로 거부하고 팝오버가 현지화된 이유를 보인다.
- 전송은 사람의 클릭 또는 Enter(IME 조합 중 제외)로만 일어나고, 실패는 성공으로 보이지 않으며 입력은 보존되고, 팝오버를 연 페이지가 아닌 페이지로는 보내지지 않는다.
- 적용 표면: PR·이슈·저장소 헤더 버튼(항목 3)과 PR·이슈 목록 배치 버튼(항목 4 — Q3).

## 완료의 정의

- 반드시 재현해 막아야 끝인 실패:
  - 앱 trim 뒤 `!`로 시작하게 되는 노트 — `!x`, ` !x`, 그리고 U+0085·U+200B·U+00A0·U+3000 뒤에 `!x` — 가 claude 셸 모드에 닿는다 → 워커가 거부해 네이티브 요청이 나가지 않는다. `/x`·`#x`·`{main} x`도 같다.
  - claude를 띄우지 않는 버튼(프리셋 5개)이나 저장 입력이 5개인 버튼으로 온 노트 메시지(위조 포함) → 거부.
  - 팝오버를 연 PR에서 다른 PR로 옮긴 뒤 전송 → `PAGE_CHANGED_ERROR`(`background.js:165`)로 거부.
  - IME 조합을 확정하는 Enter가 전송한다, `{success:false}`가 성공으로 보이거나 입력이 지워진다 → 둘 다 일어나지 않는다.
- acceptance oracle: red를 먼저 확인한 `node --test`(exit 0, 실행 수 기록 — 기준선 258)의 판정 함수 표·속성·조립 테스트, `cd app && swift test`(exit 0 — 기준선 CoreTests 517 + AppTests 130)의 trim 전제 고정과 카탈로그 게이트, `node tools/check-locales.js` exit 0. 팝오버의 키보드·IME·단축키·테마·클리핑과 argv/typed 실제 전달은 node로 검증되지 않으므로(확장 페이지에 DOM 하네스 없음 — `testing.md`) 항목 5가 체크리스트에 넣은 항목을 드라이버가 실제 Chrome에서 수행한 결과를 근거 칸에 적는다.
- 코퍼스 범위: `extension/defaults.js`의 13개 프리셋(전수 소탕 표에 하나씩), 소탕 표의 사용자 명령 모양, 5개 로케일 카탈로그, 페이지 종류 5개. 저장 fixture는 만들지 않는다.
- 원자성·부분 실패·롤백 경계: 전송 한 번은 요청 한 건이고 진행 중에는 다시 보낼 수 없다. 워커·앱 검증의 거부는 터미널 실행 전이라(`Request.swift:290-295` — resolve가 run보다 먼저) 다시 보내도 중복이 없다. 앱이 탭을 연 뒤 응답만 유실되면 재전송이 세션을 하나 더 연다 — 기존 버튼과 같은 잔여이고, 요청 idempotency는 이 루프에서 만들지 않는다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

이 루프가 막는 실패를 일으킬 수 있는 행위자(사람·프로세스·시스템)와 그 능력을 열거한다. **발견을 배정하려면 어느 행위자가 그 결함에 닿는지 이름을 대야 한다** — 모델 밖 행위자가 필요한 발견은 기본이 잔여(원장 기록, 배정 없음)다. 행위자를 새로 들이는 것은 범위 변경이라 사용자 승인이 필요하다. 해당 없으면(순수 로직 루프) N/A + 근거.

- 사용자: 노트를 쓰고 클릭·Enter로 보낸다, 한국어·일본어·중국어 IME 조합 중 Enter·Esc를 누른다, 팝오버를 연 채 페이지를 옮기거나 뒤로 간다, typed 전달 중 그 탭에 타이핑한다(#16).
- GitHub 페이지 스크립트(XSS)와 github.com 호스트 권한을 가진 다른 확장: content script와 DOM을 공유해 팝오버 입력값을 바꾸거나 오버레이를 덮을 수 있다(닫힌 shadow root가 이를 막는다고 가정하지 않는다 — 미측정). 합성 이벤트는 `isTrusted`에 막힌다(`defaults.js:337-360`). 변수를 읽어 오는 DOM(브랜치 링크·`defaultBranch` JSON)을 바꿀 수 있지만 값은 앱 화이트리스트를 지난다(`CommandRenderer.swift:36-55`). 워커의 `onMessage`에는 닿지 못한다 — 웹 페이지는 `externally_connectable`이 없어 보낼 수 없고(`manifest.json`), 다른 확장의 메시지는 `onMessageExternal`로 가는데 워커는 `onMessage`만 듣는다(`background.js:574`). 따라서 노트로 닿을 수 있는 최대치는 사용자가 누른 전송에 실린 평문 한 줄이다.
- 확장 새로고침 전후의 인접 세대 content script: 옛 탭의 content script는 `note`를 보내지 않는다 — 기존 경로 그대로.
- claude(모델): 노트를 사용자 메시지로 받는다 — 위 행위자가 평문을 바꿔 넣으면 사용자 지시로 읽힌다(프롬프트 주입 잔여, 문서화 대상).
- 동일 uid 프로세스: 모델 밖 — 앱 소켓과 Warp helper의 신뢰 경계(`SECURITY.md`).

## 비목표 — 건드리지 않는다

- 확장 아이콘 클릭(`background.js:552-571`): 입력할 UI가 없다 — 노트 없이 첫 버튼을 실행하는 지금 동작 그대로.
- 이미 떠 있는 claude 세션에 노트만 보내기: 앱은 이전 요청의 세션 핸들을 보관하지 않는다(`HostServer.swift:279-295`, `ClaudeInjector.swift:986-989`).
- 앱의 전달 기계(`ClaudeInputPlan`·`ClaudeInjector`·`TerminalRunner`)와 요청 프로토콜: 노트는 기존 `claude_inputs`로 간다.
- 노트 저장·이력·설정(`storage.sync`, `SETTINGS_VERSION`): 노트는 클릭마다의 값이다.
- 여러 줄 노트: 앱이 LF/CR를 거부하고(`Request.swift:197-208`) argv가 개행을 싣지 못한다(`ClaudeInputPlan.swift:775-777`).
- `!`·`/`·`#` 노트(Q1).
- 앱 오류 원문의 페이지 표시(#29).
- iTerm2/WezTerm argv 경로의 1024바이트 canonical 한계에 대한 수정 — 체크리스트 실측만(Q4).
- 앱 setup window 문구(Q6)와 저장된 입력의 정규화 차이(Q7).

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

0라운드 이후 이 절과 「완료의 정의」에 항목을 **더하는 것은 범위 변경이다** — 결정 원장의 `사용자` 행 없이 추가하지 않는다(드라이버·검증자 발의는 비용 추정과 함께 사용자 승인 후). 드라이버가 스스로 쓴 기준을 스스로 집행하는 것이 일감 자가 생산의 뿌리다.

- 노트는 claude 입력 하나다. 새 프로토콜 필드나 앱 경로를 만들지 않고 요청 `claude_inputs`의 **마지막** 원소로만 붙인다 — 맥락을 까는 `!` run이 먼저 가야 claude가 노트를 맥락과 함께 읽는다(`new-terminal-checklist.md:196`). 그래서 노트도 템플릿이다(`Request.swift:168-172`; `{이거}`도 변수 이름으로 읽힌다 — 실측).
- 노트는 클릭 메시지가 공급하는 **유일한 원천**이다. command·variables·지문에 섞지 않는다 — `shown`은 저장된 버튼의 지문 그대로다(`defaults.js:905-917`).
- 판정은 `defaults.js`의 단일 함수가 내리고, 워커의 판정이 권위를, content의 판정은 UX만 맡는다. 두 벌을 만들지 않는다:
  - claude를 띄우는가 — options 경고의 기존 정의(`options.js:404`)를 옮겨 content 그리기·worker 검증·options 경고가 공유한다 (엄격도는 Q2)
  - 노트를 받는 버튼인가 — 위 판정 + 정규화된 저장 입력 수 < `MAX_CLAUDE_INPUTS`
  - 노트 판정 — 정규화와 거부 사유(비었음·상한 초과·첫 글자·개행/제어문자·없는 변수)
- 첫 글자 규칙: 일반 공백(U+0020) trim 뒤 첫 글자가 `\p{Z}`·`\p{C}`·`!`·`/`·`#`·`{`이면 거부한다. 앱은 템플릿 렌더 → C0/DEL·개행 거부 → `.whitespacesAndNewlines` trim → `!`/`/`/`#` 분류 순서이고(`Request.swift:170-180`, `ClaudeInputPlan.swift:30-38`), 이 trim이 벗기는 비-C0 스칼라 21개는 모두 Z∪C다(실측: U+0020 U+0085 U+00A0 U+1680 U+2000∼U+200B U+2028 U+2029 U+202F U+205F U+3000). 그러니 이 규칙을 지난 첫 글자는 앱의 어느 단계에서도 바뀌지 않는다. JS `trim()`·`\p{Z}`로 대체하지 않는다 — 둘 다 U+0085·U+200B를 놓친다(실측).
- 제어 바이트·개행은 조용히 지우지 않고 보이게 거부한다(`defaults.js:863-866`의 `trim()` 사고).
- 전송은 사람만 한다. 아이콘·전송 버튼은 `onUserClick`(`defaults.js:350-360`)으로, Enter 키는 같은 `isUserGesture`에 `isComposing` 제외를 더해 한 곳에서 가드한다.
- `{success:false}`는 실패로 보이고(`content.js:69-71`) 입력은 보존된다. 오류 원문은 페이지에 그리지 않는다(`buttons.test.js:679-701`) — 로컬 판정은 현지화 문구, 그 밖은 원인을 단정하지 않는 일반 실패 문구와 console 원문.
- 페이지 목표는 팝오버를 **연 순간** 읽어 보낸다. 전송 직전 비교는 최종 게이트가 한다(`background.js:182-207`). 목표가 바뀌면 팝오버를 아이콘과 함께 치운다(`content.js:863-883`).
- 한 요청의 claude 입력 합계는 `MAX_CLAUDE_INPUTS`(`defaults.js:321`) 이하다 — Warp helper 수명 산정의 전제다(`app/Sources/WarpHelper/main.swift:51`).
- DOM은 경계가 아니다. 팝오버의 격리 방식(shadow root 여부)은 스타일·단축키 문제로만 고르고, 보안은 워커의 판정이 진다.
- 카탈로그: 새 문자열은 5개 로케일 전부에 둔다. 핀(`tools/check-locales.js:28-36`, `tests/i18n.test.js:668`·`:1608-1646`)은 리뷰된 편집으로만 옮긴다. `_locales`를 바꾸는 승격은 `swift test`도 게이트다 — `CatalogueOwnershipTests`가 `_locales`를 읽어 앱 카탈로그와의 값 중복·스토어 안 중복·포함 관계를 막는다(`app/Tests/AppTests/CatalogueOwnershipTests.swift:50`·`:173-289`; 앱에 `Close`가 이미 있다 — `app/Sources/App/Resources/en.lproj/Localizable.strings:64`).
- 게이트의 성패는 종료 코드로 판정하고 실행 테스트 수를 따로 적는다(CLAUDE.md). red 먼저, 토글은 패치 역적용.
- 앱 프로덕션 코드는 바꾸지 않는다. Swift 변경은 첫 글자 규칙의 전제를 `resolveRequest` 진입점으로 고정하는 테스트뿐이다(Q7 처분 전).

## 배치 점검 (0라운드)

모드: default

(`default` 또는 `ultrafast`. 이 줄이 적힌 뒤로는 스킬 인자가 아니라 이 값이 모드를 정한다 — 스킬의 점검 블록이 이 줄을 읽는다.)

이 표의 실측 주체는 드라이버다 — 구현자가 채우는 행은 「에이전트 첫 보고」뿐이고, 자기 샌드박스의 실패로 드라이버 실측 값을 덮어쓰지 않는다(샌드박스 제약은 리포 오버레이 「격리 안에서 도는·못 도는 게이트」에 드라이버가 적는다).

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | `ignored` (메인 `.git/info/exclude`) |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 적용됨 — 에이전트 첫 보고 `git log --oneline -2`의 첫 줄 `3aa6c98` = 기준 트리 HEAD |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/agent-a7397a9d0ed8f049e` · `worktree-agent-a7397a9d0ed8f049e` · `3aa6c98` |
| 리포 오버레이 `.claude/drive-agent-loop.md` — 기준 트리의 경로(메인 것을 복사했으면 그렇게), 없으면 드라이버가 골격으로 작성. 커밋하지 않는다 — `오버레이 무시: ignored` 확인 | 기준 트리의 `.claude/drive-agent-loop.md` — 이전 루프들이 커밋한 추적 파일이라 `오버레이 무시: NOT`; 이 루프에서는 수정하지 않는다 |
| cmux 패널 (점검 블록 `cmux:` 신호가 켜졌을 때만, 아니면 N/A) — `cmux markdown open <작업 트리 계획 파일 절대경로>` → pane id. 계획 파일 첫 승격 전에 채운다 | `pane:56` (surface:73) |
| 트리마다 의존성 동기화 (기준·작업) | N/A — 외부 의존성 없음(루트 `package.json` 없음, `app/Package.swift`에 외부 dependency 없음) |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | N/A — git 밖 자산 없음 |
| 증분 리뷰 소요(분) — 첫 세 번 | |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | "claude를 띄우는가"·"노트를 받는 버튼인가"·노트 판정·노트를 마지막에 붙이는 `claude_inputs` 조립을 `defaults.js` 단일 함수로 세우고 `updateClaudeWarn`이 같은 술어를 쓰게 한다; 앱 trim이 벗기는 선행 스칼라가 Z∪C뿐이라는 전제를 `resolveRequest` 진입점으로 고정한다 | 판정 계약 | (a) "claude를 띄우는가"가 `options.js:404` 인라인 한 곳뿐이라 content·worker가 공유할 술어가 없다 (b) 노트 판정이 없다 — JS 공백 개념(`trim()`·`\p{Z}`)으로 만든 `!` 검사는 앱이 벗기는 U+0085·U+200B를 놓친다(실측) (c) 합계·바이트 상한과 페이지 종류 변수 판정이 없다 (d) 첫 글자 규칙의 전제를 고정하는 테스트가 없다 | `extension/defaults.js`, `extension/options.js`, 신규 `tests/claude-note.test.js`, `app/Tests/CoreTests/CoreTests.swift` | — | todo | | |
| 2 | 워커가 상세·저장소 클릭 메시지의 선택 필드 `note`를 형 검사한 뒤 항목 1의 판정으로 검증하고, 통과한 노트만 항목 1의 조립 함수로 요청에 싣는다; 거부는 `{success:false}`(영문 진단, console 전용); 확장 아이콘 경로는 노트를 싣지 않는다; "메시지는 비교 키일 뿐 원천이 아니다"라는 주석을 노트 예외로 고친다 | 실행 경로(worker) | (a) `onMessage`가 `note`를 모른다(`background.js:612-623`) (b) `runButton`이 저장된 입력만 싣는다(`background.js:371-375`) (c) 원천을 부정하는 주석(`defaults.js:844-854`, `background.js:156-158`·`303-304`)이 노트 도입 뒤 거짓이 된다 | `extension/background.js`, `extension/defaults.js`(주석), `tests/buttons.test.js`(조립 경로 lint — `:652-661`과 같은 모양) | 1 | todo | | |
| 3 | PR·이슈·저장소 헤더에서 해당 버튼에 붙은 ▾ 캐럿을, 헤더의 overflow 밖에 팝오버를 그린다 — 캐럿은 분할 버튼의 오른쪽 조각으로, 저장소 헤더의 채운 초록 버튼에서는 버튼과 이어진 조각이고 PR·이슈 행의 아이콘 버튼 옆에서는 작은 캐럿이며 `currentColor` 단색 SVG다(D4·D5); 열 때 목표 캡처, 한 줄 입력·전송·닫기, 가드, 접근성(`aria-haspopup`·`aria-expanded`·툴팁/레이블), 진행·성공·실패 표시와 실패 시 입력 보존, 로컬 판정의 현지화 문구, 목표 변경 시 제거; GitHub 단축키 차단·DOM 격리 방식·스타일 주입의 CSP 통과·라이트/다크 테마는 실브라우저 실측으로 정한다(기존 버튼은 CSSOM `style.cssText`만 쓴다 — `content.js:32`); 위치 계산은 `layout.js` 순수 함수; 새 문자열을 5개 카탈로그에 넣고 핀을 옮긴다 | UI·카탈로그 | (a) 버튼 옆 입력 UI가 없다 (b) PR 헤더의 버튼 칸과 메타 행이 overflow:hidden이라 칸 안에 둔 팝오버는 잘린다(`layout.js:6-17`) (c) content의 원천 부정 주석(`content.js:77-83`)이 노트 도입 뒤 거짓이 된다 | `extension/content.js`, `extension/layout.js`, `tests/layout.test.js`, `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`, `tools/check-locales.js`(바이트 핀), `tests/i18n.test.js`(호출 수·속성 목록 핀), 필요 시 `tests/buttons.test.js` | 1, 2 | todo | | |
| 4 | 목록 배치 버튼에 같은 캐럿·팝오버를 붙인다 — 선택은 전송 시점에 읽고 선택 오류(0개·25개 초과)는 팝오버에 보이며 입력 보존; 배치 메시지와 요청이 노트를 싣고(모든 항목 공유, 항목별 변수 렌더), 워커의 목록 분기가 같은 판정으로 검증한다 | 배치 경로 | (a) `buildListBatchMessage`·`buildListBatchRequest`에 노트 자리가 없다(`defaults.js:560-593`) (b) 목록 `onMessage` 분기와 `executeListBatch`가 노트를 모른다(`background.js:469-511`·`581-610`) (c) 목록 버튼은 클릭 시점의 선택을 읽는다(`content.js:567`) | `extension/defaults.js`, `extension/background.js`, `extension/content.js`, `tests/list-pages.test.js`, 새 문자열이 생기면 항목 3의 카탈로그·핀 파일 | 1, 2, 3 | todo | | |
| 5 | 노트의 사용법·규칙·권한 영향을 README에, 실행 경로 점검 항목을 체크리스트에, 코드로 알 수 없는 결정을 CLAUDE.md와 context에 남긴다 | 문서 | (a) README의 claude 입력·Warp 권한 서술이 노트를 모른다(`README.md:14,16,34,94,156,190,285,287`) (b) 체크리스트에 노트 경로가 없다 — CLAUDE.md는 실행 경로를 더하는 기능에 항목 추가를 요구한다 (c) 평문 전용 결정, 첫 글자 규칙의 실측 전제, 열 때 목표 캡처가 CLAUDE.md·`docs/context/`에 없다 | `README.md`, `CLAUDE.md`, `docs/new-terminal-checklist.md`, `docs/context/claude-input-delivery.md`, 필요 시 `docs/context/index.md` | 2, 3, 4 | todo | | |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶이고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다. 승격 칸에는 커밋 해시를 적는다
- `의존`: 다른 항목의 계약(시그니처·불변식·생성물·호출 순서)을 전제하면 그 번호를 적는다. 그 항목에 정정(A′)이 오면 이 항목의 근거를 다시 낸 뒤에야 최종 리뷰에 들어간다
- `확정 결함`: 설계 리뷰·판정에서 이 항목으로 확정된 결함이 여럿이면 처방 산문과 분리해 `(a) … (b) …`로 열거한다 (하나뿐이면 — 항목 문장이 곧 결함이다). 배정문은 이 라벨을 인용한다 — 「이번 배정은 (a)(b), (c)는 후속」. 열거가 검증자 스레드·스크래치패드에만 있으면 세션과 함께 사라지고, 명세에 열거가 없으면 배정 전 자기 대조를 성실히 해도 빠진 결함이 보이지 않는다(실사고)
- 판정이 항목을 다시 열면 행을 고치지 말고 개정 항목으로 잇는다 — 같은 항목의 개정은 prime(`6′`), 형제 부류나 prime 소진 뒤는 letter(`6a`), 식별자는 재사용하지 않는다(append-only 표가 모호해진다). **선행 행의 상태는 그 승격에 대한 마지막 판정이지 종결이 아니다 — 부류의 종결은 체인 끝 항목의 상태가 나타낸다.** 이 규약 없이 표를 처음 읽으면(cold review·재개 브리핑) 개정된 행들이 미해결로 보인다
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`
- `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다. `verified`(드라이버 근거 대조)·`cleared`(증분 리뷰에서 범위 내 확인)·`agreed`(최종 리뷰 또는 cold review)·`dropped`(중단 결정)는 드라이버의 결정이고, 드라이버가 문구를 지정하면 에이전트가 그대로 적는다
- 근거 칸에는 **재실행 가능한 것**만: 명령과 결과 줄, 테스트 이름과 수, 수치를 낸 스크립트 경로. "확인했다"도, "이 함수가 이걸 읽어서 저렇게 한다"는 메커니즘 설명도 근거가 아니다 — 1행이 기준이다

## 결정 원장

append-only — **첫 승격 이후부터**다(첫 승격 전의 R0 초안은 아직 인용된 판정이 없으므로 재작성해도 된다). 결정의 이유, 기각한 반박과 근거, 잔여 불확실성 — 코드 서술은 여기에도 넣지 않는다. 기존 행을 고치지 않고 새 행을 더한다. `유형`은 결정 주체(`사용자`/`드라이버`)다. **행을 적는 손은 구현자여도 행의 발행은 드라이버다** — 두 유형 모두 드라이버가 문구를 지정한 것만 적고, 구현자는 스스로 행을 추가하지 않는다(구현자 발의는 「열린 질문」에 적어 처분을 기다린다). `claimed`가 상태의 구현자 상한인 것과 같은 축이다. **`사용자` 행은 배경 원천·검증자 권고와 어긋나도 우선하고, 새 `사용자` 행으로만 뒤집힌다** — 배경 소스에 적힌 내용을 사용자가 이 루프에서 결정·수정·취소한 것이 여기 남는다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | 목록 배치 버튼까지 적용할지(Q3) | 포함 — 항목 4 유지 | R0 보고 회신(2026-09-28) | — |
| D2 | 사용자 | `!`·`/`·`#` 노트 허용 여부(Q1) | 평문만 — 첫 글자 규칙으로 거부 | R0 보고 회신 | — |
| D3 | 사용자 | "claude를 띄우는가"의 엄격도(Q2) | options 경고의 `\bclaude\b`를 공유한다 | R0 보고 회신 | 오탐(`echo claude` 등)이면 노트가 조용히 버려지고 성공이 표시된다 — 저장 입력과 같은 잔여 |
| D4 | 사용자 | 아이콘 모양 | ▾ 드롭다운 캐럿 — GitHub의 `Merge pull request ▾`·`Code ▾`와 같은 분할 버튼 패턴(💬 등 이모지 후보는 기각) | R0 회신 | — |
| D5 | 드라이버 | 캐럿을 이모지 face로 그리면 face 규칙(`isTextFace`)에 엮이고 GitHub 테마 색을 따르지 않는다 | GitHub 드롭다운 캐럿과 같은 모양의 단색 SVG(`currentColor`)로 그린다 — Octicons 소스를 복사하지 않고 자체 path | D4 | 라이트/다크·크기는 실브라우저 미확인 |
| D6 | 드라이버 | 범위 밖 Q6 — setup window Warp 문구의 "three" | 이슈로 분리(사용자 처분) | https://github.com/dazebug/terminal-checkout/issues/87 | — |
| D7 | 드라이버 | 범위 밖 Q7 — 저장 입력의 선행 공백 정규화 차이 | 기록만 — 사용자 처분은 "이슈로 분리"였으나, 확장에는 저장 입력의 종류를 판정·표시하는 곳이 없어 보이는 것과 실행되는 것이 어긋나는 사용자 가시 결함이 없다; 확장이 입력 종류를 판정하는 곳은 이번 노트뿐이고 첫 글자 규칙이 닫는다 | `rg -n "'!'" extension/options.js extension/defaults.js` → 0건(`options.js:1331`은 주석) | 확장이 저장 입력의 종류를 판정하는 기능이 생기면 재검토 |
| D8 | 드라이버 | 노트 바이트 상한(Q4) | 4096 UTF-8 바이트 | `ClaudeInputPlan.swift:57-65`(`claudeMergedLineLimit`과 같은 근거) | iTerm2/WezTerm argv 1024바이트 한계는 미실측 — 체크리스트에서 실측 |
| D9 | 드라이버 | 노트 안 `{단어}`(Q5) | 페이지 종류가 주는 변수만 렌더하고 그 밖은 팝오버·워커가 거부 — 리터럴 지원은 앱 변경이라 비목표 | `CommandRenderer.swift:57` | — |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점 전체. 미검사 항목을 비워 두지 않는 것이 이 표의 목적이다. 세 열뿐이다 — 셋째 열은 코드로 알 수 없는 이유 한 절이거나 `파일:행`이다. 판정이 안전이고 그런 이유가 없는 대상은 한 행에 나열해 합친다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `pr.checkoutClaude` | 캐럿 ○ · `[노트]` → 앱 append 조건을 채우면 argv, 아니면 typed | `defaults.js:48-51` · `ClaudeInputPlan.swift:770-777` |
| `pr.worktreeClaude` | 캐럿 ○ · `[노트]` → 위와 같음 | `defaults.js:52-55` |
| `repo.openClaude` | 캐럿 ○ · `[노트]` → 위와 같음 | `defaults.js:126-129` |
| `pr.review` | 캐럿 ○ · `[!view, !diff, 노트]` → 병합된 `!` 한 줄 + 노트 typed, 합계 3 (Warp의 Accessibility 요구는 지금과 같음) | `defaults.js:61-65` · `ClaudeInputPlan.swift:316-326` |
| `issue.read` | 캐럿 ○ · `[!×3, 노트]` → 병합 한 줄 + 노트 typed, 합계 4 | `defaults.js:84-93` |
| `issue.startWork` | 캐럿 ○ · `[!view, 노트]` → typed 2개 | `defaults.js:94-98` |
| `pr-list.checkoutClaude` | 캐럿 ○(항목 4) · 항목마다 `[노트]` → argv 조건부 | `defaults.js:76-79` · `defaults.js:560-565` |
| `issue-list.triageClaude` | 캐럿 ○(항목 4) · 항목마다 `[!view, 노트]` → typed | `defaults.js:108-112` |
| `pr.checkout` · `pr.worktree` · `issue.open` · `repo.open` · `repo.updateMain` | 캐럿 × — 명령에 `claude`가 없다 | `defaults.js:44-47,56-59,99-103,122-125,130-133` |
| 사용자 명령 `… && claude --model x`·`--continue` | 캐럿 ○ · 앱이 플래그로 append를 거부 → typed, claude TUI가 뜨면 전달 | `ClaudeInputPlan.swift:450-452` |
| 사용자 명령 `echo claude`·`cat ~/.claude/…`·`claude -p …` | 캐럿 ○(오탐) · typed → 120초 대기 뒤 로그만 남고 버튼·팝오버는 성공 — 저장 입력과 같은 잔여(Q2) | `ClaudeInjector.swift:1024-1030` |
| 사용자 alias(`cc` 등)로 claude를 띄우는 명령 | 캐럿 × (미탐) | 명령 텍스트로는 alias를 알 수 없다 |
| 저장 입력이 5개인 버튼 | 캐럿 × (합계 상한) | `defaults.js:321,809` |
| "claude를 띄우는가"를 판정하는 곳 | content 그리기·worker 검증·options `updateClaudeWarn` → 한 함수(항목 1) | `options.js:402-408` |
| `claude_inputs`를 조립하는 곳 | `runButton`·`buildListBatchRequest` → 항목 1의 조립 함수 경유; 확장 아이콘 경로는 노트 없음 | `background.js:371-375,567` · `defaults.js:560-565` |
| 메시지 필드가 요청 원천이 되는 곳 | 노트 하나(예외); 목록의 `selected`는 비교 키로 남는다 | `defaults.js:512-514` · `background.js:496-503` |
| "메시지는 원천이 아니다"를 말하는 주석 | 노트 예외로 갱신(항목 2·3) | `defaults.js:844-854` · `content.js:77-83` · `background.js:156-158,303-304` |
| 입력 첫 글자를 바꿀 수 있는 앱 단계 | 렌더(`{`)·trim(Z∪C)·분류(`!/#`) → 첫 글자 규칙이 셋 다 막는다 | `Request.swift:170-180` · `CommandRenderer.swift:57,96-104` · `ClaudeInputPlan.swift:30-38` |
| 노트 내부 문자(첫 글자 제외) | LF/CR/C0/DEL은 확장이 먼저 거부하고 앱도 거부; 그 밖은 저장 입력과 같은 앱 규칙이며 확장만의 추가 규칙은 없다 | `Request.swift:197-222` |
| 노트 안 `{단어}` | 페이지 종류 변수면 렌더, 아니면 확장이 거부; 앱의 `\w`는 유니코드라 확장이 놓친 이름도 앱이 거부(Q5) | `CommandRenderer.swift:57` · `defaults.js:220-233` |
| 버튼이 붙는 표면 | PR 헤더·이슈 배지 행·저장소 crumb(항목 3), 목록 툴바(항목 4); 확장 아이콘 클릭 제외 | `content.js:589-622,721-831` · `background.js:552-571` |
| 팝오버를 치우는 곳 | 목표가 바뀔 때 `removeInsertedButtons`가 캐럿·팝오버를 함께 지운다 | `content.js:863-883` |
| 앱 setup window의 Warp 문구 | 변경 불필요 — 노트 클릭이 typed로 거부돼도 같은 안내 창이 뜬다; "all three" 불일치는 Q6 | `TerminalRunner.swift:169-172` · `app/Sources/App/Resources/en.lproj/Localizable.strings:79,84` |
| iTerm2/WezTerm argv의 1024바이트 canonical 한계 | 미검사 — 앱은 cmux만 가드한다; 긴 노트로 체크리스트에서 실측(항목 5, Q4) | `TerminalRunner.swift:468-488` |
| 팝오버 입력 중 GitHub 전역 단축키 | 미검사 — shadow root 안의 입력은 바깥 리스너에 host로 재지정되어 보인다; 실브라우저 실측(항목 3) | |
| IME 조합 중 Enter·Esc | 미검사 — 실브라우저 실측(항목 3) | |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 차단·수정·실측 줄은 에이전트가, 판정 줄은 드라이버가 지정한 문구를 에이전트가 적는다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — <계획 커밋 해시> · 승격 hh:mm · 리뷰 hh:mm∼hh:mm · 왕복 <n> · 원문 <경로>

- 반박: <미실시>
- 처리: <미실시>
- 실측: <미실시>
- 판정: <미실시>

## 열린 질문

원 요구 충족 후 발견된 마이너·에지케이스 방어 후보는 여기 적립한다(즉시 배정 금지) — 사용자 대화로 포함/이슈/기록 중 처분이 정해지면 그 결과를 원장에 남기고 지운다.
