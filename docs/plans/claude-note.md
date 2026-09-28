# claude-note

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다 (규칙의 정본은 요약이 아니다)
- 대상: terminal-checkout — `extension/`·`tests/`·`tools/check-locales.js`·`README.md`·`CLAUDE.md`·`docs/` (Swift는 `app/Tests/`만)
- 시작 커밋: `3aa6c98` (`fix: the PR buttons find the header's branch links by document order, not by screen position (#86)`)
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/claude-note-review` (`worktree-claude-note-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/agent-a7397a9d0ed8f049e` (`worktree-agent-a7397a9d0ed8f049e`)
- 현재: R1 · 마지막 승격 9c65961(1′ 커밋 승격 대기) · 리뷰 중 없음 · 게이트 그린(node 285/285)
  - 기준선(작업 트리 `3aa6c98`, 구현자 실행): `node --test` exit 0 · 258/258 · `cd app && swift test` exit 0 · CoreTests 517(skipped 1) + AppTests 130 · `node tools/check-locales.js` exit 0
- 최근 검증자 판정: R0 재리뷰 yes · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/0fc35e90-1ec3-413c-9d07-cb8929cf4b08/claude-note/R0b-review.md`

이 파일은 **실행한 계획과 실행할 계획의 기록**이다 — 결정(사용자·드라이버), 판정(검증자), 항목의 상태와 재실행 근거(명령 + 결과 줄 + 수치), 남은 큐, 크로스 리포 사실. 코드 수정 과정을 자연어로 풀어 쓰지 않는다: 무엇이 바뀌었는지는 커밋이, 어떻게 동작하는지는 코드가 말한다. 결정이나 질문이 특정 동작에 걸리면 한 절과 `파일:행`으로 끝낸다. 이 템플릿에 없는 소절을 만들지 않는다 — 테스트 설계는 테스트 파일이 말한다.

## 배경 — 확인한 원천

문제를 파악하며 확인한 영구 소스만 — Slack 스레드·이슈·PR·설계 문서처럼 세션이 끝나도 남는 것. 스크래치패드 경로는 여기 두지 않는다. 원천의 내용과 이 루프의 결정이 어긋나면 결정 원장의 `사용자` 행이 우선한다 — 원천을 읽었으면 원장에서 사용자가 결정·수정·취소한 것을 이어서 확인해라.

- 요청 원문 — 이 루프의 대화에서 나왔고 영구 링크는 없다: 「크롬 버튼 옆에 아이콘을 추가하고 그걸 누르면 뭔가 열리면서, 해당버튼이 클로드를 여는 버튼이면 클로드에게 전달할 한 마디를 추가하고 전송하는 기능」
- [이슈 #16](https://github.com/dazebug/terminal-checkout/issues/16) — typed 전달 중 같은 탭에서 사용자가 친 글자가 우리 입력과 섞여 함께 제출된다(열림, 구조적 수정 없음) — 노트가 `!` 프리셋에 붙으면 이 잔여를 그대로 진다.
- [이슈 #21](https://github.com/dazebug/terminal-checkout/issues/21) — 페이지 스크립트의 합성 클릭이 명령을 실행하던 결함(이슈는 열려 있으나 `onUserClick`으로 막혀 있다 — `defaults.js:337-360`) — 캐럿·전송·Enter가 같은 가드를 타야 하는 근거.
- [이슈 #29](https://github.com/dazebug/terminal-checkout/issues/29) — 버튼 실패의 이유가 페이지에 안 보인다(열림) — 팝오버가 오류 원문을 그리지 않는 경계의 출처.
- [`docs/context/claude-input-delivery.md`](../context/claude-input-delivery.md) — 평문 입력 하나만 argv, 섞이면 전부 typed인 이유와 `!`를 claude 셸 모드에 타이핑하는 결정.
- [`docs/context/localization.md`](../context/localization.md) — 확장 언어는 Chrome이 정하고, 사용자가 친 바이트는 정규화하지 않고 싣는다.
- [`docs/context/testing.md`](../context/testing.md) — 소스 lint와 런타임 오라클의 구분, 확장 페이지에 DOM 하네스가 없다는 것, 문자열 목록이 아니라 계약으로 거는 게이트.
- [`docs/context/github-page-reading.md`](../context/github-page-reading.md) — 헤더 버튼의 앵커(배너 랜드마크·브랜치 링크) — 캐럿이 붙는 자리.

## 목표

- claude를 띄우는 버튼에만 ▾ 캐럿이 붙는다 — 그 버튼과 이어진 분할 버튼의 오른쪽 조각이다(D4·D5); 판정은 `defaults.js`의 한 함수이고 그리기(content)·검증(worker)·options 경고가 공유한다; 13개 프리셋 중 8개가 해당한다(전수 소탕 표).
- 캐럿을 누르면 한 줄 입력 팝오버가 열리고, 보내면 그 버튼의 명령이 실행되며 노트는 그 요청 `claude_inputs`의 마지막 원소가 된다 — 전달 경로(argv/typed)는 앱이 자기 trim 뒤에 정하고 계획은 약속하지 않는다(D13). 노트에는 변수가 없어 앱의 렌더가 노트를 바꾸지 않는다(D10). 앱 프로덕션 코드는 바뀌지 않는다.
- 앱에 도달하는 노트는 평문 한 줄이다: 앱이 셸 명령·입력 상자 지시로 분류할 수 있는 값, 개행·제어문자, 상한 초과, 앱이 변수로 읽을 수 있는 `{…}`(D10)는 워커가 `{success:false}`로 거부하고 팝오버가 현지화된 이유를 보인다.
- 전송은 사람의 클릭 또는 Enter(IME 조합 중 제외)로만 일어나고, 실패는 성공으로 보이지 않으며 입력은 보존되고, 팝오버를 연 페이지가 아닌 페이지로는 보내지지 않는다. UI의 성공은 앱이 명령을 받아 터미널을 열었다는 뜻뿐이다 — 노트가 claude에 전달됐다는 뜻이 아니다(D12).
- 적용 표면: PR·이슈·저장소 헤더 버튼(항목 3)과 PR·이슈 목록 배치 버튼(항목 4 — D1).

## 완료의 정의

- 반드시 재현해 막아야 끝인 실패:
  - 앱 trim 뒤 `!`로 시작하게 되는 노트 — `!x`, ` !x`, 그리고 U+0085·U+200B·U+00A0·U+3000 뒤에 `!x` — 가 claude 셸 모드에 닿는다 → 워커가 거부해 네이티브 요청이 나가지 않는다. `/x`·`#x`·`{main} x`도 같다.
  - 변수 토큰(`{repo}`·`{number}`·`{이거}` 등)을 담은 노트 → 거부, 네이티브 호출 0(D10).
  - 명시적 빈 노트·공백뿐인 노트·문자열이 아닌 `note` → 거부 — 노트 없는 실행으로 바뀌지 않는다.
  - claude를 띄우지 않는 버튼(프리셋 5개)이나 정규화된 저장 입력이 5개인 버튼으로 온 노트 메시지(위조 포함) → 거부.
  - 지문이 바뀐 버튼, 또는 팝오버를 연 페이지와 다른 페이지(`PAGE_CHANGED_ERROR`, `background.js:165`)로 가는 노트 → 네이티브 호출 0.
  - 중복 전송 — Enter 연타, Enter와 클릭의 중첩, 전송 직후 닫기·재열기, 본체와 캐럿 교차 조작 → 요청 1건.
  - 배치 부분 실패 → 실패로 보이고 항목 결과(배지)가 남으며 자동 재전송은 없다(D12).
  - 응답을 보류한 채 헤더를 재생성하고 다시 나타난 같은 버튼으로 전송 → 요청이 추가되지 않는다.
  - content 스냅샷과 워커 재조회가 다른 목록 선택 → 네이티브 호출 0.
  - IME 조합을 확정하는 Enter가 전송한다, `{success:false}`가 성공으로 보이거나 입력이 지워진다 → 둘 다 일어나지 않는다.
- acceptance oracle:
  - red를 먼저 확인한 `node --test`(exit 0, 실행 수 기록 — 기준선 258)의 판정 함수 표·속성·조립 테스트, `cd app && swift test`(exit 0 — 기준선 CoreTests 517 + AppTests 130)의 trim 전제 고정과 카탈로그 게이트, `node tools/check-locales.js` exit 0.
  - 워커 런타임 하네스(항목 2): 실제 `background.js`의 `onMessage` 콜백을 Chrome API 대역(경계당 하나)으로 돌린다. 관측 — 거부 사례의 네이티브 호출 0회; 정상 노트는 저장 명령 그대로·마지막 입력에 노트 정확히 한 번·네이티브 1회; 상세·저장소·목록 분기 전부; 노트 없는 클릭은 변경 전 빌더와 바이트 동일(13개 프리셋 × 해당 페이지 종류, 빈 `claude_inputs` 키 생략 포함); 저장 객체·배열 비변경; 검사·전달을 제거하는 토글에서 실패. 같은 대역으로 실제 `chrome.action.onClicked` 콜백도 호출해 다섯 페이지 종류에서 기존 첫 버튼이 노트 없이 실행됨을 본다. 페이지 변경 검사는 앞선 조회를 정상 통과시킨 뒤 대기 중 페이지가 바뀌어 **최종 게이트가** 거부하는 사례를 포함하고, 최종 게이트를 제거하는 토글이 그 이유로 실패해야 한다.
  - 실브라우저(드라이버 수행, 절차는 항목 3·4가 체크리스트에 먼저 쓴다): 합성 클릭·합성 Enter 거부, IME 확정 Enter 비전송, 중복 전송, 페이지 이동, 배치 부분 실패, 레이아웃·테마, argv/typed 실제 전달 — node로 검증되지 않는 것들이다(확장 페이지에 DOM 하네스 없음 — `testing.md`).
- 코퍼스 범위: `extension/defaults.js`의 13개 프리셋(전수 소탕 표에 하나씩), 소탕 표의 사용자 명령 모양, 5개 로케일 카탈로그, 페이지 종류 5개. 저장 fixture는 만들지 않는다.
- 원자성·부분 실패·롤백 경계: 전송 한 번은 요청 한 건이고 진행 중에는 다시 보낼 수 없다. 워커·앱 검증의 거부는 터미널 실행 전이라(`Request.swift:290-295` — resolve가 run보다 먼저) 다시 보내도 중복이 없다. 앱이 탭을 연 뒤 응답만 유실되면 재전송이 세션을 하나 더 연다 — 기존 버튼과 같은 잔여이고, 요청 idempotency는 이 루프에서 만들지 않는다. 배치는 일부 항목을 실행한 뒤 `success:false`일 수 있어(`Request.swift:385`) 사람이 다시 보내면 성공한 항목도 다시 실행된다 — 자동 재전송은 하지 않는다(D12).

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

이 루프가 막는 실패를 일으킬 수 있는 행위자(사람·프로세스·시스템)와 그 능력을 열거한다. **발견을 배정하려면 어느 행위자가 그 결함에 닿는지 이름을 대야 한다** — 모델 밖 행위자가 필요한 발견은 기본이 잔여(원장 기록, 배정 없음)다. 행위자를 새로 들이는 것은 범위 변경이라 사용자 승인이 필요하다. 해당 없으면(순수 로직 루프) N/A + 근거.

- 사용자: 노트를 쓰고 클릭·Enter로 보낸다, Enter를 연타하거나 전송 직후 팝오버를 닫았다 다시 열거나 본체와 캐럿을 번갈아 누른다, 한국어·일본어·중국어 IME 조합 중 Enter·Esc를 누른다, 팝오버를 연 채 페이지를 옮기거나 뒤로 간다, typed 전달 중 그 탭에 타이핑한다(#16).
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
- `!`·`/`·`#` 노트(D2).
- 앱 오류 원문의 페이지 표시(#29).
- iTerm2/WezTerm argv 경로의 1024바이트 canonical 한계에 대한 수정 — 기존 노출, 체크리스트에서 실측하고 종결 때 미해결이면 이슈로 옮긴다(D11).
- 앱 setup window 문구(D6)와 저장된 입력의 정규화 차이(D7).

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

0라운드 이후 이 절과 「완료의 정의」에 항목을 **더하는 것은 범위 변경이다** — 결정 원장의 `사용자` 행 없이 추가하지 않는다(드라이버·검증자 발의는 비용 추정과 함께 사용자 승인 후). 드라이버가 스스로 쓴 기준을 스스로 집행하는 것이 일감 자가 생산의 뿌리다.

- 노트는 claude 입력 하나다. 새 프로토콜 필드나 앱 경로를 만들지 않고 요청 `claude_inputs`의 **마지막** 원소로 정확히 한 번 붙인다 — 맥락을 까는 `!` run이 먼저 가야 claude가 노트를 맥락과 함께 읽는다(`new-terminal-checklist.md:196`).
- 노트에는 변수가 없다(D10). 앱은 노트도 템플릿으로 렌더하므로(`Request.swift:168-172`; `{이거}`도 변수 이름으로 읽힌다 — 실측) 앱 패턴 `\{(\w+)\}`(`CommandRenderer.swift:57`)의 상위집합에 걸리는 `{…}`를 담은 노트는 거부한다 — 렌더 결과가 원문과 같으니 4096바이트 상한이 곧 전달 바이트 상한이고 배치 항목마다 다르지 않다.
- 노트 없는 클릭의 네이티브 요청은 지금과 바이트 동일하고, 노트가 있어도 저장된 command·입력·지문 객체를 바꾸지 않는다. 명시적 빈 값·공백뿐인 값·문자열이 아닌 `note`는 거부하며 "노트 없음"으로 취급하지 않는다.
- 노트는 클릭 메시지가 공급하는 **유일한 원천**이다. command·variables·지문에 섞지 않는다 — `shown`은 저장된 버튼의 지문 그대로다(`defaults.js:905-917`).
- 판정은 `defaults.js`에서 소유자가 하나씩인 네 함수가 내리고(D14), 워커의 판정이 권위를, content의 판정은 UX만 맡는다. 두 벌을 만들지 않는다:
  - claude를 띄우는가 — options 경고의 기존 정의(`options.js:404`)를 옮긴다; options 경고와 공유하는 것은 이 함수뿐이다 (엄격도는 D3)
  - 노트를 받는 버튼인가 — 위 판정 + 정규화된 저장 입력 수 + 1 ≤ `MAX_CLAUDE_INPUTS`(D13)
  - 노트 판정 — 정규화와 거부 사유 코드(비었음·상한 초과·첫 글자·변수 토큰(D10)·개행/제어문자)
  - 조립 — 저장된 버튼을 바꾸지 않고 `executionPayload`의 입력 뒤에 노트를 정확히 한 번 붙인다
- 첫 글자 규칙: 일반 공백(U+0020) trim 뒤 첫 글자가 `\p{Z}`·`\p{C}`·`!`·`/`·`#`이면 거부한다. 앱은 템플릿 렌더 → C0/DEL·개행 거부 → `.whitespacesAndNewlines` trim → `!`/`/`/`#` 분류 순서이고(`Request.swift:170-180`, `ClaudeInputPlan.swift:30-38`), 렌더는 D10으로 노트를 바꾸지 않으며, 이 trim이 벗기는 비-C0 스칼라 21개는 모두 Z∪C다(실측: U+0020 U+0085 U+00A0 U+1680 U+2000∼U+200B U+2028 U+2029 U+202F U+205F U+3000 — 드라이버 프로브가 실제 `resolveRequest`로 재확인, R0). 그러니 이 규칙을 지난 첫 글자는 앱의 어느 단계에서도 바뀌지 않는다. 첫 글자 `{`는 따로 막지 않는다 — 렌더가 첫 글자를 바꿀 길이 D10으로 없어졌다. JS `trim()`·`\p{Z}`로 대체하지 않는다 — 둘 다 U+0085·U+200B를 놓친다(실측).
- 제어 바이트·개행은 조용히 지우지 않고 보이게 거부한다(`defaults.js:863-866`의 `trim()` 사고).
- 전송은 사람만 한다. 캐럿·전송 버튼은 `onUserClick`(`defaults.js:350-360`)으로, Enter 키는 같은 `isUserGesture`에 `isComposing` 제외를 더해 한 곳에서 가드한다.
- 분할 버튼 하나(본체+캐럿)에 진행 중 잠금 하나: 공통 전송 함수가 첫 `await` 전에 잡고, 팝오버 DOM이 사라져도 요청이 끝날 때까지 유지하며, 이전 요청의 늦은 응답은 새 팝오버를 닫거나 입력을 지우지 않는다. 실행 입구(본체 클릭·캐럿 클릭·전송 버튼·Enter)는 모두 이 잠금을 거친다. 잠금의 정체성은 DOM 노드가 아니라 **같은 분할 버튼**(같은 페이지 목표·같은 종류·같은 인덱스·같은 지문)이다 — GitHub가 헤더를 교체해 본체·캐럿이 다시 만들어져도(`content.js:829`·`:907`) 진행 중인 요청 동안 다시 나타난 같은 버튼은 잠겨 있고, 이전 요청의 늦은 응답은 새 버튼·새 팝오버를 바꾸지 않는다. 다른 버튼·다른 페이지까지 막는 전역 잠금은 아니다.
- UI의 성공은 앱이 명령을 받아 터미널을 열었다는 뜻뿐이다(D12) — 전달은 그 뒤 비동기로 일어나고(`HostServer.swift:279`) 그 실패는 로그로만 남는다. `{success:false}`는 실패로 보이고(`content.js:69-71`) 입력은 보존된다; 배치는 바깥 `success:true` 안의 앱 판정(`interpretListBatchResponse`의 `appSuccess`·`itemKeys`)으로 읽고 부분 실패는 실패로 보인다; 자동 재전송은 없다. 오류 원문은 페이지에 그리지 않는다(`buttons.test.js:679-701`) — 로컬 판정은 현지화 문구, 그 밖은 원인을 단정하지 않는 일반 실패 문구와 console 원문.
- 캡처 시점(content의 캡처 규칙): 페이지 목표는 팝오버를 **연 순간**, 노트와 목록 선택은 **전송 때** 각각 한 번 읽고, content는 `await` 뒤 DOM에서 다시 읽지 않는다. 워커는 지금처럼 저장 버튼을 읽은 뒤 현재 선택을 DOM에서 독립적으로 다시 읽어 메시지 스냅샷과 대조하고 그 재조회 결과로 항목을 만든다(`background.js:478-503`) — 스냅샷과 재조회가 다르면 네이티브 호출 0. 전송 직전 비교는 최종 게이트가 한다(`background.js:182-207`). 목표가 바뀌면 팝오버를 캐럿과 함께 치우지만(`content.js:863-883`), 닫기·페이지 이동은 이미 넘긴 실행을 취소하지 않는다(최종 검사 뒤 IPC 구간의 잔여 — `background.js:361`).
- 한 요청의 claude 입력 합계는 `MAX_CLAUDE_INPUTS`(`defaults.js:321`) 이하다 — 정규화된 저장 입력(`executionPayload`가 보내는 것) 수 + 1로 센다(D13). Warp helper 수명 산정의 전제다(`app/Sources/WarpHelper/main.swift:51`).
- 노트의 전달 경로(argv/typed)를 계획·문서·UI가 약속하지 않는다 — 경로는 앱이 자기 trim 뒤에 정한다(D13).
- DOM은 경계가 아니다. 팝오버의 격리 방식(shadow root 여부)은 스타일·단축키 문제로만 고르고, 보안은 워커의 판정이 진다.
- 카탈로그: 새 문자열은 5개 로케일 전부에 둔다. 핀(`tools/check-locales.js:28-36`, `tests/i18n.test.js:668`·`:1608-1646`)은 리뷰된 편집으로만 옮긴다. `_locales`를 바꾸는 승격은 `swift test`도 게이트다 — `CatalogueOwnershipTests`가 `_locales`를 읽어 앱 카탈로그와의 값 중복·스토어 안 중복·포함 관계를 막는다(`app/Tests/AppTests/CatalogueOwnershipTests.swift:50`·`:173-289`; 앱에 `Close`가 이미 있다 — `app/Sources/App/Resources/en.lproj/Localizable.strings:64`).
- 게이트의 성패는 종료 코드로 판정하고 실행 테스트 수를 따로 적는다(CLAUDE.md). red 먼저, 토글은 패치 역적용.
- 앱 프로덕션 코드는 바꾸지 않는다. Swift 변경은 첫 글자 규칙의 전제를 `resolveRequest` 진입점으로 고정하는 테스트뿐이다.

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
| 1 | 판정 계약 — `defaults.js`에서 소유자가 하나씩인 네 함수: claude 판정(options 경고가 공유하는 것은 이것뿐)·노트 수용(정규화된 저장 입력 수 기준)·노트 판정(평문 첫 글자·변수 토큰(D10)·길이·개행/제어, 거부 사유 코드)·조립(저장된 버튼 비변경, 노트는 마지막에 정확히 한 번); 그리고 `resolveRequest` 진입점으로 trim 전제를 고정하는 Swift 테스트 | 판정 계약 | (a) "claude를 띄우는가"가 `options.js:404` 인라인 한 곳뿐이라 content·worker가 공유할 술어가 없다 (b) 노트 판정이 없다 — JS 공백 개념(`trim()`·`\p{Z}`)으로 만든 `!` 검사는 앱이 벗기는 U+0085·U+200B를 놓친다(실측) (c) 앱이 노트를 템플릿으로 렌더해 원문 493B가 8201B가 되고 배치 항목마다 길이가 갈린다(드라이버 프로브) — 변수 토큰 판정이 없다 (d) 합계를 정규화된 수로 세는 함수와, 저장 객체를 바꾸지 않고 노트를 마지막에 한 번 붙이는 조립 함수가 없다 (e) trim 전제를 진입점으로 고정하는 테스트가 없다 | `extension/defaults.js`, `extension/options.js`, 신규 `tests/claude-note.test.js`, `app/Tests/CoreTests/CoreTests.swift` | — | verified | red 먼저: `node --test tests/claude-note.test.js` 구현 전 14/14 실패(함수 미정의 13 · lint 1), options 경고 lint 추가 뒤 1 실패 → 구현 후 15/15 통과 · 게이트: `node --test` exit 0 · 273/273(기준선 258, +15) · `cd app && swift test` exit 0 · CoreTests 518(skip 1; 기준선 517, +1) · AppTests 130 · `node tools/check-locales.js` exit 0 · 토글(`git apply -R`): `defaults.js` 변경 제거 → 14 실패/1 통과(options lint만 통과) · `options.js` 변경 제거 → 테스트 3·4 실패 · 고장 주입(스크래치 사본 복원): 첫 글자 규칙을 `trim()`+`[!/#]`로 → 테스트 9·10 실패(U+200B 통과) · 중괄호 규칙을 ASCII `\{\w+\}`로 → 테스트 11 실패(`이거 {이거}`) · `Request.swift` trim에 `q` 추가(패치 역적용으로 복원) → `testEveryLeadingScalarTheTrimStripsIsASeparatorOrOther` 실패(`U+0071`) · 노트 없는 경로: `node /tmp/claude-note-payload-snapshot.js <작업 트리> <out>` 변경 전후 16개 버튼(`executionPayload`·`buttonFingerprint`·`toStoredButton`·`normalizeClaudeInputs`) → `cmp` exit 0 · 기존 테스트 수정 0건 · Swift 테스트 소요 2.9초(요청당 입력 4096개; 입력 하나씩은 9.4초) · 재실행(드라이버): 작업 트리 node --test → exit 0 · 273/273; cd app && swift test → exit 0 · CoreTests 518(skip 1) · AppTests 130; 고장 주입(스크래치 사본, 첫 글자 규칙을 /^[!\/#]/u로) → tests/claude-note.test.js 15 중 2 실패(9·10) | |
| 2 | 워커 경로 — 상세·저장소·목록 배치 분기 전부에서 `note` 형 검사 → 항목 1 판정 → 조립 → 네이티브 호출; 배치 메시지·요청 빌더의 노트 자리; 실제 `background.js`의 `onMessage`를 Chrome API 대역(경계당 하나)으로 돌리는 런타임 하네스와 토글(「완료의 정의」의 관측 목록); 원천 부정 주석 갱신 | 워커 경로 | (a) `onMessage`가 `note`를 모른다 — 상세·저장소(`background.js:612-623`)와 목록(`background.js:581-610`) (b) `runButton`(`background.js:371-375`)·`buildListBatchRequest`(`defaults.js:560-565`)·`buildListBatchMessage`(`defaults.js:584-593`)에 노트 자리가 없다 (c) 워커 경로를 런타임으로 통과하는 테스트가 없다 — 지금 검사는 소스 lint다(`tests/buttons.test.js:652-661`) (d) 원천 부정 주석(`defaults.js:844-854`, `background.js:156-158`·`303-304`)이 노트 도입 뒤 거짓이 된다 | `extension/background.js`, `extension/defaults.js`, 신규 런타임 하네스 테스트, `tests/list-pages.test.js`, `tests/buttons.test.js` | 1 | verified | red 먼저: `node --test tests/worker-note.test.js` 구현 전 10 중 5 실패(2·3 노트 무시, 4·5·10 거부 상수·판정 없음) · 1·6·7·8·9는 기존 불변식이라 구현 전에도 통과 → 구현 후 10/10 · 게이트: `node --test` exit 0 · 283/283(직전 273, +10) · 앱·카탈로그 무변경이라 `swift test` 미실행 · 기존 lint `tests/buttons.test.js`의 wire message 검사가 `executionPayload(` 문자열에 묶여 깨져 `clickPayload(`로 고치고 두 빌더 본문 확인을 더함(소탕 표) · 토글(`git apply -R` `background.js`) → 10 중 5 실패(2·3·4·5·10) · 고장 주입(`python3 /tmp/claude-note-item2-toggles.py <작업 트리>`, 저장 바이트 복원 확인, `--test-reporter=tap`): 워커 노트 판정 제거 → 3·4 실패(`pr 42`가 `success: true`) · 노트 전달 제거 → 2·3 실패 · 최종 게이트 두 곳 제거 → 7 실패(`success: true`, 기대는 `PAGE_CHANGED_ERROR`) · 노트 없는 경로: `node /tmp/claude-note-noteless-compare.js <작업 트리> <확장 폴더> <out>`를 `3aa6c98`의 `background.js`·`defaults.js`·`i18n.js`(`git show`로 추출)와 현재 트리에 각각 → 18회(프리셋 클릭 13 + 아이콘 5)의 응답·네이티브 메시지 직렬화 `cmp` exit 0 · 하네스 함정: 스크립트에서 돌린 `node --test`는 spec 리포터로 바뀌어 TAP 정규식이 아무것도 못 잡았다 — 토글 판정은 `--test-reporter=tap` + 종료 코드로 함 · 재실행(드라이버): 작업 트리 node --test --test-reporter=tap → exit 0 · 283/283; 고장 주입(스크래치 사본) 최종 게이트 제거 → worker-note 10 중 1 실패(7) · 워커 노트 판정 제거 → 10 중 2 실패(3·4) · 1′ 뒤 재실행: `node --test --test-reporter=tap` exit 0 · 285/285 · `node /tmp/claude-note-noteless-compare.js <작업 트리> <확장 폴더> <out>`을 `/tmp/claude-note-ext-3aa6c98`(`git show 3aa6c98:`의 세 파일과 `cmp` exit 0)과 현재 트리에 각각 → 18회 `cmp` exit 0 | |
| 3 | 분할 버튼·팝오버 컴포넌트와 PR·이슈·저장소 헤더 장착 — ▾ 캐럿은 claude를 띄우는 버튼에 붙은 분할 버튼의 오른쪽 조각으로, 저장소 헤더의 채운 초록 버튼에서는 버튼과 이어진 조각이고 PR·이슈 행의 아이콘 버튼 옆에서는 작은 캐럿이며 `currentColor` 단색 SVG다(D4·D5); 한 줄 입력·전송·닫기, 전송 잠금·캡처 시점, 키보드·IME·단축키 차단, 접근성(`aria-haspopup`·`aria-expanded`·툴팁/레이블), 진행·성공·실패 표시와 입력 보존, 목표 변경 시 제거, 5개 로케일 문자열과 핀; DOM 격리 방식·스타일 주입의 CSP 통과·라이트/다크 테마는 실브라우저 실측으로 정한다(기존 버튼은 CSSOM `style.cssText`만 쓴다 — `content.js:32`); 위치 계산은 `layout.js` 순수 함수; **이 항목의 실브라우저 점검 절차를 `docs/new-terminal-checklist.md`에 먼저 쓴다** | UI 컴포넌트·카탈로그 | (a) claude 버튼에 붙은 입력 UI가 없다 (b) PR 헤더의 버튼 칸과 메타 행이 overflow:hidden이라 칸 안에 둔 팝오버는 잘린다(`layout.js:6-17`) (c) 실행 입구가 여럿(본체·캐럿·전송 버튼·Enter)인데 진행 중 잠금의 소유자가 없다 — 지금 버튼은 제 `disabled`만 쓴다(`content.js:46-47`·`675-676`) (d) content의 원천 부정 주석(`content.js:77-83`)이 노트 도입 뒤 거짓이 된다 (e) 이 항목의 실브라우저 점검 절차가 체크리스트에 없다 (f) 판정의 새 거부 코드 `unpaired-surrogate`(1′)에 현지화 문구가 없다 — 항목 3이 5개 로케일 문구를 넣는다 | `extension/content.js`, `extension/layout.js`, `tests/layout.test.js`, `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`, `tools/check-locales.js`(바이트 핀), `tests/i18n.test.js`(호출 수·속성 목록 핀), `docs/new-terminal-checklist.md` | 1, 2 | todo | | |
| 4 | 목록 장착 — 항목 3 컴포넌트를 목록 배치 버튼에 붙인다: 선택은 전송 때 한 번 읽고, 선택 오류(0개·25개 초과)는 팝오버에 보이며 입력 보존, 결과는 `interpretListBatchResponse`·`itemKeys`·결과 배지로; 두 번째 검증기·전송 상태를 만들지 않는다; **이 항목의 점검 절차를 체크리스트에 먼저 쓴다** | 목록 장착 | (a) 목록 버튼은 클릭 시점의 선택을 읽는다(`content.js:567`) — 팝오버에서는 전송 때 한 번 (b) 배치의 앱 실패는 바깥 `success:true` 안의 `batch`로 온다(`background.js:604-605`) — 이행을 성공으로 읽으면 실패 표시와 입력 보존이 깨진다 (c) 이 항목의 실브라우저 점검 절차가 체크리스트에 없다 | `extension/content.js`, `tests/list-pages.test.js`, 필요 시 항목 3의 카탈로그·핀 파일, `docs/new-terminal-checklist.md` | 1, 2, 3 | todo | | |
| 5 | 문서 — README·CLAUDE.md·`docs/context/claude-input-delivery.md`(필요 시 `docs/context/index.md`) | 문서 | (a) README의 claude 입력·Warp 권한 서술이 노트를 모른다(`README.md:14,16,34,94,156,190,285,287`) (b) 평문 전용(D2)·변수 금지(D10)·첫 글자 규칙의 실측 전제·UI 성공의 뜻(D12)·경로 비약속(D13)·열 때 목표 캡처가 CLAUDE.md·`docs/context/`에 없다 | `README.md`, `CLAUDE.md`, `docs/context/claude-input-delivery.md`, 필요 시 `docs/context/index.md` | 2, 3, 4 | todo | | |
| 1′ | 판정 계약 개정 — 리뷰 1 차단 | 판정 계약 | (a) 단독 서로게이트가 앞머리 밖에서 통과하고 바이트 검사가 다른 문자열을 센다 (b) 닫힌 중괄호 판정이 이차 비용 (c) `trimOrdinarySpaces`의 `/ +$/`가 이차 비용 — `normalizeClaudeInputs`와 공유 (d) 판정 머리 주석의 "reaching claude exactly as written"이 앱의 말미 trim과 어긋난다 | `extension/defaults.js`·`extension/background.js`(진단 매핑)·`tests/claude-note.test.js`·`tests/worker-note.test.js` | 1 | verified | red 먼저: `node --test --test-reporter=tap tests/claude-note.test.js tests/worker-note.test.js` 구현 전 27 중 4 실패(13 서로게이트 — `high first`가 `leading-character`, 14 비용 — `Script execution timed out after 1500ms`, 16 닫힌 목록, 21 워커 런타임) → 구현 후 27/27 · 게이트: `node --test --test-reporter=tap` exit 0 · 285/285(직전 283, +2) · `node tools/check-locales.js` exit 0 · 앱 무변경이라 `swift test` 미실행 · (a) `/\p{Cs}/u`를 고른 이유: 한 번 훑는 선형 검사이고, `u` 플래그에서 짝 맞은 쌍은 보충 평면 코드 포인트 하나라 걸리지 않고 고립 반쪽만 Cs다; `String.prototype.isWellFormed`는 Chrome 111부터인데 `rg -n minimum_chrome_version extension/manifest.json` → 0건이고, 이 파일은 이미 `\p{…}`+`u`를 쓴다 · 새 코드 `unpaired-surrogate`는 `empty` 뒤·`control-character` 앞 → `CLAUDE_NOTE_ERRORS`·`CLAUDE_NOTE_REFUSALS`·워커 런타임 사례 2건(× `pr`·`issue-list`, 네이티브 0) · 비용 테스트: n=131072 두 부류를 `vm.runInThisContext(…, { timeout: 1500 })`로 — 구현 후 `duration_ms: 0.808`(두 입력 판정+정규화 합) · 옛 구현 복원(`python3 /tmp/claude-note-1p-restore-proofs.py <작업 트리>` — 변형 파일 → `diff -u --label` 패치 → `git apply -R` → 실행 → `git apply`, 매번 바이트 복원 True·`git status --porcelain` 불변): 옛 중괄호 정규식 → claude-note 17 중 1 실패(14, `open braces: Script execution timed out after 1500ms`) · 옛 trim 정규식 → 17 중 1 실패(14, `inner spaces: Script execution timed out after 1500ms`) · `\p{Cs}` 줄 제거 → 27 중 3 실패(13·16·21) · 워커 진단 줄 제거 → 27 중 2 실패(21·27) · 프로덕션 변경 전체 역적용 → 27 중 4 실패(13·14·16·21, red와 같음) · 차등(`node /tmp/claude-note-1p-differential.js <작업 트리>`, 오라클 = `git show HEAD:extension/defaults.js`(9c65961), 옛 정규식임을 소스 문자열로 확인): `trimOrdinarySpaces` 500683건 불일치 0 · `normalizeClaudeInputs` 60044건(희소 배열 19382 · 양쪽 같은 예외 3365) 불일치 0 · 중괄호 두 `indexOf` 대 `/\{[^}]*\}/u` 500683건(참 70537) 불일치 0 · `claudeNoteVerdict` 500704건 중 고립 반쪽 없는 264238건 불일치 0, 있는 236466건 전부 `unpaired-surrogate` · NBSP·U+3000·TAB 양끝 보존 · 코퍼스: 수기(빈 값·공백뿐·양끝/내부 공백·특수 문자 25종 × 배치 9·중괄호·서로게이트·이모지·결합 문자·4096/4097B) + 시드 생성 50만(길이 0∼48, 20만은 고립 반쪽 제외) + 긴 입력 400(256∼2048자, 공백 70%) + 비배열 인자·비문자열 원소 21종·희소 배열 · 계약 밖: trim에 비문자열을 직접 넘기면 둘 다 TypeError(메시지만 다름), `replace` 메서드가 있는 객체는 HEAD는 그 반환값·트리는 TypeError — 호출부 둘은 `String()` 뒤·`typeof` 검사 뒤에만 부른다 · 비용 측정(`node /tmp/claude-note-1p-cost.js <작업 트리>`, 32768/131072/524288자, 5회 최솟값): 판정 9부류·trim 2·정규화 2·`commandStartsClaude` 3 전부 마지막 4배 단계 ×1.0∼×3.8, 524288자 최대 4.026ms(이모지 쌍) · (d) 말미 축소: 드라이버 프로브 `r1probe/out-wire.txt` `trailing-nbsp` 3→1B · `trailing-zwsp` 4→1B · 재실행(드라이버): 작업 트리 node --test --test-reporter=tap → exit 0 · 285/285; 스크래치 사본 — 옛 중괄호 정규식 복원 → claude-note 17 중 1 실패(14) · 옛 trim 정규식 복원 → 17 중 1 실패(14) · \p{Cs} 줄 제거 → 17 중 2 실패(13·16) | |
| 2′ | 워커 하네스 개정 — 리뷰 2 차단 | 실행 경로(worker) | (a) 대역이 판독 함수별 기대 인자 값(선택자·`{kind, owner, repo}` 등)과 발신 탭을 대조하지 않는다 — 같은 자료형의 틀린 값도 통과한다 (b) 네이티브 호스트 이름을 기록·단언하지 않는다 (c) 최종 게이트 테스트의 페이지 이동이 게이트 조회에 묶여 있다 (d) 단일 앱 실패·배치 부분 실패의 워커 응답 전달이 런타임 테스트 밖이다(D12의 전제) | `tests/worker-harness.js`·`tests/worker-note.test.js` | 2, 1′ | todo | | |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶인다. 독립 승격(다른 항목과 따로·나란히)은 파일 집합과 계약이 모두 겹치지 않을 때만 하고, 파일이 겹치는 항목은 선행 항목의 계약이 승격된 뒤 의존 순서대로 차례로 승격한다. 승격 칸에는 커밋 해시를 적는다
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
| D10 | 드라이버 | 검증자 R0-1·R0-5: 노트가 템플릿이라 렌더 전후 길이가 다르고(원문 493B → 8201B, 배치 항목별 4096B/4097B), 실행 종류·`{base}` 부재·유니코드 이름·`{cd}`가 판정을 가른다 | D9를 대체 — 노트에는 변수를 두지 않는다: 앱이 변수로 읽을 수 있는 `{…}`를 담은 노트는 거부해 앱 렌더가 노트를 바꾸지 않게 한다(렌더 결과 = 원문 → 4096B 상한이 곧 전달 바이트 상한, 배치 항목별 차이 없음). 판정은 앱 패턴 `\{(\w+)\}`(ICU, `CommandRenderer.swift:57`)의 상위집합으로 한다 | 드라이버 프로브(실제 `resolveRequest`): `repo-expansion rawBytes: 493 resolvedBytes: [8201]` · `item-9 … [4096]` · `item-10 … [4097]` · `unicode-variable REJECTED: Variable {이거} not provided` · `repo-button-on-pr REJECTED: Variable {number} not provided` · R0 | 상위집합 규칙의 과잉 거부(예: `{"a":1}`)는 현지화 문구로 보인다 |
| D11 | 드라이버 | 검증자 R0-1 후단: argv로 붙은 노트가 명령을 1024B canonical 한계 너머로 밀면 iTerm2/WezTerm 새 탭에서 잘릴 수 있다 | 이 루프에서 고치지 않는다 — 기존 노출이다(한계 가드는 cmux뿐 `TerminalRunner.swift:640-672`; iTerm2 `write text`·WezTerm `send-text`는 탭 생성 직후 대기 없이 쓴다 `AppleScriptSupport.swift:65`·`TerminalRunner.swift:969-979`). 수정은 앱의 raw-mode 대기를 두 터미널로 넓히는 별도 범위이고 앱 프로덕션 코드 불변 원칙과 충돌한다. 완료를 막지 않고, 체크리스트에 실측 항목을 두고, 종결 때 미해결이면 이슈로 옮긴다 | 드라이버 추산: `{cd}`(기본 디렉터리 설정, `BaseDirectory.swift:73-114`) ≈420B + `pr.worktreeClaude` 본문(30자 브랜치) ≈320B → 노트 전 ≈740B · 사용자 터미널은 cmux(한계 가드 있음) · R0 실행 요청 2는 미실행(두 앱이 꺼져 있고 iTerm2 자동화는 TCC 동의 창을 띄울 수 있다) | iTerm2/WezTerm에서 탭 생성 → 셸 raw mode 진입 시점 미실측 — 잘림 여부 미확인 |
| D12 | 드라이버 | 검증자 R0-2: 앱은 탭을 연 뒤 전달을 비동기로 시작하고 응답한다(`HostServer.swift:279`) — 요청 성공은 노트 전달 성공이 아니다; 배치는 일부 실행 뒤 `success:false`일 수 있다(`Request.swift:385`) | 반영 — UI 성공은 "앱이 명령을 받아 터미널을 열었다"만 뜻한다; 배치 결과는 기존 `interpretListBatchResponse`(`appSuccess`·`itemKeys`)와 결과 배지로 보이고 부분 실패는 실패로 보인다; 자동 재전송은 없다. D3의 잔여는 정규식 오탐에 한정되지 않는다 — 정상 프리셋에서도 비동기 전달 실패는 성공 표시 뒤 로그로만 남는다 | R0 | — |
| D13 | 드라이버 | 검증자 R0-6: 확장의 정규화와 앱의 trim이 달라 경로를 확장이 예측할 수 없다(실측: 저장 `["\u200B"]` + 노트 `hello` → 앱 결과 `["hello"]`, argv 후보) | 반영 — 계획·문서는 노트의 전달 경로(argv/typed)를 약속하지 않는다; 경로는 앱이 자기 trim 뒤에 정한다. 합계 상한은 정규화된 저장 입력(`executionPayload`가 보내는 것) 수 + 1 ≤ `MAX_CLAUDE_INPUTS` | 드라이버 프로브 `stored-whitespace rawBytes: 5 resolvedBytes: [5]` · R0 | — |
| D14 | 드라이버 | 검증자 R0-7: 항목 1의 네 책임을 한 함수로 합치면 options 경고가 노트 수용 여부에 종속되고, 워커 검증·조립(항목 2·4)과 팝오버 상태·전송 가드(항목 3·4)가 두 벌이 될 수 있으며, 체크리스트(항목 5)와 동작 증거(항목 3·4)가 순환 의존한다 | 반영 — 항목을 계약 기준으로 재분할하고, 실브라우저 점검 절차는 항목 3·4가 각자 체크리스트에 먼저 쓴다 | R0 | — |
| D15 | 드라이버 | 검증자 R0b: 상위집합이라는 설명만으로는 구현이 증명되지 않는다 — ICU `\w`를 JS로 재현하면 어긋날 수 있다 | D10의 판정은 닫힌 중괄호 구간을 넓게 거부하는 구조적 상위집합으로 한다(예: `/\{[^}]*\}/u` — 앱 패턴 `\{(\w+)\}`의 모든 일치는 `}`를 담지 않는 닫힌 구간이다); `{{repo}}`·`\{repo}`도 예외 없이 거부한다(앱 렌더러에 이스케이프 규칙이 없다 — `CommandRenderer.swift:96`) | R0b | 과잉 거부(`{}`·`{ a }`·`{"a":1}`)는 현지화 문구로 보인다 |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점 전체. 미검사 항목을 비워 두지 않는 것이 이 표의 목적이다. 세 열뿐이다 — 셋째 열은 코드로 알 수 없는 이유 한 절이거나 `파일:행`이다. 판정이 안전이고 그런 이유가 없는 대상은 한 행에 나열해 합친다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `pr.checkoutClaude` | 캐럿 ○ · `[노트]` · 경로는 앱이 정한다(D13) | `defaults.js:48-51` · `ClaudeInputPlan.swift:770-777` |
| `pr.worktreeClaude` | 캐럿 ○ · `[노트]` → 위와 같음 | `defaults.js:52-55` |
| `repo.openClaude` | 캐럿 ○ · `[노트]` → 위와 같음 | `defaults.js:126-129` |
| `pr.review` | 캐럿 ○ · `[!view, !diff, 노트]` 합계 3 · 경로는 앱이 정한다(D13) | `defaults.js:61-65` |
| `issue.read` | 캐럿 ○ · `[!×3, 노트]` 합계 4 · 경로는 앱이 정한다(D13) | `defaults.js:84-93` |
| `issue.startWork` | 캐럿 ○ · `[!view, 노트]` 합계 2 · 경로는 앱이 정한다(D13) | `defaults.js:94-98` |
| `pr-list.checkoutClaude` | 캐럿 ○(항목 4) · 항목마다 `[노트]` · 경로는 앱이 정한다(D13) | `defaults.js:76-79` · `defaults.js:560-565` |
| `issue-list.triageClaude` | 캐럿 ○(항목 4) · 항목마다 `[!view, 노트]` · 경로는 앱이 정한다(D13) | `defaults.js:108-112` |
| `pr.checkout` · `pr.worktree` · `issue.open` · `repo.open` · `repo.updateMain` | 캐럿 × — 명령에 `claude`가 없다 | `defaults.js:44-47,56-59,99-103,122-125,130-133` |
| 사용자 명령 `… && claude --model x`·`--continue` | 캐럿 ○ · 경로는 앱이 정한다(D13) | `ClaudeInputPlan.swift:450-452` |
| 사용자 명령 `echo claude`·`cat ~/.claude/…`·`claude -p …` | 캐럿 ○(오탐) · claude가 뜨지 않아 전달은 120초 대기 뒤 로그로만 남고 UI는 성공 — D3·D12의 잔여 | `ClaudeInjector.swift:1024-1030` |
| 사용자 alias(`cc` 등)로 claude를 띄우는 명령 | 캐럿 × (미탐) | 명령 텍스트로는 alias를 알 수 없다 |
| 정규화된 저장 입력이 5개인 버튼 | 캐럿 × (합계 상한, D13) | `defaults.js:321,867-876` |
| "claude를 띄우는가"를 판정하는 곳 | `commandStartsClaude` 하나 — options `updateClaudeWarn`이 부른다; content 그리기·worker 검증은 항목 2/3에서 호출 | `defaults.js:952-954` · `options.js:404` |
| `claude_inputs`를 조립하는 곳 | `clickPayload` 하나(노트가 없으면 `executionPayload`, 있으면 `executionPayloadWithNote`) — `runButton`과 `buildListBatchRequest`가 부른다; 확장 아이콘 경로는 노트 없음(하네스로 확인) | `defaults.js:1051-1053,561-566` · `background.js:402` |
| 클릭 메시지 필드가 요청에 닿는 곳 | `note` 하나만 원천 — `noteOfClick`만 읽고(첫 `await` 전), 판정이 돌려준 노트만 `clickedButton`(수용)·`clickPayload`(조립)로 간다; `action`은 경로 선택, `buttonIndex`는 저장 버튼 색인, `shown`·`target`은 비교 키, `selected`는 대조용 스냅샷(항목은 워커 재조회로 만든다), `resultKeyProtocol`은 형식 확인 | `background.js:189-195,334-341,531-537,613-667` · `defaults.js:512-514` |
| "메시지는 원천이 아니다"를 말하는 주석 | `defaults.js`·`background.js` 세 곳 노트 예외로 갱신(항목 2), `content.js`는 항목 3 | `defaults.js:861-863` · `background.js:157-158,331-333` · `content.js:77-83` |
| 입력 첫 글자를 바꿀 수 있는 앱 단계 | 렌더는 D10으로 노트를 바꾸지 않고, trim(Z∪C)·분류(`!/#`)는 첫 글자 규칙이 막는다; trim 전제는 진입점 테스트가 고정 | `Request.swift:170-180` · `CommandRenderer.swift:57,96-104` · `ClaudeInputPlan.swift:30-38` · `defaults.js:1000` · `CoreTests.swift:739-778` |
| 노트 내부 문자(첫 글자 제외) | LF/CR/C0/DEL은 확장이 먼저 거부하고 앱도 거부; 변수 토큰은 확장이 거부(D10); 그 밖은 저장 입력과 같은 앱 규칙 | `Request.swift:197-222` |
| 노트 안 `{단어}` | 닫힌 중괄호 구간을 모두 거부 — 첫 `{` 뒤에 `}`가 있으면(두 `indexOf`, 1′; `/\{[^}]*\}/u`와 결과 동일은 차등 비교) — 렌더가 노트를 바꾸지 않는다; 과잉 거부(`{"a":1}` 등)는 현지화 문구(D10·D15) | `CommandRenderer.swift:57` · `defaults.js:1033-1034` |
| 버튼이 붙는 표면 | PR 헤더·이슈 배지 행·저장소 crumb(항목 3), 목록 툴바(항목 4); 확장 아이콘 클릭 제외 | `content.js:589-622,721-831` · `background.js:552-571` |
| 팝오버를 치우는 곳 | 목표가 바뀔 때 `removeInsertedButtons`가 캐럿·팝오버를 함께 지운다 | `content.js:863-883` |
| 실행 입구(본체 클릭·캐럿 클릭·전송 버튼·Enter) | 분할 버튼 하나에 진행 중 잠금 하나 — 공통 전송 함수가 첫 `await` 전에 잡는다(항목 3) | `content.js:45-64,560-584,673-693` |
| 노트·목록 선택을 DOM에서 읽는 곳 | 전송 때 한 번 — `await` 뒤 다시 읽지 않는다(항목 3·4) | `content.js:567` |
| claude 입력·노트의 정규화(양끝 U+0020 trim) | `trimOrdinarySpaces` 하나 — `normalizeClaudeInputs`와 노트 판정이 같이 쓴다; 1′에서 정규식을 양끝 색인 걷기로 바꿈(출력·예외 동일은 차등 비교) | `defaults.js:876-890,1028` |
| options 경고의 "입력이 있는가" | 고침 — `trim()` 대신 `normalizeClaudeInputs`로 센다: 탭만 있는 입력은 보내지고 앱이 거부하는데 경고가 숨었다 | `options.js:403` |
| 편집기의 입력 행 상한 · 저장 버튼 판독의 입력 수 상한 | 안전 — 앞은 편집 행 수, 뒤는 저장 모양 판정이고 전송 판정이 아니다; 저장 때 정규화되고 노트 수용은 정규화 수로 센다 | `options.js:376,1307` · `defaults.js:809,962,1095` |
| `buttonUsesAllowedVariables`의 입력 순회 · `migrations.js`의 claude 명령·입력 | 안전 — 변수 판정과 옛/새 명령 데이터·미리보기 사본이고 claude 판정이나 정규화가 아니다 | `defaults.js:220-233` · `migrations.js:25-33,258-261,344-353` |
| `background.js` · `content.js` | `background.js`는 항목 2가 호출(`noteOfClick`→`claudeNoteVerdict`, `clickedButton`→`buttonTakesClaudeNote`, `clickPayload`→`executionPayloadWithNote`); `content.js`는 판정 없음 — 항목 3이 `buttonTakesClaudeNote`·`claudeNoteVerdict`를 호출 | `background.js:191,339,402` |
| 앱의 경로 판정(`commandAcceptsAppendedClaudePrompt`) | 확장이 복제하지 않는다(D13) | `ClaudeInputPlan.swift:453-589` |
| 실행 함수를 부르는 곳 | 둘뿐 — `onMessage`(상세는 `RUN_BY_KIND`, 목록은 `executeListBatch`, 노트 전달)와 확장 아이콘(`RUN_BY_KIND`, 인자 4개라 노트 없음) | `background.js:599,641,667` |
| 빌더 → 송신 | `runButton`→`sendToNativeHost`, `buildListBatchRequest`→`sendBatchToNativeHost`만 — 둘 다 `clickPayload`에서 짓고 최종 게이트 뒤 동기 구간을 유지한다 | `background.js:399-407,537-541` |
| 기존 lint(`buttons.test.js`의 wire message 검사) | 고침 — `runButton`이 `clickPayload`로 짓게 되어 `executionPayload(` 문자열 검사가 깨졌다; 의미(송신에 자기 정규화가 없고 지문의 payload에서 출발)를 `clickPayload(` 확인과 `clickPayload`·`executionPayloadWithNote` 본문의 `executionPayload(button)` 확인으로 유지 | `tests/buttons.test.js:652-671` |
| 앱 setup window의 Warp 문구 | 변경 불필요 — 노트 클릭이 typed로 거부돼도 같은 안내 창이 뜬다; "all three" 불일치는 D6 | `TerminalRunner.swift:169-172` · `app/Sources/App/Resources/en.lproj/Localizable.strings:79,84` |
| iTerm2/WezTerm argv의 1024바이트 canonical 한계 | 미검사 — 앱은 cmux만 가드한다; 긴 노트로 체크리스트에서 실측(항목 3, D11) | `TerminalRunner.swift:640-672` · `AppleScriptSupport.swift:65` · `TerminalRunner.swift:969-979` |
| 팝오버 입력 중 GitHub 전역 단축키 | 미검사 — shadow root 안의 입력은 바깥 리스너에 host로 재지정되어 보인다; 실브라우저 실측(항목 3) | |
| IME 조합 중 Enter·Esc | 미검사 — 실브라우저 실측(항목 3) | |
| 노트 판정과 보조 함수의 처리 비용(길이 검사 전) | 선형(1′) — `claudeNoteVerdict`(`\p{Cs}`·`[\p{Cc}\p{Zl}\p{Zp}]` 한 글자 클래스, `^` 고정 첫 글자, 두 `indexOf`, `TextEncoder`)·`trimOrdinarySpaces`(양끝 색인 걷기)·`normalizeClaudeInputs`·`commandStartsClaude`(`\bclaude\b` — 시도마다 고정 길이 리터럴); 측정은 4배 단계 ×1.0∼×3.8(1′ 근거), 두 부류 131072자는 시간 상한 테스트가 고정 | `defaults.js:876-890,968-970,1025-1037` |
| 노트가 지나가는 나머지 함수(`buttonTakesClaudeNote`·`executionPayloadWithNote`·`clickPayload`·`noteOfClick`·`CLAUDE_NOTE_REFUSALS`) | 정규식 없음 — 위의 정규화·복사·조회뿐 | `defaults.js:974-979,1043-1053` · `background.js:173-194` |
| 노트 경로 밖의 기존 정규식 — URL·키 경로, 페이지 텍스트·속성, 저장 템플릿·face·툴팁, 마이그레이션, 카탈로그 | 범위 밖 — 노트가 지나가지 않는다; 고치지 않는다 | `defaults.js:228,279-284,334,369,422,432,536,1178` · `background.js:28,37,87,92,253,262,278,441` · `content.js:183,207,727` · `migrations.js:94` · `i18n.js:36,56` |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 차단·수정·실측 줄은 에이전트가, 판정 줄은 드라이버가 지정한 문구를 에이전트가 적는다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — 605fc78 · 승격 14:14 · 리뷰 14:14∼14:23 · 왕복 1 · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/0fc35e90-1ec3-413c-9d07-cb8929cf4b08/claude-note/R0-review.md`

- 반박: R0-1 노트 상한이 렌더 전후를 구분하지 않고 배치 항목별 렌더를 놓친다(P1) · R0-2 요청 성공≠노트 전달, 배치 부분 실패의 응답 경계(P1) · R0-3 진행 중 재전송 잠금의 소유자·수명·캡처 시점(P1) · R0-4 오라클이 워커의 새 신뢰 경계를 런타임으로 통과하지 않는다(P1) · R0-5 변수 검증 단위(실행 종류·`{base}`·유니코드·`{cd}`)(P2) · R0-6 경로 설명 오류·합계 기준·노트 없는 클릭 바이트 불변(P2) · R0-7 계약 기준 재분할·체크리스트 순환(P2)
- 처리: R0-1 반영(D10 — 노트 변수 금지로 렌더=원문) + 후단 기각(D11 — 기존 노출, 종결 때 이슈로) · R0-2 반영(D12) · R0-3 반영(불변 원칙 — 전송 잠금·캡처 시점) · R0-4 반영(완료의 정의 — 실제 `background.js` 런타임 하네스, 실브라우저 항목) · R0-5 반영(D10으로 부류 소멸) · R0-6 반영(D13, 불변 원칙 — 바이트 불변·비변경·빈/비문자열 거부) · R0-7 반영(D14 — 항목 재분할)
- 실측: 드라이버 프로브(실제 `resolveRequest`) `repo-expansion [8201]` · `item-9 [4096]` · `item-10 [4097]` · `stored-whitespace [5]` · `unicode-variable REJECTED` · `repo-button-on-pr REJECTED` · `stripped` 21개 · `outsideZC: []`; 실행 요청 2(iTerm2/WezTerm 4096B argv)는 미실행(D11)
- 판정: "이 계획으로 시작하는 데 합의하는가: no." → 반영 후 재리뷰

#### 설계 리뷰 재요청 — 130e607 · 승격 14:42 · 리뷰 14:42∼14:47 · 왕복 1 · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/0fc35e90-1ec3-413c-9d07-cb8929cf4b08/claude-note/R0b-review.md`

- 반박: R0b-1 목록 선택 1회 읽기는 content 규칙 — 워커의 재조회·대조는 유지(P2) · R0b-2 하네스가 아이콘 경로(`chrome.action.onClicked`)와 대기 중 페이지 변경을 돌려야 한다(P2) · R0b-3 잠금 수명이 같은 분할 버튼의 DOM 재생성을 덮어야 한다(P2) · R0b-4 파일 겹침 승격 규칙 문구(P3) · D10 구현 권고 — 닫힌 중괄호 구간을 넓게 거부, `{{repo}}`·`\{repo}` 예외 없음
- 처리: 전부 반영(불변 원칙 캡처 시점·진행 중 잠금, 완료의 정의 하네스·실패 목록, 항목 표 규칙 줄, D15)
- 실측: 추가 실행 요청 없음; D11 완료 차단 요구는 검증자가 철회("D11의 기각은 수용하며, 이전의 완료 차단 요구를 철회한다")
- 판정: "이 계획으로 시작하는 데 합의하는가: yes." → R1 시작

### R1

#### 리뷰 1 — 증분 · 130e607..8b14701 · 승격 15:11 · 리뷰 15:11∼15:21, 회신 15:22∼15:25 · 왕복 2 · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/0fc35e90-1ec3-413c-9d07-cb8929cf4b08/claude-note/R1-review1.md`·`R1-review1b.md`

- 차단: 단독 서로게이트가 앞머리 밖에서 판정을 통과하고 바이트 검사는 U+FFFD 치환 문자열을 센다(재현: `'a' + U+D800 + 'b'` → `valid:true`, `utf8Identity:false`, 앱 JSON 파서 거부 `command_template is required`, runCalls 0) · 닫힌 중괄호 정규식과 기존 SP trim이 길이 검사 전에 이차 비용(재현: `'{'.repeat(8192)` 95ms, 32768부터 1초 타임아웃; `'x' + ' '.repeat(n-2) + 'x'` 같음)
- 수정: 항목 1′로 연다(항목 2 뒤)
- 실측: 드라이버 프로브 `r1probe/out-plain.txt`·`out-wire.txt`·`out-cost.txt`(스크래치)
- 판정: "blocked" — "1′의 (a)∼(d) 처리는 적절합니다" → 항목 1 `verified` 유지, 1′ 배정

#### 리뷰 2 — 증분 · 8b14701..9c65961 · 승격 15:28 · 리뷰 15:28∼15:41, 회신 15:47∼15:52 · 왕복 2 · 원문 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/0fc35e90-1ec3-413c-9d07-cb8929cf4b08/claude-note/R1-review2.json`·`R1-review2b.json`

- 차단: 하네스 대역이 `executeScript`의 `target`·`args`와 네이티브 호스트 이름을 보지 않는다(재현: 검증자 변형 `bad-tab`·`bad-host`가 worker-note 10/10 통과) · 최종 게이트 테스트가 게이트 자신의 조회 안에서 페이지를 옮겨, 게이트를 빼면 이동도 사라진다(재현: 검증자 `r1-worker-flow.cjs --gate-off`는 독립 이동으로 `moved:true`·네이티브 1회 → exit 1, 커밋된 테스트는 이 재현을 못 한다)
- 수정: 항목 2′로 연다(1′ 뒤)
- 실측: 드라이버 프로브 `r1probe/out-mut-tab.txt`·`out-mut-host.txt`·`out-flow.txt`·`out-flow-gateoff.txt`(스크래치); 원본 워커는 독립 이동에 네이티브 0, 단일 실패·배치 부분 실패 응답 전달 정확
- 판정: "blocked" — "2′의 (a)∼(c)와 1′ 이후 진행 순서를 수용합니다" → 항목 2 `verified` 유지, 2′ 배정

## 열린 질문

원 요구 충족 후 발견된 마이너·에지케이스 방어 후보는 여기 적립한다(즉시 배정 금지) — 사용자 대화로 포함/이슈/기록 중 처분이 정해지면 그 결과를 원장에 남기고 지운다.
