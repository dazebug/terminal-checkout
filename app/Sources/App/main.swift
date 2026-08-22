import AppKit
import Core
import Foundation

// 테스트용 헤드리스 모드: UI 없이 소켓 서버만 띄운다 (e2e 테스트에서 사용)
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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
