import Foundation

/// The Native Messaging host name — only lower-case alphanumerics, `_` and `.` are allowed (no hyphens).
public let nativeHostName = "com.dazebug.terminal_checkout"

public func extensionOrigin(_ extensionID: String) -> String {
    "chrome-extension://\(extensionID)/"
}

/// `allowed_origins` is an array — moving to the Web Store can list the store ID alongside the development one.
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
