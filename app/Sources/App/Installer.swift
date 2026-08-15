import Core
import Foundation

enum SetupState {
    case ok(String)
    case warning(String)
    case error(String)

    var message: String {
        switch self {
        case .ok(let m), .warning(let m), .error(let m): return m
        }
    }
}

enum InstallerError: Error, CustomStringConvertible {
    case bundledExtensionMissing

    var description: String {
        switch self {
        case .bundledExtensionMissing: return "앱 번들 안에 extension 리소스가 없습니다. 앱을 다시 빌드하세요."
        }
    }
}

/// Native Host manifest 등록과 확장 프로그램 폴더 설치를 담당한다.
enum Installer {
    /// 현재 실행 중인 앱 번들 안의 relay 절대경로 (manifest의 path로 쓰인다)
    static var relayPath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/terminal-checkout-relay"
    }

    static var bundledExtensionPath: String? {
        Bundle.main.resourcePath.map { $0 + "/extension" }
    }

    /// Chrome에 로드할 확장 폴더 — App Support 고정 경로 단일 위치.
    static var extensionDirectory: String { defaultExtensionInstallPath() }

    /// 번들 확장 manifest의 "key" — 확장 ID를 컴퓨터·경로와 무관하게 고정하는 공개키.
    /// (같은 ID여야 storage.sync 설정이 같은 Google 계정의 Chrome끼리 동기화된다)
    static var bundledManifestKey: String? {
        guard let dir = bundledExtensionPath,
              let data = FileManager.default.contents(atPath: dir + "/manifest.json"),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return nil
        }
        return obj["key"] as? String
    }

    static var currentExtensionID: String {
        bundledManifestKey.flatMap(extensionID(fromManifestKey:))
            ?? extensionID(forPath: extensionDirectory)
    }

    /// Native Host가 허용할 확장 ID 목록. Web Store 전환 시 store ID를 여기에 추가하면 된다.
    /// 경로 기반 ID는 key 도입 전에 로드된 확장(제거·재설치 전까지 옛 ID로 동작)을 위해 남긴다.
    static var allowedExtensionIDs: [String] {
        var ids = [currentExtensionID]
        let pathID = extensionID(forPath: extensionDirectory)
        if !ids.contains(pathID) { ids.append(pathID) }
        return ids
    }

    static var optionsPageURL: String {
        "chrome-extension://\(currentExtensionID)/options.html"
    }

    // MARK: Native Host manifest

    static func installManifest() throws {
        try FileManager.default.createDirectory(
            atPath: chromeNativeMessagingDir(), withIntermediateDirectories: true
        )
        let data = nativeHostManifestJSON(relayPath: relayPath, extensionIDs: allowedExtensionIDs)
        try data.write(to: URL(fileURLWithPath: nativeHostManifestPath()), options: .atomic)
        // iTerm Checkout 시절 레거시 manifest 정리
        try? FileManager.default.removeItem(atPath: legacyManifestPath())
    }

    static func manifestState() -> SetupState {
        guard let data = FileManager.default.contents(atPath: nativeHostManifestPath()),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .error("등록되지 않음 — [등록/업데이트]를 누르세요")
        }
        let pathOK = obj["path"] as? String == relayPath
        // 순서 무관 집합 비교 (ID 목록이 늘어나도 안정적)
        let expected = Set(allowedExtensionIDs.map(extensionOrigin))
        let originOK = Set(obj["allowed_origins"] as? [String] ?? []) == expected
        switch (pathOK, originOK) {
        case (true, true): return .ok("등록됨")
        case (false, _): return .warning("다른 위치의 앱을 가리킴 — [등록/업데이트]로 갱신하세요")
        case (_, false): return .warning("확장 ID가 현재 설정과 다름 — [등록/업데이트]로 갱신하세요")
        }
    }

    // MARK: 확장 프로그램 폴더

    /// 번들에 내장된 확장 프로그램을 App Support 아래 고정 경로로 복사한다.
    /// (앱을 옮기거나 재빌드해도 확장 경로·ID가 유지되도록)
    static func installExtensionCopy() throws {
        guard let source = bundledExtensionPath,
              FileManager.default.fileExists(atPath: source) else {
            throw InstallerError.bundledExtensionMissing
        }
        let dest = extensionDirectory
        try FileManager.default.createDirectory(
            atPath: appSupportDirectory(), withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if FileManager.default.fileExists(atPath: dest) {
            try FileManager.default.removeItem(atPath: dest)
        }
        try FileManager.default.copyItem(atPath: source, toPath: dest)
    }

    static func extensionState() -> SetupState {
        let manifest = (extensionDirectory as NSString).appendingPathComponent("manifest.json")
        if FileManager.default.fileExists(atPath: manifest) {
            return .ok("준비됨")
        }
        return .error("확장 폴더 없음 — [Chrome에 설치하기]를 누르면 준비됩니다")
    }

    /// 번들 확장과 설치된 사본의 내용이 다른가 (앱 업데이트로 확장이 갱신된 경우 등)
    static func extensionCopyNeedsUpdate() -> Bool {
        guard let source = bundledExtensionPath else { return false }
        return directoryContentsDiffer(source, extensionDirectory)
    }

    private static func directoryContentsDiffer(_ a: String, _ b: String) -> Bool {
        func fileMap(_ root: String) -> [String: Data]? {
            let fm = FileManager.default
            guard let enumerator = fm.enumerator(atPath: root) else { return nil }
            var map: [String: Data] = [:]
            for case let relative as String in enumerator {
                let full = (root as NSString).appendingPathComponent(relative)
                var isDirectory: ObjCBool = false
                guard fm.fileExists(atPath: full, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                map[relative] = fm.contents(atPath: full) ?? Data()
            }
            return map
        }
        guard let mapA = fileMap(a), let mapB = fileMap(b) else { return true }
        return mapA != mapB
    }

    /// 실행 시 자동 셋업: 안전·멱등 항목만 조용히 처리한다.
    /// (Chrome 확장 로드와 TCC 권한 허용은 사용자만 할 수 있는 단계로 남는다)
    static func autoSetup() {
        // 사본이 없거나 번들과 다르면(앱 업데이트) 자동 재복사 — 별도 버튼 불필요.
        // Chrome은 unpacked 확장 파일을 디스크에서 읽으므로, 반영에는 확장 새로고침만 필요하다
        if extensionCopyNeedsUpdate() {
            try? installExtensionCopy()
        }
        if case .ok = manifestState() {} else {
            try? installManifest() // 앱 위치 변경 시 self-healing
        }
    }
}
