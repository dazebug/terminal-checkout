# button-limit

- Procedure source: `drive-agent-loop` skill — reload the skill and this file after compaction or session replacement.
- Target: `terminal-checkout` — Chrome extension and macOS app (`extension/`, `app/`).
- Starting commit: `a5a9504c8716abd165837bfbe67d9e990a69c082`.
- Reference tree: `/Users/choongjaelee/Codes/terminal-checkout/.claude/worktrees/button-limit-review` (`worktree-button-limit-review`) · work tree: `/Users/choongjaelee/Codes/terminal-checkout-button-limit-work` (`button-limit-work`).
- Current: R0 · 마지막 승격 a5a9504(스냅샷) · 리뷰 중 없음 · 게이트 JS·로케일 그린, Swift 드라이버 실행 중
- Latest verifier decision: approved to begin from this plan · driver design review, 2026-10-02.

## 배경 — 확인한 원천

- [Snapshot commit `a5a9504`](https://github.com/dazebug/terminal-checkout/commit/a5a9504c8716abd165837bfbe67d9e990a69c082) — raises `MAX_BUTTONS` from three to five, adds the five-versus-six test, makes the migration test use the constant, and changes four README files. Confirmed with `git show a5a9504`.
- [PR #99](https://github.com/dazebug/terminal-checkout/pull/99) — related increase of the stored Claude-input cap from five to ten. The assignment supplies this synopsis; `gh pr view 99` could not reach GitHub from this sandbox, so the PR body was not independently read.

## 목표

- Each GitHub page kind can store and display up to five usable buttons; a sixth usable entry is counted as skipped.
- The options page, import path, service worker, content script, and extension-icon path agree on that cap.
- A five-button settings key is saved when it fits the existing per-key byte budget; one that does not is refused with the existing size error, never silently trimmed.
- Current copy, locale messages, and tests describe five buttons; the existing size-error wording stays unchanged per D3, while historical references and unrelated counts remain classified rather than mistaken for active caps.

## 완료의 정의

- Failure to prevent: five valid saved buttons are read as three, or the missing entries are dropped without a count and a warning.
- Acceptance oracle: `node --test` and `node tools/check-locales.js` pass; five valid buttons survive all shared readers, the sixth is counted, and the exact five-button test fails when `MAX_BUTTONS` is toggled to three in memory. The storage-size and legacy-client choices below are resolved. The driver runs `cd app && swift test`.
- Corpus scope: no direct live `storage.sync` query was made. Use synthetic arrays built from the 13 shipped presets and the five extension locale catalogues; the driver separately measured a current local key in Chrome Profile 1 LevelDB (D2).
- Atomicity, partial failure, rollback: no terminal command is run by a settings edit. Each page kind is one `storage.sync` key; an older client can overwrite that key with its retained first three entries on Save. D4 retains the options warning and calls for updating every device before saving a fourth button; Export is the existing recovery path.

## 상정 행위자 — 누가 이 실패를 일으킬 수 있는가

- User with a newer extension: saves five buttons to the account's synced key.
- User with an older extension capped at three: reads the same key, sees only the first three in the form, and can remove the other two by saving.
- Extension content script or service worker: reads the synced key and draws or executes the entries its shared reader accepts.
- Chrome `storage.sync`: distributes the same per-kind key to extensions on the user's devices.

## 비목표 — 건드리지 않는다

- `MAX_CLAUDE_INPUTS`, the click-time note slot, and app delivery lifetime: these are per-button input limits, not the number of buttons stored for a page kind.
- List row-selection and fan-out limits such as `MAX_BATCH_ITEMS`: they limit selected GitHub rows, not configured buttons.
- Preset commands, the settings schema, and `SETTINGS_VERSION`, unless the driver explicitly approves a scope change.
- Historical migration-plan text and unrelated numeric examples, including the three repository presets and test fixtures that use three only as a sample value.
- Browser or GUI execution in this sandbox. The requested live rendering check remains unverified here.
- Creating or attaching a GitHub issue; the user said there is none for this work.

## 불변 원칙

- Keep `MAX_BUTTONS` in `extension/defaults.js` as the only page-kind count. All editor controls read it, and all readers go through `adoptStoredButtons`; do not add a second cap or silently slice a list.
- Preserve order. The first five valid entries survive, later usable entries increment `skipped`, and import and synced-storage reads share the same verdict.
- Do not substitute presets for a key that contained unreadable entries in the options page. Before a Save can remove skipped entries, keep the visible skipped-entry warning and its export path (D4).
- `storedItemBytes` measures the key name plus UTF-8 JSON bytes. `MAX_STORED_ITEM_BYTES = 6144` remains an active refusal independent of `MAX_BUTTONS`; over-budget keys use the existing size error and are never silently trimmed (D2).
- Keep the extension's five locale catalogues aligned. Count text must receive `MAX_BUTTONS` as an argument rather than carrying a fixed numeral.
- The change adds no execution path or page kind. Do not change terminal execution or add a `docs/new-terminal-checklist.md` path for a button-count-only change.
- This review authorizes one commit containing only this plan file; do not edit implementation files, tests, or other documentation. Do not launch a browser in this sandbox.

## 배치 점검 (0라운드)

모드: ultrafast

| 점검 | 결과 |
|:--|:--|
| `git check-ignore -q .claude/worktrees/probe` → ignored (아니면 `.gitignore` 또는 `info/exclude`에 `.claude/worktrees/`) | ignored (드라이버 실측) |
| 설정 `worktree.baseRef: "head"` — 에이전트 첫 보고의 `git log --oneline -2`가 기준 HEAD를 보이는가 | N/A — ultrafast 전용 clone. 기준 트리는 a5a9504로 ff(드라이버) |
| 에이전트 첫 보고: 작업 트리 경로 · 브랜치 · HEAD | `/Users/choongjaelee/Codes/terminal-checkout-button-limit-work` · `button-limit-work` · `a5a9504c8716abd165837bfbe67d9e990a69c082`; `git log --oneline -2` begins `a5a9504`, `a6fd63b`. |
| 리포 오버레이 `.claude/drive-agent-loop.md` — 기준 트리의 경로(메인 것을 복사했으면 그렇게), 없으면 드라이버가 골격으로 작성. 커밋하지 않는다 — `오버레이 무시: ignored` 확인 | `.claude/drive-agent-loop.md` 는 리포에 커밋된 추적 파일(#65, #77) — 이 루프에서 수정하지 않는다 |
| cmux 패널 (점검 블록 `cmux:` 신호가 켜졌을 때만, 아니면 N/A) — `cmux markdown open <작업 트리 계획 파일 절대경로>` → pane id. 계획 파일 첫 승격 전에 채운다 | pane:536 (surface:637) |
| 트리마다 의존성 동기화 (기준·작업) | 해당 없음 — node --test 무의존, swift 게이트는 드라이버 |
| git 밖 로컬 자산을 가리키는 env (이름=절대경로) — 에이전트가 읽기 확인 | 해당 없음 |
| 증분 리뷰 소요(분) — 첫 세 번 | |

## 작업 항목

| # | 항목 | 부류 | 확정 결함 | 파일 집합 | 의존 | 상태 | 근거 | 승격 |
|:--|:--|:--|:--|:--|:--|:--|:--|:--|
| 1 | Validate the committed five-button snapshot, both requested gates, and the exact cap toggle. | Snapshot verification | — | Existing snapshot `a5a9504` (read-only; no implementation edits). | — | verified | `node --test` → exit 0, 324 tests, 324 pass, 0 fail. `node tools/check-locales.js` → exit 0, all five live catalogues match. `node .git/button-limit-audit.cjs toggle` → expected red, exit 1, one test fails at `tests/buttons.test.js:531` because only `b1`–`b3` remain when the cap is three. 재실행(드라이버): node --test → exit 0, 324 pass · node .git/button-limit-audit.cjs toggle → exit 1, 1 fail | — |
| 2 | Complete the non-visual cap/value-flow sweep and record the size, guidance, and older-client dispositions. | Stored-cap propagation and sync compatibility | — | `extension/defaults.js`; `extension/options.js`; `extension/background.js`; `extension/migrations.js`; `extension/options.html`; `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json`; `tests/buttons.test.js`; `tests/migration.test.js`; `tests/i18n.test.js`; `README*`; `CLAUDE.md`; `docs/**`; `app/Sources/**/*.swift`. | 1 | claimed | D2·D3·D4 처분, 수정 대상 없음 — 소탕 표 | — |
| 3 | Read the PR header, issue badge row, repository banner, and list mounts from code; leave actual five-button rendering for post-install verification. | GitHub DOM layout | — | `extension/content.js`; `extension/layout.js`; `tests/layout.test.js`. | 2 | claimed | 코드 판독 — 소탕 표의 네 행, 실제 렌더는 D5 잔여 | — |

## 결정 원장

| # | 유형 | 주장/위험 | 결정 | 근거 (명령·수치·경로 · SHA 또는 리뷰 번호) | 잔여 불확실성 |
|:--|:--|:--|:--|:--|:--|
| D1 | 사용자 | Per-kind button cap and issue scope | Each GitHub page kind may hold up to five buttons, not three; no issue is associated with this work. | User instruction, 2026-10-02. | None. |
| D2 | 드라이버 | 버튼 5개 × 가장 긴 배포 입력 10개 모델이 7,727B로 키당 예산 6,144B를 넘는다 | 예산 유지 — 개수 상한과 크기 상한은 별개다. 초과하면 저장이 안내와 함께 거부될 뿐 조용히 잘리지 않는다 | `node .git/button-limit-audit.cjs bytes` → 3/4/5개 4,643/6,185/7,727B; 사용자 실설정의 가장 큰 키 1,433B (`conflictButtons`, 드라이버가 Chrome Profile 1 LevelDB에서 읽음) | 긴 입력을 많이 둔 실제 설정이 예산에 닿으면 재검토 |
| D3 | 드라이버 | 크기 초과 안내가 입력 개수가 원인일 때도 "가장 긴 명령을 줄이라"고만 한다 | 기록만 — 이 루프에서 문구를 바꾸지 않는다 | 같은 문구를 PR #99 때 사용자가 "기록만"으로 처분했다 | 입력 때문에 초과하는 실제 사례가 나오면 문구 개정 |
| D4 | 드라이버 | 상한 3인 구버전이 5개 저장분을 읽으면 앞의 셋만 남기고, 거기서 저장하면 넷째·다섯째가 지워진다 | 코드 변경 없음 — 옵션 페이지가 건너뛴 개수, 저장 시 삭제, 먼저 내보내기를 이미 안내한다. PR 본문에 "넷째 버튼을 저장하기 전에 모든 기기의 확장을 업데이트하라"를 적는다 | `git show a5a9504^:extension/defaults.js` 의 `MAX_BUTTONS = 3`; `extension/options.js:636-670` | 페이지의 버튼 그리기 경로는 콘솔에만 남긴다 |
| D5 | 드라이버 | 이슈 배지 줄·저장소 배너·목록 마운트에는 지역 줄바꿈 규칙이 없어 버튼 5개가 좁은 창에서 붐빌 수 있다 | 이 루프에서 CSS를 바꾸지 않는다 — 실제 렌더 측정 없이 고치는 것은 추측 수정이다. 설치 후 실제 GitHub 페이지에서 확인한다 | 소탕 표의 PR 헤더·이슈 배지 줄·저장소 배너·목록 마운트 행 | 다섯 버튼의 실제 렌더 미확인 |

## 전수 소탕 표

| 대상 | 판정 | 코드로 알 수 없는 이유 또는 `파일:행` |
|:--|:--|:--|
| Snapshot | Safe; the commit is the current HEAD and its exact test toggles red at three. | `git show a5a9504`; `tests/buttons.test.js:528-531`. |
| Cap definition and editor guards | One value flows to adoption, append, add/duplicate guards, duplicate visibility, and limit help. | `extension/defaults.js:320-324,809-826,1276-1278`; `extension/options.js:50-63,285-386,1281,1551-1558`. |
| Storage, import, worker, and content readers | Safe by shared adoption: storage and import use `adoptStoredButtons`; the worker and content script use `readStoredButtons`. | `extension/migrations.js:677-708`; `extension/background.js:140-144`; `extension/content.js:92-100`; `extension/defaults.js:1243-1251`. |
| Older cap-three extension reading five saved entries | D4: it retains the first three and counts two skipped; the options page shows the skipped-key warning and says Save removes them and to export first. Keep that warning and put the all-devices update instruction in the PR body. The content reader only logs to the console. | Parent source: `git show a5a9504^:extension/defaults.js` (`MAX_BUTTONS = 3`); current warning path `extension/options.js:636-670`, `extension/migrations.js:711-720`, and `extension/defaults.js:1243-1251`. |
| Per-kind storage bytes | D2: keep the 6,144-byte per-key budget as a limit separate from the five-button cap. The synthetic five-by-ten model is 7,727 bytes; over-budget saves are refused by the existing size error and never silently trimmed. The largest real settings key measured by the driver was 1,433B (`conflictButtons`) in Chrome Profile 1 LevelDB. The model is not an absolute maximum because input strings have no length cap. | `extension/defaults.js:738-755`; `extension/migrations.js:480-483,555-562`; `.git/button-limit-audit.cjs` → 3/4/5 buttons: 4,643/6,185/7,727B; driver read from Chrome Profile 1 LevelDB. |
| Oversize guidance | D3: keep the current copy in this loop. The five locale messages say to shorten the longest command even when the input count can cause the oversize; the same wording received the user's record-only disposition during PR #99. Revisit if an actual input-driven over-budget case occurs. | `extension/_locales/en/messages.json:185`; same key at line 185 in `ko`, `ja`, `zh_CN`, and `zh_TW`; `extension/migrations.js:478-482`; PR #99 disposition supplied by driver. |
| PR header | Code reading closes the mount contract: `flex-shrink: 0` protects the buttons, `min-width: 0` lets the branch row shrink, and the button host can wrap. Actual five-button rendering remains a D5 install-time check. | `extension/content.js:570-601,1224-1232`; `extension/layout.js:22-24`; `tests/layout.test.js:26-50`. |
| Issue badge row | Code reading closes the mount contract: all accepted buttons append to a flex ancestor and do not shrink; no local wrapping rule is set. Actual five-button rendering remains a D5 install-time check. | `extension/content.js:1237-1278`. |
| Repository banner | Code reading closes the mount contract: the breadcrumb item is flex and receives every button; `REPO_BUTTON_STYLE` sets neither `flex-shrink` nor wrapping. Actual five-button rendering remains a D5 install-time check. | `extension/content.js:2-15,1172-1185,1287-1304`. |
| List mount | Code reading closes the mount contract: every accepted button goes to a flex or inline-flex host with an 8px gap and no wrapping rule. Actual five-button rendering remains a D5 install-time check. | `extension/content.js:435-451,528-562`. |
| Five extension locale catalogues | Safe by dynamic argument: `MAX_BUTTONS` supplies the number, and the locale checker passes. | `extension/options.js:50-63`; `extension/_locales/*/messages.json:19`; `node tools/check-locales.js` → all five catalogues match. |
| README and historical comments/plans | The four localized README files now say five. Keep old-cap and old-import-limit statements as history; the three repository faces are a preset count, not a cap. | `git show --stat a5a9504`; `extension/defaults.js:115,320-324,804-808`; `extension/options.js:1070-1075`; `tests/buttons.test.js:513-516`; `docs/plans/settings-migration.md:162`. |
| App Swift sources | No `MAX_BUTTONS` consumer found. `WarpHelper`'s `MAX_CLAUDE_INPUTS + 1` is the per-request input cap and does not grow with page-kind button count. | `app/Sources/WarpHelper/main.swift:51`; `rg -n 'MAX_BUTTONS' app` → no matches. |
| Other numeric threes | Safe/out of scope: examples and counts refer to locale interpolation, page families, or preset count rather than a per-kind maximum. | `tests/i18n.test.js:861-870`; `docs/new-terminal-checklist.md:73`; `extension/defaults.js:115`. |

## 라운드 로그

### R0

#### 설계 리뷰 — 드라이버 · 초안 미커밋 · 원문 없음(드라이버 직접 리뷰)

- 반박: 바이트 예산 초과 모델 / 크기 안내 문구 / 구버전 기기 / 화면 배치 미검사
- 처리: D2·D3·D4·D5, 코드 변경 없음
- 실측: 드라이버 재실행 node --test 324 pass, 토글 1 fail, 바이트 감사 3/4/5개 4,643/6,185/7,727B
- 판정: 드라이버 판정: 이 계획으로 시작하는 데 합의한다 — 스냅샷 검증과 결정 기록으로 닫는다

### R1

Not started; the R0 review approves beginning from this plan.

## 열린 질문

None; D2–D5 record the dispositions. Actual five-button rendering remains an install-time verification residual under D5.
