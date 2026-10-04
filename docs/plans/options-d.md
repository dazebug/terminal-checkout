# options-d

- 절차 정본: drive-agent-loop 스킬과 이 계획 템플릿
- 대상: `extension/options.html` · `extension/options.js` Chrome 확장 옵션 페이지
- 시작 커밋: `b8d8f483aaa76e556e244e414fbdd0a0ea51ad21` (`b8d8f48`)
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/options-d-review` (`worktree-options-d-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-options-d-work` (`options-d-work`)
- 현재: R1 · 마지막 승격 b62595f · 리뷰 중 없음 · 게이트 그린(401)
- 최근 검증자 판정: 계획을 레인 3개로 재편하면 시작에 합의한다 — 1단계 항목 1부터 · R0

## 배경 — 확인한 원천

- [`CLAUDE.md`](../../CLAUDE.md) 는 옵션 페이지의 단일 저장 버튼, 첫 로드 게이트, 저장 전 소유 키 재읽기, 런타임 uid, 편집 상태 기준 마이그레이션, 목록 종류별 가시성, 입력 트리밍, 드래그 취소, 기본값 단일 원천과 테마 토큰 관계를 정한다.
- [`README.md`](../../README.md) 의 옵션 페이지·변수·Development 절은 사용자 기능 설명과 확장 게이트의 정본이다.
- [`docs/context/index.md`](../context/index.md), [`options-page-reordering.md`](../context/options-page-reordering.md), [`localization.md`](../context/localization.md), [`testing.md`](../context/testing.md), [`claude-input-delivery.md`](../context/claude-input-delivery.md), [`batch-fan-out.md`](../context/batch-fan-out.md) 는 옵션 구조·드래그·현지화·검증의 이유와 실행 경계 근거다.
- [`extension/options.html`](../../extension/options.html), [`extension/options.js`](../../extension/options.js), [`extension/defaults.js`](../../extension/defaults.js), [`extension/migrations.js`](../../extension/migrations.js), [`extension/i18n.js`](../../extension/i18n.js), [`extension/layout.js`](../../extension/layout.js), [`extension/_locales/*/messages.json`](../../extension/_locales/) 는 현재 구현 원천이다.
- [`.git/mockup-d/src-d-real-github.html`](../../.git/mockup-d/src-d-real-github.html), [`shared.js`](../../.git/mockup-d/shared.js), [`shared.css`](../../.git/mockup-d/shared.css), [`built-D.html`](../../.git/mockup-d/built-D.html) 는 작업 트리에 둔 D 디자인·상호작용 참고다. 목업의 복제 모델과 고정 데이터는 구현 원천이 아니다.
- 사용자 결정 (2026-10-02): B는 빽빽하고 구획을 나누면 찾기 어려워 제외한다. GitHub의 위치를 보여 주는 D를 고른다. 프리셋 위치 서랍·사용 중 표시·놓을 자리 강조·드래그 추가·기존 버튼 교체 확인, 바깥 클릭 시 팝오버 닫기와 편집 초안 유지를 확인했다.

## 목표

- 옵션 페이지를 버튼의 실제 GitHub 위치가 보이는 D 편집 화면으로 바꾼다.
- 현재 편집·저장·동기화·마이그레이션·백업 기능을 보존하고 버튼을 편집 상태에서 미리 본다.
- 기존 저장값·기본값 원천과 저장 바이트를 보존하며 화면 상태는 저장하지 않는다.
- DOM 없는 테스트와 소스 감사, clone 안의 jsdom 스모크, 드라이버의 실제 브라우저 확인으로 동작을 고정한다.

## 완료의 정의

- 기능 보존 전수 소탕 표의 모든 행이 정해진 작업 항목에 도착하고, 빠지는 제품 동작이 없다. 목업 전용 상태 전환기와 conflict 종류만 main에 없는 목업 요소로 제외한다.
- 저장 충돌 배너가 저장되지 않은 초안을 내보내기로 보존할 수 있다고 안내하지 않는다. 내보내기는 기존처럼 저장값만 내보내며, 편집 초안은 팝오버를 닫아도 보존한다.
- acceptance oracle: 리포 루트의 의존성 없는 `node --test` 에서 새 DOM 없는 모델 함수 테스트와 타입이 정해진 소스 감사를 포함해 전체 테스트가 통과한다. 기존 `buttons.test.js`, `claude-note.test.js`, `i18n.test.js`, `migration.test.js`, `layout.test.js`, `list-pages.test.js`, `readme-catalogue-labels.test.js`, `source-audit.test.js` 계약도 통과한다. 각 레인은 clone의 `.git/tools/` 에 `npm install --prefix .git/tools jsdom` 으로만 jsdom을 설치하고, 커밋 밖 `.git/smoke-<이름>.cjs` 로 DOM·이벤트 스모크를 실행한다. 각 레인은 명령과 출력 원문을 근거로 남기며 드라이버는 같은 스크립트를 다시 실행한 뒤 실제 브라우저에서 확인한다. `package.json` 과 리포 의존성은 추가하지 않고 구현자는 브라우저·GUI 앱을 띄우지 않는다.
- 드라이버 브라우저 확인: 다섯 종류의 GitHub 위치·모양과 편집 중인 실제 버튼, 설정용 예시 화면 표시, 버튼 자리 drag·키보드 대안, 프리셋 사용 중·hover 강조·추가·교체 확인, 팝오버 바깥 클릭·Escape·포커스 복귀·초안 유지, 5개·10개 상한, 변수 경고, 실행 전 예시 도크, Reset·마이그레이션, 가져오기·내보내기, 첫 로드 전 차단·실패 재시도·저장 충돌, 800 px와 900 px 전후의 배치·줄바꿈·잘림을 확인한다. 소스 검사와 jsdom만으로 실제 렌더링을 주장하지 않는다.
- 실설정 왕복: 사용자 실제 설정(비소유 키 포함)으로 로드 → 버튼 하나 편집 → Save → 바뀐 소유 키는 그 버튼 종류뿐이고 비소유 키는 바이트가 같다. 드라이버가 미리보기 하네스로 확인한다.
- 코퍼스 범위: 실제 버튼 종류 5개와 `defaults.js` 의 프리셋 13개, 확장 로케일 5개 (`en`, `ko`, `ja`, `zh_CN`, `zh_TW`), README 4개 (`README.md`, `README.ko.md`, `README.ja.md`, `README.zh-Hant.md`), 요청에 열거된 옵션 관련 테스트.
- 원자성·부분 실패·롤백 경계: 가져오기·프리셋 적용·마이그레이션·초기화·변경 취소·팝오버 편집은 편집 상태만 바꾼다. 저장은 [Save] 한 경로에서만 한다. 저장 직전 모든 소유 키를 다시 읽어 변경이 있으면 거부하고 자동 병합하지 않는다. 저장 오류는 화면에 남기며 자동 재시도·롤백하지 않는다. Chrome storage API 오류 때 부분 쓰기가 가능한지는 확인하지 않았고 저장 경로를 바꾸지 않으므로 이번 루프의 위험 범위가 아니다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

- 사용자: 버튼과 입력 행을 추가·삭제·재정렬하고, 프리셋·가져오기·마이그레이션을 적용하며, 저장값으로 변경 취소를 할 수 있다.
- 같은 Chrome 동기화 계정의 다른 프로필·기기: 열린 옵션 화면의 저장값과 다른 값을 기록할 수 있다.
- Chrome 확장 런타임·카탈로그: 초기 읽기·저장·할당량 오류와 로케일 키 불일치를 전달한다.
- 구현자 레인 A·B·C: A는 이 clone, B는 `/Users/choongjaelee/Codes/terminal-checkout-options-d-work2`, C는 `/Users/choongjaelee/Codes/terminal-checkout-options-d-work3` 에서 각각 작업한다.
- 드라이버: 실제 브라우저에서 배치·포커스·클릭·키보드·드롭·실설정 왕복을 확인한다.

## 비목표 — 건드리지 않는다

- `extension/content.js` 의 GitHub 페이지 분류·버튼 삽입·실행 결과: 옵션 화면이 실제 렌더를 따르되 실행 경로는 바꾸지 않는다.
- `app/`, 네이티브 메시징, 터미널·Claude 전달: UI 재배치만 한다.
- 저장 키·스키마·마이그레이션 레지스트리·기본 프리셋 데이터·`toStoredButton`·저장 직렬화: 기존 값을 그대로 사용한다.
- 앱 팔레트의 CSS 토큰과 `Theme.swift` 관계: 앱 팔레트는 기존 거울 관계를 유지하고 GitHub 복제 화면만 별도 토큰을 쓴다.
- 목업 전용 상태 전환기와 conflict PR 버튼 종류: main의 실제 다섯 종류에 없으므로 제품에 넣지 않는다. 충돌 PR 종류는 병합되지 않은 `origin/conflict-button` 에만 있다.
- Chrome storage 오류의 부분 쓰기 동작 조사·수정: 저장 경로를 바꾸지 않고 현행 오류 처리를 유지한다.
- 리포 의존성이나 `package.json` 도입: jsdom은 clone 내부 `.git/tools/` 에서만 쓴다. 구현자는 브라우저·GUI를 실행하지 않고 화면 확인은 드라이버가 한다.

## 불변 원칙

- 세 전용 clone과 단계는 고정한다. 1단계 계약·골격은 레인 A 단독, 2단계 항목 2∼7은 세 레인이 병렬로 구현하고 각 항목을 승격하며, 3단계 통합은 레인 A가 한다. README 네 언어판은 레인 C가 7′ 뒤에, 맥락 문서는 레인 B가 항목 8과 병렬로 작성한다.
- 레인 사이 파일 집합은 겹치지 않는다. `extension/options.js`·`extension/options.html` (인라인 스타일 포함)·`extension/defaults.js` 는 레인 A만 고친다. 레인 B·C는 자기 신규 JS·CSS·테스트 파일만 고치며, 필요한 마운트 지점·링크·엔진 API는 항목 1이 미리 만든다. 항목 1이 정하지 않은 엔진 API가 필요하면 그 레인은 파일을 고치지 않고 멈춰서 묻는다.
- `tools/check-locales.js`의 `CATALOGUE_BASELINE_HASHES`(로케일 다섯 파일의 sha256)와 `tests/i18n.test.js`의 인자 호출 지점 수는 카탈로그·호출을 의도적으로 바꾼 커밋이 함께 갱신하는 리뷰용 고정값이다. 세 레인 모두 **자기 변경 때문에 바뀐 그 값만** 이 두 파일에서 고쳐도 된다 — 다른 줄은 고치지 마라. 충돌은 손으로 합치지 말고 기준 쪽 값을 받은 뒤 **합쳐진 결과로 다시 계산해 넣는다**(해시는 파일 바이트의 sha256, 호출 수는 테스트가 읽은 수). 마크업 속성 감사는 사용자에게 읽히는 속성 값을 카탈로그 메시지로 채워 통과시키고, 감사 목록 자체는 고치지 마라.
- 편집 엔진은 `extension/options.js` 에 둔다. 스냅샷 JSDoc은 다섯 종류별 버튼 배열과 버튼의 runtime `uid`, 저장 필드 `face`·`label`·`command`·`claudeInputs`, 종류별 정확한 프리셋 명령 일치 `presetId` (없으면 `null`), 비어 있지 않고 어떤 종류별 프리셋 명령과도 같지 않은 `customCommand`, 버튼별 필수값 오류·Claude 경고, 전체 `dirty`·`revision`, 기본 main·저장소 override, 로드·저장·동기화·마이그레이션·상태 줄을 완전히 선언한다. 스냅샷의 검증과 Save는 같은 검증 함수 결과를 쓴다. 기본 main은 엔진 상태가 정본이고 DOM 입력칸은 그 상태를 반영한다. `FACE_EMOJI` 와 얼굴 글자 수 상한 `FACE_MAX_LENGTH = 24` 는 `defaults.js` 에 두고 편집 화면이 함께 쓴다.
- `dispatch(action)` 은 항상 `Promise<OptionsDispatchResult>` 를 반환한다. 결과는 `{ok, reason?, createdUid?, snapshot}` 이며 `reason` 은 `not-loaded`·`busy`·`limit`·`not-found`·`needs-confirmation`·`invalid`·`failed` 중 하나다. `createdUid` 는 `button-add`·`button-duplicate`·`preset-add` 가 만든 uid다. dispatch는 `confirm`·`alert`·`prompt` 를 열지 않는다. 사용자 확인이 필요한 custom-command `preset-replace` 와 미저장 편집이 있는 `discard`·`adopt-latest` 는 화면 모듈이 자체 UI로 확인한 뒤 `confirmed: true` 를 보내며, 확인 전에는 `needs-confirmation` 을 돌려준다. 저장과 기존 load/import/export 경로를 제외한 변경 action은 편집 상태 변경 함수를 호출한다. 마이그레이션 후보 선택은 `migration-selection` 의 candidate uid와 boolean `selected` 로 바꾸며 설정 dirty는 올리지 않고 review intent만 기록한다. `migration-panel-toggle` 은 엔진 snapshot의 `migration.panelOpen` 을 바꾼다.
- 엔진 상태는 화면의 정본이다. 로드 실패·상태 줄 문구·마이그레이션 패널 열림 상태를 엔진 state로 보유하고 스냅샷은 DOM에서 읽지 않는다. 화면 입력은 event의 값을 dispatch로 보내며 DOM 값을 저장의 입력으로 삼지 않는다. 통합 뒤 `options.html` 의 `#app` 은 복제 화면과 편집기만 담고 첫 로드 응답 전까지 `inert` 이다. 셸은 바깥에 남아 재시도만 할 수 있고, 하단 설정 루트도 첫 로드 전까지 `inert` 이다. 옛 카드·전역 설정·백업 DOM과 그 전용 렌더·이벤트 코드는 통합에서 제거한다.
- `subscribe(listener)` 는 등록 즉시 호출하지 않는다. 상태 변경 뒤 알림을 마이크로태스크 하나로 합쳐 호출하고, 최초 그림은 각 `mount` 가 `getSnapshot()` 으로 그린다. 버튼 action은 `(kind, uid)`, 버튼 이동은 `(kind, uid, beforeUid)`, 입력 행 action은 `(kind, buttonUid, inputIndex)`, 입력 이동은 `(kind, buttonUid, fromIndex, beforeIndex)` 로 식별한다. 외부 데이터 조회에는 `Map` 또는 `Object.hasOwn` 을 쓴다. 첫 로드 응답 전에는 저장과 편집 action을 거부한다. `#app[inert]` 가 복제 화면·팝오버 입력을 막고 셸은 `retry-load` 만 제공한다.
- 화면 모듈 계약은 `optionsShell.mount(root, engine, settingsRoot)`, `optionsReplica.mount(root, engine, editor)`, `optionsEditor.mount(root, engine)` 이다. 셸의 첫 루트는 저장 막대·배너·로드 오류·상태 줄을 두고 둘째 루트는 복제 화면 뒤에 전역 설정·백업을 둔다. `optionsReplica` 는 `focusButton(kind, uid)` (버튼이 없으면 해당 종류 추가 자리로 포커스), `openDrawer()`·`closeDrawer()`·`isDrawerOpen()`, `getExampleContext()` 를 공개한다. `getExampleContext()` 는 하나뿐인 `EXAMPLE_CONTEXT` 를 그대로 돌려주며 실행 전 예시도 이를 읽는다. `optionsEditor.open({kind, uid, anchor, restoreFocusTo})` 에서 `anchor` 는 옆에 붙을 요소, `restoreFocusTo` 는 닫을 때 돌아갈 요소다. 복귀 요소 연결이 끊겼으면 `optionsReplica.focusButton(kind, uid)` 를 부른다. 편집기 모듈은 `close()`·`isOpen()` 을 공개한다. 열린 팝오버와 서랍은 한 번에 하나뿐이며 편집기를 열면 서랍을 닫고 서랍을 열면 편집기를 닫는다.
- 로케일 파일 다섯 개는 세 레인이 함께 쓰는 유일한 파일 예외다. 각 레인은 고유한 물리 키 접두어와 앵커 바로 뒤에 자기 키 블록 하나만 넣는다. 모든 로케일의 키 순서와 앵커 위치는 동일하다. 레인 A는 `ext_d_shell_` 을 `ext_button_save` 뒤에, 레인 C는 `ext_d_editor_` 를 `ext_migration_badge` 뒤에, 레인 B는 `ext_d_replica_` 를 `ext_validate_tooltip` 뒤에 넣는다. 이 앵커는 각각 현재 17·82·154번째 키다. 소스 ID는 `chromeMessageId()` 경계에 맞춰 `ext.d.shell.*`, `ext.d.editor.*`, `ext.d.replica.*` 를 쓴다.
- 2단계 레인은 승격 직전마다 기준 트리의 최신 승격 위로 rebase한다. 레인 B·C는 `git fetch origin worktree-options-d-review` 후 `git rebase FETCH_HEAD` 를 실행한다. 레인 A는 `git fetch /Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/options-d-review worktree-options-d-review` 후 `git rebase FETCH_HEAD` 를 실행한다. 자기 파일 집합 밖에서 난 충돌은 해소하지 말고 멈춰서 묻는다. 로케일 파일 충돌은 두 쪽 키 블록을 모두 남기는 방식으로만 해소한다.
- `defaults.js` 가 종류·프리셋·저장 키·상한·가시성의 단일 원천이다. 목업의 `KINDS`, `SAVED`, `PRESETS` 를 복사하지 않는다. 현재 종류는 `pr`, `pr-list`, `issue`, `issue-list`, `repo` 5개다. 종류별 버튼 상한 5와 입력 상한 10을 지킨다.
- 같은 편집 상태를 저장하면 현 페이지와 같은 키·값 구조와 저장값이 나온다. `toStoredButton` 과 저장 직렬화를 바꾸지 않는다. 고른 페이지·서랍·팝오버·자리 표시 같은 화면 상태는 storage에 넣지 않는다.
- 사용자 storage에는 main이 소유하지 않는 키가 있을 수 있다. 예를 들어 `conflictButtons` 는 브랜치 빌드가 남긴 키다. 저장은 현행대로 `SETTINGS_KEYS` 가 소유한 키만 쓰고 비소유 키를 덮거나 삭제하지 않는다. 유일한 `chrome.storage.sync.set` 호출 자리는 Save 경로다. 기존 소스 감사에는 이 단일 호출 자리를 고정하는 검사가 없으므로 항목 1의 `tests/options-page-source.test.js` 가 호출 수와 Save 연결을 고정한다.
- 첫 로드 응답 전에는 페이지를 조작하거나 저장하지 않는다. 검증 후 모든 소유 키와 버전을 저장 직전 다시 읽고 달라졌으면 저장을 거부하며 자동 병합하지 않는다. 저장 버전은 migration 적용·부분 적용·거절이나 Reset 같은 명시적 사용자 행위의 결과로만 갱신한다.
- 편집 runtime uid는 저장·내보내기에 기록하지 않는다. 추가는 `adoptButton`, 재구성은 `reshapeButton`, 직렬화는 기존 `toStoredButton` 계약을 따른다. 외부 데이터 키는 `Map` 또는 `Object.hasOwn` 으로 조회한다.
- 마이그레이션 계획은 저장값이 아닌 현재 편집 상태에서 계산한다. 적용할 후보는 uid로 식별하고, 검토·적용·유지·초기화 같은 사용자 행위가 있을 때만 저장 버전을 갱신한다.
- `claude_inputs` 는 양끝 일반 공백만 다듬는다. 컨트롤 문자를 삭제하거나 일반 `trim()` 으로 바꾸지 않는다. 입력 경고·순서·종류별 도움말을 보존하고 실제 전달 의미를 변경하지 않는다.
- [변경 취소]는 변경이 있을 때 확인하고, 확인 후 현재 저장값을 기존 로드 경로로 다시 읽어 편집 상태를 바꾼다. storage에 쓰지 않고 migration 버전을 바꾸지 않는다. Reset은 백업 패널에서 기본 프리셋으로 편집 상태를 초기화하는 기존 기능이다.
- 복제 화면은 편집 상태의 실제 버튼을 그린다. 주변 풍경과 실행 전 예시 값은 한 곳의 `EXAMPLE_CONTEXT` 상수로 정의한다: `octo-demo/sample-repo`, PR `#42` (`example/options` → `main`, 제목 `Add button presets`), issue `#17` (`Example tracking issue`), 실행 예시 repo 경로 `/work/sample-repo`. 화면에는 확장 카탈로그 문구 `설정용 예시 화면(실제 GitHub 아님)` 을 보이고 목업의 `dazebug/terminal-checkout`·PR `#99`·issue `#88` 을 사용하지 않는다.
- GitHub 페이지 풍경에서 보이는 GitHub 자체 UI 문구는 레인 B의 JSDoc 타입이 있는 `GITHUB_UI_COPY` 한 표에 영어 리터럴로 모은다. 표에는 화면에 쓰는 `Code`, `Issues`, `Pull requests`, `Actions`, `Projects`, `Wiki`, `Security`, `Insights`, `Settings`, `Type / to search`, `Edit`, `Open`, `Closed`, `Conversation`, `Commits`, `Checks`, `Files changed`, `Reviewers`, `Assignees`, `Labels`, `Label`, `Milestone`, `Milestones`, `Development`, `No reviews`, `None yet`, `New issue`, `New pull request`, `Filters`, `Author`, `Reviews`, `Sort`, `Watch`, `Fork`, `Star`, `Public`, `No conflicts with base branch`, `Merging can be performed automatically.` 를 둔다. 확장 문구는 전부 카탈로그를 거친다. 타입이 정해진 소스 감사는 새 화면 모듈에 이 표 밖의 사용자 문구 리터럴이 없음을 고정한다.
- 버튼 모습은 실제 렌더 규칙을 따른다. 목록 버튼은 텍스트 길이와 상관없이 pill이며 PR·issue 상세는 emoji/텍스트 차이, repo는 초록 액션 버튼이다. 프리셋 13개의 한 줄 설명은 기본값에 복사하지 않고 레인 B의 새 카탈로그 문자열로 각 로케일에 둔다.
- 팝오버와 서랍은 바깥 클릭과 Escape로 닫히고, 열었던 버튼·자리로 포커스를 돌리며 초안은 남긴다. 닫기 키는 포인터 동작의 키보드 대안이다.
- 모든 끌기 동작에는 키보드 또는 버튼 대안이 있다. 버튼 순서에는 위·아래 이동, 서랍의 추가·바꾸기에는 명시적인 버튼, 입력 행 순서에는 위·아래 이동을 둔다. 버튼 자리와 서랍 카드도 포함해 어떤 drag 표면이든 redraw가 진행 중인 drag를 취소한다.
- 앱 팔레트 CSS 토큰은 `Theme.swift` 와 계속 거울 관계다. GitHub 복제 화면의 색은 GitHub 색이므로 별도의 `--gh-` 토큰 묶음에 두고 `Theme.swift` 와 거울 관계가 아니라고 주석을 단다. 이 경계는 항목 10의 `CLAUDE.md` 테마 토큰 문장에도 반영한다.
- 새 확장 화면 문구는 물리 로케일 5곳 전부에 추가하고 메시지 인자·HTML 계약을 맞춘다. 새 프리셋 설명은 13개 × 5개 로케일 카탈로그 값이다. README가 새 화면 문구를 인용하면 네 언어판을 함께 고치고 `readme-catalogue-labels.test.js` 계약을 통과한다.
- 화면 계약은 커밋되는 DOM 없는 모델 함수 테스트와 타입이 정해진 소스 감사로 고정한다. 각 레인의 jsdom 스모크는 clone의 `.git/tools/` 와 `.git/smoke-<이름>.cjs` 에서만 실행한다. 실제 브라우저는 드라이버가 확인한다. 의존성을 리포에 넣지 않는다.
- 계획 파일은 레인 A만 고친다. 레인 B·C의 상태와 근거는 드라이버가 지정한 문구로 레인 A가 옮겨 적는다.

## 배치 점검 (0라운드)

모드: ultrafast

| 점검 | 결과 |
|:--|:--|
| 기준 트리 · 브랜치 | `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/options-d-review` · `worktree-options-d-review` |
| 기준 트리 `.claude/worktrees/` 무시 상태 | ignored · `.git/info/exclude:7`; 작업 clone에는 worktree가 없어 clone의 무시 규칙 점검은 해당 없음 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `git rev-parse --show-toplevel` → `/Users/choongjaelee/Codes/terminal-checkout-options-d-work`<br>`git branch --show-current` → `options-d-work`<br>`git log --oneline -2`:<br>`b8d8f48 feat: the setup window becomes a settings window with General, GitHub and Slack panes (#108)`<br>`416ce06 feat: the Slack thread shortcut is a global hotkey the app registers — it works with Slack in front, and the app can open at login (#107)`<br>HEAD `b8d8f483aaa76e556e244e414fbdd0a0ea51ad21` |
| cmux 패널 (신호가 켜졌을 때만) | `surface:87` (`pane:54`) |
| 의존성 동기화 | N/A — `package.json` 없음 |
| git 밖 로컬 자산 env — 에이전트가 읽기 확인 | 오버레이 `Local asset env: None`. 템플릿과 mockup 입력 파일을 읽었다 |
| 증분 리뷰 소요(분) — 첫 세 번 | N/A — 아직 리뷰 없음 |
| 에이전트 첫 보고: 확장 게이트 `node --test` | 종료 코드 0<br>ℹ tests 326<br>ℹ suites 0<br>ℹ pass 326<br>ℹ fail 0<br>ℹ cancelled 0<br>ℹ skipped 0<br>ℹ todo 0<br>ℹ duration_ms 623.002916 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | 계약·골격 | 레인 A · 1단계 계약·골격 | — (저장 충돌 안내 결함은 항목 3) | `extension/options.js`, `extension/options.html` (마운트·스크립트·링크와 인라인 스타일), `extension/options-shell.js/css`, `extension/options-replica.js/css`, `extension/options-editor.js/css`, `tests/options-shell.test.js`, `tests/options-replica.test.js`, `tests/options-editor.test.js`, `tests/options-page-source.test.js`, `tests/i18n.test.js` (새 CSS 자산 역할 등록), 로케일 앵커 계약 | — | verified | 기존 화면 유지; `node --test` → `ℹ tests 336`, `ℹ pass 336`, `ℹ fail 0`, `exit_code=0`; `node .git/smoke-shell.cjs` → 깊은 동결 스냅샷·구독 1회·카드 7개·소유 digest 동일·`conflictButtons` 쓰기 없음; 재실행: 드라이버 미리보기 로드 오류 0·입력 48·저장 쓰기 0 | 5b0017a |
| 1′ | 엔진 계약 보강 | 레인 A · 1단계 계약 보강 | (a) dispatch가 옛 카드 DOM을 조작하고 preset-replace가 confirm()을 연다 (b) 검증 판정 두 벌 (c) 결과·확인·presetId·customCommand·FACE_EMOJI·기본 main 계약 공백 (d) 실패할 수 없는 typedef 테스트 | `extension/options.js`, `extension/defaults.js`, `tests/options-page-source.test.js`, `tests/buttons.test.js`, `tests/claude-note.test.js` | 1 | verified | `node --test` → `ℹ tests 340`, `ℹ pass 340`, `ℹ fail 0`, `exit_code=0`; `node .git/smoke-engine.cjs` → `load_error_count=0`, `dispatch_actions=26`, `dialog_calls=0`, `detached_dom_actions=button-patch,input-move,preset-replace`, `confirmation_probes=preset-replace:needs-confirmation,discard:needs-confirmation,adopt-latest:needs-confirmation`, `duplicate_created_uid_matches_snapshot=true`, 소유 digest `a20853fbb4989a6c316b5101629478061b59ab5be039a29ae222040cf96557e4` 동일, `storage_writes=1`, `conflictButtons_written=false`, `conflictButtons_unchanged=true`; 재실행: 드라이버 `node --test` 340 pass · `.git/smoke-engine.cjs` 출력 동일 · 미리보기 로드 오류 0 | |
| 2 | 셸 | 레인 A · 셸 | — | `extension/options.js` (마이그레이션 선택·패널 action), `extension/options-shell.js/css`, `extension/defaults.js` (`FACE_MAX_LENGTH`), `extension/options.html`, `extension/_locales/*/messages.json`, `tests/options-shell.test.js`, `tests/options-page-source.test.js`, `tests/i18n.test.js`, `tools/check-locales.js` | 1, 1′ | verified | `node --test` → `ℹ tests 355`, `ℹ pass 355`, `ℹ fail 0`, `exit_code=0`; `node .git/smoke-shell.cjs` → `main_load_error_count=0`, `legacy_cards=7`, `discard_confirmed=true`, `discard_storage_writes=0`, `sync_banner_actions=reload,accept,defer`, `sync_accept_restored_remote_default=true`, `storage_writes=1`, `conflictButtons_written=false`, `retry_loaded=true`, `migration_candidates=1`, `migration_read_only=1`, `migration_selection_action=reviewTouched_without_dirty`, `migration_apply_storage_writes=0`, `migration_keep_pending=false`, `migration_keep_storage_writes=0`; 재실행: 드라이버 기준 트리 `node --test` 355 pass · 미리보기 로드 오류 0 · 첫 로드 전 Save 거부 (`requireLoaded`) | |
| 3 | 전역 설정·백업 | 레인 A · 전역 설정·백업 | (a) 저장 충돌 배너·오류가 저장값만 내보내는 export로 편집을 보존하라고 잘못 안내한다 (`extension/options.js:1105; extension/_locales/en/messages.json:11,167,211`) | `extension/options-shell.css`, `extension/options-shell.js`, `extension/options.html`, `extension/_locales/*/messages.json`, `tests/migration.test.js`, `tests/options-shell.test.js`, `tests/options-page-source.test.js`, `tests/i18n.test.js`, `tools/check-locales.js` | 1, 2 | verified | `node --test` → `ℹ tests 364`, `ℹ pass 364`, `ℹ fail 0`, `exit_code=0`; `node .git/smoke-backup.cjs` → load 오류 0, legacy 전역 표면 숨김, override 불완전·중복 경고와 삭제, 빈 main은 `main` 저장, export는 미저장 편집 제외·storage 쓰기 0, 정상·초과·미래 버전 import는 편집 상태만 변경, Reset 확인·storage 쓰기 0, 소유 키만 저장·`conflictButtons` 미기록·브라우저 대화상자 0; `node .git/smoke-shell.cjs` → 로드·다시 시도·동기화·마이그레이션 동작 유지; 재실행: 드라이버 기준 트리 `node --test` 364 pass · `tests/migration.test.js` 단언 변경은 결함 red→green | |
| 3′ | 셸 표시 결함 | 레인 A · 셸 표시 | (a) `hidden` 영역을 CSS `display` 가 덮어 로드 성공 후에도 오류 영역이 보인다 (b) 깨끗한 상태가 저장 사건 문장으로 보인다 | `extension/options.html`, `extension/options-shell.js/css`, `extension/_locales/*/messages.json`, `tests/options-page-source.test.js`, `tests/options-shell.test.js`, `tests/i18n.test.js`, `tools/check-locales.js` | 2 | verified | 재실행: 드라이버 기준 트리 `node --test` 374 pass · 실제 브라우저 편집기 연 상태에서 hidden인데 보이는 요소 0 (승격 전 4) | 53cf591 |
| 3″ | 한국어 줄바꿈 | 레인 A · 셸 표시 | 한국어 문구가 음절 사이에서 줄이 바뀐다 | `extension/options.html`, `tests/options-page-source.test.js` | 3′ | verified | 재실행: 드라이버 기준 트리 `node --test` 374 pass · 실제 브라우저 편집기 연 상태에서 hidden인데 보이는 요소 0 (승격 전 4) | 8f9d5b7 |
| 3‴ | 셸 접근성·IME 입력 | 레인 A · 셸 접근성 | (a) 마이그레이션 후보 라벨이 체크박스를 감쌌다가 heading에 다시 추가해 연결을 끊는다 (b) IME 조합 중 Escape를 셸 단축키가 가로챈다 | `extension/options-shell.js`, `tests/options-shell.test.js` | 3 | claimed | 수정 전 재현 스크립트: 마이그레이션 `labelControl=null`, `checkboxLabels=0`, 라벨 클릭 뒤 선택 불변; IME Escape `defaultPrevented=true`; `node --test tests/options-shell.test.js` → `ℹ tests 8`, `ℹ pass 6`, `ℹ fail 2`; 수정 후 `.git/smoke-accessibility.cjs` → main·override repo/branch·가져오기 파일·마이그레이션 체크박스 이름 연결, 라벨 클릭 선택 전환, IME Enter/Escape 중 확인 유지, 일반 Escape 닫힘, jsdom 오류 0; `node --test` → `ℹ tests 397`, `ℹ pass 397`, `ℹ fail 0` | |
| 3⁗ | 셸 확인창 모달 차단 | 레인 A · 셸 확인 UI | aria-modal 확인창이 열린 동안 페이지 배경·설정·복제 화면을 조작할 수 있어 포커스와 엔진 상태가 바뀐다 | `extension/options-shell.js`, `tests/options-shell.test.js` | 2·3 | claimed | 수정 전 재현: `aria-modal=true`, `activeOutsideModal=true`, `backgroundInert=false`, `engineMain=draft-while-confirming`; 수정 전 `node --test tests/options-shell.test.js` → `ℹ tests 10`, `ℹ pass 8`, `ℹ fail 2`; 수정 후 제공 재현: `activeOutsideModal=false`, `backgroundInert=true`, `engineMain=develop`; `.git/smoke-confirmation.cjs` → 변경 취소·Reset·동기화 받아들이기 각각 배경 inert·Tab 순환·배경 편집 차단·Escape 뒤 포커스 복귀; 재실행 `node --test` → `ℹ tests 401`, `ℹ pass 401`, `ℹ fail 0` | |
| 4 | 복제 화면 | 레인 B · 복제 화면 | (a) 목록 페이지 미리보기가 실제 pill 모양을 그리지 않는다 (`extension/options.js:393; extension/content.js:504,524`)<br>(b) 800 px에서 목록·편집 막대 문구가 세로로 접히며 900 px 이하 배치는 실측되지 않았다 (2026-10-04 사용자 관찰) | `extension/options-replica.js/css`, `tests/options-replica.test.js`, B 로케일 블록. 주변 값은 이 모듈의 단일 `EXAMPLE_CONTEXT` 상수에 둔다: `octo-demo/sample-repo`, PR `#42`, issue `#17`, branch `example/options`, base `main`, 제목 `Add button presets`, repo 경로 `/work/sample-repo` | 1 | verified | 레인 B 커밋 `7fc851f` · 레인 B 하네스 5/5 페이지·목록 pill 2·storage 쓰기 0 · 드라이버 실제 브라우저 800px: 다섯 페이지 카드·브랜치 옆 버튼 3개·편집기 열림 · 재실행 361 pass | 7fc851f |
| 5 | 프리셋 서랍 | 레인 B · 프리셋 서랍 | — | `extension/options-replica.js/css`, `tests/options-replica.test.js`, B 로케일 블록 | 1·4 | verified | 레인 B 커밋 c3f8b38 · 하네스: 서랍 카드 5/1/3/1/3·자리 강조·[추가]·위치 지정 끌어 놓기·확인 뒤 교체·대화상자 0·storage 쓰기 0 · 드라이버 재실행 380 pass · 프리셋 설명 13개를 실제 명령과 대조 | c3f8b38 |
| 5′ | 복제 화면 줄바꿈 | 레인 B · 복제 화면 | 복제 화면의 언어 공통 `word-break: keep-all` 이 일본어·중국어 문구도 줄바꿈하지 못하게 한다 | `extension/options-replica.css`, `tests/options-replica.test.js` | 4 | verified | 드라이버 재실행 384 pass · replica에서 언어 무관 keep-all 제거 확인 | 097d025 |
| 5″ | 서랍 바꾸기 동작 | 레인 B · 프리셋 서랍 | 서랍 카드의 `[바꾸기]` 를 누른 뒤 이벤트 대상이 분리되면서 바깥 클릭 처리기가 서랍을 닫는다 | `extension/options-replica.js`, `tests/options-replica.test.js` | 5 | verified | 실제 브라우저에서 서랍 `[바꾸기]` 클릭 뒤 서랍 열림 유지 · 385 pass | 88bd567 |
| 5‴ | 목록 버튼 편집·서랍 확인 재개 | 레인 B · 복제 화면 | (a) 목록 페이지에서 쓸 수 없는 변수를 넣은 버튼이 복제 화면에서 사라져 편집 진입점이 없다 (b) 서랍 교체 확인을 Escape로 닫고 다시 열면 `[확인]` 이 동작하지 않는다 | `extension/options-replica.js/css`, `tests/options-replica.test.js` | 4·5″ | wip | 레인 B 진행 중; 드라이버 cold 재현 스크립트에서 목록 버튼 진입점 0, 확인 뒤 revision 불변 | |
| 5⁗ | 끌기 뒤 클릭·풍경 언어 | 레인 B · 복제 화면 | (a) 끌기 뒤 다음 클릭을 삼킨다 (b) P3 영어 풍경 문구에 document 언어가 지정되지 않는다 | `extension/options-replica.js/css`, `tests/options-replica.test.js` | 5·5‴ | wip | 드라이버 cold 재현 스크립트 확인: 끌기 직후 첫 클릭이 동작하지 않음, P3 영어 풍경에 lang 미지정 | |
| 6 | 팝오버 편집기 | 레인 C · 팝오버 편집기 | — | `extension/options-editor.js/css`, `tests/options-editor.test.js`, C 로케일 블록 | 1 | verified | 레인 C 커밋 `46f12de` · 레인 C 하네스: 열기·바깥 클릭/Escape 닫기와 포커스 복귀·재열기 값 유지·대화상자 0·storage 쓰기 0 · 드라이버 재실행 352 pass | 46f12de |
| 7 | claude 입력과 실행 전 예시 | 레인 C · 입력·실행 예시 | — | `extension/options-editor.js/css`, `tests/options-editor.test.js`, C 로케일 블록 | 1·6 | verified | 레인 C 커밋 `a2e164d` · 하네스: 입력 행 추가·삭제·↑↓·합성 DragEvent·상한·타이핑 중 노드 유지·예시 표시·storage 쓰기 0 · 드라이버 재실행 371 pass · 실제 브라우저에서 편집기 열림 | a2e164d |
| 7′ | 편집기 표시 결함 | 레인 C · 편집기 표시 | (a) `hidden` 요소가 보임 (b) 리사이즈에 자리를 다시 잡지 않음 — 폭 0에서 열면 세로 띠로 고정 (c) 명령 칸 아래 맨 글자 예시 (d) 변수 목록 두 번 (e) 하단 동작 막대 뒤로 본문이 비침 | `extension/options-editor.js/css`, `tests/options-editor.test.js`, C 로케일 블록 | 7 | verified | 실제 브라우저에서 hidden 요소 0 · 하네스 0폭 열기·리사이즈 · 384 pass | 98de9cc |
| 7″ | 편집기 포커스·바깥 클릭 | 레인 C · 편집기 표시 | (a) 버튼이 사라질 때 편집기 포커스 복귀가 셸 포커스와 다툰다 (b) 다시 그려 분리된 편집기 안 클릭을 바깥 클릭으로 잘못 판정한다 | `extension/options-editor.js`, `tests/options-editor.test.js` | 7′ | verified | 하네스 포커스 다툼·바깥 클릭 경로 판정 · 387 pass | 53e8c41 |
| 7‴ | 편집기 IME·좁은 창 배치 | 레인 C · 편집기 표시 | (a) IME 조합 중 Escape가 편집기를 닫는다 (b) 좁은 창에서 아래쪽 버튼을 열면 편집기 높이가 0이다 | `extension/options-editor.js/css`, `tests/options-editor.test.js` | 7′ | wip | 레인 C 진행 중; 드라이버 cold 재현 스크립트에서 조합 중 Escape로 편집기 닫힘, 579×700 아래쪽 anchor에서 높이 0 | |
| 7⁗ | 편집기 확인 포커스·재배치 | 레인 C · 편집기 표시 | (a) 동기화 알림 렌더가 교체 확인의 포커스를 지운다 (b) 다시 그려진 버튼의 옛 좌표에 편집기가 고정된다 | `extension/options-editor.js/css`, `tests/options-editor.test.js` | 7′·7″ | wip | 드라이버 cold 재현 스크립트 확인: 교체 확인 포커스가 분리됨, 편집기 위치가 재그린 버튼을 따르지 않음 | |
| 8 | 통합 | 레인 A · 3단계 통합 | (a) 옛 카드·셸 DOM 및 전용 렌더·이벤트 코드가 남아 이중 상태와 경로를 유지한다 (b) 엔진 스냅샷이 오류·상태 값을 옛 DOM에서 읽는다 (c) 숨김 규칙 주석이 모든 페이지에서 버튼을 숨긴다고 과장하지만 실제 숨김은 목록 종류만이다 (`extension/defaults.js`, `extension/content.js`) | `extension/options.html`, `extension/options.js`, `extension/defaults.js`, `tests/options-page-source.test.js`, 기존 옵션 관련 테스트 | 2·3·4·5·6·7 | verified | 드라이버 실제 브라우저 실설정 왕복: 바뀐 소유 키 `buttons` 하나·`conflictButtons` 같음 · 388 pass | c9a622b |
| 8′ | 복제 화면 첫 배치와 제목 | 레인 A · 화면 배치 | (a) 복제 화면 앞에 긴 설정·백업 도움말이 나와 복제 화면이 첫 화면 밖에 밀린다 (b) 통합 뒤 페이지에 `h1` 이 없다 | `extension/options.html`, `extension/options.js`, `extension/options-shell.js/css`, `tests/options-shell.test.js`, `tests/options-page-source.test.js` | 8 | claimed | `node .git/smoke-layout.cjs` → DOM 순서 savebar < page-card/replica < global-settings/backup, `h1=Terminal Checkout — 설정 (lang=ko)`, 첫 로드 전 설정 `inert`·컨트롤 비활성·추가 변화 없음, 로드 오류 0; `node --test` → `ℹ tests 389`, `ℹ pass 389`, `ℹ fail 0`, `exit_code=0` | |
| 9 | README 네 언어판 | 레인 C · README 네 언어판 | 새 UI 레이블을 README가 인용할 때 카탈로그 값과 불일치하면 화면 문구를 찾을 수 없다 (`tests/readme-catalogue-labels.test.js:49`) | `README.md`, `README.ko.md`, `README.ja.md`, `README.zh-Hant.md`, `tests/readme-catalogue-labels.test.js` | 8 | verified | README 네 언어판 · 버튼 순서 키 ←/→ 정정 · 384 pass | 08a7fd2 |
| 10 | 맥락 문서 | 레인 B · 맥락 문서 | D 선택·레이어 분리·로케일·실제 저장 보존 이유는 코드만으로 알 수 없다 | `docs/context/options-page-design.md`, `docs/context/index.md`, `CLAUDE.md` | 8 | verified | 결정 기록 · A·C 순위 근거 정정 | 75376e2 |
| 10′ | 결정 기록 근거 정정 | 레인 B · 맥락 문서 | 선택 경위 문구가 기록된 세션 순서와 A·C 순위 근거를 정확히 반영하지 않는다 | `docs/context/options-page-design.md` | 10 | verified | 결정 기록 · A·C 순위 근거 정정 | 950ec8d |

- 항목 1은 레인 A만 승격한다. B·C의 새 모듈과 테스트는 JSDoc 계약만 가진 골격으로 이 단계에 만든 뒤, 계약 커밋 이후 각 레인이 자기 파일 집합을 구현한다. 엔진 API·화면 mount/open 계약·`EXAMPLE_CONTEXT` 값과 필드·로케일 앵커를 이 단계에서 고정한다. 각 action은 기존 함수·이벤트 처리기를 감싸는 계약만 둔다.
- 항목 2∼7은 2단계에서 레인 A·B·C가 병렬 구현한다. 각 작업 항목은 별도 승격 크기이며 위 의존 항목의 계약만 사용한다. 레인은 지정된 모듈·테스트 파일 이외를 고치지 않는다.
- 항목 8은 레인 B·C가 서로 다른 파일에서 진행 중이어도 레인 A가 병행한다. 항목 9는 레인 C가 7′ 뒤에, 항목 10은 레인 B가 항목 8과 병렬로 맡는다.

## 결정 원장

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | B는 빽빽하고 영역을 나누면 필요한 버튼 위치를 찾기 어렵다 | GitHub 위치를 거의 그대로 보여 주는 D를 선택 | 사용자 결정, 2026-10-02 | — |
| D2 | 사용자 | 프리셋 위치와 적용 대상이 보여야 한다 | 위치별 카드 서랍, 사용 중 표시, hover 위치 강조, 드래그 추가, 기존 버튼 교체 전 확인 | 사용자 결정, 2026-10-02 | — |
| D3 | 사용자 | 편집 중 바깥을 누르면 팝오버가 닫히되 저장 전 내용은 남아야 한다 | 바깥 클릭으로 팝오버를 닫고 편집 초안을 유지한다 | 사용자 결정, 2026-10-02 | — |
| D4 | 사용자 | 버튼 수 상한은 main에 이미 적용됨 | 종류별 5개 제한을 유지한다 | `#106`, `main:extension/defaults.js:324` | — |
| D5 | 사용자 | 이 단계는 계획 검토이며 코드는 아직 고치지 않는다 | R0 리뷰를 반영하고 `docs/plans/options-d.md` 한 파일만 지정 메시지로 커밋한 뒤 멈춘다. 코드는 변경하지 않는다 | 2026-10-04 사용자 지시 | — |
| D6 | 사용자 | 구현자 하나로는 느리다 | 구현자 3명이 레인 A·B·C로 병렬 구현한다. 1단계 계약 커밋은 레인 A 단독, 2단계는 세 레인 동시, 3단계 통합은 레인 A | 2026-10-04 사용자 지시 | 레인 사이 계약 어긋남은 1단계 계약과 rebase 규칙으로 막는다 |
| D7 | 드라이버 | 목업의 고정 예시와 설명을 제품에 넣을지(Q1) | 버튼은 편집 상태를 그리고, 풍경은 한 곳의 예시 값으로 그리며 예시 화면임을 표시한다. 프리셋 설명은 카탈로그에 둔다 | R0 설계 리뷰 | — |
| D8 | 드라이버 | Q2 [변경 취소] 동작 | [변경 취소]를 넣는다. 저장값을 기존 로드 경로로 다시 읽어 편집 상태를 바꾸며, 변경이 있으면 확인을 거친다. 저장하지 않고 버전도 바꾸지 않는다. Reset은 백업 패널로 옮겨 그대로 둔다 | R0 설계 리뷰 | — |
| D9 | 드라이버 | Q5 팝오버·서랍의 키보드 닫기 | Escape는 팝오버와 서랍을 닫고 포커스를 연 자리로 돌린다. 바깥 클릭과 같이 초안은 남는다 | R0 설계 리뷰 | — |
| D10 | 드라이버 | Chrome storage API 실패 뒤 부분 쓰기 여부 | 부분 쓰기 여부는 확인하지 않았다 — 저장 경로를 바꾸지 않으므로 이 루프의 위험이 아니다 | R0 설계 리뷰 | 저장 API 동작은 미확인 상태로 남는다 |
| D11 | 드라이버 | 연결할 옵션 재설계 이슈·PR 존재 여부 | 관련 이슈·PR 없음 — 출처는 이 루프의 PR이 된다 | `gh issue list --repo dazebug/terminal-checkout --state all --search "options in:title"` 결과 #78·#24만, 둘 다 무관; R0 실측 | — |
| D12 | 드라이버 | 문서 항목 배정 변경 | 항목 10을 레인 B로 재배정 — 레인 A가 항목 8을 맡는 동안 문서를 병렬로 쓴다. 항목 9는 레인 C가 7′ 뒤에 맡는다 | 2026-10-05 사용자 지시 | — |
| D13 | 드라이버 | 저장 직전 재읽기 뒤 쓰기 완료 전 원격 변경이 덮이는 창 | cold 분류 A 잔여 — `storage.sync` 에 비교 후 쓰기가 없어 남는 기존 잔여(설정 마이그레이션 때부터 명시), 이번 변경의 회귀 아님 | cold 검토 | 기록만 |

## 전수 소탕 표

현 옵션 페이지가 제공하는 기능 전부를 새 위치에 대응했다. 이번 범위에서 빠지는 사용자 기능은 없다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| 첫 로드 완료 전 옵션 UI 비활성·저장 차단 | 항목 8 — `#app[inert]` 가 복제 화면·편집기를 막고 셸 Save도 비활성; `.git/smoke-load-gate.cjs` 에서 편집 dispatch `not-loaded` | `options.html:358`, `options.js:593,685` |
| 첫 로드 실패 메시지·다시 시도 | 항목 8 — 셸에서 오류를 표시하고 Retry 후 다시 로드; `.git/smoke-shell.cjs` 의 `retry_loaded=true` | `options.html:484`, `options.js:593` |
| 다섯 종류의 페이지별 배치와 저장값 미리보기 | 항목 4·8 — 복제 화면의 다섯 페이지 카드가 편집 상태 버튼을 보여 줌; `.git/smoke-shell.cjs` 의 페이지 5·렌더 버튼 확인 | `options.js:4`, `options.html:387,400,411,423,435` |
| PR·issue 상세 emoji 또는 텍스트 pill, repo 초록 버튼 | 항목 4·8 — 복제 화면 버튼은 해당 종류의 편집값과 GitHub 모양을 사용; 레인 B 하네스 5/5 페이지 | `options.js:393`, `content.js:565,613` |
| PR 목록·issue 목록 버튼의 pill 모양 | 항목 4·8 — 복제 화면 목록 버튼은 pill 렌더; 레인 B 하네스 목록 pill 2 | `options.js:393`, `content.js:504,524` |
| 얼굴·툴팁 필드, 글자수 제한 24, emoji 팔레트, 미리보기 | 항목 6·8 — 편집기 필드·미리보기·팔레트와 `FACE_MAX_LENGTH` 유지; `.git/smoke-shell.cjs` 에서 상한 24와 팔레트 확인 | `options.js:285,313,329,393` |
| 종류별 프리셋 선택·기존 명령 덮어쓰기 확인 | 항목 5·6·8 — 복제 화면 서랍에서 추가·확인 뒤 교체, 편집기에서 기존 프리셋 교체 확인; `.git/smoke-drawer-add.cjs` 13개 카드·버튼 3→4, `.git/smoke-shell.cjs` 교체 확인 | `options-replica.js:571,648`, `options-editor.js:669,755`, `options.js:885` |
| 명령 textarea, 자동 크기, 변수 삽입, 변수 도움말과 경고 | 항목 6·8 — 편집기에 명령 입력·종류별 변수 도움말·실행 예시·Claude 경고; `.git/smoke-shell.cjs` 에서 경고 표시와 제거 확인 | `options.js:333`, `options.html:387,400,411,423,435` |
| 변수 사용 불가 버튼의 종류별 가시성 | 항목 8 — 편집기에서 명령을 수정하고 복제 화면의 종류별 표시 규칙을 사용; 주석은 목록만 숨기는 규칙으로 수정 | `defaults.js:216,220`, `content.js:544` |
| Claude 입력 행 추가·삭제·최대 10·유형 안내·경고 | 항목 7·8 — 편집기의 입력 행·유형 안내·상한·경고; `.git/smoke-shell.cjs` 에서 추가·삭제·경고 확인 | `options.js:341,376`, `defaults.js:329` |
| Claude 입력 행 재정렬 | 항목 7·8 — 편집기에서 위·아래 버튼과 드래그 대안; `.git/smoke-shell.cjs` 에서 이동 버튼 확인 | `options.js:285,1330`, `docs/context/options-page-reordering.md` |
| 버튼 추가·중복·삭제·고유 레이블·종류별 최소 1개·최대 5개 | 항목 5·6·8 — 서랍 추가와 편집기 복제·삭제; `.git/smoke-engine.cjs` 에서 추가·복제·삭제 action, `.git/smoke-drawer-add.cjs` 에서 추가 확인 | `options.js:308,384`, `defaults.js:324,1316` |
| 버튼 순서 변경·첫 버튼 동작·입력 중 포커스 | 항목 4·6·8 — 복제 화면 자리와 편집기 순서 조작, 편집 입력 초점 보존; `.git/smoke-shell.cjs` 에서 입력 노드·포커스 확인 | `options.js:280,285`, `README.md:239` |
| 기본 main 브랜치 (빈 값 저장 시 `main`)와 저장소별 override 추가·삭제·불완전·중복 검증 | 항목 3·8 — 셸 설정 패널; `.git/smoke-backup.cjs` 에서 override 검증·삭제와 빈 main의 `main` 저장 | `options.html:446`, `options.js:410,579,708` |
| Reset | 항목 3·8 — 셸 백업 패널에서 확인 후 편집 상태만 초기화; `.git/smoke-backup.cjs` 에서 Reset 후 쓰기 0 | `options.js:850` |
| Save 유효성 검사·저장 직전 소유 키 전부 재읽기·변경 충돌 거부·버전 consent | 항목 2·8 — 셸 Save가 기존 엔진 경로를 호출; `.git/smoke-engine.cjs` 에서 편집 없는 저장 digest 동일·비소유 키 미기록 | `options.js:685,715,724` |
| 진행·성공·오류·할당량 상태, 미저장 표시·이탈 경고 | 항목 2·8 — 셸 저장 막대와 상태 줄이 엔진 스냅샷을 표시; `.git/smoke-shell.cjs` 에서 clean/dirty·성공·검증 오류, `.git/smoke-load-gate.cjs` 에서 첫 로드 Save 차단 | `options.js:800`, `options.html:477` |
| 동기화 변경 stale 안내, reload/adopt/defer와 작업 중 보류 | 항목 2·8 — 셸 동기화 배너의 다시 읽기·받아들이기·미루기; `.git/smoke-shell.cjs` 에서 세 동작과 편집 확인 | `options.js:261,593` |
| 마이그레이션 badge·검토 패널·선택·적용·유지·review-only | 항목 2·8 — 셸 배지와 검토 패널에서 선택·적용·유지, 정보 항목은 읽기 전용; `.git/smoke-shell.cjs` 에서 후보 1·정보 1·적용/유지 storage 쓰기 0 | `options.js:273,964`, `migrations.js:243,326` |
| JSON export·날짜·버전·저장값 전용·미저장 제외 안내·저장값이 없을 때의 오류 | 항목 3·8 — 셸 백업 패널의 export가 저장값만 출력; `.git/smoke-backup.cjs` 에서 미저장 main 제외·storage 쓰기 0 | `options.js:1105`, `_locales/en/messages.json:11,167,211` |
| JSON import·256 KiB 제한·오류·미래 버전 거부·건너뛴 값 보고·부분 편집 상태 반영 | 항목 3·8 — 셸 백업 패널의 import가 편집 상태만 변경; `.git/smoke-backup.cjs` 에서 정상·초과·미래 버전 모두 확인 | `options.js:1160`, `migrations.js:384` |
| 페이지별 변수·마이그레이션·Claude 입력·백업 도움말 | 항목 3·6·7·8 — 도움말은 셸·편집기의 기존 카탈로그 메시지로 제공; `node --test` 의 카탈로그 참조 검사 통과 | `options.html:387,446,465`, `_locales/en/messages.json` |
| 접근성 레이블·키보드 조작·동적 상태 공지·포커스 | 항목 2·3‴·4·5·6·7·8 — main·override 저장소/브랜치·가져오기 파일·마이그레이션 체크박스에 연결된 이름, IME 조합 중 셸 단축키 무시, Escape·드래그 대안과 상태 공지; `.git/smoke-accessibility.cjs` 에서 라벨 연결·선택 전환·IME Enter/Escape 보존·일반 Escape 닫기 | `options-shell.js`, `tests/options-shell.test.js` |
| 저장 충돌 배너와 export 안내 사이의 의미 충돌 | 항목 3·8 — 셸은 편집 보존 수단으로 export를 말하지 않고 최신값 수용 후 재적용·Save를 안내; `tests/options-shell.test.js` 와 `node --test` 통과 | `_locales/en/messages.json:11,167,211` |
| 목업의 고정 PR #99·issue #88·SAVED·가짜 설명 | 항목 4·5·8 — 복제 화면은 편집 상태 버튼·고정 예시 context·카탈로그 프리셋 설명을 사용; `.git/smoke-shell.cjs` 의 context와 예시 배너 확인 | `.git/mockup-d/shared.js` |
| 목업의 평소·편집·서랍·예시·변수 오류 상태 스위처 | 항목 8 — 목업 전환기는 제거하고 실제 셸·편집기·복제 화면의 상태로 렌더; legacy DOM 노드 0 | `.git/mockup-d/src-d-real-github.html:319` |
| 목업의 충돌 토글과 conflict PR 버튼 kind | 항목 8 — main에 없는 PR kind와 토글은 추가하지 않음; 실제 데이터의 `conflictButtons` 는 저장 후에도 보존하고 기록하지 않음 | `main:extension/defaults.js:193`, `origin/conflict-button:extension/defaults.js:227-244`, `.git/mockup-d/src-d-real-github.html:319` |
| 목업의 [변경 취소] 버튼 | 항목 2·8 — 셸에서 확인 후 기존 로드 경로로 되돌리고 쓰지 않음; `.git/smoke-shell.cjs` 에서 취소 storage 쓰기 0 | `.git/mockup-d/src-d-real-github.html:219`, `options.js:850` |
| 800 px에서 페이지 목록 줄바꿈·편집 막대 세로 분절 | 항목 4·8 — 복제 화면 배치를 보존하고 통합 스타일을 점검; 800 px 실제 브라우저 결과는 레인 B 승격 근거에 기록 | 2026-10-04 사용자 제공 800 px 관찰; 소스로 화면 배치 판정 불가 |

## 라운드 로그

### R0

#### 설계 리뷰 — R0 · 계획 수정 · 승격 없음 · 왕복 1 · 원문 사용자 지시

- 반박: R0-1 항목이 승격보다 크고 레인을 나눌 수 없음 · R0-2∼R0-6 열린 질문 다섯 개 결정 · R0-7 배치 점검 실측 · R0-8 불변 원칙 7개 누락 · R0-9∼R0-11 검증·완료 정의·서술 정리
- 처리: 전부 반영 (항목 표 10개로 재편, 원장 D6∼D11, 불변 원칙 추가)
- 실측: 기준 트리 `.claude/worktrees/` ignored · 관련 이슈 검색 0건 · `node --test` 326 pass
- 판정: "계획을 레인 3개로 재편하면 시작에 합의한다 — 1단계 항목 1부터"

### R1

#### 리뷰 cold — b8d8f48..5ac1026 · 새 스레드 01a10816-cbd7-7c33-a267-29ba243c1117

- 차단: (1) 목록 버튼에 그 페이지에서 못 쓰는 변수를 넣으면 복제 화면에서 사라져 편집 불가 (2) 서랍 교체 확인을 Escape로 닫고 다시 열면 [확인] 무동작 (3) IME 조합 중 Escape가 편집기를 닫음 (4) 마이그레이션 체크박스 라벨 미연결 (5) 좁은 창 아래쪽 버튼에서 편집기 높이 0 — 전부 분류 B
- 수정: 항목 5‴(레인 B: 1·2)·7‴(레인 C: 3·5)·3‴(레인 A: 4)
- 실측: 드라이버가 검토자 재현 스크립트를 샌드박스 밖에서 실행해 5건 모두 재현
- 판정: 이 구현에 합의하는가: no
- 처리 결과: 1차 결함 5건 수정·승격: 08ec8f6·af07234·b62595f, 테스트 심사 91c7701

#### 리뷰 cold 2 — b8d8f48..b62595f · 새 스레드 01a10838-3b38-7ec3-9748-c2aec607cb2f

- 차단: (1) 분류 A: 저장 재읽기 뒤 쓰기 완료 전 원격 변경 덮어쓰기 — 기존 잔여 (2) 동기화 알림이 교체 확인 포커스를 지움 (3) 셸 확인창 aria-modal인데 배경 조작 가능 (4) 다시 그려진 버튼의 옛 좌표에 편집기 고정 (5) 끌기 뒤 다음 클릭을 삼킴 (6) P3 영어 풍경 lang 미지정 — (2)∼(6) 분류 B
- 수정: 항목 7⁗(레인 C: 2·4)·5⁗(레인 B: 5·6)·3⁗(레인 A: 3), (1)은 기존 원장 행대로 기록만
- 실측: 드라이버가 재현 스크립트 확인
- 판정: 이 구현에 합의하는가: no

## 열린 질문

- 없음 — R0 리뷰 결정과 드라이버 실측으로 Q1∼Q6을 처리했다.
