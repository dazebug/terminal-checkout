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
}
