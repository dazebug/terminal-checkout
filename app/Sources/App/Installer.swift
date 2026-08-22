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

    /// Shown to the user (`showError`'s informative text), so it comes from the catalogue rather
    /// than being written here.
    var description: String {
        switch self {
        case .bundledExtensionMissing: return localized("app.error.bundledExtensionMissing")
        }
    }
}

/// Registers the Native Host manifest and installs the extension folder.
enum Installer {
    /// The absolute path of the relay inside the running app bundle (the manifest's `path`)
    static var relayPath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/terminal-checkout-relay"
    }

    static var bundledExtensionPath: String? {
        Bundle.main.resourcePath.map { $0 + "/extension" }
    }

    /// The extension folder Chrome loads — one fixed location under App Support.
    static var extensionDirectory: String { defaultExtensionInstallPath() }

    /// The bundled extension manifest's `key` — the public key that pins the extension ID
    /// independently of machine and path. (The ID has to be identical for `storage.sync` settings to
    /// sync between Chromes on the same Google account.)
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

    /// The extension IDs the Native Host accepts. Moving to the Web Store means adding the store ID
    /// here. The path-based ID stays for an extension that was loaded before the key existed — it
    /// keeps running under the old ID until it is removed and loaded again.
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
        // Clean up the legacy manifest from the iTerm Checkout days
        try? FileManager.default.removeItem(atPath: legacyManifestPath())
    }

    /// The three sentences that point at a button take its label from the catalogue as `%@` (D28),
    /// and every one of them is read at the moment the window draws it.
    static func manifestState() -> SetupState {
        guard let data = FileManager.default.contents(atPath: nativeHostManifestPath()),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return .error(
                localized("app.status.manifest.notRegistered", localized("app.button.registerUpdate"))
            )
        }
        let pathOK = obj["path"] as? String == relayPath
        // Compared as sets, so the order of the ID list does not matter as it grows
        let expected = Set(allowedExtensionIDs.map(extensionOrigin))
        let originOK = Set(obj["allowed_origins"] as? [String] ?? []) == expected
        switch (pathOK, originOK) {
        case (true, true): return .ok(localized("app.status.manifest.registered"))
        case (false, _):
            return .warning(
                localized("app.status.manifest.wrongPath", localized("app.button.registerUpdate"))
            )
        case (_, false):
            return .warning(
                localized("app.status.manifest.wrongExtensionID", localized("app.button.registerUpdate"))
            )
        }
    }

    // MARK: The extension folder

    /// Copies the extension bundled inside the app to a fixed path under App Support, so that moving
    /// or rebuilding the app leaves the extension's path and ID unchanged.
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
            return .ok(localized("app.status.extensionFolder.ready"))
        }
        return .error(
            localized("app.status.extensionFolder.missing", localized("app.button.installInChrome"))
        )
    }

    /// Whether the bundled extension and the installed copy differ — after an app update, say
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

    /// Setup that runs on launch: the steps that are safe and idempotent, done quietly. Loading the
    /// extension into Chrome and granting the TCC permissions stay with the user.
    static func autoSetup() {
        // Copy again when there is no copy, or when it differs from the bundle (an app update) — no
        // button for it. Chrome reads an unpacked extension's files from disk, so a refresh in
        // chrome://extensions is all that is needed for it to take effect
        if extensionCopyNeedsUpdate() {
            try? installExtensionCopy()
        }
        if case .ok = manifestState() {} else {
            try? installManifest() // self-healing when the app has moved
        }
    }
}
