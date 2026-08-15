import Core
import Foundation

/// 앱이 단일 소스로 관리하는 설정. 터미널 선택은 확장이 아니라 여기서 결정된다.
enum Settings {
    static var terminal: String {
        get {
            if let value = UserDefaults.standard.string(forKey: "terminal") { return value }
            // 기본값: 설치된 터미널 자동 감지 (iTerm2 우선)
            if PermissionChecker.isITermInstalled { return "iterm" }
            if PermissionChecker.isWezTermInstalled { return "wezterm" }
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
}

extension Notification.Name {
    /// 소켓 요청 처리 시 발행 — 설정 창이 열려 있으면 상태를 실시간 갱신한다
    static let terminalCheckoutRequestHandled = Notification.Name("TerminalCheckoutRequestHandled")
}
