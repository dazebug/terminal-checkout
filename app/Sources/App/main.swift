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

// Capture the external system language order and apply AppKit's choice before `NSApplication.shared`.
// The method must read that order before writing an explicit app override; `auto` later reads the
// argument/global domains directly so this app's own value cannot become its system-language input.
// Measured (D14), a write after AppKit's first localization lookup leaves that process in the old
// language and only shows up on the next launch. The headless server above never reaches here on
// purpose — it draws nothing, and a process with no window has no business rewriting defaults.
AppLocalization.applyStoredLanguageToAppKit()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
