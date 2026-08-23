import Foundation

/// The iTerm2 bundle ID. AppleScript targets this ID rather than the name — that keeps working when the app file is called iTerm.app, or when a copy has confused LaunchServices' name resolution (this is what avoids -1728).
public let iTermBundleID = "com.googlecode.iterm2"

/// **The only door AppleScript goes out through**, and the delivery is stdin rather than `-e`.
///
/// **Why not `-e`.** Foundation re-encodes `Process.arguments` to NFD on Darwin
/// (`ProcessArgumentBoundaryTests`), so a script handed over as an argument reaches the interpreter
/// decomposed — measured for `설계`: `-e` gives it `1109 1165 11AF 1100 1168`, stdin and a script
/// file both give `C124 ACC4`. That is the user's own sentence to claude, in whichever of the five
/// languages they wrote it, and when the input is a `!` one it is the **shell** that receives the
/// decomposed bytes — the failure mode this repository has already met once, where a Korean pattern
/// stopped matching the NFC bytes on disk with no error anywhere.
///
/// **Why the carrier and not a normalisation of ours.** Composing to NFC would equally change what
/// a user who typed NFD wrote. The promise is the bytes they wrote, so the fix is to stop passing
/// them through something that rewrites them.
///
/// **Why stdin and not a script file**, which measures the same: a file has to be created, secured
/// and deleted on a path taken several times per input (marker, clear, body, CR, cleanup), and a
/// deletion that fails leaves residue this repository would then have to reclaim — it already
/// carries two such reclaimers. Measured alongside: stdin reports the **same status and the same
/// stderr** as `-e` for both a syntax error and a missing target, and a 200 KB script goes through
/// without the write blocking.
///
/// **What is not measured**: the last hop. Whether iTerm2's `write text` puts these bytes on the tty
/// unchanged needs iTerm2 running. What is established is that the bytes leave AppleScript itself
/// intact — measured through two independent sinks, `do shell script` and AppleScript's own UTF-8
/// writer.
///
/// There is no default timeout on purpose: the four call sites want 10s (twice), 180s and 300s, and
/// a default none of them used would be a value no test ever exercises.
public func runAppleScript(
    _ script: String, timeout: TimeInterval
) throws -> (status: Int32, stdout: String, stderr: String) {
    try runProcess("/usr/bin/osascript", ["-"], input: script, timeout: timeout)
}

/// Escapes text so it can sit safely inside an AppleScript string literal.
public func escapeForAppleScript(_ text: String) -> String {
    var s = text.replacingOccurrences(of: "\\", with: "\\\\")
    s = s.replacingOccurrences(of: "\"", with: "\\\"")
    s = s.replacingOccurrences(of: "\r\n", with: "\\n")
    s = s.replacingOccurrences(of: "\n", with: "\\n")
    s = s.replacingOccurrences(of: "\r", with: "\\n")
    s = s.replacingOccurrences(of: "\t", with: "\\t")
    return s
}

/// The AppleScript that opens a new tab in iTerm2 and runs a command.
/// It branches to cover the case where there is no window at all (where `create tab` is not possible).
/// At the end it returns "session id|tty" — claude input delivery uses that handle to find the session again.
public func iTermScript(for command: String) -> String {
    let escaped = escapeForAppleScript(command)
    return """
    tell application id "\(iTermBundleID)"
        activate
        if (count of windows) = 0 then
            create window with default profile
        else
            tell current window to create tab with default profile
        end if
        set s to current session of current window
        tell s to write text "\(escaped)"
        return (id of s) & "|" & (tty of s)
    end tell
    """
}

/// The AppleScript that types text into an already-open session (used for claude input delivery).
/// With submit=false it only types, without a newline — the claude TUI does not recognise LF as a submission, and it discards input that arrives during initialisation, so the submission (the newline) has to be sent separately once the screen has been confirmed to reflect the text.
/// When the session cannot be found (the tab was closed) it returns "gone", which is how the caller learns to stop the remaining delivery.
public func iTermWriteToSessionScript(sessionID: String, text: String, submit: Bool) -> String {
    let escapedID = escapeForAppleScript(sessionID)
    let escapedText = escapeForAppleScript(text)
    let write = submit
        ? "tell s to write text \"\(escapedText)\""
        : "tell s to write text \"\(escapedText)\" newline NO"
    return """
    tell application id "\(iTermBundleID)"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (id of s) is "\(escapedID)" then
                        \(write)
                        return "ok"
                    end if
                end repeat
            end repeat
        end repeat
        return "gone"
    end tell
    """
}

/// Control characters cannot be written into an AppleScript string literal, so they are spelled as
/// `character id` and concatenated. **Derived from the key string, never transcribed**: iTerm2 is
/// the one terminal that does not receive `claudeClearInputKey` as bytes, and while the numbers
/// were written out by hand, changing that constant left iTerm2 on the old sequence in silence.
func appleScriptCharacters(of keys: String) -> String {
    keys.unicodeScalars.map { "(character id \($0.value))" }.joined(separator: " & ")
}

/// The AppleScript that clears the input box — `claudeClearInputKey`, i.e. Ctrl+U (0x15) **then**
/// Backspace (0x7F), in a single `write text` (a newline between the two would submit).
///
/// Why Backspace follows is recorded at `claudeClearInputKey`: Ctrl+U alone leaves claude's `!`
/// shell mode behind, and the plain input typed after it runs as a shell command (measured).
public func iTermClearInputScript(sessionID: String) -> String {
    let escapedID = escapeForAppleScript(sessionID)
    let keys = appleScriptCharacters(of: claudeClearInputKey)
    return """
    tell application id "\(iTermBundleID)"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (id of s) is "\(escapedID)" then
                        tell s to write text (\(keys)) newline NO
                        return "ok"
                    end if
                end repeat
            end repeat
        end repeat
        return "gone"
    end tell
    """
}

/// The AppleScript that returns a session's current screen text — used to check whether typing actually landed.
public func iTermSessionContentsScript(sessionID: String) -> String {
    let escapedID = escapeForAppleScript(sessionID)
    return """
    tell application id "\(iTermBundleID)"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (id of s) is "\(escapedID)" then
                        return contents of s
                    end if
                end repeat
            end repeat
        end repeat
        return "gone"
    end tell
    """
}
