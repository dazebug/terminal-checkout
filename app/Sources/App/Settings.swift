import Core
import Foundation

/// 앱이 단일 소스로 관리하는 설정. 터미널 선택은 확장이 아니라 여기서 결정된다.
enum Settings {
    static var terminal: String {
        get {
            if let value = UserDefaults.standard.string(forKey: "terminal") { return value }
            // 기본값: 설치된 터미널 자동 감지. 순서는 지원이 오래돼 실사용으로 다져진
            // 순이다 — Warp는 pane을 지목할 정식 API가 없어 헬퍼 프로세스를 끼우므로 마지막
            if PermissionChecker.isITermInstalled { return "iterm" }
            if PermissionChecker.isWezTermInstalled { return "wezterm" }
            if PermissionChecker.isWarpInstalled { return "warp" }
            return "iterm"
        }
        set { UserDefaults.standard.set(newValue, forKey: "terminal") }
    }

    /// 소켓으로 마지막 요청이 도착한 시각 — "확장이 Chrome에 로드되어 실제로 연결됐다"는 유일한 증거.
    /// (폴더 준비 여부만으로는 Chrome 로드 완료를 알 수 없다)
    static var lastRequestAt: Date? {
        get { UserDefaults.standard.object(forKey: "lastRequestAt") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "lastRequestAt") }
    }

    static func recordRequestEvidence() {
        lastRequestAt = Date()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .terminalCheckoutRequestHandled, object: nil)
        }
    }

    /// 명령이 부르는 도구(z/gh/claude)의 마지막 확인 결과. 확인은 로그인 셸을 띄우느라
    /// 시간이 걸리므로, 창이 열리자마자 보여줄 직전 값을 남겨 둔다. 확인 전이면 nil.
    static var toolAvailability: [String: Bool]? {
        get { UserDefaults.standard.dictionary(forKey: "toolAvailability") as? [String: Bool] }
        set { UserDefaults.standard.set(newValue, forKey: "toolAvailability") }
    }

    /// 앱 실행 때마다 다시 확인한다 — 사용자가 그 사이 도구를 설치했을 수 있다.
    /// 확인에 실패하면(셸이 응답하지 않음) 직전 결과를 그대로 둔다.
    static func refreshToolAvailability() {
        DispatchQueue.global(qos: .utility).async {
            guard let result = checkTools() else {
                checkoutLog("도구 확인 실패 — 로그인 셸이 응답하지 않음")
                return
            }
            toolAvailability = result
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .terminalCheckoutToolsChecked, object: nil)
            }
        }
    }
}

extension Notification.Name {
    /// 소켓 요청 처리 시 발행 — 설정 창이 열려 있으면 상태를 실시간 갱신한다
    static let terminalCheckoutRequestHandled = Notification.Name("TerminalCheckoutRequestHandled")
    /// 도구 확인이 끝났을 때 발행 — 확인은 백그라운드라 창이 먼저 열려 있을 수 있다
    static let terminalCheckoutToolsChecked = Notification.Name("TerminalCheckoutToolsChecked")
}
