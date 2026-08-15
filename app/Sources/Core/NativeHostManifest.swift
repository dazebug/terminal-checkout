import Foundation

/// Native Messaging host 이름 — 소문자 영숫자·`_`·`.`만 허용 (하이픈 금지)
public let nativeHostName = "com.dazebug.terminal_checkout"

public func extensionOrigin(_ extensionID: String) -> String {
    "chrome-extension://\(extensionID)/"
}

/// allowed_origins는 배열 — Web Store 전환 시 store ID + 개발용 ID를 병기할 수 있다.
public func nativeHostManifestJSON(relayPath: String, extensionIDs: [String]) -> Data {
    let manifest: [String: Any] = [
        "name": nativeHostName,
        "description": "Terminal Checkout Native Host",
        "path": relayPath,
        "type": "stdio",
        "allowed_origins": extensionIDs.map(extensionOrigin),
    ]
    return try! JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
}
