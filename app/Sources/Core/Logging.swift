import Foundation
import os

/// 앱·릴레이가 공유하는 진단 로그.
///
/// NSLog를 쓰지 않는 이유: NSLog는 메시지를 os_log의 인자로 넘기고, 인자는 통합 로그에서
/// 기본적으로 가려진다. 그래서 `log show`에 `<private>`으로만 남아, 실패했다는 사실은 알아도
/// 무엇이 실패했는지는 읽을 수 없다 — claude 입력이 전달되다 만 사고를 조사할 때 로그가
/// 한 줄 있는데도 내용을 못 읽어 타임스탬프 간격으로 경로를 좁혀야 했다 (실측).
///
/// 확인: `log show --predicate 'subsystem == "com.dazebug.terminal-checkout"' --last 1h`
private let checkoutLogger = Logger(subsystem: appBundleID, category: "app")

public func checkoutLog(_ message: String) {
    checkoutLogger.log("\(message, privacy: .public)")
}
