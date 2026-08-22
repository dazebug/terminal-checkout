import Core
import Foundation

// The Chrome Native Messaging relay: forwarding between stdio and the app's socket.
//
// The crux: this process is a child of Chrome, so running osascript here would attribute the TCC permission to **Chrome**. That is why it runs nothing itself and only delegates to the Terminal Checkout app, which is launched through LaunchServices (`open`) and thereby becomes its own responsible process.

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

/// Tries to connect to the socket; on failure it launches the app in the background and retries (waiting up to 10 seconds for a cold start).
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

// Forwards the messages Chrome sends on stdin, in order (exiting at EOF)
while let message = readFramedMessage(fromFD: 0) {
    guard let fd = connectWithLaunch() else {
        replyError("Could not launch the Terminal Checkout app. Check that Terminal Checkout.app is installed.")
        continue
    }
    defer { close(fd) }

    // Generous response timeout: on the first run this may be waiting for the user to answer the TCC permission prompt
    var tv = timeval(tv_sec: 180, tv_usec: 0)
    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

    guard writeFramedMessage(message, toFD: fd), let response = readFramedMessage(fromFD: fd) else {
        replyError("Communication with the Terminal Checkout app failed. Try relaunching the app.")
        continue
    }
    writeFramedMessage(response, toFD: 1)
}
