import AppKit
import Core
import Foundation

enum AutomationStatus {
    case granted
    case denied
    case notDetermined
    case targetNotRunning
    case unknown(Int32)

    var label: String {
        switch self {
        case .granted: return "허용됨"
        case .denied: return "거부됨 — 시스템 설정 → 개인정보 보호 → 자동화에서 허용하세요"
        case .notDetermined: return "아직 요청 안 됨 — [권한 요청]을 누르세요"
        case .targetNotRunning: return "iTerm2가 실행 중이 아니라 확인 불가 — [권한 요청]을 누르면 실행됩니다"
        case .unknown(let code): return "상태 확인 실패 (OSStatus \(code))"
        }
    }

    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
}

enum PermissionChecker {
    static var isITermInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) != nil
    }

    static var isWezTermInstalled: Bool {
        findWezTermCLI() != nil
    }

    /// iTerm2 자동화(Apple Events) 권한 상태 — 프롬프트를 띄우지 않고 조회만 한다.
    static func iTermAutomationStatus() -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: iTermBundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .targetNotRunning
        default: return .unknown(status)
        }
    }

    /// iTerm2를 먼저 실행해 두고, 무해한 Apple Event를 보내 권한 프롬프트를 유도한다.
    /// 타게팅은 번들 ID로 한다 — 이름 해석 실패(-1728)를 피하고 대상 앱을 확정하기 위해.
    static func requestITermAutomation(completion: @escaping (Result<Void, Error>) -> Void) {
        launchITerm { _ in
            DispatchQueue.global().async {
                // 실행될 때까지 대기 (최대 10초; 실패해도 osascript의 자동 실행이 백업)
                for _ in 0..<50 {
                    if !NSRunningApplication.runningApplications(withBundleIdentifier: iTermBundleID).isEmpty {
                        break
                    }
                    usleep(200_000)
                }
                do {
                    // count windows: 반드시 Apple Event를 전송하는 무해한 조회 —
                    // version/name은 로컬에서 응답될 수 있어 동의 프롬프트를 유발하지 못한다
                    let result = try runProcess(
                        "/usr/bin/osascript",
                        ["-e", "tell application id \"\(iTermBundleID)\" to count windows"],
                        timeout: 300 // 사용자가 프롬프트에 응답할 때까지 기다린다
                    )
                    DispatchQueue.main.async {
                        if result.status == 0 {
                            completion(.success(()))
                        } else {
                            completion(.failure(TerminalError.appleScriptFailed(
                                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                            )))
                        }
                    }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    private static func launchITerm(completion: @escaping (Bool) -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) else {
            completion(false)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
