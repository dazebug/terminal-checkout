# base-dir-fallback

- 대상: `/Users/choongjaelee/Codes/terminal-checkout-base-dir-fallback` (브랜치 `base-dir-fallback`)
- 시작 커밋: `294c46a`
- 현재: **R4 워킹트리(항목 11 — PR #32 리뷰 반영, 미커밋)** · base `ef42cf9` · 게이트 3종 그린(swift 210/0, node 24/0, e2e 9 PASS)
- 최근 검증자 판정: **합의(yes) ×2** — R1(`5e77163`)·R3 재검증(`f870f26`), 스레드 `01a023c2-8afe-7de1-b755-489ec6b5bc6d`

이슈 #30 — "A cold zoxide DB fails every preset silently — `command -v z` still reports all green". 확정 방향은 **옵션 1+1a**(base dir을 옵션으로 받아 두고 `z` 실패 시 base dir 기반으로 동작, 클론이 안 돼 있으면 clone까지)이며 이 방향 자체는 재론하지 않는다.

## 목표

- 앱 설정 창에 저장한 **저장소 기본 폴더(base dir)** 가 있으면, zoxide DB가 비어 있든 zoxide 자체가 없든 11개 프리셋 전부가 저장소 디렉터리로 진입해 `&&` 체인의 나머지(fetch·checkout·worktree·claude)를 끝까지 실행한다.
- 아직 클론돼 있지 않은 저장소는 base dir 아래로 clone한 뒤 그 자리에서 체인을 이어 간다 — clone은 앱이 아니라 사용자 셸의 같은 체인 안에서, 화면에 보이는 채로 일어난다.
- base dir을 설정하지 않은 사용자에게는 **렌더링 결과 문자열이 지금과 완전히 같다**. 이 동등성은 테스트로 고정한다.
- 설정 창의 `z` 경고가 base dir 유무에 따라 오류↔경고로 갈린다 — base dir이 있으면 `z`가 없어도 모든 버튼이 실패하지는 않기 때문.
- 확장은 base dir을 보내지도 알지도 못한다. 확장이 그 이름의 변수를 보내면 병합되지 않고 거부된다.

## 비목표 — 건드리지 않는다

- **이슈 #29(확장 아이콘·버튼 실패의 표면화)**: 셸 안에서 일어나는 실패를 앱이 관찰할 채널을 새로 만들지 않는다. #30은 "명령은 정확히 전달됐고 셸 안에서 죽는다"는 전제 위에 있고, 이번 작업은 그 실패 자체를 없애는 쪽이다.
- **콜드 DB 감지(`zoxide query`)와 DB 워밍(`zoxide add`) 자동화**: 이슈 본문의 첫 번째 방향이지만 zoxide 전용이라 `z.sh` 사용자를 못 덮고, 확정 방향(1+1a)이 이를 대체한다. `ToolChecker`는 지금처럼 `command -v z`까지만 본다.
- **저장소별 base dir 다중화·owner 계층 레이아웃(`<base>/<owner>/<repo>`)**: `repoMainBranch` 오버라이드라는 선례가 있어 흉내 내기 쉽지만, 표 UI·검증·문서가 통째로 붙는다. 단일 base dir로 끝낸다.
- **문자 화이트리스트 확장**: 공백·`~`·한글이 들어간 경로를 허용하려고 `allowedValueScalars`(`CommandRenderer.swift:26-33`)를 넓히지 않는다. `~`는 입력 시점에 확장하고, 나머지는 설정 창에서 사유와 함께 거부한다.
- **기존 사용자의 저장된 버튼 문자열 마이그레이션**: `storage.sync`에 이미 저장된 command를 우리가 고쳐 쓰지 않는다. 새 프리셋은 프리셋을 명시적으로 적용할 때와 저장소가 비어 있을 때(`DEFAULT_*`)만 적용된다.
- **새 터미널 추가, 앱 로컬라이제이션(#24), fork-safe 체크아웃(#26), `uninstall.sh` 정리(#28)**: 같은 파일을 스치지만 별개 이슈다. 특히 #26은 clone URL을 다루므로 섞이기 쉬운데, 이번 clone은 "base dir에 없으면 가져온다"이지 "fork에서 가져온다"가 아니다.
- **앱이 직접 `cd`/`clone`을 실행하는 경로**: 아키텍처(TCC 귀속)와 관찰 가능성 양쪽에서 금지다.

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

- **`extension/defaults.js`가 프리셋·기본값·표시 규칙·페이지 분류·스토리지 키의 단일 정본이다.** 11개 프리셋 문자열은 이 파일에서만 바뀐다. `content.js`·`background.js`·`options.js`는 이 파일을 먼저 로드해 같은 값을 본다.
- **base dir의 정본은 앱이다.** 확장에는 값을 지정할 방법을 주지 않는다 — 터미널 선택과 같은 규칙(CLAUDE.md). 근거는 취향이 아니라 저장소 성질이다: 경로는 기계마다 다른데 확장 설정은 `storage.sync`로 계정을 따라 다른 기계로 간다(`README.md:149`, `extension/options.js:399`의 `BACKUP_KEYS`) — 동기화되는 순간 반대편 기계에서 조용히 틀린 경로가 된다. 그래서 앱의 `UserDefaults`에 두고, native messaging 프로토콜에는 새 필드를 **추가하지 않는다**(구버전 확장 ↔ 신버전 앱 조합도 그대로 동작한다).
- **확장이 보낸 앱 변수는 병합이 아니라 거부다.** `allowedVariables`(`CommandRenderer.swift:19-21`)에 앱 제공 변수 이름을 넣지 않는다 — 넣는 순간 확장이 임의 셸 조각을 보낼 수 있는 구멍이 된다. "요청 변수 검증"과 "앱 변수 병합"은 순서가 다른 두 단계로 유지한다.
- **문자 화이트리스트는 하나뿐이고 넓히지 않는다.** base dir 값도 `sanitizeValue`(`CommandRenderer.swift:35-40`)의 **같은 판정 함수**를 받는다 — 두 번째 검증기를 만들지 않는다. 정규식으로 되돌리지 않는다(파이썬 시절 `$`가 끝 개행 하나를 허용하던 구멍이 그렇게 생겼다). `/`·`-`·`_`·`.`는 이미 허용 문자라 `/Users/foo/Codes` 같은 절대경로는 그대로 통과한다. `~`는 허용 문자로 **추가하지 말고** 입력 시점에 홈 경로로 확장해 셸에 닿지 않게 한다.
- **셸 조각 변수는 앱이 조립한 텍스트에만 허용되는 새로운 부류다.** 조각의 재료는 (i) 앱 설정에서 온 검증된 경로와 (ii) 이미 `sanitizeValue`를 통과한 변수 값, 이 둘뿐이다. 요청에서 온 텍스트가 이 부류로 들어가는 경로는 만들지 않는다. `renderCommand`는 치환 결과를 다시 스캔하지 않지만(`CommandRenderer.swift:52-65`의 단일 패스 — `result += value` 후 `last = whole.upperBound`) 그 성질에 기대는 대신, 조각은 애초에 치환이 끝난 값으로 만든다.
- **그룹은 `{ …; }`이고 절대 `( … )`가 아니다.** `cd`가 현재 셸에 남아야 하기 때문이다(`extension/defaults.js:6-7`). 새로 만드는 조각 전체에 적용된다.
- **`z`가 먼저다.** base dir은 `z`가 실패했을 때만 쓰인다 — `z`가 성공적으로 점프한 디렉터리를 base dir이 덮어쓰지 않는다. 실측(R0): 콜드 DB는 `zoxide: no match found` + exit 1, `z` 미설치는 `command not found: z` + exit 127 — 둘 다 `||`로 넘어간다. 즉 이 한 갈래가 "콜드 DB"와 "zoxide 자체가 없음"을 동시에 덮는다.
- **base dir 미설정 = 지금과 완전히 같다.** 렌더 결과가 문자열 단위로 동등해야 하고, 그것을 테스트로 고정한다. 이 성질이 "프리셋 문자열을 길게 늘이는" 대신 "앱이 조각을 조립하는" 설계를 고른 이유다 — 프리셋에 `{basedir}` 경로 변수만 넣으면 미설정 사용자는 `Variable {basedir} not provided`로 **모든 버튼이 깨진다**.
- **앱은 `clone`도 `cd`도 직접 실행하지 않는다.** 전부 사용자 셸의 한 체인 안에서 보이는 채로 일어난다. 앱이 실행하면 TCC 귀속과 아키텍처 분리가 흔들리고, 어차피 앱은 셸 안의 실패를 관찰할 수 없다(#30의 전제).
- **라운드마다**: `cd app && swift test`(Core 단위), 리포 루트 `node --test`(확장 순수 함수), `app/build.sh` 후 `app/e2e.sh`(relay↔소켓 왕복)가 전부 그린이어야 한다. red를 먼저 쓰고 red를 눈으로 확인한 뒤 구현한다.
- **언어**(2026-08-21 사용자 지시로 개정, 메인 CLAUDE.md Working principles에 명문화): **코멘트와 문서는 `app/` 포함 전부 영어로 쓴다.** 이 브랜치가 이미 한국어로 쓴 신규 주석은 영어로 교체한다(기존 코드의 레거시 한국어 주석은 건드리지 않는다 — 일괄 번역은 별개 작업). 사용자 대면 UI 문구는 #24(다국어화)가 정본이므로 지금은 한국어 유지.

### 설계 결정 요약 (R0 판단 — 뒤집으려면 여기부터 읽는다)

앱이 조립해 채우는 변수 **`{cd}`** 하나를 도입하고, 프리셋은 `z {repo} && …` 대신 `{cd} && …`로 시작한다.

| base dir | `{cd}`가 치환되는 문자열 |
|:--|:--|
| 미설정 | `z {repo}` — 지금과 바이트 동일 |
| 설정(`B`), owner 있음 | `{ z R \|\| cd B/R \|\| { gh repo clone O/R B/R && cd B/R; }; }` |
| 설정, owner 없음 | `{ z R \|\| cd B/R; }` |

(`R`=검증된 `repo`, `O`=검증된 `owner`, `B`=검증된 base dir)

이 형태를 고른 이유:

- 미설정 사용자의 동작 불변이 **한 곳에서** 떨어진다. 프리셋에 경로 변수를 박는 방식으로는 불가능하다.
- 전략이 한 함수에 모인다 — 나중에 순서·clone 방식을 바꿔도 프리셋 11개를 다시 만지지 않는다.
- 프리셋 문자열이 읽을 수 있는 길이로 남는다(옵션 페이지의 command textarea는 `rows=2` autosize).
- 대가: "값이 셸 문법인 변수"라는 새 부류가 생긴다. 위 불변 원칙의 셸 조각 항목이 그 경계이고, 이 경계를 코드 주석과 CLAUDE.md 양쪽에 남긴다.

## 작업 항목

| # | 항목 | 상태 | 근거 | 라운드 |
|:--|:--|:--|:--|:--|
| 1 | **Core: base dir 검증·정규화 단일 함수.** `~` 확장 → 절대경로 요구 → 후행 `/` 제거 → 기존 `sanitizeValue`와 **같은** 문자 판정. `sanitizeValue`를 `public`으로 올리거나 얇은 공개 래퍼 하나만 만든다(두 번째 검증기 금지). 빈 문자열 = 미설정. **red**: `app/Tests/CoreTests/CoreTests.swift`에 `BaseDirectoryTests` 신설 — `/Users/x/Codes` 통과 / `~/Codes` 확장 / 공백·`;`·`$`·한글 거부 / 상대경로 거부 / 후행 슬래시 정규화 / 빈 값은 오류가 아니라 미설정 | agreed | `app/Sources/Core/BaseDirectory.swift:20-41` (`normalizedBaseDirectory`), `sanitizeValue`는 `CommandRenderer.swift:45-47`에서 `private`→모듈 내부로만 열었다(두 번째 검증기 없음). red: `swift test` → `CoreTests.swift:103:28: error: cannot find 'normalizedBaseDirectory' in scope`. green: `swift test --filter BaseDirectoryTests` → `Executed 8 tests, with 0 failures`. 개행은 트림하지 않아 `/Users/x/Codes\n`이 화이트리스트에 걸린다(파이썬 시절 `$` 구멍 재발 방지) | R1 |
| 2 | **Core: 진입 조각 조립 함수** `repoEntryCommand(repo:owner:baseDir:)`. 위 표대로 조립. 그룹은 `{ …; }`만. **red**: `BaseDirectoryTests`에 오라클 테스트 — 미설정 시 `"z \(repo)"`와 문자열 동등 / 설정 시 `z`가 첫 절 / 결과에 `(` 미포함 / owner 부재 시 clone 절 부재 / base dir이 검증에 실패하면 던진다 | agreed | `app/Sources/Core/BaseDirectory.swift:59-74` (`repoEntryCommand`). red: `CoreTests.swift:139:17: error: cannot find 'repoEntryCommand' in scope`. green: `swift test --filter RepoEntryCommandTests` → `Executed 10 tests, with 0 failures`. 오라클: `{ z remy \|\| cd /Users/x/Codes/remy \|\| { gh repo clone frograms/remy /Users/x/Codes/remy && cd /Users/x/Codes/remy; }; }`. 재료(repo·owner)를 조립 지점에서 다시 `sanitizeValue`에 태운다 — 결과만이 면제 대상 | R1 |
| 3 | **Core: `{cd}` 주입 경로.** `resolveRequest(_:baseDirectory:)`(기본값 `""` = 미설정) 추가 — 앱은 **base dir 문자열 하나만** 넘기고, 조각 조립은 Core 안에서 항목 2의 함수가 한다(드라이버 추가 제약). 요청의 `variables`는 지금처럼 `allowedVariables`로만 검증하고(→ 확장이 `cd`를 보내면 `Unknown variable: {cd}`), 앱이 조립한 값은 그 뒤에 병합하되 **`sanitizeValue`를 태우지 않는다**(공백·중괄호라 통과 못 한다 — 그게 셸 조각 부류다). 템플릿이나 claude 입력이 `{cd}`를 쓰는데 `repo`가 없으면 `Variable {repo} not provided`로 거부한다. **red**: `RequestTests`에 — 확장이 보낸 `cd` 거부 / 미설정 시 바이트 동일 / 설정 시 오라클 치환 / `repo` 없이 `{cd}` 사용 시 거부 / claude 입력에서도 치환(결정 6) / 잘못된 base dir은 던짐(결정 4) | agreed | `Request.swift:13-76`(`resolveRequest(_:baseDirectory:)`)·`:78-100`(`appProvidedVariables`), `CommandRenderer.swift:71-83`(`appVariables`는 `sanitizeValue` 미적용). red: `CoreTests.swift:310:52: error: extra argument 'baseDirectory' in call`. **red가 실제 버그를 잡았다**: 조립을 이름 충돌 검사보다 먼저 하면 `{"cd":…}` 요청이 `Variable {repo} not provided`로 거부돼(`CoreTests.swift:323: XCTAssertEqual failed: ("Variable {repo} not provided") is not equal to ("Unknown variable: {cd}")`) 진짜 사유가 가려진다 → `Request.swift:85-88`에 순서 보장 guard 추가. green: `swift test` → `Executed 206 tests, with 0 failures`(기준 180 + 신규 26) | R1 |
| 4 | **App: `Settings.baseDirectory` + `HostServer` 배선.** `UserDefaults` 키 `baseDirectory`, 앱은 **문자열을 보관만** 한다(검증·정규화·조립은 전부 Core). `HostServer.serve`(`:96-112`)가 `handleRequest(json:baseDirectory:)`로 넘긴다. App 타깃에는 테스트가 없으므로 **로직을 여기 두지 않는다** — 이 항목은 배선 한두 줄로 유지하는 것이 요구사항이다. **red**: 항목 8의 e2e 케이스 + 수기 검증 | agreed | `Settings.swift:21-28`(저장만), `HostServer.swift:96-99`(`handleRequest(json:baseDirectory:)` 한 줄). App에는 **자체 검증기도 조립 로직도 없다 — Core 함수를 부르기만 한다**(R3 정정, Codex P2-1: 종전 근거 "grep → 0건"은 부정확했다. 항목 5·6에서 `SetupWindowController`가 `normalizedBaseDirectory`를 3곳에서 호출한다 — `:668`·`:702`·`:825`. 전부 Core 호출이고 판정 로직의 사본은 아니다). `app/build.sh` → `Build complete!`, `app/e2e.sh` → `PASS` 9건 `e2e 전체 통과` | R1 |
| 5 | **Core+App: `z` 임계도 판정.** `SetupWindowController.toolAdvice`(`:39-53`)의 `z`가 base dir 설정 여부에 따라 오류↔경고로 갈리고 조언 문구도 갈린다. 판정은 Core의 순수 함수로 뽑아 테스트한다. **red**: `ToolCheckTests`에 2건(base dir 있음 → z는 경고 / 없음 → 오류) | agreed | Core: `ToolChecker.swift:11-20`(`toolIsCritical`). red: `cannot find 'toolIsCritical' in scope`. green: `swift test --filter ToolCheckTests` → `Executed 8 tests, with 0 failures`(기준 6). App 배선: `SetupWindowController.swift:42-68`(`toolAdvice`가 상수→함수, z 문구가 갈린다), 호출부 `:694-695`. 판정은 Core가 정본이고 App에는 문구만 있다. 저장값이 손상돼 정규화가 실패하면 폴백이 못 도므로 `configured=false`(z는 다시 오류)로 접는다 — `:694`. gh 문구에도 clone 단계를 더했다(`:60-64`) | R1 |
| 6 | **App: 설정 창 「저장소 기본 폴더」 카드.** 텍스트필드 + [폴더 선택…](`NSOpenPanel`) + 상태 줄(검증 실패 사유, 존재하지 않는 폴더 경고). 터미널 카드와 같은 급의 **상시 카드**로 둔다(완료되면 숨는 설치 카드가 아니다). 파이프라인 점(`pipelineNodes`)은 늘리지 않는다 — Chrome→relay→앱→터미널 경로의 홉이 아니다. 문구는 한국어. **red 없음** — 항목 9의 수기 검사 목록으로 대체 | claimed | `SetupWindowController.swift:230-256`(카드), `:140`·`:151`(터미널 카드 뒤 배치), `:650-681`(`updateBaseDirCard`), `:800-846`(`baseDirectoryReason`·`baseDirectoryEdited`·`chooseBaseDirectory`). `./app/build.sh` → `Build complete!` 경고 없음. 저장은 정규화된 값으로(`~` 펼침·후행 슬래시 제거) 하고 필드에 되돌려 써 "실제로 도는 값"을 보여 준다. 검증 실패는 **저장하지 않고** 사유만 띄운다(입력 시점 거부 — 결정 4의 손상된 저장값 갈래는 `:658-668`이 따로 처리). 없는 폴더는 경고+저장(결정 5). 파이프라인 점은 늘리지 않았다. **미검증**: 실제 창을 띄운 시각·조작 확인은 하지 않았다 — GUI 기동이 `Installer.autoSetup()`을 돌려 사용자의 살아 있는 Native Host manifest를 이 워크트리 빌드로 덮어쓰기 때문(`Installer.swift`의 `autoSetup`). 아래 수기 검사 목록으로 넘긴다 | R1 |
| 7 | **Extension: 프리셋 11개 + `DEFAULT_*` 3세트를 `{cd}`로.** `extension/defaults.js`에서만. `BUTTON_KINDS[*].variables`의 뜻("확장이 실제로 넘기는 것")은 지키고, 앱 제공 변수는 별도 상수(`APP_VARIABLES = ['cd']`)로 둔다. **red**: `tests/buttons.test.js` — (a) 기존 `the default repository button only moves to the repo`(`:97-101`)가 `'z {repo}'`를 고정하고 있어 **의도적으로 깨진다**. 새 기대값으로 갱신하고 왜 바꾸는지 주석을 남긴다. (b) 신규: 모든 프리셋의 `command`가 `{cd}`로 시작한다(맨 앞 `z {repo}`가 다시 새어 들어오는 것을 막는 회귀 방지). (c) 변수 검사(`:86-95`)가 `variables ∪ APP_VARIABLES`로 판정 | agreed | `extension/defaults.js:6-10`(설명), `:104-109`(`APP_VARIABLES = ['cd']`), 프리셋 11개 전부 `{cd}`로 시작(`grep -n "command: " extension/defaults.js` → 11줄 모두 `'{cd}`). red: `ReferenceError: APP_VARIABLES is not defined`. green: `node --test` → `# tests 24 / # pass 24 / # fail 0`(기준 22 — 같은 명령을 294c46a 사본에서 실행해 대조). 신규 회귀 테스트 2건: `every preset enters the repository through {cd}`, `app-provided variables are not in any page's variable list`. `:100`의 `'z {repo}'` 고정은 `'{cd}'`로 갱신하고 이유를 주석에 남겼다 | R1 |
| 8 | **e2e: 확장이 보낸 `cd` 거부.** `app/e2e.sh`에 결정적 케이스 1건(`{"command_template":"{cd}","variables":{"cd":"x"}}` → `Unknown variable: {cd}`). 개발자 머신의 `UserDefaults`에 의존하는 케이스는 넣지 않는다 | agreed | `app/e2e.sh:77-83`. `./app/build.sh && ./app/e2e.sh` → `PASS: app-provided variable cannot come from the extension` 포함 9건 전부 PASS, `e2e 전체 통과`. 이름 거부는 변수 검증 단계에서 나므로 base dir 설정값과 무관하다 | R1 |
| 9 | **문서·잔여 표면.** `README.md`(요구사항의 zoxide 위상, 설치 1단계, 변수 표에 `{cd}` 행 + 값의 출처가 앱이라는 표시, 사용법 코드블록 2곳, 트러블슈팅에 `zoxide: no match found` 항목), `docs/new-terminal-checklist.md`(아래 3개 실행 경로 추가), `install.sh:41-43` 경고 문구, `extension/options.html`의 변수 도움말 3곳과 `options.js:105` placeholder, `CLAUDE.md`(base dir 정본성·셸 조각 변수 경계·R0 실측 + **Working principles 절을 메인 체크아웃과 같은 문구로 반영** — 이 브랜치의 `CLAUDE.md`에는 아직 없다. 정본은 `/Users/choongjaelee/Codes/terminal-checkout/CLAUDE.md:5`). **코드 파일 주석 2건(`app/Sources/Core/WarpControl.swift:78`, `app/Tests/CoreTests/CoreTests.swift:1162`)은 판정 라운드로 이월** — Codex가 R1 커밋의 그 파일들을 읽는 중이라 검증 대상과 워킹트리를 갈라 놓지 않는다 | agreed | R2에서 **문서만** 수정(코드·테스트 0건). `README.md`: 요구사항 `:40-43`, 설치 1단계 재작성 `:47-65`, UI 라벨 매핑 `:79`, 설정 창 4단계 신설 `:92`·마무리 문장 `:95`, Updating 안내 `:112`(R0 결정 8), PR 코드블록 `:120-124`, 저장소 버튼 `:142`, **신설 「Getting into the repository」 `:163-176`**(폴백 표·콜드 DB 서술·앱 소유 이유), 변수 표 `{cd}` 행 `:182`, 변수 주석 `:191`, 트러블슈팅 신설 `:225` + 기존 z 항목 보강 `:227`. `docs/new-terminal-checklist.md`: 실행 경로 3건 `:61-63`, payload `:105` + 설명 `:107`. `CLAUDE.md`: Working principles `:5`(메인과 `diff` 동일 확인), base dir 정본성 `:45`, 셸 조각 경계+실측 `:46`, ToolChecker 항목에 임계도 한 줄 `:47`. `install.sh:41-45`. `extension/options.html`: 헤더 `:306`, 변수 도움말 3곳 `:313`·`:325`·`:337`, 프리셋 설명 `:314`. `extension/options.js:105`. 게이트 3종 재실행 그린 | R2 |

| 10 | **판정 라운드(R3): Codex P2 권고 4건 + 이월 2건.** ① **P2-1 타입 경계** — `renderCommand(appVariables:)`가 public이라 "앱 조립값만"을 타입으로 강제하지 못한다. 조각 오버로드를 `internal`로 내리고 public 표면은 `renderCommand(template:variables:)`만 남긴다(공개 API를 되넓히지 않는다). ② **P2-2 정본 드리프트 교차 검증** — Core `repoEntryVariable` ↔ `extension/defaults.js`의 `APP_VARIABLES`. 선례 `UninstallScriptSyncTests`를 따라 Swift 테스트가 JS를 읽어 양방향 집합 일치를 고정한다. red 대신 **토글 증명**. ③ **P2-3 비문자열 저장값** — `Settings.baseDirectory`가 String 아닌 값을 "미설정"으로 접는다. 결정 4를 엄격 적용해 `String(describing:)`으로 넘겨 거부되게 한다. ④ **P2-4 항목 4 근거 정정**. ⑤ 이월: 낡은 주석 2곳(`WarpControl.swift`, `CoreTests.swift`)을 `{cd}` 기준으로 영어 갱신. ⑥ 이월: 설정 창 카드에 기존 사용자 안내 한 줄(한국어) | agreed | ① `CommandRenderer.swift:60-66`(public 얇은 래퍼)·`:68-86`(internal 오버로드, 기본값 제거로 오버로드 모호성 회피). 경계 실측: `grep -n "public func renderCommand" ` → 1건(2인자만), `appVariables:` 호출자는 `Request.swift:54`·`:60` 둘뿐, App·Relay·WarpHelper의 `renderCommand` 호출 0건. `@testable import Core`(`CoreTests.swift:2`)라 테스트는 그대로 통과 — 공개 표면을 넓히지 않았다. ② `CoreTests.swift:2081-2126`(`AppVariableSyncTests` 2건) + 헬퍼 `repoFileContents`를 파일 스코프로 올려 선례와 공유(`:2046-2057`). **토글 증명**: JS만 `goto`로 → `XCTAssertEqual failed: ("["goto"]") is not equal to ("["cd"]")`; 되돌린 뒤 Swift만 `goto`로 → `("["cd"]") is not equal to ("["goto"]")`; 양쪽 복원 후 `git diff --quiet` 확인 + `Executed 2 tests, with 0 failures`. 파서 자체도 실패할 수 있음을 `testParserRejectsWhatItCannotRead`로 고정(선언 부재·주석·복수 원소·빈 배열). ③ `Settings.swift:27-33`. **미검증** — App 타깃에 테스트가 없어 비문자열 plist 값을 실제로 넣어 보지는 않았다(배선 4줄). ④ 항목 4 근거 칸 갱신. ⑤ `WarpControl.swift:76-83`, `CoreTests.swift:1405-1407`. ⑥ `SetupWindowController.swift:254-261`(한국어 UI 문구 + 영어 주석). 게이트: swift **210/0**(기준 208 + 신규 2) · node 24/0 · e2e 9 PASS | R3 |

| 11 | **PR #32 리뷰 반영(R4): cd 절이 "저장소가 있다"의 증거가 아니다.** `z` 실패 후 `<base>/<repo>`가 빈 디렉터리·비저장소 디렉터리면 `cd`가 0을 반환해 clone 절을 건너뛰고, 프리셋 체인의 `git fetch`/`git checkout`이 그 무관한 디렉터리에서 돈다. cd 절을 `git -C <dir> rev-parse --git-dir >/dev/null && cd <dir>`로 감싸 저장소 확인 뒤에만 통과시킨다(Core `repoEntryCommand` 한 곳 — 프리셋 11개가 상속). `>/dev/null`은 stdout만 — stderr는 폴백 사유라 남긴다(결정 7 유지). **red**: 오라클 테스트(`RepoEntryCommandTests`·`RequestTests`)를 새 기대값으로 먼저 바꿔 red 확인 후 구현. `testStderrIsNotSuppressed`는 `/dev/null` 문자열 고정이 새 조각에서 깨지므로 **stderr 리다이렉션 부재** 판정으로 좁힌다 | claimed | `BaseDirectory.swift:78`(조각), `:53-63`(가드 근거·stdout/stderr 구분 주석). red 5건: `CoreTests.swift:153`·`:164`·`:173`·`:228`(RepoEntryCommandTests) + `:330`(RequestTests) — 예: `XCTAssertEqual failed: ("{ z remy \|\| cd /Users/x/Codes/remy \|\| …") is not equal to ("{ z remy \|\| { git -C /Users/x/Codes/remy rev-parse --git-dir >/dev/null && cd /Users/x/Codes/remy; } \|\| …")`. green: `swift test` → `Executed 210 tests, with 0 failures`. `testStderrIsNotSuppressed`(`:196-205`)는 `2>`·`&>` 부재 판정으로 갱신하고 이유를 주석에 남겼다. 셸 실측 3건은 R4 로그 | R4 |

의존: 1 → 2 → 3 → {4, 5}; 3 → 7 → 8; 6은 1·4 뒤; 9는 마지막; 10은 R1·R2 판정 뒤; 11은 PR #32 리뷰 판정 뒤.

`docs/new-terminal-checklist.md`에 추가할 실행 경로(CLAUDE.md가 새 실행 경로마다 요구하는 것):

- [ ] 콜드 zoxide DB(또는 zoxide 미설치) 상태에서 base dir 폴백이 저장소로 진입하고 체인의 끝까지 간다
- [ ] base dir에 아직 클론되지 않은 저장소에서 clone이 돌고, 새 클론 안에서 나머지 체인이 이어진다
- [ ] base dir 미설정일 때 실행되는 명령이 이전과 같다(터미널에 찍힌 명령 문자열로 확인)

설정 창 카드(항목 6)는 자동 검증이 없으므로 같은 목록에 넣는다 — R1에서 컴파일까지만 확인했다:

- [ ] 「저장소 기본 폴더」 카드가 터미널 카드 아래에 상시 보이고, 창 높이가 밀리지 않는다
- [ ] `~/Codes` 입력 → Enter/포커스 이탈 시 절대 경로로 펼쳐져 필드에 되돌아오고 저장된다
- [ ] [폴더 선택…] 시트로 고른 경로가 같은 경로로 저장된다
- [ ] 공백이 든 경로 입력 → 저장되지 않고 사유가 빨간 줄로 뜬다(필드의 입력은 남는다)
- [ ] 없는 폴더 입력 → 노란 경고로 저장된다
- [ ] 필드에 타이핑하는 도중 다른 창을 거쳐 돌아와도(refresh) 입력이 덮어써지지 않는다
- [ ] base dir 설정 후 z가 없는 환경에서 도구 카드의 z 줄이 빨강→노랑으로 바뀌고 문구가 갈린다

## 전수 소탕 표

"첫 절이 실패해 체인이 조용히 죽는" 부류와, 그 전제를 사실로 적어 둔 문서·문구 전체.

| 지점 | 이 부류가 성립하는가 | 확인 방법 | 판정 |
|:--|:--|:--|:--|
| `extension/defaults.js:12,16,20,24,28` (PR 프리셋 5) | 성립 — 첫 절이 `z {repo}` | `grep -n 'z {repo}' extension/defaults.js` | 구멍(항목 7) |
| `extension/defaults.js:38,48,53` (이슈 프리셋 3) | 성립 | 동일 | 구멍(항목 7) |
| `extension/defaults.js:64,68,72` (저장소 프리셋 3) | 성립 | 동일 | 구멍(항목 7) |
| `extension/defaults.js:76-89` (`DEFAULT_*` 3세트) | 성립 — 프리셋을 참조하는 파생 | 코드 읽기 | 항목 7에 자동 포함(파생) |
| `tests/buttons.test.js:100` | 성립 — 기본 command를 `'z {repo}'`로 고정 | `node --test` | 구멍(항목 7, 의도적 갱신) |
| `extension/options.js:105` (command placeholder `z {repo} && claude`) | 성립 — 새 버튼을 쓰는 사용자에게 콜드 DB 형태를 학습시킨다 | 옵션 페이지에서 빈 카드 추가 | 닫음(R2) — `{cd} && claude`로 교체 |
| `extension/options.html:313,325,337` (변수 도움말 3곳) | 성립 — `{cd}`가 없어 사용자가 알 방법이 없다 | 페이지 육안 | 닫음(R2) — 3곳 모두 `{cd}` 추가, `:314`에 프리셋 설명, `:306`에 "base folder는 앱에 있다" |
| `README.md:40,47-59` (요구사항·설치 1단계) | 성립 — zoxide를 사실상 필수로 서술, 완화책이 `:59` 한 줄 | 문서 읽기 | 닫음(R2) — zoxide/base dir 택일로 재작성(`:40-43`, `:47-65`) |
| `README.md:109-115,132` (사용법 코드블록 2곳) | 성립 — 프리셋 문자열을 그대로 인용 | 문서 읽기 | 닫음(R2) — `{cd}`로 교체(`:120`, `:142`) |
| `README.md:152-168` (변수 표) | 성립 — `{cd}` 행 없음, "값이 페이지에서 온다"는 전제도 깨진다 | 문서 읽기 | 닫음(R2) — `{cd}` 행 `:182` + 예외 명시 `:191` + 전용 절 `:163-176` |
| `README.md:198` (트러블슈팅 `z doesn't work`) | 성립 — 로그인 셸·init 문제만 다루고 `no match found`는 리포 어디에도 없다 | `grep -rn 'no match found'` → 0건 | 닫음(R2) — 전용 항목 `:225` 신설, 기존 항목 `:227` 보강 |
| `install.sh:41-43` | 성립 — zoxide 없으면 "기본 명령이 동작하지 않는다"고 단정 | 스크립트 읽기 | 닫음(R2) — Warning→Note, base dir 대안 안내(`:41-45`) |
| `app/Sources/App/SetupWindowController.swift:39-44` (`z` 조언) | 성립 — "모든 버튼이 실패합니다"가 base dir 설정 시 거짓이 된다 | 코드 읽기 | 구멍(항목 5) |
| `app/Sources/Core/ToolChecker.swift:9,23-26` (`command -v z`) | 부분 성립 — 함수 존재만 증명. DB 내용은 원리적으로 여기서 알 수 없다 | 이슈 #30 본문 | 안전(설계상 유지, 비목표) |
| `docs/new-terminal-checklist.md:61` (`z {repo}` 점프 항목) | 성립 — 폴백 경로가 검사 목록에 없다 | 문서 읽기 | 닫음(R2) — 미설정·콜드DB·미클론 3갈래로 분리(`:61-63`) |
| `docs/new-terminal-checklist.md:103` (검증 payload 예시) | 성립(경미) — 예시 템플릿이 `z {repo} && claude` | 문서 읽기 | 닫음(R2) — `{cd} && claude`로 교체하고 owner 추가(`:105`), 거부 사례 설명 `:107` |
| `app/Sources/Core/WarpControl.swift:78`, `app/Tests/CoreTests/CoreTests.swift:1162` (주석 "이동은 `z {repo}`가 한다") | 성립(문서) — 진입 수단이 바뀌면 낡는다 | `grep -n 'z {repo}'` | **열림 — 판정 라운드로 이월**(R2 범위 제외: Codex가 R1 커밋의 이 파일들을 읽는 중) |
| `app/e2e.sh:44,48,61,65` (payload의 `z {repo}`) | 성립 안 함 — 오류 경로 payload라 셸에서 실행되지 않는다 | 스크립트 읽기 | 안전 |
| `app/Tests/CoreTests/CoreTests.swift` 렌더 테스트의 `z {repo}` 다수 | 성립 안 함 — 임의의 템플릿 예시일 뿐 | 테스트 읽기 | 안전 |
| `extension/manifest.json:5` (description) | 성립 안 함 — `z` 언급 없음 | `grep -n description` | 안전 |
| `claude_inputs` 안의 `{cd}` | 성립 안 함 — 균일 치환하되 재료가 전부 검증된 값이고, claude 입력은 자유 텍스트 계약 | R0 결정 6 | 안전(결정 6) |
| `background.js`/`content.js`의 변수 조립부 | 성립 안 함 — 확장은 `cd`를 만들지도 보내지도 않는다(그것이 설계) | `background.js:191-204,219-224,239` | 안전 |

## 라운드 로그

### R0 — `294c46a` (계획 초안)

- 차단: 없음(구현 전). 확정 방향은 옵션 1+1a로 고정, 세부 설계는 아래 실측 위에서 판단.
- 조사: `extension/defaults.js` 전문, `Core/{CommandRenderer,Request,ToolChecker,TerminalRunner,Terminal,Paths}.swift`, `App/{Settings,HostServer,SetupWindowController}.swift`, `extension/{background,content,options}.js`, `extension/options.html`, `tests/buttons.test.js`, `app/e2e.sh`, `install.sh`, `docs/new-terminal-checklist.md`, 이슈 #29·#30 본문.
- 실측(zsh 5.9 / zoxide 0.9.9 / git on macOS 25.4.0):
  - 빈 `_ZO_DATA_DIR`에서 `zsh -f -c 'eval "$(zoxide init zsh)"; z totallynotarepo1234'` → stderr `zoxide: no match found`, **exit 1**
  - `z`가 아예 없을 때 → `zsh:1: command not found: z`, **exit 127**
  - `z X || cd /tmp` → 두 경우 모두 `cd`로 넘어가 `PWD=/tmp` (한 갈래가 콜드 DB와 미설치를 동시에 덮는다)
  - `git clone <url> <base>/a/b/c/repo` (중간 디렉터리 전부 부재) → **exit 0**, 경로가 생성됨 → 조각에 `mkdir -p`가 필요 없다
  - `{ z R || cd B/R || { git clone U B/R && cd B/R; }; } && print OK` 3경로 실측: (z 실패+dir 없음) clone→cd→OK, (z 실패+dir 있음) cd→OK, (z 성공) clone 그룹 건너뛰고 OK
  - `false || false || print C && print D` → `C` `D` — `&&`/`||` 동일 우선순위·좌결합이라 그룹 없이도 꼬리 `&&`가 붙지만, 사용자가 `{cd}`를 어디에 놓든 안전하도록 조각 전체를 `{ …; }`로 감싼다
- 판정: 미요청(검증자 스레드 미기동).

### R1 — 워킹트리(미커밋, base `294c46a`)

- 범위: 항목 1∼8. 항목 9(문서)는 다음 라운드.
- 차단: 없음. 다만 red가 실제 결함 1건을 잡았다 — 앱 변수 이름 충돌 검사가 조각 조립보다 뒤에 있으면 `{"cd": …}`를 보낸 요청이 `Variable {repo} not provided`로 거부돼 진짜 사유(이름 충돌)가 가려진다. `Request.swift:78-84`에 순서 보장 guard로 수정.
- 수정: 재사용한 함수는 `sanitizeValue` 하나 — base dir 검증(`normalizedBaseDirectory`)도, 조각 재료 재확인(`repoEntryCommand`)도 같은 함수를 부른다. 두 번째 검증기는 만들지 않았다.
- 실측: `swift test` 208/0(기준 180 + 신규 28), `node --test` 24/0(기준 22 — 294c46a 사본에서 같은 명령으로 대조), `app/e2e.sh` PASS 9건.
- 언어 규칙 개정 반영: 이 브랜치가 새로 쓴 한국어 주석을 전부 영어로 교체했다. 확인 명령 `git diff -U0 -- app extension tests | grep '^+' | grep -E '^\+\s*(//|///|#)' | grep -P '[\x{AC00}-\x{D7A3}]'` → 출력 없음. 남은 한글 추가 줄은 설정 창 UI 문구(#24가 정본)와 화이트리스트 거부를 검증하는 테스트 픽스처 `"/Users/x/코드"`뿐이다.
- 드라이버 대조: 게이트 3종 직접 재실행(swift 208/0 · node 24/24 · e2e 9 PASS). 표본 — `BaseDirectory.swift` 전문(조각 오라클·재료 재검증·`{ }` 그룹), `Request.swift`·`CommandRenderer.swift`·`HostServer.swift`·`e2e.sh` diff(이름 충돌은 조립 전 거부, 조각만 sanitize 면제, 치환 결과 재스캔 없음, App에 로직 없음), 프리셋 11개 `{cd}` 시작 grep, 추가 주석 한글 0건 grep. 항목 1∼5·7·8 → `verified`. 항목 6은 시각 검증 불가(GUI 기동이 살아 있는 Native Host manifest를 덮음)로 `claimed` 유지 — 수기 검사 목록으로 이월.
- 판정(Codex, 스레드 `01a023c2-8afe-7de1-b755-489ec6b5bc6d`): **"`yes` — `5e77163`의 R1 코드에는 고위험 명령 주입이나 `{cd}` 우회가 없습니다. 다만 아래 P2 수준의 유지보수 위험은 남아 있습니다."** 불변 원칙 4종(미설정 바이트 동일·확장 `{cd}` 거부·화이트리스트 단일·App 분리) 전부 "통과" 판정. 우리가 노출한 판단 6건에 반박 없음. P2 지적: ① 항목 4 근거의 "App 검색 0건"은 부정확(SetupWindowController가 Core 검증기를 호출 — 별도 검증기는 아님) ② `renderCommand(appVariables:)`가 public이라 "앱 조립값만"을 타입으로 강제하지 않음 ③ Core `repoEntryVariable` ↔ JS `APP_VARIABLES` 교차 검증 테스트 부재(정본 드리프트) ④ `Settings.baseDirectory`가 비문자열 저장값을 "미설정"으로 접음(결정 4의 엄격 적용이면 보강 대상) ⑤ base dir의 `..`·중복 슬래시 허용(주입은 아님 — containment 요구 시 별도 보강). Codex 환경 실측: node 24/24·신규 Core 55/55·release build 통과, Swift 6건 실패와 e2e 미기동은 샌드박스의 소켓 bind 제한(변경 파일과 무관 — 드라이버 로컬에서는 전부 그린).

### R2 — 워킹트리(미커밋, base `5e77163`)

- 범위: 항목 9의 **문서분만**. 코드 파일 주석 2건(`WarpControl.swift:78`, `CoreTests.swift:1162`)은 Codex가 R1 커밋의 그 파일들을 읽는 중이라 판정 라운드로 이월했다. `git diff --name-only`에 `app/Sources`·`app/Tests`·`extension/defaults.js`·`tests/` 0건 — 검증 대상과 워킹트리가 갈리지 않는다.
- 수정: `README.md`·`docs/new-terminal-checklist.md`·`CLAUDE.md`·`install.sh`·`extension/options.html`·`extension/options.js`(placeholder 한 줄). 소탕 표의 항목 9 행 9개를 「닫음(R2)」으로 갱신했고, 주석 2건 행만 「열림 — 판정 라운드로 이월」로 남겼다.
- 설계 판단: `{cd}`를 README에 세 번 설명하는 대신 「Getting into the repository」 절 하나를 만들고 요구사항·설치·변수 표·트러블슈팅이 앵커로 가리키게 했다(리포의 Documentation principle — 같은 사실을 여러 곳에 두지 않는다). 설정 창 4단계 항목의 버튼 이름은 README의 기존 관례대로 영어로 쓰고 `:79`의 한국어 라벨 매핑 표에 2건(`Repository base folder`, `Choose Folder…`)을 추가했다.
- **발견(판정 라운드 처리 대상)**: R0 결정 8의 "설정 창 base dir 카드 설명 문구"에 **기존 사용자 안내가 없다**. `SetupWindowController.swift:245-253`의 문구는 base dir이 무엇인지와 "비워 두면 지금까지와 같다"까지만 말하고, 저장된 버튼이 옛 command를 유지하므로 옵션 페이지에서 프리셋을 다시 적용해야 `{cd}`로 옮겨진다는 사실은 없다. 이번 라운드는 코드 파일을 건드리지 않으므로 기록만 한다. README 쪽 대응은 `:112`에 들어갔다.
- 실측: `swift test` 208/0 · `node --test` 24/0 · `bash -n install.sh` OK · `app/build.sh` + `app/e2e.sh` PASS 9건. 문서만 바꿨어도 회귀 확인차 3종 전부 재실행했다. 마크다운 위험 점검 — 백틱 밖의 `<base>`/`<repo>` 0건(HTML 태그로 렌더되지 않음), 앵커 `#getting-into-the-repository` 링크 6곳에 대상 헤딩 1개 존재.
- 판정: 미요청(R1 판정 대기 중). → 이후 R2는 드라이버 대조 후 `a76351a`로 커밋, 항목 9 `verified`.

### R3 — 워킹트리(미커밋, base `a76351a`) · 판정 라운드

- 차단: 없음. Codex R1 판정이 **합의(yes)**라 P0/P1은 없고, P2 권고 4건 + R2 이월 2건을 항목 10으로 묶어 처리했다.
- 수정: ① 조각 오버로드를 `internal`로 내려 public 표면을 `renderCommand(template:variables:)` 하나로 줄였다. 타입으로 "앱 조립값만"을 표현할 수 없다는 Codex 지적이 맞으므로, **모듈 경계가 그 역할을 진다**는 것을 함수 주석에 명시했다(`CommandRenderer.swift:68-86`). 내부 오버로드에서 기본값 `= [:]`를 뺀 것은 두 오버로드가 2인자 호출에서 모호해지기 때문이다. ② 교차 검증 테스트는 선례(`UninstallScriptSyncTests`)의 `#filePath` 방식을 그대로 쓰되, 헬퍼 `repoFileContents`를 파일 스코프로 올려 **한 벌만** 두었다(사본을 만들면 이 라운드가 고치려는 드리프트를 테스트 쪽에 새로 만드는 셈이다). ③ `Settings.baseDirectory`가 `object(forKey:)`로 읽어 String이 아니면 `String(describing:)`으로 넘긴다. ⑤⑥ 이월 2건.
- 실측: 게이트 3종 — `swift test` **210/0**(기준 208 + 신규 2), `node --test` 24/0, `app/build.sh` + `app/e2e.sh` PASS 9건. P2-1 경계 실측 — `public func renderCommand` 1건(2인자만), `appVariables:` 호출자 `Request.swift:54`·`:60` 둘뿐, App·Relay·WarpHelper에서 `renderCommand` 호출 0건. P2-2 토글 증명 — 양방향 각각 실패 출력 확보 후 복원(`git diff --quiet` 통과).
- **미검증**: P2-3은 App 타깃에 테스트가 없어 비문자열 plist 값을 실제로 넣어 확인하지 않았다. 컴파일과 코드 읽기까지다.
- **기각 1건(Codex P2-5, 고치지 않음)**: base dir의 `..`·중복 슬래시를 containment로 막으라는 권고. base dir은 **same-uid 사용자가 자기 기계의 자기 앱에 직접 입력하는 값**이라 넘을 권한 경계가 없다 — `..`로 갈 수 있는 곳은 그 사용자가 `cd`로도 갈 수 있는 곳이고, 앱의 신뢰 경계는 이미 uid다(`SECURITY.md`, Warp 헬퍼와 같은 선언). 지킬 대상이 없는 검증은 오탐만 만든다(`../` 를 실제로 쓰는 레이아웃을 막는다). **재검토 트리거**: base dir 값이 덜 신뢰된 소스에서 오게 되면 — 확장·URL 스킴·가져오기 파일·MDM 프로파일 등 사용자 타이핑이 아닌 경로가 생기거나, 앱이 그 경로에 대해 사용자 대신 파괴적 동작(삭제·덮어쓰기)을 하게 되는 순간. 그때는 containment가 지킬 대상이 생긴다.
- 판정: 미요청(드라이버가 다음 검증 요청에 이 기각 반증을 함께 싣는다).

## 열린 질문

(없음 — R0의 8건은 아래 「R0 결정」으로 전부 닫혔다)

## R0 결정 (드라이버 승인, 2026-08-21)

1. **변수 이름은 `{cd}`로 확정.** 값 변수(명사)와 구별되는 동사형 이름이 "셸 조각" 부류임을 드러낸다. 원시 경로 변수 `{basedir}`는 이번에 노출하지 않는다 — 새 표면(문서·테스트·미설정 거부 의미론)이 배로 늘고, 직접 체인을 짜는 사용자는 자기 경로를 리터럴로 쓰면 된다.
2. **clone은 `gh repo clone {owner}/{repo} <B/R>`.** 프로토콜·인증을 gh 설정에 위임해 private 저장소와 SSH/HTTPS 취향을 모두 덮는다. gh는 이미 `checkedTools`에 있어 새 검사 표면이 없다. gh 부재 시 clone 절만 화면에 보이며 실패한다(z·cd 폴백은 gh 없이 동작).
3. **clone은 무조건 붙인다(옵트인 체크박스 없음).** Slack 합의안 1a 그대로. 트리거는 "z 실패 + base dir에도 없음"뿐이고, 명령이 화면에 보이며 Ctrl+C로 끊을 수 있다.
4. **저장된 base dir 검증 실패 시 (a) 렌더에서 던져 버튼이 사유와 함께 실패한다.** 리포 철학(보이는 실패 > 조용한 폴백, `{base}`의 무-폴백 선례) 그대로.
5. **존재하지 않는 폴더는 경고하되 저장은 허용.** clone이 중간 디렉터리를 만들므로(R0 실측) 동작 자체는 하고, 오타의 결과(재클론)도 화면에 보인다. 저장 거부는 "나중에 만들 폴더" 워크플로를 막는다.
6. **`claude_inputs`에서도 균일 치환한다.** README:164의 약속과 단일 코드 경로를 유지한다. 조각의 재료가 전부 검증된 값이라 새 주입면이 아니고, claude 입력은 어차피 자유 텍스트다. 소탕 표의 해당 행은 이 결정으로 닫는다.
7. **stderr는 숨기지 않는다(`2>/dev/null` 금지).** 폴백 2줄은 무슨 일이 일어났는지 설명해 주고, 숨기면 진짜 실패(권한 등)까지 같이 사라진다 — "보이는 잔재가 조용한 삭제보다 낫다".
8. **알림은 README Updating 절 한 줄 + 설정 창 base dir 카드 설명 문구까지만.** 옵션 페이지 배너는 만들지 않는다(범위).

추가 제약(드라이버): **`{cd}` 조각 조립은 Core 안에서, sanitize를 통과한 값으로만 한다.** HostServer는 base dir 문자열만 넘기고 조각을 만들지 않는다 — App에 로직을 두지 않는다는 항목 4의 요구와, "조각 재료는 검증된 값뿐"이라는 불변 원칙이 같은 자리에서 지켜지게 한다.

### R3 재검증 — `f870f26` (종결)

- 판정(Codex, 같은 스레드): **"판정: yes. `f870f26` 기준으로 P0/P1 및 잔여 P2 차단 사유는 없습니다."** P2 4건 처리 확인(공개 표면 2인자 1개·동기화 테스트 양방향·비문자열 구분 전달·항목 4 정정이 코드와 일치), 신규 표면 우회 없음("치환 결과를 재스캔하지 않고, `{cd}`의 이중 치환 경로도 없습니다").
- 기각 수용: **"`..` containment 기각도 수용합니다."** — "containment는 보안 경계라기보다 경로 정책이 되고, 정당한 레이아웃을 오탐할 수 있습니다. 계획서의 재검토 트리거도 충분합니다."
- 비차단 잔여(수정하지 않음, 트리거만 기록): `AppVariableSyncTests`의 정규식 파서는 주석 안의 완전한 가짜 `APP_VARIABLES = […]` 선언도 읽을 수 있다 — 현재 드리프트도 런타임 우회도 아니고, 고치려면 테스트에 JS 파서를 들여야 해 비례가 맞지 않는다. 재검토 트리거: defaults.js에 `APP_VARIABLES` 텍스트를 담은 주석이 생기거나 선언 형식이 바뀌어 파서가 어긋나는 순간(그때는 테스트가 실패로 드러난다).
- 검증자 실측: 표적 Swift 36/0, node 24/24 (e2e는 샌드박스 제한으로 드라이버 실측 인용).

### R4 — 워킹트리(미커밋, base `ef42cf9`) · PR #32 리뷰 반영

- 차단: Codex가 PR #32에 인라인 게시한 P2 1건(`BaseDirectory.swift:70`), 드라이버가 실측 재현해 **반영** 판정. 요지: 조각이 `cd`의 성공을 "요청한 저장소가 있다"의 증거로 취급한다 — `z` 실패 후 `<base>/<repo>`가 빈 디렉터리·비저장소 디렉터리면 `cd`가 0을 반환해 clone 절이 건너뛰어지고, 이후 `git fetch`/`git checkout`이 그 무관한 디렉터리에서 돈다.
- 수정: cd 절을 `{ git -C <dir> rev-parse --git-dir >/dev/null && cd <dir>; }`로 감쌌다. **Core `repoEntryCommand` 한 곳**만 고쳐 프리셋 11개가 그대로 상속한다 — 조각을 앱이 조립하도록 설계한 이유가 여기서 값을 한다. `>/dev/null`은 **stdout만** 버린다(성공 시 `.git` 경로 한 줄). stderr는 그대로라 결정 7이 유지된다.
- 실측(구현 에이전트 독립 재현, zsh -f + 로컬 bare 저장소):
  - ① 무방비 조각 + 빈 `<base>/<repo>` → `pwd`가 그 빈 디렉터리, `git rev-parse` → `fatal: not a git repository (or any of the parent directories): .git`, **clone 절 미도달**
  - ② 가드 조각 + 같은 빈 디렉터리 → stderr에 `fatal: not a git repository …` 뒤 `CLONE CLAUSE REACHED`, `cd` 미실행(`pwd` 불변)
  - ③ `git clone`은 기존 **빈** 디렉터리로 exit 0, 비어 있지 않으면 `fatal: destination path '…' already exists and is not an empty directory.` exit 128 — **가시 실패**이고 기존 내용을 건드리지 않는다
- 테스트: red를 먼저 만들었다 — 오라클 5건(`CoreTests.swift:153`·`:164`·`:173`·`:228`·`:330`)을 새 기대값으로 바꿔 `Executed 10 tests, with 4 failures` + `Executed 17 tests, with 1 failure` 확인 후 구현 → 210/0. 셸 동작 자체(빈 디렉터리 → clone 도달)는 Swift로 고정할 수 없어 위 실측이 유일한 근거다.
- **남기는 것(수정하지 않음)**: `<base>/<repo>`가 이름만 같은 **다른 git 저장소**면 가드를 통과해 그 저장소에서 체인이 돈다. `z`의 퍼지 점프가 갖는 동일 부류(기존 동작)이고, base dir의 계약("저장소들을 클론해 두는 폴더")상 그 이름의 디렉터리가 다른 저장소인 것은 사용자 자신의 레이아웃 위반이며, 완전한 정체 확인(remote URL 대조)은 무겁고 부서지기 쉽다. **재검토 트리거**: 체인이 파괴적 동작(삭제·강제 덮어쓰기)을 갖게 되거나, base dir이 사용자 타이핑 밖(확장·URL 스킴·가져오기 파일·MDM)에서 오게 되는 순간.
- 문서 동기화: `README.md:170`(표) + `:176`(가드 문단 신설), `docs/new-terminal-checklist.md:64`(비저장소 디렉터리 실행 경로), `CLAUDE.md:47`(가드 불릿 신설 — 남기는 것과 트리거 포함). 과거 라운드 근거 칸의 옛 오라클 인용은 역사이므로 손대지 않았다.
- 판정: 미요청.
