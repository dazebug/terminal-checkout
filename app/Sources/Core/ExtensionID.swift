import CryptoKit
import Foundation

/// Chrome unpacked 확장 ID 계산: SHA-256(절대경로 UTF-8) 앞 32 hex를 a-p로 매핑.
public func extensionID(forPath path: String) -> String {
    let digest = SHA256.hash(data: Data(path.utf8))
    let hex = digest.map { String(format: "%02x", $0) }.joined().prefix(32)
    let mapped = hex.map { ch -> Character in
        let value = UInt8(String(ch), radix: 16)!
        return Character(UnicodeScalar(UInt8(ascii: "a") + value))
    }
    return String(mapped)
}
