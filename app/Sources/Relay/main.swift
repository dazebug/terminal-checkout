import Core
import Foundation

// Chrome Native Messaging relay: stdio ↔ 앱 소켓 중계.
//
// 핵심: 이 프로세스는 Chrome의 자식이라 여기서 osascript를 실행하면 TCC 권한이
// Chrome에 귀속된다. 그래서 아무 것도 직접 실행하지 않고, LaunchServices(open)로
// 실행되어 스스로 responsible process가 된 Terminal Checkout 앱에 위임만 한다.

func replyError(_ message: String) {
    let json = (try? JSONSerialization.data(withJSONObject: ["success": false, "error": message]))
        ?? Data(#"{"success":false}"#.utf8)
    writeFramedMessage(json, toFD: 1)
}

func launchApp() -> Bool {
    guard let result = try? runProcess(
        "/usr/bin/open", ["-g", "-b", appBundleID, "--args", "--background"], timeout: 15
    ) else { return false }
    return result.status == 0
}

/// 소켓 연결 시도, 실패하면 앱을 백그라운드로 띄우고 재시도 (cold start 최대 10초 대기)
func connectWithLaunch() -> Int32? {
    let path = defaultSocketPath()
    if let fd = connectToUnixSocket(path: path) { return fd }
    guard launchApp() else { return nil }
    for _ in 0..<50 {
        usleep(200_000)
        if let fd = connectToUnixSocket(path: path) { return fd }
    }
    return nil
}

// Chrome이 stdin으로 보내는 메시지를 순서대로 중계 (EOF에서 종료)
while let message = readFramedMessage(fromFD: 0) {
    guard let fd = connectWithLaunch() else {
        replyError("Terminal Checkout 앱을 실행할 수 없습니다. Terminal Checkout.app이 설치되어 있는지 확인하세요.")
        continue
    }
    defer { close(fd) }

    // 응답 타임아웃 여유: 최초 실행 시 TCC 권한 프롬프트 응답을 기다릴 수 있다
    var tv = timeval(tv_sec: 180, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    guard writeFramedMessage(message, toFD: fd), let response = readFramedMessage(fromFD: fd) else {
        replyError("Terminal Checkout 앱과의 통신에 실패했습니다. 앱을 다시 실행해 보세요.")
        continue
    }
    writeFramedMessage(response, toFD: 1)
}
