# i18n-five-locales

- 대상: `/Users/choongjaelee/Codes/terminal-checkout` (앱 `app/`, 확장 `extension/`)
- 시작 커밋: `92a2354`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/i18n-review` (`worktree-i18n-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/agent-ae53697e324bf1279` (`worktree-agent-ae53697e324bf1279`)
- 현재: R0 · 마지막 승격 `55fadef` · 리뷰 2회(설계) 종료 · 게이트 그린(swift 351/0 (1 skipped), node 158/0, build.sh 0, e2e 9 PASS — `55fadef` 실측, `baseline-55fadef.txt`)
- 최근 검증자 판정: **blocked** (2차) — 반박 11건이 「구현을 전제로 닫힘」이고 검증자가 "가장 작은 언블록은 정확한 세대 계약 + 통과하는 테스트"라고 적었다. 즉 다음 언블록 조건은 설계 라운드가 아니라 **구현**이다 · 원문 `<스크래치패드>/review-0-response.md`·`review-1-response.md`

이슈 #24 — "Localize the app's user-facing strings (en + ko)"를 사용자 요청으로 확장한 것이다. 이슈는 앱만, `en`+`ko`만 다뤘다. 사용자 요청은 **로케일 5개**(`ko`·`en`·`ja`·`zh-Hans`·`zh-Hant`)와 **확장·확장 설정 페이지까지**이고, 여기에 이슈가 "별도 추적"으로 미뤄 둔 **`app/`에 남은 한글의 영어화**가 같은 PR에 얹힌다. 축이 셋이고 서로 다른 판정을 받으므로 이 계획은 처음부터 셋을 갈라 다룬다: **로컬라이즈**(키 + 5개 카탈로그), **언어 소유권과 동기화**(앱이 정하고 확장이 따른다 — D8·D17), **영어화**(단일 언어로 번역, 키 없음).

## 목표

- 앱과 확장이 **최종적으로 같은 하나의 언어**로 수렴한다(D17). 언어는 앱 설정 창에서 고르고(기본값 `시스템 언어를 따름`), 확장은 그 값을 앱에서 받아 그린다 — 로케일은 `ko`·`en`·`ja`·`zh-Hans`·`zh-Hant` 5개이고, 목록에 없는 언어는 **영어**로 접힌다(오늘은 한국어로 접힌다 — 실측). **수렴 전 구간은 존재한다**: 앱 기동 직후, 앱이 죽어 있는 동안, 그리고 확장이 앱에 아직 못 물어본 첫 렌더에는 두 언어가 보일 수 있다 — 감추지 않고 문서에 적는다.
- 그 수렴이 **단조**다. 실패한 질의·낡은 응답·순서가 뒤바뀐 응답·읽을 수 없는 캐시는 **더 새로운 유효 로케일을 절대 덮지 못한다**. 이것이 이 루프에서 가장 깨지기 쉬운 성질이고, 순수 함수 하나로 뽑아 적대 케이스로 고정한다.
- 앱이 그리는 것은 **우리 문자열도 AppKit 크롬(`NSAlert` 버튼·`NSOpenPanel`)도** 고른 언어를 따른다. 우리 문자열은 즉시, AppKit 크롬은 다음 기동에 따라오며, 그 사이를 사용자가 알 수 있다(D14). TCC 프롬프트는 명시적 예외다(D14 잔여).
- 키 집합·플레이스홀더가 5개 로케일 간에 어긋나거나, 라벨을 인용하는 본문이 라벨과 갈리거나, 빌드된 `.app`이 소스 카탈로그와 다르면 **게이트가 red**가 된다.
- 언어 전환과 배포의 **각 상태 전이가 원자적이다**(D55): 진행 중인 claude 입력 전달을 재시작이 끊지 않고, 확장 사본 교체는 완전한 옛 사본이거나 완전한 새 사본이거나 둘 중 하나다. **관측 가능한 중간 상태가 없다고 주장하지는 않는다** — 최종적 일관성 구간(D17)과 전진 전용 롤백(D25)은 우리가 명시적으로 받아들인 것이다.
- `en` 카탈로그가 정본 라벨 12개와 **글자 그대로** 일치하고, 그 일치를 테스트가 고정한다(D30).
- `app/` 아래의 한국어 주석·개발자 문자열·테스트 오라클이 영어가 된다 — 단 **실측 데이터로서의 한글**(멀티바이트 입력 픽스처)은 남는다.
- 기존 4개 게이트가 **개발자 기계(ko-KR)와 CI(en) 양쪽에서** 그린이다. 로케일이 테스트 결과를 바꾸는 경로를 만들지 않는다.

## 완료의 정의

- 반드시 재현해 막아야 끝인 실패:
  - **더 오래되거나 느린 앱 인스턴스에서 온 과거의 성공 로케일이 더 새로운 앱 선택 로케일을 덮는다.** 또는 그 때문에 렌더된 기본 버튼이 지문 검사에 실패한다(D17·D18).
  - **앱을 재설치·초기화해 `epoch`가 0으로 돌아갔는데 확장이 「더 낮으니 무시」로 판정해 옛 언어에 갇힌다** — 정수 하나로는 리셋과 낡음을 구별할 수 없다. `installId`가 그 갈래다(D32).
  - **캐시 갱신 후 재그리기가 진행 중인 클릭을 무효화하거나 옵저버를 이중 등록한다** — 언어가 바뀐 순간 사용자가 누르고 있던 버튼이 죽는다.
  - **로컬라이즈된 문자열이 셸에 들어간다**(D34). `testCommand`는 칩으로 보이면서 실제로 실행되므로, 번역된 아포스트로피 하나가 `echo '…'` 인용을 깨 테스트 버튼이 셸 오류를 낸다.
  - **콘텐츠 스크립트가 로케일 A로 그렸는데 서비스 워커가 로케일 B로 기본 버튼을 지문 계산해 클릭이 `BUTTON_CHANGED_ERROR`로 거부된다** — 명령은 한 글자도 바뀌지 않았는데. 오늘 `buttonFingerprint()`가 `face`·`label`을 포함하므로(`defaults.js:425`) 라벨을 로컬라이즈하는 순간 성립한다(D18, P0).
  - **언어 변경 재시작이 진행 중인 요청을 조용히 버린다.** `HostServer.swift:120`이 응답 뒤에 `deliverClaudeInputs`를 백그라운드로 띄우고 `applicationWillTerminate`는 소켓만 닫는다 — **Warp 주입 헬퍼가 고아로 남는다**(D20). 헬퍼의 유일한 방어선이 수명이라는 CLAUDE.md의 신뢰 경계가 깨진다.
  - **확장 사본 교체가 실패해 "완전한 옛 사본도 완전한 새 사본도 아닌" 상태가 남는다.** `Installer.swift:101`이 지우고 나서 복사하고 `:153`의 `try?`가 실패를 삼킨다(D19).
  - **빌드된 `.app`에 로케일이 빠졌는데 소스 기반 테스트는 전부 통과한다**(D21). `build.sh`가 번들을 손으로 조립하므로 소스 검사만으로는 증명되지 않는다.
  - **`auto`인데 기동이 `AppleLanguages`를 써 시스템 설정이 영구 앱 오버라이드로 굳는다**(D22) — 사용자가 macOS 언어를 바꿔도 앱만 따라가지 않는다.
  - `AppleLanguages=(fr)` → 설정 창이 한국어. 실측(R0): dev region `ko`면 `fr` 요청이 `["ko"]`로, `en`이면 `["en"]`으로 접힌다. 현재 `app/Info.plist:6`이 `ko`다.
  - 어느 로케일 카탈로그에 키 하나가 빠짐 → 그 언어 사용자 화면에 원시 키가 그대로.
  - **본문이 인용한 라벨과 실제 버튼 라벨이 갈린다**(D28) — 8곳이 대괄호로 서로를 부르고, 갈린 상태가 5개 로케일에서 각각 가능하다.
  - 피커로 언어를 바꿨는데 AppKit 크롬이 옛 언어로 남고 **재시작 안내도 없다**. 실측(R0): 런타임 `AppleLanguages` 쓰기는 같은 프로세스에 무효(`preferredLocalizations` `["ko"]` 유지, `NSAlert` 버튼 `확인` 유지, readback만 `["ja"]`).
  - 옵션 페이지·콘텐츠 스크립트가 로케일 질의를 **기다리느라** 즉시 그리지 못한다 — 앱이 없으면 최대 25초 빈 화면(D15).
  - **신버전 확장 ↔ 구버전 앱**: 질의에 구버전 앱은 `{"success":false,"error":"command_template is required"}`로 답한다(`app/e2e.sh:51-54`가 고정). 확장이 이 실패를 캐시로 굳히면 그 프로필은 영구히 잘못된 언어가 된다.
  - **구버전 확장 ↔ 신버전 앱**: 응답에 `locale`이 늘어난다. 구버전 `background.js`는 `response.success`만 보므로 안전해야 하고, 깨지면 모든 버튼이 죽는다(`background.js:239`).
  - 로케일을 `variables`에 실으면 `allowedVariables`에 없어 요청 **전체**가 `Unknown variable: {locale}`로 거부된다.
  - 프리셋 `name`을 로컬라이즈하면 `options.js:435`의 `presets.find(p => p.name === name)`가 못 찾아 프리셋 적용이 무동작이 된다.
  - `defaults.js`가 모듈 스코프에서 `chrome.*`을 부르면 `node --test` 158건이 전부 죽는다(`vm.runInThisContext`, `chrome` 전역 없음).
  - 마커를 바꾸면서 옛 헤더를 인식하지 않으면 디스크의 `.toml`이 앱·`uninstall.sh` 양쪽에서 영영 회수되지 않는다.
  - 테스트 오라클을 `Bundle(url: <lproj 상위>)`로 쓰면 **호스트 기계 언어**로 해석된다(실측: ko-KR 기계에서 `en`을 겨눈 조회가 `APP-KO`).
- acceptance oracle: 기존 4개 게이트 + 신규 8개 —
  ① 앱 카탈로그 정합(5개 로케일 키 집합·플레이스홀더 동일 · 소스 참조 키 ⊆ 카탈로그 · 미참조 키 0 · 동적 키 0)
  ② 확장 사전 정합(같은 4가지)
  ③ **선언된 소유권**(D24): 논리 메시지 ID마다 사는 카탈로그를 선언으로 두고 게이트가 강제한다. 값 중복은 3단으로 — 저장소 **간** 완전일치 red · 저장소 **내** 완전일치 red + 명시 예외 목록 · 부분 중복 미검사
  ④ 정본 라벨 고정(D30): 문서 3곳을 읽어 10개 대조 + 문서에 없는 2개(`Request Accessibility Permission`·`Extension`)는 테스트 상수로 고정하고 근거로 #24를 인용
  ⑤ **라벨 인용 관계**(D28): 본문이 `%@`로 받는 라벨 키가 실재하고, 인용이 하드코딩으로 되돌아가지 않았는지
  ⑥ **최종 번들 자원 대조**(D21·D54): 소스 `.lproj`의 **모든 파일**이 빌드된 `.app`의 같은 경로와 **바이트 동일**하고, **파일 집합이 일치**한다(존재 검사가 아니다 — `InfoPlist.strings`를 존재만 보면 손상된 파일이 통과한다). 부재·누락·여분 전부 실패
  ⑦ **로케일 해석·캐시 리듀서 적대 테스트 13건**(D54): 앱 4(항목 5) + 확장 리듀서 6(항목 16) + **미지 로케일 응답·형식 오류 세대 필드**(항목 16) + 지문 정규화(항목 19). 재그리기 계약 3건은 별도로 센다
  ⑧ **생명주기·배포**: 재시작이 진행 중 요청을 버리지 않는다 · 교체 실패가 완전한 한쪽만 남긴다
  게이트는 **ko-KR 기계와 en CI 양쪽**에서 그린이어야 한다. 피커의 AppKit 크롬 절반과 TCC 프롬프트는 자동 게이트로 잡히지 않는다 — 항목 8의 근거 칸이 그 실측을 낸다.
- 코퍼스 범위(R0 실측, 인벤토리 `<스크래치패드>/inventory-app.tsv`·`inventory-ext.tsv`·`inventory-notes.md`):
  - **UI 메시지 214개 / 고유 키 218개**(앱 93 / 확장 125). 5개 로케일이면 **1,090 문자열**.
  - 앱의 「한글 리터럴 118개」는 조각을 복원하면 **UI 메시지 93개**다. 줄어든 25개는 전부 `+`로 이어 붙던 조각이고 가장 큰 것이 `warpAccessibilityHelpText`(4→1)·`claudeWrapperAdvice`(3→1)·`toolAdvice` z 갈래(5→2)·base dir 도움말 2건(각 3→1)이다.
  - 비-키(로그·마커·픽스처·콘솔) 33행. 한글 포함 줄 총 2,294(계획 파일 제외 시 1,474).
  - 스캔 스크립트: `<스크래치패드>/{scan,strings,count_swift,count_html,count_js,count_inv}.py`.
- 원자성·부분 실패·롤백 경계: **N/A가 아니다**(리뷰 §7). 네 가지가 상태를 남긴다 — ① **로케일 캐시**는 사용자가 쓴 데이터는 아니지만 지속되는 애플리케이션 상태다(항목 16의 리듀서 계약이 경계), ② **재시작**은 진행 중 명령·비동기 전달·Warp 헬퍼 수명에 걸린다(항목 13), ③ **확장 사본 교체**는 지금 비원자적이다(항목 14), ④ **마커 변경은 롤백 비호환**이다 — 구버전 바이너리는 새 헤더 파일을 회수하지 못하고, 피해는 `~/.warp/tab_configs/`에 파일이 남는 것뿐이라 문서화하고 받아들인다(D25). 그 밖에 `_locales/`·`_i18n/` 추가는 `Installer.extensionCopyNeedsUpdate()`가 감지해 자동 재복사하고 사용자는 chrome://extensions 새로고침이 필요하다(실측).

## 비목표 — 건드리지 않는다

- `README.md`·`docs/**`·`CONTRIBUTING.md`·`SECURITY.md`의 **다국어화**: 문서는 영어 단일 정본. 라벨 인용 갱신과 기계 번역 고지만 일어난다.
- **로그·콘솔의 로컬라이즈**: 앱 로그·Core·Relay·WarpHelper·확장 콘솔은 **명시적으로 영어인 진단 표면**이다(D27이 D3·D13의 근거를 정정). 영어화 대상일 뿐이다.
- **`testCommand`의 번역**(D29): `echo 'Terminal Checkout: 연결 OK'`는 화면에 보이면서 **실제로 실행된다**. 번역하면 아포스트로피를 쓰는 언어에서 `echo '…'` 인용이 깨져 테스트 버튼이 셸 오류를 낸다. 영어로 고정한다 — `{cd}`가 화이트리스트에서 면제된 것과 같은 부류, **값이 셸 구문인 문자열**이다.
- **확장 안의 언어 피커**: 소유자는 앱 하나다(D8). 옵션 페이지는 현재 언어를 읽기 전용으로 보이고 앱 창을 가리킨다.
- **`TerminalError`를 타입 사유로 쪼개는 리팩터**(D11) · **저장소별·페이지별 언어 오버라이드** · **RTL·의사 로케일** · **번역 워크플로 도구** · **제품명·번들 식별자·Native Host 이름·확장 ID** · **CWS 리스팅 메타데이터**.
- **`.stringsdict`·복수형 기계**(D31): 앱 UI 복수형 0건, 확장 3건은 영어 문구 리라이트로 없앤다.
- **`SETTINGS_VERSION` 인상**: i18n은 저장된 command를 바꾸지 않는다.
- **`CoreTests.swift`의 한글 픽스처 데이터**: 멀티바이트 실측 데이터라 유지한다.
- ~~"동작 변경 일체"~~ — **이 비목표는 철회한다**(리뷰 §1). 아래 다섯 가지는 **필요한 동작 변경**이고 범위 안이다: 로케일 질의·응답 처리, 재시작 조율, 기본 버튼 지문 의미, 확장 사본 교체와 롤백, 진행 중 명령 처리.

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

- **모든 렌더 경로는 검증된 단조 로케일 스냅숏 하나를 쓴다**(D17). 실패·낡음·미지·순서 뒤바뀜 응답은 더 새로운 유효 로케일을 절대 덮지 못한다. 계약 다섯 가지를 코드가 답해야 한다 — ① 무엇이 "더 새로움"인가 → **`(installId, epoch)` 쌍**(D32): `installId`가 다르면 무조건 수용, 같으면 `epoch >`일 때만 수용, ② 성공한 옛 응답이 캐시를 덮는가(**못 덮는다**), ③ `locale` 없는 명령 응답은 캐시를 보존하는가(**보존한다**), ④ `storage.local` 값을 어떻게 검증하는가, ⑤ 캐시가 바뀐 뒤 콘텐츠 스크립트에 어떻게 알리는가.
- **캐시가 바뀐 뒤의 재그리기도 계약이다**(검증자 §1). 알림을 보내는 것만으로는 이미 그려진 UI가 안전하게 갱신된다는 증명이 되지 않는다. 셋을 지킨다 — **옵저버가 중복 등록되지 않는다** · **활성 버튼이 DOM에서 떨어져 나가지 않는다**(재그리기가 노드를 갈아 끼우면 진행 중인 클릭 핸들러가 고아가 된다) · **전달 중인 명령이 무효화되지 않는다**(재그리기는 표시만 바꾸고 실행 중인 요청을 건드리지 않는다).
- **로컬라이즈된 카탈로그 값은 셸·AppleScript·TOML·터미널 입력에 절대 들어가지 않는다**(D34). 이것은 `{cd}`가 문자 화이트리스트에서 면제된 것과 같은 부류이고, CLAUDE.md의 "Never let request-supplied text into this class"와 나란히 선다. 기계/셸 페이로드는 **타입으로 분리해** 로컬라이즈된 문자열과 같은 자리에서 다뤄지지 못하게 한다. 동적 텍스트가 언젠가 셸에 들어가야 하면 **테스트된 셸 리터럴 인코더 하나**를 거친다.
- **로컬라이즈된 조각을 런타임에 이어 붙이지 않는다**(D36). 예외는 **선언된 플레이스홀더**뿐이고, 조건 분기는 번역된 절을 조립하지 말고 **완결된 메시지 ID를 고른다**. 게이트가 구조로 검사한다.
- **버튼 지문은 「같은 버튼인가」가 아니라 「같은 것이 실행되는가」를 답한다**(D33). 어느 버튼인지는 `index`가, 무엇이 실행되는지는 지문이 답하고 둘의 쌍이 정체성이다. 지문에 로컬라이즈된 표시 문자열이 들어가면 두 확장 컨텍스트가 서로 다른 로케일을 해석했을 때 **명령이 그대로인데도** 클릭이 거부된다.
- **로케일 판정과 캐시 갱신은 순수 함수다.** 앱 쪽은 `resolveLocale(preference:systemPreferred:available:)`로 **Core에** 둔다(App 타깃에는 테스트가 없다), 확장 쪽은 캐시 리듀서를 `chrome` 없이 부를 수 있는 함수로 둔다. 리뷰 §5의 8케이스가 테스트로 존재하지 않으면 동기화 계약이 미명세라는 뜻이다.
- **로케일은 앱에서 확장으로만 흐른다.** 반대 방향의 필드는 만들지 않는다. 순서가 이유다 — 설치 안내 창은 확장이 설치되기 전에 사용자가 처음 보는 화면이라 확장이 정본이면 그 시점에 답이 없다(D8).
- **로케일 질의는 앱 프로토콜 봉투의 관심사이지 Core의 관심사가 아니다**(D23). `HostServer`가 답하고 `Request.swift`는 손대지 않는다 — 명령 해석기를 앱 상태와 얽지 않고, **최상위 미지 키를 무시하는 기존 동작**을 보존한다.
- **로케일은 최상위 필드이지 `variables`가 아니다.** 값은 화이트리스트를 그대로 통과하는 모양(`a-zA-Z0-9-_./`)이어야 셸 경로로 새어도 무해하다 — `zh-Hans`·`zh-Hant`는 이미 그 모양이다.
- **프로토콜에 필드를 더할 때 두 스큐 조합을 모두 살린다**, 그리고 그 성질을 테스트로 고정한다.
- **앱의 거절은 예외가 아니라 `{success:false, error}`다**(CLAUDE.md). 로케일 질의도 같은 규약을 따른다. **실패한 질의는 캐시하지 않는다** — 폴백만 하고 다음 기회에 다시 묻는다.
- **확장의 렌더링은 로케일 질의를 기다리지 않는다**(D15). 캐시로 즉시 → 없으면 `chrome.i18n` → 응답이 오면 다시 그린다.
- **언어를 바꾸면 우리 문자열은 즉시 바뀐다**(D14). AppKit 크롬은 다음 기동에 따라오고, 그 사이가 있다는 것을 화면이 말한다.
- **로컬라이즈된 값을 오래 사는 객체에 붙잡아 두지 않는다**(리뷰 §2). 정적 포매터·한 번만 만드는 메뉴·생성 시점에 문자열을 굳히는 뷰는 언어 변경을 따라오지 못한다 — 오늘 `SetupWindowController.swift:615`의 `ko_KR` 고정 포매터와 `AppDelegate.swift:47`의 1회 메뉴 구성이 그 모양이다.
- **`auto`는 시스템 언어를 계속 따라간다**(D22). 해석된 값을 `AppleLanguages`에 쓰지 않고, 그 키를 **지운다**. 명시적 언어를 골랐을 때만 쓴다.
- **문자열 카탈로그의 소유권은 선언된다**(D24). 저장소는 셋(앱 `.lproj` · 확장 자체 사전 · 확장 `_locales`)이고 키 공간은 겹치지 않는다(`app.*` / `ext.*` / `extName`·`extDescription` 정확히 둘). 생성기는 두지 않는다(D9).
- **본문이 인용하는 라벨은 관계다**(D28). 대괄호로 다른 버튼을 부르는 8곳은 `%@`로 라벨 키를 받고 게이트가 그 관계를 검사한다.
- **화면에 보이면서 셸로 가는 문자열은 번역 대상이 아니다**(D29). `testCommand`가 그 부류이고, 소탕 표가 그 부류를 전수로 센다.
- **셸이 grep하거나 코드가 `hasPrefix`로 비교하는 문자열은 기계 마커다.** 새 마커는 **언어 중립 토큰**으로 만들어 언어 때문에 다시 바뀔 일을 없앤다(D25).
- **배포는 원자적이다**(D19). 형제 디렉터리에 완전히 만든 뒤 교체하고, 실패를 `try?`로 삼키지 않는다.
- **재시작은 진행 중 전달을 끊지 않는다**(D20). Warp 헬퍼의 유일한 방어선이 수명이라는 CLAUDE.md의 신뢰 경계가 그 이유다.
- **테스트 오라클은 호스트 기계 언어에 의존하지 않는다.** `Bundle(path: <상위>/<loc>.lproj)`만 결정적이고, 카탈로그 정합은 Bundle을 거치지 않고 파일을 읽는다.
- **주석 번역은 「왜」를 보존한다.** 실측 수치와 기각된 대안을 요약하지 말고 같은 사실을 영어로 옮긴다.
- **주석의 주장은 같은 파일·`CLAUDE.md`·실측과 어긋나지 않는다**(D56). 번역이 세기를 강화하는 것은 이 부류의 **부분집합**일 뿐이다 — 원본이 이미 어긋나 있던 자리는 번역↔원본 대조로는 영원히 안 잡힌다. 그래서 소탕은 **양방향 필수**다: ① 영어의 절대어법(`never`·`always`·`guarantee`·`successfully`…)을 원본과 대조 ② 한국어 **목적 구문**(`∼하지 않기 위한/위해서`)을 역방향으로 대조 — 목적이 보증으로 바뀌는 **정확한 언어적 형태**다. 그리고 ③ 모든 주장을 같은 파일의 다른 곳·`CLAUDE.md`·실측값과 대조한다. **실측과 추론의 구분도 같은 규칙**이다(clear 시퀀스는 `!`만 실측, `/`·`#`는 추론이라고 명시돼 있다).
- **하드랩 금지 · 물결표**: 문단은 한 논리 줄, 범위는 `∼`(U+223C).
- **TDD**: 게이트를 먼저 써서 red를 눈으로 확인하고 구현으로 green을 만든다.
- **라운드마다**: `cd app && swift test` · `node --test` · `app/build.sh` · `app/e2e.sh` 전부 그린. 기준선 swift 351(1 skipped) · node 158 · e2e 9 PASS.
- **PR은 하나, 커밋은 부류별로 쪼갠다.**

## 배치 점검 (0라운드)

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | ignored — `.git/info/exclude:7:.claude/worktrees/` |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 예 — `92a2354` / `da37339`, main HEAD와 일치 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/…/agent-ae53697e324bf1279` · `worktree-agent-ae53697e324bf1279` · `92a2354` |
| 트리마다 `uv sync` (기준·작업) | N/A — Python 패키지 없음. 게이트는 `swift test`·`node --test`·`build.sh`·`e2e.sh` |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 확장 서명키 `~/Library/Application Support/TerminalCheckout/extension-key.pem` — 존재·`-rw-------` 확인(이번 작업은 읽지 않는다) |
| 증분 리뷰 소요(분) — 첫 세 번 | R0 설계 리뷰 9분(23:56∼00:05, 왕복 1) |

## 작업 항목

**부류 순서가 곧 승격 순서다.** 「영어화」를 먼저 두는 것은 취향이 아니라 리뷰 §3이 지적한 파일 충돌을 원천에서 없애기 때문이다 — `CoreTests.swift`·`WarpControl.swift`·`app/e2e.sh`를 나중 항목들이 공유하는데, 이 셋을 먼저 영어로 비워 두면 뒤따르는 항목이 **영어 파일에 영어 테스트를 더하는** 단순 작업이 된다. 반대로 로컬라이즈를 먼저 하면 같은 파일을 두 번 만지게 되고 승격이 직렬화된다.

| # | 항목 | 부류 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | **Core 소스 영어화.** `ClaudeInjector`(282줄)·`WarpControl`(93)·`TerminalRunner`(74)·`WarpHelperProtocol`(70)·`ToolChecker`(48) 외 Core 전부. 문자열 61개는 전부 로그·오류 서술이며 **명시적으로 영어인 진단 표면**이다(D27). 마커 상수는 항목 4가 따로 다룬다 | 영어화 | `app/Sources/Core/*.swift`, `app/Tests/CoreTests/CoreTests.swift`(오라클 3줄만) | — | verified | `grep -rn '[가-힣]' app/Sources/Core/` → **2건만 남음**(`WarpControl.swift:17`·`:80`, 항목 4의 마커). 게이트 4종: `cd app && swift test` → `Executed 351 tests, with 1 test skipped and 0 failures`(기준선과 동일 수) · `node --test` → `# pass 158 / # fail 0` · `app/build.sh` → `Build complete!` · `app/e2e.sh` → **PASS 9건 전부, 오라클 문자열 무변경**(`git diff --stat app/e2e.sh` → 빈 출력 — 9개 오라클은 이미 영어인 Core 문자열이라 손대지 않았다). 번역 규모: Core 15파일 617 한글 줄 → 0, 문자열 리터럴 49개 영어화. **목적지 판정**(값 흐름 추적): 로그 전용 44 · 확장 콘솔 3(`ClaudeInputBlocker.message`, `TerminalError.description` → `{success:false,error}`) · **확장 콘솔 + 설치 안내 창 2**(`warpTabConfigFailed` — `runInTerminal(.warp)` → `runInWarp` → `writeNewFile`가 던지면 `SetupWindowController.swift:1000`의 `testResultLabel`이 `실패: Warp tab config error: …`로 렌더한다). **항목 25가 인용할 새 문구 2건**: 타임라인 형식 `<message> (+1.2s, total 3.4s)` · 전달 집계 `claude(pid N): sent M of K input(s) (receipt is not confirmed)`. 범위 밖 파일 무변경: `git diff --stat app/e2e.sh app/Sources/App app/Sources/Relay app/Sources/WarpHelper` → 빈 출력. **경계 교차 1건**: `CoreTests.swift`의 오라클 리터럴 3개(`:1925`·`:1943`·`:1964`)가 Core 문자열을 글자 그대로 고정하고 있어 같은 승격에서 갱신했다 — 항목 3의 산문·실패 메시지는 손대지 않았다. **기존 결함 1건 수정**: `warpHelperToken()`을 설명하는 주석이 `isOurRequestToken`의 doc 블록에 붙어 있던 것을 제자리로 옮겼다(내용 불변, 위치만 — 번역 전부터 그랬음을 `git diff`로 확인) | |
| 2 | **WarpHelper·Relay·빌드 스크립트 영어화.** `WarpHelper/main.swift`(137줄, 문자열 11)·`Relay/main.swift`(9줄, 문자열 2)·`build.sh`(5)·`e2e.sh`(7)·`Package.swift`(2) | 영어화 | `app/Sources/WarpHelper/main.swift`, `app/Sources/Relay/main.swift`, `app/build.sh`, `app/e2e.sh`, `app/Package.swift` | — | verified | `grep -rn '[가-힣]'` 5파일 → **0건**. 게이트 4종: swift `Executed 351 tests, with 1 test skipped and 0 failures` · node `# pass 158 / # fail 0` · `build.sh` → `Build complete: …` · `e2e.sh` → **PASS 9건 + `e2e: all cases passed`**. **오라클 불변 확인**(`grep -c 'PASS'`가 아니라): `git diff app/e2e.sh | grep -E '^[+-]' | grep -E '<오라클 9개 정규식>'` → **0 매치**, 그리고 `grep -n` 으로 9개 리터럴이 `:45`·`:49`·`:53`·`:57`·`:62`·`:66`·`:71`·`:75`·`:83`에 그대로 있음을 확인(변경 줄은 14줄, 전부 주석·출력 문구). **`build.sh` 출력 인용처 없음**: `grep -rn '빌드 완료\|Build complete' .github/workflows/ci.yml install.sh README.md docs/ CLAUDE.md` → `build.sh`를 **호출**하는 4곳만 나오고(ci.yml:22 · install.sh:61 · README.md:233 · checklist:33) stdout 문구를 인용·grep하는 곳은 0건 — 그래서 단독 변경 가능. **Relay 문자열 2개의 문자 그대로 비교 없음**: `grep -rn '앱을 실행할 수 없습니다\|통신에 실패했습니다' extension/ tests/` → 0건 (`background.js:239`가 `response?.error`를 그대로 던질 뿐 값을 비교하지 않는다). **목적지 판정**: Chrome 콘솔 2(Relay `replyError`) · 앱 로그 11(WarpHelper `checkoutLog`/`fail`) · 터미널 stdout 2(`build.sh` 완료, `e2e.sh` 통과) · CI 로그 1(`e2e.sh` 소켓 실패) · 나머지는 주석. 범위 밖 무변경: `git diff --stat app/Sources/App app/Sources/Core app/Tests extension/ tests/` → 빈 출력 | |
| 3 | **`CoreTests` 영어화(453줄).** 주석과 `XCTAssert` 실패 메시지 42건. **한글 픽스처 데이터는 남긴다**(`:271`·`:1324`·`:1681`·`:1693`·`:3389`·`:3398` 등). 어느 한글이 데이터이고 어느 것이 산문인지 판정을 근거 칸에 표로 남긴다 | 영어화 | `app/Tests/CoreTests/CoreTests.swift` | — | verified | 한글 447줄 → **40줄(전부 픽스처 데이터)**. `swift test` → `Executed 351 tests, with 1 test skipped and 0 failures` — **개수·스킵 수 불변**(테스트 이름을 바꾼 것이 없어 중복 이름도 없었다는 뜻). node 158/0 · `build.sh` · `e2e.sh` PASS 9. 범위 밖 무변경: `git diff --stat app/Sources extension/ tests/ app/e2e.sh app/build.sh` → 빈 출력. **판정 기준**(내가 정한 것): 그 한글이 **테스트가 입력으로 넣거나 기대값으로 비교하는 값**이면 **데이터**, **실패했을 때 사람이 읽는 설명**이면 **산문**. 위치로 가른다 — `XCTAssert*`의 **마지막 message 인자**와 `XCTFail`/`XCTSkipIf`의 인자는 산문, 그 밖의 위치(피연산자·배열 원소·함수 인자·픽스처 변수)는 데이터. **애매하면 데이터로 본다**: 어떤 값의 멀티바이트성이 "중요하지 않다"는 판단은 테스트가 명시하지 않은 커버리지 판단이고 틀리면 조용히 사라지는 반면, 한글 픽스처가 남는 손해는 없다 — **두 오류의 비대칭이 이 기준의 근거이고, 기준 자체는 아직 검증받지 않은 판단이다**(읽는 사람이 픽스처를 오인할 위험은 없는 반면, 잘못 번역하면 어떤 테스트 실패로도 드러나지 않는 커버리지 상실이 된다). **경계 사례 5종**: ① 한 `XCTAssert` 줄에 데이터와 메시지가 함께 있는 것(예: `XCTAssertEqual(session.submitted, ["!git status"], "…")`) → 위치로 갈라 message만 번역 · ② 메시지 안에 데이터가 보간된 것(`"\(run) 를 합쳤다"`) → 산문만 번역하고 `\(…)`는 유지 · ③ **셸 명령 안의 한글 주석**(`"z r && claude # 나중에"`) → 데이터(`#` 뒤에 무언가 있다는 것이 테스트의 요지) · ④ **타임라인 스텝 이름**(`요청 수신`·`Warp 탭 생성`·`claude 준비`) → 데이터(테스트가 넣고 기대한다 — 항목 1의 판정과 동일) · ⑤ **비-ASCII 파일 이름·내용**(`terminal-checkout-내파일.toml`·`tcw-내소켓.sock`·`남의파일.txt`·`내 작업 공간`) → 데이터(회수 로직이 이름·내용으로 판정하므로 비-ASCII가 요지). **D56 양방향 소탕**: 추가된 주석 줄의 절대어법 79건을 원본과 대조(강화 0건) + **주석 주장 ↔ `XCTAssert` 실제 단언 대조**에서 **1건 수정** — `testEverySendPassesTheSameGate`의 주석이 「네 자리(표식·Ctrl+U·본문·CR)」라는 **고정 목록**을 말하는데 단언은 `gateChecks == sendCallCount`라는 **일반 성질**이고 이 실행의 전송은 5회다. **테스트가 주석보다 강한** 쪽이라 주석을 단언에 맞췄다 | |
| 4 | **마커를 언어 중립 토큰으로(D25·D38).** 새 헤더는 언어가 없는 토큰이고 사람이 읽는 설명은 **그 아래 줄**로 분리한다. 토큰을 **「영구 기계 프로토콜」로 문서화한다** — "지금은 로컬라이즈 안 함"이 아니라 **"이 토큰은 다시 바뀌지 않는다"**를 코드 주석과 `uninstall.sh` 양쪽에 남긴다(D38). 옛 한국어 헤더는 회수용으로 계속 인식하고 `uninstall.sh`도 둘 다 지운다. 롤백 비호환은 **해결된 설계가 아니라 받아들인 전진 전용 잔여**라고 적는다. **red**: 옛 헤더로 시작하는 내용이 회수 대상으로 판정되는 테스트 + `UninstallScriptSyncTests`에 두 헤더 행 | 마커 | `app/Sources/Core/WarpControl.swift`, `uninstall.sh`, `app/Tests/CoreTests/CoreTests.swift` | 1, 3 | todo | | |
| 5 | **Core: 로케일 해석 순수 함수.** `resolveLocale(preference:systemPreferred:available:)` + 지원 로케일 상수 5개. `auto`는 시스템 선호 목록을 훑어 첫 일치, 없으면 `en`. **red 먼저**, 리뷰 §5의 앱 쪽 4케이스를 테스트 이름으로 — `testAutoMatchesOnlyThroughRegionFallback`(`zh-HK`·`zh-MO`·`en-GB`만 걸리는 선호 순서)·`testUnsupportedExplicitLocaleFallsBackToEnglish`·`testCorruptStoredPreferenceIsNotTrusted`·`testResolvedTagAlwaysNamesABundledLproj`. 폴백 값은 R0 실측표(D12)로 고정한다. **`epoch`는 선호가 아니라 「해석된 로케일 스냅숏」의 리비전이므로**(D48) 이 함수의 출력이 곧 리비전의 입력이다 | 골격-앱 | `app/Sources/Core/Localization.swift`(신규), `app/Tests/CoreTests/CoreTests.swift` | 3 | todo | 낼 명령: `swift test --filter LocaleResolutionTests`. 각 이름이 단언하는 것 — `testAutoMatchesOnlyThroughRegionFallback`: 선호 목록에 `zh-HK`·`zh-MO`·`en-GB`만 있을 때 **해석 결과 태그**가 각각 `zh-Hant`·`zh-Hant`·`en` · `testUnsupportedExplicitLocaleFallsBackToEnglish`: 명시 선호가 미지원일 때 **`en`**(시스템 선호로 새지 않음) · `testCorruptStoredPreferenceIsNotTrusted`: 비문자열·미지 문자열이 **`auto`와 같은 경로로 접히지 않고** 거부됨 · `testResolvedTagAlwaysNamesABundledLproj`: 어떤 입력에도 출력이 **번들에 실재하는 5개 태그 중 하나** | |
| 6 | **앱 번들 골격.** `Contents/Resources/<loc>.lproj/{Localizable,InfoPlist}.strings` 5벌, `CFBundleDevelopmentRegion` `ko`→`en`, `build.sh`가 `.lproj`를 복사, App 타깃의 **단일 조회 함수**(`Bundle(path: <Resources>/<태그>.lproj)`, 태그 주입 가능). `main.swift`가 AppKit을 건드리기 전에 저장된 언어를 `AppleLanguages`로 쓰되 **`auto`면 키를 지운다**(D22). SwiftPM `resources:`/`Bundle.module`은 쓰지 않는다(D1) | 골격-앱 | `app/Info.plist`, `app/build.sh`, `app/Sources/App/main.swift`, `app/Sources/App/Localization.swift`(신규), `app/Sources/App/Resources/*.lproj/*`(신규) | 5 | todo | | |
| 7 | **최종 번들 자원 대조 게이트(D21).** 빌드된 `.app`의 5개 `Localizable.strings`가 소스와 **바이트 동일**하고 `InfoPlist.strings` 5개가 존재하는지. 게이트를 빌드 후 스크립트로 둘지 테스트로 둘지 정하고 **CI에 배선한다**(`.github/workflows/ci.yml`이 `build.sh`를 이미 돌린다). D1의 조용한 실패가 `build.sh`로 옮겨간 것을 닫는 유일한 장치다 | 골격-앱 | `app/verify-bundle.sh`(신규) 또는 `app/Tests/AppTests/`, `.github/workflows/ci.yml` | 6 | todo | | |
| 8 | **`Settings.language` + 피커 + 창 즉시 갱신 + 재시작 버튼.** `auto` 기본, 비문자열 저장값은 `baseDirectory`와 같은 방식으로 접지 않고 넘긴다. 우리 문자열은 재시작 없이 즉시 다시 그려지고, AppKit 크롬을 위해 피커 옆에 「지금 다시 시작」을 둔다(항목 13이 그 안전 조건을 준다). **근거 칸에 낼 실측 3건**: ① 재시작 뒤 `NSAlert`·`NSOpenPanel`이 고른 언어로 뜨는가 ② TCC 프롬프트가 따라오는가(안 되면 그렇다고 적고 고치지 않는다) ③ `auto`로 여러 번 기동한 뒤 시스템 언어를 바꿨을 때 앱이 따라가는가(D22 전용 프로브). **`epoch` 규칙(D48·D49)**: 기동 시와 선호 변경 시 해석된 로케일을 다시 계산해 **마지막으로 발행한 값과 다르면** `epoch`를 올리고 둘 다 영속한다 — `auto`에서 시스템 언어가 바뀌어도 다음 기동에 반영된다. **`epoch`를 올릴 수 있는 것은 설치 안내 창을 가진 GUI 프로세스뿐**이고 쓰기는 원자적 read-modify-write다; 코드 주석에 「기록자는 하나」와 그 트리거 조건을 남긴다 | 골격-앱 | `app/Sources/App/Settings.swift`, `app/Sources/App/SetupWindowController.swift`, `app/Sources/App/Localization.swift` | 5, 6 | todo | 낼 명령: `swift test --filter testAutoSystemLanguageChangeAdvancesLocaleRevision`(선호는 `auto` 그대로인데 시스템 언어가 바뀌면 **`epoch`가 증가하고 발행 로케일이 새 값**) · `swift test --filter testConcurrentInstancesCannotReuseInstallIdAndEpoch`(헤드리스가 발행만 하고 **쓰지 않음**을 단언 — 같은 `epoch`로 다른 로케일이 나가는 경로가 없다). 앱이 떠 있는 동안의 시스템 언어 변경에 `NSLocale.currentLocaleDidChangeNotification`을 구독할지는 여기서 정하고 근거를 남긴다 | |
| 9 | **장수명 UI 상태 제거.** `SetupWindowController.swift:615`의 `ko_KR` 고정 정적 포매터와 `AppDelegate.swift:47`의 1회 메뉴 구성처럼 **생성 시점에 언어를 굳히는** 자리를 언어 변경에 반응하게 바꾼다. 조회 함수만으로는 즉시 전환이 되지 않는다(리뷰 §4 P1) | 골격-앱 | `app/Sources/App/SetupWindowController.swift`, `app/Sources/App/AppDelegate.swift` | 8 | todo | | |
| 10 | **`SetupWindowController` 문자열 → 키(93개 중 63).** 인벤토리의 메시지 단위를 그대로 쓴다 — 조각 25개는 이미 6문장으로 복원돼 있다. 라벨 인용 3곳은 `%@`로 라벨 키를 받는다(D28). **렌더되지 않는 `**…**`·백틱을 번역 전에 걷어낸다**(번역하면 5배로 늘어난다). **`testCommand`를 기계/셸 페이로드 타입으로 분리한다**(D34) — 영어 고정에 그치지 않고, 로컬라이즈된 상태 메시지와 같은 자리에서 다뤄지지 못하게 타입이 막는다. 조각 연결 3곳(`toolAdvice`의 `+`, `apply(prefix:)`의 접두사 결합, `note +=`)이 D36 게이트의 회귀 사례다. `SetupWindowLayoutTests`의 3개 한국어 단언을 같은 승격에서 고친다 | 문자열-앱 | `app/Sources/App/SetupWindowController.swift`, `app/Tests/AppTests/SetupWindowLayoutTests.swift`, `app/Sources/App/Resources/*.lproj/*` | 6, 8, 9 | todo | | |
| 11 | **나머지 App 타깃 문자열 → 키(30).** `AppDelegate` 메뉴 8 · `Installer` 7 · `PermissionChecker` 5 · `Info.plist`의 `NSAppleEventsUsageDescription`. 라벨 인용 5곳은 `%@`로 받는다(D28). `HostServer`·`Settings`·`Theme`의 한국어는 로그·`fatalError`라 **영어화**(파일이 겹치므로 여기서 함께) | 문자열-앱 | `app/Sources/App/{AppDelegate,Installer,PermissionChecker,HostServer,Settings,Theme}.swift`, `app/Sources/App/Resources/*.lproj/*` | 6, 9 | todo | | |
| 12 | **앱 카탈로그 정합 + 라벨 인용 관계 게이트.** 키 집합·플레이스홀더·소스 참조·미참조 0·동적 키 0, 그리고 D28의 인용 관계. `#filePath`로 파일을 읽어 `PropertyListSerialization`으로 파싱한다(Bundle 미사용, D7). **red 먼저**(카탈로그가 비었으니 실패), green은 항목 23 이후 | 골격-앱 | `app/Tests/AppTests/LocalizationCatalogTests.swift`(신규) | 6, 10, 11, 23 | todo | | |
| 13 | **재시작 조율(D20).** 진행 중 명령·비동기 claude 전달이 있으면 재시작을 미루거나 알린다. `applicationWillTerminate`가 소켓만 닫는 것을 고쳐 **Warp 헬퍼를 고아로 남기지 않는다** — 취소·정리 경로를 정확히 정의한다. **red**: 전달 중 재시작 요청이 즉시 실행되지 않는다는 테스트 + 헬퍼 종료가 보장된다는 테스트 | 원자성 | `app/Sources/App/AppDelegate.swift`, `app/Sources/App/HostServer.swift`, `app/Sources/App/SetupWindowController.swift`, `app/Sources/Core/ClaudeInjector.swift`, `app/Tests/CoreTests/CoreTests.swift` | 8 | todo | | |
| 14 | **확장 사본 원자적 교체(D19).** 형제 디렉터리에 완전히 만든 뒤 교체하고 `try?`로 실패를 삼키지 않는다. **`install.sh`도 이 항목에 필수로 포함한다**(D54) — 조건부가 아니다: 그 경로에 `rm -rf` 뒤 `ditto`가 있어 같은 부류의 비원자적 교체다. **`extensionCopyNeedsUpdate()`의 사각지대를 전제로 삼지 않는다**(빈 디렉터리는 맵에 안 잡힌다 — 소탕 표). **red**: 복사 도중 실패시키면 완전한 옛 사본이 남는다는 테스트 | 원자성 | `app/Sources/App/Installer.swift`, `install.sh`, `app/Tests/AppTests/` | — | todo | | |
| 15 | **앱 프로토콜: 로케일을 내려보낸다.** ① 응답에 `locale` + **`(installId, epoch)` 세대 쌍**(D32, D48이 `epoch`의 뜻을 정정) — `epoch`는 **해석된 로케일 스냅숏의 리비전**이고 `installId`는 앱 데이터 생성 시 한 번 만들어지는 불투명 값이다. **"모든 응답"은 성립하지 않는다**(D51): 전송 오류·구버전 앱 응답·실패 응답은 메타데이터를 실을 수 없고, 그것들은 **캐시 입력으로서 무동작(no-op)**이다 — 네 응답(성공·검증실패·질의·내부오류)의 계약을 그 관점으로 쓴다 ② 냉시동용 질의에 명령 실행 없이 답한다 — **`HostServer`에만 두고 `Request.swift`는 손대지 않는다**(D23). 성공·검증실패·질의·내부오류 **네 응답 모두**의 로케일 계약을 정의한다(리뷰 §2). D26에 따라 `app.status.extension.waiting` 문구를 "확장이 앱에 말을 걸었다"까지만 말하도록 고친다. **red**: `e2e.sh`에 질의 케이스 + 응답에 `locale`이 실리는 케이스 + `command_template` 없는 요청이 여전히 `{success:false}`인 기존 케이스 유지 | 프로토콜 | `app/Sources/App/HostServer.swift`, `app/Sources/Core/Localization.swift`, `app/e2e.sh`, `app/Tests/CoreTests/CoreTests.swift`, `app/Sources/App/SetupWindowController.swift` | 2, 5, 8 | todo | 낼 명령: `swift test --filter testConcurrentInstancesCannotReuseInstallIdAndEpoch` — **헤드리스 서버는 읽어서 발행만 하고 절대 쓰지 않는다**(D49)를 단언한다 | |
| 16 | **확장 캐시 리듀서 + 폴백 + 재렌더.** `(installId, epoch)`로 캐시를 갱신하는 **순수 함수**(D32: `installId`가 다르면 무조건 수용, 같으면 `epoch >`일 때만), `storage.local` 값 검증, 콘텐츠 스크립트 통지. 렌더는 질의를 기다리지 않는다(D15). `sendToNativeHost()`가 실패 응답을 던져 버려 메타데이터를 잃으므로(`background.js:232`) **의도적 리팩터가 필요하다** — `locale`을 JSON에 더하는 것만으로는 갱신되지 않는다. **확장이 자기 순번으로 울타리를 친다**(D50): 요청마다 단조 증가하는 `requestSeq`를 붙이고 **자기가 적용한 최고 `requestSeq`보다 낮은 응답은 무시**한다 — 순서는 앱이 준 숫자가 아니라 확장 자신이 보낸 순서로 정해지므로 구버전 앱에도 성립한다. `(installId, epoch)`는 그 위에서 앱 쪽 순서를 정한다. **리셋·복구 규칙**(D51): `installId`가 있는데 `epoch`가 없거나 형식이 틀리면 **미지 상태로 취급해 채택도 덮어쓰기도 하지 않는다**. **red 먼저** | 프로토콜 | `extension/background.js`, `extension/content.js`, `extension/options.js`, `extension/i18n.js`, `tests/i18n.test.js`(신규) | 15, 17 | todo | 낼 명령: `node --test tests/i18n.test.js`. 각 이름이 **단언하는 것**(D54 — 콜백이 돌아온 것은 단언이 아니다) — `an out-of-order response…`: 같은 `installId`에 새 epoch 뒤 옛 epoch를 먹이고 **최종 캐시 값** · `a failed query…`: 유효한 캐시에서 시작해 **캐시 쓰기도 통지도 없었음** · `a successful response without locale…`: 버려지는 목이 아니라 **유효한 세대를 실은 통상 명령 응답 경로**를 태운다 · `a corrupt storage.local value…`: 채택되지도 **다시 쓰이지도** 않음 · `a different installId…`: 무조건 수용 + **뒤늦게 도착한 옛 인스턴스 응답이 현재를 덮지 않음**(D50) · `the same installId with an equal epoch…`: **다른 로케일**로 먹여야 규칙이 실제로 검사된다 · `an unknown locale in a response…` · `a malformed generation field…`(D54 신규 2건). **재그리기 3건은 DOM 연결성이 아니라 여러 번의 재그리기에 걸친 실제 native 전송 횟수와 리스너 수를 단언한다** — `the locale observer is registered once, not once per redraw`·`a redraw does not detach a button whose click is in flight`·`a redraw does not invalidate a command already sent to the host`. 이월 실행 요청: `late response from prior install` | |
| 17 | **확장 i18n 골격.** `extension/_i18n/<태그>.js` 5벌 + 조회 헬퍼(`chrome` 없이 Node 로드 가능, 조회는 호출 시점) + `_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`에 **`extName`·`extDescription` 두 키만** + `manifest.json`의 `default_locale`·`__MSG_…__`·`content_scripts` 순서 + `background.js`의 `importScripts`. 리뷰 §3이 「따로 승격할 수 없다」고 지적한 묶음이라 한 항목이다. 로드 순서는 정적으로 보장된다(Chrome 문서: `js` 배열 순서대로 주입). 확장 ID가 바뀌지 않는지 확인해 근거에 적는다 | 골격-확장 | `extension/manifest.json`, `extension/i18n.js`(신규), `extension/_i18n/*.js`(신규), `extension/_locales/**`(신규), `extension/options.html`, `extension/background.js` | — | todo | | |
| 18 | **프리셋 안정 식별자.** `PR_PRESETS`/`ISSUE_PRESETS`/`REPO_PRESETS`에 `id`를 더하고 `<select>`의 value·조회 키를 `name`→`id`로 옮긴다(`options.js:86`·`:435`). `DEFAULT_*`의 `label`도 같은 경로 | 골격-확장 | `extension/defaults.js`, `extension/options.js`, `tests/buttons.test.js` | — | todo | | |
| 19 | **버튼 지문의 정체성 규칙(D18·D33·D52, P0).** 지문 = **`runButton`이 실제로 보내는 정규화된 페이로드**에서 파생한다(D52) — `defaults.js:327`은 원본 `claudeInputs`를 보존하는데 `background.js:247`은 보내기 전에 trim하고 빈 입력을 지우므로, 정규화가 어긋나면 **지문은 다른데 native 메시지는 바이트 동일한** 두 버튼이 생긴다. 정체성은 컬렉션으로 한정해 **`(kind, index, executionFingerprint)`**이고, 이것은 **실행 정체성이지 보안·UX 정체성이 아니다**. 코드가 이미 답을 준다 — `toStoredButton`(`defaults.js:504-511`)이 uid를 떼어 내 **저장된 버튼에는 영속 id가 없고**, `runButton`(`background.js:247-266`)이 `command_template`+`claude_inputs`만 보내 **`face`·`label`은 확장 밖으로 나가지 않는다**. 네 갈래의 답: **이름만 바꾼 편집** → 지문 불변, 클릭 수용(오늘은 거부 = 오탐) · **커스텀 버튼** → 자기 `command`+`claudeInputs`가 정체성(스키마 변경 불필요) · **프리셋 파생 저장 스냅숏** → 프리셋 id는 저장되지 않고 저장되어서도 안 된다(CLAUDE.md), 스냅숏의 명령이 정체성 · **복제 버튼** → 동작이 같으면 지문도 같다(아래 잔여). **red 먼저**: `a fingerprint check cannot fail because two contexts resolved different locales`. `tests/buttons.test.js:366`의 `labelChanged`가 오늘 「달라야 한다」를 단언하므로 **같은 승격에서 뒤집고 이유를 주석에 남긴다**. 지문 의미가 좁아지는 것이 마이그레이션 통지에 영향을 주는지 확인해 근거에 적는다 | 골격-확장 | `extension/defaults.js`, `extension/background.js`, `extension/content.js`, `tests/buttons.test.js` | 18 | todo | 낼 명령: `node --test tests/buttons.test.js`. `normalized execution payload fingerprint` — **정규화 전후로 native 메시지가 바이트 동일한 두 버튼은 지문도 같다**를 단언한다(trim·빈 입력 제거를 통과시킨 뒤 비교). 복제 버튼 잔여는 D52에서 **수용됨**: 명령과 `claudeInputs`가 같으면 요청과 실행이 동일하므로 명령 선택 실패를 만들지 않는다 | |
| 20 | **소유권 레지스트리 + 정합 게이트(D24·D37).** 레지스트리가 생성기의 동기화 책임을 대신하므로 검사는 5가지다 — 모든 논리 ID에 소유자가 **정확히 하나** · 소유된 카탈로그 항목이 전부 선언된 ID로 매핑 · **고아·미선언 항목 0** · 예외 항목이 명시적·유한·정당화됨 · 소비자가 선언된 소유자/키를 쓴다. **플레이스홀더·마크업 유효성은 별도 검사**이고, **조각 연결 금지(D36)도 여기서 구조로 검사한다**(선언된 플레이스홀더 외의 런타임 연결 0). 값 중복은 3단 — 저장소 **간** 완전일치 red · 저장소 **내** 완전일치 red + 명시 예외 목록 · 부분 중복 미검사. 예외가 실제로 필요하다: `허용됨`이 두 맥락에 정당하게 있고 확장에도 stale 배너 ↔ `SAVE_CONFLICT_MESSAGE` 중복이 있다. **알려진 잔여를 근거 칸에 적는다**(D37): 다른 ID를 받은 의미적 중복 · 부분 중첩 · 저장소 간 번역 드리프트는 잡지 못한다. `_locales` 키가 정확히 2개인 것도 여기서 고정 | 골격-확장 | `tests/i18n.test.js`, 소유권 선언 파일(신규) | 17, 18, 21, 22, 23 | todo | | |
| 21 | **옵션 페이지 문자열(76).** `options.html` 산문 37덩이(4,905자) + `options.js` 카드 템플릿·상태·`confirm()`·마이그레이션 패널. **마크업 방침 C**: 값에는 태그를 두지 않고 `%n$s` 자리에 JS가 `<code>`로 감싼 리터럴을 넣는다(`<code>` 안은 거의 전부 번역 금지 리터럴). **예외 A**는 번역돼야 하는 단어를 강조하는 `<b>` 6곳뿐이고, 그 경우만 마크업째 담되 게이트에 **태그 균형·태그 집합 일치** 검사를 넣는다. **방침 B(문장을 조각으로 쪼개 JS가 조립)는 기각** — 앱에서 25조각을 6문장으로 되돌린 이유와 정면충돌한다. **복수형 2건을 리라이트한다**(D31a). 단 `%2$s`는 **우리가 D36을 스스로 어긴 자리라 철회한다**(D55) — 로컬라이즈된 조각을 플레이스홀더로 끼워 넣는 것이 바로 우리가 구조로 금지한 조각 조립이다. 대신 **「누락 있음」/「누락 없음」 두 갈래를 각각 완결된 메시지 ID로 고른다**: `ext.migration.applied` = `Commands updated in the form: %1$d. Press Save to apply.` / `ext.migration.appliedWithDeclined` = `Commands updated in the form: %1$d. %2$d changed since the preview was built and were left alone. Press Save to apply.` 플레이스홀더는 **스칼라 값이나 선언된 완결 치환에만** 쓴다. (`%1$d of %2$d selected`는 이미 수 중립이라 그대로.) `item.source`의 raw enum(`verbatim`/`prefix`) 노출을 번역 대상으로 승격할지 식별자로 남길지 정한다 | 문자열-확장 | `extension/options.html`, `extension/options.js`, `extension/_i18n/*.js` | 17, 18 | todo | | |
| 22 | **나머지 확장 문자열(49).** `defaults.js`(프리셋 `name` 11 + repo `face` 3 + `BUTTON_CHANGED_ERROR` + `'New Button'`)·`content.js`(3)·`background.js`(`PAGE_CHANGED_ERROR`)·`migrations.js`(14). **복수형 1건을 정확히 이 문구로 리라이트한다**(D31a, `describeSkipped`): `Unusable entries skipped in %1$s: %2$d`. `migrations.js` `customNote`의 렌더 안 되는 백틱을 번역 전에 걷어낸다. **콘솔 전용 문자열은 영어 유지** | 문자열-확장 | `extension/{defaults,content,background,migrations}.js`, `extension/_i18n/*.js` | 17, 18, 19 | todo | | |
| 23 | **`en` + `ko` 카탈로그 본문.** `ko`는 현재 문자열의 이전, `en`은 새로 쓴다. **정본 라벨 레지스트리(D30·D35)**: 12개 ID 전부를 **레지스트리에 등재하고 그것이 정본**이다 — README·`install.sh`·검사 목록·이슈 #24는 소비자이자 증거다. 문서를 읽는 검사는 소비자 검사로 남기고(README 10 · `install.sh` 2 · 검사 목록 1), 문서에 없는 2개(`Request Accessibility Permission`·`Extension`)도 레지스트리에 등재해 테스트가 덮게 한다 — 그래야 문서가 인용을 그만두어도 라벨이 검사에서 조용히 빠지지 않는다 | 번역본 | `app/Sources/App/Resources/{en,ko}.lproj/*`, `extension/_i18n/{en,ko}.js`, `extension/_locales/{en,ko}/messages.json`, `app/Tests/AppTests/CanonicalLabelTests.swift`(신규) | 10, 11, 21, 22 | todo | | |
| 24 | **`ja` + `zh-Hans` + `zh-Hant` 카탈로그 본문.** 모델 번역 초벌을 그대로 싣는다(사용자 결정). 게이트가 보장하는 것은 키·플레이스홀더 정합뿐이고 **번역 품질은 잡지 못한다** — 고지는 항목 25 | 번역본 | `app/Sources/App/Resources/{ja,zh-Hans,zh-Hant}.lproj/*`, `extension/_i18n/{ja,zh-Hans,zh-Hant}.js`, `extension/_locales/{ja,zh_CN,zh_TW}/messages.json` | 23 | todo | | |
| 25 | **문서.** `README.md:80` 노트 블록 제거 · `install.sh:99`·`:101` gloss 제거(#24 체크박스) · `docs/new-terminal-checklist.md:135`의 로그 인용 갱신(**이미 낡았다** — 인용 `입력 N개 중 M개 전달` ↔ 실제 `claude(pid …) 입력 N개 중 M개 보냄(수신은 확인하지 않는다)`) · 새 로케일 추가 시 손댈 지점 목록 · **PR 본문·README에 "기계 번역 초벌, 개선 PR 환영" 명시** · **언어 전환의 재시작 경계·TCC 잔여·수렴 전 두 언어 구간을 README에 기록** · **D25 레거시 헤더 인식 코드를 언제 지울지 트리거 조건** · **`CLAUDE.md`의 "Extension-install completion is judged by a recorded socket request" 문장을 D26 범위로 갱신** · `CLAUDE.md`에 이번 실측 반영 · `docs/context/`에 i18n 결정 항목 추가 | 문서 | `README.md`, `install.sh`, `docs/new-terminal-checklist.md`, `CLAUDE.md`, `docs/context/*` | 1, 2, 4, 23 | todo | | |

| 26 | **주석의 주장 정정(R2 증분 리뷰, D56).** 6건 — `WarpControl.swift:16`(보증→목적) · `WarpControl`의 `reclaimStaleWarpTabConfigs` 목적절 2개 · `ClaudeInjector.swift:60`(수신→렌더, 화면이 우리 pane임을 전제로) · `:197`(Ctrl+U 성공→화면 관측) · `ClaudeInjector`의 `expecting` 목적절 · `TerminalRunner`의 fallback spawn 모호성. **동작 변경 없음 — 주석뿐** | 영어화 | `app/Sources/Core/{WarpControl,ClaudeInjector,TerminalRunner}.swift` | 1 | verified | 게이트 4종 그린(swift `Executed 351 tests, with 1 test skipped and 0 failures` · node `# pass 158 / # fail 0` · `build.sh` → `Build complete: …` · `e2e.sh` PASS 9). `git diff --stat` → 3파일 12줄(+계획). 범위 밖 무변경: `git diff --stat app/Tests extension/ tests/ app/Sources/App app/Sources/WarpHelper app/Sources/Relay` → 빈 출력. 소탕 양방향: 번역이 추가한 절대어법 **79건** 순방향 대조(수정 1) + 한국어 목적 구문 **8건** 역방향 대조(수정 2 추가) + 나머지 주장을 `:191`·`:201`·`CLAUDE.md`와 대조(수정 3). 나머지 73건은 원본과 세기가 같다 | `<이 커밋>` |
- 항목 하나는 승격 하나에 들어갈 크기다. 같은 부류는 한 승격에 묶이고, 파일 집합이 겹치지 않는 부류만 따로 승격할 수 있다. 승격 칸에는 커밋 해시를 적는다
- `의존`: 다른 항목의 계약(시그니처·불변식·생성물·호출 순서)을 전제하면 그 번호를 적는다. 그 항목에 정정(A′)이 오면 이 항목의 근거를 다시 낸 뒤에야 최종 리뷰에 들어간다
- **게이트 항목(7·12·20)은 red를 먼저 내고 green은 카탈로그가 찬 뒤**다 — `의존`에 최종 카탈로그 항목이 들어 있는 것은 그 뜻이다
- 상태 사다리: `todo` → `wip` → `claimed` → `verified` → `cleared` → `agreed`. 이탈은 `dropped`
- `claimed`까지가 구현 에이전트가 스스로 올리는 상한이다. `verified`·`cleared`·`agreed`·`dropped`는 드라이버의 결정이고, 드라이버가 문구를 지정하면 에이전트가 그대로 적는다
- 근거 칸에는 **재실행 가능한 것**만: 명령과 결과 줄, 테스트 이름과 수, 수치를 낸 스크립트 경로. "확인했다"도 메커니즘 설명도 근거가 아니다 — 1행이 기준이다

## 결정 원장

append-only. 결정의 이유, 기각한 반박과 근거, 잔여 불확실성 — 코드 서술은 여기에도 넣지 않는다. 기존 행을 고치지 않고 새 행을 더한다.

| # | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|
| D1 | 이슈 #24가 지목한 대로 SwiftPM `resources:` + `Bundle.module`로 카탈로그를 싣는다 | **기각** — `.lproj`를 `Contents/Resources/`에 직접 두고 `Bundle.main`으로 읽는다 | 생성된 접근자가 보는 곳은 `Bundle.main.bundleURL/<Name>.bundle`(= `.app` **최상위**)와 바이너리에 박힌 **절대 `.build` 경로** 둘뿐이고, 없으면 `Swift.fatalError`. 실측: 번들에 복사하지 않은 상태에서도 `.build/…/L10nProbe_App.bundle`로 해석돼 **빌드 기계에서는 누락이 보이지 않는다** · R0 | **게이트 없이는 같은 부류다** — 조용한 실패가 `build.sh`로 옮겨갔을 뿐이라는 R0 리뷰 지적이 옳다. D21이 그 구멍을 닫는다 |
| D2 | `CFBundleDevelopmentRegion`은 표시에 영향이 없으니 `ko`로 둬도 된다 | **기각** — `en`으로 바꾼다 | 실측: `AppleLanguages=(fr)`일 때 dev region `ko` → `["ko"]`, `en` → `["en"]` · R0 | macOS 앱별 언어 목록 의존은 D8이 흡수 |
| D3 | Core·Relay·WarpHelper도 로컬라이즈한다 | **기각** — 영어 단일 언어 | ① `app/e2e.sh`가 Core 오류 문자열 9건을 `grep -qF`로 고정한다 ② 확장 콘솔이 표면이다 ③ `BaseDirectoryProblem` 선례가 있다 · R0 | 근거 ②의 표현은 D27이 정정한다 |
| D4 | 확장은 자체 사전 + `storage.sync` 언어 설정으로 런타임 전환을 지원한다 | **기각** — `chrome.i18n` + `_locales` | manifest `name`/`description`은 다른 방법이 없고, Chrome은 `_locales`가 있으면 `default_locale`을 요구한다(공식 문서). 코드는 `ko`·`ja`·`zh_CN`·`zh_TW` · R0 | D8·D9가 UI 부분을 뒤집는다 |
| D5 | 프리셋 `name`을 그대로 로컬라이즈한다 | **기각** — 먼저 `id`를 도입한다(항목 18) | `options.js:86`이 value에 이름을 넣고 `:435`가 이름으로 되찾는다 · R0 | 저장된 `label`은 스냅숏이라 저장 시점 언어로 남는다 |
| D6 | `defaults.js`에서 모듈 로드 시점에 `chrome.i18n.getMessage`를 부른다 | **기각** — 호출 시점 조회 | `tests/{buttons,migration,layout}.test.js`가 `chrome` 전역 없이 실행한다. 기준선 158 pass · R0 | 없음 |
| D7 | 카탈로그 정합 테스트를 `Bundle`로 쓴다 | **기각** — 파일을 읽어 파싱 | 실측: `swift test` 안 `Bundle.main`은 Xcode `usr/bin`이고 조회는 키를 반환. `Bundle(url:)`은 호스트 언어(ko-KR)로 해석. `Bundle(path: <loc>.lproj)`만 결정적. `.strings`는 `PropertyListSerialization`으로 파싱됨 · R0 | 없음 |
| D8 | 앱과 확장이 각자 플랫폼 로케일을 따른다 | **기각 — 언어는 하나이고 사용자가 고른다. 소유자는 앱이다.** 피커는 설치 안내 창, 저장은 앱 `Settings`, 기본값 `auto`. 확장은 native messaging으로 받아 `storage.local`에 캐시하고 그것으로 그린다. 앱이 없으면 `chrome.i18n`으로 폴백 | 사용자 답변 "한 언어가 보이고 선택할 수 있어야지"(2026-08-22). 설치 안내 창은 **확장이 설치되기 전에** 보는 화면이라 확장이 정본이면 그 시점에 답이 없다. CLAUDE.md의 터미널 선택 규약과 같은 방향 | 확장이 앱을 못 만나는 동안 두 언어가 갈릴 수 있다 → D17이 계약으로 만든다 |
| D9 | 확장 UI를 `chrome.i18n`으로 그린다 | **기각 — `chrome.i18n`은 manifest의 `name`/`description`에만.** UI는 자체 사전 | `chrome.i18n`은 Chrome UI 언어에 묶이고 런타임 전환이 없다(D4). D8이 요구하는 "앱이 정한 언어로 확장이 그린다"를 만들 수 없다 | 메커니즘이 둘이 된다 → D24가 소유권 선언으로 경계를 만든다 |
| D10 | `warpTabConfigHeader`를 한국어 기계 마커로 남긴다 | **기각 — 영어로 바꾸고 레거시 상수를 둔다** | 영어 트리에 한국어 상수를 남기는 것보다 회수 경로를 명시하는 편이 표면이 작다 | D25가 「영어」를 「언어 중립 토큰」으로 정정한다 |
| D11 | 로컬라이즈된 창에 영어 기술 사유가 섞이는 것 | **허용** | 리팩터는 범위 밖이고, 기술 사유는 이슈에 붙여 넣는 진단 문자열이라 영어가 낫다 | 불만이 오면 `BaseDirectoryProblem` 선례로 쪼갠다 |
| D12 | `zh-Hant`/`zh_TW` 하나로 `zh_HK`까지 덮는다 | **채택** | 실측(5개 `.lproj`): `zh-HK`·`zh-Hant-HK`·`zh-MO`·`zh-TW` → `["zh-Hant"]`, `zh`·`zh-SG` → `["zh-Hans"]`, `en-GB`·`pt-BR` → `["en"]` · R0 | 없음 |
| D13 | 진단 문자열을 로컬라이즈한다 | **기각 — 영어 단일 언어** | 사용자 결정(2026-08-22). `docs/new-terminal-checklist.md:135`가 로그 줄을 인용해 수기 검사에 쓴다 | 근거의 표현은 D27이 정정 |
| D14 | 피커가 우리 문자열만 바꾸고 AppKit 크롬·TCC는 `AppleLanguages`를 따르게 둔다 | **기각 — 앱이 그리는 모든 것이 고른 언어를 따른다.** 우리 문자열은 즉시, AppKit 크롬은 `AppleLanguages`를 써서 **재시작 뒤** | 실측(`probe/appkit.py`): ⓐ AppKit이 올라온 뒤 쓰면 같은 프로세스 무효(`["ko"]`·`확인` 유지, readback만 `["ja"]`) ⓑ 다음 기동엔 반영(`["ja"]`·`OK`) ⓒ **AppKit을 건드리기 전에** 쓰면 같은 프로세스도 반영(`zh-Hant`·`好`) ⓓ 우리 문자열은 `Bundle(path:)`라 `AppleLanguages`와 무관 | **TCC 프롬프트는 통제 밖일 수 있다** — 실측 못 했다(사용자의 살아 있는 권한을 리셋해야 한다). 항목 8이 실측하고 안 되면 문서에 남긴다 |
| D15 | 옵션 페이지가 질의 응답을 기다렸다가 그린다 | **기각 — 렌더링은 절대 질의를 기다리지 않는다.** 질의가 앱을 깨우는 것 자체는 허용 | relay는 앱을 띄우며 최대 25초 블로킹한다(`Relay/main.swift:18`+`:28-31`). 앱이 없는 사용자에게 25초 빈 화면은 그 자체로 결함 | 질의 실패를 캐시에 굳히면 안 된다 → D17 |
| D16 | 로케일 질의가 「확장 설치 완료」 판정을 넓히는 것 | **허용 — 같은 부류의 증거다** | 규칙의 이유는 "준비된 폴더는 Chrome이 로드했는지 말해 주지 못한다"이고, 질의는 로드된 확장이 보낸 실제 소켓 요청이다 | D26이 그 증언 범위를 좁힌다 |
| D17 | "한 언어" 목표가 D8·D15와 충돌한다 | **수용 — 목표를 「최종적 일관성」으로 다시 쓰고 동기화 계약을 명시한다.** 새 불변 원칙: 모든 렌더 경로는 검증된 단조 로케일 스냅숏 하나를 쓴다. 계약 5가지(세대값·옛 성공 응답 무효·`locale` 없는 응답은 보존·`storage.local` 검증·콘텐츠 스크립트 통지)를 못박는다 | 리뷰 §1·§2 | 앱 기동 직후·앱 실패 구간에 두 언어가 보일 수 있다 — 문서에 적는다 |
| D18 | `buttonFingerprint()`가 `face`·`label`을 포함해 로케일이 갈리면 명령이 안 바뀌었는데도 클릭이 거부된다 | **수용 — P0. 지문에서 로컬라이즈된 표시 문자열을 뺀다.** 답을 바꾸는 것은 명령과 안정 id이지 표시 언어가 아니다. **red 먼저** | 리뷰 §4 · `defaults.js:425` | 지문 의미가 좁아지는 것이 마이그레이션 통지에 영향을 주는지 항목 19가 확인 |
| D19 | 확장 배포가 원자적이지 않다 | **수용 — 형제 디렉터리에 완전히 만든 뒤 교체하고 실패를 삼키지 않는다** | 리뷰 §4·§7 · `Installer.swift:101`·`:153`. CLAUDE.md 작업 원칙(결함 부류를 원천에서) | `install.sh`도 같은 항목에 넣을지는 파일 집합을 보고 정한다 |
| D20 | 언어 변경 재시작이 진행 중 명령·비동기 전달을 끊는다 | **수용 — 전달이 진행 중이면 재시작을 미룬다** | 리뷰 §4·§7 · `HostServer.swift:120`. 단순 UX가 아니라 CLAUDE.md의 신뢰 경계다 — Warp 헬퍼의 유일한 방어선이 수명이고, 재시작이 그 계약을 깨면 헬퍼가 고아로 남는다 | 취소·정리 경로를 정확히 정의해야 한다 — 항목 13 |
| D21 | D1이 더 안전하다고 증명되지 않았다 | **수용 — 최종 번들 대조 게이트를 추가한다.** D1은 유지한다 | 리뷰 §6·실행요청 4. `Bundle.module`은 없으면 `fatalError`라 대안이 더 낫지 않다 | 게이트를 빌드 후 스크립트로 둘지 테스트로 둘지 항목 7이 정한다 |
| D22 | 기동 시 해석된 `auto` 값을 `AppleLanguages`에 쓰면 시스템 설정이 영구 앱 오버라이드가 된다 | **수용 — `auto`일 때는 키를 쓰지 않고 지운다.** 명시적 언어일 때만 쓴다 | 리뷰 §2 | 전용 프로브로 실측 — 항목 8 |
| D23 | 로케일을 `Request.swift`(Core)에 넣지 마라 | **수용** | 리뷰 §3. CLAUDE.md의 relay·Core·App 분리와 같은 방향이고, 최상위 미지 키를 무시하는 기존 동작을 보존해야 한다 | 없음 |
| D24 | 「정본 단일성」의 값 중복 검사가 너무 엄격하고 동시에 너무 약하다 | **수용 — 「선언된 소유권」으로 바꾼다.** 논리 메시지 ID마다 사는 카탈로그를 선언하고 게이트가 강제한다. 값 중복은 **3단** — 저장소 간 완전일치 red · 저장소 내 완전일치 red + 명시 예외 목록 · 부분 중복 미검사. 생성기는 계속 두지 않는다(D9 유지) | 리뷰 §6. 3단이 필요한 실측: `허용됨`이 Apple Events(`PermissionChecker:14`)와 손쉬운 사용(`SetupWindowController:717`) 두 맥락에 정당하게 있고, 확장에도 stale 배너 ↔ `SAVE_CONFLICT_MESSAGE` 중복이 있으며, 도구 조언 4건이 같은 앞부분을 공유한다 — 지금 문구대로면 **오늘 red** | 없음 |
| D25 | D10은 전진 호환만 된다 | **부분 수용 — 새 헤더를 언어 중립 토큰으로 만든다.** 사람이 읽는 설명은 아래 줄로 분리. 구 헤더는 회수용으로 계속 인식. 롤백 비호환은 문서화하고 받아들인다 | 리뷰 §4·§7. 토큰으로 만들면 이 마커는 **언어 때문에 다시 바뀔 일이 영영 없다** — 부류를 원천에서 닫는다 | 구 헤더 인식 코드 제거 트리거는 항목 25가 기록 |
| D26 | D16은 "어떤 확장 컨텍스트가 호스트에 닿았다"의 증거일 뿐이다 | **수용 — D16을 좁힌다.** 질의는 "확장이 로드돼 앱에 말을 걸었다"까지만 증언한다. 설치 안내 창 문구가 더 강하게 말하면 고친다 | 리뷰 §6 | 없음 |
| D27 | D3·D13의 근거 "사용자에게 닿지 않는다"가 틀렸다 | **수용 — 근거를 고친다.** 결론은 유지, 이유를 **"명시적으로 영어인 진단 표면"**으로 다시 쓴다 | 리뷰 §6. D3·D13의 근거 칸은 append-only라 고치지 않고 이 행이 정정한다 | 없음 |
| D28 | 라벨 상호 인용 8곳이 관계로 표현돼 있지 않다 | **수용 — 본문이 `%@`로 라벨 키를 받고 게이트가 검사한다** | 에이전트 실측(인벤토리): `[등록/업데이트]` 3 · `[Chrome에 설치하기]` 2 · `[권한 요청]` 2 · 확장의 `[Save]`·`[Got it]`·`[Export (JSON)]`. 키만 뽑으면 버튼은 새 라벨인데 본문은 옛 라벨을 부르는 상태가 **5개 로케일에서 각각** 가능해진다 | 없음 |
| D29 | `testCommand`도 UI 문자열이니 번역한다 | **기각 — 셸 페이로드다. 영어 고정, 비목표** | `echo 'Terminal Checkout: 연결 OK'`는 칩으로 보이면서 실행된다. 아포스트로피를 쓰는 언어에서 `echo '…'` 인용이 깨져 테스트 버튼이 셸 오류를 낸다. `{cd}`가 화이트리스트에서 면제된 것과 같은 부류 — **값이 셸 구문인 문자열** | 이 부류를 소탕 표가 전수로 센다 |
| D30 | 정본 라벨은 #20 표의 10개다 | **기각 — 12개이고 어느 한 곳도 12개를 다 갖고 있지 않다** | 실측(`grep`): README 10(각 2∼3회) · `install.sh` 2 · 검사 목록 1. 이슈 #24 표에만 있는 것 2(`Request Accessibility Permission`·`Extension`), README에만 있는 것 2(`Repository base folder`·`Choose Folder…`) | 없음 |
| D31 | 5개 로케일이면 복수형 기계(`.stringsdict` 등)가 필요하다 | **기각 — 넣지 않는다. 영어 문구를 리라이트한다** | 앱 UI 복수형 **0건**(개수 문장은 전부 로그 → D13), 확장 **3건**(`migrations.js:657`·`options.js:925`·`:927`). ko/ja/zh는 복수형이 없고 `en`만 갖는다 — 기계를 넣으면 카탈로그 스키마가 두 모양이 되고 정합 게이트가 커지는데 **4/5 로케일에서 폼이 항상 빈다** | 회피가 정당하려면 문구가 **실제로 수 중립**이어야 한다 — 정확한 문구를 항목 21·22에 박았다(D31a) |
| D31a | 리라이트한 문구가 여전히 수를 의미하면 부류를 감춘 것이다 | **수용 — 정확한 문구를 계획에 박고 0·1·2·다수를 확인한다.** 셋 다 「명사 레이블 + 콜론 + 수」 형태로 바꾼다: ① `Unusable entries skipped in %1$s: %2$d` ② `Commands updated in the form: %1$d. Press Save to apply.%2$s` ③ ` Changed since the preview was built and left alone: %1$d.` | 이 형태에서 명사는 **수와 일치하지 않는 범주 레이블**이라 0·1·2·다수 모두에서 영어가 자연스럽다("Commands updated: 1"은 UI 레이블 관용). ko/ja/zh는 수 분류사가 굴절하지 않아 그대로 옮겨진다. 검증자 §3 | ①은 `count>0`일 때만 방출되고 ②는 0이 될 수 있다(전부 미선택) — 둘 다 위 형태에서 자연스럽다 |
| D32 | 단조 세대값은 정수 하나면 된다 | **기각 — `(installId, epoch)` 쌍이다.** `epoch`는 앱 `Settings`에 영속하는 단조 비감소 정수로 **명시적 언어 변경 때만** 증가한다. `installId`는 앱 데이터가 새로 만들어질 때 한 번 생성되는 불투명 값이다. 확장의 캐시 갱신 규칙: `installId`가 캐시된 것과 **다르면 무조건 수용**(앱이 재설치·초기화됐고 앱이 정본이다), **같으면 `epoch >` 일 때만 수용**. 실패 응답·`locale` 없는 응답·미지 값은 캐시를 보존한다 | 검증자 §1: "A plain integer can become ambiguous after reset." 순서 문제는 **동시에 떠 있는 응답들 사이에서만** 생기고 재기동·재설치를 가로질러 생기지 않는다 — 세션 안에서는 `epoch`가 순서를 정하고, 세션이 갈리면 `installId` 변화가 그것을 알려 준다. 리셋으로 `epoch`가 0으로 돌아가도 `installId`가 달라 모호해지지 않는다 | 없음 |
| D33 | 지문에서 로컬라이즈된 표시 문자열을 빼면 끝이다 | **부분 수용 — 정체성 규칙을 명시한다. 지문은 「같은 버튼인가」가 아니라 「같은 것이 실행되는가」다.** 지문 = `{command, claudeInputs}`. **어느 버튼인지는 `index`가, 무엇이 실행되는지는 지문이 답하고, 둘의 쌍이 정체성이다** | 코드로 확인한 사실 셋: ① **저장된 버튼에는 영속 id가 없다** — `toStoredButton`(`defaults.js:504-511`)이 `face`·`label`·`command`·`claudeInputs` 넷만 남기고 uid를 떼어 낸다(CLAUDE.md: 저장 데이터에서 발견된 uid는 버린다) ② **앱에 건너가는 것은 정확히 그 둘뿐이다** — `runButton`(`background.js:247-266`)이 `{command_template: button.command, variables}` + `claude_inputs`만 보낸다. `face`·`label`은 확장 밖으로 나가지 않는다 ③ 그래서 `command`+`claudeInputs`가 같은 두 버튼은 **바이트 동일한 native 메시지**를 만든다 | **요구사항 ③(명령이 같은 두 버튼 구별)은 버튼 단위로는 충족하지 못한다** — 복제 버튼처럼 동작이 같고 라벨만 다른 쌍은 지문이 같다. 그 혼동은 관측 불가하다(실행 결과가 동일)지만 **버튼 단위 정체성이 필요해지면 저장 스키마에 영속 id를 넣어야 하고 그것은 `SETTINGS_VERSION` 인상을 뜻한다** — 이번 범위 밖이고, 필요해지는 순간을 항목 19가 트리거로 기록한다 |
| D34 | `testCommand`는 영어로 고정하면 된다 | **부분 수용 — 불변 원칙으로 올리고 타입으로 분리한다.** **로컬라이즈된 카탈로그 값은 셸·AppleScript·TOML·터미널 입력에 절대 들어가지 않는다.** `testCommand`는 영어 고정에 그치지 말고 **기계/셸 페이로드 타입**으로 분리해 로컬라이즈된 상태 메시지와 같은 자리에서 다뤄지지 못하게 한다 | 검증자 §3. `{cd}`가 문자 화이트리스트에서 면제된 것과 **같은 부류**이고, CLAUDE.md의 그 규칙("Never let request-supplied text into this class")과 나란히 둔다. 고정(pinning)을 감사 면제로 쓰지 않기 위해 소탕은 이 불변 원칙의 관점으로 전수로 한다 | 동적 텍스트가 언젠가 셸에 들어가야 하면 **테스트된 셸 리터럴 인코더 하나**를 거치게 한다 — 지금은 그런 자리가 없다 |
| D35 | 정본 라벨은 문서를 읽어 대조하면 된다 | **수용 — 레지스트리가 정본이고 문서·이슈는 소비자/증거다.** 12개 ID 전부를 레지스트리에 등재하고, 문서에 없는 2개(`Request Accessibility Permission`·`Extension`)도 등재해 테스트가 덮게 한다 | 검증자 §3. "문서를 읽어 대조"는 **소비자 검사**이지 정본이 아니다 — 문서가 라벨을 인용하지 않게 되는 순간 그 라벨은 검사에서 조용히 빠진다 | 없음 |
| D36 | 조각 연결 금지는 관행으로 지키면 된다 | **수용 — 구조 검사로 만든다.** 로컬라이즈된 조각을 런타임에 이어 붙이는 것을 게이트가 금지하고 예외는 **선언된 플레이스홀더**뿐이다. 조건 분기는 번역된 절을 조립하지 말고 **완결된 메시지 ID를 고른다** | 검증자 §3. 우리가 25조각을 6문장으로 되돌린 것을 규칙으로 굳히는 것이다 — 규칙이 없으면 다음 사람이 다시 조각을 만든다. 현재 코드의 위반 사례가 곧 회귀 테스트다(`toolAdvice`의 `+` 연결, `apply(prefix:)`의 접두사 결합, `note +=`) | 없음 |
| D37 | 소유권 선언만 있으면 정본 단일성이 증명된다 | **수용 — 레지스트리가 생성기의 동기화 책임을 대신하고, 무엇을 못 잡는지 명시한다.** 게이트 5가지: 모든 논리 ID에 소유자가 정확히 하나 · 소유된 카탈로그 항목이 전부 선언된 ID로 매핑 · 고아·미선언 항목 0 · 예외 항목이 명시적·유한·정당화됨 · 소비자가 선언된 소유자/키를 쓴다. **플레이스홀더·마크업 유효성은 별도 검사**다 | 검증자 §4 | **알려진 잔여(감추지 않는다)**: 다른 ID를 받은 의미적 중복 · 부분 중첩 · 독립 저장소 간 번역 드리프트는 이 게이트가 잡지 못한다 |
| D38 | `.toml` 마커 토큰은 "지금은 로컬라이즈 안 함"이다 | **수용 — 「영구 기계 프로토콜」로 문서화한다.** "이 토큰은 다시 바뀌지 않는다"를 코드 주석과 `uninstall.sh` 양쪽에 남긴다. 롤백 비호환은 **해결된 설계가 아니라 받아들인 전진 전용 잔여**라고 적는다 | 검증자 §1·§3 | 구버전 바이너리는 새 헤더 파일을 회수하지 못한다 — 피해는 `~/.warp/tab_configs/`에 파일이 남는 것뿐 |
| D47 | D3의 근거 문장 "창에 뜨는 사유는 이미 `BaseDirectoryProblem`처럼 타입으로 넘긴다"가 전수로 참이다 | **기각 — 전수로는 참이 아니다. 결론(Core는 영어)만 유지하고 근거를 정정한다** | 항목 1의 값 흐름 추적에서 나온 반례: `TerminalError.warpTabConfigFailed(String)`는 사유를 **문자열 그대로** 싣고, `testTerminal` → `runInTerminal(.warp)` → `runInWarp` → `writeNewFile`가 던지면 `SetupWindowController.swift:1000`의 `testResultLabel`이 `실패: Warp tab config error: …`로 렌더한다 — Warp를 고른 사용자가 [터미널에서 실행]을 눌렀을 때 TOML 쓰기가 실패하면 도달하는 실제 경로다. 결론이 바뀌지 않는 이유는 D11이 "로컬라이즈된 창에 영어 기술 사유가 섞이는 것"을 이미 허용했고 이 문자열이 정확히 그 부류이기 때문이다. 원장은 append-only라 D3의 근거 칸은 고치지 않고 이 행이 정정한다 | Core 문자열의 목적지는 이제 셋으로 갈린다(로그 44 · 확장 콘솔 3 · **확장 콘솔 + 창 2**) — 소탕 표가 그 분류를 든다 |
| D48 | **P0 — `auto`가 세대 계약과 정면 모순.** 선호가 `auto`로 남아 있으면 시스템 언어 변경이 해석된 로케일을 바꾸지만 D32는 "명시적 언어 변경 때만 `epoch` 증가"라 확장은 `(같은 installId, 같은 epoch, 새 locale)`을 받고 **규칙대로 거부한다** — 확장이 영원히 옛 언어로 남는다 | **수용 — `epoch`는 선호의 리비전이 아니라 「해석된 로케일 스냅숏」의 리비전이다.** 앱은 기동 시와 선호 변경 시 해석된 로케일을 다시 계산하고, 마지막으로 **발행한** 로케일과 다르면 `epoch`를 올리고 둘 다 영속한다. `auto`에서 시스템 언어가 바뀌면 다음 기동에 자동으로 반영된다 | 검증자 §1. D32의 "명시적 언어 변경 때만"이라는 문구가 원인이므로 그 문구를 고친다 | 앱이 떠 있는 동안의 시스템 언어 변경은 다음 기동에 반영된다 — `NSLocale.currentLocaleDidChangeNotification` 구독 여부는 항목 8이 정하고 근거를 남긴다 |
| D49 | **P0 — 같은 `installId`를 공유하는 두 프로세스가 `epoch`를 갈라 놓을 수 있다.** `--headless-server`와 GUI가 같은 번들 ID와 `UserDefaults.standard`를 쓴다(`main.swift:6`). read-modify-write 두 번이 **같은 epoch로 다른 로케일을 발행**할 수 있고, 그러면 동일-epoch 리듀서가 정당한 새 선택을 버린다 | **수용 — 단일 기록자 규칙.** `epoch`를 올릴 수 있는 것은 **설치 안내 창을 가진 GUI 프로세스뿐**이다. 헤드리스 서버는 읽어서 발행만 하고 절대 쓰지 않는다(피커가 없으므로 올릴 이유도 없다). 쓰기는 원자적 read-modify-write로 한다. 이것으로 동시 기록자 케이스가 **존재 자체가 사라진다** — 잠금보다 낫다 | 검증자 §1 | 미래에 두 번째 기록자가 생기면 규칙이 깨진다 — 코드 주석에 「기록자는 하나」와 트리거 조건을 남긴다 |
| D50 | **`installId`가 다르면 무조건 수용은 안전하지 않다** — 리셋·재설치를 가로질러 살아남은 옛 프로세스나 이미 날아가던 relay 응답이 다른 ID를 달고 와서 현재 캐시를 덮는다. "순서 문제는 재설치를 가로지르지 않는다"는 **우리 주장은 불변식이 아니라 가정이었다** | **수용 — 확장 쪽에 자기 순번 울타리를 둔다.** 확장이 요청마다 단조 증가하는 `requestSeq`를 붙이고, **자기가 적용한 최고 `requestSeq`보다 낮은 응답은 무시**한다. 순서는 앱이 준 숫자가 아니라 **확장 자신이 보낸 순서**로 정해진다. `(installId, epoch)`는 그 위에서 앱 쪽 순서를 정한다 | 검증자 §1. 확장은 자기가 어떤 요청의 응답인지 알고 있으므로 이 울타리에는 앱의 협조가 필요 없다 — 구버전 앱에도 그대로 성립한다 | 없음 |
| D51 | **리셋이 원자적으로 정의돼 있지 않다** — 부분 리셋, 잘못된 `epoch`, `installId`를 남긴 채 `epoch`만 되돌리는 마이그레이션이 쌍이 없애려던 모호함을 되살린다. 그리고 항목 15의 "모든 응답에 `locale`+세대"는 전송 오류·구버전 앱 응답에서 성립하지 않아 "실패·`locale` 없음은 캐시 보존" 규칙과 충돌한다 | **수용 — 리셋·복구 규칙과 응답 계약을 명시한다.** `installId`가 있는데 `epoch`가 없거나 형식이 틀리면 **미지 상태로 취급해 캐시를 채택하지도 덮어쓰지도 않는다**. 앱 쪽 복구는 새 `installId`를 발행하는 것이다(D50의 울타리 위에서 정상 경로로 수렴한다). 전송 오류·구버전 응답·실패 응답은 **캐시 입력으로서 무동작(no-op)**이고, 네 응답의 계약을 그 관점으로 다시 쓴다 | 검증자 §1·§3 | 없음 |
| D52 | **지문 정체성 2건 정정** | **수용 — ① 정체성은 컬렉션으로 한정한다: `(kind, index, executionFingerprint)`. ② 지문은 `runButton`이 실제로 보내는 정규화된 페이로드에서 파생한다** — `defaults.js:327`은 원본 `claudeInputs`를 보존하는데 `background.js:247`은 보내기 전에 trim하고 빈 입력을 지운다. 정규화가 어긋나면 **지문은 다른데 native 메시지는 바이트 동일한** 두 버튼이 생긴다. 이것이 **실행 정체성이지 보안·UX 정체성이 아님**을 명시한다 | 검증자 §2 | 복제 버튼 잔여는 **수용됨**: 명령과 `claudeInputs`가 같으면 요청과 실행이 동일하므로 오늘 명령 선택 실패를 만들지 않는다 |
| D53 | 목표 문구 "중간 상태를 남기지 않는다"가 우리가 명시적으로 받아들인 최종적 일관성 구간·전진 전용 롤백과 모순된다 | **수용 — "각 상태 전이가 원자적이다"로 고친다.** 관측 가능한 중간 상태가 없다고 주장하지 않는다 | 검증자 §3 | 없음 |
| D54 | **게이트 오류 3건**: ⑥이 `Localizable.strings`만 바이트 대조하고 `InfoPlist.strings`는 존재만 봐서 **손상된 파일이 통과한다** · ⑦이 "8가지"라면서 6+3을 나열하고 **미지 로케일·잘못된 세대 필드**가 빠졌다 · 항목 14가 `install.sh` 포함을 조건부로 두는데 그 경로에 `rm -rf` 뒤 `ditto`가 있다. 그리고 테스트 이름만으로는 공허한 통과를 막지 못한다 | **전부 수용.** ⑥ → 소스 `.lproj`의 **모든 파일**을 바이트 대조하고 **파일 집합 일치**를 요구한다. ⑦ → 미지 로케일 응답과 형식 오류 세대 필드를 케이스로 추가하고 수를 맞춘다(13건). 항목 14 → `install.sh`를 **필수**로 넣는다. 테스트는 이름 옆에 **무엇을 단언하는지**까지 항목 근거 칸에 적는다 — 콜백이 돌아온 것은 단언이 아니다 | 검증자 §3·§4 | 없음 |
| D55 | **항목 21의 `Commands updated … %2$s`가 D36을 어긴다** — `%2$s`가 로컬라이즈된 조각이면 우리가 방금 구조로 금지한 조각 조립이다 | **수용 — 「누락 있음」/「누락 없음」 두 갈래를 각각 완결된 메시지 ID로 고른다.** 플레이스홀더는 스칼라 값이나 **선언된 완결 치환**에만 쓴다 | 검증자 §3. **우리가 우리 규칙을 어긴 자리**라 그대로 둘 수 없다 | 없음 |
| D56 | 이 부류는 「번역이 주장을 강화한 자리」다 | **기각 — 부류는 「주석의 주장이 같은 파일·`CLAUDE.md`·실측과 어긋나는 자리」이고, 번역 강화는 그 부분집합이다.** 남은 영어화 항목(3)과 이후 모든 번역에 **양방향 소탕**을 적용하고, 불변 원칙으로도 올린다 | 규정을 바꾼 것은 실측이다: 검증자가 낸 표본 4건 중 **번역이 실제로 강화한 것은 1건뿐**(`WarpControl.swift:16` — 한국어 `지우지 않기 **위한** 마지막 확인이다`(목적) → 영어 `is never removed`(보증), 같은 파일 `:366`의 잔여 경쟁과 모순). **2건은 원본 한국어가 이미 모순됐고 번역이 충실히 옮긴 것**(`ClaudeInjector.swift:60`의 원본 `반영 확인이 비로소 claude의 **수신**을 뜻하게 된다` ↔ `:191`·CLAUDE.md · `:197`의 원본 `우리가 **성공적으로 비웠거나**(Ctrl+U)` ↔ `:201`·CLAUDE.md의 "the clear succeeded라고 쓰지 마라"). 1건은 영어 표현만 모호(`TerminalRunner`의 fallback spawn). 소탕은 두 방향으로 돌렸다 — 번역이 **추가한** 절대어법 79건을 원본과 대조(수정 1건), 한국어 **목적 구문** 8건을 역방향 대조(수정 2건 추가: `reclaimStaleWarpTabConfigs`의 목적절 2개, `ClaudeInjector`의 `expecting` 목적절). **`∼하지 않기 위한/위해서`가 목적이 보증으로 바뀌는 정확한 언어적 형태**이고, 역방향 대조는 순방향이 놓친 것을 잡는다 — 항목 3·11이 이 패턴을 그대로 쓴다 | **양방향 소탕이 필수다 — 한쪽만 돌리면 원본에서 물려받은 모순이 남는다.** 로그 문자열의 세기는 이번 소탕에서 뺐다(아래 소탕 표의 근거) — **검증받지 않은 판단**이라 다음 리뷰에 싣는다 |

## 전수 소탕 표

같은 부류가 숨어 있을 수 있는 지점 전체. 미검사 항목을 비워 두지 않는 것이 이 표의 목적이다. 세 열뿐이다 — 셋째 열은 코드로 알 수 없는 이유 한 절이거나 `파일:행`이다. 판정이 안전이고 그런 이유가 없는 대상은 한 행에 나열해 합친다.

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `SetupWindowController.swift` UI 메시지 63 | 로컬라이즈(항목 10) | 조각 25개를 6문장으로 복원한 결과 — `inventory-app.tsv` |
| `{AppDelegate,Installer,PermissionChecker}.swift` UI 메시지 20 + `InfoPlist.strings` 1 | 로컬라이즈(항목 11) | |
| **로컬라이즈된 값이 셸·AppleScript·TOML·tty로 가는 경로**(D34 불변 원칙 관점의 전수) | `testCommand`는 **타입 분리 + 영어 고정**(항목 10) · 나머지는 안전 | 앱이 셸/AppleScript/TOML/tty로 내보내는 자리는 넷이다 — ① `testCommand`(`SetupWindowController.swift:155`, 화면에도 보인다 → 유일한 겹침) ② `runInTerminal`의 `command`(Core가 조립, 요청 값은 화이트리스트) ③ `warpTabConfigTOML`(마커 + `appDisplayName` + 명령, 항목 4) ④ claude 입력(요청에서 온 텍스트). **카탈로그 값이 닿는 곳은 ①뿐이고, 타입 분리가 그 겹침을 없앤다.** 고정만으로는 감사 면제가 되므로 불변 원칙으로 올렸다. 확장 쪽 유사 부류는 placeholder 4건(`{cd} && claude`·`!gh issue view {number}…`·`remy-worker`·`master`)이며 실행되지 않아 **표시 전용** |
| `app/Info.plist`의 `CFBundleDevelopmentRegion=ko` | 구멍(항목 6) | `app/Info.plist:6` |
| `NSAppleEventsUsageDescription`(TCC 프롬프트) | 로컬라이즈(항목 11) + **미검사**(항목 8이 실측) | 그리는 것은 tccd다. 확인하려면 사용자의 살아 있는 Automation 권한을 리셋해야 해 이번 세션에서 하지 않았다. 통제 밖이면 고치지 않고 문서에 남긴다(D14) |
| `NSAlert` 버튼·`NSOpenPanel` 시스템 문구 | 앱 피커를 따르게 한다 — **재시작 뒤**(항목 6·8) | 실측: 런타임 쓰기는 무효, `main.swift`에서 AppKit보다 먼저 쓰면 유효 |
| **오래 사는 객체에 굳은 로컬라이즈 값** | 구멍(항목 9) | `SetupWindowController.swift:615`(정적 `ko_KR` 포매터) · `AppDelegate.swift:47`(1회 메뉴). 전수: 카드·라벨은 `refresh()`가 다시 쓰므로 이 둘이 전부다 |
| `HostServer`·`Settings`·`Theme`의 한국어 | 영어화(항목 11) | 로그·`fatalError` |
| Core 로그 44 | 영어화 완료(항목 1) | **명시적으로 영어인 진단 표면**(D27). 전부 `checkoutLog`/`timeline?.step` |
| `ClaudeInputBlocker.message` 3 | 영어화 완료(항목 1) | 확장 콘솔에만 닿는다(`content.js:165-181`, 이슈 #29) |
| `warpTabConfigFailed` 2 | 영어화 완료(항목 1) — **D3의 전제가 깨지는 자리** | 확장 콘솔뿐 아니라 **설치 안내 창에도 뜬다**: `testTerminal` → `runInTerminal(.warp)` → `runInWarp` → `writeNewFile`가 던지면 `SetupWindowController.swift:1000`이 `실패: %@`로 렌더한다. D3의 근거는 "창에 뜨는 사유는 타입으로 넘긴다"였는데 이 갈래는 문자열을 그대로 싣는다 — D11이 이미 허용한 부류라 결론(영어)은 바뀌지 않는다 |
| **주석의 주장이 같은 파일·`CLAUDE.md`·실측과 어긋나는 자리**(D56 부류, `00c7a70`+`f73c361` 전수) | 6건 수정 완료 · 나머지 안전 | 방법 둘: ① 번역으로 **추가된** 주석 줄에서 절대어법(`never`·`always`·`guarantee`·`ensure`·`impossible`·`proves`·`successfully`·`must not`·`cannot`) **79건**을 뽑아 원본 한국어와 대조 ② 한국어 **목적 구문**(`위한`·`위해서`) **8건**을 역방향으로 대조. 수정 6건 — `WarpControl.swift:16`(보증→목적) · `WarpControl` `reclaimStaleWarpTabConfigs` 목적절 2개 · `ClaudeInjector.swift:60`(수신→렌더) · `:197`(Ctrl+U 성공→화면 관측) · `ClaudeInjector`의 `expecting` 목적절 · `TerminalRunner`의 fallback spawn 모호성. 나머지 73건은 한국어와 세기가 같다(`never mixed` ← `섞지 않는다`, `no guarantee it is ours` ← `보장이 없다`, `guarantees` ← `보장한다`) |
| **로그 문자열의 주장 세기** | **검사 대상에서 뺐다 — 검증받지 않은 판단** | 근거: 로그는 **사실 보고**(무엇이 일어났는가)이지 **계약 서술**(무엇이 보장되는가)이 아니라서 같은 잣대를 대면 오탐만 는다. 반대로 **계약을 말하는 로그가 있다면 그것 자체가 발견**이므로, 이 판단이 틀리면 소탕이 아니라 그 로그 줄이 결함이다. 다음 증분 리뷰 본문에 싣는다 |
| `ClaudeInputPlan.swift` · `BaseDirectory.swift`의 절대어법 | **미검사** | 원래 영어라 「번역」 부류 밖이었으나, **D56의 새 정의(주장이 어긋나는 자리)로는 범위 안**이다. 절대어법 스캔 111건 중 상당수가 이 두 파일에 있다. 이번 승격에서는 하지 않았다 |
| **실측 ↔ 추론 구분** | 안전 | `ClaudeInjector.swift:31`이 "Only `!` was measured … but that is inference, not measurement"로 그대로 보존됐다. 실측 수치(0.1∼0.19s · 13개 pane 중 3개 · 20회 측정 59/14/9ms · 0.5∼0.7초 · 134∼143ms)도 전부 남아 있다 |
| **원본 한국어가 이미 다른 곳과 모순되던 자리**(D56의 본체 — 번역 강화는 부분집합) | 2건 수정 완료 — **번역 손실이 아니다** | `ClaudeInjector.swift:60`(원본 `반영 확인이 비로소 claude의 수신을 뜻하게 된다`)과 `:197`(원본 `우리가 성공적으로 비웠거나(Ctrl+U)`)은 번역이 충실했고 **한국어가 이미** `:191`·`:201`·`CLAUDE.md`와 모순됐다. 영어↔한국어 대조로는 안 잡히고 각 주장을 `CLAUDE.md`와 대조해야 나온다 — 항목 3·11의 소탕은 두 방향을 다 돌린다 |
| `Relay/main.swift`의 `replyError` 2 | 영어화 완료(항목 2) | Chrome이 받는 `error` 값 → **확장 콘솔**. 확장이 이 문자열을 문자 그대로 비교하는 코드는 없다(`grep` 0건) — `background.js:239`는 값을 그대로 던지기만 한다 |
| `WarpHelper/main.swift` 문자열 11 | 영어화 완료(항목 2) | 전부 `checkoutLog`/`fail` → **앱 로그**. tty에는 읽지도 쓰지도 않는다(파일 서문의 불변) |
| `build.sh`의 완료 출력 · `e2e.sh`의 통과·실패 출력 | 영어화 완료(항목 2) | **터미널 stdout / CI 로그**. 인용·grep하는 곳 0건이라 단독으로 바꿀 수 있었다 |
| `e2e.sh`의 오라클 9건 | **불변 — 이번에도 손대지 않았다** | diff에 나타나지 않는 것으로 확인(문자열 매칭 0건). Core가 영어로 남는 것이 전제(D3) |
| `WarpControl.swift:22` 마커 + `:86` 꼬리말 | 언어 중립 토큰 + 레거시 인식(항목 4, D25) | `uninstall.sh:63`·`CoreTests.swift:4019`·`WarpControl.swift:48`이 함께 움직인다 |
| `SetupWindowLayoutTests.swift:165`·`:166`·`:178` | 항목 10과 **같은 승격** | 소스 문자열을 글자 그대로 단언한다 |
| `CoreTests.swift` 한글 산문·실패 메시지 | 영어화(항목 3) | |
| `CoreTests.swift`의 한글 447줄 | 산문 407 영어화 · **데이터 40 유지**(항목 3) | 판정 기준과 경계 사례 5종은 항목 3 근거 칸. 주석↔단언 대조에서 1건 수정(주석이 고정 목록, 단언은 일반 성질) — **테스트가 더 강한** 방향이라 주석을 고쳤다 |
| `CoreTests.swift` 한글 **픽스처 데이터** | **유지** | 멀티바이트 실측 — `:271`·`:1324`·`:1681`·`:1693`·`:3389`·`:3398` 등 |
| `app/e2e.sh` 오라클 9건 | 안전(로케일 무관) + 신규 케이스(항목 15) | Core가 영어로 남는 것이 전제(D3) |
| **`app/e2e.sh`가 설치된 앱의 실제 `UserDefaults`를 쓴다** | **미검사 부작용 — 항목 15가 판정** | `HostServer.serve`가 프레임마다 `Settings.recordRequestEvidence()`를 부르고, `--headless-server`도 같은 번들 ID(`com.dazebug.terminal-checkout`)로 도므로 e2e 실행이 사용자의 `lastRequestAt`을 갱신한다. 실측: 기준 트리 게이트 실행 직후 `defaults read com.dazebug.terminal-checkout` → `lastRequestAt = "2026-08-22 15:06:16 +0000"`(= 00:06 KST, 게이트 실행 시각). **기존 결함이지만 항목 15가 e2e에 질의 케이스를 더하면서 D16·D26의 「설치 완료」 판정과 직접 얽힌다** |
| 요청 최상위 미지 키를 앱이 무시하는 성질 | 안전 — 항목 15가 테스트로 고정 | `Request.swift:21-48`이 세 키만 읽는다. D23에 따라 이 파일은 손대지 않는다 |
| 응답 추가 키를 구버전 확장이 무시하는 성질 | 안전 — 항목 15·16이 고정 | `background.js:239` |
| `{"query":"locale"}`을 구버전 앱이 받는 경우 | 안전 — 기존 e2e 케이스가 이미 고정 | `app/e2e.sh:51-54` |
| `sendToNativeHost()`가 실패 응답을 던져 메타데이터를 잃는 것 | 구멍(항목 16) | `background.js:232` — `locale`을 JSON에 더하는 것만으로는 갱신되지 않는다 |
| `buttonFingerprint()`의 `face`·`label` | 구멍(항목 19, P0) | `defaults.js:425` |
| `Installer.swift:101`의 삭제 후 복사 · `:153`의 `try?` · `install.sh`의 앱 삭제 후 복사 | 구멍(항목 14) | |
| `extensionCopyNeedsUpdate()`의 사각지대 | 무해하나 **전제로 삼지 않는다**(항목 14) | 파일이 하나도 없는 **빈** 디렉터리는 파일 맵에 안 잡혀 `false`. 실측(`copyprobe/probe.swift`): 평평 동일 → false · `_locales`+`_i18n` 추가 → true · 복사 후 → false · 중첩 1바이트 수정 → true · 빈 디렉터리 추가 → false. 우리 카탈로그는 항상 파일을 담으므로 무해 |
| `applicationWillTerminate`가 소켓만 닫는 것 | 구멍(항목 13) | `HostServer.swift:120`이 응답 뒤 비동기 전달을 띄운다 |
| `manifest.json` `content_scripts` 로드 순서 | **안전 — 정적으로 보장됨** | Chrome 문서: "injected in the order they appear in this array". `run_at` 기본 `document_idle`. Chrome 실행 불필요 |
| `manifest.json`에 `default_locale` 추가가 확장 ID를 바꾸는가 | **미검사**(항목 17이 확인) | ID는 `key`에서 나오지만 실제 로드 확인은 Chrome이 필요하다 |
| `options.html`의 정적 영어 텍스트가 스크립트 실행 전에 보인다 | 구멍(항목 21) | `options.html:442` — 첫 페인트가 영어로 깜빡일 수 있다 |
| `_locales` 키가 정확히 2개 · 키 공간 분리 | 게이트(항목 20, D24) | |
| 라벨 상호 인용 8곳 | 관계로 전환 + 게이트(항목 10·11·21·22, D28) | |
| 렌더 안 되는 `**…**`·백틱 2곳 | **번역 전에 걷어낸다**(항목 10·22) | `SetupWindowController.swift:1062`(`**…**`+백틱) · `migrations.js:81-84`(백틱). 번역하면 5개 로케일로 복제된다 |
| `item.source`의 raw enum(`verbatim`/`prefix`) 노출 | 결정 대상(항목 21) | `options.js:830` |
| `app.status.extension.waiting` 문구 | 구멍(항목 15, D26과 같은 승격) | "GitHub PR 페이지에서 버튼을 누르면 완료"라고 말하는데 D16으로 판정이 넓어진다 |
| 복수형 3자리 | 영어 리라이트(항목 21·22, D31) | `migrations.js:657` · `options.js:925`·`:927` |
| `extension/layout.js` · `console.*` 21건 | 안전 / 영어 유지 | |
| 프리셋 `command` 11 + `V0_TO_V1` 맵 + `SETTINGS_VERSION` | **불변** | 셸 명령·verbatim 비교 대상 |
| 5개 로케일에서 설정 창 레이아웃 | **미검사** | `setupContentWidth=560`은 한/영 기준이고 `SetupWindowLayoutTests`는 한 로케일에서만 돈다. GUI 기동이 `Installer.autoSetup()`으로 사용자의 살아 있는 manifest를 덮어쓴다 |
| CJK 글리프가 `Theme.mono`(SF Mono)에서 폴백 | **미검사** | 화면을 봐야 안다 |
| `String(format: "%.1f")` 등 숫자 서식 | 안전 | 로케일 없이 POSIX 서식 |
| `docs/context/signing-and-permissions.md:8`의 한국어 로그 인용 | **유지** | 날짜가 붙은 과거 증거이고 그 문구는 이미 소스에 없다 |
| `docs/new-terminal-checklist.md:135`의 로그 인용 | 구멍(항목 25) | 인용과 실제가 **이미 다르다**(`전달` ↔ `보냄`) |
| `README.md:80` · `install.sh:99`·`:101` | 구멍(항목 25) | #24 체크박스 |
| `CONTRIBUTING.md` · `SECURITY.md` · `LICENSE` · `.github/workflows/ci.yml` | 안전 | 한글 없음 |

## 라운드 로그

라운드는 검증자의 전체 판정 사이의 구간이다. 리뷰(증분·최종·cold)마다 어느 커밋에 대한 것인지와 계측(승격 시각·리뷰 시작·종료·왕복 수)을 적고, 리뷰 하나는 차단·수정·실측·판정 네 줄이다. 차단·수정·실측 줄은 에이전트가, 판정 줄은 드라이버가 지정한 문구를 에이전트가 적는다. 보고서 원문은 스크래치패드 파일 경로로 가리킨다 — 옮겨 적지 않는다. R0은 설계 리뷰다 — 차단 자리에 반박, 수정 자리에 처리(반영/기각 + 원장 번호)를 적고 둘 다 드라이버가 지정한다.

### R0

#### 설계 리뷰 — `55fadef` · 승격 23:56 · 리뷰 23:56∼00:05 · 왕복 1 · 원문 `<스크래치패드>/review-0-response.md`

- 반박: P0 ① 동기화 계약 부재(§1·§2) · P0 ② 버튼 지문의 로케일 민감성(§4). 그 밖에 §2 누락 불변식 4건 · §3 항목·의존 오류 · §4 기존 결함 6건(비원자적 배포·실패 응답 메타데이터·장수명 UI·진행 중 전달·전진 호환 마커·로드 순서) · §6 게이트 불충분과 D1·D9·D14·D3/D13·D16 재검토 · §7 원자성 `N/A` 오판
- 처리: 수용 D17∼D27, 항목·의존 정정은 리뷰 §3 그대로. 에이전트 발견 7건 추가 수용 D28∼D31 + D24 3단 정밀화 + 마크업 방침 C 채택 + 잔가지 3건
- 실측: 기준선 게이트 4종 그린(swift 351/1 skipped · node 158 · build.sh 0 · e2e 9 PASS, `baseline-55fadef.txt`) · 인벤토리 214 메시지/218 키(조각 25→6 복원) · `extensionCopyNeedsUpdate` 프로브 5케이스 · `content_scripts` 순서 정적 확정 · `AppleLanguages` 3케이스(D14) · 중국어권 폴백 9케이스(D12)
- 판정: `do you agree that we should start from this plan: blocked`

#### 설계 리뷰 2 — `55fadef` · 승격 00:10 · 리뷰 00:10∼00:25 · 왕복 1 · 원문 `<스크래치패드>/review-1-response.md`

- 반박: 반박 11건이 **「구현을 전제로 닫힘」**으로 판정됐고 남은 것은 명세 구멍 7건 — 세대값이 정수 하나면 리셋 후 모호해진다(§1) · 지문 정체성 규칙이 미명세(§1·§2) · 로컬라이즈 값의 셸 유입 금지가 불변 원칙이 아니라 고정에 그친다(§3) · 정본 라벨의 정본이 문서로 돼 있다(§3) · 조각 연결 금지가 규칙이 아니라 관행(§3) · 소유권 게이트가 못 잡는 것이 미명시(§4) · 마커 토큰의 영구성이 미문서화(§1·§3). 그리고 재그리기 계약과 복수형 회피의 정확한 문구를 요구
- 처리: 수용 D32∼D38 + D31a. 검증자가 "가장 작은 언블록은 정확한 세대 계약 + 통과하는 테스트"라고 적었으므로 **다음 언블록 조건은 설계 라운드가 아니라 구현**이다
- 실측: 지문 설계의 근거를 코드로 확정 — `toStoredButton`(`defaults.js:504-511`)이 uid를 떼어 내 저장 버튼에 영속 id가 없고, `runButton`(`background.js:247-266`)이 `command_template`+`claude_inputs`만 보내 `face`·`label`은 확장 밖으로 나가지 않는다. 기존 테스트 `tests/buttons.test.js:366`이 반대 규칙(`labelChanged`는 달라야 한다)을 고정하고 있어 항목 19가 뒤집는다
- 판정: `blocked` — 구현으로 언블록

### R1

#### 증분 리뷰 — `95f586b` · 승격 00:34 · 리뷰 00:34∼00:42 · 왕복 1 · 원문 `<스크래치패드>/review-2-response.md`

- 차단: P0 ① `auto`가 세대 계약과 정면 모순(선호가 `auto`면 시스템 언어가 바뀌어도 `epoch`가 안 올라 확장이 영원히 옛 언어) · P0 ② 같은 `installId`를 공유하는 GUI ↔ `--headless-server`의 교차 프로세스 epoch 충돌. 그 밖에 계획 오류 6건(무조건 수용의 안전성 · 리셋 미정의 · 지문 정체성 2건 · 응답 계약 · 게이트 3건 · 항목 21의 D36 위반)
- 수정: 수용 D48∼D55(드라이버 문서의 D39∼D46이 각각 D48·D49·D50·D51·D52·D53·D54·D55가 됐다 — D47을 항목 1에서 이미 쓴 탓에 8칸 밀렸다). 목표 문구·게이트 ⑥⑦·항목 5·8·14·15·16·19·21 개정, 테스트 이름 정밀화를 각 근거 칸에 반영
- 실측: 항목 1 승격(`00c7a70`) 게이트 4종 그린 — swift 351(1 skipped)/0 · node 158/0 · `build.sh` · `e2e.sh` 9 PASS
- 판정: `behavior-free Core Englishing may continue, but the first locale implementation should not start from 95f586b unchanged`

### R2

#### 증분 리뷰 — `00c7a70` (번역 손실 수색) · 승격 01:04 · 리뷰 01:04∼01:13 · 왕복 1 · 원문 `<스크래치패드>/review-3-response.md`

- 차단: P1 3건 — 영어가 한국어보다 강하게 말하는 자리(`WarpControl.swift:16` 보증 ↔ `:366` 잔여 경쟁 · `ClaudeInjector.swift:60` 수신 증명 ↔ `:191`·CLAUDE.md · `:197` Ctrl+U를 증거로 ↔ `:201`·CLAUDE.md) + P2 1건(`TerminalRunner`의 fallback spawn 모호성). 기계적 주장(마커 2줄만 남음·실측값·기각된 대안·실측↔추론 구분 보존·옮긴 주석 1건)은 통과
- 수정: 항목 26으로 6건 수정(표본 4 + 소탕 추가 2), D56 신설 후 **부류 정의를 재작성** — 드라이버가 「번역이 강화한 자리」로 규정한 것을 에이전트 실측(4건 중 1건만 해당)에 따라 **「주장이 같은 파일·CLAUDE.md·실측과 어긋나는 자리」**로 넓히고 번역 강화를 부분집합으로 두었다. 불변 원칙으로도 승격
- 실측: 절대어법 79건 순방향 · 목적 구문 8건 역방향 · 게이트 4종 그린. `ClaudeInjector.swift:31`의 실측↔추론 구분과 수치 6종(0.1∼0.19s · 13 pane 중 3 · 59/14/9ms · 0.5∼0.7s · 134∼143ms) 보존 확인
- 판정: `① Partly closed.` → 항목 26 `verified`

**미회신**: D3 근거 정정에 대한 질문(창에 닿는 문자열 2건을 타입 사유로 바꿀지, 기록된 잔여로 둘지)에 검증자가 답하지 않았다 — 침묵은 합의가 아니므로 다음 리뷰 본문에 다시 싣는다. 로그 문자열의 세기를 소탕에서 뺀 판단도 함께 싣는다.

## 열린 질문

Q1∼Q11은 결정됐다 — 원장 D8∼D16과 항목 24·25에 있다. 아래는 그 결정들과 R0 리뷰가 새로 연 것뿐이다.

- **Q12 — TCC 프롬프트가 앱의 언어를 따르지 않는 것으로 밝혀지면, 그 사실만 적고 끝인가.** D14가 "고치지 마라"로 답했지만, 그 경우 **권한을 처음 요청하는 순간 사용자가 보는 유일한 문장이 시스템 언어로 뜬다** — 설치 안내의 가장 중요한 한 걸음이 고른 언어 밖에 놓인다. 항목 8의 실측이 그렇게 나오면 설정 창이 프롬프트 직전에 같은 내용을 고른 언어로 미리 말해 줄지 결정이 필요하다. 항목 8·25에 걸린다.
- **Q13 — `app/e2e.sh`가 사용자의 실제 앱 설정을 건드리는 것을 그대로 둘 것인가.** 게이트를 한 번 돌릴 때마다 설치된 앱의 `lastRequestAt`이 갱신돼 설정 창이 "확장 연결 확인됨"으로 바뀐다(실측: 게이트 실행 직후 `lastRequestAt`이 그 시각). 기존 결함이지만 항목 15가 e2e에 로케일 질의를 더하면 **테스트가 「설치 완료」 판정을 만들어 내는** 모양이 된다. e2e 전용 도메인(`-AppleLanguages` 방식의 인자 오버라이드나 `TERMINAL_CHECKOUT_SOCKET` 같은 env 스위치)으로 가를지, 범위 밖으로 둘지 결정이 필요하다. 항목 15를 막고 있다.
- **Q14 — 재시작을 미루는 동안 사용자가 무엇을 보는가.** D20은 "미루거나 알린다"까지만 정했다. claude 입력 전달은 실측상 수 분이 걸릴 수 있어(기동 대기 기본 2분 + 입력별 재시도) 「지금 다시 시작」이 몇 분간 눌리지 않는 상태가 정상 동작이 된다. 그동안 우리 문자열은 이미 새 언어라 사용자는 "절반만 바뀐 창"을 오래 본다. 대기 표시를 어디까지 할지 항목 13이 정해야 한다.
