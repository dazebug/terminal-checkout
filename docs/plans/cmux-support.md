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
3. cmux 제어 소켓에 외부에서 붙기 위한 전제(socket control mode = `automation`)가 앱 설정 창·README에 **명시적 상태**로 드러나고, **설정 창 버튼 하나로 앱이 그 옵션을 켤 수 있으며**(D1-b — cmux.json 기록), 전제가 없을 때 실패가 조용히 성공으로 보이지 않는다.
4. iTerm2·WezTerm·Warp의 산출 경로가 그대로다(케이스 추가로 생긴 switch 확장 외에 기존 갈래의 동작 변경 없음).
5. `docs/new-terminal-checklist.md`의 §1 표를 빠짐없이 덮고, cmux 고유의 실측 항목이 §2에 추가된다.

## 비목표 — 건드리지 않는다

- **cmux의 UserDefaults·비밀번호 파일을 우리가 만지지 않는다.** 비밀번호는 번들 CLI가 스스로 찾으므로(D1) 우리 코드가 만질 이유가 없다. 설정 파일(`~/.config/cmux/cmux.json`)은 **예외 하나만** 쓴다 — 설정 창 버튼으로 `automation.socketControlMode`를 기록하는 갈래(D1-b, 사용자 지시 2026-08-23). 그 외에는 읽지도 쓰지도 않는다 — 상태 판정은 살아 있는 프로브(`cmux ping`)로 한다
- cmux의 **agent-session surface**(`new-surface --type agent-session --provider claude`)·browser·simulator·`ssh`/`mosh`/`vm` 계열: 우리 명령 모델은 "셸에 한 줄"이고 그 위에서 claude가 뜬다. cmux의 네이티브 agent 세션은 tty·게이트 3겹이 성립하지 않는다
- cmux **workspace group·layout·todo·sidebar·notification**: 새 탭 하나를 만드는 것이 우리 계약이다
- **확장(JS) 쪽 동작**: 확장은 터미널을 모르고 알 수단도 두지 않는다(CLAUDE.md). `extension/manifest.json`의 description 문구만 바뀐다
- 기존 3개 터미널의 실행·전달 경로: switch가 컴파일 에러로 드러내는 자리에 케이스를 더하는 것 외에 손대지 않는다
- cmux를 우리가 대신 설치하는 것. socket mode 변경도 **설정 창 버튼의 명시적 클릭으로만** 한다 — 설치 스크립트·앱 기동 중 자동 변경은 하지 않는다(다른 앱의 보안 관련 설정이므로 클릭이 동의다)
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

**[채택 확장 — D1-b, 사용자 지시 2026-08-23] 앱이 옵션을 켜는 수단을 제공한다.** 지시 원문: "cmux의 옵션이 automation인 경우를 전제로 구현하고, 앱에서는 해당 옵션을 켜도록 하는것을 계획에 추가해". 설정 창 「cmux 소켓 제어」 카드의 버튼 하나가 `~/.config/cmux/cmux.json`에 `"automation": {"socketControlMode": "automation"}`을 기록한다. 조건:

1. 쓰기 전 타임스탬프 `.bak` 백업(cmux CLI 자신의 Agent Help가 권고하는 절차)
2. **명시적 버튼으로만 발동** — 설치·기동 중 자동 변경 금지
3. 기존 파일의 주석·다른 키 보존 — JSONC라 파싱-재직렬화 금지, **텍스트 삽입 편집**으로 한다. 비주석 `automation` 키가 이미 있으면 값만 교체, 파일이 없으면 최소 JSON 생성. 편집 로직은 순수 함수로 떼어 단위 테스트로 고정
4. 적용 확인은 `cmux ping` 라이브 프로브 — 파일 변경이 자동 반영되지 않으면(→ R1-m) 버튼이 cmux 재시작 안내를 띄운다

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
| 키 전송 | `surface.send_key` | `key`·`surface_id` | `CLI/cmux.swift:5259-5266` |
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

**[남는 위험]** `rpc`는 "raw v2 method" 탈출구다. 메서드 이름·파라미터가 버전 사이에 바뀔 수 있다(cmux는 0.64.x로 빠르게 움직인다). 완화: 메서드 이름을 한 자리 상수로 모으고, 실패 로그에 메서드 이름을 남기고, 검사 목록에 "cmux 버전이 오르면 rpc 메서드 5개 확인" 항목을 넣는다.

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

## 작업 항목

| # | 항목 | 상태 | 근거 (무엇을 실행해 무엇이 나오면 claimed인가) | 의존 | 라운드 |
|:--|:--|:--|:--|:--|:--|
| 1 | `Terminal`에 `cmux` 케이스 + `TerminalIdentifierTests`에 rawValue 리터럴과 `allCases.count` 4 | cleared | `TerminalIdentifierTests`에 4개 rawValue 리터럴·`allCases.count == 4`를 추가하고, 컴파일 switch 구멍은 R1 라운드 로그에 기록했다. 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 2 | `findCmuxCLI()`·`cmuxSocketPath()` (Core) | cleared | `CmuxTests.testCmuxCLICandidatePathsUseBundleLocationsBeforePATH`, `testFindCmuxCLIReturnsTheFirstExecutableCandidate`, `testCmuxSocketPathOnlyReportsAnExistingSocket`로 후보 순서·생존 소켓 판정을 고정했다(실환경 게이트는 드라이버). 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 3 | `cmuxRPC(cli:method:params:)` + 메서드 이름 상수 5개(`workspace.create`·`surface.send_text`·`surface.send_key`·`surface.read_text`·`debug.terminals`) | cleared | `CmuxTests`의 메서드 상수·ASCII argv·JSON 의미 보존·workspace/send/read 응답 파싱 테스트로 고정했다. CLI stdin 경로가 없어 `\uXXXX` JSON argv를 채택한 근거는 D2에 기록했다. 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 4 | `TerminalError`에 `cmuxNotFound`·`cmuxSocketDenied`·`cmuxRPCFailed` — 소켓 거부를 **구분되는 문구**로 | cleared | `CmuxTests.testCmuxRPCFailuresDistinguishSocketDenialAndMethod`와 `CmuxLocalizationTests.testCmuxTerminalErrorsUseAllFiveCatalogs`로 분류·5로케일 경로를 고정했다(실제 relay 왕복은 드라이버). 재실행(드라이버): swift test 493(1 skip)·node 220, 0 실패. toggle red는 신규 심볼 참조라 구현 제거 시 컴파일 실패로 성립. | | R1 |
| 5 | `runInCmux(_ command: String) throws -> TerminalSessionHandle` — 소켓 없으면 인자 없는 `open -b com.cmuxterm.app` + 폴링 → `workspace.create`(focus true) → `surface.send_text`로 `command+"\r"` | cleared | 순수 함수·인자 조립 단위 테스트 + 드라이버가 2026-08-26 동일 rpc 시퀀스를 실측(workspace.create focus:true 58∼110ms → surface.send_text 38ms queued:false → 명령 실행 확인: 리다이렉트 파일 생성). 앱 경유 최종 실측은 R1-j(항목 21). 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | `3(cmuxRPC 계약)` | |
| 6 | `cmuxWorkspaceCreateAttempts(windowID:)` 순수 함수 + 테스트 — **R1-g가 통과하면 `dropped`** | todo | 단위 테스트 + 창 2개 실측 | | |
| 7 | `runInTerminal` switch에 `.cmux` | cleared | `runInTerminal`의 `.cmux`가 `return try runInCmux(command)`으로 연결된다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | | |
| 8 | `TerminalSessionHandle`에 `.cmux(surfaceID:workspaceID:cliPath:)` + `screenNeedsPaneProof` 갈래(false) | cleared | `testItem8OnlyWarpNeedsPaneProof`가 `.cmux`·`.warp`·기존 세 handle의 oracle을 고정하고, cmux handle을 `surfaceID`·`workspaceID`·`cliPath`와 함께 저장한다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | | |
| 9 | `deliverClaudeInputs`의 tty 갈래 — `debug.terminals` 폴링 + `cmuxTTYName(debugTerminalsJSON:surfaceID:)` 순수 파서 | cleared | `testItem9CmuxTTYNameParsesTheMatchingSurface`, `testItem9CmuxTTYNameReturnsNilForNullTTY`, `testItem9CmuxTTYNameReturnsNilForMissingSurface`, `testItem9CmuxTTYNameReturnsNilForInvalidJSON`로 파서를 고정하고, cmux 갈래는 유한 폴링 타임아웃에 입력을 포기한다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | `3(cmuxRPC 계약)` | |
| 10 | `sendKeys`의 `case .cmux` — 텍스트·CR은 `surface.send_text`, Ctrl+U는 `surface.send_key ctrl+u`. `queued` 로깅. claudeClearInputKey는 #36 이후 Ctrl+U(0x15)+Backspace(0x7F) 2바이트다 — cmux 갈래는 send_key `ctrl+u` 뒤 send_key `backspace`로 매핑한다(R1-i에서 두 키의 바이트 정확성 실측 완료). 바이트 시퀀스를 그대로 send_text로 보내지 않는 이유는 D2(원시 텍스트 경로의 제어문자 필터 미확정)와 같다. | cleared | `testItem10CmuxClearInputUsesCtrlUThenBackspace`, `testItem10CmuxBodyUsesSurfaceSendTextWithoutChangingIt`, `testItem10CmuxCRUsesOneSurfaceSendTextCR`가 세 입력의 메서드·파라미터와 CR 보존을 고정한다. `sendKeys`의 cmux 갈래는 RPC 성공을 확인하고 `queued:true`만 값 그대로 로그한다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | `3(cmuxRPC 계약)` | |
| 11 | `screenText`의 `case .cmux` — `surface.read_text` | cleared | `testItem11CmuxScreenTextRequiresTheTextField`가 `surface_id` 파라미터와 `text` 필드·필드 없음의 nil을 고정한다. cmux 갈래는 RPC 실패·필드 없음에서 nil이며 다른 화면 폴백을 만들지 않는다. 재실행(드라이버): swift 502(1 skip)·node 220·build.sh·e2e 9/9, 0 실패. | `3(cmuxRPC 계약)` | |
| 12 | `Settings.terminal` 자동 감지에 cmux 한 줄(맨 뒤) | cleared | `CmuxDetectionTests.testItem12CmuxOnlyInstallationSelectsCmux`, `testItem12NoInstalledTerminalFallsBackToITerm`, `testItem12ITermWinsOverCmux`, `testItem12WarpWinsOverCmux`가 순수 우선순위 함수를 고정한다. `Settings.terminal`은 iTerm → WezTerm → Warp → cmux 순으로 같은 함수에 설치 판정을 넣는다. 재실행(드라이버): swift 512(1 skip)·node 220, 0 실패. 실환경 reachable 실측: `cmux ping` → PONG, exit 0. | | |
| 13 | `PermissionChecker.isCmuxInstalled` + `cmuxSocketStatus()` 라이브 프로브(`cmux ping`) | cleared | `CmuxTests`의 5개 `testItem13CmuxSocketStatus...`가 notInstalled·notRunning(소켓 부재 우선)·denied·reachable·failed 분류를 고정하고, `CmuxLocalizationTests.testCmuxSocketStatusLabelsUseAllFiveCatalogs`가 5상태 × 5로케일 raw-key 부재를 고정한다. `isCmuxInstalled`는 실행과 같은 `findCmuxCLI()`를 쓰며, `cmuxSocketStatus()`는 소켓 존재와 5초 `cmux ping`을 매번 분류하고 저장하지 않는다. 실환경: 드라이버가 reachable 상태만 실측할 수 있다(사용자의 cmux가 automation으로 살아 있다 — notRunning·denied 실측은 사용자 상태를 바꿔야 하므로 항목 21로 이월). 재실행(드라이버): swift 512(1 skip)·node 220, 0 실패. 실환경 reachable 실측: `cmux ping` → PONG, exit 0. | | |
| 14 | `SetupWindowController` — 라디오, `terminalChanged` if-체인, 안내 노트, `refresh` 권한 switch, 새 「cmux 소켓 제어」 카드(+[자동화 허용] 버튼 — D1-b), `pipelineNodes` | verified | `SetupWindowController`에 4번째 cmux 라디오·상태 카드·[자동화 허용]/[다시 확인] 버튼·reachable/notRunning/denied/notInstalled/failed pipeline 매핑을 추가했고, `SetupWindowLayoutTests.testItem14CmuxSelectionShowsSocketSectionAndUsesStatusState`와 제품명 집합 "cmux", `CmuxLocalizationTests.testItem14And22CmuxCardStringsExistInAllFiveCatalogs`로 고정했다. 설정 창 4상태 캡처(미설치/소켓 거부/허용/cmux 꺼짐)는 설치 후 사용자 참여인 항목 21로 이월한다. 재실행(드라이버): swift 527(1 skip)·node 220, 0 실패. 설정 창 캡처·라이브 버튼 실측은 항목 21. | `13` | |
| 15 | `install.sh` 프리플라이트에 cmux 감지 + 안내 | todo | `./install.sh` 출력의 "감지된 터미널"에 cmux가 찍힌다 | | |
| 16 | `README.md` — 터미널 목록·아키텍처 그림·설정 단계·권한 안내·fallback 제한·트러블슈팅 + **cmux socket mode 안내** | todo | diff 리뷰 | | |
| 17 | manifest description은 `__MSG_…__` 참조이고 실제 문구는 `extension/_locales/{en,ko,ja,zh_CN,zh_TW}/messages.json` 5파일에 있다 — 다섯 로케일 모두 갱신, `tools/check-locales.js`가 게이트(불변 원칙 16) | todo | `node --test` 220 그대로 + 문자열 diff | | |
| 18 | `docs/new-terminal-checklist.md` — §1에 "소켓 접근 모드가 필요한 터미널" 줄, §2에 cmux 전용 실측 블록 | todo | diff | | |
| 19 | `CLAUDE.md`에 cmux 함정 추가(rpc 통일 이유·`unescapeSendText` 구멍·서버의 LF→CR 변환·socket mode 전제·tty가 push 기반) + 5행의 낡은 터미널 목록 갱신 | todo | diff | | |
| 20 | 게이트 4종 재실행 | todo | 각 명령의 마지막 줄 인용 | | |
| 21 | `docs/new-terminal-checklist.md` §2 실측 전체 수행(사용자 참여) | todo | 체크박스별 근거 | | |
| 22 | cmux.json `automation.socketControlMode` 기록 헬퍼(D1-b — 순수 함수: JSONC 주석 보존 텍스트 편집 + `.bak` 백업) + 설정 창 버튼 연결 | verified | `CmuxTests`의 `testItem22CmuxConfigInsertsAutomationBeforeCommentedTemplateAndPreservesJSONC`, `testItem22CmuxConfigReplacesOnlyExistingSocketModeValue`, `testItem22CmuxConfigAddsMissingSocketModeAsTheFirstAutomationMember`, `testItem22CmuxConfigReturnsUnchangedWhenAutomationIsAlreadyEnabled`, `testItem22CmuxConfigCreatesMinimalJSONForMissingOrBlankFile`, `testItem22CmuxConfigDoesNotTreatAStringValueAsTheAutomationKey`, `testItem22CmuxConfigIgnoresAutomationInsideBlockComment`, `testItem22CmuxConfigRejectsNonObjectAndUnbalancedInputWithoutEditing`가 JSONC 주석 템플릿 오인·비주석 automation/socketControlMode·빈 입력·문자열/블록 주석·잘못된 구조를 고정하고, `CmuxAutomationTests` 3개가 백업 선행·디렉터리 생성·원자 교체·3초(0.3초 간격) bounded poll·unchanged no-op을 고정한다. `CmuxAutomation`은 버튼에서만 비동기 호출된다. 라이브 버튼→cmux.json→`.bak`→ping 실측은 드라이버/사용자 환경 대조로 남긴다. 재실행(드라이버): swift 527(1 skip)·node 220, 0 실패. 설정 창 캡처·라이브 버튼 실측은 항목 21. | `13` | |

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
| `Core/ClaudeInjector.swift:1086-1142` (`sendKeys`) | 예 — 컴파일러가 잡는다 | `swift build`; clear key 특례는 `cmuxSendOperations`가 `ctrl+u` 뒤 `backspace`로 분리 | 구멍(항목 10) |
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
| `App/SetupWindowController.swift:1671-1700` (다시 확인·자동화 허용 action, App I/O 경계) | 예 — 명시적 클릭만 JSONC 기록을 시작하고 completion은 main으로 돌아온다 | 코드 확인 | 확인(항목 14, 22) |
| `App/CmuxAutomation.swift:30-138` (백업·원자적 쓰기·bounded live poll) | 예 — 설정 파일을 쓰는 유일한 App 경계 | 코드 + `CmuxAutomationTests` | 확인(항목 22) |
| `Core/CmuxConfig.swift:1-365` (JSONC lexer/parser와 텍스트 편집) | 예 — 주석/문자열을 건너뛰는 순수 편집 계층 | `CmuxTests` | 확인(항목 22) |
| `Tests/AppTests/SetupWindowLayoutTests.swift:392,430-445` (터미널 제품명 집합·cmux 카드/pipeline) | 예 | `swift test` | 확인(항목 14) |
| `App/HostServer.swift:177-201` | 아니오 — `Settings.terminal`을 그대로 넘긴다 | 코드 확인 | 안전 |
| `App/AppDelegate.swift`·`Installer.swift`·`Theme.swift` | 아니오 | `grep -rn "iterm\|wezterm\|warp"` 무결과 | 안전 |
| `Core/Paths.swift:31` (`com.iterm.checkout.json`) | 아니오 — 레거시 manifest 이름 | 코드 확인 | 안전 |
| `app/Info.plist` `NSAppleEventsUsageDescription` | 아니오(D6) | 결정 D6 | 안전 — D6이 뒤집히면 구멍 |
| `app/Package.swift`·`app/build.sh` (헬퍼 타깃·복사·서명) | 아니오 — pane 안 헬퍼를 만들지 않는다 | 결정 D4 Plan A | 안전 |
| `install.sh:34-42` (iTerm2·WezTerm·Warp만 감지하고 `exit 1`) | 예 — cmux 감지·프리플라이트 누락은 항목 15 소관 | 스크립트 확인 | 구멍(항목 15) |
| `uninstall.sh:20-37` (Warp 잔여 스윕) | **아니오** — cmux는 디스크에 남기는 것이 없다(Tab Config·헬퍼 소켓 없음) | 결정 D4 Plan A | 안전 |
| `Tests/CoreTests/CoreTests.swift:673-688` (`TerminalIdentifierTests`) | 예 — **`allCases.count`가 3으로 박혀 테스트가 빨개진다** | `swift test` | 구멍(항목 1) |
| `Tests/CoreTests/CmuxTests.swift:6-20` (cmux 식별자·후보·소켓 순수 테스트) | 예 | `swift test` | 구멍(항목 1, 2) |
| `Tests/CoreTests/CoreTests.swift:1802-1833` (`UninstallScriptSyncTests`) | 아니오 — 새 상수가 없다 | 결정 D4 | 안전 |
| `README.md:3,13,17-19,22,30,73-76,114,127,188,190-192` | 예 — **문서** | diff | 구멍(항목 16) |
| `CLAUDE.md:5`(터미널 목록이 이미 Warp 누락), `24,32-38,44-45` | 예 — **문서**, 게다가 이미 낡았다 | diff | 구멍(항목 19) |
| `extension/manifest.json:5` | 예 — **문자열** | diff | 구멍(항목 17) |
| `extension/` 나머지 | 아니오 — 확장은 터미널을 모른다 | `grep -rn "iterm\|wezterm\|warp" extension/` → manifest만 | 안전 |
| `app/e2e.sh:44` (`"terminal":"iterm"`) | 아니오 — 요청의 terminal 필드는 앱이 무시한다(`RequestTests.testTerminalFieldIsIgnored`) | 코드 확인 | 안전 |
| `docs/new-terminal-checklist.md` | 예 — **문서**, 갱신 의무 | diff | 구멍(항목 18) |

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

- 항목 1∼4를 `verified`로 갱신했다. `Terminal` rawValue 4개와 `allCases.count == 4`, cmux CLI 후보·소켓 생존 판정, RPC 메서드 5개·ASCII JSON argv·응답 파서, cmux 오류 분류와 5로케일 Localization 경로를 코드와 테스트에 반영했다.
- 항목 1의 enum 추가로 컴파일러가 잡는 exhaustive switch 구멍은 현재 트리에서 `Core/TerminalRunner.swift:102-114`(`claudeInputBlocker`, #36 신설), `Core/TerminalRunner.swift:245-251`(`runInTerminal`), `App/SetupWindowController.swift:1190-1198`(`updateTerminalControls`), `:1264-1284`(`refresh` 권한), `:1405-1436`(`pipelineNodes`)다. 이 부류에서는 새 케이스가 컴파일되도록 해당 위치에만 cmux 분기를 닫았고, 실제 실행·설정 UI 경로는 항목 5 이후로 남겼다.
- 컴파일러가 잡지 못하는 현재 위치도 갱신했다: `App/Settings.swift:19-32` 자동 감지 순수 함수·호출, `App/SetupWindowController.swift:1170-1177` 라디오 if-체인, `:1205` Warp `==`, `:1287-1288` 섹션 `!=`, `App/PermissionChecker.swift:53-94` 설치 판정·cmux 상태 프로브, `Tests/AppTests/SetupWindowLayoutTests.swift:392` 제품명 집합.
- TDD 테스트: `TerminalIdentifierTests.testRawValuesAreTheStoredIdentifiers`를 4개로 늘렸고, `CmuxTests.testCmuxCLICandidatePathsUseBundleLocationsBeforePATH`, `testFindCmuxCLIReturnsTheFirstExecutableCandidate`, `testCmuxSocketPathOnlyReportsAnExistingSocket`, `testCmuxRPCMethodNamesAreTheFiveSupportedMethods`, `testCmuxRPCArgumentsAreASCIIAndPreserveJSONValues`, `testCmuxRPCResponseParsesWorkspaceIdentifiers`, `testCmuxRPCResponseParsesQueuedAndText`, `testCmuxRPCFailuresDistinguishSocketDenialAndMethod`, `CmuxLocalizationTests.testCmuxTerminalErrorsUseAllFiveCatalogs`를 추가했다.
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

## 열린 질문 → 결정 (2026-08-23, 사용자·드라이버)

1. **수용 + 확장** — automation 전제로 구현하고, **앱이 설정 창 버튼으로 옵션을 켠다**(D1-b에 조건과 함께 반영). automation의 의미(같은 uid 노출 확대)는 README·설정 창에 적는다 — 사용자 승인.
2. 소멸(1 수용). AppleScript 대안(D6)은 기록으로만 남는다.
3. **채택안 확정** — CR=`surface.send_text`, Ctrl+U=`surface.send_key`. R1-i로 실측 검증하고 `send_text \u{15}` 시험 결과는 기록만 한다.
4. **실측 승인** — 안전 조건 그대로(우리가 만든 workspace UUID만 지목, 사용자 pane은 조회 금지, 종료 시 close). cmux.json 편집도 승인(`.bak` 백업 조건). 실측 후 automation 모드는 **켠 채로 둔다**(사용자가 원하는 최종 상태).
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
| R1-g·R1-h | **[보류]**: cmux 창 2개가 필요 — 창 추가는 사용자 동의 후(안전 조건). 단 참고 관찰: 프로브 workspace들은 전부 사용자의 기존 창(window:1)에 생겼다 | 창 2개를 추가하는 실측은 사용자 동의 후 | 우리가 만든 창만 닫는다 |
| R1-i | **[완료]**: 우리 workspace에서 `stty raw -echo; cat -v` 후 send_text `"\r"` → `^M` 하나, send_key `ctrl+u` → `^U`(0x15), send_key `backspace` → `^?`(0x7F). CR·Ctrl+U·Backspace 모두 의도한 원시 바이트로 들어간다 — 열린 질문 3의 채택안 검증 완료 | 우리 workspace의 raw tty 실측(드라이버 실측 2026-08-26) | 우리 workspace 전용 |
| R1-j | **[보류]**: 항목 1∼11 구현 후 | 전체 경로 실측은 항목 1∼11 완료 후 | 전용 임시 디렉토리 |
| R1-k | **[완료]**: cold surface에 send_text → `queued:true`. **queued는 유실이 아니다** — surface가 웜업되면 flush되어 pty에 들어간다(실측: 셸 배너보다 먼저 들어가 프롬프트 라인버퍼에 재등장). 항목 10의 queued 로깅 사유가 이것이다: 보냈다고 착각한 바이트가 나중에 도착할 수 있다 | cold surface send_text 후 웜업·pty 확인(드라이버 실측 2026-08-26) | 우리 workspace 전용 |
| R1-l | **[완료]**: `workspace.create` 58∼110ms + `surface.send_text` 38ms(각 time 실측) — WezTerm 왕복과 같은 수준, execQueue 예산 안 | 각 RPC 응답의 `time` 기록(드라이버 실측 2026-08-26) | 측정만 |
| R1-m | **[완료]** cmux.json 변경이 재시작 없이 반영되는가 → **반영된다**(2026-08-23 실측: 기록 직후 외부 ping이 거부→PONG으로 바뀜, 재시작 없음) | 실측 완료 | 버튼 UX 확정: 기록 → `cmux ping` 폴링으로 적용 확인, 재시작 안내는 미반영 시 폴백으로만. `cmux reload-config`는 cmuxOnly에서 외부 호출이 거부되므로 수단이 아님(「재개」) |
