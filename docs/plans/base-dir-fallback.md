# base-dir-fallback

- 대상: `/Users/choongjaelee/Codes/terminal-checkout-base-dir-fallback` (브랜치 `base-dir-fallback`)
- 시작 커밋: `294c46a`
- 현재: R1 커밋(항목 1∼8) · 게이트 3종 그린(드라이버 재실행 — swift 208/0, node 24/24, e2e 9 PASS) · Codex R1 검증 진행 중 · 병행: 항목 9(문서)
- 최근 검증자 판정: 미요청

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
| 1 | **Core: base dir 검증·정규화 단일 함수.** `~` 확장 → 절대경로 요구 → 후행 `/` 제거 → 기존 `sanitizeValue`와 **같은** 문자 판정. `sanitizeValue`를 `public`으로 올리거나 얇은 공개 래퍼 하나만 만든다(두 번째 검증기 금지). 빈 문자열 = 미설정. **red**: `app/Tests/CoreTests/CoreTests.swift`에 `BaseDirectoryTests` 신설 — `/Users/x/Codes` 통과 / `~/Codes` 확장 / 공백·`;`·`$`·한글 거부 / 상대경로 거부 / 후행 슬래시 정규화 / 빈 값은 오류가 아니라 미설정 | verified | `app/Sources/Core/BaseDirectory.swift:20-41` (`normalizedBaseDirectory`), `sanitizeValue`는 `CommandRenderer.swift:45-47`에서 `private`→모듈 내부로만 열었다(두 번째 검증기 없음). red: `swift test` → `CoreTests.swift:103:28: error: cannot find 'normalizedBaseDirectory' in scope`. green: `swift test --filter BaseDirectoryTests` → `Executed 8 tests, with 0 failures`. 개행은 트림하지 않아 `/Users/x/Codes\n`이 화이트리스트에 걸린다(파이썬 시절 `$` 구멍 재발 방지) | R1 |
| 2 | **Core: 진입 조각 조립 함수** `repoEntryCommand(repo:owner:baseDir:)`. 위 표대로 조립. 그룹은 `{ …; }`만. **red**: `BaseDirectoryTests`에 오라클 테스트 — 미설정 시 `"z \(repo)"`와 문자열 동등 / 설정 시 `z`가 첫 절 / 결과에 `(` 미포함 / owner 부재 시 clone 절 부재 / base dir이 검증에 실패하면 던진다 | verified | `app/Sources/Core/BaseDirectory.swift:59-74` (`repoEntryCommand`). red: `CoreTests.swift:139:17: error: cannot find 'repoEntryCommand' in scope`. green: `swift test --filter RepoEntryCommandTests` → `Executed 10 tests, with 0 failures`. 오라클: `{ z remy \|\| cd /Users/x/Codes/remy \|\| { gh repo clone frograms/remy /Users/x/Codes/remy && cd /Users/x/Codes/remy; }; }`. 재료(repo·owner)를 조립 지점에서 다시 `sanitizeValue`에 태운다 — 결과만이 면제 대상 | R1 |
| 3 | **Core: `{cd}` 주입 경로.** `resolveRequest(_:baseDirectory:)`(기본값 `""` = 미설정) 추가 — 앱은 **base dir 문자열 하나만** 넘기고, 조각 조립은 Core 안에서 항목 2의 함수가 한다(드라이버 추가 제약). 요청의 `variables`는 지금처럼 `allowedVariables`로만 검증하고(→ 확장이 `cd`를 보내면 `Unknown variable: {cd}`), 앱이 조립한 값은 그 뒤에 병합하되 **`sanitizeValue`를 태우지 않는다**(공백·중괄호라 통과 못 한다 — 그게 셸 조각 부류다). 템플릿이나 claude 입력이 `{cd}`를 쓰는데 `repo`가 없으면 `Variable {repo} not provided`로 거부한다. **red**: `RequestTests`에 — 확장이 보낸 `cd` 거부 / 미설정 시 바이트 동일 / 설정 시 오라클 치환 / `repo` 없이 `{cd}` 사용 시 거부 / claude 입력에서도 치환(결정 6) / 잘못된 base dir은 던짐(결정 4) | verified | `Request.swift:13-76`(`resolveRequest(_:baseDirectory:)`)·`:78-100`(`appProvidedVariables`), `CommandRenderer.swift:71-83`(`appVariables`는 `sanitizeValue` 미적용). red: `CoreTests.swift:310:52: error: extra argument 'baseDirectory' in call`. **red가 실제 버그를 잡았다**: 조립을 이름 충돌 검사보다 먼저 하면 `{"cd":…}` 요청이 `Variable {repo} not provided`로 거부돼(`CoreTests.swift:323: XCTAssertEqual failed: ("Variable {repo} not provided") is not equal to ("Unknown variable: {cd}")`) 진짜 사유가 가려진다 → `Request.swift:85-88`에 순서 보장 guard 추가. green: `swift test` → `Executed 206 tests, with 0 failures`(기준 180 + 신규 26) | R1 |
| 4 | **App: `Settings.baseDirectory` + `HostServer` 배선.** `UserDefaults` 키 `baseDirectory`, 앱은 **문자열을 보관만** 한다(검증·정규화·조립은 전부 Core). `HostServer.serve`(`:96-112`)가 `handleRequest(json:baseDirectory:)`로 넘긴다. App 타깃에는 테스트가 없으므로 **로직을 여기 두지 않는다** — 이 항목은 배선 한두 줄로 유지하는 것이 요구사항이다. **red**: 항목 8의 e2e 케이스 + 수기 검증 | verified | `Settings.swift:21-28`(저장만), `HostServer.swift:96-99`(`handleRequest(json:baseDirectory:)` 한 줄). App에는 검증도 조립도 없다 — `grep -n 'normalizedBaseDirectory\|repoEntryCommand' app/Sources/App` → 0건. `app/build.sh` → `Build complete! (14.12s)`, `app/e2e.sh` → `PASS` 9건 `e2e 전체 통과` | R1 |
| 5 | **Core+App: `z` 임계도 판정.** `SetupWindowController.toolAdvice`(`:39-53`)의 `z`가 base dir 설정 여부에 따라 오류↔경고로 갈리고 조언 문구도 갈린다. 판정은 Core의 순수 함수로 뽑아 테스트한다. **red**: `ToolCheckTests`에 2건(base dir 있음 → z는 경고 / 없음 → 오류) | verified | Core: `ToolChecker.swift:11-20`(`toolIsCritical`). red: `cannot find 'toolIsCritical' in scope`. green: `swift test --filter ToolCheckTests` → `Executed 8 tests, with 0 failures`(기준 6). App 배선: `SetupWindowController.swift:42-68`(`toolAdvice`가 상수→함수, z 문구가 갈린다), 호출부 `:694-695`. 판정은 Core가 정본이고 App에는 문구만 있다. 저장값이 손상돼 정규화가 실패하면 폴백이 못 도므로 `configured=false`(z는 다시 오류)로 접는다 — `:694`. gh 문구에도 clone 단계를 더했다(`:60-64`) | R1 |
| 6 | **App: 설정 창 「저장소 기본 폴더」 카드.** 텍스트필드 + [폴더 선택…](`NSOpenPanel`) + 상태 줄(검증 실패 사유, 존재하지 않는 폴더 경고). 터미널 카드와 같은 급의 **상시 카드**로 둔다(완료되면 숨는 설치 카드가 아니다). 파이프라인 점(`pipelineNodes`)은 늘리지 않는다 — Chrome→relay→앱→터미널 경로의 홉이 아니다. 문구는 한국어. **red 없음** — 항목 9의 수기 검사 목록으로 대체 | claimed | `SetupWindowController.swift:230-256`(카드), `:140`·`:151`(터미널 카드 뒤 배치), `:650-681`(`updateBaseDirCard`), `:800-846`(`baseDirectoryReason`·`baseDirectoryEdited`·`chooseBaseDirectory`). `./app/build.sh` → `Build complete!` 경고 없음. 저장은 정규화된 값으로(`~` 펼침·후행 슬래시 제거) 하고 필드에 되돌려 써 "실제로 도는 값"을 보여 준다. 검증 실패는 **저장하지 않고** 사유만 띄운다(입력 시점 거부 — 결정 4의 손상된 저장값 갈래는 `:658-668`이 따로 처리). 없는 폴더는 경고+저장(결정 5). 파이프라인 점은 늘리지 않았다. **미검증**: 실제 창을 띄운 시각·조작 확인은 하지 않았다 — GUI 기동이 `Installer.autoSetup()`을 돌려 사용자의 살아 있는 Native Host manifest를 이 워크트리 빌드로 덮어쓰기 때문(`Installer.swift`의 `autoSetup`). 아래 수기 검사 목록으로 넘긴다 | R1 |
| 7 | **Extension: 프리셋 11개 + `DEFAULT_*` 3세트를 `{cd}`로.** `extension/defaults.js`에서만. `BUTTON_KINDS[*].variables`의 뜻("확장이 실제로 넘기는 것")은 지키고, 앱 제공 변수는 별도 상수(`APP_VARIABLES = ['cd']`)로 둔다. **red**: `tests/buttons.test.js` — (a) 기존 `the default repository button only moves to the repo`(`:97-101`)가 `'z {repo}'`를 고정하고 있어 **의도적으로 깨진다**. 새 기대값으로 갱신하고 왜 바꾸는지 주석을 남긴다. (b) 신규: 모든 프리셋의 `command`가 `{cd}`로 시작한다(맨 앞 `z {repo}`가 다시 새어 들어오는 것을 막는 회귀 방지). (c) 변수 검사(`:86-95`)가 `variables ∪ APP_VARIABLES`로 판정 | verified | `extension/defaults.js:6-10`(설명), `:104-109`(`APP_VARIABLES = ['cd']`), 프리셋 11개 전부 `{cd}`로 시작(`grep -n "command: " extension/defaults.js` → 11줄 모두 `'{cd}`). red: `ReferenceError: APP_VARIABLES is not defined`. green: `node --test` → `# tests 24 / # pass 24 / # fail 0`(기준 22 — 같은 명령을 294c46a 사본에서 실행해 대조). 신규 회귀 테스트 2건: `every preset enters the repository through {cd}`, `app-provided variables are not in any page's variable list`. `:100`의 `'z {repo}'` 고정은 `'{cd}'`로 갱신하고 이유를 주석에 남겼다 | R1 |
| 8 | **e2e: 확장이 보낸 `cd` 거부.** `app/e2e.sh`에 결정적 케이스 1건(`{"command_template":"{cd}","variables":{"cd":"x"}}` → `Unknown variable: {cd}`). 개발자 머신의 `UserDefaults`에 의존하는 케이스는 넣지 않는다 | verified | `app/e2e.sh:77-83`. `./app/build.sh && ./app/e2e.sh` → `PASS: app-provided variable cannot come from the extension` 포함 9건 전부 PASS, `e2e 전체 통과`. 이름 거부는 변수 검증 단계에서 나므로 base dir 설정값과 무관하다 | R1 |
| 9 | **문서·잔여 표면.** `README.md`(요구사항의 zoxide 위상, 설치 1단계, 변수 표에 `{cd}` 행 + 값의 출처가 앱이라는 표시, 사용법 코드블록 2곳, 트러블슈팅에 `zoxide: no match found` 항목), `docs/new-terminal-checklist.md`(아래 3개 실행 경로 추가), `install.sh:41-43` 경고 문구, `extension/options.html`의 변수 도움말 3곳과 `options.js:105` placeholder, `CLAUDE.md`(base dir 정본성·셸 조각 변수 경계·R0 실측 + **Working principles 절을 메인 체크아웃과 같은 문구로 반영** — 이 브랜치의 `CLAUDE.md`에는 아직 없다. 정본은 `/Users/choongjaelee/Codes/terminal-checkout/CLAUDE.md:5`), "이동은 `z {repo}`가 한다"고 적힌 주석 2곳(`app/Sources/Core/WarpControl.swift:78`, `app/Tests/CoreTests/CoreTests.swift:1162`) | todo | | |

의존: 1 → 2 → 3 → {4, 5}; 3 → 7 → 8; 6은 1·4 뒤; 9는 마지막.

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
| `extension/options.js:105` (command placeholder `z {repo} && claude`) | 성립 — 새 버튼을 쓰는 사용자에게 콜드 DB 형태를 학습시킨다 | 옵션 페이지에서 빈 카드 추가 | 구멍(항목 9) |
| `extension/options.html:314,326,337` (변수 도움말 3곳) | 성립 — `{cd}`가 없어 사용자가 알 방법이 없다 | 페이지 육안 | 구멍(항목 9) |
| `README.md:40,47-59` (요구사항·설치 1단계) | 성립 — zoxide를 사실상 필수로 서술, 완화책이 `:59` 한 줄 | 문서 읽기 | 구멍(항목 9) |
| `README.md:109-115,132` (사용법 코드블록 2곳) | 성립 — 프리셋 문자열을 그대로 인용 | 문서 읽기 | 구멍(항목 9) |
| `README.md:152-168` (변수 표) | 성립 — `{cd}` 행 없음, "값이 페이지에서 온다"는 전제도 깨진다 | 문서 읽기 | 구멍(항목 9) |
| `README.md:198` (트러블슈팅 `z doesn't work`) | 성립 — 로그인 셸·init 문제만 다루고 `no match found`는 리포 어디에도 없다 | `grep -rn 'no match found'` → 0건 | 구멍(항목 9) |
| `install.sh:41-43` | 성립 — zoxide 없으면 "기본 명령이 동작하지 않는다"고 단정 | 스크립트 읽기 | 구멍(항목 9) |
| `app/Sources/App/SetupWindowController.swift:39-44` (`z` 조언) | 성립 — "모든 버튼이 실패합니다"가 base dir 설정 시 거짓이 된다 | 코드 읽기 | 구멍(항목 5) |
| `app/Sources/Core/ToolChecker.swift:9,23-26` (`command -v z`) | 부분 성립 — 함수 존재만 증명. DB 내용은 원리적으로 여기서 알 수 없다 | 이슈 #30 본문 | 안전(설계상 유지, 비목표) |
| `docs/new-terminal-checklist.md:61` (`z {repo}` 점프 항목) | 성립 — 폴백 경로가 검사 목록에 없다 | 문서 읽기 | 구멍(항목 9) |
| `docs/new-terminal-checklist.md:103` (검증 payload 예시) | 성립(경미) — 예시 템플릿이 `z {repo} && claude` | 문서 읽기 | 구멍(항목 9) |
| `app/Sources/Core/WarpControl.swift:78`, `app/Tests/CoreTests/CoreTests.swift:1162` (주석 "이동은 `z {repo}`가 한다") | 성립(문서) — 진입 수단이 바뀌면 낡는다 | `grep -n 'z {repo}'` | 구멍(항목 9) |
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
- 판정: 요청함(Codex R1, 커밋 직후).

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
