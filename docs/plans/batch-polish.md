# batch-polish (#78 · #79)

- 절차 정본: drive-agent-loop 스킬 — 컴팩션·세션 교체 뒤에는 스킬을 다시 로드하고 이 파일을 다시 읽는다
- 대상: `/Users/choongjaelee/Codes/terminal-checkout-batch-polish-work` (Chrome 확장 + macOS 앱)
- 시작 커밋: `eb70d54`
- 기준 트리: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/batch-polish-review` (`worktree-batch-polish-review`) · 작업 트리: `/Users/choongjaelee/Codes/terminal-checkout-batch-polish-work` (`batch-polish-work`)
- 현재: R0 초안 · 마지막 승격 없음 · 리뷰 중 없음 · 게이트 JS/locale 그린, Swift 미실행
- 최근 검증자 판정: 미요청 · 원문 —

이 파일은 실행할 계획의 기록이다 — 결정, 항목의 경계와 근거, 배치 점검, 열린 질문만 남긴다. 승인 전에는 구현·커밋하지 않는다.

## 배경 — 확인한 원천

- [GitHub 이슈 #78](https://github.com/dazebug/terminal-checkout/issues/78) — `pr-list`·`issue-list`가 허용하고 보내는 `{owner}`가 옵션 페이지의 두 목록 변수 도움말에서 빠졌다.
- [GitHub 이슈 #79](https://github.com/dazebug/terminal-checkout/issues/79) — 배치를 모르는 구버전 앱의 명시적 `{success:false,error}`가 `items` 부재 때문에 제네릭 오류로 바뀐다.
- [README.md](../../README.md) — `node --test`와 `node tools/check-locales.js`가 확장 게이트이며, `_locales`는 수동 편집되는 정본이고 번역 변경 뒤 바이트 핀을 검토한다.
- [CLAUDE.md](../../CLAUDE.md) — `BUTTON_KINDS`가 변수 계약의 단일 원천이고, 앱의 `{success:false}`는 정상 응답 데이터로 검사해야 하며, 로케일 변경은 의도된 번역 편집으로 검토한다.

## 목표

다섯 Chrome 로케일의 PR 목록·이슈 목록 옵션 도움말이 실제 목록 변수 계약과 같이 `{owner}`를 안내한다.

앱이 배치를 통째로 거절(per-item 결과 없음)한 `success:false`·문자열 `error`·`items` 부재 응답은 원래 오류와 앱 세대 불일치 가능성 힌트를 보존하고, 진짜 무형 응답은 기존 제네릭 오류를 유지한다.

현대 배치 응답, `BUTTON_KINDS`·`buildListBatchItems`의 owner 전달, 기존 콘솔 오류 경로와 버튼 표시 경로는 바뀌지 않는다.

변경 범위는 확장과 확장 테스트·로케일 핀으로 한정하며 `app/`은 수정하지 않는다.

## 완료의 정의

- 반드시 재현해 막아야 하는 실패: `extension/_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`의 `ext_section_prList_variables`·`ext_section_issueList_variables`를 읽으면 `{owner}`가 없고, `interpretListBatchResponse({success:true,batch:{success:false,error:"command_template is required"}})`와 `interpretListBatchResponse({success:true,batch:{success:false,error:"items must contain at most 25 item(s)"}})`가 각각 그 오류 대신 `native host returned no result`를 반환한다.
- acceptance oracle: 실패 후보 테스트를 먼저 추가해 red를 확인한 뒤 `node --test`가 exit 0이고 실행 테스트 수가 증가하며, `node tools/check-locales.js`가 exit 0으로 다섯 카탈로그의 이름·인자 구조를 통과시키고, 현대 응답과 무형 응답의 기존 판정도 함께 통과한다.
- 코퍼스 범위: `extension/_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`의 두 목록 도움말 키 10개, 상세 PR·이슈 도움말의 owner 표기, `tests/list-pages.test.js`의 전체-거절 응답·현대 응답·무형 응답 경계.
- 원자성·부분 실패·롤백 경계: 정적 로케일 편집과 순수 응답 해석만 다루므로 native request 재시도·명령 재실행·부분 롤백은 N/A이며, 기존 배치 전송과 앱의 실행 원자성은 건드리지 않는다.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

- 옵션 사용자: 목록 버튼 설정을 편집하며 옵션 도움말을 보고 실제 사용 가능한 `{owner}`를 알지 못할 수 있다.
- 앱이 배치를 통째로 거절하는 macOS 앱: 확장으로부터 `{command, items}`를 받고 `command_template is required` 또는 형태 거절 문구를 `items` 없이 반환한다.
- 확장·앱 세대 불일치 — 어느 쪽이 낡아도 이 분기에 닿는다(구버전 앱: `command_template is required`; 현행 앱: 형태 거절 문구).
- 번역 편집자: 다섯 `_locales` 카탈로그의 대응 문자열을 갱신할 수 있으며, 의도된 변경 뒤 baseline pin을 갱신해야 한다.

## 비목표 — 건드리지 않는다

- `app/`: 앱의 요청 형태 거절 응답은 이미 명시적 실패이므로 Swift 코드·앱 테스트·앱 로케일은 수정하지 않는다.
- `extension/content.js`의 새 표시 경로: 현재 오류는 `console.error`로만 기록되고 버튼 `title`은 명령 라벨을 유지·복원하므로, 버튼 title·badge·알림 UI를 새로 만들지 않는다.
- `extension/background.js`의 batch envelope·전송: `batchNativeOutcome`, `sendBatchToNativeHost`, `executeListBatch`와 listener의 외부 응답 shape는 유지한다.
- `extension/defaults.js`의 `BUTTON_KINDS`·`buildListBatchItems`: 두 목록 kind의 owner 허용·item variables 전달은 이미 정상이므로 수정하지 않는다.
- `README.md` 변수 표, settings migration/version, 새 언어 추가 및 셸에 도달하는 문자열은 범위에 넣지 않는다.
- #79의 별도 UI 표시를 위해 `extension/i18n.js` 또는 다섯 로케일에 새 오류 message를 추가하는 일은 현재 콘솔 전용 경로를 유지하는 한 하지 않는다.

## 불변 원칙

- 확장은 `BUTTON_KINDS`가 정의한 page variable과 `buildListBatchItems`가 만드는 item variables를 단일 계약으로 유지하며 `{owner}` 전달 로직을 재작성하지 않는다.
- `_locales`는 Chrome이 읽는 수동 편집 정본이다. #78은 상세 이슈 도움말의 기존 `{owner}` 표기와 같은 위치·형태로 두 목록 도움말에만 토큰을 추가하고, 다섯 파일을 모두 의도된 번역 편집으로 검토한 뒤 `tools/check-locales.js:28-35`의 바이트 핀을 갱신한다.
- 로케일 변경은 shell command/value 번역이 아니며 `tools/check-locales.js`는 읽기 전용이다. 구조·이름·argument binding gate와 live byte pin을 서로 다른 신호로 판정한다.
- 현대 batch response는 `success` boolean과 `items` 배열을 가진 현재 계약으로 그대로 해석하고, 전체-거절 분기는 `success:false`·비어 있지 않은 문자열 `error`·`items` 필드 부재의 명시적 shape에만 적용한다.
- 전체-거절 응답도 소비자가 이미 처리하는 outcome 모양(appSuccess null → throw → console)을 그대로 타며 새 표시 경로를 만들지 않는다.
- `success`가 boolean이 아니거나 `items`가 존재하지만 현재 배열 계약을 이루지 못하는 무형 응답은 `native host returned no result`로 fail-closed 한다. 정확한 전체-거절 predicate는 D4를 따른다.

## 배치 점검 (0라운드)

모드: ultrafast

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | ignored — 드라이버 실측(기준 트리). 메인 리포 `.git/info/exclude`가 담당하며 clone에는 `.claude/worktrees/`가 생기지 않으므로 clone 결과는 해당 없음 |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | 기준 트리는 HEAD(=origin/main) eb70d54에서 생성 — 첫 보고와 일치 |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-batch-polish-work` · `batch-polish-work` · `eb70d54` |
| 리포 오버레이 `.claude/drive-agent-loop.md` — 있으면 경로, 없으면 이번 초안과 함께 작성 | 있음 — `/Users/choongjaelee/Codes/terminal-checkout-batch-polish-work/.claude/drive-agent-loop.md` |
| cmux 패널 (점검 블록 `cmux:` 신호가 켜졌을 때만, 아니면 N/A) — `cmux markdown open <작업 트리 계획 파일 절대경로>` → pane id. 계획 파일 첫 승격 전에 채운다 | `pane:52` (surface:79) — 드라이버가 열었음 |
| 트리마다 의존성 동기화 (기준·작업) | 동일 HEAD·clean tree이고 dependency delta 없음; extension은 Node 의존성 없음, `app/Package.swift`는 로컬 SwiftPM target만 선언하며 Swift gate는 driver 소유 |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 없음 — 계획 입력으로 사용하는 외부 파일은 env가 아닌 명시된 이슈 사본·템플릿이며 overlay의 local asset env 선언도 `None` |
| 증분 리뷰 소요(분) — 첫 세 번 | N/A — 승격·증분 리뷰 없음 |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | PR 목록·이슈 목록 옵션 도움말에 `{owner}`를 추가하고 다섯 로케일의 의도된 번역 편집에 맞춰 baseline pin을 갱신한다. | 로케일 내용·바이트 핀 | — | `extension/_locales/{en,ja,ko,zh_CN,zh_TW}/messages.json`, `tools/check-locales.js`, `tests/i18n.test.js` | — | verified | red 후보: `tests/i18n.test.js`의 kind→도움말 키 매핑 `{pr: ext.section.pr.variables, 'pr-list': ext.section.prList.variables, issue: ext.section.issue.variables, 'issue-list': ext.section.issueList.variables, repo: ext.section.repo.variables}`으로 5 locale × 5 kind에서 `BUTTON_KINDS[kind].variables`와 `APP_VARIABLES`의 모든 `{name}` 부분 문자열을 단언. `node --test` → `ℹ tests 253`, `ℹ pass 252`, `ℹ fail 1`, `exit_code=1`; 원문 누락 10건: `en/pr-list help omits {owner}`, `en/issue-list help omits {owner}`, `ko/pr-list help omits {owner}`, `ko/issue-list help omits {owner}`, `ja/pr-list help omits {owner}`, `ja/issue-list help omits {owner}`, `zh-Hans/pr-list help omits {owner}`, `zh-Hans/issue-list help omits {owner}`, `zh-Hant/pr-list help omits {owner}`, `zh-Hant/issue-list help omits {owner}`. 10개 문자열 편집 뒤 `node --test` → `ℹ tests 253`, `ℹ pass 251`, `ℹ fail 2`, 다섯 `_locales/*/messages.json differs from the committed catalogue baseline pin` 및 편집 pin 테스트 실패, `exit_code=1`. 갱신 pin: `en=092fc4f057daa2e48a38f9f90844a5550688b282bcbf83ef6a6816ad82f3dd11`, `ja=88905b4bc396b0c9996fb59ac105a469653f34609b55706561fbdf7fcb30deab`, `ko=1148f7e0ce096f5b0e19fa639a1554a811a8b12733f88ba62dddf642ac6fff13`, `zh-Hans=f71114794d54388234cc59bdffd9f6a612354aaa10f6cd9140eb0d24b532c929`, `zh-Hant=6f2c0cee6f698f7fae5f0a14ff43bc0804977b271664ab77ea50606e19f886d8`. 갱신 뒤 `node --test` → `ℹ tests 253`, `ℹ pass 253`, `ℹ fail 0`, `exit_code=0`; `node tools/check-locales.js` → `all 5 live catalogues carry the same names and argument bindings as en`, `exit_code=0`. 토글: `git diff -- extension/_locales tools/check-locales.js > /private/tmp/tc-batch-polish-toggle.patch`·`git apply -R /private/tmp/tc-batch-polish-toggle.patch`·`git apply /private/tmp/tc-batch-polish-toggle.patch` 각각 exit 0; 역적용 중 `node --test` → `ℹ tests 253`, `ℹ pass 252`, `ℹ fail 1`, 동일 D6 누락 10건, `exit_code=1`; 복원 뒤 `git status --porcelain`은 `docs/plans/batch-polish.md`, 다섯 locale, `tests/i18n.test.js`, `tools/check-locales.js`만 출력하고 repo의 `toggle.patch` 없음. 재실행(드라이버): node --test → 253 pass / 0 fail exit 0 · check-locales exit 0 | — |
| 2 | 앱이 배치를 통째로 거절(per-item 결과 없음)한 응답의 원래 `error`와 앱 세대 불일치 가능성 힌트를 보존하고, 무형 응답만 기존 제네릭 오류로 남긴다. 전체-거절 predicate는 `batch.success === false && typeof batch.error === 'string' && batch.error !== '' && batch.items === undefined`이다. | 전체-거절 응답 호환·오류 해석 | (a) 전체-거절 응답의 error 유실 — 제네릭으로 덮임 (b) 무형 응답과의 경계 미정의 | `extension/defaults.js`, `tests/list-pages.test.js` | — | todo | red 후보: `interpretListBatchResponse({success:true,batch:{success:false,error:'command_template is required'}})`와 `interpretListBatchResponse({success:true,batch:{success:false,error:'items must contain at most 25 item(s)'}})`는 원문과 정본 힌트를 보존; nested `success` 비boolean 또는 `items` 비배열 shape는 제네릭 유지. 표시 경로 근거: `extension/content.js:574-582`의 catch는 `console.error`와 button text만 처리하고 `:532-537`에서 title을 라벨로 복원 | — |

## 결정 원장

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | — | 범위는 #78+#79를 한 브랜치(batch-polish)에서; 루프 종결 후 keep-the-why → gh-pr-drive automerge | 사용자 지시 2026-09-03 | — |
| D2 | 드라이버 | 두 결함이 앱 변경으로 번질 수 있다 | 확장 전용으로 다루고 `app/`은 수정하지 않는다 | 배정문 R0 · 앱 응답은 이미 명시적 실패 | 실제 앱 연동은 샌드박스 밖 |
| D3 | 드라이버 | 부류 혼합 시 승격 경계가 흐려진다 | 파일 집합이 겹치지 않는 #78 로케일 부류와 #79 응답 해석 부류를 별도 항목·별도 승격으로 | 항목 1·2 파일 집합 | — |
| D4 | 드라이버 | "구버전 앱 전용 분기"라는 전제 | 전체-거절 분기의 predicate는 `batch.success === false && typeof batch.error === 'string' && batch.error !== '' && batch.items === undefined`. `items` 키가 있으나 비배열이면 무형(제네릭), `success:true`인데 `items` 없음도 무형 | `app/Sources/Core/Request.swift:376` — parseBatchRequest 실패는 items 키 없이 `{success:false,error}`; 앱은 null items를 만들지 않는다 | — |
| D5 | 드라이버 | 힌트 문구가 "앱이 낡았다"고 단정하면 현행 앱의 형태 거절에서 거짓 진단이 된다 | 콘솔 영문 진단, i18n 키 없음. 문구 정본: `${batch.error} — the app rejected the whole batch without per-item results; an app older than this extension answers this way`. 반환 outcome은 transportSuccess true · appSuccess null · items [] 유지 | R0-5 · `extension/content.js:109-110,579` | 표시 경로 재분류는 비목표 |
| D6 | 드라이버 | 10개 문자열의 `{owner}` 포함 검사는 재발을 못 막는다 | 항목 1의 red 테스트는 (ii) 계약 테스트: BUTTON_KINDS의 kind마다 옵션 도움말이 그 kind의 variables 전부(+APP_VARIABLES)를 `{name}` 토큰으로 안내한다 — 5로케일 | R0-8 | — |

## 전수 소탕 표

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| `BUTTON_KINDS['pr-list'/'issue-list']` · `buildListBatchItems` | 안전·변경 없음 | `extension/defaults.js:192-208,509-521` — owner가 허용 목록과 item variables에 이미 있다 |
| `README.md` 목록 변수 표 | 안전·변경 없음 | `README.md:249-263` — 목록 page의 `{repo}`, `{owner}`, `{number}`를 이미 명시한다 |
| `ext_section_pr_variables` · `ext_section_issue_variables` | 안전·비교 기준 | `extension/_locales/*/messages.json:448-503` — 다섯 로케일의 상세 도움말은 `{owner}`를 이미 표기한다 |
| `ext_section_prList_variables` · `ext_section_issueList_variables` | 구멍(항목 1) | `extension/_locales/*/messages.json:465-517` — 목록 도움말만 owner 표기가 없다 |
| `_locales` directory/name/argument structure | 안전·핀만 갱신 | `tools/check-locales.js:24-35,64-74,113-143,195-209` — 구조 gate와 byte pin이 분리되어 있다 |
| options help 소비 경로·static args | 안전·변경 없음 | `extension/options.html:403-426`, `extension/options.js:50-70` — 기존 `data-i18n` key를 그대로 소비하며 새 인자는 없다 |
| `batchNativeOutcome` · `sendBatchToNativeHost` | 안전·변경 없음 | `extension/background.js:338-359` — boolean `success:false`를 정상 batch response로 넘긴다 |
| `executeListBatch` · background listener | 안전·변경 없음 | `extension/background.js:477-518,590-618` — native response를 outer `{success:true,batch}`로 전달하는 기존 envelope를 유지한다 |
| `interpretListBatchResponse` modern envelope | 안전·변경 없음 | `extension/defaults.js:580-597` — boolean app success와 array items를 가진 현대 응답의 item 결과 계약은 유지한다 |
| `interpretListBatchResponse` 전체-거절 envelope | 구멍(항목 2) | `extension/defaults.js:569-588` — 앱이 배치를 통째로 거절한 boolean `success:false`와 string `error`가 있어도 items 부재 branch가 제네릭으로 덮는다 |
| list command error consumer·button UI | 안전·새 표시 경로 없음 | `extension/content.js:101-111,574-582` — `appSuccess:null`이면 throw 후 `console.error`; `extension/content.js:532-537` — title은 config label이다 |
| extension i18n policy | 안전·조건부 질문 | `tests/i18n.test.js:1795-1799,1874-1894` — `console.*`는 English diagnostic으로 분류되며 새 dictionary key가 필요하지 않다; UI 재분류는 열린 질문이다 |
| Core request handling | 안전·변경 없음 | `app/Sources/Core/Request.swift:20-31,81-98,375-377` — 앱은 command 오류를 string error로 반환하는 경계이며 이번 항목에서 재설계하지 않는다 |

## 라운드 로그

### R0

#### 설계 리뷰 — 초안(미승격) · 승격 — · 리뷰 22:42 · 왕복 1 · 원문 `~/.claude/scratch/tc-batch-polish/r0-review.md`

- 반박: 심각도 1위 R0-5 전제 오류; R0-1 배치 점검 실측 주체·값, R0-2 원장 D1∼D6, R0-3 R1 자리표시자, R0-4 불변 원칙, R0-6 predicate·확정 결함, R0-7 질문, R0-8 계약 테스트를 정정한다.
- 처리: 8건 전부 반영 — 원장 D1∼D6
- 실측: `node --test` → `ℹ tests 252`, `ℹ suites 0`, `ℹ pass 252`, `ℹ fail 0`, `exit_code=0`; `node tools/check-locales.js` → `all 5 live catalogues carry the same names and argument bindings as en`, `exit_code=0`
- 판정: 반박 8건 전부 반영으로 처리 — 이 계획으로 시작하는 데 합의한다 (드라이버, R0)

### R1

#### 리뷰 1 — 증분 · (항목 1 커밋 해시는 커밋 뒤 채움 — 다음 커밋에서) · 승격 — · 리뷰 — · 왕복 — · 원문 —

- 차단: —
- 수정: 항목 1 (배정 22:3x · 완료 22:49)
- 실측: 재실행(드라이버): node --test → 253 pass / 0 fail exit 0 · check-locales exit 0
- 판정: 대기 — 승격 뒤 드라이버 증분 리뷰

## 열린 질문

- 없음 — R0의 D4와 D5로 닫혔다.
