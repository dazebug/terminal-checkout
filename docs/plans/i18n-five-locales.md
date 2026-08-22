# i18n-five-locales

- 대상: `/Users/choongjaelee/Codes/terminal-checkout` (앱 `app/`, 확장 `extension/`)
- 시작 커밋: `92a2354`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/i18n-review` (`worktree-i18n-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/agent-ae53697e324bf1279` (`worktree-agent-ae53697e324bf1279`)
- 현재: R0 초안(사용자 결정 Q1·Q3·Q4·Q8 + 드라이버 결정 D8∼D16 반영) · 마지막 승격 없음 · 리뷰 중 없음 · 게이트 그린(swift 351/0 (1 skipped), node 158/0, e2e 9 PASS — 시작 커밋 기준 실측)
- 최근 검증자 판정: 미요청 · 원문 없음

이슈 #24 — "Localize the app's user-facing strings (en + ko)"를 사용자 요청으로 확장한 것이다. 이슈는 앱만, `en`+`ko`만 다뤘다. 사용자 요청은 **로케일 5개**(`ko`·`en`·`ja`·`zh-Hans`·`zh-Hant`)와 **확장·확장 설정 페이지까지**이고, 여기에 이슈가 "별도 추적"으로 미뤄 둔 **`app/`에 남은 한글의 영어화**가 같은 PR에 얹힌다. 축이 셋이고 서로 다른 판정을 받으므로 이 계획은 처음부터 셋을 갈라 다룬다: **로컬라이즈**(키 + 5개 카탈로그), **언어 소유권**(앱이 정하고 확장이 따른다 — D8), **영어화**(단일 언어로 번역, 키 없음).

## 목표

- 앱과 확장이 **같은 하나의 언어**로 보인다. 언어는 앱 설정 창에서 고르고(기본값 `시스템 언어를 따름`), 확장은 그 값을 앱에서 받아 그린다 — 로케일은 `ko`·`en`·`ja`·`zh-Hans`·`zh-Hant` 5개이고, 목록에 없는 언어는 **영어**로 접힌다(오늘은 한국어로 접힌다 — 실측).
- 앱이 그리는 것은 **우리 문자열도 AppKit 크롬(`NSAlert` 버튼·`NSOpenPanel`)도** 고른 언어를 따른다. 우리 문자열은 즉시, AppKit 크롬은 다음 기동에 따라오며, 그 사이를 사용자가 알 수 있다(D14).
- 키 집합·플레이스홀더가 5개 로케일 간에 어긋나면 **게이트가 red**가 된다. 런타임에 원시 키가 화면에 뜨는 경로를 정적으로 봉한다.
- 문자열 카탈로그가 세 곳(앱 `.lproj` · 확장 자체 사전 · 확장 `_locales`)에 생기지만 **같은 문장이 두 곳에 손으로 적히는 일이 게이트로 막힌다**.
- 프로토콜에 로케일이 실려도 **구버전 확장 ↔ 신버전 앱, 신버전 확장 ↔ 구버전 앱** 두 조합이 모두 지금과 같이 동작한다.
- `en` 카탈로그가 #20에서 머지된 문서(`README.md`·`install.sh`·`docs/new-terminal-checklist.md`)가 이미 인용하는 라벨과 **글자 그대로** 일치하고, 그 일치를 테스트가 고정한다.
- `app/` 아래의 한국어 주석·개발자 문자열·테스트 오라클이 영어가 된다 — 단 **실측 데이터로서의 한글**(멀티바이트 입력 픽스처)은 남는다.
- 기존 4개 게이트(`swift test` 351, `node --test` 158, `app/build.sh`, `app/e2e.sh` 9 PASS)가 **개발자 기계(ko-KR)와 CI(en) 양쪽에서** 그린이다. 로케일이 테스트 결과를 바꾸는 경로를 만들지 않는다.

## 완료의 정의

- 반드시 재현해 막아야 끝인 실패:
  - `AppleLanguages=(fr)` → 설정 창이 한국어. 실측(R0): `CFBundleDevelopmentRegion=ko`인 번들에 `fr`을 요청하면 `preferredLocalizations=["ko"]`, `en`이면 `["en"]`. 현재 `app/Info.plist:6`이 `ko`다.
  - 어느 로케일 카탈로그에 키 하나가 빠짐 → 그 언어 사용자 화면에 원시 키(`setup.card.extension`)가 그대로. 지금은 그 언어로 앱을 띄우기 전에는 아무도 모른다.
  - 앱에서 일본어를 고른 사용자가 GitHub 페이지에서는 영어 버튼을 본다 — 확장이 앱의 선택을 받지 못하는 경로.
  - 피커로 언어를 바꿨는데 `NSAlert` 버튼·`NSOpenPanel`이 옛 언어로 남고 **재시작 안내도 없다**. 실측(R0): `UserDefaults.standard`에 `AppleLanguages`를 런타임에 쓰면 같은 프로세스에는 효과가 없다 — 쓴 뒤에도 `preferredLocalizations`는 `["ko"]`, `NSAlert` 기본 버튼은 `확인` 그대로였고 readback만 `["ja"]`였다.
  - 옵션 페이지·콘텐츠 스크립트가 로케일 질의 응답을 **기다리느라** 즉시 그리지 못한다 — 앱이 없는 사용자에게는 최대 25초 빈 화면이 된다(D15).
  - **신버전 확장 ↔ 구버전 앱**: 로케일 질의에 구버전 앱은 `{"success":false,"error":"command_template is required"}`로 답한다(오늘 `app/e2e.sh:51-54`가 그 동작을 고정한다). 확장이 이 실패를 **캐시로 굳히면** 그 프로필은 영구히 잘못된 언어가 된다.
  - **구버전 확장 ↔ 신버전 앱**: 응답에 `locale` 키가 늘어난다. 구버전 `background.js`는 `response.success`만 보므로 안전해야 하고, 그것이 깨지면 모든 버튼이 죽는다(`background.js:239`).
  - 로케일을 `variables`에 실으면 `allowedVariables`에 없어 요청 **전체**가 `Unknown variable: {locale}`로 거부된다 — 명령이 통째로 죽는다.
  - 앱이 설치돼 있지 않은데 옵션 페이지를 열면 relay가 앱을 띄우려다 최대 25초(`Relay/main.swift:18`의 15초 + `:28-31`의 10초) 블로킹한다 — 그동안 옵션 페이지가 비어 있으면 안 된다.
  - 프리셋 `name`을 로컬라이즈하면 `extension/options.js:435`의 `presets.find(p => p.name === name)`가 못 찾아 프리셋 적용이 무동작이 된다 — `name`이 `<select>`의 **value**이자 조회 키다(`options.js:86`).
  - `extension/defaults.js`가 모듈 스코프에서 `chrome.*`을 부르면 `node --test` 158건이 전부 죽는다 — 세 테스트 파일 모두 `vm.runInThisContext`로 이 파일을 **`chrome` 전역 없이** 실행한다(`tests/buttons.test.js:12`, `tests/migration.test.js:12`, `tests/layout.test.js:9`).
  - `warpTabConfigHeader`(`app/Sources/Core/WarpControl.swift:22`)를 바꾸면서 레거시 헤더를 인식하지 않으면 이미 사용자 디스크에 있는 `.toml`이 앱(`warpTabConfigIsOurs`의 `hasPrefix`)에서도 `uninstall.sh:63`의 `grep`에서도 영영 회수되지 않는다.
  - 테스트 오라클을 `Bundle(url: <lproj를 담은 디렉터리>)`로 쓰면 **호스트 기계 언어**로 해석된다. 실측(R0): 이 기계(`AppleLanguages=(ko-KR)`)에서 `en`을 겨눈 조회가 `APP-KO`를 돌려줬다 — 개발자 기계에서 통과하고 CI에서 실패하거나, 더 나쁘게 반대로 조용히 통과한다.
- acceptance oracle: 기존 4개 게이트 + 신규 5개 — ① 앱 카탈로그 정합(5개 로케일 키 집합 동일 · 플레이스홀더 동일 · 소스 참조 키 ⊆ 카탈로그 · 미참조 키 0 · 동적 키 0), ② 확장 사전 정합(같은 4가지), ③ **정본 단일성**(세 카탈로그의 키 공간이 서로 겹치지 않음 · 로케일마다 값 문자열 중복 0 · `_locales`의 키가 정확히 2개), ④ 정본 라벨 고정(`en` 값 == `README.md`·`install.sh`·`docs/new-terminal-checklist.md`가 인용한 문자열 — 파일을 읽어 대조, `UninstallScriptSyncTests` 선례), ⑤ 프로토콜 스큐(`app/e2e.sh`에 로케일 질의 케이스 + `command_template` 없는 요청이 여전히 `{success:false}`로 답한다는 기존 케이스 유지). 게이트는 **ko-KR 기계와 en CI 양쪽**에서 그린이어야 한다. 피커의 AppKit 크롬 쪽 절반은 자동 게이트로 잡히지 않는다 — 항목 4의 근거 칸이 그 실측을 낸다.
- 코퍼스 범위(R0 실측):
  - 한글 포함 줄 총 **2,294**(리포 전체, 계획 파일 2개 820줄 제외 시 **1,474**). 파일별 상위: `app/Tests/CoreTests/CoreTests.swift` 453 · `app/Sources/Core/ClaudeInjector.swift` 282 · `app/Sources/WarpHelper/main.swift` 137 · `app/Sources/App/SetupWindowController.swift` 125 · `app/Sources/Core/WarpControl.swift` 93 · `app/Sources/Core/TerminalRunner.swift` 74 · `app/Sources/Core/WarpHelperProtocol.swift` 70 · `app/Sources/Core/ToolChecker.swift` 48.
  - 그중 **한글이 든 문자열 리터럴**(주석 제외) 총 **269줄**. 로컬라이즈 후보인 App 타깃은 `SetupWindowController` 87 · `AppDelegate` 9 · `HostServer` 8 · `Installer` 7 · `PermissionChecker` 5 · `Settings` 1 · `Theme` 1 = **118 리터럴**(연결 조각 포함이므로 메시지 수는 이보다 적다 — 이슈 본문의 "약 57개"는 `SetupWindowController` 기준). Core+Relay+WarpHelper는 **61 리터럴**(전부 로그·오류 서술 — 영어화 대상).
  - 확장: `options.html` 본문 산문 **37덩이 / 4,905자**(실측) · JS 후보 문자열 `options.js` 56 · `migrations.js` 44 · `defaults.js` 25 · `content.js` 24 · `background.js` 17(거친 스캔의 상한이며 정확한 카탈로그는 항목 13·14의 산출물) · `manifest.json` name+description 2 · 프리셋 `name` 11 + repo 프리셋 `face` 3.
  - 스크립트: `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/221e113f-3ee7-4894-bb18-3ab384bfeb20/scratchpad/{scan,strings,count_swift,count_html,count_js}.py`.
- 원자성·부분 실패·롤백 경계: **N/A** — 사용자 데이터를 쓰지 않는다(저장 설정도, 파일도). 단 세 가지가 배포·상태 경계에 걸린다: ① `extension/_locales/`와 `extension/_i18n/`이 생기면 `Installer.extensionCopyNeedsUpdate()`(`app/Sources/App/Installer.swift:126`)가 내용 차이를 감지해 App Support 사본을 자동 재복사하고, 사용자는 chrome://extensions에서 새로고침해야 반영된다. ② `manifest.json`에 `default_locale`을 더하는 것이 확장 ID를 바꾸지 않는지 확인이 필요하다(ID는 `key`에서 나온다 — CLAUDE.md상 ID가 바뀌는 변경은 새로고침이 아니라 제거·재로드). ③ 로케일 질의도 소켓 요청이라 `Settings.recordRequestEvidence()`를 찍는다 — "확장이 Chrome에 로드됐다"는 증거의 뜻이 넓어진다(항목 7의 결정 대상).

## 비목표 — 건드리지 않는다

- `README.md`·`docs/**`·`CONTRIBUTING.md`·`SECURITY.md`의 **다국어화**: 문서는 영어 단일 정본으로 남는다. 이 파일들에는 `en` 라벨 인용의 갱신과 기계 번역 고지만 일어난다.
- **로그의 로컬라이즈**: 영어 단일 언어다. 사용자 결정이며 근거는 원장 D13에 있다.
- **Core·Relay·WarpHelper의 로컬라이즈**: 영어 단일 언어로 남긴다(원장 D3). 기술적 불가가 아니라 선택이다 — 실측(R0)으로 `Contents/MacOS/` 안의 **다른 이름 실행 파일**도 `Bundle.main`이 감싸는 `.app`으로 잡혀 `Contents/Resources/*.lproj`를 읽는다(relay·헬퍼 모양 그대로).
- **확장 안의 언어 피커**: 언어의 소유자는 앱 하나다(D8). 옵션 페이지는 현재 언어를 **읽기 전용**으로 보여 주고 앱 창을 가리킬 뿐이다 — 양쪽에 피커를 두면 두 정본이 된다.
- **TCC 프롬프트(`NSAppleEventsUsageDescription`)의 언어를 앱이 통제하는 것**: 그 문자열을 그리는 것은 tccd이고 어느 로컬라이제이션을 고르는지 우리가 정하지 못할 수 있다. 실측하되 안 되면 **그렇다고 문서에 적고 고치지 않는다**(D14).
- **저장소별·페이지별 언어 오버라이드**, **RTL·의사 로케일(pseudo-locale)**, **번역 워크플로 도구**(Crowdin 등) 도입.
- **제품명·번들 식별자·Native Host 이름·확장 ID**: `Terminal Checkout`, `com.dazebug.terminal-checkout`, `com.dazebug.terminal_checkout`, manifest `key`는 그대로다.
- **Chrome Web Store 리스팅 메타데이터**의 다국어화: 스토어 전환 자체가 아직 없다(`Installer.allowedExtensionIDs`에 store ID 미등록).
- **동작 변경 일체**: 이번 작업은 문자열의 위치와 언어, 그리고 로케일 한 필드만 다룬다. 프리셋 `command` 문자열, `SETTINGS_VERSION`, 마이그레이션 레지스트리, 실행 경로, 게이트 3종(`ClaudeInjector`)은 손대지 않는다. 특히 **`SETTINGS_VERSION`은 올리지 않는다** — 마이그레이션 통지는 저장된 *command*에 관한 것이고 i18n은 command를 바꾸지 않는다. `TerminalError`를 타입 사유로 쪼개는 리팩터도 범위 밖이다(D11).
- **`app/Tests/CoreTests/CoreTests.swift`의 한글 픽스처 데이터**: `"설계 정리해줘"`·`"내 작업 공간"`·`"terminal-checkout-내파일.toml"` 등은 멀티바이트 입력을 겨눈 실측 데이터다. 영어로 바꾸면 커버리지가 사라진다.

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

- **로케일은 앱에서 확장으로만 흐른다.** 앱이 정본이고, 확장은 받아서 캐시하고 그리기만 한다 — 반대 방향의 필드는 만들지 않는다. 반대가 아닌 이유는 순서다: 설치 안내 창은 **확장이 설치되기 전에** 사용자가 처음 보는 화면이라 확장이 정본이면 그 시점에 답이 없는 반면, 앱은 확장 없이도 항상 자기 언어를 해석할 수 있다(D8). 이것은 터미널 선택·base dir과 **같은 방향의 규칙**이고, 그 둘과 달리 값이 확장으로 내려간다는 점만 다르다.
- **문자열 카탈로그의 정본은 로케일마다 하나다.** 저장소는 셋(앱 `.lproj` · 확장 자체 사전 · 확장 `_locales`)이지만 **키 공간이 서로 겹치지 않고**(`app.*` / `ext.*` / `_locales`는 `extName`·`extDescription` 정확히 둘), 같은 문장이 두 곳에 나타나면 게이트가 red다. 생성기는 두지 않는다 — 빌드 단계가 늘면 CI가 그것을 돌려야 하고 생성물과 소스가 갈리는 새 실패 부류가 생긴다. 두 표면이 같은 정보를 말해야 하면 **각자의 표면에 맞게 다르게 쓴다**(앱 창과 옵션 페이지는 애초에 다른 UI다).
- **로케일은 최상위 필드이지 `variables`가 아니다.** `variables`에 넣으면 `allowedVariables`(`CommandRenderer.swift:32-34`)에 없어 요청 전체가 거부된다. 그리고 값은 화이트리스트(`sanitizeValue`)를 그대로 통과하는 모양(`a-zA-Z0-9-_./`)이어야 셸 경로로 새어도 무해하다 — `zh-Hans`·`zh-Hant`는 이미 그 모양이다.
- **프로토콜에 필드를 더할 때 두 스큐 조합을 모두 살린다.** 요청은 지금도 모르는 최상위 키를 무시하고(`resolveRequest`는 `command_template`·`variables`·`claude_inputs`만 읽는다 — `terminal` 필드가 무시되는 것과 같은 성질), 응답은 `success`·`error`만 읽힌다(`background.js:239`). 그 성질에 기대되 **테스트로 고정한다**.
- **앱의 거절은 예외가 아니라 `{success:false, error}`다**(CLAUDE.md). 로케일 질의도 같은 규약을 따르고, 확장은 `success`를 확인하지 않는 경로를 만들지 않는다. 그리고 **실패한 질의는 캐시하지 않는다** — 폴백만 하고 다음 기회에 다시 묻는다.
- **확장의 렌더링은 로케일 질의를 기다리지 않는다**(D15). 캐시로 즉시 그리고, 캐시가 없으면 `chrome.i18n` 언어로 그리고, 응답이 오면 다시 그린다. 「그리기 전에 알아낸다」는 순서는 앱이 없는 사용자에게 25초 빈 화면이 된다.
- **언어를 바꾸면 우리 문자열은 즉시 바뀐다**(D14). AppKit 크롬은 다음 기동에 따라오고, 그 사이가 있다는 것을 화면이 말한다 — 재시작을 미룬 사용자가 아무 반응도 못 보는 상태를 만들지 않는다.
- **App 타깃의 모든 사용자 문자열은 하나의 조회 함수를 지난다**(항목 1이 이름을 정한다). 자리마다 `NSLocalizedString`을 직접 쓰면 정합 게이트가 소스를 스캔할 수 없다 — 그리고 키를 동적으로 만드는 코드는 금지다(스캔이 불가능해지고, 그 순간 「누락 키」가 다시 런타임에만 드러난다).
- **로케일 해석 로직은 Core에 둔다.** App 타깃에는 테스트가 거의 없다(`AppTests`는 레이아웃 3파일뿐) — 선택값·시스템 선호·지원 목록에서 `.lproj` 태그를 고르는 판정은 순수 함수로 Core에 두고 App은 부르기만 한다. base dir이 같은 이유로 Core에 있다.
- **`app/e2e.sh`의 오라클은 영어 Core 문자열이다.** `Unknown variable: {evil}`·`Invalid characters`·`command_template is required`·`claude_inputs must be an array` 9건이 그렇다. Core가 로케일 의존이 되는 순간 이 게이트는 기계마다 다른 답을 준다.
- **셸이 grep하거나 코드가 `hasPrefix`로 비교하는 문자열은 기계 마커이지 UI가 아니다.** 로컬라이즈하지 않는다 — 로케일마다 다른 마커는 `uninstall.sh`가 잡을 수 없다. 마커를 **바꿀 때는 옛 값을 인식하는 경로를 같은 승격에 넣는다**(D10).
- **`extension/defaults.js`는 프리셋·기본값·표시 규칙·페이지 분류·스토리지 키의 단일 정본이다.** i18n이 두 번째 정본을 만들지 않는다. 그리고 이 파일은 `chrome` 전역 없이 Node에서 실행 가능해야 한다 — 조회는 모듈 스코프가 아니라 **호출 시점**에 일어난다.
- **로케일 캐시는 `storage.local`이고 `storage.sync`가 아니다.** 기계 A에서 해석된 언어가 계정을 타고 기계 B로 가면 안 된다 — base dir이 확장에 없는 것과 같은 이유다.
- **테스트 오라클은 호스트 기계 언어에 의존하지 않는다.** 실측(R0): `swift test` 안에서 `Bundle.main`은 `/Applications/Xcode.app/Contents/Developer/usr/bin`이고 조회는 **키를 그대로** 돌려준다. `Bundle(url: <lproj 상위 디렉터리>)`는 **호스트 언어**로 해석된다. `Bundle(path: <상위>/<loc>.lproj)`만 로케일별로 결정적이다. 카탈로그 파일 자체는 `PropertyListSerialization`으로 파싱된다 — 정합 게이트는 Bundle을 거치지 않고 파일을 읽는 편이 더 단단하다.
- **주석 번역은 「왜」를 보존한다.** `ClaudeInjector`·`WarpControl`·`TerminalRunner`·`CoreTests`의 한국어 주석 대부분은 실측 수치와 기각된 대안을 담고 있다. 요약·정리하지 말고 같은 사실을 영어로 옮긴다.
- **하드랩 금지 · 물결표**: 문서·주석의 문단은 한 논리 줄로 쓰고, 마크다운에서 범위는 `∼`(U+223C)를 쓴다.
- **TDD**: 정합 게이트를 먼저 써서 red를 눈으로 확인하고(카탈로그가 없거나 비었으니 실패), 그다음 카탈로그와 치환을 넣어 green을 만든다.
- **라운드마다**: `cd app && swift test` · 리포 루트 `node --test` · `app/build.sh` 후 `app/e2e.sh`가 전부 그린. 기준선은 swift 351(1 skipped) · node 158 · e2e 9 PASS.
- **PR은 하나, 커밋은 부류별로 쪼갠다**(사용자 결정 Q8).

## 배치 점검 (0라운드)

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | ignored — `.git/info/exclude:7:.claude/worktrees/` |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 예 — `92a2354` / `da37339`, main HEAD와 일치 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/agent-ae53697e324bf1279` · `worktree-agent-ae53697e324bf1279` · `92a2354` |
| 트리마다 `uv sync` (기준·작업) | N/A — Python 패키지 없음. 게이트는 `swift test`·`node --test`·`build.sh`·`e2e.sh` |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 확장 서명키 `~/Library/Application Support/TerminalCheckout/extension-key.pem` — 존재·`-rw-------` 확인(이번 작업은 이 파일을 읽지 않는다) |
| 증분 리뷰 소요(분) — 첫 세 번 | |

## 작업 항목

| # | 항목 | 부류 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | **앱 로컬라이제이션 골격.** `Contents/Resources/<loc>.lproj/Localizable.strings` 5벌 + `InfoPlist.strings`(`NSAppleEventsUsageDescription`), `CFBundleDevelopmentRegion` `ko`→`en`, `build.sh`가 `.lproj`를 번들로 복사, App 타깃의 **단일 조회 함수**(예: `L(_:)`). 조회는 `Bundle(path: <Resources>/<태그>.lproj)`로 하며 그 태그를 바깥에서 주입할 수 있게 둔다 — 이 seam 하나가 테스트 오라클과 항목 4의 피커를 **둘 다** 떠받친다. 그리고 `main.swift`가 **AppKit을 처음 건드리기 전에** 저장된 언어를 `AppleLanguages`로 써 AppKit 크롬까지 같은 언어가 되게 한다(D14 — 실측상 그 자리에서만 같은 프로세스에 반영된다). SwiftPM `resources:`/`Bundle.module`은 쓰지 않는다(D1) | 골격-앱 | `app/Info.plist`, `app/build.sh`, `app/Sources/App/main.swift`, `app/Sources/App/Localization.swift`(신규), `app/Sources/App/Resources/*.lproj/*`(신규) | — | todo | | |
| 2 | **Core: 로케일 해석 순수 함수.** 지원 로케일 상수 5개 + `resolveLocale(preference:systemPreferred:available:)` — `auto`면 시스템 선호 목록을 훑어 첫 일치, 없으면 `en`. `zh-TW`·`zh-HK`·`zh-MO`→`zh-Hant`, `zh`·`zh-SG`→`zh-Hans` 접힘을 값으로 고정한다. **red**: `CoreTests`에 `LocaleResolutionTests` 신설 | 골격-앱 | `app/Sources/Core/Localization.swift`(신규), `app/Tests/CoreTests/CoreTests.swift` | — | todo | | |
| 3 | **앱 카탈로그 정합 게이트.** 5개 로케일 키 집합 동일 · 플레이스홀더 집합 동일 · 소스 스캔으로 얻은 참조 키 ⊆ 카탈로그 · 미참조 키 0 · 동적 키 0. 파일을 `#filePath`로 읽어 `PropertyListSerialization`으로 파싱한다(Bundle 미사용, D7). **red 먼저** | 골격-앱 | `app/Tests/AppTests/LocalizationCatalogTests.swift`(신규) | 1(조회 함수 이름·파일 배치) | todo | | |
| 4 | **앱 언어 설정 + 피커(D14).** `Settings.language`(`auto` 기본, 비문자열 저장값은 `baseDirectory`와 같은 방식으로 접지 않고 넘긴다), 설정 창의 언어 행. 고르면 **우리 문자열은 재시작 없이 즉시** 다시 그려지고(항목 1의 seam), AppKit 크롬을 위해 `AppleLanguages`를 함께 써 두고 피커 옆에 **「지금 다시 시작」**을 둔다. 확장에 내려보낼 값은 항목 2가 해석한 태그다. **근거 칸에 낼 실측 3건**: ① 재시작 뒤 `NSAlert`·`NSOpenPanel`이 고른 언어로 뜨는가, ② TCC 프롬프트(`NSAppleEventsUsageDescription`)가 따라오는가 — 안 되면 그렇다고 적고 고치지 않는다, ③ 재시작이 소켓 서버를 끊는 동안 눌린 버튼이 어떻게 실패하는가(relay가 앱을 띄우고 10초 재시도한다 — `Relay/main.swift:24-33`) | 골격-앱 | `app/Sources/App/Settings.swift`, `app/Sources/App/SetupWindowController.swift`, `app/Sources/App/Localization.swift` | 1, 2 | todo | | |
| 5 | **`SetupWindowController` 문자열 → 키.** 창 제목·카드 제목·버튼·①∼④ 안내·터미널별 주석·상태 줄·알림 87 리터럴, `relativeFormatter`의 `ko_KR` 고정(`:617`) 제거 후 해석된 로케일 사용, `baseDirectoryReason`(`:897`)·`claudeWrapperAdvice`(`:1049`)·`warpAccessibilityHelpText`(`:1060`)·`panel.prompt`(`:933`). **같은 승격에 그 문자열을 고정한 테스트**를 넣는다 — `SetupWindowLayoutTests`의 `"그대로 실행되지만"`·`"거절"`·`"명령은 실행되지만"`(`:165`·`:166`·`:178`), 그리고 키가 되면 짧은 키로 레이아웃을 재게 되는 문제 | 문자열-앱 | `app/Sources/App/SetupWindowController.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Sources/App/Resources/*.lproj/*` | 1, 4(언어 행이 같은 파일에 들어간다) | todo | | |
| 6 | **나머지 App 타깃 문자열 → 키.** `AppDelegate` 메뉴 8, `Installer`의 `SetupState` 6 + `InstallerError`, `PermissionChecker.AutomationStatus.label` 5. `HostServer.ServerError`·`Settings`·`Theme`의 한국어는 **로그·`fatalError`이므로 영어화**(파일이 겹치므로 여기서 함께) | 문자열-앱 | `app/Sources/App/{AppDelegate,Installer,PermissionChecker,HostServer,Settings,Theme}.swift`, `app/Sources/App/Resources/*.lproj/*` | 1 | todo | | |
| 7 | **프로토콜: 앱이 로케일을 내려보낸다.** ① 모든 응답에 `locale` 최상위 필드를 얹는다(추가 왕복 없이 매 명령마다 갱신), ② 냉시동용 질의 `{"query":"locale"}`에 명령을 실행하지 않고 답한다. 구버전 앱이 이 질의에 `{"success":false,"error":"command_template is required"}`로 답하는 성질은 **바꾸지 않는다**. 질의도 `Settings.recordRequestEvidence()`를 찍는다(D16) — 그 성질을 테스트로 고정한다. **red**: `app/e2e.sh`에 질의 케이스 + 응답에 `locale`이 실리는 케이스 | 프로토콜 | `app/Sources/App/HostServer.swift`, `app/Sources/Core/Request.swift`, `app/e2e.sh`, `app/Tests/CoreTests/CoreTests.swift` | 2 | todo | | |
| 8 | **확장: 로케일 획득·캐시·폴백(D15).** 서비스 워커가 질의로 받아 `storage.local`에 캐시하고 매 응답의 `locale`로 갱신한다. **렌더링은 질의를 기다리지 않는다** — 캐시로 즉시 그리고, 없으면 `chrome.i18n.getUILanguage()`로 그리고, 응답이 오면 다시 그린다. **실패한 질의는 캐시하지 않는다**. 콘텐츠 스크립트는 native messaging을 쓸 수 없으므로 캐시만 읽는다. 옵션 페이지는 현재 언어를 **읽기 전용**으로 보이고 앱 창을 가리킨다. **red**: `tests/`에 폴백 체인 순수 함수 테스트(앱 없음·질의 실패·캐시 없음·알 수 없는 태그) + 재렌더가 첫 렌더를 기다리게 하지 않는다는 순서 테스트 | 프로토콜 | `extension/background.js`, `extension/content.js`, `extension/options.js`, `extension/i18n.js`, `tests/i18n.test.js`(신규) | 7, 9 | todo | | |
| 9 | **확장 자체 사전 골격.** `extension/_i18n/<태그>.js` 5벌 + 조회 헬퍼(`chrome` 전역 없이 Node에서 로드 가능, 조회는 호출 시점). `chrome.i18n`은 UI에 쓰지 않는다(D9) | 골격-확장 | `extension/i18n.js`(신규), `extension/_i18n/*.js`(신규), `extension/options.html`(script 태그), `extension/manifest.json`(content_scripts 목록) | — | todo | | |
| 10 | **`_locales`는 manifest 전용.** `default_locale` + `name`/`description`을 `__MSG_extName__`/`__MSG_extDescription__`로, `_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`에 **그 두 키만**. 확장 ID가 바뀌지 않는지 확인해 근거에 적는다 | 골격-확장 | `extension/manifest.json`, `extension/_locales/**`(신규) | — | todo | | |
| 11 | **프리셋에 안정 식별자.** `PR_PRESETS`/`ISSUE_PRESETS`/`REPO_PRESETS`에 `id`를 더하고 `<select>`의 value·조회 키를 `name`→`id`로 옮긴다(`options.js:86`·`:435`). `name`은 그 뒤에야 로컬라이즈 가능한 표시 문자열이 된다. `DEFAULT_*`의 `label`도 같은 경로 | 골격-확장 | `extension/defaults.js`, `extension/options.js`, `tests/buttons.test.js` | — | todo | | |
| 12 | **정합 + 정본 단일성 게이트.** 확장 사전 5벌의 키 집합·플레이스홀더 동일 · 소스가 부르는 키 전부 존재 · 미참조 키 0. 그리고 **세 카탈로그를 함께 읽어** 키 공간이 겹치지 않음(`app.*` / `ext.*` / `_locales` 2키) · 로케일마다 값 문자열 중복 0 · `manifest.json`의 `__MSG_…__`가 전부 해석됨을 고정한다. **red 먼저** | 골격-확장 | `tests/i18n.test.js`, `app/Tests/AppTests/LocalizationCatalogTests.swift` | 3, 9, 10 | todo | | |
| 13 | **옵션 페이지 문자열.** `options.html` 산문 37덩이(4,905자) + `options.js`의 카드 템플릿·상태 메시지·`confirm()`·마이그레이션 패널. 산문 안에 `<code>`·`<b>`가 섞여 있어(`options.js`의 `innerHTML` 8곳, 리터럴 안 태그 4개) **메시지 단위를 어디서 자를지**가 이 항목의 설계 결정이다 | 문자열-확장 | `extension/options.html`, `extension/options.js`, `extension/_i18n/*.js` | 9 | todo | | |
| 14 | **나머지 확장 문자열.** `defaults.js`(프리셋 `name` 11 + repo `face` 3 + `BUTTON_CHANGED_ERROR` + `'New Button'`), `content.js`(`Opening.../Done!/Error!`), `background.js`(`PAGE_CHANGED_ERROR`), `migrations.js`(`describe`·`prefixDescribe`·`customNote`·거절 메시지 4종). **콘솔 전용 문자열은 로컬라이즈하지 않는다**(영어 유지) | 문자열-확장 | `extension/{defaults,content,background,migrations}.js`, `extension/_i18n/*.js` | 9, 11 | todo | | |
| 15 | **`en` + `ko` 카탈로그 본문.** `ko`는 현재 문자열의 이전, `en`은 새로 쓴다. #20 정본 라벨 10개와 글자 그대로 일치시키고 그 일치를 테스트가 `README.md`·`install.sh`·`docs/new-terminal-checklist.md`를 읽어 고정한다(`UninstallScriptSyncTests` 선례) | 번역본 | `app/Sources/App/Resources/{en,ko}.lproj/*`, `extension/_i18n/{en,ko}.js`, `extension/_locales/{en,ko}/messages.json`, `app/Tests/AppTests/CanonicalLabelTests.swift`(신규) | 3, 5, 6, 12, 13, 14 | todo | | |
| 16 | **`ja` + `zh-Hans` + `zh-Hant` 카탈로그 본문.** 모델 번역 초벌을 그대로 싣는다(사용자 결정 Q1). 기계적으로 보장되는 것은 키·플레이스홀더 정합뿐이고 **번역 품질은 게이트가 잡지 못한다** — 그 사실의 고지는 항목 21 | 번역본 | `app/Sources/App/Resources/{ja,zh-Hans,zh-Hant}.lproj/*`, `extension/_i18n/{ja,zh-Hans,zh-Hant}.js`, `extension/_locales/{ja,zh_CN,zh_TW}/messages.json` | 15 | todo | | |
| 17 | **Core 소스 영어화.** `ClaudeInjector`(282줄) · `WarpControl`(93) · `TerminalRunner`(74) · `WarpHelperProtocol`(70) · `ToolChecker`(48) · `Request`·`Terminal`·`Logging`·`Framing`·`ExtensionID`·`Paths`·`NativeHostManifest`·`UnixSocket`·`CommandRenderer`. 문자열 61개는 전부 로그·오류 서술(D13) — `DeliveryTimeline`의 `총`(`Logging.swift:54`)처럼 검사 목록이 인용하는 것은 항목 21과 짝을 맞춘다 | 영어화 | `app/Sources/Core/*.swift` | — | todo | | |
| 18 | **WarpHelper·Relay·빌드 스크립트 영어화.** `WarpHelper/main.swift`(137줄, 문자열 11) · `Relay/main.swift`(9줄, 문자열 2) · `app/build.sh`(5) · `app/e2e.sh`(7) · `app/Package.swift`(2) | 영어화 | `app/Sources/WarpHelper/main.swift`, `app/Sources/Relay/main.swift`, `app/build.sh`, `app/e2e.sh`, `app/Package.swift` | — | todo | | |
| 19 | **`CoreTests` 영어화(453줄).** 주석과 `XCTAssert` 실패 메시지 42건이 대상이고, **한글 픽스처 데이터는 남긴다**(`:271`·`:1324`·`:1681`·`:1693`·`:3389`·`:3398` 등 — 멀티바이트 실측). 어느 한글이 데이터이고 어느 것이 산문인지 판정을 표로 남긴다 | 영어화 | `app/Tests/CoreTests/CoreTests.swift` | — | todo | | |
| 20 | **`warpTabConfigHeader` 영어화 + 레거시 회수(D10).** 새 헤더 상수 + 레거시 상수(현 한국어 값)를 나란히 두고 `warpTabConfigIsOurs`가 **둘 다** 인식한다. `uninstall.sh`도 두 헤더를 지운다. `warpTabConfigTOML`의 꼬리말도 영어로. **red**: `UninstallScriptSyncTests`에 레거시 헤더 행 추가 + 옛 헤더로 시작하는 내용이 회수 대상으로 판정되는 테스트 | 마커 | `app/Sources/Core/WarpControl.swift`, `uninstall.sh`, `app/Tests/CoreTests/CoreTests.swift` | 17, 19(같은 두 파일을 만진다 — 같은 승격 창에서 순서대로) | todo | | |
| 21 | **문서·과도기 주석 정리.** `README.md:80`의 한국어 라벨 노트 블록 제거, `install.sh:99`·`:101`의 gloss 제거(#24 체크박스), `docs/new-terminal-checklist.md:135`의 로그 인용 갱신(**현재도 이미 낡았다** — 인용은 `입력 N개 중 M개 전달`인데 코드는 `claude(pid …) 입력 N개 중 M개 보냄(수신은 확인하지 않는다)`), 새 로케일을 추가할 때 손댈 지점 목록, **PR 본문·README에 "기계 번역 초벌, 개선 PR 환영" 명시**, **D10 레거시 헤더 상수를 언제 지울지 트리거 조건 기록**, **언어 전환의 재시작 경계와 TCC 프롬프트 잔여를 README에 기록**(D14 — 고치지 않고 적는다), **`CLAUDE.md`의 "Extension-install completion is judged by a recorded socket request" 문장 갱신**(지금 문구는 버튼 누름을 암시하는데 D16으로 로케일 질의도 같은 증거가 된다), `CLAUDE.md`에 이번 실측(번들 로딩·dev region 폴백·테스트 오라클 함정·로케일 소유권·런타임 `AppleLanguages` 무효) 반영, `docs/context/`에 i18n 결정 항목 추가 | 문서 | `README.md`, `install.sh`, `docs/new-terminal-checklist.md`, `CLAUDE.md`, `docs/context/*` | 15(en 라벨), 20(트리거 조건) | todo | | |

- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶이고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다. 승격 칸에는 커밋 해시를 적는다
- `의존`: 다른 항목의 계약(시그니처·불변식·생성물·호출 순서)을 전제하면 그 번호를 적는다. 그 항목에 정정(A′)이 오면 이 항목의 근거를 다시 낸 뒤에야 최종 리뷰에 들어간다
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`
- `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다. `verified`(드라이버 근거 대조)·`cleared`(증분 리뷰에서 범위 내 확인)·`agreed`(최종 리뷰 또는 cold review)·`dropped`(중단 결정)는 드라이버의 결정이고, 드라이버가 문구를 지정하면 에이전트가 그대로 적는다
- 근거 칸에는 **재실행 가능한 것**만: 명령과 결과 줄, 테스트 이름과 수, 수치를 낸 스크립트 경로. "확인했다"도, "이 함수가 이걸 읽어서 저렇게 한다"는 메커니즘 설명도 근거가 아니다 — 1행이 기준이다

## 결정 원장

append-only. 결정의 이유, 기각한 반박과 근거, 잔여 불확실성 — 코드 서술은 여기에도 넣지 않는다. 기존 행을 고치지 않고 새 행을 더한다.

| # | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|
| D1 | 이슈 #24가 지목한 대로 SwiftPM `resources:` + `Bundle.module`로 카탈로그를 싣는다 | **기각** — `.lproj`를 `Contents/Resources/`에 직접 두고 `Bundle.main`으로 읽는다 | 생성된 접근자(`.build/…/App.build/DerivedSources/resource_bundle_accessor.swift`)가 보는 곳은 `Bundle.main.bundleURL/<Name>.bundle`(= `.app` **최상위**, `Contents/Resources`가 아님)와 바이너리에 박힌 **절대 `.build` 경로** 둘뿐이고, 없으면 `Swift.fatalError`. 실측 프로브: 번들에 복사하지 않은 상태에서도 `Bundle.module`이 `/…/L10nProbe/.build/arm64-apple-macosx/release/L10nProbe_App.bundle`로 해석돼 **빌드 기계에서는 누락이 보이지 않는다**. 반면 `Contents/Resources/<loc>.lproj` + `Bundle.main`은 App·Core 양쪽에서 동작 · R0 | 없음 |
| D2 | `CFBundleDevelopmentRegion`은 표시에 영향이 없으니 `ko`로 둬도 된다 | **기각** — `en`으로 바꾼다 | 실측: 5개 `.lproj` 동일 배치에서 `AppleLanguages=(fr)`일 때 dev region `ko` → `preferredLocalizations=["ko"]`, `en` → `["en"]` · R0 | macOS 앱별 언어 선택 목록에 `LSUIElement` 앱이 뜨는지 미확인(D8이 흡수) |
| D3 | Core·Relay·WarpHelper도 로컬라이즈한다 | **기각** — 영어 단일 언어 | ① `app/e2e.sh`가 Core 오류 문자열 9건을 `grep -qF`로 고정한다 — 로케일 의존이 되면 게이트가 기계마다 다른 답을 낸다. ② 이 문자열들이 사용자에게 닿는 경로는 확장 **콘솔**뿐이다(`content.js:165-181`은 `❌`만 그리고 `console.error`로 흘린다 — 이슈 #29). ③ 창이 정말 보여 주는 사유는 이미 선례가 있다: `BaseDirectoryProblem`처럼 **타입으로 사유를 넘기고 문장은 App이 쓴다**(`CommandRenderer.swift:3-9`) · R0 | `TerminalError`가 `testResultLabel`에 그대로 뜬다 → D11에서 허용으로 정리 |
| D4 | 확장은 자체 사전 + `storage.sync` 언어 설정으로 런타임 전환을 지원한다 | **기각** — `chrome.i18n` + `_locales` | ① `manifest.json`의 `name`/`description`은 `__MSG_…__`+`_locales` **외의 방법이 없다**. ② Chrome은 `_locales`가 있으면 `default_locale`을 요구한다(공식 문서 확인). ③ 코드: `ko`·`ja`·`zh_CN`·`zh_TW`(하이픈 아님) · R0 | 런타임 전환 불가 · Chrome UI 언어에 종속 → D8·D9가 이 부분을 뒤집는다 |
| D5 | 프리셋 `name`을 그대로 로컬라이즈한다 | **기각** — 먼저 `id`를 도입한다(항목 11) | `options.js:86`이 `new Option(p.name, p.name)`으로 value에 이름을 넣고 `:435`가 `presets.find(p => p.name === name)`으로 되찾는다 — 이름이 곧 식별자다 · R0 | 저장된 `label`은 스냅숏이라 저장 시점 언어로 남는다(기존 성질과 동일) |
| D6 | `defaults.js`에서 모듈 로드 시점에 `chrome.i18n.getMessage`를 부른다 | **기각** — 호출 시점 조회 | `tests/{buttons,migration,layout}.test.js`가 `vm.runInThisContext`로 `chrome` 전역 없이 실행한다. 기준선 `node --test` → 158 pass · R0 | 없음 |
| D7 | 카탈로그 정합 테스트를 `Bundle`로 쓴다 | **기각** — 파일을 읽어 파싱 | 실측: `swift test` 안 `Bundle.main` = `/Applications/Xcode.app/Contents/Developer/usr/bin`, 조회는 키를 반환. `Bundle(url: <lproj 상위>)`는 호스트 언어(ko-KR)로 해석돼 `en`을 겨눈 조회가 `APP-KO`를 반환. `Bundle(path: <상위>/<loc>.lproj)`만 결정적. `.strings`는 `PropertyListSerialization`으로 파싱됨 · R0 | 없음 |
| D8 | 앱과 확장이 각자 플랫폼 로케일을 따른다(D4의 귀결) | **기각 — 언어는 하나이고 사용자가 고른다. 소유자는 앱이다.** 설치 안내 창에 언어 피커를 두고 앱 `Settings`에 저장하며, 기본값은 `시스템 언어를 따름`(Auto). 확장은 native messaging으로 앱에서 해석된 로케일을 받아 `storage.local`에 캐시하고 그것으로 UI를 그린다. 앱이 없거나 응답이 없으면 `chrome.i18n` 언어로 폴백한다 | 사용자 답변 "한 언어가 보이고 선택할 수 있어야지"(2026-08-22). 소유자를 앱으로 둔 이유: 설치 안내 창은 **확장을 설치하기 전에** 사용자가 처음 보는 화면이라 확장이 정본이면 그 시점에 답이 없다. 반대로 앱은 확장 없이도 항상 자기 언어를 해석할 수 있다. `CLAUDE.md`의 기존 규약("The app is the single source of truth for terminal selection")과 같은 방향이다 | 확장이 앱을 못 만나는 동안 두 언어가 갈릴 수 있다 — 폴백 구간을 문서에 적는다 |
| D9 | 확장 UI를 `chrome.i18n`으로 그린다 | **기각 — `chrome.i18n`은 `manifest.json`의 `name`/`description`에만 쓴다.** UI 문자열은 확장 자체 사전으로 그린다(런타임 전환이 필요하므로) | `chrome.i18n`은 Chrome UI 언어에 묶이고 런타임 전환이 없다(D4). D8이 요구하는 "앱이 정한 언어로 확장이 그린다"를 `chrome.i18n`으로는 만들 수 없다. `manifest.json`의 `name`/`description`은 `__MSG_…__`+`_locales` 외의 방법이 없어(D4) 그 둘만 남긴다 | 메커니즘이 둘이 된다 — **문자열의 정본은 하나여야 한다**(불변 원칙 참조) |
| D10 | `warpTabConfigHeader`를 한국어 기계 마커로 남긴다 | **기각 — 영어로 바꾸고 레거시 헤더 상수를 둔다.** 앱의 `warpTabConfigIsOurs`와 `uninstall.sh`가 신·구 두 헤더를 모두 인식해 기존 `.toml`을 회수한다 | 영어 트리에 한국어 상수를 남기는 것보다, 회수 경로를 명시적으로 두는 편이 표면이 작다. 회수 실패는 사용자 디스크에 고아 파일을 남기는 실사고다 | 레거시 상수를 언제 지울지 미정 — 항목 21에서 트리거 조건만 기록한다 |
| D11 | 로컬라이즈된 창에 영어 기술 사유가 섞이는 것(`testResultLabel`) | **허용** | `TerminalError`를 타입 사유로 쪼개는 리팩터는 이번 범위 밖이고(비목표: 동작 변경 일체), 기술 사유는 사용자가 이슈에 붙여 넣는 진단 문자열이라 영어가 오히려 낫다 | 사용자 불만이 오면 `BaseDirectoryProblem` 선례로 쪼갠다 — 트리거 조건만 기록 |
| D12 | `zh-Hant`/`zh_TW` 하나로 홍콩(`zh_HK`)까지 덮는다 | **채택** | 로케일 하나를 더 유지하는 비용 대비 이득이 없다. 실측(R0, 5개 `.lproj` 배치): `zh-HK`·`zh-Hant-HK`·`zh-MO`·`zh-TW` → `preferredLocalizations=["zh-Hant"]`, `zh`·`zh-SG` → `["zh-Hans"]`, `en-GB` → `["en"]`, `pt-BR` → `["en"]` | 없음 |
| D13 | `checkoutLog`/`DeliveryTimeline`이 내보내는 진단 문자열을 로컬라이즈한다 | **기각 — 영어 단일 언어** | 사용자 결정 "로그는 영어로 해"(2026-08-22). 그전에 이미 같은 결론이었던 근거 둘: `docs/new-terminal-checklist.md:135`가 로그 줄을 글자 그대로 인용해 수기 검사 목록으로 쓰므로 로케일마다 달라지면 목록이 무의미해지고, 사용자가 이슈에 붙여 넣는 진단 문자열이라 영어가 유용하다 | 없음 |
| D14 | 피커가 **우리 문자열만** 바꾸고 AppKit 크롬(`NSAlert` 버튼·`NSOpenPanel`)·TCC 프롬프트는 `AppleLanguages`를 따르게 둔다 | **기각 — 일관성이 이긴다. 앱이 그리는 모든 것이 고른 언어를 따른다.** 우리 문자열은 즉시 바뀌고, AppKit 크롬을 위해 앱 자신의 `UserDefaults`에 `AppleLanguages`를 쓴다. **실측 결과 재시작이 필요하다**: 그래서 피커 옆에 「지금 다시 시작」을 두고, 우리 문자열은 재시작 없이도 즉시 바뀌게 한다 | 사용자 요구는 "한 언어가 보이고 선택할 수 있어야지"다 — 버튼만 영어인 창은 그 요구를 절반만 만족한다. 재시작 비용은 이 앱이 `LSUIElement` 백그라운드 에이전트라 낮다. **실측(R0, 스크래치패드 `probe/appkit.py`, `Chrome.app` 5개 `.lproj`)**: ⓐ AppKit이 올라온 뒤 `UserDefaults.standard`에 `AppleLanguages=["ja"]`를 써도 같은 프로세스에는 무효 — `preferredLocalizations`는 `["ko"]`, `NSAlert` 기본 버튼은 `확인` 그대로이고 readback만 `["ja"]`. ⓑ 다음 기동에서는 반영 — `preferred=["ja"]`, 버튼 `OK`. ⓒ **AppKit을 건드리기 전에** 같은 프로세스에서 쓰면 반영 — `zh-Hant` 쓰고 `preferred=["zh-Hant"]`, 버튼 `好`. 그래서 쓰기 자리는 `main.swift`이고, 세션 중 변경은 재시작이 필요하다. ⓓ 우리 문자열은 `Bundle(path: <태그>.lproj)`라 `AppleLanguages`와 무관하게 항상 고른 언어(`ours.en=MAIN-en`, `ours.ja=MAIN-ja`) | **TCC 프롬프트는 통제 밖일 수 있다** — 실측하지 못했다. `NSAppleEventsUsageDescription`을 그리는 것은 tccd이고, 확인하려면 사용자의 살아 있는 Automation 권한을 리셋해 실제 프롬프트를 띄워야 한다(과거 권한 상실 사고가 있던 영역이라 이번 세션에서 하지 않았다). 항목 4가 실측하고, 안 되면 문서에 남긴다. 재시작이 소켓 서버를 끊는 동안의 버튼 실패도 항목 4의 실측 |
| D15 | 옵션 페이지가 로케일 질의의 응답을 **기다렸다가** 그린다 | **기각 — 렌더링은 절대 질의를 기다리지 않는다.** 옵션 페이지·콘텐츠 스크립트는 캐시(`storage.local`)로 **즉시** 그리고, 캐시가 없으면 `chrome.i18n` 언어로 그린 뒤, 질의 응답이 오면 다시 그린다. 질의가 앱을 깨우는 것 자체는 허용한다 | relay는 앱을 띄우며 최대 25초 블로킹한다(`Relay/main.swift:18`의 15초 + `:28-31`의 10초). 앱이 설치돼 있지 않은 사용자에게 25초 빈 화면은 그 자체로 결함이다. 앱을 깨우는 것은 막지 않는다 — 확장은 앱 없이는 어차피 동작하지 않고, 앱은 보통 이미 떠 있다 | 질의 실패를 캐시에 **굳히면 안 된다**(완료의 정의의 재현 실패) — 실패는 캐시하지 말고 다음 기회에 다시 물어라 |
| D16 | 로케일 질의가 `recordRequestEvidence()`를 찍어 「확장 설치 완료」 판정을 넓히는 것 | **허용 — 같은 부류의 증거다** | CLAUDE.md의 규칙은 "완료는 **기록된 소켓 요청**으로 판정한다, 폴더가 준비된 것으로 판정하지 않는다"이고 그 이유는 "준비된 폴더는 Chrome이 실제로 로드했는지 말해 주지 못한다"이다. 로케일 질의는 **로드된 확장이 보낸 실제 소켓 요청**이라 그 증거력이 같다 — relay는 허용된 확장 ID의 native messaging으로만 불린다. 판정이 "GitHub에서 버튼을 눌렀다"에서 "확장이 앱에 말을 걸었다"로 넓어지는 것은 규칙의 **의도대로**이지 우회가 아니다 | 항목 21에서 CLAUDE.md의 그 문장을 갱신한다 — 지금 문장은 버튼 누름을 암시한다 |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점 전체. 미검사 항목을 비워 두지 않는 것이 이 표의 목적이다. 세 열뿐이다 — 셋째 열은 코드로 알 수 없는 이유 한 절이거나 `파일:행`이다. 판정이 안전이고 그런 이유가 없는 대상은 한 행에 나열해 합친다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `app/Sources/App/SetupWindowController.swift` 문자열 87 | 로컬라이즈(항목 5) | |
| `app/Sources/App/{AppDelegate,Installer,PermissionChecker}.swift` 문자열 21 | 로컬라이즈(항목 6) | |
| `app/Info.plist`의 `NSAppleEventsUsageDescription` | 로컬라이즈(항목 1) + **미검사**(항목 4가 실측) | 그리는 것은 tccd다. 확인하려면 사용자의 살아 있는 Automation 권한을 리셋해 실제 프롬프트를 띄워야 해 이번 세션에서 하지 않았다(과거 권한 상실 사고 영역). 통제 밖으로 밝혀지면 고치지 않고 문서에 남긴다(D14) |
| `app/Info.plist`의 `CFBundleDevelopmentRegion=ko` | 구멍(항목 1) | `app/Info.plist:6` |
| `NSAlert` 버튼·`NSOpenPanel` 시스템 문구 | 앱 피커를 따르게 한다 — **재시작 뒤에**(항목 1·4, D14) | 실측: 런타임 `AppleLanguages` 쓰기는 같은 프로세스에 무효, `main.swift`에서 AppKit보다 먼저 쓰면 유효. 우리 문자열인 `panel.prompt`(`SetupWindowController.swift:933`)는 항목 5 |
| `app/Sources/App/HostServer.swift` `ServerError` 3 + 타임라인 4 | 영어화(항목 6) | 창에 뜨지 않는다 — `AppDelegate.swift:42`가 `checkoutLog`로만 흘린다 |
| `app/Sources/App/Settings.swift:78`, `Theme.swift:68` | 영어화(항목 6) | 각각 `checkoutLog`·`fatalError` |
| `app/Sources/Core/ClaudeInjector.swift` 문자열 39 | 영어화(항목 17, D13) | 전부 `checkoutLog`/`timeline?.step` |
| `app/Sources/Core/TerminalRunner.swift` `ClaudeInputBlocker.message` 3 + `warpTabConfigFailed` 2 | 영어화(항목 17) | 확장 콘솔에만 닿는다(`content.js:165-181`, 이슈 #29). 창에 뜨는 것은 `testResultLabel` 경로뿐이고 D11이 허용했다 |
| `app/Sources/Core/Logging.swift:54`의 `총` | 영어화(항목 17) + 인용 갱신(항목 21) | `docs/new-terminal-checklist.md:135` |
| `app/Sources/Core/WarpControl.swift:22` `warpTabConfigHeader` | 영어화 + 레거시 상수(항목 20, D10) | `uninstall.sh:63`의 `grep`, `CoreTests.swift:4019`의 상수 고정, `WarpControl.swift:48`의 `hasPrefix` — 셋이 함께 움직여야 한다 |
| `app/Sources/Core/WarpControl.swift:86`의 `— 탭이 열리면 지웁니다.` | 영어화(항목 20) | 사용자가 `.warp/tab_configs/`에서 실제로 읽는 파일 내용이지만 UI가 아니다 |
| `app/Sources/Relay/main.swift:38`·`:48` | 영어화(항목 18) | Chrome이 받는 `error` 문자열 — 확장 콘솔행 |
| `app/Sources/WarpHelper/main.swift` 문자열 11 | 영어화(항목 18) | 전부 `checkoutLog`/종료 사유 |
| `app/Tests/AppTests/SetupWindowLayoutTests.swift:165`·`:166`·`:178` | 항목 5와 **같은 승격** | 소스 문자열을 글자 그대로 단언한다 — 키가 되는 순간 red |
| `app/Tests/CoreTests/CoreTests.swift` 한글 산문·실패 메시지 | 영어화(항목 19) | |
| `app/Tests/CoreTests/CoreTests.swift` 한글 **픽스처 데이터** | **유지** | 멀티바이트 실측 데이터 — `:271`·`:1324`·`:1681`·`:1693`·`:3389`·`:3398` 등 |
| `app/e2e.sh`의 오라클 9건 | 안전(로케일 무관) + 신규 케이스 2건(항목 7) | Core가 영어로 남는 것이 전제(D3) |
| **요청 최상위 미지 키**(`terminal` 등)를 앱이 무시하는 성질 | 안전 — 항목 7이 테스트로 고정 | `Request.swift:21-48`이 세 키만 읽는다 |
| **응답 추가 키**를 구버전 확장이 무시하는 성질 | 안전 — 항목 7·8이 테스트로 고정 | `background.js:239`가 `response?.success`만 본다 |
| `{"query":"locale"}`을 구버전 앱이 받는 경우 | 안전 — 기존 e2e 케이스가 이미 고정 | `app/e2e.sh:51-54` → `command_template is required` |
| `Settings.recordRequestEvidence()`가 로케일 질의에도 찍히는가 | 찍는다 — 허용(D16), 항목 7이 테스트로 고정 | `HostServer.swift:94`. 판정이 "확장이 앱에 말을 걸었다"로 넓어지며, CLAUDE.md 문장은 항목 21이 갱신한다 |
| 언어 전환 재시작 중 눌린 버튼 | **미검사**(항목 4가 실측) | `HostServer.stop()`이 소켓을 unlink하고 relay가 앱을 띄워 10초 재시도한다(`Relay/main.swift:24-33`) — 코드로 경로는 읽히나 실제 타이밍은 앱을 재시작시켜 봐야 안다 |
| 로케일 캐시를 `storage.sync`에 두는 실수 | 금지 — 불변 원칙 | 기계마다 다른 값이 계정을 타고 넘어간다 |
| `extension/manifest.json` `name`·`description` | 로컬라이즈 — `_locales` 2키만(항목 10) | |
| `extension/options.html` 산문 37덩이 · `options.js` UI 문자열 | 로컬라이즈(항목 13) | 산문 안에 `<code>`·`<b>`가 섞여 메시지 단위 분할이 설계 결정 |
| `extension/migrations.js`의 `describe`·`prefixDescribe`·`customNote`·거절 메시지 4 | 로컬라이즈(항목 14) | |
| `extension/defaults.js` 프리셋 `name` 11 + repo `face` 3 | 로컬라이즈(항목 14) — `id` 도입 후(항목 11) | 저장 시 스냅숏이 되므로 언어가 고정된다 |
| `extension/defaults.js` `BUTTON_CHANGED_ERROR`, `'New Button'` | 로컬라이즈(항목 14) | |
| `extension/defaults.js`·`background.js`의 `console.warn`/`console.error` 12 | **로컬라이즈 금지 — 영어 유지**(D13과 같은 이유) | README 트러블슈팅이 콘솔을 보라고 안내한다 |
| `extension/content.js` `'Opening...'`·`'Done!'`·`'Error!'` | 로컬라이즈(항목 14) | 텍스트 face일 때만 뜬다(`content.js:22-25`) |
| `extension/layout.js` | 안전 | 문자열 없음 |
| 프리셋 `command` 문자열 11 + `V0_TO_V1` 맵 | **불변** | 셸 명령이고 마이그레이션이 verbatim 비교한다 |
| `SETTINGS_VERSION`(`defaults.js:134`) | **불변** | i18n은 저장된 command를 바꾸지 않는다 |
| `manifest.json`에 `default_locale` 추가가 확장 ID를 바꾸는가 | **미검사**(항목 10이 확인) | ID는 `key`에서 나온다고 알고 있으나 실제 로드 확인은 Chrome을 띄워야 한다 |
| `manifest.json` `content_scripts`에 `i18n.js`를 더할 때 로드 순서 | **미검사**(항목 9) | `defaults.js`보다 먼저 와야 하는지는 조회를 호출 시점으로 두면 무관하나 실제 확인 필요 |
| `Installer.extensionCopyNeedsUpdate()`가 `_locales/`·`_i18n/` 추가를 감지하는가 | **미검사** | `Installer.swift:131-146`이 파일 맵을 비교하므로 감지될 것으로 읽히나 실제 실행 확인 필요 |
| 5개 로케일에서 설정 창 레이아웃이 깨지지 않는가 | **미검사** | `setupContentWidth=560`·`terminalRadioWidth=120`은 한/영으로 맞춘 값이고, `SetupWindowLayoutTests`는 한 로케일에서만 돈다. GUI를 띄워야 알 수 있고, GUI 기동은 `Installer.autoSetup()`이 사용자의 살아 있는 Native Host manifest를 덮어쓴다 |
| CJK 글리프가 `Theme.mono`(SF Mono)에 없어 폴백된다 | **미검사** | 같은 이유 — 화면을 봐야 안다 |
| `String(format: "%.1f")`(`Logging.swift:58`) 등 숫자 서식 | 안전 | `String(format:)`은 로케일 없이 POSIX 서식을 쓴다 |
| `RelativeDateTimeFormatter`의 `ko_KR` 고정 | 구멍(항목 5) | `SetupWindowController.swift:617` |
| `docs/context/signing-and-permissions.md:8`의 한국어 로그 인용 | **유지** | 날짜가 붙은 과거 증거이고 그 문구는 이미 현재 소스에 없다 |
| `docs/new-terminal-checklist.md:135`의 로그 인용 | 구멍(항목 21) | 인용 `입력 N개 중 M개 전달` ↔ 실제 `claude(pid …) 입력 N개 중 M개 보냄(수신은 확인하지 않는다)`(`ClaudeInjector.swift:780`) — **이미 낡았다** |
| `README.md:80` 노트 블록 · `install.sh:99`·`:101` gloss | 구멍(항목 21) | #24의 체크박스 |
| `CONTRIBUTING.md` · `SECURITY.md` · `LICENSE` · `.github/workflows/ci.yml` | 안전 | 한글 없음 |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 차단·수정·실측 줄은 에이전트가, 판정 줄은 드라이버가 지정한 문구를 에이전트가 적는다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — <계획 커밋 해시> · 승격 hh:mm · 리뷰 hh:mm∼hh:mm · 왕복 <n> · 원문 <경로>

- 반박:
- 처리: 사용자 결정 Q1·Q3·Q4·Q8 + 드라이버 결정 D8∼D16 반영 — 불변 원칙 4줄 신설(로케일 흐름 방향 · 카탈로그 정본 단일성 · 렌더링은 질의를 기다리지 않는다 · 언어 전환의 즉시/재시작 경계), 항목 16 → 21로 재구성(신규 2·4·7·8·10·12, 기존 5·6·9·11·13·14 개정), 열린 질문 Q1∼Q11 전부 폐기 후 Q12 신설
- 실측: 초안 작성 중 낸 것 — 번들 로딩 4케이스(D1) · dev region 폴백 2×8케이스(D2) · 테스트측 번들 3형태(D7) · 중국어권 폴백 9케이스(D12) · **런타임/기동전/다음기동 `AppleLanguages` 3케이스와 `NSAlert` 버튼 언어(D14)** · `Contents/MacOS`의 형제 실행 파일도 `.app` 리소스를 읽음 · 기준선 게이트 swift 351(1 skipped)/node 158/e2e 9. 프로브 패키지 `/private/tmp/claude-501/-Users-choongjaelee-Codes-terminal-checkout/221e113f-3ee7-4894-bb18-3ab384bfeb20/scratchpad/probe/`
- 판정:

## 열린 질문

Q1∼Q11은 모두 결정됐다 — 사용자 결정은 D8·D13과 항목 16·21에, 드라이버 결정은 원장 D8∼D16에 있다. 아래는 그 결정들이 새로 연 것뿐이다.

- **Q12 — TCC 프롬프트가 앱의 언어를 따르지 않는 것으로 밝혀지면, 그 사실만 적고 끝인가.** D14가 "고치지 마라"로 이미 답했지만, 그 경우 **권한을 처음 요청하는 순간 사용자가 보는 유일한 문장이 시스템 언어로 뜬다** — 설치 안내의 가장 중요한 한 걸음이 고른 언어 밖에 있게 된다. 항목 4의 실측 결과가 그렇게 나오면 안내 문구로 보완할지(설정 창이 프롬프트 직전에 같은 내용을 고른 언어로 미리 말해 주는 식) 결정이 필요하다. 항목 4·21에 걸린다.
