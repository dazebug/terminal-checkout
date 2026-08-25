# claude-input-reorder

- 대상: `extension/` (Chrome extension options page) in `dazebug/terminal-checkout`
- 시작 커밋: `fa9fb81`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/claude-input-reorder-review` (`worktree-claude-input-reorder-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-claude-input-reorder-work` (`claude-input-reorder-work`)
- 현재: R0 설계 리뷰 반영 · write_codex `01a038d5-8398-78f0-83a5-4c3ef01bce51` · 마지막 승격 없음 · 리뷰 중 없음 (최종) · 게이트 혼합 — Node 217/0, 로케일 검사 그린, Swift는 샌드박스 환경 실패
- 최근 검증자 판정: R0 방향 승인, R0-1∼R0-8 반영 후 계획만 커밋 · 원문 없음

## 배경 — 확인한 원천

- 관련 issue·PR·설계 문서: 없음. 사용자가 `gh issue list --state all`의 30개 이슈를 확인했으며 claude 입력 순서 변경과 관련된 항목은 없다고 했다. 따라서 영구 원천 링크를 꾸며내지 않는다.
- 사용자 요청: “크롬 확장 claude 입력줄도 ⠿ 로 순서 바꾸는 UI를 추가해주세요.” 현재 옵션 페이지에는 카드 순서용 손잡이·↑↓만 있고 카드 안 `claudeInputs` 행에는 순서 변경 경로가 없다.
- `CLAUDE.md`와 `extension/defaults.js`: `claudeInputs`의 배열 순서는 앱이 입력을 전달하는 순서이고, 연속한 `!` 입력은 하나의 `;` 셸 라인으로 합쳐질 수 있으므로 순서는 기능적 데이터다. 이 계획은 그 순서를 바꾸는 편집 경로만 추가한다.

## 목표

- 한 카드의 `claudeInputs`가 두 개 이상이면 각 행에 `⠿` 손잡이를 보여 주고, 손잡이 드래그와 손잡이에 포커스를 둔 ↑↓ 키로 같은 카드 안의 행 순서를 바꾼다.
- 화면에 보이는 행 순서, `state.buttons[kind][cardIndex].claudeInputs`의 순서, [Save] 뒤 저장되는 `claudeInputs`의 순서가 일치한다.
- 행 드래그가 카드 드래그나 다른 카드의 입력 목록을 건드리지 않으며, 카드의 기존 순서 변경·입력 편집·최대 개수 제한을 유지한다.
- ↑↓로 옮긴 뒤에는 이동한 행의 새 손잡이에 포커스를 복원하고, 다섯 로케일에서 새 접근성 이름과 툴팁이 정상적으로 표시된다. 마우스 drop 경로는 포커스를 조작하지 않는다.

## 완료의 정의

- 반드시 재현해 막아야 할 실패: 한 카드의 `claudeInputs`를 `['!first', '!second']`로 만든 뒤 첫 행을 아래로 끌거나 첫 행 손잡이에서 `ArrowDown`을 눌렀을 때, 현재는 행 순서를 바꿀 UI가 없어 `['!second', '!first']`를 만들 수 없다.
- acceptance oracle: 같은 카드에서 이동 후 행의 `data-ci`와 화면의 `⏎N` 표기가 새 배열 순서와 맞고, [Save]가 `toStoredButton`의 순서 보존 경로로 기록하며, 다른 카드 위에 놓은 드래그는 어느 배열도 바꾸지 않는다. 위·아래 끝의 키는 스크롤만 막고 배열·포커스를 바꾸지 않는다.
- 코퍼스 범위: `extension/options.js`의 세 `SECTIONS`(`pr`, `issue`, `repo`)와 `extension/defaults.js`의 11개 shipped preset(그중 3개가 비어 있지 않은 `claudeInputs`를 가진다), `MAX_CLAUDE_INPUTS = 5`; 수기 검증은 행 수 0·1·2·5를 각각 포함한다.
- 원자성·부분 실패·롤백 경계: 이동은 `edit` 한 번으로 edit state에만 적용되고 저장소·터미널·앱을 직접 건드리지 않는다. `state.loaded`가 아니거나 이동이 제자리면 변이·재렌더·포커스 복원을 하지 않으며, 카드 밖·다른 카드 드롭은 정리만 하고 이동하지 않는다. 저장 실패 시의 충돌·재시도는 기존 [Save] 경계가 담당하므로 이 기능에 별도 롤백은 N/A다.

## 비목표 — 건드리지 않는다

- **카드 사이의 `claudeInputs` 이동**: 한 행은 한 버튼의 입력 목록에 속한다. 다른 카드로 옮기면 두 버튼의 실행 payload를 동시에 바꾸고 목적지의 `MAX_CLAUDE_INPUTS` 판정까지 필요해지므로 이번 요청의 범위를 넘긴다.
- **`MAX_CLAUDE_INPUTS`, 저장 스키마, migration, preset의 내용 변경**: 재배열은 길이와 값의 정규화 없이 배열 순서만 바꾼다.
- **앱의 claude 전달·`!` 병합·터미널 권한·TCC 경계 변경**: 새로운 실행 경로가 아니라 기존 payload의 편집 순서만 바꾼다.
- **카드 자체의 순서 의미나 override 행의 드래그**: 기존 카드 reorder는 유지하고, override 표에는 이번 손잡이를 추가하지 않는다.
- **DOM 테스트를 위해 가짜 브라우저 하네스를 새로 도입하거나 정적 정규식으로 실제 드래그 성공을 주장하는 것**: `options.js`의 DOM 이벤트와 native drop은 현재 Node 단위 테스트 대상이 아니며 브라우저 검증으로 남긴다.
- **새 터미널 지원 체크리스트나 `app/` 코드 변경**: 실행 경로·터미널 분기가 추가되지 않으므로 해당 체크리스트의 항목을 늘리지 않는다.

## 불변 원칙

- `claudeInputs`의 순서는 의미 있는 입력 순서다. 재배열 경로는 값을 합치거나 정렬하거나 `trim`하거나 빈 행을 제거하지 않고, [Save] 시 기존 `toStoredButton`이 하는 순서 보존만 따른다.
- 행 드래그는 시작한 `kind`와 카드 하나에 고정된다. 같은 섹션의 다른 카드와 다른 섹션은 drop target이 아니며, 행 이동은 목록 길이를 바꾸지 않으므로 목적지 `MAX_CLAUDE_INPUTS` 검사를 새로 만들지 않는다.
- 행 drag의 drop zone은 시작 카드의 `.claude-rows` container 하나뿐이다. `dragover`의 `preventDefault`와 target index 계산은 그 container 안에서만 수행하며, 카드 header·command textarea·카드의 나머지 영역·다른 카드에서는 Chrome이 no-drop을 표시하고 행을 옮기지 않는다.
- 카드와 행은 하나의 `drag` 상태 안에서 `type: 'button'`과 `type: 'claude'`로 구분한다. 행 손잡이는 카드의 `.drag-handle`과 다른 `.ci-drag-handle`을 써서 기존 `mousedown` 경로가 카드를 draggable로 만들지 않게 한다. 카드의 `card.draggable` 확인은 유지하고, 카드의 `dragover`·`drop`·`dragend`는 버튼 타입만, 행의 같은 이벤트는 claude 타입과 같은 카드만 처리한다.
- `moveButton`의 본문은 요소의 필드를 보지 않고 복사·splice의 index arithmetic만 한다. 이름을 `moveItem`으로 일반화해 카드 배열과 문자열 `claudeInputs` 배열 양쪽에서 같은 “원본 기준 insert-before, 뒤로 이동할 때 한 칸 보정” 계약과 원본 불변성을 사용한다. `reorderButtons`는 카드 state/render/focus를 묶는 래퍼로 남기고, `reorderClaudeInputs`는 중첩된 카드 state 경로와 행 focus를 묶는 별도 래퍼로 두되 둘 다 이동 산술을 복제하지 않는다.
- `dropIndex`는 카드라는 의미를 갖지 않는 위치 계산으로 일반화하고, `markDropTarget`·`clearDropMarks`·`endDrag`는 item selector 또는 item collection을 받아 그 범위만 처리한다. 섹션 안에 `.claude-row`가 중첩되어 있으므로 카드 정리가 행 표시를 우연히 지우거나 행 dragend가 카드 상태를 끝내지 않도록 selector와 drag type을 함께 제한한다.
- 기존 카드처럼 `dataTransfer`에는 명령·행 값·인덱스를 싣지 않는다. DOM과 타입이 같은 문서 안에서 상태를 확인하고, 외부에 붙여 넣을 수 있는 문자열 payload를 만들지 않는다.
- 행 손잡이는 `claudeInputs.length > 1`일 때만 렌더링한다. 0개와 1개에는 순서 변경 affordance가 없고, 두 개 이상일 때 끝에서의 `ArrowUp`·`ArrowDown`은 `preventDefault`만 하고 목록·포커스를 그대로 둔다.
- `renderButtons`가 섹션 전체 `innerHTML`을 비우므로 이동 전 DOM 노드를 다시 포커스하지 않는다. ↑↓ 이동 후에는 반환된 새 행 인덱스로 새 `.ci-drag-handle`을 조회해 포커스를 복원한다. 행과 카드의 두 mouse-drop 경로는 포커스를 조작하지 않으며, 기존 card drop의 포커스 손실은 선행 동작이고 이번 범위 밖이다.
- `.claude-row`에는 `position: relative`를 둬 `::before`·`::after` drop indicator가 카드가 아니라 행을 기준으로 그려지게 한다. indicator offset은 `margin-bottom: 7px`인 행 gap의 중간에 오도록 `top: -4px`·`bottom: -4px`를 사용하며, 이는 12px gap에 `-7px`를 쓰는 카드 규칙에 대응한다.
- 모든 이동은 `edit`를 통해 `touch`의 loaded 선행 검사를 통과한 뒤에만 상태를 바꾼다. 이벤트를 직접 dispatch하거나 페이지가 아직 load 중이어도 guard 앞에 변이가 놓이지 않는다.
- 새 `aria-label`·`title`은 `options.js`의 `t` 호출로만 만들고, 새 `ext.claudeInput.reorder.aria`는 `$ARG1$`와 sibling `placeholders` block으로 1-based row number를 받으며 en·ja·ko·zh_CN·zh_TW에 모두 둔다. `ext.reorder.tooltip`은 카드와 행이 공유하도록 기존 tooltip key를 rename한 것이므로 각 locale의 기존 value를 verbatim copy한다. 다섯 파일의 byte pin은 구조 변경과 함께 `tools/check-locales.js`의 `CATALOGUE_BASELINE_HASHES.locales`에서 갱신한다.
- Node 테스트는 종료 상태와 실행 수로 판정하고, `node --test`·`node tools/check-locales.js`·`cd app && swift test`를 최종 게이트로 다시 실행한다. Swift가 이 샌드박스처럼 환경 권한 때문에 매니페스트 전에 실패하면 코드 회귀로 판정하지 않고 원문을 그대로 보고한다.

## 배치 점검 (0라운드)

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | 드라이버가 메인 저장소에서 사전 측정 — ignored; `$(git rev-parse --git-common-dir)/info/exclude`에 `.claude/worktrees/`가 있음 |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 드라이버 설정은 이 트리 밖이라 미확인; 첫 보고의 HEAD는 `fa9fb81`로 기준·작업 트리와 일치 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | 완료 — `/Users/choongjaelee/Codes/terminal-checkout-claude-input-reorder-work` · `claude-input-reorder-work` · `fa9fb81` |
| 트리마다 `uv sync` (기준·작업) | N/A — `pyproject.toml`·`uv.lock` 등 uv 입력 파일이 없음 |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 이 계획에서 참조한 env 자산 없음; 개인 설정과 템플릿은 지정된 절대 경로에서 읽음 |
| 증분 리뷰 소요(분) — 첫 세 번 | 아직 측정하지 않음 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | `moveButton`을 `moveItem`으로 일반화하고 카드 이동의 기존 index 보정·원본 불변성 tests를 유지하면서 문자열 `claudeInputs`의 앞·뒤 이동과 원본 불변성 cases를 같은 promotion에 추가한다 | 순수 자료구조 계약 | — | `extension/defaults.js`, `tests/buttons.test.js` | — | claimed | red: `node --test` exit 1, 218/217/1, 새 test의 `ReferenceError: moveItem is not defined`; green: exit 0, 218/218/0 | — |
| 2 | 0·1개에는 숨기고 2개 이상 행에만 `.ci-drag-handle`, 행 번호별 접근성 이름·툴팁, drop 표시선과 handle layout을 렌더링한다. `.claude-row`를 positioned container로 만들고 기존 tooltip key를 `ext.reorder.tooltip`으로 rename해 공유하며 새 aria key 하나를 다섯 catalogue에 추가한다. exact source-site·argument count와 live byte pin을 갱신한다 | UI·로컬라이제이션 | — | `extension/options.js`, `extension/options.html`, `extension/i18n.js`(검토; 로직 변경 없음), `extension/_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`, `tests/i18n.test.js`, `tools/check-locales.js` | — | claimed | red: `node --test` exit 1, 218/214/4 with missing-key and exact-site failures; green: `node --test` exit 0, 218/218/0 and `node tools/check-locales.js` exit 0, all 5 names/bindings match | — |
| 3 | 카드와 행의 native drag listener를 discriminated `drag` 상태와 selector-scoped `dropIndex`·`markDropTarget`·`clearDropMarks`·`endDrag`로 연결한다. 카드 listener는 claude drag를 무시하고 행 listener는 시작 카드의 `.claude-rows` 안에서만 `preventDefault`하며, card/row의 mousedown·dragstart·dragend가 서로의 state를 정리하지 않게 한다 | DOM drag 상호작용 | — | `extension/options.js`, `extension/options.html` | 1, 2 | todo | `nl -ba extension/options.js \| sed -n '1300,1406p'` → section delegation, kind-only guard, 무조건 card `dragend`; 중첩 전용 타입 판정이 없음 | — |
| 4 | 행의 ↑↓ 경계 동작, 같은 카드 전용 `reorderClaudeInputs`, `edit` 선행, 이동 후 새 행 손잡이 focus를 구현한다. 행과 카드의 mouse-drop path는 focus를 조작하지 않고, 기존 card drop의 focus loss는 선행 동작으로 기록한다 | 키보드·상태·접근성 | — | `extension/options.js` | 1, 3 | todo | `nl -ba extension/options.js \| sed -n '1339,1419p'` → 카드 keyboard만 있고 row path 없음; `renderButtons`가 `innerHTML`을 비움 | — |
| 5 | 실제 옵션 페이지에서 0·1·2·5행, 위·아래·중간 이동, 카드 밖·다른 카드 drop, card/row 동시 nesting, Save/reload, 다섯 locale을 확인하고 세 최종 gate를 종료 상태로 기록한다 | 브라우저·릴리스 검증 | — | 옵션 페이지와 Chrome automation 수기 시나리오; 최종 diff의 1∼4 파일 집합 | 2, 3, 4 | todo | `CLAUDE.md`의 CDP 측정 → synthetic input은 native drop을 완결하지 못하므로 post-drop은 synthetic `DragEvent`로 검증 | — |

- 항목 하나는 한 승격에 들어갈 크기다. 1은 `defaults.js` 순수 계약과 그 테스트, 2는 렌더·CSS·catalogue와 그 i18n 테스트, 3∼4는 `options.js` 상호작용이므로 1·2를 먼저 통과시킨 뒤 3·4를 묶어 구현한다.
- 항목 1의 `moveItem` 문자열·뒤 이동·앞 이동·원본 불변성 cases는 **(ii) 불변 원칙 계약**이며 `moveItem` 구현과 같은 promotion에 들어간다. 항목 2의 i18n key/placeholder/catalogue/pin cases는 **(ii) 다국어 불변 원칙 계약**이며 key와 렌더 code와 같은 promotion에 들어간다. 둘 다 UI listener가 실제로 drop했는지를 주장하지 않는다.
- 5의 브라우저 확인은 **새 committed test가 아니다**. CDP synthetic drag는 `dragstart`∼`dragend`까지만 재현하고 native `drop`을 끝내지 못한다는 측정이 있으므로, 실제 pointer drag와 post-drop synthetic `DragEvent`를 구분해 기록한다. DOM 경로를 인위적인 fake로 덮어쓰지 않는다.
- `확정 결함` 열은 R0 설계 리뷰에서 새로 확정된 결함이 없으므로 모두 `—`다. 검증자가 구현 후 결함을 확정하면 기존 행을 고치지 않고 prime 또는 letter 개정 항목으로 이어 붙인다.

## 결정 원장

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 드라이버 | 행은 어느 목록으로든 옮길 수 있는가 | **같은 카드 안에서만** 허용한다. cross-card move는 두 버튼의 실행 payload 소유권과 목적지 `MAX_CLAUDE_INPUTS`를 함께 바꾸므로 거부한다 | R0 설계 리뷰; 사용자 목표는 카드 내부 행 reorder이고, `options.js:354-366`의 행이 카드별 `btn.claudeInputs`에 생성됨 | 없음 |
| D2 | 드라이버 | section에 위임된 카드 listener와 중첩 행 listener가 같은 native drag를 처리할 위험 | 하나의 `drag` 상태에 `button`/`claude` type을 넣고, row handle class도 분리한다. kind-only인 기존 guard를 type+card guard로 좁힌다. `stopPropagation` 하나에 의존하지 않는다 | R0 설계 리뷰; `options.js:1350-1406`이 section에 위임되고 card `dragend`가 현재 무조건 `endDrag`를 호출함; 기존 `card.draggable` 확인은 일부만 차단 | 실제 Chrome의 relatedTarget 경계는 항목 5에서 브라우저 검증 |
| D3 | 드라이버 | `moveButton`, `dropIndex`, mark/cleanup helper를 행용으로 복제할 것인가 | `moveButton`은 `moveItem`으로 이름을 일반화해 재사용하고, 위치·표시·정리 helper도 selector-scoped generic으로 재사용한다. `reorderButtons`와 `reorderClaudeInputs`는 state/render/focus가 달라 별도 wrapper로 두되 index arithmetic는 복제하지 않는다 | R0 설계 리뷰; `defaults.js:656-660`은 plain array만 slice/splice이고, `rg -n moveButton`(docs/plans 제외)은 14 matches: `extension/options.js:1343`의 production call 1개, definition 1개, tests 12개 | generic helper의 최종 인자 모양은 구현 시 확정 |
| D4 | 드라이버 | 0·1행에도 손잡이를 둘 것인가, 끝 키를 어떻게 처리할 것인가 | 카드 handle과 같은 기준으로 2개 이상에만 표시한다. 끝의 ↑↓는 default scroll을 막되 no-op이며 현재 손잡이에 포커스를 둔다. 1→2 전환 때 모든 row input이 handle 폭만큼 왼쪽으로 이동하는 것도 카드와 같은 동작으로 보고 수용한다 | R0 설계 리뷰; `options.js:297`의 card handle이 `count > 1`일 때만 렌더되고 `options.js:1410-1418`이 끝에서 return함 | 없음 |
| D5 | 드라이버 | 전체 section redraw 뒤 포커스를 잃는가 | ↑↓에서만 이동한 행의 새 `.ci-drag-handle`을 kind·카드·새 `data-ci`로 다시 찾아 focus한다. 두 mouse-drop path는 focus를 조작하지 않으며, 기존 card drop의 focus loss는 선행 동작이고 범위 밖이다 | R0 설계 리뷰 (R0-3); `options.js:284`가 `innerHTML = ''`이고 기존 keyboard만 `cardElement(...).focus()`하며 drop에는 복원이 없음 | 실제 브라우저 focus ring 표현은 항목 5에서 수기 확인 |
| D6 | 드라이버 | 기존 generic reorder 문구를 재사용할 것인가 | 카드의 `ext.card.reorder.aria`는 그대로 두고, tooltip은 카드와 행이 공유하도록 `ext.reorder.tooltip`으로 rename한다. 행의 `ext.claudeInput.reorder.aria`만 새 문자열이며 `ext.field.claudeInputs.help`는 늘리지 않는다 | R0 설계 리뷰; row는 입력 목록 안에 중첩되고 기존 help는 순서 전달을 이미 설명함 | 다섯 언어의 새 aria 번역 문안은 구현 시 번역 품질 검토 필요 |
| D6a | 드라이버 | D6의 aria label에 행 위치를 넣을 것인가 | aria label은 1-based row number를 Chrome message substitution `$ARG1$`로 포함하고 sibling `placeholders` block에 `ARG1`의 `content: "$1"`을 선언한다. 다섯 catalogue 모두 binding을 선언하고 `tools/check-locales.js`가 argument binding을 검증하게 한다 | R0 설계 리뷰 (D6 보완); `%1$s`는 `formatMessage`의 non-Chrome 경로이고 catalogue binding 누락은 해당 gate에서 실패해 빈 접근성 이름이 shipping되지 않음 | 없음 |
| D7 | 드라이버 | DOM code를 Node unit test로 억지로 덮을 것인가 | pure array와 i18n contract만 committed test로 두고, native drag·nested bubbling·focus는 브라우저 시나리오로 검증한다 | R0 설계 리뷰; `docs/context/testing.md:88-100`과 기준선 Node suite에 `options.js` DOM 실행 harness가 없음 | 수기/automation 환경에서 실제 pointer drop 가능 여부 |
| D8 | 드라이버 | 기존 `ext.field.claudeInputs.help`를 늘릴 것인가 | **늘리지 않는다**. 이미 “delivered in order”를 말하고 section-level help가 `⠿` 의미를 가르치며 handle의 `title`이 affordance를 전달한다. 기존 문장에 다섯 언어로 한 clause를 더하는 대안은 marginal discoverability에 비해 실제 번역 검토 비용이 크다 | R0 설계 리뷰 | 없음 |
| D9 | 드라이버 | 카드와 행이 공유하는 tooltip key의 이름을 무엇으로 할 것인가 | `ext.card.reorder.tooltip`을 `ext.reorder.tooltip`으로 rename해 카드 handle과 row handle이 공유한다. 각 locale의 기존 value는 verbatim copy하고, `ext.card.reorder.aria`는 그대로 두며 `ext.claudeInput.reorder.aria`만 새로 만든다 | R0 설계 리뷰; `ext.card.reorder.tooltip`을 row에도 그대로 재사용하는 대안은 diff가 작지만 call site 하나의 이름으로 둘을 섬기게 하는 작은 거짓말이며, 번역된 `face`가 그 비용을 치른 것과 같은 부류다 | 없음 |

## 전수 소탕 표

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `extension/defaults.js:32-110`, `228-230`, `417-463`, `623-629`; `extension/options.js:1218-1297`; `extension/i18n.js`; `tests/source-audit.test.js`; `extension/options.js`의 load/save; `extension/migrations.js`; storage keys/version; `extension/content.js`; `extension/background.js`; `app/**`; `docs/new-terminal-checklist.md` | 안전 | |
| `extension/defaults.js:653-661`의 `moveItem` | 변경 대상(항목 1) | second copy of the move arithmetic를 만들지 않고 card/row 양쪽이 같은 plain-array function과 원본 불변성 cases를 사용 |
| `extension/options.js:281-377` `renderButtons` | 변경 대상(항목 2) | row markup에 2개 이상 조건부 handle, row 번호를 포함한 localized aria/title, drag marker class를 추가 |
| `extension/options.js:1300-1420` reorder section | 변경 대상(항목 3·4) | 현재는 `.btn-card`와 card-only state만 알고, nested row drag·row keyboard branch·drop-zone 제한이 없다 |
| `extension/options.html:79-116`, `208-239` | 변경 대상(항목 2) | `.claude-row`의 positioned anchor, row handle, row dragging, row before/after indicator를 추가 |
| 다섯 `_locales/*/messages.json`과 `tools/check-locales.js:28-35` | 변경 대상(항목 2) | a user-visible string introduced without all five catalogues and their pin을 막고, tooltip key rename과 새 `$ARG1$`/`placeholders` binding을 같은 승격에서 반영 |
| `tests/buttons.test.js`의 `moveButton`·`MAX_CLAUDE_INPUTS` 관련 cases | 변경 대상(항목 1) | move test를 `moveItem`으로 바꾸고 문자열 row case를 추가하며 `MAX_CLAUDE_INPUTS` stored-entry reject contract는 유지 |
| `tests/i18n.test.js`의 source-site count/list·catalogue tests | 변경 대상(항목 2) | `options.js`의 새 aria/title call 두 곳과 placeholder binding을 exact corpus/count에 반영하고 다섯 catalogue parity를 유지 |

## 라운드 로그

### R0

#### 설계 리뷰 — R0 수정 반영 · 승격 없음 · 리뷰 완료 · 왕복 1 · 원문 없음

- 반박: R0-1∼R0-8 — 기준 트리 경로, 테스트 promotion 단위, card drop focus 범위, row drop zone, row indicator anchor, 결정 원장 근거, 소탕 표 압축, 배치 측정을 지적했다.
- 처리: 반영 — 기준 트리와 write_codex thread id를 수정하고, 테스트를 항목 1·2에 접어 항목을 1∼5로 정리했으며, D5를 keyboard-only focus restore로 고쳤다. same-card `.claude-rows` drop zone, `.claude-row` `position: relative`, D6a aria placeholder, D8 help 비확장을 명시하고 안전 행을 압축했다.
- 실측: `node --test` exit 0, tests 217/pass 217/fail 0; `node tools/check-locales.js` exit 0, `all 5 live catalogues carry the same names and argument bindings as en`; `cd app && swift test` exit 1, `/Users/choongjaelee/.cache/clang/ModuleCache` 쓰기 거부로 manifest 단계 실패.
- 판정: "R0 방향 승인" → 계획만 승격 가능, 항목 1∼5 `todo`

## 열린 질문

- 실제 Chrome에서 행을 같은 카드의 마지막 gap에 놓을 때 `dragleave`의 `relatedTarget`과 native `drop` 순서가 계획한 selector/type guard와 일치하는지 — 항목 3·5에서 확인한다. CDP synthetic input만으로는 native drop을 판정하지 않는다.
