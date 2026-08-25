import CryptoKit
import Foundation

/// Computes a Chrome unpacked-extension ID: the first 32 hex digits of SHA-256(absolute path as UTF-8), mapped onto a-p.
/// This is what Chrome itself does when the manifest carries no "key".
public func extensionID(forPath path: String) -> String {
    chromeExtensionID(hashing: Data(path.utf8))
}

/// The ID derived from the manifest "key" (a base64 DER public key) — with a key present Chrome ignores the path and builds the ID from this value instead, so loading the folder on any machine yields the same ID (the precondition for storage.sync carrying settings between machines). nil when the value is not base64.
public func extensionID(fromManifestKey key: String) -> String? {
    guard let der = Data(base64Encoded: key), !der.isEmpty else { return nil }
    return chromeExtensionID(hashing: der)
}

private func chromeExtensionID(hashing data: Data) -> String {
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
    let mapped = hex.map { ch -> Character in
        let value = UInt8(String(ch), radix: 16)!
        return Character(UnicodeScalar(UInt8(ascii: "a") + value))
    }
    return String(mapped)
}
