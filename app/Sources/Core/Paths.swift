import Foundation

/// 앱 번들 ID. Native host 이름(com.dazebug.terminal_checkout)과 별개 네임스페이스.
public let appBundleID = "com.dazebug.terminal-checkout"
public let appDisplayName = "Terminal Checkout"

public func appSupportDirectory() -> String {
    (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/TerminalCheckout")
}

/// relay↔앱 소켓 경로. 테스트를 위해 환경변수로 오버라이드 가능.
public func defaultSocketPath() -> String {
    if let raw = getenv("TERMINAL_CHECKOUT_SOCKET") {
        let value = String(cString: raw)
        if !value.isEmpty { return value }
    }
    return (appSupportDirectory() as NSString).appendingPathComponent("host.sock")
}

public func chromeNativeMessagingDir() -> String {
    (NSHomeDirectory() as NSString)
        .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
}

public func nativeHostManifestPath() -> String {
    (chromeNativeMessagingDir() as NSString).appendingPathComponent("\(nativeHostName).json")
}

/// iTerm Checkout 시절 레거시 manifest
public func legacyManifestPath() -> String {
    (chromeNativeMessagingDir() as NSString).appendingPathComponent("com.iterm.checkout.json")
}

/// 앱이 확장 프로그램 사본을 설치하는 기본 위치 (경로가 안정적이어야 확장 ID가 고정된다)
public func defaultExtensionInstallPath() -> String {
    (appSupportDirectory() as NSString).appendingPathComponent("extension")
}
