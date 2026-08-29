# 리포 오버레이 — terminal-checkout

## 검사 명령

검사 명령의 정본은 [`README.md`](../README.md)의 「Development」 절이다. 이 루프의 앱 게이트는 `cd app && swift test`, 확장 게이트는 `node --test`다. 성공·실패는 각 명령의 exit status로 판정하고 실행된 테스트 수를 별도로 기록한다.

## 격리 안에서 못 하는 검사

`cd app && swift test`는 구현자 샌드박스에서 실행하지 않는다. Swift gate 결과는 드라이버가 clone에서 재실행하고, 구현자는 환경 실패를 구현 회귀나 green으로 해석하지 않는다.

## 로컬 자산 env

해당 없음.

## ultrafast 모드 — 구현자 샌드박스 실측

swift 게이트는 구현자 샌드박스에서 돌지 않는다(이전 루프 실측) — 드라이버가 clone에서 `cd <clone>/app && swift test`로 대신 돌린다. `node --test`는 README.md Development 절의 확장 게이트로 유지하며 결과는 exit status와 실행 테스트 수로 기록한다.

## 배정 메시지에 더할 리포 고유 문장

cmux command send gate는 raw mode를 모든 payload의 선행조건으로 삼지 않고, `darwinCanonicalLineLimit` 이하 payload를 canonical buffer 안에서 즉시 보내며 한도 초과 payload만 raw mode를 기다린다.
