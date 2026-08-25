import Foundation

/// The app bundle ID. A separate namespace from the Native host name (com.dazebug.terminal_checkout).
public let appBundleID = "com.dazebug.terminal-checkout"
public let appDisplayName = "Terminal Checkout"

public func appSupportDirectory() -> String {
    (NSHomeDirectory() as NSString).appendingPathComponent("Library/Application Support/TerminalCheckout")
}

/// The relay↔app socket path. Overridable through an environment variable so tests can point it elsewhere.
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

/// The legacy manifest from the iTerm Checkout days.
public func legacyManifestPath() -> String {
    (chromeNativeMessagingDir() as NSString).appendingPathComponent("com.iterm.checkout.json")
}

/// Where the app installs its copy of the extension (the path has to be stable for the extension ID to stay fixed).
public func defaultExtensionInstallPath() -> String {
    (appSupportDirectory() as NSString).appendingPathComponent("extension")
}
