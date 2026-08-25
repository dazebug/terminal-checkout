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
    ///
    /// **Built beside the old copy, then swapped.** It used to delete the destination and copy into
    /// it, which meant the folder Chrome reads was *absent* for the length of a recursive copy and
    /// then partially populated — and that window grew when five locales added `_locales/` and
    /// `_i18n/` to it. What Chrome would find there is not a stale extension but a broken one: no
    /// manifest at all, or dictionaries without the code that reads them.
    ///
    /// `replaceItemAt` is Foundation's replacement primitive and the reason this is possible at all.
    /// Measured on a populated directory with a throwaway probe kept nowhere: plain `rename(2)`
    /// refuses with `ENOTEMPTY` (errno 66), while `replaceItemAt` succeeds, consumes the staged
    /// directory, and left the destination **present on every one of ~10,200 reads** from a thread
    /// doing nothing but opening files inside it across four runs.
    ///
    /// **What that does not buy**, and the probe showed this too: a reader that opens two files in
    /// sequence can still take one from each generation, because its first `open` happened before
    /// the swap and its second after. No filesystem primitive prevents that — only a reader that
    /// snapshots. The claim here is that the directory is never absent and never half-built, not
    /// that a reader mid-flight sees one generation.
    ///
    /// The staged copy is removed on the way out. On success there is nothing left to remove —
    /// `replaceItemAt` consumes it — so the cleanup matters on the failure path, which is the one
    /// that would otherwise leave a full copy of the extension lying beside it.
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
        let staging = extensionStagingPath()
        try? FileManager.default.removeItem(atPath: staging)
        defer { try? FileManager.default.removeItem(atPath: staging) }
        try FileManager.default.copyItem(atPath: source, toPath: staging)

        if FileManager.default.fileExists(atPath: dest) {
            _ = try FileManager.default.replaceItemAt(
                URL(fileURLWithPath: dest), withItemAt: URL(fileURLWithPath: staging)
            )
        } else {
            // Nothing to replace on a first install, and `replaceItemAt` wants something there. A
            // rename onto an absent path is atomic on its own.
            try FileManager.default.moveItem(atPath: staging, toPath: dest)
        }
    }

    /// Where the next copy is built. A sibling of the destination, so the swap is a rename within
    /// one filesystem rather than a copy across two — and hidden, because a folder that exists only
    /// between two instants should not invite anyone to load it into Chrome.
    ///
    /// The name is fixed rather than unique on purpose: a crash between the copy and the swap leaves
    /// exactly one piece of debris, and the next run removes it before staging. A unique name would
    /// leave one per crash, with nobody to collect them.
    static func extensionStagingPath() -> String {
        (appSupportDirectory() as NSString).appendingPathComponent(".extension.staging")
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
            // Not `try?`. There is no window to report into at launch, but a swallowed failure here
            // is the difference between "Chrome has the old extension" and "Chrome has whatever was
            // there", and the only place that distinction can still be recovered is the log. The
            // swap itself leaves the previous copy in place on failure, so the state this reports is
            // a known one rather than a mystery.
            do {
                try installExtensionCopy()
            } catch {
                checkoutLog("updating the installed extension copy failed — \(errorMessage(error))")
            }
        }
        if case .ok = manifestState() {} else {
            try? installManifest() // self-healing when the app has moved
        }
    }
}
