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

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
