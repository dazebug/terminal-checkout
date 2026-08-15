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

/// 이미 열린 세션에 텍스트 한 줄을 타이핑하는 AppleScript (claude 입력 전달용).
/// 세션을 못 찾으면(탭 닫힘) "gone"을 돌려줘 호출자가 남은 전달을 중단하게 한다.
public func iTermWriteToSessionScript(sessionID: String, text: String) -> String {
    let escapedID = escapeForAppleScript(sessionID)
    let escapedText = escapeForAppleScript(text)
    return """
    tell application id "\(iTermBundleID)"
        repeat with w in windows
            repeat with t in tabs of w
                repeat with s in sessions of t
                    if (id of s) is "\(escapedID)" then
                        tell s to write text "\(escapedText)"
                        return "ok"
                    end if
                end repeat
            end repeat
        end repeat
        return "gone"
    end tell
    """
}
