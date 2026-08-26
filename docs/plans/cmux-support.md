# cmux 터미널 지원

- 대상: `terminal-checkout` (작업 clone `/Users/choongjaelee/Codes/terminal-checkout-cmux-support-work`, 브랜치 `cmux-support-work` — spark 변형이라 linked worktree가 아닌 전용 clone)
- base: 2f922d6 (재개 2026-08-26 — 최초 R0는 a20f69d 기준, 「재개」 참조)
- 현재: R0 승인(2026-08-23, 열린 질문 5건 결정 완료 — 「열린 질문 → 결정」) · R1 착수. 게이트 기준선은 base 이동 후 드라이버가 재측정했다(`swift test` 483 tests(1 skip)·`node --test` 220 pass)
- 검증 구성: spark — 구현=Codex(write_codex), 검증=드라이버 겸임, 종결 cold review 필수. 게이트 4종(`cd app && swift test`·`node --test`·`app/build.sh`·`app/e2e.sh`)은 전부 드라이버가 clone에서 돌린다(Codex 샌드박스에서 swift 게이트가 돌지 않음 — 실측)
- 최근 검증자 판정: 미요청

조사 대상 cmux는 **설치본과 같은 커밋의 소스**다: `/Applications/cmux.app` = `cmux 0.64.22 (102) [ddd4a01bc]`, 소스 = `manaflow-ai/cmux` 태그 `v0.64.22` = `ddd4a01bc5d8ebac19643930f5fd7d40e85f1534`. 설치본의 `cmux.sdef`는 소스의 `Resources/cmux.sdef`와 바이트 동일함을 `diff`로 확인했고, `Info.plist`의 `CMUXCommit`이 `ddd4a01bc`다. 아래 `CLI/…`·`Sources/…`·`Packages/…` 인용은 모두 그 트리의 것이다.

## 재개 (2026-08-26, spark)

- 사용자 지시: spark 변형으로 재개, 종결 후 /keep-the-why와 /gh-pr-drive auto를 이어서 실행
- base 이동 a20f69d → 2f922d6 (경유: i18n 5로케일 #41·#53, 설정 창 크기·배치 수리 #54, 저장소 버튼 이모지 #55, claude 입력 행 재정렬 #57). **이 문서의 우리 리포 파일:행 인용은 a20f69d 기준이다** — `ClaudeInjector`·`TerminalRunner`·`SetupWindowController`·`Settings`가 그 사이 크게 바뀌었으므로(#36·#41·#54) 각 부류 착수 시 현재 트리로 재확인해 갱신한다. cmux 소스 인용은 설치본이 같은 버전이라 그대로 유효하다(2026-08-26 재확인: `cmux 0.64.22 (102) [ddd4a01bc]`)
- 환경 재확인(2026-08-26): 외부 `cmux ping` → PONG, `~/.config/cmux/cmux.json`에 `"automation": {"socketControlMode": "automation"}` 잔존 — R1-a·R1-m의 기존 실측이 유효하다
- 참고 수확(spawn-claude 스킬의 cmux 갈래, 실측 완료본): ① `cmux reload-config` 명령이 있으나 cmuxOnly 상태에서는 외부 호출 자체가 소켓 거부에 막히므로 D1-b 버튼의 반영 수단이 될 수 없다 — 파일 워처의 라이브 반영(R1-m 실측)이 정본, 기록만 남긴다 ② `new-workspace --id-format both`가 ref와 UUID를 함께 찍는다 — 우리는 rpc 경로(D2)를 유지하되 R1-b 응답 스키마 대조에 참고 ③ `--command`의 unescapeSendText 함정 재확인(D2와 일치)
- 구 워크트리 `/Users/choongjaelee/Codes/terminal-checkout-cmux-support`(브랜치 `cmux-support` @ a20f69d)는 이 루프의 쓰기 경로에서 제외 — 종결 시 그 브랜치를 최종 커밋으로 ff·push해 PR을 만든다

## 목표

1. `Terminal`에 `cmux` 케이스가 생기고, 앱 설정 창에서 고른 뒤 GitHub 버튼을 누르면 **사용자가 마지막으로 쓰던 cmux 창**에 workspace(=탭)가 생겨 명령이 돈다.
2. 그 workspace에서 claude가 뜨면 예약한 claude 입력이 기존 프로토콜 그대로 전달된다 — 게이트 ①포그라운드=claude ②tty raw mode ③같은 PID를 통과하고, [타이핑 → 화면 반영 확인 → CR 제출] 순서를 지키며, 바이트는 전부 `send(_:io:)` 한 문을 지난다.
3. cmux 제어 소켓에 외부에서 붙기 위한 전제(socket control mode = `automation`)가 앱 설정 창·README에 **명시적 상태**로 드러나고, 설정 창 버튼은 값을 복사해 기존 설정 파일 또는 폴더를 열어 주며 앱은 설정 파일을 쓰지 않는다(D1-b), 전제가 없을 때 실패가 조용히 성공으로 보이지 않는다.
4. iTerm2·WezTerm·Warp의 산출 경로가 그대로다(케이스 추가로 생긴 switch 확장 외에 기존 갈래의 동작 변경 없음).
5. `docs/new-terminal-checklist.md`의 §1 표를 빠짐없이 덮고, cmux 고유의 실측 항목이 §2에 추가된다.

## 비목표 — 건드리지 않는다

- **cmux의 UserDefaults·비밀번호 파일·설정 파일을 우리가 만지지 않는다.** 비밀번호는 번들 CLI가 스스로 찾으므로(D1) 우리 코드가 만질 이유가 없다. 설정 창 버튼은 `"automation": { "socketControlMode": "automation" }` 조각을 클립보드에 복사하고 기존 설정 파일 또는 폴더를 열어 줄 뿐이다(D1-b, 사용자 결정 2026-08-27). 상태 판정은 살아 있는 프로브(`cmux ping`)로 한다
- cmux의 **agent-session surface**(`new-surface --type agent-session --provider claude`)·browser·simulator·`ssh`/`mosh`/`vm` 계열: 우리 명령 모델은 "셸에 한 줄"이고 그 위에서 claude가 뜬다. cmux의 네이티브 agent 세션은 tty·게이트 3겹이 성립하지 않는다
- cmux **workspace group·layout·todo·sidebar·notification**: 새 탭 하나를 만드는 것이 우리 계약이다
- **확장(JS) 쪽 동작**: 확장은 터미널을 모르고 알 수단도 두지 않는다(CLAUDE.md). `extension/manifest.json`의 description 문구만 바뀐다
- 기존 3개 터미널의 실행·전달 경로: switch가 컴파일 에러로 드러내는 자리에 케이스를 더하는 것 외에 손대지 않는다
- cmux를 우리가 대신 설치하는 것. 앱은 socket control mode를 바꾸지 않으며, 설정 창은 값을 복사해 주고 설정 파일을 열어 줄 뿐이다 — 설치 스크립트·앱 기동 중 자동 변경은 하지 않는다
- cmux 버전 감시·경고 UI(열린 질문 5 결정): 검사 목록 항목으로만 둔다
- cmux의 **AppleScript 표면**(D6에서 기각). `app/Info.plist`의 `NSAppleEventsUsageDescription`도 그대로 둔다

전수 소탕 지시는 범위를 일부러 넓히므로 이 절이 경계다. 여기 없는 곳으로 번지면 항목을 새로 만들어 승인을 받는다.

## 불변 원칙

CLAUDE.md의 우회 금지 조항 중 이 작업에 걸리는 것 전부:

1. **TCC 분리**: 실행은 `open`(LaunchServices)으로 뜬 앱이 한다. relay에 실행 로직을 두지 않는다. cmux CLI 호출도 앱 프로세스에서만 한다
2. **게이트 3겹 우회 금지**: ①포그라운드 프로세스가 claude ②tty가 raw mode ③처음 준비된 claude와 같은 PID. cmux가 surface 단위로 정확히 보낸다는 이유로 하나도 빼지 않는다. 셋 다 tty 기반이므로 **cmux에서도 tty 경로를 반드시 얻어야 하고**, 못 얻으면 claude 입력을 포기한다(명령은 실행된다)
3. **바이트가 나가는 모든 자리는 `send(_:io:)` 단일 문을 지난다**: 표식·입력창 클리어·본문 타이핑·CR·전달 종료 정리. cmux 갈래는 `sendKeys`의 `case .cmux`만 새로 만들고 그 위쪽 흐름은 손대지 않는다
4. **[개행 없는 타이핑 → 화면 반영 확인 → CR 제출]** 순서. "텍스트+개행 한 번에 전송"으로 단순화 금지. cmux의 `--command`/`terminal.paste`처럼 개행을 붙여 주는 편의 기능이 있어도 claude 입력에는 쓰지 않는다
5. **`screenReflectsNewInput`은 타이핑 직전 화면과 비교**해 프로브가 한 번 더 보일 때만 통과. 스냅샷 실패는 확인 실패
6. **대체 신호로 반영 확인을 대신하지 않는다** — `FIONREAD`도, cmux `send` 응답의 성공 코드도, `queued:false`도 "claude가 그렸다"는 뜻이 아니다
7. **변수 값 검증은 문자 단위 화이트리스트** — 정규식으로 되돌리지 않는다
8. **터미널 선택은 앱이 단일 소스**. 저장값 정본은 `Terminal`의 rawValue이고, 그 계약은 `TerminalIdentifierTests`의 **리터럴**로만 지킨다(`allCases.count`도 함께 올린다)
9. **`{success:false, error}` 검사**: 새 실패 사유(cmux 소켓 거부 등)도 같은 경로로 나가야 하고, 조용히 성공으로 보이면 안 된다
10. **GUI 앱 PATH 함정**: cmux CLI도 절대 경로 후보를 명시적으로 탐색한다. 설치 감지와 실행이 **같은 함수**를 쓴다(`isWarpInstalled`↔`findWarpExecutable` 선례)
11. **사용자가 보던 창에 탭을 만든다** — 폴백까지가 한 세트다
12. **게이트 4종 그린 유지**: `cd app && swift test`(드라이버 기준선 483 tests, 1 skip → 늘어난 수), `node --test`(드라이버 기준선 220 pass), `app/build.sh`, `app/e2e.sh`
13. **iTerm2/WezTerm/Warp 산출 경로 바이트 불변**
14. **검사 목록 갱신 의무**: `docs/new-terminal-checklist.md` §2에 cmux 항목을 함께 추가한다
15. **남의 pane을 건드리지 않는다**: 우리가 만든 workspace/surface의 **UUID를 명시**해서만 보내고 읽는다. `--surface` 없이 부르면 cmux는 **포커스된 surface**로 떨어지므로(`Sources/TerminalController.swift:5491-5497`) 기본값에 기대지 않는다. 실측도 마찬가지 — 사용자의 라이브 claude 세션이 같은 cmux 안에서 돌고 있다
16. **i18n(#41 이후)**: 사용자 노출 문자열은 앱은 `Localization`(`.lproj` 5로케일), 확장은 `_locales`+`i18n.js`를 지난다 — cmux가 추가하는 설정 창 카드·버튼·에러 문구·manifest description도 같은 경로로 넣고 5로케일을 모두 채운다. 로케일 정합 게이트는 확장 `tools/check-locales.js`가 `tests/i18n.test.js`를 통해 `node --test`에 포함되고, 앱 source-audit가 `swift test`의 `LocalizationCatalogTests`에 포함된다(직접 `node tools/check-locales.js` 실행도 가능하다)

이 작업 고유의 규칙:

- **cmux 핸들은 UUID로만 들고 다닌다.** `workspace:2`·`surface:3` 같은 ref는 위치 기반이라 다른 workspace가 닫히면 다른 것을 가리킨다. `new-workspace`가 stdout에 찍는 `OK <workspace_ref>`(`CLI/cmux.swift:7851`)를 쓰지 않는 이유가 이것이다
- **텍스트 전송은 `cmux rpc surface.send_text`(JSON)로만 한다** — `cmux send`의 인자 언이스케이프 구멍(D2) 때문
- cmux 소켓 접근 실패는 **claude 입력 실패와 구분해서** 로그·UI에 남긴다(Warp의 "명령은 됨/입력만 안 됨" 구분과 같은 취급)

## 설계 결정

각 결정은 [채택] / [기각한 대안 + 근거]로 남긴다. 근거 없는 "확인했다"는 쓰지 않는다.

### 결정 원장

| 주체 | 날짜 | 결정 |
|:--|:--|:--|
| 사용자 | 2026-08-27 | [자동화 허용] 버튼의 역할을 축소한다(파일 열기·클립보드까지, 쓰기 없음). 근거: 이 기능이 cold review 1∼7차 지적의 약 절반(18건)을 냈고 실패 모드가 전부 사용자 파일 손상·권한 누출·거짓 안심이었다. 대체 수단 `cmux settings automation`은 automation이 꺼진 상태에서 소켓 거부로 막힌다(드라이버 실측). 삭제 규모: CmuxAutomation 417 + 그 테스트 677 + Core/CmuxConfig 387 + 관련 테스트. |

### D1. 외부 프로세스의 소켓 접근 — 사용자가 cmux의 socket control mode를 바꾸는 것이 전제

**소스 근거**

- 외부 셸에서 `cmux ping` → `ERROR: Access denied - only processes started inside cmux can connect`(드라이버 실측). 문구 출처 `Sources/TerminalController+SocketConfiguration.swift:113-118`, 쓰이는 자리 `Sources/TerminalController.swift:1544-1554`
- **"processes started inside cmux"의 정체는 peer pid 조상 추적이다.** 연결은 항상 accept하고(accept 시점에 `LOCAL_PEERPID`로 pid만 붙잡아 둔다 — `Server/SocketControlServer+AcceptSource.swift:111-112`), **첫 명령 줄에서** 판정한다. 판정 본체는 `Transport/SocketClientAuthorization.swift:79-95`:
  ```swift
  case .off:        return nil
  case .cmuxOnly:   return authorizedCommand(command, peerProcessID:…, peerHasSameUID:…, capabilityAuthority:…, isDescendant:…)
  case .automation, .password:
      guard peerHasSameUID else { return nil }
      return SocketClientCapabilityCommand(command)?.command ?? command
  case .allowAll:   return SocketClientCapabilityCommand(command)?.command ?? command
  ```
  `isDescendant`는 `sysctl`로 부모를 최대 128단계 거슬러 올라가 앱의 `getpid()`와 맞추는 것이다(`Transport/SocketTransport+Peer.swift:19-27,56-84`, 앵커 `Sources/TerminalController.swift:182`). **LaunchServices로 뜬 우리 앱은 어떤 경우에도 cmux의 자손이 아니다.**
- 모드는 `automation.socketControlMode`, **기본값 `cmuxOnly`**(`Packages/macOS/CmuxSettings/…/SocketControl/SocketControlSettings.swift:82-84`, 카탈로그 `Keys/AutomationCatalogSection.swift:5-9`, cmux.json 파싱 `Sources/KeyboardShortcutSettingsFileStore.swift:823-832`)
- 설정 창 문구(`Sources/SocketControlMode+Display.swift:32-45`):
  - `cmuxOnly` — "Only processes started inside cmux terminals can send commands."
  - `automation` — **"Allow external local automation clients from this macOS user (no ancestry check)."**
  - `password` — "Require socket authentication with a password stored in a local file."
  - `allowAll` — "Allow any local process and user to connect with no auth. Unsafe."
- 사용자의 현재 `~/.config/cmux/cmux.json`은 `$schema`·`schemaVersion` 외 전부 주석 상태다(`socketPassword`·`socketControlMode`가 187∼188행에 주석으로만 존재) → **지금은 기본값 `cmuxOnly`** (R0 시점. 재개 시점에는 R1-a의 automation 기록이 적용돼 있다 — 「재개」)

**[채택]** 요구 조건은 **`automation` 모드**(`password`·`allowAll`도 통과하므로 막지 않는다). `automation`의 경계는 "이 macOS 사용자"(uid)이고, 이는 이 앱이 자기 소켓에 이미 쓰는 경계와 같다(`HostServer.swift:82` `getpeereid(fd,&uid,&gid)==0, uid==getuid()`). 새 신뢰 경계를 만들지 않는다.

**[교체 — D1-b, 사용자 결정 2026-08-27]** [자동화 허용] 버튼은 사용자 설정 파일을 읽거나 쓰지 않는다. `"automation": { "socketControlMode": "automation" }` 조각을 클립보드에 복사하고 기존 `~/.config/cmux/cmux.json`을 열거나, 파일이 없으면 이미 있는 설정 폴더를 열어 사용자가 직접 수정하게 한다. 파일·폴더가 없으면 안내만 남긴다. cmux 자체 설정 → Automation도 대안으로 안내하며, cmux는 파일 변경을 즉시 반영하므로 재시작이 필요 없다(R1-m). 이전의 JSONC 편집·백업·원자적 교체·권한 축소·라이브 적용 확인은 이 범위 축소로 dropped했다.

README·설정 창 문구에 automation 모드의 의미(**같은 uid의 아무 프로세스나 cmux를 조종할 수 있게 됨**)를 명시한다 — 사용자 승인됨.

**[사용자 실측 2026-08-23 — D1 보강]** cmuxOnly의 계보 판정 실측 확정: cmux pane 안에서 `CMUX_SOCKET_CAPABILITY`를 지우고 `env -i`로 돌려도 PONG(주입 토큰이 아니라 부모 사슬 판정), launchd로 띄운 외부 프로세스는 "Access denied - only processes started inside cmux can connect". automation으로 바꾸면 계보 조건만 사라지고 same-uid 조건은 남는다. 소켓 경로는 클라이언트가 자동 발견한다(빈 env에서도 붙음 — `/tmp/cmux-last-socket-path` 폴백, `CMUX_SOCKET_PATH`로 명시 가능) → `cmuxSocketPath()`(항목 2)는 경로 계산용이 아니라 "cmux 살아 있음" 판정(소켓 파일 존재 확인)용으로 축소 검토.

**`password` 모드는 추가 작업 없이 함께 동작한다.** 번들 CLI가 비밀번호를 스스로 찾는다: `--password` → `CMUX_SOCKET_PASSWORD` → `~/.local/state/cmux/socket-control-password`(0600, 0700 디렉토리) → 레거시 키체인 순(`CLI/cmux.swift:1652-1667`, 저장소 `Packages/macOS/CmuxSettings/…/SocketControl/SocketControlPasswordStore.swift:21,82-98,190-247`). 우리 앱의 자식으로 도는 CLI가 같은 uid로 그 파일을 읽으므로 **비밀번호가 우리 코드를 지나가지 않는다** — 이 설계의 이점이다. 비밀번호는 자동 생성되지 않으므로 `password` 모드는 사용자가 값을 설정해야 한다(`AutomationSection.swift:178` "No password set. External clients will be blocked until one is configured.").

**[기각] capability 토큰 수확** — cmux가 pane 프로세스에 넣는 `CMUX_SOCKET_CAPABILITY=v1.<b64>.<b64>`를 **남의 pane** 환경에서 긁어 쓰는 방식. 기술적으로는 동작한다: 토큰은 `HMAC-SHA256(signingKey, "cmux.socket-capability.token.v1\0"+nonce)`이고 검증은 MAC 확인 + same-uid뿐이다 — pid·surface·시각에 묶이지 않고 **만료도 없다**(`Transport/SocketClientCapabilityAuthority.swift:6-8` "An authority is immutable and contains no session registry. Tokens issued from the same secret and audience remain valid across listener and app restarts.", 발행 `:51-58`, 검증 `:64-79`). 그것이 **기각을 더 강하게 만든다**: 우리가 저장해야 할 것이 만료 없는 bearer 자격증명이 된다. 더해서 ①남의 프로세스 환경을 캐는 것은 우리 신뢰 경계 선언("우리 것을 숨기지 않는다"와 "남의 것을 캔다"는 다르다)과 어긋나고, ②외부 발급 API가 아예 없어 지원되는 경로가 아니며, ③`cmuxOnly`에서만 쓰이는 내부 구현이라 버전 간 계약이 아니다.

**[기각] `allowAll` 안내** — "Allow any local process and **user** to connect with no auth. Unsafe."(위 인용). 소켓 파일이 0666이 된다(`SocketControlMode+SocketControl.swift:7-14`). 권하지 않는다.

**전제가 없을 때의 동작(불변)**: 명령 실행이 실패하므로 `Request.handleRequest`가 `{success:false, error}`로 돌려주고 버튼이 실패로 보인다.

**상태 프로브의 안전성**: 설정 창이 상태를 보려고 반복해 붙어도 잠기지 않는다. `SocketClientPreauthorizationLimiter`는 **동시 32개 상한일 뿐 레이트 리밋이 아니고**(`Server/SocketClientPreauthorizationLimiter.swift:16-26`, 예산 `Sources/TerminalController.swift:372-374`), 그나마 `cmuxOnly`에서 비자손 피어에만 걸린다(`Sources/TerminalController+SocketClientCapability.swift:36-44`). 백오프·락아웃·피어별 계정이 없다.

### D2. cmux와의 통신 형태 — `cmux rpc <method> <json>`

**소스 근거**

- `cmux send`는 인자들을 공백으로 이어 붙인 뒤 `unescapeSendText`를 태운다(`CLI/cmux.swift:5237-5239`). 그 함수는 `CLI/cmux.swift:17675-17680`:
  ```swift
  private func unescapeSendText(_ text: String) -> String {
      return text
          .replacingOccurrences(of: "\\n", with: "\r")
          .replacingOccurrences(of: "\\r", with: "\r")
          .replacingOccurrences(of: "\\t", with: "\t")
  }
  ```
  `\\`를 다루지 않으므로 **리터럴 두 글자 `\`+`n`을 그대로 보낼 방법이 없다** — 그 입력은 CR로 바뀌어 조기 제출이 된다. 명령 템플릿과 claude 입력은 사용자가 쓰는 문자열이므로 실제 위험이다. `new-workspace --command`도 같은 함수를 지난다(`CLI/cmux.swift:7852` `let text = unescapeSendText(commandText + "\\n")`).
- `cmux rpc <method> [json-params]`는 JSON을 그대로 파라미터로 넘기고 응답 JSON을 출력한다(`CLI/cmux.swift:4478-4486`). 변환이 없다.
- 우리가 쓸 메서드는 CLI가 실제로 부르는 것들이다:

| 용도 | 메서드 | 파라미터 | 근거 |
|:--|:--|:--|:--|
| workspace 생성 | `workspace.create` | `window_id?`·`cwd?`·`title?`·`focus` | `CLI/cmux.swift:7824-7846` |
| 텍스트 전송 | `surface.send_text` | `text`·`surface_id` | `CLI/cmux.swift:5240-5248`, `Coordinator/Surface/ControlCommandCoordinator+Surface2.swift:210-242` |
| 화면 읽기 | `surface.read_text` | `surface_id`·`scrollback?`·`lines?` | `CLI/cmux.swift:5203-5227` |
| tty 조회 | `debug.terminals` | (없음) | `CLI/cmux.swift:5039` |
| 창 조회(쓰면) | CLI `current-window` (v1 `current_window`) | — | `CLI/cmux.swift:4557-4563` |

**[채택]** 전송·조회를 `cmux rpc`로 한다. 텍스트·CR(`\r`)이 JSON 문자열 이스케이프 하나로 정확히 표현된다.

**[기각] `cmux send` + 사전 이스케이프** — `\\`가 없어 표현 불가(위 인용).

**[중요 — 서버 쪽에도 변환이 있다]** `rpc`로 우회해도 **서버의 입력 문법**은 지난다. `parsedSocketInputEvents`(`Packages/macOS/CmuxTerminal/…/Surface/TerminalSurface+Input.swift:235-330`)는 스칼라 단위로 가른다:

- `0x0D` CR → 원시 바이트 `0x0D` ✅ (우리 제출 키가 그대로 나간다, `:261-263`)
- **`0x0A` LF → 역시 `0x0D`로 바뀐다**(`:279-285`) — 텍스트 안에 개행이 들어가면 **조기 제출**이 된다. `rpc`로도 피할 수 없다. 우리 입력은 원래 한 줄이지만(README "입력은 한 줄씩만 가능합니다"), cmux 갈래에서는 이것이 **조용한 제출**이 되므로 CLAUDE.md에 함정으로 남긴다
- `0x09` TAB·`0x08`/`0x7F` → **키 이벤트로 전환**(바이트가 아니다)
- `0x1B` ESC → 화살표·CSI는 키 이벤트로 재발행되고, 완결된 OSC/DCS는 **pty가 아니라 터미널 파서로** 간다(`:524-530`)
- 그 밖(0x15 Ctrl+U 포함)은 원시 텍스트로 버퍼링되어 `ghostty_surface_text_input`으로 나간다(`:322-326`)

**bracketed paste는 붙지 않는다.** `surface.send_text`는 `ghostty_surface_text_input`(타이핑 경로)이고, bracketed paste는 별개 진입점 `ghostty_surface_text`(=`TerminalSurface.sendText`, AppleScript `input text`와 `terminal.paste`가 쓰는 것)다 — 갈림이 소스 주석에 명시돼 있다(`Sources/TerminalController.swift:14859-14870`). **개행도 붙지 않는다**(cmux 자신의 Feed 경로가 CR을 손으로 덧붙인다 — `Sources/AppDelegate.swift:9742-9747`).

**[채택] 제출(CR)은 `surface.send_text`의 `"\r"`, 입력창 클리어(Ctrl+U)는 `surface.send_key`의 `"ctrl+u"`.** 서로 다른 메서드를 쓰는 이유가 각각 있다:
- CR을 `send_key enter`로 보내지 않는 것은, 키 경로가 libghostty의 키 인코더를 지나 **Kitty keyboard protocol이 켜져 있으면 CSI-u 시퀀스가 될 수 있기** 때문이다(claude TUI가 켤 수 있다). `send_text`의 CR은 모드와 무관한 원시 바이트 쓰기다
- Ctrl+U를 `send_text`의 `\u{15}`로 보내지 않는 것은, 원시 텍스트 경로가 제어문자를 거르는지 이 트리만으로 확정할 수 없고(ghostty 서브모듈 미체크아웃), **cmux 자신이 agent 입력창을 비울 때 `["ctrl+a","ctrl+k","ctrl+u"]` 키 경로를 쓰기** 때문이다(`Sources/TerminalController+AgentPromptDelivery.swift:6-14`). 키 이름 파싱은 `+`/`-` 모두 받고 `ctrl+u`가 일반 폴백으로 해석된다(`TerminalSurface+Input.swift:694-738`)
- 둘 다 `send(_:io:)` 한 문 안에서 갈린다 — iTerm2 갈래가 이미 같은 모양이다(`ClaudeInjector.swift:537-552`)
- **[미확정 — R1-i]** 두 선택은 각각 실측으로 확인한다: `cat -v`로 CR이 `^M` 하나로 들어오는지, Ctrl+U가 claude 입력창을 실제로 비우는지

**[교체 — D8, 2026-08-26]** 위 채택안의 Ctrl+U 갈래는 실기기에서 틀렸다(R1-i 정정). 클리어도 `surface.send_text`로 보내고, `0x15`와 `0x7F`를 바이트마다 별도 호출한다.

**[남는 위험]** `rpc`는 "raw v2 method" 탈출구다. 메서드 이름·파라미터가 버전 사이에 바뀔 수 있다(cmux는 0.64.x로 빠르게 움직인다). 완화: 메서드 이름을 한 자리 상수로 모으고, 실패 로그에 메서드 이름을 남기고, 검사 목록에 "cmux 버전이 오르면 rpc 메서드 4개 확인" 항목을 넣는다.

**[확인할 응답 필드]** `surface.send_text` 응답의 `queued: Bool`은 "surface가 아직 차가워서 바이트가 pty에 안 들어갔다"는 뜻이다(`ControlCommandCoordinator+Surface2.swift:345-354`). 반영 확인이 어차피 막아 주지만 **로그에는 남긴다** — 진단이 갈린다. R1-k 실측: queued:true였던 텍스트는 surface 웜업 시 flush되어 pty에 들어간다 — 유실로 취급하지 말고, 반영 확인 없이 CR을 보내지 않는 기존 원칙이 이 경우를 막는다.

CLI는 JSON을 stdin으로 받는 수단 없이 `cmux rpc <method> [json-params]` 인자로 받으므로, `JSONSerialization` 뒤 비ASCII 스칼라를 `\uXXXX`(보충 평면은 surrogate pair)로 이스케이프해 JSON argv 전체를 ASCII로 만든다 — JSON 의미와 원본 문자열 바이트를 보존한다.

### D3. 새 탭(workspace) 만들기와 창 선택

**소스 근거**

- `workspace.create` 파라미터와 `--focus` **기본값 false**(`applyFocusOption(focusOpt, defaultValue: false, …)`, `CLI/cmux.swift:7845`)
- 선택자 우선순위(`Coordinator/ControlRoutingSelectors.swift:12-15`):
  > "an explicit `window_id` param wins outright (and a **present-but-unresolvable `window_id` resolves to no target**); then group, then workspace, then surface, then pane; finally the caller's own window, **then the active scriptable window**."
- 실제 폴백 코드는 `Sources/TerminalController.swift:3750`:
  ```swift
  return tabManager ?? AppDelegate.shared?.currentScriptableMainWindow()?.tabManager
  ```
  `tabManager`는 `NSWindow.didBecomeKeyNotification`으로 갱신되는 **마지막 활성 창 래치**다(`Sources/TerminalController.swift:126`, 기록 `:788-794`) — 타임스탬프가 아니라 래치라서 cmux가 백그라운드여도 값이 남는다
- 외부 호출자는 `CMUX_WORKSPACE_ID`/`CMUX_SURFACE_ID`가 없어 아무 선택자도 붙지 않는다(`CLI/cmux.swift:17693-17708`)

**[채택]** `window_id`를 **넘기지 않는다**. 서버 기본값이 이미 "마지막으로 활성이던 창"이라 WezTerm이 겪은 "mux의 첫 창(가장 오래된 창)으로 간다"가 성립하지 않는다. `focus`는 `true`로 명시한다(기본 false면 사용자가 탭이 생긴 것을 못 본다 — 다른 세 터미널과 갈린다).

**[알려진 흠]** 그 래치는 소켓 명령들도 다시 가리킨다(예: `window.create` 경로 `Sources/TerminalControllerControlCommandContext.swift:75`). 즉 다른 자동화가 먼저 돌면 `window.current`가 사용자가 본 적 없는 창을 가리킬 수 있다. 우리는 `workspace.create`만 쓰므로 우리 자신이 래치를 옮기지는 않는다. → **R1-g로 실측**.

**[조건부 폴백]** R1-g가 어긋나면 WezTerm과 **대칭으로** 시도 목록을 만든다: `cmuxWorkspaceCreateAttempts(windowID:)` = `[window_id 지정, 미지정]` — `wezTermSpawnAttempts(windowID:)`(`TerminalRunner.swift:254-258`)와 같은 모양이고 같은 이유다(지정한 창이 그 사이 닫히면 위 인용대로 **"no target"으로 실패**하므로 거기서 포기하면 안 된다). 순수 함수로 떼어 `CoreTests`에 고정한다(`WezTermWindowTests` 선례).

**[cmux가 꺼져 있을 때]** 소켓(`~/.local/state/cmux/cmux.sock`)이 없다 → **인자 없이** `open -b com.cmuxterm.app`으로 띄우고(LaunchServices이므로 cmux가 스스로 responsible process가 된다) 소켓이 생길 때까지 유한 시간 폴링한 뒤 재시도한다. 끝내 실패하면 `TerminalError`로 던진다. **인자가 붙으면 안 된다**: `SessionPersistence.shouldAttemptRestore`(`Sources/SessionPersistence.swift:158-176`)가 `-psn_…` 외의 모든 launch argument를 "명시적 열기 의도"로 보고 **세션 복원을 끈다**.

**[기각] 파일 열기 경로(`cmux <path>` = `open -a cmux <path>`)로 부트스트랩** — 소켓 없이 workspace를 만들 수 있는 유일한 경로다(`docs/cli-contract.md:30`, 구현 `CLI/cmux.swift:5979-5985`가 문자 그대로 `/usr/bin/open -a <bundle> <dir>`). 게다가 **실행 가능한 파일을 넘기면 cmux가 그것을 실행한다**: `shouldRunInTerminal`(`Sources/AppDelegate+CmuxSSHURL.swift:241-246`)이 exec 비트·`.command`/`.tool`·`public.unix-executable`을 매치하고 `initialInput = "'<경로>'\n"`으로 셸에 타이핑까지 한다(`:214-215`), 확인 대화상자 없이. 즉 Warp의 Tab Config와 같은 모양의 소켓 없는 실행 경로가 존재한다. 그럼에도 기각하는 이유 넷:
1. **핸들이 없다.** workspace·surface id를 돌려주지 않으므로 `surface.read_text`로 화면을 확인할 대상을 지목할 수 없다 → 반영 확인 프로토콜이 성립하지 않는다(claude 입력 불가). 되살리려면 pane 안 헬퍼(WarpHelper급 새 실행 타깃)가 필요하다
2. **세션 복원이 깨진다.** cmux가 꺼져 있을 때 이 경로로 띄우면 인자 붙은 실행이 되어 위 `shouldAttemptRestore`가 복원을 끈다 — 버튼 한 번이 사용자의 이전 cmux 세션을 날린다
3. **셸 의미가 다르다.** 타이핑되는 것이 스크립트 경로이므로 명령이 **비대화식 서브셸**에서 돈다 → `z`(zoxide가 rc에서 정의하는 셸 함수)를 찾지 못한다
4. 창 지정·`focus` 수단이 없다

**[기각] `cmux://prompt?text=…`** — 텍스트를 포커스된 터미널에 붙여 넣는 URL이 있지만 ①모달 확인이 뜨고 기본 버튼이 Cancel이며(`Sources/AppDelegate+CmuxSSHURL.swift:690-724`), ②제어문자를 전부 거부하고(`Sources/CmuxSSHURLRequest.swift:872-881`) 대화상자 문구 자체가 "will not press Return"이며, ③대상이 **포커스된** 터미널이라 우리 pane을 지목할 수 없다.

### D4. tty 경로 획득 — `debug.terminals`에서 읽는다 (Plan A 성립)

**소스 근거**

- `cmux debug-terminals --json`(= `rpc debug.terminals`)의 `terminals[]` 항목에 `surface_id`·`workspace_id`·`window_id`와 함께 **`tty`**가 있다(`Sources/TerminalController.swift:5117` `let ttyName = workspace?.surfaceTTYNames[panelId]`, 출력 `:5186`). `cmux tree --json`·`system.top`에도 같은 값이 실린다. `list-panes`·`identify`에는 **없다**
- 값은 **basename**이다(`ttys004`, `/dev/` 없음) — 셸이 `t="${t##*/}"`로 잘라 보고한다
- **push 기반**이다: `surface.report_tty`는 pane 안의 셸 통합이 cmux에 알려 주는 쓰기다(`Coordinator/Surface/ControlCommandCoordinator+SurfaceReportTTY.swift:6-70`, 저장 `Sources/AgentDeliveryTargetResolution.swift:106-119`). 통합은 cmux가 `ZDOTDIR` 등을 번들 디렉토리로 돌려 심는다(`Spawn/TerminalSurface+StartupEnvironment.swift:389+`, 스크립트 `Resources/shell-integration/cmux-zsh-integration.zsh:788-828`)
- 앱은 진짜 device 이름도 안다(`ghostty_surface_tty_name`, `Surface/TerminalSurface+ProcessInfo.swift:20-73`)지만 **소켓으로 노출하지 않는다**

**[채택] Plan A**: `rpc debug.terminals` → 우리 `surface_id`의 `tty` → `/dev/` + basename. 순수 파서 `cmuxTTYName(debugTerminalsJSON:surfaceID:)`를 `wezTermTTYName`(`ClaudeInjector.swift:84-91`)과 같은 모양으로 만들고 단위 테스트로 고정한다. pane에 군더더기 명령이 하나도 생기지 않는다.

**[폴백] tty가 `null`이면 claude 입력을 포기하고 그 이유를 로그에 남긴다.** 명령은 이미 돌고 있다 — WezTerm fallback·Warp 헬퍼 미기동과 같은 취급이다. `null`이 되는 경우는 셸 통합이 안 뜬 pane(사용자가 셸을 갈아 끼웠거나 통합을 껐을 때)이다. 우리 workspace는 cmux가 스폰하므로 통합이 뜨는 것이 정상이지만, 그것을 전제로 삼지 않는다. tty 보고가 늦을 수 있으므로 **유한 시간 폴링**한다(Warp 헬퍼 tty 폴링 `ClaudeInjector.swift:603-615`와 같은 모양).

**[기각] pane 안에서 `tty >| <파일>`을 실행해 보고받기** — 사용자에게 보이는 군더더기 한 줄이 생기고, 지워야 할 파일이 늘어 `uninstall.sh`·`UninstallScriptSyncTests`까지 번진다. Plan A가 성립하므로 불필요하다.

**[기각] `ps -axE`로 환경변수 토큰을 심어 tty 찾기** — `workspace_env`로 토큰을 넣고 `ps -E`로 찾는 안. 실측: `/bin/sleep`처럼 시스템 바이너리의 환경은 같은 uid인데도 `ps -E`로 보이지 않는다(`/bin/ps -E -o command= -p <pid>`가 명령만 출력). 어떤 프로세스가 보이는지 규칙을 확정하지 못해 신뢰할 수 없다.

**[기각] 화면에서 tty를 읽기** — 타이밍·줄바꿈에 취약하고 실패가 조용하다.

### D5. 화면 반영 확인 — `surface.read_text`는 surface 단위로 정확하다 → `screenNeedsPaneProof = false`

**소스 근거**

- `surface_id`를 주면 그 workspace의 그 패널 자신의 `ghostty_surface_t`에 대해 `ghostty_surface_read_text`를 부른다(`Sources/TerminalController.swift:5478-5490`, 읽기 `:5258-5291`). **전역/최전면 그리드를 읽는 경로가 없다**
- `surface_id`가 있는데 못 찾으면 `not_found`다 — 조용한 폴백이 없다(`:5478-5490`). `surface_id`를 **주지 않았을 때만** 포커스된 surface로 떨어진다(`:5491-5497`) → 그래서 불변 원칙 15에 "UUID를 명시"를 박았다
- workspace 해석은 라우팅된 TabManager의 **모든** workspace를 훑으므로 백그라운드 workspace의 surface도 찾힌다(`Sources/TerminalController+ControlSurfaceContext.swift:43-53`)
- 창이 key인지·보이는지·가려졌는지 확인하는 곳이 없다(`readTerminalTextRawSnapshot` `:5237-5241`은 `surface != nil`만 본다)

**[채택]** `screenNeedsPaneProof = false`. cmux는 iTerm2·WezTerm과 같은 등급이다 — pane 증명이 없고, "그 탭을 보고 있어야 한다"는 Warp식 제약이 없고, 손쉬운 사용 권한이 필요 없다. `canConfirmScreen`도 `true` 고정.

**[실패 모드]** 차가운(agent-hibernated·아직 안 뜬) surface는 `internal_error`를 돌려준다(`:5501-5518`). 그때 `screenText`는 `nil`을 돌려주고 프로토콜은 그것을 **확인 실패**로 다룬다 — 정확히 우리가 원하는 동작이다(`send_text`는 큐잉되는데 `read_text`는 에러가 되는 **비대칭**이 있으므로, "보냈으니 됐다"로 넘어가면 안 된다는 불변 원칙 6이 여기서 실제로 작동한다).

**[형식]** 응답 `{text, base64, …}`. 기본은 viewport만(`--scrollback` 없이) — WezTerm `get-text`와 같은 범위다. CLI stdout으로 받으면 `print`가 개행을 하나 더 붙이지만(`CLI/cmux.swift:5227`), `screenReflectsNewInput`이 공백을 다 지우고 비교하므로 영향이 없다. `rpc`로 받으면 그 문제도 없다.

### D6. 권한 지도

| 권한 | cmux | 근거 |
|:--|:--|:--|
| TCC 자동화(Apple Events) | **불필요** | AppleScript를 쓰지 않는다 → `app/Info.plist`의 `NSAppleEventsUsageDescription` 변경 없음 |
| 손쉬운 사용(접근성) | **불필요** | D5 — 화면 읽기가 소켓으로 되므로 AX가 필요 없다 |
| cmux 소켓 제어 | **필요 — 사용자가 cmux Settings → Automation에서 켠다** | D1 |

즉 **cmux는 WezTerm 동급(TCC 0개)**이고, 대신 cmux 쪽 설정 하나가 전제다.

**[기각] AppleScript 경로 전면 채택** — cmux는 `NSAppleScriptEnabled=true`이고(`Resources/Info.plist:127-130`, 게이트가 코드에 하드코딩된 `true` — `Sources/AppleScriptSupport.swift:86-94`) sdef에 `new tab`·`input text … to <terminal>`·`perform action <Ghostty action> on <terminal>`이 있다. **소켓 인증을 완전히 우회한다**는 것이 유일한 장점이고, 조사해 보니 입력 자체는 가능하다: `input text`는 bracketed paste라 CR·Ctrl+U를 못 보내지만(`Sources/TerminalController.swift:14859-14870`), `perform action "text:\r"`·`"text:\x15"`는 Ghostty의 `text:` 액션이라 **래핑 없는 원시 바이트**다(액션 문자열은 필터 없이 `ghostty_surface_binding_action`으로 넘어간다 — `Packages/macOS/CmuxTerminal/…/Surface/TerminalSurface+CopyMode.swift:12-18`). 그럼에도 기각하는 이유 셋:

1. **화면을 읽을 수단이 사용자 클립보드를 파괴한다.** sdef에는 화면 내용 속성이 **없다**(전수 확인). 유일한 우회는 `perform action "write_screen_file:copy,vt"`로 임시 파일 경로를 **클립보드에 올려** 받는 것인데(cmux 자신이 쓰는 방식 — `Sources/TerminalController.swift:5563-5602`), cmux는 그때 자기 클립보드 가로채기를 무장한다(`Services/Pasteboard/TerminalPasteboardService.swift:88-113`). **외부 호출자에게는 그 가로채기가 없어 `NSPasteboard.general`이 그대로 덮인다**(`:186-195`). 우리는 입력 하나당 화면을 5∼10번 읽으므로 사용자의 클립보드가 반복적으로 파괴된다. 남은 대안은 Warp식 AX 읽기인데, 그러면 pane 증명·포커스 제약·손쉬운 사용 권한이 되살아난다
2. **권한이 줄기는커녕 늘어난다**: 자동화 + (AX를 쓴다면) 손쉬운 사용 둘 다. `PermissionChecker`의 상태 조회·요청·시스템 설정 열기와 설정 창 카드가 통째로 하나 더 붙는다
3. `new tab`은 **cwd도 명령도 받지 못한다**(sdef에 `in`뿐; 내부 `addWorkspace`는 cwd를 받지만 AppleScript는 넘기지 않는다 — `Sources/AppleScriptSupport.swift:199-225`). 명령은 `perform action "text:…"`로 Zig 문자열 리터럴 문법을 태워 보내야 하고, 그 파서는 cmux 문서상 "currently not validated"다

기록만 남기고 채택하지 않는다. D1의 전제를 드라이버·사용자가 거부하면 **유일한 대안**이므로 「열린 질문」에 남긴다.

### D7. 케이스 이름·저장값·자동 감지 순서

- **[채택]** `case cmux`, rawValue `"cmux"`. 앱 이름·번들 CLI 이름과 같아 별칭이 필요 없다(`iterm`이 iTerm2를 가리키는 예외와 다르다)
- 자동 감지 순서: `iterm → wezterm → warp → cmux`(맨 뒤). `Settings.terminal`의 기존 주석은 "지원이 오래돼 실사용으로 다져진 순"이고, cmux는 가장 새롭고 **사용자 쪽 선행 설정까지 필요**하므로 마지막이 맞다
- 설치 감지: `findCmuxCLI()` 하나를 Core에 두고 `PermissionChecker.isCmuxInstalled`가 그것을 쓴다. 후보는 `/Applications/cmux.app/Contents/Resources/bin/cmux` → `~/Applications/cmux.app/Contents/Resources/bin/cmux` → `/opt/homebrew/bin/cmux` → `/usr/local/bin/cmux` → PATH 순이다. **번들 안 경로가 정본**이다 — cmux가 pane에 넣는 `CMUX_BUNDLED_CLI_PATH`가 그것을 가리킨다(`Surface/TerminalSurface+RuntimeSurfaceCreation.swift:111-114`)
- 성능: 번들 CLI는 48MB Mach-O지만 콜드 스타트가 **10∼20ms**다(`/usr/bin/time -p cmux version` 3회: 0.02/0.01/0.01). `runInTerminal`이 도는 execQueue는 Chrome 응답을 막으므로(`HostServer.swift:96-112`) 호출 수를 2회(`workspace.create` + `surface.send_text`)로 유지한다 — WezTerm의 왕복 20∼40ms와 같은 수준이다

### D8. claude 아래 cmux 클리어는 바이트별 `surface.send_text`

**[교체 — 2026-08-26]** claude가 kitty keyboard protocol flag 1과 modifyOtherKeys 2를 켜므로, cmux 0.64.22의 키 이벤트 경로에서 `ctrl+u`가 CSI-u로 인코딩되어 claude에 처리되지 않는다(Claude Code 2.1.246 실측). `claudeClearInputKey`의 `0x15`와 `0x7F`는 각각 별도의 `surface.send_text` 호출로 보내고, 한 호출에 두 바이트를 넣지 않는다. 한 호출에서는 `!`가 남고, 두 호출을 순서대로 하면 입력창이 빈다. 따라서 cmux RPC 메서드는 `workspace.create`·`surface.send_text`·`surface.read_text`·`debug.terminals` 네 개다.

### D9. marker 사라짐은 모든 6자 window의 잔재 검사

**[채택 — 2026-08-26]** marker 전체 문자열의 count만 baseline으로 되돌아왔는지 보는 것은 한 글자 잘린 잔재를 통과시킨다. `screenShowsMarkerErased(before:after:marker:)`는 공백을 제거한 marker의 모든 6자 window를 세어 각 window의 after count가 before count와 같을 때만 사라짐으로 판정한다. 이 순수 판정은 marker 실험의 사라짐 polling에만 적용하고, CR 뒤 본문 tail 판정은 별도 계약으로 유지한다.

### D10. claude_inputs의 CR/LF는 앱 경계에서 거부

**[채택 — 2026-08-26, O1 정정 2026-08-27]** 렌더링 뒤 원본 `claude_inputs`에 NUL·LF·CR 검사를 먼저 하고, 나머지 제어 문자 검사를 통과한 뒤에만 바깥 공백을 제거한다. 모든 typed carrier에서 개행은 marker·화면 반영 확인·최종 CR보다 먼저 제출되므로 조용한 우회가 된다. 검사를 trim 뒤에 두면 `.whitespacesAndNewlines`가 가장자리의 TAB·CR·LF를 지우고 TAB만 있는 입력이 성공 응답과 함께 사라진다(cold review 8차). `command_template`은 실행 계약상 CR을 붙이고 개행을 별도 shell command로 실행하므로 이 제한을 적용하지 않는다.

**N1 보강 — 2026-08-27:** `claude_inputs`는 NUL·개행의 기존 진단을 먼저 거친 뒤 나머지 C0 제어 문자와 DEL도 거부한다. 이 바이트들은 타이핑되고 DEL은 Backspace로 동작하며 반영 확인은 앞 24자만 보므로, 뒤의 제어 문자가 CR 전에 명령을 바꿀 수 있다. `command_template`에는 적용하지 않는다.

### D11. cmux 설정 파일은 앱이 쓰지 않는다

**[폐기 — 사용자 결정 2026-08-27]** 이전 D1-b의 JSONC 텍스트 편집·백업·원자적 교체·권한 축소·심링크 해석·라이브 적용 확인은 사용자 파일 손상·권한 누출·거짓 안심을 낳은 cold review 1∼7차 지적의 약 절반(18건) 때문에 범위에서 제거했다. 현재 버튼은 설정 조각을 클립보드에 복사하고 기존 파일 또는 폴더를 열어 사용자가 직접 수정하게 하며, 앱은 설정 파일을 읽거나 쓰지 않는다.

### D12. cmux ping PONG/거부가 기본 소켓 파일보다 우선

**L2 보강 — 2026-08-27:** 재시도 지점은 문자열 마커가 아니라 `Error: Failed to connect to socket at ` 또는 `Error: Socket not found at `으로 **시작하는** 실측 CLI 오류 타입만 허용한다. 두 형태 모두 드라이버가 측정한 원문이고 `Error: `는 CLI 출력의 일부다. 접두사를 뺀 문자열로 고정했던 이전 테스트는 통과하면서도 실제 자동 기동 경로를 막았고, 이제 접두사가 사라지면 닫히는 방향으로 실패한다. 부분 문자열은 `workspace.create: post-create hook: no such file or directory`처럼 서버가 만든 뒤의 실패를 구별하지 못한다.

**N2 보강 — 2026-08-27:** 두 실측 형태는 `Error: ` 접두사까지 필수로 앵커한다. 접두사를 뺀 테스트가 초록이면서 실경로의 자동 기동을 막았던 사실을 기록한다.

**[채택 — 2026-08-26]** cmux CLI는 `CMUX_SOCKET_PATH`와 `/tmp/cmux-last-socket-path`로 소켓을 스스로 찾으므로 PONG은 기본 소켓 파일 부재보다 먼저 `reachable`, Access denied는 `denied`로 분류한다. 두 결과가 모두 아니고 기본 소켓도 없을 때만 `notRunning`이며, 기동 필요 판정은 소켓 부재와 ping 실패의 동시 조건이다. Access denied는 cmux를 다시 띄워 고칠 수 없으므로 즉시 `cmuxSocketDenied`로 실패시켜야 한다. 소켓 파일이 있으면 ping을 생략하고 진행하며, automation 거부 진단은 `workspace.create`의 RPC 분류로 보존한다(H3). **[교체 — I5, 2026-08-26]** 실행 경로는 ping을 쓰지 않고 `workspace.create`를 정본 진단으로 삼는다. 첫 RPC가 `cmuxSocketDenied`면 즉시 던지고, 그 밖의 실패에서만 한 번 기동·`debug.terminals` 서버 폴링·`workspace.create` 한 번의 재시도를 한다. 설정 창 라이브 상태 프로브의 ping 정본과 실행 경로의 `workspace.create` 정본은 서로 다른 계약이다. J2에서는 timeout·invalid JSON처럼 서버 부작용 가능성이 있는 결과를 재시도하지 않고, 연결 자체가 성립하지 않았음이 보이는 RPC 실패만 재시도한다. J5에서는 기동 뒤 `debug.terminals` 서버 응답을 준비 정본으로 삼고, 거부는 즉시 `cmuxSocketDenied`로 끝낸다.

### D13. 자동화 버튼은 설정 안내만 제공한다

**[교체 — 사용자 결정 2026-08-27]** 버튼은 라이브 상태와 무관하게 활성이고, `"automation": { "socketControlMode": "automation" }` 조각을 클립보드에 복사한 뒤 기존 설정 파일 또는 폴더를 연다. 파일·폴더를 만들거나 쓰지 않으므로 백업 경고·in-flight 상태·결과 후처리로 라이브 상태를 덮는 경로는 없다. cmux 자체 설정 → Automation도 함께 안내하고, cmux의 파일 워처가 변경을 즉시 반영하므로 재시작은 필요 없다(R1-m). 분류가 흔들리는 라이브 프로브는 상태 표시의 정본으로만 남는다. 같은 부류가 세 번 나왔고, 이제 인스턴스가 아니라 대입 지점을 감사 테스트로 고정한다.

### D14. cmux 화면 읽기 오류 억제는 surface별이며 성공 시 초기화

**[채택 — 2026-08-26]** 화면 읽기 오류 로그는 surface UUID별 마지막 메시지만 억제하고, 같은 surface의 성공한 read가 그 기록을 지운다. 전달 종료 시 해당 surface의 기록을 삭제하고, 실패만 이어지는 경우에도 32개 상한에서 stale 기록을 비워 맵을 제한한다(H5). 프로세스 전역 마지막 문자열만 비교하는 방식은 다른 surface의 같은 오류와 성공 뒤 재발한 오류를 삼키므로 기각한다. I5의 실행 복구도 첫 실패 뒤 한 번만 재시도하며, 성공한 workspace를 다시 만들지 않는다.

### D15. cmux 설정 파일 편집기 제거

**[폐기 — 사용자 결정 2026-08-27]** 파일이 없거나 공백뿐인 경우의 최소 JSON 생성, 토큰이 있는 깨진 JSONC의 거부, 주석 보존 스캔은 앱이 설정 파일을 읽거나 쓰지 않도록 범위를 줄이면서 더 이상 적용되지 않는다. 사용자가 클립보드 조각을 직접 파일에 붙여 넣고 편집한다.

### D16. `runProcess` 종료 상한

**L5∼L7 보강 — 2026-08-27:** 손실 디코딩으로 유효한 앞부분을 살리고 잘린 멀티바이트 원본을 로그에 남기며, 두 출력 버퍼를 락으로 보호하고 마지막 0.25초 대기 timeout을 로그에 남긴다. `open -b` 종료 상태와 마지막 비거부 readiness 오류도 timeout 설명에 함께 보존한다.

**[채택 — 2026-08-26]** timeout 뒤 SIGTERM에 2초 유예를 주고 SIGKILL로 에스컬레이션한 뒤, 자식·손자가 파이프를 붙든 경우에도 drain을 최대 1초와 마지막 0.25초로만 기다린다. 성공 경로는 그대로 두고, 종료를 무시하는 자식 때문에 공용 subprocess helper가 무기한 대기하는 것을 기각한다(I7). J3에서는 부모가 정상 종료해도 남은 드레인을 1초로 제한하고 부분 출력을 로그와 함께 반환하며, Process 공개 API에는 자식 측 process-group 설정 hook가 없어 parent `setpgid`의 exec 경쟁 한계가 있다. J8 실측은 `/bin/sh` 대상 Darwin 25.4.0에서 20/20 EACCES였고, 파이프 리더를 닫는 쪽이 실제 상한이며 손자 잔존(1 → 2)이 확인됐다.

## 작업 항목

| # | 항목 | 상태 | 근거 (무엇을 실행해 무엇이 나오면 claimed인가) | 의존 | 라운드 |
|:--|:--|:--|:--|:--|:--|
| 1 | `Terminal`에 `cmux` 케이스 + `TerminalIdentifierTests`에 rawValue 리터럴과 `allCases.count` 4 | cleared | `TerminalIdentifierTests`에 4개 rawValue 리터럴·`allCases.count == 4`를 추가하고, 컴파일 switch 구멍은 R1 라운드 로그에 기록했다. 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 2 | `findCmuxCLI()`·`cmuxSocketPath()` (Core) | cleared | `CmuxTests.testCmuxCLICandidatePathsUseBundleLocationsBeforePATH`, `testFindCmuxCLIReturnsTheFirstExecutableCandidate`, `testCmuxSocketPathOnlyReportsAnExistingSocket`로 후보 순서·생존 소켓 판정을 고정했다(실환경 게이트는 드라이버). 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 3 | `cmuxRPC(cli:method:params:)` + 메서드 이름 상수 4개(`workspace.create`·`surface.send_text`·`surface.read_text`·`debug.terminals`) | cleared | `CmuxTests`의 메서드 상수·ASCII argv·JSON 의미 보존·workspace/send/read 응답 파싱 테스트로 고정했다. CLI stdin 경로가 없어 `\uXXXX` JSON argv를 채택한 근거는 D2에 기록했다. 메서드 4개(send_key 제거, D8). D12: PONG·Access denied 결과가 기본 소켓 파일 부재보다 우선하고 거부는 즉시 `cmuxSocketDenied`로 끝난다. 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 4 | `TerminalError`에 `cmuxNotFound`·`cmuxSocketDenied`·`cmuxRPCFailed` — 소켓 거부를 **구분되는 문구**로 | cleared | `CmuxTests.testCmuxRPCFailuresDistinguishSocketDenialAndMethod`와 `CmuxLocalizationTests.testCmuxTerminalErrorsUseAllFiveCatalogs`로 분류·5로케일 경로를 고정했다(실제 relay 왕복은 드라이버). 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 5 | `runInCmux(_ command: String) throws -> TerminalSessionHandle` — 소켓 없으면 인자 없는 `open -b com.cmuxterm.app` + 폴링 → `workspace.create`(focus true) → `surface.send_text`로 `command+"\r"` | cleared | 순수 함수·인자 조립 단위 테스트 + 드라이버가 2026-08-26 동일 rpc 시퀀스를 실측(workspace.create focus:true 58∼110ms → surface.send_text 38ms queued:false → 명령 실행 확인: 리다이렉트 파일 생성). D12: ping PONG이면 cmux를 다시 열지 않고 진행하고 Access denied면 기동하지 않고 즉시 실패한다. 앱 경유 최종 실측은 R1-j(항목 21). 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | `3(cmuxRPC 계약)` | |
| 6 | `cmuxWorkspaceCreateAttempts(windowID:)` 순수 함수 + 테스트 — **R1-g가 통과하면 `dropped`** | dropped | R1-g 통과 — window_id 미지정으로 마지막 활성 창에 생성됨을 확인, 시도 목록 불필요. | | |
| 7 | `runInTerminal` switch에 `.cmux` | cleared | `runInTerminal`의 `.cmux`가 `return try runInCmux(command)`으로 연결된다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | | |
| 8 | `TerminalSessionHandle`에 `.cmux(surfaceID:workspaceID:cliPath:)` + `screenNeedsPaneProof` 갈래(false) | cleared | `testItem8OnlyWarpNeedsPaneProof`가 `.cmux`·`.warp`·기존 세 handle의 oracle을 고정하고, cmux handle을 `surfaceID`·`workspaceID`·`cliPath`와 함께 저장한다. D9의 `screenShowsMarkerErased` 6자 window 테스트와 R1-j Fake delivery 테스트가 marker 잔재를 pane-proof 성공으로 오인하지 않는 경계를 고정한다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | | |
| 9 | `deliverClaudeInputs`의 tty 갈래 — `debug.terminals` 폴링 + `cmuxTTYName(debugTerminalsJSON:surfaceID:)` 순수 파서 | cleared | `testItem9CmuxTTYNameParsesTheMatchingSurface`, `testItem9CmuxTTYNameReturnsNilForNullTTY`, `testItem9CmuxTTYNameReturnsNilForMissingSurface`, `testItem9CmuxTTYNameReturnsNilForInvalidJSON`로 파서를 고정하고, cmux 갈래는 유한 폴링 타임아웃에 입력을 포기한다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | `3(cmuxRPC 계약)` | |
| 10 | `sendKeys`의 `case .cmux` — marker·본문·CR·클리어 모두 `surface.send_text`; 클리어만 `0x15`·`0x7F` 두 별도 호출. `queued` 로깅. D8에서 `send_key`를 제거했다. | cleared | `testItem10CmuxClearInputIsTwoSendTextCallsCtrlUThenBackspace`, `testItem10EveryCmuxByteGoesThroughSendText`, `testItem10CmuxBodyUsesSurfaceSendTextWithoutChangingIt`, `testItem10CmuxCRUsesOneSurfaceSendTextCR`가 입력별 메서드·파라미터와 CR 보존을 고정한다. `sendKeys`의 cmux 갈래는 RPC 성공을 확인하고 `queued:true`만 값 그대로 로그한다. D10: `claude_inputs`의 CR/LF는 typed 경로 전에 앱 경계에서 거부한다. D14: 화면 읽기 오류 억제는 surface별이고 성공 시 초기화한다. | `3(cmuxRPC 계약)` | |
| 11 | `screenText`의 `case .cmux` — `surface.read_text` | cleared | `testItem11CmuxScreenTextRequiresTheTextField`가 `surface_id` 파라미터와 `text` 필드·필드 없음의 nil을 고정한다. cmux 갈래는 RPC 실패·필드 없음에서 nil이며 다른 화면 폴백을 만들지 않는다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | `3(cmuxRPC 계약)` | |
| 12 | `Settings.terminal` 자동 감지에 cmux 한 줄(맨 뒤) | cleared | `CmuxDetectionTests.testItem12CmuxOnlyInstallationSelectsCmux`, `testItem12NoInstalledTerminalFallsBackToITerm`, `testItem12ITermWinsOverCmux`, `testItem12WarpWinsOverCmux`가 순수 우선순위 함수를 고정한다. `Settings.terminal`은 iTerm → WezTerm → Warp → cmux 순으로 같은 함수에 설치 판정을 넣는다. 재실행(드라이버): swift 512(1 skip)·node 220, 0 실패. 실환경 reachable 실측: `cmux ping` → PONG, exit 0. | | |
| 13 | `PermissionChecker.isCmuxInstalled` + `cmuxSocketStatus()` 라이브 프로브(`cmux ping`) | cleared | `CmuxTests`의 5개 `testItem13CmuxSocketStatus...`가 notInstalled·notRunning·denied·reachable·failed 분류를 고정하고, `CmuxLocalizationTests.testCmuxSocketStatusLabelsUseAllFiveCatalogs`가 5상태 × 5로케일 raw-key 부재를 고정한다. `isCmuxInstalled`는 실행과 같은 `findCmuxCLI()`를 쓰며, `cmuxSocketStatus()`는 소켓 존재와 5초 `cmux ping`을 매번 분류하고 저장하지 않는다. D12: PONG·Access denied가 기본 소켓 파일 부재보다 우선하고, 그 외 소켓 부재만 notRunning이며 실행 경로의 거부는 즉시 실패한다. 실환경: 드라이버가 reachable 상태만 실측할 수 있다(사용자의 cmux가 automation으로 살아 있다 — notRunning·denied 실측은 사용자 상태를 바꿔야 하므로 항목 21로 이월). 재실행(드라이버): swift 512(1 skip)·node 220, 0 실패. 실환경 reachable 실측: `cmux ping` → PONG, exit 0. | | |
| 14 | `SetupWindowController` — 라디오, `terminalChanged` if-체인, 안내 노트, `refresh` 권한 switch, 「cmux 소켓 제어」 카드(+[설정 파일 열기] 버튼), `pipelineNodes` | claimed | `SetupWindowController`에 4번째 cmux 라디오·상태 카드·[설정 파일 열기]/[다시 확인] 버튼·reachable/notRunning/denied/notInstalled/failed pipeline 매핑을 추가했고, 버튼은 모든 상태에서 활성이다. `SetupWindowLayoutTests.testItem14CmuxSelectionShowsSocketSectionAndUsesStatusState`와 제품명 집합 "cmux", `CmuxLocalizationTests.testItem14CmuxCardStringsExistInAllFiveCatalogs`로 고정했다. 축소된 계약에 따라 자동화 기록·JSONC 편집·백업·원자 교체·권한 처리·심링크 쓰기·in-flight/백업 경고 후처리는 dropped했고, 설정 창 캡처·사용자 실측은 항목 21로 남긴다. | `13` | |
| 15 | `install.sh` 프리플라이트에 cmux 감지 + 안내 | cleared | `install.sh:34-69`에 Core `findCmuxCLI()`와 같은 번들 우선 후보(`/Applications` → `$HOME/Applications` → Homebrew → `/usr/local` → PATH)와 실행 가능 판정을 넣고, 감지 실패 안내를 iTerm2·WezTerm·Warp·cmux로 갱신했다. 앱 함수와 어긋나면 설치 통과/앱 미설치 판정이 갈리는 이유를 주석으로 남겼다. 재실행(드라이버): swift 527(1 skip)·node 220, 0 실패. | | R1 |
| 16 | `README.md` — 터미널 목록·아키텍처 그림·설정 단계·권한 안내·fallback 제한·트러블슈팅 + **cmux socket mode 안내** | cleared | `README.md:8,16,28,34-35,41,91-94,178-185,262,271-275`에 cmux 실행·surface 단위 백그라운드 전달·TCC 0개/automation 전제·설정 카드·uid 경계·Warp 구별·트러블슈팅을 기록했다. 재실행(드라이버): swift 527(1 skip)·node 220, 0 실패. | | R1 |
| 17 | manifest description은 `__MSG_…__` 참조이고 실제 문구는 `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json` 5파일에 있다 — 다섯 로케일 모두 갱신, `tools/check-locales.js`가 게이트(불변 원칙 16) | cleared | `extension/manifest.json:5`가 `__MSG_extDescription__` 참조임을 확인하고, 5개 `_locales/*/messages.json:7`의 extDescription에 cmux를 추가했다. `node --test`/`tools/check-locales.js`는 드라이버 게이트 소관이다. 재실행(드라이버): swift 527(1 skip)·node 220, 0 실패. | | R1 |
| 18 | `docs/new-terminal-checklist.md` — §1에 "소켓 접근 모드가 필요한 터미널" 줄, §2에 cmux 전용 실측 블록 | cleared | `docs/new-terminal-checklist.md:9,18,23,45,49,122-130`에서 저장 rawValue·현재 `claudeInput: ClaudeDelivery.Admission?`·2바이트 clear key·cmux socket mode 표면과 §2 실측 블록을 갱신했다. 재실행(드라이버): swift 527(1 skip)·node 220, 0 실패. | | R1 |
| 19 | `CLAUDE.md`에 cmux 함정 추가(rpc 통일 이유·`unescapeSendText` 구멍·서버의 LF→CR 변환·socket mode 전제·tty가 push 기반) + 5행의 낡은 터미널 목록 갱신 | cleared | `CLAUDE.md:7,55-63`에 cmux rpc 단일 경로·v0.64.22 개행 함정·automation uid 경계·socket 부재 분류 불가·tty/queued 웜업·입력 바이트·ASCII argv·무인자 `open -b`·Warp 반대 화면 등급을 기록했고, `SECURITY.md:12`의 same-uid 모델에도 cmux automation을 반영했다. 재실행(드라이버): swift 527(1 skip)·node 220, 0 실패. | | R1 |
| 20 | 게이트 4종 재실행 | verified | 최종 코드에서 드라이버 재실행: swift 533(1 skip)·node 220·build.sh 완료·e2e 9/9, 0 실패. | | |
| 21 | `docs/new-terminal-checklist.md` §2 실측 전체 수행(사용자 참여) | verified | R1-g PASS, R1-k 웜업 flush를 앱 로그에서 실증(첫 요청 `queued=true`인데 명령 실행됨), R1-j 재실측 통과(위). R1-g는 재실측에서도 활성 창(W2)에 생성. R1-n(automation 미설정 시 안내 문구) 실측 포함. | | |
| 22 | `CmuxConfigHelp` — automation JSON 조각 클립보드 + 기존 파일/폴더 열기, 사용자 파일 읽기·쓰기 없음 | claimed | `CmuxConfigHelpTests.testItem22ConfigClipboardFragmentContainsAutomationSetting`과 `testItem22ConfigRevealTargetChoosesFileDirectoryOrNothing`가 조각 내용과 파일·폴더·없음 대상 선택을 고정한다. 축소된 계약에 따라 JSONC 파싱·편집·최소 JSON 생성·백업·원자 교체·권한 변경·심링크 target 쓰기·라이브 적용 폴링은 dropped했다. 버튼은 기존 파일 또는 폴더만 열고 파일·디렉터리를 만들거나 쓰지 않는다. | `13` | |

## 전수 소탕 표

컴파일러가 잡는 것(default 없는 switch)과 못 잡는 것(`==`·if-체인·문자열·스크립트·문서)을 구분한다.

| 지점 | 이 부류가 성립하는가 | 확인 방법 | 판정 |
|:--|:--|:--|:--|
| `Core/Terminal.swift:3-7` (enum) | 예 — 시작점 | 케이스 추가 | 구멍(항목 1) |
| `Core/Terminal.swift:11-13` (`init(storedValue:)`) | 아니오 — 폴백이 한 곳뿐 | 코드 확인 | 안전 |
| `Core/TerminalRunner.swift:245-251` (`runInTerminal`) | 예 — **컴파일러가 잡는다** | `swift build` | 구멍(항목 1, 7) |
| `Core/TerminalRunner.swift:3-34` (`TerminalError`) | 예 — 새 실패 사유 | 컴파일 + 문구 | 구멍(항목 4) |
| `Core/TerminalRunner.swift:102-114` (`claudeInputBlocker` 분기, #36 신설 — 요청한 `ClaudeInjector.swift` 행 아래에 기록하되 현재 위치는 `TerminalRunner.swift`) | 예 — **컴파일러가 잡는다** | `swift build` | 구멍(항목 1, 5) |
| `Core/ClaudeInjector.swift:4-20` (`TerminalSessionHandle`) | 예 | 케이스 추가 | 구멍(항목 8) |
| `Core/ClaudeInjector.swift:13-18` (`screenNeedsPaneProof`) | 예 — **`if case`라 컴파일러가 못 잡는다** | 눈으로 + `testItem8OnlyWarpNeedsPaneProof` oracle | 구멍(항목 8) |
| `Core/ClaudeInjector.swift:930-932` (`defer`의 `if case .warp` 헬퍼 종료) | **아니오** — cmux는 종료시킬 pane 내 프로세스가 없다(D4 Plan A) | 결정 D4 | 안전 |
| `Core/ClaudeInjector.swift:937-961` (tty switch) | 예 — 컴파일러가 잡는다 | `swift build`; cmux는 `debug.terminals` 유한 폴링 | 구멍(항목 9) |
| `Core/ClaudeInjector.swift:191-195` (`canConfirmScreen`·`screenNeedsPaneProof`) | 아니오 — `screenNeedsPaneProof=false`면 `canConfirmScreen()`은 화면 차단 사유만 본다 | 결정 D5 | 안전 |
| `Core/ClaudeInjector.swift:991-996` (권한 지목 로그의 "Warp뿐이라서" 전제) | **아니오 — 전제가 유지된다**(cmux는 `canConfirmScreen`이 false가 되지 않는다) | 결정 D5 | 안전 — D5가 뒤집히면 구멍 |
| `Core/ClaudeInjector.swift:1086-1142` (`sendKeys`) | 예 — 컴파일러가 잡는다 | `swift build`; clear key 특례는 `cmuxSendOperations`가 0x15·0x7F를 각각 `surface.send_text`로 분리 | 구멍(항목 10) |
| `Core/ClaudeInjector.swift:1144-1173` (`screenText`) | 예 — 컴파일러가 잡는다 | `swift build`; cmux는 `surface.read_text`의 `text`만 사용 | 구멍(항목 11) |
| `App/Settings.swift:19-32` (자동 감지 순수 함수 호출·if-체인) | 예 — **컴파일러가 못 잡는다** | 눈으로 + `CmuxDetectionTests` | 구멍(항목 12) |
| `App/PermissionChecker.swift:53-94` (`isITermInstalled`·`isWezTermInstalled`·`isWarpInstalled`·`isCmuxInstalled` 및 `cmuxSocketStatus`) | 예 | 눈으로 + `CmuxTests` | 구멍(항목 13) |
| `App/SetupWindowController.swift:881-884,1307,1472,1479` (`isITermInstalled`·`isWezTermInstalled`·`isWarpInstalled`·`isCmuxInstalled` 호출처) | 예 — 라디오 4개, iTerm permission 상태, WezTerm/Warp pipeline 상태를 모두 확인 | `rg` 호출처 전수 확인 + 코드 | 확인(항목 14) |
| `App/Settings.swift:27-32` (`isXxxInstalled` 자동 감지 호출처) | 예 — iTerm → WezTerm → Warp → cmux 순수 우선순위 함수의 단일 실행 경로 | 코드 확인 | 확인(항목 12) |
| `App/Installer.swift` (`isXxxInstalled` 호출 없음·터미널 상태 프로브 없음) | 아니오 — 설치 복사·manifest만 담당 | `rg` 호출처 전수 확인 | 안전 |
| `App/SetupWindowController.swift:264-303` (라디오·상태 라벨·permission/cmux/accessibility 섹션 프로퍼티) | 예 | 코드 확인 | 확인(항목 14) |
| `App/SetupWindowController.swift:881-905,966-990` (라디오 생성·4개 세로 배치·cmux 카드 content) | 예 — cmux 카드가 terminal card에 포함된다 | 코드 확인 | 확인(항목 14) |
| `App/SetupWindowController.swift:1211-1221` (`terminalChanged` if-체인) | 예 — **컴파일러가 못 잡는다**(체크리스트가 명시) | 코드 확인 | 확인(항목 14) |
| `App/SetupWindowController.swift:1232-1248` (`updateTerminalControls` switch + Warp 전용 note) | 예 — cmux는 라디오만 on, Warp note는 cmux에 붙지 않는다 | `swift build` + 코드 확인 | 확인(항목 14) |
| `App/SetupWindowController.swift:1295-1340` (`refresh` permission/cmux status switch + 섹션 visibility + pipeline 전달) | 예 — cmux ping을 한 번 읽고 카드·pipeline에 같은 status를 쓴다 | `swift build` + 코드 확인 | 확인(항목 14) |
| `App/SetupWindowController.swift:1448-1505` (`pipelineNodes` switch) | 예 — 상태별 ok/warn/err와 nil unknown을 닫는다 | `swift build` + 코드 확인 | 확인(항목 14) |
| `App/SetupWindowController.swift:1678-1722` (다시 확인·설정 파일 열기 action, App I/O 경계) | 예 — 조각을 복사하고 기존 파일 또는 폴더를 여는 유일한 UI 경계이며 파일·디렉터리를 쓰지 않는다 | 코드 확인 | 확인(항목 14, 22) |
| `App/CmuxConfigHelp.swift:1-28` (클립보드 조각·파일/폴더 reveal 순수 함수) | 예 — 사용자 설정 파일을 쓰지 않는 도움말 계층 | 코드 + `CmuxConfigHelpTests` | 확인(항목 22) |
| `Tests/AppTests/SetupWindowLayoutTests.swift:392,430-445` (터미널 제품명 집합·cmux 카드/pipeline) | 예 | `swift test` | 확인(항목 14) |
| `App/HostServer.swift:177-201` | 아니오 — `Settings.terminal`을 그대로 넘긴다 | 코드 확인 | 안전 |
| `App/AppDelegate.swift`·`Installer.swift`·`Theme.swift` | 아니오 | `grep -rn "iterm\|wezterm\|warp"` 무결과 | 안전 |
| `Core/Paths.swift:31` (`com.iterm.checkout.json`) | 아니오 — 레거시 manifest 이름 | 코드 확인 | 안전 |
| `app/Info.plist` `NSAppleEventsUsageDescription` | 아니오(D6) | 결정 D6 | 안전 — D6이 뒤집히면 구멍 |
| `app/Package.swift`·`app/build.sh` (헬퍼 타깃·복사·서명) | 아니오 — pane 안 헬퍼를 만들지 않는다 | 결정 D4 Plan A | 안전 |
| `install.sh:34-69` (iTerm2·WezTerm·Warp·cmux 감지와 `exit 1` 프리플라이트) | 예 — 앱 `findCmuxCLI()`와 후보 순서를 맞춰야 한다 | 스크립트 확인 | 확인(항목 15) |
| `uninstall.sh:20-37` (Warp 잔여 스윕) | **아니오** — cmux는 디스크에 남기는 것이 없다(Tab Config·헬퍼 소켓 없음) | 결정 D4 Plan A | 안전 |
| `Tests/CoreTests/CoreTests.swift:673-688` (`TerminalIdentifierTests`) | 예 — **`allCases.count`가 3으로 박혀 테스트가 빨개진다** | `swift test` | 구멍(항목 1) |
| `Tests/CoreTests/CmuxTests.swift:6-20` (cmux 식별자·후보·소켓 순수 테스트) | 예 | `swift test` | 구멍(항목 1, 2) |
| `Tests/CoreTests/CoreTests.swift:1802-1833` (`UninstallScriptSyncTests`) | 아니오 — 새 상수가 없다 | 결정 D4 | 안전 |
| `README.md:8,16,28,34-35,41,91-94,178-185,262,271-275` | 예 — **문서** | diff | 확인(항목 16) |
| `CLAUDE.md:7,55-63` (cmux 운용 제약) | 예 — **문서** | diff | 확인(항목 19) |
| `SECURITY.md:12,15` (same-uid 신뢰 모델과 근거 링크) | 예 — cmux automation도 uid 경계를 공유한다 | diff | 확인(항목 19) |
| `extension/manifest.json:5` + `extension/_locales/*/messages.json:7` | 예 — manifest는 `__MSG_…__` 참조, 실제 description은 5개 로케일 | manifest 확인 + 문자열 diff | 확인(항목 17) |
| `extension/_locales/*/messages.json:182` | 아니오 — Warp 접근성 안내는 cmux와 무관한 typed-route 설명 | `grep -rn` 전수 확인 | 안전 |
| `app/e2e.sh:44` (`"terminal":"iterm"`) | 아니오 — 요청의 terminal 필드는 앱이 무시한다(`RequestTests.testTerminalFieldIsIgnored`) | 코드 확인 | 안전 |
| `docs/new-terminal-checklist.md:9,18,23,45,49,122-130` | 예 — **문서**, 갱신 의무 | diff | 확인(항목 18) |
| `docs/plans/base-dir-fallback.md:75,77,121,155,166,168` | 아니오 — 과거 계획의 파일:행 인용·판정 기록일 뿐 현재 터미널 지원 목록이 아니다 | `grep -rn` 전수 확인 | 안전 — `docs/context/`와 함께 이 부류의 수정 범위 밖 |

## 라운드 로그

### R0 — a20f69d (계획 수립, 코드 변경 없음)

- 차단: 없음(첫 라운드)
- 조사(설치본과 같은 커밋 `v0.64.22`/`ddd4a01bc5`): ①소켓 접근 모드 체계와 조상 추적의 실체 ②`cmux send`의 `unescapeSendText` 구멍과 `rpc` 무변환 경로 ③`surface.send_text`가 bracketed paste가 아니라는 것과 서버 입력 문법의 LF→CR 변환 ④`surface.read_text`의 surface 정확도(포커스 무관) ⑤`debug.terminals`의 `tty` 필드와 그것이 push 기반이라는 것 ⑥라우팅 기본값이 "마지막 활성 창 래치" ⑦AppleScript 표면의 한계(화면 읽기가 클립보드를 파괴)
- 실측(우리 쪽): `node --test` 22 pass, `swift test` 함수 180개(grep), cmux CLI 콜드 스타트 10∼20ms(`/usr/bin/time -p cmux version` ×3), `ps -E`로 시스템 바이너리 환경이 보이지 않음, 설치본 sdef ≡ 소스 sdef(`diff`)
- 판정: 미요청
- 승인(2026-08-23): 계획 승인 + 열린 질문 5건 결정(「열린 질문 → 결정」). 결정 반영은 드라이버가 계획 파일을 직접 갱신(사용자 지시 "그냥 계획파일 직접 업데이트해")

### 재개 R0′ — 2f922d6 (spark 전환, 코드 변경 없음)

- 사용자 지시(2026-08-26): spark 변형으로 재개 + 종결 후 /keep-the-why·/gh-pr-drive auto. 직전 상태: R1 중 사용자 "시작은 하지마"로 에이전트 TaskStop(2026-08-23), 워크트리 코드 무변경
- R1 중단 전 진행분: cmux.json automation 기록 완료(라이브 반영 = R1-m 답), 외부 ping PONG(R1-a 답), tty null 관찰 1건(미확정 → R1-f), 프로브 workspace `tc-probe-2` 정리 완료
- 드라이버 설계 재검토(spark에서 검증자=드라이버): R0 계획 유지, 반영 둘 — 불변 원칙 16(i18n) 추가, 파일:행 재확인 의무(「재개」). 부류 분할·의존: 항목 5·9·10·11은 항목 3(cmuxRPC 계약)에, 항목 14·22는 항목 13에 의존 — 배정 시 `의존` 열에 적는다
- 역할 배분(spark): cmux 실측(R1-a∼m)은 전부 드라이버가 수행(Codex 샌드박스는 네트워크·소켓 불가), Codex는 코드·테스트·문서만. 게이트 4종도 드라이버가 clone에서 실행

### R1 — Core 순수 계층 (2026-08-26, Codex)

- 항목 1∼4를 `verified`로 갱신했다. `Terminal` rawValue 4개와 `allCases.count == 4`, cmux CLI 후보·소켓 생존 판정, RPC 메서드 4개·ASCII JSON argv·응답 파서, cmux 오류 분류와 5로케일 Localization 경로를 코드와 테스트에 반영했다.
- 항목 1의 enum 추가로 컴파일러가 잡는 exhaustive switch 구멍은 현재 트리에서 `Core/TerminalRunner.swift:102-114`(`claudeInputBlocker`, #36 신설), `Core/TerminalRunner.swift:245-251`(`runInTerminal`), `App/SetupWindowController.swift:1190-1198`(`updateTerminalControls`), `:1264-1284`(`refresh` 권한), `:1405-1436`(`pipelineNodes`)다. 이 부류에서는 새 케이스가 컴파일되도록 해당 위치에만 cmux 분기를 닫았고, 실제 실행·설정 UI 경로는 항목 5 이후로 남겼다.
- 컴파일러가 잡지 못하는 현재 위치도 갱신했다: `App/Settings.swift:19-32` 자동 감지 순수 함수·호출, `App/SetupWindowController.swift:1170-1177` 라디오 if-체인, `:1205` Warp `==`, `:1287-1288` 섹션 `!=`, `App/PermissionChecker.swift:53-94` 설치 판정·cmux 상태 프로브, `Tests/AppTests/SetupWindowLayoutTests.swift:392` 제품명 집합.
- TDD 테스트: `TerminalIdentifierTests.testRawValuesAreTheStoredIdentifiers`를 4개로 늘렸고, `CmuxTests.testCmuxCLICandidatePathsUseBundleLocationsBeforePATH`, `testFindCmuxCLIReturnsTheFirstExecutableCandidate`, `testCmuxSocketPathOnlyReportsAnExistingSocket`, `testCmuxRPCMethodNamesAreTheFourSupportedMethods`, `testCmuxRPCArgumentsAreASCIIAndPreserveJSONValues`, `testCmuxRPCResponseParsesWorkspaceIdentifiers`, `testCmuxRPCResponseParsesQueuedAndText`, `testCmuxRPCFailuresDistinguishSocketDenialAndMethod`, `CmuxLocalizationTests.testCmuxTerminalErrorsUseAllFiveCatalogs`를 추가했다.
- 게이트 4종은 드라이버가 실행한다. 이 부류에서는 `swift test`·`node --test`·build·e2e를 실행하지 않았다.
- 드라이버 대조(2026-08-26): swift 493(신규 10 = CmuxTests 9 + CmuxLocalizationTests 1, 이후 중복 1 삭제로 9)·node 220. 수정 3건 반영 — socketDenied 문구 오진(소켓 부재 처방 → automation 모드 처방), rpcFailed 형식-payload 불일치, 식별자 테스트 중복 삭제. build.sh·e2e.sh는 실행 경로가 생기는 항목 5·7 승격에서 돌린다.
- 드라이버 증분 리뷰(2026-08-26, c85d604): ① 부류 내 차단 없음 ② 새 표면(localizedErrorMessage 폴백 경계·asciiJSON·cmuxRPCFailure 분류) 우회 수색 — 발견 3건(socketDenied 문구 오진·rpcFailed 형식-payload 불일치·식별자 테스트 중복)은 같은 커밋에서 수정. 항목 1∼4 cleared.
- 부류 2(실행·전달 경로) 드라이버 대조(2026-08-26): 게이트 4종 그린 — build.sh·e2e.sh는 이 승격에서 처음 실행. 관찰 1건(비차단): cmuxTTYName은 tty 값에 `/`가 들어오면 nil을 돌려준다 — cmux가 언젠가 full path를 보내는 쪽으로 바뀌면 조용한 입력 포기가 되지만, 방향이 안전(명령은 돌고 로그에 남는다)하고 현재 소스는 basename을 보증하므로 그대로 둔다. cmux 버전 인상 검사 목록(항목 18)에 함께 넣는다.
- 드라이버 증분 리뷰(2026-08-26, fbef5bf): ① 부류 내 차단 없음 ② 새 표면(runInCmux의 create→send 2단계·cmuxQueryTTY 폴링·cmuxSendOperations·cmuxTTYName 파서) 우회 수색에서 차단 없음, 비차단 관찰 1건은 라운드 로그에 기록됨. 항목 5·7·8·9·10·11 cleared.
- 부류 3(감지·상태 프로브): 항목 12는 `terminalForInstalledTerminals` 순수 우선순위 함수와 Settings 연결, 항목 13은 `CmuxSocketStatus` 분류·라이브 `cmux ping`·5로케일 label로 cleared했다. TDD 테스트는 자동 감지 4개, 상태 분류 5개, 상태 label 5상태 × 5로케일이다. 게이트는 드라이버가 실행한다.
- 부류 3(감지·상태 프로브) 드라이버 대조(2026-08-26): 첫 게이트에서 swift 1 실패 — CatalogueOwnershipTests.testOneValueInsideAnotherIsDeclared(en: app.status.cmux.notInstalled가 app.error.cmux.notInstalled에 포함, 사유 미등록). 예외 등록 대신 상태 라벨을 맨 상태어('Not installed')로 바꿔 해소. 교훈: 상태 라벨은 문장이 아니라 상태어로 — 에러 문구와의 포함 관계를 만들지 않는다. notRunning·denied 실환경 실측은 항목 21로 이월(사용자의 라이브 cmux 상태를 바꿔야 함).
- 부류 3 승격(2026-08-26): 드라이버 증분 리뷰 cleared — 새 표면(classifyCmuxSocketStatus·terminalForInstalledTerminals·라벨 카탈로그) 우회 수색에서 차단 없음.
- 부류 4(설정 창·cmux.json 기록): 항목 14·22를 claimed했다. cmux 카드·상태 pipeline·명시적 자동화 허용 action과 JSONC 보존 편집·백업·원자적 쓰기·bounded live poll을 구현했고, 설정 창 4상태 캡처는 설치 후 사용자 참여인 항목 21로 이월했다. 게이트는 드라이버가 실행한다.
- 부류 4(설정 창 카드 + cmux.json 버튼) 드라이버 냉독·대조(2026-08-26): 결함 2건 발견·같은 커밋에서 수정 — ① 새 cmux.json이 0644로 생성됨(cmux 규약 0600, socketPassword를 담을 수 있는 파일) ② 삽입 텍스트가 파일의 개행·들여쓰기를 따르지 않음(사용자가 손으로 편집하는 파일). JSONC 편집기는 파싱-재직렬화가 아니라 스팬 텍스트 편집이라 주석·후행 콤마·키 순서가 보존되며, 무효 입력은 쓰기 거부. 검사 목록(항목 18)에 '버튼 후 cmux.json과 .bak이 0600인가'를 추가한다.
- 드라이버 증분 리뷰(2026-08-26, 8320819): ① 부류 내 차단 없음 ② 새 표면 우회 수색 — 냉독 발견 2건(0644 생성·서식 미준수) 같은 커밋에서 수정. 항목 14·22 cleared.
- 부류 5(문서·스크립트) 드라이버 대조(2026-08-26): 첫 게이트에서 node 2 실패 — `_locales` 바이트 핀(의도된 편집 확인 후 핀 갱신이 절차). 핀 갱신으로 해소. 문서 보정 2건(검사 목록 0600 항목, CLAUDE.md의 소켓 모드 전제 정밀화: 계보 검사 없는 모드 — automation 권장, password·allowAll도 통과).
- R1-j 결함 수리(2026-08-26): 원인·측정·D8·D9. red: swift test --filter 3개 → Executed 3 tests, with 5 failures (드라이버) / green: swift 533(1 skip)·node 220·build.sh·e2e 9/9 (드라이버).
- 부수 관찰(2026-08-26): `debug.terminals`는 닫힌 surface를 `mapped:false`·`tty:null`·`workspace_id:null`로 계속 나열한다(실측 4건). `cmuxTTYName`은 surface_id 일치와 tty 문자열을 함께 요구하므로 영향 없음.
- cold review 1차(2026-08-26, 최종 12ef63b): 판정 no, 차단 7건 — F1 개행 조기 제출·F2 동시 편집 덮어쓰기·F3 두 번째 바이트의 게이트 우회·F4 백업 0644·F5 프로브 없는 초록·F6 PONG보다 소켓 경로 우선. 6건 수리, F7(try? 로 typed error 소실)은 로그 보강. red: 7 테스트 16 실패(드라이버) / green: swift 537(1 skip)·node 220·build.sh 완료·e2e 9/9, 0 실패. 재실측: PASS — 설치본(sha256 d057c393… 일치, 창 2개 중 활성 창 W2)에서 relay 요청 `!echo tc-r1j3-input-ok` → transcript 391ca523…에 `<bash-input>echo tc-r1j3-input-ok</bash-input>`와 `<bash-stdout>tc-r1j3-input-ok</bash-stdout>`(shell mode 제출·실행). 앱 로그: tab 0.4s → tty 1.5s → claude ready 2.0s → pane proof(2/12) 6.2s → 반영 6.7s → CR 7.2s → 완료 7.8s. workspace는 활성 창에 생성(R1-g 3회째 확인), 창은 닫음.
- F7 로그 방식: tty 폴링은 포기 시점에 마지막 RPC 오류 1회만 남기고, 화면 읽기는 연속 동일 오류를 억제하며 다른 오류로 바뀌면 기록한다.
- cold review 2차(2026-08-26, 5300f75): 판정 no, 차단 3건 + 비차단 1건 — G1 비교∼교체 사이 유실 창(`backupItemName`으로 교체된 바이트 보존), G2 실행 경로가 Access denied를 Bool로 뭉갬(즉시 `cmuxSocketDenied`), G3 자동화 버튼 후처리가 라이브 상태를 덮음(`refresh()`가 정본), G4 화면 읽기 오류 억제가 프로세스 수명·surface 무구분. 1차 지적 중 F1·F3·F4는 닫힘 확인. red: clone에서 `swift test --filter` 6개 → Executed 6 tests, with 7 failures, exit 1 — G1 `.bak`에 V3 없음, G2 `.denied`가 `launch`, G3 세 케이스가 nil 아님, G4 성공 초기화·surface 구분 모두 실패. 억제 테스트 1개만 통과. / green: swift 543(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. 실측: R1-j 4회째 PASS(13.7s), G2 실측 — automation을 끈 상태에서 0.2초에 automation 문구로 실패(이전에는 10초 timeout 오진).
- cold review 3차(2026-08-26, c8b42e4): 판정 no, 차단 4건 + 비차단 1건 — H1 `backupItemName`이 같은 이름의 기존 백업을 삭제(Foundation 계약)·버튼 in-flight 비활성화 소실, H2 교체 성공 뒤 chmod 실패를 전체 실패로 보고, H3 `.failed`에 기동·정상 경로 ping 추가로 D12·D7 위반, H4 정확한 라이브 진단을 generic 문구로 덮음, H5 억제 맵 무한 증가. 2차 지적 G1∼G4는 닫힘 확인. red: 7 테스트 12 실패(드라이버) / green: swift 549(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. 실측: R1-j 5회째 PASS(13.0s), R1-n 재실측 PASS — ping이 `Failed to write to socket`을 돌려준 회차에서도 automation 문구가 나왔다(소켓 존재 시 ping 생략의 근거).
- cold review 4차(2026-08-26, a5eeb4c): 판정 no, 7건 — I1 백업 chmod 실패가 성공으로 보임, I2 백업 이름 예약의 TOCTOU, **I3 cmuxOnly 실측 상태(`.failed`)에서 [Allow Automation]이 비활성 — 복구 경로가 막혀 있었다**, I4 in-flight 불변 부재, I5 stale 소켓·비기본 소켓의 생존성·진단, I6 공백 파일 계약, I7 `runProcess` timeout이 실제 상한이 아님. red: 10 테스트 15 실패(전체 30.1초가 I7의 증거) / green: swift 555(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. 실측: R1-j 6회째 PASS(5.1s), I3·R1-n — 같은 cmuxOnly 상태가 회차에 따라 `.denied`와 `.failed(Failed to write to socket)` 둘로 관측되므로 두 상태 모두에서 버튼이 활성이어야 한다(실측 2회).
- cold review 5차(2026-08-26, bb511c5): 판정 no, 차단 5건 + 비차단 1건 + 드라이버 추가 1건 — J1 교체 부분 실패 시 진짜 백업 삭제(치명), J2 결과 불확실한 `workspace.create` 재시도, J3 정상 종료 경로의 무한 드레인(**드라이버 실측: 타임아웃 테스트 뒤 `sleep 30` PID 잔존**), J4 백업 경고가 한 번 쓰고 잊힘, J5 준비 판정이 다시 소켓 파일 의존, J6 예약 직후 잔재 창, **J7 심링크된 cmux.json에서 [Allow Automation] 실패(드라이버 실측: `NSCocoaErrorDomain Code=4`)**. I3·I4·I6은 닫힘 확인. red: 6 테스트 12 실패(전체 30.1초가 J3의 증거) / green: swift 559(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. 실측(설치본, 드라이버): R1-j 7회째 PASS(7.5s), **J7 심링크 실기기 PASS**(설정 창 [자동화 허용] → 상태줄 `소켓 접근 거부` → `연결 가능`, 링크 유지·target이 automation 획득·백업은 target 디렉터리에 0600 원본 바이트), R1-n 3회째 PASS(0.2s), **J2 회귀 검사 PASS**(cmux 완전 종료 뒤 자동 기동 2.4s, CLI 오류 원문 `Failed to connect to socket … (Connection refused, errno 61)`), **J8 setpgid 20/20 EACCES**(손자 잔존 1 → 2). J7 실측 중 무관한 결함 하나를 발견해 이슈로 남겼다(#59 — 설정 창이 base dir 입력창에 포커스를 준 채 열려 오타 한 글자가 저장까지 간다).

- cold review 6차(2026-08-26, bd01c24): 판정 no, 차단 6건 + 비차단 1건 — L1 파일을 고치지 않고도 백업 경고가 해제됨(이미 automation + cmux 꺼짐에서 재클릭), L2 재시도 마커가 부분 문자열이라 서버가 만든 뒤의 후처리 실패도 재시도(workspace 중복), L3 교체 중간 실패에서 진짜 백업이 0600 보장을 잃음, L4 예약 identity를 `close` 뒤 경로에서 읽음, L5 잘못된 UTF-8 한 바이트가 전체 출력을 빈 문자열로 만듦, L6 마지막 대기 실패 뒤 버퍼 읽기가 데이터 경합, L7 기동·준비 실패 진단 소실(비차단). J5∼J8은 닫힘 확인. red: 8 테스트 11 실패(드라이버) / green: swift 567(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. **green 중 드라이버 실측으로 L2 앵커 결함을 잡았다** — 실제 CLI stderr은 `Error: `로 시작하는데 앵커가 그 접두사를 몰라, 테스트는 통과하면서 실경로의 자동 기동을 막고 있었다. 사용자 cmux를 끄지 않고 `CMUX_SOCKET_PATH`로 두 형태를 재측정했다: `Error: Failed to connect to socket at <path> (Connection refused, errno 61)`(소켓 파일은 있고 listener 없음)과 `Error: Socket not found at <path>`(소켓 파일 없음). 둘 다 접두사 포함 앵커로 고정했고, 테스트 입력도 실측 원문으로 바꿨다(red 3 테스트 4 실패 확인 후 green).
- cold review 7차(2026-08-27, f3e077b): 판정 no, 4건 — **N1 `claude_inputs`가 NUL·개행만 거부해 DEL(U+007F)이 통과, 타이핑되는 바이트라 Backspace로 동작하고 반영 확인은 앞 24자만 보므로 24자 뒤의 DEL은 검사에 걸리지 않은 채 CR이 나가 다른 명령이 조용히 실행된다(cmux 이전부터 있던 결함)**, N2 앵커가 `Error: `를 선택적으로 벗겨 측정되지 않은 무접두사 형태도 재시도로 승인, N3 identity 확인∼경로 삭제/chmod TOCTOU(`funlinkat`은 Swift Darwin에 없음 — 드라이버 실측), N4 `fileExists == false`가 '없음'과 '확인 불가'를 합쳐 EACCES에서 경고가 영구히 사라진다. L3·L5·L6·L7은 닫힘 확인. red: 4 테스트 8 실패(드라이버) / green: 다음 커밋 라운드에 기입. green: swift 571(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. N3은 `funlinkat` 부재(드라이버 실측: `import Darwin; _ = funlinkat` 컴파일 실패, 반면 `O_NOFOLLOW`·`fstat`·`fchmod`는 보인다)를 인정하고 두 갈래로 풀었다 — chmod는 `O_NOFOLLOW` 디스크립터 기반, 삭제는 예약 이름에 8자리 hex를 넣어 경로를 예측 불가로 만들고 identity 검사를 방어 이중화로 남겼다.
- cold review 8차(2026-08-27, 7404ecd): 판정 no, **차단 1건** — N1의 제어 문자 검사가 `trimmingCharacters` 뒤에 있어 가장자리의 TAB·개행이 검사를 빠져나가고, `["\t"]`는 빈 문자열이 되어 성공 응답과 함께 사라진다. N2·N3·N4는 닫힘 확인(N3은 선언된 same-UID 신뢰 모델 안에서). 그 밖의 차단 없음. red: 3 테스트 7 실패(드라이버) / green: 다음 커밋 라운드에 기입.
- cold review 9차(2026-08-27, 38fd8a7): 판정 no, 차단 2건 + 비차단 1건 — **P1 O1이 앱 경계에서만 닫혔고 확장의 `trim()`이 제어 문자를 먼저 지워 버튼 경로를 우회했다**(`["\t"]`는 저장 시점에 소멸, `["\t!echo x"]`는 변조 후 실행), P2 설정 버튼 피드백이 라이브 진단 라벨을 덮어 D13 위반(G3·H4에 이은 3회째 — 소스 감사 테스트로 원천을 막았다), P3 계획 비목표가 축소와 어긋남. O2의 삭제는 죽은 참조 없이 깨끗하다고 확인됨. red: node 222/2 실패 + swift 2 실패(드라이버) / green: swift 542(1 skip)·node 222·build.sh·e2e 9/9, 0 실패. P1은 두 호출부가 `normalizeClaudeInputs` 하나를 쓰게 해 한쪽만 바뀌는 재발을 막았고, P2는 `cmuxFeedbackLabel`을 분리하고 `refresh()`가 그것을 비우게 했다. 소스 감사 테스트가 라이브 라벨 대입을 `refresh()`로 고정한다.

### 테스트 심사

| 테스트 이름 | 고정하는 계획 항목 번호 | 입장 기준 | 같은 계약을 다른 고도에서 또 고정하는 테스트 | 판정 |
| `CmuxConfigHelpTests.testItem22ConfigClipboardFragmentContainsAutomationSetting` | 22 | i: 클립보드 조각 제공을 되돌리면 실패; ii: 사용자가 붙여 넣을 automation/socketControlMode 조각을 정확히 고정; iii: 없음 | 없음 | 유지 |
| `CmuxConfigHelpTests.testItem22ConfigRevealTargetChoosesFileDirectoryOrNothing` | 22 | i: 파일·폴더·없음 대상 선택을 되돌리면 실패; ii: 파일이 있으면 파일을, 파일만 없고 폴더가 있으면 폴더를, 둘 다 없으면 아무것도 열지 않는 비파괴 계약을 고정; iii: 없음 | 없음 | 유지 |
| `CmuxDetectionTests.testItem12CmuxOnlyInstallationSelectsCmux` | 12 | i: cmux 자동 감지 분기를 되돌리면 실패; ii: 네 설치 여부 입력의 cmux 단독 결과를 고정; iii: 없음 | `CmuxDetectionTests.testItem12NoInstalledTerminalFallsBackToITerm`, `testItem12ITermWinsOverCmux`, `testItem12WarpWinsOverCmux`(같은 함수의 다른 우선순위 경계, 중복 아님) | 유지 |
| `CmuxDetectionTests.testItem12NoInstalledTerminalFallsBackToITerm` | 12 | i: 기본 fallback을 되돌리면 실패; ii: 아무 설치도 없을 때 단일 소스가 iTerm을 선택하는 계약을 고정; iii: 없음 | `CmuxDetectionTests.testItem12CmuxOnlyInstallationSelectsCmux`, `testItem12ITermWinsOverCmux`, `testItem12WarpWinsOverCmux`(같은 함수의 다른 우선순위 경계) | 유지 |
| `CmuxDetectionTests.testItem12ITermWinsOverCmux` | 12 | i: 기존 iTerm 우선순위를 바꾸면 실패; ii: 새 cmux가 기존 선택을 선점하지 않는 순서를 고정; iii: 없음 | `CmuxDetectionTests.testItem12CmuxOnlyInstallationSelectsCmux`, `testItem12NoInstalledTerminalFallsBackToITerm`, `testItem12WarpWinsOverCmux`(같은 함수의 다른 우선순위 경계) | 유지 |
| `CmuxDetectionTests.testItem12WarpWinsOverCmux` | 12 | i: 기존 Warp 우선순위를 바꾸면 실패; ii: cmux보다 Warp가 앞서는 순서를 고정; iii: 없음 | `CmuxDetectionTests.testItem12CmuxOnlyInstallationSelectsCmux`, `testItem12NoInstalledTerminalFallsBackToITerm`, `testItem12ITermWinsOverCmux`(같은 함수의 다른 우선순위 경계) | 유지 |
| `CmuxLocalizationTests.testCmuxTerminalErrorsUseAllFiveCatalogs` | 4 | i: cmux 오류 Localization을 되돌리면 실패; ii: 5개 카탈로그에서 raw key가 없고 RPC method payload가 보존되는 계약을 고정; iii: 없음 | `CmuxTests.testCmuxRPCFailuresDistinguishSocketDenialAndMethod`(Core 분류, 다른 고도) | 유지 |
| `CmuxLocalizationTests.testCmuxSocketStatusLabelsUseAllFiveCatalogs` | 13 | i: 5상태 라벨 카탈로그를 되돌리면 실패; ii: 모든 상태가 5로케일의 값으로 그려지는 i18n 계약을 고정; iii: 첫 게이트의 상태 라벨 포함 관계 결함은 별도 카탈로그 게이트로 해소됨 | `SetupWindowLayoutTests.testItem14CmuxSelectionShowsSocketSectionAndUsesStatusState`(카드 조합, 다른 고도) | 유지 |
| `CmuxLocalizationTests.testItem14CmuxCardStringsExistInAllFiveCatalogs` | 14 | i: 카드·버튼 문자열을 되돌리면 실패; ii: 새 UI 키 전부가 5로케일에 존재해야 하는 원칙 16을 고정; iii: 없음 | `SetupWindowLayoutTests.testItem14CmuxSelectionShowsSocketSectionAndUsesStatusState`(UI 조합, 다른 고도) | 유지 |
| `SetupWindowLayoutTests.testPipelineNodesAreLocalized` | 14 | i: cmux pipeline node와 상태 인자를 되돌리면 실패; ii: 4개 터미널 노드의 label/detail이 카탈로그 프레임이고 로케일별로 달라지는 오라클을 고정; iii: 없음 | `CmuxLocalizationTests.testItem14CmuxCardStringsExistInAllFiveCatalogs`(키 존재, 다른 고도) | 유지 |
| `SetupWindowLayoutTests.testItem14CmuxSelectionShowsSocketSectionAndUsesStatusState` | 14 | i: cmux 라디오·섹션·상태 매핑을 되돌리면 실패; ii: cmux 선택 시 카드가 보이고 denied가 err 상태의 label/detail로 연결되는 UI 조합을 고정; iii: 없음 | `CmuxLocalizationTests.testCmuxSocketStatusLabelsUseAllFiveCatalogs`, `testItem14CmuxCardStringsExistInAllFiveCatalogs`(카탈로그, 다른 고도) | 유지 |
| `CmuxTests.testCmuxCLICandidatePathsUseBundleLocationsBeforePATH` | 2 | i: 후보 생성 순서나 번들 경로를 되돌리면 실패; ii: D7의 번들 우선 후보와 PATH 순서를 바이트 단위로 고정; iii: 없음 | `CmuxTests.testFindCmuxCLIReturnsTheFirstExecutableCandidate`(선택 함수, 다른 순수 계약) | 유지 |
| `CmuxTests.testFindCmuxCLIReturnsTheFirstExecutableCandidate` | 2 | i: 실행 가능 후보 선택을 되돌리면 실패; ii: 감지와 실행이 같은 `findCmuxCLI`에서 첫 실행 가능 경로를 고르는 계약을 고정; iii: 없음 | `CmuxTests.testCmuxCLICandidatePathsUseBundleLocationsBeforePATH`(후보 목록, 다른 순수 계약) | 유지 |
| `CmuxTests.testCmuxSocketPathOnlyReportsAnExistingSocket` | 2·13 | i: 소켓 생존 판정 구현을 되돌리면 실패; ii: 정해진 상태 경로는 존재할 때만 반환하고 CLI 인자로 쓰지 않는 계약을 고정; iii: 소켓 부재가 모드와 무관하게 notRunning이 되는 관찰을 지지 | `CmuxTests.testItem13CmuxSocketStatusSocketAbsenceWinsOverPingOutput`(분류 함수, 다른 고도) | 유지 |
| `CmuxTests.testCmuxRPCMethodNamesAreTheFourSupportedMethods` | 3 | i: 4개 상수를 제거·변경하면 실패; ii: wire method 이름을 리터럴로 고정하는 RPC 계약을 고정; iii: D8에서 키 전송 메서드를 제거한 변경을 특성화 | `CmuxTests`의 각 RPC 파라미터 테스트(메서드 값이 아니라 조립, 같은 고도에서 중복 아님) | 유지 |
| `CmuxTests.testCmuxRPCArgumentsAreASCIIAndPreserveJSONValues` | 3 | i: ASCII argv 직렬화나 JSON 의미 보존을 되돌리면 실패; ii: 리터럴 `\n`, CR, 한글 NFC 바이트, 512바이트 초과 값을 JSON으로 보존하고 argv 전체를 ASCII로 만드는 계약을 고정; iii: Foundation argv NFD 재인코딩 결함을 특성화 | `CmuxTests.testItem10CmuxBodyUsesSurfaceSendTextWithoutChangingIt`(RPC operation 조립, 다른 고도) | 유지 |
| `CmuxTests.testCmuxRPCResponseParsesWorkspaceIdentifiers` | 3 | i: workspace·surface 응답 파서를 되돌리면 실패; ii: R1-b의 UUID·ref·group 필드와 surface_id 직접 획득 계약을 고정; iii: 없음 | `CmuxTests.testItem5CmuxWorkspaceIdentifiersRequireWorkspaceAndSurface`(실행 전 필수성, 다른 고도) | 유지 |
| `CmuxTests.testCmuxRPCResponseParsesQueuedAndText` | 3 | i: queued/text 응답 파서를 되돌리면 실패; ii: send queued와 read text의 응답 schema를 고정; iii: queued를 유실로 오해하지 않는 R1-k 관찰의 데이터 표면을 특성화 | `CmuxTests.testItem11CmuxScreenTextRequiresTheTextField`(read 결과 사용, 다른 고도) | 유지 |
| `CmuxTests.testCmuxRPCFailuresDistinguishSocketDenialAndMethod` | 3·4 | i: Access denied와 method 포함 오류 분류를 되돌리면 실패; ii: 소켓 거부와 RPC 실패를 App Localization으로 넘기는 경계와 method payload를 고정; iii: socketDenied 처방 오진 및 rpcFailed 형식 불일치가 승계된 결함으로 특성화됨 | `CmuxLocalizationTests.testCmuxTerminalErrorsUseAllFiveCatalogs`(문구, 다른 고도) | 유지 |
| `CmuxTests.testItem5CmuxRunParametersUseFocusOnlyAndPreserveCommandCR` | 5 | i: workspace.create/send 인자 조립을 되돌리면 실패; ii: focus:true만 보내고 window_id·cwd를 생략하며 명령 뒤 CR만 붙이는 D3 계약을 고정; iii: 없음 | `CmuxTests.testItem10CmuxCRUsesOneSurfaceSendTextCR`(전달 operation, 다른 고도) | 유지 |
| `CmuxTests.testItem5CmuxWorkspaceIdentifiersRequireWorkspaceAndSurface` | 5 | i: surface_id 없는 생성 응답을 성공으로 강등하면 실패; ii: workspace_id와 surface_id가 둘 다 있어야 `TerminalSessionHandle`을 만들 수 있다는 조용한 성공 금지 계약을 고정; iii: R1-b의 surface_id 직접 응답 및 원칙 9를 특성화 | `CmuxTests.testCmuxRPCResponseParsesWorkspaceIdentifiers`(응답 schema, 다른 고도) | 유지 |
| `CmuxTests.testItem9CmuxTTYNameParsesTheMatchingSurface` | 9 | i: debug.terminals의 surface별 tty 파서를 되돌리면 실패; ii: 일치 surface의 basename을 `/dev/` 경로로 바꾸는 UUID 명시 계약을 고정; iii: R1-f의 push tty 실측을 특성화 | `CmuxTests.testItem9CmuxTTYNameReturnsNilForNullTTY`, `testItem9CmuxTTYNameReturnsNilForMissingSurface`, `testItem9CmuxTTYNameReturnsNilForInvalidJSON`(같은 파서의 실패 경계) | 유지 |
| `CmuxTests.testItem9CmuxTTYNameReturnsNilForNullTTY` | 9 | i: tty null 폴백을 되돌리면 실패; ii: 셸 통합이 tty를 주지 않을 때 nil로 안전하게 입력을 포기하는 게이트를 고정; iii: R1-f의 pty 없음 관찰을 특성화 | `CmuxTests.testItem9CmuxTTYNameParsesTheMatchingSurface`(정상 파싱, 같은 파서의 다른 경계) | 유지 |
| `CmuxTests.testItem9CmuxTTYNameReturnsNilForMissingSurface` | 9 | i: surface UUID 매칭을 완화하면 실패; ii: 다른 surface의 tty를 재사용하지 않는 원칙 15를 고정; iii: 없음 | `CmuxTests.testItem9CmuxTTYNameParsesTheMatchingSurface`(정상 매칭, 같은 파서의 다른 경계) | 유지 |
| `CmuxTests.testItem9CmuxTTYNameReturnsNilForInvalidJSON` | 9 | i: 파싱 실패를 입력 허용으로 바꾸면 실패; ii: 비JSON debug 응답은 nil로 닫는 3중 게이트 계약을 고정; iii: 없음 | `CmuxTests.testItem9CmuxTTYNameParsesTheMatchingSurface`(정상 파싱, 같은 파서의 다른 경계) | 유지 |
| `CmuxTests.testItem10CmuxClearInputIsTwoSendTextCallsCtrlUThenBackspace` | 10 | i: cmux clear operation을 되돌리면 실패; ii: `surface.send_text`로 0x15와 0x7F를 별도 호출하는 순서·surface_id를 고정; iii: kitty protocol 아래 키 이벤트가 무효였던 R1-j 결함을 특성화 | `ClaudeControlKeyTests.testControlKeysAreTheExpectedBytes`(raw byte oracle, 다른 고도) | 유지 |
| `CmuxTests.testItem10EveryCmuxByteGoesThroughSendText` | 10 | i: marker·clear·본문·CR의 cmux operation 배선을 되돌리면 실패; ii: 모든 operation method가 `surface.send_text`이고 clear만 두 operation이라는 D8 계약을 고정; iii: 없음 | `CmuxTests.testItem10CmuxClearInputIsTwoSendTextCallsCtrlUThenBackspace`(clear 세부 조립, 같은 고도지만 전체 경로와 중복 아님) | 유지 |
| `ClaudeSubmissionSurvivalTests.testItem10KittyKeyboardModeLeavesMarkerRemnantAndStopsBeforeTyping` | 10·8 | i: D9 잔재 판정과 delivery 중단을 되돌리면 실패; ii: 본문을 marker 잔재 위에 타이핑·제출하지 않고 cleanup으로 끝내는 오라클을 고정; iii: R1-j transcript 결함과 kitty flag 1 아래 ctrl+u 무효를 FakeClaudeSession knob으로 특성화 | `ScreenReflectionTests.testScreenShowsMarkerErasedRejectsAnElevenCharacterRemnant`(순수 판정, 다른 고도) | 유지 |
| `ScreenReflectionTests.testScreenShowsMarkerErasedRejectsAnElevenCharacterRemnant` | 8 | i: D9 순수 함수의 6자 window 검사를 되돌리면 실패; ii: 12자 marker의 11자 잔재를 false로 판정하는 pane-proof oracle을 고정; iii: R1-j의 한 글자 삭제 사고를 특성화 | `ClaudeSubmissionSurvivalTests.testItem10KittyKeyboardModeLeavesMarkerRemnantAndStopsBeforeTyping`(Fake delivery, 다른 고도) | 유지 |
| `ScreenReflectionTests.testScreenShowsMarkerErasedAcceptsAnEmptyScreen` | 8 | i: D9가 실제 빈 화면을 erased로 인정하지 못하면 실패; ii: before·after 모두 marker가 없을 때 true인 경계를 고정; iii: 없음 | `ScreenReflectionTests.testScreenShowsMarkerErasedAcceptsAnUnchangedExistingOccurrence`(기존 occurrence, 다른 입력 경계) | 유지 |
| `ScreenReflectionTests.testScreenShowsMarkerErasedIgnoresUnrelatedText` | 8 | i: marker window count 외 화면 변화에 민감해지면 실패; ii: unrelated text가 추가돼도 marker 잔재 없음은 true인 계약을 고정; iii: 없음 | `ScreenReflectionTests.testScreenShowsMarkerErasedAcceptsAnEmptyScreen`(빈 화면, 다른 경계) | 유지 |
| `ScreenReflectionTests.testScreenShowsMarkerErasedAcceptsAnUnchangedExistingOccurrence` | 8 | i: before에 이미 있던 marker를 after에서 한 번 유지하는 경우를 잔재로 오인하면 실패; ii: 각 window count가 baseline과 같으면 true인 계약을 고정; iii: 없음 | `ScreenReflectionTests.testScreenShowsMarkerErasedAcceptsAnEmptyScreen`(빈 화면, 다른 경계) | 유지 |
| `CmuxTests.testItem10CmuxBodyUsesSurfaceSendTextWithoutChangingIt` | 10 | i: 본문을 send_text로 보내는 operation을 되돌리면 실패; ii: 본문을 그대로 보내고 CR·제어키로 변환하지 않는 계약을 고정; iii: Foundation 비ASCII 보존 요구를 cmux operation에서 특성화 | `CmuxTests.testCmuxRPCArgumentsAreASCIIAndPreserveJSONValues`(최종 argv 직렬화, 다른 고도) | 유지 |
| `CmuxTests.testItem10CmuxCRUsesOneSurfaceSendTextCR` | 10 | i: CR 전송 operation을 되돌리면 실패; ii: CR을 `surface.send_text`로 한 번만 보내고 개행을 덧붙이지 않는 원칙 4를 고정; iii: R1-i의 0x0D 실측을 특성화 | `ClaudeControlKeyTests.testControlKeysAreTheExpectedBytes`(raw byte oracle, 다른 고도) | 유지 |
| `CmuxTests.testItem11CmuxScreenTextRequiresTheTextField` | 11 | i: surface.read_text 파라미터·text 필드 처리를 되돌리면 실패; ii: text가 없거나 RPC 오류인 화면은 nil이며 폴백하지 않는 D5 계약을 고정; iii: 차가운 surface의 internal_error를 확인 실패로 처리하는 관찰을 특성화 | `CmuxTests.testCmuxRPCResponseParsesQueuedAndText`(응답 schema, 다른 고도) | 유지 |
| `CmuxTests.testItem13CmuxSocketStatusIncludesNotInstalledState` | 13 | i: notInstalled 상태를 제거하면 컴파일·패턴 매칭이 실패; ii: CLI 부재와 소켓 상태를 구분하는 5상태 enum 계약을 고정; iii: 없음 | `CmuxLocalizationTests.testCmuxSocketStatusLabelsUseAllFiveCatalogs`(상태 라벨, 다른 고도) | 유지 |
| `CmuxTests.testItem13CmuxSocketStatusSocketAbsenceWinsOverPingOutput` | 13 | i: 소켓 부재 우선 분류를 되돌리면 실패; ii: ping PONG이어도 socketExists=false면 notRunning인 계약을 고정; iii: 꺼짐과 거부를 ping만으로 구별할 수 없다는 D1 결함을 특성화 | `CmuxTests.testCmuxSocketPathOnlyReportsAnExistingSocket`(경로 존재 판정, 다른 고도) | 유지 |
| `CmuxTests.testItem13CmuxSocketStatusClassifiesAccessDenied` | 13 | i: Access denied 대소문자 분류를 되돌리면 실패; ii: stdout·stderr의 거부 문구를 denied로 분류하는 프로브 계약을 고정; iii: socketDenied가 소켓 부재 처방이 아니라 automation 모드 문제라는 수정의 입력을 특성화 | `CmuxLocalizationTests.testCmuxSocketStatusLabelsUseAllFiveCatalogs`(라벨, 다른 고도) | 유지 |
| `CmuxTests.testItem13CmuxSocketStatusClassifiesSuccessfulPong` | 13 | i: exit 0+PONG reachable 분류를 되돌리면 실패; ii: 라이브 ping reachable 상태를 고정; iii: 드라이버 실환경 PONG 대조의 순수 입력을 특성화 | `CmuxLocalizationTests.testCmuxSocketStatusLabelsUseAllFiveCatalogs`(라벨, 다른 고도) | 유지 |
| `CmuxTests.testItem13CmuxSocketStatusPreservesFailureSummary` | 13 | i: 기타 실패의 원문 요약을 버리면 실패; ii: failed(String)가 사용자가 볼 원문을 보존하는 계약을 고정; iii: 없음 | `CmuxLocalizationTests.testCmuxTerminalErrorsUseAllFiveCatalogs`(오류 문구, 다른 고도) | 유지 |
| `TerminalIdentifierTests.testRawValuesAreTheStoredIdentifiers` | 1 | i: cmux enum/rawValue를 되돌리면 실패; ii: 저장 식별자 4개 리터럴과 `allCases.count == 4`라는 단일 소스를 고정; iii: 식별자 테스트 중복 제거 후 남긴 정본 오라클 | 없음 — `CmuxTests`에 식별자 중복 없음 | 유지 |
| `TerminalIdentifierTests.testStoredValueParsingFallsBackToITerm` | 1 | i: cmux 저장값 파싱을 되돌리면 실패; ii: 네 식별자와 미지 값의 iTerm fallback을 한 파싱 지점에서 고정; iii: 없음 | `TerminalIdentifierTests.testRawValuesAreTheStoredIdentifiers`(rawValue 목록, 다른 계약) | 유지 |
| `PaneProofRoutingTests.testItem8OnlyWarpNeedsPaneProof` | 8 | i: `.cmux(surfaceID:workspaceID:cliPath:)` 또는 `screenNeedsPaneProof`를 되돌리면 실패; ii: cmux는 surface UUID 오라클로 pane proof가 false이고 Warp만 true라는 라우팅 계약을 고정; iii: 없음 | 없음 — 기존 터미널 handle oracle을 한 테스트에서 함께 고정하며 cmux 중복 없음 | 유지 |

## 열린 질문 → 결정 (2026-08-23, 사용자·드라이버)

1. **수용 + 확장** — automation 전제로 구현하고, automation의 의미(같은 uid 노출 확대)는 README·설정 창에 적는다 — 사용자 승인. 2026-08-27 사용자 결정으로 설정 창 버튼은 파일을 쓰지 않고 설정 조각을 복사해 기존 파일 또는 폴더를 여는 도움말 동작으로 축소했다.
2. 소멸(1 수용). AppleScript 대안(D6)은 기록으로만 남는다.
3. **[교체 — D8, 2026-08-26]** CR·Ctrl+U·Backspace 모두 `surface.send_text`로 보낸다. CR은 `"\r"` 한 호출, 클리어는 `"\u{15}"` 다음 `"\u{7F}"` 두 별도 호출이다. raw 셸의 키 측정은 claude TUI에 적용되지 않았고, D8의 Claude Code 실기기 측정으로 기존 답을 교체한다.
4. **실측 승인** — 안전 조건 그대로(우리가 만든 workspace UUID만 지목, 사용자 pane은 조회 금지, 종료 시 close). cmux.json 직접 편집은 사용자·드라이버 실측으로만 수행하고, 앱 버튼은 파일을 쓰지 않는다. 실측 후 automation 모드는 **켠 채로 둔다**(사용자가 원하는 최종 상태).
5. **검사 목록 항목으로만** 둔다. 설정 창 버전 경고는 과설계라 비목표에 명시.

## R1 실측 설계 (안전 조건 포함)

전제: cmux는 **사용자가 이미 띄워 둔 인스턴스**를 쓴다. 모든 조작은 **우리가 방금 만든 workspace의 UUID를 명시**해서만 하고, 사용자 pane의 UUID는 조회하지 않는다. 정리는 `workspace.close`로 우리 것만.

| # | 확정할 것 | 방법 | 안전 조건 |
|:--|:--|:--|:--|
| R1-a | **[완료]** `automation` 모드로 바꾸면 외부에서 붙는가 → **붙는다**(2026-08-23 PONG, 2026-08-26 재확인 PONG) | `cmux ping` | 모드 변경은 cmux.json 직접 편집으로 수행됨(사용자 승인, `.bak`: `cmux.json.20260823-160057.bak`). automation 유지 중 |
| R1-b | **[완료]**: `workspace.create {"focus":false,"title":"tc-probe-a"}` 응답에 `workspace_id`·`surface_id`·`window_id`(각 UUID)와 `*_ref`·`group_*` 가 실린다 — surface_id를 별도 조회 없이 응답에서 바로 얻는다 | `workspace.create` 응답 확인(드라이버 실측 2026-08-26) | 새 workspace만 생긴다. 끝나면 닫는다 |
| R1-c | **[완료·해소]**: R1-b 응답에 surface_id가 있으므로 `surface.list` 폴백 불필요 — 항목·상수에 추가하지 않는다 | R1-b 응답과 항목 3 API 대조(드라이버 실측 2026-08-26) | workspace_id를 우리 것으로 명시 |
| R1-d | **[완료]**: workspace 2개에서 A에만 난수 타이핑 후 B의 surface_id로 read_text → 난수 없음(CLEAN), A → 있음. surface 단위 정확성 확정 | 두 workspace의 `surface.read_text` 대조(드라이버 실측 2026-08-26) | 둘 다 우리 것. 사용자 탭을 포커스하지 않는다 |
| R1-e | **[완료]**: 선택되지 않은(백그라운드) live surface에 send_text → `queued:false`, read_text → 방금 보낸 난수 확인. **사용자가 다른 탭으로 전환해도 전달이 계속된다**(Warp와 다른 등급) — D5 채택(screenNeedsPaneProof=false) 실측 확정 | 백그라운드 surface send/read와 탭 전환(드라이버 실측 2026-08-26) | 위와 같음 |
| R1-f | **[완료]**: focus:false로 만든 비가시 workspace는 65초가 지나도 `tty:null`·`runtime_surface_ready:false`·`ghostty_surface_ptr:nil` — **pty가 아직 없는 상태**(2026-08-23 tty null 관찰의 원인). focus:true 생성은 수십 ms 안에 materialize되어 send_text가 `queued:false`로 즉시 들어가고, tty는 `debug.terminals`에 채워진다(실측 ttys020 등). cold였던 surface도 웜업되면 tty가 채워진다. → 항목 9의 폴링 설계 유지, 폴링 타임아웃 안에 안 채워지면 claude 입력 포기(D4 폴백) | `cmux rpc debug.terminals`를 생성 상태별 대조(드라이버 실측 2026-08-26) | 출력이 전체를 담으므로 **우리 행만 파싱**한다 |
| R1-g·R1-h | **[완료]** 창 2개(W1 사용자 창, W2 드라이버가 `new-window`·`focus-window`로 생성·활성화) 상태에서 앱 요청 → workspace가 W2(마지막 활성 창)에 생성. D3 확인. W2는 `close-window`로 닫음. | 창 2개에서 마지막 활성 창을 바꾼 뒤 앱 경유 workspace 생성(드라이버 실측 2026-08-26) | 우리가 만든 W2와 workspace만 닫는다 |
| R1-i | **[정정]**: 우리 workspace에서 `stty raw -echo; cat -v` 후 send_text `"\r"` → `^M` 하나, send_key `ctrl+u` → `^U`(0x15), send_key `backspace` → `^?`(0x7F)였으나 이 측정은 raw 셸(kitty protocol 꺼짐)에서였다. **정정(2026-08-26)**: claude(2.1.246, kitty flag 1 활성) 아래에서는 `send_key ctrl+u`가 무효, `send_key backspace`만 1자 삭제 — R1-j 결함의 원인. claude 아래 재측정: `send_text \u{15}` 비움, `send_text \u{7F}` 별도 호출로 `!` 제거, 한 호출 2바이트는 `!` 잔류. 채택안을 D8로 교체. | raw 셸 및 실행 중 claude TUI의 바이트 실측(드라이버 실측 2026-08-26) | 우리 workspace 전용 |
| R1-j | **[완료]**: 앱 경로 실측(설치본, 17:34) — 로그는 성공(tab 0.6s → tty 1.5s → claude ready 2.2s → 반영 5.6s → CR 6.0s → 완료 6.3s)이나 transcript에는 `tctqr20ckbi!echo tc-r1j-input-ok`(마커 11자 잔재 + 본문, 평문 제출). 원인 R1-i 정정 참조. D8·D9 적용 후 재실측 완료. **재실측(2026-08-26, D8·D9 적용 빌드, 설치본 sha256 일치)**: PASS — transcript에 `<bash-input>echo tc-r1j2-input-ok</bash-input>` → `<bash-stdout>tc-r1j2-input-ok</bash-stdout>`(shell mode 제출·실행). 로그: tab 0.2s → tty 1.4s → claude ready 1.9s → pane proof passed(2/12) 5.7s → 반영 6.0s → CR 6.4s → 완료 6.7s. 첫 send_text는 queued=true였고 명령은 실행됨(R1-k 재확인). | 설치본 앱 경로와 Claude transcript 대조(드라이버 실측 2026-08-26) | D8·D9 수리 후 재실측 |
| R1-k | **[완료]**: cold surface에 send_text → `queued:true`. **queued는 유실이 아니다** — surface가 웜업되면 flush되어 pty에 들어간다(실측: 셸 배너보다 먼저 들어가 프롬프트 라인버퍼에 재등장). 항목 10의 queued 로깅 사유가 이것이다: 보냈다고 착각한 바이트가 나중에 도착할 수 있다 | cold surface send_text 후 웜업·pty 확인(드라이버 실측 2026-08-26) | 우리 workspace 전용 |
| R1-l | **[완료]**: `workspace.create` 58∼110ms + `surface.send_text` 38ms(각 time 실측) — WezTerm 왕복과 같은 수준, execQueue 예산 안 | 각 RPC 응답의 `time` 기록(드라이버 실측 2026-08-26) | 측정만 |
| R1-m | **[완료]** cmux.json 변경이 재시작 없이 반영되는가 → **반영된다**(2026-08-23 실측: 기록 직후 외부 ping이 거부→PONG으로 바뀜, 재시작 없음) | 실측 완료 | 파일 워처의 라이브 반영이 정본이다. 현재 버튼은 설정 조각을 복사하고 기존 파일 또는 폴더를 열어 사용자가 직접 수정하게 하며, `cmux reload-config`는 cmuxOnly에서 외부 호출이 거부되므로 수단이 아니다(「재개」) |
| R1-n | **[완료]** automation을 끈 상태(cmuxOnly, ping이 Access denied)에서 앱 요청 → 0.2초에 `{success:false}`와 automation 안내 문구. 기동·timeout 오진 없음 | 설치본 앱 경로 + cmux.json 모드 토글(드라이버 실측 2026-08-26) | 실측 후 automation으로 원복, 파일 0600 확인 **재실측(H3 적용, 2026-08-26)**: ping이 `Failed to write to socket`이던 회차에도 0.2초에 automation 문구 — `workspace.create`의 거부 분류가 ping보다 정확하다. **재실측(I3 적용)**: 같은 상태의 분류가 회차에 따라 `.denied`/`.failed`로 갈린다 — 버튼 활성 조건을 '`reachable`·`notInstalled`가 아닌 모든 상태'로 넓힌 근거. |
