import Foundation

/// iTerm2 번들 ID. AppleScript 타게팅은 이름이 아닌 이 ID로 한다 —
/// 앱 파일명이 iTerm.app이거나 복사본으로 LaunchServices 이름 해석이 꼬여도 동작 (-1728 방지).
public let iTermBundleID = "com.googlecode.iterm2"

/// AppleScript 문자열 리터럴 안에 안전하게 들어가도록 이스케이프한다.
public func escapeForAppleScript(_ text: String) -> String {
    var s = text.replacingOccurrences(of: "\\", with: "\\\\")
    s = s.replacingOccurrences(of: "\"", with: "\\\"")
    s = s.replacingOccurrences(of: "\r\n", with: "\\n")
    s = s.replacingOccurrences(of: "\n", with: "\\n")
    s = s.replacingOccurrences(of: "\r", with: "\\n")
    s = s.replacingOccurrences(of: "\t", with: "\\t")
    return s
}

/// iTerm2에서 새 탭을 열고 명령을 실행하는 AppleScript.
/// 창이 하나도 없을 때(create tab 불가)를 대비해 분기한다.
/// 마지막에 "세션id|tty"를 돌려준다 — claude 입력 전달이 이 핸들로 세션을 다시 찾는다.
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

/// 이미 열린 세션에 텍스트를 타이핑하는 AppleScript (claude 입력 전달용).
/// submit=false면 개행 없이 타이핑만 한다 — claude TUI는 LF를 제출로 인식하지 않고,
/// 초기화 중 도착한 입력은 버리므로, 화면 반영을 확인한 뒤 제출(개행)을 따로 보내야 한다.
/// 세션을 못 찾으면(탭 닫힘) "gone"을 돌려줘 호출자가 남은 전달을 중단하게 한다.
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

/// 입력창을 비우는 AppleScript — Ctrl+U(0x15) **다음 Backspace(0x7F)**를 보낸다.
/// 제어문자는 AppleScript 문자열 리터럴에 넣을 수 없어 character id로 만들고, 두 글자를 한 번의
/// `write text`로 이어 보낸다(사이에 개행이 끼면 안 된다).
///
/// Backspace가 붙는 이유는 `claudeClearInputKey`에 있다 — Ctrl+U만으로는 claude의 `!` 셸 모드가
/// 남고, 그 뒤에 친 평문이 셸 명령으로 실행된다(실측).
public func iTermClearInputScript(sessionID: String) -> String {
    let escapedID = escapeForAppleScript(sessionID)
    return """
    tell application id "\(iTermBundleID)"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (id of s) is "\(escapedID)" then
                        tell s to write text ((character id 21) & (character id 127)) newline NO
                        return "ok"
                    end if
                end repeat
            end repeat
        end repeat
        return "gone"
    end tell
    """
}

/// 세션의 현재 화면 텍스트를 돌려주는 AppleScript — 타이핑이 실제로 반영됐는지 확인용.
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
