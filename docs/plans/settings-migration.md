# settings-migration

- 대상: `/Users/choongjaelee/Codes/terminal-checkout-settings-migration` (브랜치 `settings-migration`)
- 시작 커밋: `6fa5daf` (#32 머지 직후 main)
- 현재: R6 커밋(항목 12 — Save·import 시작 시점 캡처+직렬화+adoption 보류·`userAction` 가드-변이 순서·main-branch 검증기 공유·`skippedByKey`, verified) · 게이트 그린(드라이버 재실행 — node 118/0, swift 210/0, e2e 9 PASS; red 재현 — pre-R6 코드에 신규 테스트를 걸어 `not ok` 4건 확인) · Codex 재검증 대기
- 최근 검증자 판정: **차단(no) ×5** — 스레드 `01a02426-85b3-78c2-b3a6-94f89eef4214`

이슈 #31 — "Versioned settings with a consented migration path for stale saved buttons". 직전 루프(#30/#32)가 **"저장된 command 마이그레이션은 비목표"**로 명시적으로 미뤄 둔 것(`docs/plans/base-dir-fallback.md:24`)을 이번에 정면으로 다룬다. 그때 남긴 우회책은 문구 2곳뿐이다 — `README.md:112`와 설정 창 카드(`SetupWindowController.swift:255-261`)가 "옵션 페이지에서 프리셋을 다시 적용하라"고 손으로 시킨다.

## 목표

- 저장 설정에 스키마 **`version`**이 생기고, 그 값이 현재보다 낮으면 옵션 페이지에 업데이트 표시가 뜬다. 없으면 v0(레거시)이다.
- 마이그레이션 레지스트리가 **v0 프리셋 verbatim 일치**와 **엄격 접두 일치**(`z {repo}` / `z {repo} && …`)를 후보로 올린다(결정 4 개정). 그보다 느슨한 모양은 고쳐 쓰지 않고 나열만 한다.
- 프리뷰는 문자열 diff에 더해 **그 변화가 무엇인지** 말한다. 레지스트리의 모든 항목이 「무조건 개선」인지 「동작 변화」인지 스스로 선언하고, 그것을 말하지 못하는 항목은 출시하지 않는다.
- **버전은 사용자의 명시적 행위 없이는 절대 올라가지 않는다.** 아무 저장이나 버전을 찍으면 마이그레이션이 조용히 사라지고 옛 command가 영구히 남는다 — 이 루프에서 가장 깨지기 쉬운 성질이다.
- 적용은 import와 같은 패턴을 따른다: 편집 상태를 채우고, diff를 보여 주고, 쓰기는 같은 [Save] 하나로 나간다. 옛 백업 파일을 가져올 때도 같은 검사·같은 프리뷰를 받는다.
- 확장 안에서 끝난다 — 앱의 실행·검증 경로는 손대지 않는다.

## 비목표 — 건드리지 않는다

- **동의 없는 자동 적용**: 조용히 고쳐 쓰면 이 이슈가 만들려는 것(동의 기반 경로)이 사라진다. "고칠 것이 하나도 없는 마이그레이션"조차 예외가 아니다(결정 2) — 확인 클릭이 승격한다.
- **커스터마이즈된 command의 자동 재작성**(결정 4 개정으로 범위 축소): 이제 **엄격 접두 일치**(`z {repo}` 단독 또는 `z {repo} && …`)는 후보로 올린다 — 다만 그것도 동의 없이 적용되지는 않고 체크박스를 거친다. 그보다 느슨한 일치(중간에 나오는 `z {repo}`, `z {repo};`, `z {repo}&&x`, 공백이 다른 형태)는 여전히 손대지 않는다: 셸 파싱이 필요하고, 잘못 짚으면 건드리지 말라던 명령을 고치게 된다.
- **앱 설정(터미널·base dir)의 버전·마이그레이션**: 저장소도 수명도 다르다(`UserDefaults` vs `storage.sync`). 앱은 이 스키마를 읽지도 쓰지도 않는다.
- **툴바 배지·알림으로의 확산**: 옵션 페이지 표시까지가 이번 범위다. 아이콘 클릭 없이도 알리는 경로는 #29(실패 표면화)와 같은 표면을 건드린다.
- **다운그레이드 지원**: 더 새로운 버전의 백업을 낮은 확장으로 가져오는 경우는 **거부**한다(결정 5 개정) — 되돌리는 변환도, 부분 읽기도 만들지 않는다.
- **`claudeInputs`·`face`·`label`의 마이그레이션**: v0→v1은 command만 바꾼다. 메커니즘이 다른 필드로 번질 수 있게 열어 두되, 이번 레지스트리 항목은 command 하나다.
- **실행 경로가 버전을 보게 만드는 것**: `background.js:139`·`content.js:82`는 지금처럼 command를 그대로 실행한다. 옛 설정이 계속 동작하는 것이 동의 기반 설계의 전제다.

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

- **`effect`의 정의(R2 명문화, R4 정정).** `effect`는 딱 한 가지만 묻는다: **"base dir의 계약 안에서 — `<base>/<repo>`가 그 이름의 저장소일 때 — 어떤 앱 설정에서도 이 rewrite가 사용자를 더 나쁘게 만드는가?"** 계약을 명시해야 하는 이유는 그 밖에서는 무엇도 무조건이 아니기 때문이다: 같은 이름의 **다른 저장소**가 거기 있으면 `{cd}`는 그 저장소에서 명령을 돌린다. 그것은 #32가 알고 수용한 잔여(`z`의 퍼지 점프와 같은 부류이자 사용자 자신의 레이아웃)이고 이 페이지의 모든 판정으로 전파된다 — "어떤 설정에서도"라는 절대 문구는 그냥 거짓이다.
- **계획은 저장된 것이 아니라 "저장될 것"(편집 상태) 위에서 세운다.** import는 파일에 있는 키만 채우므로 나머지 섹션은 옛 command를 든 채 남고, 저장소 스냅샷으로 계획하면 그 절반이 검토 없이 승격된다. 후보의 이름은 **런타임 uid**이지 인덱스가 아니다 — 계획과 적용 사이에 타이핑·순서 변경이 일어나고, 인덱스는 그 순간 다른 버튼을 가리킨다. uid는 `toStoredButton`이 떼어 내 저장·내보내기에 절대 실리지 않는다.
- ~~version은 이 페이지가 관찰한 바닥 아래로 내려가지 않는다~~ → **R3 개정(이 설계가 틀렸다)**: **version은 쓰는 내용의 세대이고, 로드 이후 바뀐 저장소 위에는 쓰지 않는다.** 바닥은 version 표식만 지키고 그것이 서술하는 command는 지키지 않아서, v0 내용에 v1 표식을 씌워 다른 기기의 마이그레이션을 조용히 지웠다. version은 `versionToSave(loadedVersion, reviewed)`만으로 정하고, 저장은 쓰기 직전에 **소유한 키 전부**를 다시 읽어 로드 스냅샷과 대조해 하나라도 다르면 **거부**한다. `storage.sync`에 CAS가 없으므로 병합은 둘 중 누구의 의도를 버릴지 고르는 추측이 된다 — 덮어쓰기 버튼도 만들지 않는다(트리거: 사용자가 실제로 요구하면 별도 이슈).
- **페이지는 첫 로드가 끝나기 전에는 설정을 갖지 않는다.** `loaded=false`·`loadedVersion=null`로 시작하고 저장·적용·거절·리셋·가져오기가 전부 `requireLoaded()`를 통과해야 한다(버튼 disabled는 힌트, 가드가 규칙). 로드 응답은 **세대 카운터**로 걸러 추월당한 응답을 버린다 — 두 로드가 겹치면 늦게 답한 쪽이 최신이 아닐 수 있다.
- **uid는 우리가 만든다.** 저장·파일에서 들어온 uid는 항상 버리고 새로 부여하며(`adoptButton`), 보존은 편집 상태 내부 연산에서만 명시적으로 한다(`reshapeButton`). 한 함수가 둘 다 하면 구멍이 다시 생긴다 — 저장값의 `uid: 0`이 숫자 id가 돼 DOM dataset(문자열)과 어긋나 체크 해제가 무력화된 것이 그 증거다.
- **설정에서 온 문자열로 객체를 조회하지 않는다.** command·repo 이름·메시지 action은 전부 프로토타입 멤버 이름일 수 있다 — `Map`이나 `Object.hasOwn` 뒤에서만 찾는다(소탕 표 2).
- **버전은 사용자의 명시적 행위로만 올라간다.** `saveSettings`가 무조건 현재 버전을 찍으면, 툴팁 하나 고치고 저장한 사용자의 마이그레이션이 조용히 소멸한다(아이콘은 사라지고 옛 command는 남는다). 이 루프에서 이 성질 하나만 지켜도 절반은 성공이다 — 테스트로 고정한다.
- **`extension/defaults.js`가 현재 스키마 버전 상수의 단일 정본이다**(이슈 제약 5). 아이콘을 그리는 쪽도, 레지스트리도 이 상수를 본다. 레지스트리가 별도 파일로 가면 "레지스트리가 0→CURRENT의 모든 단계를 덮는가"를 테스트로 고정한다 — 상수만 올리고 항목을 빼먹는 것이 이 구조의 대표적 실패다.
- **쓰기 경로는 [Save] 하나다.** import도 마이그레이션 적용도 편집 상태만 채운다. 이 원칙을 바꿔야 한다면 계획서에 개정으로 적고 승인을 받는다 — 슬그머니 두 번째 쓰기 경로를 만들지 않는다(`options.js:329-378`이 유일한 `storage.sync.set`).
- **후보는 verbatim 일치 또는 엄격 접두 일치뿐이다**(결정 4 개정). 비교 대상은 트림도 정규화도 하지 않은 저장 문자열이다. 접두 규칙은 `=== 'z {repo}'`와 `startsWith('z {repo} && ')` 둘뿐이며, 맞으면 **맨 앞 절만** 바꾸고 나머지는 바이트 그대로 둔다. 공백 하나만 달라도(`z  {repo}`) 후보가 아니다 — 정규화를 넣는 순간 "사용자가 의도한 차이"와 "무의미한 차이"를 우리가 판정하게 되고, 그보다 느슨한 일치는 셸 파싱을 요구한다.
- **확장은 앱의 base dir 설정을 알 수 없다.** #30이 의도적으로 그렇게 설계했다(`CLAUDE.md`: 확장에는 값을 지정할 방법을 주지 않는다). 그래서 base dir은 **판정의 근거가 아니라 안내**다(결정 3 개정): `{cd}`로 바꾸는 것 자체는 어느 경우에도 나빠지지 않으므로 `effect`는 `unconditional`이고, 프리뷰는 "기본 폴더를 지정해 두었다면 폴백이 붙는다"를 한 줄로 알려 줄 뿐이다. 알아내겠다고 앱↔확장 상태 채널을 새로 뚫는 것은 #30의 설계를 뒤집는 일이라 기각.
- **옛 프리셋 문자열은 레지스트리 안에서만 산다.** `294c46a:extension/defaults.js`가 그 원본이고 현재 코드 어디에도 없다 — 레지스트리에 verbatim으로 박고, 그 사실(역사 문자열이라 고치면 안 됨)을 주석에 남긴다.
- **순수 함수는 `defaults.js`/레지스트리에, DOM은 `options.js`에.** `tests/buttons.test.js`가 `vm.runInThisContext`로 파일을 통째 실행해 이름을 꺼내는 구조라, 테스트 가능한 것과 아닌 것의 경계가 곧 파일 경계다.
- **실행 경로는 버전을 보지 않는다.** 마이그레이션 전 command도 그대로 돌아야 한다.
- **라운드마다**: 리포 루트 `node --test`(주 게이트) · `cd app && swift test`·`app/build.sh` + `app/e2e.sh`(회귀 확인 — 확장만 고쳤다면 불변이어야 한다). red를 먼저 쓰고 눈으로 확인한 뒤 구현한다.
- **언어**: 코드 주석·리포 문서는 영어(CLAUDE.md Working principles), 앱 UI 문구는 한국어(#24가 정본). 이 계획서는 직전 루프(`docs/plans/base-dir-fallback.md`) 선례를 따라 한국어로 쓴다.

### 설계 스케치 (R0 판단 — 승인 대상)

**버전이 올라가는 유일한 지점**을 다음으로 한정한다.

| 상황 | 저장 시 version |
|:--|:--|
| 저장된 설정 키가 **하나도 없음**(신규 설치) | CURRENT — 기본값은 이미 현재 세대다. 여기서 v0을 찍으면 새 사용자에게 마이그레이션 아이콘이 뜬다 |
| 마이그레이션을 **적용**하고 저장(부분 적용 포함, 결정 8) | CURRENT (동의) |
| **[Keep mine]** 또는 바꿀 것이 없을 때의 **확인 클릭**(결정 1·2) | CURRENT (검토했다는 동의) |
| **[Reset to Defaults]** 후 저장(결정 7) | CURRENT — 내용이 현재 프리셋으로 바뀌므로 |
| 그 밖의 모든 저장 | **읽어 온 값 그대로** — 툴팁 수정·버튼 추가로는 절대 올라가지 않는다. 읽어 온 값이 CURRENT보다 높아도(미래 백업, 결정 5) 그대로 보존한다 |

"신규 설치"와 "레거시(v0)"는 둘 다 `version` 키가 없다. 가르는 기준은 **다른 설정 키가 하나라도 저장돼 있는가**다. 이 판정이 틀리면 신규 사용자가 마이그레이션 화면을 보거나 레거시 사용자가 조용히 v1로 승격된다 — 순수 함수로 뽑아 테스트로 고정한다.

레지스트리 항목의 모양(항목마다 판정 선언이 의무):

```js
{ from: 0, to: 1,
  effect: 'unconditional',          // 'unconditional' | 'behavior-change' (결정 3 개정)
  rewrites: { '<v0 문자열>': '<v1 문자열>', … },   // verbatim 8쌍
  promote: command => …,            // 엄격 접두 일치일 때만 맨 앞 절 교체 (결정 4 개정)
  isStale: command => …,            // 후보가 아니어도 옛 세대인지 — informational 판정
  describe: '…', customNote: '…' }
```

v0→v1은 `effect`가 **`unconditional`**이다(결정 3 개정) — base dir 미설정이면 렌더가 바이트 동일이고, 설정했다면 그때 붙는 폴백은 사용자가 앱에서 직접 켠 설정이 일으키는 동작이지 이 rewrite가 만드는 변화가 아니다. base dir 언급은 판정이 아니라 프리뷰의 안내 한 줄로 남는다.

v0 문자열은 11개 프리셋에서 **중복을 걷어내면 8쌍**이다(`z {repo} && claude`가 3곳, `z {repo}`가 2곳). kind와 무관하게 같은 문자열은 같은 결과로 가므로 레지스트리는 kind 구분 없는 단일 맵으로 둔다.

### R0 결정 (드라이버, 2026-08-21 — 열린 질문 8건의 처분)

1. **`version`은 「검토한 세대」다(질문 1 — 초안 권고 채택).** 아이콘은 준수 표식이 아니라 할 일 표시등이다. [적용]은 바꾸겠다는 동의, [지금 것 유지]는 두겠다는 동의 — 둘 다 검토의 결과이므로 둘 다 승격한다. 옛 command를 의도적으로 유지하는 것은 base dir 미설정과 동형의 정당한 상태(#30 결정)이고, 끌 수 없는 아이콘은 사용자가 아이콘 자체를 무시하게 만들어 다음 마이그레이션의 신호를 죽인다. 이슈의 "applying is the consent"는 변경에 대한 동의를 말한 것이지 거절 경로를 금지한 것이 아니다 — 항목 4 진행.
2. **actionable 0건이어도 조용히 승격하지 않는다(질문 2).** 아이콘 → 검토 화면이 "바꿀 자동 후보 없음"과 informational 목록을 보여 주고, [확인(지금 것 유지)] 클릭이 승격한다. "버전은 명시적 행위로만"의 예외를 만들지 않는 쪽이 불변 원칙을 단순하게 유지한다 — 비용은 클릭 한 번.
3. ~~base dir 무지는 조건부 서술로 충족한다~~ → **개정(사용자, R1 중): v0→v1은 `unconditional`이다.** base dir 미설정이면 렌더가 바이트 동일하고, 설정했다면 그때 붙는 cd 폴백·clone은 마이그레이션이 아니라 **사용자가 앱에서 직접 켠 설정이 일으키는 동작**이다 — `{cd}`로 바꾸는 것 자체는 어느 경우에도 나빠지지 않는다. `effect`는 **2값**(`'unconditional' | 'behavior-change'`)으로 줄이고 `'conditional'`은 폐기한다. 프리뷰에는 선언이 아니라 **안내 한 줄**만 남긴다. 앱↔확장 상태 채널 신설은 여전히 기각.
4. ~~커스텀 command에 기계적 수정 제안을 붙이지 않는다~~ → **개정(사용자, R1 중): 커스텀도 조건을 만족하면 후보로 승격한다.** 조건은 엄격한 접두 일치 하나 — `command === 'z {repo}'` 또는 `command.startsWith('z {repo} && ')`. 그러면 **맨 앞 절만** `{cd}`로 바꾼 rewrite를 actionable 후보로 올린다(나머지는 바이트 그대로). ~~판정은 verbatim과 같은 `unconditional`이라 기본 체크~~ → **R3 개정(Codex (b) 반박 수용)**: prefix 후보는 `behavior-change`이고 **기본 해제**다. suffix가 임의라 "어떤 설정에서도 나빠지지 않는다"를 주장할 수 없다 — `z {repo} && git clean -fdx`는 옛 command에서 아무것도 안 하지만, base dir이 설정돼 있고 같은 이름의 다른 저장소가 거기 있으면 새 command는 **거기서** 지운다. `effect`는 step 단위가 아니라 후보 단위이며, 레지스트리는 `verbatimEffect`/`prefixEffect`로 나눠 선언한다. 프리뷰는 출처를 구분 표시하고(`verbatim` / `prefix`) behavior-change 항목에는 전용 설명을 항목 옆에 붙인다. 그 밖의 모양(`cd x && z {repo}`, `z {repo};`, `z {repo}&&x`, 중간의 `z {repo}`, 공백이 다른 `z  {repo}`)은 informational + 안내 문구 유지. `claudeInputs`는 비목표 그대로 — **트리거**: 커스텀 claude 입력에 `!z {repo}`가 실제로 관찰되면 재검토.
5. ~~미래 version의 백업은 경고 + 채움~~ → **개정(사용자, R1 중): 현재보다 높은 `version`의 백업은 가져오기를 거부한다.** 편집 상태를 채우지 않고, 저장에도 닿지 않으며, 저장된 version은 그대로다. 거부 메시지는 해결책 둘을 제시한다(영어): "This backup was exported by a newer version of the extension. Update the extension (`git pull` + refresh at chrome://extensions), or use Reset to Defaults to start from the current presets." 미래 값에 대한 "저장 시 보존" 규칙은 **정상 로드 경로에만** 남는다(같은 계정의 최신 확장이 올려 둔 version을 낮은 확장이 강등하지 않는 것). 거부는 "일부 키 건너뜀"이 아니라 **가져오기 전체의 실패**다.
6. **레지스트리는 `extension/migrations.js`로 분리한다(질문 6).** defaults.js는 「현재의 진실」로 남고 역사 문자열은 옆방으로 — options.html만 로드하고 content/background는 모른다(표면 최소). 드리프트는 초안이 이미 의무화한 red("레지스트리가 0→CURRENT 전 구간을 덮는다")가 막는다. 이슈 제약 5(상수는 defaults.js)는 그대로.
7. **[Reset to Defaults]는 동의다(질문 7).** 내용이 CURRENT 세대가 되는 가장 명시적인 채택 행위 — 승격 지점 표에 4행째로 추가한다(신규 설치 / 마이그레이션 적용 / 검토 확인 / 리셋 — 전부 명시적 행위).
8. **동의는 항목별이다(질문 8 — 이슈 스펙 그대로).** ~~verbatim 후보는 기본 체크된 체크박스~~ → **R3 개정**: **`unconditional` 후보만** 기본 체크이고 `behavior-change`(= prefix) 후보는 기본 해제다(결정 4 개정과 같은 근거 — 읽고 켜는 것이지 놓쳐서 켜지는 것이 아니다). 체크박스, [적용]은 체크된 것만 편집 상태에 반영. 부분 적용 후 [Save]는 version을 CURRENT로 올리고(검토 완료) 체크 해제분은 다시 묻지 않는다 — 프리뷰가 그 사실을 말한다.

계획서 언어는 한국어 유지(선례 준수 — 라인 42의 근거 그대로).

## 작업 항목

| # | 항목 | 상태 | 근거 | 라운드 |
|:--|:--|:--|:--|:--|
| 1 | **버전 상수 + 읽기/쓰기 배선.** `defaults.js`에 `SETTINGS_VERSION` 상수. `options.js:314-327`(load)이 `version`을 읽어 상태에 두고, `:329-378`(save)이 **위 표대로만** 찍는다. 신규/레거시 판정은 순수 함수(`storedSchemaVersion(data)`)로. **red**: `tests/buttons.test.js`(또는 신설 `tests/migration.test.js`) — 키가 없으면 신규=CURRENT / 다른 키만 있으면 v0 / 숫자 아닌 값·미래 값의 처리 | verified | `defaults.js:126-146`(`SETTINGS_VERSION`·`VERSION_KEY`·`SETTINGS_KEYS`), `migrations.js:83-100`(`storedSchemaVersion`·`versionToSave`), `options.js:322`(load)·`:361-371`(save). red: `Error: ENOENT ... extension/migrations.js`. green: 신규 10건. 승격 규칙 5행(신규/적용/거절·확인/리셋/그 밖) 전부 테스트로 고정 — 특히 `an ordinary save keeps the version it read` | R1 |
| 2 | **레지스트리 + 계획 계산(순수).** 레지스트리 파일 위치는 열린 질문 6. `planMigration(stored, fromVersion)` → `{ actionable[], informational[], targetVersion }`. actionable은 verbatim 일치, informational은 그 외. **red**: verbatim 일치·불일치(공백 한 칸 차이) / 중복 문자열이 kind를 넘어 같은 결과 / 이미 v1인 command는 후보 아님 / **레지스트리가 0→CURRENT 전 구간을 덮는다** / 모든 항목이 `effect`와 `describe`를 갖는다(선언 의무를 테스트로 강제) | verified | `extension/migrations.js` 신설(레지스트리 8쌍 + `promote` 접두 규칙 + `isStale`), `planMigration`·`applyMigrationPlan`. red: `ReferenceError: planMigration is not defined`. green: 누적 21건. **v0 8쌍 검증**: 격리 vm 컨텍스트로 `294c46a`와 현재 `defaults.js`를 각각 로드해 대조 — v0 distinct 8 / 레지스트리 8 / 미포함 0 / 잉여 0 / 타깃이 현재 프리셋 아님 0 / 도달 불가한 현재 프리셋 0 | R1 |
| 3 | **프리뷰 UI + 적용 경로.** 헤더(`options.html:304-307`)에 업데이트 표시, 클릭 시 항목별 "xx → yy" + **동작 서술**. [적용]은 편집 상태만 채우고 `markDirty()` → 쓰기는 기존 [Save]. 항목별 동의(체크박스)인지 일괄인지는 열린 질문 8. **red**: 프리뷰에 넘길 뷰 모델을 순수 함수로 뽑아 테스트(문자열 diff + effect 문구 포함 여부). DOM·클릭은 수기 검사 목록으로 | claimed | `options.html:266-284`(스타일)·`:308-322`(배지·패널)·`:400`(백업 도움말), `options.js:394-506`(`setPlan`·`renderMigration`·`applyMigration`), `migrations.js`의 `migrationSummary`. red: `ReferenceError: migrationSummary is not defined`. green: 세 상태(전체 체크/전체 해제/후보 0건) 고정. 출처 배지(`verbatim`/`prefix`) 표시 | R1 |
| 4 | **거절 경로**(열린 질문 1이 "reviewed" 의미론으로 확정될 때만). "지금 것 유지"도 명시적 행위이므로 command는 두고 version만 CURRENT로 올린다 — 아이콘이 영원히 남는 것을 막는 유일한 수단. **red**: 거절 후 계획이 비고 아이콘 조건이 꺼진다 | verified | `options.js:653-660`([Keep mine] → `markReviewed()` + `markDirty()`), `migrations.js:97-100`. 결정 1대로 command는 그대로 두고 version만 올린다 — 쓰기는 [Save] 경유 | R1 |
| 5 | **import 경로.** `BACKUP_KEYS`(`options.js:399`)에 `version` 추가, `parseImportedSettings`(`:405-464`)가 version을 해석(숫자 아님 → skipped), 가져온 객체에 대해 같은 계획 계산 → 같은 프리뷰. 내보내기는 저장된 값만 담으므로 자동으로 실린다. **red**: version 있는/없는/이상한 파일 3종, 가져온 v0 객체가 계획을 만든다 | verified | `options.js:415-417`(`BACKUP_KEYS`=`SETTINGS_KEYS`+version), `:437-441`·`:500`(`parseImportedSettings`가 version 반환), `:565-571`(가져온 객체로 같은 계획), `migrations.js:121-139`(`importedSchemaVersion`). red 포함 4건 — 미래 version은 **가져오기 전체 실패**로 던지고 메시지에 두 해결책(chrome://extensions 갱신 / Reset to Defaults)이 들어 있음을 정규식으로 고정 | R1 |
| 6 | **다른 기계에서 아이콘 끄기.** `chrome.storage.onChanged` 리스너가 없다(`grep storage.onChanged extension/` → 0건) — 새로 만든다. **편집 중(dirty)이면 편집 상태를 덮지 않는다**가 핵심 제약. **red**: `shouldAdoptSyncedChange(dirty, changed)` 같은 순수 판정 함수 | claimed | `options.js:662-670`(`storage.onChanged` 리스너 신설 — 기존 0건), `migrations.js:141-149`(`shouldAdoptSyncedChange`). dirty면 채택하지 않는다(편집 중 입력 보호)를 red로 고정 | R1 |
| 7 | **문구·문서 동기화.** `README.md:112`(수기 재적용 안내 → 아이콘 안내)·backup 절(`options.html:366`)에 version 언급, 옵션 페이지 도움말, 앱 설정 창 카드(`SetupWindowController.swift:255-261`, 한국어), `CLAUDE.md`에 불변 원칙 한 줄(버전은 명시적 행위로만 승격) | verified | `README.md:112`(수기 재적용 → 업데이트 표시 안내), `extension/options.html:401`(백업 절에 version·거부 규칙), `CLAUDE.md:42-43`(단일 쓰기 경로에 마이그레이션 추가 + 버전 승격 불변 원칙 신설), `app/Sources/App/SetupWindowController.swift:254-262`(한국어 카드 문구 → 업데이트 표시 안내) | R1 |

| 8 | **R2 — Codex R1 차단(no)의 세 부류를 근본 수정.** 증상 7개를 따로 패치하지 않는다. **⒜ 계획은 항상 "저장될 것"(편집 상태) 위에서, 버튼 identity로**: 런타임 전용 `uid`(저장·내보내기에 절대 미포함), `planMigration`은 편집 상태 스냅샷에서 계산하고 후보 id는 uid, `loadedVersion`은 편집 상태를 구성한 출처 중 **가장 낮은 세대**. **⒝ 신뢰 경계**: 레지스트리를 `Map`으로(프로토타입 키 차단) + 확장 JS의 `obj[사용자문자열]` 조회 전수 소탕, version은 **음이 아닌 정수만** 신뢰하고 판정 함수 하나를 stored·imported가 공유, step 선택은 `step.to > fromVersion`. **⒞ version 바닥·동시성**: `versionFloor`(dirty여도 항상 기록), save는 `set` 직전 재조회해 `max(floor, 현재값, versionToSave)`, `loadSettings`는 await 전후 revision 대조로 스냅샷 폐기, 체크박스는 revision만 올린다. 부수: P3 커버리지 유도 테스트, 빈 suffix 제외, `effect` 정의 명문화, 잔여 3건(describe 합산·"바꿀 것 없음" 문구·echo) | verified | 아래 R2 로그 | R2 |

| 9 | **R3 — Codex R2 차단(no)의 다섯 부류.** ⒜ 쓰기는 로드한 것 위에서만(floor 폐기, 낙관적 동시성 — 다르면 거부) ⒝ 로드 전에는 설정이 없다(`loaded` 게이트 + 로드 세대) ⒞ uid는 우리 것(`adoptButton`/`reshapeButton` 분리) ⒟ prefix 후보는 `behavior-change`(기본 해제) ⒠ 신뢰 경계 마무리(`onMessage` 가드, 역사 픽스처) | verified | 커밋 `856bf03`, 아래 R3 로그. Codex 재검증에서 이 7건은 전부 통과했고 신규 5건으로 차단됐다 — 상태 갱신은 드라이버 몫 | R3 |
| 10 | **R4 — Codex R3 차단(no)의 두 부류.** **⒜ 상태 보호의 경계**: 로드 전 조작 차단을 컨트롤 열거에서 **루트 `inert`** 하나로 바꾸고(열거는 `default-main`·[+ Add Override]를 놓쳐 첫 로드를 영구 중단시켰다), 첫 로드는 revision으로 폐기하지 않으며(`initial`), 진행 중인 리뷰(`reviewTouched`)를 미저장 편집과 같은 급으로 보호하고 자기 저장 echo를 `loadedSnapshot`으로 걸러낸다. **⒝ 저장값 모양의 신뢰 경계**: `adoptStoredSettings` 하나를 load와 import가 공유하고 버린 항목을 보이게 보고한다. 부수: `sameStoredValue`의 배열 length, 소유 키에서만 stale 배너, `effect` 정의를 base dir 계약 안으로 좁힘, 잔여 창 서술 정정. **⒝는 옵션 페이지에서 끝나지 않는다** — `content.js`·`background.js`의 읽기 지점도 같은 검증기를 거치고, 그래서 검증기는 `migrations.js`가 아니라 `defaults.js`에 있다(그 둘은 migrations.js를 로드하지 않는다) | verified | 아래 R4 로그 | R4 |

| 11 | **R5 — Codex R4 차단(no)의 세 부류.** **⒜ "사용자가 말했다"는 신호를 하나로**: `revision`이 유일한 1차 신호이고 모든 상호작용이 `touch()` 하나를 거친다. `dirty`·`reviewTouched`는 그 안에서만 갱신되고, 비동기 작업의 상태 전이는 전부 `nothingHappenedSince(revisionAtStart)` 하나로 판단한다(저장 성공 후 해제도, 로드 응답 적용도). `shouldApplyLoadedSnapshot`은 `reviewTouched`도 함께 본다. **⒝ 외부 입력 검증을 필드까지**: `readableButtonFields`가 `face`·`emoji`·`label`·`command`는 문자열, `claudeInputs`는 문자열 배열임을 요구하고 하나라도 어긋나면 **entry 전체**를 불량으로 세며, import도 같은 함수를 쓴다. **⒞ 로드 실패는 복구 가능**: inert의 루트를 `body`에서 `#app`으로 내리고 상태 줄·[Retry]를 그 밖에 둔다. **⒟ inert는 코드 규칙이 아니다**: `touch()`가 `loaded`가 아니면 무시하므로 프로그램적 이벤트도 상태를 못 바꾼다 | verified | 아래 R5 로그 | R5 |

| 12 | **R6 — Codex R5 차단(no)의 세 부류.** **⒜ 비동기 작업은 시작 시점의 세계 위에서만 정산한다**: Save가 `loadedSnapshot`·`loadGeneration`·`revision`을 불변 캡처하고 `planSave`가 캡처본·세대·"인플라이트 중 변경 도착" 셋으로 판정, Save 직렬화(`shouldStartSave` + 버튼 disabled)와 **Save 중 adoption 보류**(stale 표시만 하고 정산 뒤 재평가), import는 `planImport`로 같은 술어를 통과, `mergedSourceVersion`이 전제(양쪽 ≤ CURRENT)를 스스로 검사해 미래 저장 version + 구버전 백업을 거부. **⒝ 가드가 변이보다 먼저다**: `userAction(accept, change)` 하나로 순서를 구조화하고 진입점 전부를 `edit`/`review`/`editAndReview`로 감쌌다 — [+ Add Button]의 본문은 `appendButton`(순수)로 갈라 테스트가 닿는다. **⒞ 검증기 공유 범위**: `adoptStoredMainBranch`/`readStoredMainBranch`를 `defaults.js`에 두고 options·background가 공유, `skippedByKey`로 entry 단위 유실을 import·load 메시지까지 전파, `claudeInputs`의 hole을 불량으로 | verified | 아래 R6 로그 | R6 |

의존: 1 → 2 → 3 → {4, 5}; 6은 1 뒤 어디든; 7은 마지막; 8은 R1 판정 뒤; 9는 R2 판정 뒤; 10은 R3 판정 뒤; 11은 R4 판정 뒤; 12는 R5 판정 뒤.

수기 검사(자동 게이트가 없는 것 — 항목 3·6):

- [ ] v0 설정이 있는 프로필에서 옵션 페이지를 열면 표시가 뜨고, 프리뷰가 버튼별 "xx → yy"와 동작 서술을 보여 준다
- [ ] [적용] 후 저장하지 않고 새로고침하면 아무것도 바뀌지 않았고 표시가 그대로다
- [ ] [적용] → [Save] 후 표시가 사라지고, 같은 계정의 다른 Chrome에서도 동기화 뒤 사라진다
- [ ] 편집 중(dirty)에 다른 기계의 저장이 동기화돼도 입력이 날아가지 않는다
- [ ] 옛 백업 JSON을 가져오면 같은 프리뷰가 뜨고, 역시 [Save] 전에는 아무것도 저장되지 않는다
- [ ] 커스터마이즈된 command는 나열만 되고 값이 바뀌지 않는다
- [ ] `storage.sync`의 버튼 배열에 `null` 항목을 넣어도 GitHub 페이지에 버튼이 그려지고(나머지 항목으로), 페이지·서비스 워커 콘솔에 "N stored buttons were unreadable and skipped" 경고가 남는다
- [ ] `storage.sync.get`이 실패하도록 흉내 내면(오프라인·throw 주입) 상태 줄에 사유가 뜨고 [Retry]가 보이며, 누르면 정상 로드된다 — 실패 중에도 `#app`은 inert라 저장이 열리지 않는다
- [ ] Save를 누른 직후 다시 누르면 두 번째는 무시되고(버튼 disabled + "Already saving") 저장은 한 번만 나간다
- [ ] Save 대기 중 다른 기기가 저장하면 이 저장이 거부되고(충돌 메시지), 정산 뒤 편집이 없으면 그 변경이 화면에 반영된다
- [ ] 파일 선택 뒤 읽는 동안 카드에 타이핑하면 import가 거부되고("import again") 폼이 그대로 남는다
- [ ] 불량 항목이 섞인 백업을 가져오면 상태 줄에 "1 entry in buttons was unreadable and skipped"가 함께 뜬다

## 전수 소탕 표

"설정의 모양을 읽거나 쓰는 지점" 전체 — 하나라도 `version`을 모르면 키가 유실되거나(저장 시 누락) 잘못 승격된다. 그리고 "손으로 재적용하라"고 적힌 문구 전체.

| 지점 | 이 부류가 성립하는가 | 확인 방법 | 판정 |
|:--|:--|:--|:--|
| `options.js:314-327` (`loadSettings`) | 성립 — 읽는 키 목록에 version이 없다 | 코드 읽기 | 닫음(R1) |
| `options.js:329-378` (`saveSettings`, 유일한 `storage.sync.set`) | 성립 — 여기서 version을 어떻게 찍느냐가 이 루프의 핵심 | `grep -n 'storage.sync.set' extension/` → 1건 | 닫음(R1) — `versionToSave`만 통과 |
| `options.js:399` (`BACKUP_KEYS`) | 성립 — 내보내기/가져오기 대상 목록 | 코드 읽기 | 닫음(R1) |
| `options.js:405-464` (`parseImportedSettings`) | 성립 — 모르는 키는 버려진다 | 코드 읽기 | 닫음(R1) |
| `options.js:466-485` (`exportSettings`) | 성립(파생) — BACKUP_KEYS를 그대로 쓴다 | 코드 읽기 | 항목 5에 포함 |
| `options.js:488-502` (`applyImportedSettings`) | 성립 — 마이그레이션 적용이 따라야 할 패턴의 원형 | 코드 읽기 | 닫음(R1) |
| `options.js:381-392` (`resetSettings`) | 성립 — 현재 프리셋으로 되돌리므로 내용은 CURRENT 세대가 된다 | 코드 읽기 | 닫음(R1) — 결정 7대로 `markReviewed()` 호출 |
| `options.js:20-26` (`state`) | 성립 — 로드한 version과 "이번 세션에 동의했는가"를 담을 자리가 없다 | 코드 읽기 | 닫음(R1) |
| `background.js:139` (`loadButtons`) | 성립 안 함 — command를 그대로 실행하고 version을 보지 않는다(그것이 설계) | 코드 읽기 | 안전 |
| `content.js:82` (`loadButtonConfigs`) | 성립 안 함 — 위와 같다 | 코드 읽기 | 안전 |
| `background.js:123` (`repoMainBranch`·`defaultMain` 읽기) | 성립 안 함 — 버튼 스키마와 무관 | 코드 읽기 | 안전 |
| `defaults.js:111-124` (`BUTTON_KINDS.storageKey`) | 성립(간접) — 저장 키 목록의 정본이라 version 상수의 이웃이 된다 | 코드 읽기 | 닫음(R1) |
| `294c46a:extension/defaults.js`의 v0 command 11줄 | 성립 — 레지스트리의 원본. 중복 제거하면 8쌍 | 격리 vm 컨텍스트 대조(R1) | 닫음(R1) — 8/8 일치, 누락·잉여 0 |
| `README.md:112` (수기 재적용 안내) | 성립 — 마이그레이션이 생기면 낡는다 | 문서 읽기 | 닫음(R1) |
| `README.md`의 backup 절·`options.html:366` | 성립 — 내보내기 JSON에 version이 실린다는 사실이 빠진다 | 문서 읽기 | 닫음(R1) |
| `SetupWindowController.swift:255-261` (앱 카드 한국어 문구) | 성립 — "옵션 페이지에서 프리셋을 다시 적용하고 저장하세요"가 낡는다 | `grep -n '프리셋을 다시 적용'` | 닫음(R1) |
| `app/Sources/Core/*` (렌더·검증) | 성립 안 함 — 앱은 command 문자열을 받을 뿐 스키마를 모른다 | 코드 읽기 | 안전(이슈 제약 6 검증 결과) |
| `tests/buttons.test.js` | 성립 — 프리셋·기본값을 고정하는 곳이라 레지스트리 교차 검사의 이웃 | 파일 읽기 | 닫음(R1) — 신설 `tests/migration.test.js`가 이웃 |
| `extension/manifest.json` | 성립 안 함 — `options_page`는 자기 `<script>`로 로드하고, `content_scripts.js`는 defaults/layout/content 셋뿐이라 migrations.js가 낄 자리가 없다(의도대로 콘텐츠 스크립트는 마이그레이션을 모른다) | `sed -n '19,32p' extension/manifest.json` | 안전 — 변경 없음 |

### 소탕 표 2 — `obj[사용자 문자열]` 조회 (R2, 부류 ⒝)

키가 **사용자 설정·페이지 URL·메시지**에서 오면 평범한 객체 조회는 프로토타입 멤버를 답으로 돌려준다. 확장 JS 전체를 훑은 결과.

| 지점 | 키의 출처 | 판정 |
|:--|:--|:--|
| `migrations.js` `step.rewrites[current]` | 저장된 command | **구멍 → 닫음(R2)**: `V0_TO_V1`을 `Map`으로. `constructor`·`toString`·`__proto__`·`valueOf`·`hasOwnProperty`가 후보로 오인되고 저장 시 `.trim()`에서 죽었다 |
| `background.js:126` `data.repoMainBranch?.[repo]` | **페이지 URL의 repo 이름** | **구멍 → 닫음(R2)**: `Object.hasOwn` 가드. `{}` 오버라이드 맵에서 `repoMainBranch['constructor']`가 함수를 돌려주고 그것이 브랜치 이름으로 앱까지 흘러갔다. 기존 코드지만 같은 부류라 같은 라운드에서 닫는다 |
| `background.js:293` `ACTION_KIND[message.action]` | 런타임 메시지 | **구멍 → 닫음(R2)**: `Object.hasOwn` 가드. 상속 멤버가 truthy를 통과한 뒤 `RUN_BY_KIND[함수]`가 `undefined`가 돼 다음 줄에서 죽는다 |
| `BUTTON_KINDS[kind]`(`background.js:138`·`content.js:80`·`options.js` 다수) | `pageTypeOf`가 돌려주는 내부 열거값(`pr`/`issue`/`repo`) | 안전 — 사용자 문자열이 아니다 |
| `data[storageKey]`·`settings[storageKey]`·`data[key]`(import 파싱) | `SETTINGS_KEYS`/`SECTIONS` — 우리 상수 | 안전 |
| `state.buttons[kind]`·`presetTemplates[kind]`·`btn[field]`(필수 항목 검사) | 내부 열거값·`REQUIRED_FIELDS` | 안전 |
| `Object.fromEntries(entries)`(`serializeOverrides`) | 사용자 repo 이름이 **키가 된다** | 안전 — `fromEntries`는 own property로 만든다(프로토타입 오염 아님). 읽는 쪽은 위의 `hasOwn` 가드가 받는다 |

### 소탕 표 3 — 쓰기·편집 진입점과 로드 게이트 (R3, 부류 ⒜⒝)

`state.loaded`를 요구해야 하는 곳과, 로드 스냅샷 대조가 걸리는 곳 전부.

| 지점 | 로드 전에 불릴 수 있는가 | 판정 |
|:--|:--|:--|
| `saveSettings` | **그렇다** — 초기 await 중 [Save] | 닫음(R3): `requireLoaded()` + 버튼 disabled. 유일한 `storage.sync.set`이고 여기서 `planSave`가 로드 스냅샷과 라이브를 대조한다 |
| `resetSettings` | 그렇다 | 닫음(R3): `requireLoaded()` + disabled. 리셋은 동의(결정 7)라 로드 전에 통과하면 빈 상태를 승격시킨다 |
| `importSettings` | 그렇다 | 닫음(R3): `requireLoaded()`. 빈 편집 상태에 병합되고 대조할 스냅샷도 없다 |
| `applyMigration` | 이론상 — 계획이 없으면 패널이 안 뜨지만 가드는 둔다 | 닫음(R3): `requireLoaded()` |
| [Keep mine] / [Got it] | 위와 같다 | 닫음(R3): `requireLoaded()` |
| `+ Add Button` | 그렇다 | 닫음(R3): disabled. 편집 상태를 바꾸므로 다음 저장 내용에 들어간다 |
| [Export (JSON)] | 그렇다 | 닫음(R3): disabled. 저장소에서 직접 읽으므로 손상은 없지만 로드 전 클릭은 빈 결과로 혼란만 준다 |
| 카드 안의 입력·드래그·프리셋 적용 | 아니다 — 카드는 로드 후에만 그려진다 | 안전(구조상) |
| `loadSettings` 자신 | 겹칠 수 있다 | 닫음(R3): 세대 카운터 + revision/dirty 대조(`shouldApplyLoadedSnapshot`) |
| `storage.onChanged` → `loadSettings` | 로드 전에 도착 가능 | 닫음(R3): `state.loaded` 확인 후 반환 — 진행 중인 로드가 어차피 최신값을 가져온다 |

### 소탕 표 4 — uid가 편집 상태로 들어오는 지점 (R3, 부류 ⒞)

| 지점 | 출처 | 판정 |
|:--|:--|:--|
| `loadSettings`의 저장값 | **외부** | 닫음(R3): `adoptButton` — 들어온 uid는 버린다 |
| `applyImportedSettings`의 파일 | **외부** | 닫음(R3): `adoptButton` |
| `resetSettings`의 기본값 | 우리 프리셋이지만 편집 상태 밖 | 닫음(R3): `adoptButton` |
| `+ Add Button` | 새 버튼 | 닫음(R3): `adoptButton` |
| `applyPreset`(카드에 프리셋 적용) | 같은 카드의 내용 교체 | 닫음(R3): `reshapeButton(…, 기존 uid)` — 같은 버튼이므로 이름을 유지한다 |
| `saveSettings`의 화면 정리 | 편집 상태 | 닫음(R3): `reshapeButton(…, 기존 uid)` |
| `applyMigration`의 결과 | 편집 상태 | 닫음(R3): `reshapeButton(button, button.uid)` |
| `duplicateButton`의 사본 | 편집 상태(복제) | 닫음(R3): 사본에 `nextButtonUid()` — spread가 uid까지 복제한다 |
| `parseImportedSettings`의 형태 정규화 | 파일 | 닫음(R3): `buttonFields`(uid 없음) — 신원은 `adoptButton`이 나중에 붙인다 |
| `toStoredButton` | 편집 상태 → 저장 | 안전 — uid를 떼어 낸다(테스트로 고정) |

### 소탕 표 5 — 로드 전 조작 가능한 컨트롤 (R4, 부류 ⒜-1)

열거로는 막을 수 없다는 것이 R3에서 증명됐다(버튼만 막고 `default-main`·[+ Add Override]를 놓쳐 첫 로드가 영구 중단). **루트 하나에 `inert`**를 걸어 전수를 덮는다.

| 컨트롤 | R3(열거) | R4(루트 게이트) |
|:--|:--|:--|
| [Save] · [Reset to Defaults] · [Export] · [Import…] · [+ Add Button] ×3 | disabled | 덮임 |
| `#default-main` 입력 | **살아 있었다 — revision을 올려 첫 로드를 폐기시켰다** | 덮임 |
| [+ Add Override] · 오버라이드 행의 입력·[✕] | **살아 있었다** | 덮임 |
| 버튼 카드 내부(입력·드래그 핸들·프리셋 select·팔레트·claude 입력 행) | 로드 후에만 그려져 사실상 안전 | 덮임 |
| 마이그레이션 배지·체크박스·[Apply]·[Keep mine] | 로드 후에만 보임 | 덮임 |
| 앞으로 추가될 컨트롤 | 누락 위험 | 덮임(등록 불필요) |

`requireLoaded()` 가드는 그대로 둔다 — `inert`는 클릭 경로만 막고, 클릭에서 오지 않는 호출(이벤트, 타이머, 향후 코드)은 규칙이 따로 필요하다.

### 소탕 표 6 — 저장값을 읽는 지점 (R4, 부류 ⒝)

`storage.sync`의 내용은 다른 기기·다른 확장 버전·손편집이 쓴 것이라 import 파일과 같은 신뢰 등급이다.

| 지점 | 읽는 것 | 판정 |
|:--|:--|:--|
| `options.js` `loadSettings` | 버튼 배열·`defaultMain`·`repoMainBranch` | **구멍 → 닫음(R4)**: `adoptStoredSettings`(버튼 부분은 `defaults.js`의 `adoptStoredButtons`를 부른다) 공유. `[null]`·`{length:1}`·문자열·중첩 배열이 전부 TypeError였고 페이지가 `loaded=false`로 굳었다 |
| `options.js` `parseImportedSettings` | 같은 모양(파일) | 닫음(R4): 같은 검증기를 쓰고 파일 고유 규칙(개수 상한, "빈 배열은 설정 아님")만 위에 얹는다 |
| `options.js` `exportSettings` | 저장값을 그대로 파일로 | 안전 — 해석하지 않고 직렬화만 한다 |
| `background.js` `loadButtons` | 버튼 배열 | **닫음(R4)**: `readStoredButtons` 경유 — 같은 검증기에 `console.warn` 한 줄. 검증기를 `defaults.js`에 둬 content/background가 `migrations.js`를 로드하지 않는 경계를 지켰다 |
| `content.js` `loadButtonConfigs` | 버튼 배열(그리기) | **닫음(R4)**: 같은 `readStoredButtons` |
| `background.js:123` `repoMainBranch`·`defaultMain` | 오버라이드 맵 | **구멍 → 닫음(R6)**: R2의 `Object.hasOwn` 가드는 **키**만 봤고 **값**은 보지 않았다 — `{widget:42}`가 `main=42`를 앱에 보내고, 저장값이 문자열 `"abc"`면 `Object.hasOwn("abc","0")`이 참이라 repo `0`의 브랜치가 `"a"`가 된다. `defaults.js`의 `adoptStoredMainBranch`(순수)/`readStoredMainBranch`(+`console.warn`)를 options·background가 공유 |

### 소탕 표 7 — 상호작용 진입점: 가드가 변이보다 **먼저**인가 (R5 신호 / R6 순서)

`touch()`만이 `revision`·`dirty`·`reviewTouched`를 건드린다(R5). R5까지는 그 호출이 **변이 뒤**에 있어 가드가 "이미 일어난 변경"만 거절할 수 있었다 — 로드 전 `pr-add.click()`이 버튼을 추가한 뒤에야 물었다(Codex R5 미해결분). R6에서 순서를 규칙이 아니라 **구조**로 바꿨다: `userAction(accept, change)`(migrations.js)가 가드를 먼저 돌리고 변경은 **클로저**라 가드 앞에 앉을 자리가 없다. options.js는 `edit`/`review`/`editAndReview` 셋으로만 그것을 부른다.

| 진입점 | 경유(R6) | 신호 | 변이 전 가드 |
|:--|:--|:--|:--|
| 카드 입력 — face·label·command | `edit(…)` | dirty | ✓ |
| 카드 입력 — claude 입력 행(`.ci-input`) | `edit(…)` | dirty | ✓ |
| 카드 [Delete] | `edit(…)` | dirty | ✓ |
| 카드 [Duplicate] | `edit(…)` | dirty | ✓ (상한 확인은 가드 앞, 변이는 안) |
| 카드 팔레트 버튼 | `edit(…)` | dirty | ✓ |
| 카드 [+ Add Input] | `edit(…)` | dirty | ✓ (상한 확인은 가드 앞, `push`는 안) |
| 카드 claude 입력 [×] | `edit(…)` | dirty | ✓ |
| 프리셋 적용 select | `edit(…)` | dirty | ✓ (`confirm`은 가드 앞 — 상태를 바꾸지 않는다) |
| 드래그 drop·↑↓ (`reorderButtons`) | `edit(…)` | dirty | ✓ (거절되면 인덱스도 그대로 반환) |
| `#default-main` 입력 | `touch({dirty:true})` | dirty | ✓ (편집 상태에 바꿀 것이 없다 — 필드 자체가 그 설정이다) |
| 오버라이드 입력(repo·branch) | `edit(…)` | dirty | ✓ |
| 오버라이드 [✕] | `edit(…)` | dirty | ✓ |
| [+ Add Override] | `edit(…)` | dirty | ✓ |
| [+ Add Button] ×3 | `edit(…)` + `appendButton`(순수) | dirty | ✓ — **Codex가 지목한 그 경로**. 본문을 순수 함수로 갈라 red가 닿는다 |
| [Reset to Defaults] | `editAndReview(…)` | dirty + review | ✓ |
| 가져오기 적용(`applyImportedSettings`) | `edit(…)` | dirty | ✓ (그 앞에 `planImport` 정산까지) |
| 마이그레이션 배지 클릭 | `review(…)` | review | ✓ |
| 후보 체크박스 | `review(…)` | review | ✓ — `checked`를 읽는 것은 가드 앞, `selection` 변이는 안 |
| [Apply selected] | `editAndReview(…)` | review + dirty | ✓ |
| [Keep mine] / [Got it] | `editAndReview(…)` | review + dirty | ✓ |
| [Save] · [Export] · [Import…] · [Retry] | 사용자 상태를 바꾸지 않음(읽기·쓰기 동작) | — | `requireLoaded()`·`shouldStartSave` 가드 |

### 소탕 표 9 — 비동기 경로가 무엇을 캡처하고 무엇으로 정산하는가 (R6, 부류 ⒜)

넷 다 "읽고, 나중에 돌아와, 페이지를 바꾼다"이고 그 사이 세계가 움직인다. 각자 **시작 시점의 세계를 캡처**하고 그 캡처본으로 정산한다 — `state`를 다시 읽으면 그 사이 adoption이 갈아 끼운 값을 보게 된다(그것이 Codex R5 P1이었다).

| 경로 | 시작 시 캡처 | 쓰기·적용 게이트 | 정산(사용자에 대한 주장) |
|:--|:--|:--|:--|
| **Save** | `loadedSnapshot`·`loadGeneration`·`revision`·payload | `planSave`: ① 인플라이트 중 소유 키 변경 도착 ② `generationAtStart !== generationNow` ③ `saveConflict(캡처본, 라이브)` — 하나라도 걸리면 **거부** | `nothingHappenedSince(revisionAtStart, now)` — 거짓이면 `reviewTouched` 해제·뷰 정리·재계획을 전부 보류 |
| **load** | `revision`·`loadGeneration`·`initial` | `shouldApplyLoadedSnapshot`: 세대가 최신 + (첫 로드가 아니면) `nothingHappenedSince` ∧ `!dirty` ∧ `!reviewTouched` | 적용이 곧 정산 |
| **import** | `revision`·`loadGeneration` | `planImport`: `nothingHappenedSince` ∧ 세대 동일 — 아니면 **거부**(`IMPORT_STALE_MESSAGE`) | 적용은 `edit(…)`을 거쳐 revision을 올린다 |
| **adoption**(`storage.onChanged`) | 이벤트 자체(동기) | `shouldAdoptSyncedChange(unsavedWork(), changes)` — `unsavedWork` = `dirty ∥ reviewTouched ∥ saving` | Save 중이면 **보류**(`deferredChange`)했다가 정산 뒤 같은 질문을 다시 묻는다 |

Save·load·import·adoption이 쓰는 술어는 **`nothingHappenedSince` 하나**다(adoption은 그 술어를 쓰는 load에 위임). 세대 비교는 그 옆에 붙는 두 번째 축이고, 뜻이 다르다 — revision은 "사용자가 말했다", generation은 "페이지가 자기 내용을 갈아 끼웠다".

### 소탕 표 8 — 버튼 필드별 규칙 (R5, 부류 ⒝)

`adoptStoredButtons` → `readableButtonFields`. 하나라도 어긋나면 **entry 전체**를 버리고 센다 — 필드만 고쳐 살려 두는 것이 `claudeInputs` 유실의 원인이었다.

| 필드 | 규칙 | 어겼을 때 |
|:--|:--|:--|
| `face` | 있으면 문자열 | entry 불량 |
| `emoji`(레거시) | 있으면 문자열 | entry 불량 |
| `label` | 있으면 문자열 | entry 불량 |
| `command` | 있으면 문자열 | entry 불량 — `42`가 `.trim()`에 닿던 경로 |
| `claudeInputs` | 있으면 **문자열 배열**(원소 하나라도 비문자열이면 불량) + **hole이 없을 것**(R6: `Object.keys(arr).length === arr.length`) | entry 불량 — `"hello"`가 조용히 `[]`가 돼 다음 Save에 유실되던 경로. `new Array(1)`은 `every`가 hole을 건너뛰어 "전부 문자열"로 통과했고 빈 칸이 `"undefined"`가 됐다 |
| 위 필드가 **없음** | 허용 | 옛 버전이 저장한 버튼의 모습이다 |
| `defaultMain` | 문자열 | 키를 버리고 센다 (R6: `adoptStoredMainBranch` — background와 공유) |
| `repoMainBranch` | 문자열→문자열 맵 | 맵이 아니면 키를 버리고, 비문자열 값은 항목별로 버리고 센다 (R6: 같은 함수, background도 이것을 통과한 뒤에만 `{main}`을 정한다) |

버린 개수는 **총합만이 아니라 키별로**도 센다(`adoptStoredSettings`의 `skippedByKey` → `describeSkipped`). 총합만 있을 때는 "좋은 버튼 1 + 불량 버튼 1"인 파일이 좋은 쪽만 조용히 가져오고 보고에는 아무것도 남지 않았다 — 키가 결과에 있었기 때문이다.

## 라운드 로그

### R0 — `6fa5daf` (계획 초안)

- 차단: 없음(구현 전).
- 조사: 이슈 #31 본문 전문, `extension/defaults.js`·`options.js`(load/save/import/export 전 구간)·`options.html`·`background.js`·`content.js`, `tests/buttons.test.js`, `docs/plans/base-dir-fallback.md`, `git log --oneline -8`, `294c46a`의 v0 프리셋 문자열.
- 확인한 사실:
  - `storage.sync.set`은 리포 전체에 **1곳**(`options.js:349`)뿐이다 — 단일 쓰기 경로가 실제로 지켜지고 있다.
  - `chrome.storage.onChanged` 리스너는 **0건** — "다른 기계에서 아이콘이 꺼진다"는 요구는 새 리스너 없이는 성립하지 않는다.
  - `background.js:139`·`content.js:82`는 저장된 command를 그대로 읽어 실행한다 — 마이그레이션 전 설정이 계속 동작한다(동의 기반 설계의 전제가 이미 충족).
  - 앱은 `version`을 읽지도 쓰지도 않는다. 이슈 제약 6("앱은 건드릴 일 없음")은 **메커니즘 기준 참**이고, 낡는 것은 문구 1곳(`SetupWindowController.swift:255-261`)뿐이다.
  - v0 프리셋 command는 11개지만 중복(`z {repo} && claude` ×3, `z {repo}` ×2)을 걷어내면 **8쌍**이다.
- 판정: 미요청(검증자 스레드 미기동).

### R1 — 워킹트리(미커밋, base `6fa5daf`)

- 범위: 항목 1∼7 전부. 신규 파일 `extension/migrations.js`·`tests/migration.test.js`, 수정 `defaults.js`·`options.js`·`options.html`·`README.md`·`CLAUDE.md`·`SetupWindowController.swift`.
- 진행 중 결정 개정 3건(사용자): 결정 3(`unconditional`로), 4(엄격 접두 일치 후보 승격), 5(미래 백업 거부). 위 「R0 결정」 절의 해당 항목을 개정본으로 갈아 두었고, 그 개정으로 낡은 서술 4곳(목표·비목표·불변 원칙·설계 스케치)도 함께 고쳤다.
- red 기록: 항목 1 → `Error: ENOENT ... extension/migrations.js`; 항목 2 → `ReferenceError: planMigration is not defined`; 항목 3·5·6 → `ReferenceError: migrationSummary is not defined`. 각 red 확인 후 구현.
- **red가 실제 결함 1건을 잡았다**: 계획은 *저장된* 설정으로 계산하는데 적용은 *편집 상태*에 하므로, 그 사이 사용자가 타이핑하거나 순서를 바꾸면 인덱스가 엉뚱한 버튼을 가리킨다. `applyMigrationPlan`에 "계획할 때의 command와 아직 같을 때만 교체" 가드를 넣고 red로 고정(`a candidate is only rewritten while the command is still the one that was planned`).
- **v0 8쌍 검증(294c46a 대조)**: `git show 294c46a:extension/defaults.js`를 스크래치패드에 뽑아 격리 vm 컨텍스트로 로드하고 현재 `defaults.js`+`migrations.js`와 대조 — `v0 distinct preset commands: 8` / `registry pairs: 8` / `v0 cmds NOT in registry: []` / `registry keys not in v0: []` / `targets not a current preset: []` / `current presets unreachable: []`. 두 파일이 같은 상수명을 선언해 같은 컨텍스트에서는 `SyntaxError: Identifier 'PR_PRESETS' has already been declared`가 나므로 컨텍스트 분리가 필수였다.
- 실측: `node --test` **56/0**(기준 22 + 신규 34 — `tests/migration.test.js` 32건, 기존 24건은 불변), `swift test` 210/0, `app/build.sh` + `app/e2e.sh` PASS 9건(확장만 고쳤으므로 불변이어야 하고 실제로 불변).
- **미검증**: 항목 3·6의 DOM·클릭 동작(배지 토글, 체크박스 상호작용, 실제 `storage.onChanged` 수신)은 자동 게이트가 없다 — 위 수기 검사 목록으로 남는다. `node --check`로 세 스크립트의 구문만 확인했다.
- 판정: 미요청.

## 열린 질문 (R0에서 제기 — 전부 위 「R0 결정」으로 닫힘)

- **1. `version`의 의미론 — "마이그레이션된 세대"인가 "검토한 세대"인가.** 전자면 거절할 방법이 없어 옛 command를 의도적으로 유지하는 사용자에게 아이콘이 영구히 남는다. 후자면 [적용]과 [지금 것 유지] 둘 다 version을 올리고(내용은 그대로) 아이콘이 꺼진다 — 필드 하나로 끝나고 "적용이 곧 동의"라는 사용자 요건과도 어긋나지 않는다(거절도 하나의 결정). 초안은 **후자를 권고**하되, 이슈 문구가 전자를 전제하므로 승인이 필요하다. — 막는 항목: 1, 4
- **2. 고칠 것이 없는 계획(actionable 0건)일 때 조용히 승격할 것인가.** 아무것도 안 하면 커스텀 command만 쓰는 사용자에게 아이콘이 계속 뜬다. 승격하면 informational 목록(“당신의 커스텀 command도 같은 개선을 원할 수 있다”)을 한 번도 못 보고 지나간다. — 막는 항목: 1, 2
- **3. base dir을 모른다는 제약을 프리뷰의 조건부 서술로 해결하는 것이 "판정 선언 의무"를 충족하는가.** 대안은 앱에 상태 질의 채널을 만드는 것인데, 그것은 "확장은 앱 설정을 알 수 없다"는 #30의 설계를 뒤집고 이슈 제약 6("앱은 건드릴 일 없음")도 깬다. 초안은 조건부 서술을 권고한다. — 막는 항목: 2, 3
- **4. informational 항목(커스터마이즈된 command)에 기계적 수정 제안을 붙일 것인가.** 예: 맨 앞의 `z {repo}`만 `{cd}`로 바꾸는 1건짜리 제안 + 개별 동의. 잡히는 범위는 넓어지지만 "커스텀은 건드리지 않는다"의 경계가 흐려진다. — 막는 항목: 2, 3
- **5. 현재보다 높은 version의 백업을 가져오면.** 거절 / 경고 후 그대로 채움 / 채우되 [Save]를 막음. 그대로 두면 저장 시 낮은 version을 덮어써 표식만 조용히 강등된다. — 막는 항목: 5
- **6. 레지스트리를 `defaults.js`에 둘 것인가 `extension/migrations.js`로 뺄 것인가.** 이슈 제약 5는 **버전 상수**만 defaults.js로 못 박는다. 분리하면 defaults.js가 "현재의 진실"로 남고 역사 문자열은 옆방으로 가지만, 상수와 레지스트리가 갈라져 드리프트 여지가 생긴다(테스트로 막을 수는 있다). — 막는 항목: 2
- **7. [Reset to Defaults]는 동의인가.** 현재 프리셋으로 되돌리므로 내용은 CURRENT 세대가 된다. version을 올리지 않으면 "내용은 최신인데 아이콘은 켜짐"이 되고, 올리면 "리셋이 곧 마이그레이션 동의"가 된다. — 막는 항목: 1
- **8. 동의 단위 — 항목별인가 일괄인가.** 이슈는 동작 변화에 대해 "let the user decide per item"이라고 적었다. 항목별이면 체크박스 UI와 부분 적용 상태가 생기고, 일괄이면 단순하지만 "일부만 받기"가 불가능하다. — 막는 항목: 3

### R1 — `ab9957d` (Codex 판정: 차단)

- 판정 원문: **"이 구현에 합의하지 않습니다. `node --test` 56/0은 재현했지만, 통합 경로의 고심각도 결함을 놓칩니다."** 불변 원칙 ②(단일 쓰기 경로)·④(실행 경로 무지)는 통과, ①(명시적 승격·미래값 보존)·③(후보 판정 엄격성)은 **실패**.
- P1 ×5: (1) 부분 import(`{"defaultMain":"main"}`)가 파일에 있는 키만 계획해 나머지 섹션의 옛 command를 검토 없이 version 1로 만든다 (2) 같은 command가 둘일 때 체크 해제→순서 변경→적용이 인덱스 가드를 뚫어 엉뚱한 버튼을 고친다 (3) `V0_TO_V1["constructor"]` 등 프로토타입 키가 verbatim 후보로 오인돼 저장 시 `.trim()` TypeError (4) dirty 중 원격이 version 7을 저장하면 로컬 일반 저장이 0으로 **강등** (5) `onChanged` → `loadSettings()`의 await 사이에 타이핑하면 덮어씀, 체크박스 변경은 dirty가 아니라 sync가 선택을 되돌림.
- P2: version `0.5`를 유효로 받아 `step.from >= 0.5`가 0→1 step을 건너뛰고 빈 검토 화면 → 확인 → 옛 command가 v1로 남는다. P3: 레지스트리 커버리지 테스트가 3개 command만 봐서 쌍 하나를 지워도 통과.
- 우리 판단: (a) 검토 세대 의미론 **수용**, (d) options 전용 로드 **수용**, (c) 접두 승격 조건부 수용 — `z {repo} && `(빈 suffix)·문법 오류 command까지 후보로 잡는 경계는 제한 요구, (b) `unconditional` 분류 **반박** — "base dir이 있으면 실제 동작 변화다. 안전한 개선으로 취급할 수는 있어도 unconditional이라는 효과 분류는 부정확", (e) echo는 race·강등 결함과 겹쳐 무해로 볼 수 없음.
- 부류 이동: 순수 함수 단위는 전부 통과했고 결함은 **통합 경로**(스냅샷 선택·동시성·신뢰 경계)에 모였다 — R2는 이 세 부류를 근본 수정으로 닫는다.

### R2 — 워킹트리(미커밋, base `ab9957d`)

- 범위: 항목 8. Codex가 지목한 증상 7개를 **부류 셋**으로 묶어 근본 수정했다.
- **⒜ 계획은 편집 상태 위에서, 버튼 identity로**: 편집 상태의 모든 버튼이 런타임 `uid`를 갖고(`options.js`의 `normalizeButton` 단일 깔때기), 후보 id가 uid가 되며(`migrations.js` `planMigration`), 적용은 uid로 찾은 뒤 command 동일성까지 확인한다. `editStateSnapshot()`이 계획의 유일한 입력이라 setPlan 호출 4곳(load·save 후·import·apply/keep)이 같은 것을 본다. import는 `mergedSourceVersion`으로 **더 낮은 세대**를 취한다. uid는 `toStoredButton`(defaults.js)이 떼어 낸다.
- **⒝ 신뢰 경계**: `V0_TO_V1`을 `Map`으로, version은 `normalizeVersion`(음이 아닌 정수만) 하나를 stored·imported가 공유, step 선택은 `stepsFrom`의 `step.to > fromVersion`. `obj[사용자문자열]` 전수 소탕에서 **기존 코드 2건**(`background.js`의 `repoMainBranch[repo]`, `ACTION_KIND[message.action]`)도 같은 부류라 함께 닫았다 — 소탕 표 2.
- **⒞ version 바닥·동시성**: `state.versionFloor`(load·onChanged에서 **dirty여도** 기록), 저장은 `set` 직전 `storage.sync.get(VERSION_KEY)`로 재조회해 `versionToWrite`가 `max(바닥, 현재값, versionToSave)`를 낸다. `loadSettings`는 await 전 revision을 잡고 뒤에서 `shouldApplyLoadedSnapshot`으로 대조해 늦은 스냅샷을 버린다. 체크박스 변경은 `state.revision++`(dirty 아님)이라 sync가 선택을 되돌리지 못한다. 자기 저장의 echo도 같은 가드로 무해해진다.
- red 기록(3배치): ⒝+P3+(c) → `not ok 33∼39` 7건; ⒜ → `not ok 17·19·21·40∼45` 9건(기존 3건은 uid 도입으로 의도적으로 깨진 것); ⒞ → `not ok 46∼48` 3건. 각 배치 red 확인 후 구현.
- **잔여(설계상 남김)**: 저장의 `get`↔`set` 사이 창은 트랜잭션 없이는 닫히지 않는다 — 그 사이 다른 기계가 더 높은 version을 쓰면 이 저장이 덮는다. 바닥·재조회로 창을 최소화했고, 피해는 "알림이 한 번 더 뜬다"이지 command 손실이 아니다.
- 실측: `node --test` **72/0**(R1 56 → 신규 16), `swift test` 210/0, `app/build.sh` + `app/e2e.sh` PASS 9건. `node --check`로 확장 스크립트 5개 구문 확인.
- **미검증**: DOM·클릭 경로(배지·체크박스·실제 `storage.onChanged` 수신)는 여전히 자동 게이트가 없다 — 수기 검사 목록 그대로.
- 판정: 미요청.

### R2 — `524c91e` (Codex 판정: 차단)

- 기존 7건 재검증: **전부 통과**("P1 부분 import 통과 / 중복 command·순서 변경 통과 / prototype key 통과 / future version 강등 통과 / load race 해당 입력 통과 / fractional version 통과 / 레지스트리 drift 통과").
- 신규 P1 ×3: (1) **초기 `loadSettings()`의 await 중 [Save]** — 초기 state가 `buttons=[]`·`loadedVersion=SETTINGS_VERSION`이라 빈 배열 + version 1을 써서 "command 소실 + 조용한 승격"을 동시에 재현 (2) **겹친 load 응답의 순서 역전** — L0(옛)·L1(새)이 같은 revision이라 둘 다 적용되고 늦게 온 옛 스냅샷이 이김, 이후 툴팁 저장이 옛 command를 version 1로 씀 (3) **get↔set 창은 command 손실도 일으킨다** — 기기 A(dirty, 옛 command)가 B의 마이그레이션 저장 뒤에 저장하면 floor가 version 1을 보존한 채 옛 command를 써서 B의 명시적 마이그레이션이 사라지고 알림도 안 옴. 판정 원문: **"`versionFloor`는 version metadata만 보호하고 command 배열 병합은 하지 않습니다 … '피해는 알림 한 번 더이고 command 손실은 없다'는 잔여 수용 근거는 성립하지 않습니다."**
- 신규 P2 ×2: (4) 저장 데이터의 `uid: 0`(숫자)을 보존해 계획 id(숫자)와 DOM dataset(문자열)이 어긋나 **체크 해제가 무력화**, 중복 uid도 동일 (5) **`unconditional`은 prefix 커스텀에 부정확** — `z {repo} && git clean -fdx` + base dir + 동명 타저장소면 옛 command는 아무것도 안 하고 새 command는 다른 저장소에서 `git clean -fdx`. "verbatim preset만 unconditional로 두고 prefix custom은 behavior-change로 보는 편이 정확".
- 신규 P3 ×2: (6) `onMessage(null)`이 `message.action`에서 예외(hasOwn 이전) (7) 현재 프리셋에서 유도한 커버리지는 프리셋과 쌍을 **함께** 지우면 통과 — 역사 문자열 자체의 오라클이 없다.
- 판단: (a)(c)(d) 수용, (b) 반박(위 5), 잔여 창 재반박(위 3).
- **드라이버 소견**: R2의 "version 바닥" 설계는 내 지시였고 틀렸다 — version은 관찰된 최댓값이 아니라 **쓰는 내용의 세대**를 말해야 한다. 바닥은 v0 내용에 v1 표식을 씌우는 장치였다. R3는 바닥을 버리고 저장 시점의 낙관적 동시성 검사(로드 스냅샷과 라이브 저장값 대조, 다르면 저장 거부 + 재로드 안내)로 바꾼다 — storage.sync에 CAS가 없으니 **덮어쓰기 대신 거부**가 리포 철학(보이는 실패 > 조용한 손상)에 맞는 답이다.

### R3 — 워킹트리(미커밋, base `524c91e`) · 항목 9

- 범위: Codex R2 차단의 신규 7건을 부류 다섯으로 묶어 근본 수정. 기존 7건은 재검증에서 전부 통과했으므로 건드리지 않았다.
- **⒜ 쓰기는 로드한 것 위에서만.** `versionFloor`·`raiseVersionFloor`·`versionToWrite`를 **삭제**했다(드라이버 소견대로 그 설계가 결함의 원인이었다 — version 표식만 지키고 command는 지키지 않았다). version은 `versionToSave`만으로 정하고, 저장은 쓰기 직전 소유 키 전부를 재조회해 `planSave`가 로드 스냅샷과 대조, 다르면 거부한다(`SAVE_CONFLICT_MESSAGE`). 성공 시 로드 스냅샷을 방금 쓴 payload로 갱신해 자기 echo를 구분한다. onChanged는 dirty 여부와 무관하게 `staleSinceLoad`를 세워 배너를 띄우되, 판정은 저장 시 재조회가 정본이다(이벤트 유실 대비).
- **⒝ 로드 전에는 설정이 없다.** `loaded=false`·`loadedVersion=null`로 시작하고 진입점 7곳이 `requireLoaded()`를 통과한다(+ 버튼 disabled). 로드 세대 카운터를 `shouldApplyLoadedSnapshot`에 넣어 추월당한 응답을 버린다.
- **⒞ uid는 우리 것.** `normalizeButton` 하나를 `adoptButton`(외부 입력 — uid를 버리고 새로 부여)과 `reshapeButton`(편집 상태 — 이름 유지)으로 갈랐고, 둘 다 `defaults.js`에 둬 순수 테스트가 닿는다. 유입 지점 10곳을 소탕 표 4로 정리했다.
- **⒟ prefix 후보는 `behavior-change`.** 레지스트리를 `verbatimEffect`/`prefixEffect`로 갈라 선언 의무를 유지하고, 후보마다 `effect`와 전용 `describe`를 싣는다. `defaultSelection`이 `unconditional`만 체크한다.
- **⒠ 신뢰 경계 마무리.** `onMessage`에 `typeof message?.action !== 'string'` 가드(+`buttonIndex` 정수 확인). 역사 오라클 `tests/fixtures/presets-v0.json`을 `git show 294c46a:extension/defaults.js`에서 **생성**해(손으로 옮겨 적지 않았다) 14개 항목(distinct 8)을 고정하고, 파일 헤더의 `_note`에 "고쳐서 테스트를 통과시키면 안 되는 역사"임을 적었다.
- red 기록(3배치): ⒟+⒠ → `not ok 10·49·50`; ⒞ → `not ok 52·53·54`; ⒜+⒝ → `ReferenceError: saveConflict is not defined`. 각 배치 red 확인 후 구현.
- R2 테스트 2건(`the floor only ever rises`, `a save never writes below anything it has already seen`)은 **삭제**했다 — 틀린 설계를 고정하고 있었다. 삭제 자리에 왜 지웠는지 남겼다.
- 실측: `node --test` **81/0**(R2 72 → 신규 9, 삭제 2). `swift test`·`app/e2e.sh`는 회귀 확인.
- **잔여(설계상, R4 정정)**: 저장의 `get`↔`set` 사이 창은 `storage.sync`에 CAS가 없어 닫히지 않는다 — 그 틈에 다른 기기가 쓰면 LWW로 1회 덮인다. **그 덮인 것이 마이그레이션 결정이었다면 손실은 영구적이다**: 우리가 쓴 version이 우리 것이라 알림이 다시 뜨지 않아 같은 제안을 받을 기회가 없다. 이전에 적었던 "피해는 알림 한 번 더"는 틀렸다. 창을 최소화하고 **덮어쓰기 대신 거부**를 택했으며, 덮어쓰기 버튼은 만들지 않았다(트리거: 사용자가 실제로 요구하면 별도 이슈).
- **미검증**: DOM·클릭 경로(배지·체크박스·배너·실제 `storage.onChanged` 수신)는 여전히 자동 게이트가 없다.
- 판정: 미요청.

### R3 — `856bf03` (Codex 판정: 차단)

- 기존 7건 재현: **전부 통과**(부분 import / 중복·reorder / prototype key / 미래 version 강등은 `planSave.refused` / 순서 역전 / fractional / 픽스처 14개 전부 현재 프리셋 도달). 불변 원칙 ②③④ 통과, ①은 "조건부 통과 — get↔set 창을 동시 기기까지 포함한 절대 원칙으로 읽으면 실패".
- 신규 P1 ×2: (1) **초기 load 중 `default-main` 입력·`add-override` 클릭이 load를 영구 중단** — `updateLoadedGate`가 일부 컨트롤만 막아 revision이 올라가고, 첫 응답이 폐기된 뒤 재시도가 없어 `loaded=false`로 굳는다 (2) **체크 해제 뒤 원격 변경이 selection을 되돌린다** — 체크 후 새로 시작된 `loadSettings()`는 체크 이후 revision을 시작값으로 잡아 통과하고 `setPlan`이 기본 선택으로 재설정 → Apply가 **사용자가 거부한 항목을 적용**. 자기 저장 echo도 같은 경로(`loadedSnapshot`이 echo 판정에 쓰이지 않음).
- 신규 P2: `{"buttons":[null]}`·`{"buttons":{"length":1}}` 같은 저장값이 `adoptButton`/`.map`에서 TypeError → 옵션 페이지가 `loaded=false`로 멈춤(import 경로는 파서가 거르지만 storage 경로는 무방비). P3 ×2: `sameStoredValue`가 배열 length를 안 봐 sparse array를 동일 취급 / 소유하지 않은 키 변경에도 stale 배너.
- 판단: (a)(c)(d) 수용, 거부 정책 수용. (b) "어떤 설정에서도"라는 절대 문구 반박 — 동명 타저장소면 `{cd}`가 옛 command가 중단했을 작업을 다른 저장소에서 돌린다(#32의 수용 잔여가 전파됨). 잔여 창 설명 반박: "Keep mine 시나리오에서는 command가 사라지고 version도 1이라 알림이 재생성되지 않는다" — 수용, 서술을 정정한다.
- 부류 이동: 동시성 모델 자체(R3)는 서고, 남은 것은 **상태 보호의 경계**(로드 전·리뷰 중)와 **저장값 모양의 신뢰 경계**다.

### R4 — 워킹트리(미커밋, base `856bf03`) · 항목 10

- 범위: Codex R3 차단의 신규 5건을 두 부류로 묶어 근본 수정. 기존 7건은 재현에서 전부 통과했고 동시성 모델(R3)은 그대로 둔다.
- **⒜-1 로드 전에는 조작이 불가능하다.** 컨트롤 열거를 버리고 **`document.body.inert`** 하나로 바꿨다(소탕 표 5). `updateLoadedGate`가 한 줄이 됐고, 앞으로 추가되는 컨트롤도 등록 없이 덮인다. 그리고 **첫 로드는 revision으로 폐기하지 않는다** — 보호할 편집이 화면에 없으므로 `shouldApplyLoadedSnapshot({initial})`이 generation만 본다. 폐기는 "추월당했을 때"만 남는다.
- **⒜-2 진행 중인 리뷰는 미저장 편집이다.** `state.reviewTouched`(체크박스 변경·배지 클릭에서 true, 저장·적용된 로드에서 false)를 도입하고 `shouldAdoptSyncedChange(dirty || reviewTouched, changes)`로 원격 adoption을 막는다(배너는 그대로 뜬다). 자기 저장 echo는 `isOwnEcho(changes, loadedSnapshot)`로 걸러 — `loadedSnapshot`을 conflict 판정뿐 아니라 echo 판정에도 쓴다.
- **⒝ 저장값 모양은 import와 같은 신뢰 경계.** `adoptStoredSettings` 하나를 load와 import가 **공유**한다. 버린 항목은 `skipped`로 세어 상태 줄에 "N stored entries were unreadable and skipped"로 **보이게** 알린다 — 조용히 기본값으로 접으면 "버튼이 없다"는 거짓말이 되고 무엇이 그 값을 썼는지도 숨긴다. `defaultMain`·`repoMainBranch`의 모양도 같은 자리에서 검사한다(`Object.entries('abc')`가 0·1·2 오버라이드 행을 만들던 경로).
- P3 2건: `sameStoredValue`가 배열 `length`를 먼저 본다(`new Array(1)` vs `[]`), stale 배너는 `ownedChangedKeys`가 비지 않을 때만 — 같은 필터를 adopt·배너·echo 세 판정이 공유한다.
- 문구 정정 2건: `effect` 정의를 **base dir 계약 안으로** 좁혔다(동명 타저장소는 #32의 수용 잔여이고 여기로 전파된다 — "어떤 설정에서도"는 거짓), 잔여 창 서술에서 "알림 한 번 더"를 지우고 **"덮인 것이 마이그레이션 결정이면 version이 우리 것이라 알림이 돌아오지 않아 손실이 영구적"**으로 고쳤다. `migrations.js`·`options.js` 주석과 계획서 양쪽.
- red 기록: `not ok 58·59·60·62·63·64·65`(7건) — 첫 로드 initial / 소유 키 필터 / echo 판정 / 비정상 저장값 4형태 / 비버튼 키 모양 / sparse 배열. 확인 후 구현.
- 실측: `node --test` **93/0**(R3 81 → 신규 12: `migration.test.js` 8건 + `buttons.test.js` 4건). `swift test`·`app/e2e.sh`는 회귀 확인.
- **⒝는 세 reader 전부.** 처음에는 `background.js`·`content.js`를 잔여로 남겼지만, Codex가 방금 차단한 부류 그대로를 두 곳 남기는 것이므로 같은 라운드에서 닫았다. 검증기(`adoptStoredButtons`)는 **`defaults.js`**에 둔다 — 설정 모양은 마이그레이션이 아니라 설정의 관심사이고, content/background는 `migrations.js`를 로드하지 않는다(그 경계는 유지). 두 reader는 `readStoredButtons`로 검증 + `console.warn`("N stored buttons were unreadable and skipped — open the options page to repair") + 남은 것이 없을 때만 기본값. 옵션 페이지의 `adoptStoredSettings`도 같은 함수를 부른다. red는 `tests/buttons.test.js`(defaults.js만 로드) 4건 — `ReferenceError: adoptStoredButtons is not defined` 확인 후 구현. 실동작은 수기 검사 목록에 1항목 추가.
- **미검증**: DOM·클릭 경로(inert 게이트의 실제 동작, 배지·체크박스·배너, 실제 `storage.onChanged` 수신)는 여전히 자동 게이트가 없다.
- 판정: 미요청.

### R4 — `209bf9b` (Codex 판정: 차단)

- 기존 5건: **전부 차단 확인**(initial 적용·generation 폐기 / reviewTouched로 adoption 거부 / `[null]`·`{length:1}`·문자열·중첩 배열 → `skipped=1` 무예외 / sparse length conflict / 소유 키·echo). `git diff --check` 통과.
- 신규 P1: **`reviewTouched`가 비동기 경계에서 풀린다** — Save 대기 중 체크박스 변경(revision 2) → set 성공 → 성공 경로가 `reviewTouched=false`를 **먼저** 만든 뒤 revision 변경을 감지 → 다음 원격 변경에 adoption이 허용돼 선택이 기본값으로 돌아가고 Apply가 거부 항목을 적용할 수 있다. 또 **배지 클릭은 revision을 올리지 않아** 진행 중이던 `loadSettings()`가 도착하면 `reviewTouched`를 보지 않는 `shouldApplyLoadedSnapshot`이 응답을 적용해 리뷰를 지울 수 있다.
- 신규 P2 ×2: (1) **필드 모양 미검증** — `adoptStoredButtons`가 entry가 object인지만 보고 `command: 42`·`claudeInputs: "hello"`·비문자열 `face`를 통과시켜 `.trim()` TypeError 또는 claudeInputs가 조용히 `[]`로 바뀌어 다음 Save에 유실 (2) **`storage.sync.get` reject 시 영구 inert** — 첫 로드의 rejection 처리·재시도가 없어 `loaded=false`·`body.inert=true`로 영원히 남고 아무 메시지도 없다.
- 신규 P3: 프로그램적 이벤트(`dispatchEvent(new Event('input'))`, `add-override.click()`)가 inert를 우회해 해당 listener에 `requireLoaded()`가 없으므로 로드 후 false dirty — 손실은 없지만 "inert가 코드 규칙을 대체하지는 못한다".
- 잔여: "현재 문구에 동의한다 … CAS 없는 storage.sync로는 이 창을 제거할 수 없다. 다만 이 잔여를 제품 정책으로 수용하는 것과 불변 원칙을 완전히 만족하는 것은 별개다." `initial` 오판·`isOwnEcho` 오탐은 찾지 못함(오탐은 무해로 판정).
- 부류 이동: 남은 것은 **"사용자가 말했다"는 신호의 단일화**(revision·dirty·reviewTouched가 세 개의 반쪽 신호)와 **외부 입력 검증의 깊이**(컨테이너까지만, 필드는 아직 신뢰), 그리고 **로드 실패의 복구 경로**다.

### R5 — 워킹트리(미커밋, base `209bf9b`) · 항목 11

- 범위: Codex R4 차단의 신규 4건을 세 부류로 묶어 근본 수정. R4의 5건은 재검증에서 전부 차단 확인됐으므로 손대지 않았다.
- **⒜ 신호 단일화.** `revision`이 유일한 1차 신호이고, 모든 상호작용이 `touch({dirty, review})` 하나를 거친다(소탕 표 7). `dirty`·`reviewTouched`는 그 함수 안에서만 갱신된다. 비동기 경계는 전부 `nothingHappenedSince(revisionAtStart, revisionNow)` 하나로 판단한다 — 저장 성공 경로에서 **"저장소에 대한 사실"**(`loadedSnapshot`·`staleSinceLoad`)과 **"사용자에 대한 주장"**(`reviewTouched`·`dirty`·뷰 정리·재계획)을 갈라, 후자는 전부 그 술어 뒤로 옮겼다. Codex (1)이 정확히 이 순서 문제였다: `reviewTouched=false`가 revision 검사보다 앞에 있었다. 배지 클릭은 이제 `touch({review:true})`로 revision을 올리고, `shouldApplyLoadedSnapshot`은 `reviewTouched`도 함께 본다(Codex (2)의 양쪽 절반).
- **⒝ 필드까지 검증.** `readableButtonFields`를 `defaults.js`에 두고 `adoptStoredButtons`가 부른다(소탕 표 8). 필드가 어긋나면 **entry 전체**를 버린다 — 필드만 고쳐 살려 두는 방식이 `claudeInputs: "hello"` → `[]` 유실의 원인이었다. import는 이미 같은 검증기를 거치므로 규칙이 하나다.
- **⒞ 로드 실패 복구.** `storage.sync.get`을 try/catch로 감싸고, inert의 루트를 `body` → `#app`으로 내려 상태 줄·[Retry]를 밖에 뒀다. 실패 시 사유 + [Retry](새 load generation으로 재시도), 게이트는 그대로 닫힌 채다 — 열면 R3의 P1(빈 배열 저장)이 되살아난다.
- **⒟ 초크포인트.** `touch()`가 `shouldAcceptUserAction(state.loaded)`에서 막으므로, `dispatchEvent`·프로그램적 `.click()`이 inert를 우회해도 상태가 변하지 않는다. listener마다 가드를 붙이는 열거를 하지 않았다 — 다음에 추가되는 listener가 곧 잊히는 listener다.
- red 기록: ⒜⒞⒟ → `ReferenceError: nothingHappenedSince is not defined`; ⒝ → `not ok 25·26·28·29`(buttons.test.js). 각 확인 후 구현.
- 실측: `node --test` **102/0**(R4 93 → 신규 9: `migration.test.js` 4 + `buttons.test.js` 5). `swift test` 210/0, `app/build.sh` + `app/e2e.sh` PASS 9건. HTML 구조 확인: `#app` 여닫이 1쌍, `#retry-btn`·`#status`는 `</main>` **뒤**, 배지·[Save]는 안.
- 잔여: get↔set 창은 그대로(Codex가 서술에 동의). 수기 검사에 로드 실패·Retry 1항목 추가.
- **미검증**: DOM·클릭 경로(inert 실동작, 배지·체크박스·배너·Retry, 실제 `storage.onChanged` 수신)는 여전히 자동 게이트가 없다.
- 판정: 미요청.

### R5 — `0b60b52` (Codex 판정: 차단)

- R4 4건: 신호 정산 순서·배지 race **통과**, 필드 검증 **통과**, 로드 실패·Retry **통과**, **프로그램적 입력 미해결** — "`touch()`는 거부하지만 상태 변경이 먼저다. `pr-add.click()`은 버튼을 추가한 뒤에야 `touch()`를 호출한다. `add-override`, 카드 입력·삭제·복제·reorder, checkbox selection도 같은 패턴". P0 없음.
- 신규 P1 ×2: (1) **저장 중 원격 adoption이 `saveConflict`를 우회** — clean 상태에서 Save 시작, live `get` pending 중 다른 기기가 S1 저장 → onChanged → `loadSettings()`가 S1을 적용해 `state.loadedSnapshot`이 S1 → live get도 S1 → 대조가 S1 vs S1로 conflict 없음 → Save 시작 시 만든 S0 payload가 S1을 **덮는다**(adoption은 사용자 행위가 아니라 revision도 안 오름) (2) **미래 version이 옛 import로 내려간다** — 저장 version 2(미래) + import `{version:0}` → `mergedSourceVersion(2,0)=0` → 일반 Save 0, Keep mine 후 1.
- 신규 P2 ×3: (3) import의 `file.text()` await 뒤 revision 가드가 없어 그 사이 입력을 파일 값이 덮음 (4) 혼합 불량 import(`command:42` entry 하나)는 검증기가 버리지만 `parseImportedSettings`의 `skipped`에 안 잡혀 조용히 유실 (5) background의 `repoMainBranch` 값 검증이 공유되지 않음 — `{widget:42}`면 `main=42`를 앱에 보내고, 맵이 문자열 `"abc"`+repo `"0"`이면 `"a"`가 브랜치.
- 신규 P3: `claudeInputs: new Array(1)`이 `every`의 hole 건너뛰기로 통과. (참고: `saveConflict({buttons:undefined},{})`는 동일 취급 — storage.sync가 JSON이라 undefined는 항상 누락으로 정규화되므로 재현 경로 아님.)
- 잔여 창: "교차 기기의 get↔set 사이 LWW 창은 현재 서술대로 받아들인다 … post-write 재조회는 탐지만 가능하고 예방하지 못한다." Codex가 제시한 CAS 없이 닫을 수 있는 것: Save 시작 시 loadedSnapshot·load generation **불변 캡처** 후 set 직전 재검사 / Save 직렬화(mutex·disabled) / import 완료 직전 `nothingHappenedSince` / 모든 편집 handler에서 **변이 전** `touch()` 성공 확인 / 미래 storage version 보유 시 구버전 import 거부.
- 부류 이동: 동시성 모델·신호·검증은 섰고, 남은 것은 **비동기 작업의 캡처 시점**(Save·import가 시작 시점의 세계를 붙들지 않음)과 **변이-가드 순서**, 그리고 검증기 **공유 범위**(background의 overrides)다.

### R6 — 워킹트리(미커밋, base `0b60b52`) · 항목 12

- 범위: Codex R5 차단의 신규 6건(P1 ×2·P2 ×3·P3 ×1)과 미해결 1건(프로그램적 입력)을 부류 셋으로 묶어 근본 수정. R5의 4건 중 통과 3건은 손대지 않았다.
- 자리: `migrations.js:372-419`(`SAVE_RELOADED_MESSAGE`·`shouldStartSave`·`planSave`·`IMPORT_STALE_MESSAGE`·`planImport`)·`:133-160`(미래 version 메시지 2개 + `mergedSourceVersion` 전제)·`:463-503`(`adoptStoredSettings`의 `skippedByKey` + `describeSkipped`)·`:532`(`userAction`), `defaults.js:261`(`readableButtonFields`의 hole 규칙)·`:280-317`(`adoptStoredMainBranch`/`readStoredMainBranch`)·`:357`(`appendButton`), `options.js:122-148`(`updateSavingGate`·`unsavedWork`·`isOurOwnWrite`·`adoptDeferredChange`)·`:354-367`(`edit`/`review`/`editAndReview`)·`:526-620`(Save 캡처·직렬화·`finally`)·`:622`(`settleSave`)·`:952-975`(import 정산), `background.js:128`(`readStoredMainBranch`).
- **⒜ 비동기 작업은 시작 시점의 세계 위에서만 정산한다**(소탕 표 9).
  - **Save 캡처.** `savedRevision`·`generationAtStart`·`capturedSnapshot`을 시작 시 한 번 잡고, `planSave`가 `state`가 아니라 그 캡처본을 본다. Codex P1-1의 핵심은 **adoption이 사용자 행위가 아니라 revision을 올리지 않는다**는 것이었다 — 그래서 기존 신호는 전부 통과했고 `loadedSnapshot`만 S1로 갈아 끼워져 대조가 S1 vs S1이 됐다.
  - **두 번째 자물쇠.** 라이브 `get`은 원격 쓰기가 커밋되기 *전*의 값으로 답해질 수 있는 반면 change 이벤트는 커밋됐다고 말한다. 이벤트가 더 강한 사실이므로 `changedWhileInFlight`만으로도 거부한다. 세대가 바뀌었으면(`SAVE_RELOADED_MESSAGE`) 화면이 payload가 서술하는 폼이 아니므로 역시 거부 — 충돌이 없어도 거부다.
  - **Save 직렬화.** `shouldStartSave({loaded, saving})` + `save-btn.disabled`. **adoption은 Save 중 보류**한다: `unsavedWork()`에 `saving`을 넣어 채택을 막고, 사유가 Save뿐이면 `deferredChange`에 담아 `finally`에서 같은 질문을 다시 묻는다(버리지 않는다 — 편집이 없으면 그 변경은 결국 화면에 와야 한다). 자기 echo는 `pendingWrite`로도 판정한다: `set`이 resolve하기 전에 change 이벤트가 도착할 수 있다.
  - **import 정산.** `planImport`가 `nothingHappenedSince` + 세대 동일을 요구하고, 아니면 파일을 **적용하지 않고** 거부한다(`IMPORT_STALE_MESSAGE`). `file.text()` await 뒤에 아무 가드가 없어 그 사이 타이핑이 파일 값에 덮이던 경로.
  - **미래 version + 구버전 백업.** `mergedSourceVersion`이 전제(양쪽 ≤ `SETTINGS_VERSION`)를 **함수 안에서** 검사한다 — `Math.min`은 그 전제 안에서만 "합쳐진 편집 상태의 가장 낡은 세대"를 뜻한다. 저장 version 2 + 파일 0이 0이 되고 다음 Save가 그 0을 적어 다른 기기의 검토를 강등시키던 경로. 메시지 상수 2개(`BACKUP_FROM_FUTURE_MESSAGE`·`STORED_FROM_FUTURE_MESSAGE`)로 갈라 결정 5와 같은 부류의 해결책을 담았다. 부수로 `versionToSave`의 주석이 `mergedSourceVersion` 위에 잘못 붙어 있던 것을 제자리로 옮겼다.
- **⒝ 가드가 변이보다 먼저다 — 열거가 아니라 구조로**(소탕 표 7). `userAction(accept, change)`가 가드를 먼저 돌리고 **변경은 클로저**라 가드 앞에 앉을 자리가 없다. options.js는 `edit`/`review`/`editAndReview` 셋으로만 그것을 부르고, `markDirty`는 사라졌다(`grep -rn markDirty extension/` → 0건). R5 표의 13행을 실제 handler 단위로 풀어 **상태를 바꾸는 진입점 20개**로 재점검했다(+ 상태를 바꾸지 않는 [Save]·[Export]·[Import…]·[Retry] 1행). [+ Add Button]의 본문은 `appendButton`(defaults.js, 순수)으로 갈라 red가 닿는다 — "loaded=false에서 add를 부르면 `buttons`가 불변"을 `userAction`∘`shouldAcceptUserAction`∘`appendButton` 합성으로 고정했다. listener마다 가드를 붙이는 열거는 하지 않았다(R5와 같은 이유: 다음에 추가되는 listener가 곧 잊히는 listener다).
- **⒞ 검증기 공유 범위.** `adoptStoredMainBranch`(순수)/`readStoredMainBranch`(+`console.warn`)를 **`defaults.js`**에 두고 options의 `adoptStoredSettings`와 background의 `resolveMainBranch`가 공유한다 — R4가 버튼에 대해 한 것과 같은 구조이고, 같은 이유로 migrations.js가 아니다. R2의 `Object.hasOwn` 가드는 **키**만 봤고 **값**은 보지 않았다. `skippedByKey`를 도입해 entry 단위 유실을 import·load 메시지까지 전파하고(총합만으로는 "좋은 항목 1 + 불량 1"이 조용히 반쪽만 들어왔다), `readableButtonFields`가 sparse 배열을 불량으로 판정한다.
- red 기록: `not ok 30 - adoptStoredButtons: a hole in claudeInputs is not a string`(AssertionError) · `not ok 31 - appendButton: the new button takes the first preset face not already in use`(ReferenceError) · `not ok 32 - appendButton: leaves the original array alone and stops at the cap` · `migration.test.js` 전체 로드 실패 `# ReferenceError: planImport is not defined`(→ `not ok 3 - tests/migration.test.js`). 확인 후 구현.
- 기존 테스트 2건은 `planSave`의 인자 이름을 `loadedSnapshot` → `capturedSnapshot`으로 바꿨다(이번 라운드의 요지가 그 이름이다). 삭제한 테스트는 없다.
- 실측: `node --test` **118/0**(R5 102 → 신규 16: `migration.test.js` 13 + `buttons.test.js` 3), `swift test --package-path app` 210/0, `./app/build.sh` + `./app/e2e.sh` PASS 9건(확장만 고쳤으므로 불변이어야 하고 실제로 불변). `node --check` 확장 스크립트 5개, `git diff --check` 통과.
- **잔여**: get↔set 창 자체는 그대로다 — CAS가 없으니 **탐지**만 늘렸다(캡처본 대조 + change 이벤트 + 세대). 두 신호 중 어느 것도 도착하지 않는 창(원격 쓰기가 커밋됐는데 `get`도 옛 값을 주고 이벤트도 아직 안 온 순간)은 남고, 거기서는 R3부터의 서술 그대로 LWW로 1회 덮이며 그것이 마이그레이션 결정이었으면 손실은 영구적이다.
- **미검증**: DOM·클릭 경로(Save 직렬화의 실제 버튼 disabled, 보류된 adoption의 실제 수신, import 중 타이핑, 배지·체크박스·배너·Retry)는 여전히 자동 게이트가 없다 — 수기 검사 목록에 4항목을 더했다.
- 판정: 미요청.
