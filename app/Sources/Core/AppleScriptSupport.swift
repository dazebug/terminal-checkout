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
public func iTermScript(for command: String) -> String {
    let escaped = escapeForAppleScript(command)
    return """
    tell application id "\(iTermBundleID)"
        activate
        if (count of windows) = 0 then
            create window with default profile
            tell current session of current window
                write text "\(escaped)"
            end tell
        else
            tell current window
                create tab with default profile
                tell current session
                    write text "\(escaped)"
                end tell
            end tell
        end if
    end tell
    """
}
