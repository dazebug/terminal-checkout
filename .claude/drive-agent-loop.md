# drive-agent-loop 오버레이 — terminal-checkout

## 검사 명령

CLAUDE.md의 Development 및 이 계획의 「완료의 정의」가 정본이다. `cd app && swift test`, `node --test`, `./app/build.sh`, `./app/e2e.sh` 네 게이트는 모두 드라이버가 실행하고, 구현자는 실행하지 않는다. 결과는 exit status와 원문으로만 판정하며 reporter 출력 grep으로 green/red를 추정하지 않는다.

## 격리 안에서 못 하는 검사

네 게이트 전체는 구현자 샌드박스 밖의 드라이버가 실행한다. 직전 루프에서 `cd app && swift test`가 이 샌드박스에서 실행되지 않는 것이 실측되었고, 이번 ultrafast 루프에서는 같은 환경 실패를 구현 회귀로 해석하지 않는다. 드라이버의 원문은 `/tmp/cmux-spark.qH3zbk/`에 보존한다.

## 로컬 자산 env

해당 없음. 스크래치패드 경로는 `/tmp/cmux-spark.qH3zbk/`이다.

## ultrafast 모드 — 구현자 샌드박스 실측

모드: `ultrafast`. `cd app && swift test`, `node --test`, `./app/build.sh`, `./app/e2e.sh`는 모두 드라이버 소유라 구현자 샌드박스에서는 실행하지 않는다. 이 clone의 기준 HEAD는 `e2e9c43fa842a1571ee76706048766b82cc0afa9`이고 App target은 baseline에서 아직 컴파일되지 않는다. 샌드박스에서 관측한 실패가 있더라도 원문만 전달하고 구현 회귀·green으로 반올림하지 않는다.

## 배정 메시지에 더할 리포 고유 문장

1024바이트 canonical-limit 계약과 channel별 socket pointer pin을 유지하라. 살아 있는 pointer가 있으면 cmux의 모든 RPC와 ping에 `CMUX_SOCKET_PATH`를 전달하고, stable/NIGHTLY를 섞지 말라. `TerminalSessionHandle.cmux`의 `workspaceID`와 두 parser 식별자 요구를 제거하지 말고, `cmux NIGHTLY` label은 제품명 그대로 둬라. cmux settings file은 쓰지 않는다.
