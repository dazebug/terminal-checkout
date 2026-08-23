import AppKit
import Core
import Foundation

// Headless mode for tests: the socket server only, with no UI (this is what `e2e.sh` drives)
if CommandLine.arguments.contains("--headless-server") {
    let server = HostServer(socketPath: defaultSocketPath())
    do {
        // This process draws nothing and has no picker, so inventing a revision here is what D49
        // rules out — and `.nothing` is where it says so. It used to say it by discarding the right
        // the bind hands back, which is a sentence only to a reader who knows what was discarded;
        // the announcement is a required argument, so the headless server cannot start answering
        // without stating what it publishes any more than the GUI can (round 17 review)
        try server.start(announcing: .nothing)
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

// **The launch language is decided here; publishing it happens once the socket is ours.**
//
// Resolving stays here, next to the write above, so the two answers cannot be computed at different
// moments — that was always the reason this line came before AppKit. What moved is the *publication*
// (round 14 review): `NSLock` is process-local and cannot stop a second GUI instance, and this file
// runs before `HostServer.start()` decides which instance owns the socket. Publishing here let a
// second instance — one `open -n` away, which is how our own restart relaunches — write a different
// locale under the same install id and epoch, a pair the extension then cannot order.
//
// The instance that owns the socket is the one the extension talks to, so it is the only one with
// standing to say what language it is in. The delegate publishes this value after binding.
let launchLocale = AppLocalization.resolvedLocale()

let app = NSApplication.shared
let delegate = AppDelegate(launchLocale: launchLocale)
app.delegate = delegate
app.run()
