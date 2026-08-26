import AppKit
import Core
import Foundation

extension CmuxSocketStatus {
    /// Read at draw time, like `AutomationStatus.label`, so changing the app language redraws the
    /// current state instead of retaining a sentence from the previous catalogue.
    var label: String {
        switch self {
        case .notInstalled: return localized("app.status.cmux.notInstalled")
        case .notRunning: return localized("app.status.cmux.notRunning")
        case .denied: return localized("app.status.cmux.denied")
        case .reachable: return localized("app.status.cmux.reachable")
        case .failed(let detail): return localized("app.status.cmux.failed", detail)
        }
    }
}

enum AutomationStatus {
    case granted
    case denied
    case notDetermined
    case targetNotRunning
    case unknown(Int32)

    /// Read where it is drawn, never stored: a value kept in a property would hold the language it
    /// was built in. The two cases that point at a button take its label from the catalogue as `%@`
    /// rather than spelling it out, so renaming the button cannot leave the sentence quoting a
    /// button that is no longer there.
    var label: String {
        switch self {
        case .granted: return localized("app.automation.granted")
        case .denied: return localized("app.automation.denied")
        case .notDetermined:
            return localized("app.automation.notDetermined", localized("app.button.requestItermPermission"))
        case .targetNotRunning:
            return localized("app.automation.targetNotRunning", localized("app.button.requestItermPermission"))
        case .unknown(let code): return localized("app.automation.unknown", code)
        }
    }

    var isGranted: Bool {
        if case .granted = self { return true }
        return false
    }
}

enum PermissionChecker {
    /// The live TCC query is the default. Tests replace this function briefly to model the state
    /// transition that System Settings produces when the window becomes key again.
    static var accessibilityStatusProvider: () -> Bool = { accessibilityIsTrusted() }

    static var isITermInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) != nil
    }

    static var isWezTermInstalled: Bool {
        findWezTermCLI() != nil
    }

    /// Uses the same executable lookup Core uses — if detection and execution disagree, the result
    /// is "installed according to the settings, not found when run".
    static var isWarpInstalled: Bool {
        findWarpExecutable() != nil
    }

    /// Uses the same executable lookup Core uses for cmux execution — detection and execution must
    /// not disagree about whether the CLI is installed.
    static var isCmuxInstalled: Bool {
        findCmuxCLI() != nil
    }

    /// Reads cmux's live socket state on every call. The result is intentionally not stored: cmux
    /// may reload its control mode while this window remains open, and the ping itself has no lockout.
    static func cmuxSocketStatus() -> CmuxSocketStatus {
        guard let cli = findCmuxCLI() else { return .notInstalled }
        let socketExists = cmuxSocketPath() != nil
        do {
            let result = try runProcess(cli, ["ping"], timeout: 5)
            return classifyCmuxSocketStatus(
                socketExists: socketExists,
                pingStatus: result.status,
                stdout: result.stdout,
                stderr: result.stderr
            )
        } catch {
            return classifyCmuxSocketStatus(
                socketExists: socketExists,
                pingStatus: -1,
                stdout: "",
                stderr: errorMessage(error)
            )
        }
    }

    /// The Accessibility permission. It is a hard requirement for buttons that schedule claude input
    /// on Warp: without reading the screen there is no way to tell whether claude received the
    /// input, and a CR sent without that check submits an empty line while the input claude
    /// discarded is recorded as "delivered" (measured). Running a command needs none of this.
    static var isAccessibilityGranted: Bool {
        accessibilityStatusProvider()
    }

    /// Raises the prompt. Unlike the automation permission this one is not granted here — it only
    /// points at System Settings — so there is no success/failure callback and the result is read
    /// back by asking for the status again.
    static func requestAccessibility() {
        requestAccessibilityPrompt()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The state of the iTerm2 automation (Apple Events) permission — a query only, raising no prompt.
    static func iTermAutomationStatus() -> AutomationStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: iTermBundleID)
        let status = AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notDetermined
        case OSStatus(procNotFound): return .targetNotRunning
        default: return .unknown(status)
        }
    }

    /// Launches iTerm2 first, then sends a harmless Apple Event to draw the permission prompt.
    /// The target is addressed by bundle id — it avoids the name-resolution failure (-1728) and
    /// leaves no doubt about which app is being asked for.
    static func requestITermAutomation(completion: @escaping (Result<Void, Error>) -> Void) {
        launchITerm { _ in
            DispatchQueue.global().async {
                // Wait for it to come up (10s at most; osascript launching it itself is the backstop)
                for _ in 0..<50 {
                    if !NSRunningApplication.runningApplications(withBundleIdentifier: iTermBundleID).isEmpty {
                        break
                    }
                    usleep(200_000)
                }
                do {
                    // `count windows`: a harmless query that is guaranteed to send an Apple Event —
                    // `version` and `name` can be answered locally and so raise no consent prompt
                    let result = try runAppleScript(
                        "tell application id \"\(iTermBundleID)\" to count windows",
                        timeout: 300 // waits for the user to answer the prompt
                    )
                    DispatchQueue.main.async {
                        if result.status == 0 {
                            completion(.success(()))
                        } else {
                            completion(.failure(TerminalError.appleScriptFailed(
                                result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                            )))
                        }
                    }
                } catch {
                    DispatchQueue.main.async { completion(.failure(error)) }
                }
            }
        }
    }

    private static func launchITerm(completion: @escaping (Bool) -> Void) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: iTermBundleID) else {
            completion(false)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
