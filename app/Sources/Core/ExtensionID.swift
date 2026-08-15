import CryptoKit
import Foundation

/// Chrome unpacked 확장 ID 계산: SHA-256(절대경로 UTF-8) 앞 32 hex를 a-p로 매핑.
/// manifest에 "key"가 없을 때 Chrome이 쓰는 방식이다.
public func extensionID(forPath path: String) -> String {
    chromeExtensionID(hashing: Data(path.utf8))
}

/// manifest "key"(base64 DER 공개키) 기반 ID — key가 있으면 Chrome은 경로를 무시하고
/// 이 값에서 ID를 만들므로, 어느 컴퓨터에서 로드해도 같은 ID가 된다 (storage.sync가
/// 컴퓨터 간에 이어지는 전제 조건). base64가 아니면 nil.
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
