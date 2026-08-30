# batch-list-pages

- 절차 정본: `/Users/choongjaelee/.claude/skills/drive-agent-loop/assets/plan-template.md` — R0 초안이며 사용자 승인 전 구현하지 않고 계획 파일만 커밋한다
- 대상: `/Users/choongjaelee/Codes/terminal-checkout-batch-list-pages-work/extension/`
- 시작 커밋: `1f3ef872d505969c834b777369c1b0dea06a4f60` (PR #73 머지 직후)
- 기준 트리: `main`/`origin/main` at `1f3ef87` · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-batch-list-pages-work` (`batch-list-pages`)
- 현재: R0 · 마지막 승격 없음 · R0 설계 리뷰 판정 완료 · 게이트 그린 (`node --test` exit 0, 222/222)
- 최근 검증자 판정: 드라이버 설계 리뷰 — 이 계획으로 시작하는 데 합의한다 — 항목 0부터 · 원문 없음

## 배경 — 확인한 원천

- [이슈 #67](https://github.com/dazebug/terminal-checkout/issues/67) — `/pulls`와 `/issues`를 `pr-list`·`issue-list`로 분류하고, 행 선택을 `items[]` 배치 요청으로 연결하며, 선택 방식·list-safe 변수·결과 UI를 확장한다는 기능 원천이다.
- [PR #73](https://github.com/dazebug/terminal-checkout/pull/73), `1f3ef87`, `app/Sources/Core/Request.swift:81-350` — `items` 키가 있으면 배치로 판정하고, top-level `command`·선택적 `claude_inputs`·비어 있지 않은 `items[].variables`를 요구하며, 최대 8개를 받는다. 모든 item의 내용 검증이 끝나기 전에는 실행하지 않고, 하나라도 검증에 실패하면 모든 item을 `{success:false,error}`로 돌려주며 유효했던 item에는 `not launched — batch rejected during validation`을 넣는다. 검증을 통과하면 순차 실행하고 item 순서의 결과를 반환하며, 실행 실패 후에도 다음 item을 계속한다.
- [PR #73](https://github.com/dazebug/terminal-checkout/pull/73), `1f3ef87`, `app/Sources/App/HostServer.swift:184-279` — 응답 예산은 요청 도착부터 150초이고, 두 번째 이후 item이 예산을 넘으면 실행하지 않고 `not launched — response deadline exceeded`를 해당 item 결과로 기록한다. 서비스 워커가 앱의 응답을 다시 해석하지 않고 Core의 결과를 직렬화하는 경계도 확인했다.
- `app/Sources/Core/CommandRenderer.swift:32-34` — 기준 트리의 `allowedVariables`에는 `repo`, `branch`, `base`, `main`, `branch_underbar`, `number`, `owner`만 있어 스펙이 요구하는 `{pr}`·`{issue}` list preset이 거부됐다. 항목 0에서 두 이름만 whitelist에 추가하고 실행·검증 semantics는 바꾸지 않았다.
- `extension/defaults.js:1-226,268-311` — defaults·preset·storage key·page classification·page target의 단일 원천이다. 현재 `/owner/repo/issues`와 `/owner/repo/pulls`는 repository tab으로 `repo`가 되고, `pageTargetOf`는 detail 외에는 number를 주지 않는다. content script와 service worker가 서로 다른 분류를 만들면 `/settings/profile` 같은 잘못된 경로에 명령을 보낼 수 있다는 현재 원칙도 확인했다.
- `extension/content.js:69-124,222-367,370-442` — 기존 버튼은 storage에서 읽은 command fingerprint와 page target을 보내고, `chrome.runtime.sendMessage`의 정상 응답 안에 든 `{success:false}`를 직접 검사한다. PR/issue detail의 구조적 anchor와 URL 변경·MutationObserver·polling 수명주기를 재사용해야 하며, 현재 list-row 선택과 toolbar attach는 없다.
- `extension/background.js:156-275,277-407,409-433` — 단건은 `command_template`을 `sendNativeMessage`로 보내고 `nativeOutcome`의 실패를 예외로 표면화한다. content script의 row selection을 받을 batch action, 앱의 정상적인 batch `success:false`를 보존하는 반환 경로, list selection batch를 제외하면서 기존 repo command로 폴백하는 icon 경로는 없다.
- `extension/options.js:1-154,586-729,1019-1137`, `extension/options.html:387-421`, `extension/migrations.js:1-94,185-290` — 현재 세 종류의 button kind와 세 storage key를 `SECTIONS`·`SETTINGS_KEYS`·backup·migration이 파생한다. `SETTINGS_VERSION`은 저장 내용이 검토된 세대이며 일반 Save가 임의로 올려서는 안 되고, 마이그레이션·부분 적용·거절·Reset 같은 명시적 행위만 올린다는 규칙이다.
- `README.md:8-18,119-175,229-247` 및 `docs/new-terminal-checklist.md:87-114` — 사용자에게 보이는 page별 변수와 claude-input 경로, 개발 게이트, 이미 실린 앱 batch fan-out 수기 점검을 확인했다. 새 list preset 두 개를 채택하면 현재 문서의 shipped preset 수와 typed-input 수치도 함께 재검토해야 한다.
- `docs/context/index.md`, `docs/context/testing.md`, `docs/context/options-page-reordering.md`, `docs/context/localization.md` — root `tests/`의 순수 함수·source oracle 경계, GitHub DOM을 faithful하게 재현하지 못하는 테스트 한계, redraw 중 index를 보존하지 말아야 하는 이유, `_locales`가 Chrome이 읽는 정본이라는 규칙을 확인했다. 사용자 지시의 `extension/test/` 경로는 이 checkout에 존재하지 않고 실제 JavaScript 테스트는 `tests/` 아래에 있다.
- `git log --oneline -15` — HEAD가 `1f3ef87`이며 직전 변경이 앱 측 `items[]` protocol이고, 그 앞에 cmux·claude delivery·settings migration이 있어 이번 계획은 앱 Core가 아니라 extension fan-out에 집중해야 함을 확인했다.

## 목표

- `https://github.com/<owner>/<repo>/pulls`와 `/issues`가 각각 `pr-list`와 `issue-list`로 동일하게 분류되고, content script와 service worker의 target gate가 그 분류를 공유한다. extension icon click은 selection DOM을 볼 수 없으므로 list selection 기반 batch를 실행하지 않고 기존 repo command로 폴백한다.
- 현재 보이는 list row를 안정적인 PR/issue 번호와 title로 식별하고, GitHub native row checkbox가 있는 경우와 없는 경우를 안전하게 전환하며, 선택된 각 row를 최대 8개까지 한 terminal session으로 fan-out한다. 선택이 0개이면 전체 visible rows로 묵시적으로 확장하지 않고 버튼 오류가 된다.
- list-safe 변수만 쓰는 list button이 `command`·선택적 `claude_inputs`·순서 보존 `items[].variables`의 앱 계약으로 전송되고, 단건의 `command_template` wire shape와 섞이지 않는다. 앱의 inner `success:false`와 per-item results가 content script까지 보존된다.
- batch button은 기존 busy/done/error 표시와 공존하면서 overall failure와 row별 결과를 보여 주고, settings·preset·migration·locale·README·hands-on checklist와 root `node --test` 순수 oracle이 함께 갱신된다.

## 완료의 정의

- 반드시 재현해 막아야 하는 실패: `/owner/repo/pulls` 또는 `/owner/repo/issues`에서 선택된 두 row가 현재는 repository page로 분류되어 batch 없이 동작하지 않는 상태를 재현하고, 구현 후에는 선택 순서대로 두 item을 가진 요청 하나가 전송되며 각각 한 session의 결과가 대응한다. 0개 선택·9개 선택·selection/page navigation 변경·앱의 overall `success:false` with `items`도 각각 전체 visible 실행, cap 초과, 잘못된 row 실행, 성공으로 보이는 버튼이 되지 않아야 한다.
- acceptance oracle: 구현 시작 시 `tests/`의 순수 함수 테스트를 먼저 추가해 red를 확인하고, 구현 후 리포 루트에서 `node --test`의 exit 0과 실행 test count를 기록한다. classification·wire envelope·selection identity·native/fallback predicate·response mapping·migration version을 테스트로 고정하고, 실제 GitHub DOM selector와 native checkbox 권한 조합은 `docs/new-terminal-checklist.md`의 수기 확인으로 남긴다. 앱 게이트 `cd app && swift test`는 드라이버가 실행하며 이 계획의 extension 결과로 해석하지 않는다.
- 코퍼스 범위: `extension/defaults.js`, `content.js`, `background.js`, `options.js`, `options.html`, `migrations.js`, `i18n.js`, `layout.js`, `manifest.json`, `_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`, `tests/*.js`, `README.md`, `CLAUDE.md`, `docs/new-terminal-checklist.md`, 항목 0의 `app/Sources/Core/CommandRenderer.swift`·`app/Tests/CoreTests/`, 그리고 `app/Sources/Core/Request.swift`·`app/Sources/App/HostServer.swift`의 읽기 전용 batch 계약이다. list row 실코퍼스는 canonical `/pull/<number>`·`/issues/<number>` anchor를 가진 현재 GitHub PR/issue list DOM이다.
- 원자성·부분 실패·롤백 경계: shape/cap/content validation은 앱 계약상 전 item preflight라 0 launch이고, launch 단계는 순차·부분 실패이며 실패 뒤 item도 계속한다. extension은 앱 실패 응답을 자동 재시도하지 않는다. transport 오류나 응답 shape 오류 뒤의 사용자가 누르는 재실행은 이미 성공한 session을 중복할 수 있으므로 idempotency를 가장하지 않고, 응답에 기록된 item 결과만 표시한다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

- GitHub 문서/프론트엔드: hashed CSS class와 지연 렌더링·Turbo navigation·row 재배치·native checkbox 권한 상태를 바꿀 수 있어 row anchor와 toolbar 발견을 깨뜨릴 수 있다.
- 사용자: batch 중 checkbox를 바꾸거나 다른 list/detail로 이동할 수 있고, 같은 tab에서 native selection과 extension button을 동시에 조작할 수 있다.
- content script: DOM을 읽고 fallback checkbox를 만들며 selection snapshot을 보낼 수 있지만, message 값은 신뢰할 수 없는 입력으로 취급해야 한다.
- service worker와 다른 extension/options context: 저장된 button 순서·command·locale generation을 바꾸거나 page read와 native send 사이에 비동기 경쟁을 만들 수 있다.
- Terminal Checkout app/native host: 정상 응답으로 overall `success:false`, ordered per-item failures, validation rejection, response-deadline rejection을 반환할 수 있다. extension은 이를 IPC exception과 구별해야 한다.
- 저장소를 공유하는 다른 Chrome 기기: `storage.sync`의 list button key나 version을 바꿀 수 있으며, options page의 기존 optimistic conflict guard가 이 write를 덮어쓰지 않아야 한다.

## 비목표 — 건드리지 않는다

- 앱은 원칙적으로 건드리지 않는다 — 유일한 예외는 항목 0의 `allowedVariables`에 `pr`·`issue` 두 이름을 더하는 것(스펙 #67이 전제한 변수, 실행·검증 semantics 무변경). relay/socket framing, terminal runner, batch 실행 계약은 그대로다.
- extension icon click에서 list selection을 추측하거나 전체 visible rows를 실행하는 경로: icon에는 DOM selection 접근이 없다는 명세상 불가능한 기능이다. 기존 detail/repository icon 동작은 유지한다.
- GitHub REST/GraphQL API로 row를 다시 조회하거나 title·branch를 원격에서 보강하는 것: 번호는 row anchor에서 읽고, list page에는 `{branch}`·`{base}`가 없다.
- 선택 상태를 `storage.sync`나 preset에 저장하는 것: selection은 현재 document의 일시 상태이고 page target이 바뀌면 폐기한다.
- batch cap 8을 늘리거나 병렬 launch·자동 rollback·idempotency protocol을 추가하는 것: 앱의 `batchItemLimit`·순차 실행 계약 밖이다.
- 기존 PR detail·issue detail·repository header button의 command semantics, `command_template` 단건 wire shape, app-provided `{cd}` 조립을 list 기능 때문에 재설계하는 것.
- jsdom이나 synthetic GitHub fixture를 실제 DOM acceptance oracle로 승격하는 것: 현재 테스트 환경은 content script의 실제 GitHub layout을 faithful하게 재현하지 못한다.

## 불변 원칙

- **배치 wire contract는 앱 코드가 정본이다.** `items` 키가 있으면 top-level `command`가 필수이고 `command_template`과 함께 보내지 않는다. `claude_inputs`는 없거나 string array이고, 각 item은 object인 `variables`를 반드시 가져야 한다. extension은 선택된 row마다 `{variables: {repo: <repo>, pr: <number>}}` 또는 `{variables: {repo: <repo>, issue: <number>}}`를 만들며 `owner`, `number`, `branch`, `base`, `main`을 list item에 넣지 않는다.
- **앱의 검증·실행 semantics를 UI 판단으로 복제하지 않는다.** 앱은 최대 8개를 거부하고, 모든 item을 먼저 resolve/sanitize하며, 하나라도 content validation에 실패하면 0개를 launch한다. 성공한 batch도 `items`를 ordered array로 반환하고, partial runtime failure는 overall `success:false`와 item별 `{success,error?}`를 함께 반환한다. 150초 이후의 미실행 item은 정확한 `not launched — response deadline exceeded`를 결과로 가진다.
- **`success:false`는 두 층으로 구별한다.** native transport/shape failure는 service worker가 outer failure로 보내고, 앱의 batch `{success:false, error, items}`는 정상 응답 데이터로 보존해 `sendResponse({success:true, batch:<app response>})` 같은 outer envelope로 전달한다. content script는 outer `success`와 inner `batch.success`를 각각 검사하며 inner false를 done으로 표시하지 않는다.
- **page classification은 `extension/defaults.js` 하나에서만 나온다.** `/owner/repo/pulls/?`와 `/owner/repo/issues/?`를 generic `REPO_TABS`보다 먼저 `pr-list`·`issue-list`로 분류하고 list target의 `number`는 null로 둔다. content script와 service worker는 이 target을 그대로 비교하고, list와 detail·PR list와 issue list 사이의 kind 차이를 navigation change로 취급한다.
- **icon path에는 list batch runner를 넣지 않는다.** service worker icon handler는 list kind를 selection 기반 batch로 처리하지 않고 기존 `isRepoPage` DOM 검증을 거쳐 `repo` command로 폴백한다. 이것이 재분류 전 리스트 페이지에서 실행되던 repository icon 동작을 유지하며, selection을 요구하는 batch action은 content script의 DOM click에서만 시작한다. header의 기존 repository button은 list page에서도 그대로 남긴다.
- **row identity는 DOM index가 아니다.** canonical row anchor의 owner/repo/kind/number를 key로 삼고 title은 text-only display 값으로만 쓴다. selection snapshot·background 재-read·response mapping·redraw rebind 모두 이 key를 사용해 lazy row insertion과 reorder가 다른 row를 실행하지 않게 한다.
- **GitHub native checkbox와 fallback checkbox는 page-level mode를 명시적으로 판정한다.** 현재 수집한 모든 eligible row에 연결된 non-select-all native checkbox를 확인할 수 있을 때만 native mode를 쓰고, complete coverage가 아니면 extension-owned checkbox를 모든 eligible row에 주입한다. 뒤늦게 complete native set이 생기거나 사라지면 owned controls를 제거·재생성하되 key별 checked state를 옮긴다. 부분적으로 섞인 mode를 우연히 허용하지 않는다.
- **선택은 background에서 한 번 더 읽는다.** content message의 selected keys는 비교용 snapshot일 뿐 source가 아니다. service worker는 tab DOM에서 현재 href와 selected row anchor/checkbox를 다시 읽어 clicked target·message snapshot과 일치하는지 검사하고, 그 read 결과로만 item variables를 조립한다. read와 native handoff 사이의 IPC TOCTOU는 기존 단건 gate와 같은 residual로 남기고 자동 재시도로 확대하지 않는다.
- **list-safe visibility는 기존 kind metadata와 합쳐진다.** `BUTTON_KINDS['pr-list'].variables = ['repo','pr']`, `BUTTON_KINDS['issue-list'].variables = ['repo','issue']`로 두고, command와 모든 claude input의 placeholder가 해당 목록 또는 `APP_VARIABLES`에만 속하는지 shared predicate로 판정한다. content와 background가 같은 filtered list를 사용해 button index/fingerprint가 어긋나지 않게 하며, unsafe stored/imported button은 list page에서 숨기되 storage를 조용히 rewrite하지 않는다. app의 missing-variable rejection은 마지막 fail-closed backstop으로 남긴다.
- **list 설정은 detail 설정과 분리한다.** `prListButtons`와 `issueListButtons`를 별도 storage key와 `BUTTON_KINDS` entry로 두면 `{pr}`·`{issue}` 전용 command가 detail page의 `{number}`·`{branch}` command에 섞이지 않고 options/editor·fingerprint·backup이 같은 파생 구조를 사용할 수 있다.
- **새 preset은 두 개를 추가한다.** PR list에는 `{cd} && gh pr checkout {pr} && claude`를, issue list에는 `{cd} && claude`와 `!gh issue view {issue} --comments`를 기본으로 둔다. `gh`가 branch를 locally resolve하므로 list page에 branch/base detection을 추가하지 않는다. preset name key와 face는 기존 관례로 구현한다. 현재 11개/3개 typed/8개 no-input 수치는 13개/4개 typed/9개 no-input으로 갱신한다.
- **version은 reviewed-against 세대다.** 현재 `SETTINGS_VERSION=1`에서 list key와 preset이 추가되면 2로 올리고, `1→2`는 v1에 list command가 없으므로 기존 command를 rewrite하지 않는 review-only registry step으로 등록한다. v1 사용자에게 absent list keys를 current defaults로 보여 주더라도 일반 Save는 version 1을 유지하며, 명시적 review 전에도 기존 규칙대로 편집 상태의 전 소유 key를 Save payload에 쓴다. migration 확인·적용·부분 적용·Reset 같은 명시적 행위 뒤의 Save만 2를 쓴다. `SETTINGS_KEYS`·backup·conflict snapshot은 새 key를 자동 포함한다.
- **모든 저장은 기존 단일 Save 경로를 지킨다.** migration preview/import는 edit state만 채우고 storage를 직접 쓰지 않는다. 새 key 추가가 기존 `storage.sync` optimistic conflict, uid minting, future-version refusal, import merge semantics를 우회하지 않게 한다.
- **result UI는 source와 상태를 섞지 않는다.** batch button 하나의 busy/done/error phase는 기존 button status convention으로 표시하고, 앱 inner response의 ordered `items`를 click 당시 row key에 매핑한다. per-item success/failure badge는 row의 text-only result surface에 두며, response에 `items`가 없으면 per-row 성공/실패를 꾸며내지 않고 overall error만 표시한다. 여러 list button이 존재하면 각 button의 result state가 서로 덮어쓰지 않도록 button identity를 결과 state key에 포함한다.
- **0개와 cap 초과는 명시적 local failure다.** zero selected는 request를 만들지 않고 button을 error phase와 localized accessible diagnostic으로 바꾼다. 8개 초과 selection은 허용하되 button click에서 localized cap error로 거부하고 ninth selection을 자동으로 되돌리지 않는다. app의 cap은 backstop으로 유지하며, 어느 경우에도 “현재 보이는 전체”를 선택하지 않는다.
- **로케일과 사용자 입력을 분리한다.** 새 UI 문구·preset name·aria/title은 다섯 `_locales`의 message key로 만들고 user-owned row title/command/number는 `textContent`와 command variable로만 다룬다. `_locales` live bytes가 정본이고 `tools/check-locales.js` baseline hash와 `tests/i18n.test.js`의 attribute-site oracle을 의도적으로 갱신한다.
- **테스트는 pure seam을 먼저 세운다.** 구현 전 root `tests/`에 red를 만들고 `node --test`로 확인한 뒤 구현한다. DOM selector 자체를 가짜 fixture의 green으로 주장하지 않고, pure row-key/selection/mode/request/result/migration 함수와 source-level call-site guard를 gate로 삼으며 실제 GitHub list DOM·권한 조합·navigation은 hands-on checklist의 잔여로 기록한다.
- **실기기 DOM 확인은 hands-on 잔여로 둔다.** 권한별 native checkbox, filter/toolbar structural anchor, 지연 렌더링과 DOM 교체는 `docs/new-terminal-checklist.md`에 기록하고 종결 보고에서 사용자 실기기 확인으로 승계한다. 이 설계 루프의 gate로 삼지 않는다.

## 배치 점검 (0라운드)

모드: ultrafast

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | exit 1, 미매치. 현재 작업 트리는 `/Users/choongjaelee/Codes/...`이고 `.claude/worktrees/probe`는 이 checkout 안의 무시 대상 경로가 아니다 |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 리포 파일/오버레이에는 선언 없음; 현재 첫 보고의 `git log --oneline -2`는 `1f3ef87`와 `42ba068`을 보였다 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-batch-list-pages-work` · `batch-list-pages` · `1f3ef872d505969c834b777369c1b0dea06a4f60` |
| 리포 오버레이 `.claude/drive-agent-loop.md` — 있으면 경로, 없으면 이번 초안과 함께 작성 | 있음: `.claude/drive-agent-loop.md`; extension gate는 `node --test`, Swift gate는 driver 실행, local asset env는 None으로 선언돼 있다 |
| cmux 패널 (점검 블록 `cmux:` 신호가 켜졌을 때만, 아니면 N/A) — `cmux markdown open <작업 트리 계획 파일 절대경로>` → pane id. 계획 파일 첫 승격 전에 채운다 | `cmux markdown open …/docs/plans/batch-list-pages.md` → surface:37 pane:33 (드라이버 실행) |
| 트리마다 의존성 동기화 (기준·작업) | 별도 JS dependency lockfile과 `Package.resolved`가 없고 현재 tree는 `git status` clean인 기준 commit에서 시작했다 |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 없음; overlay가 local asset env `None`으로 선언한다 |
| 증분 리뷰 소요(분) — 첫 세 번 | 해당 없음; R0 초안 전이며 리뷰 0회 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 0 | 앱 renderer whitelist에 `pr`·`issue`를 추가하고 기존 render test 파일에 red→green 테스트를 추가한다 | app variable contract | (a) `{pr}`/`{issue}` 렌더가 `unknownVariable`로 거부됨(red 재현: `renderCommand(template: "echo {pr}", variables: ["pr": "7"])` → 기준 트리 throw) | `app/Sources/Core/CommandRenderer.swift`, `app/Tests/CoreTests/` (기존 render test 파일) | — | verified | 상태 전이: `wip` → `claimed` → `verified`; red 단계에서 whitelist 수정 전 같은 호출을 실패 기대에 고정했고, `testRenderPullRequestVariable`, `testRenderIssueVariable`가 최종 치환 기대를 둔다. diff: `allowedVariables`에 `pr`·`issue` 두 이름 추가 및 두 렌더 테스트 16줄 추가; 전수 소탕 표에 renderer→request→test/e2e/docs 흐름과 미변경 사유 갱신; verified — driver reran the full gate: exit 0, 589/0; toggle re-applied red on exactly the two new tests. | Swift gate는 driver 실행; 실행·검증 semantics는 그대로 |
| 1 | `pageTypeOf`·`pageTargetOf`에 `pr-list`/`issue-list`를 추가하고 list target을 content/background 양쪽에 연결하며, icon click은 list kind에서 기존 repo 실행으로 폴백한다 | page classification | (a) `/pulls`와 `/issues`가 현재 `repo`로 판정됨 (b) 재분류 후 list kind를 repo 실행으로 폴백하지 않으면 기존 icon repository command가 사라짐 | `extension/defaults.js`, `extension/content.js`, `extension/background.js`, `tests/buttons.test.js`, `tests/list-pages.test.js` | — | todo | `rg -n "REPO_TABS|function pageTypeOf|function pageTargetOf|RUN_BY_KIND|onClicked" extension/defaults.js extension/background.js` → list path와 icon dispatch가 현재 repository/detail만 다룸; `node --test` → exit 0, 222 pass (list coverage 없음) | — |
| 2 | list-safe kind metadata와 PR/issue list preset·별도 storage section·options editor를 만들고 `SETTINGS_VERSION` 1→2 review-only migration을 등록한다 | settings and migration | (a) `{pr}`/`{issue}`와 list-only preset namespace가 없음 (b) 새 storage shape를 version/backup/conflict/migration machinery에 등록할 경로가 없음 | `extension/defaults.js`, `extension/options.html`, `extension/options.js`, `extension/migrations.js`, `extension/_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`, `tools/check-locales.js`, `tests/migration.test.js`, `tests/i18n.test.js` | 0·1의 app whitelist·kind/storage 계약 | todo | `nl -ba extension/defaults.js | sed -n '158,200p'` → 세 kind와 세 key만 존재; `nl -ba extension/options.js | sed -n '8,12p;636,729p'` → sections와 Save payload가 현재 kind만 파생; `nl -ba extension/migrations.js | sed -n '43,94p'` → registry가 0→1만 가짐 | — |
| 3 | list row anchor에서 stable key·number·title을 수집하고, native checkbox complete coverage와 extension-owned fallback을 감지·전환하며 selection을 key로 보존한다 | row selection | (a) list row checkbox를 읽거나 주입하는 code가 없음 (b) lazy redraw에서 DOM index로 selection을 보존할 기반이 없음 (c) 같은 target 안에서 DOM 교체(페이지네이션·필터·turbo 갱신)가 일어나면 fallback checkbox와 선택이 사라진다 — 선택은 현재 문서의 일시 상태로 자연 폐기가 맞고(비목표와 일관), 재주입 트리거(list 컨테이너 관찰 또는 1s 폴링 백스톱)와 '사라진 행이 스냅샷에 남아 background 재검증에서 전체 거부되는' 경로의 오류 문구를 항목 5의 UI 계약과 함께 확정한다 | `extension/content.js`, `extension/defaults.js`, `tests/list-pages.test.js`, `docs/new-terminal-checklist.md` | 1의 list target·shared row key | todo | `rg -n "checkbox|list|pull/|issues/|MutationObserver|removeInsertedButtons" extension/content.js extension/defaults.js` → existing content path에 row selection implementation 없음; `docs/context/options-page-reordering.md` → redraw 뒤 index 보존은 안전하지 않음 | — |
| 4 | selected snapshot을 background에서 재검증하고 앱의 exact batch envelope을 생성·전송하며 outer transport result와 inner app result를 분리한다 | batch transport | (a) background가 단건 `command_template`만 전송함 (b) native `{success:false}`를 per-item payload로 보존하지 않으면 batch failure가 content에서 성공으로 오인될 수 있음 | `extension/content.js`, `extension/background.js`, `extension/defaults.js`, `tests/list-pages.test.js`, `tests/buttons.test.js` | 0·1·2·3의 target, visible button, selected row 계약 | todo | `nl -ba extension/background.js | sed -n '234,275p;382,433p'` → `nativeOutcome` false throw와 단건 listener만 존재; `nl -ba app/Sources/Core/Request.swift | sed -n '81,124p;280,350p'` → `command`/`items` shape와 validation/ordered result이 확정됨 | — |
| 5 | list toolbar/filter structural anchor에 batch buttons를 붙이고 기존 button phase와 row별 ordered badge를 함께 그리며 zero/cap/malformed response를 명시적으로 표면화한다 | results UI | (a) list page에 toolbar button attach 지점이 없음 (b) overall/per-row result와 empty selection 오류 UI가 없음 | `extension/content.js`, `extension/_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`, `tests/list-pages.test.js`, `tests/i18n.test.js`, `docs/new-terminal-checklist.md` | 0·3·4의 row/result identity와 response envelope | todo | `nl -ba extension/content.js | sed -n '276,345p;347,381p'` → detail/repository anchor만 있고 list toolbar/result badge가 없음; `nl -ba extension/i18n.js | sed -n '1,134p'` → 새 user-facing strings는 locale `tr` 경로를 타야 함 | — |
| 6 | pure/source oracle을 red→green 순서로 추가해 page classification·list-safe filter·selection mode·wire/result mapping·migration을 고정하고 DOM은 수기 범위로 제한한다 | tests | (a) 현재 222개 테스트가 list page를 repository로 고정하고 있음 (b) 실제 GitHub list DOM을 검증하는 content harness가 없음 | `tests/list-pages.test.js` (신규), `tests/buttons.test.js`, `tests/migration.test.js`, `tests/i18n.test.js`, `tests/layout.test.js` (필요 시), `extension/defaults.js`, `extension/content.js`, `extension/background.js` | 0∼5 | todo | `node --test` → exit 0, `tests 222`, `pass 222`, `fail 0`; `docs/context/testing.md` → DOM/drag의 faithful harness 한계와 pure/source gate 원칙 | — |
| 7 | README 변수 표·list 사용/제한·permission 수치와 `CLAUDE.md`의 durable preset count, new-terminal hands-on checklist를 구현 결과에 맞게 갱신한다 | docs and localization | (a) 현재 문서가 list page와 `{pr}`/`{issue}`를 설명하지 않음 (b) 두 preset 추가 시 11/3/8 수치가 stale해짐 | `README.md`, `CLAUDE.md`, `docs/new-terminal-checklist.md`, `extension/_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`, `tools/check-locales.js`, `tests/i18n.test.js` | 2·5의 확정 preset/UI 문구 | todo | `rg -n "11|three|3|8|claude input|Variables|Development|batch fan-out" README.md CLAUDE.md docs/new-terminal-checklist.md` → 기존 수치와 단건/app batch 설명 확인; `tools/check-locales.js` → live catalogue baseline hash가 고정돼 있음 | — |

- 항목 하나는 승인 후 승격 하나에 들어갈 크기로 유지한다. 순서는 0 → 1 → 2 → 3 → 4 → 5 → 6 → 7이며, 0은 list preset이 의존하는 앱 변수 계약의 유일한 예외이고 1·2는 계약이 확정되면 병합 가능한 별도 부류이며 4·5는 각자 선행 항목의 identity를 전제한다.
- `의존`은 page kind/storage/row key/response envelope처럼 다른 항목이 먼저 고정해야 하는 계약을 가리킨다. 어떤 항목의 설계가 바뀌면 뒤 항목의 test oracle과 file set을 다시 낸 뒤 리뷰에 들어간다.
- R0에서는 모두 `todo`이며 구현자가 스스로 올릴 수 있는 상태 상한은 `claimed`다. `verified`·`cleared`·`agreed`·`dropped`는 드라이버 판정 뒤에만 기록한다.
- 각 승격의 근거는 `node --test` exit와 실행 count, pure test 이름, 재현 가능한 `rg`/`nl` 명령으로 기록한다. 앱 Swift gate는 driver 결과를 별도로 기록하고 이 계획의 sandbox 측정으로 덮어쓰지 않는다.

## 결정 원장

R0 설계 리뷰에서 D1∼D3가 발행됐다. 아래 결정은 계획의 확정 계약이며, 구현자는 이 원장과 항목 0부터의 순서를 기준으로 승격한다.

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 드라이버 | `{pr}`/`{issue}`가 앱 whitelist에 없어 스펙의 리스트 프리셋이 전면 거부됨 | 앱 `allowedVariables`에 두 이름 추가로 해소, 별도 이슈로 빼지 않음 — 스펙 구현의 필요 조건이고 이름 2개는 semantics 무변경 | `CommandRenderer.swift:32-34`, R0 설계 리뷰 | Swift gate는 driver 실행 |
| D2 | 드라이버 | 아이콘 클릭의 리스트 페이지 처리 | repo 커맨드 폴백으로 기존 동작 보존 — 스펙의 exclude는 배치 실행 부재를 뜻함 | `background.js:388-407`, R0 설계 리뷰 | 없음 |
| D3 | 드라이버 | R0 열린 질문 8건 일괄 처분 | 아래 각 결정: Q1 분리 채택 — `prListButtons`·`issueListButtons` 별도 storage key·BUTTON_KINDS entry; Q2 review-only 1→2 채택 — 기존 의미론 유지(ordinary Save는 version을 움직이지 않고, absent list key는 명시적 review 전 payload에서 보존하지 않는다 — 기존 키와 같은 규칙: Save는 편집 상태의 전 소유 key를 쓴다); Q3 PR-list는 `{cd} && gh pr checkout {pr} && claude`, issue-list는 `{cd} && claude` + claudeInputs `['!gh issue view {issue} --comments']`로 확정하며 이름 key·face는 기존 관례로 구현; Q4 complete native coverage일 때만 native, 아니면 전 행 owned fallback, key별 checked state 이전; Q5 선택은 8개 초과를 허용하되 button click에서 localized cap 오류로 거부하고 ninth를 되돌리지 않으며 app cap은 backstop으로 유지; Q6 button identity로 badge 분리; Q7 실기기 GitHub DOM은 `docs/new-terminal-checklist.md` hands-on 항목으로 기록하고 종결 보고에서 사용자 실기기 확인으로 승계하며 이 루프의 gate로 삼지 않음; Q8 README·CLAUDE.md 수치를 13/4/9로 갱신 승인 | R0 설계 리뷰 | Q1∼Q8 처분 완료 |

## 전수 소탕 표

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `extension/defaults.js`의 page type·target·BUTTON_KINDS·SETTINGS_KEYS·preset 목록 | 구멍(항목 1, 2) | `defaults.js:158-226,268-311` — 현재 list kind·list-safe variables·list storage key가 없음 |
| `extension/content.js`의 insert·click·navigation·observer/polling 경로 | 구멍(항목 3, 4, 5) | `content.js:347-442` — detail/repository button 수명주기만 있고 row selection·list toolbar·batch response rendering이 없음 |
| `extension/background.js`의 icon·message·native send·final gate | 구멍(항목 1, 4) | `background.js:234-275,382-433` — 단건 `command_template`와 false-as-error path만 있음; list batch는 제외하되 icon의 기존 repo command 폴백을 보존해야 함 |
| `extension/options.html`·`options.js`의 section·load/save/export/import/review | 구멍(항목 2) | `options.js:8-12,636-729,1019-1137` — section 목록과 storage payload가 세 kind에 고정돼 있음 |
| `extension/migrations.js`·`tests/migration.test.js`·`tests/fixtures/presets-v0.json` | 구멍(항목 2, 6) | `migrations.js:43-94` 및 `migration.test.js:84-108` — registry는 0→1이고 review-only 1→2 계약이 없음; v0 fixture는 역사 보존용이라 list preset에 임의 pair를 추가하지 않음 |
| `_locales`·`tools/check-locales.js`·`tests/i18n.test.js` | 구멍(항목 2, 5, 7) | 다섯 live catalogue가 각 125 keys이고 baseline hashes가 고정돼 있어 새 preset/UI 문구는 다섯 파일·hash·attribute oracle을 함께 검토해야 함 |
| `extension/manifest.json`·`extension/i18n.js`·`extension/layout.js` | 안전(검토) | `manifest.json:20-30`의 기존 content match/script order가 새 code를 기존 파일에 두는 한 충분하고, `i18n.js`의 `tr`/`nativeOutcome`과 `layout.js`의 순수 layout helper는 계약을 유지함; module 추출을 승인하면 별도 항목으로 승격 |
| `tests/buttons.test.js`·`tests/list-pages.test.js`·root `node --test` | 구멍(항목 6) | 현재 `node --test`는 exit 0, 222 pass지만 `buttons.test.js`가 `/issues`를 `repo`로 기대하고 list DOM harness는 없음 |
| `README.md` 변수 표·Development·permission 문구, `CLAUDE.md`, `docs/new-terminal-checklist.md` | 구멍(항목 7) | `README.md:119-175,229-247`, `CLAUDE.md`의 shipped preset 수, checklist batch fan-out 행에 list selection·변수·결과 UI가 없음. README 변수 표의 `{pr}`·`{issue}` 추가는 **항목 7로 이월** |
| `app/Sources/Core/CommandRenderer.swift`의 request variable source of truth | 완료(항목 0) | `CommandRenderer.swift:32-34`의 `allowedVariables`에 기존 7개와 `{pr}`·`{issue}`를 함께 두고, `:57`의 placeholder regex가 이름을 찾아 `:64-99`의 `renderCommand`가 key whitelist·value sanitize·치환 순서로 흘린다. 항목 0 diff는 두 이름만 추가했으며 실행·검증 semantics는 변경하지 않음 |
| `app/Sources/Core/Request.swift`·`app/Sources/Core/BaseDirectory.swift`의 변수 흐름 | 안전(항목 0에서 재확인) | `Request.swift:34-65`가 request `variables`를 문자열 맵으로 만들고 `:130-158`이 command와 claude input 모두 같은 renderer를 호출하며 `:208-226`은 app-only `{cd}`를 별도 조립한다. `BaseDirectory.swift:16-17`의 `repoEntryVariable = "cd"`는 extension의 `APP_VARIABLES`와 동기화되는 별도 값이며, `{pr}`·`{issue}`를 특수 취급하지 않음. batch parsing과 HostServer 실행 semantics는 건드리지 않음 |
| 앱 소스 주석의 변수 전제 | 검토 완료(항목 0) | `CommandRenderer.swift:68-80`, `Request.swift:201-207`, `BaseDirectory.swift:5,47`, `HostServer.swift:197`, `Localization.swift:231`, `ToolChecker.swift:12`, `CmuxControl.swift:354`, `TerminalRunner.swift:524`, `WarpControl.swift:103`, `SetupWindowController.swift:731`은 `{repo}`·`{cd}` 및 기존 variable whitelist/앱 조립 경계를 설명한다. 항목 0은 실행 경로만 고치므로 주석은 수정하지 않고, 새 사용자-facing 변수 설명은 항목 7로 이월 |
| `app/Tests/CoreTests/CoreTests.swift`의 렌더·요청 fixture와 앱 변수 이름 상수 | 완료(항목 0) | `CoreTests.swift:16-40`의 `testRenderAllVariables`, `testRenderPullRequestVariable`, `testRenderIssueVariable`가 렌더 기대를 고정하고, `:254-350,437-560`의 request fixture가 같은 renderer 흐름을 사용한다. `:4748-4792`의 `repoEntryVariable`·`APP_VARIABLES` 교차 검증은 `{cd}`만 다루며 별도 request whitelist 상수는 없음; 새 `{pr}`·`{issue}` 테스트 두 건 외에는 변경하지 않음 |
| `app/Tests/CoreTests/BatchProtocolTests.swift`·`app/Tests/AppTests/HostProtocolTests.swift`의 변수 fixture | 안전(항목 0) | `BatchProtocolTests.swift:17-289`와 `HostProtocolTests.swift:8,595,746,985`는 `{repo}`·`{branch}`·`{main}`·`{number}` fixture로 request/batch response를 검증한다. list의 유효한 `{pr}`·`{issue}` wire case는 후속 batch 항목의 몫이며, 항목 0에서는 protocol fixture나 검증 semantics를 바꾸지 않음 |
| `app/e2e.sh`의 변수 사용 후보 | 후보 검토 완료(항목 0에서 변경 없음) | `app/e2e.sh:103-159`는 `{repo}`·`{main}`·`{number}`·`{owner}`·`{cd}`와 미제공 `{nope}`를 실패 경로 payload에만 넣고, 성공적인 `{pr}`·`{issue}` 실행은 다루지 않는다. 이 스크립트는 빌드된 app의 relay/socket error-path gate이므로 renderer whitelist 두 이름 추가만으로 payload·실행 semantics를 바꾸지 않으며, list valid-path coverage가 필요하면 후속 batch 항목에서 별도 결정함 |
| `extension/defaults.js`의 upstream variable 목록과 page metadata | 구멍(항목 1, 2) | `defaults.js:152-176`의 `APP_VARIABLES = ['cd']`, `BUTTON_KINDS[*].variables`, preset placeholder가 extension이 실제로 보낼 이름을 결정한다. `{pr}`·`{issue}` list metadata와 preset 추가는 항목 1·2의 몫이며, 앱 whitelist만 먼저 여는 항목 0에서는 수정하지 않음 |
| `docs/plans/base-dir-fallback.md`·`docs/plans/settings-migration.md`의 역사 문서 | 안전(역사 보존) | `base-dir-fallback.md:34,46,69,73-74,77` 및 `settings-migration.md:14,23,43,78,85`의 `{cd}`·`{repo}`·`allowedVariables` 언급은 이미 결정된 설계와 마이그레이션 기록이지 runtime 값의 source가 아니다. 항목 0에서 historical plan을 현재 `{pr}`·`{issue}` 문서로 덮어쓰지 않음 |
| `extension/test/` | 해당 없음 | 이 checkout에는 경로가 없고, 실제 JS gate corpus는 `tests/`이다. 없는 디렉터리를 만들거나 테스트를 옮기는 것은 이번 계획의 범위가 아니다 |

## 라운드 로그

라운드는 사용자 승인 전 R0 설계 초안이다. 이 파일은 계획 커밋으로만 저장되며 구현 커밋은 없다.

### R0

#### 설계 리뷰 — 계획 초안 · 승격 없음 · 리뷰 완료 · 왕복 1 · 원문 없음

- 반박: R0-1은 `{pr}`·`{issue}` 앱 whitelist 결락, R0-2는 배치 점검 모드 표기, R0-3은 list repository button과 icon 폴백, R0-4는 동일 target의 DOM 교체 경로를 지적했다.
- 처리: D1에서 항목 0과 Swift driver gate를 추가하고 항목 2·4·5의 의존을 갱신했다. D2에서 repo button은 list page에도 남기고 icon은 `isRepoPage` 검증을 포함한 repo 실행으로 폴백하도록 확정했다. D3에서 별도 list key·두 preset·review-only migration·all-or-none checkbox·cap 오류·button별 badge·hands-on 범위·13/4/9 문서 수치를 확정했으며, 항목 3의 페이지네이션·필터·Turbo 재주입과 stale snapshot 오류 경로를 항목 5와 묶었다.
- 실측: `node --test` → exit 0; `tests 222`, `pass 222`, `fail 0`, `skipped 0`; `cd app && swift test`는 실행하지 않았고 driver가 실행한다.
- 판정: 드라이버 설계 리뷰 — 차단 1(앱 변수 whitelist 결락), 정정 3(모드 표기·repo 버튼/아이콘 폴백 확정·페이지네이션 세부), 열린 질문 8건 전부 처분. 이 계획으로 시작하는 데 합의한다 — 항목 0부터.

### R1

#### 리뷰 없음 — 승격 없음 · 원문 없음

- 반박: R0 승인 전이므로 없음.
- 수정: 없음.
- 실측: 없음.
- 판정: 사용자 설계 리뷰 대기.

## 열린 질문

- 없음 — R0 열린 질문 Q1∼Q8은 D3에서 모두 처분되었고, 실기기 DOM 확인은 열린 설계 질문이 아니라 `docs/new-terminal-checklist.md`의 종결 확인 항목으로 승계한다.
