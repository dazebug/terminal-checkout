import AppKit
import Core
import Foundation

// Headless mode for tests: the socket server only, with no UI (this is what `e2e.sh` drives)
if CommandLine.arguments.contains("--headless-server") {
    let server = HostServer(socketPath: defaultSocketPath())
    do {
        try server.start()
    } catch {
        FileHandle.standardError.write(Data("server start failed: \(errorMessage(error))\n".utf8))
        exit(1)
    }
    FileHandle.standardOutput.write(Data("listening \(defaultSocketPath())\n".utf8))
    RunLoop.main.run()
    exit(0)
}

// Before **any** localization lookup happens in this process, not merely before AppKit exists:
// measured (D14), a write that lands after the first lookup leaves this process in the old
// language and only shows up on the next launch. `NSApplication.shared` below is that first touch.
// The headless server above never reaches here on purpose — it draws nothing, and a process with
// no window has no business rewriting the user's language defaults.
AppLocalization.applyStoredLanguageToAppKit()

// The launch publisher, in the one file the headless server provably never reaches (it exits
// above). It runs here rather than in `AppDelegate` for that reason and for one more: this is
// already the place that decides what language this launch is in, and publishing what was just
// resolved keeps the two answers from being computed at different moments.
Settings.publishLocaleAtLaunch()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
