# settings-migration

- 대상: `/Users/choongjaelee/Codes/terminal-checkout-settings-migration` (브랜치 `settings-migration`)
- 시작 커밋: `6fa5daf` (#32 머지 직후 main)
- 현재: R1 커밋(항목 1∼7 — 1·2·4·5·7 verified, 3·6 claimed: DOM 수기 검사 잔여) · 게이트 그린(드라이버 재실행 — node 56/0, swift 210/0, e2e 9 PASS) · Codex R1 검증 진행
- 최근 검증자 판정: 미요청

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
4. ~~커스텀 command에 기계적 수정 제안을 붙이지 않는다~~ → **개정(사용자, R1 중): 커스텀도 조건을 만족하면 후보로 승격한다.** 조건은 엄격한 접두 일치 하나 — `command === 'z {repo}'` 또는 `command.startsWith('z {repo} && ')`. 그러면 **맨 앞 절만** `{cd}`로 바꾼 rewrite를 actionable 후보로 올린다(나머지는 바이트 그대로). 판정은 verbatim과 같은 `unconditional`이라 기본 체크이고, 프리뷰가 출처를 구분 표시한다(`verbatim` / `prefix`). 그 밖의 모양(`cd x && z {repo}`, `z {repo};`, `z {repo}&&x`, 중간의 `z {repo}`, 공백이 다른 `z  {repo}`)은 informational + 안내 문구 유지. `claudeInputs`는 비목표 그대로 — **트리거**: 커스텀 claude 입력에 `!z {repo}`가 실제로 관찰되면 재검토.
5. ~~미래 version의 백업은 경고 + 채움~~ → **개정(사용자, R1 중): 현재보다 높은 `version`의 백업은 가져오기를 거부한다.** 편집 상태를 채우지 않고, 저장에도 닿지 않으며, 저장된 version은 그대로다. 거부 메시지는 해결책 둘을 제시한다(영어): "This backup was exported by a newer version of the extension. Update the extension (`git pull` + refresh at chrome://extensions), or use Reset to Defaults to start from the current presets." 미래 값에 대한 "저장 시 보존" 규칙은 **정상 로드 경로에만** 남는다(같은 계정의 최신 확장이 올려 둔 version을 낮은 확장이 강등하지 않는 것). 거부는 "일부 키 건너뜀"이 아니라 **가져오기 전체의 실패**다.
6. **레지스트리는 `extension/migrations.js`로 분리한다(질문 6).** defaults.js는 「현재의 진실」로 남고 역사 문자열은 옆방으로 — options.html만 로드하고 content/background는 모른다(표면 최소). 드리프트는 초안이 이미 의무화한 red("레지스트리가 0→CURRENT 전 구간을 덮는다")가 막는다. 이슈 제약 5(상수는 defaults.js)는 그대로.
7. **[Reset to Defaults]는 동의다(질문 7).** 내용이 CURRENT 세대가 되는 가장 명시적인 채택 행위 — 승격 지점 표에 4행째로 추가한다(신규 설치 / 마이그레이션 적용 / 검토 확인 / 리셋 — 전부 명시적 행위).
8. **동의는 항목별이다(질문 8 — 이슈 스펙 그대로).** verbatim 후보는 기본 체크된 체크박스, [적용]은 체크된 것만 편집 상태에 반영. 부분 적용 후 [Save]는 version을 CURRENT로 올리고(검토 완료) 체크 해제분은 다시 묻지 않는다 — 프리뷰가 그 사실을 말한다.

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

의존: 1 → 2 → 3 → {4, 5}; 6은 1 뒤 어디든; 7은 마지막.

수기 검사(자동 게이트가 없는 것 — 항목 3·6):

- [ ] v0 설정이 있는 프로필에서 옵션 페이지를 열면 표시가 뜨고, 프리뷰가 버튼별 "xx → yy"와 동작 서술을 보여 준다
- [ ] [적용] 후 저장하지 않고 새로고침하면 아무것도 바뀌지 않았고 표시가 그대로다
- [ ] [적용] → [Save] 후 표시가 사라지고, 같은 계정의 다른 Chrome에서도 동기화 뒤 사라진다
- [ ] 편집 중(dirty)에 다른 기계의 저장이 동기화돼도 입력이 날아가지 않는다
- [ ] 옛 백업 JSON을 가져오면 같은 프리뷰가 뜨고, 역시 [Save] 전에는 아무것도 저장되지 않는다
- [ ] 커스터마이즈된 command는 나열만 되고 값이 바뀌지 않는다

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
