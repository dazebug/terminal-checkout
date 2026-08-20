# 새 터미널 지원 검사 목록

터미널 분기는 Core의 실행·입력 전달, App의 설정·권한·설정 창에 흩어져 있고, 단위 테스트와 `app/e2e.sh`는 터미널을 실제로 열지 않는다(e2e는 오류 경로만 쓴다). 그래서 새 터미널을 붙일 때 빠뜨린 분기는 테스트가 통과한 뒤 실사용에서만 드러난다 — 아래 목록은 그 간극을 메우기 위한 것이다.

이미 확인된 터미널별 함정(WezTerm의 창 선택·GUI 앱 PATH, iTerm2의 `current window`)은 `CLAUDE.md`에 있으므로 여기서는 반복하지 않는다.

## 1. 코드에서 손댈 지점

터미널 식별자는 앱이 `UserDefaults`의 `terminal` 키에 저장하는 문자열이다(`iterm`, `wezterm`, `warp`). 확장은 이 값을 모르고 알 수단도 두지 않는다 — 확장 쪽은 동작상 손댈 것이 없다.

**Core**

| 지점 | 할 일 |
|:---|:---|
| `TerminalRunner.runInTerminal(command:terminal:injectsClaudeInput:)` | 식별자 분기 추가. `injectsClaudeInput`은 입력 전달에 별도 준비가 필요한 터미널만 본다 |
| `TerminalRunner.runInXxx(_:)` (신규) | 새 탭 생성 → 명령 전송 → `TerminalSessionHandle` 반환 |
| `TerminalSessionHandle` (`ClaudeInjector.swift`) | 케이스 추가. 핸들을 못 만들면(`.none`) claude 입력은 전달되지 않는다 |
| `ClaudeInjector.deliverClaudeInputs` | 핸들에서 tty 경로를 얻는 갈래 |
| `ClaudeInjector.sendKeys` | 텍스트 · CR(`\r`, 제출) · Ctrl+U(`\u{15}`, 입력창 클리어) 세 가지 |
| `ClaudeInjector.screenText` | 화면 텍스트 조회 — 타이핑 **직전과 직후** 두 번 찍어 비교한다(`screenReflectsNewInput`). 읽을 수 없으면 입력을 보내지 않는 것이 정답이다 |
| `ClaudeSessionIO.screenNeedsPaneProof` | 화면 조회가 그 세션의 것이라고 단정할 수 없는 터미널은 true — 입력마다 난수 표식으로 pane을 먼저 증명한다. pane/세션 id로 정확히 읽는 터미널은 기본값(false) 그대로 둔다 |

`ClaudeInjector`의 세 갈래 중 하나만 빠져도 실행은 되고 claude 입력만 조용히 멈춘다. 특히 `screenText`가 없으면 반영 확인이 실패해 CR을 보내지 못한다.

CLI를 호출하는 터미널이면 실행 파일 경로를 명시적으로 탐색해야 하고, AppleScript로 제어하는 터미널이면 TCC 자동화 대상이 하나 늘어난다(권한 요청·상태 조회 경로도 함께 필요).

pane을 지목할 API가 아예 없는 터미널(Warp)은 pane 안에서 도는 헬퍼 프로세스가 그 자리를 대신한다 — 그러면 `app/Package.swift`의 타깃과 `app/build.sh`의 번들 복사·서명도 함께 늘어난다.

**App**

| 지점 | 할 일 |
|:---|:---|
| `Settings.terminal` | 저장값이 없을 때의 자동 감지 순서 |
| `PermissionChecker.isXxxInstalled` | 설치 감지. AppleScript 제어면 상태 조회·권한 요청·시스템 설정 열기까지 |
| `SetupWindowController` | 라디오 버튼 추가, 미설치 시 비활성화, 저장(`terminalChanged`)·복원, 권한 카드 표시 조건, 파이프라인 노드의 이름·색·설명 |
| `app/Info.plist` | `NSAppleEventsUsageDescription`은 앱 전체에 하나뿐이다 — 문구에 특정 터미널 이름이 박혀 있으면 갱신 |
| `install.sh` | 프리플라이트의 터미널 감지 목록과 안내 문구. 하나도 못 찾으면 `exit 1`로 설치를 막으므로, 빠뜨리면 새 터미널만 깔린 환경에서 설치 자체가 안 된다 (앱의 설치 감지와 판정 기준이 다르다) |
| `README.md` | 요구 터미널 목록·아키텍처 그림·설정 단계·권한 안내·fallback 제한·트러블슈팅에 터미널 이름이 박혀 있다. 코드가 지원해도 여기가 낡으면 사용자는 미지원으로 읽는다 |

터미널 이름은 `extension/manifest.json`의 description에도 박혀 있다 — 확장에서 손댈 것은 이 문구뿐이다.

**테스트**

CLI 응답이나 스크립트 출력을 파싱하는 부분(창 고르기, pane→tty 조회 등)은 순수 함수로 떼어 `app/Tests/CoreTests`에 고정한다 — `WezTermWindowTests`가 그 예다. 실행 자체는 단위 테스트로 잡히지 않으므로 아래 실측이 유일한 검증이다.

## 2. 실측 검사 목록

앱 설정 창에서 새 터미널을 고르고 표시등 4단계가 모두 초록인 상태에서 시작한다.

**기동과 명령**

- [ ] 앱 설정 창 [터미널에서 실행] → 새 탭에서 echo가 돈다
- [ ] 저장소 페이지 버튼 → 새 탭의 작업 디렉토리가 그 리포다 (`{repo}` `{owner}` `{main}` 치환)
- [ ] PR 버튼 → 새 탭 + `{repo}` `{branch}` `{base}` `{branch_underbar}` 치환
- [ ] 이슈 버튼 → 새 탭 + `{number}` `{owner}` 치환
- [ ] 확장 아이콘 클릭 → PR · 이슈 · 저장소 페이지에서 각각 첫 번째 버튼 (분기가 서로 다르다)
- [ ] 기본 브랜치가 `master`인 리포의 저장소·이슈 버튼에서 `{main}` 치환 (페이지에서 읽은 값이고, 못 읽으면 조용히 글로벌 기본값으로 떨어진다)
- [ ] `z {repo}` 이동 — 로그인 셸을 인터랙티브로 띄우지 않으면 zoxide 함수를 찾지 못해 첫 단계에서 죽는다
- [ ] `&&`로 길게 이어진 명령(워크트리 생성 → cd → merge → claude)의 마지막 단계까지 도달

**창 선택**

- [ ] 창을 둘 이상 띄우고 두 번째 창을 활성화한 상태에서 실행 → 보고 있던 창에 탭이 생긴다
- [ ] 탭을 붙일 창을 찾지 못했을 때의 폴백
- [ ] 찾은 창이 탭 생성 직전에 닫혔을 때의 폴백 (여기서 포기하면 새 창이 튀어나온다)
- [ ] 터미널이 아예 꺼져 있을 때 — 새 창으로 뜨는지, 그때 claude 입력은 포기되는지

**claude 입력**

- [ ] 예약한 입력이 순서대로 타이핑·제출된다 — 슬래시 커맨드와 `!`로 시작하는 셸 모드를 각각
- [ ] 게이트 ①②: claude가 뜨기 전 셸에 입력이 새지 않는다 (exec 직후 canonical 구간 포함)
- [ ] 게이트 ③: 원래 claude를 끝내고 같은 tty에 새 claude를 띄운 뒤, 남은 입력이 그쪽으로 흘러가지 않는다
- [ ] 세션 탭을 도중에 닫으면 전송이 중단된다
- [ ] 처음 여는 폴더의 trust 프롬프트가 떠 있는 동안 제출이 보류된다
- [ ] claude 입력을 예약하지 않은 버튼은 입력 전달용 준비(헬퍼 등)를 하지 않는다 — 탭에 군더더기 명령이 생기지 않는다

**pane 안 헬퍼를 쓰는 터미널(Warp)**

- [ ] 헬퍼가 뜨지 못한 경우(번들에서 빠짐·소켓 경로 초과) — 명령은 실행되고 claude 입력만 포기되며 이유가 앱 로그에 남는다
- [ ] 전달이 끝난 뒤 헬퍼가 사라진다 (`ps -axo command= | grep warp-helper`, 소켓 파일도 삭제)
- [ ] 전달 도중 탭을 닫으면 헬퍼가 스스로 종료한다 — 떠도는 프로세스가 남지 않는다
- [ ] 화면 읽기 권한이 없으면 입력을 전달하지 않고, 그 이유가 앱 로그와 설정 창에 남는다 (명령 실행은 되는 것과 구분되어야 한다)
- [ ] 512바이트가 넘는 입력(한글 포함)이 잘리지 않고 전달된다 — tty 입력 큐 상한을 나눠 넣는 갈래
- [ ] 연속으로 두 버튼을 빠르게 누르면 두 탭에 각자의 명령이 뜬다 (Tab Config 파일이 서로를 덮어쓰지 않는다)
- [ ] 사용자가 만든 같은 이름의 Tab Config가 덮어써지지 않는다
- [ ] 사용자가 다른 탭·다른 앱을 보고 있으면 제출이 보류되고, 돌아오면 이어서 완료된다 (그 사이 표식이 입력창에 남지 않아야 한다)
- [ ] 전달 도중 손쉬운 사용 권한을 회수하면 더 이상 아무것도 주입되지 않고, 남은 조각이 정리된다
- [ ] 그 터미널이 세션 내역을 저장하는 방식(Warp는 GUI로 띄운 세션만 저장한다는 사용자 진술)이 우리가 만든 탭에도 적용되는지

## 3. 검증 수단

확장을 거치지 않고 앱만 때리려면 relay에 Chrome과 같은 프레이밍(4바이트 리틀엔디안 길이 + JSON)으로 payload를 넣는다. 소켓 경로는 홈 기준으로 고정돼 있어 relay는 어느 사본을 써도 실행 중인 앱에 붙는다 — 다만 셸에 `TERMINAL_CHECKOUT_SOCKET`이 남아 있으면 그 소켓으로 간다.

```bash
python3 -c 'import struct,subprocess,sys
p=sys.stdin.read().encode()
r=subprocess.run(["/Users/<you>/Applications/Terminal Checkout.app/Contents/MacOS/terminal-checkout-relay"],
                 input=struct.pack("=I",len(p))+p, capture_output=True)
n=struct.unpack("=I",r.stdout[:4])[0]; print(r.stdout[4:4+n].decode())' <<< \
'{"command_template":"z {repo} && claude","variables":{"repo":"terminal-checkout"},"claude_inputs":["!echo ok"]}'
```

- **새 탭·작업 디렉토리**: 실행 전후로 셸이 붙은 tty 집합을 비교하고(`ps -eo tty,command`), 새 tty의 셸 pid에 `lsof -a -p <pid> -d cwd`로 작업 디렉토리를 확인한다. 터미널 앱을 제어할 권한 없이 검증된다
- **claude가 입력을 실제로 받았는지**: `~/.claude/projects/<cwd 슬러그>/*.jsonl`에서 `<bash-input>`(셸 모드)과 `<command-name>`(슬래시 커맨드)을 찾는다. 화면을 읽지 않고도 순서와 시각이 남는다
- **앱의 판정**: `/usr/bin/log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 15m --info` — 성공 시 `입력 N개 중 M개 전달`이 남는다. 절대 경로로 부르는 이유는 셸에서 `log`가 함수·별칭에 가려질 수 있기 때문이다
- **앱 설정 창 버튼 누르기**: 좌표를 합성해 클릭하면 그 위에 겹친 창이 이벤트를 받는다(실측). 접근성 API로 버튼을 직접 누르는 편이 확실하다. 창만 캡처하려면 `screencapture -l <windowID>`를 쓴다

claude 입력은 앱이 3개를 모두 전달해도 claude가 첫 출력을 보고 자율 작업을 시작하면 나머지가 claude 자체의 입력 큐에 남는다(실측) — 앱 로그의 전달 개수와 트랜스크립트의 실행 개수가 다를 수 있으니, 전달 실패로 오판하지 말고 두 근거를 함께 본다.
